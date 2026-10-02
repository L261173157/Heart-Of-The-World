## 玩法生态回归：固定城主据点/满载重生/旧档修复、可完成的本地委托与库存同步。
extends Node

var _fails := 0
var _checks := 0
var _manager: QuestManager
var _last_hud := ""


func _ready() -> void:
	WorldSim.set_process(false)
	GameState.save_enabled = false
	GameState.SAVE_PATH = "user://gameplay_ecology_test_%d.json" % OS.get_process_id()
	EventBus.quest_updated.connect(func(text: String) -> void: _last_hud = text)
	_run.call_deferred()


func _run() -> void:
	seed(20261001)
	_test_boss_fortress_anchors()
	_test_boss_capacity_and_legacy_restore()
	_test_local_hunt_and_three_survivors()
	_test_hunt_depletion_and_reload()
	_test_hunt_migration_and_waiting()
	_test_collect_inventory_reconciliation()
	_reset()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.SAVE_PATH))
	if _fails == 0:
		print("=== 玩法生态回归全部通过（%d 项） ===" % _checks)
	else:
		print("=== 玩法生态回归失败 %d/%d ===" % [_fails, _checks])
	get_tree().quit(0 if _fails == 0 else 1)


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])


func _reset() -> void:
	if is_instance_valid(_manager):
		_manager.free()
	_manager = null
	WorldSim.stop()
	GameState.save_enabled = false
	GameState.reset_all()
	_last_hud = ""


func _species(names: Array) -> Array[SpeciesData]:
	var out: Array[SpeciesData] = []
	for source: SpeciesData in SpeciesCatalog.build_all():
		if source.species_name in names:
			var species: SpeciesData = source.duplicate(true)
			species.breeding_rate = 0.0
			species.migrate_count = 0
			species.prey = []
			species.lifespan_min = 100000
			species.lifespan_max = 100000
			out.append(species)
	return out


func _region(id: String, terrain: String, center: Vector2, capacity := 20) -> SimRegion:
	var region := SimRegion.new()
	region.id = id
	region.display_name = "测试区" + id
	region.terrain = terrain
	region.center = center
	region.size = Vector2(8000, 8000)
	region.capacity = capacity
	return region


func _find_alive(sim: EcologySim, species_name: String) -> MonsterInstance:
	for inst: MonsterInstance in sim.instances.values():
		if inst.is_alive and inst.species.species_name == species_name:
			return inst
	return null


func _world_regions() -> Array:
	var out: Array = []
	for def: Dictionary in WorldConfig.region_defs():
		var region := _region(def["id"], def["terrain"], def["center"], def["capacity"])
		region.size = def["size"]
		region.threat = def["threat"]
		region.neighbor_ids.assign(def["neighbors"])
		out.append(region)
	return out


func _fortress_anchors() -> Dictionary:
	var anchors := {}
	for dungeon: Dictionary in ObstacleField.dungeons():
		anchors[WorldConfig.TERRAIN_BOSSES[dungeon["terrain"]]] = {
			"region_id": dungeon["patch_id"], "position": dungeon["center"]}
	var forest := BiomeMap.farthest_patch("forest")
	anchors["巨魔王"] = {"region_id": forest["id"], "position": forest["center"]}
	return anchors


func _test_boss_fortress_anchors() -> void:
	_reset()
	for world_seed: int in [BiomeMap.DEFAULT_SEED, 777777, 42]:
		BiomeMap.configure(world_seed)
		var anchors := WorldConfig.boss_anchors()
		_check(anchors == _fortress_anchors(), "种子 %d：世界 Boss 配置与障碍城塞真源一致" % world_seed)
		var sim := EcologySim.new()
		sim.predation_enabled = false
		sim.reintroduction_enabled = false
		var names: Array = []
		for source: SpeciesData in SpeciesCatalog.build_all():
			names.append(source.species_name)
		var species := _species(names)
		sim.setup(_world_regions(), species, WorldConfig.initial_population(), anchors)
		for name: String in anchors:
			var boss := _find_alive(sim, name)
			_check(boss != null and boss.region_id == anchors[name]["region_id"]
					and boss.spawn_pos == anchors[name]["position"],
					"种子 %d：%s 初生与城塞同址" % [world_seed, name])
			var respawns := [0]
			sim.boss_respawned.connect(func(_name: String) -> void: respawns[0] += 1, CONNECT_ONE_SHOT)
			sim.report_killed(boss.id)
			sim.boss_respawn_timers[name] = 1
			sim.tick()
			boss = _find_alive(sim, name)
			_check(boss != null and boss.region_id == anchors[name]["region_id"]
					and boss.spawn_pos == anchors[name]["position"] and respawns[0] == 1,
					"种子 %d：%s 真实 tick 重生仍在城塞且仅发一次轮次信号" % [world_seed, name])


