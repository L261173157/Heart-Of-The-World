## 真实 HUD 阅读地图生命周期：隐藏零准备/采样、暂停补完、温缓存及事件失效。
extends Node

const MAIN := preload("res://scenes/main/main.tscn")
var _checks := 0
var _fails := 0
var _world: Node2D
var _player: Player
var _hud: CanvasLayer
var _map: Minimap


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.save_enabled = false
	GameState.SAVE_PATH = "user://map_performance_test.json"
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		push_error("FAIL " + message)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _tap(control: Control) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = control.get_global_rect().get_center()
	event.pressed = true
	get_viewport().push_input(event, true)
	await _frames(2)
	event = event.duplicate()
	event.pressed = false
	get_viewport().push_input(event, true)
	await _frames(2)


func _open_map() -> void:
	await _tap(_hud.get_node("Root/Minimap"))
	_check(get_tree().paused and _map.is_visible_in_tree() and _map.is_processing(),
		"真实 HUD 地图点击打开暂停阅读层并启用处理")


func _close_map() -> void:
	await _tap(_hud._map_layer.find_child("ChoiceClose", true, false))
	_check(not get_tree().paused and not _map.is_visible_in_tree() and not _map.is_processing(),
		"真实关闭按钮恢复世界并停用隐藏地图")


func _complete_terrain() -> void:
	# 帧数只是失败看门狗；成功条件必须是队列真实耗尽，不直接调用 step。
	var frames := 0
	while _map._terrain.has_pending() and frames < 2000:
		await _frames(1)
		_check(_map._terrain.last_step_samples <= MinimapTerrain.SAMPLE_BUDGET,
			"模态内每帧仍遵守24次采样硬预算")
		frames += 1
	_check(not _map._terrain.has_pending(), "真实暂停处理自动完成地形队列")


func _capture(label: String) -> void:
	var directory := OS.get_environment("HOTW_MAP_SHOTS")
	if directory.is_empty():
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(directory)
	var path := directory.path_join(label + ".png")
	_check(get_viewport().get_texture().get_image().save_png(path) == OK, "保存真实渲染截图 " + label)
	print("MAP SCREENSHOT ", path)


