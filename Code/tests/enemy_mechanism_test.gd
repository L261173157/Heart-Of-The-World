## 怪物机制闭环：真实 RVO/身体跨 LOD、普通近战遮挡与前摇中断。
## 不调整物种速度/射程，不关闭主验证中的避让，不改范围砸击的遮挡策略。
extends Node2D

const PLAYER := preload("res://scenes/player/player.tscn")
const ORIGIN := Vector2(120000, 120000)
var _player: Player
var _checks := 0
var _fails := 0
var _next_id := 0

func _ready() -> void:
	GameState.save_enabled = false
	GameState.ecology_snapshot = null
	GameState.reset_all()
	WorldSim.stop()
	BiomeMap.configure(BiomeMap.DEFAULT_SEED)
	ObstacleField.restore_destroyed([])
	WorldSim.sim = EcologySim.new()
	var region := SimRegion.new()
	region.id = "enemy_mechanism"
	region.center = ORIGIN
	region.size = Vector2(100000, 100000)
	region.capacity = 1000
	WorldSim.sim.regions[region.id] = region
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])

func _frames(count: int) -> void:
	for n in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func _reset_player(pos := ORIGIN) -> void:
	_player.position = pos
	_player.visible = true
	_player.current_hp = 10000.0
	_player._is_dead = false
	_player._hurt_iframes = 0.0
	_player._protect_timer = 0.0
	_player._dash_timer = 0.0

func _monster(id: String, scene_name: String, pos: Vector2, age := 200, size := 1.0) -> MonsterBase:
	var monster: MonsterBase = load("res://scenes/monsters/%s.tscn" % scene_name).instantiate()
	add_child(monster)
	monster.set_physics_process(false)
	var inst := MonsterInstance.new()
	_next_id += 1
	inst.id = _next_id
	inst.species = load("res://data/species/%s.tres" % id).duplicate()
	inst.region_id = "enemy_mechanism"
	inst.age = age
	inst.lifespan = 100000
	inst.size_scale = size
	inst.spawn_pos = pos
	WorldSim.sim.instances[inst.id] = inst
	monster.setup(inst)
	monster.position = pos
	monster._player_ref = _player
	monster.state = MonsterBase.S_CHASE
	monster._aggro_lock = 100.0
	return monster

func _run() -> void:
	seed(20261003)
	_player = PLAYER.instantiate()
	add_child(_player)
	_player.set_process(false)
	_player.set_physics_process(false)
	_player.get_node("Camera2D").enabled = false
	_reset_player()
	await _frames(2)
	await _ordinary_speeds()
	await _age_and_enrage()
	await _same_body_lod()
	await _crowd_avoidance()
	await _melee_cover()
	await _cover_during_windup()
	_player.queue_free()
	await _frames(2)
	WorldSim.stop()
	print("=== ENEMY MECHANISM %s (%d checks) ===" % ["PASS" if _fails == 0 else "FAIL", _checks])
	get_tree().quit(0 if _fails == 0 else 1)

func _measure_speed(monster: MonsterBase, expected: float, label: String) -> void:
	monster.set_physics_process(true)
	await _frames(3)
	var before := monster.position
	await _frames(18)
	var distance := before.distance_to(monster.position)
	var wanted := expected * 18.0 / Engine.physics_ticks_per_second
	_check(absf(monster.velocity.length() - expected) < 1.0,
		"%s：真实速度 %.2f = 公式 %.2f" % [label, monster.velocity.length(), expected])
	_check(absf(distance - wanted) < maxf(2.5, wanted * 0.04),
		"%s：真实身体位移 %.2f ≈ %.2f" % [label, distance, wanted])
	monster.set_physics_process(false)

func _ordinary_speeds() -> void:
	_reset_player()
	for entry: Array in [["goblin", "goblin", 200], ["bat", "goblin", 200], ["guardian", "guardian", 0]]:
		for avoidance in [false, true]:
			var monster := _monster(entry[0], entry[1], ORIGIN + Vector2(700, 0), entry[2])
			monster._nav.avoidance_enabled = avoidance
			await _measure_speed(monster, monster.inst.move_speed(), "%s RVO=%s" % [entry[0], avoidance])
			_check(monster._nav.avoidance_enabled == avoidance, "验证过程保留所选避让模式")
			monster.queue_free()
			await _frames(2)

