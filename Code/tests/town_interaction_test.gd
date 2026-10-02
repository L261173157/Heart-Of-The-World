## 营地闭环：真实入口 Area、键盘/触屏同源交互、房间墙、取消回城与冷存档。
extends Node

const MAIN := preload("res://scenes/main/main.tscn")
var _world: Node2D
var _player: Player
var _checks := 0
var _fails := 0
var _region_events: Array[String] = []


func _ready() -> void:
	GameState.save_enabled = false
	EventBus.player_entered_region.connect(func(id: String, _label: String) -> void: _region_events.append(id))
	_run.call_deferred()


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("  %s %s" % ["PASS" if ok else "FAIL", label])


func _step(frames := 1) -> void:
	for i in frames:
		await get_tree().physics_frame
		await get_tree().process_frame


func _settle() -> void:
	await get_tree().create_timer(0.7).timeout
	await _step(3)


func _enter() -> void:
	_world = MAIN.instantiate()
	add_child(_world)
	_player = _world.get_node("Player")
	_world.hit_stop_enabled = false
	WorldSim.set_process(false)


func _run() -> void:
	if "--interior-reader" in OS.get_cmdline_user_args():
		var old_fog = GameState.explored.duplicate()
		var old_landmarks := GameState.discovered_landmarks.duplicate()
		var old_bounty := GameState.bounty.duplicate(true)
		_enter()
		await _step(8)
		var center := ObstacleField.interior_pocket(0)
		await _assert_room_context(0, old_fog, old_landmarks, old_bounty, "冷启动")
		_check(_player.global_position.distance_to(center + Vector2(0, 30)) < 1.0,
				"屋内保存冷启动仍在原房间")
		_player.teleport_to(center + Vector2(0, 82))
		await _step(4)
		TouchInput.queue_attack()
		await _settle()
		var door: Node2D = _world._town_doors[0]
		_check(_player.global_position.distance_to(door.global_position + Vector2(0, 90)) < 1.0,
				"冷启动房间出口仍可返回对应房屋")
		_check(_world._room_context == -1 and _world._current_region_id == BiomeMap.region_id_at(WorldConfig.spawn_pos()),
				"冷启动出屋恢复户外区域语义")
		var hud := _world.get_node("HUD")
		_check(hud._region_name != "旅舍", "冷启动出屋恢复户外地点标签")
		for child in _world.get_children():
			if child is BountyManager:
				var preserved := GameState.bounty.duplicate(true)
				GameState.bounty = {}
				child._roll_later(0.01)
				child._process(0.02)
				_check(child._rolling or child._roll_delay == child.EXTINCT_CHECK_INTERVAL
						or not GameState.bounty.is_empty(), "出屋后重新启动实际本地赏金选择")
				while child._rolling:
					await _step()
				var chosen_locally := false
				if not GameState.bounty.is_empty():
					var home := WorldSim.sim.region_of_point(WorldConfig.spawn_pos())
					var chosen_id: String = GameState.bounty.get("region_id", "")
					chosen_locally = chosen_id == home.id or chosen_id in home.neighbor_ids
				_check(chosen_locally or (GameState.bounty.is_empty() and child._roll_delay > 0.0),
						"出屋实际赏金选择完成且仅限本区邻区或正常空单重试")
				GameState.bounty = preserved

		await _leave()
		if _fails == 0:
			print("=== TOWN INTERIOR COLD READER PASS ===")
		get_tree().quit(_fails)
		return
	if "--cold-reader" in OS.get_cmdline_user_args():
		_enter()
		await _step(8)
		_check(_player.global_position.distance_to(WorldConfig.spawn_pos()) < 1.0,
				"独立进程继续回城后的营地位置")
		_check(_player.velocity.is_zero_approx() and not _player._is_dead,
				"冷启动没有冲刺/死亡/移动残留")
		await _leave()
		if _fails == 0:
			print("=== TOWN COLD READER PASS ===")
		get_tree().quit(_fails)
		return
	GameState.reset_all()
	GameState.world_seed = BiomeMap.DEFAULT_SEED
	GameState.SAVE_PATH = "user://town_interaction_%d.json" % OS.get_process_id()
	_enter()
	await _step(12)
	await _test_world_props()
	_prepare_active_bounty()
	for idx in 2:
		await _test_house(idx)
	await _test_return()
	var health := _player.current_hp
	GameState.save_enabled = true
	_check(GameState.save_now(), "回城后真实保存成功")
	GameState.save_enabled = false
	await _leave()
	var output: Array = []
	var previous := OS.get_environment("HOTW_TEST_SAVE")
	OS.set_environment("HOTW_TEST_SAVE", ProjectSettings.globalize_path(GameState.SAVE_PATH))
	var code := OS.execute(OS.get_executable_path(), PackedStringArray([
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"res://tests/town_interaction_test.tscn", "--quit-after", "15000", "--", "--cold-reader"
	]), output, true)
	OS.set_environment("HOTW_TEST_SAVE", previous)
	var completed := false
	for line: String in output:
		print(line)
		completed = completed or "=== TOWN COLD READER PASS ===" in line
	_check(code == 0 and completed, "回城保存独立进程往返")
	GameState._load()
	_check(is_equal_approx(float(GameState.player_snapshot["hp"]), health),
			"传送保存不补满生命（%.4f→%.4f）" % [health, float(GameState.player_snapshot["hp"])])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.SAVE_PATH))
	print("=== TOWN INTERACTION %s (%d checks, %d failures) ===" % ["PASS" if _fails == 0 else "FAIL", _checks, _fails])
	get_tree().quit(0 if _fails == 0 else 1)


