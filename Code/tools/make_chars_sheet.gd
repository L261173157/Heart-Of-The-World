## 一次性工具：拼 NA characters 对照表（5列×6行，格 96×168）
## 编号按位置：第 r 行第 c 列 = (r-1)*5+c。输出 /tmp/na_chars_sheet.png
extends SceneTree


func _init() -> void:
	var cols := 5
	var cell := Vector2i(96, 168)
	var img := Image.create(cols * cell.x, 6 * cell.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.16, 0.16, 0.2, 1.0))
	for i in range(1, 26):
		var src := Image.load_from_file(ProjectSettings.globalize_path(
			"res://assets/na/characters/%d.png" % i))
		if src == null:
			continue
		src.resize(cell.x, cell.y, Image.INTERPOLATE_NEAREST)
		var cx := (i - 1) % cols
		var cy := (i - 1) / cols
		img.blend_rect(src, Rect2i(Vector2i.ZERO, cell),
			Vector2i(cx * cell.x, cy * cell.y))
	img.save_png("/tmp/na_chars_sheet.png")
	print("saved /tmp/na_chars_sheet.png")
	quit(0)
