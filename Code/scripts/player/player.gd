## 玩家控制器：移动 + 无锁定普攻 + 冲刺位移（无敌帧）+ 受击击退 + 死亡重生。
## ACT 无锁定（策划：无锁定通过攻击达到降低敌方血量目的）——
## 攻击方向 = 最后移动方向，判定框朝该方向短暂开启，命中所有进入的怪物。
## 冲刺消耗 MP 并带 0.18s 无敌帧，是躲避冲锋/重击的核心手段。
## 输入双通道：键盘（Input Map 动作）+ 触屏（TouchInput），玩法代码不区分平台。
class_name Player
extends CharacterBody2D

const ATTACK_WINDOW := 0.18
const ATTACK_REACH := 26.0
## 三段连击：窗口内连续普攻，第三段高伤重击退；超时重置
const COMBO_WINDOW := 0.9
## 攻击朝向吸附：扇形半角与半径（解决"边退边打"的方向冲突）
const AIM_CONE_DEG := 60.0
const AIM_RANGE := 150.0
## 冲刺增伤窗口：冲刺取消攻击后摇后，下次普攻加成（高级技巧空间）
const DASH_BUFF_TIME := 1.0
const DASH_BUFF_MULT := 1.3
const RESPAWN_DELAY := 2.0
## 重生保护帧：出生点可能被怪围住，短暂无敌防止落地即死
const RESPAWN_PROTECT := 1.0
## 受击无敌帧：多只怪同帧命中只结算第一下——群体围攻是压力不是即死
const HURT_IFRAME := 0.35
## 冲刺期间只与墙壁碰撞（穿透怪物）：被围时的核心逃生手段
const MASK_NORMAL := 3
const MASK_DASH := 1
const KNOCKBACK_DECAY := 700.0
const DASH_SPEED := 620.0
const DASH_TIME := 0.18
const DASH_COST := 12.0
const DASH_COOLDOWN := 1.2
const AFTERIMAGE_INTERVAL := 0.06
## 重击：以自身为圆心的 AOE 挥砸（清哥布林/兵蚁人海的保命大招）
const HEAVY_COST := 22.0
const HEAVY_COOLDOWN := 4.0
const HEAVY_RADIUS := 80.0
const HEAVY_MULT := 2.4
## 法弹：智力系远程（与雪蝎对射 / 风筝走位的构筑选择）
const BOLT_COST := 8.0
const BOLT_COOLDOWN := 0.8
const BOLT_MULT := 1.6
## 治疗：MP→HP 的资源博弈（MP 同时供冲刺/重击/法弹/治疗，取舍即深度）
const HEAL_COST := 25.0
const HEAL_COOLDOWN := 8.0
const HEAL_MULT := 3.0
## 武装强化：普攻增益状态（近战持续流构筑——贴身连击回血，
## 与重击的瞬间爆发、法弹的远程风筝形成三种输出节奏的分野）
const EMPOWER_COST := 30.0
const EMPOWER_COOLDOWN := 15.0
const EMPOWER_DURATION := 6.0
const EMPOWER_MULT := 1.6
## 每次普攻命中回复最大生命的比例（连击节奏越快收益越高）
const EMPOWER_HEAL_FRAC := 0.03

@onready var attack_hitbox: Area2D = $AttackHitbox
@onready var attack_shape: CollisionShape2D = $AttackHitbox/CollisionShape2D
@onready var visual: Sprite2D = $Visual
@onready var slash: Polygon2D = $Slash

var stats: CharacterStats
var current_hp: float = 0.0
var current_mp: float = 0.0
var facing: Vector2 = Vector2.RIGHT

var _attack_cooldown := 0.0
var _attack_timer := 0.0
var _respawn_timer := 0.0
var _is_dead := false
var _spawn_position := Vector2.ZERO
var _hit_this_swing: Array = []
var _hud_accum := 0.0
var _knockback := Vector2.ZERO
var _slash_tween: Tween
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
## 冲刺中按下的攻击缓冲（冲刺→攻击增伤连招不丢输入；触屏本身经 TouchInput 排队已有缓冲）
var _attack_buffered := false
## 最近一次致死伤害来源名（死亡信息用）
var last_killed_by := ""