func _test_world_props() -> void:
	var layer: ObstacleTileLayer
	var nav: NavTileLayer
	for child in _world.get_children():
		if child is ObstacleTileLayer:
			layer = child
		elif child is NavTileLayer:
			nav = child
	var sample_pos: Vector2 = WorldConfig.spawn_pos() + ObstacleField.CAMP_PROPS[1][0]
	var cell := Vector2i(floori(sample_pos.x / 32.0), floori(sample_pos.y / 32.0))
	var anchor := (Vector2(cell) + Vector2(0.5, 0.5)) * 32.0
	var origin := Vector2i(cell.x >> 4, cell.y >> 4) * 512
	layer._on_chunk_ready(origin)
	await _step(4)
	_check(layer.get_cell_source_id(cell) == 0, "营地树来自真实障碍瓦片")
	_check(ObstacleField.blocks(anchor, 10.0) and ObstacleField.nav_blocked_cell(cell),
			"树干阻挡与导航同一真源")
	_player.teleport_to(anchor + Vector2(0, 48))
	await _step(3)
	_check(_player.test_move(_player.global_transform, Vector2(0, -50)), "真实玩家扫掠碰撞到可见树干")
	var source := layer.tile_set.get_source(0) as TileSetAtlasSource
	var td := source.get_tile_data(ObstacleField.KIND_ATLAS["tree"], 0)
	_check(source.texture_region_size.y == 160 and td.y_sort_origin == 0
			and layer.y_sort_enabled and _world.y_sort_enabled, "大树完整画布与真实脚点排序")
	var tree_image := source.texture.get_image().get_region(source.get_tile_texture_region(ObstacleField.KIND_ATLAS["tree"]))
	_check(tree_image.get_used_rect().size.y >= 90, "树内容高至少90px而非裁成32px")
	var roots := layer.tile_set.get_source(1) as TileSetAtlasSource
	for x in 3:
		var root_image := roots.texture.get_image().get_region(roots.get_tile_texture_region(Vector2i(x, 0)))
		_check(root_image.get_used_rect().size.x >= 28 and root_image.get_used_rect().size.y >= 26,
				"盘根硬格保留足以覆盖碰撞的可见木质素材%d" % x)
	var forest_center: Vector2 = BiomeMap.patches_of_terrain("forest")[0]["center"]
	var forest_cell := Vector2i(forest_center / 32.0)
	var mature := 0
	var undergrowth := 0
	for y in range(22, 48):
		for x in range(-28, 28):
			var c := forest_cell + Vector2i(x, y)
			var sample := ObstacleField.sample_cell(c)
			if sample.get("kind", "") in ["tree", "big_tree", "pine"]:
				var art: Dictionary = preload("res://scripts/main/terrain/obstacle_visual_rules.gd").appearance(c, sample["kind"])
				mature += int(art["source"] == 0)
				undergrowth += int(art["source"] == 1)
	_check(mature > 0 and undergrowth > mature, "密林成熟树冠稀疏分布、剩余硬格可见盘根层")
	var rock_pos: Vector2 = WorldConfig.spawn_pos() + ObstacleField.CAMP_PROPS[9][0]
	var rock := Vector2i(floori(rock_pos.x / 32.0), floori(rock_pos.y / 32.0))
	nav._fill_chunk(Vector2i(rock.x >> 4, rock.y >> 4))
	_check(ObstacleField.nav_blocked_cell(rock + Vector2i.RIGHT), "大岩石导航预留身体宽度")
	var rock_anchor := (Vector2(rock) + Vector2.ONE * 0.5) * 32.0
	layer._on_chunk_ready(Vector2i(rock.x >> 4, rock.y >> 4) * 512)
	await _step(4)
	_player.teleport_to(rock_anchor + Vector2(0, 55))
	await _step(3)
	_check(_player.test_move(_player.global_transform, Vector2(0, -55)), "放大岩石的真实碰撞体与可见底座相同位置")
	ObstacleField.damage_cell(rock)
	var kind := ObstacleField.damage_cell(rock)
	EventBus.obstacle_destroyed.emit(rock, (Vector2(rock) + Vector2.ONE * 0.5) * 32.0, kind)
	_check(kind == "rock" and not ObstacleField.nav_blocked_cell(rock + Vector2i.RIGHT),
			"两击碎岩后释放邻格导航余量")
	_check(nav.get_cell_source_id(rock + Vector2i.RIGHT) == 0, "真实导航层同步开放碎岩旁通路")
	await _step(3)
	_check(not _player.test_move(_player.global_transform, Vector2(0, -55)), "碎岩后真实角色可通过原底座碰撞位置")


