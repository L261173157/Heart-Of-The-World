## 真实世界装配回归：Boss 城塞锚点、已发现复活点、死亡窗口与冷读档。
extends Node

const MAIN := preload("res://scenes/main/main.tscn")
var _failures := 0
var _checks := 0
var _world: Node2D
var _player: Player
var _boss_events: Dictionary = {}
var _previous_boss_ids: Dictionary = {}


func _ready() -> void:
	GameState.save_enabled = false
	WorldSim.set_process(false)
	get_tree().paused = true
	if "--cold-reader" in OS.get_cmdline_user_args():
		_cold_read.call_deferred()
	else:
		_run.call_deferred()


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print("  %s %s" % ["PASS" if ok else "FAIL", label])


func _enter() -> void:
	_world = MAIN.instantiate()
	add_child(_world)
	_player = _world.get_node("Player")
	_boss_events.clear()
	_previous_boss_ids.clear()
	var sim: EcologySim = _world._sim
	sim.boss_respawned.connect(func(species_name: String) -> void:
		_boss_events[species_name] = int(_boss_events.get(species_name, 0)) + 1)
	for inst: MonsterInstance in sim.instances.values():
		if inst.species.is_boss:
			_previous_boss_ids[inst.species.species_name] = inst.id


func _leave() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_world.queue_free()
	await get_tree().process_frame
	get_tree().paused = false
	await get_tree().physics_frame
	await get_tree().process_frame
	get_tree().paused = true


func _run() -> void:
	GameState.SAVE_PATH = "user://gameplay_world_%d.json" % OS.get_process_id()
	GameState.reset_all()
	GameState.world_seed = BiomeMap.DEFAULT_SEED
	_enter()
	var all := WorldConfig.checkpoints()
	var dg: Dictionary = ObstacleField.dungeons()[0]
	var id: String = "fortress:" + dg["patch_id"]
	var checkpoint: Vector2 = all[id]["position"]
	var center: Vector2 = dg["center"]
	_check(not GameState.discovered_checkpoints.has(id), "新档不会解锁未到访城塞")
	_check(WorldConfig.nearest_checkpoint_respawn(center, GameState.discovered_checkpoints)
			== WorldConfig.spawn_pos(), "未知远方死亡仅使用已拥有的家园")
	_player.global_position = center
	_world._discover_nearby_checkpoints()
	_check(GameState.discovered_checkpoints.has(id), "真实世界发现扫描解锁城塞入口")
	var count := GameState.discovered_checkpoints.size()
	_world._discover_nearby_checkpoints()
	_check(GameState.discovered_checkpoints.size() == count, "重复发现不重复追加检查点")
	_check(checkpoint.distance_to(center) <= 600.0 and checkpoint.distance_to(center) > 250.0,
			"城塞检查点在南门外且距挑战不足四秒基础步行")
	_check(not ObstacleField.blocks(checkpoint, 12.0)
			and ObstacleField.liquid_kind_at(checkpoint) == "", "城塞复活点无墙无岩浆")
	_player._is_dead = true
	var snapshot: Dictionary = _player.save_snapshot()
	_check(Vector2(snapshot["position"][0], snapshot["position"][1]) == checkpoint,
			"死亡期间保存使用已发现的最近检查点")
	_player._respawn()
	_check(_player.global_position == checkpoint and not _player._is_dead
			and _player.current_hp == GameState.stats.max_hp(), "真实复活回入口并恢复战斗状态")
	# 所有生成种子的点位都要能站立，非法/旧世界 id 不能授予位置。
	for item_id: String in all:
		var p: Vector2 = all[item_id]["position"]
		_check(not ObstacleField.blocks(p, 12.0) and ObstacleField.liquid_kind_at(p) == "",
				"检查点可站立：" + item_id)
	_check(not GameState.discover_checkpoint("fortress:does_not_exist"), "拒绝伪造检查点 id")
	_prepare_full_boss_homes()
	_player.global_position = checkpoint
	# 已发现 NPC 地标是旧档迁移的唯一营地凭据，不借用迷雾大格。
	var camp_lm := ""
	for lm: Dictionary in LandmarkRegistry.landmarks():
		if LandmarkRegistry.NPC_BY_KIND.has(lm["kind"]):
			camp_lm = lm["id"]
			break
	GameState.discovered_landmarks.append(camp_lm)
	_world._restore_discovered_checkpoints()
	_check(GameState.discovered_checkpoints.has("landmark:" + camp_lm), "旧档已发现营地迁移为检查点")
	GameState.save_enabled = true
	_check(GameState.save_now(), "真实存档写入检查点与角色位置")
	GameState.save_enabled = false
	await _leave()
	var output: Array = []
	var previous_save := OS.get_environment("HOTW_TEST_SAVE")
	OS.set_environment("HOTW_TEST_SAVE", ProjectSettings.globalize_path(GameState.SAVE_PATH))
	var exit_code := OS.execute(OS.get_executable_path(), PackedStringArray([
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"res://tests/gameplay_world_test.tscn", "--quit-after", "10000", "--", "--cold-reader"
	]), output, true)
	OS.set_environment("HOTW_TEST_SAVE", previous_save)
	var completed := false
	for entry: String in output:
		print(entry)
		completed = completed or "=== CHECKPOINT COLD READER PASS ===" in entry
	_check(exit_code == 0 and completed, "独立进程冷启动保留检查点、原地继续与再次死亡")
	GameState.discovered_checkpoints.clear()
	GameState._load()
	_check(not GameState.discovered_checkpoints.is_empty(), "重新读取真实保存文件")
	_check(GameState.discovered_checkpoints.has(id)
			and GameState.discovered_checkpoints.has("landmark:" + camp_lm), "检查点重新读档往返")
	_enter()
	_check(_player.global_position == checkpoint, "退出/继续保持复活点位置")
	_test_waiting_bosses_resume()
	_player.global_position = center
	_player._is_dead = true
	_player._respawn()
	_check(_player.global_position == checkpoint, "重复死亡仍回最近已发现入口")
	await _leave()
	GameState.reset_all()
	_check(GameState.discovered_checkpoints.is_empty(), "新冒险清除旧世界检查点")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.SAVE_PATH))
	print("=== 玩法世界回归%s（%d项，失败%d） ===" % ["全部通过" if _failures == 0 else "失败", _checks, _failures])
	get_tree().quit(0 if _failures == 0 else 1)