func _ready() -> void:
	add_to_group("player")
	stats = GameState.stats
	current_hp = stats.max_hp()
	current_mp = stats.max_mp()
	_spawn_position = global_position
	attack_shape.disabled = true
	attack_hitbox.body_entered.connect(_on_attack_body_entered)
	# 延迟到所有节点 ready 之后再推初值，保证 HUD 已连接信号
	_push_hud.call_deferred()


func _physics_process(delta: float) -> void:
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	_dash_cd = maxf(0.0, _dash_cd - delta)
	_heavy_cd = maxf(0.0, _heavy_cd - delta)
	_bolt_cd = maxf(0.0, _bolt_cd - delta)
	_heal_cd = maxf(0.0, _heal_cd - delta)
	_empower_cd = maxf(0.0, _empower_cd - delta)
	if _empower_timer > 0.0:
		_empower_timer = maxf(0.0, _empower_timer - delta)
		if _empower_timer <= 0.0:
			visual.modulate = Color.WHITE  # 强化结束，收回金色光泽
	_dash_buff_timer = maxf(0.0, _dash_buff_timer - delta)
	_combo_timer = maxf(0.0, _combo_timer - delta)
	_protect_timer = maxf(0.0, _protect_timer - delta)
	_hurt_iframes = maxf(0.0, _hurt_iframes - delta)
	if _combo_timer <= 0.0:
		_combo = 0
	if _attack_timer > 0.0:
		_attack_timer -= delta
		if _attack_timer <= 0.0:
			attack_shape.disabled = true

	if _is_dead:
		velocity = Vector2.ZERO
		return

	# 冲刺中：固定方向高速位移 + 无敌帧 + 残影，结束前不响应移动输入；
	# 期间按攻击进入缓冲（触屏队列本就保留），冲刺一结束立即兑现
	if _dash_timer > 0.0:
		_dash_timer -= delta
		if _dash_timer <= 0.0:
			collision_mask = MASK_NORMAL
		velocity = facing * DASH_SPEED
		_afterimage_accum -= delta
		if _afterimage_accum <= 0.0:
			_afterimage_accum = AFTERIMAGE_INTERVAL
			_spawn_afterimage()
		if Input.is_action_just_pressed("attack"):
			_attack_buffered = true
		move_and_slide()
		return

	if _attack_buffered:
		_attack_buffered = false
		_try_attack()

	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if TouchInput.joystick_active:
		dir = TouchInput.move_vector
	velocity = dir * stats.move_speed() + _knockback
	_knockback = _knockback.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * delta)
	if dir != Vector2.ZERO:
		facing = dir.normalized()
		# 骑士素材朝右：左右移动翻转即可，攻击方向由挥砍特效表达
		if absf(dir.x) > 0.1:
			visual.flip_h = dir.x < 0.0
		_spawn_dust(delta)
	move_and_slide()

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


## 冲刺：消耗 MP，朝当前朝向高速位移，期间无敌（躲冲锋/重击/弹幕）；
## 同时取消攻击后摇并给下一击增伤——走位输出循环的技巧上限
func _try_dash() -> void:
	if _dash_timer > 0.0 or _dash_cd > 0.0:
		return
	if current_mp < DASH_COST:
		return
	current_mp -= DASH_COST
	EventBus.player_mp_changed.emit(current_mp, stats.max_mp())
	_dash_timer = DASH_TIME
	_dash_cd = DASH_COOLDOWN * stats.cooldown_mult()
	_afterimage_accum = 0.0
	_attack_cooldown = 0.0
	_dash_buff_timer = DASH_BUFF_TIME
	collision_mask = MASK_DASH
	EventBus.player_dashed.emit()


