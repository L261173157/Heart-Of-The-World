## 原始模拟信号夹具；不借 world_event，不在断言前伪造事实、迁徙或猎杀账本。
extends SceneTree
const Facts := preload("res://scripts/main/campaign_world_facts.gd")
const Encounters := preload("res://scripts/main/campaign_encounters.gd")
var failures := 0
var checks := 0
var _flags: Dictionary = {}
var _probe_region := "a"
var _known := true
var _reachable := true
var _stats := CharacterStats.new()

func _init() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("CAMPAIGN_WORLD_FACTS FAIL: "+message)
	else: print("PASS "+message)

func _species(name := "fixture", boss := false) -> SpeciesData:
	var s := SpeciesData.new()
	s.species_name = name
	s.is_boss = boss
	s.breeding_rate = 0.0
	s.migrate_count = 0
	s.expansion_threshold = 1000
	s.base_strength = 0.1
	s.base_agility = 0.1
	s.base_intellect = 0.1
	s.strength_growth = 0
	s.agility_growth = 0
	s.intellect_growth = 0
	return s

func _sim(count := 10, migrates := false, boss := false) -> EcologySim:
	var regions: Array = []
	for index in 3:
		var r := SimRegion.new()
		r.id = ["a","b","c"][index]
		r.center = Vector2(index*2000,0)
		r.size = Vector2(2000,2000)
		r.capacity = 1024
		if index < 2: r.neighbor_ids.append(["b","c"][index])
		regions.append(r)
	var species := _species("fixture",boss)
	if migrates:
		species.migrate_count = 3
		species.expansion_threshold = 2
	var types: Array[SpeciesData] = [species]
	var sim := EcologySim.new()
	sim.predation_enabled = false
	sim.reintroduction_enabled = false
	sim.setup(regions,types,{"a":{"fixture":count}})
	for inst: MonsterInstance in sim.instances.values():
		inst.age = 1
		inst.lifespan = 100000
		inst.spawn_pos = Vector2(0,0)
	return sim

func _facts(sim: EcologySim, saved := {}) -> CampaignWorldFacts:
	var facts := Facts.new()
	root.add_child(facts)
	facts.configure(sim,734,saved)
	return facts

func _test_migration() -> void:
	var sim := _sim(12,true)
	var facts := _facts(sim)
	_check(facts.snapshot().events.is_empty(),"setup population and nests are a baseline, no fresh fact")
	sim.tick()
	var migrations: Array = facts.snapshot().events.filter(func(e: Dictionary) -> bool: return e.kind == "migration")
	_check(migrations.size() >= 3,"actual EcologySim expansion emits at least three raw migration facts")
	_check(facts.migration_trigger().is_empty(),"multiple real migrations without obtained clue do not trigger")
	_check(facts.obtain_clue("a","fixture:read_route"),"valid acquired local clue is recorded")
	var trigger := facts.migration_trigger()
	_check(not trigger.is_empty(),"three real nonboss migrations across two boundaries plus clue trigger")
	var boundaries := {}
	for event: Dictionary in trigger.get("events",[]):
		boundaries[Facts._boundary(event)] = true
		_check(event.instance_id > 0 and event.from_region != event.to_region and event.seed == 734,
			"each migration retains actual identity, from/to and world seed")
	_check(boundaries.size() >= 2,"boundaries are from cached pre-signal regions, not overwritten destination")
	_check(facts.migration_status().state == "continuing","recent migration closure reports continuing")
	sim.find_species("fixture").migrate_count = 0
	for _i in 121: sim.tick()
	_check(facts.migration_status().state == "stopped","migration investigation can finish after movement has stopped")
	var saved := JSON.parse_string(JSON.stringify(facts.snapshot())) as Dictionary
	var copy := _facts(sim,saved)
	_check(JSON.stringify(copy.migration_trigger()) == JSON.stringify(trigger),"pinned original migration proof survives JSON reload after window expiry")
	_check(copy.snapshot().events.size() == facts.snapshot().events.size(),"configure does not replay population as fresh events")
	copy.free()
	facts.free()
	# Same-boundary round trips never satisfy two-region-boundary requirement.
	var simple := _sim(10,true)
	(simple.regions.b as SimRegion).neighbor_ids.clear()
	var one := _facts(simple)
	one.obtain_clue("a","fixture:one_boundary")
	simple.tick()
	_check(one.migration_trigger().is_empty(),"three actual moves across only one boundary do not trigger")
	one.free()
	var boss_sim := _sim(1,false,true)
	var boss_facts := _facts(boss_sim)
	boss_facts.obtain_clue("a","fixture:boss")
	for _i in 4: boss_sim.tick()
	_check(boss_facts.migration_trigger().is_empty() and boss_facts.decline_trigger().is_empty(),"Boss populations and repaired Boss movement cannot qualify ecological world lines")
	boss_facts.free()

