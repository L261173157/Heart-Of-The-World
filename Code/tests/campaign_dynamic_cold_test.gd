## 独立进程 save_now/_load + EcologySim.restore_from_dict + 正式 CampaignQuest。
## 主线/区域前置是明示夹具；随机/世界行动与付款、所有生态事件均经过实际运行层。
extends "res://tests/campaign_dynamic_runtime_test.gd"
var phase := ""
var manifest_path := ""
var prior: Dictionary = {}

func _run() -> void:
	phase = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "verify"
	manifest_path = OS.get_environment("HOTW_TEST_SAVE")+".manifest.json"
	BiomeMap.configure(GameState.world_seed)
	ObstacleField.restore_destroyed(GameState.destroyed_cells)
	if phase=="init":
		GameState.campaign_quest=Data.create(GameState.world_seed)
		GameState.gold=0
		GameState.inventory={}
		GameState.stats.level=100
		GameState.stats.xp=0
		var evidence := {}
		for key: String in Data.Outpost.EVIDENCE: evidence[key]=true
		Data.authorize_chapter1(GameState.campaign_quest,{"id":"lost_outpost_v1","evidence":evidence,"outcome":"survey","survey_confirmed":true})
	else:
		check(FileAccess.file_exists(manifest_path),"previous independent process wrote manifest")
		prior=JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
		check(not GameState.campaign_quest.is_empty(),"actual GameState._load restored campaign")
	var sim:=fixture_sim()
	# Identical authored ecology fixture in every process; the runtime may never move or create its nest.
	var nid:="random_nest:"+str(GameState.world_seed)+":0"
	var giver:=CampaignLayout.object_position(nid+":giver")
	var nrid:=BiomeMap.region_id_at(giver)
	var nr: SimRegion=sim.regions[nrid]
	nr.center += giver+Vector2(200,0)-sim.camp_pos(nr,sim.find_species("fixture"))
	if phase!="init":
		var snapshot: Variant=GameState.ecology_snapshot
		check(snapshot is Dictionary,"actual save includes ecology snapshot")
		check(sim.restore_from_dict(sim.regions.values(),sim.species_list.duplicate(),snapshot),"actual EcologySim restore preserves identities/nests/time")
	else:
		for inst: MonsterInstance in sim.instances.values():
			inst.age=1
			inst.lifespan=100000
		var camp:=CampaignLayout.object_position("random_camp:"+str(GameState.world_seed)+":0:target")
		for inst: MonsterInstance in sim.instances.values():
			if inst.region_id==BiomeMap.region_id_at(camp): inst.spawn_pos=camp+Vector2(48,0)
	WorldSim.sim=sim
	world=CampaignWorld.new()
	add_child(world)
	player=CharacterBody2D.new()
	player.add_to_group("player")
	add_child(player)
	host=FixtureHost.new()
	add_child(host)
	dynamic=host._dynamic
	await frames()
	dynamic.set_physics_process(false)
	host._main.set_physics_process(false)
	host._optional.set_physics_process(false)
	if phase=="init":
		fixture_story_progress()
		dynamic._ensure_relief_needs()
	else: verify_loaded()
	var parts:=phase.split("|")
	match parts[0]:
		"accept": await accept_random_case(parts[1],int(parts[2]) if parts.size()>2 else 0)
		"progress","complete": await progress_random_case(parts[1],parts[0]=="complete",int(parts[2]) if parts.size()>2 else 0)
		"rock_cross_partial": await rock_cross_partial()
		"decline_start": begin_decline_case()
		"world_accept": await accept_world_case(parts[1])
		"world_progress","world_complete": await progress_world_case(parts[1],parts[0]=="world_complete")
		"service_full":
			await go("world_relief:need_a")
			GameState.inventory["onigiri"]=99
			dynamic.claim_service("world_relief:need_a")
			check(GameState.campaign_quest.services.world_relief_station.claimed and _pending_total("onigiri") > 0 and _pending_sources_unique(),"actual full save retains paid service and unique pending supply")
		"service_claim":
			await go("world_relief:need_a")
			check(GameState.campaign_quest.services.world_relief_station.claimed and GameState.count_item("onigiri")==99 and _pending_total("onigiri")>0,"cold full service keeps paid receipt and pending stock")
			var pending := GameState.pending_items.duplicate(true)
			dynamic.claim_service("world_relief:need_a")
			check(GameState.pending_items==pending,"cold replay does not duplicate pending stock")
			var remaining := _pending_total("onigiri")
			GameState.inventory["onigiri"]=98
			check(_claim_one_pending("onigiri") and _pending_total("onigiri")==remaining-1,"cold explicit claim transfers exactly one pending item")
			dynamic.claim_service("world_relief:need_a")
			dynamic.claim_service("world_relief:need_a")
			check(GameState.campaign_quest.services.world_relief_station.claimed and GameState.count_item("onigiri")==99,"actual finite service claims exactly once")
		"verify": await verify_terminal()
	persist_and_exit()

