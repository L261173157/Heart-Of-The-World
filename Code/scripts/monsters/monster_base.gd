## 怪物表现基类：MonsterInstance（纯数据）的"身体"。
## 公共状态机：巡逻 → 追击 → 攻击 / 逃跑 / 长途迁徙 / 尸体；
## 各物种子类通过重写虚函数注入专属机制（冲锋/分裂/远程/协同/重击）。
## 属性全部从 inst 实时计算；死亡/老化由 EcologySim 单点权威决定
## （report_killed → instance_died 信号回到这里）。
## 战斗参数（侦测/射程/冷却/逃跑比/护甲/击退抗性）全部读 SpeciesData。
class_name MonsterBase
extends CharacterBody2D

const S_PATROL := 0
const S_CHASE := 1
const S_ATTACK := 2
const S_FLEE := 3
const S_MIGRATING := 4
const S_CORPSE := 5

const PATROL_RADIUS := 60.0
const PATROL_SPEED := 40.0
## 巡猎接近（斑块级流式生成配套）：玩家进斑块时实例在数千米外生成，
## 侦测圈外的个体以巡猎步速主动逼近到「侦测圈外 20%（且至少可见）」处
## 驻足转常规巡逻——跑图必与斑块种群相遇，且是渐进包围而非贴脸围殴。
## 这是 AI 行为：实例 spawn_pos/锚点不漂移，巢穴与据点语义不变
const HUNT_SPEED_MULT := 0.7
## 巡猎触发距离：只逼近玩家周边这一半径内的个体，更远的原地巡逻等玩家
## 走近——同时围上来的永远只有个位数，跑图压力渐进而不至于全斑围殴
const HUNT_MAX_DIST := 24000.0
const MIGRATE_ARRIVE_DIST := 24.0
const KNOCKBACK_DECAY := 900.0
## 通用近战前摇：出刀前短暂站定预警（此前妖鬼/骷髅兵冷却一到瞬间结算，
## 玩家"看不见攻击发生"就挨刀——被打时必须读得出攻击来源与规避窗口）。
## 与石魔像蓄力圈同一设计语言；前摇期间走出 attack_range×1.1 即取消本次出刀
## （1.1 而非 1.0：0.2s 前摇内玩家脚程就能跨出整个攻击距离，按 1.0 严格复查
## 会让近战怪对会走位的玩家刀刀挥空；10% 容差 = "认真逃离才躲得掉"）
const MELEE_WINDUP := 0.2
## 近战出刀前摇的站定预警色（"接下来 0.2 秒要出刀"的可读性信号）
const WINDUP_TINT := Color(1.0, 0.72, 0.4)
## 导航直线兜底距离：目标超出此距离（≈导航窗边缘）不查路径，直线+滑行
## （窗内 NavigationAgent 走导航网格绕障；窗外反正看不见，直线即可）
const NAV_DIRECT_DIST := 2600.0
## 重设导航目标的最小位移：目标挪动小于此值不触发重算路径（每帧 set 目标
## 会让 NavigationServer 每帧全量重算路径，30 只活跃怪会吃满帧预算）
const NAV_RETARGET_STEP := 64.0

## 导航代理（世界 v5）：追击/逃跑/迁徙/巡逻的绕障路径 + RVO 同族群体避让
## （蚂蚁群散开包围取代物理推挤长龙）。移动经 velocity 协议：
## set_velocity(期望) → velocity_computed(安全速度) → move_and_slide
var _nav: NavigationAgent2D = null
var _nav_target := Vector2.INF
## 卡死看门狗状态（_nav_velocity_toward 用）
var _nav_stuck_pos := Vector2.INF
var _nav_stuck_ms := 0
var _nav_stuck_until_ms := 0
## RVO 回调到达标记（回调缺失的极端时序按原速直行兜底，宁可挤不能卡）
var _awaiting_rvo := false
var _pending_move_delta := 0.0

## 物种节点注册表（static）：受击求援按物种定向派发，
## 只遍历本物种列表——替代原先 EventBus 全体妖鬼+骷髅兵广播（群体战 O(全怪) 开销）
static var _species_registry: Dictionary = {}

var inst: MonsterInstance
var anchor := Vector2.ZERO
var current_hp := 0.0
## 出生时的 max_hp 基准：max_hp 随年龄实时增长，current_hp 需同步抬升增量
## （否则未受击的怪头顶永远挂着"缺一口"的血条，老龄个体满血误判逃跑）
var _max_hp_ref := 0.0
var state: int = S_PATROL

## 场景里 Visual 精灵的基础缩放（体型表现在此基础上乘 size_scale）
var sprite_base_scale := Vector2.ONE
## 常态底色（精英为金色；受击闪红后回到它而不是纯白）
var _base_modulate := Color.WHITE