func _test_boss_capacity_and_legacy_restore() -> void:
	_reset()
	var elsewhere := _region("elsewhere", "lava", Vector2(10000, 10000), 5)
	var fortress := _region("fortress", "lava", Vector2(100000, 100000), 1)
	var species := _species(["熔岩龟王", "黑曜牛卫"])
	var sim := EcologySim.new()
	var anchors := {"熔岩龟王": {"region_id": fortress.id, "position": fortress.center}}
	sim.setup([elsewhere, fortress], species, {"fortress": {"熔岩龟王": 1}}, anchors)
	var king := sim.find_species("熔岩龟王")
	var boss := _find_alive(sim, king.species_name)
	sim.report_killed(boss.id)
	var blocker := sim.spawn_instance(sim.find_species("黑曜牛卫"), fortress.id, 50, 0, 1.0, false, fortress.center)
	sim.boss_respawn_timers[king.species_name] = 1
	var respawns := [0]
	sim.boss_respawned.connect(func(_name: String) -> void: respawns[0] += 1)
	for tick in 3:
		sim.tick()
	_check(sim.alive_count_of_species(king.species_name) == 0 and respawns[0] == 0
			and sim.boss_respawn_timers[king.species_name] == 0,
			"据点满载持续保持到期计时，不去空闲异区重生")
	sim.report_killed(blocker.id)
	sim.tick()
	boss = _find_alive(sim, king.species_name)
	_check(boss != null and boss.region_id == fortress.id and respawns[0] == 1,
			"据点空出后下一 tick 就重生，不重新等完整倒计时")
	# 构造真实旧版快照：Boss 在远处，且无新增据点元数据。
	sim.report_hp(boss.id, 17.0)
	var data := sim.to_dict()
	data.erase("boss_anchors")
	for entry: Dictionary in data["instances"]:
		if int(entry["id"]) == boss.id:
			entry["region"] = elsewhere.id
			entry["spawn_pos"] = [elsewhere.center.x, elsewhere.center.y]
	var restored := EcologySim.new()
	var replay_regions: Array = []
	restored.instance_spawned.connect(func(inst: MonsterInstance) -> void:
		if inst.is_alive and inst.species.is_boss:
			replay_regions.append(inst.region_id))
	_check(restored.restore_from_dict([elsewhere, fortress], species, data, anchors), "旧版异地 Boss 快照可恢复")
	var repaired: MonsterInstance = restored.instances[boss.id]
	_check(repaired.region_id == fortress.id and repaired.spawn_pos == fortress.center
			and repaired.hp_mirror == 17.0 and repaired.age == boss.age
			and repaired.threat_scale == boss.threat_scale and replay_regions == [fortress.id],
			"旧版活 Boss 在重放前归位，保留 ID/血量/年龄/威胁")
	data["instances"].append({"id": 999, "species": "黑曜牛卫", "region": fortress.id,
		"alive": true, "age": 50, "lifespan": 100000, "spawn_pos": [100000, 100000]})
	var crowded := EcologySim.new()
	crowded.restore_from_dict([elsewhere, fortress], species, data, anchors)
	_check(crowded.instances[boss.id].region_id == elsewhere.id
			and crowded.alive_count_in(fortress.id) == fortress.capacity, "满载旧档修复保留活体且不超承载")
	var migrations := [0]
	crowded.instance_migrated.connect(func(_inst: MonsterInstance, _region_id: String) -> void: migrations[0] += 1)
	crowded.report_killed(999)
	crowded.tick()
	_check(crowded.instances[boss.id].region_id == fortress.id and migrations[0] == 1,
			"满载修复在腾位后通过生态权威归位并通知表现层")
	var encoded: Dictionary = JSON.parse_string(JSON.stringify(crowded.to_dict()))
	var roundtrip := EcologySim.new()
	roundtrip.restore_from_dict([elsewhere, fortress], species, encoded)
	_check(roundtrip.boss_anchor(king.species_name)["region_id"] == fortress.id,
			"JSON 往返保留固定据点，合成世界无额外装配也不漂移")


