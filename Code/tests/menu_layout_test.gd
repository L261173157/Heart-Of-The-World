## 主菜单视觉结构与输入回归：不加载世界、不写真实存档。
## 运行：Godot --headless --path Code res://tests/menu_layout_test.tscn
extends Node

const MENU_SCENE := preload("res://scenes/ui/main_menu.tscn")
const DIMENSIONS: Array[Vector2] = [Vector2(1280, 720), Vector2(1560, 720), Vector2(1280, 960)]
var _fails := 0
var _checks := 0
var _menu: Control


func _ready() -> void:
	GameState.save_enabled = false
	GameState.reset_all()
	GameState.ecology_snapshot = {"game_day": 7, "instances": []}
	GameState.gold = 233
	_run()


func _check(ok: bool, description: String) -> void:
	_checks += 1
	if ok:
		print("  PASS  ", description)
	else:
		_fails += 1
		print("  FAIL  ", description)


func _run() -> void:
	_menu = MENU_SCENE.instantiate()
	add_child(_menu)
	await get_tree().process_frame
	await get_tree().process_frame
	for dimensions: Vector2 in DIMENSIONS:
		# 测试根不负责 Control 的布局；显式模拟横屏/宽屏/平板的安全区画布。
		_menu.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_menu.position = Vector2.ZERO
		_menu.size = dimensions
		_menu._layout_menu()
		await get_tree().process_frame
		var area := Rect2(Vector2.ZERO, dimensions)
		for node_name: String in ["StartBtn", "NewBtn", "ArchiveBtn", "SettingsBtn", "QuitBtn"]:
			var button := _menu.get_node("MenuBox/" + node_name) as Button
			_check(area.encloses(button.get_global_rect()), "%s 菜单按钮在屏内：%s" % [dimensions, node_name])
			_check(button.size.y >= 48.0, "%s 点击高度至少 48px" % node_name)
		for item: Array in [["ArchiveBtn", "ArchiveLayer", "ArchiveLayer/ArchivePanel", "ArchiveLayer/ArchivePanel/Margin/VB/HB/ArchiveClose"],
				["SettingsBtn", "SettingsLayer", "SettingsLayer/SettingsBox", "SettingsLayer/SettingsBox/SettingsClose"],
				["NewBtn", "NewGameConfirm", "NewGameConfirm/NewPanel", "NewGameConfirm/NewPanel/Margin/VB/HB/NewCancel"]]:
			for iteration: int in range(3):
				await _check_modal(area, item, iteration)
	# 取消不会清档，危险确认默认把焦点留在取消按钮。
	var seed_before := GameState.world_seed
	_menu.get_node("MenuBox/NewBtn").pressed.emit()
	_menu.get_node("NewGameConfirm/NewPanel/Margin/VB/HB/NewCancel").pressed.emit()
	_check(GameState.world_seed == seed_before and GameState.gold == 233, "取消新的冒险保留原进度")
	_menu.get_node("MenuBox/NewBtn").pressed.emit()
	_menu._do_new_game()
	var seed_once := GameState.world_seed
	_menu._do_new_game()
	_check(GameState.world_seed == seed_once, "同帧重复确认不二次重掷世界")
	_check(_menu.get_node("MenuBox/StartBtn").text == "开始冒险"
			and not _menu.get_node("MenuBox/NewBtn").visible, "清档后恢复新玩家入口")
	_menu._toast("first")
	var old_tween: Tween = _menu._toast_tween
	_menu._toast("second")
	_check(not old_tween.is_valid(), "重复提示终止旧淡出动画")
	_check(_menu.get_node("MenuToast").z_index > 0, "保存结果提示位于模态遮罩之上")
	_menu.queue_free()
	await get_tree().process_frame
	if _fails == 0:
		print("=== MENU LAYOUT REGRESSION PASSED (%d checks) ===" % _checks)
	else:
		print("=== MENU LAYOUT REGRESSION FAILED (%d/%d) ===" % [_fails, _checks])
	get_tree().quit(0 if _fails == 0 else 1)


func _check_modal(area: Rect2, item: Array, iteration: int) -> void:
	var button := _menu.get_node("MenuBox/" + item[0]) as Button
	button.grab_focus()
	button.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	var layer := _menu.get_node(item[1]) as Control
	var panel := _menu.get_node(item[2]) as Control
	var label := "%s %s 第%d次" % [area.size, item[1], iteration + 1]
	_check(area.encloses(panel.get_global_rect()), label + "：弹层完整位于屏内")
	_check(layer.is_ancestor_of(get_viewport().gui_get_focus_owner()), label + "：捕获键盘焦点")
	_check(_menu.get_node("MenuBox/StartBtn").focus_mode == Control.FOCUS_NONE,
			label + "：背景按钮不能被 Tab 选中")
	_menu._start()
	_check(not _menu._starting, label + "：模态打开时拒绝开始回调")
	if item[1] == "NewGameConfirm":
		_check(get_viewport().gui_get_focus_owner() == _menu.get_node(
				"NewGameConfirm/NewPanel/Margin/VB/HB/NewCancel"), label + "：默认聚焦取消")
	var escape := InputEventAction.new()
	escape.action = "ui_cancel"
	escape.pressed = true
	_menu._unhandled_key_input(escape)
	_check(not layer.visible and get_viewport().gui_get_focus_owner() == button,
			label + "：Escape 关闭并还原焦点")
	# 关闭是幂等操作，双击不能因 toggle 再次打开弹层。
	button.pressed.emit()
	await get_tree().process_frame
	var close_button := _menu.get_node(item[3]) as Button
	close_button.pressed.emit()
	close_button.pressed.emit()
	_check(not layer.visible and get_viewport().gui_get_focus_owner() == button,
			label + "：同帧双击关闭不会重新打开")
