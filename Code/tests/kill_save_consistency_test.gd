## 击杀事务：真实受击→奖励→自然防抖落盘→独立进程恢复，不伪造存档计时。
extends Node

var _checks := 0
var _fails := 0
var _world: Node
var _player: Player
var _reentrant_body: MonsterBase
var _reentrant_bytes := PackedByteArray()
var _reentrant_seen := false
var _nested_body: MonsterBase
var _nested_started := false
var _nested_peak := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.save_enabled = false
	WorldSim.set_process(false)
	get_tree().paused = true
	if "--cold-reader" in OS.get_cmdline_user_args():
		_cold_read.call_deferred()
	else:
		_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok: _fails += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])

func _frames(count := 3) -> void:
	for _i in count: await get_tree().process_frame

func _spawn_world() -> void:
	_world = preload("res://scenes/main/main.tscn").instantiate()
	add_child(_world)
	_player = _world.get_node("Player")

func _target() -> MonsterBase:
	for inst: MonsterInstance in WorldSim.sim.instances.values():
		if inst.is_alive and not inst.is_elite and not inst.species.is_boss and not inst.species.splits_on_death:
			_player.global_position = inst.spawn_pos + Vector2(80, 0)
			_world._stream_pass()
			await _frames()
			for body: Node in get_tree().get_nodes_in_group("monsters"):
				if body is MonsterBase and body.inst.id == inst.id:
					return body
	return null

func _saved_entry(data: Dictionary, id: int) -> Dictionary:
	for entry: Dictionary in data["ecology"]["instances"]:
		if int(entry["id"]) == id: return entry
	return {}

func _read_save() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(GameState.SAVE_PATH))

func _run() -> void:
	GameState.reset_all()
	GameState.world_seed = 20260908
	_spawn_world()
	await _frames()
	GameState.bounty = {}
	GameState.quests["active"] = []
	var body := await _target()
	_check(body != null, "真实世界流式生成普通目标")
	if body == null:
		_finish()
		return
	GameState.save_enabled = true
	_check(GameState.save_now(), "先保存活目标以预热六秒生态缓存")
	var before_gold := GameState.gold
	var before_xp := GameState.stats.xp
	var expected_gold := before_gold + EconomyMath.kill_gold(body.inst)
	var expected_xp := before_xp + body.inst.xp_reward()
	var id := body.inst.id
	seed(42) # 普通目标无装备掉落，不能靠候选装备的失效路径掩盖击杀问题。
	body.take_damage(1000000.0, _player.global_position)
	_check(not body.inst.is_alive and GameState.gold == expected_gold and GameState.stats.xp == expected_xp,
		"真实击杀发放一次金币经验并记录死亡")
	_check(GameState.pending_equipment.is_empty() and GameState.stats.equips.is_empty(), "隔离无装备掉落路径")
	_check(GameState._ecology_cache == null, "完整击杀后旧活目标缓存失效")
	await get_tree().create_timer(2.2, true, false, true).timeout
	var saved := _read_save()
	_check(not _saved_entry(saved, id).get("alive", true) and int(saved["gold"]) == expected_gold
		and int(saved["xp"]) == expected_xp, "自然二秒自动保存中死亡与奖励一致")
	_check(Time.get_unix_time_from_system() - GameState._ecology_saved_at < 1.0,
		"自动保存确实重建生态快照，未复用六秒缓存")
	var file := FileAccess.open(GameState.SAVE_PATH + ".expected", FileAccess.WRITE)
	file.store_string(JSON.stringify({"id": id, "gold": expected_gold, "xp": expected_xp}))
	file.close()
	var output: Array = []
	var code := OS.execute(OS.get_executable_path(), PackedStringArray([
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"res://tests/kill_save_consistency_test.tscn", "--quit-after", "10000", "--", "--cold-reader"
	]), output, true)
	var completed := false
	for entry: String in output:
		print(entry)
		completed = completed or "KILL SAVE COLD PASS" in entry
	_check(code == 0 and completed, "自动档独立冷进程恢复不复活已领奖目标")
	# 奖励信号内的即时保存/重复伤害是重入控制；任何半笔结算都不能落盘。
	_reentrant_body = await _target()
	_check(_reentrant_body != null, "第二个真实目标可测试同步重入")
	if _reentrant_body != null:
		GameState.save_now()
		_reentrant_bytes = FileAccess.get_file_as_bytes(GameState.SAVE_PATH)
		var kills := GameState.session_kills
		EventBus.monster_killed_by_player.connect(_during_reward)
		seed(42)
		_reentrant_body.take_damage(1000000.0, _player.global_position)
		EventBus.monster_killed_by_player.disconnect(_during_reward)
		_check(_reentrant_seen and GameState.session_kills == kills + 1, "奖励回调重入伤害不会重复发奖")
		saved = _read_save()
		_check(not _saved_entry(saved, _reentrant_body.inst.id).get("alive", true)
			and int(saved["gold"]) == GameState.gold and int(saved["xp"]) == GameState.stats.xp,
			"回调中的保存要求在完整死亡后提交全部奖励")
	await _test_nested_and_split()
	GameState._notification(NOTIFICATION_APPLICATION_PAUSED)
	_check(not _saved_entry(_read_save(), id).get("alive", true), "后台全量保存继续保持死亡")
	GameState.save_enabled = false
	DirAccess.remove_absolute(GameState.SAVE_PATH + ".expected")
	_finish()

