## 失联的前哨：实际场景、触屏确认、玩家碰撞移动与独立冷进程契约。
## 继承旧首章的隔离装配/断言工具；不继承旧剧情流程或通过伪造动作完成任务。
extends "res://tests/camp_pilot_contract_test.gd"

var _walked := 0.0
var _walk_failures := 0
var _patrol_text := ""

func _mount(fresh := false) -> void:
	if fresh: _patrol_text = ""
	get_tree().node_added.connect(_freeze_new_actor)
	await super._mount(fresh)
	get_tree().node_added.disconnect(_freeze_new_actor)

func _freeze_new_actor(node: Node) -> void:
	if not node is MonsterBase: return
	# node_added 早于_ready，Godot 会在_ready自动启用脚本物理处理；冻结必须等ready信号。
	if node.is_node_ready(): node.set_physics_process(false)
	else: node.ready.connect(func() -> void: node.set_physics_process(false), CONNECT_ONE_SHOT)

func _prop(id: String) -> Node2D:
	for node: Node in get_tree().get_nodes_in_group("outpost_objects"):
		if node is Node2D and str(node.get("outpost_id")) == id:
			return node as Node2D
	return null

func _step_touch(index: int, pressed: bool, point := Vector2(450, 420)) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = get_viewport().get_screen_transform() * point
	event.pressed = pressed
	Input.parse_input_event(event)

## 格心导航只规划路线，真正位移仍由原玩家 TouchInput / move_and_slide 驱动。
## 不增速、不删碰撞、不以设置位置代替成功动作，怪物冻结仅隔离路径/剧情契约。
func _walk_to(goal: Vector2, label: String, arrival := 18.0) -> bool:
	_hud._close_dialogue()
	TouchInput.reset()
	var start := _player.global_position
	var cell_size := 32.0
	var a := Vector2i((start / cell_size).floor())
	var b := Vector2i((goal / cell_size).floor())
	var lo := Vector2i(mini(a.x, b.x) - 28, mini(a.y, b.y) - 28)
	var hi := Vector2i(maxi(a.x, b.x) + 29, maxi(a.y, b.y) + 29)
	var astar := AStarGrid2D.new()
	astar.region = Rect2i(lo, hi - lo)
	astar.cell_size = Vector2.ONE * cell_size
	astar.offset = Vector2.ONE * cell_size * 0.5
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()
	for y in range(lo.y, hi.y):
		for x in range(lo.x, hi.x):
			var cell := Vector2i(x, y)
			astar.set_point_solid(cell, ObstacleField.blocks((Vector2(cell) + Vector2.ONE * 0.5) * cell_size, 12.0))
	astar.set_point_solid(a, false)
	if astar.is_point_solid(b):
		_check(false, label + "：目的格被真实障碍阻挡")
		_walk_failures += 1
		return false
	var path := astar.get_point_path(a, b)
	if path.is_empty():
		_check(false, label + "：真实同源碰撞地图没有路线")
		_walk_failures += 1
		return false
	path.append(goal)
	var cursor := 1 if path.size() > 1 else 0
	var previous := _player.global_position
	var stuck_origin := previous
	var stuck_frames := 0
	_player.set_physics_process(true)
	for step in 6000:
		if _player.global_position.distance_to(goal) <= arrival: break
		while cursor < path.size() - 1 and _player.global_position.distance_to(path[cursor]) < 12.0:
			cursor += 1
		TouchInput.joystick_active = true
		TouchInput.move_vector = _player.global_position.direction_to(path[cursor])
		await get_tree().physics_frame
		_freeze_monsters()
		var moved := _player.global_position.distance_to(previous)
		if moved >= 32.0:
			_check(false, label + "：单帧位移必须来自行走而非传送")
		_walked += moved
		previous = _player.global_position
		stuck_frames += 1
		if stuck_frames >= 120:
			if _player.global_position.distance_to(stuck_origin) < 4.0: break
			stuck_origin = _player.global_position
			stuck_frames = 0
	TouchInput.reset()
	_player.set_physics_process(false)
	var arrived := _player.global_position.distance_to(goal) <= arrival
	_check(arrived, label + "：实际玩家碰撞行走抵达")
	if not arrived:
		_walk_failures += 1
		print("OUTPOST_WALK_BLOCKER ", JSON.stringify({"label": label, "start": [start.x, start.y],
			"goal": [goal.x, goal.y], "actual": [_player.global_position.x, _player.global_position.y],
			"waypoint": [path[cursor].x, path[cursor].y]}))
	return arrived

func _walk_prop(id: String, offset := Vector2(0, 56)) -> bool:
	var prop := _prop(id)
	_check(prop != null, "稳定实体ID存在：" + id)
	if prop == null: return false
	return await _walk_to(prop.global_position + offset, "前往" + id)

func _finish() -> void:
	print("OUTPOST_WALKED_PIXELS ", snappedf(_walked, 1.0))
	print("=== OUTPOST CHAPTER CONTRACT %s (%d checks, %d failures) ===" % ["PASS" if _fails == 0 else "FAIL", _checks, _fails])
	get_tree().quit(0 if _fails == 0 else 1)

