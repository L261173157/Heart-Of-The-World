## 真实世界/击杀/菜单继续/磁盘重读，覆盖本地赏金与显式任务追踪。
extends Node

var _checks := 0
var _fails := 0
var _last_bounty := ""
var _completed := 0
var _kill_gold_sample := -1
var _completion_gold := -1

# 独立常数期望：满额的 .5 向上/普通向下取整；耗尽先 floor 基数再乘词条。
const REWARD_CASES := [
	{"gold": 25, "bonus": false, "depleted": false, "paid": 25},
	{"gold": 25, "bonus": false, "depleted": true, "paid": 12},
	{"gold": 26, "bonus": true, "depleted": false, "paid": 33},
	{"gold": 25, "bonus": true, "depleted": false, "paid": 31},
	{"gold": 25, "bonus": true, "depleted": true, "paid": 15},
]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.save_enabled = false
	WorldSim.set_process(false)
	EventBus.bounty_updated.connect(func(text: String) -> void: _last_bounty = text)
	# 必须早于真实世界的 BountyManager 订阅：击杀金币已到账，赏金尚未发。
	EventBus.monster_killed_by_player.connect(func(_xp: int, _gold: int, _name: String, _species: String) -> void:
		_kill_gold_sample = GameState.gold)
	EventBus.bounty_completed.connect(func(_text: String) -> void:
		_completed += 1
		_completion_gold = GameState.gold)
	var args := OS.get_cmdline_user_args()
	if not args.is_empty() and args[0].begins_with("--reward-"):
		if OS.get_environment("HOTW_TEST_SAVE").is_empty() or args.size() != 3 \
				or args[0] not in ["--reward-settle", "--reward-verify"] \
				or not args[1].is_valid_int() or int(args[1]) < 0 or int(args[1]) >= REWARD_CASES.size():
			_check(false, "冷进程必须提供隔离 HOTW_TEST_SAVE 和合法案例编号")
			get_tree().quit(1)
			return
		_cold_reward.call_deferred(args[0], int(args[1]), int(args[2]))
	else:
		GameState.SAVE_PATH = "user://gameplay_tasks_%d.json" % OS.get_process_id()
		_run.call_deferred()


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])


func _frames(count: int = 2) -> void:
	for i in count:
		await get_tree().process_frame


func _bounty() -> BountyManager:
	for child: Node in get_tree().current_scene.get_children():
		if child is BountyManager:
			return child
	return null


func _quest(id: String, kind: String, need: int) -> Dictionary:
	return {"id": id, "landmark_id": id, "giver": "回归委托人", "kind": kind,
		"title": id, "progress": 0, "need": need, "gold": 10, "xp": 1}


