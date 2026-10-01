## 玩家控制器：移动 + 无锁定普攻 + 冲刺位移（无敌帧）+ 受击击退 + 死亡重生。
## ACT 无锁定（策划：无锁定通过攻击达到降低敌方血量目的）——
## 攻击方向 = 最后移动方向，判定框朝该方向短暂开启，命中所有进入的怪物。
## 冲刺消耗 MP 并带 0.18s 无敌帧，是躲避冲锋/重击的核心手段。
## 输入双通道：键盘（Input Map 动作）+ 触屏（TouchInput），玩法代码不区分平台。
class_name Player
extends CharacterBody2D

## 技能数值（费用/冷却/倍率/持续）的真源在 CharacterStats（v2 数值框架），
## 这里只留表现层手感常量：判定框几何 / 输入窗 / 物理参数 / 残影节奏。
const Skill := preload("res://scripts/character/character_stats.gd")
const SpritePlayback := preload("res://scripts/animation/sprite_playback.gd")

const ATTACK_WINDOW := 0.18
## 攻击动画收尾残留：判定窗结束后攻击动画再停留片刻播完收招段再回 walk/idle。
## 只影响表现（攻击期间本就不锁移动），连击重触发会立即切段
const ATTACK_ANIM_LINGER := 0.14
const ATTACK_REACH := 26.0
## 攻击朝向吸附：扇形半角与半径（解决"边退边打"的方向冲突）
const AIM_CONE_DEG := 60.0
const AIM_RANGE := 150.0
const RESPAWN_DELAY := 2.0
## 重生保护帧：出生点可能被怪围住，短暂无敌防止落地即死
const RESPAWN_PROTECT := 1.0
## 受击无敌帧：多只怪同帧命中只结算第一下——群体围攻是压力不是即死
## 熔岩灼烧节奏与强度（世界 v5）
const LAVA_TICK := 0.5
const LAVA_DAMAGE_FRAC := 0.03
const HURT_IFRAME := 0.35
## 受击动画展示时长；素材实际帧数/逐帧时长经 SpritePlayback 适配此窗
const HURT_ANIM_TIME := 0.3
## 冲刺期间只与墙壁碰撞（穿透怪物）：被围时的核心逃生手段
const MASK_NORMAL := 3
const MASK_DASH := 1
const KNOCKBACK_DECAY := 700.0
const DASH_SPEED := 620.0
const DASH_TIME := 0.18
const AFTERIMAGE_INTERVAL := 0.06
## --- HeroMotion v2（2026-09-16 英雄动作系统重设计）---
## 起步加速/停步减速：起停不再是 0↔满速的瞬时切换（瞬时满速+动画同步起播
## = 像被弹射的雕像，"走路生硬"主因之一）。加速 ~0.07s / 减速 ~0.05s 到位，
## 低于出招节奏感知阈值不吃手感，但起停从此有了重量
const MOVE_ACCEL := 2400.0
const MOVE_DECEL := 3200.0
## 步频同步基准：walk 动画 6 帧@12fps = 0.5s/循环、每循环两步 → 基准步幅 40px。
## 播放速率随地面速度缩放，移速成长（等级/鞋子词条）后步幅恒定不脚滑
const STRIDE_PX := 40.0
## 步频锁相 bob 幅度（px）：步落地沉、换步浮，与帧动画同源同拍
const BOB_AMPLITUDE := 1.05

@onready var attack_hitbox: Area2D = $AttackHitbox
@onready var attack_shape: CollisionShape2D = $AttackHitbox/CollisionShape2D
@onready var visual: AnimatedSprite2D = $Visual

## 打击特效帧（slice_spritesheets 生成的 NA fx 条带表）
const FX_SLASH := preload("res://assets/creatures/frames/fx_slash/fx_slash_frames.res")
const FX_SLASH_GOLD := preload("res://assets/creatures/frames/fx_slash_gold/fx_slash_gold_frames.res")
const FX_BURST := preload("res://assets/creatures/frames/fx_burst/fx_burst_frames.res")

## 三忍皮肤（美术 v5）：蓝/黑/白忍同布局表（idle/walk/attack/die 动画名同构，
## 换帧零逻辑差异）；存档键 settings.hero_skin，缺省蓝忍
const HERO_SKINS := {
	"blue": preload("res://assets/creatures/frames/ninja/ninja_frames.res"),
	"dark": preload("res://assets/creatures/frames/ninja_dark/ninja_dark_frames.res"),
	"white": preload("res://assets/creatures/frames/ninja_white/ninja_white_frames.res"),
}

## 视觉基础缩放（挤压回弹的恢复基准，_ready 时从场景读）
var _visual_base_scale := Vector2.ONE
## 落地阴影 / 脚点 y（尘土等脚下元素共用，_ready 按帧脚点 meta 定） / 挤压 tween / 行走浮动相位
var _shadow: ShadowBlob
var _feet_y := 0.0
var _squash_tween: Tween

var stats: CharacterStats
var current_hp: float = 0.0
var current_mp: float = 0.0
var facing: Vector2 = Vector2.RIGHT

var _attack_cooldown := 0.0
var _attack_timer := 0.0
## 从出招起算的总表现窗 = 判定窗 + 收招窗；两者不能并行倒计时。
var _attack_anim_linger := 0.0
var _attack_visual_flip := false
var _respawn_timer := 0.0
var _is_dead := false
## 熔岩池灼烧（世界 v5）：站立每 LAVA_TICK 结算 LAVA_DAMAGE_FRAC 最大生命
var _lava_accum := 0.0
var _hit_this_swing: Array = []
var _hud_accum := 0.0
var _knockback := Vector2.ZERO
var _dash_timer := 0.0
var _dash_cd := 0.0
var _afterimage_accum := 0.0
var _heavy_cd := 0.0
var _bolt_cd := 0.0
var _heal_cd := 0.0
var _empower_cd := 0.0
## 武装强化剩余持续时间（>0 = 强化状态中）
var _empower_timer := 0.0
var _dust_accum := 0.0
var _combo := 0
var _combo_timer := 0.0
var _dash_buff_timer := 0.0
## 重生保护帧计时
var _protect_timer := 0.0
## 受击无敌帧计时
var _hurt_iframes := 0.0
## 受击动画残留计时（>0 期间 hurt 压过 walk/idle，挨打可读）
var _hurt_anim_timer := 0.0
## 冲刺中按下的攻击缓冲（冲刺→攻击增伤连招不丢输入；触屏通道同样并入这里，双通道同源）
var _attack_buffered := false
## 普攻预输入缓冲剩余时间：攻击冷却中按下不丢弃，转好即出刀（连击不断段）
var _attack_buffer_timer := 0.0
const ATTACK_BUFFER_TIME := 0.12
## 普攻命中顿帧节流标记（AOE 同帧命中多只只压一次 time_scale）
var _last_hit_stop := -9999.0
## 受击白闪 tween（新的受击到来先杀旧的，避免旧 tween 把颜色拉错）
var _hurt_tween: Tween
var _death_tween: Tween
## 最近一次致死伤害来源名（死亡信息用）
var last_killed_by := ""
## HeroMotion v2：平滑后的移动分量（击退/冲刺直接写 velocity，不经此变量）
var _move_vel := Vector2.ZERO
## 上一帧是否处于 walk 态（起停过渡反馈用）
var _was_walking := false
## 插值保留浮点累积，只在最终绘制取整；逐帧取整反馈会把 1px bob 永远锁在零。
var _visual_bob := 0.0


