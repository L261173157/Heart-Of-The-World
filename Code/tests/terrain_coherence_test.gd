## 地表表现契约：跨块逐像素一致、六群系材质、权威液体/碰撞/导航不变、装饰归属。
## 可直接运行：godot --headless --path Code -s tests/terrain_coherence_test.gd
extends SceneTree

var _checks := 0
var _failures := 0
var _liquid_samples := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		push_error(label)


func _run() -> void:
	root.get_node("GameState").save_enabled = false
	var original_seed := BiomeMap.current_seed()
	TerrainPainter.ensure_atlases()
	for seedv in [BiomeMap.DEFAULT_SEED, 20261002]:
		BiomeMap.configure(seedv)
		for terrain: String in BiomeMap.TERRAIN_INFO:
			var patch: Dictionary = BiomeMap.patches_of_terrain(terrain)[0]
			var pos: Vector2 = patch["center"] + Vector2(2200, 1400)
			var origin := Vector2i(floori(pos.x / 16.0) * 16, floori(pos.y / 16.0) * 16)
			_test_partition(origin, "%d/%s" % [seedv, terrain])
			_test_world_parity(origin, terrain)
			_test_decoration(origin)
		_test_boundary(seedv)
		var spawn := BiomeMap.spawn_pos()
		for approach: Vector2 in [Vector2(-310, -25), Vector2(215, -145), Vector2(100, 24), Vector2(0, 330)]:
			_check(TerrainPainter.is_camp_path(spawn + approach), "现有营地入口和行商前有步道")
		_check(not TerrainPainter.is_camp_path(spawn + Vector2(650, 0)), "步道不延伸到未验证的野外")
		_check(not TerrainPainter.is_camp_path(ObstacleField.interior_pocket(0)), "室内不生成营地步道")
	_test_atlases()
	_check(_liquid_samples > 0, "权威液体对照包含真实湿格，避免全干样本假通过")
	BiomeMap.configure(original_seed)
	if _failures == 0:
		print("=== TERRAIN COHERENCE PASSED (%d checks) ===" % _checks)
	quit(0 if _failures == 0 else 1)


func _test_partition(origin: Vector2i, label: String) -> void:
	var full := TerrainPainter.paint_chunk(origin, 32)
	var repeat := TerrainPainter.paint_chunk(origin, 32)
	_check(full.get_data() == repeat.get_data(), "%s 重载确定性" % label)
	var stitched := Image.create(512, 512, false, Image.FORMAT_RGBA8)
	for y in 2:
		for x in 2:
			var offset := Vector2i(x, y) * 256
			var quadrant := TerrainPainter.paint_chunk(origin + offset, 16)
			stitched.blit_rect(quadrant, Rect2i(0, 0, 256, 256), offset)
	_check(full.get_data() == stitched.get_data(), "%s 横纵块接缝逐像素等价" % label)
	_check(not full.is_invisible(), "%s 地表非空" % label)
	# 不只整块拼接：任意 16px 对齐窗口须等于大图的对应裁切。
	var shifted := TerrainPainter.paint_chunk(origin + Vector2i(112, 80), 12)
	_check(shifted.get_data() == full.get_region(Rect2i(112, 80, 192, 192)).get_data(),
		"%s 任意窗口裁切等价" % label)


func _test_world_parity(origin: Vector2i, terrain: String) -> void:
	var cells_before := var_to_bytes(ObstacleField.cells_of_chunk(origin))
	var nav_before := ObstacleField.nav_blocked_chunk(origin).duplicate()
	var destroyed_before := var_to_bytes(ObstacleField.destroyed_list())
	TerrainPainter.paint_chunk(origin, 32)
	_check(cells_before == var_to_bytes(ObstacleField.cells_of_chunk(origin)), "绘制不改障碍样本")
	_check(nav_before == ObstacleField.nav_blocked_chunk(origin), "绘制不改真实导航掩码")
	_check(destroyed_before == var_to_bytes(ObstacleField.destroyed_list()), "绘制不改破坏覆盖层")
	for y in 8:
		for x in 8:
			var pos := Vector2(origin) + Vector2(x * 64 + 8, y * 64 + 8)
			var pid := BiomeMap.region_id_at(pos)
			var t := BiomeMap.terrain_of_patch(pid)
			var material := TerrainPainter._material(t, floori(pos.x / 16.0), floori(pos.y / 16.0), pos, pid)
			if material == 2: _liquid_samples += 1
			_check((material == 2) == (ObstacleField.liquid_kind_at(pos) != ""),
				"%s 可见真实液体消费权威液体场" % terrain)


func _test_boundary(seedv: int) -> void:
	var a: Vector2 = BiomeMap.spawn_pos()
	var b: Vector2 = BiomeMap.patches_of_terrain("forest")[0]["center"]
	for i in 22:
		var mid := (a + b) * 0.5
		if BiomeMap.terrain_at(mid) == "plains": a = mid
		else: b = mid
	var origin := Vector2i(floori(a.x / 16.0) * 16 - 256, floori(a.y / 16.0) * 16 - 256)
	_test_partition(origin, "%d/群系交界" % seedv)


func _test_decoration(origin: Vector2i) -> void:
	var chunk_origin := Vector2i(floori(float(origin.x) / 512) * 512, floori(float(origin.y) / 512) * 512)
	var points := WorldDeco.decoration_points(chunk_origin)
	_check(points == WorldDeco.decoration_points(chunk_origin), "装饰重载不漂移")
	_check(points.size() <= WorldDeco.CHUNK_PROPS, "装饰保持每块候选上限")
	var rect := Rect2(Vector2(chunk_origin), Vector2(512, 512))
	var owned := true
	for pos: Vector2 in points:
		if not rect.has_point(pos): owned = false
	_check(owned, "装饰不跨块抢占/重复撒放")


func _test_atlases() -> void:
	var snow: Image = TerrainPainter._surfaces["snow"]
	var ash: Image = TerrainPainter._surfaces["lava"]
	_check(snow.get_pixel(16, 16).v > 0.8, "雪地读作浅色积雪")
	_check(ash.get_pixel(16, 16).v < 0.5, "熔岩地读作暗色灰烬")
	_check(TerrainPainter.TEXTURE_SIZE == 32 and TerrainPainter.TS == 16,
		"提升视觉粒度但保留逻辑网格")
	for terrain: String in TerrainPainter.RULES:
		var image: Image = TerrainPainter._water_edges[terrain]
		var opaque := true
		for y in image.get_height():
			for x in image.get_width():
				if image.get_pixel(x, y).a < 0.999: opaque = false
		_check(opaque, "%s 16 种岸线邻接均无透明裂缝" % terrain)
		var surface: Image = TerrainPainter._surfaces[terrain]
		for phase in 4:
			for edges in 16:
				var center := image.get_pixel(edges * 16 + 8, phase * 16 + 8)
				var ground := surface.get_pixel((phase % 2) * 16 + 8, (phase / 2) * 16 + 8)
				_check(not center.is_equal_approx(ground), "%s 最窄液体格中心仍可见液体" % terrain)

