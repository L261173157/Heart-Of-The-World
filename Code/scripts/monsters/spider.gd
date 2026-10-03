## 沼泽蛛：远程吐息风筝——与玩家保持中距离吐弹幕，被贴近会主动后撤；
## 残血提前逃跑。逼身近战或绕侧追击是破解思路，弹幕可走位规避。
## 保持距离读 SpeciesData（沼泽蛛/弹弓地精/石仔怪/火魔鸦共用本原型）
class_name Spider
extends MonsterBase

const BACKOFF_STUCK_TIME := 0.5
const S_SPIT_WINDUP := 10
## （弹幕经 Projectile.spawn 类级池发射，2026-10-01）

## 被逼到墙角的后撤卡墙计时与"困兽"状态：后撤顶墙超时后不再徒劳后退，
## 改为按攻击冷却贴脸吐息——否则玩家把它逼进墙角再贴近，它会顶墙站桩
## 永远不还手（后撤分支直接 return，连吐息都不放）
var _backoff_stuck := 0.0
var _cornered := false
var _spit_windup := 0.0


func _chase_tick(_delta: float, player: Node2D) -> void:
	if player == null or not player.visible:
		state = S_PATROL
		return
	var dist := global_position.distance_to(player.global_position)
	# 激怒期间脱离判定同样放大（与基类一致——捣巢"全族激愤"对风筝型也生效）
	var drop_radius: float = inst.species.detect_radius * 1.3
	if _enrage_timer > 0.0:
		drop_radius *= ENRAGE_DETECT_MULT
	if dist > drop_radius and _aggro_lock <= 0.0:
		state = S_PATROL
		return
	if dist < inst.species.keep_away_dist:
		if _cornered or _is_backed_into_wall():
			_backoff_stuck += _delta
			if _backoff_stuck >= BACKOFF_STUCK_TIME:
				_cornered = true
		else:
			_backoff_stuck = 0.0
		if _cornered:
			# 退无可退：原地按冷却吐息，保持反击能力
			velocity = Vector2.ZERO
			if _attack_cd <= 0.0 and _has_los(player.global_position):
				_attack_cd = inst.species.attack_cooldown
				_spit(player)
			return
		# 被贴近：后撤拉开距离（导航绕障，不再顶墙站桩滑步）
		var away := (global_position - player.global_position).normalized()
		velocity = _nav_velocity_toward(global_position + away * 300.0, inst.move_speed())
		return
	_cornered = false  # 成功拉开距离，解除困兽状态
	if dist <= inst.species.attack_range:
		# 世界 v5 视线博弈：掩体挡住弹道就不浪费吐息——沿导航路径向玩家逼近
		# 重取视线（路径天然绕过掩体，转出阴影即停步吐息；玩家躲岩石卡远程怪
		# 视线有真实收益）。不做定点侧翼：侧翼点在多岩区会选到不可达口袋，
		# 导航返回无路径后直撞墙原地振荡（combat 掩体用例实测）
		if _has_los(player.global_position):
			velocity = Vector2.ZERO
			if _attack_cd <= 0.0:
				_attack_cd = inst.species.attack_cooldown
				_spit(player)
			return
		velocity = _nav_velocity_toward(player.global_position, inst.move_speed())
		return
	velocity = _nav_velocity_toward(player.global_position, inst.move_speed())


## 后撤是否被真实阻挡：只认玩家与地形——被同类虫海挤住不等于"退无可退"
## （旧实现 any-contact 会把开阔地的群怪误判成墙角，风筝机制形同虚设）
func _is_backed_into_wall() -> bool:
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		if col.get_collider() is MonsterBase:
			continue
		return true
	return false


func _spit(player: Node2D) -> void:
	# 吐息动作上屏（Archer_Shoot 8 帧@10fps）：本原型从不进 S_ATTACK，
	# 旧状态映射下这条攻击帧永远没有播放路径（2026-09-28 动作补齐）
	_play_action_anim("attack", 0.75)
	# 飞弹实际离手前留出与近战同长的可读前摇；风筝/困兽和射击冷却仍走原入口。
	state = S_SPIT_WINDUP
	_spit_windup = MELEE_WINDUP
	velocity = Vector2.ZERO
	_begin_attack_warning(player, inst.attack_power())


func _extra_state_tick(delta: float, player: Node2D) -> void:
	if state != S_SPIT_WINDUP:
		return
	velocity = Vector2.ZERO
	if player == null or not player.visible:
		_clear_attack_context()
		_spit_windup = 0.0
		state = S_PATROL
		return
	_spit_windup = maxf(0.0, _spit_windup - delta)
	if _spit_windup > 0.0:
		return
	_clear_attack_warning()
	# 蓄力期间出现掩体仍不穿墙射击；下一次继续正常导航重取视线。
	if _has_los(player.global_position):
		_release_spit(player)
	_clear_attack_context()
	state = S_CHASE


func _release_spit(player: Node2D) -> void:
	_squash(Vector2(0.94, 1.06), 0.12)  # 吐息轻弹
	var dir := (player.global_position - global_position).normalized()
	var context := _damage_context(player, inst.attack_power(), true, -dir)
	Projectile.spawn(get_parent(), global_position + dir * 16.0, dir,
		CombatMath.magic_damage(float(context["strength"])), 270.0, inst.display_name(),
		inst.species.projectile_tex, context)
