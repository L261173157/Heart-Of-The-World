## 地图种子和生态全局 RNG 分别固定；普通世界不保证总有可接遭遇。
## 七组真实正例保留 Lv30 均衡构筑；map=1/ecology=19 固定自然无单反例。
## 不增怪、不改位置/年龄/属性/密度；逐组清空知识并复建两次核对完整状态。
extends Node
class ProbeHost extends Node:
	func ledger() -> Dictionary: return GameState.campaign_quest
	func _chapter_enabled(_c: Dictionary) -> bool: return true
	func _save() -> void: pass
	func _publish() -> void: pass
var checks := 0
var failures := 0
var astar_witnesses := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("DYNAMIC FEASIBILITY FAIL: " + label)
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	GameState.save_enabled = false
	var fixtures: Array = []
	for seed_value: int in [20260908, 1, 2, 42, 734, 12345, 987654]:
		fixtures.append({"world":seed_value,"ecology":seed_value,"camp":true})
	# 原 CI 未记录 RNG，无法还原其确切随机状态；此为独立复现的同类失败。
	fixtures.append({"world":1,"ecology":19,"camp":false})
	for fixture: Dictionary in fixtures:
		var first := _probe_fixture(fixture.world, fixture.ecology, fixture.camp, 1)
		var replay := _probe_fixture(fixture.world, fixture.ecology, fixture.camp, 2)
		check(first == replay, "map %d / ecology %d repeats the complete ecology snapshot and exact selected identities" % [fixture.world, fixture.ecology])
	check(astar_witnesses > 0, "registered fixtures actually cover the A* regression")
	print("CAMPAIGN_DYNAMIC_FEASIBILITY_TEST %s checks=%d failures=%d astar_witnesses=%d" % ["PASS" if failures == 0 else "FAIL", checks, failures, astar_witnesses])
	get_tree().quit(0 if failures == 0 else 1)

func _probe_fixture(seed_value: int, ecology_seed: int, expect_camp: bool, round_index: int) -> Dictionary:
	GameState.world_seed = seed_value
	BiomeMap.configure(seed_value)
	ObstacleField.restore_destroyed([])
	GameState.campaign_quest = CampaignQuestData.create(seed_value)
	GameState.exploration = ExplorationFog.new(seed_value)
	GameState.explored = PackedByteArray()
	GameState.stats.reset()
	GameState.stats.level = 30
	GameState.stats.strength = 30
	GameState.stats.agility = 30
	GameState.stats.intellect = 30
	var regions: Array = []
	for def: Dictionary in WorldConfig.region_defs():
		var r := SimRegion.new()
		r.id=def.id; r.center=def.center; r.size=def.size; r.capacity=def.capacity
		r.terrain=def.terrain; r.threat=def.threat
		for neighbor: String in def.neighbors: r.neighbor_ids.append(neighbor)
		regions.append(r)
	var sim := EcologySim.new()
	# BiomeMap.configure 不会固定 EcologySim 的年龄、寿命与散布随机数。
	seed(ecology_seed)
	sim.setup(regions, SpeciesCatalog.build_all(), WorldConfig.initial_population(), WorldConfig.boss_anchors())
	var original := JSON.stringify(sim.to_dict())
	var host := ProbeHost.new()
	add_child(host)
	var runtime := CampaignDynamic.new()
	runtime.setup(host)
	runtime._sim = sim
	add_child(runtime)
	runtime.set_physics_process(false)
	runtime.encounters.configure(sim, seed_value)
	var cid := "random_camp:%d:0" % seed_value
	var context := runtime._context(cid)
	check(runtime.encounters._camp_target(context).is_empty(), "unexplored actual world cannot expose a camp")
	var nid := "random_nest:%d:0" % seed_value
	var giver := CampaignLayout.object_position(nid + ":giver")
	var region_id := BiomeMap.region_id_at(giver)
	var candidates := 0
	for key: String in sim.nests:
		if key.get_slice("|", 0) != region_id or not sim.nests[key].active: continue
		var species := sim.find_species(key.get_slice("|", 1))
		if species.is_boss: continue
		var point := sim.camp_pos(sim.regions[region_id], species)
		GameState.fog_reveal_position(point)
		if point.distance_to(giver) <= 5000: candidates += 1
	runtime._prepare_nest(nid)
	check(candidates > 0, "seed %d has real existing local nests" % seed_value)
	var binding: Dictionary = runtime._runtime().bindings.get(nid + ":target", {})
	check(not binding.is_empty(), "seed %d binds a real reachable nest" % seed_value)
	if not binding.is_empty():
		var point := Vector2(float(binding.position[0]), float(binding.position[1]))
		check(not ObstacleField.nav_blocked_at(point), "nest marker is not placed in a blocking cell")
		check(runtime._route_exists(giver, point), "nest marker has a bounded actual route")
		check(not runtime.encounters._nest_target(point, runtime._context(nid)).is_empty(), "bound nest remains actually active and capability matched")
	var origin := CampaignLayout.object_position(cid + ":giver")
	var camp_region := BiomeMap.region_id_at(origin)
	for inst: MonsterInstance in sim.instances.values():
		if inst.is_alive and inst.region_id == camp_region: GameState.fog_reveal_position(inst.spawn_pos)
	var selected := runtime.encounters._camp_target(context)
	var census := _camp_census(sim, runtime, context)
	print("FEASIBILITY_STATE " + JSON.stringify({"world_seed":seed_value,"ecology_seed":ecology_seed,"round":round_index,"snapshot_sha256":original.sha256_text(),"region":camp_region,"origin":[origin.x,origin.y],"census":census,"selected":selected}))
	check(not selected.is_empty() == expect_camp, "map %d / ecology %d has expected real camp availability %s" % [seed_value, ecology_seed, expect_camp])
	check(census.eligible_species.is_empty() == selected.is_empty(), "camp availability matches the actual known/reachable/capable survivor census")
	if not expect_camp:
		check(census.groups["冰霜小魔"].eligible_ids == [205] and census.groups["冰霜小魔"].route_rejected_ids == [206], "natural scatter leaves only one reachable imp, insufficient for target plus survivor")
		check(census.groups["巨蝠"].route_rejected_ids == [207,208,209], "other actual multi-member camp is unreachable")
		for species: String in ["炸弹鱼","鱼叉鲨"]:
			check(census.groups[species].eligible_ids.size() == 1 and census.groups[species].local_alive == 1 and census.groups[species].quota == 0, "reachable real singleton cannot supply a sustainable quota")
	if not selected.is_empty():
		check(int(selected.quota) >= 1 and int(selected.quota) <= 2, "quota remains finite")
		check(int(selected.local_alive) > int(selected.quota) and int(selected.global_alive) - int(selected.quota) >= EcologySim.ENDANGERED_THRESHOLD, "quota preserves local and global reserves")
		check(selected.target_ids.size() > int(selected.quota), "reachable capable target IDs also retain a survivor")
		for id: int in selected.target_ids:
			var inst: MonsterInstance = sim.instances.get(id)
			check(inst != null and inst.is_alive and inst.region_id == camp_region and inst.species.species_name == selected.species, "target is an actual unchanged local identity")
			if inst == null: continue
			check(CampaignEncounters.capable(inst, GameState.stats), "target satisfies authoritative combat-band risk")
			var position := runtime.encounters._current_position(inst, context)
			check(position == inst.spawn_pos and origin.distance_to(position) <= CampaignEncounters.LOCAL_RADIUS and GameState.fog_knows_position(position), "target retains its actual current position, local radius and earned knowledge")
			check(runtime._route_exists(origin, position), "target has a bounded gameplay-obstacle route")
			var simple := runtime._clear(origin, inst.spawn_pos)
			for corner: Vector2 in [Vector2(origin.x, inst.spawn_pos.y), Vector2(inst.spawn_pos.x, origin.y)]:
				if runtime._clear(origin, corner) and runtime._clear(corner, inst.spawn_pos): simple = true
			if not simple:
				astar_witnesses += 1
				check(runtime._grid_route(origin, inst.spawn_pos), "non-straight/non-L-shaped real route requires the A* fallback")
	check(JSON.stringify(sim.to_dict()) == original, "seed %d probing never changes clock, individuals, population, nests, anchors, or ecology" % seed_value)
	check(runtime.encounters.total_issued() == 0 and GameState.campaign_quest.quests.is_empty(), "feasibility probing never fabricates accepted or completed content")
	print("FEASIBILITY seed=%d ecology_seed=%d round=%d nest=%s camp=%s quota=%d unchanged=%s" % [seed_value, ecology_seed, round_index, not binding.is_empty(), selected.get("species", ""), selected.get("quota", 0), JSON.stringify(sim.to_dict()) == original])
	runtime.free()
	host.free()
	return {"snapshot":original,"camp":selected,"nest":binding.duplicate(true)}

