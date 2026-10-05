## Deterministic performance/conservation guard, independent of wall-clock speed.
## The only synthetic inputs are a three-region ecology and explicit cache-context negative controls.
extends Node
class CountingFacts extends CampaignWorldFacts:
	var snapshot_copies:=0
	func snapshot() -> Dictionary:
		snapshot_copies+=1
		return super.snapshot()
class CountingEncounters extends CampaignEncounters:
	var snapshot_copies:=0
	func snapshot() -> Dictionary:
		snapshot_copies+=1
		return super.snapshot()
class Host extends Node:
	var saves:=0
	var publishes:=0
	func ledger() -> Dictionary: return GameState.campaign_quest
	func _chapter_enabled(_c: Dictionary) -> bool: return true
	func _save() -> void: saves+=1
	func _publish() -> void: publishes+=1
var checks:=0
var failures:=0
func _ready() -> void:
	GameState.save_enabled=false
	_run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error("COPY GUARD FAIL: "+label)
func _run() -> void:
	GameState.world_seed=734
	BiomeMap.configure(734)
	GameState.campaign_quest=CampaignQuestData.create(734)
	var regions: Array=[]
	for i in 3:
		var region:=SimRegion.new()
		region.id=["a","b","c"][i]
		region.center=Vector2(i*2000,1000)
		region.size=Vector2(2000,2000)
		region.capacity=1024
		region.neighbor_ids.append(["b","c","a"][i])
		regions.append(region)
	var species:=SpeciesData.new()
	species.species_name="copy_guard_fixture"
	species.breeding_rate=0
	species.migrate_count=3
	species.expansion_threshold=2
	var types: Array[SpeciesData]=[species]
	var sim:=EcologySim.new()
	sim.predation_enabled=false
	sim.reintroduction_enabled=false
	sim.setup(regions,types,{"a":{"copy_guard_fixture":12}})
	for inst: MonsterInstance in sim.instances.values():
		inst.age=1
		inst.lifespan=100000
	WorldSim.sim=sim
	var host:=Host.new()
	add_child(host)
	var dynamic:=CampaignDynamic.new()
	var facts:=CountingFacts.new()
	var encounters:=CountingEncounters.new()
	dynamic.facts=facts
	dynamic.encounters=encounters
	dynamic.setup(host)
	add_child(dynamic)
	dynamic.set_physics_process(false)
	dynamic.configure_after_restore()
	facts.obtain_clue("a","fixture:read_record")
	var observed:={"migrations":0}
	sim.instance_migrated.connect(func(_inst: MonsterInstance,_region: String) -> void: observed.migrations+=1)
	for tick in 12: sim.tick()
	check(int(observed.migrations)>30,"many genuine raw migrations exercised the hot listener")
	check(facts.snapshot_copies==0 and encounters.snapshot_copies==0,"raw-event write-through never calls either full snapshot API")
	check(is_same(GameState.campaign_quest.world_facts,facts.persistence_state()),"live fact ledger binds the exact owner-managed state")
	check(is_same(GameState.campaign_quest.encounters,encounters.persistence_state()),"finite-instance ledger binds its exact owner-managed state")
	check(int(GameState.campaign_quest.world_facts.sequence)>=int(observed.migrations),"every raw event is already authoritative before deferred publication")
	check(host.saves==0 and host.publishes==0,"background facts do not call host save/publish every tick")
	dynamic.flush_for_save()
	check(facts.snapshot_copies==0 and encounters.snapshot_copies==0,"save preparation flushes bookkeeping without another whole-ledger copy")
	var old_tick:=sim.tick_count
	var old_sequence: int=facts.persistence_state().sequence
	var full:=dynamic.campaign_for_save(GameState.campaign_quest.duplicate(true),old_tick,true)
	check(dynamic.can_reuse_ecology_cache(old_tick),"a completed-tick matching snapshot can reuse the ordinary ecology cache")
	sim.tick()
	var current_sequence: int=facts.persistence_state().sequence
	check(current_sequence>old_sequence,"live evidence continues advancing after the saved cache pair")
	var cached:=dynamic.campaign_for_save(GameState.campaign_quest.duplicate(true),old_tick,false)
	check(int(cached.world_facts.sequence)==old_sequence and int(cached.world_facts.last_tick)==old_tick,"background serialization selects the exact historical companion to cached ecology")
	check(int(GameState.campaign_quest.world_facts.sequence)==current_sequence,"serializing an older cache pair never rolls back or drops live facts")
	GameState.campaign_quest.paused_chains.append("random_wounded")
	check(not dynamic.can_reuse_ecology_cache(old_tick),"a changed non-observer campaign context cannot reuse the older world pair")
	GameState.campaign_quest.paused_chains.clear()
	check(dynamic.can_reuse_ecology_cache(old_tick),"saved context is isolated from later live dictionary mutations")
	var isolated:=facts.snapshot()
	isolated.events.clear()
	isolated.sequence=-100
	check(int(facts.persistence_state().sequence)==current_sequence and not facts.persistence_state().events.is_empty(),"public fact snapshots remain independent deep copies")
	var isolated_instances:=encounters.snapshot()
	isolated_instances.counts.random_wounded=3
	check(encounters.total_issued()==0,"public instance snapshots cannot mutate the live slots")
	check(facts.snapshot_copies==1 and encounters.snapshot_copies==1,"only the two explicit reader requests incurred whole-snapshot copies")
	check(int(full.world_facts.sequence)==old_sequence,"a cached immutable save companion was not changed by later ecology")
	print("CAMPAIGN_DYNAMIC_COPY_GUARD_TEST %s checks=%d failures=%d raw_migrations=%d"%["PASS" if failures==0 else "FAIL",checks,failures,int(observed.migrations)])
	get_tree().quit(0 if failures==0 else 1)
