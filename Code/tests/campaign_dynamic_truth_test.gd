## Real raw EcologySim events + registered scene objects. Fixture population/positions are staged explicitly;
## production observer, offers, actions, bindings, saved proof and HUD remain unmodified.
extends "res://tests/campaign_dynamic_runtime_test.gd"
var source_region := ""
var destination_region := ""
var third_region := ""
var historical := Vector2.INF

func _run() -> void:
	BiomeMap.configure(GameState.world_seed)
	GameState.campaign_quest=Data.create(GameState.world_seed)
	GameState.codex={}
	GameState.explored=PackedByteArray()
	GameState.exploration=ExplorationFog.new(GameState.world_seed)
	var evidence := {}
	for id: String in Data.Outpost.EVIDENCE: evidence[id]=true
	Data.authorize_chapter1(GameState.campaign_quest,{"id":"lost_outpost_v1","evidence":evidence,"outcome":"survey","survey_confirmed":true})
	GameState.campaign_quest.travel.unlocked=CampaignLayout.TERRAINS.duplicate()
	GameState.stats.level=100
	WorldSim.sim=fixture_sim()
	for inst: MonsterInstance in WorldSim.sim.instances.values():
		inst.age=1
		inst.lifespan=100000
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
	dynamic.facts.set_physics_process(false)
	host._main.set_physics_process(false)
	host._optional.set_physics_process(false)
	await migration_truth()
	await presentation_truth()
	print("CAMPAIGN_DYNAMIC_TRUTH_TEST %s checks=%d failures=%d" % ["PASS" if failures==0 else "FAIL",checks,failures])
	get_tree().quit(0 if failures==0 else 1)

func raw_migration(point: Vector2, two_boundaries := false) -> Dictionary:
	var sim := WorldSim.sim
	for region: SimRegion in sim.regions.values(): region.neighbor_ids.clear()
	(sim.regions[source_region] as SimRegion).neighbor_ids.append(destination_region)
	if two_boundaries: (sim.regions[destination_region] as SimRegion).neighbor_ids.append(third_region)
	var ordered := {}
	for key: String in [source_region,destination_region,third_region]: ordered[key]=sim.regions[key]
	for key: String in sim.regions:
		if not ordered.has(key): ordered[key]=sim.regions[key]
	sim.regions=ordered
	var actors: Array[Node2D]=[]
	for inst: MonsterInstance in sim.instances.values():
		if not inst.is_alive or inst.region_id!=source_region: continue
		var actor := FixtureActor.new()
		actor.inst=inst
		actor.position=point
		actor.add_to_group("monsters")
		add_child(actor)
		actors.append(actor)
	dynamic.facts._physics_process(0.2)
	var species := sim.find_species("fixture")
	species.expansion_threshold=0
	species.migrate_count=1
	sim.tick()
	species.migrate_count=0
	for actor: Node2D in actors: actor.free()
	return dynamic.facts.latest_migration(source_region)

