## 审计回归：原始触屏与配对鼠标、连续赐福的手势身份、成长页返回数据。
extends "res://tests/equipment_bag_ui_test.gd"

func _run() -> void:
	# iOS 的弹窗嵌在游戏窗口；验证原生 PopupMenu 的实际指针分发。
	get_tree().root.gui_embed_subwindows = true
	await _create_fixture()
	var legacy := Gear.legacy_item({"name": "触屏物攻样本", "rarity": 2, "affixes": {"atk": 0.2}}, "touch_filter_legacy", "weapon")
	legacy["favorite"] = true
	GameState.receive_equipment(legacy)
	var canvases := [Vector2i(1280, 720), Vector2i(1560, 720), Vector2i(1024, 640)]
	if not OS.get_environment("HOTW_MOBILE_AUDIT_SHOTS").is_empty():
		canvases.insert(2, Vector2i(2160, 1080))
	for canvas: Vector2i in canvases:
		get_tree().root.size = canvas
		get_tree().root.content_scale_size = canvas
		get_tree().root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		get_tree().root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
		await _settle()
		await _test_touch_filters(canvas)
	await _test_option_cancel()
	await _test_craft_base()
	await _tap(_button("InventoryClose"))
	await _tap(_button("ResumeBtn"))
	await _test_passive_rounds()
	await _test_clipped_option()
	await _test_popup_lifecycle()
	await _test_scaled_popup()
	_hud.queue_free()
	_player.queue_free()
	await _settle()
	TouchInput.reset()
	get_tree().paused = false
	print("=== MOBILE READING AUDIT %s (%d checks) ===" % ["PASS" if _fails == 0 else "FAIL", _checks])
	get_tree().quit(0 if _fails == 0 else 1)

func _test_touch_filters(canvas: Vector2i) -> void:
	await _tap(_button("PauseBtn"))
	await _tap(_button("MenuInventory"))
	await _tap(_button("BagTab_gear"))
	await _show_filter_controls()
	await _select_touch_option("BagAffixFilter", "phys")
	_check(_bag.get("_filters").get("affix") == "phys", "触屏选择属性生效 " + str(canvas))
	await _select_touch_option("BagSlotFilter", "weapon")
	await _select_touch_option("BagRarityFilter", 2)
	await _select_touch_option("BagTagFilter", "favorite")
	await _select_touch_option("BagSort", "level")
	var rows := _bag.find_children("BagItem_*", "Button", true, false)
	_check(rows.size() == 1 and str(rows[0].name) == "BagItem_touch_filter_legacy", "实际筛选列表只显示四条件匹配项 " + str(canvas))
	await _select_touch_option("BagAffixFilter", "magic")
	_check(_bag.find_children("BagItem_*", "Button", true, false).is_empty(), "触屏切换属性产生实际空结果")
	await _select_touch_option("BagAffixFilter", "")
	await _select_touch_option("BagRarityFilter", -1)
	await _select_touch_option("BagTagFilter", "all")
	await _select_touch_option("BagSlotFilter", "")
	_check(int(_bag.get("_pages")) >= 3, "触屏清除筛选恢复原分页")
	await _select_touch_option("BagSort", "newest")
	if canvas.x != 1024:
		await _tap(_button("InventoryClose"))
		await _tap(_button("ResumeBtn"))

func _popup_item_point(popup: PopupMenu, index: int) -> Vector2:
	# OptionButton 的各行均为同字体的普通文本；从真实布局取行高，避免写死主题像素。
	var items := popup.find_child("*PopupMenuItems*", true, false) as Control
	_check(items != null, "原生弹窗项目布局已生成")
	if items == null: return Vector2.INF
	var local := items.get_global_rect().position + Vector2(items.size.x * 0.5, items.size.y / popup.item_count * (index + 0.5))
	return get_viewport().get_screen_transform().affine_inverse() * (popup.get_screen_transform() * local)