var _attack_cd := 0.0
## 近战前摇剩余时间（> 0 = 预警站定中，结束时出刀）
var _melee_windup := 0.0
## 仇恨锁：群体响应期间不因脱离侦测圈而放弃追击
var _aggro_lock := 0.0
## 巢穴被捣毁的全族激怒：侦测提升 + 不再逃跑
var _enrage_timer := 0.0
const ENRAGE_TIME := 60.0
const ENRAGE_DETECT_MULT := 1.8
var _knockback := Vector2.ZERO
var _patrol_target := Vector2.ZERO
var _patrol_wait := 0.0
var _patrol_target_valid := false
## 巡猎接近进行中（setup 时按玩家距离判定；进入侦测圈/驻足后清除）
var _hunt_mode := false
## 受击闪红 tween（写入新的闪红/技能色前先杀旧的，避免旧 tween 把颜色拉回去）
var _flash_tween: Tween
## 落地阴影（消除贴纸悬浮感）
var _shadow: ShadowBlob
## 挤压/回弹 tween（攻击预备-过冲的打击感层，与帧动画叠加）
var _squash_tween: Tween
## 行走浮动计时（_update_anim 的 bob 相位）
var _anim_time := 0.0
## 玩家引用缓存：替代每物理帧的组查询（失效置空重查）
var _player_ref: Node2D
## 头顶血条（事件驱动重绘的宿主）
var _hp_bar: MonsterHpBar

@onready var visual: AnimatedSprite2D = $Visual


func setup(p_inst: MonsterInstance) -> void:
	inst = p_inst
	# 落点与巡逻锚点：区域内部随机扎根（±45% 半幅），
	# 避免全员挤在区域中心一团、四周大片空旷；分裂子代在母体死亡处扎根
	var region: SimRegion = WorldSim.sim.get_region(inst.region_id)
	if inst.spawn_pos != Vector2.INF:
		anchor = inst.spawn_pos
		var offset := Vector2(randf_range(-26.0, 26.0), randf_range(-26.0, 26.0))
		# 分裂子代出生避让击杀者：玩家还站在尸体上时向反方向弹出——
		# 出生即与玩家重叠会被 depenetration 生硬弹开（"裂开瞬间挤成一团"），
		# 偏移后仍紧邻尸体（"在尸体处裂开"的语义不变）
		var killer := _get_player()
		if inst.generation > 0 and killer != null and killer.visible \
				and inst.spawn_pos.distance_to(killer.global_position) < 48.0:
			var away := inst.spawn_pos - killer.global_position
			if away == Vector2.ZERO:
				away = Vector2.UP
			offset = away.normalized() * 42.0 \
					+ Vector2(randf_range(-10.0, 10.0), randf_range(-10.0, 10.0))
		global_position = inst.spawn_pos + offset
	elif region != null:
		var half := region.size * 0.45
		anchor = region.center + Vector2(randf_range(-half.x, half.x), randf_range(-half.y, half.y))
		global_position = anchor
	else:
		anchor = WorldSim.sim.get_region_center(inst.region_id)
		global_position = anchor
	# 读档恢复的怪带伤开局（hp_mirror 由受击/成长时 report_hp 维护；-1 = 满血）；
	# 钳 [1, max] 防手改档超界——濒死个体恢复成 1 血而不是即死即崩
	var max_now := inst.max_hp()
	current_hp = clampf(inst.hp_mirror, 1.0, max_now) if inst.hp_mirror > 0.0 else max_now
	_max_hp_ref = max_now
	sprite_base_scale = visual.scale
	if inst.is_elite:
		_base_modulate = Color(1.0, 0.78, 0.30)
		modulate = _base_modulate
	elif inst.species.is_boss:
		# Boss：暗金底色 + 恒定脉动光晕（顶点掠食者的威压感）
		_base_modulate = Color(1.0, 0.72, 0.35)
		modulate = _base_modulate
	_apply_size_visual()
	# 阴影随体型缩放（含场景基础缩放，与脚点 y 同源——否则石魔像/Boss
	# "大怪踩小影"，阴影与体型读数对不上）；占地系数走 body_k()
	var body := body_k()
	if _shadow != null:
		_shadow.shadow_scale = Vector2.ONE * sprite_base_scale.x * body
		_shadow.position.y = 9.0 * sprite_base_scale.y * body
	# 碰撞体随体型缩放（duplicate 防共享 shape 资源被同场景多物种互相污染）：
	# 小型档更好绕开、大型档更好命中——命中判定与视觉占地一致
	var cs := $CollisionShape2D as CollisionShape2D
	if cs != null and cs.shape != null and not is_equal_approx(body, 1.0):
		var scaled := cs.shape.duplicate()
		if scaled is CircleShape2D:
			(scaled as CircleShape2D).radius *= body
		elif scaled is RectangleShape2D:
			(scaled as RectangleShape2D).size *= body
		else:
			scaled = null  # 其余形状类型暂无场景使用，出现时按需补
		if scaled != null:
			cs.shape = scaled
	# 种族帧覆盖（冰晶史莱姆共用红史莱姆场景但换蓝色帧）：换帧会停播，重开 idle
	if inst.species.frames_override != null:
		visual.sprite_frames = inst.species.frames_override
		visual.play(&"idle")
	# 注册表登记：has 先行判一次（get_or_add 的默认参数每次调用都会构造新数组）。
	# 注意不能写 `var a: Array = dict.get(k)` ——键缺失时 get 返回 null，
	# 对强类型 Array 变量赋 null 是运行时错误（首个该物种个体登记时必然踩中）
	if not _species_registry.has(inst.species.species_name):
		_species_registry[inst.species.species_name] = []
	_species_registry[inst.species.species_name].append(self)
	# 导航代理参数（需要 inst）：半径随体型；RVO 同族避让——按物种名哈希取
	# 避让层位（30 层内偶发同层 = 两个物种互相避让，无害且更生动）
	if _nav != null:
		_nav.radius = clampf(12.0 * maxf(0.6, inst.size_scale), 8.0, 30.0)
		_nav.avoidance_enabled = true
		_nav.neighbor_distance = 96.0
		_nav.max_neighbors = 6
		var layer := 1 << (absi(hash(inst.species.species_name)) % 30)
		_nav.avoidance_layers = layer
		_nav.avoidance_mask = layer
	# 巡猎接近判定：斑块级流式下个体常在数千米外生成，侦测圈外的非 Boss
	# 个体主动逼近（Boss 盘踞斑块中心不巡猎）。只巡猎「玩家当前所在斑块」
	# 的个体——邻接斑块生成的原地巡逻（玩家跨斑时才触发），避免邻斑怪群
	# 跨斑围殴把遭遇密度推到失控。stream_all 全量生成的测试场景同样受
	# 同斑判定约束，近处个体由距离判定天然豁免
	if not inst.species.is_boss:
		var player0 := _get_player()
		var in_player_patch := false
		if player0 != null and player0.visible and WorldSim.sim != null:
			var player_region: SimRegion = WorldSim.sim.region_of_point(player0.global_position)
			in_player_patch = player_region != null and player_region.id == inst.region_id
		_hunt_mode = in_player_patch \
				and global_position.distance_to(player0.global_position) \
						> inst.species.detect_radius * 1.5 \
				and global_position.distance_to(player0.global_position) <= HUNT_MAX_DIST


