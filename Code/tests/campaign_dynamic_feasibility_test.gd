## Seven fixed real-world feasibility fixtures, not a promise that arbitrary worlds always issue encounters.
## Exploration and a level-30 balanced build are explicit prerequisites. No ecology mutation is allowed.
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
	for seed_value: int in [20260908, 1, 2, 42, 734, 12345, 987654]:
		GameState.world_seed = seed_value
		BiomeMap.configure(seed_value)
		ObstacleField.restore_destroyed([])
		GameState.campaign_quest = CampaignQuestData.create(seed_value)
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
		var cid := "random_camp:%d:0" % seed_value
		var origin := CampaignLayout.object_position(cid + ":giver")
		var camp_region := BiomeMap.region_id_at(origin)
		for inst: MonsterInstance in sim.instances.values():
			if inst.is_alive and inst.region_id == camp_region: GameState.fog_reveal_position(inst.spawn_pos)
		var selected := runtime.encounters._camp_target(runtime._context(cid))
		check(not selected.is_empty(), "seed %d has a real accessible capability-matched healthy camp" % seed_value)
		if not selected.is_empty():
			check(int(selected.quota) >= 1 and int(selected.quota) <= 2, "quota remains finite")
			check(int(selected.local_alive) > int(selected.quota) and int(selected.global_alive) - int(selected.quota) >= EcologySim.ENDANGERED_THRESHOLD, "quota preserves local and global reserves")
			for id: int in selected.target_ids:
				var inst: MonsterInstance = sim.instances.get(id)
				check(inst != null and inst.is_alive and inst.region_id == camp_region and inst.species.species_name == selected.species, "target is an actual unchanged local identity")
				if inst == null: continue
				check(CampaignEncounters.capable(inst, GameState.stats), "target satisfies authoritative combat-band risk")
				check(runtime._route_exists(origin, inst.spawn_pos), "target has a bounded gameplay-obstacle route")
				var simple := runtime._clear(origin, inst.spawn_pos)
				for corner: Vector2 in [Vector2(origin.x, inst.spawn_pos.y), Vector2(inst.spawn_pos.x, origin.y)]:
					if runtime._clear(origin, corner) and runtime._clear(corner, inst.spawn_pos): simple = true
				if not simple:
					astar_witnesses += 1
					check(runtime._grid_route(origin, inst.spawn_pos), "non-straight/non-L-shaped real route requires the A* fallback")
		check(JSON.stringify(sim.to_dict()) == original, "seed %d probing never changes clock, individuals, population, nests, anchors, or ecology" % seed_value)
		check(runtime.encounters.total_issued() == 0 and GameState.campaign_quest.quests.is_empty(), "feasibility probing never fabricates accepted or completed content")
		print("FEASIBILITY seed=%d nest=%s camp=%s quota=%d" % [seed_value, not binding.is_empty(), selected.get("species", ""), selected.get("quota", 0)])
		runtime.free()
		host.free()
	check(astar_witnesses > 0, "registered fixtures actually cover the A* regression")
	print("CAMPAIGN_DYNAMIC_FEASIBILITY_TEST %s checks=%d failures=%d astar_witnesses=%d" % ["PASS" if failures == 0 else "FAIL", checks, failures, astar_witnesses])
	get_tree().quit(0 if failures == 0 else 1)