func _select_touch_option(name_: String, value: Variant) -> void:
	if name_ != "BagBaseChoice": await _show_filter_controls()
	var option := _button(name_) as OptionButton
	_check(option != null, "实际下拉控件存在 " + name_)
	if option == null: return
	var target := -1
	for index in option.item_count:
		if option.get_item_metadata(index) == value: target = index
	_check(target >= 0, "下拉候选存在 " + name_ + " / " + str(value))
	if target < 0: return
	var emulation_before := Input.emulate_mouse_from_touch
	var selections := [0]
	option.item_selected.connect(func(_index: int) -> void: selections[0] += 1)
	await _tap(option)
	var popup := option.get_popup()
	_check(popup.visible, "配对原始触屏打开下拉 " + name_)
	if not popup.visible: return
	if name_ == "BagAffixFilter" and value == "phys":
		await _save_mobile_shot("dropdown")
	var point := _popup_item_point(popup, target)
	_check(get_viewport().get_visible_rect().has_point(point), "目标下拉项完整位于视口内 " + name_)
	await _tap_at(point)
	_check(selections[0] == 1, "原生弹窗触屏选择恰好一次 " + name_)
	if is_instance_valid(popup): popup.hide()
	_check(Input.emulate_mouse_from_touch == emulation_before, "关闭下拉恢复原触屏模拟设置")
	_check(_hud._gesture_gate.held.is_empty(), "跨弹窗触点已全部释放")

func _test_option_cancel() -> void:
	await _show_filter_controls()
	var option := _button("BagAffixFilter") as OptionButton
	var original: Dictionary = _bag.get("_filters").duplicate(true)
	var point := _center(option)
	_touch(point, true)
	_touch(point, false, 7, true)
	await _settle()
	_check(not option.get_popup().visible and _bag.get("_filters") == original, "取消按下不打开下拉或修改筛选")
	_touch(point, true)
	_drag(point + Vector2(0, -45))
	_touch(point + Vector2(0, -45), false)
	await _settle()
	_check(not option.get_popup().visible and _bag.get("_filters") == original, "拖动筛选行只滚动，不打开下拉")
	await _show_filter_controls()
	point = _center(option)
	_touch(point, true, 31, false, false)
	_drag(point + Vector2(0, -25), 31)
	await _settle()
	var other := _button("BagRarityFilter") as OptionButton
	_touch(_center(other), true, 32, false, false)
	_touch(_center(other), false, 32, false, false)
	await _settle()
	_check(not other.get_popup().visible, "列表滚动占用期间第二指不能打开其它下拉")
	_touch(point, false, 31, true, false)
	await _settle()
	await _show_filter_controls()
	await _tap(option)
	_check(option.get_popup().visible, "取消滚动后新手势可以打开下拉")
	await _key(KEY_ESCAPE)
	_check(not option.get_popup().visible and _bag.visible and _bag.get("_filters") == original, "Escape 仅取消下拉，保留背包及筛选")
	# 原生鼠标/键盘入口仍保持可用。
	option.grab_focus()
	await _key(KEY_ENTER)
	_check(option.get_popup().visible, "键盘仍可打开原生下拉")
	await _key(KEY_ESCAPE)
	await _mouse_click(option)
	_check(option.get_popup().visible, "原生鼠标仍可打开下拉")
	await _key(KEY_ESCAPE)
	_check(_hud._gesture_gate.held.is_empty(), "原生弹窗接收的鼠标/键盘释放不会留下旧手势")
	await _tap(option)
	point = _popup_item_point(option.get_popup(), 1)
	_touch(point, true)
	await _settle()
	_touch(point, false, 7, true)
	await _settle()
	_check(_bag.get("_filters") == original, "原生下拉项目收到系统取消不能提交")
	if not is_instance_valid(option): option = _button("BagAffixFilter") as OptionButton
	if option.get_popup().visible: await _key(KEY_ESCAPE)
	await _tap(option)
	point = _popup_item_point(option.get_popup(), 1)
	_touch(point, true)
	await _settle()
	get_tree().root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	get_tree().root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	_touch(point, false)
	await _settle()
	_check(_bag.get("_filters") == original and not option.get_popup().visible, "失焦恢复关闭下拉，旧抬手不能提交")
	_check(Input.emulate_mouse_from_touch, "失焦关闭恢复触屏鼠标模拟")
	# 原本禁用模拟的环境也支持纯原始触屏，关闭不能擅自改回开启。
	Input.emulate_mouse_from_touch = false
	await _tap(option)
	point = _popup_item_point(option.get_popup(), 1)
	_touch(point, true, 41, false, false)
	_touch(point, false, 41, true, false)
	await _settle()
	_check(_bag.get("_filters") == original and not Input.emulate_mouse_from_touch, "纯原始触屏取消，保留原禁用模拟设置")
	Input.emulate_mouse_from_touch = true

