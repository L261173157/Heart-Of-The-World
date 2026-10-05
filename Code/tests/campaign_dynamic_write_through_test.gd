## Independent raw-event persistence controls. Production observer/runtime; explicitly synthetic three-region ecology.
## No event dictionaries, completed quests, kills or population changes are injected into the campaign ledger.
extends Node
class TestHost extends Node:
	func ledger() -> Dictionary: return GameState.campaign_quest
	func _chapter_enabled(_c: Dictionary) -> bool: return true
	func _save() -> void: pass
	func _publish() -> void: pass
var dynamic: CampaignDynamic
var host: TestHost
var sim: EcologySim
var checks := 0
var failures := 0
var callbacks := 0
var blocked_tmp := ""
var old_bytes := PackedByteArray()
var raw_migrations := 0
var cached_pair: Dictionary = {}
var cache_callbacks := 0
var cache_reuses := 0
var cache_current_captures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("WRITE THROUGH FAIL: " + message)
func _ready() -> void: _run.call_deferred()
func fixture_sim() -> EcologySim:
	var regions: Array = []
	for index in 3:
		var r := SimRegion.new()
		r.id = ["a", "b", "c"][index]
		r.center = Vector2(index * 2000, 1000)
		r.size = Vector2(2000, 2000)
		r.capacity = 1024
		r.neighbor_ids.append(["b", "c", "a"][index])
		regions.append(r)
	var species := SpeciesData.new()
	species.species_name = "write_through_fixture"
	species.breeding_rate = 0
	species.migrate_count = 3
	species.expansion_threshold = 2
	var types: Array[SpeciesData] = [species]
	var value := EcologySim.new()
	value.reintroduction_enabled = false
	value.predation_enabled = false
	value.setup(regions, types, {"a":{"write_through_fixture":12}})
	for inst: MonsterInstance in value.instances.values():
		inst.age = 1
		inst.lifespan = 100000
	return value
func canonical(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)))
func _run() -> void:
	GameState.save_enabled = false
	check(not OS.get_environment("HOTW_TEST_SAVE").is_empty(), "must use an isolated test save")
	if OS.get_environment("HOTW_TEST_SAVE").is_empty(): get_tree().quit(1); return
	GameState.world_seed = 734
	BiomeMap.configure(734)
	GameState.campaign_quest = CampaignQuestData.create(734)
	sim = fixture_sim()
	WorldSim.sim = sim
	host = TestHost.new()
	add_child(host)
	dynamic = CampaignDynamic.new()
	dynamic.setup(host)
	add_child(dynamic)
	dynamic.set_physics_process(false)
	dynamic.configure_after_restore()
	check(dynamic.facts.snapshot().events.is_empty(), "startup replay never creates fresh raw facts")
	# An explicit known-site fixture is only a clue precondition; it cannot manufacture a migration.
	dynamic.facts.obtain_clue("a", "fixture:read_record")
	var isolated_fact_copy := dynamic.facts.snapshot()
	isolated_fact_copy.clues.clear()
	isolated_fact_copy.sequence = 900000
	check(not dynamic.facts.known_clue("a").is_empty() and int(dynamic.facts.snapshot().sequence) == 0, "public fact snapshots remain isolated copies after listener optimization")
	var isolated_encounter_copy := dynamic.encounters.snapshot()
	isolated_encounter_copy.counts.random_wounded = 3
	check(dynamic.encounters.total_issued() == 0, "public encounter snapshots remain isolated copies after listener optimization")
	GameState.save_enabled = true
	check(GameState.save_now(true), "baseline full save succeeds")
	sim.instance_migrated.connect(_after_migrated)
	sim.tick()
	sim.instance_migrated.disconnect(_after_migrated)
	check(callbacks >= 3, "actual expansion exercised several immediate raw-event save listeners")
	check(not blocked_tmp.is_empty() and FileAccess.get_file_as_bytes(GameState.SAVE_PATH) == old_bytes, "failed writes never replace the last successful raw-event snapshot")
	check(DirAccess.remove_absolute(blocked_tmp) == OK, "remove only the test's deliberate temporary-path blocker")
	GameState._process(GameState.SAVE_DEBOUNCE + 0.01)
	check_saved_facts("scheduled retry")
	var pinned := dynamic.facts.migration_trigger()
	check(not pinned.is_empty(), "real migrations across two boundaries pin a genuine trigger")
	# Let a long normal fixture stream overflow the bounded ring without yielding a deferred scene publication.
	sim.instance_migrated.connect(func(_inst: MonsterInstance, _to: String) -> void: raw_migrations += 1)
	for tick in 100: sim.tick()
	var complete := dynamic.facts.snapshot()
	check(raw_migrations > CampaignWorldFacts.MAX_EVENTS, "actual raw-event burst exceeds persistent ring capacity")
	check(complete.events.size() == CampaignWorldFacts.MAX_EVENTS, "raw-event storage remains bounded")
	check(canonical(complete.triggers.world_migration) == canonical(pinned), "ring eviction never loses the pinned original trigger")
	check(GameState.save_now(true), "save immediately after raw burst succeeds without a deferred publish")
	check_saved_facts("immediate post-burst save")
	_test_background_pairs()
	var victim: MonsterInstance
	for inst: MonsterInstance in sim.instances.values():
		if inst.is_alive: victim = inst; break
	check(victim != null, "fixture retains live individuals; no zero-world restore workaround")
	var id := victim.id
	sim.instance_died.connect(_after_natural_death)
	sim._die(victim, EcologySim.DEATH_PREDATED)
	check(not dynamic.facts.death_evidence([id], sim.tick_count).is_empty(), "real predation death remains independently attributable")
	check_saved_facts("immediate natural-death save")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GameState.SAVE_PATH))
	var clean := CampaignQuestData.sanitize(saved.campaign_quest, 734)
	check(canonical(clean.world_facts) == canonical(dynamic.facts.snapshot()), "JSON ledger sanitation loses no completed raw event, trigger, clue or population state")
	check(clean.quests.is_empty() and clean.encounters.instances.is_empty(), "raw observation and persistence never fabricate content acceptance or rewards")
	print("CAMPAIGN_DYNAMIC_WRITE_THROUGH_TEST %s checks=%d failures=%d callbacks=%d burst_migrations=%d cache_reuses=%d cache_current_captures=%d" % ["PASS" if failures == 0 else "FAIL", checks, failures, callbacks, raw_migrations, cache_reuses, cache_current_captures])
	get_tree().quit(0 if failures == 0 else 1)