func _ready() -> void:
	add_to_group("player")
	stats = GameState.stats
	# 三忍皮肤：按存档外观换帧（动画名同构；场景默认已接蓝忍，非蓝才需要换）
	var hero_skin: String = str(GameState.settings.get("hero_skin", "blue"))
	if HERO_SKINS.has(hero_skin) and visual.sprite_frames != HERO_SKINS[hero_skin]:
		visual.sprite_frames = HERO_SKINS[hero_skin]
		visual.play(&"idle")
	current_hp = stats.max_hp()
	current_mp = stats.max_mp()
	# v4 大世界：出生点 = 家园角斑块中心（BiomeMap 确定性派生）；
	# 有跨会话快照则优先恢复
	if not _restore_saved_state():
		global_position = WorldConfig.spawn_pos()
	# 相机边界随世界尺寸（v4 起为运行期数据）
	var cam := get_node_or_null("Camera2D") as Camera2D
	if cam != null:
		cam.limit_right = int(WorldConfig.WORLD_SIZE.x)
		cam.limit_bottom = int(WorldConfig.WORLD_SIZE.y)
	_visual_base_scale = visual.scale
	_shadow = ShadowBlob.new()
	_shadow.z_index = -1
	# 阴影贴真实脚点（与怪物侧同源公式；2026-10-01 修复：60ea6d7 帧重切
	# 21×19→67×60 后旧 9.0×scale 常量悬在小腿高度，与动画分离）
	var layout := MonsterBase.shadow_layout(visual.sprite_frames, _visual_base_scale)
	_feet_y = layout["y"]
	_shadow.position.y = _feet_y
	_shadow.shadow_scale = layout["s"]
	add_child(_shadow)
	_add_player_marker()
	attack_shape.disabled = true
	attack_hitbox.body_entered.connect(_on_attack_body_entered)
	# 延迟到所有节点 ready 之后再推初值，保证 HUD 已连接信号
	_push_hud.call_deferred()
	# 升级白闪光（美术 v5 fx 全量）：世界层特效走 fx_requested 通道。方法引用
	# 连接：stats 常驻 autoload 而 player 随世界释放，lambda 不随对象释放断连，
	# 下一局世界的升级信号会悬空调用已释放的本节点
	GameState.stats.leveled_up.connect(_on_leveled_up_fx)
	# v7 消耗品：HUD 快捷槽/物品栏发 item_use_requested，效果应用在本节点
	# （生命/精力的权威持有者，满血满蓝拦截与治疗技能同口径）
	EventBus.item_use_requested.connect(use_item)


func _on_leveled_up_fx(_level: int, _levels: int) -> void:
	EventBus.fx_requested.emit("flash", global_position, 1.5)


## 头顶定位标记（zoom1 广角下绿衣忍者在草地背景中可寻性不足，视觉分析实证；
## 死亡/重生随宿主整体 visible 自动隐藏恢复）
func _add_player_marker() -> void:
	add_child(PlayerMarker.new())


## 跨会话恢复角色位置与当前资源。世界边界留 20px 安全边距，坏档不会把玩家
## 放到墙外（v4 大世界：旧档坐标落在新世界出生角附近，钳到边界内即可）；
## HP 至少 1，死亡态由 save_snapshot 归一为出生点满状态。
## 返回是否真的应用了快照（false = 新开局，出生点由调用方设置）
func _restore_saved_state() -> bool:
	if typeof(GameState.player_snapshot) != TYPE_DICTIONARY:
		return false
	var snapshot: Dictionary = GameState.player_snapshot
	var pos: Array = snapshot.get("position", [])
	if pos.size() == 2:
		global_position = Vector2(
			clampf(float(pos[0]), 20.0, WorldConfig.WORLD_SIZE.x - 20.0),
			clampf(float(pos[1]), 20.0, WorldConfig.WORLD_SIZE.y - 20.0))
		# 世界 v5：老档坐标可能落进障碍（障碍场晚于坐标存档落地）——推到最近
		# 空位；本身在空处则原样返回（位置逐位不变）
		global_position = ObstacleField.nudge_free(global_position, 10.0)
	current_hp = clampf(float(snapshot.get("hp", stats.max_hp())), 1.0, stats.max_hp())
	current_mp = clampf(float(snapshot.get("mp", stats.max_mp())), 0.0, stats.max_mp())
	return true


## GameState 保存与 game_world 退场缓存共用。死亡的 2 秒表现不跨会话延续：
## 按游戏既有重生规则写成最近安全点满血蓝，避免读档免费回到此前登录位置。
func save_snapshot() -> Dictionary:
	if _is_dead:
		var respawn_pos := WorldConfig.nearest_safe_respawn(global_position)
		return {"position": [respawn_pos.x, respawn_pos.y],
			"hp": stats.max_hp(), "mp": stats.max_mp()}
	return {"position": [global_position.x, global_position.y],
		"hp": current_hp, "mp": current_mp}


