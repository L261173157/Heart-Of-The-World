## 《断开的守望》独立实景验收。复用首章的真实行走工具，不伪造章节证据或领奖收据。
## 冷启动由 run_campaign_lifecycle_test.py 驱动；只有库存/短写边界使用明确夹具。
extends "res://tests/outpost_chapter_contract_test.gd"

const C2 := "watch_c2_forest"
const FIXED_ACTIONS := ["AttackBtn", "ShieldBtn", "DashBtn", "ShortcutBtn", "QuickSlotBtn", "MoreBtn"]
var _campaign: Node
var _campaign_layout: Script
var _campaign_data: Script

func _freeze_new_actor(node: Node) -> void:
	super._freeze_new_actor(node)
	# 装配帧也冻结角色，冷恢复的HP/MP不被测试准备期间的自然恢复改写。
	if node is Player:
		if node.is_node_ready(): node.set_physics_process(false)
		else: node.ready.connect(func() -> void: node.set_physics_process(false), CONNECT_ONE_SHOT)

func _walk_query() -> PhysicsShapeQueryParameters2D:
	var query := PhysicsShapeQueryParameters2D.new()
	# 与原 Player 的实际方形身体同源；半径12的圆会漏掉20×20方形的四角。
	query.shape = (_player.get_node("CollisionShape2D") as CollisionShape2D).shape
	query.collision_mask = 3
	query.exclude = [_player.get_rid()]
	return query

func _walk_transform(at: Vector2) -> Transform2D:
	var transform := _player.global_transform
	transform.origin = at
	return transform * (_player.get_node("CollisionShape2D") as CollisionShape2D).transform

func _walk_physics_blocked(at: Vector2, query: PhysicsShapeQueryParameters2D) -> bool:
	query.motion = Vector2.ZERO
	query.transform = _walk_transform(at)
	return not _world.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()

func _walk_blocked(at: Vector2, query: PhysicsShapeQueryParameters2D) -> bool:
	return ObstacleField.blocks(at, 12.0) or _walk_physics_blocked(at, query)

func _walk_sweep_clear(from: Vector2, to: Vector2, query: PhysicsShapeQueryParameters2D, contact_start := false) -> bool:
	# 真实身体贴墙时，ObstacleField的圆形半径+2px余量可覆盖一个合法站位。
	# 仅当前身体的短首段可退出该保守余量；终点、门户和其它路段仍严格检查。
	var may_exit_margin := contact_start and from == _player.global_position and from.distance_to(to) <= 64.0
	if _walk_physics_blocked(from, query) or _walk_blocked(to, query): return false
	var in_start_margin := ObstacleField.blocks(from, 12.0)
	if in_start_margin and not may_exit_margin: return false
	var samples := maxi(1, ceili(from.distance_to(to) / 8.0))
	for index in range(1, samples):
		var blocked := ObstacleField.blocks(from.lerp(to, float(index) / samples), 12.0)
		if blocked and not in_start_margin: return false
		if not blocked: in_start_margin = false
	query.transform = _walk_transform(from)
	query.motion = to - from
	var sweep := _world.get_world_2d().direct_space_state.cast_motion(query)
	query.motion = Vector2.ZERO
	return sweep.size() == 2 and sweep[0] >= 1.0

## 格心被占不等于原请求点不可达。只从未占用格心经真实身体扫掠接近原点，绝不把障碍格改成空格。
func _walk_plan(from: Vector2, goal: Vector2, query: PhysicsShapeQueryParameters2D) -> PackedVector2Array:
	if _walk_blocked(goal, query): return PackedVector2Array()
	var a := Vector2i((from / 32.0).floor())
	var b := Vector2i((goal / 32.0).floor())
	var lo := Vector2i(mini(a.x,b.x)-28, mini(a.y,b.y)-28)
	var hi := Vector2i(maxi(a.x,b.x)+29, maxi(a.y,b.y)+29)
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(lo,hi-lo)
	grid.cell_size = Vector2(32,32)
	grid.offset = Vector2(16,16)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	grid.update()
	for y in range(lo.y,hi.y):
		for x in range(lo.x,hi.x):
			var cell := Vector2i(x,y)
			grid.set_point_solid(cell,_walk_blocked((Vector2(cell)+Vector2.ONE*0.5)*32.0,query))
	# 首项被替换成原角色当前位置，不会指挥身体走入这个可能被挤占的格心。
	grid.set_point_solid(a,false)
	var portals: Array[Vector2i] = []
	for y in range(b.y-2,b.y+3):
		for x in range(b.x-2,b.x+3):
			var cell := Vector2i(x,y)
			if not grid.is_point_solid(cell): portals.append(cell)
	portals.sort_custom(func(left: Vector2i,right: Vector2i) -> bool:
		return ((Vector2(left)+Vector2.ONE*0.5)*32.0).distance_squared_to(goal) < ((Vector2(right)+Vector2.ONE*0.5)*32.0).distance_squared_to(goal))
	for portal: Vector2i in portals:
		var point := (Vector2(portal)+Vector2.ONE*0.5)*32.0
		if not _walk_sweep_clear(point,goal,query): continue
		var path := grid.get_point_path(a,portal)
		if path.is_empty(): continue
		if path.size()==1:
			if not _walk_sweep_clear(from,goal,query,true): continue
			path[0] = from
		elif _walk_sweep_clear(from,path[1],query,true):
			path[0] = from
		else:
			# 实际身体偏离格心时，直接替换首项可能斜切原演员方角。
			# 只保留同一原格心作为真实路点，且两段均须用原身体扫掠验证。
			var start_center := path[0]
			if _walk_blocked(start_center,query): continue
			if not _walk_sweep_clear(from,start_center,query,true): continue
			if not _walk_sweep_clear(start_center,path[1],query): continue
			path.insert(0,from)
		path.append(goal)
		return path
	return PackedVector2Array()

