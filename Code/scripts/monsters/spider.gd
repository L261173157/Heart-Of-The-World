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
var _spit_dir := Vector2.RIGHT
var _spit_distance := 0.0


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
			velocity = _spacing_velocity(player)
			if _attack_cd <= 0.0:
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


## 冷却期慢速侧移保持间距；被掩体挡住时仍走原有寻路接近入口。
func _spacing_velocity(player: Node2D) -> Vector2:
	var away := (global_position - player.global_position).normalized()
	if away.is_zero_approx():
		away = Vector2.RIGHT
	var side := 1.0 if inst.id % 2 == 0 else -1.0
	var distance := clampf(inst.species.keep_away_dist + 45.0,
		inst.species.keep_away_dist, inst.species.attack_range * 0.85)
	var target := player.global_position + away.rotated(side * 0.25) * distance
	return _nav_velocity_toward(target, inst.move_speed() * 0.35)


func _spit(player: Node2D) -> void:
	if not _try_attack_slot(player):
		return
	state = S_SPIT_WINDUP
	_spit_windup = maxf(0.05, inst.species.ranged_windup_time)
	_attack_cd = inst.species.attack_cooldown
	velocity = Vector2.ZERO
	_spit_distance = global_position.distance_to(player.global_position)
	_begin_attack_warning(player, inst.attack_power())
	_spit_dir = _attack_aim_dir
	_show_attack_sector(inst.species.attack_range)
	_play_action_anim("attack", _spit_windup + inst.species.ranged_recovery_time)
	set_tint(WINDUP_TINT)


func _restore_tint() -> Color:
	return WINDUP_TINT if state == S_SPIT_WINDUP else super()


func _on_staggered() -> void:
	_spit_windup = 0.0


func _on_nav_velocity(safe_velocity: Vector2) -> void:
	super(Vector2.ZERO if state == S_SPIT_WINDUP else safe_velocity)


func _extra_state_tick(delta: float, player: Node2D) -> void:
	if state != S_SPIT_WINDUP:
		return
	velocity = Vector2.ZERO
	if player == null or not player.visible:
		_clear_attack_context()
		_spit_windup = 0.0
		state = S_PATROL
		set_tint(_restore_tint())
		return
	_spit_windup = maxf(0.0, _spit_windup - delta)
	if _spit_windup > 0.0:
		return
	_clear_attack_warning()
	# 只沿开始预警的射线检查新掩体，不在释放瞬间追踪玩家重新瞄准。
	var query := PhysicsRayQueryParameters2D.create(global_position,
		global_position + _spit_dir * _spit_distance, 1)
	query.exclude = [get_rid()]
	if player is CollisionObject2D:
		query.exclude = [get_rid(), (player as CollisionObject2D).get_rid()]
	query.hit_from_inside = true
	if get_world_2d().direct_space_state.intersect_ray(query).is_empty():
		_release_spit(player)
	_start_attack_recovery(inst.species.ranged_recovery_time)
	_clear_attack_context(true)
	state = S_CHASE
	set_tint(_restore_tint())


func _release_spit(player: Node2D) -> void:
	_squash(Vector2(0.94, 1.06), 0.12)  # 吐息轻弹
	var dir := _spit_dir
	var context := _damage_context(player, inst.attack_power(), true, -dir)
	Projectile.spawn(get_parent(), global_position + dir * 16.0, dir,
		CombatMath.magic_damage(float(context["strength"])), 270.0, inst.display_name(),
		inst.species.projectile_tex, context)