func migration_truth() -> void:
	var id := "random_migration:"+str(GameState.world_seed)+":0"
	var origin := CampaignLayout.object_position(id+":giver")
	var old_pad := CampaignLayout.object_position(id+":target")
	source_region=BiomeMap.region_id_at(origin)
	for key: String in WorldSim.sim.regions:
		if key==source_region: continue
		if destination_region.is_empty(): destination_region=key
		elif third_region.is_empty(): third_region=key
	# A fixture-held read clue only authorizes this region, never a hidden actor coordinate.
	dynamic.facts.obtain_clue(source_region,"fixture:previously_read_record")
	check(not dynamic._prepare_migration(id),"no genuine event means no migration offer or historical binding")
	var far := Vector2.INF
	for offset: Vector2 in [Vector2(16000,0),Vector2(-16000,0),Vector2(0,16000),Vector2(0,-16000)]:
		if BiomeMap.region_id_at(origin+offset)==source_region: far=origin+offset; break
	check(far.is_finite(),"negative fixture has a far point in the same enormous patch")
	var event := raw_migration(far)
	check(event.get("from_position",[])==[far.x,far.y],"real migration captured actual loaded source position")
	GameState.fog_reveal_position(far)
	check(not dynamic._prepare_migration(id),"same-patch event over6000 away cannot publish an unrelated local pad")
	for offset: Vector2 in [Vector2(512,0),Vector2(-512,0),Vector2(0,512),Vector2(0,-512)]:
		var candidate := origin+offset
		if candidate.distance_to(old_pad)>256 and dynamic._site_walkable(candidate,source_region) and dynamic._site_has_approach(candidate,source_region) and dynamic._route_exists(origin,candidate): historical=candidate; break
	check(historical.is_finite(),"positive fixture has a genuinely local safe historical point distinct from old pad")
	event=raw_migration(historical)
	check(not dynamic._prepare_migration(id),"unknown historical point is not exposed by a region-wide clue")
	GameState.fog_reveal_position(historical)
	check(dynamic._prepare_migration(id),"genuine local source event creates bounded safe historical binding")
	var target := dynamic._position(id+":target")
	check(target.distance_to(historical)<=384 and target.distance_to(old_pad)>128,"actual object moved to event site, not arbitrary authored pad")
	var destination := CampaignWorldFacts.migration_position(event,destination_region)
	check(CampaignWorldFacts.migration_position(event,source_region)==historical and destination!=historical,"source uses from_position and destination uses its own recorded endpoint")
	var selected := dynamic.facts.local_migration_site(destination_region,destination,func(point: Vector2) -> Vector2: return point)
	check(not selected.is_empty() and selected.position==destination and selected.migration==event,"destination-side raw query selects its true endpoint independently")
	check(dynamic.facts.local_migration_site(source_region,origin,func(_point: Vector2) -> Vector2: return Vector2.INF).is_empty(),"no usable historical site yields no selection")
	dynamic._exposed[id]=true
	world.refresh_state(dynamic.visual_state())
	for role: String in CampaignEncounters.REQUIRED_ROLES.random_migration:
		await go(id+":"+role)
		dynamic._discover()
	await go(id+":giver")
	var blocked := dynamic._context(id)
	blocked.route_exists=func(_from: Vector2,_to: Vector2) -> bool: return false
	check(dynamic.encounters.candidate("random_migration",blocked).is_empty(),"unreachable actual site blocks offer even with known scene objects")
	var payload := dynamic.object_payload(id+":giver")
	check(payload.get("kind","")=="camp_action","eligible real known historical site offers explicit acceptance")
	var rebound := Vector2.INF
	for offset: Vector2 in [Vector2(128,0),Vector2(-128,0),Vector2(0,128),Vector2(0,-128)]:
		var point := historical+offset
		if dynamic._site_walkable(point,source_region) and dynamic._site_has_approach(point,source_region) and dynamic._route_exists(origin,point): rebound=point; break
	check(rebound.is_finite(),"preaccept rebind fixture has a different safe local historical point")
	GameState.fog_reveal_position(rebound)
	raw_migration(rebound)
	check(dynamic._known(id+":target"),"old physical target was genuinely observed before rebind")
	dynamic._prepare_migration(id)
	check(not dynamic._known(id+":target"),"unaccepted rebind clears knowledge of the former target even with new site's fog known")
	check(dynamic.encounters.candidate("random_migration",dynamic._context(id)).is_empty(),"new bound object must itself be observed before preview can return")
	historical=rebound
	target=dynamic._position(id+":target")
	await go(id+":target")
	dynamic._discover()
	await go(id+":giver")
	dynamic.object_payload(id+":giver")
	var preview: Dictionary=dynamic._previews.get(id,{}).duplicate(true)
	check(not preview.is_empty(),"actual observation of rebound node restores honest offer")
	event=raw_migration(historical)
	check(preview.get("proof",{}).get("migration",{})!=event,"later real event has a different immutable identity and time")
	var before := dynamic.encounters.total_issued()
	dynamic.accept_random(id)
	check(dynamic.encounters.total_issued()==before and dynamic.encounters.active().is_empty(),"stale preview rejects a newer event without spending a slot")
	dynamic.object_payload(id+":giver")
	dynamic.accept_random(id)
	check(dynamic.encounters.active().get("id","")==id,"fresh preview accepts matching event and site")
	if dynamic.encounters.active().is_empty(): return
	var accepted: Dictionary=dynamic.encounters.active().proof.duplicate(true)
	var binding: Dictionary=dynamic._runtime().bindings[id+":target"].duplicate(true)
	raw_migration(historical+Vector2(32,0),true)
	dynamic._prepare_migration(id)
	check(dynamic.encounters.active().proof==accepted and dynamic._runtime().bindings[id+":target"]==binding,"later true migration cannot repoint accepted event or target")
	var witness: MonsterInstance=WorldSim.sim.instances[int(accepted.migration.instance_id)]
	var actor := FixtureActor.new()
	actor.inst=witness
	actor.position=origin+Vector2(1700,0)
	actor.visible=false
	actor.add_to_group("monsters")
	add_child(actor)
	var action: Dictionary=Catalog.action(id,id+":site")
	check(dynamic.next_target(action).position==target and dynamic.next_target(action).object_id==id+":target","hidden live actor location never replaces historical guidance")
	check(dynamic.encounters.refresh_active(dynamic._context(id)).state=="migrated","moved target remains honestly closable at fixed historical site")
	WorldSim.sim._die(witness,EcologySim.DEATH_AGING)
	actor.free()
	check(dynamic.encounters.refresh_active(dynamic._context(id)).state=="lost","real target death becomes lost, without spawning a replacement")
	await go(id+":giver")
	dynamic.perform_action(id+":request")
	check(dynamic._done(Catalog.action(id,id+":request")),"actual request record is read before site action")
	player.position=old_pad
	await frames()
	dynamic.perform_action(id+":site")
	check(not dynamic._done(action),"standing at unrelated old pad cannot satisfy historical site action")
	var node := world.object_node(id+":target")
	node.position=old_pad
	check(dynamic.encounters.refresh_active(dynamic._context(id)).state=="site_unavailable","even a moved registered object cannot silently redefine accepted site")
	world.refresh_state(dynamic.visual_state())
	# Real CharacterBody movement crosses the final interaction boundary at the genuine scene object.
	player.position=target+Vector2(0,144)
	await frames()
	player.move_and_collide(Vector2(0,-112))
	await frames()
	check(node.can_interact(),"actual body movement reaches the fixed historical object")
	dynamic.perform_action(id+":site")
	check(dynamic._done(action),"correct actual site accepts truthful disappearance evidence")
	var proof: Dictionary=GameState.campaign_quest.quests[id].evidence.get(id+":site",{})
	check(proof.get("outcome","")=="lost" and proof.get("events",[])==[accepted.migration] and proof.get("target_position",[])==accepted.site_position,"saved site proof distinguishes historic event from later lost outcome")
	await go(id+":return")
	dynamic.perform_action(id+":report")
	check(Data.ready(GameState.campaign_quest,id) and Data.paid(GameState.campaign_quest,id),"disappearance closes finite encounter through actual return interaction")
	var cold := Data.sanitize(JSON.parse_string(JSON.stringify(GameState.campaign_quest)),GameState.world_seed)
	check(cold.dynamic_runtime.bindings[id+":target"]==binding and cold.encounters.instances[id].proof==CampaignEncounters._proof(accepted,GameState.world_seed),"JSON sanitation retains exact accepted event/site after death and later migrations")
	check(cold.quests[id].evidence[id+":site"]==proof,"JSON sanitation retains immutable observation outcome and event identity")
	check(cold.encounters.instances[id].proof.migration==accepted.migration and cold.encounters.instances[id].proof.site_position==accepted.site_position,"independent cold assertions retain original migration/event/site, not just sanitizer output")
	check(int(cold.encounters.instances[id].seed)==GameState.world_seed and cold.encounters.instances[id].proof.region_id==accepted.region_id and int(cold.encounters.instances[id].issued_tick)>=int(accepted.migration.tick),"cold accepted contract preserves world identity, endpoint region and chronology")

