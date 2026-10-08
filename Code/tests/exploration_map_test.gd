## 真实世界探索回归：移动、三态地图、信息边界、房间、保存重载与有界采样。
extends Node
const MAIN := preload("res://scenes/main/main.tscn")
var _checks := 0
var _fails := 0
var _world: Node2D
var _player: Player
var _map: Minimap

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.save_enabled = false
	GameState.SAVE_PATH = "user://exploration_map_test.json"
	if OS.get_environment("HOTW_EXPLORATION_STAGE") == "read":
		_cold_read.call_deferred()
	else:
		_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		push_error("FAIL " + message)

func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame

func _open() -> void:
	_world = MAIN.instantiate()
	add_child(_world)
	var initial_player: Player = _world.get_node("Player")
	_check(get_viewport().get_visible_rect().has_point(
		get_viewport().get_canvas_transform() * initial_player.global_position),
		"出生或读档在首个物理/渲染帧前同步实际视口")
	await _frames(3)
	_player = _world.get_node("Player")
	_map = _world.get_node("HUD/Root/Minimap")
	WorldSim.set_process(false)
	_world.get_node("Monsters").process_mode = Node.PROCESS_MODE_DISABLED

func _run() -> void:
	GameState.reset_all()
	GameState.world_seed = 20260908
	BiomeMap.configure(GameState.world_seed)
	await _open()
	_world._reveal_fog()
	_map._refresh_navigation()
	var origin := _player.global_position
	_check(GameState.fog_knows_position(origin), "真实出生位置写入细探索")
	_test_camera_sight_boundary()
	_check(not GameState.fog_knows_position(origin + Vector2(2200, 0)), "同一粗格不再自动揭开2200px外")
	_check(GameState.exploration.chunks.size() <= 4, "开局只分配附近最多4个128字节块")
	var version := GameState.fog_version
	_world._reveal_fog()
	_check(GameState.fog_version == version, "站立不重复写入或推进探索版本")
	# 真实输入/物理移动和世界计时揭雾，不能只调用纯函数代替游戏闭环。
	Input.action_press("move_down")
	await _frames(110)
	Input.action_release("move_down")
	await _frames(20)
	_map._refresh_navigation()
	_check(_player.global_position.distance_to(origin) > 250.0, "真实输入移动越过多个细格")
	_check(GameState.fog_version > version, "世界移动定时器自动扩展探索")
	_check(GameState.fog_knows_position(_player.global_position), "移动终点已探索")
	_check(not _map._is_visible_position(origin + Vector2(2200, 0)), "未知圈外无当前视野")
	# 到访后走远：历史地形保留，活体不会从暗记忆区泄露。
	var remembered := origin + Vector2(0, -1400)
	_check(GameState.fog_knows_position(remembered), "出生圆的后缘保持记忆")
	_check(not _map._is_visible_position(remembered), "离开的已知后缘退出当前视野")
	for candidate: Dictionary in _map._known_candidates():
		if candidate["kind"] == "monster":
			_check(_map._is_visible_position(candidate["pos"]), "每个活体点都通过当前视野筛选")
	_check(not _map._known_candidates().any(func(c: Dictionary) -> bool:
		return c["kind"] == "landmark" and not str(c["id"]).trim_prefix("landmark:") in GameState.discovered_landmarks),
		"未发现地标无地图或导航泄漏")
	# 同一地形采样缓存只在当前局部窗，暂停采样也不能丢失标记/房间语义。
	_map._terrain.clear()
	_map._refresh_navigation()
	var max_usec := 0
	for i in 240:
		var start := Time.get_ticks_usec()
		var samples := _map._terrain.step()
		max_usec = maxi(max_usec, Time.get_ticks_usec() - start)
		_check(samples <= MinimapTerrain.SAMPLE_BUDGET, "每帧采样硬预算24 第%d批" % i)
	_check(_map._terrain.cells.size() > 100 and _map._terrain.cells.size() <= MinimapTerrain.MAX_CELLS,
		"真实地图生成局部地形且缓存有界")
	_check(not _map._terrain.base_cells.is_empty() and _map._terrain.base_cells.size() <= MinimapTerrain.MAX_BASE_CELLS,
		"先填充的粗地被缓存同样只覆盖局部窗口")
	var sampled := _map._terrain.total_samples
	_map._refresh_navigation()
	_map._terrain.step()
	_check(_map._terrain.total_samples == sampled, "静止已填满窗口不重采地形")
	print("EXPLORATION PERF max24sample_us=%d cached=%d chunks=%d" % [max_usec,
		_map._terrain.cells.size(), GameState.exploration.chunks.size()])
	# 真实地图原数据一致性（包括障碍和液体）与摧毁通知局部失效。
	var terrain_key: Vector2i = _map._terrain.cells.keys()[0]
	var terrain_pos := (Vector2(terrain_key) + Vector2.ONE * 0.5) * MinimapTerrain.CELL
	_check(_map._terrain.cells[terrain_key]["terrain"] == BiomeMap.terrain_at(terrain_pos), "小地图群系同世界真源")
	_check(_map._terrain.cells[terrain_key]["liquid"] == ObstacleField.liquid_kind_at(terrain_pos), "小地图液体同可见液体真源")
	EventBus.obstacle_destroyed.emit(terrain_key * 2, terrain_pos, "rock")
	_check(not _map._terrain.cells.has(terrain_key), "破坏事件只失效对应地图格")
	_map._refresh_navigation()
	for i in 240:
		_map._terrain.step()
	_check(_map._terrain.cells.has(terrain_key), "破坏后按权威场补采地图格")
	var saved_fog := GameState.exploration.to_dict()
	var saved_coarse := GameState.explored.duplicate()
	for room in 2:
		_player.global_position = ObstacleField.interior_pocket(room)
		_world._reveal_fog()
		_map._refresh_navigation()
		_check(_map._target.get("id", "") == "room_exit:%d" % room, "室内只指向自己的出口")
		_check(_map._terrain.cells.is_empty() and _map._terrain.base_cells.is_empty() and _map._markers.is_empty(), "室内无大陆底图或怪物残影")
		_check(GameState.exploration.to_dict() == saved_fog and GameState.explored == saved_coarse,
			"室内不揭开大陆细图或旧粗图")
	_player.global_position = origin + Vector2(0, 400)
	_world._reveal_fog()
	_map._refresh_navigation()
	_check(_map._interior_index == -1, "返回室外恢复北向上地图")
	GameState.save_enabled = true
	_check(GameState.save_now(), "真实世界探索存档成功")
	GameState.save_enabled = false
	saved_fog = GameState.exploration.to_dict()
	var save_seed := GameState.world_seed
	_world.queue_free()
	await _frames(3)
	GameState.reset_all()
	GameState._load()
	_check(GameState.world_seed == save_seed and GameState.exploration.to_dict() == saved_fog, "真实文件重载保留种子绑定细探索")
	await _open()
	_map._refresh_navigation()
	_check(GameState.fog_knows_position(origin) and not GameState.fog_knows_position(origin + Vector2(10000, 0)),
		"重建真实场景后探索保留且未知仍黑")
	_world.queue_free()
	await _frames(3)
	_test_prepare_incremental()
	_test_save_migrations()
	_test_data_edges(saved_fog, save_seed)
	if _fails == 0:
		print("=== EXPLORATION MAP PASSED (%d checks) ===" % _checks)
	get_tree().quit(0 if _fails == 0 else 1)

