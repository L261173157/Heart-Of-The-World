## 可选故事不能用账本标志冒充实际效果：七种子、原玩家身体、真实墙体与射线。
extends Node

const SEEDS := [BiomeMap.DEFAULT_SEED, 1, 42, 99, 20261004, 982451653, 2147483647]
const LAYER := preload("res://scripts/main/terrain/obstacle_tile_layer.gd")
const NAV := preload("res://scripts/main/terrain/nav_tile_layer.gd")
const PLAYER := preload("res://scenes/player/player.tscn")
const DIRECTIONS := [Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN]

## 只省略无关的任务菜单初始化；旅行筛选方法完全使用生产 CampaignQuest。
class TravelProbe extends CampaignQuest:
	func _ready() -> void:
		pass

var checks := 0
var failures := 0
var player: Player
var world: CampaignWorld
var layer: ObstacleTileLayer
var nav: NavTileLayer
var scene: Node2D
var seed_value := 0

func _ready() -> void:
	GameState.save_enabled = false
	WorldSim.set_process(false)
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("OPTIONAL GEOMETRY FAIL %d: %s" % [seed_value, label])

func _step(frames := 2) -> void:
	for i in frames:
		await get_tree().physics_frame
		await get_tree().process_frame

func _run() -> void:
	for current_seed: int in SEEDS:
		seed_value = current_seed
		BiomeMap.configure(seed_value)
		ObstacleField.restore_destroyed([])
		CampaignLayout.set_open_gates([])
		await _build_scene()
		await _test_scholar()
		_test_watchman()
		await _test_troll_arrivals()
		scene.queue_free()
		await _step(3)
	BiomeMap.configure(BiomeMap.DEFAULT_SEED)
	ObstacleField.restore_destroyed([])
	if failures == 0:
		print("=== CAMPAIGN OPTIONAL GEOMETRY PASS (%d checks, 7 seeds) ===" % checks)
	else:
		print("=== CAMPAIGN OPTIONAL GEOMETRY FAILED (%d/%d checks, 7 seeds) ===" % [failures, checks])
	get_tree().quit(0 if failures == 0 else 1)

func _build_scene() -> void:
	scene = Node2D.new()
	add_child(scene)
	layer = LAYER.new()
	scene.add_child(layer)
	nav = NAV.new()
	scene.add_child(nav)
	var center := CampaignLayout.site_center("hill")
	_load_rectangle(Rect2(center + Vector2(-1792, -1376), Vector2(2048, 2304)))
	world = CampaignWorld.new()
	scene.add_child(world)
	player = PLAYER.instantiate() as Player
	(player.get_node("Camera2D") as Camera2D).enabled = false
	scene.add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	player.teleport_to(CampaignLayout.entry("hill"))
	await _step(4)
	_check(_body_clear(player.position), "丘陵真实入口有完整玩家身体净空")

func _load_rectangle(bounds: Rect2) -> void:
	var low := Vector2i(floori(bounds.position.x / 512), floori(bounds.position.y / 512))
	var high := Vector2i(floori(bounds.end.x / 512), floori(bounds.end.y / 512))
	for y in range(low.y, high.y + 1):
		for x in range(low.x, high.x + 1):
			var chunk := Vector2i(x, y)
			layer._on_chunk_ready(chunk * 512)
			nav._fill_chunk(chunk)
	while not layer._lay_queue.is_empty():
		layer._process(0)

