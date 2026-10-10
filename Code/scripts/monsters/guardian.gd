## 重击守卫：普通物种保留原有近身砸击；熔岩龟王单独启用三招与半血阶段。
## Boss 地面范围、扇形朝向和落点在前摇开始时锁定，实际命中与同一预警几何一致。
## 不改生态、成长或伤害公式；阶段由现有生命推导，无新增存档字段。
class_name Guardian
extends MonsterBase

const S_WINDUP := 10
const S_RECOVER := 11
const S_PHASE_CHANGE := 12
const MOVE_STOMP := 0
const MOVE_SWEEP := 1
const MOVE_ERUPTION := 2
const IMPACT_DISPLAY_TIME := 0.14

var _state_timer := 0.0
var _ring: RangeRing
var _ring_step := -1
var _boss_loop := false
var _boss_phase := 1
var _move_cursor := 0
var _current_move := MOVE_STOMP
var _move_origin := Vector2.ZERO
var _move_direction := Vector2.RIGHT
var _move_radius := 0.0
var _windup_duration := 0.8
var _recovery_duration := 0.0


## 单个可复用地面预警，最多 48 段；按 12 档推进，不逐帧新建节点或全量重画。
class RangeRing extends Node2D:
	var radius := 0.0
	var progress := 0.0
	var shape := 0  # 0=圆形，1=固定方向扇形，2=落点，3=无伤阶段提示
	var direction := Vector2.RIGHT
	var half_angle := PI * 0.34
	var impact := false

	func _draw() -> void:
		if radius <= 0.0:
			return
		if shape == 3:
			# 双金环表示阶段变化，不沿用伤害范围的红色实线/填充。
			var r := radius * (0.8 + 0.2 * progress)
			draw_arc(Vector2.ZERO, r, -PI * 0.8, -PI * 0.2, 18, Color(1, 0.88, 0.35, 0.9), 3.0)
			draw_arc(Vector2.ZERO, r, PI * 0.2, PI * 0.8, 18, Color(1, 0.88, 0.35, 0.9), 3.0)
			return
		var tint := Color(1.0, 0.45, 0.16, 0.65 + 0.35 * progress)
		var fill := Color(1.0, 0.3, 0.12, 0.06 + 0.12 * progress)
		var width := 2.0 + 2.0 * progress
		if impact:
			tint = Color(1.0, 0.92, 0.63, 0.95)
			fill = Color(1.0, 0.56, 0.2, 0.25)
			width = 4.0
		if shape == 1:
			var angle := direction.angle()
			var points := PackedVector2Array([Vector2.ZERO])
			for i in 25:
				points.append(Vector2.from_angle(angle - half_angle + 2.0 * half_angle * i / 24.0) * radius)
			draw_colored_polygon(points, fill)
			draw_arc(Vector2.ZERO, radius, angle - half_angle, angle + half_angle, 25, tint, width)
			draw_line(Vector2.ZERO, points[1], tint, width)
			draw_line(Vector2.ZERO, points[-1], tint, width)
		else:
			draw_circle(Vector2.ZERO, radius, fill)
			draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, tint, width)
			if shape == 2:
				# 十字落点与中心圈区别于近身震地，边界始终等于真实命中半径。
				draw_arc(Vector2.ZERO, radius * 0.35, 0.0, TAU, 20, tint, 2.0)
				for axis: Vector2 in [Vector2.RIGHT, Vector2.DOWN]:
					draw_line(-axis * 10.0, axis * 10.0, tint, 2.0)


func setup(p_inst: MonsterInstance) -> void:
	super(p_inst)
	_boss_loop = inst.species.is_boss and inst.species.guardian_boss_moves
	# 流式卸载/读档的低血 Boss 直接延续第二阶段，不重复获得变身空窗或回复生命。
	_boss_phase = 2 if _boss_loop and current_hp <= inst.max_hp() * inst.species.guardian_phase_hp_ratio else 1
	_ring = RangeRing.new()
	_ring.radius = inst.species.attack_range * inst.species.guard_smash_range_mult
	_ring.z_index = -1
	add_child(_ring)
	_ring.visible = false
	if _boss_loop:
		_ring.top_level = true
		set_tint(_restore_tint())


