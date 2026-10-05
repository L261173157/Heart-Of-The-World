extends Node
const Dynamic := preload("res://scripts/main/campaign_dynamic.gd")
const Data := preload("res://scripts/main/campaign_quest_data.gd")
const Catalog := preload("res://scripts/main/campaign_catalog.gd")
class FixtureActor extends Node2D:
	var inst: MonsterInstance

class FixtureHost extends CampaignQuest:
	var batch := 4
	func _chapter_enabled(c: Dictionary) -> bool: return int(c.get("batch",99)) <= batch
	func visual_state() -> Dictionary:
		var value := super.visual_state()
		value.enabled_batch=batch
		return value
var dynamic: CampaignDynamic
var world: CampaignWorld
var host: FixtureHost
var player: CharacterBody2D
var checks := 0
var failures := 0
var moved_actors: Array[Node2D] = []
func _ready() -> void:
	GameState.save_enabled = false
	_run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("DYNAMIC FAIL: "+label)
func frames() -> void:
	await get_tree().physics_frame
	await get_tree().process_frame
func go(id: String) -> void:
	world.refresh_state(dynamic.visual_state())
	var node := world.object_node(id)
	check(node != null,"registered "+id)
	if node == null: return
	for offset: Vector2 in [Vector2(0,40),Vector2(40,0),Vector2(-40,0),Vector2(0,-40),Vector2.ZERO]:
		player.global_position = node.global_position+offset
		GameState.fog_reveal_position(player.global_position)
		await frames()
		if node.can_interact(): return
	check(false,"on-site interaction "+id)
func fixture_sim() -> EcologySim:
	var regions: Array = []
	for def: Dictionary in WorldConfig.region_defs():
		var r := SimRegion.new()
		r.id = def.id
		r.center = def.center
		r.size = def.size
		r.capacity = 1024
		r.terrain = def.terrain
		regions.append(r)
	var species := SpeciesData.new()
	species.species_name = "fixture"
	species.base_strength = 0.1
	species.base_agility = 0.1
	species.base_intellect = 0.1
	species.breeding_rate = 0
	species.migrate_count = 0
	species.expansion_threshold = 1000
	var population := {}
	for r: SimRegion in regions: population[r.id] = {"fixture":8}
	var sim := EcologySim.new()
	sim.predation_enabled = false
	sim.reintroduction_enabled = false
	var list: Array[SpeciesData] = [species]
	sim.setup(regions,list,population)
	return sim
func _run() -> void:
	BiomeMap.configure(GameState.world_seed)
	GameState.campaign_quest = Data.create(GameState.world_seed)
	var evidence := {}
	for id: String in Data.Outpost.EVIDENCE: evidence[id] = true
	Data.authorize_chapter1(GameState.campaign_quest,{"id":"lost_outpost_v1","evidence":evidence,"outcome":"survey","survey_confirmed":true})
	GameState.campaign_quest.travel.unlocked = CampaignLayout.TERRAINS.duplicate()
	GameState.stats.level = 100
	world = CampaignWorld.new()
	add_child(world)
	player = CharacterBody2D.new()
	player.add_to_group("player")
	add_child(player)
	WorldSim.sim = fixture_sim()
	host = FixtureHost.new()
	add_child(host)
	dynamic = host._dynamic
	await frames()
	dynamic.set_physics_process(false)
	check(dynamic.facts.snapshot().events.is_empty(),"initial setup has no fabricated ecological facts")
	for template: String in ["random_wounded","random_parcel","random_sign","random_rocks","random_medicine","random_message","random_runes"]:
		await complete_random(template)
	await complete_random("random_wounded")
	await complete_random("random_wounded")
	await complete_random("random_rocks")
	await complete_random("random_rocks")
	check(dynamic.encounters.snapshot().counts.random_wounded==3,"exactly three immutable per-template slots consumed")
	check(dynamic.encounters.candidate("random_wounded",{}).is_empty(),"fourth template instance can never be offered")
	await ecology_templates()
	await world_arcs()
	var damaged_cooldowns:=dynamic.encounters.snapshot()
	var expected_cooldowns: Dictionary=damaged_cooldowns.last_closed.duplicate()
	var expected_issue: int=damaged_cooldowns.last_issue_tick
	damaged_cooldowns.last_closed={}
	damaged_cooldowns.last_issue_tick=-45
	var repaired_cooldowns:=CampaignEncounters.sanitize(damaged_cooldowns,GameState.world_seed)
	check(repaired_cooldowns.last_closed==expected_cooldowns,"damaged family-cooldown index reconstructs from immutable instance closure times")
	check(repaired_cooldowns.last_issue_tick==expected_issue,"damaged global-cooldown index cannot backdate the last issued instance")
	host.batch = 3
	check(dynamic.accept_random("random_wounded:"+str(GameState.world_seed)+":1").contains("重新"),"batch three blocks random acceptance")
	host.batch = 4
	print("CAMPAIGN_DYNAMIC_RUNTIME_TEST %s checks=%d failures=%d" % ["PASS" if failures==0 else "FAIL",checks,failures])
	get_tree().quit(0 if failures==0 else 1)