func _run() -> void:
	GameState.reset_all()
	GameState.world_seed = 20260908
	BiomeMap.configure(GameState.world_seed)
	_world = MAIN.instantiate()
	# 测试驱动需在暂停时等帧，但真实世界必须保持游戏默认的可暂停模式。
	_world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_world)
	await _frames(5)
	_player = _world.get_node("Player")
	_hud = _world.get_node("HUD")
	_map = _hud._map_layer.find_child("ReadingMap", true, false)
	WorldSim.set_process(false)
	_world.get_node("Monsters").process_mode = Node.PROCESS_MODE_DISABLED
	_check(not _map.is_processing() and _map._terrain._window == Rect2i(),
		"真实默认隐藏阅读图不在ready阶段准备地形窗口")
	_check(_map._terrain.total_samples == 0 and _map._terrain.pending.is_empty(),
		"首次打开前没有隐藏采样或待采队列")
	var origin := _player.global_position
	var fog_version := GameState.fog_version
	Input.action_press("move_down")
	for i in 105:
		await get_tree().physics_frame
	Input.action_release("move_down")
	for i in 12:
		await get_tree().physics_frame
	_check(_player.global_position.distance_to(origin) > 250.0 and GameState.fog_version > fog_version,
		"真实物理移动持续推进玩家与探索")
	_check(_map._terrain.total_samples == 0 and _map._terrain._window == Rect2i(),
		"玩家移动和迷雾更新期间隐藏阅读图仍然零准备零采样")
	var hidden_start := Time.get_ticks_usec()
	for i in 120:
		_map._process(0.25)
		_map._refresh_navigation()
	var hidden_usec := Time.get_ticks_usec() - hidden_start
	_check(_map._terrain.total_samples == 0 and _map._terrain.pending.is_empty(),
		"隐藏时显式刷新及处理也不能绕过按需守卫")
	_player.set_physics_process(false)
	_player.velocity = Vector2.ZERO
	await _open_map()
	_check(_map._terrain.has_pending(), "首次打开只有有界的部分采样，没有同步填满窗口")
	var partial_cells := _map._terrain.cells.duplicate(true)
	await _close_map()
	var partial_samples := _map._terrain.total_samples
	await _frames(10)
	_check(_map._terrain.total_samples == partial_samples, "补完前关闭也立即停用尚未完成的采样队列")
	await _open_map()
	for key: Vector2i in partial_cells:
		_check(_map._terrain.cells.get(key, {}) == partial_cells[key], "快速重开继续保留已完成的局部样本")
	var paused_pos := _player.global_position
	var paused_tick := WorldSim.sim.tick_count
	var paused_fog := GameState.exploration.to_dict()
	await _complete_terrain()
	_check(_map._terrain.cells.size() > 100 and not _map._terrain.base_cells.is_empty(),
		"首次打开在暂停中补齐真实粗地被及精细地形")
	_check(_player.global_position == paused_pos and WorldSim.sim.tick_count == paused_tick \
			and GameState.exploration.to_dict() == paused_fog,
		"补完地图不推进玩家、生态或探索")
	_test_exact_draw_cache()
	await _test_draw_sources("open")
	await _capture("map_open")
	var warm_samples := _map._terrain.total_samples
	var warm_cells := _map._terrain.cells.duplicate(true)
	await _close_map()
	await _frames(20)
	_check(_map._terrain.total_samples == warm_samples, "关闭后立即停止地形采样")
	await _capture("map_closed")
	await _open_map()
	await _complete_terrain()
	_check(_map._terrain.total_samples == warm_samples and _map._terrain.cells == warm_cells,
		"静止关闭再开完整复用温缓存，不重复采样")
	await _test_draw_sources("reopen")
	await _capture("map_reopen")
	# 覆盖在读图中打开另一个模态，再返回原地图的父级可见性事件。
	_hud._open_task_list()
	await _frames(3)
	_check(not _map.is_processing() and not _map.is_visible_in_tree(), "阅读层被嵌套模态隐藏时停止处理")
	_hud._close_top_layer_or_toggle_pause()
	await _frames(3)
	_check(_map.is_processing() and _map.is_visible_in_tree() and get_tree().paused,
		"返回上一层恢复地图处理及既有暂停状态")
	await _close_map()
	# 隐藏期间移动到未缓存的真实剧情机关；重新打开须核对当前位置与新迷雾。
	var gate_cells := CampaignLayout.gate_cells("c2:forest_gate")
	_check(not gate_cells.is_empty(), "机关夹具来自真实剧情几何")
	var gate_cell: Vector2i = gate_cells[gate_cells.size() / 2]
	var gate_key := Vector2i(floori(float(gate_cell.x) / 2), floori(float(gate_cell.y) / 2))
	_player.global_position = (Vector2(gate_cell) + Vector2.ONE * 0.5) * ObstacleField.CELL + Vector2(0, 160)
	_world._reveal_fog()
	await _frames(3)
	_check(_map._terrain.total_samples == warm_samples, "隐藏移动不为新窗口提前采样")
	await _open_map()
	await _complete_terrain()
	_check(_map._player_pos == _player.global_position and _map._terrain.cells.has(gate_key),
		"重开即时跟随真实位置与新增已知机关")
	_check(_map._terrain.cells.size() <= MinimapTerrain.MAX_CELLS \
			and _map._terrain.base_cells.size() <= MinimapTerrain.MAX_BASE_CELLS,
		"窗口移动后精细与粗地被缓存仍有界")
	await _test_draw_sources("gate_closed")
	var closed_gate: Dictionary = _map._terrain.cells.get(gate_key, {}).duplicate(true)
	_check(int(closed_gate.get("blocked", 0)) > 0, "地图原来记录关闭机关的真实障碍")
	var campaign: CampaignWorld = get_tree().get_first_node_in_group("campaign_world")
	var state := campaign.state.duplicate(true)
	state["open_gates"] = ["c2:forest_gate"]
	campaign.refresh_state(state)
	_check(not _map._terrain.cells.has(gate_key), "真实机关投影通知立即失效可见地图对应缓存格")
	await _frames(2)
	await _complete_terrain()
	_check(_map._terrain.cells.get(gate_key, {}) == MinimapTerrain.sample(gate_key) \
			and int(_map._terrain.cells.get(gate_key, {}).get("blocked", 4)) < int(closed_gate.get("blocked", 0)),
		"暂停内重采开放机关，与真实障碍场完全一致")
	await _test_draw_sources("gate_open")
	await _close_map()
	state["open_gates"] = []
	campaign.refresh_state(state)
	var closed_samples := _map._terrain.total_samples
	await _frames(6)
	_check(not _map._terrain.cells.has(gate_key) and _map._terrain.total_samples == closed_samples,
		"隐藏时机关事件只失效缓存，不启动补采")
	await _open_map()
	await _complete_terrain()
	_check(_map._terrain.cells.get(gate_key, {}) == closed_gate, "再次打开按真实关闭机关恢复地图")
	await _close_map()
	# 同种子换档仍需辨别探索对象，不能把温缓存泄漏进新档的未知区域。
	GameState.exploration = ExplorationFog.new(GameState.world_seed)
	GameState.explored = PackedByteArray()
	GameState.fog_version += 1
	await _open_map()
	_check(_map._terrain.cells.is_empty() and _map._terrain.base_cells.is_empty() \
			and _map._terrain.pending.is_empty(), "同种子空探索替换清除旧地形且不采样未知区")
	await _test_draw_sources("world_reset")
	GameState.fog_reveal_position(_player.global_position)
	await get_tree().create_timer(0.30, true).timeout
	await _complete_terrain()
	_check(_map._terrain.cells.has(gate_key), "暂停中迷雾版本推进重新准备已知区")
	await _test_draw_sources("fog_reveal")
	await _test_draw_boundary_sources()
	for key: Vector2i in _map._terrain.cells:
		_check(GameState.fog_knows_position((Vector2(key) + Vector2.ONE * 0.5) * MinimapTerrain.CELL),
			"所有缓存地形采样仍在已知区域内")
	await _close_map()
	print("MAP PERF hidden120process_refresh_us=%d hidden_samples=0 warm_reopen_samples=0 visible_cells=%d" % [
		hidden_usec, _map._terrain.cells.size()])
	_world.queue_free()
	await _frames(3)
	TouchInput.reset()
	if _fails == 0:
		print("=== MAP PERFORMANCE PASS (%d checks) ===" % _checks)
	get_tree().quit(0 if _fails == 0 else 1)