func on_sim_death() -> void:
	super()
	if _ring != null:
		_ring.visible = false


func on_migrate(to_region_id: String, p_dest := Vector2.INF) -> void:
	if state == S_CORPSE:
		return
	# 正常生态不迁移守卫；外部生命周期取消仍须撤下子类私有范围和动作。
	if _ring != null:
		_ring.hide()
	_state_timer = 0.0
	_action_anim_timer = 0.0
	super(to_region_id, p_dest)


func _chase_tick(delta: float, player: Node2D) -> void:
	if _boss_loop and _valid_target(player) and _attack_cd <= 0.0 \
			and global_position.distance_to(player.global_position) <= _boss_trigger_range() \
			and _has_los(player.global_position):
		state = S_ATTACK
		velocity = Vector2.ZERO
		return
	super(delta, player)


func _attack_tick(_delta: float, player: Node2D) -> void:
	if _boss_loop:
		_boss_attack_tick(player)
		return
	if not _valid_target(player):
		_cancel_guardian_move()
		return
	var dist := global_position.distance_to(player.global_position)
	if dist > inst.species.attack_range * 1.3:
		state = S_CHASE
		return
	if _attack_cd > 0.0:
		velocity = (player.global_position - global_position).normalized() * inst.move_speed() * 0.4 \
			if dist > inst.species.attack_range else Vector2.ZERO
		return
	if not _try_attack_slot(player):
		velocity = Vector2.ZERO
		return
	velocity = Vector2.ZERO
	state = S_WINDUP
	_state_timer = inst.species.guard_windup_time
	_begin_attack_warning(player, inst.attack_power(), false)
	_play_action_anim("attack", inst.species.guard_windup_time)
	set_tint(Color(1.0, 0.7, 0.3))
	_squash(Vector2(1.14, 0.86), 0.7)
	if _ring != null:
		_ring.visible = true
		_ring.progress = 0.0
		_ring_step = -1
		_ring.queue_redraw()


func _valid_target(player: Node2D) -> bool:
	return is_instance_valid(player) and player.visible \
		and not (player is Player and (player._is_dead or player.current_hp <= 0.0))


func _next_boss_move() -> int:
	if _boss_phase == 1:
		return MOVE_STOMP if _move_cursor % 2 == 0 else MOVE_SWEEP
	return [MOVE_ERUPTION, MOVE_SWEEP, MOVE_STOMP][_move_cursor % 3]


func _boss_trigger_range() -> float:
	match _next_boss_move():
		MOVE_SWEEP:
			return inst.species.attack_range * inst.species.guardian_sweep_range_mult * inst.species.guardian_sweep_trigger_mult
		MOVE_ERUPTION:
			return inst.species.detect_radius
	return inst.species.attack_range * 1.3