func _q() -> Dictionary:
	return GameState.get("outpost_quest") as Dictionary

func _evidence(key: String) -> bool:
	return bool(_q().get("evidence", {}).get(key, false))

func _chapter_equal(before: Dictionary) -> bool:
	return _same(before, _q())

func _interact(id: String, confirm := true) -> void:
	var prop := _prop(id)
	_check(prop != null, "使用真实道具：" + id)
	if prop == null: return
	_hud._close_dialogue()
	prop.interact()
	await _frames()
	_check(_hud._dialogue_panel.visible, id + "打开真实阅读对话")
	_check(get_tree().paused, id + "主动阅读暂停世界")
	if not confirm: return
	if _hud._dialogue_yes.visible:
		await _tap(_hud._dialogue_yes)
	_hud._close_dialogue()
	await _frames()

func _accept_chapter() -> bool:
	await _home()
	_keeper().interact()
	await _frames()
	_check(_hud._dialogue_panel.visible, "真实营地巡守提供完整前哨章节")
	if _hud._dialogue_kind == "camp_choice":
		var accept_button: Button
		for child: Node in _hud._dialogue_option_box.get_children():
			if child is Button and (str(child.name).contains("accept") or str(child.name).contains("resume")):
				accept_button = child
		_check(accept_button != null, "旧单并存时明确选择完整前哨章节")
		if accept_button != null: await _tap(accept_button)
	if not _hud._dialogue_yes.visible:
		_check(false, "前哨接取存在明确确认入口")
		return false
	await _tap(_hud._dialogue_yes)
	_hud._close_dialogue()
	_check(_q().get("id", "") == "lost_outpost_v1" and _q().get("active", false), "新接取写入稳定完整章节ID")
	return _q().get("id", "") == "lost_outpost_v1" and _q().get("active", false)

func _action_failures() -> void:
	var before := _q().duplicate(true)
	var wallet := _wallet()
	for id: String in ["not_a_prop", "patrol_record", "entrance_record", "wounded_patrol", "aid_bag", "repair_tools", "signpost"]:
		_qm.outpost_action(id)
	_check(_chapter_equal(before) and _wallet() == wallet, "远程或错误ID动作不写证据、不拿任务物、不付奖励")
	_check(not GameState.discovered_checkpoints.has("outpost:lost_watch"), "未修复前即使伪造远程操作也无前哨检查点")
	var target: Dictionary = _qm.outpost_target()
	_check(not target.is_empty() and not target.get("live_facts", {}).has("alive_count"), "任务提供作者线索但不泄漏远处活体生态")

func _first_clue() -> bool:
	if not await _walk_prop("patrol_record"): return false
	var prop := _prop("patrol_record")
	_patrol_text = str(_qm.outpost_object_payload("patrol_record").get("text", ""))
	var before := _q().duplicate(true)
	prop.hide()
	_qm.outpost_action("patrol_record")
	_check(_chapter_equal(before), "隐藏实际道具不能被直接API调查")
	prop.show()
	await _interact("patrol_record", false)
	_check(_chapter_equal(before), "打开线索阅读不等于确认调查")
	_hud._close_dialogue()
	_check(_chapter_equal(before), "关闭线索对话完整保留原状态")
	# 原触点开窗后，另一个手指点确认不得穿透为新确认。
	_step_touch(91, true)
	prop.interact()
	await _frames()
	await _tap(_hud._dialogue_yes)
	_check(_chapter_equal(before), "保留原触点时另一手指不能确认新的线索")
	_step_touch(91, false)
	_hud._on_dialogue_action("confirm")
	_check(_chapter_equal(before), "原触点释放帧不能变成确认")
	await _frames()
	await _tap(_hud._dialogue_yes)
	_hud._close_dialogue()
	_check(_evidence("patrol_read") and not _evidence("entrance_read"), "新手势只记第一条具名线索，不替代第二现场")
	var paid := _wallet()
	_qm.outpost_action("patrol_record")
	_check(_wallet() == paid, "重复调查第一线索不重复支付")
	return _evidence("patrol_read")