func _test_craft_base() -> void:
	await _tap(_button("BagGear_craft"))
	await _scroll_to(_button("BagCraftSlot_weapon"), _bag.get("_list_scroll"))
	await _tap(_button("BagCraftSlot_weapon"))
	await _scroll_to(_button("BagPurchaseWhite"), _bag.get("_list_scroll"))
	await _tap(_button("BagPurchaseWhite"))
	var option := _button("BagBaseChoice") as OptionButton
	_check(option != null, "切换白装后显示基底下拉")
	if option == null: return
	await _scroll_to(option, _bag.get("_list_scroll"))
	var target: String = str(option.get_item_metadata(1))
	await _select_touch_option("BagBaseChoice", target)
	_check(_bag.get("_selected_base") == target and str(_bag.get("_offer").get("item", {}).get("base_id", "")) == target, "打造基底触屏选择刷新真实成品报价")

func _test_passive_rounds() -> void:
	GameState.stats.pending_points = 1
	GameState.stats.pending_passive_picks = 2
	GameState.stats.passive_choices.assign(["phys", "cdr", "hp"])
	GameState.stats.passive_offer_id += 1
	await _tap(_button("PauseBtn"))
	await _tap(_button("MenuGrowth"))
	await _tap(_button("OpenBlessing"))
	_touch(_center(_hud.passive_cards[0]), true, 11, false, false)
	_touch(_center(_hud.passive_cards[1]), true, 12, false, false)
	await _settle()
	_touch(_center(_hud.passive_cards[0]), false, 11, false, false)
	await _settle()
	_check(GameState.stats.pending_passive_picks == 1, "第一根手指仅领取第一轮")
	_touch(_center(_hud.passive_cards[2]), true, 13, false, false)
	_touch(_center(_hud.passive_cards[2]), false, 13, false, false)
	await _settle()
	_check(GameState.stats.pending_passive_picks == 1, "旧第二指尚未释放时第三指不能领取新一轮")
	_touch(_center(_hud.passive_cards[1]), false, 12, false, false)
	await _settle()
	_check(GameState.stats.pending_passive_picks == 1, "旧第二指抬起不能领取新一轮")
	var point := _center(_hud.passive_cards[0])
	_touch(point, true)
	_touch(point, false, 7, true)
	await _settle()
	_check(GameState.stats.pending_passive_picks == 1, "系统取消卡片不消耗资格")
	# 单独验证身份守卫：即使未来某次重绘漏掉取消，旧按下也不能读取新 metadata。
	_touch(point, true)
	await _settle()
	GameState.stats.passive_offer_id += 1
	_hud.passive_cards[0].set_meta("passive_offer_id", GameState.stats.passive_offer_id)
	_touch(point, false)
	await _settle()
	_check(GameState.stats.pending_passive_picks == 1, "手势提交核对按下身份，不读取被覆盖的新身份")
	_touch(point, true)
	await _settle()
	get_tree().root.propagate_notification(NOTIFICATION_APPLICATION_PAUSED)
	get_tree().root.propagate_notification(NOTIFICATION_APPLICATION_RESUMED)
	_touch(point, false)
	await _settle()
	_check(GameState.stats.pending_passive_picks == 1 and int(_hud.passive_cards[0].get("_touch_index")) == -1, "后台恢复后的旧释放不消耗资格")
	if GameState.stats.pending_passive_picks > 0:
		await _tap(_hud.passive_cards[0])
	_check(GameState.stats.pending_passive_picks == 0 and _hud._stats_overview_layer.visible, "全新手势领取下一轮并返回成长")
	var blessing := _button("OpenBlessing")
	var summary := _hud._stats_overview_layer.find_child("Body", true, false).get_child(0) as Label
	_check(blessing.disabled and blessing.text.contains("0次"), "成长页刷新赐福余额与禁用状态")
	_check(not summary.text.contains("已获赐福：暂无"), "成长页刷新实际已获赐福")
	await _tap(_button("PreviewAttribute_strength"))
	await _tap(_button("ConfirmAttribute"))
	_check(GameState.stats.pending_points == 0 and _hud._stats_overview_layer.visible, "最后一点分配后返回成长")
	_check(_button("PreviewAttribute_strength").disabled and _button("PreviewAttribute_agility").disabled \
		and _button("PreviewAttribute_intellect").disabled, "成长页禁用全部已耗尽属性入口")
	if not OS.get_environment("HOTW_MOBILE_AUDIT_SHOTS").is_empty():
		for canvas: Vector2i in [Vector2i(1280, 720), Vector2i(2160, 1080)]:
			get_tree().root.size = canvas
			get_tree().root.content_scale_size = canvas
			await _settle()
			await _save_mobile_shot("growth")

