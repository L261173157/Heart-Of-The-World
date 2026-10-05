## Original Player, real obstacle bodies and actual attack input. No synthetic passage credit.
## Main prerequisites alone are ledger fixtures; all regional actions use their actual objects.
extends "res://tests/campaign_optional_runtime_test.gd"
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const LAYER := preload("res://scripts/main/terrain/obstacle_tile_layer.gd")
const SEEDS := [BiomeMap.DEFAULT_SEED,1,42,99,20261004,982451653,2147483647]
var layer: ObstacleTileLayer
var player: Player
var case_id := ""
var seed_value := 0

func _run() -> void:
	WorldSim.set_process(false)
	if OS.get_environment("HOTW_PASSAGE_COLD") == "1":
		await _cold_run()
	else:
		for value: int in SEEDS:
			seed_value = value
			GameState.world_seed = value
			BiomeMap.configure(value)
			await _build()
			for row: Array in [["swamp","near"],["hill","near"],["hill","outer"]]:
				await _case(row[0],row[1])
			_host.queue_free()
			_world.queue_free()
			player.queue_free()
			layer.queue_free()
			await _frames(3)
	if _fails == 0: print("=== CAMPAIGN REGIONAL PASSAGE PASS (%d checks; %s) ===" % [_checks,"cold" if OS.get_environment("HOTW_PASSAGE_COLD")=="1" else "7 seeds, 3 selected passages"])
	get_tree().quit(0 if _fails==0 else 1)

func _build() -> void:
	_world = World.new()
	add_child(_world)
	player = PLAYER_SCENE.instantiate() as Player
	_player = player
	player.get_node("Camera2D").enabled = false
	add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	_host = FixtureHost.new()
	add_child(_host)
	_attach_optional()
	_optional.set_physics_process(false)
	_host.changed.connect(_refresh)
	layer = LAYER.new()
	add_child(layer)
	_refresh()
	await _frames(3)

func _load_region(terrain: String) -> void:
	var at := CampaignLayout.object_position("region_"+terrain+":choice")-Vector2(0,256)
	for y in range(floori((at.y-576)/512),floori((at.y+576)/512)+1):
		for x in range(floori((at.x-576)/512),floori((at.x+576)/512)+1): layer._on_chunk_ready(Vector2i(x,y)*512)
	while not layer._lay_queue.is_empty(): layer._process(0)
	await _frames(3)

func _set_at(point: Vector2) -> void:
	player.teleport_to(point)
	_optional._track_routes()

func _walk(path: Array, track := true) -> bool:
	for point: Vector2 in path:
		var limit := 0
		while player.position.distance_to(point)>0.1 and limit<2000:
			limit += 1
			var step := player.position.direction_to(point)*minf(8.0,player.position.distance_to(point))
			var hit := player.move_and_collide(step)
			if track: _optional._track_routes()
			if hit!=null:
				_check(false,"%s seed%d actual body blocked %s toward %s" % [case_id,seed_value,player.position,point])
				return false
	return true