func _enter_and_recover(take_tools := true, verify_front := false) -> bool:
	if not await _walk_prop("entrance_record", Vector2(-40, 56)): return false
	var first_text := _patrol_text
	var second_text := str(_qm.outpost_object_payload("entrance_record").get("text", ""))
	_check(first_text.contains("入口") and second_text.contains("缺口") and first_text != second_text,
		"两条具名调查信息不同且指向可执行现场行动")
	var investigation_wallet := _wallet()
	await _interact("entrance_record")
	_assert_reward_delta(investigation_wallet, 6, 8, "调查")
	_check(_evidence("entrance_read") and not _evidence("wounded_found"), "第二线索完成后仍须实际寻找伤员")
	if not await _walk_prop("signpost", Vector2(0, 64)): return false
	var early := _q().duplicate(true)
	var early_wallet := _wallet()
	await _interact("signpost")
	_check(_chapter_equal(early) and _wallet() == early_wallet
		and not GameState.discovered_checkpoints.has("outpost:lost_watch"), "即使站在真实路标旁，缺少救援/工具/生态证据也不能修复或领奖")
	if verify_front and not await _front_route_contract(): return false
	var layout: Script = load("res://scripts/ecology/outpost_layout.gd")
	var entrances: Dictionary = layout.entrances()
	var side: Vector2 = entrances["side"]
	if not await _walk_to(side + Vector2(-96, 0), "绕行真实西侧入口外"): return false
	if not await _walk_to(side + Vector2(96, 0), "从真实侧门进入围墙"): return false
	if not await _walk_prop("wounded_patrol", Vector2(0, 56)): return false
	await _interact("wounded_patrol")
	_check(_evidence("wounded_found") and not _evidence("rescued"), "找到伤员不等于自动救援")
	var position := _prop("wounded_patrol").global_position
	await _frames(90)
	_check(_prop("wounded_patrol").global_position == position, "受伤巡守原地等待，不变成护送或计时任务")
	var before := _q().duplicate(true)
	_qm.outpost_action("wounded_patrol")
	_check(not _evidence("rescued") and _q().get("evidence", {}) == before.get("evidence", {}), "缺少独有药包和工具时不能救援")
	if not await _walk_prop("supply_record", Vector2(0, 56)): return false
	await _interact("supply_record")
	_check(_evidence("supply_read") and not _evidence("aid_taken") and not _evidence("tools_taken"), "补给线索只揭示物资去处，不直接授予任务物")
	if not await _walk_prop("aid_bag", Vector2(0, 56)): return false
	var ordinary := GameState.inventory.duplicate(true)
	await _interact("aid_bag")
	_check(_evidence("aid_taken") and GameState.inventory == ordinary, "真实药包进入唯一任务证据，不占99库存也不扣普通药品")
	var after := _q().duplicate(true)
	await _interact("aid_bag")
	_check(_q().get("evidence", {}) == after.get("evidence", {}) and GameState.inventory == ordinary, "药包重复操作不会复制或消耗独有证据")
	if take_tools:
		return await _take_tools_and_aid()
	return true

func _take_tools_and_aid() -> bool:
	if not await _walk_prop("repair_tools", Vector2(0, 56)): return false
	var ordinary := GameState.inventory.duplicate(true)
	await _interact("repair_tools")
	_check(_evidence("tools_taken") and GameState.inventory == ordinary, "工具经真实绕路取得，独有证据与普通库存分离")
	if not await _walk_prop("wounded_patrol", Vector2(0, 56)): return false
	_check(not _evidence("rescued"), "持有药包工具之后仍需明确救援")
	var rescue_wallet := _wallet()
	await _interact("wounded_patrol")
	_assert_reward_delta(rescue_wallet, 9, 12, "救援")
	_check(_evidence("rescued") and _evidence("aid_taken") and _evidence("tools_taken"), "实际救援成功且保留两份唯一领取凭据")
	_check(GameState.inventory == ordinary, "救援不消耗背包普通恢复品")
	_check(_prop("wounded_patrol").get("rescued") and is_zero_approx(_prop("wounded_patrol").get_node("PatrolVisual").rotation), "救援后的实际巡守从受伤卧姿恢复为驻留立姿")
	_check(not _evidence("signpost_repaired") and not GameState.discovered_checkpoints.has("outpost:lost_watch"), "救援后不能跳过生态与修复直接启用前哨")
	return _evidence("rescued")

func _front_route_contract() -> bool:
	var layout: Script = load("res://scripts/ecology/outpost_layout.gd")
	var front: Vector2 = layout.entrances()["front"]
	if not await _walk_to(front + Vector2(0, 80), "正门障碍前实际站位"): return false
	var evidence: Dictionary = _q().get("evidence", {}).duplicate(true)
	_player.set_physics_process(true)
	TouchInput.joystick_active = true
	TouchInput.move_vector = Vector2.UP
	await _frames(35)
	TouchInput.reset()
	_player.set_physics_process(false)
	_check(_player.global_position.y > front.y + 15.0, "未打碎路障时实际向上行走被正门挡住")
	_check(_q().get("evidence", {}) == evidence, "触碰路障不伪造调查或物资证据")
	var cells: Array = layout.front_barricade_cells()
	for cell: Vector2i in cells:
		var pos := (Vector2(cell) + Vector2.ONE * 0.5) * 32.0
		if not await _walk_to(pos + Vector2(0, 48), "逐格路障近身挥砍"): return false
		_player.facing = Vector2.UP
		for _swing in 2:
			_player.set_physics_process(true)
			TouchInput.queue_attack()
			await _frames(20)
			_player.set_physics_process(false)
		_check(not ObstacleField.is_obstacle_cell(cell), "真实普通攻击两刀移除正门石障：" + str(cell))
	if not await _walk_to(front + Vector2(0, -96), "打通后穿过真实正门"): return false
	if not await _walk_to(front + Vector2(0, 96), "实际退出正门再验证侧路"): return false
	return true

