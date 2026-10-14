## 审计修复：每个阶段由 Python 在独立进程启动，直接使用真实菜单/世界与存档入口。
extends Node

class InterruptedRestore extends "res://autoload/game_state.gd":
	func _restore_save_data(data: Dictionary) -> bool:
		gold = int(data.get("gold", 0))
		return false # 模拟后续恢复被中断，绝不走完成标记。

class InterruptedEquipmentRestore extends "res://autoload/game_state.gd":
	func _restore_equipment_state(_data: Dictionary) -> bool:
		return false # 内层恢复失败也必须上传给外层完成标记。

var failures := 0
var phase := ""

func _ready() -> void:
	GameState.save_enabled = false
	GameState.set_process(false)
	WorldSim.set_process(false)
	phase = OS.get_cmdline_user_args()[0]
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	print("  %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok: failures += 1

func _run() -> void:
	match phase:
		"load_guard":
			var original := FileAccess.get_file_as_bytes(GameState.SAVE_PATH)
			var probe := InterruptedRestore.new()
			probe.SAVE_PATH = GameState.SAVE_PATH
			probe.stats = CharacterStats.new()
			probe._load()
			check(probe.gold == 123 and probe._load_incomplete, "中断恢复后部分内存不会被标记为完成")
			check(not probe.save_now() and probe._loaded_save_bytes == original and FileAccess.get_file_as_bytes(GameState.SAVE_PATH) == original, "加载中断写保护保留原始字节")
			probe.free()
			var nested := InterruptedEquipmentRestore.new()
			nested.SAVE_PATH = GameState.SAVE_PATH
			nested.stats = CharacterStats.new()
			nested._load()
			check(nested._load_incomplete and not nested.save_now() and FileAccess.get_file_as_bytes(GameState.SAVE_PATH) == original, "嵌套装备恢复失败传播为不可覆盖状态")
			nested.free()
		"load_invalid_root":
			var original := FileAccess.get_file_as_bytes(GameState.SAVE_PATH)
			GameState.save_enabled = true
			check(GameState._load_incomplete and not GameState.save_now() and FileAccess.get_file_as_bytes(GameState.SAVE_PATH) == original, "解析失败/非字典存档禁止后续自动覆盖")
		"generation_new":
			check(GameState.world_generation == 2, "无档首启使用新世界代次")
			GameState.reset_all()
			check(GameState.world_generation == 2, "明确新冒险使用新世界代次")
			GameState.save_enabled = true
			check(GameState.save_now() and int(_read().world_generation) == 2, "新世界代次完整落盘")
		"generation_current":
			check(GameState.world_generation == 2 and GameState.world_generation_supported(), "新世界跨进程保持代次2")
			GameState.save_enabled = true
			check(GameState.save_now(), "已知代次可正常保存")
		"generation_legacy":
			check(GameState.world_generation == 1, "缺少代次的旧档固定恢复旧世界")
			var original := FileAccess.get_file_as_bytes(GameState.SAVE_PATH)
			GameState.save_enabled = true
			check(GameState.save_now() and int(_read().world_generation) == 1, "旧世界不因升级切换锚点")
			var backup := GameState.SAVE_PATH + ".pre-equipment-v17.bak"
			var alternate := GameState.SAVE_PATH + ".pre-equipment-" + original.hex_encode().sha256_text().substr(0, 16) + ".bak"
			check(FileAccess.get_file_as_bytes(backup) == original or (FileAccess.file_exists(alternate) and FileAccess.get_file_as_bytes(alternate) == original), "v19升级保留原始字节备份")
		"generation_future":
			var original := FileAccess.get_file_as_bytes(GameState.SAVE_PATH)
			GameState.save_enabled = true
			check(not GameState.world_generation_supported() and not GameState.save_now() and FileAccess.get_file_as_bytes(GameState.SAVE_PATH) == original, "未来/非法世界代次只读且原档逐字节不变")
			var menu := preload("res://scenes/ui/main_menu.tscn").instantiate()
			add_child(menu)
			menu.get_node("%StartBtn").pressed.emit()
			check(not menu._starting and str(menu.get_node("%MenuToast").text).contains("不支持"), "未知世界禁止以另一套地形启动")
			menu.free()
		"seed":
			GameState.reset_all()
			GameState.world_seed = BiomeMap.DEFAULT_SEED
			GameState.gold = 123
			GameState.add_item("onigiri", 3)
			GameState.receive_equipment(EquipmentCatalog.mint_item(EquipmentCatalog.generate(99, 5, 2, "physical_sword"), "audit:kept"))
			GameState.ecology_snapshot = {"tick": 23, "day_time": 0.3, "game_day": 0, "instances": []}
			GameState.save_enabled = true
			check(GameState.save_now(), "生成包含装备、物品及生态的真实存档")
		"tutorial":
			check(GameState.gold == 123 and GameState.equipment_state.items.has("audit:kept") and GameState.count_item("onigiri") == 3, "坏引导值不损坏金币/装备/库存")
			check(GameState.ecology_snapshot is Dictionary and int(GameState.ecology_snapshot.get("tick", -1)) == 23, "坏引导值不打断生态恢复")
			var expected := OS.get_environment("HOTW_EXPECT_FLAG") == "1"
			check(GameState.tutorial_flags.has("welcome") == expected and GameState.tutorial_flags.has("other"), "bool/旧数字及非法类型逐字段恢复")
			GameState.save_enabled = true
			check(GameState.save_now(), "消毒后可保存完整恢复状态")
		"midnight_seed":
			GameState.reset_all()
			GameState.world_seed = BiomeMap.DEFAULT_SEED
			BiomeMap.configure(GameState.world_seed, GameState.world_generation)
			var world := preload("res://scenes/main/main.tscn").instantiate()
			add_child(world)
			for frame in 20: await get_tree().process_frame
			world.process_mode = Node.PROCESS_MODE_DISABLED
			WorldSim.resume_clock(0.998, 0)
			GameState.save_enabled = true
			check(GameState.save_now(), "午夜前完整缓存保存")
			var immediate_day := []
			var on_midnight := func(day: int) -> void:
				check(WorldSim.day_time < 0.01, "跨日同步订阅者读到新相位")
				immediate_day.append(day)
			EventBus.game_day_advanced.connect(on_midnight)
			WorldSim._process(0.6)
			EventBus.game_day_advanced.disconnect(on_midnight)
			check(immediate_day == [1], "一次跨午夜只广播一次游戏日")
			WorldSim._process(2.0)
			get_tree().paused = true
			GameState._process(2.1)
			get_tree().paused = false
			var saved := _read()
			check(GameState.stats.age_days == 1 and int(saved.ecology.game_day) == 1 and saved.ecology.day_time < 0.02, "午夜自动档年龄与最新日相同时提交")
			GameState.save_enabled = false
			world.queue_free()
			await get_tree().process_frame
		"midnight_resume":
			var world := preload("res://scenes/main/main.tscn").instantiate()
			add_child(world)
			world.process_mode = Node.PROCESS_MODE_DISABLED
			WorldSim._process(0.6)
			check(GameState.stats.age_days == 1 and WorldSim.game_day == 1, "跨进程恢复不重复衰老")
			GameState.save_enabled = true
			check(GameState.save_now() and GameState.save_now(false), "午夜恢复后的完整档和缓存档均成功")
			GameState.save_enabled = false
			world.queue_free()
			await get_tree().process_frame
		"quit":
			GameState.save_enabled = true
			GameState.set_setting("volume", 0.8)
			GameState.save_now()
			var menu := preload("res://scenes/ui/main_menu.tscn").instantiate()
			add_child(menu)
			menu.find_child("VolumeSlider", true, false).value = 0.15
			print("SAVE_AUDIT quit BUTTON")
			menu.get_node("%QuitBtn").pressed.emit()
			return
		"quit_failure", "reset_failure":
			GameState.save_enabled = true
			GameState.gold = 123
			GameState.save_now()
			var before := FileAccess.get_file_as_bytes(GameState.SAVE_PATH)
			DirAccess.make_dir_absolute(GameState.SAVE_PATH + ".tmp")
			var menu := preload("res://scenes/ui/main_menu.tscn").instantiate()
			add_child(menu)
			if phase == "quit_failure":
				GameState.set_setting("volume", 0.15)
				menu.get_node("%QuitBtn").pressed.emit()
				await get_tree().process_frame
				check(str(menu.get_node("%MenuToast").text).contains("失败"), "退出失败留在菜单并显示未保存")
			else:
				menu.get_node("%NewBtn").pressed.emit()
				menu.get_node("%NewConfirmBtn").pressed.emit()
				check(GameState.gold == 0, "重置失败保留新冒险内存")
				menu.get_node("%ArchiveBtn").pressed.emit()
				check(not menu.get_node("%ArchiveSave").disabled, "空进度新冒险保存失败仍提供手动重试")
				check(str(menu.get_node("%MenuToast").text).contains("失败"), "重置失败不谎报清空成功")
			check(FileAccess.get_file_as_bytes(GameState.SAVE_PATH) == before and GameState._save_timer > 0, "失败保留原磁盘字节并排队重试")
			DirAccess.remove_absolute(GameState.SAVE_PATH + ".tmp")
			GameState._process(GameState.SAVE_DEBOUNCE + 0.1)
			check(int(_read().gold) == (0 if phase == "reset_failure" else 123), "恢复可写后保存内存状态")
			menu.free()
		"reset_resume":
			check(GameState.gold == 0 and GameState.equipment_state.items.is_empty(), "重置重试后冷启进入新冒险")
		"zero_seed":
			GameState.reset_all()
			GameState.stats.lifespan_days = 1
			GameState._on_player_died_lifespan()
			check(GameState.stats.lifespan_days == 0, "实际死亡回调寿命降为零")
			GameState.save_enabled = true
			check(GameState.save_now(), "零寿命保存")
		"life_bounds":
			check(GameState.stats.lifespan_days == float(OS.get_environment("HOTW_EXPECT_LIFE")), "负值钳零/缺键默认与读取契约一致")
		"zero_resume":
			check(GameState.stats.lifespan_days == 0, "零寿命冷启动原样恢复")
			check(is_equal_approx(GameState.stats.max_hp(), 96.0), "零寿命衰减不因读档改变")
	GameState.save_enabled = false
	WorldSim.stop()
	print("SAVE_AUDIT %s %s" % [phase, "PASS" if failures == 0 else "FAIL"])
	get_tree().quit(0 if failures == 0 else 1)

func _read() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(GameState.SAVE_PATH))