func _quest_world(local_count: int = 3, neighbor_count: int = 0, remote_count: int = 10) -> EcologySim:
	_reset()
	var local := _region("local", "plains", Vector2(10000, 10000))
	var neighbor := _region("neighbor", "forest", Vector2(30000, 10000))
	var remote := _region("remote", "forest", Vector2(500000, 500000))
	local.neighbor_ids = [neighbor.id]
	neighbor.neighbor_ids = [local.id]
	var sim := EcologySim.new()
	sim.predation_enabled = false
	sim.reintroduction_enabled = false
	sim.setup([local, neighbor, remote], _species(["火把哥布林", "弹弓地精"]),
		{"local": {"火把哥布林": local_count}, "neighbor": {"弹弓地精": neighbor_count},
		"remote": {"弹弓地精": remote_count}})
	WorldSim.start(sim)
	_manager = QuestManager.new()
	add_child(_manager)
	return sim


func _kill(sim: EcologySim, name: String) -> void:
	var inst := _find_alive(sim, name)
	sim.report_killed(inst.id)
	EventBus.monster_killed_by_player.emit(0, 0, name, name)


func _test_local_hunt_and_three_survivors() -> void:
	var sim := _quest_world()
	var quest := _manager._gen_quest("test_hunter", "hunt", "营地猎人")
	_check(quest.get("species", "") == "火把哥布林" and int(quest.get("need", 0)) == 3
			and quest.get("hunt_region", "") == "local", "本区仅 3 只时发 3 只任务，优先本区而非远处 10 只")
	_manager.accept(quest)
	_check(_last_hud.contains("测试区local") and _last_hud.contains("0/3"), "HUD 显示本地目标与真实需求")
	for n in 3:
		_kill(sim, "火把哥布林")
	_check(GameState.quests["active"].is_empty() and GameState.quests["completed"].get("test_hunter", 0) == 1
			and sim.player_extinct.has("火把哥布林"), "杀完仅存 3 只真实触发永久灭绝，委托仍完整结算")
	_quest_world(0, 3)
	quest = _manager._gen_quest("test_hunter", "hunt", "营地猎人")
	_check(quest.get("hunt_region", "") == "neighbor", "本区无健康种群时优先邻区")
	_quest_world(0, 0)
	_check(_manager._gen_quest("test_hunter", "hunt", "营地猎人").is_empty(), "远处未探索存量不生成远征烂单")
	for inst: MonsterInstance in WorldSim.sim.instances.values():
		if inst.is_alive:
			var cell := Vector2i(inst.spawn_pos / WorldConfig.WORLD_SIZE * GameState.FOG_GRID)
			GameState.fog_reveal_cell(cell.x, cell.y)
	quest = _manager._gen_quest("test_hunter", "hunt", "营地猎人")
	_check(quest.get("hunt_region", "") == "remote", "本区/邻区无目标时允许已探索据点")


func _test_hunt_depletion_and_reload() -> void:
	var sim := _quest_world(3, 0, 0)
	var quest := _manager._gen_quest("test_hunter", "hunt", "营地猎人")
	_manager.accept(quest)
	_kill(sim, "火把哥布林")
	var natural := _find_alive(sim, "火把哥布林")
	natural.age = natural.lifespan  # 实际 tick 的自然老死，不伪发任务信号
	sim.tick()
	_check(quest["progress"] == 1 and quest["need"] == 2
			and quest["gold"] == floori(float(quest["hunt_original_gold"]) * 2.0 / 3.0)
			and _last_hud.contains("数量调整") and _last_hud.contains("1/2"),
			"自然减员下调剩余需求，保留击杀进度并按原单缩放奖励/HUD")
	GameState.save_enabled = true
	_check(GameState.save_now(), "调整中委托可保存")
	GameState.save_enabled = false
	_manager.free()
	_manager = null
	GameState.quests = {"active": [], "completed": {}}
	GameState._load()
	_manager = QuestManager.new()
	add_child(_manager)
	quest = GameState.quests["active"][0]
	_check(quest["progress"] == 1 and quest["need"] == 2 and quest["hunt_original_need"] == 3,
			"真实存档读回保留部分进度与原始报酬基数，不重复缩奖")
	var before_gold := GameState.gold
	var remaining := _find_alive(sim, "火把哥布林")
	remaining.age = remaining.lifespan
	sim.tick()
	_check(GameState.quests["active"].is_empty() and GameState.gold - before_gold
			== floori(float(quest["hunt_original_gold"]) / 3.0), "剩余目标自然灭绝时按已击杀 1/3 结算，不丢部分进度、不付整单")
	_manager.free()
	_manager = null
	GameState.quests = {"active": [{"id": "legacy", "landmark_id": "legacy_npc", "giver": "猎人",
		"kind": "hunt", "species": "火把哥布林", "title": "旧委托", "progress": 3,
		"need": 4, "gold": 100, "xp": 40}], "completed": {}}
	before_gold = GameState.gold
	_manager = QuestManager.new()
	add_child(_manager)
	_check(GameState.quests["active"].is_empty() and GameState.gold - before_gold == 75,
			"旧档 3/4 永久缺目标委托 ready 后按已完成部分结算")