func _test_scholar() -> void:
	var gate_id := "side_scholar:shortcut_gate"
	var start := CampaignLayout.object_position(gate_id)
	var finish := CampaignLayout.object_position("side_scholar:shortcut_exit")
	var giver := CampaignLayout.object_position("side_scholar:giver")
	var site := CampaignLayout.site_center("hill")
	var bounds := Rect2(site + Vector2(-1760, -1344), Vector2(1984, 2240))
	var approach := _physics_path(CampaignLayout.entry("hill"), giver, bounds)
	_check(not approach.is_empty() and _walk(approach), "学者发布人可从本章入口实际走到")
	var to_gate := _physics_path(giver, start, bounds)
	_check(not to_gate.is_empty() and _walk(to_gate), "发布人到近道南端实际可走")
	player.teleport_to(start)
	var collision := player.move_and_collide(finish - start)
	_check(collision != null and player.position.distance_to(finish) > 100, "关闭的南门以实际墙体阻挡穿行")
	var closed_path := _physics_path(start, finish, bounds)
	_check(not closed_path.is_empty(), "保留铭文时外侧绕行仍存在，出口不是封闭奖励房")
	_check(_walk(closed_path), "关闭近道时完整绕行由原玩家身体走通")
	var closed_length := _length(closed_path)
	_check(closed_length > start.distance_to(finish) + 128, "关闭时绕行确实比南北直穿更长")
	var exit_node := world.object_node("side_scholar:shortcut_exit")
	_check(exit_node != null and bool(exit_node.call("can_interact")), "关闭近道仍能从外侧实际到达并交互出口")
	world.refresh_state({"open_gates": [gate_id]})
	await _step(4)
	var open_path := _physics_path(start, finish, bounds)
	_check(not open_path.is_empty() and _walk(open_path), "拆取机关件后原玩家身体实际走通近道")
	var open_length := _length(open_path)
	_check(open_length + 128 < closed_length, "开门后物理最短路显著短于原绕行")
	_check(is_equal_approx(open_length, start.distance_to(finish)), "开启的房间是南北贯通直线通道")
	player.teleport_to(start)
	_check(player.move_and_collide(finish - start) == null and player.position.distance_to(finish) < 1,
		"原玩家完整扫掠确实穿过南门、房间及北出口")
	for cell: Vector2i in CampaignLayout.gate_cells(gate_id):
		_check(layer.get_cell_source_id(cell) == -1 and nav.get_cell_source_id(cell) >= 0,
			"开门同步清除可见墙并恢复导航格")
	world.refresh_state({"open_gates": [gate_id]})
	await _step(2)
	player.teleport_to(start)
	_check(player.move_and_collide(finish - start) == null and player.position.distance_to(finish) < 1,
		"重复投影不会重新堵住已开的实体近道")
	world.refresh_state({})
	await _step(4)
	player.teleport_to(start)
	_check(player.move_and_collide(finish - start) != null, "恢复未开门快照重新阻挡实际身体")
	for cell: Vector2i in CampaignLayout.gate_cells(gate_id):
		_check(layer.get_cell_source_id(cell) >= 0 and nav.get_cell_source_id(cell) == -1,
			"关闭快照同步恢复可见墙并收回导航格")
	print("OPTIONAL GEOMETRY seed=%d scholar closed=%.0f open=%.0f" % [seed_value, closed_length, open_length])

func _test_watchman() -> void:
	var giver := CampaignLayout.object_position("side_watchman:giver")
	var old_flag := CampaignLayout.object_position("side_watchman:old_flag")
	var site := CampaignLayout.site_center("hill")
	var bounds := Rect2(site + Vector2(-1760, -1344), Vector2(1984, 2240))
	var approach := _physics_path(CampaignLayout.entry("hill"), giver, bounds)
	_check(not approach.is_empty() and _walk(approach), "瞭望者可从本章入口实际走到")
	_check(_ray_blocked(giver, old_flag), "原发布人到旧旗的真实视线确被岩脊阻断")
	var old_node := world.object_node("side_watchman:old_flag")
	_check(old_node != null and not bool(old_node.call("is_observed", giver)), "旧旗现场显示也服从实际遮挡")
	for id: String in ["side_watchman:watch_near", "side_watchman:watch_high"]:
		var at := CampaignLayout.object_position(id)
		_check(not _ray_blocked(giver, at), id + " 到发布人有真实无遮挡视线")
		var node := world.object_node(id)
		_check(node != null and bool(node.call("is_observed", giver)), id + " 在现场可观察")
		var path := _physics_path(giver, at, bounds)
		_check(not path.is_empty() and _walk(path), id + " 从发布人真实步行可达")
		_check(node != null and bool(node.call("can_interact")), id + " 身体到达后可现场交互")
	var old_path := _physics_path(giver, old_flag, bounds)
	_check(not old_path.is_empty() and _walk(old_path), "旧旗虽然遮挡，绕过岩脊后仍真实可达")
	_check(old_node != null and bool(old_node.call("can_interact")), "旧旗到场调查无需穿墙")

func _test_troll_arrivals() -> void:
	var giver := CampaignLayout.object_position("side_troll:giver")
	var pads := CampaignLayout.entry_candidates("side_troll")
	var bounds := Rect2(giver - Vector2.ONE, Vector2.ONE * 2)
	for pad: Vector2 in pads:
		bounds = bounds.expand(pad)
	bounds = bounds.grow(192)
	_load_rectangle(bounds)
	await _step(4)
	_check(pads.size() >= 3, "远端旧旗遗址保留多个实际到达候选")
	for i in pads.size():
		var pad := pads[i]
		_check(_body_clear(pad) and ObstacleField.liquid_kind_at(pad) == "",
			"旧旗到达候选%d有真实身体净空且无液体伤害" % i)
		_check(pad.distance_to(BiomeMap.farthest_patch("forest")["center"]) > 1800,
			"旧旗到达候选%d不落在原巨魔王脚下" % i)
		var path := _physics_path(pad, giver, bounds)
		_check(not path.is_empty() and _walk(path), "旧旗到达候选%d可实际走到远端发布人" % i)
		var node := world.object_node("side_troll:giver")
		_check(node != null and bool(node.call("can_interact")), "旧旗到达候选%d最终可现场交谈" % i)
	await _test_troll_safety_selector(pads)

