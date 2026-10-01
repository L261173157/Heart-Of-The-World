## 世界状态回归：真实 Boss 生死轮次、菜单往返、独立进程冷启动、障碍与位置恢复。
## "$GODOT" --headless --path Code res://tests/world_persistence_test.tscn --quit-after 10000
## 自建沙盒档，冷启动子进程仅继承 HOTW_TEST_SAVE 指向的测试档，绝不碰真实进度。
extends Node

const MAIN_SCENE := preload("res://scenes/main/main.tscn")
const TEST_SEED := 777777
var _fails := 0
var _world: Node2D
var _player: Player


func _ready() -> void:
	WorldSim.set_process(false)  # tick 由测试显式推进，避免墙钟影响检查窗口
	get_tree().paused = true  # 冻结物理；禁用整棵节点树会摘除碰撞体但留下 RVO 回调
	GameState.save_enabled = false
	if "--cold-reader" in OS.get_cmdline_user_args():
		_cold_read.call_deferred()
	else:
		_run.call_deferred()


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  PASS  %s" % label)
	else:
		_fails += 1
		print("  FAIL  %s" % label)


func _enter_world() -> void:
	_world = MAIN_SCENE.instantiate()
	add_child(_world)
	_player = _world.get_node("Player")


func _leave_world() -> void:
	# 先让 deferred 挂层/生成队列排空，再退场；物理恢复一帧回收服务端 RID。
	await get_tree().process_frame
	await get_tree().process_frame
	_world.queue_free()
	await get_tree().process_frame
	get_tree().paused = false
	await get_tree().physics_frame
	await get_tree().process_frame
	get_tree().paused = true
	_world = null
	_player = null


func _run() -> void:
	seed(20261001)
	GameState.SAVE_PATH = "user://world_persistence_test_%d.json" % OS.get_process_id()
	GameState.reset_all()
	GameState.world_seed = TEST_SEED
	_test_seed_order()
	await get_tree().process_frame
	await _test_world_roundtrip()
	_test_new_adventure()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.SAVE_PATH))
	_finish()


## 选一个在旧种子有墙、存档种子无墙的合法坐标，入树同步断言（不等物理帧）。
func _test_seed_order() -> void:
	var candidates: Array[Vector2] = []
	BiomeMap.configure(TEST_SEED)
	ObstacleField.restore_destroyed([])
	for i in 150:
		var p := Vector2(10000.0 + i * 4096.0, 10000.0 + i * 3456.0)
		if not ObstacleField.blocks(p, 10.0):
			candidates.append(p)
	BiomeMap.configure(BiomeMap.DEFAULT_SEED)
	ObstacleField.restore_destroyed([])
	var saved_pos := Vector2.INF
	for p: Vector2 in candidates:
		if ObstacleField.blocks(p, 10.0) and ObstacleField.nudge_free(p, 10.0) != p:
			saved_pos = p
			break
	_check(saved_pos != Vector2.INF, "种子时序测试找到异世界墙格")
	if saved_pos == Vector2.INF:
		saved_pos = Vector2(20000, 20000)
	GameState.player_snapshot = {"position": [saved_pos.x, saved_pos.y], "hp": 80.0, "mp": 30.0}
	_enter_world()
	_check(BiomeMap.current_seed() == TEST_SEED and _player.global_position == saved_pos,
			"Player ready 前使用存档种子，不被旧世界障碍误挤走")
	# 死亡存档与正常复活必须落在同一最近安全点，不能回到这次登录点。
	_player.global_position = Vector2(600000, 600000)
	_player._is_dead = true
	var dead_snapshot: Dictionary = _player.save_snapshot()
	_player._respawn()
	_check(Vector2(dead_snapshot["position"][0], dead_snapshot["position"][1])
			== _player.global_position, "死亡窗口存档与实际复活位置一致")