func _exit_tree() -> void:
	# 节点销毁/场景卸载时从注册表摘除，防悬挂引用与跨场景泄漏
	if inst == null:
		return
	var list: Array = _species_registry.get(inst.species.species_name)
	if list != null:
		list.erase(self)
		if list.is_empty():
			_species_registry.erase(inst.species.species_name)


func _ready() -> void:
	add_to_group("monsters")
	_nav = NavigationAgent2D.new()
	_nav.path_desired_distance = 12.0
	_nav.target_desired_distance = 20.0
	_nav.velocity_computed.connect(_on_nav_velocity)
	add_child(_nav)
	_hp_bar = MonsterHpBar.new()
	add_child(_hp_bar)
	_shadow = ShadowBlob.new()
	_shadow.z_index = -1
	_shadow.position.y = 9.0
	add_child(_shadow)
	EventBus.nest_ransacked.connect(_on_nest_ransacked)


func _on_nest_ransacked(species_name: String) -> void:
	if inst != null and inst.species.species_name == species_name and not inst.species.is_boss:
		_enrage_timer = ENRAGE_TIME
		_pulse_red()


## 技能预警/情绪色写入点：先杀掉进行中的闪红，避免旧 tween 结束时把颜色拉回底色
func set_tint(color: Color) -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	modulate = color


## 闪红结束时应恢复的颜色；子类重写以返回当前预警色（石魔像蓄力橙/野猪前摇色）
func _restore_tint() -> Color:
	# 近战前摇中被击：闪红收回后预警色仍在（出刀可读性不因受击丢失）
	if _melee_windup > 0.0:
		return WINDUP_TINT
	return _base_modulate


## 受击/激怒闪红：渐回"当前应有颜色"——预警色期间被攻击不吞掉预警
func _pulse_red() -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	modulate = Color(1.0, 0.45, 0.45)
	_flash_tween = create_tween()
	_flash_tween.tween_property(self, "modulate", _restore_tint(), 0.15)


func _get_player() -> Node2D:
	if _player_ref == null or not is_instance_valid(_player_ref):
		_player_ref = get_tree().get_first_node_in_group("player") as Node2D
	return _player_ref


## 体型表现（分裂子代缩小）；子类可扩展（如红史莱姆的果冻脉动在此基础上叠加）
func _apply_size_visual() -> void:
	visual.scale = _visual_base()


## visual.scale 的稳态基准（果冻脉动/squash 回弹目标同源）：
## 场景画幅 × 个体体型 × 物种 visual_scale（Boss=画幅补偿对齐 16px 基准；
## 非 Boss=iOS 横屏重设计的体型档位：小型 0.7 / 标准 1.0 / 大型 1.3 / 守卫 1.7）
func _visual_base() -> Vector2:
	return sprite_base_scale * maxf(0.45, inst.size_scale) * inst.species.visual_scale


## 碰撞/阴影/血条抬升的占地系数：非 Boss 含物种档位（占地随视觉缩放）；
## Boss 只含 size_scale——其 visual_scale 是画幅补偿，不改变世界占地
func body_k() -> float:
	if inst.species.is_boss:
		return maxf(0.45, inst.size_scale)
	return maxf(0.45, inst.size_scale) * inst.species.visual_scale