func stage_before_archive(chain: String) -> Dictionary:
	dynamic._bind_ecology()
	world.refresh_state(dynamic.visual_state())
	if chain=="world_decline":
		await go("world_decline:last_site")
		dynamic.action(["clue","world_decline:last_site"])
	for stage: Dictionary in Catalog.chain(chain).steps:
		await go(dynamic._stage_object(stage))
		dynamic.accept_world(stage.id,dynamic._stage_object(stage))
		check(GameState.campaign_quest.quests.get(stage.id,{}).get("accepted",false),"real world stage accepted "+stage.id)
		for a: Dictionary in stage.actions:
			if str(a.id)==chain+":s3:archive": break
			await go(a.object)
			dynamic.perform_action(a.id)
			check(dynamic._done(a),"real prerequisite observation recorded "+a.id)
	check(Dynamic.recorded_investigation(GameState.campaign_quest,chain).is_empty(),"unfinished investigation does not appear as completed codex annotation")
	return GameState.campaign_quest.duplicate(true)

func check_archive(base: Dictionary, chain: String, outcome: String, hud: Node) -> void:
	# Independent fixture branch from a genuinely earned pending archive. Each closure still goes through the scene action.
	GameState.campaign_quest=base.duplicate(true)
	dynamic._sync()
	var id := chain+":s3:archive"
	var object_id := str(Catalog.action(chain+":s3",id).object)
	await go(object_id)
	dynamic.perform_action(id)
	var record := Dynamic.recorded_investigation(GameState.campaign_quest,chain)
	check(not record.is_empty() and record.proof.outcome==outcome,"actual scene closure stores honest "+outcome)
	if record.is_empty(): return
	var text := Dynamic.investigation_text(record)
	check(text.contains(Dynamic.INVESTIGATION_OUTCOMES[outcome]) and text.contains("历史触发") and text.contains("结案采样") and text.contains(str(record.trigger.source)),"archive displays recorded outcome, distinct timestamps and actual source "+outcome)
	var saved := JSON.stringify(GameState.campaign_quest)
	var money := [GameState.gold,GameState.stats.xp,GameState.codex.duplicate(true)]
	for repeat in 3:
		var payload := dynamic.object_payload(object_id)
		var lines := str(payload.get("text", "")).split("\n")
		var current: Dictionary = dynamic.facts.migration_status(record.trigger) if chain == "world_migration" else dynamic.facts.decline_status(record.trigger)
		check(lines.size() >= 2 and lines[0].contains(str(record.trigger.species)) and lines[0].contains(Dynamic.INVESTIGATION_OUTCOMES[outcome]) and lines[1].contains("现在") and lines[1].contains(str(Dynamic.INVESTIGATION_OUTCOMES.get(current.get("state", ""), current.get("state", "")))), "completed endpoint distinguishes the saved species/outcome from the separately labelled actual current outcome " + outcome)
		hud.call("_refresh_codex")
		var label: Label=hud.get("codex_content")
		check(label.text.contains(text),"actual codex label includes saved factual note "+outcome)
	check(JSON.stringify(GameState.campaign_quest)==saved and money==[GameState.gold,GameState.stats.xp,GameState.codex],"reopening codex and endpoint changes no facts, receipts, rewards or kills "+outcome)
	var cold := Data.sanitize(JSON.parse_string(saved),GameState.world_seed)
	check(Dynamic.investigation_text(Dynamic.recorded_investigation(cold,chain))==text,"cold-sanitized completed note preserves recorded outcome "+outcome)
	if outcome=="endangered":
		var label: Label=hud.get("codex_content")
		check(GameState.codex.get("fixture",0)==0 and label.text.contains("fixture  调查记录（未曾猎杀）"),"never-killed species receives factual investigation note without fabricated kill credit")
		var incomplete := cold.duplicate(true)
		incomplete.quests[chain+":s3"].evidence.erase(id)
		check(Dynamic.recorded_investigation(incomplete,chain).is_empty(),"missing final archive proof cannot reveal a completed note")
	if outcome in ["continuing","endangered"]:
		await reading_layout(hud,object_id,record)
