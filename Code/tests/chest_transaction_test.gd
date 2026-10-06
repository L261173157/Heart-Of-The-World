## 城塞开箱事务：真实流式实体、每个同步奖励信号保存、独立进程冷读。
## 入口 run_chest_transaction_test.py 隔离存档并严格检查日志；Boss 死亡通过模拟 API 设置，非战斗验收。
extends Node

const MAIN_SCENE := preload("res://scenes/main/main.tscn")
const WORLD_SCRIPT := preload("res://scripts/main/game_world.gd")
var _checks := 0
var _fails := 0
var _world: Node
var _player: Player
var _chest: Node
var _patch := ""
var _before_bytes := PackedByteArray()
var _observed: Dictionary = {}
var _phase := ""
var _streamed_reentry := false
var _opening_dungeon: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.save_enabled = false
	GameState.set_process(false)
	WorldSim.set_process(false)
	get_tree().paused = true
	var args := OS.get_cmdline_user_args()
	_phase = args[0] if not args.is_empty() else "write"
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok: _fails += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])

func _snapshot() -> Dictionary:
	return {"gold": GameState.gold, "inventory": GameState.inventory.duplicate(true),
		"pending_items": GameState.pending_items.duplicate(true), "pending_item_sequence": GameState.pending_item_sequence,
		"item_source_receipts": GameState.item_source_receipts.duplicate(true), "chest_claims": GameState.chest_claims.duplicate(true)}

func _same(a: Variant, b: Variant) -> bool:
	return JSON.parse_string(JSON.stringify(a)) == JSON.parse_string(JSON.stringify(b))

func _check_state(expected: Dictionary, label: String) -> void:
	var actual := _snapshot()
	for field: String in actual:
		_check(_same(actual[field], expected[field]), "%s：%s 精确一致" % [label, field])

func _read_save() -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(GameState.SAVE_PATH))
	return data if data is Dictionary else {}

func _spawn_world() -> void:
	_world = MAIN_SCENE.instantiate()
	add_child(_world)
	_player = _world.get_node("Player")
	await get_tree().process_frame
	await get_tree().process_frame

func _leave_world() -> void:
	if _world == null: return
	await get_tree().process_frame
	await get_tree().process_frame
	_world.queue_free()
	await get_tree().process_frame
	get_tree().paused = false
	await get_tree().physics_frame
	await get_tree().process_frame
	get_tree().paused = true
	_world = null
	_chest = null

func _dungeon(terrain: String) -> Dictionary:
	for dungeon: Dictionary in _world._dungeon_list():
		if dungeon.terrain == terrain: return dungeon
	return {}

func _stream(dungeon: Dictionary) -> void:
	_player.global_position = dungeon.center
	_world._update_dungeons()
	_patch = dungeon.patch_id
	_chest = _world._chests.get(_patch)

func _during_signal(label: String) -> void:
	_observed[label] = int(_observed.get(label, 0)) + 1
	_check(GameState._world_reward_depth > 0 and _chest.taken, "%s：广播前已有开箱防重入保护" % label)
	var before := _snapshot()
	_check(not _chest.can_interact(), "%s：结算中不再提供交互" % label)
	_chest.interact()
	_check(_same(before, _snapshot()), "%s：同步重入不重复扣钥匙或发奖励" % label)
	for full: bool in [false, true]:
		_check(not GameState.save_now(full), "%s：同步保存如实返回尚未落盘" % label)
		_check(FileAccess.get_file_as_bytes(GameState.SAVE_PATH) == _before_bytes,
			"%s：同步保存不写入半笔开箱" % label)
	if label == "inventory_changed" and not _streamed_reentry:
		_test_streamed_reentry()

func _test_streamed_reentry() -> void:
	# 第一笔库存广播就是扣钥匙，此时持久收据尚未写入；原实体锁不足以保护新实体。
	_streamed_reentry = true
	var before := _snapshot()
	_player.global_position = _opening_dungeon.center + Vector2(10000, 10000)
	_world._update_dungeons()
	_check(not _world._chests.has(_patch), "钥匙广播内真实卸载原宝箱")
	_player.global_position = _opening_dungeon.center
	_world._update_dungeons()
	var replacement: Node = _world._chests.get(_patch)
	_check(replacement != null and replacement != _chest, "钥匙广播内真实流式生成新宝箱实体")
	if replacement == null: return
	_check(not replacement.can_interact(), "跨节点开箱保护挡住新实体候选")
	replacement.interact()
	_check(_same(before, _snapshot()), "新实体同步重入不消耗第二把钥匙/双发金币或溢出")
	_check(FileAccess.get_file_as_bytes(GameState.SAVE_PATH) == _before_bytes,
		"流式替换重入仍不能提前写入半笔开箱")

