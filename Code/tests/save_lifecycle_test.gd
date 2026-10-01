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
			if not stats.has_method("claim_passive") or expected.get("passive_choices", []).is_empty():
				_check(false, "提供事务式赐福领取入口")
			else:
				var id: String = expected["passive_choices"][0]
				_check(stats.call("claim_passive", id, int(expected["passive_offer_id"])), "冷启动领取一张卡")
				GameState._notification(NOTIFICATION_WM_CLOSE_REQUEST)
		"verify":
			var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
			var remaining := int(expected.get("pending_passive_picks", -1)) - 1
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
