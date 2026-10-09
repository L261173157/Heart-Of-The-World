## 突袭蛇：蓄力冲锋——先停步低头（前摇预警），再沿锁定方向直线高速冲撞；
## 撞墙会陷入硬直（反击窗口），命中则重创并击退玩家（命中后同样停顿）。
## 残血不逃反狂暴：移速与冲锋更快。走位引它撞墙是最优解。
## 冲锋参数（触发距离/前摇/速度/时限/伤害倍率/硬直）读 SpeciesData——
## 雪原窃贼/野兔/古木魔像共用本原型，Boss 型可按物种单独调参。
## 注：撞地形触发硬直，撞同伴只中止冲锋不硬直（2026-09-04 细化，原"撞同伴
## 也硬直"按涌现玩法保留过，会把引猪撞怪堆变成无脑套路）
class_name Boar
extends MonsterBase

const S_TELL := 10
const S_CHARGE := 11
const S_TIRED := 12

const ENRAGE_HP_RATIO := 0.3
const ENRAGE_SPEED_MULT := 1.4

var _enraged := false
var _state_timer := 0.0
var _charge_dir := Vector2.RIGHT
var _charge_start := Vector2.ZERO


func _speed_mult() -> float:
	return ENRAGE_SPEED_MULT if _enraged else 1.0


func _on_taken_damage(_amount: float, _from_position: Vector2) -> void:
	if not _enraged and current_hp > 0.0 and current_hp <= inst.max_hp() * ENRAGE_HP_RATIO:
		_enraged = true
		set_tint(Color(1.0, 0.55, 0.45))


## 贴身攻击状态：冷却一转好就回追击重新抉择——冲锋是突袭蛇的核心机制
## （撞墙硬直 = 反击窗口），若困在普通近战里，"贴脸站撸把它变木桩"就成了最优解，
## 机制博弈被完全绕过；回 CHASE 后 _chase_tick 会立即再次触发冲锋前摇
func _attack_tick(_delta: float, player: Node2D) -> void:
	if player == null or not player.visible:
		state = S_PATROL
		return
	if _attack_cd <= 0.0:
		state = S_CHASE
		return
	var dist := global_position.distance_to(player.global_position)
	if dist > inst.species.attack_range * 1.1:
		state = S_CHASE
		return
	# 冷却恢复期缓慢逼近保持压迫（与石魔像守卫同法）：此前冷却 2s 纯站桩，
	# 贴脸白给窗口过宽，"躲完冲锋贴身输出"没有代价，冲撞博弈被弱化
	if dist > inst.species.attack_range:
		velocity = (player.global_position - global_position).normalized() * inst.move_speed() * 0.4
	else:
		velocity = Vector2.ZERO


func _chase_tick(delta: float, player: Node2D) -> void:
	if player != null and player.visible and _attack_cd <= 0.0 \
			and global_position.distance_to(player.global_position) < inst.species.charge_trigger_dist:
		if not _try_attack_slot(player):
			velocity = _pressure_velocity(player)
			return
		state = S_TELL
		_state_timer = inst.species.charge_tell_time
		_charge_dir = (player.global_position - global_position).normalized()
		_begin_attack_warning(player, inst.attack_power() * inst.species.charge_damage_mult)
		_charge_dir = _attack_aim_dir
		_show_attack_sector(minf(360.0, inst.move_speed() * _speed_mult() \
			* inst.species.charge_speed_mult * inst.species.charge_max_time))
		velocity = Vector2.ZERO
		set_tint(Color(1.0, 0.85, 0.6))  # 前摇预警色
		_squash(Vector2(1.12, 0.88), 0.45)  # 低头蹲伏预备
		# 前摇=挥击预备帧：攻击条带只在冷却恢复窗播放、真实出招相位反而
		# 站桩的错位自此修正（压制窗=前摇全长，蓄满帧起冲）。
		# Troll 系（巨魔王）有专属 Windup 前摇条带，优先取用
		_play_action_anim("windup", inst.species.charge_tell_time) \
				or _play_action_anim("attack", inst.species.charge_tell_time)
		return
	super(delta, player)


func _extra_state_tick(delta: float, player: Node2D) -> void:
	if (state == S_TELL or state == S_CHARGE) and (player == null or not player.visible):
		_clear_attack_context()
		velocity = Vector2.ZERO
		state = S_PATROL
		_apply_mood_color()
		return
	match state:
		S_TELL:
			velocity = Vector2.ZERO
			_state_timer -= delta
			if _state_timer <= 0.0:
				_clear_attack_warning()
				state = S_CHARGE
				_attack_context_state = S_CHARGE
				_charge_start = global_position
				_state_timer = inst.species.charge_max_time
				_squash(Vector2(0.88, 1.12), 0.15)  # 起冲拉伸
				_apply_mood_color()
		S_CHARGE:
			# 记录本帧扫过的起点；命中与撞墙统一在移动后判定，不能用上一帧
			# 距离先判伤害、再让放大的精英/Boss 身体撞到玩家并误当墙取消。
			_charge_start = global_position
			velocity = _charge_dir * inst.move_speed() * _speed_mult() * inst.species.charge_speed_mult
			_state_timer -= delta
		S_TIRED:
			velocity = Vector2.ZERO
			_state_timer -= delta
			if _state_timer <= 0.0:
				state = S_CHASE
				_apply_mood_color()