func _on_inventory() -> void:
	_during_signal("inventory_changed")

func _on_gold(_amount: int) -> void:
	_during_signal("gold_changed")

func _on_item(id: String, _count: int, _total: int) -> void:
	_during_signal("item_gained:" + id)

func _on_received(id: String, _stored: int, _pending: int, _total: int) -> void:
	_during_signal("item_reward_received:" + id)

func _on_equipment() -> void:
	_during_signal("equipment_offer_changed")

func _connect_signals() -> void:
	EventBus.inventory_changed.connect(_on_inventory)
	EventBus.gold_changed.connect(_on_gold)
	EventBus.item_gained.connect(_on_item)
	EventBus.equipment_offer_changed.connect(_on_equipment)
	if EventBus.has_signal("item_reward_received"):
		EventBus.connect("item_reward_received", _on_received)

func _disconnect_signals() -> void:
	EventBus.inventory_changed.disconnect(_on_inventory)
	EventBus.gold_changed.disconnect(_on_gold)
	EventBus.item_gained.disconnect(_on_item)
	EventBus.equipment_offer_changed.disconnect(_on_equipment)
	if EventBus.has_signal("item_reward_received"):
		EventBus.disconnect("item_reward_received", _on_received)

func _test_read_only_and_missing_key(key: String) -> void:
	var before := _snapshot()
	for property: String in ["_future_save_version", "_future_campaign_min_reader", "_future_equipment_schema"]:
		var original: int = GameState.get(property)
		GameState.set(property, GameState.SAVE_VERSION + 1)
		_check(GameState.equipment_read_only() and not _chest.can_interact(), property + "：只读档不能开箱")
		_chest.interact()
		_check(not _chest.taken and _same(before, _snapshot()), property + "：不消耗钥匙/收据/奖励")
		# 无钥匙型同样受只读保护，不能只依赖 remove_item 拦截。
		_chest.key_id = ""
		_chest.interact()
		_check(not _chest.taken and _same(before, _snapshot()), property + "：无钥匙型不绕过只读保护")
		_chest.key_id = key
		GameState.set(property, original)
	GameState.inventory.erase(key)
	before = _snapshot()
	_chest.interact()
	_check(not _chest.taken and _same(before, _snapshot()), "缺钥匙不留下领取收据或奖励")
	_check(GameState._world_reward_depth == 0 and not _chest._opening, "拒绝交互不遗留事务/重入锁")
	GameState.inventory[key] = 2

func _test_repeats(dungeon: Dictionary, expected: Dictionary) -> void:
	for _i in 3: _chest.interact()
	_check_state(expected, "连续点击")
	_player.global_position = dungeon.center + Vector2(10000, 10000)
	_world._update_dungeons()
	_check(not _world._chests.has(_patch), "离开城塞确实回收实体")
	_stream(dungeon)
	_check(_chest != null and _chest.taken and not _chest.can_interact(), "真实流式重建保持收据且不可交互")
	_chest._process(0.0)
	_check(not _chest.visible, "已开宝箱流式重建后不可见")
	_chest.interact()
	_check_state(expected, "流式重建重复点击")

func _run() -> void:
	if _phase == "reject_key":
		await _test_key_rejection()
	elif _phase == "cold":
		await _cold()
	else:
		await _write()
	GameState.save_enabled = false
	await _leave_world()
	print("=== CHEST TRANSACTION %s %s (%d checks) ===" % [_phase, "PASS" if _fails == 0 else "FAIL", _checks])
	get_tree().quit(0 if _fails == 0 else 1)