func presentation_truth() -> void:
	fixture_story_progress()
	check(not dynamic.facts.migration_trigger().is_empty(),"actual repeated two-boundary migrations provide world investigation trigger")
	var hud: Node=preload("res://scenes/ui/hud.tscn").instantiate()
	add_child(hud)
	hud.set_process(false)
	var base := await stage_before_archive("world_migration")
	await check_archive(base,"world_migration","continuing",hud)
	for tick in CampaignWorldFacts.MIGRATION_WINDOW: WorldSim.sim.tick()
	await check_archive(base,"world_migration","stopped",hud)
	for inst: MonsterInstance in WorldSim.sim.instances.values():
		if inst.is_alive: WorldSim.sim._die(inst,EcologySim.DEATH_AGING)
	await check_archive(base,"world_migration","lost",hud)
	# Separate real-ecology fixture for decline variants, with a genuinely observed three-tick trigger.
	GameState.campaign_quest=Data.create(GameState.world_seed)
	var evidence := {}
	for id: String in Data.Outpost.EVIDENCE: evidence[id]=true
	Data.authorize_chapter1(GameState.campaign_quest,{"id":"lost_outpost_v1","evidence":evidence,"outcome":"survey","survey_confirmed":true})
	GameState.campaign_quest.travel.unlocked=CampaignLayout.TERRAINS.duplicate()
	WorldSim.sim=fixture_sim()
	for inst: MonsterInstance in WorldSim.sim.instances.values():
		inst.age=100
		inst.lifespan=100000
	dynamic.configure_after_restore()
	dynamic.facts.set_physics_process(false)
	fixture_story_progress()
	var survivors := 0
	for inst: MonsterInstance in WorldSim.sim.instances.values():
		if survivors<5: survivors+=1
		else: WorldSim.sim._die(inst,EcologySim.DEATH_AGING)
	for tick in 3: WorldSim.sim.tick()
	base=await stage_before_archive("world_decline")
	await check_archive(base,"world_decline","endangered",hud)
	var species := WorldSim.sim.find_species("fixture")
	species.breeding_rate=1.0
	WorldSim.sim.tick()
	species.breeding_rate=0
	check(WorldSim.sim.alive_count_of_species("fixture")>=6,"actual reproduction yields recovered population")
	await check_archive(base,"world_decline","recovered",hud)
	for inst: MonsterInstance in WorldSim.sim.instances.values():
		if inst.is_alive: WorldSim.sim._die(inst,EcologySim.DEATH_AGING)
	await check_archive(base,"world_decline","naturally_absent",hud)
	WorldSim.sim.reintroduction_enabled=true
	for tick in 512:
		WorldSim.sim.tick()
		if WorldSim.sim.alive_count_of_species("fixture")>0: break
	WorldSim.sim.reintroduction_enabled=false
	check(WorldSim.sim.alive_count_of_species("fixture")>0,"actual reintroduction creates living targets before permanent-loss branch")
	for inst: MonsterInstance in WorldSim.sim.instances.values():
		if inst.is_alive: WorldSim.sim.report_killed(inst.id,inst.spawn_pos)
	dynamic.facts.flush_for_save()
	await check_archive(base,"world_decline","player_extinct",hud)
	await permanent_source_presentation(hud)
	hud.free()

