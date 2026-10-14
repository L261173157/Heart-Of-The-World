## 原生弹窗先于 _input 消费模拟 mouse-up；取消触摸必须先判定，再交给原生菜单。
## 仅弹窗可见期间接管触屏→鼠标，关闭/退树时恢复全局原设置。
extends Node

signal input_observed(event: InputEvent)

var _popup: PopupMenu
static var _active_popups := 0
static var _emulation_was_enabled := false
var _active := false
var _touch_index := -1
var _touch_origin := Vector2.ZERO
var _dragged := false
var _mouse_down := false

func _ready() -> void:
	_popup = get_parent() as PopupMenu
	_popup.about_to_popup.connect(_opened)
	_popup.popup_hide.connect(_closed)

func _opened() -> void:
	if _active: return
	_active = true
	if _active_popups == 0:
		_emulation_was_enabled = Input.emulate_mouse_from_touch
	_active_popups += 1
	Input.emulate_mouse_from_touch = false
	_touch_index = -1
	_dragged = false

func _closed() -> void:
	var was_active := _active
	_active = false
	_touch_index = -1
	if _mouse_down:
		# 取消时释放桥接的鼠标状态，使用屏外坐标避免向底层控件补发点击。
		_mouse(Vector2(-10000, -10000), false)
	if was_active:
		_active_popups -= 1
		if _active_popups == 0:
			Input.emulate_mouse_from_touch = _emulation_was_enabled

func _exit_tree() -> void:
	_closed()

func _input(event: InputEvent) -> void:
	input_observed.emit(event)
	if not _active: return
	if event is InputEventScreenTouch:
		if event.pressed and not event.canceled and _touch_index == -1:
			_touch_index = event.index
			_touch_origin = event.position
			_dragged = false
			_mouse(event.position, true)
		elif event.index == _touch_index and (not event.pressed or event.canceled):
			_touch_index = -1
			if event.canceled or _dragged:
				_popup.hide()
			else:
				_mouse(event.position, false)
	elif event is InputEventScreenDrag and event.index == _touch_index:
		_dragged = _dragged or event.position.distance_to(_touch_origin) > 10.0

func _mouse(point: Vector2, down: bool) -> void:
	var mouse := InputEventMouseButton.new()
	mouse.device = InputEvent.DEVICE_ID_EMULATION
	_mouse_down = down
	mouse.position = _popup.get_screen_transform() * point
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = down
	# 必须重新走 Window 的原生分发；Viewport.push_input 会跳过 PopupMenu 的选择逻辑。
	Input.parse_input_event(mouse)
