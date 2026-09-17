## 实体落地阴影（纯表现）：椭圆软阴影垫在脚下，消除像素精灵的"贴纸悬浮感"。
## 挂为怪物/玩家身体的子节点（z_index -1，画在身体之下、地面之上）；
## 尺寸随实体缩放由宿主在 setup/_ready 时设置 shadow_scale。
class_name ShadowBlob
extends Node2D

var shadow_scale := Vector2.ONE:
	set(v):
		shadow_scale = v
		queue_redraw()


func _draw() -> void:
	# 椭圆 = 先压扁 y 再画圆；黑色低透明，不抢主体
	draw_set_transform(Vector2.ZERO, 0.0, shadow_scale * Vector2(1.0, 0.42))
	draw_circle(Vector2.ZERO, 6.5, Color(0.0, 0.0, 0.0, 0.30))
