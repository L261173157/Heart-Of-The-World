## 一次性工具：从 na_tileset 抠建筑候选块拼对照板（3列×3行，块间留白）。
## 块序（从左到右、从上到下）：A 房1 B 房2 C 房3 / D 鸟居 E 招牌 F 城墙 /
## G 城塔 H 地牢砖 I 宝箱探针。输出 /tmp/na_stamps_board.png
extends SceneTree


func _init() -> void:
	var src := Image.load_from_file(ProjectSettings.globalize_path(
		"res://assets/creatures/sheets/na_tileset.png"))
	var candidates := {
		"A_house1": Rect2i(0, 0, 80, 64),
		"B_house2": Rect2i(96, 0, 80, 64),
		"C_house3": Rect2i(192, 0, 80, 64),
		"D_torii": Rect2i(352, 32, 96, 64),
		"E_dojo": Rect2i(288, 48, 64, 64),
		"F_castle": Rect2i(0, 80, 96, 64),
		"G_tower": Rect2i(288, 48, 160, 64),
		"H_dungeon": Rect2i(0, 144, 96, 48),
		"I_chest": Rect2i(0, 176, 32, 32),
	}
	var keys := candidates.keys()
	keys.sort()
	var cell_w := 200
	var cell_h := 150
	var img := Image.create(cell_w * 3, cell_h * 3, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.1, 0.3, 0.15, 1.0))
	for i in range(keys.size()):
		var crop := src.get_region(candidates[keys[i]])
		crop.resize(crop.get_width() * 2, crop.get_height() * 2, Image.INTERPOLATE_NEAREST)
		var cx := (i % 3) * cell_w + (cell_w - crop.get_width()) / 2
		var cy := (i / 3) * cell_h + (cell_h - crop.get_height()) / 2
		img.blend_rect(crop, Rect2i(Vector2i.ZERO, crop.get_size()), Vector2i(cx, cy))
	img.save_png("/tmp/na_stamps_board.png")
	print("saved /tmp/na_stamps_board.png")
	quit(0)
