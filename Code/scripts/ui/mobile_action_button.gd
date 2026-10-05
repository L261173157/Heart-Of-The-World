## 真实多点触控按钮：每个按钮独立持有触点，按下即沿既有 button_down 输入。
## 不依赖系统只模拟一根手指的鼠标；滑出/后台/模态均释放，不补发动作。
extends Button

var input_allowed: Callable
var _touch_index := -1
var _touch_inside := false
var _touch_scroll: ScrollContainer
var _scroll_touch_origin := Vector2.ZERO
var _scroll_value_origin := Vector2.ZERO
var _touch_scrolling := false
const SCROLL_OWNER_META := &"mobile_action_touch_owner"


func _ready() -> void:
	EventBus.touch_input_reset.connect(cancel_touch)


func _input(event: InputEvent) -> void:
	# Godot 仍会为触屏额外生成一组鼠标事件；只在本按钮范围拦截它，
	# 避免一次回城立刻触发第二次取消。只拦截按下，不吞释放：
	# 摇杆可能持有模拟鼠标触点，拇指在按钮上松手仍必须收到 mouse-up。
	if event is InputEventMouseButton and event.pressed and event.device == InputEvent.DEVICE_ID_EMULATION \
			and _touch_allowed() and _hit_test(event.position):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.index == _touch_index and (not touch.pressed or touch.canceled):
			var activate := not touch.canceled and not _touch_scrolling and _touch_inside and _allowed() \
					and _hit_test(touch.position)
			cancel_touch()
			get_viewport().set_input_as_handled()
			if activate:
				# Raw touches bypass BaseButton GUI handling. Mirror its toggle
				# transition once; native mouse/keyboard retain their own path.
				if toggle_mode:
					button_pressed = not button_pressed
				pressed.emit()
		elif touch.pressed and not touch.canceled and _touch_index == -1 \
				and _touch_allowed() and _hit_test(touch.position):
			if not _begin_scroll_touch(touch.position):
				get_viewport().set_input_as_handled()
				return
			_touch_index = touch.index
			_touch_inside = true
			queue_redraw()
			get_viewport().set_input_as_handled()
			if not disabled:
				button_down.emit()
	elif event is InputEventScreenDrag and event.index == _touch_index:
		if not _touch_allowed():
			cancel_touch()
		else:
			_update_scroll_touch(event.position)
			_touch_inside = not _touch_scrolling and _hit_test(event.position)
		queue_redraw()
		get_viewport().set_input_as_handled()


## 原始触屏在 GUI 分发之前到达，必须自己遵守所有祖先的可见裁剪。
## 滚动行即使 is_visible_in_tree() 为真，矩形仍可能伸到关闭键下面。
## 用各控件的局部坐标检测，兼容 CanvasLayer、缩放与旋转；同一规则也
## 用于抬起、拖动和模拟鼠标拦截，不能只修按下而留下吞键/误提交路径。
func _hit_test(point: Vector2) -> bool:
	if not get_viewport().get_visible_rect().has_point(point):
		return false
	if not Rect2(Vector2.ZERO, size).has_point(get_global_transform_with_canvas().affine_inverse() * point):
		return false
	var ancestor := get_parent()
	while ancestor != null and not ancestor is Viewport:
		if ancestor is Control and ancestor.clip_contents:
			var local: Vector2 = ancestor.get_global_transform_with_canvas().affine_inverse() * point
			if not Rect2(Vector2.ZERO, ancestor.size).has_point(local):
				return false
		ancestor = ancestor.get_parent()
	return true


## 行按钮拦截了模拟鼠标按下，ScrollContainer 的原生鼠标拖动无法启动。
## 由持有该触点的行在原有死区后直接滚动；滚动手势永不再变成行点击。
## 同一列表只认一根手指，避免第二指在拖动途中消费其它行。
func _begin_scroll_touch(point: Vector2) -> bool:
	var scroll := _scroll_container()
	if scroll == null:
		return true
	var owner_id := int(scroll.get_meta(SCROLL_OWNER_META, 0))
	if owner_id != 0 and owner_id != get_instance_id() and is_instance_id_valid(owner_id):
		return false
	_touch_scroll = scroll
	_touch_scroll.set_meta(SCROLL_OWNER_META, get_instance_id())
	_scroll_touch_origin = _touch_scroll.get_global_transform_with_canvas().affine_inverse() * point
	_scroll_value_origin = Vector2(_touch_scroll.scroll_horizontal, _touch_scroll.scroll_vertical)
	return true


func _scroll_container() -> ScrollContainer:
	var ancestor := get_parent()
	while ancestor != null and not ancestor is Viewport:
		if ancestor is ScrollContainer:
			return ancestor
		ancestor = ancestor.get_parent()
	return null


func _touch_allowed() -> bool:
	return _allowed()


func _update_scroll_touch(point: Vector2) -> void:
	if not is_instance_valid(_touch_scroll):
		return
	var offset := _touch_scroll.get_global_transform_with_canvas().affine_inverse() * point - _scroll_touch_origin
	var horizontal := _touch_scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED
	var vertical := _touch_scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED
	if not _touch_scrolling:
		_touch_scrolling = (horizontal and absf(offset.x) > _touch_scroll.scroll_deadzone) \
				or (vertical and absf(offset.y) > _touch_scroll.scroll_deadzone)
	if not _touch_scrolling:
		return
	if horizontal:
		_touch_scroll.scroll_horizontal = roundi(_scroll_value_origin.x - offset.x)
	if vertical:
		_touch_scroll.scroll_vertical = roundi(_scroll_value_origin.y - offset.y)


func _allowed() -> bool:
	return not disabled and is_visible_in_tree() and not get_tree().paused \
			and (not input_allowed.is_valid() or input_allowed.call())


func cancel_touch() -> void:
	var held := _touch_index != -1
	_touch_index = -1
	_touch_inside = false
	_touch_scrolling = false
	if is_instance_valid(_touch_scroll) and int(_touch_scroll.get_meta(SCROLL_OWNER_META, 0)) == get_instance_id():
		_touch_scroll.remove_meta(SCROLL_OWNER_META)
	_touch_scroll = null
	queue_redraw()
	if held:
		button_up.emit()


func _exit_tree() -> void:
	cancel_touch()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		cancel_touch()


func _draw() -> void:
	if _touch_index != -1 and _touch_inside:
		draw_circle(size * 0.5, minf(size.x, size.y) * 0.43, Color(1, 0.92, 0.66, 0.16))
		draw_arc(size * 0.5, minf(size.x, size.y) * 0.47, 0, TAU, 48,
				Color(1, 0.9, 0.55, 0.95), 3)
