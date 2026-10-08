## 生态扩张索引差分：按实例插入序保持候选、随机调用与信号可见结果。
## 可选 HOTW_ECOLOGY_BASELINE 指向 git show <修复前提交>:Code/scripts/ecology/ecology_sim.gd
## 导出的原始脚本；默认把当前脚本中的增量更新替换为旧版批次置脏，便于 CI 常驻。
extends SceneTree

var _failures := 0
var _checks := 0
var _optimized: GDScript
var _reference: GDScript
var _events := 0
var _migrations := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/ecology/ecology_sim.gd")
	var baseline_path := OS.get_environment("HOTW_ECOLOGY_BASELINE")
	var baseline := FileAccess.get_file_as_string(baseline_path) if baseline_path != "" else source
	if baseline_path == "":
		# 精确恢复修复前的批次失效点，其余逻辑共享，以免复制整份生态代码。
		var marker := "_index_migration_batch(region.id, species.species_name, movable, moved, index_revision)"
		if baseline.count(marker) != 1:
			printerr("FAIL ECOLOGY_INDEX 旧版失效点未唯一匹配，须更新差分基线")
			quit(1)
			return
		baseline = baseline.replace(marker, "_index_dirty = true")
	_optimized = _instrument(source)
	_reference = _instrument(baseline)
	if _optimized == null or _reference == null:
		quit(1)
		return
	print("ECOLOGY_INDEX_REFERENCE ", baseline_path if baseline_path != "" else "legacy migration invalidation")
	for rng_seed in [7, 1987, 8675309]:
		_compare_fixture(rng_seed, false, false)
		_compare_fixture(rng_seed, true, false)
		_compare_fixture(rng_seed, true, true)
	for world_seed in [BiomeMap.DEFAULT_SEED, 41, 90210]:
		_compare_world(world_seed)
	print("=== ECOLOGY INDEX %s checks=%d signals=%d migrations=%d ===" % [
		"PASS" if _failures == 0 else "FAIL", _checks, _events, _migrations])
	quit(0 if _failures == 0 else 1)


## 包裹原有全局 RNG 函数，不换算法；shuffle 仍调用 Godot 原方法。
## 比较每类随机调用数、shuffle 长度及其后连续输出，守住消耗量与后续 RNG 状态。
func _instrument(source: String) -> GDScript:
	source = source.replace("class_name EcologySim\n", "")
	for method in ["randf", "randi", "randf_range", "randi_range"]:
		var regex := RegEx.new()
		regex.compile("(?<![A-Za-z0-9_.])" + method + "\\(")
		source = regex.sub(source, "_test_" + method + "(", true)
	source = source.replace("movable.shuffle()", "_test_shuffle(movable)")
	source += """
var _test_draws := [0, 0, 0, 0, 0, 0]
func _test_randf() -> float:
	_test_draws[0] += 1
	return randf()
func _test_randi() -> int:
	_test_draws[1] += 1
	return randi()
func _test_randf_range(low: float, high: float) -> float:
	_test_draws[2] += 1
	return randf_range(low, high)
func _test_randi_range(low: int, high: int) -> int:
	_test_draws[3] += 1
	return randi_range(low, high)
func _test_shuffle(values: Array) -> void:
	_test_draws[4] += 1
	_test_draws[5] += maxi(0, values.size() - 1)
	values.shuffle()
"""
	var script := GDScript.new()
	script.source_code = source
	if script.reload() != OK:
		_failures += 1
		return null
	return script


func _compare_fixture(rng_seed: int, restored: bool, reentrant: bool) -> void:
	var regions := _fixture_regions()
	var species := _fixture_species()
	var initial := {"a": {"grazer": 15, "hunter": 8}, "b": {"grazer": 8},
		"c": {"grazer": 5, "splitter": 6}, "d": {"hunter": 3, "boss": 1}}
	seed(rng_seed)
	var a = _reference.new()
	a.setup(regions, species, initial)
	var next_a := _rng_tail()
	seed(rng_seed)
	var b = _optimized.new()
	b.setup(regions, species, initial)
	_check(next_a == _rng_tail() and a.to_dict() == b.to_dict(), "新世界初始化同源")
	if restored:
		var saved: Dictionary = a.to_dict()
		# 插入序与 ID 故意反向交错；恢复后的迁入者必须插入正确候选位置。
		for i in saved["instances"].size():
			saved["instances"][i]["id"] = 10000 - i * 17
			saved["instances"][i]["age"] = 39 + i % 12
			saved["instances"][i]["lifespan"] = 52 + i % 9
			saved["instances"][i]["hp"] = 8.0 + i
		saved["next_id"] = 10001
		saved["tick"] = 1200
		# 旧档城主异地，恢复时应归位；其余种群由真正迁徙 pass 处理。
		seed(rng_seed)
		_check(a.restore_from_dict(regions, species, saved), "旧档基线恢复")
		next_a = _rng_tail()
		seed(rng_seed)
		_check(b.restore_from_dict(regions, species, saved), "旧档优化恢复")
		_check(next_a == _rng_tail() and a.to_dict() == b.to_dict(), "乱序 ID 旧档恢复相同")
	var events_a: Array = []
	var events_b: Array = []
	_connect(a, events_a, reentrant)
	_connect(b, events_b, reentrant)
	for step in 90:
		_compare_step(a, b, events_a, events_b, rng_seed * 1000 + step,
			"fixture/%d/%s/%s/%d" % [rng_seed, restored, reentrant, step], step)
	print("ECOLOGY_INDEX_FIXTURE seed=%d restored=%s reentrant=%s tick=%d" % [
		rng_seed, restored, reentrant, b.tick_count])
	_disconnect(a)
	_disconnect(b)


