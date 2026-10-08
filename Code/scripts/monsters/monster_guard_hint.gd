## 出招头顶盾形预警。只在前摇开始/结束时重绘，数值分档由 CharacterStats 决定。
## 不把 Boss 标签当成不可挡：提示只消费正在发生的那一招。
extends Node2D

var _shield := PackedVector2Array([
	Vector2(-10, -10), Vector2(0, -13), Vector2(10, -10),
	Vector2(9, 2), Vector2(5, 9), Vector2(0, 13),
	Vector2(-5, 9), Vector2(-9, 2), Vector2(-10, -10),
])
const INK := Color(0.07, 0.10, 0.16, 0.97)

var warning := "normal"
var strength := 0.0
var blockable := true
var _actor_offset := Vector2.ZERO


func _init() -> void:
	name = "GuardHint"
	# 脱离宿主的闪红/精英金色调制，黄色危险级别不会被蓄力橙染成另一档。
	# 仍由宿主拥有并清理，只在短暂前摇期间跟随宿主平移，不逐帧重绘。
	top_level = true
	process_priority = 150
	z_index = 30
	visible = false
	set_process(false)


func show_attack(stats: CharacterStats, p_strength: float, p_blockable: bool,
		actor_offset: Vector2) -> void:
	strength = p_strength
	blockable = p_blockable
	warning = stats.guard_warning(strength, blockable) if stats != null else \
			("normal" if blockable else "unblockable")
	_actor_offset = actor_offset.round()
	_follow_actor()
	show()
	set_process(true)
	queue_redraw()


func clear() -> void:
	hide()
	set_process(false)


func _process(_delta: float) -> void:
	_follow_actor()


func _follow_actor() -> void:
	var actor := get_parent() as Node2D
	if actor != null:
		var point := actor.global_position
		var sync := actor.get_node_or_null("RenderSync")
		if sync != null:
			point = sync.get_render_position()
		global_position = (point + _actor_offset).round()


func _draw() -> void:
	var tint := Color(0.81, 0.88, 0.94)
	match warning:
		"near":
			tint = Color(1.0, 0.87, 0.24)
		"break":
			tint = Color(1.0, 0.24, 0.20)
		"unblockable":
			tint = Color(1.0, 0.50, 0.30)
	draw_colored_polygon(_shield, INK)
	draw_polyline(_shield, INK, 6.0)
	draw_polyline(_shield, tint, 2.5)
	match warning:
		"break":
			# 裂纹保留形状差异，红绿色觉差异也能读到危险。
			draw_polyline(PackedVector2Array([
				Vector2(2, -10), Vector2(-3, -3), Vector2(3, 0),
				Vector2(-2, 6), Vector2(0, 10),
			]), tint, 3.0)
		"unblockable":
			draw_line(Vector2(-8, -8), Vector2(8, 8), tint, 3.0)
			draw_line(Vector2(8, -8), Vector2(-8, 8), tint, 3.0)
		_:
			draw_line(Vector2.ZERO, Vector2(0, -6), tint, 3.0)
			draw_circle(Vector2(0, 5), 1.6, tint)
