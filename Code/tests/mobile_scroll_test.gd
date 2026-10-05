## 原始触屏从真实行内滚动：不借滚动条/ensure_control_visible，不误点行。
extends "res://tests/mobile_clipping_test.gd"

func _run() -> void:
	_hud = preload("res://scenes/ui/hud.tscn").instantiate()
	add_child(_hud)
	_player = preload("res://scenes/player/player.tscn").instantiate()
	_player.position = WorldConfig.spawn_pos()
	add_child(_player)
	EventBus.item_use_requested.connect(func(_id: String) -> void: _uses += 1)
	for canvas: Vector2i in [Vector2i(1280,720), Vector2i(1560,720), Vector2i(1024,640)]:
		get_tree().root.size = canvas
		get_tree().root.content_scale_size = canvas
		get_tree().root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		await _settle()
		await _test_more_scroll(canvas)
		await _test_long_reading_scroll(canvas)
	_hud.queue_free()
	_player.queue_free()
	await _settle()
	TouchInput.reset()
	get_tree().paused = false
	if _fails == 0:
		print("=== MOBILE SCROLL PASS (%d checks) ===" % _checks)
	else:
		print("=== MOBILE SCROLL FAIL (%d checks, %d failures) ===" % [_checks, _fails])
	get_tree().quit(0 if _fails == 0 else 1)

func _test_more_scroll(canvas: Vector2i) -> void:
	GameState.inventory.clear()
	for id: String in ItemCatalog.ids_of_kind("consumable"):
		GameState.inventory[id] = 3
	_player.current_hp = 20
	_player.current_mp = 10
	_player._push_hud()
	await _tap(_button("MoreBtn"))
	var scroll := _hud._more_items.get_parent() as ScrollContainer
	scroll.scroll_vertical = 0
	await _settle()
	var first := _button("QuickItem_onigiri")
	var target := _button("QuickItem_water-pot")
	var inventory_before := GameState.inventory.duplicate(true)
	var uses_before := _uses
	var point := _center(first)
	_check(not scroll.get_global_rect().has_point(_center(target)), "下方物品起初真实裁剪 " + str(canvas))
	# 小于容器本身死区的抖动仍是一按一次的点击，使用后由真实 HUD 重建行。
	_touch(point,true,7,false,false)
	_drag(point+Vector2(0,minf(2,scroll.scroll_deadzone*0.5)))
	_touch(point,false,7,false,false)
	await _settle()
	_check(GameState.count_item("onigiri")==2 and _uses==uses_before+1, "死区内轻微抖动仍只用一次可见补给")
	inventory_before = GameState.inventory.duplicate(true)
	uses_before = _uses
	first = _button("QuickItem_onigiri")
	target = _button("QuickItem_water-pot")
	point = _center(first)
	_touch(point,true,7,false,false)
	_drag(point+Vector2(0,-40))
	await _settle()
	var held_offset := scroll.scroll_vertical
	var other := _visible_row_point(scroll,_hud._more_items)
	_touch(other,true,9,false,false)
	_touch(other,false,9,false,false)
	await _settle()
	_check(_uses==uses_before and first.get("_touch_index")==7, "滚动期间第二指不能消费列表其它行或抢触点")
	TouchInput.reset()
	_drag(point+Vector2(0,-100))
	_touch(point+Vector2(0,-100),false,7,false,false)
	await _settle()
	_check(scroll.scroll_vertical==held_offset and _uses==uses_before and first.get("_touch_index")==-1,
		"重置中断滚动；旧拖动/抬起不滚动或消费")
	var swipes := await _swipe_to(scroll,_hud._more_items,target)
	_check(swipes>0 and scroll.get_global_rect().has_point(_center(target)), "实际行内手指上滑到隐藏补给")
	_check(_uses==uses_before and GameState.inventory==inventory_before and not get_tree().paused,
		"拖动不消费起始行/其它补给且世界继续运行")
	print("SCROLL_EVIDENCE more canvas=",canvas," swipes=",swipes," offset=",scroll.scroll_vertical," target=",target.get_global_rect())
	await _tap(target)
	_check(GameState.count_item("water-pot")==2 and _uses==uses_before+1, "滚入目标后新点击只使用目标一次")
	await _tap(_button("MoreClose"))
	_check(not _hud._more_panel.visible, "滚动后的真实关闭键正常关闭")