func go(id: String) -> void:
	await super.go(id)
	dynamic._discover()

func evidence_summary() -> Dictionary:
	var result: Dictionary={}
	for id: String in GameState.campaign_quest.get("quests",{}):
		if id.begins_with("random_") or id.begins_with("world_"): result[id]=GameState.campaign_quest.quests[id].evidence.duplicate(true)
	return result

func receipt_summary() -> Dictionary:
	var result: Dictionary={}
	for id: String in GameState.campaign_quest.get("quests",{}):
		if id.begins_with("random_") or id.begins_with("world_"):
			result[id]=GameState.campaign_quest.quests[id].receipt.duplicate(true)
	return result

func normalized(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)))

func migration_contracts() -> Dictionary:
	var contracts := {}
	for id: String in dynamic.encounters.persistence_state().instances:
		var row: Dictionary=dynamic.encounters.persistence_state().instances[id]
		if row.template_id!="random_migration": continue
		contracts[id]={"seed":row.seed,"issued_tick":row.issued_tick,"region_id":row.proof.get("region_id",""),"source":row.proof.get("source",""),"migration":row.proof.get("migration",{}),"site_position":row.proof.get("site_position",[])}
	return contracts

func verify_loaded() -> void:
	var q:=GameState.campaign_quest
	check(normalized(migration_contracts())==normalized(prior.get("migration_contracts",{})),"actual independent cold load retains accepted migration identity/source/tick/site")
	check(normalized(Dynamic.completed_investigation_notes(q))==normalized(prior.get("investigation_notes",{})),"actual independent cold load retains completed saved codex annotations")
	check(normalized(evidence_summary())==normalized(prior.get("evidence",{})),"every accepted/partial/complete action proof survives a real cold load")
	check(normalized(q.puzzle_progress)==normalized(prior.get("puzzles",{})),"actual cold load preserves unfinished rune prefix")
	check(normalized(q.dynamic_runtime.route_steps)==normalized(prior.get("route_steps",{})),"actual cold load preserves real registered-gap crossing evidence")
	check(normalized(dynamic.facts.snapshot().decline_runs)==normalized(prior.get("decline_runs",{})),"actual cold load preserves the first low-population witness before tick3")
	check(GameState.gold==int(prior.gold) and GameState.stats.xp==int(prior.xp),"actual cold load preserves gold/xp, no replay payment")
	check(normalized(receipt_summary())==normalized(prior.receipts),"actual cold load preserves every dynamic receipt")
	check(normalized(GameState.pending_items)==normalized(prior.get("pending_items",{})) and _pending_sources_unique(),"cold load preserves exact overflow quantities and unique source receipts")
	check(normalized(q.dynamic_runtime.bindings)==normalized(prior.bindings),"actual cold load preserves immutable world/nest anchors")
	check(normalized(dynamic.encounters.snapshot().counts)==normalized(prior.counts),"actual cold load does not reroll finite counts")
	check(dynamic.encounters.snapshot().active==prior.active and q.active_random==prior.active,"actual cold load agrees one active ID in both ledgers")
	check(int(dynamic.facts.snapshot().sequence)==int(prior.sequence),"restore-spawn/nest replay creates no fresh facts")
	check(WorldSim.sim.tick_count==int(prior.tick),"offline process time does not advance simulation cooldown")
	check(dynamic.encounters.snapshot().last_issue_tick==prior.last_issue_tick,"last issue cooldown persists exactly")
	check(normalized(dynamic.encounters.snapshot().last_closed)==normalized(prior.get("last_closed",{})),"each family closure cooldown persists exactly")
	check(normalized(dynamic.selected_nodes())==normalized(prior.nodes),"cold load retains selected actual network nodes")
	var total_gold:=0
	var total_xp:=0
	for receipt: Dictionary in receipt_summary().values():
		if receipt.paid:
			total_gold+=int(receipt.gold)
			total_xp+=int(receipt.xp)
	check(GameState.gold==total_gold,"real cumulative gold equals exactly the dynamic paid receipts")
	check(GameState.stats.xp==total_xp,"real cumulative XP equals exactly the dynamic paid receipts")