func _world_population() -> Dictionary:
	var rows := {}
	for id: int in WorldSim.sim.instances:
		var inst: MonsterInstance = WorldSim.sim.instances[id]
		rows[id] = {"alive": inst.is_alive, "region": inst.region_id,
			"species": inst.species.species_name, "spawn": inst.spawn_pos}
	return {"rows": rows, "nests": WorldSim.sim.nests.duplicate(true)}

func _deplete_local() -> void:
	# 旧世界耗尽夹具只经模拟权威产生自然死亡，不新增生物，不发玩家贡献事件。
	WorldSim.sim.reintroduction_enabled = false
	for inst: MonsterInstance in WorldSim.sim.instances.values():
		if inst.is_alive and inst.spawn_pos.distance_to(WorldConfig.spawn_pos()) <= 12000.0:
			inst.lifespan = inst.age + 1
	WorldSim.sim.tick()
	_world._stream_pass()
	await _frames(4)
	_freeze_monsters()

func _ecology_context() -> void:
	_hud._close_dialogue()
	_player.set_physics_process(true)
	TouchInput.queue_interact()
	await _frames(4)
	_player.set_physics_process(false)
	await _frames()

func _choose_ecology(branch: String) -> bool:
	_check(_hud._dialogue_panel.visible and _hud._dialogue_kind == "camp_choice", "现场生态选择使用真实暂停分支面板")
	if not _hud._dialogue_panel.visible or _hud._dialogue_kind != "camp_choice": return false
	var button: Button
	for child: Node in _hud._dialogue_option_box.get_children():
		if child is Button and str(child.name).contains("choose_" + branch): button = child
	_check(button != null and not button.disabled, "真实生态分支按钮可用：" + branch)
	if button == null or button.disabled: return false
	var before := _q().duplicate(true)
	await _tap(button)
	_check(_chapter_equal(before), "点击处理方案只预览，不提交生态行动")
	await _tap(_hud._dialogue_no)
	_check(_chapter_equal(before), "分支确认前返回完整保留原状态")
	for child: Node in _hud._dialogue_option_box.get_children():
		if child is Button and str(child.name).contains("choose_" + branch): button = child
	await _tap(button)
	await _tap(_hud._dialogue_yes)
	_hud._close_dialogue()
	_check(_q().get("choice", "") == branch, "独立触点明确提交生态分支：" + branch)
	return _q().get("choice", "") == branch

func _ecology(depleted := false) -> bool:
	if not await _walk_prop("survey_marker", Vector2(0, 56)): return false
	var before := _world_population()
	await _interact("survey_marker")
	for _attempt in 500:
		if _q().get("outcome", "") != "" or not _q().get("target", {}).is_empty(): break
		await _frames(2)
	_check(_world_population() == before, "现场调查与目标核对不生成生物、不更改密度或巢穴")
	if depleted:
		# 核对供给后仍须明确确认现场结果，不以“暂无目标”自动白领章节。
		if _q().get("outcome", "") == "":
			await _interact("survey_marker")
		_check(_evidence("site_surveyed"), "耗尽生态段必须有真实前哨现场观测")
		_check(_q().get("outcome", "") == "survey" and _q().get("kills", []).is_empty()
			and _q().get("ransacks", []).is_empty(), "完全耗尽旧世界仅以实际观测替代生态段，不制造猎杀/捣巢")
		return _q().get("outcome", "") == "survey"
	var target: Dictionary = _q().get("target", {})
	_check(not target.is_empty(), "新世界生态段使用原有可行目标")
	if target.is_empty(): return false
	var pos := Vector2(float(target["pos"][0]), float(target["pos"][1]))
	if not await _walk_to(pos + Vector2(0, 90), "从前哨实际行走到活体据点", 20.0): return false
	_world._stream_pass()
	await _frames(6)
	_freeze_monsters()
	await _ecology_context()
	_check(_evidence("site_surveyed"), "正常生态段必须亲自抵达实际活体据点调查")
	if not await _choose_ecology("ransack"): return false
	var ledger := _q().duplicate(true)
	EventBus.monster_killed_at.emit(-1, target["species"], target["region_id"], pos)
	EventBus.monster_killed_at.emit(123456789, target["species"], "wrong_region", pos)
	EventBus.nest_ransacked_at.emit(target["species"], "wrong_region", pos)
	_check(_chapter_equal(ledger), "不存在的目标ID和错误区域事件不能推进生态账本")
	var natural: MonsterInstance
	for inst: MonsterInstance in WorldSim.sim.instances.values():
		if inst.is_alive and inst.region_id == target["region_id"] and inst.species.species_name == target["species"]:
			natural = inst
			break
	if natural != null:
		natural.lifespan = natural.age + 1
		WorldSim.sim.tick()
		await _frames()
		_check(not natural.is_alive and _q().get("kills", []).is_empty() and _q().get("outcome", "") == "",
			"真实自然死亡不算玩家猎杀或提前完成生态段")
		EventBus.monster_killed_at.emit(natural.id, natural.species.species_name, natural.region_id, natural.spawn_pos)
		_check(_q().get("kills", []).is_empty(), "即使对自然死亡ID伪发贡献事件也不能冒领玩家猎杀")
	var nest: NestNode
	for node: Node in get_tree().get_nodes_in_group("nests"):
		if node is NestNode and node.nest_key == target["key"]: nest = node
	_check(nest != null, "目标存在真实已加载巢穴实体")
	if nest == null: return false
	if not await _walk_to(nest.global_position + Vector2(0, 48), "巢体普通攻击站位", 8.0): return false
	var alive := 0
	for inst: MonsterInstance in WorldSim.sim.instances.values():
		if inst.is_alive and inst.region_id == target["region_id"] and inst.species.species_name == target["species"]: alive += 1
	_player.facing = Vector2.UP
	for swing in 8:
		if not is_instance_valid(nest): break
		_player.set_physics_process(true)
		TouchInput.queue_attack()
		await _frames(20)
		_player.set_physics_process(false)
		_freeze_monsters()
	var alive_after := 0
	for inst: MonsterInstance in WorldSim.sim.instances.values():
		if inst.is_alive and inst.region_id == target["region_id"] and inst.species.species_name == target["species"]: alive_after += 1
	_check(not WorldSim.sim.nests[target["key"]]["active"] and _q().get("outcome", "") == "ransack",
		"真实普通攻击打碎巢穴，权威生态与章节证据同时完成")
	_check(alive_after == alive, "正常捣巢保留原有活体，不清场或制造新怪")
	_check(not _evidence("signpost_repaired") and not GameState.discovered_checkpoints.has("outpost:lost_watch"), "真实生态结果不能自动修复或自动解锁检查点")
	return _q().get("outcome", "") == "ransack"

