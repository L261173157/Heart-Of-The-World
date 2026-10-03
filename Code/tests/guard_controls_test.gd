## 持盾控件端到端：真实F/触屏/鼠标、多指、取消与全部场景生命周期。
extends Node2D

var _checks := 0
var _fails := 0
var _hud: CanvasLayer
var _player: Player
var _origin := Vector2.ZERO
var _attack_id := 200000
var _counter_starts := 0
var _last_guard := "idle"
var _next_finger := 40

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.save_enabled = false
	GameState.ecology_snapshot = null
	GameState.reset_all()
	GameState.settings.auto_aim = false
	GameState.settings.screen_shake = false
	WorldSim.stop()
	TouchInput.reset()
	_origin = WorldConfig.spawn_pos()
	_hud = preload("res://scenes/ui/hud.tscn").instantiate()
	add_child(_hud)
	_player = preload("res://scenes/player/player.tscn").instantiate()
	add_child(_player)
	_player.set_process(false)
	EventBus.player_guard_changed.connect(_on_guard)
	_run.call_deferred()

func _on_guard(state: String, _charge: int, _strength: float, _break_time: float) -> void:
	if state == "counter" and _last_guard != "counter":
		_counter_starts += 1
	_last_guard = state

func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])

func _frames(count := 1) -> void:
	for _i in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func _button(name: String) -> Button:
	return _hud.get_node("Root/" + name)

func _center(name := "ShieldBtn") -> Vector2:
	return _button(name).get_global_rect().get_center()

