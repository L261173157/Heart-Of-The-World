## 界面视觉契约与模态回归。像素画面另由 screenshot.tscn 验证，头less锁几何/状态。
extends Node2D
var _checks := 0
var _fails := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.save_enabled = false
	GameState.reset_all()
	_run()

func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		push_error("FAIL " + label)

func _run() -> void:
	var theme := HotwTheme.glass_theme()
	var button := theme.get_stylebox("normal", "Button") as StyleBoxTexture
	_check(button.texture.get_width() <= 94, "按钮源透明留白已裁去")
	_check(button.texture_margin_top + button.texture_margin_bottom <= 24, "48px按钮留有完整中心")
	_check(theme.get_stylebox("focus", "Button") is StyleBoxFlat, "键盘焦点边框明确可见")
	for color in 5:
		var image := HotwTheme.ribbon_texture(color).get_image()
		_check(image.get_size() == Vector2i(192, 64), "三片丝带已拼合")
		for x in range(44, 149):
			_check(image.get_pixel(x, 32).a > 0.95, "丝带阅读面连续无透明断带")
	var hud := preload("res://scenes/ui/hud.tscn").instantiate()
	add_child(hud)
	await get_tree().process_frame
	await get_tree().process_frame
	var root: Control = hud.get_node("Root")
	var controls: Array[String] = ["AttackBtn", "DashBtn", "HeavyBtn", "BoltBtn", "HealBtn", "EmpowerBtn", "QuickSlotBtn", "BtnEco", "BtnBag", "BtnCodex", "BtnShop", "PauseBtn"]
	for canvas: Vector2 in [Vector2(1280, 720), Vector2(1560, 720), Vector2(1280, 960), Vector2(1160, 680)]:
		root.set_anchors_preset(Control.PRESET_TOP_LEFT)
		root.position = Vector2(40, 20)
		root.size = canvas
		await get_tree().process_frame
		for node_name: String in controls:
			var control: Control = root.get_node(node_name)
			_check(root.get_global_rect().encloses(control.get_global_rect()), "%s在安全内容区内 %s" % [node_name, canvas])
			_check(control.size.x >= 80 and control.size.y >= 80, "%s触控区至少80画布单位" % node_name)
			var icon := control.get_node_or_null("Icon") as Control
			if icon != null:
				_check(control.get_global_rect().encloses(icon.get_global_rect()), "%s图标不撑出按钮" % node_name)
	root.position = Vector2.ZERO
	root.size = Vector2(1280, 720)
	var mp: ProgressBar = hud.get_node("Root/TopLeft/MPBar")
	_check((mp.get_child(0) as Control).size.x <= 22, "蓝量标记不被64px原图撑大")
	hud._on_quest_updated("委托·捣巢：摧毁荒废遗迹旁的巢穴（0/1）")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(hud.ecology_panel.position.y >= hud._hud_plate.position.y + hud._hud_plate.size.y,
		"生态展开避开增长后的任务/状态区")
	_check(hud.ecology_label.get_parent() is ScrollContainer, "生态长列表进入有界滚动区")
	# 任意实际施放冷却（已含减冷却）都从满环开始，再按本次总时长回收。
	hud._on_skills_changed(0, 0, 0, 0, 0, 100, 100)
	hud._on_skills_changed(1.104, 3.68, 0.736, 7.36, 13.8, 100, 100)
	var mask: Control = hud.skill_cds[0]["overlay"]
	_check(is_equal_approx(float(mask.get("fraction")), 1.0), "含减冷却的施放仍从满环开始")
	hud._cd_elapsed = 0.552
	hud._refresh_skill_bar()
	_check(is_equal_approx(float(mask.get("fraction")), 0.5), "圆环按实际冷却时长回收")
	hud._on_skills_changed(0.552, 3.128, 0.184, 6.808, 13.248, 100, 100)
	_check(is_equal_approx(float(mask.get("fraction")), 0.5), "后续事件不重置本次总冷却")
	# 经真实 GUI 分发验证焦点隔离：遮罩本身不能挡住背后仍持焦的商店按钮。
	GameState.gold = 1000
	hud._toggle_shop()
	var purchase: Button = hud.shop_upgrade_btns[0]
	purchase.grab_focus()
	(hud.get_node("Root/PauseBtn") as Button).pressed.emit()
	await get_tree().process_frame
	_check(hud.pause_layer.visible and not hud.shop_panel.visible and get_tree().paused,
		"商店到暂停会先收起商店")
	_check(hud.pause_layer.is_ancestor_of(get_viewport().gui_get_focus_owner()),
		"暂停捕获原商店键盘焦点")
	await _press_key(KEY_ENTER)
	_check(GameState.gold == 1000 and GameState.upgrade_level("weapon") == 0,
		"真实 Enter 不会在暂停背后购买")
	_check(not hud.pause_layer.visible and not get_tree().paused, "真实 Enter 激活当前暂停层的恢复按钮")
	hud._toggle_pause()
	(hud.get_node("Root/PauseLayer/PausePanel/Margin/VB/PauseSettingsBtn") as Button).grab_focus()
	await _press_key(KEY_ENTER)
	_check(hud.pause_settings_layer.visible and hud.pause_settings_layer.is_ancestor_of(
		get_viewport().gui_get_focus_owner()), "真实 Enter 打开设置并把焦点交给设置")
	for step in 20:
		await _press_key(KEY_TAB)
		_check(hud.pause_settings_layer.is_ancestor_of(get_viewport().gui_get_focus_owner()),
			"设置 Tab 链不进入背后暂停按钮 %d" % step)
	(hud.get_node("Root/PauseSettingsLayer/VB/PauseSettingsClose") as Button).grab_focus()
	await _press_key(KEY_ENTER)
	_check(not hud.pause_settings_layer.visible and hud.pause_layer.visible and get_tree().paused,
		"设置关闭后仍停留暂停")
	_check(get_viewport().gui_get_focus_owner() == hud.get_node(
		"Root/PauseLayer/PausePanel/Margin/VB/PauseSettingsBtn"), "设置关闭恢复原暂停入口焦点")
	await _press_key(KEY_ESCAPE)
	_check(not hud.pause_layer.visible and not get_tree().paused, "真实 Escape 从暂停回到世界")
	hud._toggle_shop()
	purchase.grab_focus()
	await _press_key(KEY_ENTER)
	_check(GameState.gold == 950 and GameState.upgrade_level("weapon") == 1,
		"退出模态后商店原键盘购买行为恢复")
	hud._toggle_shop()
	for repeat in 3:
		hud._toggle_inventory()
		_check(hud._inv_layer.visible and get_tree().paused, "物品栏打开并暂停")
		hud._toggle_codex()
		_check(not hud.codex_layer.visible and hud._inv_layer.visible and get_tree().paused, "图鉴不能穿透物品栏")
		hud._toggle_pause()
		_check(not hud._inv_layer.visible and not get_tree().paused and not hud.pause_layer.visible, "暂停入口先关闭物品栏不留双层")
		hud._toggle_codex()
		hud._toggle_shop()
		_check(hud.codex_layer.visible and not hud.shop_panel.visible and get_tree().paused, "商店不能穿透图鉴")
		hud._close_top_layer_or_toggle_pause()
		_check(not get_tree().paused and not hud.codex_layer.visible, "图鉴返回解除暂停")
		hud._toggle_pause()
		hud._open_pause_settings()
		hud._toggle_shop()
		_check(hud.pause_settings_layer.visible and not hud.shop_panel.visible and get_tree().paused, "设置期间商店不穿层")
		hud._close_top_layer_or_toggle_pause()
		_check(hud.pause_layer.visible and get_tree().paused and not hud.pause_settings_layer.visible, "设置返回保留暂停")
		hud._close_top_layer_or_toggle_pause()
		_check(not hud.pause_layer.visible and not get_tree().paused, "暂停恢复回到世界")
	# 实际关闭回调重复交付时仍只关闭一次，并丢弃暂停期间残留的战斗排队。
	hud._toggle_inventory()
	hud._close_inventory()
	hud._close_inventory()
	_check(not hud._inv_layer.visible and not get_tree().paused, "物品栏双关闭不重开")
	hud._toggle_codex()
	var codex_close: Button = hud.get_node("Root/CodexLayer/CodexPanel/Margin/VB/CodexClose")
	codex_close.pressed.emit()
	codex_close.pressed.emit()
	_check(not hud.codex_layer.visible and not get_tree().paused, "图鉴双关闭不重开")
	hud._toggle_pause()
	var resume: Button = hud.get_node("Root/PauseLayer/PausePanel/Margin/VB/ResumeBtn")
	resume.pressed.emit()
	resume.pressed.emit()
	_check(not hud.pause_layer.visible and not get_tree().paused, "恢复双击不重开暂停")
	var echo := InputEventKey.new()
	echo.keycode = KEY_ESCAPE
	echo.physical_keycode = KEY_ESCAPE
	echo.pressed = true
	echo.echo = true
	hud._unhandled_input(echo)
	_check(not get_tree().paused, "键盘自动重复不反复打开暂停")
	hud.queue_free()
	await get_tree().process_frame
	if _fails == 0:
		print("=== UI VISUAL REGRESSION PASSED (%d checks) ===" % _checks)
	get_tree().quit(0 if _fails == 0 else 1)


## 由视口走 GUI 焦点分发，不能以直接调用回调替代模态输入验证。
func _press_key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	get_viewport().push_input(event)
	await get_tree().process_frame
	event = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = false
	get_viewport().push_input(event)
	await get_tree().process_frame
