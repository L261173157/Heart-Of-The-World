## 障碍场覆盖率探针（调参用，非闸门）：
## "$GODOT" --headless --path Code -s tools/obstacle_probe.gd
extends SceneTree


func _init() -> void:
	BiomeMap.configure(BiomeMap.DEFAULT_SEED)
	for terrain in ["plains", "forest", "snow", "swamp", "hill", "lava"]:
		var patches := BiomeMap.patches_of_terrain(terrain)
		var cov := 0.0
		var n := 0
		for p in patches:
			var c: Vector2 = p["center"]
			# 中心 600px 抑制区外取样：偏移矩形 1600~8000px 段
			cov += ObstacleField.coverage_in(Rect2(c + Vector2(1600, 1600), Vector2(6400, 6400)))
			n += 1
		print("%s: %.1f%%（%d 斑块）" % [terrain, cov / n * 100.0, n])
	quit(0)
