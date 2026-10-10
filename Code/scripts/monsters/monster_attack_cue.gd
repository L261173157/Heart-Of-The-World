## 朝向预警只在起手重绘一次：近战扇区与直线射向来自真实锁定方向。
## 不创建每帧特效、不参与碰撞；伤害仍由角色本体及弹体权威判定。
extends Node2D

var _direction := Vector2.RIGHT
var _reach := 0.0
var _half_angle := 0.0


func show_sector(direction: Vector2, reach: float, half_angle: float) -> void:
	_direction = direction.normalized()
	_reach = reach
	_half_angle = half_angle
	visible = true
	queue_redraw()


func show_line(direction: Vector2, reach: float) -> void:
	show_sector(direction, reach, 0.0)


func _draw() -> void:
	var color := Color(1.0, 0.65, 0.25, 0.75)
	if _half_angle <= 0.0:
		var end := _direction * _reach
		draw_line(_direction * 14.0, end, color, 2.0)
		draw_line(end, end - _direction.rotated(0.5) * 12.0, color, 2.0)
		draw_line(end, end - _direction.rotated(-0.5) * 12.0, color, 2.0)
		return
	var start := _direction.angle() - _half_angle
	var finish := _direction.angle() + _half_angle
	var points := PackedVector2Array([Vector2.ZERO])
	for i in 17:
		points.append(Vector2.from_angle(lerpf(start, finish, i / 16.0)) * _reach)
	draw_colored_polygon(points, Color(1.0, 0.55, 0.2, 0.12))
	draw_arc(Vector2.ZERO, _reach, start, finish, 16, color, 2.0)
	draw_line(Vector2.ZERO, points[1], color, 1.0)
	draw_line(Vector2.ZERO, points[points.size() - 1], color, 1.0)