## 冲锋前摇已锁定直线，不走 RVO 转向/限速：NavigationAgent 默认 max_speed
## 为 100，会把物种实际冲锋速度截断到走路速度并提前超时。仍通过基类
## 同一物理移动/接触钩子；撞同伴由真实碰撞中止，追击/巡逻继续正常避让。
func _on_nav_velocity(safe_velocity: Vector2) -> void:
	super(velocity if state == S_CHARGE else Vector2.ZERO \
		if state == S_TELL or state == S_TIRED else safe_velocity)


## 冲锋终止判定（move_and_slide 之后，当帧碰撞数据）：
## 撞上地形（墙）→ 硬直 = 暴露给玩家的反击窗口；只撞到同伴 → 冲锋中止但无硬直
## （撞同伴白送硬直会把"引突袭蛇进怪堆连环撞停"变成无脑套路——待定池 2026-09-04 细化）；
## 自然超时 → 正常回追（不误判为撞墙白送反击窗口）
func _post_move_hook(_delta: float) -> void:
	if state != S_CHARGE:
		return
	var player := _get_player()
	var hit_player := false
	var hit_wall := false
	var hit_ally := false
	for i in get_slide_collision_count():
		var collider: Object = get_slide_collision(i).get_collider()
		if collider == null:
			continue
		if collider == player:
			# 使用真正缩放后的身体接触，不把玩家和 layer 1 的地形混为一谈。
			hit_player = true
		elif collider is MonsterBase:
			hit_ally = true
		else:
			hit_wall = true
	# 墙/同伴先截断冲锋：不把沿墙滑行的剩余位移当成可穿墙的攻击轨迹。
	if hit_wall:
		_end_charge(true)
	elif hit_ally:
		_end_charge(false)
	elif player != null and player.visible and (hit_player or _swept_charge_hits(player)):
		if player.has_method("take_damage"):
			var context := _damage_context(player,
				inst.attack_power() * inst.species.charge_damage_mult, true, -_charge_dir)
			player.take_damage(
				CombatMath.physical_damage(float(context["strength"])),
				global_position, inst.display_name(), context)
		_end_charge(true)
	elif _state_timer <= 0.0:
		_end_charge(false)


## 保留物种原有的近身命中范围，但沿实际已走过的线段检查（高速/低帧率
## 不能越过命中窗）。实体接触由上方原生 swept body collision 覆盖巨体。
## 范围不是穿墙许可：仅在候选命中时射线复核，排除玩家自身的 layer 1。
func _swept_charge_hits(player: Node2D) -> bool:
	var closest := Geometry2D.get_closest_point_to_segment(
		player.global_position, _charge_start, global_position)
	if closest.distance_squared_to(player.global_position) \
			> inst.species.charge_hit_dist * inst.species.charge_hit_dist:
		return false
	if closest.is_equal_approx(player.global_position):
		return true
	var query := PhysicsRayQueryParameters2D.create(closest, player.global_position, 1)
	query.exclude = [get_rid()]
	if player is CollisionObject2D:
		query.exclude = [get_rid(), (player as CollisionObject2D).get_rid()]
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func _end_charge(stunned: bool) -> void:
	_clear_attack_context()
	velocity = Vector2.ZERO
	_attack_cd = inst.species.attack_cooldown
	if stunned:
		state = S_TIRED  # 撞墙硬直：暴露给玩家的反击窗口
		_state_timer = inst.species.tired_time
		set_tint(_base_modulate)
		_squash(Vector2(1.3, 0.7), 0.32)  # 撞墙重击压扁
	else:
		state = S_CHASE
		_apply_mood_color()


## 奔跑中的冲撞不被轻易打停；中型蓄力可被重击打断，高韧性仍遵守基类免疫。
func _can_stagger(heavy: bool) -> bool:
	return state != S_CHARGE and super(heavy)


func _on_staggered() -> void:
	_state_timer = 0.0
	_attack_cd = maxf(_attack_cd, 0.4)


func _apply_mood_color() -> void:
	set_tint(Color(1.0, 0.55, 0.45) if _enraged else _base_modulate)


## 闪红恢复到当前情绪/预警色（受击不吞狂暴红与前摇预警）
func _restore_tint() -> Color:
	if state == S_TELL:
		return Color(1.0, 0.85, 0.6)
	if _enraged:
		return Color(1.0, 0.55, 0.45)
	return _base_modulate
