## 真实地表生成探针：六群系 PNG、交错顺序性能对照与只读障碍/导航指纹。
## HOTW_TERRAIN_OUT=/tmp/terrain 输出图片；HOTW_TERRAIN_REFERENCE=/tmp/old.gd 可选旧绘制器。
## 旧脚本需仅移除 class_name 行以避免全局类重名；不改项目代码或存档。
extends SceneTree

var _reference: GDScript


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.get_node("GameState").save_enabled = false
	BiomeMap.configure(BiomeMap.DEFAULT_SEED)
	var reference_path := OS.get_environment("HOTW_TERRAIN_REFERENCE")
	if not reference_path.is_empty():
		_reference = load(reference_path) as GDScript
		if _reference == null:
			push_error("无法读取对照绘制器")
			quit(1)
			return
	var start := Time.get_ticks_usec()
	TerrainPainter.ensure_atlases()
	print("TERRAIN_INIT current_ms=%.2f" % ((Time.get_ticks_usec() - start) / 1000.0))
	if _reference != null:
		start = Time.get_ticks_usec()
		_reference.ensure_atlases()
		print("TERRAIN_INIT reference_ms=%.2f" % ((Time.get_ticks_usec() - start) / 1000.0))
	var origins: Array[Vector2i] = []
	var names: Array[String] = []
	for terrain: String in ["plains", "forest", "snow", "swamp", "hill", "lava"]:
		var pos: Vector2 = BiomeMap.patches_of_terrain(terrain)[0]["center"] + Vector2(2200, 1400)
		if terrain == "plains": pos = BiomeMap.spawn_pos()
		origins.append(Vector2i(floori((pos.x - 384) / 16.0) * 16, floori((pos.y - 384) / 16.0) * 16))
		names.append(terrain)
	var current_ms: Array[float] = []
	var reference_ms: Array[float] = []
	# 每轮交换先后顺序，排除预热和同时运行其它验证进程的固定顺序偏差。
	for pass_id in 4:
		for origin: Vector2i in origins:
			for offset in 3:
				var at := origin + Vector2i(offset * 512, 0)
				if pass_id % 2 == 0 and _reference != null:
					_measure(_reference, at, reference_ms)
				_measure(TerrainPainter, at, current_ms)
				if pass_id % 2 == 1 and _reference != null:
					_measure(_reference, at, reference_ms)
	_report("current", current_ms)
	if _reference != null: _report("reference", reference_ms)
	var fingerprint := PackedByteArray()
	var out := OS.get_environment("HOTW_TERRAIN_OUT")
	if not out.is_empty(): DirAccess.make_dir_recursive_absolute(out)
	for i in origins.size():
		var origin := origins[i]
		fingerprint.append_array(var_to_bytes(ObstacleField.cells_of_chunk(origin)))
		fingerprint.append_array(ObstacleField.nav_blocked_chunk(origin))
		print("TERRAIN_SAMPLE %s origin=%s" % [names[i], origin])
		if not out.is_empty():
			TerrainPainter.paint_chunk(origin, 48).save_png(out.path_join(names[i] + ".png"))
			if _reference != null:
				_reference.paint_chunk(origin, 48).save_png(out.path_join(names[i] + "_before.png"))
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(fingerprint)
	print("TERRAIN_AUTHORITY_SHA256 ", ctx.finish().hex_encode())
	var bytes := 0
	for terrain: String in TerrainPainter.RULES:
		for source: Dictionary in [TerrainPainter._surfaces, TerrainPainter._patch_edges, TerrainPainter._water_edges]:
			bytes += (source[terrain] as Image).get_data_size()
		for overlay: Image in TerrainPainter._overlays[terrain]: bytes += overlay.get_data_size()
	print("TERRAIN_CACHE bytes=%d" % bytes)
	print("=== TERRAIN PROBE COMPLETE ===")
	quit()


func _measure(painter: GDScript, origin: Vector2i, samples: Array[float]) -> void:
	var start := Time.get_ticks_usec()
	painter.paint_chunk(origin, 32)
	samples.append((Time.get_ticks_usec() - start) / 1000.0)


func _report(label: String, samples: Array[float]) -> void:
	samples.sort()
	var total := 0.0
	for ms in samples: total += ms
	print("TERRAIN_BENCH %s n=%d mean_ms=%.2f median_ms=%.2f p95_ms=%.2f" % [
		label, samples.size(), total / samples.size(), samples[samples.size() / 2],
		samples[ceili(samples.size() * 0.95) - 1]])