func complete_random(template: String) -> void:
	WorldSim.sim.tick_count += 400
	GameState.campaign_quest.travel.unlocked = CampaignLayout.TERRAINS.duplicate()
	var ordinal: int = dynamic.encounters.snapshot().counts.get(template,0)
	var id := template+":"+str(GameState.world_seed)+":"+str(ordinal)
	if template=="random_migration": check(dynamic._prepare_migration(id),"bind actual known local historical migration site")
	dynamic._exposed[id] = true
	world.refresh_state(dynamic.visual_state())
	check(not dynamic._known(id+":giver"),"revealing registered objects does not mark them known")
	for role: String in CampaignEncounters.REQUIRED_ROLES[template]:
		await go(id+":"+role)
		dynamic._discover()
	check(dynamic._known(id+":giver"),"actual observed local giver becomes known")
	await go(id+":giver")
	var payload := dynamic.object_payload(id+":giver")
	check(payload.get("kind","") == "camp_action","candidate shown only in on-site menu "+template+" "+str(payload.get("text","")))
	if template=="random_camp":
		var preview: Dictionary = dynamic._previews.get(id,{})
		if not preview.is_empty():
			var actor := FixtureActor.new()
			actor.inst = WorldSim.sim.instances[int(preview.proof.target_ids[0])]
			actor.position = actor.inst.spawn_pos+Vector2(20000,0)
			actor.add_to_group("monsters")
			add_child(actor)
			var before := dynamic.encounters.total_issued()
			dynamic.accept_random(id)
			check(GameState.campaign_quest.active_random.is_empty() and dynamic.encounters.total_issued()==before,"stale preview revalidates current loaded actor positions without spending slot")
			check(actor.inst.spawn_pos.distance_to(actor.position)>6000,"negative actor test never changed ecology spawn position")
			actor.free()
			dynamic.object_payload(id+":giver")
	var result := dynamic.accept_random(id)
	check(GameState.campaign_quest.active_random == id,"matching data/engine accepted instance "+template+" "+result)
	if GameState.campaign_quest.active_random != id: return
	check(dynamic.encounters.active().id == id,"canonical ID shared by both ledgers")
	var stage := Catalog.stage(id)
	for a: Dictionary in stage.actions:
		if a.kind == "puzzle":
			await go(a.puzzle_objects[1])
			dynamic.touch_rune(a.id,a.puzzle_objects[1])
			check(not dynamic._done(a),"wrong rune does not finish")
			for rune: String in a.puzzle_objects:
				await go(rune)
				dynamic.touch_rune(a.id,rune)
			check(dynamic._done(a),"on-site sequence finishes finite puzzle")
			continue
		await go(str(a.object))
		if a.get("ecology_mode","") == "camp_resolution":
			var row := dynamic.encounters.active()
			var seen := FixtureActor.new()
			seen.inst=WorldSim.sim.instances[int(row.proof.target_ids[0])]
			seen.position=seen.inst.spawn_pos
			seen.add_to_group("monsters")
			add_child(seen)
			seen.visible=false
			check(dynamic.next_target(a).object_id==a.object,"hidden registered actor never leaks exact tracking coordinate")
			seen.visible=true
			check(dynamic.next_target(a).object_id=="" and dynamic.next_target(a).position==seen.global_position,"only currently observed actor gives precise live guidance")
			seen.position=seen.inst.spawn_pos+Vector2(200,120)
			var natural_position:=seen.global_position
			WorldSim.sim._die(seen.inst,EcologySim.DEATH_AGING)
			var natural_events:=dynamic.facts.death_evidence([int(row.proof.target_ids[0])],int(row.issued_tick))
			check(not natural_events.is_empty() and natural_events[-1].position==[natural_position.x,natural_position.y],"natural death retains actual loaded actor position rather than stale spawn")
			seen.free()
			check(dynamic.encounters.active().proof.credited_ids.is_empty(),"raw natural death is never credited as player kill")
			if ordinal==0:
				for n in int(row.proof.quota): WorldSim.sim.report_killed(int(row.proof.target_ids[n+1]),dynamic._position(id+":target"))
				check(dynamic.encounters.active().proof.credited_ids.size()==int(row.proof.quota),"only bound actual killed IDs satisfy accepted quota")
			else:
				WorldSim.sim.report_killed(int(row.proof.target_ids[1]),dynamic._position(id+":target"))
				for target_id: int in row.proof.target_ids:
					var actor := FixtureActor.new()
					actor.inst=WorldSim.sim.instances[target_id]
					if not actor.inst.is_alive:
						actor.free()
						continue
					actor.position=actor.inst.spawn_pos+Vector2(20000,0)
					actor.add_to_group("monsters")
					add_child(actor)
					moved_actors.append(actor)
				var status := dynamic.encounters.refresh_active(dynamic._context(id))
				check(status.state=="migrated" and status.can_survey_close and status.credited_ids.size()==1,"postaccept moved actors allow truthful survey while preserving one real player contribution")
		if a.kind == "obstacle":
			dynamic.perform_action(str(a.id))
			check(not dynamic._done(a),"uncleared authored rocks reject result")
			for cell: Vector2i in CampaignLayout.barrier_cells(str(a.barrier_id)):
				for hit in 4: ObstacleField.damage_cell(cell)
			dynamic._route_cache.clear()
		if a.kind == "route":
			dynamic.perform_action(str(a.id))
			check(not dynamic._done(a),"teleport to endpoint is not traversed route")
			var start: Vector2 = world.object_node(a.route_waypoints[0]).global_position
			var end: Vector2 = world.object_node(a.route_waypoints[1]).global_position
			await go(a.route_waypoints[0])
			dynamic._last_position = player.global_position
			dynamic._track_route()
			player.global_position=end+Vector2(0,40)
			dynamic._track_route()
			dynamic._track_route()
			check(GameState.campaign_quest.optional_routes.get(a.id,[]).size()==1,"teleport preserves earned route point but cannot grant destination")
			await go(a.route_waypoints[0])
			dynamic._track_route()
			for point: Vector2 in [start+Vector2(0,-288),end+Vector2(0,-288),end]:
				var previous:=player.global_position
				var count:=maxi(1,ceili(previous.distance_to(point)/24.0))
				for step in range(1,count+1):
					player.global_position=previous.lerp(point,float(step)/count)
					dynamic._track_route()
			dynamic.perform_action(str(a.id))
			check(not dynamic._done(a) and int(dynamic._runtime().route_steps.get(a.id,0))==0,"the genuinely walkable old outer detour cannot certify the destroyed rock gap")
			await go(a.route_waypoints[0])
			dynamic._track_route()
			for step in range(1,21):
				player.global_position = start.lerp(end,float(step)/20)
				dynamic._track_route()
			await go(a.object)
		var real_position := player.global_position
		player.global_position += Vector2(2000,0)
		dynamic.perform_action(str(a.id))
		check(not dynamic._done(a),"stale remote action rejected "+str(a.id))
		player.global_position = real_position
		result = dynamic.perform_action(str(a.id))
		check(dynamic._done(a),"actual role action "+str(a.id)+" "+result)
	check(Data.ready(GameState.campaign_quest,id) and Data.paid(GameState.campaign_quest,id),"finite receipt "+id)
	check(dynamic.encounters.active().is_empty(),"paid terminal clears one-active slot")
	var count := dynamic.encounters.total_issued()
	dynamic.accept_random(id)
	check(dynamic.encounters.total_issued()==count,"duplicate acceptance cannot issue a second instance")
	var q := Data.sanitize(JSON.parse_string(JSON.stringify(GameState.campaign_quest)),GameState.world_seed)
	check(Data.ready(q,id) and Data.paid(q,id),"cold restore preserves actions and receipt "+id)
	for actor: Node2D in moved_actors: actor.free()
	moved_actors.clear()

