## 野猪：蓄力冲锋——先停步低头（前摇预警），再沿锁定方向直线高速冲撞；
## 撞墙会陷入硬直（反击窗口），命中则重创并击退玩家。
## 残血不逃反狂暴：移速与冲锋更快。走位引它撞墙是最优解。
class_name Boar
extends MonsterBase

const S_TELL := 10
const S_CHARGE := 11
const S_TIRED := 12

const CHARGE_TRIGGER_DIST := 320.0
const CHARGE_TELL_TIME := 0.5
const CHARGE_SPEED_MULT := 2.6
const CHARGE_MAX_TIME := 0.9
const CHARGE_HIT_DIST := 38.0
const CHARGE_DAMAGE_MULT := 2.0
const TIRED_TIME := 1.3
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


func _chase_tick(delta: float, player: Node2D) -> void:
	if player != null and player.visible and _attack_cd <= 0.0 \
			and global_position.distance_to(player.global_position) < CHARGE_TRIGGER_DIST:
		state = S_TELL
		_state_timer = CHARGE_TELL_TIME
		_charge_dir = (player.global_position - global_position).normalized()
		velocity = Vector2.ZERO
		set_tint(Color(1.0, 0.85, 0.6))  # 前摇预警色
		return
	super(delta, player)


func _extra_state_tick(delta: float, player: Node2D) -> void:
	match state:
		S_TELL:
			velocity = Vector2.ZERO
			_state_timer -= delta
			if _state_timer <= 0.0:
				state = S_CHARGE
				_state_timer = CHARGE_MAX_TIME
				_apply_mood_color()
		S_CHARGE:
			velocity = _charge_dir * inst.move_speed() * _speed_mult() * CHARGE_SPEED_MULT
			_state_timer -= delta
			if player != null and player.visible \
					and global_position.distance_to(player.global_position) < CHARGE_HIT_DIST:
				if player.has_method("take_damage"):
					player.take_damage(
						CombatMath.physical_damage(inst.attack_power() * CHARGE_DAMAGE_MULT),
						global_position, inst.display_name())
				_end_charge()
			elif get_slide_collision_count() > 0 or _state_timer <= 0.0:
				_end_charge()
		S_TIRED:
			velocity = Vector2.ZERO
			_state_timer -= delta
			if _state_timer <= 0.0:
				state = S_CHASE
				_apply_mood_color()


func _end_charge() -> void:
	_attack_cd = inst.species.attack_cooldown
	if get_slide_collision_count() > 0:
		state = S_TIRED  # 撞墙硬直：暴露给玩家的反击窗口
		_state_timer = TIRED_TIME
		set_tint(_base_modulate)
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