func _boss_attack_tick(player: Node2D) -> void:
	if not _valid_target(player):
		_cancel_guardian_move()
		return
	var distance := global_position.distance_to(player.global_position)
	if distance > _boss_trigger_range() or not _has_los(player.global_position):
		state = S_CHASE
		return
	if _attack_cd > 0.0:
		velocity = _nav_velocity_toward(player.global_position, inst.move_speed() * 0.4) \
			if distance > inst.species.attack_range else Vector2.ZERO
		return
	if not _try_attack_slot(player):
		velocity = Vector2.ZERO
		return
	_current_move = _next_boss_move()
	_move_cursor += 1
	_move_origin = global_position
	_move_direction = (player.global_position - global_position).normalized()
	if _move_direction.is_zero_approx():
		_move_direction = Vector2.RIGHT
	_move_radius = inst.species.attack_range * inst.species.guard_smash_range_mult
	if _current_move == MOVE_SWEEP:
		_move_radius = inst.species.attack_range * inst.species.guardian_sweep_range_mult
	elif _current_move == MOVE_ERUPTION:
		_move_origin = player.global_position
		_move_radius = inst.species.attack_range * inst.species.guardian_eruption_radius_mult
	_windup_duration = inst.species.guard_windup_time * inst.species.guardian_move_windup_mults[_current_move]
	_state_timer = _windup_duration
	state = S_WINDUP
	velocity = Vector2.ZERO
	# 扇扫可挡；震地与脚下喷发不可挡。同源上下文锁定强度/盾形提示。
	_begin_attack_warning(player, inst.attack_power(), _current_move == MOVE_SWEEP)
	_play_action_anim("windup", _windup_duration) or _play_action_anim("attack", _windup_duration)
	set_tint(_restore_tint())
	_squash(Vector2(1.12, 0.88), _windup_duration)
	_ring.global_position = _move_origin
	_ring.radius = _move_radius
	_ring.shape = _current_move
	_ring.direction = _move_direction
	_ring.half_angle = inst.species.guardian_sweep_half_angle
	_ring.impact = false
	_ring.progress = 0.0
	_ring_step = -1
	_ring.show()
	_ring.queue_redraw()


func _on_taken_damage(_amount: float, _from_position: Vector2) -> void:
	if _boss_loop and _boss_phase == 1 and current_hp > 0.0 \
			and current_hp <= inst.max_hp() * inst.species.guardian_phase_hp_ratio:
		# 半血当帧撤销尚未落下的攻击，绝不把原前摇隐藏后继续结算伤害。
		_clear_attack_context()
		_boss_phase = 2
		_move_cursor = 0
		state = S_PHASE_CHANGE
		_state_timer = inst.species.guardian_phase_time
		velocity = Vector2.ZERO
		_ring.global_position = global_position
		_ring.radius = inst.species.attack_range * 0.9
		_ring.shape = 3
		_ring.progress = 0.0
		_ring.impact = false
		_ring_step = -1
		_ring.show()
		_ring.queue_redraw()
		set_tint(_restore_tint())
		_play_action_anim("windup", inst.species.guardian_phase_time) or _play_action_anim("attack", inst.species.guardian_phase_time)
		_squash(Vector2(1.15, 0.85), inst.species.guardian_phase_time)
		EventBus.hint_requested.emit("%s：第二阶段" % inst.species.species_name)


func _restore_tint() -> Color:
	if state == S_WINDUP:
		return Color(1.0, 0.7, 0.3)
	if _boss_loop and state == S_PHASE_CHANGE:
		return Color(1.0, 0.9, 0.45)
	if _boss_loop and _boss_phase == 2:
		return Color(1.0, 0.48, 0.28)
	return _base_modulate


func _extra_state_tick(delta: float, player: Node2D) -> void:
	if _boss_loop:
		_boss_state_tick(delta, player)
		return
	if state != S_WINDUP:
		return
	if not _valid_target(player):
		_cancel_guardian_move()
		return
	velocity = Vector2.ZERO
	_state_timer -= delta
	_update_ring_progress(inst.species.guard_windup_time)
	if _state_timer > 0.0:
		return
	_clear_attack_warning()
	set_tint(_base_modulate)
	_squash(Vector2(0.88, 1.12), 0.2)
	if _ring != null:
		_ring.visible = false
	_attack_cd = inst.species.attack_cooldown
	EventBus.fx_requested.emit("boom", global_position, 1.8 if inst.species.is_boss else 1.2)
	if player != null and player.visible \
			and global_position.distance_to(player.global_position) <= inst.species.attack_range * inst.species.guard_smash_range_mult:
		if player.has_method("take_damage"):
			var context := _damage_context(player, inst.attack_power(), false)
			player.take_damage(CombatMath.physical_damage(float(context["strength"])),
				global_position, inst.display_name(), context)
	_clear_attack_context()
	state = S_CHASE