func persist_and_exit() -> void:
	dynamic._sync()
	GameState.save_enabled=true
	check(GameState.save_now(true),"actual full save_now atomically writes player/campaign/ecology")
	var state:=dynamic.encounters.snapshot()
	var file:=FileAccess.open(manifest_path,FileAccess.WRITE)
	check(file!=null,"manifest file writable")
	if file!=null:
		file.store_string(JSON.stringify({"gold":GameState.gold,"xp":GameState.stats.xp,"receipts":receipt_summary(),"pending_items":GameState.pending_items,
			"evidence":evidence_summary(),"puzzles":GameState.campaign_quest.puzzle_progress,"route_steps":GameState.campaign_quest.dynamic_runtime.route_steps,"decline_runs":dynamic.facts.snapshot().decline_runs,"bindings":GameState.campaign_quest.dynamic_runtime.bindings,"counts":state.counts,"active":state.active,
			"sequence":dynamic.facts.snapshot().sequence,"tick":WorldSim.sim.tick_count,"last_issue_tick":state.last_issue_tick,"last_closed":state.last_closed,
			"nodes":dynamic.selected_nodes(),"migration_contracts":migration_contracts(),"investigation_notes":Dynamic.completed_investigation_notes(GameState.campaign_quest)}))
		file.close()
	print("CAMPAIGN_DYNAMIC_COLD %s phase=%s checks=%d failures=%d"%["PASS" if failures==0 else "FAIL",phase,checks,failures])
	get_tree().quit(0 if failures==0 else 1)

func accept_random_case(template: String, ordinal := 0) -> void:
	while WorldSim.sim.tick_count-int(dynamic.encounters.snapshot().last_issue_tick)<45 or (dynamic.encounters.snapshot().last_closed.has(template) and WorldSim.sim.tick_count-int(dynamic.encounters.snapshot().last_closed[template])<300): WorldSim.sim.tick()
	var id:=template+":"+str(GameState.world_seed)+":"+str(ordinal)
	if template=="random_nest":
		var giver:=CampaignLayout.object_position(id+":giver")
		player.position=giver
		GameState.fog_reveal_position(giver)
		dynamic._prepare_nest(id)
	if template=="random_migration":
		var local:=BiomeMap.region_id_at(CampaignLayout.object_position(id+":giver"))
		var other: Array=[]
		for r: SimRegion in WorldSim.sim.regions.values():
			r.neighbor_ids.clear()
			if r.id!=local and other.size()<2: other.append(r.id)
		(WorldSim.sim.regions[local] as SimRegion).neighbor_ids.append(str(other[0]))
		(WorldSim.sim.regions[other[0]] as SimRegion).neighbor_ids.append(str(other[1]))
		var ordered: Dictionary={}
		for key: String in [local,str(other[0]),str(other[1])]: ordered[key]=WorldSim.sim.regions[key]
		for key: String in WorldSim.sim.regions:
			if not ordered.has(key): ordered[key]=WorldSim.sim.regions[key]
		WorldSim.sim.regions=ordered
		var migration_actors := stage_local_migration(id)
		var species:=WorldSim.sim.find_species("fixture")
		species.migrate_count=3
		species.expansion_threshold=2
		dynamic._earn_record_clues()
		WorldSim.sim.tick()
		for actor: Node2D in migration_actors: actor.free()
		species.migrate_count=0
		check(not dynamic.facts.migration_trigger().is_empty(),"genuine simulated expansion plus previously read local clue pins trigger")
	if template=="random_migration": check(dynamic._prepare_migration(id),"bind actual known local historical migration site")
	dynamic._exposed[id]=true
	for role: String in CampaignEncounters.REQUIRED_ROLES[template]: await go(id+":"+role)
	await go(id+":giver")
	var offered:=host.object_payload(id+":giver")
	check(offered.get("kind","")=="camp_action","actual local menu offers known eligible finite instance "+template+" "+str(offered.get("text","")))
	host.action(str(offered.get("action","")))
	check(dynamic.encounters.active().get("id","")==id and GameState.campaign_quest.active_random==id,"actual atomic canonical accept "+id)
	check(not Data.ready(GameState.campaign_quest,id),"acceptance alone never completes random stage")