func _test_decline() -> void:
	var sim := _sim(5)
	var facts := _facts(sim)
	sim.tick()
	sim.tick()
	_check(facts.decline_trigger().is_empty(),"endangered population for only two simulation ticks does not trigger")
	var saved := JSON.parse_string(JSON.stringify(facts.snapshot())) as Dictionary
	facts.free()
	facts = _facts(sim,saved)
	facts._on_tick(sim._build_summary())
	_check(facts.decline_trigger().is_empty(),"same-tick summary/reload does not count as another sustained tick")
	sim.tick()
	var trigger := facts.decline_trigger()
	_check(not trigger.is_empty() and trigger.cause == "sustained_decline","three consecutive actual tick summaries trigger decline")
	_check(trigger.baseline == 5 and trigger.start_tick == 1 and trigger.tick == 3,"decline proof preserves trigger baseline and precise interval")
	_check(facts.decline_status().state == "endangered","current endangered status is read from actual population")
	sim.spawn_instance(sim.find_species("fixture"),"a",1)
	_check(facts.decline_status().state == "recovered","real recovery may close old decline without reopening reward")
	var evidence := facts.snapshot()
	_check(Facts.sanitize(evidence,735).events.is_empty(),"other seed cannot leak facts or triggers")
	_check(Facts.sanitize({"seed":734,"events":[null,"bad",{"kind":"death"}],"clues":false,"decline_runs":3},734).events.is_empty(),"damaged fact fields are rejected safely")
	facts.free()
	var interrupted := _sim(5)
	var interrupted_facts := _facts(interrupted)
	interrupted.tick()
	interrupted.tick()
	interrupted.spawn_instance(interrupted.find_species("fixture"),"a",1)
	interrupted.tick()
	var victim: MonsterInstance = interrupted.instances.values()[0]
	interrupted.report_killed(victim.id)
	interrupted.tick()
	_check(interrupted_facts.decline_trigger().is_empty(),"one healthy tick resets endangered streak")
	interrupted_facts.free()

func _test_raw_deaths_and_bounds() -> void:
	var sim := _sim(1)
	var facts := _facts(sim)
	var inst: MonsterInstance = sim.instances.values()[0]
	sim.report_killed(inst.id,Vector2(16,32))
	var snapshot := facts.snapshot()
	_check(snapshot.events.size() == 2 and snapshot.events[0].cause == "killed", "actual final player kill records death and subsequently confirmed permanent extinction")
	_check(snapshot.events[0].position == [16.0,32.0],"actual reported death position is preserved")
	_check(facts.decline_trigger().cause == "permanent_extinction" and facts.decline_status().state == "player_extinct", "new permanent extinction has raw causal evidence and truthful closure")
	facts.free()
	var resumed := _facts(sim,{})
	_check(resumed.decline_trigger().is_empty() and resumed.snapshot().events.is_empty(),"existing extinction at configure is a baseline, never a new decline event")
	resumed.free()
	var natural := _sim(1)
	var natural_facts := _facts(natural)
	(natural.instances.values()[0] as MonsterInstance).lifespan = 1
	natural.tick()
	_check(natural_facts.snapshot().events[0].cause == "aging" and natural_facts.decline_trigger().is_empty(),"natural death is not player extinction or kill contribution")
	natural_facts.free()
	var plentiful := _sim(620,true)
	var bounded := _facts(plentiful)
	bounded.obtain_clue("a","fixture:bounded_route")
	plentiful.tick()
	var pinned := bounded.migration_trigger()
	for victim: MonsterInstance in plentiful.instances.values(): plentiful.report_killed(victim.id)
	var trimmed := bounded.snapshot()
	_check(trimmed.events.size() <= Facts.MAX_EVENTS,"long raw death stream has bounded persistent ring")
	_check(not pinned.is_empty() and trimmed.triggers.world_migration == pinned,"evicted raw event ring cannot destroy accepted world trigger evidence")
	_check(Facts.sanitize(trimmed,734).triggers.world_migration == pinned,"sanitizer preserves pinned evidence independently of ring")
	bounded.free()