func _age_and_enrage() -> void:
	_reset_player()
	var monster := _monster("goblin", "goblin", ORIGIN + Vector2(700, 0), 0)
	var identity := monster.get_instance_id()
	await _measure_speed(monster, monster.inst.move_speed(), "幼龄普通追击")
	monster.inst.age = 300
	await _measure_speed(monster, monster.inst.move_speed(), "同身体成长后的追击")
	_check(monster.get_instance_id() == identity and monster._nav.avoidance_enabled,
		"成长同步不重建身体也不绕过 RVO")
	monster.queue_free()
	await _frames(2)
	var boar := _monster("boar", "boar", ORIGIN + Vector2(850, 0), 200) as Boar
	boar._attack_cd = 100.0  # 只测普通追击，冲锋由既有真物理回归单独守闸。
	await _measure_speed(boar, boar.inst.move_speed(), "突袭蛇未狂暴追击")
	boar.take_damage(boar.current_hp * 0.8)
	_check(boar._enraged, "真实承伤触发狂暴")
	await _measure_speed(boar, boar.inst.move_speed() * Boar.ENRAGE_SPEED_MULT, "同身体狂暴后追击")
	_check(boar._nav.avoidance_enabled, "狂暴仍通过 RVO 避让")
	boar.queue_free()
	await _frames(2)

func _same_body_lod() -> void:
	_reset_player()
	var monster := _monster("bat", "goblin", ORIGIN + Vector2(980, 0))
	monster.state = MonsterBase.S_PATROL
	monster._hunt_recheck_remaining = 0.0
	var identity := monster.get_instance_id()
	var expected := monster.inst.move_speed() * MonsterBase.HUNT_SPEED_MULT
	monster.set_physics_process(true)
	await _frames(12)
	_check(monster.position.distance_to(_player.position) > MonsterBase.LOD_FAR_DIST
		and monster._hunt_mode and absf(monster.velocity.length() - expected) < 1.0,
		"同身体远档按真实巡猎速度积分")
	var reached_near := false
	for frame in 180:
		await _frames(1)
		if monster.position.distance_to(_player.position) < 870.0:
			reached_near = true
			break
	_check(reached_near, "不传送、不重建，真实移动跨入900px近档")
	var before := monster.position
	await _frames(18)
	_check(monster.get_instance_id() == identity and monster._hunt_mode and monster._nav.avoidance_enabled,
		"跨档后保留同一身体、巡猎和 RVO")
	_check(absf(monster.velocity.length() - expected) < 1.0,
		"跨档不将%.2f截成100：实际%.2f" % [expected, monster.velocity.length()])
	_check(absf(before.distance_to(monster.position) - expected * 18.0 / Engine.physics_ticks_per_second) < 2.5,
		"近档实际位移与远档同速")
	monster.queue_free()
	await _frames(2)

func _crowd_avoidance() -> void:
	_reset_player()
	var upper := _monster("bat", "goblin", ORIGIN + Vector2(-650, -10.5))
	var lower := _monster("bat", "goblin", ORIGIN + Vector2(-650, 10.5))
	upper.set_physics_process(true)
	lower.set_physics_process(true)
	var altered := false
	var min_distance := INF
	for frame in 36:
		await _frames(1)
		min_distance = minf(min_distance, upper.position.distance_to(lower.position))
		if upper._navq_velocity != Vector2.INF:
			altered = altered or upper.velocity.distance_to(upper._navq_velocity) > 1.0
	_check(upper._nav.avoidance_enabled and lower._nav.avoidance_enabled and altered,
		"同族相遇仍由真实 RVO 修正期望速度")
	_check(min_distance > 18.0 and upper.position.x > ORIGIN.x - 610.0
		and lower.position.x > ORIGIN.x - 610.0, "群体避让不重叠、不被新上限冻结")
	upper.queue_free()
	lower.queue_free()
	await _frames(2)