func _test_exact_draw_cache() -> void:
	var saved_fog := GameState.exploration
	GameState.exploration = ExplorationFog.new(GameState.world_seed)
	GameState.exploration.remember_legacy_cell(Vector2i(3, 0))
	var terrain_center := Vector2(12000, 96)
	var fog_center := Vector2(11968, 64)
	_check(ExplorationFog.cell_of(terrain_center) == ExplorationFog.cell_of(fog_center),
		"夹具的64px地形中心与128px雾中心位于同一雾格")
	_check(_map._is_known_position(terrain_center) and not _map._is_known_position(fog_center),
		"旧4000px记忆边界两侧必须保留不同精确位置查询")
	GameState.exploration.remember_legacy_cell(Vector2i.ZERO)
	GameState.exploration.remember_legacy_cell(Vector2i(199, 0))
	_check(not _map._is_known_position(Vector2(-1, 100)) and _map._is_known_position(Vector2(0, 100)),
		"西侧边界不能钳到已探索边格")
	_check(_map._is_known_position(Vector2(799999, 100)) and not _map._is_known_position(Vector2(800000, 100)),
		"东侧边界不能钳到已探索边格")
	GameState.exploration = saved_fog


## 可选的独立旧源码差分：只包裹真实_draw，不复刻绘制算法。计数与计时分开，
## 避免逐查询计数放大旧版耗时；两版消费同一冻结状态并逐字节比较渲染像素。
func _draw_probe(source: String, count_queries: bool) -> Control:
	var script := GDScript.new()
	source = source.replace("class_name Minimap\n", "")
	source = source.replace("func _ready() -> void:", "func _probe_unused_ready() -> void:")
	source = source.replace("func _process(delta: float) -> void:", "func _probe_unused_process(delta: float) -> void:")
	source = source.replace("func _draw() -> void:", "func _probe_draw_body() -> void:")
	if count_queries:
		source = source.replace("func _is_known_position(pos: Vector2) -> bool:\n",
			"func _is_known_position(pos: Vector2) -> bool:\n\t_probe_queries += 1\n\t_probe_positions[pos] = true\n")
	source += "\nvar _probe_times: Array[int] = []\nvar _probe_queries := 0\nvar _probe_positions: Dictionary = {}\n"
	source += "func _ready() -> void:\n\tpass\nfunc _process(_delta: float) -> void:\n\tpass\n"
	source += "func _draw() -> void:\n\tvar started := Time.get_ticks_usec()\n\t_probe_draw_body()\n\t_probe_times.append(Time.get_ticks_usec() - started)\n"
	script.source_code = source
	_check(script.reload() == OK, "独立原始地图源码可编译")
	var probe: Control = script.new()
	probe.size = _map.size
	probe.process_mode = Node.PROCESS_MODE_ALWAYS
	for property: String in ["_terrain", "_has_player", "_player_pos", "_interior_index", "_target", "_markers"]:
		probe.set(property, _map.get(property))
	return probe