func _repair(pending := false) -> bool:
	var before := _q().duplicate(true)
	_qm.outpost_action("signpost")
	_check(_chapter_equal(before), "远离路标时不能远程修复或领取终段奖励")
	if not await _walk_prop("signpost", Vector2(0, 64)): return false
	_check(not GameState.discovered_checkpoints.has("outpost:lost_watch"), "仅走到/看见路标不提前开启检查点")
	var wallet := _wallet()
	await _interact("signpost", false)
	_check(not _evidence("signpost_repaired") and not GameState.discovered_checkpoints.has("outpost:lost_watch"), "仅打开修复说明不视为修复")
	await _tap(_hud._dialogue_no)
	_check(_wallet() == wallet and not _evidence("signpost_repaired"), "取消修复不会花物品/付奖励或改变路标")
	await _interact("signpost")
	_check(_evidence("signpost_repaired") and GameState.discovered_checkpoints.has("outpost:lost_watch"), "真实本地确认修复后才启用前哨检查点")
	_check(_prop("signpost").get("repaired") and _prop("wounded_patrol").get("rescued"), "实际路标与常驻巡守表现同步永久章节结果")
	_check(not str(_q().get("next_clue", "")).is_empty(), "修复后留下可读后续线索")
	if pending:
		_check(_wallet() == wallet and not _q().get("receipts", {}).get("restoration", {}).get("paid", false),
			"库存99保留已经修复的世界状态，但终段整笔奖励保持未支付")
	else:
		_assert_reward_delta(wallet, 24, 24, "修复")
		_check(_q().get("stage", "") == "completed" and _q().get("receipts", {}).get("restoration", {}).get("paid", false),
			"普通容量在前哨直接完成最终支付，无强制返回营地")
		await _next_clue_contract()
	return _evidence("signpost_repaired")

func _assert_reward_delta(before: Dictionary, base_gold: int, base_xp: int, label: String) -> void:
	var gold := 0 if _q().get("legacy_reserved", false) else roundi(base_gold * GameState.stats.gold_mult())
	var xp := 0 if _q().get("legacy_reserved", false) else int(base_xp * GameState.stats.passive_mult("xp", 1.1) * (1.0 + GameState.stats.equip_affix("xp")))
	_check(GameState.gold == int(before["gold"]) + gold and GameState.stats.xp == int(before["xp"]) + xp,
		label + "金币和经验整笔精确到账，旧单保留时本章不重付")

func _next_clue_contract() -> void:
	if not await _walk_prop("wounded_patrol", Vector2(0, 56)): return
	var wallet := _wallet()
	await _interact("wounded_patrol")
	_check(_evidence("next_clue_received") and _wallet() == wallet, "完结后与真实常驻巡守领取区域线索，不重付任何奖励")

func _expected_path() -> String:
	return GameState.SAVE_PATH + ".outpost_expected"

func _write_chapter_expected() -> void:
	_write_expected({"ledger": _q().duplicate(true), "wallet": _wallet(),
		"checkpoints": GameState.discovered_checkpoints.duplicate(),
		"destroyed": ObstacleField.destroyed_list(), "patrol_text": _patrol_text})