func _physics_process(delta: float) -> void:
	if state == S_CORPSE:
		velocity = Vector2.ZERO
		return

	_attack_cd = maxf(0.0, _attack_cd - delta)
	_aggro_lock = maxf(0.0, _aggro_lock - delta)
	_enrage_timer = maxf(0.0, _enrage_timer - delta)
	# 年龄增长 → max_hp 实时上调，未受伤的部分随上限同步抬升
	# （已扣血量保持不变，血条比例对玩家始终可信）
	var max_now := inst.max_hp()
	if max_now > _max_hp_ref:
		current_hp = minf(current_hp + (max_now - _max_hp_ref), max_now)
		_max_hp_ref = max_now
		if _hp_bar != null:
			_hp_bar.notify_change()  # 已显示的血条同步重绘，比例不滞后到下次受击
		_sync_hp_mirror()
	# 离开攻击状态（逃跑/受击断招/死亡/迁徙）即作废进行中的前摇；非死亡的中断
	# 同时收回前摇预警色——否则走位拉开距离取消出刀后，怪身上一直挂着
	# "要出刀"的橙色直到下次受击，前摇预警的可信度被破坏；
	# 尸体态例外：灰化色已由 on_sim_death 写定，覆写会把尸体拉回活体色
	if state != S_ATTACK and _melee_windup > 0.0:
		_melee_windup = 0.0
		if state != S_CORPSE:
			set_tint(_restore_tint())
	var player := _get_player()

	if _enrage_timer <= 0.0 and _wants_flee(player) \
			and (state == S_PATROL or state == S_CHASE or state == S_ATTACK):
		state = S_FLEE

	match state:
		S_PATROL:
			_patrol(delta, player)
		S_CHASE:
			_chase_tick(delta, player)
		S_ATTACK:
			_attack_tick(delta, player)
		S_FLEE:
			_flee_tick(player)
		S_MIGRATING:
			_migrate_tick()
		_:
			_extra_state_tick(delta, player)

	velocity += _knockback
	_knockback = _knockback.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * delta)
	# RVO 避让：期望速度交 NavigationServer，安全速度回调里执行移动（群体散开）。
	# 回调缺失的极端时序按原速直行兜底——宁可偶尔挤一下，不能一帧不动卡死
	if _nav != null and _nav.avoidance_enabled:
		if _awaiting_rvo:
			_awaiting_rvo = false
			move_and_slide()
			_post_move_and_anim(delta)
		_pending_move_delta = delta
		_awaiting_rvo = true
		_nav.set_velocity(velocity)
	else:
		move_and_slide()
		_post_move_and_anim(delta)


## 移动后处理（move_and_slide 之后）：当帧碰撞钩子 + 朝向 + 帧动画。
## 直接移动与 RVO 回调两条路径共用，保持两条路径的行为逐位一致
func _post_move_and_anim(delta: float) -> void:
	# move_and_slide 之后的状态钩子：需要当帧碰撞数据的判定在此读取
	# （状态 match 在 move 之前执行，读到的是上一物理帧的残留数据）
	_post_move_hook(delta)
	# 素材默认朝右，横向移动时翻转（纵向移动保持上一朝向）
	if absf(velocity.x) > 5.0:
		visual.flip_h = velocity.x < 0.0
	_anim_time += delta
	_update_anim()


func _on_nav_velocity(safe_velocity: Vector2) -> void:
	_awaiting_rvo = false
	if state == S_CORPSE:
		return
	velocity = safe_velocity
	move_and_slide()
	_post_move_and_anim(_pending_move_delta)


# --- 导航寻路（世界 v5） ---

## 朝目标移动的期望速度：近距走 NavigationAgent 路径（绕障），超远/无网格
## 直线兜底。目标重设按 NAV_RETARGET_STEP 节流（见常量注释）
func _nav_velocity_toward(target: Vector2, speed: float) -> Vector2:
	var direct := (target - global_position).normalized() * speed
	if _nav == null or global_position.distance_to(target) > NAV_DIRECT_DIST:
		_nav_target = Vector2.INF
		return direct
	# 卡死看门狗（所有导航状态共用）：1s 内位移不足期望 15% 判定贴边卡死，
	# 强制重铺路径并持续 0.45s 横向蹭步脱困（追击怪贴障碍边物理卡死的兜底——
	# combat 掩体用例曾实测绕至 83px 处滞留到超时；正常移动不触发）
	var now := Time.get_ticks_msec()
	if now < _nav_stuck_until_ms:
		return direct.orthogonal().normalized() * speed * 0.7
	if _nav_stuck_pos == Vector2.INF \
			or global_position.distance_to(_nav_stuck_pos) > maxf(6.0, speed * 0.15):
		_nav_stuck_pos = global_position
		_nav_stuck_ms = now
	elif now - _nav_stuck_ms >= 1000:
		_nav_stuck_ms = now
		_nav_stuck_pos = global_position
		_nav_stuck_until_ms = now + 450
		_nav_target = Vector2.INF
	if _nav_target == Vector2.INF or _nav_target.distance_squared_to(target) > NAV_RETARGET_STEP * NAV_RETARGET_STEP:
		_nav_target = target
		_nav.target_position = target
	var next := _nav.get_next_path_position()
	if next.distance_squared_to(global_position) < 4.0:
		return direct
	return (next - global_position).normalized() * speed


