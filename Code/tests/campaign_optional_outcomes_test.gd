## 正常 WorldConfig 初始生态七种子：真实已有巢、实体标记、身体路径与共享服务。
## 冻结模拟/AI仅为可复现的几何和证据闸门，不修改任何实例/巢穴位置或数量。
extends "res://tests/campaign_optional_runtime_test.gd"
const GAME_WORLD := preload("res://scripts/main/game_world.gd")
const ACTUAL_PLAYER := preload("res://scenes/player/player.tscn")
const OBSTACLES := preload("res://scripts/main/terrain/obstacle_tile_layer.gd")
var layer: ObstacleTileLayer
var actors: Array[MonsterBase] = []
var nests: Array[NestNode] = []
var current_seed := 0

func _run() -> void:
	WorldSim.set_process(false)
	var tested_seeds: Array = [BiomeMap.DEFAULT_SEED,1,42,99,20261004,982451653,2147483647]
	if not OS.get_environment("HOTW_OUTCOME_SEED").is_empty(): tested_seeds=[int(OS.get_environment("HOTW_OUTCOME_SEED"))]
	for value: int in tested_seeds:
		current_seed = value
		GameState.world_seed = value
		BiomeMap.configure(value)
		seed(value)
		var regions: Array = []
		for definition: Dictionary in WorldConfig.region_defs():
			var region := SimRegion.new()
			for key: String in ["id","terrain","threat","center","size","capacity"]: region.set(key,definition[key])
			region.display_name = definition["name"]
			region.neighbor_ids.assign(definition["neighbors"])
			regions.append(region)
		var sim := EcologySim.new()
		sim.setup(regions,SpeciesCatalog.build_all(),WorldConfig.initial_population(),WorldConfig.boss_anchors())
		WorldSim.start(sim)
		WorldSim.set_process(false)
		_world = World.new()
		add_child(_world)
		_player = ACTUAL_PLAYER.instantiate()
		_player.get_node("Camera2D").enabled = false
		add_child(_player)
		_player.set_physics_process(false)
		_player.set_process(false)
		_host = FixtureHost.new()
		add_child(_host)
		_attach_optional()
		_host.changed.connect(_refresh)
		await _frames()
		_fresh()
		GameState.stats.level = 10
		GameState.stats.strength = 14
		GameState.stats.upgrade_weapon = 1
		GameState.stats.upgrade_vigor = 1
		GameState.stats.passives = {"hp":1,"phys":1}
		await _normal_forest(sim)
		for actor: MonsterBase in actors: actor.queue_free()
		for nest: NestNode in nests:
			if is_instance_valid(nest): nest.queue_free()
		actors.clear()
		nests.clear()
		if layer != null: layer.queue_free()
		_host.queue_free()
		_world.queue_free()
		_player.queue_free()
		WorldSim.stop()
		await _frames(3)
	# 各端点必须在实际 CampaignWorld 装配后可独立交互，但共享同一收据。
	_world = World.new()
	add_child(_world)
	_player = CharacterBody2D.new()
	_player.add_to_group("player")
	add_child(_player)
	_host = FixtureHost.new()
	add_child(_host)
	_attach_optional()
	_host.changed.connect(_refresh)
	await _frames()
	for branch in 2:
		_fresh()
		await _complete_chain(Catalog.chain("region_plains"),branch)
		var state := _optional.visual_state()
		_check(state.services.has("region_plains:station"),"平原始终保留实际接应站")
		_check(state.services.has("region_plains:work_outer") == (branch==1),"集中一个端点、分散两个真实端点")
		if branch==1:
			_check(_world.object_node("region_plains:station").position.distance_to(_world.object_node("region_plains:work_outer").position)>400,"分散服务两个端点物理位置不同")
			await _go("region_plains:work_outer")
			_check(_optional.object_payload("region_plains:work_outer").get("kind","")=="camp_choice","外缘第二端点真实开放商店和领取菜单")
			GameState.inventory["onigiri"]=0
			_optional.claim_service("region_plains:work_outer")
			_check(GameState.inventory.get("onigiri",0)==1,"外缘端点实际领取唯一库存")
			_cold()
			await _go("region_plains:station")
			_optional.claim_service("region_plains:station")
			_check(GameState.inventory.get("onigiri",0)==1,"主站冷恢复后共享库存墓碑、不复制第二份")
			_capture_snapshot("region_plains:s3",branch,"service")
			_service_damage_control("region_plains_station","region_plains:station")
	if _fails==0: print("=== CAMPAIGN OPTIONAL OUTCOMES PASS (%d checks, %d standard initial seeds) ===" % [_checks,tested_seeds.size()])
	get_tree().quit(0 if _fails==0 else 1)