func _test_data_edges(saved: Dictionary, saved_seed: int) -> void:
	var fog := ExplorationFog.new(saved_seed + 1)
	var old := PackedByteArray()
	old.resize(5000)
	old.fill(255)
	fog.restore(saved, old)
	_check(fog.chunks.is_empty() and fog.legacy.is_empty(), "错种子细探索拒绝且不回退到粗图")
	fog.restore(null, old)
	_check(fog.is_explored(Vector2(799999, 799999)) and fog.chunks.is_empty(), "旧档完整记忆无需展开全世界细格")
	_check(not fog.is_explored(Vector2(-1, 0)) and not fog.is_explored(Vector2(800000, 0)), "边界外不钳到已探索边格")
	fog.restore({"version": 1, "seed": saved_seed + 1, "chunks": {"bad": "!", "-1,0": "!"}}, old)
	_check(fog.chunks.is_empty() and fog.legacy.is_empty(), "损坏新格式安全归零不扩大旧图")
	var bits := PackedByteArray()
	bits.resize(ExplorationFog.CHUNK_BYTES)
	bits.fill(255)
	var encoded := Marshalls.raw_to_base64(bits)
	fog.restore({"version": 1, "seed": saved_seed + 1, "chunks": {
		"4294967296,0": encoded, "0,4294967296": encoded, "18446744073709551616,0": encoded,
		"-4294967296,0": encoded, "196,0": encoded}}, old)
	_check(fog.chunks.is_empty() and not fog.is_explored(Vector2(16, 16)),
		"合法位图的巨大坐标不能经32位溢出别名揭示原点")
	_check(fog.reveal(Vector2(549755813888.0, 0)).is_empty(), "巨大世界坐标也不会绕回原点")
	for bad: String in ["!".repeat(172), "A".repeat(172), "=" + "A".repeat(170) + "=",
		"A".repeat(170) + "\n=", "=".repeat(172)]:
		fog.restore({"version": 1, "seed": saved_seed + 1, "chunks": {"0,0": bad},
			"legacy": "!".repeat(6668)}, old)
		_check(fog.chunks.is_empty() and fog.legacy.is_empty(), "正确长度的坏base64字母/填充安全拒绝")
	_check(ExplorationFog.decode_bitmap("A".repeat(6668), ExplorationFog.LEGACY_BYTES).is_empty(),
		"旧地图长度正确但填充错误也安全拒绝")
	GameState.world_seed = saved_seed
	GameState.exploration = ExplorationFog.new(saved_seed)
	GameState.explored = PackedByteArray()
	GameState.fog_reveal_position(Vector2(4000, 4000))
	_check(GameState.fog_knows_position(Vector2(3990, 3990)) and GameState.fog_knows_position(Vector2(4010, 4010)),
		"细格跨旧4000px边界不会被粗图再次裁断")
	fog = ExplorationFog.new(saved_seed)
	fog.reveal(Vector2(64, 64))
	_check(fog.chunks.size() == 1 and not fog.is_explored(Vector2(3000, 3000)), "世界角落圆形揭示有界无对角超揭示")
	GameState.reset_all()
	_check(GameState.exploration.chunks.is_empty() and GameState.explored.is_empty(), "新冒险清除细图与粗图")