func _write() -> void:
	var args := OS.get_cmdline_user_args()
	var terrain := args[1] if args.size() > 1 else "hill"
	var full := args.size() > 2 and args[2] == "full"
	var nested := args.size() > 3 and args[3] == "nested"
	GameState.reset_all()
	GameState.world_seed = BiomeMap.DEFAULT_SEED
	GameState.stats.level = 8 if full else 1
	GameState.stats.passives = {"gold": 2} if full else {}
	await _spawn_world()
	GameState.quests["active"] = []
	GameState.bounty = {}
	var dungeon := _dungeon(terrain)
	_check(not dungeon.is_empty(), "找到真实 %s 城塞" % terrain)
	if dungeon.is_empty(): return
	_opening_dungeon = dungeon
	_stream(dungeon)
	var key: String = EconomyMath.DUNGEON_KEYS[terrain]
	var boss: String = WorldConfig.TERRAIN_BOSSES[terrain]
	var h := hash("chest|%s|%d" % [key, GameState.stats.level])
	var items: Array[String] = [EconomyMath.BOSS_BONUS_POOL[absi(h) % EconomyMath.BOSS_BONUS_POOL.size()],
		EconomyMath.COLLECT_POOL_RARE[absi(h >> 8) % EconomyMath.COLLECT_POOL_RARE.size()]]
	GameState.gold = 100
	GameState.inventory = {key: 2, items[0]: 99 if full else 2, items[1]: 99 if full else 3}
	GameState.pending_items = {"pending:8": {"id": "pending:8", "item_id": key, "count": 7, "source": "fixture:existing"}}
	GameState.pending_item_sequence = 8
	GameState.item_source_receipts = {"fixture:existing": true}
	var before := _snapshot()
	_chest.interact()
	_check(_chest.locked and _same(before, _snapshot()), "活 Boss 保持封印，奖励与难度不变")
	GameState.save_enabled = true
	_check(GameState.save_now() and GameState._ecology_cache != null, "真实活 Boss 快照预热存档缓存")
	# 模拟 API 只设置死亡窗口，不把本测试冒充实际战斗。
	for inst: MonsterInstance in _world._sim.instances.values():
		if inst.is_alive and inst.species.species_name == boss: _world._sim.report_killed(inst.id)
	_check(_world._sim.alive_count_of_species(boss) == 0, "模拟 API 建立真实 Boss 死亡窗口")
	_test_read_only_and_missing_key(key)
	var expected := _snapshot()
	expected.gold += roundi(EconomyMath.bounty_gold(8, GameState.stats.level) * GameState.stats.gold_mult())
	expected.chest_claims[_patch] = true
	expected.inventory[key] = 1
	for id: String in items:
		var total := int(expected.inventory[id]) + 1
		expected.inventory[id] = mini(GameState.ITEM_MAX, total)
		if total > GameState.ITEM_MAX:
			expected.pending_item_sequence += 1
			var sequence: int = expected.pending_item_sequence
			var receipt := "pending:%d" % sequence
			expected.pending_items[receipt] = {"id": receipt, "item_id": id, "count": 1, "source": "reward:%d" % sequence}
	var fixture := {"expected": expected, "terrain": terrain, "boss": boss, "patch": _patch, "items": items,
		"full": full, "nested": nested, "writer_pid": OS.get_process_id()}
	var file := FileAccess.open(GameState.SAVE_PATH + ".expected", FileAccess.WRITE)
	file.store_string(JSON.stringify(fixture))
	file.close()
	_before_bytes = FileAccess.get_file_as_bytes(GameState.SAVE_PATH)
	var notify: Callable = _chest.notify_taken
	_chest.notify_taken = func() -> void:
		notify.call()
		_during_signal("receipt")
	_connect_signals()
	if nested: GameState.begin_world_reward()
	_chest.interact()
	_disconnect_signals()
	_check_state(expected, "完整结算")
	_check(_streamed_reentry, "确实执行扣钥匙信号内流式替换与重入")
	_check(_observed.get("inventory_changed", 0) == 3 and _observed.get("gold_changed", 0) == 1
		and _observed.get("equipment_offer_changed", 0) == 2 and _observed.get("receipt", 0) == 1,
		"确实覆盖扣钥匙/金币/双件库存/装备通知/收据全部同步边界")
	for id: String in items:
		_check(_observed.get("item_gained:" + id, 0) == 1, id + "：物品信号恰好一次")
		if EventBus.has_signal("item_reward_received"):
			_check(_observed.get("item_reward_received:" + id, 0) == 1, id + "：溢出反馈信号恰好一次")
	if nested:
		_check(GameState._world_reward_depth == 1 and GameState._world_reward_save_requested,
			"外层事务仍持有延迟保存")
		_check(FileAccess.get_file_as_bytes(GameState.SAVE_PATH) == _before_bytes, "嵌套开箱结束仍不提前写盘")
		GameState.end_world_reward()
	_check(GameState._world_reward_depth == 0 and not GameState._world_reward_save_requested
		and not GameState._world_reward_save_full and not _chest._opening, "事务与保存/重入锁全部释放")
	var saved := _read_save()
	for field: String in expected:
		_check(saved.has(field) and _same(saved[field], expected[field]), "回调触发的最终存档完整：" + field)
	var committed := FileAccess.get_file_as_bytes(GameState.SAVE_PATH)
	_check(committed != _before_bytes, "同步请求在完整开箱后真实落盘，无额外手动保存")
	GameState.save_enabled = false
	_test_repeats(dungeon, expected)
	await _leave_world()
	await _spawn_world()
	_stream(_dungeon(terrain))
	_chest.interact()
	_check(_chest.taken and not _chest.locked, "同进程退场重进恢复已开奖励与 Boss 死亡窗口")
	_check_state(expected, "世界重载")
	_check(FileAccess.get_file_as_bytes(GameState.SAVE_PATH) == committed, "验证与退场未覆写冷进程输入")
	print("CHEST_TRANSACTION_OBSERVED ", JSON.stringify(_observed))

