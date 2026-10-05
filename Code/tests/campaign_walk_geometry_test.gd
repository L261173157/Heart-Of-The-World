## 步行验收机器人自身的几何回归；明确隔离的静态障碍夹具，不写故事证据、不建立生态实例。
## 正向仍使用原Player/TouchInput/真实碰撞，不能把测试路点或碰撞体伪装成剧情完成。
extends "res://tests/campaign_story_acceptance_test.gd"
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const HUD_SCENE := preload("res://scenes/ui/hud.tscn")
var _scene: CampaignWorld
var _blocker: StaticBody2D
var _goal: Vector2
var _record: Node2D

func _fixture(offset: Vector2, shape: Shape2D) -> void:
	_world=Node2D.new()
	add_child(_world)
	_scene=CampaignWorld.new()
	_world.add_child(_scene)
	_scene.refresh_state({"enabled_batch":4})
	_record=_scene.object_node("side_letter:record")
	_goal=_record.global_position+Vector2(0,56)
	_blocker=StaticBody2D.new()
	_blocker.name="ExplicitWalkerGeometryFixture"
	_blocker.collision_layer=2
	_blocker.collision_mask=0
	_blocker.position=_goal+offset
	var collision:=CollisionShape2D.new()
	collision.shape=shape
	_blocker.add_child(collision)
	_world.add_child(_blocker)
	_player=PLAYER_SCENE.instantiate()
	_world.add_child(_player)
	_player.set_physics_process(false)
	# 原Player的_ready会选择家园出生点；本隔离几何夹具在任何测试动作前设置初始站位。
	_player.position=_scene.object_node("side_letter:giver").global_position+Vector2(12,60)
	_player.get_node("Camera2D").reset_smoothing()
	_player.get_node("Camera2D").force_update_scroll()
	_player.set_process(false)
	_hud=HUD_SCENE.instantiate()
	_world.add_child(_hud)
	await _frames(3)

func _tear_down() -> void:
	TouchInput.reset()
	get_tree().paused=false
	_world.queue_free()
	await _frames(3)

func _circle(radius: float) -> CircleShape2D:
	var circle:=CircleShape2D.new()
	circle.radius=radius
	return circle

func _closed_gate_contact() -> void:
	# 隔离测试的初始布置；使用作者原门格与正式障碍装配，不制造任务状态。
	await _fixture(Vector2(0,24),_circle(10.56))
	var cells := CampaignLayout.gate_cells("c2:forest_gate")
	var middle := (Vector2(cells[cells.size()/2])+Vector2.ONE*0.5)*32.0
	var layer := ObstacleTileLayer.new()
	_world.add_child(layer)
	var bounds := Rect2(middle-Vector2(256,256),Vector2(512,512))
	for y in range(floori(bounds.position.y/512),floori(bounds.end.y/512)+1):
		for x in range(floori(bounds.position.x/512),floori(bounds.end.x/512)+1): layer._on_chunk_ready(Vector2i(x,y)*512)
	while not layer._lay_queue.is_empty(): layer._process(0)
	_player.position=middle+Vector2(0,80)
	_player.get_node("Camera2D").reset_smoothing()
	_player.get_node("Camera2D").force_update_scroll()
	await _frames(3)
	var ledger := GameState.campaign_quest.duplicate(true)
	var hp := _player.current_hp
	_player.set_physics_process(true)
	TouchInput.joystick_active=true
	TouchInput.move_vector=Vector2.UP
	await _frames(30)
	TouchInput.reset()
	_player.set_physics_process(false)
	var contact := _player.global_position
	var query := _walk_query()
	_check(contact.y>middle.y+10 and contact.y<middle.y+29,"原Player通过输入实际接触并被原关闭门体挡住")
	_check(not _walk_physics_blocked(contact,query) and ObstacleField.blocks(contact,12),"真实身体合法贴墙，但保守圆形余量确实判为受阻")
	var outward := contact+Vector2(0,32)
	var behind := middle-Vector2(0,32)
	_check(not _walk_blocked(outward,query) and not _walk_blocked(behind,query),"向外与门后负例终点都实际且数学可站立")
	_check(not _walk_sweep_clear(contact,outward,query),"普通门户扫掠仍不能忽略保守起点余量")
	_check(_walk_sweep_clear(contact,outward,query,true),"当前身体短首段以连续真实扫掠合法退出贴墙余量")
	_check(not _walk_sweep_clear(contact,behind,query,true),"即使门后终点可站，首段也不能穿过实际关闭门体")
	_check(not _walk_sweep_clear(contact+Vector2(0.25,0),outward,query,true),"贴墙例外不能用于非当前身体起点")
	_check(not _walk_sweep_clear(contact,contact+Vector2(0,96),query,true),"贴墙例外不能扩张到长距离路段")
	_check(_walk_physics_blocked(middle,query) and not _walk_sweep_clear(middle,outward,query,true),"真实身体已与门重叠的起点仍被拒绝")
	var destination := middle+Vector2(0,80)
	var path := _walk_plan(contact,destination,query)
	_check(not path.is_empty() and path[-1]==destination,"规划从真实贴墙位置选择清楚的首段，保留原终点")
	if not path.is_empty(): await _walk_to(destination,"原关闭门前真实退出贴墙",8)
	var closed := true
	for cell: Vector2i in cells: closed=closed and ObstacleField.is_obstacle_cell(cell)
	_check(closed and GameState.campaign_quest==ledger and _player.current_hp==hp,"真实退出未开门、改生命或制造任务证据")
	await _tear_down()

