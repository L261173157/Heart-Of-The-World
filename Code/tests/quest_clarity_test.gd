## 真正 NPC → 对话触屏 → 库存信号 → 交付/自动结算 → 存档恢复。
## 可用 --cold-write / --cold-claim / --cold-paid 搭配同一 HOTW_TEST_SAVE 做独立进程验证。
extends Node2D

const Presentation := preload("res://scripts/ui/quest_presentation.gd")
const World := preload("res://scripts/main/game_world.gd")
const COLLECT_ID := "lm_clarity_collect"
var _checks := 0
var _fails := 0
var _hud: CanvasLayer
var _player: Player
var _qm: QuestManager
var _npc: Node2D
var _completed := 0
var _last_completion := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.save_enabled = false
	WorldSim.stop()
	EventBus.quest_completed.connect(_on_completed)
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		GameState.SAVE_PATH = "user://quest_clarity_%d.json" % OS.get_process_id()
		GameState.reset_all()
		_run.call_deferred()
	elif args[0] in ["--cold-write", "--cold-claim", "--cold-paid"] and not OS.get_environment("HOTW_TEST_SAVE").is_empty():
		_cold.call_deferred(args[0])
	else:
		_check(false, "冷进程模式要求明确的隔离 HOTW_TEST_SAVE")
		_finish(false)


func _on_completed(text: String) -> void:
	_completed += 1
	_last_completion = text


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("  %s %s" % ["PASS" if ok else "FAIL", label])


func _settle() -> void:
	for i in 3:
		await get_tree().process_frame


func _mount() -> void:
	_hud = preload("res://scenes/ui/hud.tscn").instantiate()
	add_child(_hud)
	_player = preload("res://scenes/player/player.tscn").instantiate()
	add_child(_player)
	_player.set_physics_process(false)
	_player.position = Vector2(400, 350)
	_qm = QuestManager.new()
	add_child(_qm)
	_npc = World.LandmarkNPC.new()
	_npc.landmark_id = COLLECT_ID
	_npc.quest_kind = "collect"
	_npc.kind = "古树"
	_npc.giver = "草药师"
	_npc.interact_fn = _qm.offer
	_npc.position = _player.position + Vector2(45, 0)
	add_child(_npc)
	await _settle()


func _touch(control: Control) -> void:
	await _settle()
	var point := get_viewport().get_screen_transform() * control.get_global_rect().get_center()
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.position = point
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	event = InputEventScreenTouch.new()
	event.index = 0
	event.position = point
	event.pressed = false
	Input.parse_input_event(event)
	await _settle()


func _accepted() -> Dictionary:
	_npc.interact()
	await _settle()
	_check(_hud._dialogue_panel.visible and _hud._dialogue_kind == "quest", "真实NPC打开可接委托对话")
	await _touch(_hud._dialogue_yes)
	_check(GameState.quests["active"].size() == 1, "触屏确认只接取一单")
	if GameState.quests["active"].is_empty():
		return {}
	return GameState.quests["active"][0]


