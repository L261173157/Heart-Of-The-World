## 技能预备只绘制少量低透明几何；既有重击爆裂/法弹资源仍负责真实释放。
## 与身体同节点生命周期，暂停/取消立即清理，不新增逐帧分配特效节点。
extends Node2D

var _kind := ""
var _phase := ""
var _direction := Vector2.RIGHT
var _progress := 0.0


func show_action(kind: String, phase: String, direction: Vector2, progress: float) -> void:
	_kind = kind
	_phase = phase
	_direction = direction
	_progress = progress
	visible = true
	z_index = -1 if kind == "heavy" else 5
	queue_redraw()


func clear() -> void:
	_kind = ""
	visible = false
	queue_redraw()


func _draw() -> void:
	if _phase != "windup" or _kind.is_empty():
		return
	if _kind == "heavy":
		# 逐渐聚拢的短弧只提示蓄势，不伪装为已经命中的冲击波。
		var radius := lerpf(34.0, 20.0, _progress)
		var color := Color(1.0, 0.82, 0.40, 0.22 + _progress * 0.3)
		for index in 4:
			var angle := index * TAU / 4.0
			draw_arc(Vector2(0, 13), radius, angle, angle + 0.75, 5, color, 2.0)
	else:
		var origin := (_direction * 22.0).round()
		var radius := lerpf(2.0, 7.0, _progress)
		draw_circle(origin, radius + 3.0, Color(0.37, 0.68, 1.0, 0.18))
		draw_circle(origin, radius, Color(0.55, 0.83, 1.0, 0.7))
		draw_circle(origin, maxf(1.0, radius * 0.45), Color(0.93, 0.98, 1.0, 0.95))