## 脚步尘土：移动中每 0.22s 在脚下冒一个小灰点淡出
func _spawn_dust(delta: float) -> void:
	_dust_accum += delta
	if _dust_accum < 0.22:
		return
	_dust_accum = 0.0
	var dust := Polygon2D.new()
	dust.polygon = PackedVector2Array([
		Vector2(-3, -2), Vector2(3, -2), Vector2(3, 2), Vector2(-3, 2),
	])
	dust.color = Color(0.72, 0.68, 0.6, 0.5)
	dust.z_index = -2
	get_parent().add_child(dust)
	dust.global_position = global_position + Vector2(randf_range(-4.0, 4.0), 12.0)
	var tween := dust.create_tween()
	tween.set_parallel(true)
	tween.tween_property(dust, "scale", Vector2(1.8, 1.8), 0.4)
	tween.tween_property(dust, "modulate:a", 0.0, 0.4)
	tween.chain().tween_callback(dust.queue_free)


## 冲刺残影：复制当前精灵快照，快速淡出
func _spawn_afterimage() -> void:
	var ghost := Sprite2D.new()
	ghost.texture = visual.texture
	ghost.scale = visual.scale
	ghost.flip_h = visual.flip_h
	ghost.global_position = global_position
	ghost.modulate = Color(0.6, 0.8, 1.0, 0.45)
	get_parent().add_child(ghost)
	var tween := ghost.create_tween()
	tween.tween_property(ghost, "modulate:a", 0.0, 0.3)
	tween.tween_callback(ghost.queue_free)


## 重击：消耗 MP，圆形 AOE 高倍率伤害 + 冲击环特效 + 震屏顿帧
func _try_heavy_attack() -> void:
	if _heavy_cd > 0.0 or current_mp < HEAVY_COST:
		return
	_heavy_cd = HEAVY_COOLDOWN * stats.cooldown_mult()
	current_mp -= HEAVY_COST
	EventBus.player_mp_changed.emit(current_mp, stats.max_mp())
	SfxManager.play("heavy")
	EventBus.camera_shake_requested.emit(5.0)
	EventBus.hit_stop_requested.emit(0.06)
	_play_ring(HEAVY_RADIUS, Color(1.0, 0.85, 0.4, 0.9))
	var dmg := CombatMath.physical_damage(stats.physical_attack() * HEAVY_MULT)
	var targets: Array = get_tree().get_nodes_in_group("monsters")
	targets.append_array(get_tree().get_nodes_in_group("nests"))
	for body in targets:
		var monster := body as Node2D
		if monster == null or not body.has_method("take_damage"):
			continue
		var mb := body as MonsterBase
		if mb != null and mb.state == MonsterBase.S_CORPSE:
			continue  # 尸体不吃 AOE
		if global_position.distance_to(monster.global_position) <= HEAVY_RADIUS:
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
	if _bolt_cd > 0.0 or current_mp < BOLT_COST:
		return
	_bolt_cd = BOLT_COOLDOWN * stats.cooldown_mult()
	current_mp -= BOLT_COST
	EventBus.player_mp_changed.emit(current_mp, stats.max_mp())
	SfxManager.play("bolt")
	var bolt := PlayerBolt.new()
	get_parent().add_child(bolt)
	bolt.global_position = global_position + facing * 22.0
	bolt.launch(facing, CombatMath.magic_damage(stats.magic_attack() * BOLT_MULT), stats.equip_element())


## 治疗：消耗 MP 回复智力加成生命，绿色涟漪特效（深区续航的资源取舍）
func _try_heal() -> void:
	if _heal_cd > 0.0 or current_mp < HEAL_COST or _is_dead:
		return
	_heal_cd = HEAL_COOLDOWN * stats.cooldown_mult()
	current_mp -= HEAL_COST
	var healed := stats.heal_power() * HEAL_MULT
	current_hp = minf(stats.max_hp(), current_hp + healed)
	EventBus.player_mp_changed.emit(current_mp, stats.max_mp())
	EventBus.player_hp_changed.emit(current_hp, stats.max_hp())
	SfxManager.play("heal")
	_play_ring(44.0, Color(0.5, 1.0, 0.55, 0.9))