func _probe(id: String) -> Dictionary:
	var out := {"id":id,"exists":true,"registered":true,"known":_known,"reachable":_reachable,
		"region_id":_probe_region,"position":Vector2.ZERO,"at_player":true,"needs_aid":true,
		"unclaimed":true,"recipient":true,"pending_repair":true,"breakable":true,"broken":false,
		"route_endpoint":true,"pending_need":true,"unsettled":true,"readable":true}
	out.merge(_flags,true)
	return out

func _context() -> Dictionary:
	return {"region_id":"a","origin":Vector2.ZERO,"probe_object":_probe,"stats":_stats,
		"known_position":func(_p: Vector2) -> bool: return _known,
		"route_exists":func(_from: Vector2,_to: Vector2) -> bool: return _reachable}

func _test_encounters() -> void:
	var sim := _sim(10)
	var facts := _facts(sim)
	var engine := Encounters.new()
	engine.configure(sim,734,{},facts)
	var context := _context()
	_check(engine.candidate("not_a_template",context).is_empty(),"unknown templates cannot issue")
	_check(engine.candidate("random_wounded",{}).is_empty(),"missing live context fails closed")
	for template: String in ["random_wounded","random_parcel","random_sign","random_rocks","random_medicine","random_message","random_runes"]:
		_check(not engine.candidate(template,context).is_empty(),template+" requires and accepts independently registered real authored objects")
	_flags = {"needs_aid":false}
	_check(engine.candidate("random_wounded",context).is_empty(),"uninjured NPC does not invent rescue demand")
	_flags = {"unclaimed":false}
	_check(engine.candidate("random_parcel",context).is_empty(),"recovered parcel is not issued again")
	_flags = {"pending_repair":false}
	_check(engine.candidate("random_sign",context).is_empty(),"already repaired sign is not issued")
	_flags = {"broken":true}
	_check(engine.candidate("random_rocks",context).is_empty(),"already destroyed barrier does not invent another obstacle")
	_flags = {"recipient":false}
	_check(engine.candidate("random_message",context).is_empty(),"message requires two actual recipients")
	_flags = {"unsettled":false}
	_check(engine.candidate("random_runes",context).is_empty(),"settled ruins cannot reroll")
	_flags = {}
	_known = false
	_check(engine.candidate("random_sign",context).is_empty(),"unknown object cannot issue")
	_known = true
	_reachable = false
	_check(engine.candidate("random_sign",context).is_empty(),"unreachable object cannot issue")
	_reachable = true
	_probe_region = "b"
	_check(engine.candidate("random_sign",context).is_empty(),"object outside current chapter region cannot issue")
	_probe_region = "a"
	_check(engine.candidate("random_migration",context).is_empty(),"authored marker alone cannot invent migration")
	var nest_pos := sim.camp_pos(sim.regions.a,sim.find_species("fixture"))
	_flags = {"position":nest_pos}
	_check(not engine.candidate("random_nest",context).is_empty(),"actual active reachable route-side nest can issue")
	sim.destroy_nest("a","fixture")
	_check(engine.candidate("random_nest",context).is_empty(),"historical nest existence does not prove current active nest")
	_flags = {}
	var preview := engine.candidate("random_sign",context)
	_flags = {"pending_repair":false}
	_check(not engine.accept(preview,context) and engine.total_issued() == 0,"accept rechecks stale preview and spends no slot when target changed")
	_flags = {}
	_check(engine.accept(preview,context),"fresh validated encounter accepted once")
	_check(engine.candidates(context).is_empty(),"one active encounter blocks every other template")
	_check(not engine.accept(preview,context),"duplicate accept does not spend another ordinal")
	_check(not engine.complete("finished",{}),"unvalidated action cannot close or auto-pay")
	_check(engine.record_action("parts","pickup",context),"on-site explicit action records stable evidence")
	_check(not engine.record_action("parts","pickup",context),"same action evidence remains one-time")
	_check(engine.complete("repaired",{"validated":true}),"caller-validated completed action closes finite instance")
	_check(engine.candidate("random_parcel",context).is_empty(),"global issue cooldown uses simulation tick")
	for _i in 45: sim.tick()
	_check(not engine.candidate("random_parcel",context).is_empty() and engine.candidate("random_sign",context).is_empty(),"45 ticks release global cooldown but same family still waits300")
	var persisted := JSON.parse_string(JSON.stringify(engine.snapshot())) as Dictionary
	engine.configure(sim,734,persisted,facts)
	_check(engine.total_issued() == 1 and engine.candidate("random_sign",context).is_empty(),"reload does not refresh quotas or family cooldown")
	for _i in 255: sim.tick()
	_check(engine.candidate("random_sign",context).id == "random_sign:734:1","same family after300ticks uses deterministic next ordinal")
	for ordinal in [1,2]:
		var next := engine.candidate("random_sign",context)
		_check(engine.accept(next,context),"finite ordinal accepted "+str(ordinal))
		engine.complete("repaired",{"validated":true})
		for _i in 300: sim.tick()
	_check(engine.candidate("random_sign",context).is_empty(),"per-template three-instance cap never resets with simulation time")
	var damaged := Encounters.sanitize({"seed":734,"instances":{"random_wounded:734:2":"broken"}},734)
	_check(damaged.counts.random_wounded == 3,"corrupted instance remains spent tombstone, no quota refund")
	facts.free()

