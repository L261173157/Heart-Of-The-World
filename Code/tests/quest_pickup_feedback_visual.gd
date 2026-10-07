## 实际引擎截图夹具：取景使用传送，并冻结生态/敌人AI以固定画面。
## 只验布局、真实触控阅读/拾取/普攻及账本表现，不作实走节奏、iPhone 或 Metal 证明。
## 第二章补充画面使用明示的前置账本夹具，收取动作仍走真实节点和触控。
extends Node2D

var _viewport: SubViewport
var _world: Node2D
var _player: Player
var _hud: CanvasLayer
var _qm: Node
var _out := "/tmp/outpost-chapter-visual"
var _canvas := Vector2i(1280, 720)
var _checks := 0
var _fails := 0
var _action_events: Array[String] = []
const Data := preload("res://scripts/main/campaign_quest_data.gd")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.save_enabled = false
	GameState.reset_all()
	GameState.world_seed = BiomeMap.DEFAULT_SEED
	GameState.settings.screen_shake = false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): _out = arg.trim_prefix("--out=")
		if arg.begins_with("--size="):
			var parts := arg.trim_prefix("--size=").split("x")
			_canvas = Vector2i(int(parts[0]), int(parts[1]))
	DirAccess.make_dir_recursive_absolute(_out)
	_viewport = SubViewport.new()
	_viewport.size = _canvas
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.world_2d = World2D.new()
	add_child(_viewport)
	var preview := TextureRect.new()
	preview.texture = _viewport.get_texture()
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(preview)
	_run.call_deferred()

func _frames(count := 3) -> void:
	for i in count: await get_tree().process_frame

func _process(_delta: float) -> void:
	if _world == null: return
	WorldSim.set_process(false)
	for actor: Node in get_tree().get_nodes_in_group("monsters"):
		actor.set_physics_process(false)

func _capture(label: String) -> void:
	await _frames(5)
	await RenderingServer.frame_post_draw
	var img := _viewport.get_texture().get_image()
	var path := _out.path_join("%s-%dx%d.png" % [label, _canvas.x, _canvas.y])
	_check(img.get_size() == _canvas, "native viewport pixel dimensions " + label)
	_check(img.save_png(path) == OK, "native screenshot saved " + label)
	print("QUEST_PICKUP_RENDERED_CAPTURE ", path, " pixels=", img.get_size())

func _view(position: Vector2, label: String) -> void:
	_player.teleport_to(position)
	await _frames(30)
	await _capture(label)

func _run() -> void:
	_world = preload("res://scenes/main/main.tscn").instantiate()
	EventBus.hint_requested.connect(func(message: String) -> void: print("QUEST_PICKUP_RENDER_HINT ", message))
	EventBus.camp_quest_action_requested.connect(_record_action)
	_viewport.add_child(_world)
	WorldSim.set_process(false)
	_player = _world.get_node("Player")
	_hud = _world.get_node("HUD")
	_qm = get_tree().get_first_node_in_group("quest_manager")
	await _frames(45)
	await _chapter_views()

func _record_action(action: String) -> void:
	_action_events.append(action)

func _reading_state() -> String:
	return JSON.stringify({"ordinary": GameState.quests, "outpost": GameState.outpost_quest,
		"camp": GameState.camp_quest, "campaign": GameState.campaign_quest, "tracked": GameState.tracked_quest_id,
		"gold": GameState.gold, "xp": GameState.stats.xp, "level": GameState.stats.level,
		"inventory": GameState.inventory, "pending": GameState.pending_items,
		"item_receipts": GameState.item_source_receipts, "pending_sequence": GameState.pending_item_sequence,
		"equipment": GameState.equipment_state, "equipment_drops": GameState.equipment_drop_state})