func _assert_cold_expected(label: String) -> void:
	var expected := _expected()
	_patrol_text = str(expected.get("patrol_text", ""))
	_check(_same(_q(), expected["ledger"]), label + "：完整章节证据/里程碑支付记录冷恢复")
	_check(_same(_wallet(), expected["wallet"]), label + "：金币/经验/普通库存冷恢复")
	_check(_same(GameState.discovered_checkpoints, expected["checkpoints"]), label + "：检查点冷恢复")
	_check(_same(ObstacleField.destroyed_list(), expected["destroyed"]), label + "：真实路障摧毁覆盖层冷恢复")

func _death_preserves_chapter() -> void:
	var before := _q().duplicate(true)
	_player._hurt_iframes = 0.0
	_player.take_damage(1000000.0, Vector2.INF)
	_check(_player._is_dead and _chapter_equal(before), "真实死亡不回滚独有物资、救援/修复或已付收据")

func _claim_restoration() -> void:
	if not await _walk_prop("signpost", Vector2(0, 64)): return
	var wallet := _wallet()
	await _interact("signpost")
	_check(_wallet() == wallet and not _q()["receipts"]["restoration"]["paid"], "冷恢复后仍不部分支付满99的最终奖励")
	GameState.remove_item("onigiri", 1)
	wallet = _wallet()
	await _interact("signpost")
	_assert_reward_delta(wallet, 24, 24, "修复尾款")
	_check(_q()["receipts"]["restoration"]["paid"] and _q()["stage"] == "completed"
		and GameState.count_item("onigiri") == 99, "腾出一格后在路标明确领取完整尾款且只补一件普通物品")
	wallet = _wallet()
	await _interact("signpost")
	_qm.outpost_action("signpost")
	_check(_wallet() == wallet, "再次交互/重复回调不能重复支付终段奖励")
	await _next_clue_contract()

func _cold(phase: String) -> void:
	await _mount(phase in ["--cold-clue", "--cold-depleted-write", "--cold-embedded-write"])
	match phase:
		"--cold-embedded-write":
			_check(_save(), "既有真实个体存档供新增墙体兼容性冷回归")
			_write_expected({})
			_record_embedded_candidates()
		"--cold-depleted-write":
			await _deplete_local()
			_check(_q().is_empty(), "耗尽旧世界夹具未凭空建立章节或进度")
			_check(_save(), "完全耗尽的真实生态快照写盘，供独立旧档冷恢复")
			_write_chapter_expected()
		"--cold-depleted-finish":
			_assert_cold_expected("耗尽v12旧世界")
			var population := _world_population()
			if not await _accept_chapter(): return
			if not await _first_clue() or not await _enter_and_recover() or not await _ecology(true): return
			if not await _repair(): return
			_check(_q().get("stage", "") == "completed" and _world_population() == population,
				"真正旧版耗尽存档冷加载也能完成全部调查/回收/救援/修复，不生成生物")
			_check(_save(), "耗尽旧档完成的新章节与世界变化真实写盘")
		"--cold-clue":
			if not await _accept_chapter(): return
			await _action_failures()
			if not await _first_clue(): return
			_check(not _q()["receipts"]["investigation"]["paid"], "只有第一条线索时调查里程碑仍未支付")
			_check(_save(), "第一条线索、奖励前状态真实写盘")
			_write_chapter_expected()
		"--cold-recovery":
			_assert_cold_expected("奖励前")
			GameState.inventory = {"onigiri": 99, "water-pot": 99, "fish": 99, "tea-leaf": 99}
			if not await _enter_and_recover(false): return
			_check(_q()["receipts"]["investigation"]["paid"] and not _q()["receipts"]["rescue"]["paid"],
				"第二条真实线索已付首段，但未救援不能支付第二段")
			await _death_preserves_chapter()
			_check(_save(), "独有药包与真实死亡窗口写盘")
			_write_chapter_expected()
		"--cold-rescue":
			_assert_cold_expected("药包与首段奖励后")
			_check(not _player._is_dead and not GameState.discovered_checkpoints.has("outpost:lost_watch"), "死亡冷启复活，但前哨修复前仍未解锁")
			var before := _q().duplicate(true)
			_qm.abandon("lost_outpost_v1")
			_check(not _q().get("active", true) and _q()["evidence"] == before["evidence"], "放弃只暂停章节，不抹掉独有药包证据")
			if not await _accept_chapter(): return
			_check(_q()["evidence"] == before["evidence"] and _q()["receipts"] == before["receipts"], "重新接取恢复证据及支付收据，不能再拿药包或首段钱")
			if not await _walk_prop("aid_bag", Vector2(0, 56)): return
			var unique_wallet := _wallet()
			await _interact("aid_bag")
			_check(_q()["evidence"] == before["evidence"] and _q()["receipts"] == before["receipts"]
				and _wallet() == unique_wallet and _prop("aid_bag").get("taken"), "死亡/放弃/重接/冷启后再次走到药包也不能重复领取")
			if not await _take_tools_and_aid(): return
			if not await _ecology(): return
			_check(_q()["receipts"]["rescue"]["paid"] and not _evidence("signpost_repaired"), "救援奖励后仍保留明确修复阶段")
			_check(_save(), "救援/真实生态完成、修复前状态写盘")
			_write_chapter_expected()
		"--cold-repair":
			_assert_cold_expected("修复前")
			if not await _repair(true): return
			_check(_save(), "已修复世界与库存99待付终段原子写盘")
			_write_chapter_expected()
		"--cold-claim":
			_assert_cold_expected("修复后待领奖")
			_check(_prop("signpost").get("repaired") and _prop("wounded_patrol").get("rescued"), "冷启动真实场景重建已修复路标与获救巡守")
			await _claim_restoration()
			_check(_save(), "最终已付收据与检查点真实写盘")
			_write_chapter_expected()
		"--cold-paid":
			_assert_cold_expected("最终支付后")
			var wallet := _wallet()
			_qm.outpost_action("signpost")
			_qm.abandon("lost_outpost_v1")
			_qm.accept({"id": "lost_outpost_v1"})
			_check(_wallet() == wallet and _q()["stage"] == "completed", "冷加载后重复修复/领取/放弃重接均不能复付或重开章节")
			await _death_preserves_chapter()
			_player._respawn()
			var layout: Script = load("res://scripts/ecology/outpost_layout.gd")
			_check(_player.global_position.distance_to(layout.checkpoint_position()) <= 80.0, "修复后的前哨真正成为最近死亡复活检查点")
			_check(_prop("wounded_patrol").get("rescued") and _prop("signpost").get("repaired"), "死亡复活后实际NPC/路标状态不回退")
			_record_embedded_candidates()
		"--cold-legacy-paid", "--cold-legacy-pending", "--cold-legacy-progress":
			await _legacy_chapter(phase.trim_prefix("--cold-legacy-"))
		"--cold-embedded-actor":
			await _embedded_actor()
		"--cold-invalid-id", "--cold-invalid-chain":
			if phase == "--cold-invalid-id":
				_check(_q().is_empty(), "冷读取不同稳定ID时拒绝转移其它章节的证据/收据")
			else:
				_check(not _evidence("rescued") and not _evidence("signpost_repaired"), "冷读取前置证据破损时不能保留伪造救援/修复")
			_check(not GameState.discovered_checkpoints.has("outpost:lost_watch"), "坏ID或缺失前置证据的存档不能夹带已启用前哨检查点")
			_check(not _prop("signpost").get("repaired") and not _prop("wounded_patrol").get("rescued"), "坏档不会把实际NPC或路标装配成完成状态")
		_:
			_check(false, "未知完整章节冷进程模式：" + phase)
	await _unmount()

