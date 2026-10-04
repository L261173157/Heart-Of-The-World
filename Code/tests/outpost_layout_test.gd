## 作者前哨：多种子真实障碍/通路/静态据点隔离、摧毁往返、实际物理与导航。
extends Node

const FIELD_LAYER := preload("res://scripts/main/terrain/obstacle_tile_layer.gd")
const NAV_LAYER := preload("res://scripts/main/terrain/nav_tile_layer.gd")
const WORLD := preload("res://scripts/main/outpost_world.gd")
var _checks := 0
var _fails := 0


func _ready() -> void:
	_run.call_deferred()


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		push_error("FAIL " + label)


func _run() -> void:
	get_tree().root.get_node("GameState").save_enabled = false
	var seed_before := BiomeMap.current_seed()
	for seedv in [BiomeMap.DEFAULT_SEED, 1, 42, 99, 20261004, 982451653, 2147483647]:
		_test_layout(seedv)
	BiomeMap.configure(BiomeMap.DEFAULT_SEED)
	ObstacleField.restore_destroyed([])
	await _test_physical_scene()
	BiomeMap.configure(seed_before)
	if _fails == 0:
		print("=== OUTPOST LAYOUT PASS (%d checks) ===" % _checks)
	get_tree().quit(_fails)


func _test_layout(seedv: int) -> void:
	BiomeMap.configure(seedv)
	ObstacleField.restore_destroyed([])
	var center := OutpostLayout.center()
	var geometry := OutpostLayout.obstacle_cells()
	_check(center.distance_to(BiomeMap.spawn_pos()) < 10000.0, "%d 前哨在本地范围" % seedv)
	_check(center == OutpostLayout.center() and geometry == OutpostLayout.obstacle_cells(), "同种子布局确定")
	_check(OutpostLayout.objects().size() == 8, "八处稳定调查对象")
	var record := OutpostLayout.object_position("patrol_record")
	_check(record.distance_to(BiomeMap.spawn_pos()) > 1300 and record.distance_to(OutpostLayout.object_position("entrance_record")) > 1300,
		"巡逻札记是营地与前哨之间的实际中继线索")
	_check(OutpostLayout.object_position("aid_bag").distance_to(OutpostLayout.object_position("repair_tools")) >= 640, "医药与工具独立空间")
	for item: Dictionary in OutpostLayout.objects():
		_check(not ObstacleField.blocks(item["position"], 12), "%s 交互点物理可达" % item["id"])
		_check(not ObstacleField.nav_blocked_at(item["position"]), "%s 交互点导航可达" % item["id"])
		_check(ObstacleField.liquid_kind_at(item["position"]) == "", "%s 所在地非深水熔岩" % item["id"])
	for cell: Vector2i in geometry:
		_check(ObstacleField.sample_cell(cell).get("kind", "") == geometry[cell], "作者硬障碍进入唯一真源")
		var pos := (Vector2(cell) + Vector2(0.5,0.5)) * 32.0
		_check(not ObstacleField.blocks(ObstacleField.nudge_free(pos, 22),22), "新墙上的旧角色可就近脱离")
	var route := OutpostLayout.path_to_front()
	for i in range(route.size() - 1):
		_check(_walkable_segment(route[i], route[i+1]), "营地来路保留有效角色净空")
	var side: Vector2 = OutpostLayout.entrances()["side"]
	var front: Vector2 = OutpostLayout.entrances()["front"]
	_check(_walkable_segment(side + Vector2(-112,0), side + Vector2(112,0)), "西侧入口直接可走")
	_check(not _walkable_segment(front + Vector2(0,112), front + Vector2(0,-112)), "南门初始碎石真正阻挡")
	_check(_walkable_segment(center + Vector2(-64,-464),center + Vector2(448,-464)), "北侧绕隔墙走廊净空")
	_check(_walkable_segment(center + Vector2(-64,416),center + Vector2(448,416)), "南侧绕隔墙走廊净空")
	_check(not _walkable_segment(center + Vector2(0,96),center + Vector2(256,96)), "补给隔墙不能直穿")
	_check(not ObstacleField.blocks(OutpostLayout.checkpoint_position(),22), "修复检查点对角色体型安全")
	_check(WorldConfig.checkpoints().has(OutpostLayout.CHECKPOINT_ID), "真实检查点目录登记")
	# 明确不重写已有摧毁覆盖层；即使旧档某格与作者墙重合也保留原世界结果。
	var old_cell: Vector2i = geometry.keys()[0]
	var old_remote := Vector2i(12500,12500)
	var saved: Array = ["%d,%d" % [old_cell.x,old_cell.y], "%d,%d" % [old_remote.x,old_remote.y]]
	ObstacleField.restore_destroyed(saved)
	_check(ObstacleField.sample_cell(old_cell).is_empty(), "旧摧毁格优先于新增墙")
	_check(ObstacleField.destroyed_list().has(saved[1]), "远方旧摧毁格保留")
	for cell: Vector2i in OutpostLayout.front_barricade_cells():
		_check(ObstacleField.damage_cell(cell) == "", "第一次真实攻击只减障碍耐久")
		_check(ObstacleField.damage_cell(cell) == "rock", "第二次真实攻击清除碎石")
	_check(_walkable_segment(front + Vector2(0,112),front + Vector2(0,-112)), "清障后南门真正可走")
	_check(not ObstacleField.nav_blocked_at(front), "清障后真源导航同步开放")
	var destroyed := ObstacleField.destroyed_list()
	ObstacleField.restore_destroyed([])
	ObstacleField.restore_destroyed(destroyed)
	_check(not ObstacleField.blocks(front,12) and ObstacleField.destroyed_list().has(saved[1]), "重载碎石清理与远方破坏均保留")
	ObstacleField.restore_destroyed([])
	_test_camps(seedv)


