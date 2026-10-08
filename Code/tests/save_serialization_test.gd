## 存档编码缓存回归与同快照性能探针：只经既有同步存档事务落盘。
## 基准可单独运行：场景后加 -- --benchmark-only；可用 HOTW_SAVE_PERF_FIXTURES
## 指向同一隔离目录，在修改前后复用完全相同的 fresh/aged JSON 快照。
extends Node

const SAMPLES := 31
var _fails := 0


class CountingSim extends EcologySim:
	var captures := 0

	func to_dict() -> Dictionary:
		captures += 1
		return super.to_dict()


class PairProbe extends Node:
	var allow_cache := true
	var refreshed := false
	var paired_tick := -1

	func can_reuse_ecology_cache(_cached_tick: int) -> bool:
		return allow_cache

	func campaign_for_save(copy: Dictionary, ecology_tick: int, was_refreshed: bool) -> Dictionary:
		refreshed = was_refreshed
		paired_tick = ecology_tick
		copy["encoding_probe_tick"] = ecology_tick
		return copy


func _ready() -> void:
	GameState.save_enabled = false
	WorldSim.set_process(false)
	GameState.set_process(false)
	GameState.SAVE_PATH = "user://save_serialization_test.json"
	_run.call_deferred()


func _run() -> void:
	if "--benchmark" in OS.get_cmdline_user_args() or "--benchmark-only" in OS.get_cmdline_user_args():
		_benchmark()
	if not "--benchmark-only" in OS.get_cmdline_user_args():
		_test_cache_contract()
	GameState.save_enabled = false
	WorldSim.stop()
	DirAccess.remove_absolute(GameState.SAVE_PATH)
	print("=== SAVE SERIALIZATION %s ===" % ("PASS" if _fails == 0 else "FAIL"))
	get_tree().quit(0 if _fails == 0 else 1)


func _regions() -> Array:
	var regions: Array = []
	for definition: Dictionary in WorldConfig.region_defs():
		var region := SimRegion.new()
		region.id = definition["id"]
		region.display_name = definition["name"]
		region.terrain = definition["terrain"]
		region.threat = definition["threat"]
		region.center = definition["center"]
		region.size = definition["size"]
		region.capacity = definition["capacity"]
		for neighbor: String in definition["neighbors"]:
			region.neighbor_ids.append(neighbor)
		regions.append(region)
	return regions


func _benchmark() -> void:
	seed(20261008)
	BiomeMap.configure(BiomeMap.DEFAULT_SEED)
	ObstacleField.restore_destroyed([])
	var sim := EcologySim.new()
	sim.setup(_regions(), SpeciesCatalog.build_all(), WorldConfig.initial_population())
	var fixture_dir := OS.get_environment("HOTW_SAVE_PERF_FIXTURES")
	for label: String in ["fresh", "aged"]:
		var fixture_path := fixture_dir.path_join(label + ".json") if not fixture_dir.is_empty() else ""
		var snapshot: Dictionary
		if not fixture_path.is_empty() and FileAccess.file_exists(fixture_path):
			snapshot = JSON.parse_string(FileAccess.get_file_as_string(fixture_path))
		else:
			if label == "aged":
				for _tick in 600:
					sim.tick()
			snapshot = sim.to_dict()
			if not fixture_path.is_empty():
				var fixture := FileAccess.open(fixture_path, FileAccess.WRITE)
				fixture.store_string(JSON.stringify(snapshot))
				fixture.close()
		var restored := EcologySim.new()
		_check(restored.restore_from_dict(_regions(), SpeciesCatalog.build_all(), snapshot), label + " 基准快照恢复")
		WorldSim.start(restored)
		GameState.reset_all()
		GameState.world_seed = BiomeMap.DEFAULT_SEED
		BiomeMap.configure(GameState.world_seed)
		GameState.save_enabled = true
		_check(GameState.save_now(), label + " 预热完整存档")
		var full: Array[int] = []
		var cached: Array[int] = []
		for _sample in SAMPLES:
			var before := Time.get_ticks_usec()
			var ok := GameState.save_now()
			full.append(Time.get_ticks_usec() - before)
			_check(ok, "完整存档成功", false)
			before = Time.get_ticks_usec()
			ok = GameState.save_now(false)
			cached.append(Time.get_ticks_usec() - before)
			_check(ok, "缓存存档成功", false)
		var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GameState.SAVE_PATH))
		_check(_same_data(saved["ecology"], GameState._ecology_cache), label + " 完整与缓存存档语义一致")
		print("SAVE_BENCH %s tick=%d instances=%d bytes=%d fixture_sha256=%s full=%s cached=%s" % [label,
			restored.tick_count, restored.instances.size(), FileAccess.get_file_as_bytes(GameState.SAVE_PATH).size(),
			FileAccess.get_sha256(fixture_path) if not fixture_path.is_empty() else "generated", _timings(full), _timings(cached)])
		GameState.save_enabled = false
		WorldSim.stop()


