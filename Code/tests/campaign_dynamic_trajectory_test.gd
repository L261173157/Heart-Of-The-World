## Bounded diagnostic of normal production ecology. Trigger occurrence is reported, never required.
## C1 completion is explicit setup; the regional clue is earned through actual C2 scene actions.
extends "res://tests/campaign_dynamic_runtime_test.gd"
const OBSERVATION_TICKS := 2000
func production_sim() -> EcologySim:
	var regions: Array = []
	for def: Dictionary in WorldConfig.region_defs():
		var r := SimRegion.new()
		r.id=def.id; r.center=def.center; r.size=def.size; r.capacity=def.capacity
		r.terrain=def.terrain; r.threat=def.threat
		for neighbor: String in def.neighbors: r.neighbor_ids.append(neighbor)
		regions.append(r)
	var types: Array[SpeciesData] = []
	for species: SpeciesData in SpeciesCatalog.build_all(): types.append(species.duplicate())
	var sim := EcologySim.new()
	sim.setup(regions, types, WorldConfig.initial_population(), WorldConfig.boss_anchors())
	return sim
func _run() -> void:
	GameState.save_enabled = false
	for seed_value: int in [20260908, 734, 987654]:
		# Fix only the test RNG for reproducibility; all probabilities, population and timers remain production values.
		seed(seed_value)
		GameState.world_seed = seed_value
		BiomeMap.configure(seed_value)
		ObstacleField.restore_destroyed([])
		GameState.campaign_quest = Data.create(seed_value)
		var evidence := {}
		for id: String in Data.Outpost.EVIDENCE: evidence[id] = true
		Data.authorize_chapter1(GameState.campaign_quest, {"id":"lost_outpost_v1","evidence":evidence,"outcome":"survey","survey_confirmed":true})
		WorldSim.sim = production_sim()
		var sim := WorldSim.sim
		var initial_population := _live_count(sim)
		world = CampaignWorld.new()
		add_child(world)
		player = CharacterBody2D.new()
		player.add_to_group("player")
		add_child(player)
		host = FixtureHost.new()
		add_child(host)
		dynamic = host._dynamic
		await frames()
		dynamic.set_physics_process(false)
		await go("c2:herbalist")
		host.accept_chapter("watch_c2_forest")
		host.perform_action("watch_c2_forest:s1:herbalist")
		await go("c2:old_pact")
		host.perform_action("watch_c2_forest:s1:old_pact")
		dynamic._earn_record_clues()
		var clue_region := BiomeMap.region_id_at(world.object_node("c2:old_pact").position)
		check(Data.ready(GameState.campaign_quest, "watch_c2_forest:s1"), "actual C2 NPC conversation and record read earn the regional clue")
		check(not dynamic.facts.known_clue(clue_region).is_empty(), "production clue acquisition points to the actual authored record region")
		var baseline := dynamic.facts.snapshot()
		check(baseline.events.is_empty() and baseline.triggers.is_empty(), "obtaining a record clue never invents ecological events")
		# Keep only the raw production fact observer during the long pure-simulation measurement.
		host.free()
		world.free()
		player.free()
		WorldSim.sim = null
		var observer := CampaignWorldFacts.new()
		add_child(observer)
		observer.configure(sim, seed_value, baseline)
		var counts := {"birth_signals":0,"migration_signals":0,"deaths":{},"nest_changes":0}
		sim.instance_spawned.connect(func(_inst: MonsterInstance) -> void: counts.birth_signals += 1)
		sim.instance_migrated.connect(func(_inst: MonsterInstance, _to: String) -> void: counts.migration_signals += 1)
		sim.instance_died.connect(func(_inst: MonsterInstance, cause: String) -> void: counts.deaths[cause] = int(counts.deaths.get(cause, 0)) + 1)
		sim.nest_changed.connect(func(_region: String, _species: String, _active: bool, _ransacked: bool) -> void: counts.nest_changes += 1)
		var first_migration: Dictionary = {}
		var first_decline: Dictionary = {}
		var started := Time.get_ticks_msec()
		var low_population := initial_population
		var high_population := initial_population
		for tick in OBSERVATION_TICKS:
			sim.tick()
			low_population = mini(low_population, _live_count(sim))
			high_population = maxi(high_population, _live_count(sim))
			if first_migration.is_empty(): first_migration = observer.migration_trigger()
			if first_decline.is_empty(): first_decline = observer.decline_trigger()
			if (tick + 1) % 500 == 0:
				print("TRAJECTORY_PROGRESS seed=%d tick=%d alive=%d raw_migrations=%d elapsed_ms=%d" % [seed_value, tick + 1, _live_count(sim), counts.migration_signals, Time.get_ticks_msec() - started])
		var migration_summary := {"triggered":not first_migration.is_empty()}
		if not first_migration.is_empty():
			migration_summary.merge({"tick":first_migration.tick,"species":first_migration.species,"source":first_migration.source,"events":first_migration.events,"final":observer.migration_status(first_migration)})
		var decline_summary := {"triggered":not first_decline.is_empty()}
		if not first_decline.is_empty(): decline_summary.merge({"tick":first_decline.tick,"species":first_decline.species,"baseline":first_decline.baseline,"cause":first_decline.cause,"source":first_decline.source,"region_id":first_decline.region_id,"final":observer.decline_status(first_decline)})
		check(sim.tick_count == OBSERVATION_TICKS, "exactly the bounded number of normal production ticks elapsed")
		check(counts.deaths.get(EcologySim.DEATH_KILLED, 0) == 0 and sim.player_extinct.is_empty(), "normal ecology trajectory never fabricates player kills or permanent extinction")
		print("TRAJECTORY_RESULT " + JSON.stringify({"seed":seed_value,"rng_seed":seed_value,"ticks":sim.tick_count,"initial_alive":initial_population,"min_alive":low_population,"max_alive":high_population,"final_alive":_live_count(sim),"clue_region":clue_region,"clue":baseline.clues.get(clue_region,{}),"raw":counts,"migration":migration_summary,"decline":decline_summary,"elapsed_ms":Time.get_ticks_msec()-started}))
		observer.free()
	print("CAMPAIGN_DYNAMIC_TRAJECTORY_TEST %s checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

func _live_count(sim: EcologySim) -> int:
	var total := 0
	for inst: MonsterInstance in sim.instances.values():
		if inst.is_alive: total += 1
	return total
