## 六群系作者站点：多种子布局、原 Boss 锚点、真实机关碰撞/导航和本地实体。
extends Node

const WORLD := preload("res://scripts/main/campaign_world.gd")
const LAYER := preload("res://scripts/main/terrain/obstacle_tile_layer.gd")
const NAV := preload("res://scripts/main/terrain/nav_tile_layer.gd")
var _checks := 0
var _fails := 0

func _ready() -> void:
	GameState.save_enabled = false
	_run.call_deferred()

func _check(ok: bool,label: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		push_error("FAIL " + label)

func _run() -> void:
	for seedv in [BiomeMap.DEFAULT_SEED,1,42,99,20261004,982451653,2147483647]:
		_test_seed(seedv)
	BiomeMap.configure(BiomeMap.DEFAULT_SEED)
	ObstacleField.restore_destroyed([])
	await _test_physics()
	# 真实环境伤害触发 hurt.ogg；等播放自然结束再退出，不截断音频线程。
	await get_tree().create_timer(0.8).timeout
	if _fails == 0:
		print("=== CAMPAIGN LAYOUT PASS (%d checks) ===" % _checks)
	get_tree().quit(_fails)

func _test_seed(seedv: int) -> void:
	BiomeMap.configure(seedv)
	ObstacleField.restore_destroyed([])
	var sites := CampaignLayout.sites()
	_check(sites.size() == 6,"%d 六群系各一个站点" % seedv)
	_check(sites == CampaignLayout.sites(),"同种子站点稳定")
	for terrain: String in sites:
		var site: Dictionary = sites[terrain]
		_check(BiomeMap.terrain_at(site.entry) == terrain,"%d %s 落点属于真群系" % [seedv,terrain])
		_check(not ObstacleField.blocks(site.entry,12) and not ObstacleField.nav_blocked_at(site.entry),"远征落点真实可走")
		_check(ObstacleField.liquid_kind_at(site.entry) == "","远征落点无液体伤害")
		if terrain != "plains":
			var first_id: String = {"forest":"c2:herbalist","swamp":"c3:totem_record","hill":"c4:scholar","snow":"c5:altar_record","lava":"c6:hazard_record"}[terrain]
			for candidate: Vector2 in CampaignLayout.entry_candidates(terrain):
				_check(not ObstacleField.blocks(candidate,12) and ObstacleField.liquid_kind_at(candidate)=="","有限候选落点均有干燥身体净空")
				_check(_flood(terrain,candidate).has(_cell(CampaignLayout.object_position(first_id))),"每个候选落点都能真实走到该章第一对象")
		if terrain in ["hill","lava"]:
			var dungeon: Dictionary = {}
			for row: Dictionary in ObstacleField.dungeons():
				if row.terrain == terrain:
					dungeon = row
			_check(site.boss_anchor == dungeon.center and site.region_id == dungeon.patch_id,"原城塞 Boss 锚点不变")
			_check(site.entry.distance_to(site.boss_anchor) > 1800,"首次远征不落在 Boss 脚下")
			for path: PackedVector2Array in CampaignLayout.paths(terrain).slice(0,2):
				for i in range(path.size()-1):
					_check(_walkable(path[i],path[i+1]),"接应点至城塞南门干燥通路")
	var reachable := _flood("forest")
	for item: Dictionary in CampaignLayout.objects():
		_check(not ObstacleField.blocks(item.position,12),"%s 实物站位非障碍" % item.id)
		_check(ObstacleField.liquid_kind_at(item.position) == "","%s 实物站位干燥" % item.id)
		if str(item.id).begins_with("c2:"):
			_check(reachable.has(_cell(item.position)) == (item.id != "c2:torn_record"),"关门时仅档案在门后")
	var changed := CampaignLayout.set_open_gates(["c2:forest_gate"])
	ObstacleField.invalidate_authored_cells(changed)
	reachable = _flood("forest")
	for item: Dictionary in CampaignLayout.objects():
		if str(item.id).begins_with("c2:"):
			_check(reachable.has(_cell(item.position)),"开门后所有森林对象真实可达")
	_check(CampaignLayout.set_open_gates(["c2:forest_gate"]).is_empty(),"重复投影不重复改变几何")
	changed = CampaignLayout.set_open_gates([])
	ObstacleField.invalidate_authored_cells(changed)
	_check(not _flood("forest").has(_cell(CampaignLayout.object_position("c2:torn_record"))),"关闭/新档恢复门墙")
	_test_extended_routes(seedv)

func _cell(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x/32),floori(pos.y/32))