func _timings(samples: Array[int]) -> String:
	samples.sort()
	return "p50=%.3fms,p95=%.3fms,max=%.3fms" % [samples[SAMPLES / 2] / 1000.0,
		samples[ceili(SAMPLES * 0.95) - 1] / 1000.0, samples[-1] / 1000.0]


func _test_cache_contract() -> void:
	GameState.save_enabled = false
	GameState.reset_all()
	GameState.world_seed = BiomeMap.DEFAULT_SEED
	BiomeMap.configure(GameState.world_seed)
	var sim := CountingSim.new()
	sim.setup(_regions(), SpeciesCatalog.build_all(), WorldConfig.initial_population())
	WorldSim.start(sim)
	var pair := PairProbe.new()
	add_child(pair)
	pair.add_to_group("campaign_dynamic")
	GameState.equipment_migration_notice = "引号 \" 反斜线 \\ 换行\n },\"ecology\":null 中文🌲"
	GameState.save_enabled = true
	_check(GameState.save_now() and sim.captures == 1, "完整保存同步捕获并编码世界")
	var original_encoding: PackedByteArray = GameState.get("_ecology_json")
	_check(not original_encoding.is_empty(), "生态编码缓存已生成")
	sim.tick()
	WorldSim.resume_clock(0.68, 7)
	GameState.gold = 123
	_check(GameState.save_now(false) and sim.captures == 1, "准许的自动档复用已有快照及编码")
	var data := _read_save()
	_check(int(data["gold"]) == 123 and int(data["ecology"]["tick"]) == 0,
		"角色进度保持最新，生态沿用原有六秒缓存语义")
	_check(GameState.get("_ecology_json") == original_encoding and not pair.refreshed
		and int(data["campaign_quest"]["encoding_probe_tick"]) == 0, "缓存世界与战役配对仍用同一 tick")
	_check(data["equipment_migration_notice"] == GameState.equipment_migration_notice, "中文、Unicode、引号与 JSON 形状字符串完整转义")
	_check(GameState.save_now() and sim.captures == 2, "手动保存始终刷新，不复用旧字节")
	data = _read_save()
	_check(int(data["ecology"]["tick"]) == 1 and is_equal_approx(data["ecology"]["day_time"], 0.68)
		and int(data["ecology"]["game_day"]) == 7, "完整保存含最新生态与昼夜时钟")
	sim.tick()
	GameState._ecology_saved_at -= GameState.ECOLOGY_SAVE_INTERVAL
	_check(GameState.save_now(false) and sim.captures == 3 and pair.refreshed,
		"六秒到期的自动档重新捕获及编码")
	pair.allow_cache = false
	sim.tick()
	_check(GameState.save_now(false) and sim.captures == 4 and pair.paired_tick == 3,
		"战役一致性拒绝缓存时强制刷新生态编码")
	pair.allow_cache = true
	var before_reward := FileAccess.get_file_as_bytes(GameState.SAVE_PATH)
	GameState.begin_world_reward()
	GameState.gold += 50
	var victim_id: int = sim.instances.keys()[0]
	sim.report_killed(victim_id)
	_check(not GameState.save_now(false) and FileAccess.get_file_as_bytes(GameState.SAVE_PATH) == before_reward,
		"同步奖励中途请求不能写出半笔事务")
	GameState.end_world_reward()
	data = _read_save()
	_check(sim.captures == 5 and int(data["gold"]) == 173 and not _saved_alive(data, victim_id),
		"奖励事务末尾同步落盘最新金币及死亡，不复用活目标编码")
	GameState.mark_chest_taken("serialization_probe")
	_check((GameState.get("_ecology_json") as PackedByteArray).is_empty(), "宝箱改变同时清除快照编码")
	_check(GameState.save_now(false) and sim.captures == 6 and _read_save()["chest_claims"].has("serialization_probe"),
		"宝箱与生态缓存失效后同步写入")
	GameState.reset_chest_claim("serialization_probe")
	_check((GameState.get("_ecology_json") as PackedByteArray).is_empty(), "Boss 周期重置清除生态编码")
	_check(GameState.save_now(false) and sim.captures == 7, "Boss 新周期重新捕获")
	# 重复失败不刷新成功时间、不碰旧好档；恢复后仍正确写出新增世界事实。
	var good_bytes := FileAccess.get_file_as_bytes(GameState.SAVE_PATH)
	var good_time := GameState.last_save_unix
	var temporary := ProjectSettings.globalize_path(GameState.SAVE_PATH + ".tmp")
	_check(DirAccess.make_dir_absolute(temporary) == OK, "构造临时档打开失败")
	for _retry in 2:
		GameState.gold += 1
		_check(not GameState.save_now(false) and GameState.last_save_unix == good_time
			and FileAccess.get_file_as_bytes(GameState.SAVE_PATH) == good_bytes and GameState._save_timer > 0.0,
			"缓存自动档重复失败保留好档与重试")
	sim.tick()
	GameState.mark_chest_taken("after_failure")
	DirAccess.remove_absolute(temporary)
	_check(GameState.save_now(false) and sim.captures == 8 and int(_read_save()["ecology"]["tick"]) == sim.tick_count,
		"写入恢复后提交新世界，不遗留失败前的旧编码")
	# 菜单快照有外部持有者，同对象原地修改或换对象都必须重新编码。
	GameState.ecology_snapshot = sim.to_dict()
	WorldSim.stop()
	pair.remove_from_group("campaign_dynamic")
	pair.queue_free()
	GameState.ecology_snapshot["tick"] = 10001
	_check(GameState.save_now(false) and int(_read_save()["ecology"]["tick"]) == 10001,
		"菜单转存不误用刚离开的运行态编码")
	GameState.ecology_snapshot["tick"] = 10002
	GameState.ecology_snapshot["instances"][0]["age"] = 12345
	_check(GameState.save_now(false) and int(_read_save()["ecology"]["tick"]) == 10002
		and int(_read_save()["ecology"]["instances"][0]["age"]) == 12345, "菜单快照原地及嵌套修改立即保存")
	GameState.ecology_snapshot = {"tick": 10003, "instances": [], "text": "新的🌲世界"}
	_check(GameState.save_now(false) and _same_data(_read_save()["ecology"], GameState.ecology_snapshot),
		"菜单替换快照对象也重新编码")
	GameState._load()
	_check(GameState._ecology_cache == null and (GameState.get("_ecology_json") as PackedByteArray).is_empty(),
		"重新读档清除两层缓存")
	_check(GameState.save_now(false) and int(_read_save()["ecology"]["tick"]) == 10003,
		"冷菜单读档后保存保留完整生态")
	GameState.save_enabled = false
	GameState.reset_all()
	_check((GameState.get("_ecology_json") as PackedByteArray).is_empty(), "新冒险清除生态编码")
	GameState.save_enabled = true
	_check(GameState.save_now() and not _read_save().has("ecology"), "无世界的新档不带旧 ecology 字节")
	GameState.save_enabled = false


func _read_save() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(GameState.SAVE_PATH))


func _saved_alive(data: Dictionary, id: int) -> bool:
	for entry: Dictionary in data["ecology"]["instances"]:
		if int(entry["id"]) == id:
			return entry["alive"]
	return true


func _check(ok: bool, label: String, announce := true) -> void:
	if not ok:
		_fails += 1
	if announce or not ok:
		print("  %s  %s" % ["PASS" if ok else "FAIL", label])


## JSON 数字读回都是浮点；递归比较值，不把 int/float 容器类型差异当作丢档。
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
