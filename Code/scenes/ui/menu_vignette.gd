## 主菜单的小型场景：仅消费 Tiny Swords 免费包，不加载世界或改变模拟状态。
## 坐标按 600×320 设计；整幅等比缩放，像素素材保持最近邻采样。
extends Control

const KNIGHT := preload("res://assets/ts/Units/Blue Units/Warrior/Warrior_Idle.png")
const TREE := preload("res://assets/ts/Terrain/Resources/Wood/Trees/Tree1.png")
const CASTLE := preload("res://assets/ts/Buildings/Blue Buildings/Castle.png")
const CLOUD := preload("res://assets/ts/Terrain/Decorations/Clouds/Clouds_04.png")
var _clock := 0.0
var _frame := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	resized.connect(queue_redraw)


func _process(delta: float) -> void:
	_clock += delta
	var next_frame := int(_clock * 6.0) % 8
	if next_frame != _frame:
		_frame = next_frame
		queue_redraw()


func _draw() -> void:
	var factor := minf(size.x / 600.0, size.y / 320.0)
	draw_set_transform(Vector2((size.x - 600.0 * factor) * 0.5, 0), 0, Vector2.ONE * factor)
	# 克制的阶梯月轮与山脊，给实际角色素材留出清楚的剪影区。
	var moon := Color("263b43")
	draw_rect(Rect2(224, 24, 136, 174), moon)
	draw_rect(Rect2(198, 48, 188, 126), moon)
	draw_rect(Rect2(210, 34, 164, 152), moon)
	draw_rect(Rect2(238, 17, 108, 188), moon)
	var far_ridge := PackedVector2Array([
		Vector2(24, 236), Vector2(24, 184), Vector2(70, 184), Vector2(70, 166),
		Vector2(110, 166), Vector2(110, 142), Vector2(152, 142), Vector2(152, 174),
		Vector2(208, 174), Vector2(208, 194), Vector2(282, 194), Vector2(282, 172),
		Vector2(328, 172), Vector2(328, 150), Vector2(370, 150), Vector2(370, 162),
		Vector2(424, 162), Vector2(424, 180), Vector2(476, 180), Vector2(476, 200),
		Vector2(560, 200), Vector2(560, 236)])
	draw_colored_polygon(far_ridge, Color("1c3038"))
	draw_texture_rect_region(CLOUD, Rect2(104, 58, 127, 68), Rect2(234, 115, 106, 57), Color(0.65, 0.76, 0.78, 0.18))
	draw_texture_rect_region(CLOUD, Rect2(368, 28, 106, 57), Rect2(234, 115, 106, 57), Color(0.65, 0.76, 0.78, 0.14))
	# 远处城堡与两层树木，真实素材按景深退色。
	draw_texture_rect(CASTLE, Rect2(340, 74, 176, 141), false, Color(0.50, 0.64, 0.64, 0.7))
	draw_texture_rect_region(TREE, Rect2(84, 90, 134, 179), Rect2(0, 0, 192, 256), Color("567d77"))
	draw_texture_rect_region(TREE, Rect2(404, 111, 115, 154), Rect2(0, 0, 192, 256), Color("466966"))
	# 舞台前缘使用硬像素轮廓，避免平铺地表缩成高频噪点。
	draw_colored_polygon(PackedVector2Array([
		Vector2(56, 244), Vector2(108, 226), Vector2(186, 220), Vector2(186, 216),
		Vector2(364, 216), Vector2(364, 221), Vector2(468, 228), Vector2(552, 250),
		Vector2(552, 265), Vector2(508, 281), Vector2(408, 292), Vector2(178, 292),
		Vector2(94, 282), Vector2(56, 268)]), Color("172b30"))
	draw_colored_polygon(PackedVector2Array([
		Vector2(88, 246), Vector2(150, 230), Vector2(220, 226), Vector2(362, 225),
		Vector2(457, 233), Vector2(522, 249), Vector2(466, 264), Vector2(174, 269)]), Color("314744"))
	draw_colored_polygon(PackedVector2Array([
		Vector2(335, 228), Vector2(352, 228), Vector2(329, 240), Vector2(310, 240),
		Vector2(304, 251), Vector2(325, 268), Vector2(276, 268), Vector2(273, 252),
		Vector2(292, 238)]), Color("6c6b50"))
	# 主角沿用游戏中的蓝骑士：八帧待机原画，成倍放大而非拉宽。
	draw_texture_rect_region(KNIGHT, Rect2(62, -78, 480, 480), Rect2(_frame * 192, 0, 192, 192))
	# 少量前景草簇与暖色萤火，保留安静而有生命的气氛。
	for pos: Vector2 in [Vector2(145, 249), Vector2(400, 257), Vector2(453, 244)]:
		draw_rect(Rect2(pos, Vector2(3, 9)), Color("69876e"))
		draw_rect(Rect2(pos + Vector2(-5, 3), Vector2(3, 5)), Color("557666"))
		draw_rect(Rect2(pos + Vector2(5, 2), Vector2(3, 7)), Color("557666"))
	for pos: Vector2 in [Vector2(202, 124), Vector2(387, 188), Vector2(440, 84), Vector2(115, 207)]:
		draw_rect(Rect2(pos, Vector2(3, 3)), Color(0.89, 0.77, 0.44, 0.65 + sin(_clock + pos.x) * 0.18))