func _after_migrated(inst: MonsterInstance, to: String) -> void:
	callbacks += 1
	if callbacks == 3:
		old_bytes = FileAccess.get_file_as_bytes(GameState.SAVE_PATH)
		blocked_tmp = ProjectSettings.globalize_path(GameState.SAVE_PATH + ".tmp")
		check(DirAccess.make_dir_absolute(blocked_tmp) == OK, "block this raw-event save's temporary file")
	if callbacks >= 3:
		check(not GameState.save_now(true), "raw-event immediate write failure is reported honestly")
		check(FileAccess.get_file_as_bytes(GameState.SAVE_PATH) == old_bytes, "raw-event failed write keeps previous bytes")
		return
	check(GameState.save_now(true), "reentrant save from actual migration signal succeeds")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GameState.SAVE_PATH))
	var events: Array = saved.get("campaign_quest", {}).get("world_facts", {}).get("events", [])
	check(not events.is_empty() and int(events[-1].instance_id) == inst.id and events[-1].to_region == to and events[-1].kind == "migration", "same raw migration is present before deferred scene work")
	var current_region := ""
	for row: Dictionary in saved.get("ecology", {}).get("instances", []):
		if int(row.id) == inst.id: current_region = row.region
	check(current_region == to, "same saved snapshot contains the matching authoritative individual destination")
func _after_natural_death(inst: MonsterInstance, cause: String) -> void:
	check(cause == EcologySim.DEATH_PREDATED, "death control uses the actual natural cause")
	check(GameState.save_now(true), "reentrant save from genuine natural-death signal succeeds")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GameState.SAVE_PATH))
	var events: Array = saved.campaign_quest.world_facts.events
	check(events[-1].kind == "death" and events[-1].cause == EcologySim.DEATH_PREDATED and int(events[-1].instance_id) == inst.id, "immediate persisted death retains identity and predation cause, never kill credit")
func check_saved_facts(context: String) -> void:
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GameState.SAVE_PATH))
	check(canonical(saved.get("campaign_quest", {}).get("world_facts", {})) == canonical(dynamic.facts.snapshot()), context + " retains the exact authoritative fact ledger")
	check(canonical(saved.get("campaign_quest", {}).get("encounters", {})) == canonical(dynamic.encounters.snapshot()), context + " retains the exact finite-instance ledger")

func ecology_core(value: Dictionary) -> Dictionary:
	var copy := value.duplicate(true)
	copy.erase("day_time")
	copy.erase("game_day")
	return copy
func _test_background_pairs() -> void:
	check(GameState.save_now(true), "prime a genuine full ecology/fact pair before background-cache checks")
	cached_pair = JSON.parse_string(FileAccess.get_file_as_string(GameState.SAVE_PATH))
	sim.instance_migrated.connect(_after_cached_migration)
	sim.tick()
	sim.instance_migrated.disconnect(_after_cached_migration)
	check(cache_callbacks > 0, "genuine next-tick migrations exercised background saves before deferred publication")
	check(GameState.save_now(true), "explicit full save after cached writes captures current state")
	check_saved_facts("full save after background cache writes")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GameState.SAVE_PATH))
	check(canonical(ecology_core(saved.ecology)) == canonical(sim.to_dict()), "explicit full save contains exact current ecology after intermediate background saves")
func _after_cached_migration(_inst: MonsterInstance, _to: String) -> void:
	cache_callbacks += 1
	var current_facts := dynamic.facts.snapshot()
	var current_ecology := sim.to_dict()
	check(GameState.save_now(false), "reentrant background save during real migration succeeds")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GameState.SAVE_PATH))
	var uses_prior_ecology := canonical(ecology_core(saved.ecology)) == canonical(ecology_core(cached_pair.ecology))
	var uses_current_ecology := canonical(ecology_core(saved.ecology)) == canonical(current_ecology)
	check(uses_prior_ecology or uses_current_ecology, "background save uses a verified old or current ecology snapshot")
	if uses_prior_ecology: cache_reuses += 1
	elif uses_current_ecology: cache_current_captures += 1
	var expected: Dictionary = cached_pair.campaign_quest.world_facts if uses_prior_ecology else current_facts
	check(canonical(saved.campaign_quest.world_facts) == canonical(expected), "background cache never combines stale ecology with newer raw facts")
	check(canonical(dynamic.facts.snapshot()) == canonical(current_facts), "serializing an older paired snapshot never rolls back the live authoritative fact ledger")