func progress_random_case(template: String, complete: bool, ordinal := 0) -> void:
	var id:=template+":"+str(GameState.world_seed)+":"+str(ordinal)
	check(GameState.campaign_quest.active_random==id,"cold process resumes exact active instance")
	var actions: Array=Catalog.stage(id).actions
	var limit:=actions.size() if complete else (2 if template=="random_runes" else 1)
	for index in limit:
		var a: Dictionary=actions[index]
		if dynamic._done(a): continue
		await do_action(a)
	if not complete and template=="random_runes":
		var puzzle: Dictionary=actions[-1]
		await go(puzzle.puzzle_objects[0])
		host.action("campaign|dynamic|rune|"+str(puzzle.id)+"|"+str(puzzle.puzzle_objects[0]))
		check(GameState.campaign_quest.puzzle_progress.get(puzzle.id,[]).size()==1,"actual first rune is saved unfinished before process exit")
	if complete:
		check(Data.ready(GameState.campaign_quest,id) and Data.paid(GameState.campaign_quest,id),"actual random completion has paid receipt")
		check(dynamic.encounters.active().is_empty() and GameState.campaign_quest.active_random.is_empty(),"actual paid terminal releases only one active slot")
		var gold:=GameState.gold
		host.perform_action(str(actions[-1].id))
		host.claim(id)
		check(GameState.gold==gold,"repeated final action/claim does not pay again")
	else:
		check(dynamic._done(actions[0]) and not Data.ready(GameState.campaign_quest,id),"actual partial action persists without full reward")

func do_action(a: Dictionary) -> void:
	if a.kind=="puzzle":
		var prefix: int=GameState.campaign_quest.puzzle_progress.get(a.id,[]).size()
		for rune: String in a.puzzle_objects.slice(prefix):
			await go(rune)
			host.action("campaign|dynamic|rune|"+str(a.id)+"|"+rune)
	else:
		await go(str(a.object))
		if a.kind=="obstacle":
			for cell: Vector2i in CampaignLayout.barrier_cells(str(a.barrier_id)):
				for hit in 4: ObstacleField.damage_cell(cell)
		if a.kind=="route":
			await go(a.route_waypoints[0])
			dynamic._last_position=player.position
			dynamic._track_route()
			var start:=dynamic._position(a.route_waypoints[0])
			var end:=dynamic._position(a.route_waypoints[1])
			for step in range(1,21):
				player.position=start.lerp(end,float(step)/20)
				dynamic._track_route()
			await go(a.object)
		if a.get("ecology_mode","")=="camp_resolution":
			var row:=dynamic.encounters.active()
			for i in int(row.proof.quota): WorldSim.sim.report_killed(int(row.proof.target_ids[i]),dynamic._position(str(a.object)))
		var choice:="survey" if a.get("ecology_mode","")=="nest_resolution" else ""
		if a.kind=="configure": choice=",".join(dynamic._completed_nodes().slice(0,3))
		host.action("campaign|dynamic|act|"+str(a.id)+"|"+choice)
	check(dynamic._done(a),"formal dispatcher records actual role "+str(a.id))