func _flood(terrain: String,start := Vector2.INF) -> Dictionary:
	var center := _cell(CampaignLayout.site_center(terrain))
	var first := _cell(CampaignLayout.entry(terrain) if start==Vector2.INF else start)
	var visited := {first:true}
	var queue: Array[Vector2i] = [first]
	var index := 0
	while index < queue.size():
		var cell := queue[index]
		index += 1
		for dir: Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var next := cell + dir
			if visited.has(next) or absi(next.x-center.x)>21 or absi(next.y-center.y)>21:
				continue
			if ObstacleField.nav_blocked_cell(next):
				continue
			visited[next] = true
			queue.append(next)
	return visited

func _walkable(a: Vector2,b: Vector2) -> bool:
	var count := maxi(1,ceili(a.distance_to(b)/12))
	for i in range(count+1):
		var pos := a.lerp(b,float(i)/count)
		if ObstacleField.blocks(pos,12) or ObstacleField.liquid_kind_at(pos) != "":
			return false
	return true

func _step(frames := 2) -> void:
	for i in frames:
		await get_tree().physics_frame
		await get_tree().process_frame

func _test_physics() -> void:
	var scene := Node2D.new()
	add_child(scene)
	var layer := LAYER.new()
	scene.add_child(layer)
	var nav := NAV.new()
	scene.add_child(nav)
	var center := CampaignLayout.site_center("forest")
	var chunk := Vector2i(floori(center.x/512),floori(center.y/512))
	for y in range(-2,3):
		for x in range(-2,3):
			layer._on_chunk_ready((chunk+Vector2i(x,y))*512)
			nav._fill_chunk(chunk+Vector2i(x,y))
	while not layer._lay_queue.is_empty():
		layer._process(0)
	var world := WORLD.new()
	scene.add_child(world)
	var player := preload("res://scenes/player/player.tscn").instantiate() as Player
	player.position = center + Vector2(-352,-24)
	scene.add_child(player)
	player.set_physics_process(false)
	player.teleport_to(center + Vector2(-352,-24))
	await _step(4)
	_check(player.test_move(player.global_transform,Vector2(0,-250)),"真实角色不能穿过未解石门")
	var record := world.object_node("c2:torn_record")
	_check(not record.is_observed(player.position),"墙后实物不能透墙显示")
	world.refresh_state({"open_gates":["c2:forest_gate"],"rescued":{"c2:liaison":true},"taken":{"c2:aid_cache":true},"repaired":{"c2:beacon":true}})
	await _step(5)
	_check(not player.test_move(player.global_transform,Vector2(0,-250)),"解谜刷新真实碰撞后可进入档案室")
	var before := player.position
	player.move_and_collide(Vector2(0,-250))
	_check(player.position.distance_to(before+Vector2(0,-250)) < 1,"角色实际移动走过已开的门")
	_check(record.can_interact(),"真实门后位置可以现场交互")
	_check(world.object_node("c2:liaison").rescued and world.object_node("c2:liaison").get_node("CharacterVisual").rotation == 0,"伤员救起有持续站立视觉")
	_check(world.object_node("c2:aid_cache").taken and world.object_node("c2:beacon").repaired,"箱子与灯火由持久快照投影")
	for cell: Vector2i in CampaignLayout.gate_cells("c2:forest_gate"):
		_check(layer.get_cell_source_id(cell) == -1 and nav.get_cell_source_id(cell) >= 0,"机关同步移除可见墙并开放导航")
	await _test_lava_body(scene,layer,player)
	scene.queue_free()
	await _step(3)