func _prepare_active_bounty() -> void:
	var manager: BountyManager
	for child in _world.get_children():
		if child is BountyManager:
			manager = child
	var groups := {}
	for inst: MonsterInstance in WorldSim.sim.instances.values():
		if not manager._feasible(inst):
			continue
		var key := inst.region_id + "|" + inst.species.species_name
		if not groups.has(key):
			groups[key] = []
		groups[key].append(inst.id)
		if groups[key].size() >= 3:
			GameState.bounty = {"species": inst.species.species_name, "region_id": inst.region_id,
				"need": 3, "progress": 1, "gold": 30, "xp": 20, "original_need": 3,
				"original_gold": 30, "original_xp": 20, "adjusted": false, "target_ids": groups[key].duplicate()}
			manager._roll_delay = 0.0
			manager._push()
			break
	_check(not GameState.bounty.is_empty() and GameState.bounty["progress"] == 1,
			"以真实存活且战力可行的目标建立已进行赏金")


func _assert_room_context(idx: int, old_fog, old_landmarks: Array, old_bounty: Dictionary, label: String) -> void:
	_world._reveal_fog()
	_world._discover_nearby_checkpoints()
	_world._stream_pass()
	await _step(3)
	_check(GameState.explored == old_fog and GameState.discovered_landmarks == old_landmarks,
			label + "不揭露远方迷雾或地标")
	var home_id := BiomeMap.region_id_at(WorldConfig.spawn_pos())
	_check(_world._current_region_id == home_id and _region_events.all(func(id: String) -> bool: return id == home_id),
			label + "房间不提交远方群系")
	_check(_world._music_mode == "camp" and _world._in_camp, label + "保持营地室内音乐语义")
	_check(_world._nodes.is_empty() and _world._nest_nodes.is_empty(), label + "不流入远方怪物或巢穴")
	var radar: Minimap = _world.get_node("HUD").get_node("%Minimap")
	radar._refresh_navigation()
	_check(radar._target.get("id", "") == "room_exit:%d" % idx and radar._markers.is_empty()
			and radar._target.get("distance_px", INF) < 150.0, label + "雷达只指引当前房间出口")
	_check(ObstacleField.interior_index_at(ObstacleField.interior_pocket(idx) + Vector2(240, 0)) == -1,
			label + "室内语义不外溢到周围净空")
	for child in _world.get_children():
		if child is BountyManager:
			var candidates: Array = await child._local_targets()
			_check(candidates.is_empty(), label + "不使用口袋坐标发远方赏金")
			child._roll_bounty()
		elif child is WorldEventWatcher:
			_check(child._context()["local_region_id"] == "", label + "不观察口袋下的远方群系事件")
		elif child is Tutorial:
			_check(not child._is_local_event(BiomeMap.region_id_at(_player.global_position)),
					label + "首次分裂迁徙提示不使用远方群系")
		elif child is WorldDeco:
			_check(not child._ambient.emitting, label + "没有远方雨雪浮雾火星")
		elif child is VisionLighting:
			_check(child._terrain in ["", "plains"], label + "没有远方群系染色")
	_check(GameState.bounty == old_bounty, label + "保留原赏金目标进度与奖励")


