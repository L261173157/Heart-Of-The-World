## 史莱姆：迟缓的接触伤害体，带果冻脉动表现。
## 核心机制在生态层：被玩家击杀时裂出两只缩小子代（子代不再分裂）——
## 刷得越凶数量越多，但每条血脉的总收益有上限，是"刷怪还是绕行"的博弈。
class_name Slime
extends MonsterBase

var _wobble := 0.0


func _process(delta: float) -> void:
	if state == S_CORPSE or visual == null or inst == null:
		return
	_wobble += delta * 5.0
	var base := sprite_base_scale * maxf(0.45, inst.size_scale)
	# 果冻脉动：横向膨胀时纵向压缩，体积观感守恒
	visual.scale = Vector2(
		base.x * (1.0 + 0.08 * sin(_wobble)),
		base.y * (1.0 - 0.08 * sin(_wobble))
	)