## 战役场景有原生态演员与原城镇/城塞实心建筑。规划也看真实物理体；不挪演员、不关碰撞。
func _walk_to(goal: Vector2, label: String, arrival := 18.0) -> bool:
	_hud._close_dialogue()
	TouchInput.reset()
	var query := _walk_query()
	var previous := _player.global_position
	var stuck_origin := previous
	var cursor := 0
	var stuck_frames := 0
	var path := PackedVector2Array()
	var attempts := 0
	var walked_frames := 0
	_player.set_physics_process(true)
	for _frame in 7000:
		walked_frames = _frame
		if _player.global_position.distance_to(goal) <= arrival: break
		if path.is_empty():
			attempts += 1
			if attempts > 4: break
			path = _walk_plan(_player.global_position,goal,query)
			if path.is_empty(): break
			cursor = 1 if path.size()>1 else 0
			stuck_origin = _player.global_position
			stuck_frames = 0
		while cursor < path.size()-1 and _player.global_position.distance_to(path[cursor]) < 12.0:
			# 首格连接不能被12px提前换向再次斜切；继续靠近格心直到下一段真实清楚。
			if cursor==1 and not _walk_sweep_clear(_player.global_position,path[cursor+1],query): break
			cursor += 1
		TouchInput.joystick_active = true
		TouchInput.move_vector = _player.global_position.direction_to(path[cursor])
		await get_tree().physics_frame
		_freeze_monsters()
		var moved := _player.global_position.distance_to(previous)
		if moved >= 32.0: _check(false,label+"出现非步行单帧跳跃")
		_walked += moved
		previous = _player.global_position
		stuck_frames += 1
		if stuck_frames >= 90:
			if _player.global_position.distance_to(stuck_origin) < 4.0: path.clear()
			stuck_origin = _player.global_position
			stuck_frames = 0
	TouchInput.reset()
	_player.set_physics_process(false)
	var arrived := _player.global_position.distance_to(goal) <= arrival
	_check(arrived,label+"：实际角色绕过现存物理体行走抵达")
	if not arrived:
		print("CAMPAIGN_WALK_BLOCKER ", JSON.stringify({"label":label,"goal":[goal.x,goal.y],
			"actual":[_player.global_position.x,_player.global_position.y],"replans":attempts,"frames":walked_frames,
			"cursor":cursor,"waypoint":[path[cursor].x,path[cursor].y] if not path.is_empty() else [],
			"goal_blocked":_walk_blocked(goal,query),"goal_grid_blocked":_walk_blocked((goal/32.0).floor()*32.0+Vector2(16,16),query)}))
	return arrived

func _mount(fresh := false) -> void:
	await super._mount(fresh)
	_player.set_process(false)
	_campaign = _qm.get("_campaign")
	_campaign_layout = load("res://scripts/ecology/campaign_layout.gd")
	_campaign_data = load("res://scripts/main/campaign_quest_data.gd")
	_check(_campaign != null, "真实任务管理器装配战役运行时")

func _cq() -> Dictionary:
	return GameState.get("campaign_quest") as Dictionary

func _cs(number: int) -> Dictionary:
	return _cq().get("quests", {}).get(C2 + ":s" + str(number), {})

func _ce(number: int, action: String) -> bool:
	return _cs(number).get("evidence", {}).has(C2 + ":s" + str(number) + ":" + action)

func _cp(id: String) -> Node2D:
	for node: Node in get_tree().get_nodes_in_group("npcs"):
		if node is Node2D and "campaign_id" in node and str(node.get("campaign_id")) == id:
			return node as Node2D
	return null

func _cw(id: String, offset := Vector2(0, 56)) -> bool:
	var prop := _cp(id)
	_check(prop != null, "战役实体稳定ID实际装配：" + id)
	if prop == null: return false
	return await _walk_to(prop.global_position + offset, "战役实走" + id)

func _ci(id: String, confirm := true) -> bool:
	var prop := _cp(id)
	if prop == null:
		_check(false, "实际战役交互物缺失：" + id)
		return false
	_hud._close_dialogue()
	# 已取空物件没有新的现场行动或服务时，旧点击必须失效；不能要求重开领取模态。
	if prop.get("taken") == true and not bool(prop.get("_has_current_action")) and str(prop.get("service")).is_empty():
		var is_container: bool = str(prop.get("kind")) in ["aid", "parts", "cargo"]
		_check(prop.visible if is_container else not prop.visible, id + "已取容器保留为空箱，散页整体隐藏")
		_check(str(prop.get("title")).contains("已取空" if is_container else "已取"), id + "已取状态文字明确")
		_check(not prop.can_interact() and not bool(prop.get("_near")), id + "已取物件无领取入口或拾取高亮")
		prop.interact()
		await _frames()
		_check(not _hud._dialogue_panel.visible and not get_tree().paused, id + "再次点击不打开领取模态")
		return true
	prop.interact()
	await _frames()
	_check(_hud._dialogue_panel.visible and get_tree().paused, id + "实际阅读层暂停世界")
	if not confirm: return _hud._dialogue_panel.visible
	if _hud._dialogue_yes.visible:
		await _tap(_hud._dialogue_yes)
	_hud._close_dialogue()
	await _frames()
	return true

func _option(action: String) -> Button:
	for node: Node in _hud._dialogue_option_box.get_children():
		if node is Button and str(node.get_meta("quest_action", "")) == action:
			return node as Button
	return null

func _tap(button: Control) -> void:
	# 与既有触屏回归同口径：先滚入阅读视窗，再发送真实按下/抬起事件。
	var parent := button.get_parent()
	while parent != null and not parent is ScrollContainer: parent = parent.get_parent()
	if parent is ScrollContainer:
		parent.ensure_control_visible(button)
		await _frames(3)
	await super._tap(button)

func _world_clock() -> Dictionary:
	return {"seed": GameState.world_seed, "tick": WorldSim.sim.tick_count,
		"day": WorldSim.game_day, "phase": WorldSim.day_time,
		"population": JSON.parse_string(JSON.stringify(_world_population()))}

func _resources() -> Dictionary:
	var snapshot := _player.save_snapshot()
	snapshot.erase("position")
	return {"player": snapshot, "wallet": _wallet(), "equipment": GameState.stats.equips.duplicate(true),
		"strength": GameState.stats.strength, "agility": GameState.stats.agility,
		"intellect": GameState.stats.intellect}

func _wallet_xp(wallet: Dictionary) -> int:
	var total := int(wallet["xp"])
	var formula := CharacterStats.new()
	for level in range(1, int(wallet["level"])):
		formula.level = level
		total += formula.xp_to_next()
	return total

func _at_campaign_entry(terrain: String) -> bool:
	for point: Vector2 in _campaign_layout.entry_candidates(terrain):
		if _player.global_position.distance_to(point) < 100.0: return true
	return false

func _chapter_one_seed(pending := false) -> bool:
	var before := _cq().duplicate(true)
	var wallet := _wallet()
	_campaign.accept_chapter(C2)
	_campaign.object_action("c2:beacon")
	_campaign.request_travel("forest")
	_check(_same(before, _cq()) and wallet == _wallet(), "新档未完成首章不能远征、修灯、伪造第二章或获奖")
	if not await _accept_chapter(): return false
	if not await _first_clue() or not await _enter_and_recover() or not await _ecology(): return false
	if pending: GameState.inventory["onigiri"] = 99
	if not await _repair(pending): return false
	if pending: await _next_clue_contract()
	_check(_q().get("stage", "") == "completed" and _evidence("next_clue_received"), "首章经真实调查、取物、救援、生态、修路和线索交接完成")
	return _evidence("next_clue_received")

