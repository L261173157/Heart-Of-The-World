## 封闭任务附室的旧档兼容：真实身体/导航、菜单往返和独立冷启动。
extends Node

const MAIN := preload("res://scenes/main/main.tscn")
const PLAYER := preload("res://scenes/player/player.tscn")
const MONSTER := preload("res://scenes/monsters/goblin.tscn")
const TIMERS := {"heal":5.0, "heavy":2.0, "empower":7.0, "empower_buff":2.0, "dash":0.7}
var _checks := 0
var _fails := 0
var _world: Node

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.save_enabled = false
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok: _fails += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])

func _frames(n := 3) -> void:
	for i in n:
		await get_tree().physics_frame
		await get_tree().process_frame

func _door(id: String) -> Vector2:
	var cells := CampaignLayout.gate_cells(id)
	return (Vector2(cells[cells.size() / 2]) + Vector2.ONE * 0.5) * 32.0

func _legacy_position() -> Vector2:
	return WorldConfig.farthest_terrain_center("lava") + Vector2(300,0)

func _resources(player: Player, label: String) -> void:
	_check(player.current_hp == 87.0 and player.current_mp == 23.0, label + "血蓝逐位保留")
	var timers := player.save_snapshot().get("combat_timers", {}) as Dictionary
	for key: String in TIMERS:
		_check(is_equal_approx(float(timers.get(key,-1)), TIMERS[key]), label + "冷却/增益保留 " + key)

func _enter() -> Player:
	_world = MAIN.instantiate()
	_world.process_mode=Node.PROCESS_MODE_PAUSABLE
	add_child(_world)
	await _frames()
	return _world.get_node("Player") as Player

func _run() -> void:
	get_tree().paused = true
	if "--cold" in OS.get_cmdline_user_args():
		var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GameState.SAVE_PATH + ".resume_expected"))
		var player := await _enter()
		_resources(player,"独立冷启动")
		_check(player.global_position == _door("c6:core_gate")+Vector2(0,64),"独立冷启动只迁出新增锁门附室")
		_check(GameState.campaign_quest.get("quests",{})==expected.campaign.get("quests",{}) and GameState.campaign_quest.get("main_kills",{})==expected.campaign.get("main_kills",{}) and CampaignQuest.open_gates_from(GameState.campaign_quest).is_empty(),"冷启动不制造主线完成或Boss击杀")
		_check(WorldSim.sim.tick_count==int(expected.tick) and WorldSim.day_time==float(expected.day_time)
			and WorldSim.game_day==int(expected.game_day),"冷启动保留生态tick、天数和昼夜相位")
		_check(WorldSim.sim.instances.size()==int(expected.instances),"冷启动保留真实生态实例数量")
		_finish()
		return
	GameState.reset_all()
	GameState.stats.strength=20
	GameState.stats.intellect=20
	GameState.world_seed = 42
	seed(42)
	print("CAMPAIGN_RESUME world_seed=42 rng_seed=42 old_offset=(300,0)")
	var player := await _enter()
	WorldSim.resume_clock(0.6,3)
	player.global_position = _legacy_position()
	player.current_hp = 87.0
	player.current_mp = 23.0
	player._restore_combat_timers(TIMERS)
	var before_campaign := JSON.stringify(GameState.campaign_quest)
	var tick := WorldSim.sim.tick_count
	var instances := WorldSim.sim.instances.size()
	GameState.save_enabled = true
	_check(GameState.save_now(),"写入实际旧坐标存档")
	GameState.save_enabled = false
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GameState.SAVE_PATH))
	_check(Vector2(saved.player.position[0],saved.player.position[1]) == _legacy_position(),"磁盘夹具确为新墙内原+300px存档点")
	var file := FileAccess.open(GameState.SAVE_PATH + ".resume_expected",FileAccess.WRITE)
	file.store_string(JSON.stringify({"campaign":GameState.campaign_quest,"tick":tick,"day_time":0.6,"game_day":3,"instances":instances}))
	file.close()
	var output: Array = []
	var result := OS.execute(OS.get_executable_path(),PackedStringArray(["--headless","--path",ProjectSettings.globalize_path("res://"),
		"res://tests/campaign_resume_navigation_test.tscn","--quit-after","10000","--","--cold"]),output,true)
	var complete := false
	for line: String in output:
		print(line)
		complete = complete or "=== CAMPAIGN RESUME NAVIGATION PASS" in line
	_check(result==0 and complete,"旧坐标独立冷启动完成严格场景断言")
	# 同一真实世界退到菜单，再进入，走生产快照路径；恢复本身不得改变生态。
	_world.queue_free()
	await _frames()
	var menu := preload("res://scenes/ui/main_menu.tscn").instantiate()
	add_child(menu)
	await _frames()
	_check(menu.get_node("MenuBox/StartBtn").text=="继续冒险","旧档菜单显示继续冒险")
	menu.queue_free()
	await _frames()
	player = await _enter()
	_resources(player,"菜单继续")
	_check(player.global_position==_door("c6:core_gate")+Vector2(0,64),"菜单继续只迁出新增锁门附室")
	_check(JSON.stringify(GameState.campaign_quest)==before_campaign,"迁出不改任务或Boss证据")
	_check(WorldSim.sim.tick_count==tick and WorldSim.sim.instances.size()==instances
		and WorldSim.game_day==3 and WorldSim.day_time==0.6,"菜单继续完整保留生态与时钟")
	_world.queue_free()
	await _frames()
	WorldSim.stop()
	WorldSim.sim=EcologySim.new()
	get_tree().paused = false
	for seed_value in [42,20260908,2147483647]:
		await _geometry(seed_value)
	DirAccess.remove_absolute(GameState.SAVE_PATH + ".resume_expected")
	_finish()