func _find_destructible() -> Vector2i:
	for i in 150:
		var base := Vector2i(2000 + i * 73, 2000 + i * 67)
		for dy in 24:
			for dx in 24:
				var cell := base + Vector2i(dx, dy)
				var info := ObstacleField.sample_cell(cell)
				if not info.is_empty() and ObstacleField.DESTRUCTIBLE.has(info["kind"]):
					return cell
	return Vector2i(-1, -1)


func _chunk_has(chunk: Vector2i, cell: Vector2i) -> bool:
	for entry: Dictionary in ObstacleField.cells_of_chunk(chunk):
		if entry["cell"] == cell:
			return true
	return false


func _kill_boss(sim: EcologySim, boss_name: String) -> void:
	for inst: MonsterInstance in sim.instances.values():
		if inst.is_alive and inst.species.species_name == boss_name:
			sim.report_killed(inst.id)


func _test_interrupted_obstacle_mount(chunk: Vector2i) -> void:
	var layer := ObstacleTileLayer.new()
	add_child(layer)
	layer._on_chunk_ready(chunk)
	var bodies: Array[WeakRef] = []
	for entry: Dictionary in layer._laying.values():
		bodies.append(weakref(entry["body"]))
	_check(not bodies.is_empty() and bodies[0].get_ref().get_parent() == null,
			"障碍铺设中仍有尚未挂树的碰撞体")
	layer.queue_free()  # 不消费任何铺设预算，直接模拟暂停期间回菜单
	await get_tree().process_frame
	var all_freed := true
	for body: WeakRef in bodies:
		all_freed = all_freed and body.get_ref() == null
	_check(all_freed, "立即卸载障碍层释放全部未挂树碰撞体")