func _test_clipped_option() -> void:
	_hud.get_node("Root").hide()
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var outer := Control.new()
	outer.position = Vector2(120, 100)
	outer.size = Vector2(200, 80)
	outer.scale = Vector2(1.2, 1.2)
	outer.clip_contents = true
	canvas.add_child(outer)
	var middle := Control.new()
	middle.size = Vector2(200, 200)
	outer.add_child(middle)
	var option := OptionButton.new()
	option.set_script(preload("res://scripts/ui/reading_action_button.gd"))
	option.position = Vector2(10, 50)
	option.size = Vector2(160, 70)
	option.add_item("第一项")
	option.add_item("第二项")
	middle.add_child(option)
	await _settle()
	var visible_point := option.get_global_transform_with_canvas() * Vector2(50, 10)
	var clipped_point := option.get_global_transform_with_canvas() * Vector2(50, 60)
	await _tap_at(clipped_point)
	_check(not option.get_popup().visible and int(option.get("_touch_index")) == -1, "嵌套祖先裁剪外的下拉不能捕获或打开")
	_touch(visible_point, true)
	_drag(clipped_point)
	_touch(clipped_point, false)
	await _settle()
	_check(not option.get_popup().visible, "从可见下拉拖出裁剪边界不打开")
	await _tap_at(visible_point)
	_check(option.get_popup().visible, "裁剪内片段仍可打开下拉")
	await _tap_at(_popup_item_point(option.get_popup(), 1))
	_check(option.selected == 1, "原生弹窗不受来源行裁剪，真实触屏可选择")
	canvas.queue_free()
	await _settle()
	_hud.get_node("Root").show()

