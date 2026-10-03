## 持盾专用控件：主动松手与取消分开，绝不把 button_up 当作反击。
## 只接管自己的触点，滑出即取消，旧触点滑回不重新举盾；其它手指留给摇杆。
extends Button

var input_allowed: Callable
## -1 空闲，非负值为手指索引，-2 为真实鼠标。
var _touch_index := -1
var _touch_inside := false
var _was_allowed := true
var _guard_state := "idle"
var _guard_charge := 0
var _block_flash := 0.0


func _enter_tree() -> void:
	TouchInput.set_guard_availability_check(_allowed)


func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	TouchInput.guard_canceled.connect(_clear_capture)
	EventBus.touch_input_reset.connect(_clear_capture)
	_was_allowed = _allowed()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.index == _touch_index and (not touch.pressed or touch.canceled):
			if not touch.canceled and _allowed() and get_global_rect().has_point(touch.position):
				_release_hold()
			else:
				cancel_touch()
			get_viewport().set_input_as_handled()
		elif touch.pressed and not touch.canceled and _touch_index == -1 \
				and _allowed() and get_global_rect().has_point(touch.position):
			_begin_hold(touch.index)
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index == _touch_index:
		if not _allowed() or not get_global_rect().has_point(event.position):
			cancel_touch()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index != MOUSE_BUTTON_LEFT:
			return
		if mouse.device == InputEvent.DEVICE_ID_EMULATION:
			# 拦截重复按下；释放不能吞掉，否则其它控件持有的鼠标会粘住。
			if mouse.pressed and _allowed() and get_global_rect().has_point(mouse.position):
				get_viewport().set_input_as_handled()
			return
		if not mouse.pressed and _touch_index == -2:
			if _allowed() and get_global_rect().has_point(mouse.position):
				_release_hold()
			else:
				cancel_touch()
			get_viewport().set_input_as_handled()
		elif mouse.pressed and _touch_index == -1 and _allowed() \
				and get_global_rect().has_point(mouse.position):
			_begin_hold(-2)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION \
			and _touch_index == -2:
		if not _allowed() or not get_global_rect().has_point(event.position) \
				or not (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
			cancel_touch()
		get_viewport().set_input_as_handled()


func _allowed() -> bool:
	return not disabled and is_visible_in_tree() and not get_tree().paused \
			and (not input_allowed.is_valid() or input_allowed.call())


func _begin_hold(index: int) -> void:
	_touch_index = index
	_touch_inside = true
	TouchInput.begin_guard()
	queue_redraw()


func _release_hold() -> void:
	_clear_capture()
	TouchInput.release_guard()


func cancel_touch() -> void:
	# 总是广播：控件不可用时，键盘 F 也应结束且等待新的按下。
	TouchInput.cancel_guard()


func _clear_capture() -> void:
	_touch_index = -1
	_touch_inside = false
	queue_redraw()


func _process(delta: float) -> void:
	var allowed := _allowed()
	# disabled 没有独立信号；HUD 为 ALWAYS，暂停/模态期间也能检查状态变更。
	if not allowed and (_was_allowed or _touch_index != -1):
		cancel_touch()
	_was_allowed = allowed
	if _block_flash > 0.0 and not get_tree().paused:
		_block_flash = maxf(0.0, _block_flash - delta)
		queue_redraw()


func _notification(what: int) -> void:
	if not is_node_ready():
		return
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT \
			or (what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree()):
		cancel_touch()


func _exit_tree() -> void:
	# HUD 离开世界时不等待一个已不可能送达的 release。
	TouchInput.cancel_guard()
	TouchInput.clear_guard_availability_check(_allowed)


## HUD 只转发 EventBus 快照，不持有玩家节点。
func set_guard_feedback(state: String, charge: int) -> void:
	var next_charge := clampi(charge, 0, CharacterStats.GUARD_MAX_CHARGE)
	if next_charge > _guard_charge:
		_block_flash = 0.25
	if state != _guard_state or next_charge != _guard_charge:
		_guard_state = state
		_guard_charge = next_charge
		queue_redraw()


func _draw() -> void:
	var active := _guard_state in ["raising", "guarding", "counter"] or _touch_inside
	var broken := _guard_state == "broken"
	var accent := Color("f0d185") if _guard_charge > 0 or _guard_state == "counter" else Color("a3daec")
	if broken:
		accent = Color("f18c78")
	elif disabled:
		accent = Color("85959c")
	if active or broken:
		draw_circle(size * 0.5, minf(size.x, size.y) * 0.43, Color(accent, 0.13))
		draw_arc(size * 0.5, minf(size.x, size.y) * 0.47, 0, TAU, 48, accent, 3)
	if _block_flash > 0.0:
		draw_circle(size * 0.5, minf(size.x, size.y) * 0.43, Color(1, 0.95, 0.72, _block_flash))
	# 几何盾标沿用像素 UI 的硬边、深底和浅描边，无新增位图资产。
	var center := Vector2(size.x * 0.5, size.y * 0.39)
	var outline := PackedVector2Array([
		center + Vector2(-17, -15), center + Vector2(17, -15),
		center + Vector2(15, 5), center + Vector2(9, 14), center + Vector2(0, 20),
		center + Vector2(-9, 14), center + Vector2(-15, 5)])
	draw_colored_polygon(outline, Color("284655") if not broken else Color("603b3e"))
	var closed := outline.duplicate()
	closed.append(outline[0])
	draw_polyline(closed, accent, 3, false)
	if broken:
		draw_polyline(PackedVector2Array([center + Vector2(4, -13), center + Vector2(-3, -3),
				center + Vector2(5, 3), center + Vector2(-4, 17)]), Color("f18c78"), 3, false)
	else:
		draw_line(center + Vector2(0, -10), center + Vector2(0, 11), accent, 3)
		draw_line(center + Vector2(-9, -4), center + Vector2(9, -4), accent, 3)
	for i in CharacterStats.GUARD_MAX_CHARGE:
		var x := size.x * 0.5 + (i - (CharacterStats.GUARD_MAX_CHARGE - 1) * 0.5) * 16.0
		var pip := Vector2(x, size.y * 0.71)
		draw_circle(pip, 5, Color("13252f"))
		draw_arc(pip, 5, 0, TAU, 12, Color("94a4a4"), 1.5, false)
		if i < _guard_charge:
			draw_circle(pip, 3.5, Color("f0d185"))