func _cold_read() -> void:
	_check(not GameState.discovered_checkpoints.is_empty(), "冷启动 autoload 读到已发现点")
	_enter()
	var dg: Dictionary = ObstacleField.dungeons()[0]
	var id: String = "fortress:" + dg["patch_id"]
	var checkpoint: Vector2 = WorldConfig.checkpoints()[id]["position"]
	_check(GameState.discovered_checkpoints.has(id) and _player.global_position == checkpoint,
			"新进程世界装配保持入口位置")
	_test_waiting_bosses_resume()
	_player.global_position = dg["center"]
	_player._is_dead = true
	_player._respawn()
	_check(_player.global_position == checkpoint, "新进程死亡选择原已发现入口")
	await _leave()
	if _failures == 0:
		print("=== CHECKPOINT COLD READER PASS ===")
	get_tree().quit(0 if _failures == 0 else 1)


## 只隔离本用例的容量变量；不改承载/锚点/重生流程，也不固定随机种子。
## .tres 会被 ResourceLoader 缓存，必须复制后改，避免污染随后真实重新装配。
func _isolate_boss_ticks(sim: EcologySim) -> void:
	sim.reintroduction_enabled = false
	sim.predation_enabled = false
	var isolated := {}
	for i in sim.species_list.size():
		var species: SpeciesData = sim.species_list[i].duplicate()
		species.breeding_rate = 0.0
		species.migrate_count = 0
		sim.species_list[i] = species
		isolated[species.species_name] = species
	for inst: MonsterInstance in sim.instances.values():
		inst.species = isolated[inst.species.species_name]
		inst.lifespan = maxi(inst.lifespan, inst.age + 100)  # 等待期间不由老死腾位


func _resident(sim: EcologySim, region_id: String) -> MonsterInstance:
	for inst: MonsterInstance in sim.instances.values():
		if inst.is_alive and inst.region_id == region_id and not inst.species.is_boss \
				and not inst.species.splits_on_death:
			return inst
	return null


func _boss_chest(species_name: String) -> Node:
	for dg: Dictionary in _world._dungeon_list():
		if WorldConfig.TERRAIN_BOSSES.get(dg["terrain"], "") == species_name:
			_player.global_position = dg["center"]
			_world._update_dungeons()
			return _world._chests[dg["patch_id"]]
	return null  # 森林 Boss 没有城塞宝箱