func _walkable_segment(a: Vector2, b: Vector2) -> bool:
	var steps := maxi(1, ceili(a.distance_to(b) / 8.0))
	for i in range(steps + 1):
		var p := a.lerp(b,float(i) / steps)
		if ObstacleField.blocks(p,12) or ObstacleField.liquid_kind_at(p) != "":
			return false
	return true


func _test_camps(seedv: int) -> void:
	var sim := EcologySim.new()
	sim.species_list = SpeciesCatalog.build_all()
	sim._biome_world = true
	var near := 0
	for def: Dictionary in BiomeMap.patches():
		var region := SimRegion.new()
		region.id = def["id"]
		region.terrain = def["terrain"]
		region.center = def["center"]
		region.size = def["size"]
		# 营地生成的原始落点与当前落点都不得碰作者地块，避免抑制区改写巢锚点。
		for species: SpeciesData in sim.species_list:
			if not sim.habitat_match(species,region):
				continue
			var rng := RandomNumberGenerator.new()
			rng.seed = hash("%s|%s" % [region.id,species.species_name]) & 0x7FFFFFFF
			var angle := rng.randf() * TAU
			var raw: Vector2 = region.center + Vector2(cos(angle),sin(angle)) * EcologySim.CAMP_RINGS[sim._camp_ring_index(region,species)] * region.size.x
			if BiomeMap.region_id_at(raw) != region.id:
				raw = (raw + region.center) * 0.5
				if BiomeMap.region_id_at(raw) != region.id:
					raw = region.center
			var actual := sim.camp_pos(region,species)
			if raw.distance_to(OutpostLayout.center()) < 10000:
				near += 1
			_check(not OutpostLayout.reserved_ground(raw), "%d %s 原始据点不被前哨占用" % [seedv,species.species_name])
			_check(not OutpostLayout.footprint().grow(24).has_point(actual), "%d %s 现有巢穴不碰新墙/建筑" % [seedv,species.species_name])
	print("OUTPOST_CAMP_SCAN seed=%d nearby=%d center=%s" % [seedv,near,str(OutpostLayout.center())])


func _step(frames := 2) -> void:
	for i in frames:
		await get_tree().physics_frame
		await get_tree().process_frame


func _test_physical_scene() -> void:
	var scene := Node2D.new()
	add_child(scene)
	var layer := FIELD_LAYER.new()
	scene.add_child(layer)
	var nav := NAV_LAYER.new()
	scene.add_child(nav)
	var center := OutpostLayout.center()
	var chunk := Vector2i(floori(center.x / 512.0),floori(center.y / 512.0))
	for y in range(-2,3):
		for x in range(-2,3):
			layer._on_chunk_ready((chunk + Vector2i(x,y)) * 512)
			nav._fill_chunk(chunk + Vector2i(x,y))
	while not layer._lay_queue.is_empty():
		layer._process(0.0)
	var world := WORLD.new()
	scene.add_child(world)
	await _step(4)
	var front: Vector2 = OutpostLayout.entrances()["front"]
	var side: Vector2 = OutpostLayout.entrances()["side"]
	var space := scene.get_world_2d().direct_space_state
	var blocked := PhysicsRayQueryParameters2D.create(front + Vector2(0,100),front + Vector2(0,-100),1)
	var open := PhysicsRayQueryParameters2D.create(side + Vector2(-100,0),side + Vector2(100,0),1)
	_check(not space.intersect_ray(blocked).is_empty(), "前门真实StaticBody挡住射线")
	_check(space.intersect_ray(open).is_empty(), "西门真实物理无墙")
	for cell: Vector2i in OutpostLayout.front_barricade_cells():
		ObstacleField.damage_cell(cell)
		var kind := ObstacleField.damage_cell(cell)
		get_tree().root.get_node("EventBus").obstacle_destroyed.emit(cell,(Vector2(cell)+Vector2(0.5,0.5))*32,kind)
	await _step(4)
	_check(space.intersect_ray(blocked).is_empty(), "攻击清障事件移除真实物理墙")
	var fc := Vector2i(floori(front.x/32),floori(front.y/32))
	_check(nav.get_cell_source_id(fc) == 0, "攻击清障事件补真实导航瓦片")
	_check(layer.get_cell_source_id(fc) == -1, "攻击清障事件移除可见障碍瓦片")
	var guard := world.object_node("wounded_patrol")
	var pos := guard.position
	world.refresh_state({"evidence":{"rescued":true,"aid_taken":true,"tools_taken":true,"signpost_repaired":true}})
	_check(guard.rescued and guard.position == pos and guard.get_node("PatrolVisual").rotation == 0, "救援后的驻守NPC原地持续存在")
	_check(world.object_node("signpost").repaired and world.object_node("aid_bag").taken, "路标与物资状态由账本投影")
	await _step(3)
	_check(guard.position == pos, "受救巡守不踱步/不触发护送")
	scene.queue_free()
	await _step(2)