func _run() -> void:
	await _mount()
	_check(Presentation.npc_status(COLLECT_ID)["state"] == "available", "尚未接单NPC明确标为可接")
	_check(_npc._quest_marker != null and _npc._quest_marker.text.contains("可接"), "真实NPC头顶显示可接标记")
	await _capture("quest-available")
	var quest := await _accepted()
	if quest.is_empty():
		_finish()
		return
	var id: String = quest["id"]
	var item: String = quest["item"]
	var need := int(quest["need"])
	_check(quest.get("claim_at_npc", false) and Presentation.npc_status(COLLECT_ID)["state"] == "in_progress",
			"新收集委托保存交付规则并切换进行中标记")
	_check(_npc._quest_marker.text.contains("进行中"), "接单信号即时更新真实NPC进行中标记")
	EventBus.dialogue_confirmed.emit(quest)
	_check(GameState.quests["active"].size() == 1, "延迟重复接单信号不会追加任务")
	GameState.add_item(item, need - 1)
	_check(int(quest["progress"]) == need - 1 and Presentation.objective(quest).contains("再收集 1"),
			"真实库存变化推进任务并说明还差什么")
	var gold_before := GameState.gold
	var keys_before := GameState.count_item("gold-key")
	GameState.add_item(item, 1)
	_check(Presentation.npc_status(COLLECT_ID)["state"] == "claimable"
			and GameState.count_item(item) == need and GameState.gold == gold_before and _completed == 0,
			"材料达标仅变为可交付，不自动扣料或提前给奖")
	_check(_hud.quest_label.text.contains("交付") and _hud.quest_label.text.contains("草药师"),
			"常驻追踪明确指向领奖NPC")
	_check(_npc._quest_marker.text.contains("可交付"), "达标时真实NPC头顶立即显示可交付")
	await _capture("quest-claimable")
	_hud._open_task_list()
	var task_row: Node = _hud._task_rows.get_node("QuestRow_" + id)
	_check(task_row.get_child(0).text.contains("可交付") and task_row.get_child(1).text.contains("草药师")
			and not task_row.get_node("QuestDetails_" + id).visible, "真实任务列表先展示交付状态与下一步，详情默认折叠")
	await _touch(task_row.find_child("DetailsToggle_" + id, true, false))
	_check(task_row.get_node("QuestDetails_" + id).visible and task_row.get_node("QuestDetails_" + id).get_child(1).text.contains("金钥匙"), "真实触屏展开完整奖励包含金钥匙")
	await _capture("quest-claimable-list")
	_hud._close_choice_layer()
	EventBus.quest_track_requested.emit(id)
	_check(_save(), "待交付状态与当前追踪真实写入磁盘")
	_qm.free()
	GameState.quests = {"active": [], "completed": {}}
	GameState.tracked_quest_id = ""
	GameState._load()
	_qm = QuestManager.new()
	add_child(_qm)
	_npc.interact_fn = _qm.offer
	quest = GameState.quests["active"][0]
	_check(GameState.tracked_quest_id == id and quest.get("claim_at_npc", false)
			and Presentation.state(quest) == "claimable" and GameState.gold == gold_before,
			"重建管理器与真实磁盘读档保留选中/可交付，不重发奖励")
	_player.position += Vector2(500, 0)
	EventBus.quest_claim_requested.emit(id)
	_check(GameState.count_item(item) == need and GameState.gold == gold_before, "离开NPC后的延迟领奖请求被拒绝")
	_player.position = _npc.position + Vector2(40, 0)
	_npc.interact()
	await _settle()
	_check(_hud._dialogue_kind == "claim", "回到NPC出现独立交付领奖对话")
	await _capture("quest-claim-dialogue")
	await _touch(_hud._dialogue_no)
	_check(GameState.quests["active"].size() == 1 and GameState.count_item(item) == need,
			"拒绝交付保留材料和任务")
	_npc.interact()
	# 对话显示后出售材料，确认必须重算真实库存。
	GameState.sell_material(item)
	var sold_gold := GameState.gold
	await _touch(_hud._dialogue_yes)
	_check(GameState.gold == sold_gold and GameState.count_item("gold-key") == keys_before
			and Presentation.state(quest) == "in_progress", "对话期间卖掉材料，陈旧确认不能领取奖励")
	GameState.add_item(item, need)
	_npc.interact()
	await _touch(_hud._dialogue_yes)
	var paid_gold := GameState.gold
	_check(GameState.quests["active"].is_empty() and GameState.count_item(item) == 0
			and GameState.count_item("gold-key") == keys_before + 1 and paid_gold == sold_gold + int(quest["gold"])
			and _completed == 1, "真实触屏交付恰好扣一份材料、发一次金币经验金钥匙")
	_check(_last_completion.contains("交付领奖成功") and Presentation.npc_status(COLLECT_ID)["state"] == "completed"
			and _hud.quest_label.text.contains("暂无进行中"), "成功反馈与NPC已完成清楚可见，常驻区不滞留已结单")
	_check(_npc._quest_marker.text.contains("已完成"), "领奖后真实NPC保留已完成标记")
	await _capture("quest-completed")
	EventBus.quest_claim_requested.emit(id)
	EventBus.dialogue_confirmed.emit(quest)
	_check(GameState.quests["active"].is_empty() and GameState.gold == paid_gold and _completed == 1,
			"连续领奖与旧接单回调不能重复扣料、奖励或重新接受已结单")
	_check(_save(), "领奖收据真实写盘")
	GameState._load()
	_qm._push_hud()
	_check(Presentation.npc_status(COLLECT_ID)["state"] == "completed" and GameState.gold == paid_gold
			and Presentation.receipt_text(GameState.quests["receipts"].get(COLLECT_ID, {})).contains("金钥匙"),
			"领奖后读档保留完成标记及实际奖励收据说明")
	var next := _qm.offer(COLLECT_ID, "collect", "草药师")
	_check(next["kind"] == "quest" and next["quest"]["id"] != id and next["text"].contains("已领奖"),
			"完成后仍可接下一单，清楚说明上一单已领奖")
	# 自动委托沿用即时结算；选择第二单后第一单完成不能改变追踪目标。
	var first := _qm.offer("lm_clarity_explore", "explore", "守望者")["quest"] as Dictionary
	var second := _qm.offer("lm_clarity_ransack", "ransack", "学者")["quest"] as Dictionary
	_qm.accept(first)
	_qm.accept(second)
	EventBus.quest_track_requested.emit(str(second["id"]))
	for i in int(first["need"]):
		EventBus.landmark_discovered.emit("lm_test_%d" % i, "test", "石环", Vector2.ZERO)
	_check(GameState.quests["active"].size() == 1 and GameState.tracked_quest_id == second["id"]
			and _last_completion.contains("已自动领奖"), "探索进度完成自动发奖且保留另一单选择")
	for i in int(second["need"]):
		EventBus.nest_ransacked.emit("测试")
	_check(GameState.quests["active"].is_empty() and GameState.tracked_quest_id == "" and _completed == 3,
			"捣巢自动结算后合理清除已失效追踪")
	# v9 无flag的旧单维持自动交付，不在升级后改变已有承诺。
	var legacy := {"id": "legacy", "landmark_id": "legacy", "kind": "collect", "item": "fish",
		"title": "旧收集委托", "need": 2, "progress": 0, "gold": 10, "xp": 1}
	_qm.accept(legacy)
	GameState.add_item("fish", 2)
	_check(GameState.quests["active"].is_empty() and _completed == 4,
			"旧版本无交付标志的收集单保留原自动交付行为")
	_test_claim_navigation()
	_test_receipt_sanitization()
	_finish()


