## 真实世界装配回归：Boss 城塞锚点、已发现复活点、死亡窗口与冷读档。
extends Node

const MAIN := preload("res://scenes/main/main.tscn")
var _failures := 0
var _checks := 0
var _world: Node2D
var _player: Player


func _ready() -> void:
	GameState.save_enabled = false
	WorldSim.set_process(false)
	get_tree().paused = true
	if "--cold-reader" in OS.get_cmdline_user_args():
		_cold_read.call_deferred()
	else:
		_run.call_deferred()


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print("  %s %s" % ["PASS" if ok else "FAIL", label])


func _enter() -> void:
	_world = MAIN.instantiate()
	add_child(_world)
	_player = _world.get_node("Player")


func _leave() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_world.queue_free()
	await get_tree().process_frame
	get_tree().paused = false
	await get_tree().physics_frame
	await get_tree().process_frame
	get_tree().paused = true


func _run() -> void:
	GameState.SAVE_PATH = "user://gameplay_world_%d.json" % OS.get_process_id()
	GameState.reset_all()
	GameState.world_seed = BiomeMap.DEFAULT_SEED
	_enter()
	var all := WorldConfig.checkpoints()
	var dg: Dictionary = ObstacleField.dungeons()[0]
	var id: String = "fortress:" + dg["patch_id"]
	var checkpoint: Vector2 = all[id]["position"]
	var center: Vector2 = dg["center"]
	_check(not GameState.discovered_checkpoints.has(id), "新档不会解锁未到访城塞")
	_check(WorldConfig.nearest_checkpoint_respawn(center, GameState.discovered_checkpoints)
			== WorldConfig.spawn_pos(), "未知远方死亡仅使用已拥有的家园")
	_player.global_position = center
	_world._discover_nearby_checkpoints()
	_check(GameState.discovered_checkpoints.has(id), "真实世界发现扫描解锁城塞入口")
	var count := GameState.discovered_checkpoints.size()
	_world._discover_nearby_checkpoints()
	_check(GameState.discovered_checkpoints.size() == count, "重复发现不重复追加检查点")
	_check(checkpoint.distance_to(center) <= 600.0 and checkpoint.distance_to(center) > 250.0,
			"城塞检查点在南门外且距挑战不足四秒基础步行")
	_check(not ObstacleField.blocks(checkpoint, 12.0)
			and ObstacleField.liquid_kind_at(checkpoint) == "", "城塞复活点无墙无岩浆")
	_player._is_dead = true
	var snapshot: Dictionary = _player.save_snapshot()
	_check(Vector2(snapshot["position"][0], snapshot["position"][1]) == checkpoint,
			"死亡期间保存使用已发现的最近检查点")
	_player._respawn()
	_check(_player.global_position == checkpoint and not _player._is_dead
			and _player.current_hp == GameState.stats.max_hp(), "真实复活回入口并恢复战斗状态")
	# 所有生成种子的点位都要能站立，非法/旧世界 id 不能授予位置。
	for item_id: String in all:
		var p: Vector2 = all[item_id]["position"]
		_check(not ObstacleField.blocks(p, 12.0) and ObstacleField.liquid_kind_at(p) == "",
				"检查点可站立：" + item_id)
	_check(not GameState.discover_checkpoint("fortress:does_not_exist"), "拒绝伪造检查点 id")
	# Boss 生命周期通过真实 game_world 装配，不只检查纯逻辑辅助函数。
	for species_name: String in WorldConfig.boss_anchors():
		var sim: EcologySim = _world._sim
		var anchor: Dictionary = WorldConfig.boss_anchors()[species_name]
		var victim: MonsterInstance
		for inst: MonsterInstance in sim.instances.values():
			if inst.is_alive and inst.species.species_name == species_name:
				victim = inst
				break
		_check(victim != null and victim.region_id == anchor["region_id"]
				and victim.spawn_pos == anchor["position"], "初生 Boss 与家园同锚：" + species_name)
		if victim == null:
			continue
		sim.report_killed(victim.id)
		sim.boss_respawn_timers[species_name] = 0
		sim.tick()
		var reborn: MonsterInstance
		for inst: MonsterInstance in sim.instances.values():
			if inst.is_alive and inst.species.species_name == species_name:
				reborn = inst
		_check(reborn != null and reborn.region_id == anchor["region_id"]
				and reborn.spawn_pos == anchor["position"], "真实 tick Boss 复生仍在同一城塞：" + species_name)
	# 已发现 NPC 地标是旧档迁移的唯一营地凭据，不借用迷雾大格。
	var camp_lm := ""
	for lm: Dictionary in LandmarkRegistry.landmarks():
		if LandmarkRegistry.NPC_BY_KIND.has(lm["kind"]):
			camp_lm = lm["id"]
			break
	GameState.discovered_landmarks.append(camp_lm)
	_world._restore_discovered_checkpoints()
	_check(GameState.discovered_checkpoints.has("landmark:" + camp_lm), "旧档已发现营地迁移为检查点")
	GameState.save_enabled = true
	_check(GameState.save_now(), "真实存档写入检查点与角色位置")
	GameState.save_enabled = false
	await _leave()
	var output: Array = []
	var previous_save := OS.get_environment("HOTW_TEST_SAVE")
	OS.set_environment("HOTW_TEST_SAVE", ProjectSettings.globalize_path(GameState.SAVE_PATH))
	var exit_code := OS.execute(OS.get_executable_path(), PackedStringArray([
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"res://tests/gameplay_world_test.tscn", "--quit-after", "10000", "--", "--cold-reader"
	]), output, true)
	OS.set_environment("HOTW_TEST_SAVE", previous_save)
	var completed := false
	for entry: String in output:
		print(entry)
		completed = completed or "=== CHECKPOINT COLD READER PASS ===" in entry
	_check(exit_code == 0 and completed, "独立进程冷启动保留检查点、原地继续与再次死亡")
	GameState.discovered_checkpoints.clear()
	GameState._load()
	_check(not GameState.discovered_checkpoints.is_empty(), "重新读取真实保存文件")
	_check(GameState.discovered_checkpoints.has(id)
			and GameState.discovered_checkpoints.has("landmark:" + camp_lm), "检查点重新读档往返")
	_enter()
	_check(_player.global_position == checkpoint, "退出/继续保持复活点位置")
	_player.global_position = center
	_player._is_dead = true
	_player._respawn()
	_check(_player.global_position == checkpoint, "重复死亡仍回最近已发现入口")
	await _leave()
	GameState.reset_all()
	_check(GameState.discovered_checkpoints.is_empty(), "新冒险清除旧世界检查点")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.SAVE_PATH))
	print("=== 玩法世界回归%s（%d项，失败%d） ===" % ["全部通过" if _failures == 0 else "失败", _checks, _failures])
	get_tree().quit(0 if _failures == 0 else 1)


func _cold_read() -> void:
	_check(not GameState.discovered_checkpoints.is_empty(), "冷启动 autoload 读到已发现点")
	_enter()
	var dg: Dictionary = ObstacleField.dungeons()[0]
	var id: String = "fortress:" + dg["patch_id"]
	var checkpoint: Vector2 = WorldConfig.checkpoints()[id]["position"]
	_check(GameState.discovered_checkpoints.has(id) and _player.global_position == checkpoint,
			"新进程世界装配保持入口位置")
	_player.global_position = dg["center"]
	_player._is_dead = true
	_player._respawn()
	_check(_player.global_position == checkpoint, "新进程死亡选择原已发现入口")
	await _leave()
	if _failures == 0:
		print("=== CHECKPOINT COLD READER PASS ===")
	get_tree().quit(0 if _failures == 0 else 1)