func _test_long_reading_scroll(canvas: Vector2i) -> void:
	var options: Array = []
	for i in 20:
		options.append({"action":"scroll-option-%d"%i,"label":"调查线索%d"%i,"consequence":"阅读结果","risk":"无",
			"enabled":i>=3,"disabled_reason":"缺少线索"})
	_hud._open_dialogue({"kind":"camp_choice","giver":"巡守","text":"二十项调查方案","options":options})
	await _settle()
	var scroll: ScrollContainer = _hud._dialogue_option_scroll
	var rows: VBoxContainer = _hud._dialogue_option_box
	var first := rows.get_child(0) as Button
	var target := rows.get_child(19) as Button
	var inventory_before := GameState.inventory.duplicate(true)
	_check(first.disabled and not scroll.get_global_rect().has_point(_center(target)), "二十项阅读开头有禁用行，末行不可见 " + str(canvas))
	var point := _center(first)
	await _finger_scroll(point,point+Vector2(0,-110))
	_check(scroll.scroll_vertical>0 and _hud._dialogue_selected_option.is_empty(), "禁用方案也可作为滚动起点但不能被选择")
	var before := scroll.scroll_vertical
	point = _visible_row_point(scroll,rows)
	_touch(point,true,7,false,false)
	_drag(point+Vector2(0,-55))
	await _settle()
	_touch(point+Vector2(0,-55),false,7,true,false)
	await _settle()
	_check(scroll.scroll_vertical>before and _hud._dialogue_selected_option.is_empty(), "系统取消已滚动手势不会预览任一方案")
	var swipes := await _swipe_to(scroll,rows,target)
	_check(swipes>0 and scroll.get_global_rect().has_point(_center(target)), "只靠行内连续手指上滑到第二十项")
	_check(_hud._dialogue_selected_option.is_empty() and GameState.inventory==inventory_before and get_tree().paused,
		"整个阅读拖动过程不选择/消费并保持暂停")
	print("SCROLL_EVIDENCE reading canvas=",canvas," swipes=",swipes," offset=",scroll.scroll_vertical," target=",target.get_global_rect())
	await _tap(target)
	_check(_hud._dialogue_selected_option.get("action","")=="scroll-option-19" and get_tree().paused,
		"滚入第二十项后全新点击只打开该项预览")
	await _tap(_hud._dialogue_no)
	_check(_hud._dialogue_selected_option.is_empty() and _hud._dialogue_panel.visible, "实际返回键取消预览但保留阅读")
	await _tap(_hud._dialogue_no)
	_check(not _hud._dialogue_panel.visible and not get_tree().paused, "再按实际关闭键恢复世界")

func _visible_row_point(scroll: ScrollContainer, rows: Control) -> Vector2:
	var result := Vector2.INF
	var clip := scroll.get_global_rect().grow(-8)
	for child: Node in rows.get_children():
		if not child is Button:
			continue
		var visible: Rect2 = child.get_global_rect().intersection(clip)
		if visible.size.y>=16:
			result = visible.get_center()
	return result

func _swipe_to(scroll: ScrollContainer, rows: Control, target: Control) -> int:
	var swipes := 0
	while not scroll.get_global_rect().grow(-4).has_point(_center(target)) and swipes<40:
		var point := _visible_row_point(scroll,rows)
		if point==Vector2.INF:
			break
		var before := scroll.scroll_vertical
		await _finger_scroll(point,Vector2(point.x,maxf(scroll.get_global_rect().position.y+8,point.y-200)))
		swipes += 1
		if scroll.scroll_vertical<=before:
			break
	return swipes

func _finger_scroll(start: Vector2, end: Vector2) -> void:
	_touch(start,true)
	await _settle()
	var previous := start
	for i in range(1,13):
		var point := start.lerp(end,float(i)/12)
		var transform := get_viewport().get_screen_transform()
		var motion := InputEventScreenDrag.new()
		motion.index = 7
		motion.position = transform * point
		motion.relative = transform.basis_xform(point-previous)
		motion.screen_relative = motion.relative
		motion.velocity = motion.relative * 60
		motion.screen_velocity = motion.velocity
		Input.parse_input_event(motion)
		var mouse := InputEventMouseMotion.new()
		mouse.device = InputEvent.DEVICE_ID_EMULATION
		mouse.position = motion.position
		mouse.relative = motion.relative
		mouse.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(mouse)
		previous = point
		await _settle()
	_touch(end,false)
	await _settle()
