## 红史莱姆：迟缓的接触伤害体，带果冻脉动表现。
## 核心机制在生态层：被玩家击杀时裂出两只缩小子代（子代不再分裂）——
## 刷得越凶数量越多，但每条血脉的总收益有上限，是"刷怪还是绕行"的博弈。
class_name Slime
extends MonsterBase

var _wobble := 0.0


func _process(delta: float) -> void:
	if state == S_CORPSE or visual == null or inst == null:
		return
	_wobble += delta * 5.0
	# 果冻脉动（像素安全版，2026-09-20 原生直出改造）：整数缩放档间无连续档位
	# （2↔3 = ±50% 跳变），持续非整数 scale = 像素行宽窄交替（bef0f03 同源病灶，
	# 本种是当时唯一漏网的持续非整数写入）；软体感改由 ±1 帧素横向摇摆承载——
	# offset 以帧素为单位、×整数缩放后仍是整数世界位移，scale 恒为 _apply_size_visual
	# 的取整值。纵向留给基类行走的 bob（同为整数），纵横错相即"果冻"
	var sway := roundf(sin(_wobble) * 1.2)
	if visual.offset.x != sway:
		visual.offset = Vector2(sway, visual.offset.y)
