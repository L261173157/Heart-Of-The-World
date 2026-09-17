## 相机取景探针：确定性测量角色屏上尺寸（不依赖读图）。
## 用法：godot --headless --path Code -s tools/cam_probe.gd
## 输出：zoom、帧画布尺寸、精灵内容实际包围盒、720p 视口下的屏上像素高与占比。
extends SceneTree


func _init() -> void:
	var player: Node = load("res://scenes/player/player.tscn").instantiate()
	root.add_child(player)
	await process_frame
	await process_frame
	var cam: Camera2D = player.get_node("Camera2D")
	var visual: AnimatedSprite2D = player.get_node("Visual")
	var frames: SpriteFrames = visual.sprite_frames
	var tex: Texture2D = frames.get_frame_texture("idle", 0)
	# 精灵内容的真实包围盒：逐帧纹理的非透明像素范围（帧画布通常大片留白）
	var img: Image = tex.get_image()
	var min_y := 1000000
	var max_y := -1
	var min_x := 1000000
	var max_x := -1
	for y in img.get_height():
		for x in img.get_width():
			if (img.get_pixel(x, y).a8 > 0):
				min_y = mini(min_y, y)
				max_y = maxi(max_y, y)
				min_x = mini(min_x, x)
				max_x = maxi(max_x, x)
	var content_h: int = max_y - min_y + 1
	var content_w: int = max_x - min_x + 1
	var s: float = visual.scale.x
	# 720p 基准视口：世界像素 → 视口像素 = ×zoom；720p 拉伸下即屏上像素
	var screen_h_px: float = content_h * s * cam.zoom.x
	print("zoom=%.1f frame=%dx%d content=%dx%d sprite_scale=%.2f" % [cam.zoom.x, tex.get_width(), tex.get_height(), content_w, content_h, s])
	print("世界高度=%.1fpx 屏上高度=%.0fpx/720 占比=%.1f%%" % [content_h * s, screen_h_px, screen_h_px / 720.0 * 100.0])
	quit(0)
