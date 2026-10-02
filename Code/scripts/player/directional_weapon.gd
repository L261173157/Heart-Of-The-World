## 四向武器层：保留 Warrior 身体原画，以同一条刀锋轨迹显示和判定挥击。
## Warrior 没有上下视角；各向使用去剑 Guard 蓄势身体配独立刀剑，不把翻面冒充新帧。
## 刀型/色板来自 TS Warrior：深蓝描边、薄荷钢刃、金护手和蓝握柄。仅程序矢量件。
extends Node2D

var active := false
var aim := Vector2.RIGHT
var blade_angle := 0.0
var blade_reach := 66.0
var trail := PackedVector2Array()
var striking := false
var alpha := 1.0
var gold := false
var combo := 1


func show_swing(direction: Vector2, angle: float, reach: float,
		arc: PackedVector2Array, damaging: bool, opacity: float, empowered: bool,
		step: int) -> void:
	active = true
	visible = true
	aim = direction
	blade_angle = direction.angle() + angle
	blade_reach = reach
	trail = arc
	striking = damaging
	alpha = opacity
	gold = empowered
	combo = step
	# 向上剑在身体后方，向下剑在身体前方；绝不挪动身体/脚点来伪造朝向。
	z_index = -1 if direction.y < -0.35 else 4
	queue_redraw()


func clear() -> void:
	active = false
	visible = false
	trail = PackedVector2Array()
	queue_redraw()


func _draw() -> void:
	if not active:
		return
	var steel := Color("d5edce") if not gold else Color("ffdc83")
	steel.a = alpha
	if trail.size() >= 2 and striking:
		var fan := PackedVector2Array([Vector2.ZERO])
		fan.append_array(trail)
		_fill(fan, Color(steel.r, steel.g, steel.b, 0.10 * alpha))
		draw_polyline(trail, Color(steel.r, steel.g, steel.b, 0.85 * alpha),
			6.0 if combo == 3 else 4.0, false)
		var inner := PackedVector2Array()
		for point in trail:
			inner.append((point * 0.86 / 2.0).round() * 2.0)
		draw_polyline(inner, Color(1.0, 1.0, 0.9, 0.58 * alpha), 2.0, false)
	# 身体中心到 20px 是手臂；实际可见剑刃长 46px，尖端与命中半径完全同源。
	if blade_reach <= 22.0:
		return
	var length := blade_reach
	# 靠墙时只剩短刃，不能把标准肩点放到刀尖之后生成自交多边形。
	if length < 36.0:
		draw_line(_point(Vector2(20, 0)), _point(Vector2(length, 0)), steel, 4.0, false)
		return
	var outline := PackedVector2Array([
		Vector2(20, -5), Vector2(length - 10, -5), Vector2(length, 0),
		Vector2(length - 10, 5), Vector2(20, 5)])
	_fill(_turned(outline), Color(0.16, 0.25, 0.34, alpha))
	var blade := PackedVector2Array([
		Vector2(24, -3), Vector2(length - 10, -3), Vector2(length - 2, 0),
		Vector2(length - 10, 3), Vector2(24, 3)])
	_fill(_turned(blade), steel)
	draw_line(_point(Vector2(25, 0)), _point(Vector2(length - 6, 0)),
		Color(0.44, 0.68, 0.66, alpha), 2.0, false)
	draw_line(_point(Vector2(20, -8)), _point(Vector2(20, 8)),
		Color(0.28, 0.34, 0.35, alpha), 6.0, false)
	draw_line(_point(Vector2(20, -7)), _point(Vector2(20, 7)),
		Color(0.93, 0.75, 0.38, alpha), 3.0, false)
	draw_line(_point(Vector2(12, 0)), _point(Vector2(18, 0)),
		Color(0.25, 0.39, 0.51, alpha), 5.0, false)


func _point(point: Vector2) -> Vector2:
	return (point.rotated(blade_angle) / 2.0).round() * 2.0


func _fill(points: PackedVector2Array, color: Color) -> void:
	# 极小角度/墙角裁切再像素吸附可能重合为线，此时不提交无面积三角形。
	if not Geometry2D.triangulate_polygon(points).is_empty():
		draw_colored_polygon(points, color)


func _turned(points: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in points:
		result.append(_point(point))
	return result