func _boss_state_tick(delta: float, player: Node2D) -> void:
	if state != S_WINDUP and state != S_RECOVER and state != S_PHASE_CHANGE:
		return
	if not _valid_target(player):
		_cancel_guardian_move()
		return
	velocity = Vector2.ZERO
	_state_timer -= delta
	match state:
		S_WINDUP:
			_update_ring_progress(_windup_duration)
			if _state_timer <= 0.0:
				_resolve_boss_move(player)
		S_RECOVER:
			if _state_timer <= _recovery_duration - IMPACT_DISPLAY_TIME:
				_ring.hide()
			if _state_timer <= 0.0:
				state = S_CHASE
				set_tint(_restore_tint())
		S_PHASE_CHANGE:
			_update_ring_progress(inst.species.guardian_phase_time)
			if _state_timer <= 0.0:
				_ring.hide()
				state = S_CHASE
				_attack_cd = maxf(_attack_cd, inst.species.guardian_phase_recovery)
				set_tint(_restore_tint())


func _update_ring_progress(duration: float) -> void:
	if _ring == null:
		return
	_ring.progress = clampf(1.0 - _state_timer / maxf(duration, 0.01), 0.0, 1.0)
	var step := int(_ring.progress * 12.0)
	if step != _ring_step:
		_ring_step = step
		_ring.queue_redraw()


func _resolve_boss_move(player: Node2D) -> void:
	_clear_attack_warning()
	_ring.progress = 1.0
	_ring.impact = true
	_ring.queue_redraw()
	var offset := player.global_position - _move_origin
	var hit := offset.length_squared() <= _move_radius * _move_radius
	if _current_move == MOVE_SWEEP:
		hit = hit and (offset.is_zero_approx() or _move_direction.dot(offset.normalized()) >= cos(inst.species.guardian_sweep_half_angle))
	# 近身招式不穿实体掩体；落点喷发在已预警的地面原位结算，不追随玩家。
	if _current_move != MOVE_ERUPTION:
		hit = hit and _has_melee_los(player)
	if hit and player.has_method("take_damage"):
		var context := _damage_context(player, inst.attack_power(), _current_move == MOVE_SWEEP)
		player.take_damage(CombatMath.physical_damage(float(context["strength"])),
			_move_origin, inst.display_name(), context)
	EventBus.fx_requested.emit("boom", _move_origin, 1.5 if _current_move != MOVE_SWEEP else 0.9)
	# 身体落下仍用前摇锁定的朝向，不能先清上下文再向移动中的玩家重新转身。
	_play_action_anim("attack", minf(inst.species.guardian_move_recoveries[_current_move], 0.32))
	_clear_attack_context()
	state = S_RECOVER
	_recovery_duration = inst.species.guardian_move_recoveries[_current_move]
	_state_timer = _recovery_duration
	_attack_cd = inst.species.attack_cooldown
	set_tint(_restore_tint())
	_squash(Vector2(0.88, 1.12), 0.2)


func _cancel_guardian_move() -> void:
	_clear_attack_context()
	if _ring != null:
		_ring.hide()
	velocity = Vector2.ZERO
	_state_timer = 0.0
	_action_anim_timer = 0.0
	state = S_PATROL
	set_tint(_restore_tint())


func _on_staggered() -> void:
	# 高霸体 Boss 不走此分支；普通守卫若以后配置为可打断，也不能遗留范围圈。
	if _ring != null:
		_ring.hide()
	_state_timer = 0.0


func _on_nav_velocity(safe_velocity: Vector2) -> void:
	# 圈已锁定后 RVO 不可拖走 Boss，也不把明确收招空窗变成滑步攻击。
	if _boss_loop and (state == S_WINDUP or state == S_RECOVER or state == S_PHASE_CHANGE):
		super(Vector2.ZERO)
		return
	super(safe_velocity)
