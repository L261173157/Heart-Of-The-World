## 真实屏幕尺寸和触屏/鼠标双事件：滚动裁剪不可抢关闭键，阅读与战斗手势仍隔离。
extends Node2D

const FIXED := ["AttackBtn", "ShieldBtn", "DashBtn", "ShortcutBtn", "QuickSlotBtn", "MoreBtn"]
var _hud: CanvasLayer
var _player: Player
var _checks := 0
var _fails := 0
var _uses := 0
var _casts := 0
var _confirmations := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.save_enabled = false
	GameState.reset_all()
	WorldSim.stop()
	TouchInput.reset()
	_run.call_deferred()

func _run() -> void:
	_hud = preload("res://scenes/ui/hud.tscn").instantiate()
	add_child(_hud)
	_player = preload("res://scenes/player/player.tscn").instantiate()
	_player.position = WorldConfig.spawn_pos()
	add_child(_player)
	EventBus.item_use_requested.connect(func(_id: String) -> void: _uses += 1)
	EventBus.dialogue_confirmed.connect(func(_quest: Dictionary) -> void: _confirmations += 1)
	for name_: String in ["AttackBtn", "DashBtn", "HeavyBtn", "BoltBtn", "HealBtn", "EmpowerBtn", "ShortcutBtn"]:
		_button(name_).button_down.connect(func() -> void: _casts += 1)
	for canvas: Vector2i in [Vector2i(1280, 720), Vector2i(1560, 720), Vector2i(1024, 640)]:
		get_tree().root.size = canvas
		get_tree().root.content_scale_size = canvas
		get_tree().root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		get_tree().root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
		await _settle()
		_check(get_viewport().get_visible_rect().size == Vector2(canvas), "真实视口 " + str(canvas))
		await _test_more(canvas)
		await _test_reading(canvas)
	await _test_nested_clip()
	_hud.queue_free()
	_player.queue_free()
	await _settle()
	TouchInput.reset()
	get_tree().paused = false
	if _fails == 0:
		print("=== MOBILE CLIPPING PASS (%d checks) ===" % _checks)
	else:
		print("=== MOBILE CLIPPING FAIL (%d checks, %d failures) ===" % [_checks, _fails])
	get_tree().quit(0 if _fails == 0 else 1)