func _walk_home_context(use_recall := false) -> bool:
	if use_recall and _player.global_position.distance_to(_keeper().global_position) > 200.0:
		# 旧委托菜单测试使用原有真实回城渠道；不让冻结演员在野外站桩污染菜单可达性验证。
		_hud._close_dialogue()
		TouchInput.reset()
		_player.set_physics_process(true)
		await _frames(12)
		_player.set_physics_process(false)
		_hud._toggle_pause()
		await _frames()
		var recall: Button = _hud.pause_layer.find_child("MenuRecall", true, false)
		_check(recall != null, "冒险菜单仍保留原有回城控件")
		if recall == null: return false
		await _tap(recall)
		for _i in 150:
			await _frames(1)
			if _player.global_position.distance_to(WorldConfig.spawn_pos()) < 10.0 and not _world._teleporting: break
		_check(_player.global_position.distance_to(WorldConfig.spawn_pos()) < 10.0, "真实回城读条和过场抵达家园，不直接设置位置")
		if _player.global_position.distance_to(WorldConfig.spawn_pos()) >= 10.0: return false
	# 家园房屋有独立真实碰撞；沿首章明确的南侧旧道回营，不能让格心规划穿屋。
	if _player.global_position.distance_to(_keeper().global_position) > 200.0:
		if not await _walk_to(WorldConfig.spawn_pos() + Vector2(704, 768), "绕过家园东侧真实房屋"): return false
		if not await _walk_to(WorldConfig.spawn_pos() + Vector2(0, 768), "沿原旧道抵达家园南侧"): return false
	if not await _walk_to(_keeper().global_position + Vector2(38, 0), "实走返回营地远征入口"): return false
	# 让真实速度自然停稳，不能用测试冻结把尚在行走的角色冒充安全出发状态。
	_player.set_physics_process(true)
	await _frames(12)
	_player.set_physics_process(false)
	return true

func _depart_forest() -> bool:
	if not await _walk_home_context(): return false
	_check(_campaign._origin_pos("home:patrol") == _keeper().global_position, "远征发起点跟随真正巡守演员，不能使用已过时的出生坐标")
	_keeper().interact()
	await _frames()
	if _hud._dialogue_kind != "camp_choice":
		print("CAMPAIGN_DEPART_DEBUG ", JSON.stringify({"kind":_hud._dialogue_kind,"text":_hud._dialogue_text.text,
			"player":[_player.global_position.x,_player.global_position.y],"npc":[_keeper().global_position.x,_keeper().global_position.y],
			"static_origin":[WorldConfig.spawn_pos().x-100,WorldConfig.spawn_pos().y+75],"has_clue":_campaign.has_first_clue(),
			"at_origin":_campaign._at_origin("home:patrol"),"visible":_player.visible,"paused":get_tree().paused}))
	_check(_hud._dialogue_kind == "camp_choice", "巡守提供明确战役远征选择")
	var button := _option("campaign|depart|forest|home:patrol")
	_check(button != null and not button.disabled, "林地线索解锁真实远征按钮")
	if button == null or button.disabled: return false
	var before := _cq().duplicate(true)
	var position := _player.global_position
	await _tap(button)
	_check(_same(before, _cq()) and _player.global_position == position, "选择远征只预览，不偷接任务或传送")
	await _tap(_hud._dialogue_no)
	_check(_same(before, _cq()) and _player.global_position == position, "远征预览返回不产生任何旅行或账本副作用")
	button = _option("campaign|depart|forest|home:patrol")
	if button == null: return false
	await _tap(button)
	_player.current_hp = _player.stats.max_hp() * 0.73
	_player.current_mp = _player.stats.max_mp() * 0.37
	_player._heavy_cd = 2.75
	_player._heal_cd = 3.25
	# 隔离本来就存在的每帧自然恢复/营地整秒回血，测的是旅行本身是否返还资源。
	# 原速真实行走仍使用物理处理，淡入淡出及迁移回调仍由引擎执行。
	var world_processing := _world.is_processing()
	_world.set_process(false)
	var resources := _resources()
	var clock_state := _world_clock()
	await _tap(_hud._dialogue_yes)
	_hud._close_dialogue()
	for _i in 180:
		await _frames(1)
		if _at_campaign_entry("forest") and not _world._teleporting: break
	_check(_at_campaign_entry("forest"), "确认远征经实际世界迁移抵达当前安全林地候选入口")
	if not _same(resources, _resources()):
		print("CAMPAIGN_TRAVEL_RESOURCES ", JSON.stringify({"before":resources,"after":_resources()}))
	_check(_same(resources, _resources()), "远征不治疗、不补蓝、不刷新冷却、不改装备/钱包/成长")
	_check(_same(clock_state, _world_clock()), "远征保持同一世界种子、生态个体、巢穴、tick与昼夜时钟")
	_world.set_process(world_processing)
	_check(_cq().get("chapters", {}).has(C2), "真实远征明确接取第二章并冻结预算")
	_check(not ObstacleField.blocks(_player.global_position, 12.0), "远征安全落点不嵌入真实障碍")
	return _cq().get("chapters", {}).has(C2)

func _open_camp_option(action_id: String) -> bool:
	_hud._close_dialogue()
	_keeper().interact()
	await _frames()
	var button := _option(action_id)
	_check(button != null and not button.disabled, "新战役菜单保留可用原委托入口：" + action_id)
	if button == null or button.disabled: return false
	await _tap(button)
	await _tap(_hud._dialogue_yes)
	await _frames()
	return true

func _legacy_menu(mode: String) -> void:
	_check(_evidence("signpost_repaired") and _evidence("next_clue_received"), "旧合同UI夹具承接真实完成的第一章与后续线索")
	var wallet := _wallet()
	var original: Dictionary = GameState.camp_quest.duplicate(true)
	_check(not original.is_empty() and not original.get("paid", true), "旧合同保持独立未付收据")
	if not await _walk_home_context(true) or not await _open_camp_option("outpost:legacy"): return
	if mode == "paused":
		_check(_hud._dialogue_kind == "camp_action" and _hud._dialogue_yes.visible, "已暂停旧合同在新远征菜单内仍能实际继续")
		await _tap(_hud._dialogue_yes)
		_check(GameState.camp_quest.get("active", false), "旧合同新触点确认后恢复活动")
		if not await _open_camp_option("outpost:legacy"): return
	_check(_hud._dialogue_kind == "claim" and _hud._dialogue_yes.visible, "旧待领奖合同仍提供真实交付按钮，而非只读历史")
	_hud._close_dialogue()
	_check(_wallet() == wallet and not GameState.camp_quest.get("paid", true)
		and GameState.camp_quest.get("gold") == original.get("gold") and GameState.camp_quest.get("xp") == original.get("xp"), "只进入旧单和恢复不会付奖、改价或吞未付收据")