func _wall(pos: Vector2, radius: float) -> StaticBody2D:
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	shape.shape = circle
	wall.add_child(shape)
	add_child(wall)
	wall.position = pos
	return wall

func _blocked(monster: MonsterBase) -> bool:
	var query := PhysicsRayQueryParameters2D.create(monster.position, _player.position, 1)
	query.exclude = [monster.get_rid(), _player.get_rid()]
	query.hit_from_inside = true
	return not get_world_2d().direct_space_state.intersect_ray(query).is_empty()

func _await_hit(monster: MonsterBase) -> bool:
	var saw_windup := false
	for frame in 90:
		await _frames(1)
		saw_windup = saw_windup or monster._melee_windup > 0.0
		if _player.current_hp < 10000.0:
			return saw_windup
	return false

func _melee_cover() -> void:
	for kind in ["goblin", "king"]:
		for direction: Vector2 in [Vector2.RIGHT, Vector2.DOWN]:
			var boss: bool = kind == "king"
			_reset_player(ORIGIN + direction * (18.1 if boss else 15.0))
			var wall := _wall(ORIGIN, float(ObstacleField.KIND_INFO["deadtree"]["r"]) if boss else 2.0)
			if not boss:
				# 普通小体型用薄长墙，避免在观察窗内真实绕过一个微小圆柱。
				var rect := RectangleShape2D.new()
				rect.size = Vector2(4, 160) if direction.x != 0.0 else Vector2(160, 4)
				(wall.get_child(0) as CollisionShape2D).shape = rect
			var monster := _monster("stag_beetle_king" if boss else "goblin", "ant" if boss else "goblin",
				ORIGIN - direction * (27.9 if boss else 15.0), 200, 2.2 if boss else 1.0)
			monster.set_physics_process(true)
			await _frames(24)
			_check(_blocked(monster) and monster.position.distance_to(_player.position) < 60.0,
				"%s %s：真实墙在60px内仍挡完整视线" % [kind, direction])
			_check(is_equal_approx(_player.current_hp, 10000.0), "%s %s：普通近战不能隔墙扣血" % [kind, direction])
			_check(monster._melee_windup <= 0.0 and monster._attack_context.is_empty(), "遮挡不遗留幽灵前摇/盾形预警")
			monster.set_physics_process(false)
			wall.queue_free()
			await _frames(2)
			_reset_player(_player.position)
			monster._attack_cd = 0.0
			monster.set_physics_process(true)
			var landed := await _await_hit(monster)
			_check(not _blocked(monster) and landed, "%s %s：去墙后正常前摇仍命中真实玩家" % [kind, direction])
			monster.queue_free()
			await _frames(2)

func _cover_during_windup() -> void:
	_reset_player(ORIGIN + Vector2(18.1, 0))
	var monster := _monster("stag_beetle_king", "ant", ORIGIN - Vector2(27.9, 0), 200, 2.2)
	monster.set_physics_process(true)
	var started := false
	for frame in 30:
		await _frames(1)
		if monster._melee_windup > 0.0:
			started = true
			break
	_check(started and _player.current_hp == 10000.0, "无掩体时真实开始前摇，尚未扣血")
	var wall := _wall(ORIGIN, float(ObstacleField.KIND_INFO["deadtree"]["r"]))
	await _frames(18)
	_check(_blocked(monster) and _player.current_hp == 10000.0,
		"前摇中出现真实掩体，取消本次命中而非使用旧视线")
	_check(monster._melee_windup <= 0.0 and monster._attack_context.is_empty(), "取消后不保留旧招式ID和前摇")
	monster.set_physics_process(false)
	wall.queue_free()
	await _frames(2)
	_reset_player(_player.position)
	monster._attack_cd = 0.0
	monster.set_physics_process(true)
	_check(await _await_hit(monster), "移走新掩体后需重新前摇再命中")
	monster.queue_free()
	await _frames(2)