func ecology_templates() -> void:
	var sim := WorldSim.sim
	# Fixture species are real EcologySim individuals; relocate their fixture starting positions into the authored local arena.
	var camp_id := "random_camp:"+str(GameState.world_seed)+":0"
	var at := CampaignLayout.object_position(camp_id+":target")
	var region_id := BiomeMap.region_id_at(at)
	for inst: MonsterInstance in sim.instances.values():
		if inst.region_id == region_id: inst.spawn_pos = at+Vector2(48,0)
	GameState.fog_reveal_position(at)
	await complete_random("random_camp")
	await complete_random("random_camp")
	# A real active nest is placed by the pure fixture's region center; runtime still discovers/binds it and never manufactures a nest.
	var nest_id := "random_nest:"+str(GameState.world_seed)+":0"
	var giver := CampaignLayout.object_position(nest_id+":giver")
	region_id = BiomeMap.region_id_at(giver)
	var region: SimRegion = sim.regions[region_id]
	var species := sim.find_species("fixture")
	var original := sim.camp_pos(region,species)
	region.center += giver+Vector2(200,0)-original
	GameState.fog_reveal_position(giver)
	dynamic._prepare_nest(nest_id)
	check(dynamic._runtime().bindings.has(nest_id+":target"),"real active nest binds once before publication")
	await complete_random("random_nest")
	var migration_id := "random_migration:"+str(GameState.world_seed)+":0"
	var local := BiomeMap.region_id_at(CampaignLayout.object_position(migration_id+":giver"))
	var other: Array = []
	for r: SimRegion in sim.regions.values():
		r.neighbor_ids.clear()
		if r.id != local and other.size()<2: other.append(r.id)
	(sim.regions[local] as SimRegion).neighbor_ids.append(str(other[0]))
	(sim.regions[other[0]] as SimRegion).neighbor_ids.append(str(other[1]))
	var ordered: Dictionary={}
	for key: String in [local,str(other[0]),str(other[1])]: ordered[key]=sim.regions[key]
	for key: String in sim.regions:
		if not ordered.has(key): ordered[key]=sim.regions[key]
	sim.regions=ordered
	var migration_actors := stage_local_migration(migration_id)
	species.migrate_count = 3
	species.expansion_threshold = 2
	for inst: MonsterInstance in sim.instances.values():
		inst.age = 1
		inst.lifespan = 100000
	sim.tick()
	for actor: Node2D in migration_actors: actor.free()
	species.migrate_count = 0
	dynamic._earn_record_clues()
	check(not dynamic.facts.migration_trigger().is_empty(),"actual expansion plus a read local record triggers world migration")
	await complete_random("random_migration")