# 追问和规则走真实触屏，返回后保留原操作；不能以跳过缺失按钮掩盖阅读回归。
func _reading_views(tag: String, include_rules := false) -> void:
	var original: String = _hud._dialogue_text.text
	var command: String = _hud._dialogue_action_name
	var kind: String = _hud._dialogue_kind
	var state := _reading_state()
	var event_count := _action_events.size()
	var question: Button = _hud._dialogue_option_box.get_node_or_null("DialogueQuestion_0")
	_check(question != null and not _hud._dialogue_questions.is_empty(), "actual optional question exists: " + tag)
	if question == null or _hud._dialogue_questions.is_empty(): return
	var answer: String = str(_hud._dialogue_questions[0].get("answer", ""))
	for attempt in 2:
		question = _hud._dialogue_option_box.get_node_or_null("DialogueQuestion_0")
		_hud._dialogue_option_scroll.ensure_control_visible(question)
		await _frames(4)
		await _touch(question)
		_check(_hud._dialogue_reading_page == "question" and _hud._dialogue_text.text.ends_with(answer), "actual optional question opens its answer: " + tag)
		_check(_on_screen(_hud._dialogue_text_scroll) and get_tree().paused, "answer remains readable in paused viewport: " + tag)
		_check(_hud._dialogue_yes.is_visible_in_tree() or kind == "camp_choice", "optional answer retains primary action: " + tag)
		_check(_reading_state() == state and _action_events.size() == event_count, "repeated question does not record evidence or grant rewards: " + tag)
		if attempt == 0: await _capture(tag + "-question")
		await _touch(_hud._dialogue_no)
		_check(_hud._dialogue_panel.visible and get_tree().paused and _hud._dialogue_reading_page.is_empty() and _hud._dialogue_text.text == original and _hud._dialogue_action_name == command and _hud._dialogue_kind == kind, "actual Back returns same paused interaction: " + tag)
		_check(_reading_state() == state and _action_events.size() == event_count, "question and Back leave evidence and rewards unchanged: " + tag)
		if attempt == 0: await _capture(tag + "-back")
	if not include_rules: return
	var details: Button = _hud._dialogue_option_box.get_node_or_null("DialogueRules")
	_check(details != null and not _hud._dialogue_rules.is_empty(), "actual optional rules exist: " + tag)
	if details == null: return
	var rules: String = _hud._dialogue_rules
	_hud._dialogue_option_scroll.ensure_control_visible(details)
	await _frames(4)
	await _touch(details)
	_check(_hud._dialogue_reading_page == "rules" and _hud._dialogue_text.text.ends_with(rules), "actual optional rules open separate details: " + tag)
	_check(_on_screen(_hud._dialogue_text_scroll) and get_tree().paused, "rules remain readable in paused viewport: " + tag)
	await _capture(tag + "-rules")
	await _touch(_hud._dialogue_no)
	_check(_hud._dialogue_reading_page.is_empty() and _hud._dialogue_text.text == original and _hud._dialogue_action_name == command and _hud._dialogue_kind == kind, "rules Back restores original interaction: " + tag)
	_check(_reading_state() == state and _action_events.size() == event_count, "rules and Back leave evidence and rewards unchanged: " + tag)

# 行动后结果必须确实出现并由新的继续手势关闭；不得直接关层或解除暂停。
func _continue_story_result(tag: String) -> bool:
	if not _hud._dialogue_panel.is_visible_in_tree() or _hud._dialogue_kind != "story_result":
		return _fail("实际行动缺少可阅读结果：" + tag)
	var state := _reading_state()
	var event_count := _action_events.size()
	_check(get_tree().paused and _on_screen(_hud._dialogue_panel) and _on_screen(_hud._dialogue_text_scroll), "earned result pauses world and fits viewport: " + tag)
	_check(not _hud._dialogue_text.text.is_empty() and _hud._dialogue_yes_label.text == "继续" and _on_screen(_hud._dialogue_yes), "earned result readable with visible Continue: " + tag)
	_check(_hud._dialogue_action_name.is_empty() and _hud._dialogue_quest.is_empty(), "earned result has no repeat action: " + tag)
	await _frames(12)
	_check(_hud._dialogue_panel.is_visible_in_tree() and _hud._dialogue_kind == "story_result" and _reading_state() == state, "earned result remains open without repeating evidence or rewards: " + tag)
	await _capture("earned-" + tag)
	await _touch(_hud._dialogue_yes)
	_check(not _hud._dialogue_panel.visible and not get_tree().paused, "Continue closes result and resumes world: " + tag)
	_check(_reading_state() == state and _action_events.size() == event_count, "Continue never repeats action, evidence or reward mutation: " + tag)
	return not _hud._dialogue_panel.visible and not get_tree().paused

