## CPU-only measurement of real CampaignQuest publication into mounted CampaignWorld objects.
## Input must be a copied existing save. No campaign completion evidence is authored by this test.
## Only the batch4 gate is enabled by the fixture; all publication/projection methods are production code.
extends "res://tests/campaign_dynamic_runtime_test.gd"
const SAMPLES := 60
func _run() -> void:
	GameState.save_enabled = false
	var path := OS.get_environment("HOTW_TEST_SAVE")
	check(not path.is_empty() and FileAccess.file_exists(path), "projection diagnostic requires a copied existing save")
	if path.is_empty() or not FileAccess.file_exists(path): get_tree().quit(1); return
	var input_bytes := FileAccess.get_file_as_bytes(path)
	check(not GameState.campaign_quest.is_empty(), "actual GameState cold load restored the existing campaign ledger")
	BiomeMap.configure(GameState.world_seed)
	ObstacleField.restore_destroyed(GameState.destroyed_cells)
	var regions: Array = []
	for def: Dictionary in WorldConfig.region_defs():
		var r := SimRegion.new()
		r.id=def.id; r.center=def.center; r.size=def.size; r.capacity=def.capacity
		r.terrain=def.terrain; r.threat=def.threat
		for neighbor: String in def.neighbors: r.neighbor_ids.append(neighbor)
		regions.append(r)
	var sim := EcologySim.new()
	var ecology_source := "restored_existing_save"
	if GameState.ecology_snapshot is Dictionary:
		check(sim.restore_from_dict(regions, SpeciesCatalog.build_all(), GameState.ecology_snapshot, WorldConfig.boss_anchors()), "real cumulative candidate ecology restores before observer setup")
	else:
		ecology_source = "normal_initial_population_for_explicit_ledger_only_fixture"
		sim.setup(regions, SpeciesCatalog.build_all(), WorldConfig.initial_population(), WorldConfig.boss_anchors())
	WorldSim.sim = sim
	var initial_ecology := JSON.stringify(sim.to_dict())
	world = CampaignWorld.new()
	add_child(world)
	player = CharacterBody2D.new()
	player.add_to_group("player")
	player.position = WorldConfig.spawn_pos()
	add_child(player)
	host = FixtureHost.new()
	add_child(host)
	dynamic = host._dynamic
	dynamic.set_physics_process(false)
	host._main.set_physics_process(false)
	host._optional.set_physics_process(false)
	await frames()
	for warmup in 5: host._publish()
	var before := JSON.stringify(GameState.campaign_quest)
	var objects := world.objects_by_id.size()
	check(objects > 100, "real authored campaign objects are mounted and subscribed to state publication")
	var paid := 0
	for row: Dictionary in GameState.campaign_quest.quests.values():
		if row.get("receipt", {}).get("paid", false): paid += 1
	var label := OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "existing_save"
	for mode: String in ["build_visual_state", "publish_and_project"]:
		var costs: Array[int] = []
		var started := Time.get_ticks_usec()
		for sample in SAMPLES:
			var began := Time.get_ticks_usec()
			if mode == "build_visual_state": host.visual_state()
			else: host._publish()
			costs.append(Time.get_ticks_usec() - began)
		var elapsed := Time.get_ticks_usec() - started
		costs.sort()
		print("PROJECTION_COST " + JSON.stringify({"input_label":label,"input_sha256":FileAccess.get_sha256(path),"mode":mode,"samples":SAMPLES,"mean_us":float(elapsed)/SAMPLES,"p50_us":costs[SAMPLES/2],"p95_us":costs[int(SAMPLES*0.95)-1],"max_us":costs[-1],"quests":GameState.campaign_quest.quests.size(),"paid_receipts":paid,"mounted_objects":objects,"ecology_source":ecology_source,"excluded":"HUD/QuestManager publication, GPU rendering, collision streaming, filesystem writes, mobile device performance"}))
	check(JSON.stringify(GameState.campaign_quest) == before, "publication/projection does not invent campaign actions or alter receipts")
	check(JSON.stringify(sim.to_dict()) == initial_ecology, "publication/projection never changes individuals, population, positions, nests, or clock")
	check(FileAccess.get_file_as_bytes(path) == input_bytes, "copied source save remains byte-identical")
	print("CAMPAIGN_DYNAMIC_PROJECTION_COST_TEST %s checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
