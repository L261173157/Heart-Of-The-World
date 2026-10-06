## 详情中的文字也能成为原始触屏滚动起点；按钮仍由 reading_action_button 处理。
## 与行按钮共享容器触点所有权，第二指不可抢滚动或误触另一行。
extends ScrollContainer

const OWNER_META := &"mobile_action_touch_owner"
var input_allowed: Callable
var _index := -1
var _origin := Vector2.ZERO
var _offset := 0
var _dragging := false

func _ready() -> void:
	EventBus.touch_input_reset.connect(cancel_touch)

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.index == _index and (not event.pressed or event.canceled):
			cancel_touch()
			get_viewport().set_input_as_handled()
		elif event.pressed and not event.canceled and _index == -1 and _allowed() and _inside(event.position) and not _interactive_at(event.position):
			var owner_id := int(get_meta(OWNER_META, 0))
			if owner_id != 0 and owner_id != get_instance_id() and is_instance_id_valid(owner_id): return
			set_meta(OWNER_META, get_instance_id())
			_index = event.index
			_origin = get_global_transform_with_canvas().affine_inverse() * event.position
			_offset = scroll_vertical
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index == _index:
		if not _allowed():
			cancel_touch()
			return
		var offset: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position - _origin
		if absf(offset.y) > scroll_deadzone: _dragging = true
		if _dragging: scroll_vertical = _offset - roundi(offset.y)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.device == InputEvent.DEVICE_ID_EMULATION and _index >= 0 and event.pressed:
		get_viewport().set_input_as_handled()

func _allowed() -> bool:
	return is_visible_in_tree() and (not input_allowed.is_valid() or bool(input_allowed.call()))

func _inside(point: Vector2) -> bool:
	return Rect2(Vector2.ZERO, size).has_point(get_global_transform_with_canvas().affine_inverse() * point)

func _interactive_at(point: Vector2) -> bool:
	for node: Node in find_children("*", "Control", true, false):
		if not (node is BaseButton or node is LineEdit) or not node.is_visible_in_tree(): continue
		if Rect2(Vector2.ZERO, node.size).has_point(node.get_global_transform_with_canvas().affine_inverse() * point): return true
	return false

func cancel_touch() -> void:
	_index = -1
	_dragging = false
	if int(get_meta(OWNER_META, 0)) == get_instance_id(): remove_meta(OWNER_META)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT: cancel_touch()

func _exit_tree() -> void:
	cancel_touch()
