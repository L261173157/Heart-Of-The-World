## 岩甲龟：重击守卫——察觉半径大、护甲厚、伤害极高；重击有明显前摇（蓄力变橙），
## 命中判定取攻击瞬间的距离，前摇期间走出范围即可规避。
## 永不逃跑、生态上永不迁徙、繁殖极慢——熔岩洞窟的定海神针，
## 被玩家猎杀殆尽就是一条世界线里的永久灭绝。
class_name Guardian
extends MonsterBase

const S_WINDUP := 10
const WINDUP_TIME := 0.8
const SMASH_RANGE_MULT := 1.7

var _state_timer := 0.0


func _attack_tick(_delta: float, player: Node2D) -> void:
	if player == null or not player.visible:
		state = S_PATROL
		return
	var dist := global_position.distance_to(player.global_position)
	if dist > inst.species.attack_range * 1.3:
		state = S_CHASE
		return
	velocity = Vector2.ZERO
	if _attack_cd <= 0.0:
		state = S_WINDUP
		_state_timer = WINDUP_TIME
		set_tint(Color(1.0, 0.7, 0.3))  # 蓄力预警


## 闪红恢复到蓄力橙（受击不吞预警色）
func _restore_tint() -> Color:
	return Color(1.0, 0.7, 0.3) if state == S_WINDUP else _base_modulate


func _extra_state_tick(delta: float, player: Node2D) -> void:
	if state != S_WINDUP:
		return
	velocity = Vector2.ZERO
	_state_timer -= delta
	if _state_timer > 0.0:
		return
	set_tint(_base_modulate)
	_attack_cd = inst.species.attack_cooldown
	if player != null and player.visible \
			and global_position.distance_to(player.global_position) <= inst.species.attack_range * SMASH_RANGE_MULT:
		if player.has_method("take_damage"):
			player.take_damage(CombatMath.physical_damage(inst.attack_power()), global_position, inst.display_name())
	state = S_CHASE