func _physics_process(delta: float) -> void:
	_update_anim(delta)
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	_dash_cd = maxf(0.0, _dash_cd - delta)
	_heavy_cd = maxf(0.0, _heavy_cd - delta)
	_bolt_cd = maxf(0.0, _bolt_cd - delta)
	_heal_cd = maxf(0.0, _heal_cd - delta)
	_empower_cd = maxf(0.0, _empower_cd - delta)
	if _empower_timer > 0.0:
		_empower_timer = maxf(0.0, _empower_timer - delta)
		if _empower_timer <= 0.0:
			_set_visual_base(Color.WHITE)  # 强化结束，收回金色光泽
	_dash_buff_timer = maxf(0.0, _dash_buff_timer - delta)
	_combo_timer = maxf(0.0, _combo_timer - delta)
	_attack_buffer_timer = maxf(0.0, _attack_buffer_timer - delta)
	_protect_timer = maxf(0.0, _protect_timer - delta)
	_hurt_iframes = maxf(0.0, _hurt_iframes - delta)
	if _combo_timer <= 0.0:
		_combo = 0
	if _attack_timer > 0.0:
		_attack_timer -= delta
		if _attack_timer <= 0.0:
			attack_shape.disabled = true
	_attack_anim_linger = maxf(0.0, _attack_anim_linger - delta)
	_hurt_anim_timer = maxf(0.0, _hurt_anim_timer - delta)

	if _is_dead:
		velocity = Vector2.ZERO
		return

	# 熔岩池灼烧（环境伤）：不走去 take_damage 的受击通道——无敌帧/击退是
	# "躲怪物攻击"的资产，环境灼烧不该被冲刺白嫖；白闪+飘字+死亡判定保留
	_lava_accum += delta
	if _lava_accum >= LAVA_TICK:
		_lava_accum = 0.0
		if ObstacleField.liquid_kind_at(global_position) == "lava":
			_take_environmental_damage(maxf(1.0, stats.max_hp() * LAVA_DAMAGE_FRAC))

	# 冲刺中：固定方向高速位移 + 无敌帧 + 残影，结束前不响应移动输入；
	# 期间按攻击进入缓冲（触屏队列本就保留），冲刺一结束立即兑现
	if _dash_timer > 0.0:
		_dash_timer -= delta
		if _dash_timer <= 0.0:
			# 计时归零帧无敌已失效：本帧不再以冲刺速度位移、不再生成残影，
			# 只恢复碰撞掩码后落入普通移动分支——否则存在"无敌没了却仍全速
			# 位移 + 同帧恢复怪物碰撞"的 1 帧贴脸挨刀窗口
			collision_mask = MASK_NORMAL
		else:
			# 冲刺激击帧不新增受击（无敌），但冲刺前的残留击退照常衰减并叠加——
			# 旧实现整段冻结，冲刺结束后旧击退满值"复活"再弹一下，观感突兀
			velocity = facing * DASH_SPEED + _knockback
			_knockback = _knockback.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * delta)
			_afterimage_accum -= delta
			if _afterimage_accum <= 0.0:
				_afterimage_accum = AFTERIMAGE_INTERVAL
				_spawn_afterimage()
			# 双通道先各自取值再合并（与主输入分支同法）：or 短路会让键盘命中时
			# 触摸攻击滞留队列，冲刺结束后再兑现一刀 = 一次触摸出两刀
			var key_atk := Input.is_action_just_pressed("attack")
			var pad_atk := TouchInput.consume_attack()
			if key_atk or pad_atk:
				_attack_buffered = true
			# 冲刺中技能即时响应而非丢弃/滞留：躲避中放治疗/法弹是保命连招，
			# 此前键盘整段丢失、触屏却滞留到冲刺结束才兑现——通道行为不对称
			var key_heavy := Input.is_action_just_pressed("heavy_attack")
			var pad_heavy := TouchInput.consume_heavy()
			if key_heavy or pad_heavy:
				_try_heavy_attack()
			var key_bolt := Input.is_action_just_pressed("cast_bolt")
			var pad_bolt := TouchInput.consume_bolt()
			if key_bolt or pad_bolt:
				_try_cast_bolt()
			var key_heal := Input.is_action_just_pressed("heal")
			var pad_heal := TouchInput.consume_heal()
			if key_heal or pad_heal:
				_try_heal()
			var key_emp := Input.is_action_just_pressed("empower")
			var pad_emp := TouchInput.consume_empower()
			if key_emp or pad_emp:
				_try_empower()
			move_and_slide()
			return

	if _attack_buffered:
		_attack_buffered = false
		_try_attack()
	elif _attack_buffer_timer > 0.0 and _attack_cooldown <= 0.0:
		# 预输入兑现：冷却转好的第一时间出刀
		_attack_buffer_timer = 0.0
		_try_attack()

	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if TouchInput.joystick_active:
		dir = TouchInput.move_vector
	# HeroMotion v2：目标速度经加减速逼近（起停重量感），击退仍直接叠加；
	# 起步/反向转身按加速走（跟手），松手滑步按减速走（利落）
	var target_vel := dir * stats.move_speed()
	var accel := MOVE_DECEL
	if target_vel.length() > _move_vel.length() or target_vel.dot(_move_vel) < 0.0:
		accel = MOVE_ACCEL
	_move_vel = _move_vel.move_toward(target_vel, accel * delta)
	velocity = _move_vel + _knockback
	_knockback = _knockback.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * delta)
	if dir != Vector2.ZERO:
		facing = dir.normalized()
		# 素材朝右基准（AI 英雄与骑士包一致）：左右移动翻转即可，攻击方向由挥砍特效表达
		if absf(dir.x) > 0.1 and _attack_anim_linger <= 0.0:
			visual.flip_h = dir.x < 0.0
		_spawn_dust(delta)
	move_and_slide()
	# 像素稳定：精灵世界坐标吸附整数网格（相机画布吸附稳世界；精灵自身
	# 浮点坐标仍会逐帧跳格采样——毛刺闪动的第二来源）
	visual.global_position = visual.global_position.round()

	# 双通道输入先各自取值再合并：or 短路会让触摸队列滞留一帧后误触发
	var key_attack := Input.is_action_just_pressed("attack")
	var pad_attack := TouchInput.consume_attack()
	if key_attack or pad_attack:
		_try_attack()
	var key_dash := Input.is_action_just_pressed("dash")
	var pad_dash := TouchInput.consume_dash()
	if key_dash or pad_dash:
		_try_dash()
	var key_heavy := Input.is_action_just_pressed("heavy_attack")
	var pad_heavy := TouchInput.consume_heavy()
	if key_heavy or pad_heavy:
		_try_heavy_attack()
	var key_bolt := Input.is_action_just_pressed("cast_bolt")
	var pad_bolt := TouchInput.consume_bolt()
	if key_bolt or pad_bolt:
		_try_cast_bolt()
	var key_heal := Input.is_action_just_pressed("heal")
	var pad_heal := TouchInput.consume_heal()
	if key_heal or pad_heal:
		_try_heal()
	var key_empower := Input.is_action_just_pressed("empower")
	var pad_empower := TouchInput.consume_empower()
	if key_empower or pad_empower:
		_try_empower()


## 动画映射（纯表现）：死亡→die；攻击窗口→attack 系连击段；受击残留→hurt；
## 冲刺/移动→walk；站定→idle。
## 置于 _physics_process 开头用上一帧速度判断，冲刺分支的提前 return 不会漏播。
## HeroMotion v2（2026-09-16）四件：
##   ① 步频同步——walk 播放速率随地面速度缩放（移速成长后步幅恒定，防脚底打滑）
##   ② 锁相 bob——起伏相位取自动画帧进度（步落地沉、换步浮），替代自由正弦
##     （两条独立节拍打架 = 提线木偶感）；非 walk 态平滑归零，不再瞬间 snap
##   ③ 起停反馈——起步蹬地挤压+立即一粒尘、停步落定下压（挤压手法与怪物侧一致）
##   ④ 冲刺动作语言——walk 提速 + 朝水平分量前倾（纵向冲刺不歪头），结束平滑回正
## 四方向帧可用性缓存（真机性能优化 2026-09-19）：走路/站定期每物理帧
## 两次后缀拼接 + has_animation 查询是常驻小开销；按 SpriteFrames 实例缓存
## （换肤/换帧表时引用变化自动重建）
var _dir_anim_cache_frames: SpriteFrames
var _dir_anim_cache := {}


func _dir_anims() -> Dictionary:
	var frames: SpriteFrames = visual.sprite_frames
	if frames == null:
		return {}
	if frames != _dir_anim_cache_frames:
		_dir_anim_cache_frames = frames
		_dir_anim_cache = {
			"walk": {"up": frames.has_animation("walk_up"),
				"down": frames.has_animation("walk_down")},
			"idle": {"up": frames.has_animation("idle_up"),
				"down": frames.has_animation("idle_down")},
		}
	return _dir_anim_cache