func _test_hunt_migration_and_waiting() -> void:
	var sim := _quest_world(3, 0, 0)
	var quest := _manager._gen_quest("test_hunter", "hunt", "营地猎人")
	var old := _find_alive(sim, "火把哥布林")
	old.age = old.lifespan
	sim.tick()
	_manager.accept(quest)
	_check(quest["need"] == 2 and quest["progress"] == 0, "确认接单时重新核验气泡期间的种群变化")
	_kill(sim, "火把哥布林")
	var species := sim.find_species("火把哥布林")
	species.habitats = ["plains", "forest"]
	species.migrate_count = 1
	species.expansion_threshold = 0
	sim.get_region("neighbor").neighbor_ids = []  # 防合成阈值 0 在同 tick 往返
	sim.tick()
	_check(quest["progress"] == 1 and quest["need"] == 2 and quest["hunt_region"] == "neighbor",
			"真实迁徙到邻区后更新目标位置并保留 1/2 进度")
	_kill(sim, "火把哥布林")
	_check(GameState.quests["active"].is_empty(), "迁入邻区的目标仍可击杀完成")
	# 无已计击杀不白领奖励；明确等待，后来可行目标出现自动换单。
	sim = _quest_world(3, 0, 0)
	quest = _manager._gen_quest("test_hunter", "hunt", "营地猎人")
	_manager.accept(quest)
	for inst: MonsterInstance in sim.instances.values():
		if inst.is_alive:
			inst.age = inst.lifespan
	sim.tick()
	_check(GameState.quests["active"].size() == 1 and quest.get("hunt_waiting", false)
			and _last_hud.contains("等待本地目标") and GameState.gold == 0, "零进度无候选时清楚显示等待，不虚结算")
	for n in 3:
		sim.spawn_instance(sim.find_species("弹弓地精"), "neighbor", 50, 0, 1.0, false, Vector2(30000, 10000))
	sim.tick()
	_check(quest["species"] == "弹弓地精" and not quest["hunt_waiting"] and quest["progress"] == 0,
			"可行邻区种群出现后自动替换等待中的空目标")


func _collect(id: String, item: String, need: int, progress := 0) -> Dictionary:
	return {"id": id, "landmark_id": id, "giver": "采集者", "kind": "collect",
		"title": "收集测试", "item": item, "need": need, "progress": progress, "gold": 10, "xp": 5}


func _test_collect_inventory_reconciliation() -> void:
	_quest_world()
	var earlier := _collect("pending_five", "fish", 5)
	var later := _collect("pending_three", "fish", 3)
	_manager.accept(earlier)
	_manager.accept(later)
	GameState.add_item("fish", 4)
	_check(GameState.count_item("fish") == 1 and earlier["progress"] == 1
			and _last_hud.contains("1/5") and GameState.quests["active"].size() == 1
			and GameState.quests["completed"].get("pending_three", 0) == 1,
			"两个空库存委托 5/3 同收 4 条鱼：后一单交付后前一单立即回到 1/5")
	_quest_world()
	GameState.add_item("fish", 2)
	var quest := _collect("fish_a", "fish", 5)
	_manager.accept(quest)
	_check(quest["progress"] == 2, "接取 collect 读取已有 2/5 库存")
	GameState.sell_material("fish")
	_check(quest["progress"] == 0 and _last_hud.contains("0/5"), "售出整叠材料同步回退 collect 进度与 HUD")
	GameState.add_item("fish", 4)
	var second := _collect("fish_b", "fish", 3)
	_manager.accept(second)
	_check(GameState.count_item("fish") == 1 and quest["progress"] == 1
			and GameState.quests["completed"].get("fish_b", 0) == 1,
			"另一 collect 交付扣料立即更新剩余任务，不递归多扣/重复奖励")
	_manager.free()
	_manager = null
	quest["progress"] = 4
	GameState.save_enabled = true
	_check(GameState.save_now(), "collect 脏进度夹具写入隔离存档")
	GameState.save_enabled = false
	GameState.quests = {"active": [], "completed": {}}
	GameState._load()
	quest = GameState.quests["active"][0]
	_manager = QuestManager.new()
	add_child(_manager)
	_check(quest["progress"] == 1 and _last_hud.contains("1/5"), "继续冒险时 collect 脏进度按真实库存重算")
	GameState.add_item("fish", 4)
	_check(GameState.count_item("fish") == 0 and GameState.quests["active"].is_empty()
			and GameState.quests["completed"].get("fish_a", 0) == 1,
			"材料补足后只交付一次，inventory_changed 重入不重复完成")