func _touch(control: Control) -> void:
	if control == null:
		_check(false, "missing touch control")
		return
	_check(_on_screen(control), "touchable Control visible within viewport: " + str(control.name))
	var event := InputEventScreenTouch.new()
	event.index = 91
	event.position = control.get_global_rect().get_center()
	event.pressed = true
	_viewport.push_input(event, true)
	await _frames(1)
	event = event.duplicate()
	event.pressed = false
	_viewport.push_input(event, true)
	await _frames(3)

func _prop(id: String) -> Node2D:
	for node: Node in get_tree().get_nodes_in_group("outpost_objects"):
		if str(node.get("outpost_id")) == id: return node
	return null

func _action(id: String, capture_name := "", result_tag := "") -> bool:
	if _hud._dialogue_kind == "story_result": return _fail("前一行动结果尚未用继续关闭：" + id)
	_hud._close_dialogue()
	var prop := _prop(id)
	if prop == null: return _fail("缺少真实前哨物件：" + id)
	await _view(prop.global_position + Vector2(64, 40), "world-" + id)
	if id in ["aid_bag", "repair_tools"]:
		_check(str(_hud._context_payload.get("target_id", "")) == "npc:%d" % prop.get_instance_id(), "actual contextual target selects pickup: " + id)
		_check(_on_screen(_hud._context_target_label) and not _hud._context_target_label.text.is_empty(), "pickup context visibly names target: " + id)
		await _touch(_hud._context_btn)
	else:
		prop.interact()
	await _frames(3)
	if not _hud._dialogue_panel.visible: return _fail("真实物件未打开阅读：" + id)
	if capture_name != "": await _capture(capture_name)
	if capture_name == "06-wounded-request": await _reading_views(capture_name)
	await _touch(_hud._dialogue_yes)
	if not result_tag.is_empty():
		if not await _continue_story_result(result_tag): return false
	elif _hud._dialogue_kind == "story_result":
		return _fail("意外结果层不能被下一次取景静默关闭：" + id)
	if id in ["aid_bag", "repair_tools"]:
		await _frames(30)
		var outpost_world := get_tree().get_first_node_in_group("outpost_world")
		_check(not outpost_world._ground.supply_pad_visible(id), "consumed authored floor pad removed: " + id)
		_check(not prop.visible and not prop.is_visible_in_tree(), "consumed loose prop no longer rendered: " + id)
		_check(not prop.can_interact() and not prop.get("_near"), "consumed loose prop has no affordance: " + id)
		_check(str(_hud._context_payload.get("target_id", "")) != "npc:%d" % prop.get_instance_id(), "context target cleared after pickup: " + id)
		prop.interact()
		await _frames(3)
		_check(not _hud._dialogue_panel.visible, "consumed prop cannot reopen stale dialogue: " + id)
		await _capture("after-" + id)
	if id == "patrol_record":
		await _frames(20)
		_check(prop.is_visible_in_tree() and prop.get("read"), "read clue remains visible in world")
		_check((prop.get_node("ObjectLabel") as Label).text.contains("已读"), "read clue label has recorded state")
		await _capture("read-clue-retained")
	print("QUEST_PICKUP_RENDER_ACTION ", id, " evidence=", GameState.outpost_quest.get("evidence", {}), " dialogue=", _hud._dialogue_panel.visible, " distance=", _player.global_position.distance_to(prop.global_position), " eligible=", prop.can_interact())
	return true

func _fail(message: String) -> bool:
	push_error(message)
	get_tree().quit(1)
	return false