func _update_anim(delta := 0.0) -> void:
	if visual == null or visual.sprite_frames == null or _is_dead:
		# 死亡由 _die 一次性定姿/播放，不能逐帧重启或回退到活体 idle。
		return
	var want := "idle"
	if _attack_timer <= 0.0 and _attack_anim_linger <= 0.0 and absf(facing.x) > 0.1:
		visual.flip_h = facing.x < 0.0
	if _attack_timer > 0.0 or _attack_anim_linger > 0.0:
		# 三段连击消费实际素材：TS attack1 横斩、attack2/3 共用第二种挥斩；
		# 第三段的重击由既有特效表达，缺分段动画时回退通用 attack
		# linger 窗内维持收招段（判定窗已关，纯表现）
		want = _attack_animation()
		visual.flip_h = _attack_visual_flip
	elif _hurt_anim_timer > 0.0 and visual.sprite_frames.has_animation("hurt"):
		# 受击段：不出招时压过走/站让"挨打"可读；不打断攻击窗（出招优先）
		want = "hurt"
	elif _dash_timer > 0.0 or velocity.length() > 5.0:
		want = "walk"
	if not visual.sprite_frames.has_animation(want):
		want = "idle"
	# 四方向（美术 v5 借鉴②）：纵向移动/站定时用 up/down 帧（NA 官方表列 0/1），
	# 横向保持右向帧 + flip_h 老路径——attack 系无方向分段，纵向出招仍走侧向
	if want == "walk" or want == "idle":
		if absf(facing.y) > absf(facing.x):
			var key := "up" if facing.y < 0.0 else "down"
			if _dir_anims()[want][key]:
				want += "_" + key
	# 仅循环动画需要"停了就重播"；非循环（attack 系/die）播完停在末帧，
	# 重启会闪回首帧（出招姿势），linger 收招段正是要停在读招帧上
	if visual.animation != want or (visual.sprite_frames.get_animation_loop(want) and not visual.is_playing()):
		visual.play(want)
	var walking := want.begins_with("walk")
	if walking:
		# 步频同步：speed_scale=1 时步频 = 12fps/3 帧·步 = 4 步/s（步幅 40px ⇒ 160px/s）；
		# 冲刺按冲刺速度取值（620px/s→吃满 1.8 上限，步频疾促的冲刺语言）
		var ground_speed := DASH_SPEED if _dash_timer > 0.0 else velocity.length()
		visual.speed_scale = clampf(
			(ground_speed / STRIDE_PX) / (12.0 / 3.0), 0.75, 1.8)
	elif want.begins_with("attack"):
		visual.speed_scale = SpritePlayback.speed_for_window(
			visual.sprite_frames, want, ATTACK_WINDOW + ATTACK_ANIM_LINGER)
	elif want == "hurt":
		visual.speed_scale = SpritePlayback.speed_for_window(
			visual.sprite_frames, want, HURT_ANIM_TIME)
	else:
		visual.speed_scale = 1.0
	# 锁相 bob：6 帧循环 = 两步，相位 = (帧序 + 帧内进度)/3 步取整圈
	var bob_target := 0.0
	if walking:
		var cycle := float(visual.frame + visual.frame_progress) / maxf(
			float(visual.sprite_frames.get_frame_count(want)), 1.0)
		bob_target = sin(TAU * cycle * 2.0) * BOB_AMPLITUDE
	if delta > 0.0:
		# 逻辑插值连续、最终绘制吸附整数：既保持步相又避免亚像素毛刺。
		_visual_bob = lerpf(_visual_bob, bob_target, 1.0 - exp(-16.0 * delta))
		visual.offset.y = roundf(_visual_bob)
	# 起停过渡反馈（死亡态不给——倒地帧不该被挤压）
	if delta > 0.0 and walking != _was_walking and not _is_dead:
		if walking:
			_squash(Vector2(0.94, 1.06), 0.12)  # 起步蹬地：纵向拉长蓄势
			_spawn_dust(1.0)  # 立即冒一粒尘（不等 0.22s 累积）
		else:
			_squash(Vector2(1.06, 0.94), 0.12)  # 停步落定：下压收住
	_was_walking = walking
	# 冲刺前倾：只取水平分量（纯纵向冲刺不倾），结束后平滑回正；死亡态不倾
	var lean_target := 0.0
	if _dash_timer > 0.0 and not _is_dead:
		lean_target = clampf(facing.x, -1.0, 1.0) * 0.12
	if delta > 0.0:
		visual.rotation = lerpf(visual.rotation, lean_target, 1.0 - exp(-14.0 * delta))


## 挤压回弹（攻击预备-过冲打击感；与怪物侧同名手法一致）
func _squash(amount: Vector2, dur := 0.16) -> void:
	if _squash_tween != null and _squash_tween.is_valid():
		_squash_tween.kill()
	_squash_tween = visual.create_tween()
	_squash_tween.tween_property(visual, "scale", _visual_base_scale * amount, dur * 0.4)
	_squash_tween.tween_property(visual, "scale", _visual_base_scale, dur * 0.6)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)


## 冲刺：消耗 MP，朝当前朝向高速位移，期间无敌（躲冲锋/重击/弹幕）；
## 同时取消攻击后摇并给下一击增伤——走位输出循环的技巧上限
func _try_dash() -> void:
	# 对话气泡开着时冲刺键 = 关闭对话（不消耗蓝不位移）
	if GameState.dialogue_open:
		EventBus.dialogue_action.emit("decline")
		return
	if _dash_timer > 0.0 or _dash_cd > 0.0:
		return
	if current_mp < Skill.DASH_COST:
		return
	current_mp -= Skill.DASH_COST
	EventBus.player_mp_changed.emit(current_mp, stats.max_mp())
	_push_skills()
	_dash_timer = DASH_TIME
	_dash_cd = Skill.DASH_COOLDOWN * stats.cooldown_mult()
	# 冲刺起手同步翻面（朝向可能来自攻击吸附的斜向向量，移动分支的
	# absf(dir.x) 阈值判不到小横分量时，向左冲却仍面朝右）
	if absf(facing.x) > 0.1 and _attack_anim_linger <= 0.0:
		visual.flip_h = facing.x < 0.0
	_afterimage_accum = 0.0
	# 只重置冷却、不关闭进行中的攻击判定窗：普攻→冲刺取消后摇时判定框仍
	# 短暂开启，冲刺穿过怪堆可蹭到命中（含吸血/顿帧）——有意保留的"冲刺
	# 挥砍"进阶技巧（Hades 式 dash-strike）：冲刺拿来进攻就没法用来保命，
	# 耗蓝 + 1.2s 冷却自带博弈，风险收益自平衡
	_attack_cooldown = 0.0
	_dash_buff_timer = Skill.DASH_BUFF_TIME
	collision_mask = MASK_DASH
	EventBus.player_dashed.emit()


## 脚步尘土：移动中每 0.22s 在脚下冒一个小灰点淡出（池化复用，见 VfxPool 约定）
func _spawn_dust(delta: float) -> void:
	_dust_accum += delta
	if _dust_accum < 0.22:
		return
	_dust_accum = 0.0
	var dust := VfxPool.take("dust") as Polygon2D
	if dust == null:
		dust = Polygon2D.new()
		dust.polygon = PackedVector2Array([
			Vector2(-3, -2), Vector2(3, -2), Vector2(3, 2), Vector2(-3, 2),
		])
		dust.color = Color(0.72, 0.68, 0.6, 0.5)
		dust.z_index = -2
		get_parent().add_child(dust)
	dust.scale = Vector2.ONE
	dust.modulate.a = 1.0
	dust.global_position = global_position + Vector2(randf_range(-4.0, 4.0), _feet_y)
	var tween := dust.create_tween()
	dust.set_meta("vfx_tween", tween)
	tween.set_parallel(true)
	tween.tween_property(dust, "scale", Vector2(1.8, 1.8), 0.4)
	tween.tween_property(dust, "modulate:a", 0.0, 0.4)
	tween.chain().tween_callback(func() -> void: VfxPool.release(dust, "dust"))