func _run() -> void:
	GameState.reset_all()
	GameState.world_seed = 20260908
	BiomeMap.configure(GameState.world_seed)
	seed(123456)
	await _test_individual_reachability()
	# 将测试观察者留在根节点，真正调用换场景而非只手工重建 manager。
	get_tree().current_scene = null
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
	await _frames()
	get_tree().current_scene.get_node("MenuBox/StartBtn").pressed.emit()
	await _frames(3)
	var world := get_tree().current_scene
	_check(world.scene_file_path == "res://scenes/main/main.tscn", "真实开始按钮进入游戏世界")
	await get_tree().create_timer(1.2, true, false, true).timeout
	while _bounty()._rolling:
		await get_tree().process_frame
	_check(not GameState.bounty.is_empty(), "自动延迟发出附近可完成赏金")
	if GameState.bounty.is_empty():
		_finish()
		return
	var bounty := _bounty()
	print("  BOUNTY_ROUTE elapsed_ms=%.2f max_slice_ms=%.2f visits=%d" % [bounty._last_roll_msec, bounty._max_route_slice_msec, BountyManager.ROUTE_VISIT_LIMIT - bounty._route_visits_left])
	var player: Player = world.get_node("Player")
	var initial: Dictionary = GameState.bounty.duplicate(true)
	var origin := WorldSim.sim.region_of_point(player.global_position)
	_check(initial["region_id"] == origin.id, "出生赏金选择玩家本区而非全局随机物种")
	_check(int(initial["need"]) <= bounty._species_alive_count(), "发单目标不超过真实可战胜存量")
	var target: MonsterInstance
	for inst: MonsterInstance in WorldSim.sim.instances.values():
		if inst.is_alive and inst.species.species_name == initial["species"] and inst.region_id == initial["region_id"] \
				and inst.id in initial["target_ids"]:
			target = inst
			break
	_check(target != null and not target.species.is_boss and bounty._feasible(target), "自动目标有实体且难度符合当前战力")
	if target == null:
		_finish()
		return
	var far := target.spawn_pos + Vector2(BountyManager.LOCAL_RADIUS * 3.0, 0)
	var before_pos := player.position
	player.position = far
	var local_targets := await bounty._local_targets()
	_check(not local_targets.any(func(c: Dictionary) -> bool:
		return c["region_id"] == initial["region_id"] and c["species"] == initial["species"]),
		"离玩家过远的旧区据点不再作为新单候选")
	player.position = before_pos
	# 活体难度校验覆盖成年老怪，不以等级表硬编码推断必然能打。
	var aged := MonsterInstance.new()
	aged.species = target.species
	aged.age = 100000
	aged.threat_scale = 100.0
	_check(not bounty._feasible(aged), "超战力非Boss同样不发自动赏金")
	player.position = target.spawn_pos + Vector2(100, 0)
	world._stream_pass()
	await _frames()
	var body: MonsterBase
	for node: Node in get_tree().get_nodes_in_group("monsters"):
		if node is MonsterBase and node.inst.id == target.id:
			body = node
	_check(body != null, "走到悬赏据点后真实怪物节点流式生成")
	if body == null:
		_finish()
		return
	# 镜头和视线绑定真实已核验目标，避免抽中同物种但不在此单目标清单的个体。
	player.teleport_to(body.global_position + Vector2(24, 0))
	var camera: Camera2D = player.get_node("Camera2D")
	camera.reset_smoothing()
	camera.force_update_scroll()
	world._reveal_fog()
	var bounty_radar: Minimap = world.get_node("HUD/Root/Minimap")
	bounty_radar._refresh_navigation()
	_check(bounty_radar._target.is_empty() and bounty_radar._known_candidates().any(func(candidate: Dictionary) -> bool:
		return (candidate.get("kind", "") == "monster"
			and str(candidate["id"]).trim_prefix("monster:").to_int() in initial["target_ids"])),
		"已核验可达的赏金活体在当前地图可见，但无追踪选择时不擅自导航")
	body.take_damage(1000000.0, player.global_position)
	await _frames()
	_check(not target.is_alive and int(GameState.bounty.get("progress", 0)) == 1,
		"真实击杀链更新生态死亡与赏金1次进度")
	var partial: Dictionary = GameState.bounty.duplicate(true)
	var manager := get_tree().get_first_node_in_group("quest_manager") as QuestManager
	var explore := _quest("task_explore", "explore", 3)
	var ransack := _quest("task_ransack", "ransack", 2)
	manager.accept(explore)
	manager.accept(ransack)
	EventBus.quest_track_requested.emit(ransack["id"])
	_check(GameState.quests["active"].size() == 2 and GameState.tracked_quest_id == ransack["id"],
		"切换追踪保留全部任务，绝不隐式放弃")
	# 实际镜头靠近一个真实巢穴，不能把历史探索当作当前可见目标。
	player.position = WorldSim.sim.camp_pos(origin, target.species) + Vector2(40, 0)
	world._stream_pass()
	await _frames(2)
	camera.reset_smoothing()
	camera.force_update_scroll()
	world._reveal_fog()
	var radar: Minimap = world.get_node("HUD/Root/Minimap")
	radar._refresh_navigation()
	_check(radar._target.get("category", "") == "当前视野 · 委托"
		and radar._target.get("kind", "") == "nest" and radar._target.get("precise", false),
		"雷达仅精确追踪当前视野内所选第二项捣巢委托")
	EventBus.quest_track_requested.emit("no_such_task")
	_check(GameState.tracked_quest_id == ransack["id"], "不存在的追踪请求不破坏当前选择")
	GameState.save_enabled = true
	var hud := world.get_node("HUD")
	hud._toggle_pause()
	hud.get_node("Root/PauseLayer/PausePanel/Margin/VB/MenuBtn").pressed.emit()
	await _frames(3)
	_check(get_tree().current_scene.scene_file_path == "res://scenes/ui/main_menu.tscn" and WorldSim.sim == null,
		"真实暂停菜单按钮退出世界并停止生态")
	_check(GameState.bounty == partial, "回菜单保留赏金部分进度")
	get_tree().current_scene.get_node("MenuBox/StartBtn").pressed.emit()
	await _frames(3)
	_check(GameState.bounty == partial and GameState.tracked_quest_id == ransack["id"],
		"继续冒险复用同一赏金与选中委托，不重新抽单")
	world = get_tree().current_scene
	bounty = _bounty()
	_check(bounty._progress == 1 and not WorldSim.sim.instances[target.id].is_alive,
		"重建manager展示1次进度，已杀实体保持死亡")
	# 生态真实自然死亡：先剩1只，下调需求保留贡献；再耗尽，按1/原需求结算。
	var alive: Array[MonsterInstance] = []
	for inst: MonsterInstance in WorldSim.sim.instances.values():
		if inst.is_alive and inst.species.species_name == partial["species"] and inst.region_id == partial["region_id"]:
			alive.append(inst)
	_isolate_reward_ticks()
	for i in range(1, alive.size()):
		alive[i].age = alive[i].lifespan
	WorldSim.sim.tick()
	bounty._process(BountyManager.EXTINCT_CHECK_INTERVAL)
	_check(int(GameState.bounty.get("progress", 0)) == 1 and int(GameState.bounty.get("need", 0)) == 2,
		"真实生态减员保留已杀1只并把需求下调为2")
	_check(_last_bounty.contains("按量结算"), "目标减少时HUD公开说明按量结算")
	_check(GameState.save_now(), "调整后的任务状态真实写入磁盘")
	var adjusted: Dictionary = GameState.bounty.duplicate(true)
	hud = world.get_node("HUD")
	hud._toggle_pause()
	hud.get_node("Root/PauseLayer/PausePanel/Margin/VB/MenuBtn").pressed.emit()
	await _frames(3)
	GameState.bounty = {}
	GameState.tracked_quest_id = ""
	GameState._load()
	get_tree().current_scene.get_node("MenuBox/StartBtn").pressed.emit()
	await _frames(3)
	_check(GameState.bounty == adjusted and GameState.tracked_quest_id == ransack["id"],
		"清内存并从磁盘恢复保留调整基数与所选任务")
	var before_gold := GameState.gold
	var gold_multiplier := GameState.stats.gold_mult()
	_isolate_reward_ticks()
	for inst: MonsterInstance in WorldSim.sim.instances.values():
		if inst.is_alive and inst.species.species_name == partial["species"] and inst.region_id == partial["region_id"]:
			inst.age = inst.lifespan
	WorldSim.sim.tick()
	_bounty()._process(BountyManager.EXTINCT_CHECK_INTERVAL)
	# 奖励期望包含结算时实际已穿装备倍率；掉落只入包，不应改变它。
	var base_gold := floori(float(partial["original_gold"]) / int(partial["original_need"]))
	var expected_gold := roundi(base_gold * gold_multiplier)
	print("  BOUNTY_REWARD base=%d multiplier=%.6f actual=%d equips=%s" % [
		base_gold, gold_multiplier, GameState.gold - before_gold, GameState.stats.equips])
	_check(GameState.bounty.is_empty() and GameState.gold - before_gold == expected_gold and _completed == 1,
		"耗尽按已杀贡献结算一次，既不丢奖励也不发整单")
	_check(GameState.save_now(), "销单和奖励一同保存")
	_bounty()._reconcile()
	_bounty()._complete()
	_check(GameState.gold == before_gold + expected_gold and _completed == 1, "重复结算入口不重复奖励")
	EventBus.quest_abandon_requested.emit(explore["id"])
	_check(GameState.quests["active"].size() == 1 and GameState.tracked_quest_id == ransack["id"],
		"明确放弃指定未追踪任务，不误删首项以外的选择")
	EventBus.quest_abandon_requested.emit(ransack["id"])
	_check(GameState.quests["active"].is_empty() and GameState.tracked_quest_id == "", "最后一项放弃后清除追踪状态")
	# 寻路仍挂起时从真实暂停菜单卸载，旧协程不得在菜单或下一世界回写。
	var interrupted := _bounty()
	interrupted._roll_bounty()
	_check(interrupted._rolling, "自动发单确实进入分帧寻路而非同步卡住")
	hud = get_tree().current_scene.get_node("HUD")
	hud._toggle_pause()
	await _frames(3)
	_check(interrupted._rolling and GameState.bounty.is_empty(), "暂停时分帧发单不悄悄结算")
	hud.get_node("Root/PauseLayer/PausePanel/Margin/VB/MenuBtn").pressed.emit()
	await _frames(5)
	_check(GameState.bounty.is_empty() and WorldSim.sim == null, "退菜单取消旧世界寻路，不晚到写入赏金")
	get_tree().current_scene.get_node("MenuBox/StartBtn").pressed.emit()
	await _frames(4)
	_check(not is_instance_valid(interrupted) and _bounty() != null and not _bounty()._rolling,
		"继续冒险使用全新管理器，旧协程无悬空引用")
	_test_navigation_parity()
	_test_reward_matrix()
	_finish()