func reading_layout(hud: Node, object_id: String, record: Dictionary) -> void:
	var root: Control=hud.get_node("Root")
	var initial := JSON.stringify(GameState.campaign_quest)
	var body: Label=hud.get("_dialogue_text")
	var panel: Control=hud.get("_dialogue_panel")
	var pages := Dynamic.investigation_pages(record)
	var capture_prefix := str(record.chain)+"_"+str(record.trigger.cause)
	check("".join(pages).replace("\n","")==Dynamic.investigation_text(record).replace("\n",""),"archive pagination retains every saved source character")
	for canvas: Vector2 in [Vector2(1280,720),Vector2(1560,720),Vector2(1024,640)]:
		if DisplayServer.get_name()!="headless":
			get_window().content_scale_size=Vector2i(canvas)
			get_window().size=Vector2i(canvas)
		root.set_anchors_preset(Control.PRESET_TOP_LEFT)
		root.position=Vector2.ZERO
		root.size=canvas
		await frames()
		hud.call("_open_dialogue",dynamic.object_payload(object_id))
		await frames()
		var scroll: ScrollContainer=hud.get("_dialogue_option_scroll")
		check(root.get_global_rect().encloses(panel.get_global_rect()),"archive menu stays inside actual canvas "+str(canvas))
		check(body.get_line_count()*body.get_line_height()<=122,"recorded/current summary fits above scroll options "+str(canvas))
		check(not body.get_global_rect().intersects(scroll.get_global_rect()),"summary and archive choices never overlap "+str(canvas))
		await capture_hud(hud,capture_prefix+"_menu",canvas)
		for index in pages.size():
			dynamic.action(["archive",object_id,str(index)])
			await frames()
			check(body.text==pages[index] and body.get_line_count()*body.get_line_height()<=194,"actual archive page fits existing reading surface %s page%d" % [canvas,index])
			check(root.get_global_rect().encloses(panel.get_global_rect()),"actual source page and controls fit canvas "+str(canvas))
			if index==mini(3,pages.size()-1): await capture_hud(hud,capture_prefix+"_source",canvas)
			hud.call("_on_dialogue_action","decline")
			await frames()
			check(hud.get("_dialogue_kind")=="camp_choice","actual Back returns to archive menu without repeating closure")
		hud.call("_close_dialogue")
		hud.call("_toggle_codex")
		await frames()
		var codex: Control=hud.get_node("Root/CodexLayer/CodexPanel")
		var codex_scroll: ScrollContainer=hud.get_node("Root/CodexLayer/CodexPanel/Margin/VB/CodexScroll")
		var codex_text: Label=hud.get("codex_content")
		var close: Button=hud.get_node("Root/CodexLayer/CodexPanel/Margin/VB/CodexClose")
		check(root.get_global_rect().encloses(codex.get_global_rect()) and codex.get_global_rect().encloses(close.get_global_rect()),"actual long-note codex and close control fit canvas "+str(canvas))
		check(codex_text.size.x<=codex_scroll.size.x,"codex source lines wrap inside disabled horizontal scroll "+str(canvas))
		check(codex_scroll.get_v_scroll_bar().max_value>codex_scroll.get_v_scroll_bar().page,"long factual notes remain available through actual vertical scroll "+str(canvas))
		await capture_hud(hud,capture_prefix+"_codex",canvas)
		codex_scroll.scroll_vertical=2147483647
		await frames()
		check(codex_scroll.scroll_vertical>0,"actual codex scrolling reaches the final content "+str(canvas))
		hud.call("_toggle_codex")
	check(JSON.stringify(GameState.campaign_quest)==initial,"all archive page Back/close and codex scroll operations remain read-only")
	root.size=Vector2(1280,720)
	var capture := OS.get_environment("HOTW_DYNAMIC_TRUTH_CAPTURE")
	if not capture.is_empty():
		DirAccess.make_dir_recursive_absolute(capture)
		var file := FileAccess.open(capture+"/"+capture_prefix+"_fixture.json",FileAccess.WRITE)
		if file!=null:
			file.store_string(JSON.stringify({"campaign_quest":GameState.campaign_quest,"ecology":WorldSim.sim.to_dict(),"fixture":"campaign_dynamic_truth_test"}))
			file.close()