func _cold_read() -> void:
	GameState._load()
	var saved := GameState.exploration.to_dict()
	_check(GameState.world_seed == 20260908 and saved["chunks"].size() > 0,
		"独立进程恢复正确世界与非空细探索")
	_check(GameState.player_snapshot != null, "独立进程恢复真实玩家位置")
	await _open()
	_world._reveal_fog()
	_map._refresh_navigation()
	var spawn := WorldConfig.spawn_pos()
	_check(GameState.fog_knows_position(spawn), "冷启动已到访出生地仍有地形")
	_check(not GameState.fog_knows_position(spawn + Vector2(10000, 0)), "冷启动未知地形仍未探索")
	_check(_map._is_visible_position(_player.global_position), "冷启动当前视野按玩家真实位置重建")
	_check(GameState.exploration.seed == GameState.world_seed, "冷启动探索不串世界")
	_world.queue_free()
	await _frames(3)
	if _fails == 0:
		print("=== EXPLORATION COLD READ PASSED (%d checks) ===" % _checks)
	get_tree().quit(0 if _fails == 0 else 1)


func _test_save_migrations() -> void:
	var original_path := GameState.SAVE_PATH
	var file := FileAccess.open(original_path, FileAccess.READ)
	var saved: Dictionary = JSON.parse_string(file.get_as_text())
	file.close()
	var origin := WorldConfig.spawn_pos()
	var coarse := GameState.fog_cell_of(origin)
	var migrated_pos := Vector2(coarse) * 4000.0 + Vector2(100, 100)
	GameState.SAVE_PATH = "user://exploration_migration_test.json"
	var legacy := saved.duplicate(true)
	legacy.erase("exploration_v2")
	file = FileAccess.open(GameState.SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy))
	file.close()
	GameState._load()
	_check(GameState.exploration.chunks.is_empty() and GameState.fog_knows_position(migrated_pos),
		"真实v10旧档粗地图迁为记忆而非扩成细图")
	legacy["exploration_v2"] = null
	file = FileAccess.open(GameState.SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy))
	file.close()
	GameState._load()
	_check(not GameState.fog_knows_position(migrated_pos) and GameState.exploration.legacy.is_empty(),
		"真实文件中的null新字段不得伪装旧格式扩大探索")
	legacy["exploration_v2"] = saved["exploration_v2"].duplicate(true)
	legacy["exploration_v2"]["seed"] = GameState.world_seed + 1
	file = FileAccess.open(GameState.SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy))
	file.close()
	GameState._load()
	_check(not GameState.fog_knows_position(origin) and GameState.exploration.chunks.is_empty(),
		"真实错种子字段不串档且不影响角色存档加载")
	legacy.erase("exploration_v2")
	legacy["explored"] = "!".repeat(6668)
	file = FileAccess.open(GameState.SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy))
	file.close()
	GameState._load()
	_check(GameState.explored.is_empty() and GameState.exploration.legacy.is_empty(),
		"真实旧档的等长坏base64探索字段不会触发引擎解码错误")
	GameState.SAVE_PATH = original_path