func _test_extended_routes(seedv: int) -> void:
	var near := CampaignLayout.route_waypoints("near")
	var outer := CampaignLayout.route_waypoints("outer")
	_check(not _walkable(near[1],near[3]),"沼泽近路受真实石障阻挡")
	for i in range(outer.size()-1):
		_check(_walkable(outer[i],outer[i+1]),"沼泽外环全段可实际步行")
	for cell: Vector2i in CampaignLayout.barrier_cells("c3:near_barrier"):
		_check(ObstacleField.damage_cell(cell)=="","沼泽石障第一击只扣耐久")
		_check(ObstacleField.damage_cell(cell)=="rock","沼泽石障第二击实际破除")
	for i in range(near.size()-1):
		_check(_walkable(near[i],near[i+1]),"破障后沼泽近路真实贯通")
	_check(not _flood("snow").has(_cell(CampaignLayout.object_position("c5:tablet"))),"雪原石版在真实冰障之后")
	for cell: Vector2i in CampaignLayout.barrier_cells("c5:ice_barrier"):
		ObstacleField.damage_cell(cell)
		_check(ObstacleField.damage_cell(cell)=="ice","雪原冰障通过实际伤害破除")
	_check(_flood("snow").has(_cell(CampaignLayout.object_position("c5:tablet"))),"冰障破除后石版步行可达")
	for terrain: String in ["hill","lava"]:
		var anchor: Vector2 = CampaignLayout.sites()[terrain].boss_anchor
		var id := "c4:archive_gate" if terrain=="hill" else "c6:core_gate"
		var door := (Vector2(CampaignLayout.gate_cells(id)[1])+Vector2.ONE*0.5)*32
		_check(not _walkable(door+Vector2(0,80),door+Vector2(0,-80)),"真实城塞附室关门阻挡")
		var changed := CampaignLayout.set_open_gates([id])
		ObstacleField.invalidate_authored_cells(changed)
		_check(_walkable(door+Vector2(0,80),door+Vector2(0,-80)),"真实城塞附室开门贯通")
		var boss_cell := _cell(anchor)
		_check(ObstacleField.sample_cell(boss_cell+Vector2i(6,0)).get("kind","")=="castle","附室不覆盖原城塞东墙")
	var changed := CampaignLayout.set_open_gates([])
	ObstacleField.invalidate_authored_cells(changed)
	var reunion := CampaignLayout.ending_positions("reunion")
	_check(reunion.size() == 4 and reunion.has_all(["c2:liaison", "c3:survivor", "c4:map_keeper", "c5:leader"]), "团聚有四位固定归来人物")
	for choice: String in ["reunion", "distributed", "centralized", "", "unknown"]:
		var positions := CampaignLayout.ending_positions(choice)
		_check(positions == reunion, "历史布局调用统一返回同一团聚驻地")
		for position: Vector2 in positions.values():
			_check(not ObstacleField.blocks(position,12) and ObstacleField.liquid_kind_at(position)=="","结局人物实际安全站位")
			_check(BiomeMap.terrain_at(position) == "plains" and position.distance_to(CampaignLayout.object_position("ending:shelter")) < 480, "四位人物在同一平原避难所团聚")
	var troll := CampaignLayout.entry_for_object("side_troll:giver")
	_check(troll.distance_to(BiomeMap.farthest_patch("forest").center)>2000,"巨魔支线远征安全接近点")
	_check(not ObstacleField.blocks(troll,12) and ObstacleField.liquid_kind_at(troll)=="","巨魔支线落点通行安全")
	var snow_routes := CampaignLayout.region_routes("snow")
	_check(_route_length(snow_routes.outer)>_route_length(snow_routes.near)*1.5,"雪原外环确实更长")
	for route: PackedVector2Array in snow_routes.values():
		for i in range(route.size()-1):
			_check(_walkable(route[i],route[i+1]),"雪原遮蔽物不堵已标道路")
	var hazard := CampaignLayout.hazard_footprint()
	_check(CampaignLayout.liquid_kind(hazard.get_center())=="lava","作者熔河有唯一几何真源")
	_check(ObstacleField.liquid_kind_at(hazard.get_center())=="lava","%d 可见熔河与环境伤害同源" % seedv)
	for route: PackedVector2Array in CampaignLayout.region_routes("lava").values():
		for i in range(route.size()-1):
			_check(_walkable(route[i],route[i+1]),"熔岩两条绕行路线均有身体净空")
	ObstacleField.restore_destroyed([])

func _route_length(points: PackedVector2Array) -> float:
	var length := 0.0
	for i in range(points.size()-1):
		length += points[i].distance_to(points[i+1])
	return length

func _test_lava_body(scene: Node2D,layer: ObstacleTileLayer,player: Player) -> void:
	var center := CampaignLayout.site_center("lava")
	var chunk := Vector2i(floori(center.x/512),floori(center.y/512))
	for y in range(-2,3):
		for x in range(-2,3):
			layer._on_chunk_ready((chunk+Vector2i(x,y))*512)
	while not layer._lay_queue.is_empty():
		layer._process(0)
	player.teleport_to(CampaignLayout.hazard_footprint().get_center())
	await _step(3)
	player.current_hp = player.stats.max_hp()
	var before := player.current_hp
	player._physics_process(0.51)
	_check(player.current_hp<before,"真正玩家物理循环站熔河会失血")
	var path: PackedVector2Array = CampaignLayout.region_routes("lava").near
	player.teleport_to(path[0])
	player.current_hp = player.stats.max_hp()
	before = player.current_hp
	await _step(3)
	var reached := true
	for i in range(path.size()-1):
		var steps := maxi(1,ceili(path[i].distance_to(path[i+1])/8.0))
		for n in range(1,steps+1):
			var point := path[i].lerp(path[i+1],float(n)/steps)
			var collision := player.move_and_collide(point-player.global_position)
			if collision != null:
				reached = false
			player._physics_process(0.05)
	_check(reached and player.global_position.distance_to(path[-1])<1,"真正角色沿安全绕行线实际移动无墙卡住")
	_check(is_equal_approx(player.current_hp,before),"实际绕行熔河不吃环境伤害")