## 逐个记录原始排除原因；不调用 _camp_target，也不改生态或伪造可达性。
func _camp_census(sim: EcologySim, runtime: CampaignDynamic, context: Dictionary) -> Dictionary:
	var groups := {}
	var actors: Array = []
	var origin: Vector2 = context.origin
	for inst: MonsterInstance in sim.instances.values():
		if inst.region_id != str(context.region_id): continue
		var species := inst.species.species_name
		if not groups.has(species):
			groups[species] = {"local_alive":sim.alive_count_in(inst.region_id,inst.species),
				"global_alive":sim.alive_count_of_species(species),"eligible_ids":[],"route_rejected_ids":[]}
		var position := runtime.encounters._current_position(inst,context)
		var reasons: Array[String] = []
		if not CampaignEncounters.capable(inst,GameState.stats): reasons.append("incapable_or_ambient")
		if not position.is_finite() or origin.distance_to(position) > CampaignEncounters.LOCAL_RADIUS: reasons.append("outside_local_radius")
		if not GameState.fog_knows_position(position): reasons.append("unknown")
		if not runtime._route_exists(origin,position):
			reasons.append("unreachable")
			groups[species].route_rejected_ids.append(inst.id)
		if reasons.is_empty(): groups[species].eligible_ids.append(inst.id)
		actors.append({"id":inst.id,"species":species,"age":inst.age,"lifespan":inst.lifespan,
			"position":[position.x,position.y],"distance":origin.distance_to(position),
			"nav_blocked":ObstacleField.nav_blocked_at(position),"rejected":reasons})
	var eligible_species: Array[String] = []
	for species: String in groups:
		var group: Dictionary = groups[species]
		group.quota = maxi(0, mini(2, mini(group.local_alive-1, mini(group.global_alive-EcologySim.ENDANGERED_THRESHOLD,group.eligible_ids.size()-1))))
		if group.quota > 0: eligible_species.append(species)
	return {"groups":groups,"actors":actors,"eligible_species":eligible_species}