func _prepare_full_boss_homes() -> void:
	var sim: EcologySim = _world._sim
	_isolate_boss_ticks(sim)
	for species_name: String in WorldConfig.boss_anchors():
		var anchor: Dictionary = WorldConfig.boss_anchors()[species_name]
		var victim: MonsterInstance = sim.instances.get(_previous_boss_ids.get(species_name, -1))
		_check(victim != null and victim.is_alive and victim.region_id == anchor["region_id"]
				and victim.spawn_pos == anchor["position"], "初生 Boss 与家园同锚：" + species_name)
		if victim == null:
			continue
		sim.report_killed(victim.id)
		sim.boss_respawn_timers[species_name] = 0
		var home := sim.get_region(anchor["region_id"])
		var resident := _resident(sim, home.id)
		_check(resident != null, "据点有不分裂的容量占位种：" + species_name)
		if resident == null:
			continue
		# 原用例在此直接 tick：普通怪物可能先繁衍/迁入占满，Boss 合法等待。
		# 显式填满原配置容量，把这一分支变为必测条件，而非赌空位恰好留下。
		while sim.alive_count_in(home.id) < home.capacity:
			sim.spawn_instance(resident.species, home.id, resident.species.maturity_age,
					0, 1.0, false, resident.spawn_pos)
		var alternate_has_room := false
		for region: SimRegion in sim.regions.values():
			if region.id != home.id and sim.habitat_match(victim.species, region) \
					and sim.alive_count_in(region.id) < region.capacity:
				alternate_has_room = true
		_check(alternate_has_room, "其它适生区有空位仍必须原地等待：" + species_name)
		var chest := _boss_chest(species_name)
		if chest != null:
			GameState.add_item(chest.key_id, 1)
			chest.interact()
			_check(chest.taken and not chest.locked, "死亡窗口真实开箱：" + species_name)
	for _tick in 2:
		sim.tick()
		_assert_bosses_waiting()


func _assert_bosses_waiting() -> void:
	var sim: EcologySim = _world._sim
	for species_name: String in WorldConfig.boss_anchors():
		var anchor: Dictionary = WorldConfig.boss_anchors()[species_name]
		var home := sim.get_region(anchor["region_id"])
		_check(sim.alive_count_in(home.id) == home.capacity
				and sim.alive_count_of_species(species_name) == 0
				and int(sim.boss_respawn_timers.get(species_name, -1)) == 0
				and int(_boss_events.get(species_name, 0)) == 0,
				"满载等待不超容、不异地重生、不误发事件：" + species_name)
		var chest := _boss_chest(species_name)
		if chest != null:
			_check(chest.taken and not chest.locked, "等待/读档不重置已领取宝箱：" + species_name)


func _test_waiting_bosses_resume() -> void:
	var sim: EcologySim = _world._sim
	# 物种隔离参数不写入存档；冷进程和同进程继续均在真实装配后重建隔离。
	_isolate_boss_ticks(sim)
	_assert_bosses_waiting()
	sim.tick()
	_assert_bosses_waiting()
	for species_name: String in WorldConfig.boss_anchors():
		var anchor: Dictionary = WorldConfig.boss_anchors()[species_name]
		var home := sim.get_region(anchor["region_id"])
		var resident := _resident(sim, home.id)
		_check(resident != null, "读档后可释放一个占位名额：" + species_name)
		if resident == null:
			continue
		sim.report_killed(resident.id)
		_check(sim.alive_count_in(home.id) == home.capacity - 1, "真实击杀只释放一个名额：" + species_name)
		sim.tick()
		var reborn: MonsterInstance
		for inst: MonsterInstance in sim.instances.values():
			if inst.is_alive and inst.species.species_name == species_name:
				reborn = inst
		_check(reborn != null and reborn.id != _previous_boss_ids.get(species_name, -1)
				and sim.alive_count_of_species(species_name) == 1
				and reborn.region_id == home.id and reborn.spawn_pos == anchor["position"]
				and sim.alive_count_in(home.id) == home.capacity
				and int(sim.boss_respawn_timers[species_name]) == reborn.species.boss_respawn_ticks
				and int(_boss_events.get(species_name, 0)) == 1,
				"腾位当 tick 恰好一只新 Boss 同锚重生并重置周期：" + species_name)
		var chest := _boss_chest(species_name)
		if chest != null:
			_check(chest.locked and not chest.taken, "实际重生重新锁箱并开启新领取周期：" + species_name)
	sim.tick()
	for species_name: String in WorldConfig.boss_anchors():
		_check(sim.alive_count_of_species(species_name) == 1
				and int(_boss_events.get(species_name, 0)) == 1,
				"后续 tick 不重复出生/发重生事件：" + species_name)
