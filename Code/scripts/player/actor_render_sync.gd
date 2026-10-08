## 物理身体仍按固定步推进；只向渲染服务器提交两次物理快照之间的平移。
## 不改 Node2D.transform，所以碰撞、导航、技能原点和下一物理步绝不读回绘制结果。
## 同一个根画布承载精灵、武器、阴影与血条，避免各自插值造成脱节。
extends Node

const TELEPORT_DISTANCE := 96.0
var _body: Node2D
var _previous := Vector2.ZERO
var _current := Vector2.ZERO
var _render_position := Vector2.ZERO
var render_shift := Vector2.ZERO
var _initialized := false

func _ready() -> void:
	name = "RenderSync"
	_body = get_parent() as Node2D
	# 普通角色/AI 的物理移动结束后采样；表现更新结束后再统一提交画布。
	process_physics_priority = 100
	process_priority = 100
	reset()

func reset() -> void:
	if _body == null:
		return
	_current = _body.global_position
	_previous = _current
	_render_position = _current
	render_shift = Vector2.ZERO
	_initialized = true
	RenderingServer.canvas_item_set_transform(_body.get_canvas_item(), _body.transform)

func _physics_process(_delta: float) -> void:
	if not _initialized:
		reset()
	_previous = _current
	_current = _body.global_position
	if _previous.distance_to(_current) > TELEPORT_DISTANCE:
		_previous = _current

func get_render_position() -> Vector2:
	return _render_position

func _process(_delta: float) -> void:
	# RVO 回调可能晚于普通物理通知；传送也可能发生在 idle 回调中。
	if _current != _body.global_position:
		_current = _body.global_position
		if _previous.distance_to(_current) > TELEPORT_DISTANCE:
			_previous = _current
	_render_position = _previous.lerp(_current, Engine.get_physics_interpolation_fraction())
	# Visual 已从身体与固定锚点吸附；只加整数世界位移，保留现有像素网格。
	# 不累计上帧画布变换，也不把身体取整，长距离行走不会出现物理漂移。
	render_shift = _render_position.round() - _current.round()
	var shift := render_shift
	var parent := _body.get_parent() as Node2D
	if parent != null:
		shift = parent.global_transform.basis_xform_inv(shift)
	var drawn := _body.transform
	drawn.origin += shift
	RenderingServer.canvas_item_set_transform(_body.get_canvas_item(), drawn)

func _exit_tree() -> void:
	# 单独移除表现组件也要撤销最后一次提交，身体逻辑位置始终没被改动。
	if is_instance_valid(_body):
		RenderingServer.canvas_item_set_transform(_body.get_canvas_item(), _body.transform)
