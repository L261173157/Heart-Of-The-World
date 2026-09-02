## 虚拟摇杆（iOS 触屏 + 桌面鼠标调试双支持）。
## 触点限制在本控件矩形内才响应，输出写入 TouchInput（autoload），
## 玩家控制器从 TouchInput 读取，不与本控件直接耦合。
## 注：Godot 4.7 起引擎自带原生 VirtualJoystick 类，此处避开该名称
class_name TouchJoystick
extends Control

const BASE_RADIUS := 56.0
const KNOB_RADIUS := 24.0
const MAX_STICK := 44.0
## 低于该推动量视为松手（避免抖动漂移）
const DEAD_ZONE := 0.15

## -1 = 空闲；触屏用触摸索引；鼠标调试用 -2
var _touch_index := -1
var _knob_offset := Vector2.ZERO


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed and _touch_index == -1 and _contains(touch.position):
			_touch_index = touch.index
			_update_stick(touch.position)
		elif not touch.pressed and touch.index == _touch_index:
			_release()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _touch_index:
			_update_stick(drag.position)
	elif event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index != MOUSE_BUTTON_LEFT:
			return
		if mouse.pressed and _touch_index == -1 and _contains(mouse.position):
			_touch_index = -2
			_update_stick(mouse.position)
		elif not mouse.pressed and _touch_index == -2:
			_release()
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _touch_index == -2 and (motion.button_mask & MOUSE_BUTTON_MASK_LEFT):
			_update_stick(motion.position)


func _contains(screen_pos: Vector2) -> bool:
	return get_global_rect().has_point(screen_pos)


func _update_stick(screen_pos: Vector2) -> void:
	var local := screen_pos - get_global_rect().get_center()
	_knob_offset = local.limit_length(MAX_STICK)
	var mag := _knob_offset.length() / MAX_STICK
	TouchInput.move_vector = _knob_offset / MAX_STICK
	TouchInput.joystick_active = mag > DEAD_ZONE
	queue_redraw()


func _release() -> void:
	_touch_index = -1
	_knob_offset = Vector2.ZERO
	TouchInput.move_vector = Vector2.ZERO
	TouchInput.joystick_active = false
	queue_redraw()


func _draw() -> void:
	var center := size / 2.0
	draw_circle(center, BASE_RADIUS, Color(1, 1, 1, 0.08))
	draw_arc(center, BASE_RADIUS, 0.0, TAU, 40, Color(1, 1, 1, 0.35), 2.0)
	draw_circle(center + _knob_offset, KNOB_RADIUS, Color(1, 1, 1, 0.5))