func _chapter_views() -> void:
	var keeper: Node2D
	for npc: Node in get_tree().get_nodes_in_group("npcs"):
		if str(npc.get("landmark_id")) == "camp_ecology": keeper = npc
	if keeper == null:
		_fail("缺少真实营地巡守")
		return
	_player.teleport_to(keeper.global_position + Vector2(56, 32))
	await _frames(3)
	keeper.interact()
	await _capture("01-chapter-briefing")
	await _reading_views("01-chapter-briefing", true)
	await _touch(_hud._dialogue_yes)
	if GameState.outpost_quest.is_empty():
		_fail("新的确认手势未能接取前哨")
		return
	await _frames(20)
	_check_tracker("accepted outpost")
	await _capture("00-actionable-outpost-hud")
	await _task_views("outpost")
	if not await _action("patrol_record", "02-patrol-record"): return
	await _view(OutpostLayout.entrances()["front"] + Vector2(0, 144), "03-blocked-front-route")
	if not await _action("entrance_record", "04-entry-investigation"): return
	await _view(OutpostLayout.entrances()["side"] + Vector2(-80, 0), "05-side-route")
	if not await _action("wounded_patrol", "06-wounded-request"): return
	if not await _action("supply_record", "07-supply-routes"): return
	if not await _action("aid_bag", "08-quest-aid-pickup"): return
	if not await _action("wounded_patrol", "10-explicit-rescue", "rescue"): return
	if not _qm.outpost_evidence("rescued"):
		_fail("截图流程没有真实完成现场救援")
		return
	await _capture("11-rescued-resident")
	if not await _action("repair_tools", "09-quest-tool-pickup"): return
	for attempt in 1200:
		if not _qm.outpost_target().get("species", "").is_empty(): break
		await _frames(1)
	var target: Dictionary = _qm.outpost_target()
	if str(target.get("species", "")).is_empty():
		_fail("正常世界截图流程没有真实可行生态目标")
		return
	var pos: Vector2 = target["position"]
	_player.teleport_to(pos + Vector2(0, 110))
	await _frames(60)
	_qm.outpost_action("investigate")
	await _capture("12-ecology-choice")
	var option: Button
	for child: Node in _hud._dialogue_option_box.get_children():
		if child is Button and child.get_meta("quest_action", "") == "outpost:choose_ransack": option = child
	if option == null or option.disabled:
		_fail("正常世界截图未能选择真实巢穴分支")
		return
	await _touch(option)
	await _capture("13-ecology-confirmation")
	await _touch(_hud._dialogue_yes)
	# A declared ordinary quest fixture verifies its real auto-settlement from the same actual nest destruction.
	GameState.quests["active"].append({"id":"render-ransack", "landmark_id":"render-ransack", "title":"清理附近巢穴", "giver":"营地猎人", "kind":"ransack", "need":1, "progress":0, "gold":10, "xp":0})
	_qm._push_hud()
	# 实际普攻破巢，镜头定位并不伪造任务事件或写入完成字段。
	_player.teleport_to(pos + Vector2(0, 48))
	await _frames(3)
	for attempt in 16:
		if GameState.outpost_quest.get("stage", "") == "repair": break
		_player.facing = _player.global_position.direction_to(pos)
		TouchInput.queue_attack()
		for frame in 65:
			await _frames(1)
			if GameState.outpost_quest.get("stage", "") == "repair": break
	if GameState.outpost_quest.get("stage", "") != "repair" or GameState.outpost_quest.get("outcome", "") != "ransack":
		_fail("真实普攻没有完成捣巢，不能伪造修复画面")
		return
	_check(GameState.quests.get("receipts", {}).has("render-ransack"), "actual nest destruction auto-settled ordinary quest")
	await _wait_receipt("已自动领奖")
	_check_toast("已自动领奖", "automatic quest completion")
	await _capture("completion-toast")
	if not await _action("signpost", "14-explicit-repair", "repair"): return
	if not _qm.outpost_evidence("signpost_repaired") or not OutpostLayout.CHECKPOINT_ID in GameState.discovered_checkpoints:
		_fail("实际修复没有解锁前哨检查点")
		return
	await _capture("15-restored-checkpoint")
	if not await _action("wounded_patrol", "16-regional-next-clue", "next-clue"): return
	await _capture("17-permanent-resident")
	await _supplemental_views()
	print("=== QUEST PICKUP FEEDBACK VISUAL %s (%d checks) ===" % ["PASS" if _fails == 0 else "FAIL", _checks])
	get_tree().quit(0 if _fails == 0 else 1)