## 武装强化：消耗 MP 进入 6s 普攻增益（伤害 ×1.6 + 命中吸血）；
## 持续期间金色光泽标识，与冷却共同约束不可连开
func _try_empower() -> void:
	if _empower_cd > 0.0 or _empower_timer > 0.0 \
			or current_mp < EMPOWER_COST or _is_dead:
		return
	_empower_cd = EMPOWER_COOLDOWN * stats.cooldown_mult()
	_empower_timer = EMPOWER_DURATION
	current_mp -= EMPOWER_COST
	EventBus.player_mp_changed.emit(current_mp, stats.max_mp())
	SfxManager.play("levelup")
	visual.modulate = Color(1.0, 0.88, 0.55)
	_play_ring(40.0, Color(1.0, 0.82, 0.35, 0.9))


## 通用冲击环：以自身为圆心扩散淡出（重击金环 / 治疗绿涟漪共用）
func _play_ring(radius: float, color: Color) -> void:
	var ring := Line2D.new()
	ring.width = 7.0
	ring.default_color = color
	var points := PackedVector2Array()
	var steps := 40
	for i in steps:
		points.append(Vector2.RIGHT.rotated(TAU * i / steps) * radius)
	points.append(points[0])
	ring.points = points
	ring.z_index = 6
	get_parent().add_child(ring)
	ring.global_position = global_position
	var tween := ring.create_tween()
	tween.tween_property(ring, "scale", Vector2.ONE, 0.22) \
		.from(Vector2(0.15, 0.15)).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.parallel().tween_property(ring, "modulate:a", 0.0, 0.3)
	tween.chain().tween_callback(ring.queue_free)


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
		EventBus.player_skills_changed.emit(
			_dash_cd, _heavy_cd, _bolt_cd, _heal_cd, _empower_cd, current_mp, stats.max_mp())


func _try_attack() -> void:
	if _attack_cooldown > 0.0:
		return
	_attack_cooldown = stats.attack_interval()
	_attack_timer = ATTACK_WINDOW
	_hit_this_swing.clear()
	# 连击推进：窗口内连续攻击累积，第三段为重击（1.5×伤害 2×击退）
	_combo = (_combo + 1) % 3
	_combo_timer = COMBO_WINDOW
	# 朝向吸附：攻击瞬间朝扇形内最近敌人修正，解决"边退边打"的方向冲突
	var aim: Variant = _aim_assist()
	if aim != null:
		facing = aim
	attack_shape.disabled = false
	attack_hitbox.position = facing * ATTACK_REACH
	attack_hitbox.rotation = facing.angle()
	_play_slash(_combo)


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


## 挥砍特效：朝攻击方向闪一道弧光，快速淡出（第三段更宽更亮；强化期间金色）
func _play_slash(combo_step := 0) -> void:
	slash.position = facing * 22.0
	slash.rotation = facing.angle()
	slash.visible = true
	slash.modulate = Color(1.0, 0.82, 0.4) if _empower_timer > 0.0 else Color.WHITE
	slash.modulate.a = 1.0 if combo_step == 2 else 0.9
	if combo_step == 2:
		slash.scale = Vector2(1.4, 1.4)
	else:
		slash.scale = Vector2.ONE
	if _slash_tween != null:
		_slash_tween.kill()
	_slash_tween = slash.create_tween()
	_slash_tween.tween_property(slash, "modulate:a", 0.0, ATTACK_WINDOW)
	_slash_tween.tween_callback(func(): slash.visible = false)