## 冲刺残影：复制当前动画帧快照，快速淡出（池化复用）
func _spawn_afterimage() -> void:
	var ghost := VfxPool.take("afterimage") as Sprite2D
	if ghost == null:
		ghost = Sprite2D.new()
		get_parent().add_child(ghost)
	ghost.texture = visual.sprite_frames.get_frame_texture(visual.animation, visual.frame)
	ghost.scale = visual.scale
	ghost.flip_h = visual.flip_h
	ghost.rotation = visual.rotation  # 冲刺前倾姿态带进残影
	ghost.global_position = global_position
	ghost.modulate = Color(0.6, 0.8, 1.0, 0.45)
	var tween := ghost.create_tween()
	ghost.set_meta("vfx_tween", tween)
	tween.tween_property(ghost, "modulate:a", 0.0, 0.3)
	tween.tween_callback(func() -> void: VfxPool.release(ghost, "afterimage"))


## 重击：消耗 MP，圆形 AOE 高倍率伤害 + 冲击环特效 + 震屏顿帧
func _try_heavy_attack() -> void:
	if _heavy_cd > 0.0 or current_mp < Skill.HEAVY_COST or _is_dead:
		return
	_heavy_cd = Skill.HEAVY_COOLDOWN * stats.cooldown_mult()
	current_mp -= Skill.HEAVY_COST
	EventBus.player_mp_changed.emit(current_mp, stats.max_mp())
	_push_skills()
	SfxManager.play("heavy")
	EventBus.camera_shake_requested.emit(5.0)
	EventBus.hit_stop_requested.emit(0.06)
	_play_ring(Skill.HEAVY_RADIUS, Color(1.0, 0.85, 0.4, 0.9))
	_play_burst()
	var dmg := CombatMath.physical_damage(stats.physical_attack() * Skill.HEAVY_MULT)
	var targets: Array = get_tree().get_nodes_in_group("monsters")
	targets.append_array(get_tree().get_nodes_in_group("nests"))
	for body in targets:
		var monster := body as Node2D
		if monster == null or not body.has_method("take_damage"):
			continue
		var mb := body as MonsterBase
		if mb != null and mb.state == MonsterBase.S_CORPSE:
			continue  # 尸体不吃 AOE
		if global_position.distance_to(monster.global_position) <= Skill.HEAVY_RADIUS:
			var effective := false
			var final_dmg := dmg
			if mb != null and mb.inst != null:
				var em: float = CombatMath.elemental_multiplier(
						stats.equip_element(), mb.inst.species.element)
				final_dmg *= em
				effective = em > 1.0
			body.take_damage(final_dmg, global_position, true, stats.knockback_mult(), effective)


## 法弹：消耗 MP，朝当前朝向射出智力加成弹体
func _try_cast_bolt() -> void:
	if _bolt_cd > 0.0 or current_mp < Skill.BOLT_COST or _is_dead:
		return
	_bolt_cd = Skill.BOLT_COOLDOWN * stats.cooldown_mult()
	current_mp -= Skill.BOLT_COST
	EventBus.player_mp_changed.emit(current_mp, stats.max_mp())
	_push_skills()
	SfxManager.play("bolt")
	var bolt := PlayerBolt.new()
	get_parent().add_child(bolt)
	bolt.global_position = global_position + facing * 22.0
	bolt.launch(facing, CombatMath.magic_damage(stats.magic_attack() * Skill.BOLT_MULT), stats.equip_element())


## 治疗：消耗 MP 回复智力加成生命，绿色涟漪特效（深区续航的资源取舍）；
## 满血时拦截——白扣 25 MP + 8s 冷却在触屏端是误触重罚
func _try_heal() -> void:
	if _heal_cd > 0.0 or current_mp < Skill.HEAL_COST or _is_dead \
			or current_hp >= stats.max_hp() - 0.5:
		return
	_heal_cd = Skill.HEAL_COOLDOWN * stats.cooldown_mult()
	current_mp -= Skill.HEAL_COST
	var healed := stats.heal_power() * Skill.HEAL_MULT
	current_hp = minf(stats.max_hp(), current_hp + healed)
	EventBus.player_mp_changed.emit(current_mp, stats.max_mp())
	EventBus.player_hp_changed.emit(current_hp, stats.max_hp())
	_push_skills()
	SfxManager.play("heal")
	_play_ring(44.0, Color(0.5, 1.0, 0.55, 0.9))
	EventBus.fx_requested.emit("flash_blue", global_position, 1.0)


## 使用消耗品（v7 物品系统）：HUD 快捷槽/物品栏经 item_use_requested 触发。
## 拦截顺序：死亡 → 恢复项满档（满血吃 HP 类 / 满蓝喝水壶白费，与治疗满血
## 拦截同口径）→ 库存扣减（GameState）。效果按最大值比例恢复，不吃 heal_power
func use_item(id: String) -> void:
	if _is_dead or not ItemCatalog.is_consumable(id):
		return
	var hp_frac := float(Skill.ITEM_HP_FRAC.get(id, 0.0))
	var mp_frac := float(Skill.ITEM_MP_FRAC.get(id, 0.0))
	if hp_frac > 0.0 and current_hp >= stats.max_hp() - 0.5:
		return
	if mp_frac > 0.0 and current_mp >= stats.max_mp() - 0.5:
		return
	if not GameState.try_use_consumable(id):
		return
	if hp_frac > 0.0:
		current_hp = minf(stats.max_hp(), current_hp + stats.max_hp() * hp_frac)
		EventBus.player_hp_changed.emit(current_hp, stats.max_hp())
	if mp_frac > 0.0:
		current_mp = minf(stats.max_mp(), current_mp + stats.max_mp() * mp_frac)
		EventBus.player_mp_changed.emit(current_mp, stats.max_mp())
	SfxManager.play("heal")
	_play_ring(38.0, Color(0.6, 1.0, 0.6, 0.85))
	EventBus.fx_requested.emit("flash_gold", global_position, 1.0)


## 武装强化：消耗 MP 进入 6s 普攻增益（伤害 ×1.6 + 命中吸血）；
## 持续期间金色光泽标识，与冷却共同约束不可连开
func _try_empower() -> void:
	if _empower_cd > 0.0 or _empower_timer > 0.0 \
			or current_mp < Skill.EMPOWER_COST or _is_dead:
		return
	_empower_cd = Skill.EMPOWER_COOLDOWN * stats.cooldown_mult()
	_empower_timer = Skill.EMPOWER_DURATION
	current_mp -= Skill.EMPOWER_COST
	EventBus.player_mp_changed.emit(current_mp, stats.max_mp())
	_push_skills()
	SfxManager.play("levelup")
	_set_visual_base(Color(1.0, 0.88, 0.55))
	_play_ring(40.0, Color(1.0, 0.82, 0.35, 0.9))
	EventBus.fx_requested.emit("charge", global_position, 1.4)


