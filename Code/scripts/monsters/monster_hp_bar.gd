## 怪物血条：受击掉血后显示在头顶的小血条（Node2D 自绘，免场景开销）。
## 由 MonsterBase 在 _ready 时动态挂载；满血与尸体状态不显示。
## 事件驱动重绘：只在宿主 hp/状态变化时收到 notify_change()，
## 不做每帧 queue_redraw（50+ 怪时的全量重绘是纯浪费）。
class_name MonsterHpBar
extends Node2D

const BAR_WIDTH := 28.0
const BAR_HEIGHT := 4.0
const OFFSET_Y := -26.0

var _monster: MonsterBase


func _ready() -> void:
	_monster = get_parent() as MonsterBase
	position.y = OFFSET_Y
	z_index = 20


## 宿主受击/死亡/重置时调用；幂等
func notify_change() -> void:
	# 体型越大血条抬得越高（Boss 2.2× 的血条不再插在身体里）
	if _monster != null and _monster.inst != null:
		position.y = OFFSET_Y * clampf(_monster.inst.size_scale, 0.45, 2.6)
	queue_redraw()


func _draw() -> void:
	if _monster == null or _monster.inst == null:
		return
	if _monster.state == MonsterBase.S_CORPSE:
		return
	var max_hp := _monster.inst.max_hp()
	if max_hp <= 0.0:
		return
	var ratio: float = clampf(_monster.current_hp / max_hp, 0.0, 1.0)
	if ratio >= 0.999:
		return
	draw_rect(Rect2(-BAR_WIDTH * 0.5, 0.0, BAR_WIDTH, BAR_HEIGHT), Color(0, 0, 0, 0.6))
	var color := Color(0.9, 0.25, 0.2) if ratio < 0.3 else Color(0.35, 0.8, 0.3)
	draw_rect(Rect2(-BAR_WIDTH * 0.5 + 1.0, 1.0, (BAR_WIDTH - 2.0) * ratio, BAR_HEIGHT - 2.0), color)
