## 玩家头顶定位标记：zoom1 广角视野下绿衣忍者与草地同色相，
## 战斗中"跟丢自己"——头顶一枚下指小箭头（金色 + 暗色勾边，与 UI
## 金色语言同源），上下缓浮提供动势。纯表现，不参与任何逻辑。
class_name PlayerMarker
extends Node2D

const FLOAT_AMP := 3.0
const FLOAT_SPEED := 3.0
const BASE_Y := -56.0

var _time := 0.0


func _ready() -> void:
	z_index = 20
	_redraw()


func _process(delta: float) -> void:
	_time += delta
	_redraw()


func _redraw() -> void:
	queue_redraw()


func _draw() -> void:
	var y := BASE_Y + sin(_time * FLOAT_SPEED) * FLOAT_AMP
	# 暗色勾边在下、金色面在上：草地/雪地等亮背景上仍读得出轮廓
	var outline := PackedVector2Array([
		Vector2(-8, y), Vector2(8, y), Vector2(0, y + 11),
	])
	draw_colored_polygon(outline, Color(0.05, 0.06, 0.08, 0.65))
	var face := PackedVector2Array([
		Vector2(-6, y), Vector2(6, y), Vector2(0, y + 9),
	])
	draw_colored_polygon(face, Color(1.0, 0.85, 0.45, 0.9))