func _compare_world(world_seed: int) -> void:
	BiomeMap.configure(world_seed)
	var regions := _world_regions()
	var species := SpeciesCatalog.build_all()
	seed(734)
	var a = _reference.new()
	a.setup(regions, species, WorldConfig.initial_population(), WorldConfig.boss_anchors())
	var next_a := _rng_tail()
	seed(734)
	var b = _optimized.new()
	b.setup(regions, species, WorldConfig.initial_population(), WorldConfig.boss_anchors())
	_check(next_a == _rng_tail() and a.to_dict() == b.to_dict(), "真实世界初始化相同")
	var events_a: Array = []
	var events_b: Array = []
	_connect(a, events_a, false)
	_connect(b, events_b, false)
	for step in 20:
		_compare_step(a, b, events_a, events_b, 8800 + step,
			"world/%d/fresh/%d" % [world_seed, step], step)
	# 只为构造长程种群而推进，随后将同一快照交给两版本，隔离比较真正老档热路径。
	var aging = _optimized.new()
	aging.restore_from_dict(regions, species, b.to_dict(), WorldConfig.boss_anchors())
	aging._satiety = b._satiety.duplicate()
	seed(734)
	for step in 1180:
		aging.tick()
	var saved: Dictionary = aging.to_dict()
	var satiety: Dictionary = aging._satiety.duplicate()
	seed(123)
	a.restore_from_dict(regions, species, saved, WorldConfig.boss_anchors())
	next_a = _rng_tail()
	seed(123)
	b.restore_from_dict(regions, species, saved, WorldConfig.boss_anchors())
	_check(next_a == _rng_tail(), "老世界恢复随机状态相同")
	a._satiety = satiety.duplicate()
	b._satiety = satiety.duplicate()
	# 两边此前年龄推进不同，仅从同一老世界入口重置测试计数。
	a._test_draws.fill(0)
	b._test_draws.fill(0)
	events_a.clear()
	events_b.clear()
	for step in 30:
		_compare_step(a, b, events_a, events_b, 19000 + step,
			"world/%d/aged/%d" % [world_seed, step], step)
	print("ECOLOGY_INDEX_WORLD seed=%d aged_tick=%d population=%d" % [
		world_seed, b.tick_count, b._build_summary()["total_alive"]])
	_disconnect(a)
	_disconnect(b)


func _compare_step(a, b, events_a: Array, events_b: Array, rng_seed: int,
		label: String, step: int) -> void:
	events_a.clear()
	events_b.clear()
	seed(rng_seed)
	_actions(a, step)
	a.tick()
	var next_a := _rng_tail()
	seed(rng_seed)
	_actions(b, step)
	b.tick()
	var next_b := _rng_tail()
	_check(a.to_dict() == b.to_dict(), label + " state")
	_check(a._satiety == b._satiety, label + " satiety")
	_check(events_a == events_b, label + " signals and signal-time queries")
	_check(a._test_draws == b._test_draws, label + " RNG call counts")
	_check(next_a == next_b, label + " RNG continuation")
	_check(_bucket_ids(b) == _scan_ids(b), label + " insertion order")
	_events += events_b.size()


func _actions(sim, step: int) -> void:
	if step % 11 == 3:
		for inst: MonsterInstance in sim.instances.values():
			if inst.is_alive and (inst.can_split() or inst.species.is_boss):
				sim.report_killed(inst.id, inst.spawn_pos)
				break
	if step % 17 == 5:
		for key: String in sim.nests:
			if sim.destroy_nest(key.get_slice("|", 0), key.get_slice("|", 1)):
				break


