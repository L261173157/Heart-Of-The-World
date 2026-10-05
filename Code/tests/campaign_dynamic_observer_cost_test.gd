## Paired cost diagnostic. Every phase restores one genuine production warmup snapshot and the same RNG seed.
## Timings cover pure simulation and the active write-through listener, not rendering/device performance.
extends Node
class BenchHost extends Node:
	var saves := 0
	func ledger() -> Dictionary: return GameState.campaign_quest
	func _chapter_enabled(_c: Dictionary) -> bool: return true
	func _save() -> void: saves += 1
	func _publish() -> void: saves += 1
const WORLD_SEED := 20260908
const WARMUP_TICKS := 1000
const MEASURE_TICKS := 100
var failures := 0
var checks := 0
func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("OBSERVER COST FAIL: " + text)
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	GameState.save_enabled = false
	GameState.world_seed = WORLD_SEED
	BiomeMap.configure(WORLD_SEED)
	ObstacleField.restore_destroyed([])
	seed(WORLD_SEED)
	var regions: Array = []
	for def: Dictionary in WorldConfig.region_defs():
		var r := SimRegion.new()
		r.id=def.id; r.center=def.center; r.size=def.size; r.capacity=def.capacity
		r.terrain=def.terrain; r.threat=def.threat
		for neighbor: String in def.neighbors: r.neighbor_ids.append(neighbor)
		regions.append(r)
	var types: Array[SpeciesData] = []
	for species: SpeciesData in SpeciesCatalog.build_all(): types.append(species.duplicate())
	var warm := EcologySim.new()
	warm.setup(regions, types, WorldConfig.initial_population(), WorldConfig.boss_anchors())
	var started := Time.get_ticks_usec()
	for tick in WARMUP_TICKS: warm.tick()
	var warmup_us := Time.get_ticks_usec() - started
	var input := warm.to_dict()
	var expected_bytes := ""
	var expected_signals := ""
	for mode: String in ["baseline", "raw_facts", "dynamic_write_through"]:
		var sim := EcologySim.new()
		check(sim.restore_from_dict(regions, types, input, WorldConfig.boss_anchors()), mode + " restores identical genuine warm ecology")
		GameState.campaign_quest = CampaignQuestData.create(WORLD_SEED)
		var facts: CampaignWorldFacts = null
		var dynamic: CampaignDynamic = null
		var host: BenchHost = null
		if mode == "raw_facts":
			facts = CampaignWorldFacts.new()
			add_child(facts)
			facts.configure(sim, WORLD_SEED)
		elif mode == "dynamic_write_through":
			WorldSim.sim = sim
			host = BenchHost.new()
			add_child(host)
			dynamic = CampaignDynamic.new()
			dynamic.setup(host)
			add_child(dynamic)
			dynamic.set_physics_process(false)
			dynamic.configure_after_restore()
			facts = dynamic.facts
		if facts != null:
			# Explicit clue precondition only; no event or completion is injected.
			facts.obtain_clue(BiomeMap.region_id_at(CampaignLayout.object_position("c2:old_pact")), "c2:old_pact")
		var signals := {"spawned":0,"migrated":0,"died":0,"nests":0}
		sim.instance_spawned.connect(func(_inst: MonsterInstance) -> void: signals.spawned += 1)
		sim.instance_migrated.connect(func(_inst: MonsterInstance, _to: String) -> void: signals.migrated += 1)
		sim.instance_died.connect(func(_inst: MonsterInstance, _cause: String) -> void: signals.died += 1)
		sim.nest_changed.connect(func(_region: String, _species: String, _active: bool, _ransacked: bool) -> void: signals.nests += 1)
		seed(WORLD_SEED + 1000)
		var costs: Array[int] = []
		started = Time.get_ticks_usec()
		for tick in MEASURE_TICKS:
			var began := Time.get_ticks_usec()
			sim.tick()
			if dynamic != null and dynamic._publish_pending: dynamic._publish_changed()
			costs.append(Time.get_ticks_usec() - began)
		var elapsed_us := Time.get_ticks_usec() - started
		var output := JSON.stringify(sim.to_dict())
		var signal_bytes := JSON.stringify(signals)
		if mode == "baseline":
			expected_bytes = output
			expected_signals = signal_bytes
		else:
			check(output == expected_bytes, mode + " final ecology is byte-identical to paired baseline")
			check(signal_bytes == expected_signals, mode + " raw event counts are exactly identical")
		costs.sort()
		print("OBSERVER_COST " + JSON.stringify({"mode":mode,"world_seed":WORLD_SEED,"paired_rng_seed":WORLD_SEED+1000,"warmup_ticks":WARMUP_TICKS,"warmup_us":warmup_us,"measure_ticks":MEASURE_TICKS,"elapsed_us":elapsed_us,"mean_tick_us":float(elapsed_us)/MEASURE_TICKS,"p50_tick_us":costs[costs.size()/2],"p95_tick_us":costs[int(costs.size()*0.95)-1],"max_tick_us":costs[-1],"signals":signals,"final_ecology_sha256":output.sha256_text(),"scene_publish_stub_calls":host.saves if host!=null else 0,"facts_source_sha256":facts.get_script().source_code.sha256_text() if facts!=null else ""}))
		if dynamic != null: dynamic.free()
		elif facts != null: facts.free()
		if host != null: host.free()
		WorldSim.sim = null
	print("CAMPAIGN_DYNAMIC_OBSERVER_COST_TEST %s checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