## 与目标的视线（原生射线查询，_physics_process 上下文调用）：只检测障碍墙层
## （layer 1 树/岩）——挡弹道的才算掩体，怪群与巢穴不遮视线。终点向回撤 28px：
## 玩家碰撞体也在 layer 1，射线打进目标本体会把"看得见"永远误判成"被挡"
func _has_los(target_pos: Vector2) -> bool:
	var offset := target_pos - global_position
	var length := offset.length()
	if length < 60.0:
		return true  # 贴脸无需视线
	var to := global_position + offset.normalized() * (length - 28.0)
	var query := PhysicsRayQueryParameters2D.create(global_position, to, 1)
	query.exclude = [get_rid()]
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	return hit.is_empty()


## 状态机 → 帧动画的统一映射（纯表现，不影响逻辑判定）：
## 尸体→die（无该动画则回退 idle）；攻击/前摇站定→attack（无则 idle）；
## 其余按速度切 walk/idle。子类扩展状态（冲锋/蓄力/硬直）多数可由速度自然覆盖。
## 行走时叠加轻微上下浮动（帧动画之外的第二层动感）
func _update_anim() -> void:
	if visual == null:
		return
	var want := "idle"
	match state:
		S_CORPSE:
			want = "die"
		S_ATTACK:
			want = "attack"
		_:
			want = "walk" if velocity.length() > 5.0 else "idle"
	if visual.sprite_frames == null or not visual.sprite_frames.has_animation(want):
		want = "idle"
	if visual.animation != want or not visual.is_playing():
		visual.play(want)
	visual.offset.y = sin(_anim_time * 13.0) * 0.9 if want == "walk" else 0.0


## 挤压回弹（预备-过冲打击感）：朝 amount 比例压 0.5×dur 秒再弹回基础体型。
## 红史莱姆的果冻脉动每帧覆写 scale，会自然吞掉本效果——无碍（它有自己的弹性语言）
func _squash(amount: Vector2, dur := 0.16) -> void:
	if visual == null:
		return
	var base := _visual_base()
	if _squash_tween != null and _squash_tween.is_valid():
		_squash_tween.kill()
	_squash_tween = visual.create_tween()
	_squash_tween.tween_property(visual, "scale", base * amount, dur * 0.4)
	_squash_tween.tween_property(visual, "scale", base, dur * 0.6)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)


## 血量镜像回写（受击/成长两处调用）：current_hp 运行期真源在节点上，
## 镜像进 MonsterInstance.hp_mirror 只为存档往返——读档恢复的怪带伤开局，
## 不再"白送满血回复"。走 EcologySim.report_hp 单点通道（与 report_killed 同构）
func _sync_hp_mirror() -> void:
	if WorldSim.sim != null:
		WorldSim.sim.report_hp(inst.id, current_hp)


func take_damage(amount: float, from_position := Vector2.INF, p_heavy := false,
		p_knock_mult := 1.0, p_effective := false) -> void:
	if state == S_CORPSE:
		return
	var armor: float = clampf(inst.species.defense_reduction, 0.0, 0.8)
	var dealt: float = maxf(1.0, amount * (1.0 - armor))
	current_hp -= dealt
	if _hp_bar != null:
		_hp_bar.notify_change()
	_sync_hp_mirror()
	EventBus.damage_number.emit(global_position, int(round(dealt)), false, p_effective)
	_pulse_red()
	# 被玩家攻击会中断迁徙反击：迁徙中挨打毫无反应（不还手不停步）像坏掉了
	if state == S_MIGRATING and from_position != Vector2.INF:
		state = S_CHASE
		_aggro_lock = 3.0
	if from_position != Vector2.INF:
		# 击退抗性为并联合成 resist = kb + poise×(1-kb)（kb 先吃掉的部分，poise 只对剩余
		# 生效、边际递减）：kb=0.85 且 poise=1.0 时恰为完全霸体——石魔像/窟魔王纹丝不动；
		# 重击（连击第三段）击退翻倍 + 玩家重锤被动乘子
		var resist: float = clampf(inst.species.knockback_resist
				+ inst.species.poise * (1.0 - inst.species.knockback_resist), 0.0, 1.0)
		var dir := (global_position - from_position).normalized()
		if dir == Vector2.ZERO:
			dir = Vector2.UP
		_knockback += dir * CombatMath.KNOCKBACK_BASE * (1.0 - resist) * (2.0 if p_heavy else 1.0) * p_knock_mult
	_on_taken_damage(dealt, from_position)
	# 仇恨连锁：同物种邻近个体会来支援（妖鬼/骷髅兵实现支援半径）
	notify_allies_hit(inst.species.species_name, global_position)
	if current_hp <= 0.0:
		_die_by_player()


