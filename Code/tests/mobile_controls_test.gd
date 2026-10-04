## 手机操控回归：真实多指输入 → 玩家技能/移动；暂停、后台、拖出与取消不漏释放。
extends Node2D

var _checks := 0
var _fails := 0
var _hud: CanvasLayer
var _player: Player
var _qm: QuestManager
var _return_requests := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.save_enabled = false
	GameState.reset_all()
	WorldSim.stop()
	TouchInput.reset()
	_hud = preload("res://scenes/ui/hud.tscn").instantiate()
	add_child(_hud)
	_player = preload("res://scenes/player/player.tscn").instantiate()
	_player.position = WorldConfig.spawn_pos()
	add_child(_player)
	_qm = QuestManager.new()
	add_child(_qm)
	EventBus.return_to_town_requested.connect(func() -> void: _return_requests += 1)
	await _settle()
	_test_embedded_font()
	_test_dialogue_paper()
	await _test_layout()
	await _test_multitouch_combat()
	await _test_interrupted_touches()
	await _test_canceled_joystick()
	await _test_transition_reset()
	await _test_utilities()
	await _test_quest_confirmation()
	_hud.queue_free()
	_player.queue_free()
	_qm.queue_free()
	await _settle()
	TouchInput.reset()
	get_tree().paused = false
	if _fails == 0:
		print("=== MOBILE CONTROLS PASSED (%d checks) ===" % _checks)
	get_tree().quit(0 if _fails == 0 else 1)