func stage_local_migration(id: String) -> Array[Node2D]:
	# Explicit fixture staging before a real tick: the observer samples actual loaded actor positions.
	# No production binding, event ledger, migration signal or accepted evidence is manufactured here.
	var origin := CampaignLayout.object_position(id+":giver")
	var region := BiomeMap.region_id_at(origin)
	var historical := Vector2.INF
	for offset: Vector2 in [Vector2(512,0),Vector2(-512,0),Vector2(0,512),Vector2(0,-512),Vector2(256,256)]:
		var candidate := origin+offset
		if dynamic._site_walkable(candidate,region) and dynamic._site_has_approach(candidate,region) and dynamic._route_exists(origin,candidate):
			historical=candidate
			break
	check(historical.is_finite(),"fixture has an actual safe local migration origin")
	var actors: Array[Node2D] = []
	if not historical.is_finite(): return actors
	GameState.fog_reveal_position(historical)
	for inst: MonsterInstance in WorldSim.sim.instances.values():
		if not inst.is_alive or inst.region_id!=region: continue
		var actor := FixtureActor.new()
		actor.inst=inst
		actor.position=historical
		actor.add_to_group("monsters")
		add_child(actor)
		actors.append(actor)
	dynamic.facts._physics_process(0.2)
	return actors

