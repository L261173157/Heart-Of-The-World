## 怪物血条：受击掉血后显示在头顶的小血条（Node2D 自绘，免场景开销）。
## 由 MonsterBase 在 _ready 时动态挂载；满血与尸体状态不显示。
## 事件驱动重绘：只在宿主 hp/状态变化时收到 notify_change()，
## 不做每帧 queue_redraw（50+ 怪时的全量重绘是纯浪费）。
class_name MonsterHpBar
extends Node2D

## TS 色板合成条框（bake_structures 产线，64×12 原生绘制免缩放）
const FRAME := preload("res://assets/ts/icons/monster_bar.png")
## 框内可用填充区（框 64×12：端帽 3px + 上下边框 2px → 内腔 58×8，居中于 -32,0）
const BAR_INNER_W := 58.0
const BAR_INNER_H := 8.0
const OFFSET_Y := -26.0

var _monster: MonsterBase


func _ready() -> void:
	_monster = get_parent() as MonsterBase
	position.y = OFFSET_Y
	z_index = 20


## 宿主受击/死亡/重置时调用；幂等
func notify_change() -> void:
	# 体型越大血条抬得越高（Boss 2.2× 的血条不再插在身体里；非 Boss 随
	# 物种档位/分裂子代同缩，血条不悬浮在小体型个体头顶半空）
	if _monster != null and _monster.inst != null:
		position.y = OFFSET_Y * clampf(_monster.body_k(), 0.45, 2.6)
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
	# TS 木框暗槽 + 血量填充（残血转 TS 红），框原生尺寸绘制保像素脆度
	draw_texture_rect(FRAME, Rect2(-32.0, -2.0, 64.0, 12.0), false)
	var color := Color(0.86, 0.12, 0.13) if ratio < 0.3 else Color(0.35, 0.8, 0.3)
	draw_rect(Rect2(-BAR_INNER_W * 0.5, 0.0, BAR_INNER_W * ratio, BAR_INNER_H), color)