func _normal_forest(sim: EcologySim) -> void:
	var initial_instances := sim.instances.size()
	var initial_nests := sim.nests.size()
	var original_positions := {}
	for inst: MonsterInstance in sim.instances.values(): original_positions[inst.id]=inst.spawn_pos
	await _go("region_forest:guide")
	_optional.accept_stage("region_forest:s1","region_forest:guide")
	_optional.perform_action("region_forest:s1:clue")
	var binding: Dictionary = GameState.campaign_quest.get("optional_bindings",{}).get("region_forest",{})
	_check(not binding.is_empty(),"%d 正常初始世界绑定已有巢址，未注入合成巢" % current_seed)
	if binding.is_empty(): return
	_check(sim.instances.size()==initial_instances and sim.nests.size()==initial_nests,"作者标记绑定没有新增怪物或巢穴")
	for id: int in original_positions: _check(sim.instances[id].spawn_pos==original_positions[id],"绑定不搬动任何原实例")
	_check(not _optional._done(Catalog.actions()["region_forest:s1:nest"]),"NPC旧图只给历史坐标，不生成现场目击")
	var key: String=binding.target_key
	var camp := Vector2(binding.camp[0],binding.camp[1])
	var species := sim.find_species(key.get_slice("|",1))
	var region := sim.get_region(key.get_slice("|",0))
	_check(sim.camp_pos(region,species)==camp and sim.nests.has(key),"目标身份与未搬动的正常巢穴精确一致")
	for inst: MonsterInstance in sim.instances.values():
		if not inst.is_alive or inst.spawn_pos.distance_to(camp)>1400: continue
		var actor: MonsterBase=GAME_WORLD.MONSTER_SCENES[inst.species.species_name].instantiate()
		add_child(actor)
		actor.setup(inst)
		actor.set_physics_process(false)
		actors.append(actor)
	var nest := NestNode.new()
	add_child(nest)
	nest.setup(region.id,species.species_name,species.tint,camp)
	nests.append(nest)
	layer = OBSTACLES.new()
	add_child(layer)
	var bounds := Rect2(CampaignLayout.object_position("region_forest:guide"),Vector2.ZERO)
	for row: Array in binding.near_route: bounds=bounds.expand(Vector2(row[0],row[1]))
	for row: Array in binding.positions.values(): bounds=bounds.expand(Vector2(row[0],row[1]))
	bounds=bounds.expand(CampaignLayout.object_position("region_forest:survey_b")).grow(384)
	for y in range(floori(bounds.position.y/512),floori(bounds.end.y/512)+1):
		for x in range(floori(bounds.position.x/512),floori(bounds.end.x/512)+1): layer._on_chunk_ready(Vector2i(x,y)*512)
	while not layer._lay_queue.is_empty(): layer._process(0)
	await _frames(3)
	var walk_distance:=0.0
	for id: String in ["region_forest:survey_a","region_forest:survey_b"]:
		var path:=_optional._forest_dry_path(_optional._grid_center(_player.position),_optional._position(id))
		_check(not path.is_empty(),"%d 原来路到绑定观察点有真实干燥路径" % current_seed)
		walk_distance+=_walk_actual(path)
		_check(bool(_world.object_node(id).call("can_interact")),"真实玩家走到调查点才可交互")
		_optional.perform_action("region_forest:s1:"+("nest" if id.ends_with("survey_a") else "trail"))
	_check(Data.ready(GameState.campaign_quest,"region_forest:s1"),"正常现场完成巢区与来路调查")
	var sight: Dictionary=GameState.campaign_quest.quests["region_forest:s1"].evidence.get("region_forest:s1:nest",{})
	_check(int(sight.get("counts",{}).get("active_nests",0))>=1,"真实现场观察到正常初始活动巢")
	_capture_snapshot("region_forest:s1",current_seed)
	var choice_path:=_optional._forest_dry_path(_optional._grid_center(_player.position),_optional._position("region_forest:choice"))
	_walk_actual(choice_path)
	_optional.accept_stage("region_forest:s2","region_forest:choice")
	_optional.perform_action("region_forest:s2:choice","near")
	var target:=_optional._saved_target("region_forest")
	_check(target.get("target_key","")==key and target.get("unit_ids",[]).size()>=2,"正常已有巢与真实当前演员可选择近线处理")
	if target.is_empty():
		print("FOREST TARGET BLOCKED seed=",current_seed," candidate=",binding," actors=",actors.size())
		return
	# 反证：演员当前移走而 spawn_pos 未变，不得继续被当前目标选择器当作目击。
	var actual_positions:={}
	for actor: MonsterBase in actors:
		actual_positions[actor]=actor.position
		actor.position+=Vector2(6000,0)
	_check(_optional._choose_local_target("region_forest:survey_a",true).is_empty(),"当前演员已离场不能用旧spawn_pos生成目击")
	for actor: MonsterBase in actors: actor.position=actual_positions[actor]
	# 恢复同一实名动作后，现巢自然消退的独立分支不得授予捣巢功劳。
	var accepted:=GameState.campaign_quest.duplicate(true)
	var nest_before: Dictionary=sim.nests[key].duplicate(true)
	sim.nests[key]["active"]=false
	_walk_actual(_optional._forest_dry_path(_optional._grid_center(_player.position),_optional._position("region_forest:work_near")))
	_optional.perform_action("region_forest:s2:work")
	_check(GameState.campaign_quest.quests["region_forest:s2"].evidence.get("region_forest:s2:work",{}).get("outcome","")=="survey","接取后巢消退可诚实调查结案，不伪造捣巢")
	GameState.campaign_quest=accepted
	sim.nests[key]=nest_before
	_refresh()
	# 真正已有 NestNode 受击触发原 destroy_nest 与真实事件，数量及原巢址不变。
	for hit in 4: nest.take_damage(1)
	_optional.perform_action("region_forest:s2:work")
	_check(GameState.campaign_quest.quests["region_forest:s2"].evidence.get("region_forest:s2:work",{}).get("outcome","")=="ransack","正常初始已有巢实际受击捣毁后才记录处理")
	var bound_before:=binding.duplicate(true)
	_cold()
	_check(GameState.campaign_quest.optional_bindings.region_forest==bound_before,"绑定位置与路径冷恢复一次稳定，不重抽")
	_capture_snapshot("region_forest:s2",current_seed)
	_walk_actual(_optional._forest_dry_path(_optional._grid_center(_player.position),_optional._position("region_forest:station")))
	_optional.accept_stage("region_forest:s3","region_forest:station")
	var action: Dictionary=Catalog.actions()["region_forest:s3:walk"]
	var radar:=_optional.next_target(action)
	_check((radar.position as Vector2).distance_to(_optional._position("region_forest:work_near"))<1,"第三段雷达指向实际绑定施工点")
	_walk_actual(_optional._forest_dry_path(_optional._grid_center(_player.position),_optional._position("region_forest:work_near")))
	_optional._last_player_position=Vector2.INF
	_optional._track_routes()
	var route:=_optional.route_geometry(action)
	_check(route.size()==binding.near_route.size() and (route[0] as Vector2).distance_to(_optional._position("region_forest:work_near"))<1,"第三段路线确从绑定实际巢边施工点出发")
	_walk_actual([route[0]],true)
	var resume_anchor:=_optional._route_anchor(action)
	_player.position+=Vector2(2048,0)
	_optional._track_routes()
	_player.position=resume_anchor
	_optional._track_routes()
	_capture_snapshot("region_forest:s3",current_seed,"route_resume")
	_player.move_and_collide(Vector2(8,0))
	_optional._track_routes()
	walk_distance+=_walk_actual(route,true)
	_optional.perform_action("region_forest:s3:walk")
	_optional.perform_action("region_forest:s3:sign")
	_check(Data.ready(GameState.campaign_quest,"region_forest:s3"),"正常已有巢近线经过实际身体路线完成第三段")
	_check(sim.instances.size()==initial_instances and sim.nests.size()==initial_nests,"完整处理没有加密怪物或增添任务巢")
	_capture_snapshot("region_forest:s3",current_seed)
	var route_length:=0.0
	for i in range(1,route.size()): route_length+=(route[i-1] as Vector2).distance_to(route[i])
	print("OPTIONAL FOREST seed=%d camp=%s bound_route=%d route_length=%.0f sampled_physical_walk=%.0f" % [current_seed,key,binding.near_route.size(),route_length,walk_distance])