func _chapter_one_resume_tail() -> void:
	_check(_evidence("next_clue_received") and _q().get("stage", "") == "completed"
		and _pending_total("onigiri") > 0, "真实修复和线索已完成，满包尾奖保存在待领取")
	var wallet := _wallet()
	var pending := GameState.pending_items.duplicate(true)
	_qm.abandon("lost_outpost_v1")
	_check(_q().get("receipts", {}).get("restoration", {}).get("paid", false), "旧放弃调用不能撤销已付首章")
	if not await _walk_home_context(true) or not await _open_camp_option("outpost:menu"): return
	_hud._close_dialogue()
	_check(_wallet() == wallet and GameState.pending_items == pending, "战役菜单阅读旧首章不重付或吞掉满包余量")
	await _claim_restoration()

func _future_reader_guard() -> void:
	var original := FileAccess.get_file_as_bytes(GameState.SAVE_PATH)
	_check(int(GameState.get("_future_campaign_min_reader")) > GameState.SAVE_VERSION, "较旧客户端识别战役最低读取版本")
	GameState.gold += 1
	GameState.save_enabled = true
	_check(not GameState.save_now() and not GameState.save_now(false), "手动保存与自动保存都拒绝覆盖更高版本战役")
	GameState.save_enabled = false
	_check(FileAccess.get_file_as_bytes(GameState.SAVE_PATH) == original and not FileAccess.file_exists(GameState.SAVE_PATH + ".tmp"), "未来章节、奖励与未知字段的原始存档字节完整保留")

func _forest_clues() -> bool:
	var before := _cq().duplicate(true)
	var wallet := _wallet()
	for id: String in ["c2:old_pact", "c2:torn_record", "c2:aid_cache", "c2:beacon", "not:a:prop"]:
		_campaign.object_action(id)
	_check(_same(before, _cq()) and _wallet() == wallet, "第二章错误/远程/越级动作不写证据也不发奖")
	if not await _cw("c2:herbalist"): return false
	# EN4 can legitimately discover authored objects while walking. Preserve all
	# quest/wallet guards, then isolate the hidden-call assertion at arrival.
	_check(_same(before.get("quests",{}),_cq().get("quests",{})) and _wallet() == wallet, "实际接近只发现现场，不生成交谈证据或支付奖励")
	before = _cq().duplicate(true)
	var prop := _cp("c2:herbalist")
	prop.hide()
	_check(not prop.is_visible_in_tree(), "直接API调用前NPC确实隐藏且没有等待帧")
	_campaign.object_action("c2:herbalist")
	_check(_same(before, _cq()), "隐藏的真实NPC不能被直接API调查")
	prop.show()
	await _ci("c2:herbalist", false)
	_check(_same(before, _cq()), "只读药师对话不视为已询问")
	var before_cancel := _cq().duplicate(true)
	var cancel_wallet := _wallet()
	var observed_during_cancel := {}
	var cancel_witness: Callable = func() -> void: _witness_campaign_discoveries(before_cancel, observed_during_cancel)
	_campaign.changed.connect(cancel_witness)
	await _tap(_hud._dialogue_no)
	_campaign.changed.disconnect(cancel_witness)
	_campaign_window_preserves_ledger(before_cancel, cancel_wallet, observed_during_cancel, "取消药师确认不改变任何其他账本字段、剧情证据、收据或钱包")
	await _ci("c2:herbalist")
	_check(_ce(1, "herbalist") and not _ce(1, "old_pact"), "与NPC明确交谈不替代另一个现场旧约")
	if not await _cw("c2:old_pact"): return false
	await _ci("c2:old_pact")
	_check(_ce(1, "old_pact") and _campaign_data.ready(_cq(), C2 + ":s1"), "旧约现场确认完成第一节拍")
	return _ce(1, "old_pact")

func _forest_rune_partial() -> bool:
	if not await _forest_clues(): return false
	if not await _cw("c2:route_marks"): return false
	await _ci("c2:route_marks")
	_check(_ce(2, "route_marks") and not _ce(2, "runes"), "刻痕只提供符标顺序，不自动解谜")
	if not await _cw("c2:rune_north"): return false
	await _ci("c2:rune_north")
	_check(not _ce(2, "runes") and not _ce(2, "torn_record"), "第一枚符标只保存未完成序列，不开门或授予残页")
	_check(_cq().get("puzzle_progress", {}).get(C2 + ":s2:runes", []) == ["north"], "部分机关前缀可被持久化为北，而不是只有最终完成布尔")
	return _ce(2, "route_marks")

## EN4 的行走/关闭暂停阅读可新增现场目击；只允许严格验证过的新 known_objects 行。
## 所有既有目击、其余动态字段、任务/谜题/收据和钱包仍须逐项不变。
func _witness_campaign_discoveries(before: Dictionary, witnessed: Dictionary) -> void:
	var prior_known: Dictionary = before.get("dynamic_runtime", {}).get("known_objects", {})
	var current_known: Dictionary = _cq().get("dynamic_runtime", {}).get("known_objects", {})
	for id: String in current_known:
		if prior_known.has(id) or witnessed.has(id): continue
		var object := _cp(id)
		if object == null or not object.has_method("is_observed") or not bool(object.call("is_observed", _player.global_position)): continue
		var proof := {"position": [object.global_position.x, object.global_position.y], "tick": WorldSim.sim.tick_count}
		if _same(current_known[id], proof): witnessed[id] = proof