func _touch(index: int, point: Vector2, pressed: bool, canceled := false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = get_viewport().get_screen_transform() * point
	event.pressed = pressed
	event.canceled = canceled
	Input.parse_input_event(event)

func _drag(index: int, point: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = get_viewport().get_screen_transform() * point
	Input.parse_input_event(event)

func _key(code: Key, pressed: bool, echo := false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	event.echo = echo
	Input.parse_input_event(event)

func _tap_key(code: Key) -> void:
	_key(code, true)
	await _frames(2)
	_key(code, false)
	await _frames(2)

func _mouse(point: Vector2, pressed: bool, emulated := false) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.device = InputEvent.DEVICE_ID_EMULATION if emulated else 0
	get_viewport().push_input(event, true)

func _charge(strength := 10.0) -> void:
	_attack_id += 1
	_player.take_damage(strength, _player.global_position + Vector2(80, 0), "控件测试",
		{"strength": strength, "blockable": true, "incoming_direction": Vector2.RIGHT, "attack_id": _attack_id})

func _reset() -> void:
	get_tree().paused = false
	_key(KEY_F, false)
	TouchInput.reset()
	_player.teleport_to(_origin)
	_player.current_hp = 1000.0
	_player.current_mp = 1000.0
	_player._protect_timer = 0.0
	_player._hurt_iframes = 0.0
	_player._attack_cooldown = 0.0
	_player.facing = Vector2.RIGHT
	await _frames(3)

func _hold() -> int:
	_next_finger += 1
	_touch(_next_finger, _center(), true)
	await _frames(8)
	_check(_player.guard_state == "guarding" and TouchInput.guard_held
		and _button("ShieldBtn").get("_touch_index") == _next_finger, "真实盾钮手指持有进入防御")
	return _next_finger

func _assert_canceled(before: int, label: String) -> void:
	await _frames(25)
	_check(_counter_starts == before and _player.guard_charge == 0
		and _player.guard_state == "idle" and not TouchInput.guard_held
		and not _player._weapon_visual.active and not TouchInput.consume_guard_release(),
		label + " [state=%s charge=%s held=%s counter=%s/%s weapon=%s]" % [_player.guard_state, _player.guard_charge, TouchInput.guard_held, _counter_starts, before, _player._weapon_visual.active])

func _run() -> void:
	await _frames(3)
	await _layout()
	await _key_and_touch()
	await _multitouch_and_dedup()
	await _drag_and_system_cancel()
	await _disabled_hidden()
	await _keyboard_availability()
	await _pause_modal_dialogue()
	await _focus_background()
	await _break_recovery()
	await _transitions()
	_key(KEY_F, false)
	TouchInput.reset()
	_hud.queue_free()
	_player.queue_free()
	await _frames(30)
	WorldSim.stop()
	get_tree().paused = false
	print("=== GUARD CONTROLS %s (%d checks) ===" % ["PASS" if _fails == 0 else "FAIL", _checks])
	get_tree().quit(0 if _fails == 0 else 1)

func _layout() -> void:
	var root: Control = _hud.get_node("Root")
	var names := ["AttackBtn", "DashBtn", "HeavyBtn", "BoltBtn", "HealBtn", "EmpowerBtn", "QuickSlotBtn", "ReturnTownBtn"]
	for canvas: Vector2 in [Vector2(1280, 720), Vector2(1560, 720), Vector2(1280, 960), Vector2(1160, 680)]:
		root.set_anchors_preset(Control.PRESET_TOP_LEFT)
		root.position = Vector2(40, 20)
		root.size = canvas
		await _frames(2)
		var shield := _button("ShieldBtn")
		_check(root.get_global_rect().encloses(shield.get_global_rect()) and shield.size.x >= 80 and shield.size.y >= 80,
			"盾钮安全区及最小触控面积%s" % canvas)
		for name: String in names:
			_check(not shield.get_global_rect().grow(4).intersects(_button(name).get_global_rect().grow(4)),
				"盾钮与%s至少8px间隔%s" % [name, canvas])
		EventBus.npc_dialogue.emit({"kind": "quest", "giver": "营地猎人", "text": "测试架盾不穿透对话", "quest": {"id": "guard_layout"}})
		await _frames(2)
		_check(not shield.get_global_rect().intersects(_hud._dialogue_panel.get_global_rect()), "盾钮不遮挡对话%s" % canvas)
		EventBus.dialogue_action.emit("cancel")
	root.position = Vector2.ZERO
	root.size = Vector2(1280, 720)
	await _frames(2)

func _key_and_touch() -> void:
	await _reset()
	var mapped := false
	for event in InputMap.action_get_events("guard"):
		if event is InputEventKey and (event.keycode == KEY_F or event.physical_keycode == KEY_F):
			mapped = true
	_check(mapped, "正式InputMap将F绑定到guard")
	_key(KEY_F, true)
	await _frames()
	_check(_player.guard_state == "raising", "真实F键先举盾")
	await _frames(8)
	_check(_player.guard_state == "guarding", "真实F持续输入完成防御")
	_charge()
	var counters := _counter_starts
	_key(KEY_F, true, true)
	await _frames(2)
	_check(_player.guard_charge == 1 and _counter_starts == counters, "键盘长按自动重复不重启或反击")
	_key(KEY_F, false)
	await _frames(2)
	_check(_counter_starts == counters + 1 and _player.guard_state == "counter", "真实F松手恰好反击一次")
	await _frames(25)
	await _reset()
	var finger := await _hold()
	_charge()
	_check(_hud.get("_guard_charge") == 1 and _button("ShieldBtn").get("_guard_charge") == 1,
		"真实格挡事件同步HUD和盾钮蓄力")
	counters = _counter_starts
	_touch(finger, _center(), false)
	await _frames(2)
	_check(_counter_starts == counters + 1 and _player.guard_state == "counter", "正常盾钮内松手与F反击一致")
	_touch(finger, _center(), false)
	await _frames(25)
	_check(_counter_starts == counters + 1, "重复释放不重复反击")
	await _reset()
	finger = await _hold()
	counters = _counter_starts
	_touch(finger, _center(), false)
	await _assert_canceled(counters, "零层正常松手仅放下盾不出刀")

func _multitouch_and_dedup() -> void:
	await _reset()
	_touch(1, Vector2(160, 560), true)
	_drag(1, Vector2(205, 560))
	var start := _player.position
	var finger := await _hold()
	_check(TouchInput.joystick_active and _player.position.x > start.x, "同时左手摇杆和右手持盾继续移动")
	_charge()
	var counters := _counter_starts
	_touch(2, _center(), false)
	_touch(3, _center(), true, true)
	await _frames(2)
	_check(_player.guard_state == "guarding" and _player.guard_charge == 1
		and _button("ShieldBtn").get("_touch_index") == finger, "无关手指释放/系统取消不抢持盾手指")
	_mouse(_center(), true, true)
	_mouse(_center(), false, true)
	await _frames(2)
	_check(_player.guard_state == "guarding" and _counter_starts == counters
		and _button("ShieldBtn").get("_touch_index") == finger, "触摸附带合成鼠标不替换触点或提前反击")
	_touch(finger, _center(), false)
	await _frames(2)
	_check(_counter_starts == counters + 1 and TouchInput.joystick_active, "盾钮释放只反击一次且不抢摇杆")
	_touch(1, Vector2(205, 560), false)
	await _frames(25)
	await _reset()
	_mouse(_center(), true)
	await _frames(8)
	_check(_button("ShieldBtn").get("_touch_index") == -2 and _player.guard_state == "guarding", "普通鼠标仍可长按盾用于开发调试")
	_charge()
	counters = _counter_starts
	_mouse(_center(), false)
	await _frames(25)
	_check(_counter_starts == counters + 1, "普通鼠标松手恰好反击一次")
	await _reset()
	_key(KEY_F, true)
	await _frames(8)
	finger = await _hold()
	_charge()
	counters = _counter_starts
	_touch(finger, _center(), false)
	await _frames(2)
	_check(_player.guard_state == "guarding" and _counter_starts == counters, "F与触摸同时持盾时单独松触摸不提前反击")
	_key(KEY_F, false)
	await _frames(25)
	_check(_counter_starts == counters + 1, "最后一个持盾输入释放才反击一次")

func _drag_and_system_cancel() -> void:
	await _reset()
	var finger := await _hold()
	_charge()
	var counters := _counter_starts
	_drag(finger, Vector2(700, 320))
	Input.flush_buffered_events() # 合并同帧ScreenDrag前明确派发越界样本。
	_check(not TouchInput.guard_held and _button("ShieldBtn").get("_touch_index") == -1, "越界拖动实际派发后立即取消捕获")
	_drag(finger, _center())
	_touch(finger, _center(), false)
	await _assert_canceled(counters, "拖出即取消，拖回和旧松手不能补反击")
	for pressed in [false, true]:
		await _reset()
		finger = await _hold()
		_charge()
		counters = _counter_starts
		_touch(finger, _center(), pressed, true)
		_touch(finger, _center(), false)
		await _assert_canceled(counters, "系统取消pressed=%s不兑现反击" % pressed)
	await _reset()
	counters = _counter_starts
	_touch(10, Vector2(700, 320), true)
	_drag(10, _center())
	_touch(10, _center(), false)
	await _assert_canceled(counters, "空白处起触滑入盾钮不会举盾或反击")
	await _reset()
	finger = await _hold()
	_charge()
	counters = _counter_starts
	TouchInput.clear_queues()
	_touch(finger, _center(), false)
	await _assert_canceled(counters, "清普通输入队列同时取消持盾且不排队松手")

func _disabled_hidden() -> void:
	for mode in ["disabled", "hidden"]:
		await _reset()
		var finger := await _hold()
		_charge()
		var counters := _counter_starts
		if mode == "disabled":
			_button("ShieldBtn").disabled = true
		else:
			_button("ShieldBtn").hide()
		await _frames(2)
		_touch(finger, _center(), false)
		await _assert_canceled(counters, "%s控件清空持盾不补反击" % mode)
		_touch(12, _center(), true)
		await _frames(8)
		_check(_player.guard_state == "idle" and not TouchInput.guard_held, "%s控件不接新触摸" % mode)
		_button("ShieldBtn").disabled = false
		_button("ShieldBtn").show()
		_touch(12, _center(), false)
		await _frames(2)

func _keyboard_availability() -> void:
	for mode in ["shop", "hidden", "disabled"]:
		await _reset()
		_key(KEY_F, true)
		await _frames(8)
		_charge()
		var counters := _counter_starts
		if mode == "shop":
			await _tap_key(KEY_B)
			_check(_hud.shop_panel.visible and not get_tree().paused, "真实B键打开不暂停商店")
		elif mode == "hidden":
			_button("ShieldBtn").hide()
		else:
			_button("ShieldBtn").disabled = true
		_check(not TouchInput.guard_available, "%s变化当帧共享可用性立即关闭" % mode)
		if mode != "shop":
			# 在下一次UI _process之前模拟真正的攻击入口，不能多送一帧免费格挡。
			var hp := _player.current_hp
			_charge()
			_check(_player.current_hp == hp - 10.0 and _player.guard_charge == 0,
				"%s变化当帧伤害不会利用旧防御状态格挡" % mode)
		await _frames(2)
		_check(_player.guard_state == "idle" and _player.guard_charge == 0
			and _counter_starts == counters, "%s取消已持有F并清蓄力" % mode)
		_key(KEY_F, false)
		await _frames(2)
		_key(KEY_F, true)
		await _frames(8)
		_check(_player.guard_state == "idle" and _counter_starts == counters,
			"%s持续不可用期间释放后新按F也不能重新举盾" % mode)
		if mode == "shop":
			await _tap_key(KEY_B)
		elif mode == "hidden":
			_button("ShieldBtn").show()
		else:
			_button("ShieldBtn").disabled = false
		await _frames(8)
		_check(TouchInput.guard_available and _player.guard_state == "idle"
			and _counter_starts == counters, "%s恢复可用时旧F仍按住不会自动举盾" % mode)
		_key(KEY_F, false)
		await _frames(2)
		_key(KEY_F, true)
		await _frames(8)
		_check(_player.guard_state == "guarding", "%s恢复后重新松开按F立即可防御" % mode)
		_key(KEY_F, false)
		await _frames(2)

func _pause_modal_dialogue() -> void:
	for mode in ["pause", "inventory", "dialogue"]:
		await _reset()
		var finger := await _hold()
		_charge()
		var counters := _counter_starts
		if mode == "pause":
			_touch(20, _center("PauseBtn"), true)
			await _frames(2)
			_touch(20, _center("PauseBtn"), false)
		elif mode == "inventory":
			await _tap_key(KEY_O)
		else:
			EventBus.npc_dialogue.emit({"kind": "quest", "giver": "营地猎人", "text": "持盾取消测试", "quest": {"id": "guard"}})
		await _frames(2)
		_check(_player.guard_charge == 0 and not TouchInput.guard_held
			and _button("ShieldBtn").get("_touch_index") == -1, "%s进入立即取消盾触点及蓄力" % mode)
		_touch(finger, _center(), false)
		_touch(21, _center(), true)
		_touch(21, _center(), false)
		if mode == "dialogue":
			EventBus.dialogue_action.emit("cancel")
		else:
			await _tap_key(KEY_ESCAPE)
		await _assert_canceled(counters, "%s关闭后没有延迟反击" % mode)
	# 真实F在暂停过程中仍物理按住，恢复必须重新松开再按。
	await _reset()
	_key(KEY_F, true)
	await _frames(8)
	_charge()
	var counters := _counter_starts
	await _tap_key(KEY_ESCAPE)
	await _tap_key(KEY_ESCAPE)
	await _frames(10)
	_check(_player.guard_state == "idle" and _counter_starts == counters, "持F跨暂停恢复不会自动重新举盾")
	_key(KEY_F, false)
	await _frames(2)
	_key(KEY_F, true)
	await _frames(8)
	_check(_player.guard_state == "guarding", "恢复后松开再按F立即可用")
	_key(KEY_F, false)
	await _frames(2)

func _focus_background() -> void:
	for notification in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED]:
		await _reset()
		var finger := await _hold()
		_charge()
		var counters := _counter_starts
		get_tree().root.propagate_notification(notification)
		_touch(finger, _center(), false)
		await _assert_canceled(counters, "焦点/后台通知%d清持盾且旧释放不反击" % notification)
		_key(KEY_F, true)
		await _frames(8)
		_charge()
		counters = _counter_starts
		get_tree().root.propagate_notification(notification)
		await _frames(10)
		_check(_player.guard_state == "idle" and _counter_starts == counters, "焦点/后台中持续F被新按下门闩隔离")
		_key(KEY_F, false)
		await _frames(2)

func _break_recovery() -> void:
	await _reset()
	var finger := await _hold()
	_charge(40.0)
	_check(_player.guard_state == "broken", "强攻击实际破盾")
	_drag(finger, Vector2(700, 320))
	_touch(finger, _center(), false)
	await _frames(2)
	_touch(27, _center(), true)
	await _frames(8)
	_check(_player.guard_state == "broken" and _player._guard_break_timer > 0.3,
		"拖出取消与重新按住不能跳过破盾硬直")
	await _frames(32)
	_check(_player.guard_state == "idle", "硬直结束但仍按住不会自动重新举盾")
	_touch(27, _center(), false)
	await _frames(2)
	await _hold()

func _transitions() -> void:
	await _reset()
	var finger := await _hold()
	_charge()
	var counters := _counter_starts
	_player.teleport_to(_origin + Vector2(200, 0))
	_drag(finger, _center())
	_touch(finger, _center(), false)
	await _assert_canceled(counters, "传送同步清手指，旧拖动/释放不在新位置反击")
	await _reset()
	finger = await _hold()
	_charge()
	counters = _counter_starts
	_player._die()
	_touch(finger, _center(), false)
	_touch(30, _center(), true)
	await _frames(2)
	_check(_player.guard_state == "idle" and not TouchInput.guard_held, "死亡期间禁用新盾触摸")
	_player._respawn()
	_touch(30, _center(), false)
	await _assert_canceled(counters, "复活不保留死前蓄力或死亡期间触摸")
	await _reset()
	finger = await _hold()
	_charge()
	counters = _counter_starts
	_hud.queue_free()
	await _frames(2)
	_check(not TouchInput.guard_held and _player.guard_charge == 0, "HUD场景退出同步清持盾且不产生悬空节点错误")
	_check(TouchInput.guard_available, "HUD退出清理可用性提供者，独立玩家默认恢复可用")
	_key(KEY_F, true)
	await _frames(8)
	_check(_player.guard_state == "guarding", "HUD销毁后独立玩家真实F仍可架盾")
	_key(KEY_F, false)
	await _frames(2)

	_hud = preload("res://scenes/ui/hud.tscn").instantiate()
	add_child(_hud)
	await _frames(2)
	_touch(finger, _center(), false)
	await _assert_canceled(counters, "新HUD不会消费上一场景的释放手势")
	await _hold()

	await _reset()
	_key(KEY_F, true)
	await _frames(8)
	_charge()
	counters = _counter_starts
	_player.queue_free()
	await _frames(2)
	_player = preload("res://scenes/player/player.tscn").instantiate()
	add_child(_player)
	_player.set_process(false)
	await _frames(10)
	_check(_player.guard_state == "idle" and _counter_starts == counters,
		"F持续按住跨真实Player场景销毁重建必须等待新按下")
	_key(KEY_F, false)
	await _frames(2)
	_key(KEY_F, true)
	await _frames(8)
	_check(_player.guard_state == "guarding", "新Player场景松开再按F恢复防御")
	_key(KEY_F, false)
	await _frames(2)