func _test_world_roundtrip() -> void:
	var sim: EcologySim = _world._sim
	var dg: Dictionary = _world._dungeon_list()[0]
	var patch: String = dg["patch_id"]
	var boss_name: String = WorldConfig.TERRAIN_BOSSES[dg["terrain"]]
	var key_id: String = EconomyMath.DUNGEON_KEYS[dg["terrain"]]
	_player.global_position = dg["center"]
	sim.tick()
	_world._update_dungeons()
	var chest: Node = _world._chests[patch]
	GameState.add_item(key_id, 3)
	var gold_before := GameState.gold
	chest.interact()
	_check(sim.alive_count_of_species(boss_name) > 0
			and int(sim.boss_respawn_timers[boss_name]) > 0 and chest.locked
			and GameState.gold == gold_before and GameState.count_item(key_id) == 3,
			"活 Boss 满计时器仍锁箱，不能扣钥匙或发奖励")
	GameState.save_enabled = true
	_check(GameState.save_now() and GameState._ecology_cache != null, "预热含活 Boss 的自动存档缓存")
	GameState.save_enabled = false
	_kill_boss(sim, boss_name)
	chest.interact()  # 不等 _update_dungeons，交互现场读取已死亡
	_check(GameState._ecology_cache == null, "开箱使旧活 Boss 缓存失效，奖励与死亡窗口同档")
	_check(chest.taken and GameState.chest_claims.has(patch)
			and GameState.gold > gold_before and GameState.count_item(key_id) == 2,
			"真实击杀后开箱，一次领取并消耗一把钥匙")
	gold_before = GameState.gold
	chest.interact()
	_check(GameState.gold == gold_before and GameState.count_item(key_id) == 2,
			"重复交互不重复发奖或扣钥匙")
	# 流式往返不得影响领取记录。
	_player.global_position = dg["center"] + Vector2(10000, 10000)
	_world._update_dungeons()
	_check(not _world._chests.has(patch), "离开城塞回收宝箱节点")
	_player.global_position = dg["center"]
	_world._update_dungeons()
	_check(_world._chests[patch].taken, "流式重建保留本轮已开状态")
	# 实际破块、同种子全量覆盖重置须同时失效分块/导航/半血缓存。
	var cell := _find_destructible()
	_check(cell != Vector2i(-1, -1), "找到真实可破坏障碍")
	var cell_key := "%d,%d" % [cell.x, cell.y]
	var pos := (Vector2(cell) + Vector2(0.5, 0.5)) * ObstacleField.CELL
	var chunk := Vector2i(cell.x >> 4, cell.y >> 4) * 512
	_check(_chunk_has(chunk, cell) and ObstacleField.nav_blocked_at(pos), "障碍已进入视觉与导航缓存")
	await _test_interrupted_obstacle_mount(chunk)
	ObstacleField.damage_cell(cell)
	ObstacleField.restore_destroyed([])
	_check(ObstacleField.damage_cell(cell) == "", "覆盖层完整恢复时清除旧局半血耐久")
	_check(ObstacleField.damage_cell(cell) != "", "第二次命中实际摧毁障碍")
	_check(not _chunk_has(chunk, cell) and not ObstacleField.nav_blocked_at(pos),
			"破块后视觉与导航缓存都移除障碍")
	ObstacleField.restore_destroyed([])
	_check(_chunk_has(chunk, cell) and ObstacleField.nav_blocked_at(pos),
			"同种子恢复空覆盖层后视觉与导航均复原")
	ObstacleField.restore_destroyed([cell_key])
	_check(not _chunk_has(chunk, cell) and not ObstacleField.nav_blocked_at(pos),
			"同种子恢复摧毁覆盖层后视觉与导航均重新开放")
	_player.global_position = pos
	# 不先 save：依赖世界退出捕获 overlay，验证内存缓存本身也正确。
	await _leave_world()
	_check(GameState.destroyed_cells.has(cell_key), "回菜单时捕获最新摧毁覆盖层")
	_enter_world()
	_check(_player.global_position == pos and ObstacleField.sample_cell(cell).is_empty(),
			"继续冒险先恢复已毁格，再恢复该格内玩家精确位置")
	_player.global_position = dg["center"]
	_world._update_dungeons()
	chest = _world._chests[patch]
	chest.interact()
	_check(chest.taken and GameState.gold == gold_before and GameState.count_item(key_id) == 2,
			"菜单往返不能再次领取同一次 Boss 讨伐宝箱")
	_player.global_position = pos
	GameState.save_enabled = true
	_check(GameState.save_now(), "世界状态写入独立测试档")
	GameState.save_enabled = false
	await _leave_world()
	# 全新进程：autoload 在没有运行态 ObstacleField 的菜单先加载、再保存、再继续。
	var output: Array = []
	var previous_save := OS.get_environment("HOTW_TEST_SAVE")
	OS.set_environment("HOTW_TEST_SAVE", ProjectSettings.globalize_path(GameState.SAVE_PATH))
	var exit_code := OS.execute(OS.get_executable_path(), PackedStringArray([
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"res://tests/world_persistence_test.tscn", "--quit-after", "10000", "--", "--cold-reader"
	]), output, true)
	OS.set_environment("HOTW_TEST_SAVE", previous_save)
	var child_completed := false
	for entry: String in output:
		print(entry)
		child_completed = child_completed or "=== 世界持久化冷启动子进程通过 ===" in entry
	_check(exit_code == 0 and child_completed, "独立进程冷启动回归通过")
	# 沿父进程已有快照恢复，本次实际离屏重生必须立即清领取记录。
	_enter_world()
	sim = _world._sim
	_player.global_position = WorldConfig.spawn_pos()
	_world._update_dungeons()
	_check(not _world._chests.has(patch) and GameState.chest_claims.has(patch),
			"重生前宝箱离屏，仍保留上一轮领取记录")
	GameState.save_enabled = true
	_check(GameState.save_now() and GameState._ecology_cache != null, "预热含旧已开窗口的自动存档缓存")
	GameState.save_enabled = false
	for _tick in sim.find_species(boss_name).boss_respawn_ticks + 120:
		sim.tick()
		if sim.alive_count_of_species(boss_name) > 0:
			break
	_check(sim.alive_count_of_species(boss_name) > 0 and not GameState.chest_claims.has(patch),
			"真实离屏重生事件重置领取记录，不依赖宝箱轮询")
	_check(GameState._ecology_cache == null, "真实重生使旧死亡窗口缓存失效")
	_player.global_position = dg["center"]
	_world._update_dungeons()
	chest = _world._chests[patch]
	_check(chest.locked and not chest.taken, "重生 Boss 锁住新一轮宝箱")
	# 模拟上次画面已解锁而 Boss 刚重生的间隙：交互仍必须重新读取权威状态。
	chest.locked = false
	chest.interact()
	_check(chest.locked and GameState.gold == gold_before and GameState.count_item(key_id) == 2,
			"重生与流式轮询之间的旧解锁画面也不能绕过活 Boss")
	_kill_boss(sim, boss_name)
	chest.interact()
	_check(GameState.gold > gold_before and GameState.count_item(key_id) == 1,
			"下一轮真实击杀允许且只允许再领取一次")
	await _leave_world()


