## 真实世界/击杀/菜单继续/磁盘重读，覆盖本地赏金与显式任务追踪。
extends Node

var _checks := 0
var _fails := 0
var _last_bounty := ""
var _completed := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.save_enabled = false
	GameState.SAVE_PATH = "user://gameplay_tasks_%d.json" % OS.get_process_id()
	WorldSim.set_process(false)
	EventBus.bounty_updated.connect(func(text: String) -> void: _last_bounty = text)
	EventBus.bounty_completed.connect(func(_text: String) -> void: _completed += 1)
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
		if inst.is_alive and inst.species.species_name == initial["species"] and inst.region_id == initial["region_id"]:
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
	world._reveal_fog()
	var bounty_radar: Minimap = world.get_node("HUD/Root/Minimap")
	bounty_radar._refresh_navigation()
	_check(bounty_radar._target.get("category", "") == "赏金目标"
		and str(bounty_radar._target.get("id", "")).trim_prefix("monster:").to_int() in initial["target_ids"],
		"真实赏金在揭示迷雾后导航到已核验可达的活目标")
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
	world._reveal_fog()
	var radar: Minimap = world.get_node("HUD/Root/Minimap")
	radar._refresh_navigation()
	_check(radar._target.get("category", "") == "委托 · 捣巢", "雷达追踪选中的第二项委托")
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
	WorldSim.sim.predation_enabled = false
	WorldSim.sim.reintroduction_enabled = false
	for species: SpeciesData in WorldSim.sim.species_list:
		species.breeding_rate = 0.0
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
	for inst: MonsterInstance in WorldSim.sim.instances.values():
		if inst.is_alive and inst.species.species_name == partial["species"] and inst.region_id == partial["region_id"]:
			inst.age = inst.lifespan
	WorldSim.sim.tick()
	_bounty()._process(BountyManager.EXTINCT_CHECK_INTERVAL)
	var expected_gold := floori(float(partial["original_gold"]) / int(partial["original_need"]))
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
	_finish()


func _finish() -> void:
	GameState.save_enabled = false
	get_tree().paused = false
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.SAVE_PATH))
	if _fails == 0:
		print("=== GAMEPLAY TASKS PASSED (%d checks) ===" % _checks)
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