## 强化激活/结束等边界态写基础色前先杀受击白闪——
## 否则旧 tween 会在其后把颜色拉回"过时的恢复色"（吞掉强化金光泽或复活白色）
func _set_visual_base(color: Color) -> void:
	if _hurt_tween != null and _hurt_tween.is_valid():
		_hurt_tween.kill()
	visual.modulate = color


## 通用冲击环：以自身为圆心扩散淡出（重击金环 / 治疗绿涟漪共用；池化复用）
func _play_ring(radius: float, color: Color) -> void:
	var ring := VfxPool.take("ring") as Line2D
	if ring == null:
		ring = Line2D.new()
		ring.width = 7.0
		ring.z_index = 6
		get_parent().add_child(ring)
	ring.default_color = color
	ring.modulate.a = 1.0
	ring.scale = Vector2.ONE
	var points := PackedVector2Array()
	var steps := 40
	for i in steps:
		points.append(Vector2.RIGHT.rotated(TAU * i / steps) * radius)
	points.append(points[0])
	ring.points = points
	ring.global_position = global_position
	var tween := ring.create_tween()
	ring.set_meta("vfx_tween", tween)
	tween.tween_property(ring, "scale", Vector2.ONE, 0.22) \
		.from(Vector2(0.15, 0.15)).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.parallel().tween_property(ring, "modulate:a", 0.0, 0.3)
	tween.chain().tween_callback(func() -> void: VfxPool.release(ring, "ring"))


func _process(delta: float) -> void:
	if _is_dead:
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			_respawn()
		return
	# 自然回复（策划：生命/魔法可自然回复）
	current_hp = minf(stats.max_hp(), current_hp + stats.hp_regen_per_sec() * delta)
	current_mp = minf(stats.max_mp(), current_mp + stats.mp_regen_per_sec() * delta)
	_hud_accum += delta
	if _hud_accum >= 0.25:
		_hud_accum = 0.0
		EventBus.player_hp_changed.emit(current_hp, stats.max_hp())
		EventBus.player_mp_changed.emit(current_mp, stats.max_mp())
		_push_skills()


func _try_attack() -> void:
	# 对话气泡开着时攻击键 = 确认（接单/继续），不挥刀不消耗冷却
	if GameState.dialogue_open:
		EventBus.dialogue_action.emit("confirm")
		return
	# 世界 v5：贴着地标 NPC 时攻击键 = 对话/接任务（不消耗冷却不挥刀）
	var npc := _nearest_npc()
	if npc != null:
		npc.interact()
		return
	if _attack_cooldown > 0.0:
		# 冷却中按下不丢：进预输入缓冲，冷却一转好立即兑现（连击不断段）
		_attack_buffer_timer = ATTACK_BUFFER_TIME
		return
	_attack_cooldown = stats.attack_interval()
	_attack_timer = ATTACK_WINDOW
	_attack_anim_linger = ATTACK_WINDOW + ATTACK_ANIM_LINGER
	_hit_this_swing.clear()
	# 连击推进：窗口内连续攻击累积段位 1→2→3，第三段为重击（1.5×伤害 2×击退）
	_combo = _combo % 3 + 1
	_combo_timer = stats.combo_window()
	# 朝向吸附：攻击瞬间朝扇形内最近敌人修正，解决"边退边打"的方向冲突
	var aim: Variant = _aim_assist()
	if aim != null:
		facing = aim
	# 只锁精灵朝向，不锁移动/下一招的逻辑 facing；侧向素材必须与吸附后的出刀一致。
	_attack_visual_flip = visual.flip_h if absf(facing.x) <= 0.1 else facing.x < 0.0
	visual.flip_h = _attack_visual_flip
	_hurt_anim_timer = 0.0
	var anim := _attack_animation()
	if visual.sprite_frames.has_animation(anim):
		SpritePlayback.restart(visual, anim, SpritePlayback.speed_for_window(
			visual.sprite_frames, anim, ATTACK_WINDOW + ATTACK_ANIM_LINGER))
	attack_shape.disabled = false
	attack_hitbox.position = facing * ATTACK_REACH
	attack_hitbox.rotation = facing.angle()
	_damage_obstacle_ray()
	_play_slash(_combo)
	_squash(Vector2(1.1, 0.9), 0.16)


## 同名连击/单攻击素材回退共用选择器；启动事件与状态映射必须使用同一段。
func _attack_animation() -> StringName:
	var anim := StringName("attack" + str(clampi(_combo, 1, 3)))
	return anim if visual.sprite_frames.has_animation(anim) else &"attack"


## 最近的可交互地标 NPC（96px 内；无则 null）
func _nearest_npc() -> Node:
	var best: Node = null
	var best_d := 96.0
	for body in get_tree().get_nodes_in_group("npcs"):
		var npc := body as Node2D
		if npc == null or not npc.visible:
			continue
		var d: float = global_position.distance_to(npc.global_position)
		if d < best_d:
			best = npc
			best_d = d
	return best


## 攻击朝向吸附：默认在当前朝向 ±AIM_CONE_DEG 扇形内找最近怪；
## 开启"自动瞄准"设置（触屏友好，Archero 式）则全向吸附最近怪。返回朝向或 null
func _aim_assist() -> Variant:
	var auto_aim := bool(GameState.settings.get("auto_aim", false))
	var best: Node2D = null
	var best_dist := AIM_RANGE
	for body in get_tree().get_nodes_in_group("monsters"):
		var monster := body as Node2D
		if monster == null or not body.has_method("take_damage"):
			continue
		var mb := body as MonsterBase
		if mb != null and mb.state == MonsterBase.S_CORPSE:
			continue  # 尸体留存期不可作为吸附目标（否则朝尸体挥空）
		var offset := monster.global_position - global_position
		var dist := offset.length()
		if dist > best_dist or dist < 1.0:
			continue
		if not auto_aim and absf(facing.angle_to(offset.normalized())) > deg_to_rad(AIM_CONE_DEG):
			continue
		best = monster
		best_dist = dist
	if best == null:
		return null
	return (best.global_position - global_position).normalized()


## 挥砍特效：NA fx 挥砍帧动画（强化期间金色，第三段更大）；播完回池（池化复用）
func _play_slash(combo_step := 0) -> void:
	var fx := VfxPool.take("slash") as AnimatedSprite2D
	if fx == null:
		fx = AnimatedSprite2D.new()
		add_child(fx)
		fx.animation_finished.connect(func() -> void: VfxPool.release(fx, "slash"))
	fx.sprite_frames = FX_SLASH_GOLD if _empower_timer > 0.0 else FX_SLASH
	fx.position = facing * 22.0
	fx.rotation = facing.angle()
	if facing.x < 0.0:
		fx.flip_v = true  # 朝左挥砍保持弧光上沿朝上
	else:
		fx.flip_v = false
	fx.scale = Vector2(2.6, 2.6) * (1.4 if combo_step == 3 else 1.0)
	fx.z_index = 5
	fx.modulate = Color.WHITE
	fx.play("play")