func _test_troll_safety_selector(pads: Array[Vector2]) -> void:
	if pads.is_empty():
		_check(false, "旅行安全筛选需要真实候选点")
		return
	# 此处是明确的孤立生态夹具；不在生产世界新增怪物或移动出生记录。
	var previous_sim := WorldSim.sim
	var sim := EcologySim.new()
	var region := SimRegion.new()
	region.id = BiomeMap.region_id_at(pads[0])
	region.center = pads[0] + Vector2(10000, 10000)
	region.terrain = "forest"
	region.capacity = 10
	var species := preload("res://data/species/goblin.tres") as SpeciesData
	var species_list: Array[SpeciesData] = [species]
	sim.setup([region], species_list, {})
	WorldSim.sim = sim
	var inst := sim.spawn_instance(species, region.id, 0, 0, 1.0, false, region.center)
	var actor := preload("res://scenes/monsters/goblin.tscn").instantiate() as MonsterBase
	scene.add_child(actor)
	actor.setup(inst)
	actor.set_physics_process(false)
	actor.set_process(false)
	actor.global_position = pads[0]
	var host := TravelProbe.new()
	scene.add_child(host)
	await _step(2)
	var before := sim.to_dict()
	var alternate := host.travel_destination("side_troll")
	_check(alternate.is_finite() and alternate != pads[0],
		"真实演员占住首个旧旗落点时，生产筛选器仍找到不同安全候选")
	_check(alternate in pads and alternate.distance_to(actor.global_position) >= 700,
		"旁路候选与当前演员的实际距离满足700像素安全闸门")
	_check(inst.spawn_pos.distance_to(pads[0]) > 700,
		"危险证据来自演员当前坐标，而非远方旧出生记录")
	_check(_body_clear(alternate) and ObstacleField.liquid_kind_at(alternate) == "",
		"筛选结果确实有身体净空并保持干燥")
	if alternate.is_finite():
		actor.global_position = alternate
		_check(host.travel_destination("side_troll") == pads[0],
			"演员离开首选点后生产筛选实时恢复首选，不缓存旧危险")
	_check(sim.to_dict() == before, "安全筛选不增加个体、不改变出生点、生命或模拟时钟")
	actor.queue_free()
	host.queue_free()
	await _step(2)
	WorldSim.sim = previous_sim

func _body_clear(at: Vector2) -> bool:
	if not at.is_finite():
		return false
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = (player.get_node("CollisionShape2D") as CollisionShape2D).shape
	query.transform = Transform2D(0, at)
	query.collision_mask = player.collision_mask
	query.exclude = [player.get_rid()]
	return player.get_world_2d().direct_space_state.intersect_shape(query).is_empty()

func _ray_blocked(from: Vector2, to: Vector2) -> bool:
	var query := PhysicsRayQueryParameters2D.create(from, to, 1)
	query.exclude = [player.get_rid()]
	return not player.get_world_2d().direct_space_state.intersect_ray(query).is_empty()

## 广搜以原玩家 test_move 扫掠的实际墙体为准，不拿任务标志或逻辑可走格作答案。
func _physics_path(start: Vector2, finish: Vector2, bounds: Rect2) -> Array[Vector2]:
	if not _body_clear(start) or not _body_clear(finish):
		return []
	var destination := Vector2i(roundi((finish.x - start.x) / 32), roundi((finish.y - start.y) / 32))
	var previous := {Vector2i.ZERO: Vector2i.ZERO}
	var queue: Array[Vector2i] = [Vector2i.ZERO]
	var index := 0
	while index < queue.size():
		var cell := queue[index]
		index += 1
		if cell == destination:
			var result: Array[Vector2] = []
			while cell != Vector2i.ZERO:
				result.push_front(start + Vector2(cell) * 32)
				cell = previous[cell]
			result.push_front(start)
			return result
		var at := start + Vector2(cell) * 32
		for direction: Vector2i in DIRECTIONS:
			var next := cell + direction
			var there := start + Vector2(next) * 32
			if previous.has(next) or not bounds.has_point(there):
				continue
			if player.test_move(Transform2D(0, at), Vector2(direction) * 32):
				continue
			if ObstacleField.liquid_kind_at(there) != "":
				continue
			previous[next] = cell
			queue.append(next)
	return []

func _walk(path: Array[Vector2]) -> bool:
	if path.is_empty():
		return false
	# 只把角色放在本段起点，之后每一步都走真实 CharacterBody2D 碰撞。
	player.teleport_to(path[0])
	for i in range(1, path.size()):
		var steps := maxi(1, ceili(path[i - 1].distance_to(path[i]) / 8))
		for j in range(1, steps + 1):
			var target := path[i - 1].lerp(path[i], float(j) / steps)
			if player.move_and_collide(target - player.global_position) != null:
				return false
			if player.global_position.distance_to(target) > 1:
				return false
			if ObstacleField.liquid_kind_at(player.global_position) != "":
				return false
	return player.global_position.distance_to(path[-1]) < 1

func _length(path: Array[Vector2]) -> float:
	var total := 0.0
	for i in range(1, path.size()):
		total += path[i - 1].distance_to(path[i])
	return total
