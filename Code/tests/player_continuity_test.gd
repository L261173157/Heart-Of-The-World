## 真实主菜单往返与冷启动：剩余游戏秒数冻结，不恢复半刀或架盾手势。
extends Node

var _checks := 0
var _fails := 0
var _player: Player
var _world: Node

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.save_enabled = false
	WorldSim.set_process(false)
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok: _fails += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])

func _frames(count := 3) -> void:
	for _i in count: await get_tree().process_frame

func _enter_world() -> void:
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")
	await _frames()
	_world = get_tree().current_scene
	_player = _world.get_node("Player")

func _same_timers(expected: Dictionary, label: String) -> void:
	var actual: Dictionary = _player.save_snapshot().get("combat_timers", {})
	for key: String in expected:
		_check(is_equal_approx(float(actual.get(key, -1.0)), float(expected[key])), "%s %s" % [label, key])

func _menu_roundtrip() -> void:
	_world.get_node("HUD")._back_to_menu()
	get_tree().paused = true
	await _frames()
	get_tree().current_scene.get_node("MenuBox/StartBtn").pressed.emit()
	await _frames()
	_world = get_tree().current_scene
	_player = _world.get_node("Player")

func _run() -> void:
	get_tree().current_scene = null # 本测试控制器保留在根节点，实际世界/菜单由 SceneTree 切换。
	if "--cold-reader" in OS.get_cmdline_user_args():
		await _cold_read()
		_finish()
		return
	GameState.reset_all()
	GameState.world_seed = 20260908
	GameState.stats.strength = 20
	GameState.stats.intellect = 20
	await _enter_world()
	_player.current_hp = 1.0
	_player.current_mp = _player.stats.max_mp()
	_player._try_heal()
	_player._try_empower()
	get_tree().paused = true
	_check(_player._heal_cd == 8.0 and _player._empower_cd == 15.0 and _player._empower_timer == 6.0,
		"真实治疗和强化扣资源并建立计时")
	# 其余短计时也必须跨场景保留，半招与输入队列则必须取消。
	_player._attack_cooldown = 0.7
	_player._dash_cd = 0.8
	_player._heavy_cd = 3.0
	_player._bolt_cd = 0.6
	_player._dash_buff_timer = 0.5
	_player._hurt_iframes = 0.2
	_player._protect_timer = 0.4
	_player._attack_timer = 0.2
	_player._attack_buffered = true
	_player.guard_state = "holding"
	_player.guard_charge = 3
	var expected := {"attack": 0.7, "dash": 0.8, "heavy": 3.0, "bolt": 0.6,
		"heal": 8.0, "empower": 15.0, "empower_buff": 6.0, "dash_buff": 0.5,
		"hurt_iframes": 0.2, "protect": 0.4, "guard_break": 0.0}
	var hp := _player.current_hp
	var mp := _player.current_mp
	GameState.save_enabled = true
	for repeat in 2:
		await _menu_roundtrip()
		_same_timers(expected, "菜单继续%d保留" % repeat)
		_check(_player.current_hp == hp and _player.current_mp == mp, "菜单继续保持已付血蓝")
		_check(_player.guard_state == "idle" and _player.guard_charge == 0 and _player._attack_timer == 0
			and not _player._attack_buffered, "菜单继续不恢复半刀/旧输入/架盾蓄力")
		_player._try_heal()
		_check(_player.current_hp == hp and _player.current_mp == mp, "菜单重进不能重复治疗")
		_check(_player.visual.modulate == Color(1.0, 0.88, 0.55), "强化剩余计时恢复金色表现")
	await get_tree().create_timer(0.3, true, false, true).timeout
	_same_timers(expected, "暂停墙钟不消耗")
	GameState.save_now()
	var file := FileAccess.open(GameState.SAVE_PATH + ".expected", FileAccess.WRITE)
	file.store_string(JSON.stringify({"timers": expected, "hp": hp, "mp": mp}))
	file.close()
	var output: Array = []
	var code := OS.execute(OS.get_executable_path(), PackedStringArray([
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"res://tests/player_continuity_test.tscn", "--quit-after", "10000", "--", "--cold-reader"
	]), output, true)
	var complete := false
	for entry: String in output:
		print(entry)
		complete = complete or "PLAYER CONTINUITY COLD PASS" in entry
	_check(code == 0 and complete, "独立冷进程恢复剩余计时")
	GameState.save_enabled = false
	_player._guard_break_timer = 0.45
	_player.guard_state = "broken"
	await _menu_roundtrip()
	_check(_player.guard_state == "broken" and is_equal_approx(_player._guard_break_timer, 0.45),
		"菜单继续不能清除破防硬直")
	# 真物理帧只扣游戏秒数，回到城内关闭环境干扰。
	_player.guard_state = "idle"
	_player._guard_break_timer = 0.0
	get_tree().paused = false
	await get_tree().create_timer(0.25, false, true).timeout
	get_tree().paused = true
	_check(_player._heal_cd < 8.0 and _player._heal_cd > 7.4 and _player._empower_timer < 6.0,
		"恢复游戏后真实物理帧继续扣计时")
	# 有效血蓝不因坏计时被抛弃；旧档缺字段仍走既有零计时默认。
	var snapshot := _player.save_snapshot()
	snapshot["combat_timers"] = {"heal": "bad", "empower": INF, "heavy": -8, "bolt": 999, "unknown": 99}
	GameState.player_snapshot = GameState._sanitize_player_snapshot(snapshot)
	_player._restore_saved_state()
	_check(_player._heal_cd == 0 and _player._empower_cd == 0 and _player._heavy_cd == 0
		and _player._bolt_cd == CharacterStats.BOLT_COOLDOWN, "坏计时逐字段隔离、有限值及上限校验")
	GameState.player_snapshot = {"position": [20000, 20000], "hp": 44, "mp": 22}
	_player._restore_saved_state()
	_check(_player.current_hp == 44 and _player.current_mp == 22 and _player._bolt_cd == 0,
		"旧档缺计时保持血蓝与零冷却兼容")
	_player._heal_cd = 5
	_player._empower_timer = 3
	_player._protect_timer = 0.0
	_player._hurt_iframes = 0.0
	_player.take_damage(_player.stats.max_hp() * 100.0, _player.global_position + Vector2(30, 0))
	_check(_player._is_dead, "真实致死受击进入死亡窗口")
	GameState.player_snapshot = _player.save_snapshot()
	GameState.save_enabled = true
	GameState._notification(NOTIFICATION_APPLICATION_PAUSED)
	GameState.save_enabled = false
	var dead_timers := {}
	for key: String in expected: dead_timers[key] = 0.0
	dead_timers["protect"] = Player.RESPAWN_PROTECT
	file = FileAccess.open(GameState.SAVE_PATH + ".expected", FileAccess.WRITE)
	file.store_string(JSON.stringify({"timers": dead_timers, "hp": _player.stats.max_hp(),
		"mp": _player.stats.max_mp(), "position": GameState.player_snapshot.position}))
	file.close()
	output.clear()
	code = OS.execute(OS.get_executable_path(), PackedStringArray([
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"res://tests/player_continuity_test.tscn", "--quit-after", "10000", "--", "--cold-reader"
	]), output, true)
	complete = false
	for entry: String in output:
		print(entry)
		complete = complete or "PLAYER CONTINUITY COLD PASS" in entry
	_check(code == 0 and complete, "真实死亡窗口后台档在独立进程按复活状态恢复")
	_player._respawn()
	var respawn := _player.save_snapshot()
	_player._restore_saved_state()
	_check(_player._heal_cd == 0 and _player._empower_timer == 0 and _player._protect_timer == Player.RESPAWN_PROTECT
		and _player.current_hp == _player.stats.max_hp() and _player.current_mp == _player.stats.max_mp()
		and _player.save_snapshot() == respawn, "死亡窗口冷启动与实际复活同为满状态和保护")
	DirAccess.remove_absolute(GameState.SAVE_PATH + ".expected")
	_finish()

func _cold_read() -> void:
	get_tree().paused = true
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GameState.SAVE_PATH + ".expected"))
	# 冷进程尚在菜单时再保存，确保 GameState 的字段清洗不会吞计时。
	GameState.save_enabled = true
	GameState.save_now()
	GameState.save_enabled = false
	await _enter_world()
	_same_timers(expected.timers, "冷进程保留")
	_check(_player.current_hp == float(expected.hp) and _player.current_mp == float(expected.mp), "冷进程保留血蓝")
	if expected.has("position"):
		_check(_player.global_position == Vector2(expected.position[0], expected.position[1])
			and not _player._is_dead and _player.guard_state == "idle", "死亡窗口冷启动恢复安全点且无死亡/架盾残留")
	print("PLAYER CONTINUITY COLD %s" % ("PASS" if _fails == 0 else "FAIL"))

func _finish() -> void:
	GameState.save_enabled = false
	get_tree().paused = false
	print("=== PLAYER CONTINUITY %s (%d checks) ===" % ["PASS" if _fails == 0 else "FAIL", _checks])
	get_tree().quit(0 if _fails == 0 else 1)