## 生态迁移：模拟层归属与据点已瞬间切换（p_dest = 新营地位置，缺省回退
## 目标区域中心），节点只做"朝新据点方向离场"的演出（走到真据点可能要
## 数万像素/几十分钟——game_world 对远距迁移直接回收节点，走到这里的
## 都是近距迁移，锚点收敛为 900px 短途）
func on_migrate(to_region_id: String, p_dest := Vector2.INF) -> void:
	if state == S_CORPSE:
		return
	var target := p_dest if p_dest != Vector2.INF else WorldSim.sim.get_region_center(to_region_id)
	var dir := target - global_position
	anchor = global_position + (dir.normalized() * 900.0 if dir.length() > 1.0 else dir)
	state = S_MIGRATING


## 受击求援定向派发：只遍历该物种注册的节点，无支援行为的物种零成本跳过
static func notify_allies_hit(species_name: String, hit_position: Vector2) -> void:
	var list: Array = _species_registry.get(species_name)
	if list == null:
		return
	for node: MonsterBase in list:
		if node == null or node.state == S_CORPSE:
			continue
		var radius := node.ally_assist_radius()
		if radius > 0.0 and node.global_position.distance_to(hit_position) <= radius:
			node._on_ally_hit()


## 同物种同伴受击时的支援半径；0 = 该物种没有仇恨连锁（基类默认）
func ally_assist_radius() -> float:
	return 0.0


## 被同伴的受击求援唤起：脱离巡逻/迁徙进入追击，并锁仇恨数秒
func _on_ally_hit() -> void:
	if state == S_PATROL or state == S_MIGRATING:
		state = S_CHASE
	_aggro_lock = 3.0


## 模拟层判定的死亡（老化/击杀都走这里），幂等
func on_sim_death() -> void:
	if state == S_CORPSE:
		return
	state = S_CORPSE
	velocity = Vector2.ZERO
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	# 有死亡帧则播（玩家侧骑士才有 die 行）；怪物无死亡帧回退 idle 后由侧倒+灰化表达
	if visual != null and visual.sprite_frames != null and visual.sprite_frames.has_animation(&"die"):
		visual.stop()
		visual.play(&"die")
	if _shadow != null:
		_shadow.visible = false  # 侧倒尸体不再踩影子
	rotation = PI / 2.0
	modulate = Color(0.45, 0.45, 0.45, 0.7)
	if _hp_bar != null:
		_hp_bar.notify_change()
	# 死亡消散烟（美术 v5 fx 全量）：Boss 用暗烟加强份量感
	EventBus.fx_requested.emit(
		"darksmoke" if inst.species.is_boss else "smoke",
		global_position, 1.6 if inst.species.is_boss else 1.0)


# --- 子类可重写的机制钩子 ---

## 追击速度倍率（野猪狂暴时重写）
func _speed_mult() -> float:
	return 1.0


## 残血逃跑判定（<=0 的物种永不逃跑，如狂暴/守卫型）
func _wants_flee(player: Node2D) -> bool:
	# 被动生物：玩家近身即逃（无论血量）
	if inst.species.ambient and player != null and player.visible \
			and global_position.distance_to(player.global_position) < 260.0:
		return true
	var ratio: float = inst.species.flee_hp_ratio
	if ratio <= 0.0 or player == null or not player.visible:
		return false
	if current_hp > inst.max_hp() * ratio:
		return false
	return global_position.distance_to(player.global_position) < inst.species.detect_radius * 1.5


func _chase_tick(_delta: float, player: Node2D) -> void:
	if player == null or not player.visible:
		state = S_PATROL
		return
	var dist := global_position.distance_to(player.global_position)
	# 激怒期间脱离判定同样放大——否则捣巢后"全族激愤"的怪追两步就脱战回巡逻
	var drop_radius: float = inst.species.detect_radius * 1.3
	if _enrage_timer > 0.0:
		drop_radius *= ENRAGE_DETECT_MULT
	if dist > drop_radius and _aggro_lock <= 0.0:
		state = S_PATROL
		return
	if dist <= inst.species.attack_range:
		state = S_ATTACK
		return
	velocity = _nav_velocity_toward(player.global_position, inst.move_speed() * _speed_mult())


func _attack_tick(_delta: float, player: Node2D) -> void:
	if player == null or not player.visible:
		state = S_PATROL
		return
	var dist := global_position.distance_to(player.global_position)
	if dist > inst.species.attack_range * 1.1:
		state = S_CHASE
		return
	velocity = Vector2.ZERO
	# 前摇两段式：冷却转好先站定预警，MELEE_WINDUP 秒后结算伤害；
	# 每物理帧的 1.1× 距离门就是"出刀前复查"——玩家前摇期间拉开距离
	# 则本次出刀取消（不进冷却，走位规避有真实收益）
	if _melee_windup > 0.0:
		_melee_windup -= _delta
		if _melee_windup <= 0.0:
			_melee_windup = 0.0
			set_tint(_restore_tint())  # 收回出刀预警色
			_attack_cd = inst.species.attack_cooldown
			_perform_attack(player)
		return
	if _attack_cd <= 0.0:
		_melee_windup = MELEE_WINDUP
		set_tint(WINDUP_TINT)
		_squash(Vector2(1.08, 0.92), 0.2)  # 出刀前蹲伏预备