func _test_prepare_incremental() -> void:
	var terrain := MinimapTerrain.new()
	var calls := {"count": 0}
	var origin := Vector2(40000, 40000)
	var center := ExplorationFog.cell_of(origin)
	var known := func(pos: Vector2) -> bool:
		calls["count"] += 1
		return Vector2(ExplorationFog.cell_of(pos) - center).length() <= 12.0
	terrain.prepare(Rect2(origin - Vector2(2826, 2400), Vector2(5652, 4800)),
		20260908, 1, known, ExplorationFog.CELL)
	var initial_queries: int = calls["count"]
	var queued_count := terrain.pending.size()
	for i in 20:
		var pos := origin + Vector2((i % 2) * 64, 0)
		terrain.prepare(Rect2(pos - Vector2(2826, 2400), Vector2(5652, 4800)),
			20260908, 1, known, ExplorationFog.CELL)
	_check(initial_queries > 1000 and int(calls["count"]) - initial_queries <= 160,
		"重复跨64px窗口只查询新边缘，不全窗重查迷雾")
	_check(terrain.pending.size() == queued_count, "窗口往返保留队列且不追加重复细格")
	_check(terrain._known_cache.size() <= 4096 and terrain.pending.size() <= MinimapTerrain.MAX_CELLS,
		"准备阶段的已知格缓存和采样队列也有局部上限")


## 视野仍按实际画面裁剪；探索只读物理位置，不能被绘制相机反写。
func _test_camera_sight_boundary() -> void:
	var camera: Camera2D = _player.get_node("Camera2D")
	var body_before := _player.global_position
	var fog_before := GameState.exploration.to_dict()
	_check(_map._is_visible_position(body_before), "出生后首轮查询已同步真实相机视口")
	camera.global_position = body_before + Vector2(10000, 0)
	camera.force_update_scroll()
	_check(not get_viewport().get_visible_rect().has_point(
		get_viewport().get_canvas_transform() * body_before),
		"回归夹具确实将真实渲染视口移到远方")
	_map._refresh_navigation()
	_check(not _map._is_visible_position(body_before), "画面外已探索位置不能泄露为当前视野")
	_world._reveal_fog()
	_check(_player.global_position == body_before and GameState.exploration.to_dict() == fog_before,
		"相机偏移不改身体位置且不揭开远方探索格")
	camera.snap_to_player()
	_map._refresh_navigation()
	_check(_map._is_visible_position(body_before), "同步吸附后真实视口即时恢复当前视野")