## 实际 Minimap 从活体/迷雾/已发现地标构建候选，不直接伪造 _select_target 输入。
func _test_claim_navigation() -> void:
	var giver: Dictionary = {}
	# reset_all 会重掷世界种子；边界斑块的首个地标可在世界矩形外。
	# 本用例验证已知目标的优先级，须把 NPC、材料怪、赏金怪及 9000px
	# 返程起点都放在有效地图内，不能把边界裁剪误判成目标选择失败。
	var fixture_bounds := Rect2(Vector2.ONE * 10000.0,
			WorldConfig.WORLD_SIZE - Vector2.ONE * 20000.0)
	for landmark: Dictionary in LandmarkRegistry.landmarks():
		if landmark["kind"] == "古树" and fixture_bounds.has_point(landmark["pos"]):
			giver = landmark
			break
	_check(not giver.is_empty(), "返程导航使用真实注册的收集NPC地标")
	if giver.is_empty():
		return
	var miner: SpeciesData
	var goblin: SpeciesData
	for species: SpeciesData in SpeciesCatalog.build_all():
		if species.species_name == "地精矿工":
			miner = species
		elif species.species_name == "火把哥布林":
			goblin = species
	var region := SimRegion.new()
	region.id = "claim_navigation"
	region.center = giver["pos"]
	region.size = Vector2(10000, 10000)
	region.capacity = 100
	var sim := EcologySim.new()
	sim.setup([region], [miner, goblin], {})
	WorldSim.start(sim)
	WorldSim.set_process(false)
	_place_navigation_player((giver["pos"] as Vector2) - Vector2(400, 0))
	_npc.position = giver["pos"]
	_npc.landmark_id = giver["id"]
	var material_source := sim.spawn_instance(miner, region.id, 30, 0, 1.0, false,
			_player.position + Vector2(300, 0))
	var fallback := sim.spawn_instance(goblin, region.id, 30, 0, 1.0, false,
			_player.position + Vector2(100, 0))
	for position: Vector2 in [_player.position, giver["pos"], material_source.spawn_pos, fallback.spawn_pos]:
		var cell := GameState.fog_cell_of(position)
		GameState.fog_reveal_cell(cell.x, cell.y)
	GameState.discovered_landmarks.assign([str(giver["id"])])
	GameState.inventory.erase("tea-leaf")
	var quest := {"id": "return_to_giver", "landmark_id": giver["id"], "giver": "草药师",
		"kind": "collect", "claim_at_npc": true, "item": "tea-leaf", "title": "收集茶叶",
		"need": 2, "progress": 0, "gold": 10, "xp": 1}
	_qm.accept(quest)
	EventBus.quest_track_requested.emit(str(quest["id"]))
	var radar: Minimap = _hud.get_node("Root/Minimap")
	radar._refresh_navigation()
	EventBus.bounty_target_changed.emit(goblin.species_name)
	radar._refresh_navigation()
	_check(radar._is_known_position(material_source.spawn_pos) and radar._is_known_position(fallback.spawn_pos),
			"导航夹具的真实材料/赏金目标都在地图内且已探索")
	_check(radar._target.get("id", "") == "monster:%d" % material_source.id
			and radar._category.text == "当前目标", "未收齐时真实雷达仍优先导航材料来源")
	GameState.add_item("tea-leaf", 2)
	radar._refresh_navigation()
	_check(radar._target.get("id", "") == "landmark:" + str(giver["id"])
			and radar._category.text == "交付目标" and radar._target_name.text == "草药师",
			"材料达标后真实雷达指向已知委托人，通用地标优先级不会覆盖")
	var fog_before := GameState.explored.duplicate()
	GameState.discovered_landmarks.clear()
	radar._refresh_navigation()
	_check(radar._target.get("id", "") != "monster:%d" % fallback.id
			and not radar._target.get("precise", true) and GameState.explored == fog_before
			and not radar._known_candidates().any(func(c: Dictionary) -> bool:
				return c["id"] == "landmark:" + str(giver["id"])),
			"失去地标记录仅保留已知粗线索，不揭雾也不替换成赏金")
	GameState.discovered_landmarks.assign([str(giver["id"])])
	_place_navigation_player((giver["pos"] as Vector2) - Vector2(9000, 0))
	radar._refresh_navigation()
	_check(radar._target.get("id", "") == "quest_clue:" + str(quest["id"])
			and not radar._target.get("precise", true) and radar._category.text == "上次目击"
			and radar._distance.text == "大致方位", "离开视野后的已知交付人降级为最后所见线索")
	_place_navigation_player(_npc.position + Vector2(40, 0))
	radar._refresh_navigation()
	_check(radar._category.text == "交付目标", "已经走到NPC身边仍保留交付提示直到领奖")
	_qm.claim(str(quest["id"]))
	radar._refresh_navigation()
	_check(GameState.quests["active"].is_empty() and radar._target.is_empty()
			and radar._category.text == "未跟踪委托", "真实交付移除任务后清除指引，不滞留地标或擅自替换成赏金")
	WorldSim.stop()