## 重击爆裂：橙色爆炸帧以自身为中心（与冲击环叠用，半径观感 ≈ Skill.HEAVY_RADIUS；池化复用）
func _play_burst() -> void:
	var fx := VfxPool.take("burst") as AnimatedSprite2D
	if fx == null:
		fx = AnimatedSprite2D.new()
		add_child(fx)
		fx.animation_finished.connect(func() -> void: VfxPool.release(fx, "burst"))
	fx.sprite_frames = FX_BURST
	fx.position = Vector2.ZERO
	fx.rotation = 0.0
	fx.scale = Vector2(4.0, 4.0)
	fx.z_index = 5
	fx.modulate = Color.WHITE
	fx.play("play")


## 环境伤害（熔岩灼烧等）：绕过无敌帧/击退/顿帧，保留白闪/飘字/死亡判定
func _take_environmental_damage(amount: float) -> void:
	if _is_dead:
		return
	current_hp = maxf(0.0, current_hp - amount)
	if _hurt_tween != null and _hurt_tween.is_valid():
		_hurt_tween.kill()
	visual.modulate = Color(1.7, 1.2, 0.9)
	var restore := Color(1.0, 0.88, 0.55) if _empower_timer > 0.0 else Color.WHITE
	_hurt_tween = visual.create_tween()
	_hurt_tween.tween_property(visual, "modulate", restore, 0.12)
	EventBus.damage_number.emit(global_position, int(round(amount)), true, false)
	EventBus.camera_shake_requested.emit(3.0)
	EventBus.player_hp_changed.emit(current_hp, stats.max_hp())
	if current_hp <= 0.0:
		last_killed_by = "熔岩灼烧"
		_die()


func take_damage(amount: float, from_position := Vector2.INF, source_name := "") -> void:
	if _is_dead:
		return
	# 冲刺/重生保护/受击无敌帧：期间免疫一切伤害（群体同帧命中只结算第一下）
	if _dash_timer > 0.0 or _protect_timer > 0.0 or _hurt_iframes > 0.0:
		return
	current_hp = maxf(0.0, current_hp - amount)
	_hurt_iframes = HURT_IFRAME
	# 出招时以白闪表达受击；不排队一段即将过期的 hurt 截断残片。
	if _attack_anim_linger <= 0.0 and _attack_timer <= 0.0 \
			and visual.sprite_frames.has_animation(&"hurt"):
		_hurt_anim_timer = HURT_ANIM_TIME
		SpritePlayback.restart(visual, &"hurt", SpritePlayback.speed_for_window(
			visual.sprite_frames, &"hurt", HURT_ANIM_TIME))
	# 受击白闪 + 极短顿帧：围攻时"被谁打中"必须可读（此前只有震屏，方向感缺失）
	if _hurt_tween != null and _hurt_tween.is_valid():
		_hurt_tween.kill()
	visual.modulate = Color(1.7, 1.7, 1.7)
	var restore := Color(1.0, 0.88, 0.55) if _empower_timer > 0.0 else Color.WHITE
	_hurt_tween = visual.create_tween()
	_hurt_tween.tween_property(visual, "modulate", restore, 0.12)
	EventBus.hit_stop_requested.emit(0.05)
	EventBus.damage_number.emit(global_position, int(round(amount)), true, false)
	if source_name != "":
		last_killed_by = source_name
	if from_position != Vector2.INF:
		var dir := (global_position - from_position).normalized()
		if dir == Vector2.ZERO:
			dir = Vector2.UP
		_knockback += dir * 160.0
	EventBus.camera_shake_requested.emit(6.0)
	EventBus.player_hp_changed.emit(current_hp, stats.max_hp())
	if current_hp <= 0.0:
		_die()


func _die() -> void:
	if _is_dead:
		return
	_is_dead = true
	_respawn_timer = RESPAWN_DELAY
	# 致死一击的受击白闪 tween 会与死亡淡出并发写 modulate（约 0.12s 的 alpha 闪跳），先杀
	if _hurt_tween != null and _hurt_tween.is_valid():
		_hurt_tween.kill()
	if _squash_tween != null and _squash_tween.is_valid():
		_squash_tween.kill()
	visual.scale = _visual_base_scale
	visual.offset = Vector2.ZERO
	_visual_bob = 0.0
	visual.rotation = 0.0
	# TS Warrior 没有死亡条带：冻结中性姿势淡出，不能继续 idle/挥刀。
	# 回退素材若有 die，则留足原生动作时长后隐藏（复活延时不变）。
	var fade_time := 0.5
	if visual.sprite_frames != null and visual.sprite_frames.has_animation(&"die"):
		SpritePlayback.restart(visual, &"die")
		fade_time = minf(RESPAWN_DELAY, maxf(fade_time,
			SpritePlayback.duration(visual.sprite_frames, &"die")))
	else:
		visual.animation = &"idle"
		visual.stop()
		visual.speed_scale = 1.0
	_death_tween = visual.create_tween()
	_death_tween.tween_property(visual, "modulate:a", 0.0, fade_time)
	_death_tween.tween_callback(func(): visible = false)
	if _shadow != null:
		_shadow.visible = false
	# set_deferred：弹幕击杀路径的调用栈在 Area2D body_entered 回调内
	# （物理查询冲刷期），直接改碰撞形状状态会触发引擎错误
	attack_shape.set_deferred("disabled", true)
	# 倒下即失去强化状态（金色光泽一并收回；不动 alpha，别打断死亡淡出）
	_empower_timer = 0.0
	visual.modulate = Color(1.0, 1.0, 1.0, visual.modulate.a)
	# 死亡期间触屏按键的排队不应在复活后一次性兑现
	TouchInput.clear_queues()
	# 死亡代价：掉落两成金币（风险感 + 经济回收；赏金与商店让金币有真实价值）
	var lost := int(GameState.gold * 0.2)
	if lost > 0:
		GameState.add_gold(-lost)
		EventBus.hint_requested.emit("倒下了…丢失 %d 金币" % lost)
	EventBus.player_died.emit()


func _respawn() -> void:
	# 复活前再清一次触屏队列：死亡 2s 里 _physics_process 早退、无人消费，
	# 狂点的攻击/技能会在复活第一帧全部兑现（蓝量蒸发 + CD 全开）——
	# _die() 只清了死亡瞬间的旧队列，这里补上"死亡期间持续积压"的口子
	TouchInput.clear_queues()
	if _death_tween != null and _death_tween.is_valid():
		_death_tween.kill()
	_is_dead = false
	# v4 大世界（端到端 1 小时+）：复活在最近的低威胁群系（平原/林地）斑块中心，
	# 而非固定出生角——死亡惩罚保留（走回战斗地点要时间），但不再摧毁整局体验
	global_position = WorldConfig.nearest_safe_respawn(global_position)
	current_hp = stats.max_hp()
	current_mp = stats.max_mp()
	visual.modulate = Color.WHITE
	visual.offset.y = 0.0
	_visual_bob = 0.0
	visible = true
	if _shadow != null:
		_shadow.visible = true
	# 清战斗残留：致死击退/连击段/攻击窗口/冲刺穿怪/技能冷却与增益不带入重生
	# （重生即满状态——满血满蓝却背着旧 CD 开局会很别扭）
	_knockback = Vector2.ZERO
	_move_vel = Vector2.ZERO
	visual.rotation = 0.0
	_combo = 0
	_combo_timer = 0.0
	_dash_timer = 0.0
	collision_mask = MASK_NORMAL
	_attack_buffered = false
	_attack_buffer_timer = 0.0
	_hurt_iframes = 0.0
	_attack_timer = 0.0
	_attack_anim_linger = 0.0
	_hurt_anim_timer = 0.0
	_was_walking = false
	SpritePlayback.restart(visual, &"idle")
	_attack_cooldown = 0.0
	_dash_cd = 0.0
	_heavy_cd = 0.0
	_bolt_cd = 0.0
	_heal_cd = 0.0
	_empower_cd = 0.0
	_dash_buff_timer = 0.0
	_empower_timer = 0.0
	_hit_this_swing.clear()
	_protect_timer = RESPAWN_PROTECT
	# "本局击杀"按条命计：死亡信息展示完（2s 重生窗口）后清零，
	# 下次倒下显示的是这一条的击杀数而非进世界以来的累计
	GameState.session_kills = 0
	_push_hud()
	EventBus.player_respawned.emit()