func _test_nested_and_split() -> void:
	var region := WorldSim.sim.region_of_point(_player.global_position)
	var splitter := WorldSim.sim.spawn_instance(load("res://data/species/slime.tres"), region.id,
		20, 0, 1.0, false, _player.global_position + Vector2(50, 0))
	var nested := WorldSim.sim.spawn_instance(load("res://data/species/goblin.tres"), region.id,
		20, 0, 1.0, false, _player.global_position + Vector2(-50, 0))
	await _frames()
	var outer: MonsterBase = _world._nodes.get(splitter.id)
	_nested_body = _world._nodes.get(nested.id)
	_check(outer != null and _nested_body != null, "真实世界生成分裂父体与嵌套击杀目标")
	if outer == null or _nested_body == null: return
	var before_ids := WorldSim.sim.instances.keys()
	var kills := GameState.session_kills
	GameState.save_now()
	EventBus.monster_killed_by_player.connect(_nested_reward)
	WorldSim.sim.instance_died.connect(_during_sim_death)
	outer.take_damage(1000000.0, _player.global_position)
	EventBus.monster_killed_by_player.disconnect(_nested_reward)
	WorldSim.sim.instance_died.disconnect(_during_sim_death)
	_check(_nested_peak == 2 and _reward_depth() == 0
		and GameState.session_kills == kills + 2, "不同目标嵌套结算深度2正确回零且各奖一次")
	var saved := _read_save()
	_check(not _saved_entry(saved, splitter.id).get("alive", true)
		and not _saved_entry(saved, nested.id).get("alive", true), "嵌套外层最终保存含两只目标死亡")
	var children: Array = []
	for child: MonsterInstance in WorldSim.sim.instances.values():
		if child.id not in before_ids and child.species == splitter.species:
			children.append(child.id)
			_check(_saved_entry(saved, child.id).get("alive", false), "死亡信号请求的保存包含之后才生成的分裂子代")
	_check(children.size() == splitter.species.split_count, "容量充足时实际分裂出完整子代")
	_check(_same_data(saved.get("inventory", {}), GameState.inventory) and _same_data(saved.get("codex", {}), GameState.codex)
		and int(saved["gold"]) == GameState.gold and int(saved["xp"]) == GameState.stats.xp,
		"最终快照同时含两笔材料/图鉴/金币/经验")
	var file := FileAccess.open(GameState.SAVE_PATH + ".expected", FileAccess.WRITE)
	file.store_string(JSON.stringify({"id": splitter.id, "gold": GameState.gold, "xp": GameState.stats.xp,
		"dead_ids": [splitter.id, nested.id], "child_ids": children,
		"inventory": GameState.inventory, "codex": GameState.codex}))
	file.close()
	var output: Array = []
	var code := OS.execute(OS.get_executable_path(), PackedStringArray([
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"res://tests/kill_save_consistency_test.tscn", "--quit-after", "10000", "--", "--cold-reader"
	]), output, true)
	var completed := false
	for entry: String in output:
		print(entry)
		completed = completed or "KILL SAVE COLD PASS" in entry
	_check(code == 0 and completed, "分裂及嵌套奖励通过独立冷进程恢复")