func _place_navigation_player(position: Vector2) -> void:
	_player.global_position = position
	# 本夹具同步移动实际相机，使当前视野判定使用新位置而非上一帧画面。
	var camera: Camera2D = _player.get_node("Camera2D")
	camera.reset_smoothing()
	camera.force_update_scroll()


func _test_receipt_sanitization() -> void:
	_check(_save(), "坏字段验证先保存有效进度")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GameState.SAVE_PATH))
	saved["quests"]["receipts"] = {"bad_type": [], "bad_id": {"id": 42, "title": "坏"},
		"valid": {"id": "kept", "title": "有效记录", "gold": [], "xp": {}, "bonus": "unknown"}}
	saved["quests"]["last_receipt"] = "valid"
	var file := FileAccess.open(GameState.SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(saved))
	file.close()
	var gold_before := GameState.gold
	GameState._load()
	var receipts: Dictionary = GameState.quests["receipts"]
	_check(receipts.size() == 1 and receipts.has("valid") and receipts["valid"]["gold"] == 0
			and receipts["valid"]["xp"] == 0 and receipts["valid"]["bonus"] == ""
			and GameState.gold == gold_before, "坏收据隔离/字段消毒不会中断读档或改变奖励")


func _capture(stem: String) -> void:
	var directory := OS.get_environment("HOTW_QUEST_SHOTS")
	if directory.is_empty() or DisplayServer.get_name() == "headless":
		return
	await _settle()
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(directory)
	_check(get_viewport().get_texture().get_image().save_png(directory.path_join(stem + ".png")) == OK,
			"已保存图形证据：" + stem)


