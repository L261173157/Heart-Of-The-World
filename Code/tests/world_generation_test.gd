## 世界几何版本：审计前 v1 固定基线逐位不变，显式 v2 锚点归属正确。
## 指纹在改动前由 d64dc91243a63005f55e4b02acc5d282099c750b、官方 Godot 4.7 产生。
extends SceneTree

const GOLDEN := "res://tests/fixtures/world_generation_v1.json"
const LEGACY_SEEDS := [20260908, 93, 997, 1670]
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.get_node("GameState").save_enabled = false
	if "--legacy-reader" in OS.get_cmdline_user_args():
		await _legacy_reader()
		return
	var records := {}
	for world_seed: int in LEGACY_SEEDS:
		BiomeMap.configure(world_seed)
		records[str(world_seed)] = _fingerprints()
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GOLDEN))
	for world_seed: String in records:
		for aspect: String in expected[world_seed]:
			_check(records[world_seed][aspect] == expected[world_seed][aspect], "legacy exact %s seed=%s" % [aspect, world_seed])
	var versioned := load("res://scripts/ecology/biome_map.gd").has_method("current_generation")
	_check(versioned, "generation selection is explicit")
	if "--legacy-only" in OS.get_cmdline_user_args():
		for world_seed: int in LEGACY_SEEDS:
			_legacy_cold_roundtrip(world_seed, expected[str(world_seed)])
		print("=== WORLD GENERATION %s checks=%d ===" % ["PASS" if failures == 0 else "FAIL", checks])
		quit(0 if failures == 0 else 1)
		return
	for world_seed in range(1, 2001):
		if versioned: load("res://scripts/ecology/biome_map.gd").call("configure", world_seed, 2)
		else: BiomeMap.configure(world_seed)
		for patch: Dictionary in BiomeMap.patches():
			var center: Vector2 = patch["center"]
			_check(center.x >= 11000.0 and center.y >= 11000.0 and center.x <= 789000.0 and center.y <= 789000.0, "anchor has world-boundary clearance seed=%d patch=%s" % [world_seed, patch["id"]])
			_check(BiomeMap.region_id_at(patch["center"]) == patch["id"], "center belongs seed=%d patch=%s" % [world_seed, patch["id"]])
		_check(BiomeMap.region_id_at(BiomeMap.spawn_pos()) == "p_0_0", "spawn belongs seed=%d" % world_seed)
		for terrain: String in WorldConfig.TERRAIN_BOSSES:
			var patch := BiomeMap.farthest_patch(terrain)
			_check(BiomeMap.region_id_at(patch["center"]) == patch["id"], "boss belongs seed=%d terrain=%s" % [world_seed, terrain])
		# 多种子实际初始化，额外纳入全部已知失配种子。
		if world_seed <= 24 or world_seed in [41, 93, 981, 997, 1670, 1999]:
			var sim := _sim()
			for inst: MonsterInstance in sim.instances.values():
				_check(BiomeMap.region_id_at(inst.spawn_pos) == inst.region_id, "member belongs seed=%d id=%d" % [world_seed, inst.id])
			for region: SimRegion in sim.regions.values():
				for species: SpeciesData in sim.species_list:
					if sim.habitat_match(species, region):
						_check(BiomeMap.region_id_at(sim.camp_pos(region, species)) == region.id, "camp belongs seed=%d region=%s" % [world_seed, region.id])
	# 同一种子跨代来回切换，全部派生缓存都必须识别版本。
	if versioned:
		for world_seed: int in LEGACY_SEEDS:
			load("res://scripts/ecology/biome_map.gd").call("configure", world_seed, 2)
			_fingerprints()
			load("res://scripts/ecology/biome_map.gd").call("configure", world_seed, 1)
			_check(_fingerprints() == expected[str(world_seed)], "same seed v2 to v1 restores all geometry %d" % world_seed)
			_legacy_cold_roundtrip(world_seed, expected[str(world_seed)])
	print("=== WORLD GENERATION %s checks=%d ===" % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)

func _sim() -> EcologySim:
	var regions: Array = []
	for data: Dictionary in WorldConfig.region_defs():
		var region := SimRegion.new()
		region.id = data["id"]
		region.center = data["center"]
		region.terrain = data["terrain"]
		region.size = data["size"]
		region.capacity = data["capacity"]
		region.threat = data["threat"]
		region.neighbor_ids.assign(data["neighbors"])
		regions.append(region)
	seed(42042)
	var sim := EcologySim.new()
	sim.setup(regions, SpeciesCatalog.build_all(), WorldConfig.initial_population(), WorldConfig.boss_anchors())
	return sim

