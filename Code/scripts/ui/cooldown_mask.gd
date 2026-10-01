## 圆形冷却扫罩，始终落在按钮内，不再用黑方块遮住圆钮边框。
extends Control

var fraction := 1.0:
	set(value):
		var next := clampf(value, 0.0, 1.0)
		if not is_equal_approx(next, fraction):
			fraction = next
			queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5
	if fraction <= 0.0:
		return
	if fraction >= 0.999:
		draw_circle(center, radius, Color(0.04, 0.07, 0.10, 0.62))
		return
	var points := PackedVector2Array([center])
	var segments := maxi(2, ceili(48.0 * fraction))
	for i in segments + 1:
		var angle := -PI * 0.5 + TAU * fraction * float(i) / float(segments)
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	draw_colored_polygon(points, Color(0.04, 0.07, 0.10, 0.66))
