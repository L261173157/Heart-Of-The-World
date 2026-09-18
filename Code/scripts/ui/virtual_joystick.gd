## 虚拟摇杆（iOS 触屏 + 桌面鼠标调试双支持）。
## 浮动摇杆：左下激活区（左 45% 屏宽、顶部 35% 状态条带之下）任意位置按下
## 即起摇、基准圆浮到触点处，松手回位到默认待命位（半透明提示）。
## 固定区域式（触点必须落进控件矩形）在快节奏战斗中"拇指第一触偏出就完全
## 没反应"，是触屏 ACT 的核心手感差评点。输出写入 TouchInput（autoload），
## 玩家控制器从 TouchInput 读取，不与本控件直接耦合。
## 注：Godot 4.7 起引擎自带原生 VirtualJoystick 类，此处避开该名称
class_name TouchJoystick
extends Control

## iOS 横屏画布（720 高 ≈390pt）上拇指可及的尺寸：底盘直径 128px ≈70pt，
## 手柄与行程随动；桌面上同比例略大，可接受
const BASE_RADIUS := 64.0
const KNOB_RADIUS := 28.0
const MAX_STICK := 50.0
## 激活阈值：超过该推动量摇杆才生效（防误触）
const DEAD_ZONE := 0.15
## 释放阈值低于激活阈值形成滞回：推动量在临界附近抖动时
## 不会反复翻转 joystick_active（速度 0↔部分 抽动）
const RELEASE_ZONE := 0.10
## 浮动起摇区：左 45% 屏宽、顶部 35% 之下（血条/属性按钮带不起摇）
const ZONE_W_FRAC := 0.45
const ZONE_TOP_FRAC := 0.35

## -1 = 空闲；触屏用触摸索引；鼠标调试用 -2
var _touch_index := -1
var _knob_offset := Vector2.ZERO
## 浮动基准圆心（画布坐标）；Vector2.INF = 未起摇，画在默认待命位
var _float_center := Vector2.INF


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed and _touch_index == -1 and _in_activation_zone(touch.position):
			_touch_index = touch.index
			_float_center = touch.position
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
		if mouse.pressed and _touch_index == -1 and _in_activation_zone(mouse.position):
			_touch_index = -2
			_float_center = mouse.position
			_update_stick(mouse.position)
		elif not mouse.pressed and _touch_index == -2:
			_release()
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _touch_index == -2 and (motion.button_mask & MOUSE_BUTTON_MASK_LEFT):
			_update_stick(motion.position)


## 起摇判定：落在左下激活区，且未命中其它可交互控件（按钮/弹层）——
## _input 先于 GUI 派发，命中按钮的触摸不能同时把摇杆拽走
func _in_activation_zone(screen_pos: Vector2) -> bool:
	var vp := get_viewport_rect().size
	if screen_pos.x > vp.x * ZONE_W_FRAC or screen_pos.y < vp.y * ZONE_TOP_FRAC:
		return false
	for child in get_parent().get_children():
		if child == self or not child is Control:
			continue
		var ctrl := child as Control
		if not ctrl.is_visible_in_tree() or ctrl.mouse_filter == Control.MOUSE_FILTER_IGNORE:
			continue
		if ctrl.get_global_rect().has_point(screen_pos):
			return false
	return true


func _update_stick(screen_pos: Vector2) -> void:
	var center := _float_center if _float_center != Vector2.INF else get_global_rect().get_center()
	_knob_offset = (screen_pos - center).limit_length(MAX_STICK)
	var mag := _knob_offset.length() / MAX_STICK
	# 滞回：已激活时降到 RELEASE_ZONE 才失活，未激活时要超过 DEAD_ZONE 才激活
	if TouchInput.joystick_active:
		TouchInput.joystick_active = mag > RELEASE_ZONE
	else:
		TouchInput.joystick_active = mag > DEAD_ZONE
	TouchInput.move_vector = _knob_offset / MAX_STICK
	queue_redraw()


func _release() -> void:
	_touch_index = -1
	_knob_offset = Vector2.ZERO
	_float_center = Vector2.INF
	TouchInput.move_vector = Vector2.ZERO
	TouchInput.joystick_active = false
	queue_redraw()


## 与 TouchInput 的全局兜底配对：这里还必须清本控件持有的触点索引，
## 否则恢复后 _touch_index 仍非 -1，新的拇指触摸会被当成“已有触点”而拒绝。
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_release()


func _draw() -> void:
	# 待命位压暗（0.8）、起摇位全亮：视线能立刻找到"活着的"基准圆，
	# 但待命位在亮地面上仍要可辨（压太暗等于摇杆消失）。
	# 视觉与全 UI 统一：金色基准环 + 四向刻度 + 白芯描边摇杆头
	# 注：to_local() 是 Node2D 的方法，Control 需用全局变换的逆手动换算
	var center: Vector2
	var base_alpha := 1.0
	if _float_center != Vector2.INF:
		center = get_global_transform().affine_inverse() * _float_center
	else:
		center = size / 2.0
		base_alpha = 0.8
	var gold := Color(1.0, 0.85, 0.45, 0.75 * base_alpha)
	draw_circle(center, BASE_RADIUS, Color(0.05, 0.06, 0.08, 0.35 * base_alpha))
	draw_arc(center, BASE_RADIUS, 0.0, TAU, 48, gold, 2.5)
	# 四向刻度：拇指盲操作时给出方向锚点
	for dir: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		var tick_from: Vector2 = center + dir * (BASE_RADIUS - 12.0)
		draw_line(tick_from, center + dir * (BASE_RADIUS - 5.0),
				Color(1, 1, 1, 0.45 * base_alpha), 2.0)
	var knob := center + _knob_offset
	draw_circle(knob, KNOB_RADIUS + 2.0, Color(0.05, 0.06, 0.08, 0.9))
	draw_circle(knob, KNOB_RADIUS, Color(0.95, 0.92, 0.82, 0.92))
	draw_arc(knob, KNOB_RADIUS - 3.0, 0.0, TAU, 32,
			Color(1.0, 0.85, 0.45, 0.55 * base_alpha), 1.5)