func _campaign_window_preserves_ledger(before: Dictionary, wallet: Dictionary, witnessed: Dictionary, label: String, extra_guard := true) -> void:
	var after := _cq().duplicate(true)
	var prior_known: Dictionary = before.get("dynamic_runtime", {}).get("known_objects", {})
	var current_known: Dictionary = after.get("dynamic_runtime", {}).get("known_objects", {})
	var observed_additions := true
	var new_ids: Array[String] = []
	for id: String in prior_known:
		if not current_known.has(id) or not _same(prior_known[id], current_known[id]): observed_additions = false
	for id: String in current_known:
		if prior_known.has(id): continue
		new_ids.append(id)
		if not witnessed.has(id) or not _same(current_known[id], witnessed[id]): observed_additions = false
	_check(observed_additions, "只允许记录当帧有真实对象/视野/位置/时刻见证的新目击，既有目击不可改写")
	if not new_ids.is_empty(): print("CAMPAIGN_OBSERVED_ADDITIONS ", JSON.stringify({"window":label,"ids":new_ids}))
	if after.get("dynamic_runtime", {}).has("known_objects"):
		after["dynamic_runtime"]["known_objects"] = prior_known.duplicate(true)
	_check(_same(before, after) and _wallet() == wallet and extra_guard, label)

func _forest_runes() -> bool:
	var gate_cells: Array = _campaign_layout.gate_cells("c2:forest_gate")
	_check(not gate_cells.is_empty(), "林地栅门具有真实物理格")
	var closed := 0
	for cell: Vector2i in gate_cells:
		closed += int(ObstacleField.is_obstacle_cell(cell))
	_check(closed > 0, "解谜前栅门确实阻挡场景通行")
	if not gate_cells.is_empty():
		var middle := (Vector2(gate_cells[gate_cells.size() / 2]) + Vector2.ONE * 0.5) * 32.0
		if not await _walk_to(middle + Vector2(0, 80), "实际站到未开的栅门前", 8.0): return false
		var before := _cq().duplicate(true)
		var before_wallet := _wallet()
		var observed_during_contact := {}
		# 同步 changed 回调在发现入账当帧验视野；不能要求移动30帧后仍在屏内。
		var witness: Callable = func() -> void: _witness_campaign_discoveries(before, observed_during_contact)
		_campaign.changed.connect(witness)
		_player.set_physics_process(true)
		TouchInput.joystick_active = true
		TouchInput.move_vector = Vector2.UP
		await _frames(30)
		_campaign.changed.disconnect(witness)
		TouchInput.reset()
		_player.set_physics_process(false)
		_check(_player.global_position.y > middle.y + 10.0, "未解谜时实际向上移动被石门StaticBody挡住")
		_campaign_window_preserves_ledger(before, before_wallet, observed_during_contact, "身体碰门不改变任何其他账本字段、机关/回收证据、收据或钱包", not _ce(2, "runes") and not _ce(2, "torn_record"))
	var wallet := _wallet()
	for id: String in ["c2:rune_west"]:
		if not await _cw(id): return false
		await _ci(id)
	_check(not _ce(2, "runes") and _wallet() == wallet, "北→西错误次序不解锁、不发奖，可以重试")
	for id: String in ["c2:rune_north", "c2:rune_east", "c2:rune_west"]:
		if not await _cw(id): return false
		await _ci(id)
	_check(_ce(2, "runes"), "真实三个符标按北→东→西解开门锁")
	await _frames(6)
	var open := true
	for cell: Vector2i in gate_cells:
		open = open and not ObstacleField.is_obstacle_cell(cell)
	_check(open, "解谜同时移除同源真实栅门碰撞")
	_check(not _ce(2, "torn_record"), "开门不代替门后残页的实际回收")
	if not await _cw("c2:torn_record"): return false
	await _ci("c2:torn_record")
	_check(_ce(2, "torn_record") and _campaign_data.ready(_cq(), C2 + ":s2"), "经真实门后路线回收残页完成第二节拍")
	return _ce(2, "torn_record")

func _forest_rescue() -> bool:
	if not await _cw("c2:liaison"): return false
	await _ci("c2:liaison")
	_check(_ce(3, "liaison") and not _ce(3, "rescue"), "找到失联者不等于已救援")
	var before := _cq().duplicate(true)
	_campaign.object_action("c2:liaison")
	_check(not _ce(3, "rescue") and _same(before, _cq()), "缺少专用急救包不得现场空手救援")
	var npc_position := _cp("c2:liaison").global_position
	GameState.inventory["onigiri"] = 99
	GameState.inventory["water-pot"] = 99
	GameState.inventory["life-pot"] = 99
	var ordinary := GameState.inventory.duplicate(true)
	if not await _cw("c2:aid_cache"): return false
	await _ci("c2:aid_cache")
	_check(_ce(3, "aid_cache") and not _ce(3, "rescue") and ordinary == GameState.inventory, "满99仍可领取独有急救包，不进入普通背包、不远程救人")
	var picked := _cq().duplicate(true)
	await _ci("c2:aid_cache")
	_check(_same(picked, _cq()) and ordinary == GameState.inventory, "重复拾取不能复制急救证据或普通补给")
	if not await _cw("c2:liaison"): return false
	await _ci("c2:liaison")
	_check(_ce(3, "rescue") and ordinary == GameState.inventory, "带专用急救包返回现场确认才完成救援，普通药品不消耗")
	_check(_cp("c2:liaison").get("rescued") and is_zero_approx(_cp("c2:liaison").get_node("CharacterVisual").rotation), "获救联络员实际从卧姿恢复为驻留立姿")
	await _frames(30)
	_check(_cp("c2:liaison").global_position == npc_position, "救援后联络员继续原地驻留，无护送或隐藏计时")
	await _pause_resume_ui()
	return _ce(3, "rescue")

func _pause_resume_ui() -> void:
	var stages: Dictionary = _cq().get("quests", {}).duplicate(true)
	_hud._open_task_list()
	await _frames()
	# Godot把节点名中的冒号规范为下划线；以稳定章节前缀和节拍后缀定位同一控件。
	var abandon: Button = _hud._task_rows.find_child("Abandon_" + C2 + "*s4", true, false)
	_check(abandon != null, "真实任务面板能暂停当前未完成战役节拍")
	if abandon == null:
		print("CAMPAIGN_TASK_DEBUG ", JSON.stringify({"snapshots":_hud._task_snapshot,"visible":_hud._task_layer.visible,"passive":_hud.passive_layer.visible}))
		_hud._task_rows.print_tree_pretty()
		_hud._close_choice_layer()
		return
	await _tap(abandon)
	var confirm: Button = _hud._task_rows.find_child("ConfirmAbandon_" + C2 + "*s4", true, false)
	_check(confirm != null and not C2 in _cq().get("paused_chains", []), "点击暂停先展示明确确认，不立刻改变任务")
	if confirm != null: await _tap(confirm)
	_hud._close_choice_layer()
	_check(C2 in _cq().get("paused_chains", []) and _same(stages, _cq().get("quests", {})), "明确暂停保留所有真实行动和收据")
	if not await _cw("c2:signal_parts"): return
	var paused_state := _cq().duplicate(true)
	_campaign.object_action("c2:signal_parts")
	_check(_same(paused_state, _cq()) and not _ce(4, "signal_parts"), "暂停状态即使本人到场也阻止偷偷提交新行动")
	if not await _cw("c2:liaison"): return
	await _ci("c2:liaison")
	_check(not C2 in _cq().get("paused_chains", []) and _same(stages, _cq().get("quests", {})), "原地向真实联络员新触点确认继续，不重抽预算或复制证据")