func capture_hud(_hud: Node, label: String, canvas: Vector2) -> void:
	var directory := OS.get_environment("HOTW_DYNAMIC_TRUTH_CAPTURE")
	if directory.is_empty() or DisplayServer.get_name()=="headless": return
	DirAccess.make_dir_recursive_absolute(directory)
	await RenderingServer.frame_post_draw
	var path := directory+"/"+label+"_%dx%d.png" % [int(canvas.x),int(canvas.y)]
	var rendered := get_viewport().get_texture().get_image()
	check(rendered.get_size()==Vector2i(canvas),"actual rendered evidence matches requested canvas "+str(canvas))
	check(rendered.save_png(path)==OK,"actual rendered evidence saved "+path)

func permanent_source_presentation(hud: Node) -> void:
	GameState.campaign_quest=Data.create(GameState.world_seed)
	var evidence := {}
	for id: String in Data.Outpost.EVIDENCE: evidence[id]=true
	Data.authorize_chapter1(GameState.campaign_quest,{"id":"lost_outpost_v1","evidence":evidence,"outcome":"survey","survey_confirmed":true})
	GameState.campaign_quest.travel.unlocked=CampaignLayout.TERRAINS.duplicate()
	WorldSim.sim=fixture_sim()
	dynamic.configure_after_restore()
	dynamic.facts.set_physics_process(false)
	fixture_story_progress()
	for inst: MonsterInstance in WorldSim.sim.instances.values():
		if inst.is_alive: WorldSim.sim.report_killed(inst.id,inst.spawn_pos)
	dynamic.facts.flush_for_save()
	check(dynamic.facts.decline_trigger().get("cause","")=="permanent_extinction","genuine permanent-extinction trigger retains its longer authoritative source")
	var base := await stage_before_archive("world_decline")
	await check_archive(base,"world_decline","player_extinct",hud)
	await reading_layout(hud,"world_decline:observer",Dynamic.recorded_investigation(GameState.campaign_quest,"world_decline"))