func fixture_story_progress() -> void:
	# This is prerequisite ledger scaffolding. The tests below perform every dynamic-world action through actual scene objects.
	var q := GameState.campaign_quest
	for chain: Dictionary in Catalog.main_chapters()+Catalog.regional_arcs():
		if chain.family=="main": Data.accept_chapter(q,chain.id,100)
		for stage: Dictionary in chain.steps:
			if chain.family!="main": Data.accept(q,stage.id,100)
			for a: Dictionary in stage.actions:
				if a.get("optional",false): continue
				var proof := {"position":[100,200],"tick":WorldSim.sim.tick_count,"destination":a.object}
				if a.kind=="choice":
					var first: Variant = a.choices[0]
					proof.choice = first.id if first is Dictionary else first
					if a.chain=="region_forest": proof.choice="outer"
				var selected := str(proof.get("choice",Data.choice(q,a)))
				proof.destination = a.get("destination_by_choice",a.get("branch_objects",{})).get(selected,a.object)
				if a.kind=="puzzle": proof.order=a.puzzle_order
				if a.kind=="obstacle":
					proof.obstacle_key=a.get("barrier_id",a.object)
					proof.destroyed=true
				if a.kind=="encounter":
					proof.outcome="absent"
					proof.verified=true
				if a.kind=="route":
					proof.route=selected if not selected.is_empty() else a.routes[0]
					proof.traversed=true
					proof.visit_ids=a.get("route_by_choice",{}).get(selected,a.get("route_waypoints",[]))
					if a.get("obstacle_by_choice",{}).has(selected):
						proof.obstacle_key=a.obstacle_by_choice[selected]
						proof.destroyed=true
				if a.kind=="ecology":
					proof.outcome="survey"
					proof.verified=true
				if a.has("quest_item"): proof.item=a.quest_item
				if a.has("consumes"): proof.item=a.consumes
				Data.record(q,stage.id,a.id,proof)
			Data.mark_paid(q,stage.id)
	q.travel.visited=["plains","forest","swamp"]
	check(Data.chapter_complete(q,"watch_c6_lava"),"explicit prerequisite scaffold completes main")
	check(dynamic._completed_nodes().size()>=3,"explicit prerequisite scaffold completes regional nodes")

func world_arcs() -> void:
	await binding_controls()
	fixture_story_progress()
	dynamic._ensure_relief_needs()
	check(Data._world_unlocked(GameState.campaign_quest,"world_relief"),"three visited biomes plus two authored resident needs unlock relief")
	var saved_visited: Array = GameState.campaign_quest.travel.visited.duplicate()
	GameState.campaign_quest.travel.visited=["forest","swamp"]
	check(Data._world_unlocked(GameState.campaign_quest,"world_relief"),"verified C1 plains plus forest/swamp and two genuine authored needs unlock relief")
	check(GameState.campaign_quest.travel.visited==["forest","swamp"],"C1 eligibility does not rewrite legacy visited arrays")
	GameState.campaign_quest.travel.visited=["forest","forest","forest"]
	check(not Data._world_unlocked(GameState.campaign_quest,"world_relief"),"duplicate visits cannot inflate the relief biome count")
	GameState.campaign_quest.travel.visited=["forest","worldsite:world_migration:route_a","watchnet:region_swamp_station"]
	check(not Data._world_unlocked(GameState.campaign_quest,"world_relief"),"opaque site/network destinations cannot masquerade as visited biomes")
	GameState.campaign_quest.travel.visited=["plains"]
	check(not Data._world_unlocked(GameState.campaign_quest,"world_relief"),"reward service stocks cannot bypass three real visited biomes")
	GameState.campaign_quest.travel.visited=saved_visited
	for chain: String in ["world_relief","world_watchnet","world_migration"]: await complete_world(chain)
	# New natural attrition produces a genuine 1-5 population for three distinct real ticks.
	var sim := WorldSim.sim
	var survivors := 0
	for inst: MonsterInstance in sim.instances.values():
		if not inst.is_alive: continue
		if survivors<5:
			survivors+=1
			continue
		sim._die(inst,EcologySim.DEATH_AGING)
	for i in 2: sim.tick()
	check(dynamic.facts.decline_trigger().is_empty(),"two actual low-population ticks do not trigger decline")
	sim.tick()
	check(not dynamic.facts.decline_trigger().is_empty(),"three actual low-population ticks trigger finite decline")
	dynamic._bind_ecology()
	world.refresh_state(dynamic.visual_state())
	await go("world_decline:last_site")
	dynamic.action(["clue","world_decline:last_site"])
	await complete_world("world_decline")
	var q := Data.sanitize(JSON.parse_string(JSON.stringify(GameState.campaign_quest)),GameState.world_seed)
	for chain: String in ["world_relief","world_watchnet","world_migration","world_decline"]: check(Data.ready(q,chain+":s3") and Data.paid(q,chain+":s3"),"world cold terminal receipt "+chain)