func _draw_viewport(probe: Control) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(_map.size.ceil())
	viewport.disable_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(viewport)
	viewport.add_child(probe)
	return viewport


func _test_draw_sources(label: String) -> void:
	await _assert_draw_queries(label)
	var baseline := OS.get_environment("HOTW_MAP_DRAW_BASELINE")
	if baseline.is_empty():
		return
	_check(DisplayServer.get_name() != "headless", "源码像素差分必须使用真实图形渲染器")
	if DisplayServer.get_name() == "headless":
		return
	var sources: Array[String] = [FileAccess.get_file_as_string(baseline),
		FileAccess.get_file_as_string("res://scripts/ui/minimap.gd")]
	_check(not sources[0].is_empty(), "读取独立优化前地图源码")
	if sources[0].is_empty():
		return
	var timings: Array = [[], []]
	var images: Array[Image] = []
	var queries: Array = []
	for counting: bool in [true, false]:
		var probes: Array[Control] = []
		var viewports: Array[SubViewport] = []
		for source: String in sources:
			var probe := _draw_probe(source, counting)
			probes.append(probe)
			viewports.append(_draw_viewport(probe))
		await RenderingServer.frame_post_draw
		if counting:
			for i in 2:
				queries.append({"calls": probes[i].get("_probe_queries"),
					"unique": probes[i].get("_probe_positions").size()})
				images.append(viewports[i].get_texture().get_image())
			_check(queries[1]["calls"] == queries[1]["unique"], "真实_draw每个精确坐标最多查询一次 " + label)
			_check(probes[1].get("_probe_positions") == probes[0].get("_probe_positions"), "真实_draw查询相同位置集合 " + label)
			_check(not images[0].is_empty() and images[0].get_size() == Vector2i(_map.size.ceil()), "冻结像素来自完整非空地图 " + label)
			_check(images[0].get_data() == images[1].get_data(), "冻结真实地图优化前后逐像素一致 " + label)
			var directory := OS.get_environment("HOTW_MAP_SHOTS")
			if not directory.is_empty():
				for i in 2:
					_check(images[i].save_png(directory.path_join("draw_" + label + ("_before.png" if i == 0 else "_after.png"))) == OK,
						"保存冻结差分截图 " + label)
		else:
			# 交错ABBA，丢弃初次字体/命令分配预热；只计_draw本体，不计GPU等待。
			for probe: Control in probes:
				probe.get("_probe_times").clear()
			for repeat in 12:
				for i in [0, 1, 1, 0]:
					probes[i].queue_redraw()
					await RenderingServer.frame_post_draw
			for i in 2:
				timings[i] = probes[i].get("_probe_times").duplicate()
		for viewport: SubViewport in viewports:
			viewport.queue_free()
		await _frames(1)
	print("MAP DRAW DIFF ", JSON.stringify({"fixture": label, "queries": queries,
		"baseline_sha256": sources[0].sha256_text(), "current_sha256": sources[1].sha256_text(),
		"draw_us_before": timings[0], "draw_us_after": timings[1], "pixels_identical": images[0].get_data() == images[1].get_data()}))