func _fingerprints() -> Dictionary:
	ObstacleField.restore_destroyed([])
	CampaignLayout.set_open_gates([])
	var sim := _sim()
	var camps := []
	for region: SimRegion in sim.regions.values():
		for species: SpeciesData in sim.species_list:
			if sim.habitat_match(species, region): camps.append([region.id, species.species_name, sim.camp_pos(region, species)])
	var obstacles := []
	for patch: Dictionary in BiomeMap.patches():
		var center: Vector2 = patch["center"]
		for offset: Vector2 in [Vector2.ZERO, Vector2(450, 220), Vector2(900, 900), Vector2(-3200, 1600)]:
			var pos := center + offset
			var cell := Vector2i(floori(pos.x / 32), floori(pos.y / 32))
			obstacles.append([cell, ObstacleField.sample_cell(cell), ObstacleField.liquid_kind_at(pos)])
	var result := {"patches": _digest(BiomeMap.patches()), "camps": _digest(camps),
		"ecology": _digest(sim.to_dict()), "bosses": _digest(WorldConfig.boss_anchors()),
		"dungeons": _digest(ObstacleField.dungeons()), "landmarks": _digest(LandmarkRegistry.landmarks()),
		"checkpoints": _digest(WorldConfig.checkpoints()), "story_sites": _digest(CampaignLayout.sites()),
		"story_objects": _digest(CampaignLayout.objects()), "story_walls": _digest(CampaignLayout.obstacle_cells()),
		"obstacles": _digest(obstacles)}
	# 破坏层保存/恢复必须逐位保留已碎岩石。
	var rock := Vector2i((BiomeMap.spawn_pos() + Vector2(450,220)) / 32)
	ObstacleField.damage_cell(rock)
	ObstacleField.damage_cell(rock)
	var destroyed := ObstacleField.destroyed_list()
	ObstacleField.restore_destroyed(destroyed)
	result["destroyed"] = _digest([destroyed, ObstacleField.sample_cell(rock)])
	return result

## v19 缺代次旧档的独立进程读写：玩家、生态、破坏覆盖层与已付剧情进度不得漂移。
func _legacy_cold_roundtrip(world_seed: int, fingerprints: Dictionary) -> void:
	BiomeMap.configure(world_seed)
	ObstacleField.restore_destroyed([])
	var sim := _sim()
	var position := ObstacleField.nudge_free(BiomeMap.spawn_pos() + Vector2(0, 128), 12)
	var rock := Vector2i((BiomeMap.spawn_pos() + Vector2(450, 220)) / 32)
	ObstacleField.damage_cell(rock)
	ObstacleField.damage_cell(rock)
	var story := OutpostQuestData.create()
	story.evidence.patrol_read = true
	story.evidence.entrance_read = true
	story.receipts.investigation = {"paid":true, "status":"paid", "gold":6, "xp":8, "bonus":"", "legacy_reserved":false}
	story = OutpostQuestData.sanitize(story)
	var saved := {"version":19, "world_seed":world_seed, "gold":123,
		"player":{"position":[position.x,position.y], "hp":44, "mp":22},
		"ecology":sim.to_dict(), "outpost_quest":story, "destroyed":ObstacleField.destroyed_list(),
		"generation_test_expected":fingerprints}
	var path := "user://world_generation_%d_%d.json" % [OS.get_process_id(), world_seed]
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(saved))
	file.close()
	var old_path := OS.get_environment("HOTW_TEST_SAVE")
	OS.set_environment("HOTW_TEST_SAVE", ProjectSettings.globalize_path(path))
	var output: Array = []
	var code := OS.execute(OS.get_executable_path(), PackedStringArray([
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"-s", "tests/world_generation_test.gd", "--", "--legacy-reader"]), output, true)
	OS.set_environment("HOTW_TEST_SAVE", old_path)
	var log := "".join(output)
	print(log)
	_check(code == 0 and "WORLD_GENERATION_COLD_PASS" in log and not "SCRIPT ERROR" in log,
		"旧档独立进程保留全部坐标和剧情 %d" % world_seed)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".pre-equipment-v19.bak"))

func _legacy_reader() -> void:
	var gs := root.get_node("GameState")
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(gs.SAVE_PATH))
	_check(gs.world_generation == 1, "v19缺代次采用旧坐标")
	_check(gs.player_snapshot.position == raw.player.position, "冷读精确玩家坐标")
	_check(gs.destroyed_cells == raw.destroyed, "冷读精确已破坏格")
	_check(JSON.parse_string(JSON.stringify(gs.outpost_quest)) == raw.outpost_quest and gs.gold == 123, "冷读精确剧情证据和已付收据")
	BiomeMap.configure(gs.world_seed, gs.world_generation)
	_check(_fingerprints() == raw.generation_test_expected, "冷读保留旧版全部派生地理")
	gs.ecology_snapshot = raw.ecology
	gs.destroyed_cells.assign(raw.destroyed)
	root.get_node("WorldSim").set_process(false)
	paused = true
	var world = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(world)
	await process_frame
	_check(world.get_node("Player").global_position == Vector2(raw.player.position[0], raw.player.position[1]), "真实世界恢复无传送")
	_check(JSON.parse_string(JSON.stringify(world._sim.to_dict())) == raw.ecology, "真实世界旧生态逐项相同")
	_check(ObstacleField.destroyed_list() == raw.destroyed, "世界装配不重置破坏覆盖层")
	_check(JSON.parse_string(JSON.stringify(gs.outpost_quest)) == raw.outpost_quest, "世界装配不重置剧情进度")
	gs.save_enabled = true
	_check(gs.save_now(), "旧档迁移可完整保存")
	var written: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(gs.SAVE_PATH))
	_check(int(written.world_generation) == 1 and written.player.position == raw.player.position,
		"重存仍为旧坐标版本及原玩家位置")
	_check(written.outpost_quest == raw.outpost_quest and written.destroyed == raw.destroyed,
		"重存精确保留剧情和破坏层")
	gs.save_enabled = false
	world.queue_free()
	await process_frame
	paused = false
	await physics_frame
	await process_frame
	print("WORLD_GENERATION_COLD_%s checks=%d" % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)

func _digest(value: Variant) -> String:
	return var_to_str(value).sha256_text()

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL WORLD_GENERATION ", label)