func _check(ok: bool, label: String) -> void:
	_checks += 1
	print("  %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_fails += 1

func _button(name_: String) -> Button:
	return _hud.get_node("Root").find_child(name_, true, false) as Button

func _center(control: Control) -> Vector2:
	return control.get_global_transform_with_canvas() * (control.size * 0.5)

func _settle() -> void:
	for i in 3:
		await get_tree().physics_frame
		await get_tree().process_frame

func _touch(point: Vector2, down: bool, index := 7, canceled := false, emulate := true) -> void:
	var at := get_viewport().get_screen_transform() * point
	var touch := InputEventScreenTouch.new()
	touch.index = index
	touch.position = at
	touch.pressed = down
	touch.canceled = canceled
	Input.parse_input_event(touch)
	# 注入的原始触屏不会自动产生平台模拟鼠标，补齐真实设备的配对事件。
	if emulate:
		var mouse := InputEventMouseButton.new()
		mouse.device = InputEvent.DEVICE_ID_EMULATION
		mouse.position = at
		mouse.button_index = MOUSE_BUTTON_LEFT
		mouse.pressed = down
		Input.parse_input_event(mouse)

func _tap_at(point: Vector2) -> void:
	_touch(point, true)
	await _settle()
	_touch(point, false)
	await _settle()

func _tap(control: Control) -> void:
	await _tap_at(_center(control))

func _drag(point: Vector2, index := 7) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = get_viewport().get_screen_transform() * point
	Input.parse_input_event(event)

func _test_more(canvas: Vector2i) -> void:
	GameState.inventory.clear()
	for id: String in ItemCatalog.ids_of_kind("consumable"):
		GameState.inventory[id] = 3
	GameState.set_setting("mobile_shortcut", "bolt")
	GameState.set_setting("mobile_recovery", "heal")
	_player.current_hp = 30
	_player.current_mp = 20
	_player._push_hud()
	EventBus.inventory_changed.emit()
	var inventory_before := GameState.inventory.duplicate(true)
	var uses_before := _uses
	var casts_before := _casts
	await _tap(_button("MoreBtn"))
	_check(_hud._more_panel.visible and not get_tree().paused, "更多保持世界运行 " + str(canvas))
	await _tap(_button("MoreTab_shortcut"))
	await _tap(_button("ShortcutPreset_heavy"))
	await _tap(_button("MoreTab_recovery"))
	await _tap(_button("RecoveryPreset_onigiri"))
	_check(GameState.settings.mobile_shortcut == "heavy" and GameState.settings.mobile_recovery == "item:onigiri", "可见行真实触控选定两项预设")
	var close := _button("MoreClose")
	var scroll := _hud._more_items.get_parent() as ScrollContainer
	var hidden := _button("RecoveryPreset_life-pot")
	_check(hidden.get_global_rect().has_point(_center(close)) and not scroll.get_global_rect().has_point(_center(close)), "隐藏恢复行的未裁剪矩形确实覆盖关闭键")
	print("CLIP_REPRO canvas=", canvas, " close=", _center(close), " hidden=", hidden.get_global_rect(), " clip=", scroll.get_global_rect())
	await _tap(close)
	_check(not _hud._more_panel.visible, "实际关闭键一次触控关闭更多")
	_check(GameState.settings.mobile_shortcut == "heavy" and GameState.settings.mobile_recovery == "item:onigiri", "关闭不会被隐藏行改成生命药剂")
	_check(_uses == uses_before and _casts == casts_before and GameState.inventory == inventory_before, "预设和关闭均不消耗物品或施放技能")
	_hud._more_panel.hide()
	await _tap(_button("MoreBtn"))
	close = _button("MoreClose")
	hidden = _button("QuickItem_water-pot")
	var hidden_overlap := false
	for row: Node in _hud._more_items.get_children():
		if row is Button and row.get_global_rect().has_point(_center(close)):
			hidden_overlap = true
	_check(hidden_overlap, "真实物品页同样有裁剪行覆盖关闭坐标")
	await _tap(close)
	_check(not _hud._more_panel.visible and _uses == uses_before and GameState.inventory == inventory_before, "关闭物品页不误用隐藏补给")
	_hud._more_panel.hide()
	await _tap(_button("MoreBtn"))
	hidden = _button("QuickItem_water-pot")
	scroll.ensure_control_visible(hidden)
	await _settle()
	_check(scroll.get_global_rect().has_point(_center(hidden)), "滚入的物品行真实可见")
	await _tap(hidden)
	_check(GameState.count_item("water-pot") == 2 and _uses == uses_before + 1, "可见补给行只实际使用一次")
	await _tap(_button("MoreBtn"))
	for name_: String in FIXED:
		_check(_button(name_).is_visible_in_tree(), "仍保留常驻键 " + name_)

func _test_reading(canvas: Vector2i) -> void:
	var opening := Vector2(400, 180)
	_touch(opening, true, 91, false, false)
	TouchInput.queue_attack()
	TouchInput.queue_heal()
	_hud._open_dialogue({"kind": "quest", "giver": "巡守", "text": "确认需新手势", "quest": {"id": "clip-fresh"}})
	await _settle()
	_check(get_tree().paused and not TouchInput.consume_attack() and not TouchInput.consume_heal(), "阅读暂停并清战斗输入 " + str(canvas))
	var count_before := _confirmations
	await _tap(_hud._dialogue_yes)
	_check(_confirmations == count_before and _hud._dialogue_panel.visible, "旧手指未抬起时新指不能确认")
	_touch(opening, false, 91, false, false)
	await _settle()
	_check(_confirmations == count_before, "旧手势释放不自动确认")
	await _tap(_hud._dialogue_yes)
	_check(_confirmations == count_before + 1 and not get_tree().paused, "释放后的全新触控仅确认一次并恢复世界")
	# 真实战斗按钮仍必须在重置时释放本地捕获，不能把旧抬起补成点击。
	var more := _button("MoreBtn")
	_touch(_center(more), true, 72, false, false)
	await _settle()
	TouchInput.reset()
	_touch(_center(more), false, 72, false, false)
	await _settle()
	_check(not _hud._more_panel.visible and more.get("_touch_index") == -1, "重置后的旧抬起不会展开更多")

func _test_nested_clip() -> void:
	# 用旋转/缩放的两层裁剪验证祖先有效范围；中间普通容器不能中断检查。
	_hud.get_node("Root").hide()
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var outer := Control.new()
	outer.position = Vector2(100, 100)
	outer.size = Vector2(180, 80)
	outer.scale = Vector2(1.25, 1.25)
	outer.rotation = 0.08
	outer.clip_contents = true
	canvas.add_child(outer)
	var middle := Control.new()
	middle.size = Vector2(180, 180)
	outer.add_child(middle)
	var row := Button.new()
	row.set_script(preload("res://scripts/ui/reading_action_button.gd"))
	row.position = Vector2(10, 50)
	row.size = Vector2(150, 80)
	middle.add_child(row)
	var activated := [0]
	row.pressed.connect(func() -> void: activated[0] += 1)
	get_tree().paused = true
	await _settle()
	var visible_point := row.get_global_transform_with_canvas() * Vector2(50, 10)
	var clipped_point := row.get_global_transform_with_canvas() * Vector2(50, 60)
	await _tap_at(clipped_point)
	_check(activated[0] == 0 and row.get("_touch_index") == -1, "暂停阅读行被非直属祖先裁剪时不能捕获")
	await _tap_at(visible_point)
	_check(activated[0] == 1, "暂停阅读行可见片段仍正常提交")
	_touch(visible_point, true, 7, false, false)
	_drag(clipped_point)
	_touch(clipped_point, false, 7, false, false)
	await _settle()
	_check(activated[0] == 1 and row.get("_touch_index") == -1, "从可见片段拖到祖先裁剪外只释放不提交")
	_touch(visible_point, true, 7, false, false)
	_touch(visible_point, false, 7, true, false)
	await _settle()
	_check(activated[0] == 1 and row.get("_touch_index") == -1, "系统取消仍不提交")
	# 未解锁的新手势门禁也不能用不可见行吞掉其它控件的原生鼠标事件。
	var close := Button.new()
	close.position = clipped_point - Vector2(20, 12)
	close.size = Vector2(40, 24)
	canvas.add_child(close)
	var closed := [0]
	close.pressed.connect(func() -> void: closed[0] += 1)
	row.set("input_allowed", func() -> bool: return false)
	await _tap_at(clipped_point)
	_check(closed[0] == 1 and activated[0] == 1, "门禁未解锁的裁剪行也不吞其它按钮的点击")
	close.queue_free()
	row.set("input_allowed", Callable())
	await _settle()
	for down: bool in [true, false]:
		var mouse := InputEventMouseButton.new()
		mouse.button_index = MOUSE_BUTTON_LEFT
		mouse.position = visible_point
		mouse.pressed = down
		get_viewport().push_input(mouse, true)
		await _settle()
	_check(activated[0] == 2, "原生鼠标仍可选择可见片段且只提交一次")
	row.grab_focus()
	for down: bool in [true, false]:
		var key := InputEventKey.new()
		key.keycode = KEY_ENTER
		key.physical_keycode = KEY_ENTER
		key.pressed = down
		get_viewport().push_input(key, true)
		await _settle()
	_check(activated[0] == 3, "原生键盘确认仍只提交一次")
	get_tree().paused = false
	canvas.queue_free()
	await _settle()
	_hud.get_node("Root").show()
