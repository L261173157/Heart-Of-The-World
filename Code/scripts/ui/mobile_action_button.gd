## 真实多点触控按钮：每个按钮独立持有触点，按下即沿既有 button_down 输入。
## 不依赖系统只模拟一根手指的鼠标；滑出/后台/模态均释放，不补发动作。
extends Button

var input_allowed: Callable
var _touch_index := -1
var _touch_inside := false


func _ready() -> void:
	EventBus.touch_input_reset.connect(cancel_touch)


func _input(event: InputEvent) -> void:
	# Godot 仍会为触屏额外生成一组鼠标事件；只在本按钮范围拦截它，
	# 避免一次回城立刻触发第二次取消。只拦截按下，不吞释放：
	# 摇杆可能持有模拟鼠标触点，拇指在按钮上松手仍必须收到 mouse-up。
	if event is InputEventMouseButton and event.pressed and event.device == InputEvent.DEVICE_ID_EMULATION \
			and _allowed() and get_global_rect().has_point(event.position):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.index == _touch_index and (not touch.pressed or touch.canceled):
			var activate := not touch.canceled and _touch_inside and _allowed() \
					and get_global_rect().has_point(touch.position)
			cancel_touch()
			get_viewport().set_input_as_handled()
			if activate:
				pressed.emit()
		elif touch.pressed and not touch.canceled and _touch_index == -1 \
				and _allowed() and get_global_rect().has_point(touch.position):
			_touch_index = touch.index
			_touch_inside = true
			queue_redraw()
			get_viewport().set_input_as_handled()
			button_down.emit()
	elif event is InputEventScreenDrag and event.index == _touch_index:
		_touch_inside = get_global_rect().has_point(event.position)
		queue_redraw()
		get_viewport().set_input_as_handled()


func _allowed() -> bool:
	return not disabled and is_visible_in_tree() and not get_tree().paused \
			and (not input_allowed.is_valid() or input_allowed.call())


func cancel_touch() -> void:
	var held := _touch_index != -1
	_touch_index = -1
	_touch_inside = false
	queue_redraw()
	if held:
		button_up.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		cancel_touch()


func _draw() -> void:
	if _touch_index != -1 and _touch_inside:
		draw_circle(size * 0.5, minf(size.x, size.y) * 0.43, Color(1, 0.92, 0.66, 0.16))
		draw_arc(size * 0.5, minf(size.x, size.y) * 0.47, 0, TAU, 48,
				Color(1, 0.9, 0.55, 0.95), 3)
