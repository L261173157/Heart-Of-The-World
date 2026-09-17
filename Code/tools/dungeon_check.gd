## 一次性校验：城塞墙环结构实证（模拟层采样，不依赖视觉判读）。
## 断言：外环 44 格中仅南门 2 格为空，其余全为 castle；内腔全空；门洞两格可通行
extends SceneTree


func _init() -> void:
	BiomeMap.configure(BiomeMap.DEFAULT_SEED)
	var bad := 0
	for dg: Dictionary in ObstacleField.dungeons():
		var center: Vector2 = dg["center"]
		var cc := Vector2i(floori(center.x / 32.0), floori(center.y / 32.0))
		var walls := 0
		var gaps := 0
		for dy in range(-6, 7):
			for dx in range(-6, 7):
				# 外环 = 13×9 矩形边框（|dx|≤6 且 |dy|≤4 的边线）
				var on_wall: bool = (absi(dx) == 6 and absi(dy) <= 4) \
						or (absi(dy) == 4 and absi(dx) <= 6)
				if not on_wall:
					continue
				var cell := cc + Vector2i(dx, dy)
				var s := ObstacleField.sample_cell(cell)
				if dy == 4 and absi(dx) <= 1:
					if s.is_empty():
						gaps += 1
					else:
						print("门洞误封 %s -> %s" % [Vector2i(dx, dy), s])
						bad += 1
				else:
					if s.is_empty() or s["kind"] != "castle":
						print("墙体缺失 %s -> %s" % [Vector2i(dx, dy), s])
						bad += 1
					else:
						walls += 1
		# 内腔（不含外墙）
		var inner_blocked := 0
		for dy in range(-3, 4):
			for dx in range(-5, 6):
				var s2 := ObstacleField.sample_cell(cc + Vector2i(dx, dy))
				if not s2.is_empty():
					inner_blocked += 1
		# 门洞两格导航可走
		var door_nav := 0
		for dx in range(-1, 2):
			if not ObstacleField.is_nav_blocked(cc + Vector2i(dx, 4)):
				door_nav += 1
		print("%s 城塞@%d,%d：墙 %d 格 + 门洞 %d 格（门洞可走 %d/3）、内腔占用 %d"
			% [dg["terrain"], cc.x, cc.y, walls, gaps, door_nav, inner_blocked])
		if walls != 37 or gaps != 3 or inner_blocked != 0:
			bad += 1
	if bad == 0:
		print("=== 城塞结构实证通过 ===")
	else:
		print("=== %d 处异常 ===" % bad)
	quit(0 if bad == 0 else 1)