func _test_actual_credit() -> void:
	var sim := _sim(10)
	var facts := _facts(sim)
	var engine := Encounters.new()
	engine.configure(sim,734,{},facts)
	var context := _context()
	var candidate := engine.candidate("random_camp",context)
	_check(not candidate.is_empty() and candidate.proof.quota <= candidate.proof.local_alive-1 and candidate.proof.global_alive-candidate.proof.quota >= 6,"finite camp quota leaves local survivors and global endangered threshold")
	if candidate.is_empty():
		facts.free()
		return
	_check(engine.accept(candidate,context),"actual feasible local population can bind an instance")
	var ids: Array = candidate.proof.target_ids
	var natural: MonsterInstance = sim.instances[ids[0]]
	natural.lifespan = natural.age
	sim.tick()
	_check(engine.active().proof.credited_ids.is_empty(),"real natural death never counts as player camp contribution")
	sim.report_killed(int(ids[1]))
	_check(engine.active().proof.credited_ids == [ids[1]],"real raw killed signal credits bound individual exactly once")
	var persisted := JSON.parse_string(JSON.stringify(engine.snapshot())) as Dictionary
	var restored := Encounters.new()
	restored.configure(sim,734,persisted,facts)
	_check(restored.active().proof.credited_ids == [ids[1]],"JSON reload preserves real contribution independently of currently living targets")
	for id: int in ids.slice(2):
		var inst: MonsterInstance = sim.instances[id]
		inst.lifespan = inst.age
	sim.tick()
	var current := restored.refresh_active(context)
	_check(current.can_survey_close and current.credited_ids == [ids[1]],"target depletion allows truthful on-site closure without discarding earned contribution")
	_check(sim.alive_count_of_species("fixture") == 0,"encounter engine never respawns missing targets")
	facts.free()
	var scarce := _sim(6)
	var scarce_facts := _facts(scarce)
	var protected_engine := Encounters.new()
	protected_engine.configure(scarce,734,{},scarce_facts)
	_check(protected_engine.candidate("random_camp",context).is_empty(),"camp at global6 cannot issue quota that would create endangered population")
	scarce_facts.free()