func _on_attack_body_entered(body: Node) -> void:
	if not (body.is_in_group("monsters") or body.is_in_group("nests")) \
			or not body.has_method("take_damage"):
		return
	if body in _hit_this_swing:
		return
	_hit_this_swing.append(body)
	# 尸体不吃判定（与重击/朝向吸附同口径）：伤害被尸体守卫吞掉后，
	# 不再结算吸血/顿帧——对刚被秒杀的怪补刀 = 免费回血
	var corpse_check := body as MonsterBase
	if corpse_check != null and corpse_check.state == MonsterBase.S_CORPSE:
		return
	# 连击第三段重击（×1.5）+ 冲刺后增伤（×1.3）+ 武装强化（×1.6）
	# + 装备元素克制（火克冰/冰克火 ×1.5）
	var mult := 1.0
	if _combo == 3:
		mult *= Skill.COMBO_HEAVY_MULT
	if _dash_buff_timer > 0.0:
		mult *= Skill.DASH_BUFF_MULT
	if _empower_timer > 0.0:
		mult *= Skill.EMPOWER_MULT
	var monster := body as MonsterBase
	var effective := false
	if monster != null and monster.inst != null:
		var em: float = CombatMath.elemental_multiplier(
				stats.equip_element(), monster.inst.species.element)
		mult *= em
		effective = em > 1.0
		# 元素克制命中特效（美术 v5 fx 全量）：火→焰 / 冰→霜，只在克制时炸开
		if effective:
			EventBus.fx_requested.emit(
				"flame" if stats.equip_element() == "fire" else "frost",
				monster.global_position, 1.1)
	body.take_damage(CombatMath.physical_damage(stats.physical_attack() * mult),
			global_position, _combo == 3, stats.knockback_mult(), effective)
	# 噬血被动：命中吸血；武装强化期间额外回复最大生命 3%（连击越快续航越强）
	var lifesteal := stats.lifesteal_per_hit()
	if _empower_timer > 0.0:
		lifesteal += stats.max_hp() * Skill.EMPOWER_HEAL_FRAC
	if lifesteal > 0.0:
		current_hp = minf(stats.max_hp(), current_hp + lifesteal)
		EventBus.player_hp_changed.emit(current_hp, stats.max_hp())
	# 命中顿帧：极短的时间尺度压低，挥砍"打实"的手感；
	# 短窗节流——AOE 同帧命中多只只压一次，避免连续命中把 time_scale 反复打穿
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_hit_stop >= 0.2:
		_last_hit_stop = now
		EventBus.hit_stop_requested.emit(0.035)


## 挥砍对障碍的射线结算（世界 v5）：Area2D 的 body_entered 对"先于本次挥砍
## 就存在的静态瓦片体"不派发进入事件（形状后启用≠进入；怪物是动态体不受
## 影响）——静态体用射线直查最可靠，命中点换算障碍格
func _damage_obstacle_ray() -> void:
	var rq := PhysicsRayQueryParameters2D.create(global_position,
			global_position + facing * 44.0, 1)
	rq.exclude = [get_rid()]
	var hit := get_world_2d().direct_space_state.intersect_ray(rq)
	if hit.is_empty():
		# 流式铺设竞态兜底（真机性能优化二轮）：新入窗障碍格的逻辑数据先于
		# 碰撞体分帧铺设到位，射线会落空——按真源 ObstacleField 复查刀锋扫过
		# 的格，避免刚出现的岩石"打不着"；探测点仍在射线段上，reach 语义不变
		for reach in [30.0, 42.0]:
			var probe := Vector2i(
					floori((global_position + facing * reach).x / 32.0),
					floori((global_position + facing * reach).y / 32.0))
			var s := ObstacleField.sample_cell(probe)
			if not s.is_empty() and ObstacleField.DESTRUCTIBLE.has(s["kind"]):
				var k := ObstacleField.damage_cell(probe)
				if k != "":
					_on_obstacle_destroyed(probe, k)
				return
		return
	var collider: Object = hit["collider"]
	var is_obstacle := (collider is TileMapLayer) \
			or (collider is StaticBody2D and collider.has_meta("obstacle"))
	if not is_obstacle:
		return
	var cell := Vector2i(floori(hit.position.x / 32.0), floori(hit.position.y / 32.0))
	var kind := ObstacleField.damage_cell(cell)
	if kind != "":
		_on_obstacle_destroyed(cell, kind)
	else:
		EventBus.camera_shake_requested.emit(2.0)  # 砍硬壁的轻反馈


## 障碍摧毁反馈（普攻/法弹共用）：广播表现信号 + 概率掉零钱 + 震屏
func _on_obstacle_destroyed(cell: Vector2i, kind: String) -> void:
	var pos := (Vector2(cell) + Vector2(0.5, 0.5)) * 32.0
	EventBus.obstacle_destroyed.emit(cell, pos, kind)
	EventBus.camera_shake_requested.emit(3.0)
	if randf() < ObstacleField.DESTROY_GOLD_CHANCE:
		var amount := randi_range(int(ObstacleField.DESTROY_GOLD_RANGE[0]),
				int(ObstacleField.DESTROY_GOLD_RANGE[1]))
		GameState.add_gold(amount)
		EventBus.world_event.emit("💎 碎石中拾得 %d 金币" % amount)


## 技能冷却/蓝量即时推送：施放成功的瞬间就刷新 HUD（否则要等 0.25s 节流，
## "按了没转圈"的空窗在连招里很伤手感）
func _push_skills() -> void:
	EventBus.player_skills_changed.emit(
		_dash_cd, _heavy_cd, _bolt_cd, _heal_cd, _empower_cd, current_mp, stats.max_mp())


func _push_hud() -> void:
	EventBus.player_hp_changed.emit(current_hp, stats.max_hp())
	EventBus.player_mp_changed.emit(current_mp, stats.max_mp())
	EventBus.player_progress_changed.emit(
		GameState.stats.level, GameState.stats.xp,
		GameState.stats.xp_to_next(), GameState.stats.pending_points
	)
	EventBus.gold_changed.emit(GameState.gold)
	_push_skills()