func _cold_read() -> void:
	_check(GameState.world_seed == TEST_SEED and GameState.chest_claims.size() == 1
			and GameState.destroyed_cells.size() == 1, "冷启动加载种子、已开箱和已毁格")
	if typeof(GameState.player_snapshot) != TYPE_DICTIONARY or GameState.destroyed_cells.is_empty():
		_check(false, "冷启动测试档必须包含玩家与障碍快照")
		_finish()
		return
	var pos_data: Array = GameState.player_snapshot["position"]
	var saved_pos := Vector2(pos_data[0], pos_data[1])
	var cell_key: String = GameState.destroyed_cells[0]
	ObstacleField.restore_destroyed([])  # 全新进程尚未进入世界，运行态覆盖层为空
	GameState.save_enabled = true
	_check(GameState.save_now(), "冷启动菜单保存成功")
	GameState.save_enabled = false
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GameState.SAVE_PATH))
	_check(cell_key in saved.get("destroyed", []) and saved.get("chest_claims", {}).size() == 1,
			"冷启动菜单保存不把持久化障碍或宝箱记录覆盖为空")
	_enter_world()
	_check(_player.global_position == saved_pos and not ObstacleField.blocks(saved_pos, 10.0),
			"冷启动先恢复种子与已毁格，玩家位置逐位不变")
	var dg: Dictionary = _world._dungeon_list()[0]
	var patch: String = dg["patch_id"]
	var key_id: String = EconomyMath.DUNGEON_KEYS[dg["terrain"]]
	var gold_before := GameState.gold
	var keys_before := GameState.count_item(key_id)
	_player.global_position = dg["center"]
	_world._update_dungeons()
	var chest: Node = _world._chests[patch]
	chest.interact()
	_check(chest.taken and not chest.locked and GameState.gold == gold_before
			and GameState.count_item(key_id) == keys_before, "冷启动不能重复领取已开宝箱")
	await get_tree().process_frame
	await _leave_world()
	_finish()


func _test_new_adventure() -> void:
	# 仍在菜单，无采样触发懒重建也不能把上一世界摧毁层写进新档。
	GameState.save_enabled = true
	GameState.reset_all()
	GameState.save_enabled = false
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GameState.SAVE_PATH))
	_check(GameState.chest_claims.is_empty() and GameState.destroyed_cells.is_empty()
			and ObstacleField.destroyed_list().is_empty()
			and saved.get("chest_claims", {}).is_empty() and saved.get("destroyed", []).is_empty(),
			"新的冒险即时保存不继承旧宝箱或旧障碍覆盖层")


func _finish() -> void:
	if _fails == 0:
		if "--cold-reader" in OS.get_cmdline_user_args():
			print("=== 世界持久化冷启动子进程通过 ===")
		else:
			print("=== 世界持久化回归全部通过 ===")
	else:
		print("=== 世界持久化 %d 项失败 ===" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