func _case(terrain: String, branch: String) -> void:
	case_id = "region_"+terrain+":"+branch
	_fresh()
	# Refresh loaded cells after the prior case's destroyed overlay is reset.
	layer.queue_free()
	await _frames(2)
	layer = LAYER.new()
	add_child(layer)
	await _load_region(terrain)
	var chain := "region_"+terrain
	var aid := chain+":s3:walk"
	var a: Dictionary = Catalog.actions()[aid]
	var passage := CampaignLayout.regional_passage(terrain,branch)
	var center: Vector2 = passage.center
	var direction: Vector2 = passage.direction
	var lane := center-Vector2(0,32) if branch=="near" else center
	var approach := lane-direction*96
	var exit := lane+direction*96
	var geometry: PackedVector2Array = CampaignLayout.region_routes(terrain)[branch]
	_check(geometry==CampaignLayout.region_routes(terrain)[branch] and geometry.size()==(2 if branch=="near" else 4),case_id+" seeded route is stable and keeps its authored marker count")
	_set_at(approach)
	_check(player.move_and_collide(exit-approach)!=null,case_id+" intact registered repair physically blocks original Player")
	await _accept_and_finish_stage(chain+":s1")
	await _go(chain+":choice")
	_optional.accept_stage(chain+":s2",chain+":choice")
	_optional.perform_action(chain+":s2:choice",branch)
	await _go(chain+":work_"+branch)
	if branch=="near":
		_optional.perform_action(chain+":s2:work")
		_check(not Data.ready(GameState.campaign_quest,chain+":s2"),case_id+" intact obstacle cannot be certified by clicking work")
		await _attack_rocks(passage.id)
		_check(_optional._barrier_destroyed(passage.id),case_id+" actual attack input destroys every registered rock")
		await _go(chain+":work_"+branch)
	_optional.perform_action(chain+":s2:work")
	_check(Data.ready(GameState.campaign_quest,chain+":s2"),case_id+" selected repair completed at its real object")
	await _frames(4)
	_set_at(approach)
	_check(player.move_and_collide(exit-approach)==null,case_id+" repaired gap/gate really permits original Player body")
	await _go(chain+":station")
	_optional.accept_stage(chain+":s3",chain+":station")
	await _go(chain+":work_"+branch)
	_optional._track_routes()
	_check(GameState.campaign_quest.optional_routes.get(aid,[]).size()==1,case_id+" actual work endpoint starts route prefix")
	# The old walk goes around the wall/gate. Reach station continuously, never the repaired plane.
	var at := CampaignLayout.object_position(chain+":choice")-Vector2(0,256)
	var detour: Array = [at+Vector2(-256,256),at+Vector2(384,256),at+Vector2(384,-384),at+Vector2(0,-320)] if branch=="near" else [at+Vector2(384,256),at+Vector2(384,-384),at+Vector2(0,-320)]
	_walk(detour)
	_optional.perform_action(aid)
	_check(not _optional._done(a) and not _optional._passage_proven(a),case_id+" destruction/opening plus genuine outer detour cannot finish")
	# The revised authored markers themselves form a reachable real-body route.
	_reanchor(a)
	var work := CampaignLayout.object_position(chain+":work_"+branch)
	_set_at(work)
	_reanchor(a)
	_walk(Array(geometry))
	_walk([CampaignLayout.object_position(chain+":station")])
	_check(_optional._passage_proven(a) and _optional._verify(a,{}).is_empty(),case_id+" revised authored markers are actually walkable and certify selected passage")
	GameState.campaign_quest.optional_route_passages.erase(aid)
	# Older saves can retain all original marker contributions, but no invented gap receipt.
	GameState.campaign_quest.optional_route_steps[aid] = geometry.size()
	GameState.campaign_quest.optional_routes[aid] = _optional._route_points(a)
	_cold()
	_optional.perform_action(aid)
	_check(not _optional._done(a) and not _optional._passage_proven(a),case_id+" old full marker counts never migrate into crossing proof")
	_check(_optional.next_target(a).get("object_id","missing")=="",case_id+" old partial route receives usable passage guidance")
	# Reanchor at the retained station prefix, then walk back around to the true approach.
	_reanchor(a)
	var return_path: Array = [at+Vector2(384,-384),at+Vector2(384,256),at+Vector2(-256,256),at+Vector2(-256,-16),approach] if branch=="near" else [at+Vector2(384,-384),at+Vector2(384,256),approach]
	_walk(return_path)
	_walk([lane-direction*8])
	player.teleport_to(lane+direction*8)
	_optional._track_routes()
	_optional._track_routes()
	_check(not _optional._passage_proven(a) and GameState.campaign_quest.optional_route_reanchor.get(aid,false),case_id+" even a 16px teleport across the open gap is rejected")
	var retained: Array = GameState.campaign_quest.optional_routes[aid].duplicate()
	_cold()
	_check(GameState.campaign_quest.optional_routes[aid]==retained and GameState.campaign_quest.optional_route_reanchor.get(aid,false),case_id+" cold sanitize preserves genuine prefix and teleport reanchor")
	_reanchor(a)
	_walk(return_path)
	GameState.campaign_quest.paused_chains.append(chain)
	_walk([exit])
	_check(not _optional._passage_proven(a),case_id+" abandoned route cannot earn passage credit")
	GameState.campaign_quest.paused_chains.erase(chain)
	_walk([approach])
	_walk([exit])
	_check(_optional._passage_proven(a),case_id+" continuous original Player movement through selected passage succeeds")
	var receipt: Dictionary = GameState.campaign_quest.optional_route_passages.get(aid,{}).duplicate(true)
	player._die()
	_optional._track_routes()
	player._respawn()
	_optional._track_routes()
	_check(_optional._passage_proven(a) and GameState.campaign_quest.optional_route_reanchor.get(aid,false),case_id+" real death and respawn preserve proof while requiring reanchor")
	_reanchor(a)
	_check(GameState.campaign_quest.optional_route_passages.get(aid,{})==receipt,case_id+" travel/reanchor does not discard already earned passage")
	_set_at(player.position+Vector2(1024,0))
	_check(GameState.campaign_quest.optional_route_reanchor.get(aid,false),case_id+" interrupted partial proof is saved with reanchor required")
	await _independent_cold(a)
	_reanchor(a)
	# Finish in this process too, keeping already-paid legacy stages unchanged through migration.
	_optional.perform_action(aid)
	_optional.perform_action(chain+":s3:station")
	_check(Data.ready(GameState.campaign_quest,chain+":s3") and Data.paid(GameState.campaign_quest,chain+":s3"),case_id+" verified route finishes and pays once")
	var wallet := GameState.gold
	var legacy := GameState.campaign_quest.duplicate(true)
	legacy.erase("optional_route_passages")
	GameState.campaign_quest = Data.sanitize(legacy,GameState.world_seed)
	_refresh()
	_host._settle_ready()
	_optional.perform_action(aid)
	_optional.perform_action(chain+":s3:station")
	_check(Data.ready(GameState.campaign_quest,chain+":s3") and Data.paid(GameState.campaign_quest,chain+":s3") and GameState.gold==wallet,case_id+" old paid completion remains completed without duplicate payout")
	print("REGIONAL PASSAGE case=%s seed=%d checks=%d" % [case_id,seed_value,_checks])