func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok: _fails += 1
	print("QUEST_PICKUP_CHECK %s %s" % ["PASS" if ok else "FAIL", label])

func _on_screen(control: Control) -> bool:
	if control == null or not control.is_visible_in_tree() or control.size.x <= 0 or control.size.y <= 0: return false
	var rect := control.get_global_rect()
	if not _viewport.get_visible_rect().encloses(rect): return false
	var ancestor := control.get_parent()
	while ancestor != null:
		if ancestor is Control and ancestor.clip_contents and not ancestor.get_global_rect().encloses(rect): return false
		ancestor = ancestor.get_parent()
	return true

func _check_tracker(label: String) -> void:
	var tracker: Label = _hud.quest_label
	_check(_on_screen(tracker), "tracker visible within viewport: " + label)
	_check(tracker.get_line_count() <= tracker.max_lines_visible, "tracker content fits rendered line limit: " + label)
	var current: Dictionary = {}
	for row: Dictionary in _hud._task_snapshot:
		if str(row.get("id", "")) == GameState.tracked_quest_id: current = row
	_check(not current.is_empty() and not str(current.get("next_action", "")).is_empty(), "tracked quest exposes explicit next action: " + label)
	_check(tracker.text.contains(str(current.get("next_action", "MISSING"))), "rendered tracker includes actual target action: " + label)

func _task_views(tag: String) -> void:
	await _touch(_hud.quest_label)
	await _frames(8)
	_check(_hud._task_layer.is_visible_in_tree(), "touch tracker opens actual task modal")
	var first := _hud._task_rows.get_child(0) as Control
	_check(first.name == "QuestRow_" + GameState.tracked_quest_id.replace(":", "_"), "tracked quest appears before automatic bounty")
	_check(_on_screen(first), "collapsed tracked row fully visible")
	var toggle: Button = first.find_child("DetailsToggle_" + GameState.tracked_quest_id.replace(":", "_"), true, false)
	var details: Control = first.get_node("QuestDetails_" + GameState.tracked_quest_id.replace(":", "_"))
	_check(not details.is_visible_in_tree(), "history details collapsed by default")
	_check(_on_screen(first.get_child(1)) and _on_screen(first.get_child(2)), "compact target and actions have on-screen layout")
	await _capture("task-list-" + tag)
	await _touch(toggle)
	await _frames(8)
	_check(details.is_visible_in_tree() and details.get_child_count() > 0, "actual touch expands readable history detail")
	_check(_on_screen(details.get_child(0)), "first expanded detail visible, not clipped below viewport")
	await _capture("task-details-" + tag)
	_hud._close_choice_layer()
	await _frames(8)

func _check_toast(needle: String, label: String) -> void:
	var toast: Label = _hud.toast_label
	_check(_on_screen(toast) and toast.modulate.a > 0.9, "toast visibly rendered: " + label)
	_check(toast.text.contains(needle), "toast includes receipt: " + label)
	_check(toast.has_theme_stylebox_override("normal"), "receipt has world-label isolation backing: " + label)
	var backing := toast.get_theme_stylebox("normal") as StyleBoxFlat
	_check(backing != null and backing.bg_color.a >= 0.95, "receipt backing is opaque enough for text legibility: " + label)
	if backing != null:
		_check(backing.get_expand_margin(SIDE_LEFT) >= 8.0 and backing.get_expand_margin(SIDE_RIGHT) >= 8.0, "receipt backing pads both text edges: " + label)
		_check(_viewport.get_visible_rect().encloses(toast.get_global_rect().grow_individual(backing.get_expand_margin(SIDE_LEFT), backing.get_expand_margin(SIDE_TOP), backing.get_expand_margin(SIDE_RIGHT), backing.get_expand_margin(SIDE_BOTTOM))), "receipt backing fully inside native viewport: " + label)
	_check(toast.mouse_filter == Control.MOUSE_FILTER_IGNORE, "receipt backing does not intercept gameplay touch: " + label)
	_check(toast.get_line_count() * toast.get_line_height() <= toast.size.y + 2.0, "toast all rendered lines fit: " + label)
	for button_name: String in ["AttackBtn", "ShieldBtn", "DashBtn", "ShortcutBtn", "QuickSlotBtn", "MoreBtn"]:
		var button: Button = _hud.get_node("Root").find_child(button_name, true, false)
		_check(button.is_visible_in_tree() and not toast.get_global_rect().intersects(button.get_global_rect()), "receipt does not obscure combat button " + button_name)