func accept_world_case(stage_id: String) -> void:
	var stage:=Catalog.stage(stage_id)
	if stage_id=="world_decline:s1":
		var run: Dictionary=dynamic.facts.snapshot().decline_runs.get("fixture",{})
		check(int(run.get("count",0))==1 and run.get("position",[]).size()==2,"first decline witness really survived the prior process exit")
		if run.is_empty(): return
		var witness: MonsterInstance=WorldSim.sim.instances.get(int(run.witness_instance_id))
		check(witness!=null and witness.is_alive,"first-observation witness is a real restored individual")
		WorldSim.sim._die(witness,EcologySim.DEATH_AGING)
		check(WorldSim.sim.alive_count_in(str(run.region_id),WorldSim.sim.find_species("fixture"))==0,"genuine aging empties the original witness region before tick2")
		for i in 2: WorldSim.sim.tick()
		var trigger:=dynamic.facts.decline_trigger()
		check(not trigger.is_empty() and trigger.get("position",[])==run.position and int(trigger.get("witness_instance_id",0))==int(run.witness_instance_id),"tick3 trigger preserves the genuine first historical site despite the now-empty source region")
	dynamic._bind_ecology()
	await go(dynamic._stage_object(stage))
	if stage_id=="world_decline:s1": host.action("campaign|dynamic|clue|world_decline:last_site")
	var offered:=host.object_payload(dynamic._stage_object(stage))
	check(offered.get("kind","")=="camp_action","actual world stage menu offers eligible story")
	host.action(str(offered.get("action","")))
	check(GameState.campaign_quest.quests.get(stage_id,{}).get("accepted",false),"actual world stage accepted "+stage_id)

func progress_world_case(stage_id: String, complete: bool) -> void:
	var stage:=Catalog.stage(stage_id)
	check(GameState.campaign_quest.quests.get(stage_id,{}).get("accepted",false),"world accepted contract survived cold load")
	var limit: int=stage.actions.size() if complete else 1
	for index in limit:
		var a: Dictionary=stage.actions[index]
		if not dynamic._done(a): await do_action(a)
	if complete:
		check(Data.ready(GameState.campaign_quest,stage_id) and Data.paid(GameState.campaign_quest,stage_id),"actual finite world stage receipt "+stage_id)
		var gold:=GameState.gold
		host.perform_action(str(stage.actions[-1].id))
		host.claim(stage_id)
		check(GameState.gold==gold,"completed world stage cannot pay again")

func verify_terminal() -> void:
	for chain: String in ["world_migration","world_decline"]:
		var archived := Dynamic.recorded_investigation(GameState.campaign_quest,chain)
		check(not archived.is_empty() and Dynamic.investigation_text(archived).contains("结案采样"),"actual cold completed investigation has factual read-only archive "+chain)
	for template: String in CampaignEncounters.TEMPLATES:
		var id:=template+":"+str(GameState.world_seed)+":0"
		check(Data.ready(GameState.campaign_quest,id) and Data.paid(GameState.campaign_quest,id),"cold actual terminal template "+template)
	for chain: Dictionary in Catalog.world_arcs():
		for stage: Dictionary in chain.steps: check(Data.ready(GameState.campaign_quest,stage.id) and Data.paid(GameState.campaign_quest,stage.id),"cold actual world stage "+str(stage.id))
	for ordinal: int in [1,2]:
		var rock_id:="random_rocks:"+str(GameState.world_seed)+":"+str(ordinal)
		check(Data.ready(GameState.campaign_quest,rock_id) and Data.paid(GameState.campaign_quest,rock_id),"all three independent rock routes retain cold completion and receipts")
	check(dynamic.encounters.total_issued()==12 and dynamic.encounters.active().is_empty(),"twelve canonical slots used, no new active slot after reload")
	check(dynamic.selected_nodes().size()==3,"three installed selected nodes retained")
	for chain: String in ["world_migration","world_decline"]:
		var origin: String="world_migration:record_board" if chain=="world_migration" else "world_decline:observer"
		await go(origin)
		for target: String in dynamic.WORLD_SITE_IDS[chain]:
			if origin==target: continue
			var distance:=dynamic._position(origin).distance_to(dynamic._position(target))
			var candidates:=dynamic.expedition_candidates(target)
			check(dynamic.can_travel_site(origin,target) and not candidates.is_empty(),"earned historical site has a bounded real approach expedition "+target)
			check(host.can_travel("worldsite:"+target,origin),"formal host routes only the earned world-site expedition")
			check(host.travel_destination("worldsite:"+target).is_finite(),"formal host selects a real geometry-safe 700px hostile-clear approach")
			var nearest:=INF
			for position: Vector2 in candidates: nearest=minf(nearest,position.distance_to(dynamic._position(target)))
			check(nearest<=1536,"earned-site expedition reduces final approach to at most1536 pixels")
			print("WORLD_SITE_ACCESS ",target," direct=",snapped(distance,1.0)," approach=",nearest," candidates=",candidates.size())
	await go("world_watchnet:node_1")
	var visited_before: Array=GameState.campaign_quest.travel.visited.duplicate()
	host._on_travel_completed("worldsite:world_migration:route_a")
	host._on_travel_completed("watchnet:region_forest_station")
	check(GameState.campaign_quest.travel.visited==visited_before,"special world-site and network arrivals cannot inflate biome visits")
	check(dynamic.can_travel_node("world_watchnet:node_1",str(dynamic.selected_nodes()[1])),"actual cold network remains usable")
	check(not dynamic.can_travel_node("world_watchnet:node_1","region_lava_station"),"cold network cannot travel unselected node")
	check(GameState.campaign_quest.services.world_relief_station.claimed and GameState.count_item("onigiri")==99,"cold claimed world service cannot duplicate99 inventory")