func _save() -> bool:
	GameState.save_enabled = true
	var saved := GameState.save_now()
	GameState.save_enabled = false
	return saved


func _cold(mode: String) -> void:
	if mode == "--cold-write":
		GameState.reset_all()
		await _mount()
		var quest := await _accepted()
		if not quest.is_empty():
			GameState.add_item(str(quest["item"]), int(quest["need"]))
			EventBus.quest_track_requested.emit(str(quest["id"]))
			_check(_save(), "冷进程写入待交付单与追踪")
	elif mode == "--cold-claim":
		await _mount()
		_check(GameState.quests["active"].size() == 1, "全新进程恢复待交付单")
		if not GameState.quests["active"].is_empty():
			var quest: Dictionary = GameState.quests["active"][0]
			_check(Presentation.state(quest) == "claimable" and GameState.tracked_quest_id == quest["id"]
					and _completed == 0, "冷启动保留交付规则/选择，未自动领奖")
			_npc.interact()
			await _touch(_hud._dialogue_yes)
			_check(GameState.quests["active"].is_empty() and _completed == 1, "冷启动后真实触屏仅领奖一次")
			_check(_save(), "冷进程保存已完成收据")
	else:
		var gold_before := GameState.gold
		await _mount()
		var receipt: Dictionary = GameState.quests.get("receipts", {}).get(COLLECT_ID, {})
		_check(not receipt.is_empty() and GameState.quests["active"].is_empty()
				and Presentation.npc_status(COLLECT_ID)["state"] == "completed", "第三个进程恢复已领奖标记")
		EventBus.quest_claim_requested.emit(str(receipt.get("id", "")))
		_check(GameState.gold == gold_before and _completed == 0 and GameState.count_item("gold-key") == 1,
				"领奖后再冷启动不会重复付金币金钥匙")
	_finish(false)


func _finish(clean: bool = true) -> void:
	GameState.save_enabled = false
	get_tree().paused = false
	WorldSim.stop()
	if clean:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.SAVE_PATH))
	print("=== QUEST CLARITY %s (%d checks, %d failures) ===" % ["PASSED" if _fails == 0 else "FAILED", _checks, _fails])
	get_tree().quit(0 if _fails == 0 else 1)