func _walk_actual(path: Array, track := false, detours := 0) -> float:
	if path.is_empty(): return 0.0
	var distance:=0.0
	for point: Vector2 in path:
		var guard:=0
		while _player.position.distance_to(point)>0.1 and guard<2000:
			var before:=_player.position
			var motion:=before.direction_to(point)*minf(24.0,before.distance_to(point))
			var collision:=_player.move_and_collide(motion)
			distance+=before.distance_to(_player.position)
			if track: _optional._track_routes()
			if collision!=null or before.distance_to(_player.position)<0.01:
				if collision!=null and collision.get_collider() is MonsterBase and detours<3:
					_player.move_and_collide(before-_player.position)
					var detour:=_actor_detour(before,point)
					if not detour.is_empty():
						distance+=_walk_actual(detour,track,detours+1)
						break
				_check(false,"%d 实际身体路线被物理障碍阻断 %s -> %s" % [current_seed,before,point])
				return distance
			guard+=1
	return distance


## 遇到冻结的正常演员时按当前真实碰撞绕开；不搬怪也不关闭其身体。
func _actor_detour(start: Vector2, finish: Vector2) -> Array[Vector2]:
	var destination:=Vector2i(roundi((finish.x-start.x)/32),roundi((finish.y-start.y)/32))
	var previous:={Vector2i.ZERO:Vector2i.ZERO}
	var queue: Array[Vector2i]=[Vector2i.ZERO]
	var index:=0
	var bounds:=Rect2(start,Vector2.ZERO).expand(finish).grow(192)
	while index<queue.size():
		var cell:=queue[index]
		index+=1
		var at:=start+Vector2(cell)*32
		if cell==destination and not _player.test_move(Transform2D(0,at),finish-at):
			var result: Array[Vector2]=[finish]
			while cell!=Vector2i.ZERO:
				result.push_front(start+Vector2(cell)*32)
				cell=previous[cell]
			result.push_front(start)
			return result
		for direction: Vector2i in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:
			var next:=cell+direction
			var there:=start+Vector2(next)*32
			if previous.has(next) or not bounds.has_point(there) or ObstacleField.liquid_kind_at(there)!="": continue
			if _player.test_move(Transform2D(0,at),Vector2(direction)*32): continue
			previous[next]=cell
			queue.append(next)
	return []
