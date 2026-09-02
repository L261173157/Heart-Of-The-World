## 雪蝎：远程吐息风筝——与玩家保持中距离吐弹幕，被贴近会主动后撤；
## 残血提前逃跑。逼身近战或绕侧追击是破解思路，弹幕可走位规避。
class_name Spider
extends MonsterBase

const KEEP_AWAY_DIST := 120.0
const PROJECTILE := preload("res://scenes/monsters/projectile.tscn")


func _chase_tick(_delta: float, player: Node2D) -> void:
	if player == null or not player.visible:
		state = S_PATROL
		return
	var dist := global_position.distance_to(player.global_position)
	if dist > inst.species.detect_radius * 1.3 and _aggro_lock <= 0.0:
		state = S_PATROL
		return
	if dist < KEEP_AWAY_DIST:
		# 被贴近：后撤拉开距离
		velocity = (global_position - player.global_position).normalized() * inst.move_speed()
		return
	if dist <= inst.species.attack_range:
		velocity = Vector2.ZERO
		if _attack_cd <= 0.0:
			_attack_cd = inst.species.attack_cooldown
			_spit(player)
		return
	velocity = (player.global_position - global_position).normalized() * inst.move_speed()


func _spit(player: Node2D) -> void:
	var dir := (player.global_position - global_position).normalized()
	var projectile: Projectile = PROJECTILE.instantiate()
	get_parent().add_child(projectile)
	projectile.global_position = global_position + dir * 16.0
	projectile.launch(dir, CombatMath.magic_damage(inst.attack_power()), 270.0, inst.display_name())