func _test_popup_lifecycle() -> void:
	_hud.get_node("Root").hide()
	for original: bool in [true, false]:
		Input.emulate_mouse_from_touch = original
		var canvas := CanvasLayer.new()
		add_child(canvas)
		var option := OptionButton.new()
		option.set_script(preload("res://scripts/ui/reading_action_button.gd"))
		option.position = Vector2(120, 100)
		option.size = Vector2(200, 60)
		option.add_item("第一项")
		option.add_item("第二项")
		canvas.add_child(option)
		await _settle()
		for mode: String in ["select", "cancel", "drag", "focus", "pause"]:
			await _tap(option)
			_check(option.get_popup().visible and not Input.emulate_mouse_from_touch, "弹窗局部接管模拟 " + mode + " / " + str(original))
			var point := _popup_item_point(option.get_popup(), 1 - option.selected)
			var selected := option.selected
			_touch(point, true, 63, false, false)
			await _settle()
			if mode == "drag": _drag(point + Vector2(0, 40), 63)
			if mode == "focus": get_tree().root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
			if mode == "pause": get_tree().root.propagate_notification(NOTIFICATION_APPLICATION_PAUSED)
			_touch(point, false, 63, mode == "cancel", false)
			await _settle()
			_check(not option.get_popup().visible and Input.emulate_mouse_from_touch == original, "关闭恢复原模拟设置 " + mode + " / " + str(original))
			_check(option.selected == (1 - selected if mode == "select" else selected), "只有完整原始触屏点击可改变选项 " + mode)
			_check(not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT), "取消/选择后没有残留鼠标按下 " + mode)
		await _tap(option)
		canvas.queue_free()
		await _settle()
		_check(Input.emulate_mouse_from_touch == original, "带弹窗离场恢复原模拟设置 / " + str(original))
	Input.emulate_mouse_from_touch = true
	_hud.get_node("Root").show()
	await _tap(_hud._stats_overview_layer.find_child("ChoiceClose", true, false))
	await _tap(_button("ResumeBtn"))
	await _tap(_button("MoreBtn"))
	_check(_hud._more_panel.visible and not get_tree().paused, "弹窗离场后战斗 HUD 新触屏仍可打开更多")
	await _tap(_button("MoreClose"))
	_check(not _hud._more_panel.visible and _hud._gesture_gate.held.is_empty(), "恢复游戏关闭操作正常且手势门禁无残留")

func _save_mobile_shot(label: String) -> void:
	var directory := OS.get_environment("HOTW_MOBILE_AUDIT_SHOTS")
	if directory.is_empty(): return
	_check(DisplayServer.get_name() != "headless", "截图必须来自真实渲染器")
	if DisplayServer.get_name() == "headless": return
	DirAccess.make_dir_recursive_absolute(directory)
	await RenderingServer.frame_post_draw
	var captured := get_viewport().get_texture().get_image()
	var canvas := captured.get_size()
	print("MOBILE_AUDIT_GEOMETRY screen=", DisplayServer.screen_get_size(), " window=", DisplayServer.window_get_size(), " root=", get_tree().root.size, " canvas=", get_viewport().get_visible_rect(), " pixels=", canvas, " transform=", get_viewport().get_screen_transform())
	_check(DisplayServer.window_get_size() == get_tree().root.size, "实际窗口大小与请求一致")
	var path := directory.path_join("%s-%dx%d.png" % [label, canvas.x, canvas.y])
	var error := captured.save_png(path)
	_check(error == OK, "渲染截图写入 " + path)
	print("MOBILE_AUDIT_SCREENSHOT ", path)

func _test_scaled_popup() -> void:
	# 生产拉伸方式：2160×1080 物理窗口，1280×720 逻辑画布按 expand 扩展。
	get_tree().root.size = Vector2i(2160, 1080)
	get_tree().root.content_scale_size = Vector2i(1280, 720)
	get_tree().root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	get_tree().root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	await _settle()
	_check(not is_equal_approx(get_viewport().get_screen_transform().get_scale().x, 1.0), "生产画布真实非 1× 拉伸")
	await _tap(_button("PauseBtn"))
	await _tap(_button("MenuInventory"))
	await _tap(_button("BagTab_gear"))
	await _tap(_button("BagGear_bag"))
	await _select_touch_option("BagAffixFilter", "phys")
	_check(_bag.get("_filters").get("affix") == "phys", "非 1× 拉伸下真实触屏与原生弹窗坐标一致")
	await _show_filter_controls()
	await _tap(_button("BagAffixFilter"))
	await _save_mobile_shot("dropdown-scaled")
	await _key(KEY_ESCAPE)
	await _tap(_button("InventoryClose"))
	await _tap(_button("MenuGrowth"))
	await _save_mobile_shot("growth-scaled")
	await _tap(_hud._stats_overview_layer.find_child("ChoiceClose", true, false))
	await _tap(_button("ResumeBtn"))
