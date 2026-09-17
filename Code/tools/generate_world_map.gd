## 世界总览图离线生成（小地图底图）。
## 运行："$GODOT" --headless --path Code -s tools/generate_world_map.gd
## 采样 BiomeMap（与游戏运行时同一份噪声场/种子）逐像素上地形色——
## 小地图与真实世界严格一致。BiomeMap 的 SEED/网格/带参数改动后必须重跑本工具。
## 输出：assets/terrain/world_map.png（1000×1000，约 8s 无头采样）
extends SceneTree

const OUT := "res://assets/terrain/world_map.png"
const RES := 1000


func _init() -> void:
	var img := Image.create(RES, RES, false, Image.FORMAT_RGB8)
	var colors: Dictionary = BiomeMap.TERRAIN_COLORS
	for y in RES:
		for x in RES:
			var p := Vector2((float(x) + 0.5) / RES, (float(y) + 0.5) / RES) * BiomeMap.WORLD_SIZE
			var terrain := BiomeMap.terrain_at(p)
			img.set_pixel(x, y, colors.get(terrain, Color(0.2, 0.2, 0.2)))
	var path := ProjectSettings.globalize_path(OUT)
	var err := img.save_png(path)
	print("生成 %s（%d×%d）%s" % [path, RES, RES, "OK" if err == OK else "失败:%d" % err])
	quit(0)