func _connect(sim, events: Array, reentrant: bool) -> void:
	sim.instance_spawned.connect(func(inst): events.append(["spawn", _instance(inst)]))
	sim.instance_died.connect(func(inst, cause): events.append(["die", cause, _instance(inst)]))
	sim.corpse_expired.connect(func(inst): events.append(["expire", _instance(inst)]))
	sim.nest_changed.connect(func(region, species, active, ransacked):
		events.append(["nest", region, species, active, ransacked]))
	sim.boss_respawned.connect(func(species): events.append(["boss", species]))
	sim.tick_completed.connect(func(summary): events.append(["tick", summary.duplicate(true)]))
	var mutated := [false]
	sim.instance_migrated.connect(func(inst, region):
		_migrations += 1
		var counts: Array = []
		for id: String in sim.regions:
			counts.append(sim.alive_count_in(id))
		events.append(["migrate", _instance(inst), region, counts])
		if reentrant and not mutated[0]:
			mutated[0] = true
			# 信号中击杀/出生后查询会重建缓存；批次结束不能重复插入迁入者。
			sim.report_killed(inst.id, inst.spawn_pos)
			sim.alive_count_in(region)
			sim.spawn_instance(inst.species, region, 0, 0, 1.0, false, inst.spawn_pos)
			sim.alive_count_in(region)
	)


## 信号闭包读取模拟器，退出用例前解除连接，避免 RefCounted 引用环。
func _disconnect(sim) -> void:
	for entry: Dictionary in sim.get_signal_list():
		for connection: Dictionary in sim.get_signal_connection_list(entry["name"]):
			sim.disconnect(entry["name"], connection["callable"])


func _instance(inst: MonsterInstance) -> Array:
	return [inst.id, inst.species.species_name, inst.region_id, inst.age, inst.lifespan,
		inst.generation, inst.size_scale, inst.is_elite, inst.is_alive, inst.corpse_ticks,
		inst.spawn_pos, inst.death_pos, inst.hp_mirror]


func _rng_tail() -> Array:
	var result: Array = []
	for i in 8:
		result.append(randi())
	return result


func _bucket_ids(sim) -> Dictionary:
	var result := {}
	for region: String in sim._buckets():
		for species: String in sim._buckets()[region]:
			var ids: Array = []
			for inst: MonsterInstance in sim._buckets()[region][species]:
				if inst.is_alive:
					ids.append(inst.id)
			if not ids.is_empty():
				result[region + "|" + species] = ids
	return result


func _scan_ids(sim) -> Dictionary:
	var result := {}
	for inst: MonsterInstance in sim.instances.values():
		if inst.is_alive:
			var key := inst.region_id + "|" + inst.species.species_name
			if not result.has(key):
				result[key] = []
			result[key].append(inst.id)
	return result


func _fixture_regions() -> Array:
	var result: Array = []
	for i in 4:
		var region := SimRegion.new()
		region.id = ["a", "b", "c", "d"][i]
		region.terrain = "plains"
		region.capacity = 60
		region.center = Vector2(-8000.0 - i * 6000.0, -8000.0)
		region.size = Vector2(5000, 5000)
		for id: String in ["a", "b", "c", "d"]:
			if id != region.id:
				region.neighbor_ids.append(id)
		result.append(region)
	return result


func _fixture_species() -> Array[SpeciesData]:
	var result: Array[SpeciesData] = []
	for name: String in ["grazer", "hunter", "splitter", "boss"]:
		var species := SpeciesData.new()
		species.species_name = name
		species.maturity_age = 4
		species.lifespan_min = 40
		species.lifespan_max = 90
		species.breeding_rate = 0.025
		species.expansion_threshold = 3
		species.migrate_count = 2
		species.corpse_duration = 3
		if name == "hunter":
			species.prey = ["grazer", "splitter"]
		if name == "splitter":
			species.splits_on_death = true
			species.split_count = 2
			species.max_generation = 2
		if name == "boss":
			species.is_boss = true
			species.migrate_count = 0
			species.breeding_rate = 0.0
			species.boss_respawn_ticks = 4
		result.append(species)
	return result


func _world_regions() -> Array:
	var result: Array = []
	for def: Dictionary in WorldConfig.region_defs():
		var region := SimRegion.new()
		region.id = def["id"]
		region.display_name = def["name"]
		region.terrain = def["terrain"]
		region.threat = def["threat"]
		region.center = def["center"]
		region.size = def["size"]
		region.capacity = def["capacity"]
		for neighbor: String in def["neighbors"]:
			region.neighbor_ids.append(neighbor)
		result.append(region)
	return result


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL ECOLOGY_INDEX ", label)