func _forest_beacon() -> bool:
	var before := _cq().duplicate(true)
	_campaign.object_action("c2:beacon")
	_check(_same(before, _cq()), "救援不能替代远处烽灯修复，也不能远程领终段奖")
	if not await _cw("c2:signal_parts"): return false
	var inventory := GameState.inventory.duplicate(true)
	await _ci("c2:signal_parts")
	_check(_ce(4, "signal_parts") and not _ce(4, "beacon") and inventory == GameState.inventory, "信号零件仍是唯一任务证据，回收不自动修复")
	var reward: Dictionary = _campaign_data.reward(_cq(), C2 + ":s4")
	var bonus := str(reward.get("bonus", ""))
	_check(not bonus.is_empty(), "章节末段有可验收的普通补给奖励")
	if not bonus.is_empty(): GameState.inventory[bonus] = 99
	if not await _cw("c2:beacon"): return false
	var wallet := _wallet()
	await _ci("c2:beacon", false)
	_check(not _ce(4, "beacon") and _wallet() == wallet, "只读烽灯说明不提前修复或付奖")
	await _tap(_hud._dialogue_no)
	await _ci("c2:beacon")
	_check(_ce(4, "beacon") and _campaign_data.ready(_cq(), C2 + ":s4"), "完整前置证据加真实现场确认才点亮烽灯")
	_check(_cp("c2:beacon").get("repaired"), "烽灯实体实际表现已修复而非只有任务文字改变")
	var gold := roundi(int(reward["gold"]) * GameState.stats.gold_mult())
	var xp := int(int(reward["xp"]) * GameState.stats.passive_mult("xp", 1.1) * (1.0 + GameState.stats.equip_affix("xp")))
	_check(_cs(4).get("receipt", {}).get("paid", false) and GameState.gold == int(wallet["gold"]) + gold
		and _wallet_xp(_wallet()) == _wallet_xp(wallet) + xp and _pending_total(bonus) > 0,
		"库存99仍原子支付冻结合同金币经验，物品进入持久待领取")
	return _ce(4, "beacon")

func _forest_claim() -> void:
	if not await _cw("c2:beacon"): return
	var wallet := _wallet()
	var pending := GameState.pending_items.duplicate(true)
	_campaign.claim(C2 + ":s4")
	_check(_wallet() == wallet and _cs(4).get("receipt", {}).get("paid", false)
		and GameState.pending_items == pending, "冷恢复后已付满包合同不再支付金币经验或复制余量")
	var reward: Dictionary = _campaign_data.reward(_cq(), C2 + ":s4")
	var bonus := str(reward.get("bonus", ""))
	var remaining := _pending_total(bonus)
	_check(remaining > 0 and _pending_sources_unique(), "冷恢复保留有唯一来源的终段奖品余量")
	if not bonus.is_empty(): GameState.remove_item(bonus, 1)
	_check(_claim_one_pending(bonus) and _pending_total(bonus) == remaining - 1, "空出一格后明确领取已付终段的一份奖品")
	_check(_cs(4).get("receipt", {}).get("paid", false) and GameState.gold == int(wallet["gold"])
		and _wallet_xp(_wallet()) == _wallet_xp(wallet) and GameState.count_item(bonus) == 99,
		"领取余量只转移奖品，不再次增加金币或跨级经验")
	wallet = _wallet()
	pending = GameState.pending_items.duplicate(true)
	_campaign.claim(C2 + ":s4")
	_campaign.object_action("c2:beacon")
	_check(_wallet() == wallet and GameState.pending_items == pending, "重复领取和重复修复不能复付终段奖励")

func _claim_in_ui() -> void:
	await _ci("c2:beacon", false)
	var explicit_claim: bool = _hud._dialogue_yes.visible and _hud._dialogue_kind in ["camp_action", "claim"]
	_check(explicit_claim, "待付烽灯尾款提供玩家实际可用的独立领取按钮")
	if explicit_claim: await _tap(_hud._dialogue_yes)
	_hud._close_dialogue()
	await _frames()