func _legacy_chapter(mode: String) -> void:
	var expected := _expected()
	_check(_same(GameState.camp_quest, expected["camp_quest"]), "旧紧凑任务完整保留目标/贡献/承诺/已付收据：" + mode)
	_check(GameState.gold == int(expected["gold"]) and _same(GameState.inventory, expected["inventory"])
		and GameState.world_seed == int(expected["world_seed"]), "旧档迁移不重置世界或更改钱包：" + mode)
	_check(not GameState.discovered_checkpoints.has("outpost:lost_watch"), "旧地图全部已探索也不能绕过路标修复解锁检查点")
	var old := GameState.camp_quest.duplicate(true)
	var wallet := _wallet()
	if not await _accept_chapter(): return
	_check(_q().get("legacy_reserved", false) and not _evidence("patrol_read") and not _evidence("rescued"),
		"旧任务保留完整奖励，新剧情仍从具名调查与救援开始")
	if not await _first_clue(): return
	if not await _enter_and_recover(): return
	_check(_same(GameState.camp_quest, old) and _wallet() == wallet, "新调查/救援不重付旧任务奖励，也不改写原支付收据")
	if mode == "progress":
		_check(_q().get("stage", "") == "ecology" and _q().get("outcome", "") == "", "旧版进行中没有完成生态的证据，不能自动跨过生态段")
	else:
		_check(_q().get("stage", "") == "repair" and _q().get("kills", []).is_empty()
			and _q().get("ransacks", []).is_empty(), "旧版已完成生态直接保留历史，不要求重复猎杀/捣巢：" + mode)
		if not await _repair(): return
		_check(_wallet() == wallet and _same(GameState.camp_quest, old), "完整新剧情不重付旧奖励或吞待领奖收据：" + mode)

func _record_embedded_candidates() -> void:
	var layout: Script = load("res://scripts/ecology/outpost_layout.gd")
	var center: Vector2 = layout.center()
	var region: SimRegion = WorldSim.sim.region_of_point(center)
	var ids: Array = []
	for inst: MonsterInstance in WorldSim.sim.instances.values():
		if inst.is_alive and inst.region_id == region.id and not inst.species.is_boss:
			ids.append(inst.id)
			if ids.size() == 2: break
	_check(ids.size() == 2, "旧存档嵌墙回归有两只真实既有实例可复用")
	var expected := _expected()
	var outside := ObstacleField.nudge_free(center + Vector2(-1056, 0), 18.0)
	expected["embedded"] = {"ids": ids, "wall": [center.x + 96.0, center.y],
		"outside": [outside.x, outside.y], "player": [center.x - 160.0, center.y + 160.0]}
	_write_expected(expected)