func _supplemental_views() -> void:
	# Production transaction, deliberately prefilled inventory boundary; no simulated reward signal.
	GameState.inventory["onigiri"] = 98
	await _frames(40)
	GameState.add_item("onigiri", 3)
	await _frames(3)
	await _wait_receipt("待领取 ×2")
	_check_toast("待领取 ×2", "partial overflow 98 + 3")
	_check(_hud.toast_label.text.contains("×1（共99）") and _hud.toast_label.text.contains("菜单→背包→待领取"), "overflow distinguishes stored amount and opens a discoverable route")
	await _capture("overflow-receipt")
	# Actual first chapter was completed above. Accept second chapter at canonical data boundary,
	# then render its genuine snapshot and perform a real recovery after declared prior evidence.
	_check(Data.authorize_chapter1(GameState.campaign_quest, GameState.outpost_quest), "first chapter genuine evidence authorizes campaign")
	_check(Data.accept_chapter(GameState.campaign_quest, "watch_c2_forest", 1), "declare second chapter visual fixture")
	GameState.tracked_quest_id = "watch_c2_forest:s1"
	_qm._campaign._publish()
	_qm._push_hud()
	await _frames(20)
	_check_tracker("campaign target")
	await _capture("campaign-actionable-hud")
	await _task_views("campaign")

	# Supplemental c2 crate: seeded completed prerequisites, then actual on-site recovery.
	var chapter: Dictionary = CampaignCatalog.chapter("watch_c2_forest")
	for stage: Dictionary in chapter["steps"].slice(0, 2):
		for action: Dictionary in stage["actions"]:
			var proof := {"position":[100,200], "tick":1}
			if action["kind"] == "puzzle": proof["order"] = action["puzzle_order"]
			_check(Data.record(GameState.campaign_quest, stage["id"], action["id"], proof), "declared prerequisite " + str(action["id"]))
		_check(Data.mark_paid(GameState.campaign_quest, stage["id"]), "declared previous stage receipt " + str(stage["id"]))
	GameState.tracked_quest_id = "watch_c2_forest:s3"
	_qm._campaign._publish()
	_qm._push_hud()
	if not await _campaign_action("c2:liaison", "campaign-liaison"): return
	if not await _campaign_action("c2:aid_cache", "campaign-crate-before"): return
	var world := get_tree().get_first_node_in_group("campaign_world")
	var crate: Node2D = world.object_node("c2:aid_cache")
	await _frames(20)
	_check(crate.is_visible_in_tree() and crate.get("taken"), "empty campaign container remains visible")
	_check(not crate.can_interact() and not crate.get("_near"), "empty campaign container has no stale pickup/highlight")
	_check((crate.get_node("ObjectLabel") as Label).text.contains("已取空"), "empty container has claimed label")
	_check(str(_hud._context_payload.get("target_id", "")) != "npc:%d" % crate.get_instance_id(), "empty container cleared from contextual target")
	await _capture("campaign-empty-container")
	await get_tree().create_timer(2.1).timeout
	_check(not _hud.toast_label.has_theme_stylebox_override("normal"), "normal campaign hint removes receipt-only backing")
	await _shared_station_views()
	var giver: Node2D = world.object_node("side_patrol:giver")
	_player.teleport_to(giver.global_position + Vector2(0, 48))
	await _frames(45)
	giver.interact()
	await _frames(4)
	_check(_hud._dialogue_panel.visible, "actual side story giver opens offer")
	await _capture("side-patrol-offer")
	var before := _reading_state()
	await _reading_views("side-patrol-offer")
	await _touch(_hud._dialogue_no)
	_check(not _hud._dialogue_panel.visible and not get_tree().paused and _reading_state() == before, "side story Close resumes world without accepting or rewarding")