func _travel_safety() -> void:
	if not await _cw("c2:beacon"): return
	_player.set_physics_process(true)
	await _frames(12)
	_player.set_physics_process(false)
	var population := _world_clock()
	var world_processing := _world.is_processing()
	_world.set_process(false)
	var origin_position := _player.global_position
	_player._hurt_iframes = 0.0
	_player._protect_timer = 0.0
	var hp := _player.current_hp
	_campaign.request_travel("forest", "c2:beacon")
	_check(_world._teleporting, "无危险时真实旅行先进入淡入阶段")
	_player.take_damage(1.0, Vector2.INF)
	await _frames(20)
	_check(_player.current_hp < hp and _player.global_position == origin_position and not _world._teleporting, "淡入期间真实受击取消迁移并保留受伤结果")
	_player.set_physics_process(true)
	await _frames(14)
	_player.set_physics_process(false)
	var candidates: Array = _campaign_layout.entry_candidates("forest")
	var actors: Array = []
	var originals: Dictionary = {}
	var created: Array = []
	# 使用既有模拟个体的真实MonsterBase表现节点作为移动夹具，不创建模拟个体或改变据点坐标。
	for inst: MonsterInstance in WorldSim.sim.instances.values():
		if not inst.is_alive or inst.species.ambient or inst.species.is_boss: continue
		if not _world._nodes.has(inst.id):
			_world._spawn_monster_node(inst)
			created.append(inst.id)
		var body: MonsterBase = _world._nodes.get(inst.id)
		if body == null: continue
		originals[inst.id] = {"position":body.global_position,"state":body.state}
		body.set_physics_process(false)
		body.state = MonsterBase.S_PATROL
		body.global_position = candidates[actors.size()]
		actors.append(body)
		if actors.size() == candidates.size(): break
	_check(actors.size() == candidates.size(), "安全落点否定夹具使用足够的既有真实演员")
	if actors.size() == candidates.size():
		var pos := _player.global_position
		var resources := _resources()
		_check(not _campaign.travel_destination("forest").is_finite(), "真实移动后的演员堵住全部候选点时拒绝旅行，不信旧出生坐标")
		_campaign.request_travel("forest", "c2:beacon")
		await _frames(20)
		_check(_player.global_position == pos and _same(resources, _resources()), "所有落点不安全时真实旅行请求不传送或返还资源")
		# 起手时默认点空着，淡入期间演员进入；必须在实际迁移前再次检查。
		actors[0].global_position = originals[actors[0].inst.id]["position"]
		_check(_campaign.travel_destination("forest").is_finite(), "起手确有一个可用真实候选点")
		_campaign.request_travel("forest", "c2:beacon")
		_check(_world._teleporting, "安全起手进入真实淡入阶段")
		actors[0].global_position = candidates[0]
		await _frames(20)
		_check(_player.global_position == pos and not _world._teleporting, "淡入期间落点被占后取消实际迁移并恢复输入")
		_check(_same(resources, _resources()), "晚到危险取消不补资源、不重置冷却")
		# 只保留默认点上的演员，至少一个旁路候选应可选；不挪走挡路者来制造安全。
		for i in range(1, actors.size()): actors[i].global_position = originals[actors[i].inst.id]["position"]
		var alternate: Vector2 = _campaign.travel_destination("forest")
		_check(alternate.is_finite() and alternate != candidates[0], "默认落点危险时选取真实安全的不同候选")
		_campaign.request_travel("forest", "c2:beacon")
		await _frames(20)
		_check(_player.global_position.distance_to(alternate) < 1.0 and not _world._teleporting, "实际迁移落在验证后的旁路候选")
		_check(_same(resources, _resources()), "旁路候选旅行同样保持资源与冷却")
		var arrival: Array = _cq().get("travel", {}).get("arrivals", {}).get("forest", [])
		_check(arrival.size() == 2 and Vector2(arrival[0],arrival[1]).distance_to(alternate)<1.0, "持久记录真实到达位置，而不是写死默认入口")
	for body_value: Variant in actors:
		if not is_instance_valid(body_value): continue
		var body := body_value as MonsterBase
		var id := body.inst.id
		if id in created:
			_world._nodes.erase(id)
			body.queue_free()
		else:
			body.global_position = originals[id]["position"]
			body.state = originals[id]["state"]
	_world.set_process(world_processing)
	await _frames(3)
	_check(_same(population, _world_clock()), "安全筛选与取消没有新增、杀死或移动原生态实例")
	await _cw("c2:beacon")

func _hud_contract() -> void:
	_hud._close_dialogue()
	var root: Control = _hud.get_node("Root")
	for canvas: Vector2 in [Vector2(1280, 720), Vector2(1560, 720), Vector2(1024, 640)]:
		root.set_anchors_preset(Control.PRESET_TOP_LEFT)
		root.position = Vector2.ZERO
		root.size = canvas
		await _frames()
		var visible := 0
		for id: String in FIXED_ACTIONS:
			var button: Control = root.get_node(id)
			visible += int(button.is_visible_in_tree())
			_check(root.get_global_rect().encloses(button.get_global_rect()) and minf(button.size.x, button.size.y) >= 80.0, "%s在%s保持完整拇指触点" % [id, canvas])
		for a in FIXED_ACTIONS.size():
			for b in range(a + 1, FIXED_ACTIONS.size()):
				var first: Control = root.get_node(FIXED_ACTIONS[a])
				var second: Control = root.get_node(FIXED_ACTIONS[b])
				_check(not first.get_global_rect().grow(4).intersects(second.get_global_rect().grow(4)), "%s下%s/%s不重叠" % [canvas, FIXED_ACTIONS[a], FIXED_ACTIONS[b]])
		_check(visible == 6, "%s只保留六个常驻动作" % canvas)
	root.size = Vector2(1280, 720)
	await _frames()

func _campaign_interruptions() -> void:
	var before := _cq().duplicate(true)
	_hud._toggle_pause()
	_check(get_tree().paused and _same(before, _cq()), "暂停阅读不会回滚已完成证据")
	_hud._toggle_pause()
	_campaign.abandon(C2 + ":s3")
	var suspended := _cq().duplicate(true)
	_campaign.accept_chapter(C2)
	_check(_cs(3).get("evidence", {}) == before.get("quests", {}).get(C2 + ":s3", {}).get("evidence", {}), "暂停和恢复章节保留独有物品及救援证据")
	_check(not suspended.is_empty(), "暂停仍保留战役账本")
	_player._hurt_iframes = 0.0
	_player.take_damage(1000000.0, Vector2.INF)
	_check(_player._is_dead and _cs(3).get("evidence", {}) == before.get("quests", {}).get(C2 + ":s3", {}).get("evidence", {}), "真实死亡不丢救援和专用物品证据")
	_player._respawn()
	_player.set_physics_process(false)

func _expected_path() -> String:
	return GameState.SAVE_PATH + ".campaign_expected"

func _write_campaign_expected() -> void:
	_write_expected({"campaign": _cq().duplicate(true), "outpost": _q().duplicate(true), "wallet": _wallet(), "pending_items": GameState.pending_items.duplicate(true),
		"checkpoints": GameState.discovered_checkpoints.duplicate(), "clock": _world_clock(),
		"resources": _resources(), "destroyed": ObstacleField.destroyed_list()})