func _cold() -> void:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GameState.SAVE_PATH + ".expected"))
	_check(int(fixture.writer_pid) != OS.get_process_id(), "使用独立冷进程，非内存重载")
	var expected: Dictionary = fixture.expected
	_check_state(expected, "冷启动全部库存/溢出/收据")
	var before := FileAccess.get_file_as_bytes(GameState.SAVE_PATH)
	await _spawn_world()
	var dungeon := _dungeon(fixture.terrain)
	_stream(dungeon)
	_check(_patch == fixture.patch and _chest != null and _chest.taken and not _chest.locked,
		"冷启动真实流式宝箱保持本轮已开，Boss 不因旧缓存复活")
	_check(_world._sim.alive_count_of_species(fixture.boss) == 0, "冷启动模拟恢复确切 Boss 死亡窗口")
	_test_repeats(dungeon, expected)
	_check(FileAccess.get_file_as_bytes(GameState.SAVE_PATH) == before, "冷启动重复点击不改已提交字节")

func _test_key_rejection() -> void:
	# 专用故障注入进程：继承真实 GameState，仅让 remove_item 返回失败。
	# 主矩阵始终使用未替换的生产单例和真实流式实体。
	var save_path := GameState.SAVE_PATH
	GameState.set_script(preload("res://tests/chest_transaction_reject_key_state.gd"))
	GameState.SAVE_PATH = save_path
	GameState.save_enabled = false
	GameState.set_process(false)
	GameState.stats = CharacterStats.new()
	GameState.reset_all()
	GameState.inventory = {EconomyMath.KEY_SILVER: 2}
	GameState.gold = 100
	_chest = WORLD_SCRIPT.DungeonChest.new()
	_chest.key_id = EconomyMath.KEY_SILVER
	_chest.locked = false
	_chest.notify_taken = func() -> void: GameState.mark_chest_taken("reject-key")
	add_child(_chest)
	var before := _snapshot()
	_chest.interact()
	_check(GameState.get("remove_attempts") == 1, "确实到达 remove_item 失败路径")
	_check(_same(before, _snapshot()) and not _chest.taken, "扣钥匙失败不消费宝箱/收据/任意奖励")
	_check(GameState._world_reward_depth == 0 and not _chest._opening, "扣钥匙失败也释放事务和重入锁")
	GameState.set("reject_key", false)
	_chest.interact()
	_check(_chest.taken and GameState.count_item(EconomyMath.KEY_SILVER) == 1
		and GameState.chest_claims.has("reject-key") and GameState.gold > 100,
		"扣钥匙故障解除后可正常重试一次")
	_chest.queue_free()
	await get_tree().process_frame
	_chest = null
