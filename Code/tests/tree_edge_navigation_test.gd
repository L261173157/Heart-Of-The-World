## 树边导航回归：真实分块障碍、导航网格、蜥蜴刀客与物理帧。
## 固定旧失败点 + 三个世界种子/不同树簇/四向接近；不用重试或放宽到达门槛。
extends Node2D

const GOBLIN := preload("res://scenes/monsters/goblin.tscn")
const BUDGET := 13.0
## 固定取证点：每种子两个不同树簇/方向，避免回归时搜索绕过坏路径。
const LAYOUTS := {
	20260908: [
		Vector3i(9168, 579, 2),
		Vector3i(9168, 585, 0),
		Vector3i(9205, 586, 0),
		Vector3i(9205, 586, 2),
		Vector3i(9321, 609, 3),
		Vector3i(9197, 611, 1),
		Vector3i(9197, 611, 3),
		Vector3i(9120, 629, 1),
	],
	20261002: [
		Vector3i(8517, 1515, 3),
		Vector3i(8548, 1516, 2),
		Vector3i(8561, 1533, 2),
		Vector3i(8561, 1533, 3),
		Vector3i(8563, 1537, 0),
		Vector3i(8563, 1537, 1),
		Vector3i(8559, 1543, 0),
		Vector3i(8587, 1562, 1),
	],
	20261003: [
		Vector3i(14044, 2022, 0),
		Vector3i(13859, 2028, 2),
		Vector3i(13865, 2029, 3),
		Vector3i(13975, 2038, 1),
		Vector3i(13852, 2039, 3),
		Vector3i(14072, 2050, 2),
		Vector3i(14105, 2050, 0),
		Vector3i(14107, 2057, 1),
	],
}
var _checks := 0
var _fails := 0
var _target: Node2D
var _nav: NavTileLayer
var _obstacles: ObstacleTileLayer
var _id := 0

func _ready() -> void:
	seed(20261003)
	GameState.save_enabled = false
	WorldSim.stop()
	WorldSim.sim = EcologySim.new()
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok: _fails += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])

func _load_layout(seed_value: int, cell: Vector2i) -> void:
	if _nav != null:
		_nav.queue_free()
		_obstacles.queue_free()
		await get_tree().process_frame
	BiomeMap.configure(seed_value)
	ObstacleField.restore_destroyed([])
	_nav = NavTileLayer.new()
	add_child(_nav)
	_nav.set_process(false) # 固定本用例的实际9块，避免测试目标替身驱动整幅流式窗
	_obstacles = ObstacleTileLayer.new()
	add_child(_obstacles)
	var chunk := Vector2i(cell.x >> 4, cell.y >> 4)
	for y in range(-1, 2):
		for x in range(-1, 2):
			_nav._fill_chunk(chunk + Vector2i(x, y))
			_obstacles._on_chunk_ready((chunk + Vector2i(x, y)) * 512)
	while not _obstacles._laying.is_empty():
		await get_tree().physics_frame
		await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

func _trial(start: Vector2, goal: Vector2, age: int, rvo: bool, label: String) -> void:
	_target.position = goal
	var actor: MonsterBase = GOBLIN.instantiate()
	add_child(actor)
	actor.set_physics_process(false)
	var instance := MonsterInstance.new()
	_id += 1
	instance.id = _id
	instance.species = load("res://data/species/frog.tres")
	instance.age = age
	instance.size_scale = 1.0
	instance.spawn_pos = start
	actor.setup(instance)
	actor.position = start
	actor.state = MonsterBase.S_CHASE
	actor._nav.avoidance_enabled = rvo
	await get_tree().physics_frame
	await get_tree().physics_frame
	actor._los_cache_ms = -1000
	_check(not actor._has_los(goal), label + " 起点确实被真实树木遮挡")
	var elapsed := 0.0
	var max_penetration := 0.0
	actor.set_physics_process(true)
	while elapsed < BUDGET and actor.position.distance_to(goal) > 40.0:
		await get_tree().physics_frame
		await get_tree().process_frame
		elapsed += get_physics_process_delta_time()
		max_penetration = maxf(max_penetration, _tree_penetration(actor))
	actor.set_physics_process(false)
	var distance := actor.position.distance_to(goal)
	_check(distance <= 40.0, "%s 13秒内进入原有40px近战圈（%.2fs / %.2fpx）" % [label, elapsed, distance])
	_check(max_penetration <= 0.15, "%s 不靠穿树脱困（穿入最多%.3fpx）" % [label, max_penetration])
	actor.queue_free()
	await get_tree().process_frame

## 独立用真实矩形身体与ObstacleField圆半径检查重叠，不依赖新运动配置。
func _tree_penetration(actor: MonsterBase) -> float:
	var half: Vector2 = actor.get_node("CollisionShape2D").shape.size * 0.5
	var cell := Vector2i(floori(actor.position.x / 32.0), floori(actor.position.y / 32.0))
	var deepest := 0.0
	for y in range(-1, 2):
		for x in range(-1, 2):
			var nearby := cell + Vector2i(x, y)
			var sample := ObstacleField.sample_cell(nearby)
			if sample.is_empty(): continue
			var offset := ((Vector2(nearby) + Vector2(0.5, 0.5)) * 32.0 - actor.position).abs()
			var outside := Vector2(maxf(0.0, offset.x - half.x), maxf(0.0, offset.y - half.y))
			deepest = maxf(deepest, float(sample.r) - outside.length())
	return deepest

func _run() -> void:
	_target = Node2D.new()
	_target.add_to_group("player")
	add_child(_target)
	# 旧combat失败现场：相邻树的圆半径9，身体16.2方形，旧版本会停在第二棵树上沿。
	await _load_layout(20260908, Vector2i(11859, 11861))
	_check(ObstacleField.sample_cell(Vector2i(11858, 11861)).get("r", 0) == 9.0,
		"原失败现场的树半径仍为9px")
	for repeat in 3:
		await _trial(Vector2(379461.7, 379551.2), Vector2(379554.5, 379586.4),
			8, repeat == 2, "原失败现场 第%d次 RVO%s" % [repeat + 1, repeat == 2])
	if _fails > 0:
		get_tree().quit(1)
		return
	for seed_value in [20260908, 20261002, 20261003]:
		BiomeMap.configure(seed_value)
		ObstacleField.restore_destroyed([])
		var layouts: Array = LAYOUTS[seed_value]
		_check(layouts.size() == 8, "%d 四个方向各有两处固定真实树簇" % seed_value)
		for layout: Vector3i in layouts:
			var cell := Vector2i(layout.x, layout.y)
			var approach := layout.z
			await _load_layout(seed_value, cell)
			var center := (Vector2(cell) + Vector2(0.5, 0.5)) * 32.0
			var direction := Vector2.from_angle(0.35 + approach * PI * 0.5)
			await _trial(center - direction * 82.23, center + direction * 53.77,
				8 if approach % 2 == 0 else 40, approach % 2 == 1,
				"种子%d 树%s 方向%d" % [seed_value, cell, approach])
	if _fails == 0:
		print("=== TREE EDGE NAVIGATION PASS (%d checks) ===" % _checks)
	get_tree().quit(0 if _fails == 0 else 1)