func _cold_campaign_expected() -> void:
	var expected := _expected()
	var saved: Dictionary = expected["campaign"]
	var core_equal := true
	for key: String in ["id", "version", "seed", "chapter1_proof", "chapters", "quests", "random_used", "active_random", "history"]:
		core_equal = core_equal and _same(_cq().get(key), saved.get(key))
	core_equal = core_equal and _same(_cq().get("paused_chains", []), saved.get("paused_chains", []))
	if not core_equal:
		for key: String in ["id", "version", "seed", "chapter1_proof", "chapters", "quests", "random_used", "active_random", "history"]:
			if not _same(_cq().get(key), saved.get(key)):
				print("CAMPAIGN_COLD_DIFF ", JSON.stringify({"key":key,"expected":saved.get(key),"actual":_cq().get(key)}))
	_check(core_equal, "独立进程完整恢复战役证据、分支、预算和支付收据")
	_check(_same(_cq().get("travel", {}).get("visited", []), saved.get("travel", {}).get("visited", [])), "独立进程保留真正到达过的远征地点")
	_check(_same(_cq().get("travel", {}).get("arrivals", {}), saved.get("travel", {}).get("arrivals", {})), "独立进程保留真实安全候选落点")
	# unlocked/services/flags可由证据重建；未完成序列不能用重建掩盖丢失。
	var pending: Dictionary = saved.get("puzzle_progress", {}).duplicate(true)
	for key: String in pending.keys():
		var split := key.rsplit(":", true, 1)
		if saved.get("quests", {}).get(split[0], {}).get("evidence", {}).has(key): pending.erase(key)
	_check(_same(_cq().get("puzzle_progress", {}), pending), "独立进程精确保留尚未完成的机关输入前缀")
	if _ce(2, "runes"):
		for id: String in ["c2:rune_north", "c2:rune_east", "c2:rune_west"]:
			_check(_cp(id) != null and _cp(id).get("activated"), "完成机关冷加载仍有点亮的真实符标：" + id)
	_check(_same(_q(), expected["outpost"]), "独立进程保留原首章原始账本")
	_check(_same(_wallet(), expected["wallet"]), "独立进程精确恢复金币、经验、等级和库存")
	_check(_same(GameState.pending_items, expected.get("pending_items", {})) and _pending_sources_unique(), "独立进程逐项恢复待领取数量、ID和唯一来源")
	var checkpoints := GameState.discovered_checkpoints.duplicate()
	var expected_checkpoints: Array = expected["checkpoints"].duplicate()
	checkpoints.sort()
	expected_checkpoints.sort()
	_check(_same(checkpoints, expected_checkpoints), "独立进程不制造或丢失已启用服务")
	_check(_same(_world_clock(), expected["clock"]), "独立进程保留原生态个体和世界时钟")

func _failed_save(phase: String) -> void:
	var old := FileAccess.get_file_as_bytes(GameState.SAVE_PATH)
	var time := GameState.last_save_unix
	GameState.gold += 10
	if phase == "fail_write": GameState.tutorial_flags["campaign_large_write_probe"] = "x".repeat(65536)
	GameState.save_enabled = true
	var saved := GameState.save_now()
	GameState.save_enabled = false
	_check(not saved and GameState.last_save_unix == time, phase + "真实失败不宣称保存成功")
	_check(FileAccess.get_file_as_bytes(GameState.SAVE_PATH) == old, phase + "完整上一份章节/收据/世界好档未覆盖")
	_check(GameState._save_timer > 0.0 and not FileAccess.file_exists(GameState.SAVE_PATH + ".tmp"), phase + "移除短写临时档并保留重试")

func _cold_campaign(phase: String) -> void:
	await _mount(phase in ["chapter1", "chapter1_pending"])
	if phase not in ["chapter1", "chapter1_pending", "invalid_proof", "legacy_menu_pending", "legacy_menu_paused", "future_reader"]: _cold_campaign_expected()
	match phase:
		"chapter1": await _chapter_one_seed()
		"chapter1_pending": await _chapter_one_seed(true)
		"chapter1_resume_tail": await _chapter_one_resume_tail()
		"legacy_menu_pending": await _legacy_menu("pending")
		"legacy_menu_paused": await _legacy_menu("paused")
		"future_reader": _future_reader_guard()
		"depart": await _depart_forest()
		"rune_partial": await _forest_rune_partial()
		"runes": await _forest_runes()
		"rescue": await _forest_rescue()
		"beacon99": await _forest_beacon()
		"claim": await _forest_claim()
		"safety": await _travel_safety()
		"death":
			var before := _cq().duplicate(true)
			_player._hurt_iframes = 0.0
			_player.take_damage(1000000.0, Vector2.INF)
			_check(_player._is_dead and _same(before, _cq()), "真实死亡窗口完整保留战役证据和已付收据")
		"paid":
			_check(not _player._is_dead, "真实死亡存档冷启动后按原有规则复活")
			var wallet := _wallet()
			_campaign.claim(C2 + ":s4")
			_campaign.object_action("c2:beacon")
			_check(_wallet() == wallet and _cs(4).get("receipt", {}).get("paid", false), "已支付冷档重复回调不能再领整章尾款")
			await _hud_contract()
		"legacy_v13":
			_check(_cq().get("chapters", {}).is_empty() and _cq().get("quests", {}).is_empty(), "v13旧完成档仅继承首章权威，没有新章进度和新奖励")
			_check(_campaign_data.chapter1_complete(_cq()), "v13旧档真正完成的修复和后续线索仍能开启新章资格")
			var wallet := _wallet()
			_campaign.object_action("c2:beacon")
			_campaign.claim(C2 + ":s4")
			_check(_wallet() == wallet and _cq().get("quests", {}).is_empty(), "旧首章迁移不能顺带领取第二章奖励")
		"invalid_proof":
			_check(_same(_wallet(), _expected()["wallet"]), "损坏证据不吞掉已经写盘的钱包")
			_check(not _ce(2, "runes") and not _ce(2, "torn_record"), "缺失刻痕前置的坏档不能夹带已开门或门后残页证据")
			_check(_cs(4).get("receipt", {}).get("paid", false), "修复坏证据时保留不可逆已支付收据")
			var wallet := _wallet()
			_campaign.claim(C2 + ":s4")
			_check(_wallet() == wallet, "证据消毒不能重新支付之前已经领过的奖")
		"fail_flush", "fail_write":
			_failed_save(phase)
		_:
			_check(false, "未知战役冷启动阶段：" + phase)
	if _fails == 0 and phase not in ["paid", "legacy_v13", "legacy_menu_pending", "legacy_menu_paused", "future_reader", "invalid_proof", "fail_flush", "fail_write"]:
		_check(_save(), "真实独立章节进度原子写盘：" + phase)
		_write_campaign_expected()
	await _unmount()

func _run() -> void:
	Engine.time_scale = 4.0
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		if OS.get_environment("HOTW_TEST_SAVE").is_empty():
			_check(false, "冷启动必须由隔离存档环境启动")
		else:
			await _cold_campaign(args[0])
		_finish()
		return
	GameState.SAVE_PATH = "user://campaign_acceptance_%d.json" % OS.get_process_id()
	await _mount(true)
	if await _chapter_one_seed() and await _depart_forest() and await _forest_rune_partial() and await _forest_runes() and await _forest_rescue():
		if await _forest_beacon(): await _forest_claim()
		await _travel_safety()
		await _campaign_interruptions()
	await _hud_contract()
	await _unmount()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.SAVE_PATH))
	_finish()

func _finish() -> void:
	print("CAMPAIGN_WALKED_PIXELS ", snappedf(_walked, 1.0))
	print("=== CAMPAIGN ACCEPTANCE %s (%d checks, %d failures) ===" % ["PASS" if _fails == 0 else "FAIL", _checks, _fails])
	get_tree().quit(0 if _fails == 0 else 1)
