## 野猪：蓄力冲锋——先停步低头（前摇预警），再沿锁定方向直线高速冲撞；
## 撞墙会陷入硬直（反击窗口），命中则重创并击退玩家（命中后同样停顿）。
## 残血不逃反狂暴：移速与冲锋更快。走位引它撞墙是最优解。
## 冲锋参数（触发距离/前摇/速度/时限/伤害倍率/硬直）读 SpeciesData——
## 企鹅/野兔/古木魔像共用本原型，Boss 型可按物种单独调参。
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


func _speed_mult() -> float:
	return ENRAGE_SPEED_MULT if _enraged else 1.0


func _on_taken_damage(_amount: float, _from_position: Vector2) -> void:
	if not _enraged and current_hp > 0.0 and current_hp <= inst.max_hp() * ENRAGE_HP_RATIO:
		_enraged = true
		set_tint(Color(1.0, 0.55, 0.45))


## 贴身攻击状态：冷却一转好就回追击重新抉择——冲锋是野猪的核心机制
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
		state = S_TELL
		_state_timer = inst.species.charge_tell_time
		_charge_dir = (player.global_position - global_position).normalized()
		velocity = Vector2.ZERO
		set_tint(Color(1.0, 0.85, 0.6))  # 前摇预警色
		_squash(Vector2(1.12, 0.88), 0.45)  # 低头蹲伏预备
		return
	super(delta, player)


func _extra_state_tick(delta: float, player: Node2D) -> void:
	match state:
		S_TELL:
			velocity = Vector2.ZERO
			_state_timer -= delta
			if _state_timer <= 0.0:
				state = S_CHARGE
				_state_timer = inst.species.charge_max_time
				_squash(Vector2(0.88, 1.12), 0.15)  # 起冲拉伸
				_apply_mood_color()
		S_CHARGE:
			# 只负责推进与命中判定；撞墙/超时的终止判定在 _post_move_hook
			# （状态 match 在 move_and_slide 之前执行，这里读碰撞数据是上一帧的残留）
			velocity = _charge_dir * inst.move_speed() * _speed_mult() * inst.species.charge_speed_mult
			_state_timer -= delta
			if player != null and player.visible \
					and global_position.distance_to(player.global_position) < inst.species.charge_hit_dist:
				if player.has_method("take_damage"):
					player.take_damage(
						CombatMath.physical_damage(inst.attack_power() * inst.species.charge_damage_mult),
						global_position, inst.display_name())
				_end_charge(true)  # 命中即停顿：给玩家反击窗口
		S_TIRED:
			velocity = Vector2.ZERO
			_state_timer -= delta
			if _state_timer <= 0.0:
				state = S_CHASE
				_apply_mood_color()


## 冲锋终止判定（move_and_slide 之后，当帧碰撞数据）：
## 撞上地形（墙）→ 硬直 = 暴露给玩家的反击窗口；只撞到同伴 → 冲锋中止但无硬直
## （撞同伴白送硬直会把"引野猪进怪堆连环撞停"变成无脑套路——待定池 2026-09-04 细化）；
## 自然超时 → 正常回追（不误判为撞墙白送反击窗口）
func _post_move_hook(_delta: float) -> void:
	if state != S_CHARGE:
		return
	var hit_wall := false
	var hit_ally := false
	for i in get_slide_collision_count():
		var collider: Object = get_slide_collision(i).get_collider()
		# 碰撞对象同帧被释放（如冲锋线上被击杀的怪刚清理）时 collider 为 null：
		# 既非撞墙也非撞同伴，跳过——计撞墙会白送一段硬直
		if collider == null:
			continue
		if collider is MonsterBase:
			hit_ally = true
		else:
			hit_wall = true
	if hit_wall:
		_end_charge(true)
	elif hit_ally or _state_timer <= 0.0:
		_end_charge(false)


func _end_charge(stunned: bool) -> void:
	_attack_cd = inst.species.attack_cooldown
	if stunned:
		state = S_TIRED  # 撞墙硬直：暴露给玩家的反击窗口
		_state_timer = inst.species.tired_time
		set_tint(_base_modulate)
		_squash(Vector2(1.3, 0.7), 0.32)  # 撞墙重击压扁
	else:
		state = S_CHASE
		_apply_mood_color()


func _apply_mood_color() -> void:
	set_tint(Color(1.0, 0.55, 0.45) if _enraged else _base_modulate)


## 闪红恢复到当前情绪/预警色（受击不吞狂暴红与前摇预警）
func _restore_tint() -> Color:
	if state == S_TELL:
		return Color(1.0, 0.85, 0.6)
	if _enraged:
		return Color(1.0, 0.55, 0.45)
	return _base_modulate