func _reward_depth() -> int:
	var depth: Variant = GameState.get("_world_reward_depth")
	return int(depth) if typeof(depth) == TYPE_INT else 0

func _nested_reward(_xp: int, _gold: int, _display: String, _species: String) -> void:
	_nested_peak = maxi(_nested_peak, _reward_depth())
	if not _nested_started:
		_nested_started = true
		_nested_body.take_damage(1000000.0, _player.global_position)
		_check(not GameState.save_now(true), "外层全量保存请求延至完整分裂结束")
	else:
		_check(not GameState.save_now(false), "内层降频保存请求也不能提前提交")

func _during_sim_death(_inst: MonsterInstance, _cause: String) -> void:
	_check(not GameState.save_now(true), "模拟死亡信号中保存延至后续分裂完成")

func _during_reward(_xp: int, _gold: int, _display: String, _species: String) -> void:
	if _reentrant_seen: return
	_reentrant_seen = true
	_check(not GameState.save_now(false), "事务中尚未落盘，立即保存不能声称成功")
	_check(FileAccess.get_file_as_bytes(GameState.SAVE_PATH) == _reentrant_bytes, "事务未结束时不写入半笔存档")
	_reentrant_body.take_damage(1000000.0, _player.global_position)

func _cold_read() -> void:
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GameState.SAVE_PATH + ".expected"))
	_check(GameState.gold == int(expected.gold) and GameState.stats.xp == int(expected.xp), "冷进程加载已获奖励")
	_spawn_world()
	await _frames()
	var id := int(expected.id)
	_check(WorldSim.sim.instances.has(id) and not WorldSim.sim.instances[id].is_alive,
		"冷进程实际世界保持目标死亡")
	for dead_id: Variant in expected.get("dead_ids", []):
		_check(WorldSim.sim.instances.has(int(dead_id)) and not WorldSim.sim.instances[int(dead_id)].is_alive,
			"冷进程嵌套目标保持死亡")
	for child_id: Variant in expected.get("child_ids", []):
		_check(WorldSim.sim.instances.has(int(child_id)) and WorldSim.sim.instances[int(child_id)].is_alive,
			"冷进程分裂子代保持存活")
	if expected.has("inventory"):
		_check(_same_data(GameState.inventory, expected.inventory) and _same_data(GameState.codex, expected.codex),
			"冷进程保留分裂/嵌套材料和图鉴")
	print("KILL SAVE COLD %s" % ("PASS" if _fails == 0 else "FAIL"))
	_finish()

func _finish() -> void:
	GameState.save_enabled = false
	print("=== KILL SAVE CONSISTENCY %s (%d checks) ===" % ["PASS" if _fails == 0 else "FAIL", _checks])
	get_tree().quit(0 if _fails == 0 else 1)


func _same_data(actual: Variant, expected: Variant) -> bool:
	if typeof(actual) in [TYPE_INT, TYPE_FLOAT] and typeof(expected) in [TYPE_INT, TYPE_FLOAT]:
		return is_equal_approx(float(actual), float(expected))
	if typeof(actual) != typeof(expected):
		return false
	if typeof(actual) == TYPE_ARRAY:
		if actual.size() != expected.size():
			return false
		for i in actual.size():
			if not _same_data(actual[i], expected[i]):
				return false
		return true
	if typeof(actual) == TYPE_DICTIONARY:
		if actual.size() != expected.size():
			return false
		for key: Variant in actual:
			if not expected.has(key) or not _same_data(actual[key], expected[key]):
				return false
		return true
	return actual == expected