## 普攻执行（子类重写可加协同加成等）；source 名传给玩家做死亡信息
func _perform_attack(player: Node2D) -> void:
	_squash(Vector2(0.92, 1.08), 0.14)  # 出刀瞬间过冲
	if player.has_method("take_damage"):
		player.take_damage(CombatMath.physical_damage(inst.attack_power()), global_position, inst.display_name())
		# 命中紫色邪光（美术 v5 fx 全量；Boss ×1.5）
		EventBus.fx_requested.emit("orb", (player as Node2D).global_position,
			1.5 if inst.species.is_boss else 0.8)


## 受击后钩子（狂暴触发等）；from_position 为 Vector2.INF 表示无来源
func _on_taken_damage(_amount: float, _from_position: Vector2) -> void:
	pass


## 自定义状态（>=10）的处理入口
func _extra_state_tick(_delta: float, _player: Node2D) -> void:
	pass


## move_and_slide 之后的钩子：当帧碰撞数据（get_slide_collision）只有
## 在 move 之后才有效；需要它的判定（如野猪撞墙）重写此方法
func _post_move_hook(_delta: float) -> void:
	pass


# --- 公共状态实现 ---

func _patrol(delta: float, player: Node2D) -> void:
	var detect: float = inst.species.detect_radius * (WorldSim.night_vision_mult() if WorldSim != null else 1.0)
	if _enrage_timer > 0.0:
		detect *= ENRAGE_DETECT_MULT
	if player != null and player.visible \
			and global_position.distance_to(player.global_position) < detect \
			and not inst.species.ambient:  # 被动生物永不主动开战（只逃）
		state = S_CHASE
		_hunt_mode = false
		return
	# 巡猎接近：慢速逼向玩家，终点 = 侦测圈内边缘（到达即被侦测命中、
	# 由上方判定切 S_CHASE 接敌）——跑图遭遇必收敛为战斗；
	# 玩家不可见（死亡演出等）原地待命
	if _hunt_mode:
		if player == null or not player.visible:
			velocity = Vector2.ZERO
			return
		var dist := global_position.distance_to(player.global_position)
		if dist <= detect * 0.9:
			_hunt_mode = false
			_patrol_target_valid = false
			velocity = Vector2.ZERO
			return
		velocity = _nav_velocity_toward(player.global_position,
				inst.move_speed() * HUNT_SPEED_MULT * _speed_mult())
		return
	if _patrol_wait > 0.0:
		_patrol_wait -= delta
		velocity = Vector2.ZERO
		return
	if not _patrol_target_valid or global_position.distance_to(_patrol_target) < 6.0:
		# 路点预校验（世界 v5）：落障碍/贴障碍直接作废重选（4 次），全败则
		# 等待下轮——不再朝岩石内部走
		_patrol_target_valid = false
		for i in 4:
			var candidate := anchor + Vector2(randf_range(-PATROL_RADIUS, PATROL_RADIUS), randf_range(-PATROL_RADIUS, PATROL_RADIUS))
			if not ObstacleField.blocks(candidate, 8.0):
				_patrol_target = candidate
				_patrol_target_valid = true
				break
		_patrol_wait = randf_range(0.8, 2.5) if _patrol_target_valid else 1.0
		# 到达即站桩选新点，不朝新路点抽动一帧
		velocity = Vector2.ZERO
		return
	velocity = _nav_velocity_toward(_patrol_target, PATROL_SPEED)


func _flee_tick(player: Node2D) -> void:
	# 远离玩家直到脱离侦测圈，然后回到锚点巡逻
	if player == null or not player.visible \
			or global_position.distance_to(player.global_position) > inst.species.detect_radius * 1.6:
		state = S_PATROL
		return
	var away := (global_position - player.global_position).normalized()
	velocity = _nav_velocity_toward(global_position + away * 400.0, inst.move_speed() * _speed_mult())


func _migrate_tick() -> void:
	if global_position.distance_to(anchor) < MIGRATE_ARRIVE_DIST:
		state = S_PATROL
		_patrol_target_valid = false
		return
	velocity = _nav_velocity_toward(anchor, inst.move_speed() * _speed_mult())