func _test_house(idx: int) -> void:
	var door: Node2D = _world._town_doors[idx]
	var outside := door.global_position + Vector2(0, 32)
	_player.teleport_to(outside)
	await _step(4)
	_check(door.can_interact(), "门前真实入口区可交互%d" % idx)
	await _settle()
	_check(_player.global_position.distance_to(outside) < 1.0 and not _world._teleporting,
			"只走上门前不会自动传送%d" % idx)
	var before_mp := _player.current_mp
	var old_fog = GameState.explored.duplicate()
	var old_landmarks := GameState.discovered_landmarks.duplicate()
	var old_bounty := GameState.bounty.duplicate(true)
	_region_events.clear()
	if idx == 0:
		TouchInput.queue_attack()
	else:
		var event := InputEventAction.new()
		event.action = "attack"
		event.pressed = true
		Input.parse_input_event(event)
		await _step(2)
		event = InputEventAction.new()
		event.action = "attack"
		event.pressed = false
		Input.parse_input_event(event)
	await _settle()
	var center := ObstacleField.interior_pocket(idx)
	await _assert_room_context(idx, old_fog, old_landmarks, old_bounty, "进屋%d" % idx)
	_check(_player.global_position.distance_to(center + Vector2(0, 30)) < 1.0,
			"真实攻击输入明确进入房间%d" % idx)
	_check(_player.current_mp == before_mp and _player._attack_timer <= 0.0,
			"门交互不消耗法力/不残留攻击%d" % idx)
	_check(_player.get_node("Camera2D")._follow.distance_to(_player.global_position) < 1.0,
			"跨地图相机立即吸附%d" % idx)
	if idx == 0:
		GameState.save_enabled = true
		_check(GameState.save_now(), "房间内真实保存成功")
		GameState.save_enabled = false
		var output: Array = []
		var previous := OS.get_environment("HOTW_TEST_SAVE")
		OS.set_environment("HOTW_TEST_SAVE", ProjectSettings.globalize_path(GameState.SAVE_PATH))
		var code := OS.execute(OS.get_executable_path(), PackedStringArray([
			"--headless", "--path", ProjectSettings.globalize_path("res://"),
			"res://tests/town_interaction_test.tscn", "--quit-after", "15000", "--", "--interior-reader"
		]), output, true)
		OS.set_environment("HOTW_TEST_SAVE", previous)
		var completed := false
		for line: String in output:
			print(line)
			completed = completed or "=== TOWN INTERIOR COLD READER PASS ===" in line
		_check(code == 0 and completed, "室内存档冷进程继续及退出闭环")
	_player.teleport_to(center + Vector2(-120, 0))
	await _step(3)
	TouchInput.joystick_active = true
	TouchInput.move_vector = Vector2.LEFT
	await _step(30)
	TouchInput.reset()
	await _step(8)
	_check(_player.global_position.x >= center.x - 135.0,
			"真实移动不能穿过室内西墙%d" % idx)
	var host: Node2D
	for npc in get_tree().get_nodes_in_group("npcs"):
		if "landmark_id" in npc and npc.landmark_id == "town_host_%d" % idx:
			host = npc
	_check(host != null and host.interact_fn.call("", "", "")["kind"] == "shop",
			"室内保留真实补给服务%d" % idx)
	_player.teleport_to(center + Vector2(0, 82))
	await _step(4)
	TouchInput.queue_attack()
	await _settle()
	var back := door.global_position + Vector2(0, 90)
	_check(_player.global_position.distance_to(back) < 1.0, "明确出口返回对应屋外%d" % idx)
	var radar: Minimap = _world.get_node("HUD").get_node("%Minimap")
	radar._refresh_navigation()
	_check(radar._interior_index == -1 and GameState.bounty == old_bounty,
			"出屋恢复正常雷达并保留已进行赏金%d" % idx)
	await _settle()
	_check(_player.global_position.distance_to(back) < 1.0 and not _world._teleporting,
			"出口落点不会反弹入屋%d" % idx)
	_player.teleport_to(door.global_position + Vector2(0, -90))
	await _step(3)
	_check(not door.can_interact(), "房屋背面不抢占攻击交互%d" % idx)