func complete_world(chain: String) -> void:
	dynamic._bind_ecology()
	world.refresh_state(dynamic.visual_state())
	for stage: Dictionary in Catalog.chain(chain).steps:
		await go(dynamic._stage_object(stage))
		var result := dynamic.accept_world(stage.id,dynamic._stage_object(stage))
		check(GameState.campaign_quest.quests.get(stage.id,{}).get("accepted",false),"actual world stage accepted "+str(stage.id)+" "+result)
		for a: Dictionary in stage.actions:
			await go(a.object)
			var choice := ""
			if a.kind=="configure": choice=",".join(dynamic._completed_nodes().slice(0,3))
			result=dynamic.perform_action(a.id,choice)
			check(dynamic._done(a),"actual world action "+str(a.id)+" "+result)
		check(Data.ready(GameState.campaign_quest,stage.id) and Data.paid(GameState.campaign_quest,stage.id),"world finite stage receipt "+str(stage.id))
	check(Data.ready(GameState.campaign_quest,chain+":s3"),"actual world terminal "+chain)
	if chain=="world_watchnet":
		await go("world_watchnet:node_1")
		check(dynamic.is_service_origin("world_watchnet:node_1"),"installed node is a real on-site service origin")
		check(dynamic.can_travel_node("world_watchnet:node_1",str(dynamic.selected_nodes()[1])),"completed selected node travel is actually usable")
		check(not dynamic.can_travel_node("world_watchnet:node_1","region_lava_station"),"unselected node cannot bypass selected network")
		check(dynamic.node_destination(str(dynamic.selected_nodes()[1])).is_finite(),"installed node has a safe physical destination")
	if chain=="world_relief":
		await go("world_relief:need_a")
		GameState.inventory["onigiri"]=99
		dynamic.claim_service("world_relief:need_a")
		check(not GameState.campaign_quest.services.world_relief_station.claimed and GameState.count_item("onigiri")==99,"full inventory keeps whole finite supply pending")
		GameState.inventory["onigiri"]=98
		dynamic.claim_service("world_relief:need_a")
		dynamic.claim_service("world_relief:need_a")
		check(GameState.campaign_quest.services.world_relief_station.claimed and GameState.count_item("onigiri")==99,"finite world supply pays exactly once after freeing room")


func binding_controls() -> void:
	var source: Dictionary=dynamic._historical_sources("world_migration").get("world_migration:route_a",{})
	check(not source.is_empty() and source.position.size()==2,"raw migration retains a genuine source position")
	if source.is_empty() or source.position.size()!=2: return
	var id:="world_migration:route_a"
	var original_bindings: Dictionary=dynamic._runtime().bindings.duplicate(true)
	var original_facts:=JSON.stringify(dynamic.facts.snapshot().events)
	var at:=Vector2(float(source.position[0]),float(source.position[1]))
	var center:=Vector2i(floori(at.x/32.0),floori(at.y/32.0))
	var old: Dictionary={}
	var cells: Array[Vector2i]=[]
	for radius: int in [1,14]:
		for y in range(center.y-radius,center.y+radius+1):
			for x in range(center.x-radius,center.x+radius+1):
				var cell:=Vector2i(x,y)
				if not old.has(cell): old[cell]={"had":CampaignLayout._geometry.has(cell),"value":CampaignLayout._geometry.get(cell,"")}
				CampaignLayout._geometry[cell]="castle"
				if not cell in cells: cells.append(cell)
		ObstacleField.invalidate_authored_cells(cells)
		dynamic._runtime().bindings.erase(id)
		dynamic._route_cache.clear()
		dynamic._bind_world_site(id,str(source.region_id),{"position":source.position})
		check(ObstacleField.nav_blocked_at(at),"controlled historical source really is blocked in gameplay navigation")
		if radius==1:
			var binding: Dictionary=dynamic._runtime().bindings.get(id,{})
			check(not binding.is_empty(),"blocked source relocates only the authored observation marker to nearby dry reachable ground")
			if not binding.is_empty():
				var relocated:=Vector2(float(binding.position[0]),float(binding.position[1]))
				check(relocated.distance_to(at)<=384 and BiomeMap.region_id_at(relocated)==str(source.region_id) and dynamic._site_walkable(relocated,str(source.region_id)),"relocated marker stays within384 pixels and in the genuine raw source region")
		else:
			check(not dynamic._runtime().bindings.has(id) and not dynamic._world_eligible("world_migration"),"no reachable local observation candidate prevents world acceptance, without static-layout fallback")
		check(JSON.stringify(dynamic.facts.snapshot().events)==original_facts,"observation relocation never rewrites the actual raw migration positions")
	for cell: Vector2i in old:
		if old[cell].had: CampaignLayout._geometry[cell]=old[cell].value
		else: CampaignLayout._geometry.erase(cell)
	ObstacleField.invalidate_authored_cells(cells)
	dynamic._route_cache.clear()
	dynamic._runtime().bindings=original_bindings
	world.refresh_state(dynamic.visual_state())