func _embedded_actor() -> void:
	var expected: Dictionary = _expected()["embedded"]
	var ids: Array = expected["ids"]
	var wall := Vector2(expected["wall"][0], expected["wall"][1])
	var outside := Vector2(expected["outside"][0], expected["outside"][1])
	_world._stream_pass()
	await _frames(6)
	_freeze_monsters()
	var inside_inst: MonsterInstance = WorldSim.sim.instances.get(int(ids[0]))
	var outside_inst: MonsterInstance = WorldSim.sim.instances.get(int(ids[1]))
	var inside_body: MonsterBase = _world._nodes.get(int(ids[0]))
	var outside_body: MonsterBase = _world._nodes.get(int(ids[1]))
	_check(inside_inst != null and inside_inst.is_alive and inside_body != null, "旧版嵌入新墙的真实ID仍存活并装配演员")
	if inside_inst != null and inside_body != null:
		_check(inside_inst.spawn_pos == wall and is_equal_approx(inside_inst.hp_mirror, 7.25)
			and inside_body.inst == inside_inst, "脱墙不改变模拟身份、血量镜像或原有据点锚点")
		print("EMBEDDED_INSIDE ", {"body": inside_body.global_position, "actor_anchor": inside_body.anchor, "sim_spawn": inside_inst.spawn_pos, "hp": inside_inst.hp_mirror, "blocked": ObstacleField.blocks(inside_body.global_position, 12.0)})
		_check(not ObstacleField.blocks(inside_body.global_position, 12.0)
			and inside_body.global_position.distance_to(wall) < 160.0, "嵌墙演员只在作者地块小范围安全落位")
	_check(outside_inst != null and outside_body != null, "同档作者地块外的对照实例正常装配")
	if outside_inst != null and outside_body != null:
		print("EMBEDDED_OUTSIDE ", {"body": outside_body.global_position, "actor_anchor": outside_body.anchor, "sim_spawn": outside_inst.spawn_pos, "expected": outside, "hp": outside_inst.hp_mirror})
		# 925696c 已有每轴±26px的演员出生抖动；巡逻锚点和模拟锚点必须严格不变。
		_check(outside_inst.spawn_pos == outside and outside_body.anchor == outside
			and outside_body.inst == outside_inst and outside_body.global_position.distance_to(outside) <= Vector2(26, 26).length() + 0.1
			and is_equal_approx(outside_inst.hp_mirror, 9.25), "作者地块外实例不被章节迁移移动、治疗或重造")
	_check(not GameState.discovered_checkpoints.has("outpost:lost_watch"), "满探索旧档即使玩家站在前哨也不提前解锁未修复检查点")

func _natural_supply_contract() -> void:
	await _mount(true)
	var selector := CampQuestTargets.new()
	_world.add_child(selector)
	for ticks: int in [600, 300]:
		for _tick in ticks: WorldSim.sim.tick()
		_world._stream_pass()
		await _frames(4)
		_freeze_monsters()
		var before := _world_population()
		var result: Dictionary = await selector.select_target()
		_check(_world_population() == before, "真实%d刻后目标核查不改变存量或密度" % WorldSim.sim.tick_count)
		if not result.is_empty():
			_check(selector.current_stock_ids(result).size() >= 3 and WorldSim.sim.nests[result["key"]]["active"],
				"真实%d刻候选仍有足量活体与活动巢，不伪报可行" % WorldSim.sim.tick_count)
		else:
			_check(_qm.offer("camp_ecology", "outpost", "营地巡守").get("kind", "") == "quest",
				"真实%d刻耗尽也能开始作者剧情，不因缺怪阻塞调查救援" % WorldSim.sim.tick_count)
		print("OUTPOST_SUPPLY ", JSON.stringify({"tick": WorldSim.sim.tick_count, "target": result}))
	selector.queue_free()
	await _unmount()

func _run() -> void:
	# 仅缩短自动化墙钟时间，仍走原速度/原碰撞/原攻击间隔；真实节奏另测。
	Engine.time_scale = 4.0
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		if OS.get_environment("HOTW_TEST_SAVE").is_empty():
			_check(false, "冷进程需要明确隔离存档路径")
		else:
			await _cold(args[0])
		await _finish()
		return
	GameState.SAVE_PATH = "user://outpost_chapter_contract_%d.json" % OS.get_process_id()
	await _mount(true)
	if await _accept_chapter():
		await _action_failures()
		if await _first_clue() and await _enter_and_recover(true, true) and await _ecology():
			await _repair()
	await _unmount()
	await _mount(true)
	await _deplete_local()
	var depleted_before := _world_population()
	GameState.inventory = {"onigiri": 99, "water-pot": 99, "fish": 99, "tea-leaf": 99}
	if await _accept_chapter():
		if await _first_clue() and await _enter_and_recover() and await _ecology(true):
			if await _repair(true):
				await _claim_restoration()
	_check(_world_population() == depleted_before, "整个耗尽版本章节完成不补怪、不清生态、不提升密度")
	await _unmount()
	await _natural_supply_contract()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.SAVE_PATH))
	await _finish()