func _finish() -> void:
	GameState.save_enabled = false
	get_tree().paused = false
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.SAVE_PATH))
	print("=== GAMEPLAY TASKS %s (%d checks, %d failures) ===" % ["PASSED" if _fails == 0 else "FAILED", _checks, _fails])
	get_tree().quit(0 if _fails == 0 else 1)


## 单格分帧查询不能悄悄改变真正导航格，特别是深水洞边缘与破坏覆盖层。
func _test_navigation_parity() -> void:
	var centers: Array[Vector2] = [WorldConfig.spawn_pos(),
		WorldConfig.farthest_terrain_center("snow") + Vector2(2000, 2000),
		WorldConfig.farthest_terrain_center("hill") + Vector2(2000, 2000)]
	var parity := true
	var water_seen := false
	var destroyed_seen := false
	for center: Vector2 in centers:
		var chunk := Vector2i((center / 512.0).floor())
		ObstacleField._nav_chunk_cache.erase(chunk)
		var expected := PackedByteArray()
		for dy in ObstacleField.CHUNK_CELLS:
			for dx in ObstacleField.CHUNK_CELLS:
				var cell := chunk * ObstacleField.CHUNK_CELLS + Vector2i(dx, dy)
				expected.append(int(ObstacleField.nav_blocked_cell(cell)))
		_check(not ObstacleField._nav_chunk_cache.has(chunk), "单格查询没有暗中同步生成256格缓存")
		var actual := ObstacleField.nav_blocked_chunk(chunk * 512)
		parity = parity and actual == expected
	_check(parity, "单格导航与分块缓存768个未缓存格完全一致")
	# 稀疏障碍/水湖不保证落在小窗口；固定种子跨斑块取样直到两类实际命中。
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260909
	for i in 6000:
		if destroyed_seen and water_seen:
			break
		var terrain := "snow" if i % 2 == 0 else "hill"
		var patches := BiomeMap.patches_of_terrain(terrain)
		var center: Vector2 = patches[rng.randi() % patches.size()]["center"]
		var pos := (center + Vector2(rng.randf_range(-30000, 30000), rng.randf_range(-30000, 30000))).clamp(
			Vector2(1000, 1000), BiomeMap.WORLD_SIZE - Vector2(1000, 1000))
		var cell := Vector2i((pos / ObstacleField.CELL).floor())
		var sample := ObstacleField.sample_cell(cell)
		if not destroyed_seen and not sample.is_empty() and sample["kind"] in ObstacleField.DESTRUCTIBLE:
			ObstacleField.damage_cell(cell)
			ObstacleField.damage_cell(cell)
			_check(ObstacleField.nav_blocked_cell(cell) == ObstacleField.nav_blocked_at(pos),
				"破坏覆盖层下单格与分块导航一致")
			destroyed_seen = true
		if water_seen or not ObstacleField._water_at_cell(cell):
			continue
		water_seen = true
		for offset: Vector2i in [Vector2i.ZERO, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var position := (Vector2(cell + offset) + Vector2(0.5, 0.5)) * ObstacleField.CELL
			ObstacleField._nav_chunk_cache.erase(Vector2i((position / 512.0).floor()))
			_check(ObstacleField.nav_blocked_cell(cell + offset) == ObstacleField.nav_blocked_at(position),
				"深水核/邻格缓冲导航口径一致")
	_check(destroyed_seen, "导航等价回归确实覆盖可破坏障碍")
	_check(water_seen, "导航等价回归确实覆盖深水")


## 同物种至少3只的门槛必须逐只可达：不可把最近2只替第3只背书。
func _test_individual_reachability() -> void:
	var species: SpeciesData
	for candidate: SpeciesData in SpeciesCatalog.build_all():
		if candidate.species_name == "火把哥布林":
			species = candidate
	var start := WorldConfig.spawn_pos()
	var blocked := Vector2.INF
	for i in range(40, 180):
		var cell := Vector2i((start / ObstacleField.CELL).floor()) + Vector2i(i, i / 2)
		if ObstacleField.nav_blocked_cell(cell):
			blocked = (Vector2(cell) + Vector2(0.5, 0.5)) * ObstacleField.CELL
			break
	_check(blocked.is_finite(), "个体可达性夹具找到真实阻挡格")
	if not blocked.is_finite():
		return
	var region := SimRegion.new()
	region.id = "bounty_reachable_test"
	region.center = start
	region.size = Vector2(20000, 20000)
	region.terrain = "plains"
	region.capacity = 20
	var sim := EcologySim.new()
	sim.setup([region], [species], {})
	WorldSim.start(sim)
	var player := Node2D.new()
	player.position = start
	player.add_to_group("player")
	add_child(player)
	var manager := BountyManager.new()
	manager.set_process(false)
	add_child(manager)
	sim.spawn_instance(species, region.id, 10, 0, 1.0, false, start + Vector2(100, 0))
	sim.spawn_instance(species, region.id, 10, 0, 1.0, false, start + Vector2(140, 0))
	var unreachable := sim.spawn_instance(species, region.id, 10, 0, 1.0, false, blocked)
	var targets := await manager._local_targets()
	_check(targets.is_empty(), "2只可达加1只真实阻挡目标不能凑成3只可行库存")
	var valid := sim.spawn_instance(species, region.id, 10, 0, 1.0, false, start + Vector2(180, 0))
	targets = await manager._local_targets()
	_check(targets.size() == 1 and int(targets[0]["count"]) == 3
		and not unreachable.id in targets[0]["target_ids"] and valid.id in targets[0]["target_ids"],
		"同组第4只可达后才发3只任务，逐只验证并排除不可达ID")
	manager._route_connected.clear()
	manager._route_blocked.clear()
	manager._route_visits_left = 3
	manager._route_slice_started = Time.get_ticks_usec()
	var reached := await manager._route_exists(start, start + Vector2(500, 0))
	_check(not reached and manager._route_visits_left == 0 and manager._route_connected.size() <= 3,
		"无法在预算内完成的搜索确实停止，不突破整次发单共享预算")
	manager.free()
	player.free()
	WorldSim.stop()


## 物种资源必须复制；真实重装配/冷启动再隔离，不污染 ResourceLoader 缓存。
func _isolate_reward_ticks() -> void:
	var sim := WorldSim.sim
	sim.predation_enabled = false
	sim.reintroduction_enabled = false
	var isolated := {}
	for i in sim.species_list.size():
		var species: SpeciesData = sim.species_list[i].duplicate()
		species.breeding_rate = 0.0
		species.migrate_count = 0
		sim.species_list[i] = species
		isolated[species.species_name] = species
	for inst: MonsterInstance in sim.instances.values():
		inst.species = isolated[inst.species.species_name]


## 原真实流程保留随机掉落；专项矩阵显式装配六槽，让无/有加成每次都被执行。
func _reward_equipment(bonus: bool) -> Dictionary:
	var result := {}
	for slot: String in GameState.EQUIP_SLOTS:
		var affixes := {"hp": 0.01}
		if bonus and slot == "weapon":
			affixes = {"gold": 0.15}
		elif bonus and slot == "boots":
			affixes = {"gold": 0.10}
		result[slot] = EquipmentCatalog.legacy_item({"slot": slot, "name": "赏金回归" + slot, "rarity": 1, "affixes": affixes, "locked": true}, "bounty:" + slot, slot)
	return result


func _test_reward_matrix() -> void:
	GameState.save_enabled = false
	GameState.equipment_state = EquipmentInventory.empty_state()
	GameState._sync_equipped_stats()
	GameState.stats.passives.clear()
	# 固定世界中寻找仍存活的普通据点；不硬编码随机实体 ID。
	var groups := {}
	for inst: MonsterInstance in WorldSim.sim.instances.values():
		if not inst.is_alive or inst.species.splits_on_death or not _bounty()._feasible(inst):
			continue
		var key := inst.region_id + "|" + inst.species.species_name
		if not groups.has(key):
			groups[key] = []
		groups[key].append(inst.id)
	var ids: Array = []
	for group: Array in groups.values():
		if group.size() >= 3:
			ids = group.slice(0, 3)
			break
	_check(ids.size() == 3, "受控奖励有三只真实可战胜且不分裂的剩余目标")
	if ids.is_empty():
		return
	var target: MonsterInstance = WorldSim.sim.instances[ids[0]]
	for index in REWARD_CASES.size():
		var test: Dictionary = REWARD_CASES[index]
		GameState.equipment_state = EquipmentInventory.empty_state()
		GameState._sync_equipped_stats()
		# 奖励矩阵使用公开纯工厂构造有效装配；不靠随机掉落或更改实时战斗门槛。
		for item: Dictionary in _reward_equipment(test["bonus"]).values():
			var added := EquipmentInventory.add_item(GameState.equipment_state, item)
			var context := {"gold": GameState.gold, "materials": GameState.inventory, "level": GameState.stats.level, "can_swap": true}
			var offer := EquipmentInventory.preview(added["state"], "equip", {"id": item["id"]}, context)
			var committed := EquipmentInventory.commit(added["state"], offer, context)
			_check(committed.get("ok", false), "受控奖励装备原子装配：%d/%s" % [index, item["slot"]])
			if committed.get("ok", false): GameState.equipment_state = committed["state"]
		GameState._sync_equipped_stats()
		GameState.gold = 100
		GameState.bounty = {"species": target.species.species_name, "region_id": target.region_id,
			"need": 4, "progress": 1 if test["depleted"] else 3, "gold": test["gold"], "xp": 1,
			"original_need": 4, "original_gold": test["gold"], "original_xp": 1,
			"adjusted": false, "target_ids": ids.duplicate()}
		GameState.save_enabled = true
		_check(GameState.save_now(), "未结算赏金/装备/生态真实保存：%d" % index)
		GameState.save_enabled = false
		var settled_gold := _run_reward_process("--reward-settle", index)
		_run_reward_process("--reward-verify", index, settled_gold)
		# 子进程改的是磁盘；父进程的活体/未结算任务不变，下一案例重新写档。


func _run_reward_process(phase: String, index: int, expected_gold: int = -1) -> int:
	var output: Array = []
	var previous_save := OS.get_environment("HOTW_TEST_SAVE")
	OS.set_environment("HOTW_TEST_SAVE", ProjectSettings.globalize_path(GameState.SAVE_PATH))
	var exit_code := OS.execute(OS.get_executable_path(), PackedStringArray([
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"res://tests/gameplay_tasks_test.tscn", "--quit-after", "10000", "--", phase, str(index), str(expected_gold)
	]), output, true)
	OS.set_environment("HOTW_TEST_SAVE", previous_save)
	var marker := "=== BOUNTY COLD %s %d PASS ===" % [phase, index]
	var completed := false
	var settled_gold := -1
	for entry: String in output:
		print(entry)
		completed = completed or marker in entry
		for line: String in entry.split("\n"):
			if line.begins_with("BOUNTY_COLD_BALANCE="):
				settled_gold = line.trim_prefix("BOUNTY_COLD_BALANCE=").to_int()
	_check(exit_code == 0 and completed and settled_gold >= 100, "独立冷进程完成 %s/%d" % [phase, index])
	return settled_gold


func _cold_reward(phase: String, index: int, expected_gold: int) -> void:
	get_tree().paused = true
	var test: Dictionary = REWARD_CASES[index]
	var saved_gold := GameState.gold
	var saved_bounty := GameState.bounty.duplicate(true)
	var expected_equips := _reward_equipment(test["bonus"])
	_check(_same_reward_equips(GameState.stats.equips, expected_equips)
			and is_equal_approx(GameState.stats.gold_mult(), 1.25 if test["bonus"] else 1.0),
			"冷读档保持受控装备与明确金币倍率")
	for slot: String in GameState.EQUIP_SLOTS:
		_check(GameState.is_equipment_locked(slot), "冷读档保留装备保护：" + slot)
	get_tree().current_scene = null
	var world := preload("res://scenes/main/main.tscn").instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	_isolate_reward_ticks()
	if phase == "--reward-settle":
		_check(saved_gold == 100 and saved_bounty.get("need", 0) == 4
				and saved_bounty.get("progress", 0) == (1 if test["depleted"] else 3)
				and saved_bounty.get("original_gold", 0) == test["gold"]
				and saved_bounty.get("target_ids", []).size() == 3
				and GameState.bounty == saved_bounty and _completed == 0,
				"冷装配保留未完成进度/基数/目标，不提前结算")
		if GameState.bounty.is_empty():
			_cold_reward_finish(phase, index)
			return
		var target: MonsterInstance = WorldSim.sim.instances[int(saved_bounty["target_ids"][0])]
		var player: Player = world.get_node("Player")
		player.global_position = target.spawn_pos + Vector2(100, 0)
		world._stream_pass()
		await _frames()  # 流式节点通过 call_deferred 挂入真实场景
		var body: MonsterBase
		for node: Node in get_tree().get_nodes_in_group("monsters"):
			if node is MonsterBase and node.inst.id == target.id:
				body = node
		_check(body != null and target.is_alive, "冷读档目标真实流式生成并可击杀")
		if body == null:
			_cold_reward_finish(phase, index)
			return
		body.take_damage(1000000.0, player.global_position)
		_check(not target.is_alive and _kill_gold_sample >= saved_gold, "真实击杀与赏金前金币采样都已发生")
		var payout_before := _kill_gold_sample
		if test["depleted"]:
			_check(GameState.bounty.get("progress", 0) == 2 and _completed == 0,
					"耗尽案例真实击杀增加贡献，仍不提前发奖")
			payout_before = GameState.gold
			for id: int in saved_bounty["target_ids"]:
				var inst: MonsterInstance = WorldSim.sim.instances[id]
				if inst.is_alive:
					inst.age = inst.lifespan
			WorldSim.sim.tick()
			_bounty()._process(BountyManager.EXTINCT_CHECK_INTERVAL)
		_check(GameState.bounty.is_empty() and _completed == 1
				and _completion_gold - payout_before == int(test["paid"]),
				"受控满额/耗尽奖励符合独立常数且只完成一次：%d" % index)
		_check(_same_reward_equips(GameState.stats.equips, expected_equips), "随机掉装不改变本次受控金币装备")
	else:
		_check(saved_bounty.is_empty() and GameState.bounty.is_empty()
				and _completed == 0 and GameState.gold == saved_gold and saved_gold == expected_gold,
				"再次冷装配保持销单与余额，未重复领奖")
	var settled_gold := GameState.gold
	var completed := _completed
	for _repeat in 3:
		_bounty()._reconcile()
		_bounty()._complete()
		_bounty()._on_kill(0, 0, "重复事件", str(saved_bounty.get("species", "")))
	_check(GameState.bounty.is_empty() and GameState.gold == settled_gold and _completed == completed,
			"重复结算及迟到击杀事件不重发金币/完成事件")
	GameState.save_enabled = true
	_check(GameState.save_now(), "销单与准确余额一起落盘")
	GameState.save_enabled = false
	_cold_reward_finish(phase, index)


func _cold_reward_finish(phase: String, index: int) -> void:
	print("BOUNTY_COLD_BALANCE=%d" % GameState.gold)
	print("=== BOUNTY COLD %s %d %s ===" % [phase, index, "PASS" if _fails == 0 else "FAIL"])
	get_tree().quit(0 if _fails == 0 else 1)


func _same_reward_equips(actual: Dictionary, expected: Dictionary) -> bool:
	if actual.size() != expected.size(): return false
	for slot: String in expected:
		if not actual.has(slot): return false
		for key: String in ["id", "name", "slot", "locked", "rarity"]:
			if actual[slot].get(key) != expected[slot].get(key): return false
		if actual[slot].get("affixes", {}).size() != expected[slot]["affixes"].size(): return false
		for affix: String in expected[slot]["affixes"]:
			if not is_equal_approx(float(actual[slot].get("affixes", {}).get(affix, -1)), float(expected[slot]["affixes"][affix])): return false
	return true
