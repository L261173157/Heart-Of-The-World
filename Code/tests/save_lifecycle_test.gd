## 由 run_save_lifecycle_test.py 启动多个独立进程，验证真实冷启动与短写/flush 失败。
## HOTW_TEST_SAVE 必须指向隔离沙盒；各阶段只经磁盘传递，不共享 GameState 内存。
extends Node

var _fails := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if OS.get_environment("HOTW_TEST_SAVE").is_empty() or args.size() != 1:
		push_error("请通过 tests/run_save_lifecycle_test.py 运行隔离存档生命周期测试")
		get_tree().quit(1)
		return
	var phase := args[0]
	var state: Node = GameState
	var stats: Resource = GameState.stats
	var manifest_path := GameState.SAVE_PATH + ".expected"
	match phase:
		"seed":
			GameState.reset_all()
			GameState.add_xp(500)
			GameState.receive_equipment({"slot": "weapon", "name": "现用火刃", "rarity": 1,
					"affixes": {"atk": 0.1}, "element": "fire"})
			GameState.receive_equipment({"slot": "weapon", "name": "待选冰刃", "rarity": 3,
					"affixes": {"lifesteal": 0.06}, "element": "ice"})
			GameState.bounty = {"species": "火把哥布林", "region_id": "test_region",
					"need": 5, "progress": 2, "gold": 40, "xp": 20,
					"original_need": 5, "original_gold": 40, "original_xp": 20, "adjusted": false,
					"target_ids": [3, 5, 7, 11, 13]}
			GameState.tracked_quest_id = "test_quest"

			GameState._notification(NOTIFICATION_APPLICATION_PAUSED)
			var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GameState.SAVE_PATH))
			_check(int(data.get("pending_passive_picks", -1)) == GameState.stats.level - 1,
					"后台保存包含全部未领取升级资格")
			_check(data.get("passive_choices", []).size() == 3, "后台保存包含稳定三选一卡组")
			var file := FileAccess.open(manifest_path, FileAccess.WRITE)
			file.store_string(JSON.stringify(data))
			file.close()
		"resume":
			var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
			_check(stats.get("pending_passive_picks") == int(expected.get("pending_passive_picks", -1)),
					"全新进程自动读回待领取次数")
			_check(stats.get("passive_choices") == expected.get("passive_choices", []),
					"全新进程保持原三张卡，不重抽")
			_check(_same_data(GameState.pending_equipment, expected.get("pending_equipment", {})),
					"候选装备词条和元素跨进程保留")
			_check(_same_data(GameState.bounty, expected.get("bounty", {})) and GameState.bounty.get("progress") == 2,
					"赏金目标和部分进度跨进程保留")
			_check(GameState.tracked_quest_id == "test_quest", "所追踪委托跨进程保留")
			_check(GameState.resolve_pending_equipment(true, int(expected["equipment_offer_id"])),
					"冷启动可选择待比较装备")
			_check(GameState.stats.equip_element() == "ice" and GameState.is_equipment_locked("weapon"),
					"主动换装应用元素并保护新选择")
			if not stats.has_method("claim_passive") or expected.get("passive_choices", []).is_empty():
				_check(false, "提供事务式赐福领取入口")
			else:
				var id: String = expected["passive_choices"][0]
				_check(stats.call("claim_passive", id, int(expected["passive_offer_id"])), "冷启动领取一张卡")
				GameState._notification(NOTIFICATION_WM_CLOSE_REQUEST)
		"verify":
			var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
			var remaining := int(expected.get("pending_passive_picks", -1)) - 1
			_check(GameState.pending_equipment.is_empty() and GameState.stats.equip_element() == "ice",
					"再启动不会恢复已经处理的候选")
			_check(not GameState.resolve_pending_equipment(true, int(expected["equipment_offer_id"])),
					"跨进程重放装备凭证不能重复结算")
			_check(GameState.bounty.get("progress") == 2 and GameState.tracked_quest_id == "test_quest",
					"其它奖励领取不丢失赏金或追踪状态")

			_check(stats.get("pending_passive_picks") == remaining, "再次冷启动只剩未领取资格")
			if not expected.get("passive_choices", []).is_empty():
				var id: String = expected["passive_choices"][0]
				_check(GameState.stats.passive_level(id) == 1, "已领取奖励跨进程恰好保留一次")
				if stats.has_method("claim_passive"):
					_check(not stats.call("claim_passive", id, int(expected["passive_offer_id"])),
							"跨进程重放旧领取凭证被拒绝")
		"fail_flush", "fail_write":
			# Python 限制本子进程最大文件长度；旧好档已存在，读文件不受限制。
			var old_bytes := FileAccess.get_file_as_bytes(GameState.SAVE_PATH)
			var old_time := GameState.last_save_unix
			GameState.gold += 10
			if phase == "fail_write":
				GameState.tutorial_flags["large_write_probe"] = "x".repeat(65536)
			var result: Variant = state.call("save_now")
			_check(result == false, "%s：写入失败返回 false" % phase)
			_check(GameState.last_save_unix == old_time, "%s：失败不刷新成功时间" % phase)
			_check(FileAccess.get_file_as_bytes(GameState.SAVE_PATH) == old_bytes,
					"%s：短写/flush 失败不覆盖上一份好档" % phase)
			_check(GameState._save_timer > 0.0, "%s：失败保留自动重试" % phase)
			_check(not FileAccess.file_exists(GameState.SAVE_PATH + ".tmp"), "%s：坏临时档已清理" % phase)
		_:
			_check(false, "未知阶段 %s" % phase)
	GameState.save_enabled = false
	print("SAVE_LIFECYCLE %s %s" % [phase, "PASS" if _fails == 0 else "FAIL"])
	get_tree().quit(0 if _fails == 0 else 1)


func _check(ok: bool, message: String) -> void:
	print("  %s  %s" % ["PASS" if ok else "FAIL", message])
	if not ok:
		_fails += 1


## JSON 数字读回都是浮点；递归比较值，不把 int/float 容器类型差异当作丢档。
func _same_data(actual: Variant, expected: Variant) -> bool:
	if typeof(actual) in [TYPE_INT, TYPE_FLOAT] and typeof(expected) in [TYPE_INT, TYPE_FLOAT]:
		return is_equal_approx(float(actual), float(expected))
	if typeof(actual) != typeof(expected):
		return false
	if typeof(actual) == TYPE_ARRAY:
		if actual.size() != expected.size():
			return false
		for i in actual.size():
			if not _same_data(actual[i], expected[i]):
				return false
		return true
	if typeof(actual) == TYPE_DICTIONARY:
		if actual.size() != expected.size():
			return false
		for key: Variant in actual:
			if not expected.has(key) or not _same_data(actual[key], expected[key]):
				return false
		return true
	return actual == expected