func _test_return() -> void:
	var away := WorldConfig.spawn_pos() + Vector2(0, 720)
	_player.teleport_to(away)
	await _step(4)
	var checkpoint_count := GameState.discovered_checkpoints.size()
	EventBus.return_to_town_requested.emit()
	_check(_world._return_remaining > 0.0, "请求开启三秒回城引导")
	TouchInput.joystick_active = true
	TouchInput.move_vector = Vector2.RIGHT
	await _step(3)
	TouchInput.reset()
	_check(_world._return_remaining == 0.0 and not _world._teleporting, "移动输入打断回城")
	_player.teleport_to(away)
	await _step(3)
	EventBus.return_to_town_requested.emit()
	TouchInput.queue_attack()
	await _step(3)
	_check(_world._return_remaining == 0.0, "真实普攻打断回城")
	_player.teleport_to(away)
	await _step(3)
	EventBus.return_to_town_requested.emit()
	_player.take_damage(10.0, Vector2.RIGHT)
	await _step(3)
	_check(_world._return_remaining == 0.0, "真实受伤打断回城")
	await get_tree().create_timer(0.8).timeout
	_player.teleport_to(away)
	await _step(3)
	EventBus.return_to_town_requested.emit()
	EventBus.return_to_town_requested.emit()
	_check(_world._return_remaining == 0.0, "重复点击取消而非叠加回城")
	EventBus.return_to_town_requested.emit()
	await get_tree().create_timer(3.7).timeout
	await _step(4)
	_check(_player.global_position.distance_to(WorldConfig.spawn_pos()) < 1.0
			and not _world._teleporting and _world._return_remaining == 0.0,
			"完整真实引导返回唯一营地锚点")
	_check(_player.velocity.is_zero_approx() and _player._dash_timer == 0.0
			and _player._attack_timer == 0.0 and _player.collision_mask == Player.MASK_NORMAL,
			"回城清除位移/冲刺/攻击并恢复正常碰撞")
	_check(GameState.discovered_checkpoints.size() == checkpoint_count,
			"回城不解锁未知远方检查点")
	_check(Vector2(GameState.player_snapshot["position"][0], GameState.player_snapshot["position"][1])
			== WorldConfig.spawn_pos(), "完成传送立即更新保存快照")
	EventBus.return_to_town_requested.emit()
	_check(_world._return_remaining == 0.0, "已在营地不能重复引导")


func _leave() -> void:
	TouchInput.reset()
	_world.queue_free()
	await _step(3)
