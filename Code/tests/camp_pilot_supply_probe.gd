## 独立只读供给探针：真实种子/物种/生态 tick，不提高密度或造任务目标。
extends Node2D

const SEEDS := [20260908, 1, 2, 3, 42, 99, 20261004, 2147483646, 314159, 8675309, 10007, 65537]
var _helper: BountyManager
var _player: Node2D

func _ready() -> void:
	GameState.save_enabled = false
	WorldSim.stop()
	_run.call_deferred()

func _regions() -> Array:
	var result: Array = []
	for def: Dictionary in WorldConfig.region_defs():
		var r := SimRegion.new()
		r.id = def["id"]
		r.display_name = def["name"]
		r.terrain = def["terrain"]
		r.threat = def["threat"]
		r.center = def["center"]
		r.size = def["size"]
		r.capacity = def["capacity"]
		r.neighbor_ids.assign(def["neighbors"])
		result.append(r)
	return result

func _run() -> void:
	_player = Node2D.new()
	_player.add_to_group("player")
	add_child(_player)
	_helper = BountyManager.new()
	add_child(_helper)
	_helper.set_process(false)
	var selected_seeds: Array = [20260908, 1] if "--quick" in OS.get_cmdline_user_args() else SEEDS
	for seed_value: int in selected_seeds:
		GameState.reset_all()
		BiomeMap.configure(seed_value)
		ObstacleField.restore_destroyed([])
		seed(seed_value)
		var sim := EcologySim.new()
		sim.setup(_regions(), SpeciesCatalog.build_all(), WorldConfig.initial_population(), WorldConfig.boss_anchors())
		WorldSim.sim = sim
		_player.position = WorldConfig.spawn_pos()
		await _sample(seed_value, "fresh")
		for tick in 600:
			sim.tick()
		await _sample(seed_value, "natural600")
		for tick in 300:
			sim.tick()
		await _sample(seed_value, "natural900")
		# 用模拟权威击杀消耗本地活体，等价读取一份已被玩家清空的旧世界。
		for inst: MonsterInstance in sim.instances.values():
			if inst.is_alive and inst.spawn_pos.distance_to(_player.position) <= 12000.0:
				sim.report_killed(inst.id, inst.spawn_pos)
		await _sample(seed_value, "depleted")
	WorldSim.stop()
	print("=== CAMP PILOT SUPPLY PROBE COMPLETE ===")
	get_tree().quit()

func _sample(seed_value: int, phase: String) -> void:
	var groups := {}
	var sim := WorldSim.sim
	for inst: MonsterInstance in sim.instances.values():
		if not _helper._feasible(inst) or not inst.spawn_pos.is_finite() \
				or inst.spawn_pos.distance_to(_player.position) > 12000.0:
			continue
		var key := inst.region_id + "|" + inst.species.species_name
		if not groups.has(key):
			var region := sim.get_region(inst.region_id)
			var camp := sim.camp_pos(region, inst.species)
			groups[key] = {"species": inst.species.species_name, "count": 0,
				"distance": camp.distance_to(_player.position), "camp": camp,
				"active_nest": bool(sim.nests.get(key, {}).get("active", false))}
		groups[key]["count"] += 1
	_helper._route_connected.clear()
	_helper._route_blocked.clear()
	_helper._route_visits_left = 20000
	_helper._route_slice_started = Time.get_ticks_usec()
	var rows: Array = groups.values()
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["distance"] < b["distance"])
	for row: Dictionary in rows:
		row["reachable"] = await _helper._route_exists(_player.position, row["camp"])
		row["roundtrip_floor_seconds"] = snappedf(float(row["distance"]) * 2.0 / GameState.stats.move_speed(), 0.1)
		row.erase("camp")
	var selector := CampQuestTargets.new()
	add_child(selector)
	var actual: Dictionary = await selector.select_target()
	selector.queue_free()
	print("CAMP_SUPPLY ", JSON.stringify({"seed": seed_value, "phase": phase, "rows": rows, "actual_selector": actual}))