func _test_additional_negative_controls() -> void:
	var sim := _sim(12,true)
	var facts := _facts(sim)
	var engine := Encounters.new()
	engine.configure(sim,734,{},facts)
	sim.tick()
	_check(engine.candidate("random_migration",_context()).is_empty(),"unknown real migration cannot issue merely because its authored marker exists")
	facts.obtain_clue("a","fixture:actual_route_clue")
	_check(not engine.candidate("random_migration",_context()).is_empty(),"actual migration plus acquired local clue issues finite observation without waiting for next migration")
	var forged := facts.snapshot()
	var trigger: Dictionary = forged.triggers.world_migration
	trigger.events = [trigger.events[0],trigger.events[0],trigger.events[-1]]
	_check(not Facts.sanitize(forged,734).triggers.has("world_migration"),"duplicate event sequence cannot manufacture three distinct migration events")

	var malformed_event := {"kind":"death","seed":734,"instance_id":10,"species":"fixture","source":"EcologySim.instance_died","is_boss":"true","cause":"killed"}
	var cleaned := Facts.sanitize({"seed":734,"events":[malformed_event],"extinct_baseline":{"fixture":"true"}},734)
	_check(cleaned.events.size() == 1 and cleaned.events[0].is_boss == false and cleaned.extinct_baseline.is_empty(),"malformed boolean strings neither crash nor masquerade as authoritative facts")
	_check(Facts.sanitize({"seed":"734"},734).events.is_empty() and Encounters.sanitize({"seed":[]},734).instances.is_empty(),"wrong seed types fail closed in both pure sanitizers")
	var states := {}
	for template: String in Encounters.TEMPLATES: states[template] = 3
	var spent := Encounters.sanitize({"seed":734,"counts":states},734)
	engine.configure(sim,734,spent,facts)
	_check(engine.total_issued() == 30 and engine.candidates(_context()).is_empty(),"thirty spent slots remain exhausted even when detailed instance records were lost")
	facts.free()
	var quiet := _sim(5)
	var quiet_facts := _facts(quiet)
	quiet.tick()
	quiet.tick()
	quiet.tick_count += 10
	quiet.tick()
	_check(quiet_facts.decline_trigger().is_empty(),"missing observed ticks do not count as sustained decline through offline time")
	var last: int = quiet_facts.snapshot().events.size()
	quiet.instance_spawned.emit(quiet.instances.values()[0])
	_check(quiet_facts.snapshot().events.size() == last,"spawn replay signal only refreshes identity cache, never invents a new ecological fact")
	quiet_facts.free()

func _test_real_restore_and_splits() -> void:
	var sim := _sim(12,true)
	var facts := _facts(sim)
	facts.obtain_clue("a","fixture:restore_source")
	sim.tick()
	var saved_sim := JSON.parse_string(JSON.stringify(sim.to_dict())) as Dictionary
	var saved_facts := JSON.parse_string(JSON.stringify(facts.snapshot())) as Dictionary
	var saved_events: int = saved_facts.events.size()
	var restored := EcologySim.new()
	restored.reintroduction_enabled = false
	restored.predation_enabled = false
	_check(restored.restore_from_dict(sim.regions.values(),sim.species_list,saved_sim),"actual EcologySim.restore_from_dict restores real fixture identities and nests")
	var observer := _facts(restored,saved_facts)
	_check(observer.snapshot().events.size() == saved_events,"setup observer after actual restore ignores all restore-spawn/nest replay")
	_check(JSON.stringify(observer.migration_trigger()) == JSON.stringify(facts.migration_trigger()),"real restore retains the exact migration trigger proof")
	var original_tick := restored.tick_count
	restored.tick()
	_check(observer.snapshot().last_tick == original_tick+1,"restored observer resumes from next actual sim tick")
	observer.free()
	facts.free()
	var splitting := _sim(1)
	var species := splitting.find_species("fixture")
	species.splits_on_death = true
	species.max_generation = 1
	species.split_count = 2
	var watcher := _facts(splitting)
	var parent: MonsterInstance = splitting.instances.values()[0]
	splitting.report_killed(parent.id)
	_check(splitting.alive_count_of_species("fixture") == 2,"real split-death fixture creates two actual child instances")
	_check(watcher.decline_trigger().is_empty(),"pre-split death signal cannot falsely declare permanent extinction")
	var raw: Array = watcher.snapshot().events
	_check(raw.filter(func(e: Dictionary) -> bool: return e.kind == "extinction").is_empty(),"extinction ledger waits for post-split authoritative permanent flag")
	watcher.free()

func _run() -> void:
	_test_migration()
	_test_decline()
	_test_raw_deaths_and_bounds()
	_test_encounters()
	_test_actual_credit()
	_test_additional_negative_controls()
	_test_real_restore_and_splits()
	print("CAMPAIGN_WORLD_FACTS_TEST %s checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL",checks,failures])
	quit(0 if failures == 0 else 1)