func _geometry(seed_value: int) -> void:
	BiomeMap.configure(seed_value)
	ObstacleField.restore_destroyed([])
	CampaignLayout.set_open_gates([])
	print("CAMPAIGN_ROOM_GEOMETRY world_seed=%d" % seed_value)
	var rooms: Array[String]=["c2:forest_gate","c4:archive_gate","c6:core_gate"]
	if not CampaignLayout.gate_cells("side_troll:room_gate").is_empty(): rooms.append("side_troll:room_gate")
	for id: String in rooms:
		var scene := Node2D.new()
		add_child(scene)
		var door := _door(id)
		var inside := door+Vector2(0,-128)
		if id=="c6:core_gate": inside = _legacy_position()
		var outside := door+Vector2(0,64)
		var obstacle := ObstacleTileLayer.new()
		scene.add_child(obstacle)
		obstacle.set_process(false)
		var nav := NavTileLayer.new()
		scene.add_child(nav)
		nav.set_process(false)
		var chunk := Vector2i(floori(door.x/512),floori(door.y/512))
		for y in range(-2,3):
			for x in range(-2,3):
				obstacle._on_chunk_ready((chunk+Vector2i(x,y))*512)
				nav._fill_chunk(chunk+Vector2i(x,y))
		while not obstacle._lay_queue.is_empty(): obstacle._process(0)
		GameState.player_snapshot = {"position":[inside.x,inside.y],"hp":87.0,"mp":23.0,"combat_timers":TIMERS}
		var player := PLAYER.instantiate() as Player
		scene.add_child(player)
		player.set_physics_process(false)
		player.set_process(false)
		await _frames(5)
		_check(not ObstacleField.blocks(inside,10),id+"旧点有身体净空，不能靠原nudge_free发现封闭")
		_check(player.global_position==outside,id+"新围墙内旧档迁至真实门外")
		_resources(player,id)
		_check(player.test_move(player.global_transform,Vector2(0,-192)),id+"真实身体仍被锁门阻挡，没有偷偷开门")
		var before := player.global_position
		player.move_and_collide(Vector2(0,96))
		_check(player.global_position.distance_to(before+Vector2(0,96))<0.1,id+"门外可实际步行离开，无围困")
		player.global_position=outside
		_check(not ObstacleField.blocks(outside,10) and ObstacleField.liquid_kind_at(outside)=="",id+"恢复点有真实净空且无灼伤")
		var actor := MONSTER.instantiate() as MonsterBase
		scene.add_child(actor)
		actor.set_physics_process(false)
		var inst := MonsterInstance.new()
		inst.id=123456
		inst.species=load("res://data/species/frog.tres")
		inst.age=8
		inst.spawn_pos=outside+Vector2(80,0)
		actor.setup(inst)
		actor.position=inst.spawn_pos
		actor._nav.avoidance_enabled=false
		await _frames()
		_check(actor._nav_velocity_toward(inside,80)==Vector2.ZERO,id+"真实怪物不向封闭异侧请求不可达路径")
		actor._navq_velocity=Vector2.INF
		_check(actor._nav_velocity_toward(outside+Vector2(0,96),80).length()>0,id+"门外同连通域仍使用真导航")
		for cell: Vector2i in CampaignLayout.gate_cells(id):
			_check(nav.get_cell_source_id(cell)==-1,id+"关闭门格确实不在导航网格")
		# 紧邻外墙的重叠点会被原nudge先向东推入室内，必须在nudge后再防围困。
		var boundary:=door+Vector2(-145 if id=="side_troll:room_gate" else -273,-144)
		var nudged:=ObstacleField.nudge_free(boundary,10)
		_check(nudged.x>boundary.x+1 and not ObstacleField.blocks(nudged,10),id+"固定边界夹具确实被原nudge推入墙内")
		GameState.player_snapshot={"position":[boundary.x,boundary.y],"hp":87.0,"mp":23.0,"combat_timers":TIMERS}
		player._restore_saved_state()
		_check(player.global_position==outside,id+"墙外重叠旧点nudge后不会被封入室内")
		actor.position=inside+Vector2(64,0)
		actor._navq_velocity=Vector2.INF
		_check(actor._nav_velocity_toward(inside+Vector2(96,0),80).length()>0,id+"锁门房内同连通域仍可真寻路")
		actor.position=inst.spawn_pos
		await _corner_slime(scene,id)
		var changed := CampaignLayout.set_open_gates([id])
		ObstacleField.invalidate_authored_cells(changed)
		EventBus.campaign_geometry_changed.emit(changed)
		await _frames(5)
		player.global_position=outside
		_check(not player.test_move(player.global_transform,Vector2(0,-192)),id+"开门后真实身体可穿过门洞")
		actor._navq_velocity=Vector2.INF
		actor._nav_target=Vector2.INF
		_check(actor._nav_velocity_toward(door+Vector2(0,-128),80).length()>0,id+"同一怪物开门后恢复寻路")
		await _nav_ready(scene,door)
		var path := NavigationServer2D.map_get_path(scene.get_world_2d().navigation_map,outside,door+Vector2(0,-128),true)
		_check(path.size()>1 and path[path.size()-1].distance_to(door+Vector2(0,-128))<1,id+"真实导航路径贯通门内外 %s" % str(path))
		GameState.player_snapshot = {"position":[inside.x,inside.y],"hp":87.0,"mp":23.0,"combat_timers":TIMERS}
		player._restore_saved_state()
		_check(player.global_position==inside,id+"已开门的房内合法存档原地保持")
		changed=CampaignLayout.set_open_gates([])
		ObstacleField.invalidate_authored_cells(changed)
		for ordinary: Vector2 in [outside, outside+Vector2(0,96)]:
			GameState.player_snapshot={"position":[ordinary.x,ordinary.y],"hp":87.0,"mp":23.0,"combat_timers":TIMERS}
			player._restore_saved_state()
			_check(player.global_position==ordinary,id+"普通可达位置逐位保持")
		scene.queue_free()
		await _frames()

	# 学者房间有永久北出口，南门未开也不能当封闭旧档迁出。
	if not CampaignLayout.gate_cells("side_scholar:shortcut_gate").is_empty():
		var gate:=_door("side_scholar:shortcut_gate")
		var interior:=gate+Vector2(0,-128)
		GameState.player_snapshot={"position":[interior.x,interior.y],"hp":87.0,"mp":23.0,"combat_timers":TIMERS}
		var player:=PLAYER.instantiate() as Player
		add_child(player)
		player.set_process(false)
		player.set_physics_process(false)
		_check(player.global_position==interior,"学者南门关闭但永久北出口可达，旧档原位保留")
		_check(not CampaignLayout.separated_by_closed_gate(interior,gate+Vector2(0,64)),"学者贯通房间不触发封闭导航守卫")
		player.queue_free()
		await _frames()