func _run() -> void:
	Engine.time_scale=4
	GameState.world_seed=BiomeMap.DEFAULT_SEED
	BiomeMap.configure(GameState.world_seed)
	# 复现独立审查的角色方角漏检：旧半径12圆形查询清楚，真实20×20方形身体碰角。
	await _fixture(Vector2(-15.6484375,18.21875),_circle(10.56))
	var query:=_walk_query()
	_check(query.shape==(_player.get_node("CollisionShape2D") as CollisionShape2D).shape,"查询直接使用原Player真实碰撞形状")
	var legacy:=_walk_query()
	legacy.shape=_circle(12)
	legacy.transform=Transform2D(0,_goal)
	_check(_world.get_world_2d().direct_space_state.intersect_shape(legacy,1).is_empty(),"旧12px圆查询确实漏过方形角落障碍")
	_check(_walk_blocked(_goal,query),"真实方形足迹拒绝这个有碰撞的请求点")
	_check(_walk_plan(_player.global_position,_goal,query).is_empty(),"精确请求点受阻时不能把格心强制标空或偷换目标")
	var selected:=_campaign_approach(_record,Vector2(0,56),query)
	_check(selected.is_finite() and selected!=_goal and selected.distance_to(_record.global_position)+18<=CampaignLayout.INTERACT_DISTANCE,"物件接近可选另一个真实范围内且可达的点")
	var fixed:=_blocker.global_transform
	var hp:=_player.current_hp
	var ledger:=GameState.campaign_quest.duplicate(true)
	if selected.is_finite():
		await _cw("side_letter:record")
		_check(_player.global_position.distance_to(selected)<=18,"原身体通过输入实走抵达所选接近点")
		_check(bool(_record.call("can_interact")),"备用接近点满足对象真实距离与视线交互闸门")
	_check(_blocker.global_transform==fixed and _player.current_hp==hp and GameState.campaign_quest==ledger,"接近没有移动障碍、变更生命或伪造故事证据")
	await _tear_down()
	# 精确点可站，但其32px格心受阻：必须从真实扫掠无碰撞的其他格心走到原点。
	await _fixture(Vector2(0,24),_circle(10.56))
	query=_walk_query()
	var center:=(_goal/32.0).floor()*32+Vector2(16,16)
	_check(not _walk_blocked(_goal,query),"精确目标实际身体可站立")
	_check(_walk_blocked(center,query),"同一目标的网格格心实际被占用")
	var path:=_walk_plan(_player.global_position,_goal,query)
	_check(not path.is_empty() and path[-1]==_goal,"路径保持原请求点，不把门户坐标当成完成点")
	_check(not path.has(center),"路径不经过受阻的原格心")
	if not path.is_empty():
		_check(_walk_sweep_clear(path[-2],_goal,query),"最后一段具有原身体形状的连续物理扫掠证明")
		fixed=_blocker.global_transform
		await _walk_to(_goal,"从可通行门户实走到精确原目标",10)
		_check(_player.global_position.distance_to(_goal)<=10 and _blocker.global_transform==fixed,"实际步行遵守原到达容差，障碍位置不变")
	await _tear_down()
	# 两端能站不证明中段可过；薄墙不能被近距离或格心假证据跳过。
	var thin:=RectangleShape2D.new()
	thin.size=Vector2(40,2)
	await _fixture(Vector2(0,-12),thin)
	query=_walk_query()
	_check(not _walk_blocked(_goal,query) and not _walk_blocked(_goal+Vector2(0,-24),query),"薄墙两侧端点都能容纳真实身体")
	_check(not _walk_sweep_clear(_goal+Vector2(0,-24),_goal,query),"扫掠拒绝穿越两端之间的真实薄墙")
	await _tear_down()
	# 起终点同在一格也不能跳过实际起点扫掠：格心至目标可过，不代表偏置起点至目标可过。
	await _fixture(Vector2(-12,10),_circle(1))
	query=_walk_query()
	var cell_origin:=(_goal/32.0).floor()*32.0
	var near_start:=cell_origin+Vector2(4,4)
	var near_goal:=cell_origin+Vector2(28,28)
	var near_center:=cell_origin+Vector2(16,16)
	_check(not _walk_blocked(near_start,query) and not _walk_blocked(near_goal,query),"同格起终点都能真实站立")
	_check(_walk_sweep_clear(near_center,near_goal,query) and not _walk_sweep_clear(near_start,near_goal,query),"格心扫掠不能代替偏置真实起点扫掠")
	var near_path:=_walk_plan(near_start,near_goal,query)
	_check(near_path.size()>2 and near_path[0]==near_start and near_path[-1]==near_goal,"同格直达有障碍时仍选择实际可走的中间点")
	var every_segment:=not near_path.is_empty()
	for index in range(1,near_path.size()):
		every_segment=every_segment and _walk_sweep_clear(near_path[index-1],near_path[index],query)
	_check(every_segment,"此同格回归的每一小段都通过真实身体扫掠")
	await _tear_down()
	# 整个交互范围都被占用时必须明确拒绝，不能越界选点、隔墙交互或给予故事证据。
	var sealed:=RectangleShape2D.new()
	sealed.size=Vector2(220,220)
	await _fixture(Vector2(0,-56),sealed)
	query=_walk_query()
	var before:=_player.global_position
	ledger=GameState.campaign_quest.duplicate(true)
	_check(not _campaign_approach(_record,Vector2(0,56),query).is_finite(),"所有物件接近点都真实受阻时不给出伪可达点")
	_check(_walk_plan(before,_goal,query).is_empty(),"完全封闭情形不改实心格或穿墙路径")
	_check(_player.global_position==before and GameState.campaign_quest==ledger,"失败规划不传送角色、不产生任务证据")
	await _tear_down()
	await _closed_gate_contact()
	print("=== CAMPAIGN WALK GEOMETRY %s (%d checks, %d failures) ===" % ["PASS" if _fails==0 else "FAIL",_checks,_fails])
	get_tree().quit(0 if _fails==0 else 1)
