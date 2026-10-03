## 方向武器只负责刀剑和拖尾；身体继续播放 TS Warrior 原生 Attack1/2。
## 握点跟随原画手部，66px 是挥击弧外缘，不把整段半径画成僵直长剑。
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
var grip := Vector2.ZERO
var skin := "blue"
var windup := false
var blade_tip := Vector2.ZERO


func show_swing(direction: Vector2, angle: float, reach: float,
		arc: PackedVector2Array, damaging: bool, opacity: float, empowered: bool,
		step: int, hand := Vector2.ZERO, hero_skin := "blue", preparing := false) -> void:
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
	grip = hand
	skin = hero_skin
	windup = preparing
	blade_tip = desired_tip()
	# 上挥时武器位于身体后，下挥位于身前；身体本身不旋转、不挪脚点。
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
	var steel := Color("d4edc2")
	var shade := Color("9cbeaa")
	if skin == "dark":
		steel = Color("b8c1c3")
		shade = Color("8c9695")
	elif skin == "white":
		steel = Color("fffaba")
		shade = Color("d5cc45")
	if gold:
		steel = Color("ffdc83")
		shade = Color("c8a876")
	# 细线圆环改为有头有尾的弯月。外缘仍直接消费实际扫掠/墙体裁切采样；
	# 收招保留短暂消散，不再在判定关闭的同帧突然抹去整条刀光。
	if trail.size() >= 2:
		_ribbon(shade, 1.0, 0.70)
		_ribbon(steel, 0.76, 0.94)
		_ribbon(Color("ffffff"), 0.38, 0.94)
	if blade_reach <= maxf(10.0, grip.length() + 8.0):
		return
	# 刀尖朝向世界扫掠前沿，握柄锚在当前原画手部。刀本身比弧光短，
	# 避免将源画的66px光效边界错误当作恒长金属剑。
	var tip := blade_tip
	var axis := (tip - grip).normalized()
	var length := tip.distance_to(grip)
	if length < 14.0:
		return
	var edge := Vector2(-axis.y, axis.x)
	var guard := grip + axis * 5.0
	var shoulder := grip + axis * 10.0
	var near_tip := tip - axis * minf(8.0, length * 0.22)
	_fill(_snapped([guard - edge * 4, near_tip - edge * 4, tip,
		near_tip + edge * 4, guard + edge * 4]), _alpha(Color("161c2e")))
	_fill(_snapped([shoulder - edge * 2, near_tip - edge * 2,
		tip - axis * 2, near_tip + edge * 2, shoulder + edge * 2]), _alpha(steel))
	draw_line(_snap(shoulder), _snap(tip - axis * 5), _alpha(shade), 2.0, false)
	draw_line(_snap(guard - edge * 7), _snap(guard + edge * 7),
		_alpha(Color("161c2e")), 6.0, false)
	draw_line(_snap(guard - edge * 6), _snap(guard + edge * 6),
		_alpha(Color("c8a876")), 2.0, false)
	draw_line(_snap(grip - axis * 3), _snap(guard - axis * 2),
		_alpha(Color("161c2e")), 5.0, false)


## 输出未裁切的实际握点→刀尖；Player 用这一线段的10px包络做墙体扫掠。
func desired_tip() -> Vector2:
	var tip := Vector2.from_angle(blade_angle) * minf(blade_reach, 50.0)
	if windup:
		tip = grip + Vector2.from_angle(blade_angle) * 30.0
		if tip.length() > blade_reach:
			tip = tip.normalized() * blade_reach
	return tip


func _ribbon(color: Color, width_scale: float, opacity: float) -> void:
	var polygon := PackedVector2Array()
	var inner := PackedVector2Array()
	var opening := clampf(trail[0].distance_to(trail[trail.size() - 1]) / 36.0, 0.0, 1.0)
	for index in trail.size():
		var point := trail[index]
		var t := float(index) / float(trail.size() - 1)
		# 尾部尖、中央宽、前缘略收；厚度受实际半径约束，墙边不会反向翻面。
		var taper := sin(PI * t) * (0.55 + 0.45 * t)
		var width := minf(26.0 if combo == 3 else 22.0, point.length() * 0.40)
		polygon.append(point)
		inner.append(_snap(point.normalized() * maxf(0.0,
			point.length() - width * taper * width_scale * opening)))
	inner.reverse()
	polygon.append_array(inner)
	color.a = opacity * alpha
	_fill(polygon, color)


func _alpha(color: Color) -> Color:
	color.a = alpha
	return color


func _snap(point: Vector2) -> Vector2:
	return (point / 2.0).round() * 2.0


func _snapped(points: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point: Vector2 in points:
		result.append(_snap(point))
	return result


func _fill(points: PackedVector2Array, color: Color) -> void:
	# 墙角裁切再像素吸附可重合为线，此时不提交无面积三角形。
	if not Geometry2D.triangulate_polygon(points).is_empty():
		draw_colored_polygon(points, color)