func _test_draw_boundary_sources() -> void:
	var saved_fog := GameState.exploration
	var saved_position := _map._player_pos
	var saved_terrain := _map._terrain
	var saved_markers := _map._markers
	var saved_target := _map._target
	_map.set_process(false)
	for pos: Vector2 in [Vector2(12000, 4100), Vector2(799900, 100), Vector2(100, 100)]:
		GameState.exploration = ExplorationFog.new(GameState.world_seed)
		GameState.exploration.remember_legacy_cell(Vector2i(pos / 4000.0))
		_map._player_pos = pos
		# 冻结图还覆盖活体/巢穴/地标及越窗目标箭头，位置不依赖随机生态。
		_map._markers = [{"kind": "monster", "ambient": false, "pos": pos + Vector2(-700, 300)},
			{"kind": "monster", "ambient": true, "pos": pos + Vector2(500, 100)},
			{"kind": "nest", "pos": pos + Vector2(300, -800)},
			{"kind": "landmark", "pos": pos + Vector2(-400, -500)}]
		_map._target = {"pos": pos + Vector2(9000, -4000), "precise": true}
		_map._terrain = MinimapTerrain.new()
		var extent := _map._radar_rect().size / _map._radar_scale()
		_map._terrain.prepare(Rect2(pos - extent * 0.5, extent), GameState.world_seed,
			GameState.fog_version, _map._is_known_position)
		while _map._terrain.has_pending():
			_map._terrain.step()
		await _test_draw_sources("boundary_%d_%d" % [pos.x, pos.y])
	GameState.exploration = saved_fog
	_map._player_pos = saved_position
	_map._terrain = saved_terrain
	_map._markers = saved_markers
	_map._target = saved_target
	_map.set_process(true)


func _assert_draw_queries(label: String) -> void:
	var probe := _draw_probe(FileAccess.get_file_as_string("res://scripts/ui/minimap.gd"), true)
	var viewport := _draw_viewport(probe)
	await _frames(3)
	var expected: Dictionary = {}
	var rect := _map._radar_rect()
	var start := ExplorationFog.cell_of(_map._player_pos - rect.size * 0.5 / _map._radar_scale())
	var end := ExplorationFog.cell_of(_map._player_pos + rect.size * 0.5 / _map._radar_scale())
	for y in range(start.y, end.y + 1):
		for x in range(start.x, end.x + 1):
			var pos := (Vector2(x, y) + Vector2.ONE * 0.5) * ExplorationFog.CELL
			expected[pos] = true
			if _map._is_known_position(pos):
				for edge: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
					expected[pos + Vector2(edge) * ExplorationFog.CELL] = true
	for key: Vector2i in _map._terrain.cells:
		expected[(Vector2(key) + Vector2.ONE * 0.5) * MinimapTerrain.CELL] = true
	_check(probe.get("_probe_queries") == expected.size(), "真实_draw每个精确坐标只查询一次 " + label)
	_check(probe.get("_probe_positions") == expected, "真实_draw保留粗/细中心及邻边完整坐标集合 " + label)
	# 同一节点重绘必须重新查询，缓存不能跨帧延续到新迷雾/新世界。
	probe.set("_probe_queries", 0)
	probe.get("_probe_positions").clear()
	probe.queue_redraw()
	await _frames(2)
	_check(probe.get("_probe_queries") == expected.size() and probe.get("_probe_positions") == expected,
		"下一轮真实_draw重新查询当前状态 " + label)
	print("MAP DRAW QUERIES fixture=%s calls=%d unique=%d" % [label, probe.get("_probe_queries"), expected.size()])
	viewport.queue_free()
	await _frames(1)