## 外墙格角留有真实圆形碰撞之外的空隙；自然分裂小体型必须可以沿外侧离开。
func _corner_slime(scene: Node2D,id: String) -> void:
	var corner: Vector2=CampaignLayout._sealed_rooms[id].bounds.position+Vector2.ONE
	var target:=corner-Vector2(64,64)
	var actor:=preload("res://scenes/monsters/slime.tscn").instantiate() as MonsterBase
	scene.add_child(actor)
	actor.set_physics_process(false)
	actor.set_process(false)
	var inst:=MonsterInstance.new()
	inst.id=123457
	inst.species=load("res://data/species/slime.tres")
	inst.size_scale=pow(inst.species.split_size_scale,2)
	inst.generation=2
	inst.spawn_pos=corner
	actor.setup(inst)
	actor.position=corner
	actor._nav.avoidance_enabled=false
	await _frames()
	_check(not actor.test_move(actor.global_transform,target-corner),id+"自然二代分裂体可从外墙格角物理离开")
	for far: bool in [true,false]:
		actor._far_mode=far
		actor._navq_velocity=Vector2.INF
		_check(actor._nav_velocity_toward(target,80).length()>0,id+"外角合法通路不被封闭守卫截停 far="+str(far))
	actor.move_and_collide(target-corner)
	_check(actor.global_position.distance_to(target)<0.1,id+"二代分裂体实际移动离开外墙格角")
	actor.queue_free()
	await _frames()

## TileMap改格与NavigationServer异步同步分离；等实际门格入网而非固定帧猜测。
func _nav_ready(scene: Node2D, point: Vector2) -> void:
	for frame in 120:
		if NavigationServer2D.map_get_closest_point(scene.get_world_2d().navigation_map,point).distance_to(point)<1:
			return
		await _frames(1)
	_check(false,"120物理帧内实际门格导航完成同步")

func _finish() -> void:
	GameState.save_enabled=false
	get_tree().paused=false
	print("=== CAMPAIGN RESUME NAVIGATION %s (%d checks) ===" % ["PASS" if _fails==0 else "FAIL",_checks])
	get_tree().quit(0 if _fails==0 else 1)
