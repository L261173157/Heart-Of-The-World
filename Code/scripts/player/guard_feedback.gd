## 盾由原画 Guard 姿势持握；这里只画脚下防御方向、蓄力和接盾/破防反馈。
## 不旋转整个身体，也不画与手臂脱节的第二面盾。
extends Node2D

var state := "idle"
var direction := Vector2.RIGHT
var charge := 0
var feet_y := 0.0
var body_y := 0.0
var head_y := -40.0
var _pulse := 0.0
var _impact := 0.0
var _broken := false


func show_state(p_state: String, p_direction: Vector2, p_charge: int) -> void:
	state = p_state
	direction = p_direction
	charge = p_charge
	visible = state != "idle" or _impact > 0.0
	queue_redraw()


func impact(broken: bool) -> void:
	_broken = broken
	_impact = 1.0
	visible = true
	queue_redraw()


func clear() -> void:
	state = "idle"
	charge = 0
	_impact = 0.0
	visible = false
	queue_redraw()


func _process(delta: float) -> void:
	_pulse += delta * 5.0
	if _impact > 0.0:
		_impact = maxf(0.0, _impact - delta * 4.0)
	visible = state != "idle" or _impact > 0.0
	if visible:
		queue_redraw()


func _draw() -> void:
	var center := Vector2(0.0, feet_y)
	var angle := direction.angle()
	var color := Color("96dfee")
	if state == "broken":
		color = Color("ff765b")
	elif charge > 0 or state == "counter":
		color = Color("ffdc83")
	if state == "raising" or state == "guarding":
		var alpha := 0.45 if state == "raising" else 0.9
		draw_arc(center, 28.0, angle - CharacterStats.GUARD_HALF_ARC,
			angle + CharacterStats.GUARD_HALF_ARC, 18, Color(color, alpha), 3.0, true)
		var tip := center + direction * 32.0
		draw_circle(tip, 2.5, Color(color, alpha))
	for i in CharacterStats.GUARD_MAX_CHARGE:
		var pos := Vector2((i - 1) * 9.0, head_y)
		draw_circle(pos, 3.5, Color("242936"))
		if i < charge:
			draw_circle(pos, 2.4 + sin(_pulse) * 0.35, Color("ffdc83"))
		elif state == "raising" or state == "guarding":
			draw_arc(pos, 2.5, 0.0, TAU, 10, Color(0.8, 0.9, 1.0, 0.35), 1.0)
	if _impact > 0.0:
		var spark_center := Vector2(0.0, body_y - 2.0) + direction * 20.0
		var spark_color := Color("ff765b") if _broken else Color("fff5c4")
		spark_color.a = _impact
		for i in 5:
			var ray := direction.rotated((i - 2) * 0.5)
			draw_line(spark_center + ray * 3.0,
				spark_center + ray * (8.0 + 8.0 * (1.0 - _impact)), spark_color, 2.0)
		if _broken:
			draw_line(spark_center + Vector2(-8, -10), spark_center + Vector2(8, 6), spark_color, 3.0)
			draw_line(spark_center + Vector2(-8, 6), spark_center + Vector2(8, -10), spark_color, 3.0)
