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
	GameState.fog_reveal_position(_player.global_position)
	await get_tree().create_timer(0.30, true).timeout
	await _complete_terrain()
	_check(_map._terrain.cells.has(gate_key), "暂停中迷雾版本推进重新准备已知区")
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