func _reanchor(a: Dictionary) -> void:
	var anchor := _optional._route_anchor(a)
	_set_at(anchor)
	_walk([anchor+Vector2(0,8)])
	_check(not GameState.campaign_quest.optional_route_reanchor.get(a.id,false),case_id+" physical step at retained anchor resumes route")

func _attack_rocks(id: String) -> void:
	for cell: Vector2i in CampaignLayout.barrier_cells(id):
		var target := (Vector2(cell)+Vector2(0.5,0.5))*32
		_set_at(target-Vector2(44,0))
		for hit in 3:
			if ObstacleField.sample_cell(cell).is_empty(): break
			player.facing = Vector2.RIGHT
			player._attack_cooldown = 0
			TouchInput.queue_attack()
			player.set_physics_process(true)
			await _frames(24)
			player.set_physics_process(false)
			TouchInput.reset()
		await _frames(2)

func _independent_cold(a: Dictionary) -> void:
	var path := "user://regional-passage-%d-%s.json" % [seed_value,case_id.replace(":","-")]
	var prior_path := GameState.SAVE_PATH
	GameState.SAVE_PATH = path
	GameState.destroyed_cells.assign(ObstacleField.destroyed_list())
	GameState.save_enabled = true
	_check(GameState.save_now(),case_id+" real atomic partial-progress save succeeds")
	GameState.save_enabled = false
	GameState.SAVE_PATH = prior_path
	var old_save := OS.get_environment("HOTW_TEST_SAVE")
	OS.set_environment("HOTW_TEST_SAVE",ProjectSettings.globalize_path(path))
	OS.set_environment("HOTW_PASSAGE_COLD","1")
	OS.set_environment("HOTW_PASSAGE_ACTION",a.id)
	var output: Array = []
	var status := OS.execute(OS.get_executable_path(),["--headless","--path",ProjectSettings.globalize_path("res://"),"res://tests/campaign_regional_passage_test.tscn","--quit-after","4000"],output,true)
	OS.set_environment("HOTW_TEST_SAVE",old_save)
	OS.unset_environment("HOTW_PASSAGE_COLD")
	OS.unset_environment("HOTW_PASSAGE_ACTION")
	var text := "\n".join(output)
	text = RegEx.create_from_string("(?m)^ERROR: [0-9]+ resources still in use at exit \\(run with --verbose for details\\)\\.$").sub(text,"",true)
	text = RegEx.create_from_string("(?m)^ERROR: [0-9]+ RID allocations of type 'PN13RendererDummy14TextureStorage12DummyTextureE' were leaked at exit\\.$").sub(text,"",true)
	_check(status==0 and "CAMPAIGN REGIONAL PASSAGE PASS" in text and not "SCRIPT ERROR" in text and not "ERROR:" in text,case_id+" independent cold process restores proof, completes and cannot double-pay")
	if status!=0 or "CAMPAIGN REGIONAL PASSAGE PASS" not in text or "ERROR:" in text: print(text)

func _cold_run() -> void:
	seed_value = GameState.world_seed
	BiomeMap.configure(seed_value)
	ObstacleField.restore_destroyed(GameState.destroyed_cells)
	await _build()
	var aid := OS.get_environment("HOTW_PASSAGE_ACTION")
	var a: Dictionary = Catalog.actions()[aid]
	var chain: String = a.chain
	case_id = chain+":"+_optional._choice(a)
	await _load_region(chain.trim_prefix("region_"))
	_check(_optional._passage_proven(a),case_id+" independent cold load retains validated selected crossing")
	_check(GameState.campaign_quest.optional_routes.get(aid,[])==_optional._route_points(a),case_id+" independent cold load preserves old and new marker contribution")
	_reanchor(a)
	_optional.perform_action(aid)
	_optional.perform_action(chain+":s3:station")
	_check(Data.ready(GameState.campaign_quest,chain+":s3") and Data.paid(GameState.campaign_quest,chain+":s3"),case_id+" cold continuation really completes")
	var wallet := GameState.gold
	_cold()
	_optional.perform_action(aid)
	_optional.perform_action(chain+":s3:station")
	_host._settle_ready()
	_check(GameState.gold==wallet,case_id+" cold repeated submission cannot pay twice")