func _die_by_player() -> void:
	# 击杀奖励：经验走 MonsterInstance 真源，金币走 EconomyMath 纯逻辑层公式
	# （策划：尸体拾取，M0 简化为自动）；精英/Boss 倍率在公式内
	var xp := inst.xp_reward()
	var gold := EconomyMath.kill_gold(inst)
	GameState.add_xp(xp)
	GameState.add_gold(gold)
	# 物种名随信号直传：赏金/图鉴/成就不再解析 display_name 字符串
	EventBus.monster_killed_by_player.emit(xp, gold, inst.display_name(), inst.species.species_name)
	# v7 材料掉落：按物种确定性入包（自动拾取，与金币同口径——M0 简化延续）；
	# 精英 ×2 / Boss ×3 + Boss 附加一件消耗品（hash 确定性，无 RNG）。
	# add_item 内部发 item_gained，HUD 战斗播报位订阅呈现
	var material := EconomyMath.material_for(inst.species.species_name)
	if material != "":
		GameState.add_item(material, EconomyMath.drop_count(inst))
	if inst.species.is_boss:
		GameState.add_item(EconomyMath.boss_bonus_item(GameState.world_seed, inst.id), 1)
	# 装备掉落：Boss 必掉史诗，精英 40% 稀有，普通 8% 精良；评分更高自动替换，否则折金
	var drop_rarity := -1
	if inst.species.is_boss:
		drop_rarity = 3
	elif inst.is_elite and randf() < 0.4:
		drop_rarity = 2
	elif randf() < 0.08:
		drop_rarity = 1
	if drop_rarity >= 0:
		# 槽位随机（武器/头盔/衣服/鞋子），各槽独立比较评分
		var slots: Array = GameState.EQUIP_SLOTS
		var slot: String = slots[randi() % slots.size()]
		var item := GameState.roll_equipment(drop_rarity, slot)
		var had_prev: bool = not GameState.stats.equips.get(slot, {}).is_empty()
		if GameState.try_equip(item):
			# 换装成功：旧装备按稀有度折金（金币计数器即时可见），首件装备则无折算
			if had_prev:
				EventBus.hint_requested.emit("✨ 换装 %s（%s）→ 旧装备已折算金币" % [
					GameState.equip_description(item), GameState.SLOT_NAMES[slot]])
			else:
				EventBus.hint_requested.emit("✨ 装备 %s（%s）" % [
					GameState.equip_description(item), GameState.SLOT_NAMES[slot]])
		else:
			EventBus.hint_requested.emit("获得 %s（不如当前，折算金币）" % GameState.equip_description(item))
	# 打击感：击杀轻震，精英击杀重震 + 短顿帧（大怪倒下的"重量"）；Boss 战绩播报
	if inst.species.is_boss:
		EventBus.camera_shake_requested.emit(9.0)
		EventBus.hit_stop_requested.emit(0.12)
		EventBus.world_event.emit("🏆 顶点掠食者 %s 被讨伐！生态链将为之震荡…" % inst.species.species_name)
	elif inst.is_elite:
		EventBus.camera_shake_requested.emit(7.0)
		EventBus.hit_stop_requested.emit(0.09)
	else:
		EventBus.camera_shake_requested.emit(2.5)
	_spawn_death_burst()
	# 场景卸载（WorldSim.stop 置空）后残余帧的攻击回调可能仍走到这里——判空防崩；
	# 本地置尸体态：否则同帧第二来源命中会再次走完本函数（双倍经验/金币/掉落）
	if WorldSim.sim != null:
		WorldSim.sim.report_killed(inst.id, global_position)  # 同步触发 on_sim_death()（红史莱姆在此裂出子代）
	else:
		on_sim_death()


## 击杀爆裂：碎片小方块四散旋转淡出（颜色跟怪物 tint，精英金色；池化复用，
## 见 VfxPool 约定——多怪连续倒下时每杀 6~10 个 Polygon2D 的分配可观）
func _spawn_death_burst() -> void:
	var color := Color(1.0, 0.78, 0.30) if inst.is_elite else Color(0.85, 0.3, 0.3)
	var count := 10 if inst.is_elite else 6
	var rng := RandomNumberGenerator.new()
	rng.seed = inst.id
	var parent := get_parent()
	for i in count:
		var shard := VfxPool.take("shard") as Polygon2D
		if shard == null:
			shard = Polygon2D.new()
			shard.z_index = 20
			parent.add_child(shard)
		elif shard.get_parent() != parent:
			shard.get_parent().remove_child(shard)
			parent.add_child(shard)
		var sc := clampf(inst.size_scale, 0.6, 1.4)
		shard.polygon = PackedVector2Array([
			Vector2(-3, -3) * sc, Vector2(3, -3) * sc,
			Vector2(3, 3) * sc, Vector2(-3, 3) * sc,
		])
		shard.color = color.darkened(rng.randf_range(0.0, 0.25))
		shard.modulate.a = 1.0
		shard.rotation = 0.0
		shard.global_position = global_position
		var dir := Vector2.RIGHT.rotated(rng.randf() * TAU)
		var dist := rng.randf_range(24.0, 60.0) * clampf(inst.size_scale, 0.7, 1.4)
		var tween := shard.create_tween()
		shard.set_meta("vfx_tween", tween)
		tween.set_parallel(true)
		tween.tween_property(shard, "global_position",
			global_position + dir * dist, 0.45).set_ease(Tween.EASE_OUT)
		tween.tween_property(shard, "rotation", rng.randf_range(-6.0, 6.0), 0.45)
		tween.tween_property(shard, "modulate:a", 0.0, 0.45).set_delay(0.1)
		tween.chain().tween_callback(func() -> void: VfxPool.release(shard, "shard"))