func _check(ok: bool, label: String) -> void:
	_checks += 1
	print("  %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_fails += 1


func _button(node_name: String) -> Button:
	return _hud.get_node("Root").find_child(node_name, true, false) as Button


func _center(node_name: String) -> Vector2:
	return _button(node_name).get_global_rect().get_center()


func _test_embedded_font() -> void:
	var font := load("res://assets/fonts/NotoSansSC-Regular.ttf") as FontFile
	_check(font != null, "直接加载内嵌字体，不依赖系统回退")
	for character: String in "回城中移动出招受击取消交付领奖进行中已完成放弃保留委托攻击强化补给":
		_check(font.has_char(character.unicode_at(0)), "内嵌字库覆盖 " + character)


func _test_dialogue_paper() -> void:
	var bubble: NinePatchRect = _hud._dialogue_panel.get_node("DialoguePaper")
	var paper := bubble.texture.get_image()
	_check(paper.get_width() <= 192 and paper.get_height() <= 192, "对话九宫切片已拼合，未误用透明图集")
	var continuous := true
	for y in range(24, paper.get_height() - 24):
		for x in range(24, paper.get_width() - 24):
			continuous = continuous and paper.get_pixel(x, y).a > 0.95
	_check(continuous, "整个正文纸面连续不透明，深墨文字有稳定对比")


func _test_layout() -> void:
	var root: Control = _hud.get_node("Root")
	var names: Array[String] = ["AttackBtn", "ShieldBtn", "DashBtn", "ShortcutBtn", "QuickSlotBtn", "MoreBtn"]
	for canvas: Vector2 in [Vector2(1280, 720), Vector2(1560, 720), Vector2(1280, 960), Vector2(1160, 680)]:
		root.set_anchors_preset(Control.PRESET_TOP_LEFT)
		root.position = Vector2(40, 20)
		root.size = canvas
		await _settle()
		for i in names.size():
			var button := _button(names[i])
			_check(root.get_global_rect().encloses(button.get_global_rect()), "%s安全区内 %s" % [names[i], canvas])
			_check(button.size.x >= 80 and button.size.y >= 80, names[i] + "保留拇指触控面积")
			for j in range(i + 1, names.size()):
				_check(not button.get_global_rect().grow(4).intersects(_button(names[j]).get_global_rect().grow(4)), names[i] + "/" + names[j] + "至少8px间隔")
		_hud._open_dialogue({"kind": "quest", "giver": "营地猎人", "text": "可接：探索地标\n奖励：金币与经验。发现尚未到访的地标，接下吗？", "quest": {"id": "layout"}})
		await _settle()
		_check(root.get_global_rect().encloses(_hud._dialogue_panel.get_global_rect()), "对话和按钮保持安全区内")
		_check(get_tree().paused and not _hud._can_use_mobile_controls(), "阅读对话暂停世界且阻止战斗触控")
		_check(not _hud._dialogue_text.get_global_rect().intersects(_hud._dialogue_yes.get_global_rect()), "对话正文不覆盖明确接取按钮")
		_hud._close_dialogue()
		_check(_button("AttackBtn").size.x > _button("ShieldBtn").size.x and _button("AttackBtn").size.x > _button("ShortcutBtn").size.x, "攻击视觉/触控层级大于盾与预设技能")
		_check(_center("ShieldBtn").x < _center("AttackBtn").x and _center("DashBtn").y < _center("AttackBtn").y,
				"盾在攻击左侧且冲刺在上方，三项高频动作独立")
		for node_name: String in ["HeavyBtn", "BoltBtn", "HealBtn", "EmpowerBtn", "ReturnTownBtn", "BtnBag", "BtnEco", "BtnCodex", "BtnShop"]:
			_check(not _button(node_name).is_visible_in_tree(), "战斗视图隐藏低频入口 " + node_name)
		for node_name: String in names:
			_check(_button(node_name).is_visible_in_tree(), "六个常驻战斗键可见 " + node_name)
		_hud._toggle_more()
		await _settle()
		_check(root.get_global_rect().encloses(_hud._more_panel.get_global_rect()) and not get_tree().paused,
				"更多展开保持安全区内且世界继续运行")
		for node_name: String in ["HeavyBtn", "BoltBtn", "HealBtn", "EmpowerBtn"]:
			var skill := _button(node_name)
			_check(skill.is_visible_in_tree() and _hud._more_panel.get_global_rect().encloses(skill.get_global_rect())
					and skill.size.x >= 80 and skill.size.y >= 80, "更多中的原技能保留足够触控面积 " + node_name)
		_hud._toggle_more()
	root.position = Vector2.ZERO
	root.size = Vector2(1280, 720)
	await _settle()


func _test_multitouch_combat() -> void:
	var start := _player.global_position
	_touch_event(0, Vector2(160, 560), true)
	_drag_event(0, Vector2(205, 560))
	_touch_event(1, _center("AttackBtn"), true)
	_touch_event(2, _center("ShortcutBtn"), true)
	await _physics(3)
	_check(TouchInput.joystick_active and _player.global_position.x > start.x, "左手移动与两根右手触点同时响应")
	_check(_player._combo == 1 and _player._bolt_cd > 0, "真实多指同时触发玩家普攻与法弹")
	_check(_player.current_mp < _player.stats.max_mp(), "法弹真实消耗精力")
	_check(not TouchInput.consume_attack() and not TouchInput.consume_bolt(), "技能队列已被真实玩家消费，无重复排队")
	_drag_event(1, Vector2(700, 320))
	_touch_event(1, Vector2(700, 320), false)
	_touch_event(2, _center("ShortcutBtn"), false)
	await _settle()
	_check(_button("AttackBtn").get("_touch_index") == -1 and _button("ShortcutBtn").get("_touch_index") == -1, "滑出和冷却禁用后释放都清触点")
	_check(TouchInput.joystick_active, "右手释放不抢走左手摇杆")
	_touch_event(0, _center("AttackBtn"), false)
	await _physics(12)
	_check(not TouchInput.joystick_active and TouchInput.move_vector == Vector2.ZERO and _player.velocity.length() < 0.1, "摇杆即使在攻击钮上释放也完整停车")
	var combo := _player._combo
	_touch_event(4, Vector2(720, 400), true)
	_drag_event(4, _center("AttackBtn"))
	_touch_event(4, _center("AttackBtn"), false)
	await _physics(2)
	_check(_player._combo == combo, "空白区起触滑入攻击不误出刀")
	_player._heavy_cd = 0
	_player._dash_cd = 0
	_player._heal_cd = 0
	_player._empower_cd = 0
	_player.current_hp = 40
	_player.current_mp = _player.stats.max_mp()
	_player._push_hud()
	await _tap("MoreBtn", 5)
	_check(_hud._more_panel.visible and not get_tree().paused, "更多技能面板保持世界运行")
	await _tap("HeavyBtn", 5)
	_check(_player._heavy_cd > 0, "真实重击触控施放")
	await _tap("DashBtn", 6)
	_check(_player._dash_cd > 0, "真实冲刺触控施放")
	await _tap("HealBtn", 7)
	_check(_player._heal_cd > 0 and _player.current_hp > 40, "冲刺中辅助区治疗真实恢复生命")
	_player.current_mp = _player.stats.max_mp()
	_player._push_hud()
	await _tap("EmpowerBtn", 8)
	_check(_player._empower_cd > 0 and _player._empower_timer > 0, "更多面板强化实际生效")
	await _tap("MoreBtn", 8)
	_check(not _hud._more_panel.visible, "再次触摸更多收起技能，不改变暂停状态")
	await _physics(20)
	_player._dash_cd = 0
	_player.current_mp = _player.stats.max_mp()
	await _key(KEY_K)
	_check(_player._dash_cd > 0, "原键盘冲刺通道继续生效")
	await _physics(20)


func _test_interrupted_touches() -> void:
	_touch_event(0, Vector2(160, 560), true)
	_drag_event(0, Vector2(205, 560))
	_touch_event(1, _center("AttackBtn"), true)
	await _physics(2)
	await _tap("PauseBtn", 3)
	_check(get_tree().paused and not TouchInput.joystick_active and TouchInput.move_vector == Vector2.ZERO, "真实暂停按钮中断双指并复位摇杆")
	_check(_button("AttackBtn").get("_touch_index") == -1, "模态进入清除仍按着的技能触点")
	_touch_event(4, _center("AttackBtn"), true)
	_touch_event(4, _center("AttackBtn"), false)
	_check(not TouchInput.consume_attack(), "模态覆盖时多点触控不穿透战斗")
	await _key(KEY_ESCAPE)
	_touch_event(1, _center("AttackBtn"), false)
	_touch_event(0, Vector2(205, 560), false)
	await _physics(15)
	_check(not get_tree().paused and _player.velocity.length() < 0.1, "恢复后旧手指释放不造成角色漂移")
	_touch_event(0, Vector2(160, 560), true)
	_drag_event(0, Vector2(205, 560))
	_touch_event(1, _center("AttackBtn"), true)
	await _physics(2)
	get_tree().root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	await _physics(12)
	_check(not TouchInput.joystick_active and _button("AttackBtn").get("_touch_index") == -1, "真实节点后台通知清摇杆与按钮捕获")
	_touch_event(9, _center("AttackBtn"), true)
	await _settle()
	_check(_button("AttackBtn").get("_touch_index") == 9, "恢复后新触点可立即重新按攻击")
	_touch_event(9, _center("AttackBtn"), false, true)
	await _settle()
	_check(_button("AttackBtn").get("_touch_index") == -1, "系统 canceled 事件不留下持有触点")
	await _physics(2)


func _test_canceled_joystick() -> void:
	var joystick: Control = _hud.get_node("Root/Joystick")
	_touch_event(11, Vector2(160, 560), true)
	_drag_event(11, Vector2(205, 560))
	await _physics(3)
	_check(TouchInput.joystick_active and joystick.get("_touch_index") == 11, "摇杆持有真实手指索引，不被合成鼠标替换")
	# 显式模拟 canceled=true、pressed=true 的独立取消帧，不能靠普通 release 蒙混通过。
	_touch_event(11, Vector2(205, 560), true, true)
	await _physics(12)
	_check(not TouchInput.joystick_active and joystick.get("_touch_index") == -1 \
			and TouchInput.move_vector == Vector2.ZERO and _player.velocity.length() < 0.1, "系统取消摇杆即使pressed仍为true也立即清触点并停车")
	_touch_event(12, Vector2(160, 560), true)
	_drag_event(12, Vector2(205, 560))
	await _physics(3)
	_check(TouchInput.joystick_active and joystick.get("_touch_index") == 12, "取消后新手指立即能重新起摇")
	_touch_event(13, Vector2(700, 400), true, true)
	await _settle()
	_check(TouchInput.joystick_active and joystick.get("_touch_index") == 12, "无关手指的取消不抢走摇杆")
	_touch_event(12, Vector2(205, 560), false)
	await _physics(12)
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.position = Vector2(160, 560)
	mouse.pressed = true
	get_viewport().push_input(mouse, true)
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(205, 560)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(motion, true)
	await _physics(3)
	_check(TouchInput.joystick_active and joystick.get("_touch_index") == -2, "普通鼠标仍能拖动摇杆调试")
	mouse = mouse.duplicate()
	mouse.position = _center("AttackBtn")
	mouse.pressed = false
	get_viewport().push_input(mouse, true)
	await _physics(12)
	_check(not TouchInput.joystick_active and _player.velocity.length() < 0.1, "普通鼠标在攻击钮上释放也停车")


func _test_transition_reset() -> void:
	var joystick: Control = _hud.get_node("Root/Joystick")
	_touch_event(21, Vector2(160, 560), true)
	_drag_event(21, Vector2(205, 560))
	_touch_event(22, _center("AttackBtn"), true)
	await _physics(3)
	var destination := _player.global_position + Vector2(256, 192)
	_player.teleport_to(destination)
	_check(joystick.get("_touch_index") == -1 and _button("AttackBtn").get("_touch_index") == -1, "真实玩家传送同步清除两根手指的局部捕获")
	_drag_event(21, Vector2(220, 560))
	_touch_event(22, _center("AttackBtn"), false)
	await _physics(12)
	_check(_player.global_position.distance_to(destination) < 0.1 and not TouchInput.joystick_active \
			and _player._combo == 0, "传送后旧拖动/旧释放不会重新激活移动或攻击")
	_touch_event(23, Vector2(160, 560), true)
	_drag_event(23, Vector2(205, 560))
	await _physics(3)
	_check(joystick.get("_touch_index") == 23 and _player.global_position.x > destination.x, "传送后新的触摸可以立即移动")
	_touch_event(23, Vector2(205, 560), false)
	await _physics(12)
	_touch_event(31, Vector2(160, 560), true)
	_drag_event(31, Vector2(205, 560))
	_touch_event(32, _center("AttackBtn"), true)
	await _physics(3)
	_player._die()
	_check(joystick.get("_touch_index") == -1 and _button("AttackBtn").get("_touch_index") == -1 \
			and not TouchInput.joystick_active, "真实死亡事件清除触点与移动向量")
	_touch_event(33, _center("AttackBtn"), true)
	_touch_event(34, Vector2(160, 560), true)
	_drag_event(34, Vector2(205, 560))
	await _physics(3)
	_player._respawn()
	var respawn_position := _player.global_position
	_drag_event(34, Vector2(220, 560))
	_touch_event(33, _center("AttackBtn"), false)
	await _physics(12)
	_check(_player.global_position.distance_to(respawn_position) < 0.1 and _player._combo == 0 \
			and joystick.get("_touch_index") == -1, "复活清除死亡期间的新手势，旧事件不带出攻击或漂移")
	# 取消局部捕获不等于用户真的松指；先结束这些物理手势，再测试新的阅读手势。
	for index in [21, 31, 34]:
		_touch_event(index, Vector2(205, 560), false)
	_touch_event(32, _center("AttackBtn"), false)
	await _physics(2)


func _test_utilities() -> void:
	GameState.inventory = {"water-pot": 2}
	GameState.set_setting("mobile_recovery", "item:water-pot")
	_player.current_hp = _player.stats.max_hp()
	_player.current_mp = 10
	_player._push_hud()
	EventBus.inventory_changed.emit()
	_touch_event(0, Vector2(160, 560), true)
	_drag_event(0, Vector2(205, 560))
	await _tap("QuickSlotBtn", 1)
	_check(GameState.count_item("water-pot") == 1 and _player.current_mp > 10 and TouchInput.joystick_active, "移动中另一指补给只消耗一次且不影响摇杆")
	_touch_event(0, Vector2(205, 560), false)
	await _tap("PauseBtn", 2)
	await _touch_control(_button("MenuRecall"))
	_check(_return_requests == 1, "菜单中的回城入口只发送一次请求并恢复世界")
	EventBus.return_to_town_progress.emit(true, 2.0, 3.0)
	await _settle()
	_check(_hud._return_panel.visible and _button("MenuRecall").text == "取消回城" \
			and is_equal_approx(_hud._return_bar.value, 1.0), "真实进度事件显示读条与取消语义")
	await _tap("PauseBtn", 3)
	await _touch_control(_button("MenuRecall"))
	_check(_return_requests == 2, "读条中再次触摸发送取消请求")
	EventBus.return_to_town_progress.emit(false, 0.0, 3.0)
	_check(not _hud._return_panel.visible and _button("MenuRecall").text == "回城", "取消/完成后清理读条")
	await _tap("PauseBtn", 4)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = _center("MenuRecall")
	click.pressed = true
	get_viewport().push_input(click, true)
	await _settle()
	click = click.duplicate()
	click.pressed = false
	get_viewport().push_input(click, true)
	await _settle()
	_check(_return_requests == 3, "普通鼠标入口仍只触发一次回城")
	await _tap("PauseBtn", 5)
	_touch_event(9, _center("MenuRecall"), true)
	await _settle()
	_check(_button("MenuRecall").get("_touch_index") == 9, "菜单回城按钮持有真实触点，以取消事件判断提交")
	_touch_event(9, _center("MenuRecall"), false, true)
	await _settle()
	_check(_return_requests == 3, "系统取消回城触点不触发请求")
	await _key(KEY_ESCAPE)


func _test_quest_confirmation() -> void:
	GameState.quests["active"] = [{"id": "touch_quest", "kind": "explore", "title": "探索地标", "need": 3, "progress": 1}]
	GameState.tracked_quest_id = "touch_quest"
	_qm._push_hud()
	await _touch_control(_hud.quest_label)
	var abandon: Button = _hud._task_rows.find_child("Abandon_touch_quest", true, false)
	await _touch_control(abandon)
	_check(GameState.quests["active"].size() == 1, "放弃第一步保留任务和进度")
	var cancel: Button = _hud._task_rows.find_child("CancelAbandon_touch_quest", true, false)
	await _reveal(cancel)
	await _touch_control(cancel)
	_check(GameState.quests["active"].size() == 1 and _hud._pending_abandon_id == "", "保留按钮取消放弃")
	abandon = _hud._task_rows.find_child("Abandon_touch_quest", true, false)
	await _reveal(abandon)
	await _touch_control(abandon)
	await _key(KEY_ESCAPE)
	_check(GameState.quests["active"].size() == 1 and _hud._pending_abandon_id == ""
			and _hud._task_layer.visible and get_tree().paused, "返回先取消待确认放弃，保留任务列表")
	await _key(KEY_ESCAPE)
	_check(not _hud._task_layer.visible and not get_tree().paused, "再返回才关闭任务列表恢复世界")
	await _touch_control(_hud.quest_label)
	abandon = _hud._task_rows.find_child("Abandon_touch_quest", true, false)
	await _touch_control(abandon)
	var confirm: Button = _hud._task_rows.find_child("ConfirmAbandon_touch_quest", true, false)
	await _reveal(confirm)
	await _touch_control(confirm)
	_hud._confirm_quest_abandon("touch_quest")
	_check(GameState.quests["active"].is_empty(), "明确二次确认放弃一次且旧回调不能再作用")
	await _key(KEY_ESCAPE)


func _touch_event(index: int, point: Vector2, down: bool, canceled := false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = get_viewport().get_screen_transform() * point
	event.pressed = down
	event.canceled = canceled
	Input.parse_input_event(event)


func _drag_event(index: int, point: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = get_viewport().get_screen_transform() * point
	Input.parse_input_event(event)


func _tap(node_name: String, index: int) -> void:
	_touch_event(index, _center(node_name), true)
	await _physics(2)
	_touch_event(index, _center(node_name), false)
	await _physics(2)


func _touch_control(control: Control) -> void:
	_touch_event(0, control.get_global_rect().get_center(), true)
	await _settle()
	_touch_event(0, control.get_global_rect().get_center(), false)
	await _settle()


func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await _physics(2)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await _physics(2)


func _reveal(control: Control) -> void:
	var parent := control.get_parent()
	while parent != null and not parent is ScrollContainer:
		parent = parent.get_parent()
	if parent is ScrollContainer:
		parent.ensure_control_visible(control)
	await _settle()


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _physics(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
	await get_tree().process_frame