func rock_cross_partial() -> void:
	var id:="random_rocks:"+str(GameState.world_seed)+":0"
	var actions: Array=Catalog.stage(id).actions
	check(GameState.campaign_quest.active_random==id,"partial crossing belongs to the existing exact rock instance")
	if not dynamic._done(actions[1]): await do_action(actions[1])
	var a: Dictionary=actions[-1]
	await go(a.route_waypoints[0])
	dynamic._last_position=player.position
	dynamic._track_route()
	var start:=dynamic._position(a.route_waypoints[0])
	var stop:=dynamic._rock_gap(a)+Vector2(48,0)
	for step in range(1,21):
		player.position=start.lerp(stop,float(step)/20)
		dynamic._track_route()
	check(int(dynamic._runtime().route_steps.get(a.id,0))==1 and GameState.campaign_quest.optional_routes.get(a.id,[]).size()==1 and not Data.ready(GameState.campaign_quest,id),"real gap crossing is saved as partial progress before reaching the far endpoint")

func begin_decline_case() -> void:
	var sim:=WorldSim.sim
	var keep: Array[int]=[]
	var source:=""
	for region: SimRegion in sim.regions.values():
		var local: Array[int]=[]
		for inst: MonsterInstance in sim.instances.values():
			if inst.is_alive and inst.region_id==region.id: local.append(inst.id)
		if local.size()>=4:
			keep.assign(local.slice(0,4))
			source=region.id
			break
	check(keep.size()==4,"four genuine individuals can form the low-population observation fixture")
	dynamic._mutating=true
	for inst: MonsterInstance in sim.instances.values():
		if inst.is_alive and not inst.id in keep: sim._die(inst,EcologySim.DEATH_AGING)
	dynamic._mutating=false
	var destination:=""
	for region: SimRegion in sim.regions.values():
		region.neighbor_ids.clear()
		if region.id!=source and destination.is_empty(): destination=region.id
	(sim.regions[source] as SimRegion).neighbor_ids.append(destination)
	var species:=sim.find_species("fixture")
	species.migrate_count=3
	species.expansion_threshold=2
	sim.tick()
	species.migrate_count=0
	var run: Dictionary=dynamic.facts.snapshot().decline_runs.get("fixture",{})
	check(int(run.get("count",0))==1 and str(run.get("region_id",""))==source and run.get("position",[]).size()==2,"first actual low-population tick pins its real local witness")
	check(sim.alive_count_in(source,species)==1 and sim.alive_count_in(destination,species)==3 and dynamic.facts.decline_trigger().is_empty(),"real migration leaves one origin survivor without prematurely triggering decline")