func take_damage(amount: float, from_position := Vector2.INF, source_name := "") -> void:
	if _is_dead:
		return
	# 冲刺/重生保护/受击无敌帧：期间免疫一切伤害（群体同帧命中只结算第一下）
	if _dash_timer > 0.0 or _protect_timer > 0.0 or _hurt_iframes > 0.0:
		return
	current_hp = maxf(0.0, current_hp - amount)
	_hurt_iframes = HURT_IFRAME
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
	_is_dead = true
	_respawn_timer = RESPAWN_DELAY
	visible = false
	attack_shape.disabled = true
	# 倒下即失去强化状态（金色光泽一并收回）
	_empower_timer = 0.0
	visual.modulate = Color.WHITE
	# 死亡期间触屏按键的排队不应在复活后一次性兑现
	TouchInput.clear_queues()
	# 死亡代价：掉落两成金币（风险感 + 经济回收；赏金与商店让金币有真实价值）
	var lost := int(GameState.gold * 0.2)
	if lost > 0:
		GameState.add_gold(-lost)
		EventBus.hint_requested.emit("倒下了…丢失 %d 金币" % lost)
	EventBus.player_died.emit()


func _respawn() -> void:
	_is_dead = false
	global_position = _spawn_position
	current_hp = stats.max_hp()
	current_mp = stats.max_mp()
	visible = true
	# 清战斗残留：致死击退/连击段/攻击窗口/冲刺穿怪状态不带入重生
	_knockback = Vector2.ZERO
	_combo = 0
	_combo_timer = 0.0
	_dash_timer = 0.0
	collision_mask = MASK_NORMAL
	_attack_buffered = false
	_hurt_iframes = 0.0
	_attack_timer = 0.0
	_hit_this_swing.clear()
	_protect_timer = RESPAWN_PROTECT
	_push_hud()
	EventBus.player_respawned.emit()


func _on_attack_body_entered(body: Node) -> void:
	if not (body.is_in_group("monsters") or body.is_in_group("nests")) \
			or not body.has_method("take_damage"):
		return
	if body in _hit_this_swing:
		return
	_hit_this_swing.append(body)
	# 连击第三段重击（×1.5）+ 冲刺后增伤（×1.3）+ 武装强化（×1.6）
	# + 装备元素克制（火克冰/冰克火 ×1.5）
	var mult := 1.0
	if _combo == 2:
		mult *= 1.5
	if _dash_buff_timer > 0.0:
		mult *= DASH_BUFF_MULT
	if _empower_timer > 0.0:
		mult *= EMPOWER_MULT
	var monster := body as MonsterBase
	var effective := false
	if monster != null and monster.inst != null:
		var em: float = CombatMath.elemental_multiplier(
				stats.equip_element(), monster.inst.species.element)
		mult *= em
		effective = em > 1.0
	body.take_damage(CombatMath.physical_damage(stats.physical_attack() * mult),
			global_position, _combo == 2, stats.knockback_mult(), effective)
	# 噬血被动：命中吸血；武装强化期间额外回复最大生命 3%（连击越快续航越强）
	var lifesteal := stats.lifesteal_per_hit()
	if _empower_timer > 0.0:
		lifesteal += stats.max_hp() * EMPOWER_HEAL_FRAC
	if lifesteal > 0.0:
		current_hp = minf(stats.max_hp(), current_hp + lifesteal)
		EventBus.player_hp_changed.emit(current_hp, stats.max_hp())
	# 命中顿帧：极短的时间尺度压低，挥砍"打实"的手感
	EventBus.hit_stop_requested.emit(0.035)


func _push_hud() -> void:
	EventBus.player_hp_changed.emit(current_hp, stats.max_hp())
	EventBus.player_mp_changed.emit(current_mp, stats.max_mp())
	EventBus.player_progress_changed.emit(
		GameState.stats.level, GameState.stats.xp,
		GameState.stats.xp_to_next(), GameState.stats.pending_points
	)
	EventBus.gold_changed.emit(GameState.gold)
	EventBus.player_skills_changed.emit(
		_dash_cd, _heavy_cd, _bolt_cd, _heal_cd, _empower_cd, current_mp, stats.max_mp())