func _campaign_action(id: String, tag: String) -> bool:
	if _hud._dialogue_kind == "story_result": return _fail("前一战役结果尚未用继续关闭：" + id)
	_hud._close_choice_layer()
	_hud._close_dialogue()
	var world := get_tree().get_first_node_in_group("campaign_world")
	var prop: Node2D = world.object_node(id)
	_player.teleport_to(prop.global_position + Vector2(0, 48))
	await _frames(45)
	_check(prop.can_interact(), "campaign prop is available on site " + id)
	prop.interact()
	await _frames(3)
	if not _hud._dialogue_panel.is_visible_in_tree(): return _fail("campaign interaction did not open " + id)
	await _capture(tag)
	if id == "c2:liaison": await _reading_views(tag)
	await _touch(_hud._dialogue_yes)
	if not await _continue_story_result(tag): return false
	await _frames(3)
	return true

func _shared_station_views() -> void:
	# Declared finished outer-route ledger is a visual fixture, not a traversal claim.
	var ledger := GameState.campaign_quest
	for stage: Dictionary in CampaignCatalog.chain("region_plains")["steps"]:
		_check(Data.accept(ledger, stage["id"], 1), "declared shared supply stage " + str(stage["id"]))
		for action: Dictionary in stage["actions"]:
			var proof := {"position":[100,200], "tick":1}
			if action["kind"] == "choice": proof["choice"] = "outer"
			if action.has("destination_by_choice"): proof["destination"] = action["destination_by_choice"]["outer"]
			if action["kind"] == "route":
				proof["route"] = "outer"
				proof["traversed"] = true
				proof["visit_ids"] = action["route_by_choice"]["outer"]
			_check(Data.record(ledger, stage["id"], action["id"], proof), "declared shared supply evidence " + str(action["id"]))
		_check(Data.mark_paid(ledger, stage["id"]), "declared shared supply paid receipt")
	_qm._campaign._publish()
	var world := get_tree().get_first_node_in_group("campaign_world")
	var station: Node2D = world.object_node("region_plains:station")
	_hud._close_dialogue()
	_player.teleport_to(station.global_position + Vector2(0,48))
	await _frames(45)
	station.interact()
	await _frames(3)
	await _capture("shared-supply-before")
	var supply: Button = _option_button("campaign|optional|supply|region_plains:station")
	_check(supply != null and _on_screen(supply), "shared supply actual claim option visibly available")
	if supply == null: return
	await _touch(supply)
	await _frames(3)
	if _hud._dialogue_yes.is_visible_in_tree(): await _touch(_hud._dialogue_yes)
	await _frames(20)
	_check(Data.service_claimed(ledger, "region_plains_station"), "actual supply touch persisted shared receipt")
	for id: String in ["region_plains:station", "region_plains:work_outer"]:
		_hud._close_dialogue()
		var endpoint: Node2D = world.object_node(id)
		_player.teleport_to(endpoint.global_position + Vector2(0,48))
		await _frames(35)
		_check((endpoint.get_node("ObjectLabel") as Label).text.contains("已领取"), "shared endpoint visible claimed status " + id)
		await _capture("shared-claimed-world-" + id.replace(":","-"))
		endpoint.interact()
		await _frames(3)
		_check(_option_button("campaign|optional|supply|" + id) == null, "claimed endpoint has no repeat supply option " + id)
		var shop: Button = _option_button("campaign|optional|shop|" + id)
		_check(shop != null and _on_screen(shop), "claimed endpoint retains visible shop action " + id)
		await _capture("shared-claimed-menu-" + id.replace(":","-"))
	_hud._close_dialogue()

func _option_button(action: String) -> Button:
	for child: Node in _hud._dialogue_option_box.get_children():
		if child is Button and str(child.get_meta("quest_action", "")) == action: return child
	return null

func _wait_receipt(needle: String) -> void:
	var deadline := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline:
		if _hud.toast_label.text.contains(needle) and _hud.toast_label.modulate.a > 0.9: return
		await _frames(1)
	_check(false, "expected receipt reaches actual visible queue: " + needle)
