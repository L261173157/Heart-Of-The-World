## 叙事显示与真实触屏确认合同。章节前置使用显式账本夹具，不冒充实走/战斗验收。
## 追问必须只改变阅读页；正式行动仍走真实 HUD → EventBus → QuestManager。
extends Node2D

const Data := preload("res://scripts/main/campaign_quest_data.gd")
const Catalog := preload("res://scripts/main/campaign_catalog.gd")
const Outpost := preload("res://scripts/main/outpost_quest_data.gd")
var _hud: CanvasLayer
var _player: Player
var _qm: QuestManager
var _checks := 0
var _fails := 0
var _action_events: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.save_enabled = false
	GameState.reset_all()
	GameState.world_seed = 42
	GameState.save_enabled = false
	WorldSim.stop()
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok: _fails += 1
	print("  %s %s" % ["PASS" if ok else "FAIL", label])

func _frames(count := 3) -> void:
	for _i in count: await get_tree().process_frame

func _state() -> String:
	return JSON.stringify({"ordinary":GameState.quests,"outpost":GameState.outpost_quest,
		"camp":GameState.camp_quest,"campaign":GameState.campaign_quest,"tracked":GameState.tracked_quest_id,
		"gold":GameState.gold,"xp":GameState.stats.xp,"level":GameState.stats.level,
		"inventory":GameState.inventory,"pending":GameState.pending_items,
		"item_receipts":GameState.item_source_receipts,"pending_sequence":GameState.pending_item_sequence})

func _capture_action(action: String) -> void:
	_action_events.append(action)

func _touch(control: Control) -> void:
	_check(control != null, "待触屏按钮确实存在")
	if control == null: return
	if _hud._dialogue_option_scroll.is_ancestor_of(control):
		_hud._dialogue_option_scroll.ensure_control_visible(control)
	await _frames()
	var point := get_viewport().get_screen_transform() * control.get_global_rect().get_center()
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.position = point
	event.pressed = true
	Input.parse_input_event(event)
	await _frames(1)
	event = InputEventScreenTouch.new()
	event.index = 0
	event.position = point
	event.pressed = false
	Input.parse_input_event(event)
	await _frames()

func _question() -> Button:
	return _hud._dialogue_option_box.get_node_or_null("DialogueQuestion_0") as Button

func _option(action: String) -> Button:
	for child: Node in _hud._dialogue_option_box.get_children():
		if child is Button and child.get_meta("quest_action", "") == action: return child
	return null

func _escape() -> void:
	var event := InputEventAction.new()
	event.action = "pause"
	event.pressed = true
	Input.parse_input_event(event)
	await _frames(1)
	event = InputEventAction.new()
	event.action = "pause"
	event.pressed = false
	Input.parse_input_event(event)
	await _frames()

func _run() -> void:
	_hud = preload("res://scenes/ui/hud.tscn").instantiate()
	add_child(_hud)
	_player = preload("res://scenes/player/player.tscn").instantiate()
	add_child(_player)
	_player.set_physics_process(false)
	_player.set_process(false)
	_player.position = Vector2(40000, 40000)
	_qm = QuestManager.new()
	add_child(_qm)
	await _frames()
	_qm._campaign._main.set_physics_process(false)
	_qm._campaign._optional.set_physics_process(false)
	_qm._campaign._dynamic.set_physics_process(false)
	EventBus.camp_quest_action_requested.connect(_capture_action)
	_legacy_offer_truth()
	await _outpost_optional_questions()
	await _branch_reading_isolation()
	await _outpost_guidance_projection()
	_campaign_reveal_projection()
	_random_history_projection()
	_branch_consequences()
	await _earned_result_once()
	for canvas: Vector2i in [Vector2i(1280,720),Vector2i(1560,720),Vector2i(1600,720),Vector2i(1024,640)]:
		get_tree().root.size = canvas
		get_tree().root.content_scale_size = canvas
		await _frames(5)
		await _long_answer_scroll(canvas)
	_hud._close_dialogue()
	get_tree().paused = false
	WorldSim.stop()
	print("=== QUEST NARRATIVE UI %s (%d checks, %d failures) ===" % ["PASS" if _fails == 0 else "FAIL", _checks, _fails])
	get_tree().quit(0 if _fails == 0 else 1)

func _outpost_optional_questions() -> void:
	var offer := _qm._outpost.offer()
	_check(offer.get("kind", "") == "quest" and not offer.get("questions", []).is_empty(), "首章真实邀约有可选追问和直接接取入口")
	var opening := str(offer.get("text", ""))
	for spoiler: String in ["捣巢", "维修工具", "检查点", "世界之心"]:
		_check(not opening.contains(spoiler), "首章邀请不提前展开未知后续步骤：" + spoiler)
	var state := _state()
	var signals := _action_events.size()
	_hud._open_dialogue(offer)
	await _frames()
	_check(_hud._dialogue_yes.visible, "不读追问即可直接接下真实邀约")
	for _i in 2:
		await _touch(_question())
		_check(_hud._dialogue_reading_page == "question" and _hud._dialogue_text.text.ends_with(str(offer.get("questions", [{}])[0].get("answer", ""))), "新触点进入所选问题的准确答案")
		_check(_state() == state and _action_events.size() == signals, "重复追问不接单、不推进、不领奖、不发动作信号")
		_check(_hud._dialogue_yes.visible, "读答案期间正式接取入口仍可用")
		await _touch(_hud._dialogue_no)
		_check(_hud._dialogue_panel.visible and _hud._dialogue_reading_page == "" and get_tree().paused and _hud._dialogue_text.text == opening, "答案返回原邀请并保持暂停")
	await _touch(_hud._dialogue_no)
	_check(not _hud._dialogue_panel.visible and _state() == state, "第二次返回关闭且没有任何任务或奖励变更")
	_hud._open_dialogue(offer)
	await _frames()
	await _touch(_hud._dialogue_yes)
	_check(GameState.outpost_quest.get("active", false) and not GameState.outpost_quest.get("evidence", {}).get("patrol_read", false), "重开后跳过所有追问也能直接接取，未伪造第一条现场证据")
	_check(GameState.gold == 0 and GameState.stats.xp == 0 and not GameState.outpost_quest.receipts.investigation.paid, "接取与背景阅读都不提前领取调查报酬")

func _branch_reading_isolation() -> void:
	var branch := {"label":"走短路", "action":"narrative_fixture|near", "enabled":true,"consequence":"破除岩障后走较短路线", "risk":"要穿过实际缺口"}
	var payload := {"kind":"camp_choice","giver":"阅读夹具","text":"接应点在路的另一头。","options":[branch],
		"questions":[{"label":"为什么有人等在那里？","answer":"他答应等最后一位归队的人。"}],"rules":"选择只在另一次明确确认后提交。"}
	var state := _state()
	var signals := _action_events.size()
	_hud._open_dialogue(payload)
	await _frames()
	await _touch(_question())
	_check(not _hud._dialogue_yes.visible and _hud._dialogue_selected_option.is_empty(), "未选支路时阅读不会暗选方案或制造确认入口")
	await _escape()
	_check(_hud._dialogue_panel.visible and _hud._dialogue_reading_page == "" and _state() == state, "Esc只退出答案，保留原选择菜单和账本")
	await _touch(_option(str(branch.action)))
	_check(_hud._dialogue_selected_option == branch and _action_events.size() == signals, "触屏选择仍先预览，不提交分支")
	await _touch(_question())
	await _escape()
	_check(_hud._dialogue_selected_option == branch and _hud._dialogue_yes.visible, "答案返回仍保留原分支预览和确认")
	await _touch(_hud._dialogue_option_box.get_node_or_null("DialogueRules") as Button)
	_check(_hud._dialogue_reading_page == "rules" and _hud._dialogue_text.text.ends_with(str(payload.rules)) and _state() == state, "规则页完整可读且只修改临时阅读状态")
	await _touch(_hud._dialogue_no)
	_check(_hud._dialogue_selected_option == branch and _state() == state and _action_events.size() == signals, "规则返回不改变预览或发送动作")
	await _touch(_hud._dialogue_yes)
	_check(_action_events.size() == signals + 1 and _action_events[-1] == branch.action and _state() == state, "新确认手势只提交最初选定动作一次；夹具未变更真实任务")
	_hud._open_dialogue(payload)
	await _frames()
	_check(_hud._dialogue_reading_page == "" and _hud._dialogue_selected_option.is_empty(), "重开不继承旧答案或旧分支预览")
	_hud._close_dialogue()

func _outpost_guidance_projection() -> void:
	var saved := GameState.outpost_quest.duplicate(true)
	var q := Outpost.create()
	GameState.outpost_quest = q
	var transitions := [["", "patrol_record"], ["patrol_read", "entrance_record"], ["entrance_read", "wounded_patrol"], ["wounded_found", "supply_record"], ["supply_read", "aid_bag"], ["aid_taken", "wounded_patrol"], ["rescued", "repair_tools"], ["tools_taken", "survey_marker"]]
	for transition: Array in transitions:
		if not str(transition[0]).is_empty(): q.evidence[transition[0]] = true
		Outpost.refresh_stage(q)
		var before := _state()
		var view := _qm._outpost.snapshot()
		_check(view.target_object_id == transition[1], "首章下一步始终指向当前证据所需对象：" + str(transition[1]))
		_check(not str(view.next_action).is_empty() and view.target_title == OutpostLayout.OBJECTS[str(transition[1])].title, "行动、任务详情和世界物件使用同一对象名：" + str(transition[1]))
		_check(_state() == before, "读取首章目标不写入证据或支付")
	q.evidence.site_surveyed = true
	q.outcome = "survey"
	q.survey_confirmed = true
	Outpost.refresh_stage(q)
	_check(_qm._outpost.snapshot().target_object_id == "signpost", "合法现场勘察后才将当前目标推进至修路标")
	q.evidence.signpost_repaired = true
	Outpost.refresh_stage(q)
	var claim := _qm._outpost.snapshot()
	_check(q.stage == "claim" and claim.target_object_id == "signpost" and str(claim.next_action).contains("领取"), "修复已完成但尾款未付时仍明确到路标领取")
	q.receipts.restoration.paid = true
	Outpost.refresh_stage(q)
	var completed := _qm._outpost.snapshot()
	if str(completed.next_action).contains("交谈"):
		_check(completed.target_object_id == "wounded_patrol", "完成后的交谈指引指向巡守，不能继续指向路标")
	_check(completed.ui_state == "completed" and not completed.claim_at_npc and not completed.get("can_abandon", true), "完成后只是后续指引，不显示待领或可放弃状态")
	_check(not _qm._outpost.receipt_text().contains("林地") and not q.evidence.next_clue_received, "尚未听巡守说话时收据不提前透露林地去向")
	var proof_before := JSON.stringify(q)
	GameState.tracked_quest_id = Outpost.ID
	_qm._push_hud()
	_check(_hud.quest_label.text.contains(str(completed.next_action)), "完成后的巡守交谈指引仍真正送到HUD")
	var radar := _hud.get_node("Root/Minimap") as Minimap
	var candidates: Array[Dictionary] = []
	var patrol_guide: Dictionary = radar._select_target(candidates)
	_check(not patrol_guide.is_empty() and patrol_guide.get("pos",Vector2.INF) == OutpostLayout.object_position("wounded_patrol"), "真实雷达保留已完成章节的巡守后续目标")
	EventBus.quest_track_requested.emit("")
	_check(GameState.tracked_quest_id == "__untracked__" and JSON.stringify(q) == proof_before, "取消后续追踪不改变完成证据或收据")
	EventBus.quest_track_requested.emit(Outpost.ID)
	_check(GameState.tracked_quest_id == Outpost.ID and JSON.stringify(q) == proof_before, "可以重新追踪后续交谈，仍不重开章节")
	_hud._open_task_list()
	await _frames()
	var abandon := _hud._task_rows.find_child("Abandon_" + Outpost.ID, true, false) as Button
	_check(abandon != null and not abandon.is_visible_in_tree() and abandon.disabled, "真实任务列表不提供已完成前哨的放弃按钮")
	_hud._close_choice_layer()
	var home := preload("res://scripts/main/game_world.gd").LandmarkNPC.new()
	home.landmark_id = "camp_ecology"
	home.quest_kind = "outpost"
	home.kind = "石环"
	home.giver = "营地巡守"
	home.position = Vector2(40321,40567)
	add_child(home)
	home.set_process(false)
	q.evidence.next_clue_received = true
	var return_view := _qm._outpost.snapshot()
	_check(return_view.target_object_id == "home:patrol" and return_view.target_pos == [home.global_position.x,home.global_position.y] and str(return_view.next_action).contains("回营地"), "听到后续线索后转向真实营地巡守位置，不能猜用营地中心")
	_check(_qm._outpost.guidance_pending(), "知道林地去向但还未接取时保留回营地指引")
	_qm._push_hud()
	var home_guide: Dictionary = radar._select_target(candidates)
	_check(not home_guide.is_empty() and home_guide.get("pos",Vector2.INF) == home.global_position, "真实雷达从前哨巡守切换到营地巡守的实际位置")
	var ordinary_done := return_view.duplicate(true)
	ordinary_done.erase("guidance_pending")
	EventBus.quest_list_changed.emit([ordinary_done],Outpost.ID)
	_check(radar._select_target(candidates).is_empty(), "没有后续标志的普通已完成任务仍从雷达清除")
	_qm._push_hud()
	var campaign_saved := GameState.campaign_quest.duplicate(true)
	GameState.campaign_quest = Data.create(GameState.world_seed)
	_check(Data.authorize_chapter1(GameState.campaign_quest,q) and Data.accept_chapter(GameState.campaign_quest,"watch_c2_forest",1), "后续衔接夹具接取原第二章，不补发第一章奖励")
	_qm._push_hud()
	var stale := false
	for row: Dictionary in _hud._task_snapshot:
		if row.get("id", "") == Outpost.ID: stale = true
	_check(not _qm._outpost.guidance_pending() and not stale, "第二章接取后旧交谈指引退出任务列表，让当前章节接续")
	home.queue_free()
	await _frames()
	GameState.campaign_quest = campaign_saved
	GameState.outpost_quest = saved

func _campaign_reveal_projection() -> void:
	GameState.campaign_quest = Data.create(GameState.world_seed)
	var q: Dictionary = GameState.campaign_quest
	var first_chapter := {"id":Outpost.ID,"evidence":{},"outcome":"survey","survey_confirmed":true}
	for key: String in Outpost.EVIDENCE: first_chapter.evidence[key] = true
	_check(Data.authorize_chapter1(q, first_chapter) and Data.accept_chapter(q, "watch_c2_forest", 1), "显示合同夹具通过纯账本验证首章前置并接取第二章")
	var campaign := _qm._campaign
	var sid := "watch_c2_forest:s1"
	var stage := Catalog.stage(sid)
	var first: Dictionary = stage.actions[0]
	var second: Dictionary = stage.actions[1]
	var before := _state()
	var view := campaign.snapshot(sid)
	_check(view.target_object_id == first.object and str(view.next_action).contains(str(view.target_title)), "主线当前指引与当前未完成行动对象一致")
	_check(str(view.history).is_empty(), "尚未行动时历史不伪装为整段待办清单")
	_check(not str(view.ui_objective).contains(str(second.title)) and not str(view.next_action).contains(str(second.title)), "第二行动尚未揭示时不泄露未来行动链")
	_check(_state() == before, "读取主线指引完全只读")
	var snapshots := campaign.snapshots()
	_check(snapshots.size() == 1 and snapshots[0].id == sid, "已接一章不会同时展开全部后续阶段")
	_check(Data.record(q, sid, first.id, {"position":[40000,40000],"tick":0}), "已知经过夹具记录实际格式的第一项证据")
	view = campaign.snapshot(sid)
	_check(view.target_object_id == second.object and str(view.history).contains(str(first.text)) and not str(view.history).contains(str(second.text)), "行动后只记已取得内容，同时推进当前对象")
	_check(Data.record(q, sid, second.id, {"position":[40000,40000],"tick":0}), "阶段完成夹具记录第二项证据")
	view = campaign.snapshot(sid)
	_check(view.chapter_stage == "claim" and str(view.next_action).contains("领取") and not Data.paid(q,sid), "完整证据与已付收据分开，待领阶段不会被说成已付款")
	_check(view.gold == Data.reward(q,sid).gold and view.xp == Data.reward(q,sid).xp, "奖励预览严格使用原冻结预算")

func _branch_consequences() -> void:
	for id: String in ["watch_c3_swamp:s3:route_choice"]:
		var a: Dictionary = _qm._campaign._actions[id]
		var payload := _qm._campaign._main.payload(a)
		var options: Array = payload.get("options", [])
		_check(options.size() == 2 and str(options[0].consequence) != str(options[1].consequence), id + "两条方案有不同的实际后果")
		_check(str(payload.text).contains(str(a.prompt)) and not str(payload.text).contains(str(a.text)), id + "决定前显示待选处境，不把确认结果提前叙述为已发生")
	var ending: Dictionary = _qm._campaign._actions["watch_c6_lava:s4:ending"]
	var ending_payload: Dictionary = _qm._campaign._action_payload(str(ending.prompt), str(ending.verb), "campaign|act|"+str(ending.id), str(ending.object), ending)
	_check(ending.kind == "conclude" and not ending.has("choices") and ending_payload.kind == "camp_action" and ending_payload.get("options", []).is_empty(), "获批单结局使用普通确认，无隐藏分散/集中选项")
	_check(str(ending_payload.text) == str(ending.prompt) and ending_payload.text != ending.text, "团聚确认前后分层，未执行的归途消息不提前记为完成")
	for id: String in ["side_patrol:s2:station","side_herbalist:s2:purpose","side_scholar:s2:choice","side_merchant:s2:destination"]:
		var a: Dictionary = _qm._campaign._actions.get(id,{})
		if a.is_empty():
			_check(false, "已批准的支线决定ID保留："+id)
			continue
		var payload := _qm._campaign._optional._action_payload(a)
		var options: Array = payload.get("options", [])
		_check(options.size() == 2 and str(options[0].consequence) != str(options[1].consequence), id + "支线两种用途/去向的说明不能共用一段模糊文字")

func _long_answer_scroll(canvas: Vector2i) -> void:
	var long_answer := ""
	for index in 35: long_answer += "第%d段：我留在这里等最后一个走散的人。来时的路仍要亲自走，灯亮了也不能替人看守。\n" % index
	var payload := {"kind":"camp_action","giver":"长答案显示夹具","text":"你想问哪一件事？","action":"narrative_fixture|read",
		"confirm_text":"继续行动","questions":[{"label":"把前因后果说给我听","answer":long_answer}],"rules":"长规则说明。"}
	_hud._open_dialogue(payload)
	await _frames()
	await _touch(_question())
	var scroll: ScrollContainer = _hud._dialogue_text_scroll
	var before := _state()
	var signal_count := _action_events.size()
	_check(scroll.get_v_scroll_bar().max_value > scroll.size.y and _hud._dialogue_text.text.ends_with(long_answer.strip_edges()), "长答案完整保留且内容高于可视区 " + str(canvas))
	var panel: Rect2 = _hud._dialogue_panel.get_global_rect()
	_check(panel.encloses(scroll.get_global_rect()) and panel.encloses(_hud._dialogue_yes.get_global_rect()) and panel.encloses(_hud._dialogue_no.get_global_rect()), "长答案与确认/返回按钮均在纸面内部 " + str(canvas))
	var transform := get_viewport().get_screen_transform()
	var from := transform * (scroll.get_global_rect().position + Vector2(scroll.size.x * 0.5, scroll.size.y - 18))
	var to := transform * (scroll.get_global_rect().position + Vector2(scroll.size.x * 0.5, 18))
	var press := InputEventScreenTouch.new()
	press.index = 3
	press.position = from
	press.pressed = true
	Input.parse_input_event(press)
	await _frames(1)
	var previous := from
	for index in range(1,9):
		var at := from.lerp(to,float(index)/8.0)
		var motion := InputEventScreenDrag.new()
		motion.index = 3
		motion.position = at
		motion.relative = at - previous
		motion.screen_relative = motion.relative
		motion.velocity = motion.relative * 60.0
		motion.screen_velocity = motion.velocity
		Input.parse_input_event(motion)
		previous = at
		await _frames(1)
	var release := InputEventScreenTouch.new()
	release.index = 3
	release.position = to
	release.pressed = false
	Input.parse_input_event(release)
	await _frames()
	print("NARRATIVE_SCROLL ", JSON.stringify({"canvas":str(canvas),"offset":scroll.scroll_vertical,"height":scroll.size.y,"bar_max":scroll.get_v_scroll_bar().max_value,"label_height":_hud._dialogue_text.size.y,"text_complete":_hud._dialogue_text.text.ends_with(long_answer.strip_edges())}))
	_check(scroll.scroll_vertical > 0, "真实手指拖动正文能滚动长答案 " + str(canvas))
	_check(_state() == before and _action_events.size() == signal_count and _hud._dialogue_panel.visible, "正文滑动不会执行行动或修改任务 " + str(canvas))
	await _escape()
	_check(_hud._dialogue_reading_page == "" and _hud._dialogue_text.text == payload.text, "长答案返回时恢复原情境和阅读位置 " + str(canvas))
	_hud._close_dialogue()

## 只装配两件真实生产物件，真实HUD确认产生证据与阶段支付；不伪造被检查的证据。
func _earned_result_once() -> void:
	GameState.campaign_quest = Data.create(GameState.world_seed)
	var q: Dictionary = GameState.campaign_quest
	var chapter1 := {"id":Outpost.ID,"evidence":{},"outcome":"survey","survey_confirmed":true}
	for key: String in Outpost.EVIDENCE: chapter1.evidence[key] = true
	_check(Data.authorize_chapter1(q, chapter1) and Data.accept_chapter(q,"watch_c2_forest",1), "结果阅读夹具只建立此前章节前置")
	var props: Array[Node2D] = []
	for id: String in ["c2:herbalist","c2:old_pact"]:
		for definition: Dictionary in CampaignLayout.objects():
			if definition.id != id: continue
			var prop := CampaignWorld.CampaignObject.new()
			prop.campaign_id = id
			prop.definition = definition.duplicate(true)
			prop.title = definition.title
			prop.kind = definition.kind
			prop.interaction_label = definition.interaction_label
			prop.position = definition.position
			add_child(prop)
			props.append(prop)
	var stage := Catalog.stage("watch_c2_forest:s1")
	for index in props.size():
		var prop: Node2D = props[index]
		var action: Dictionary = stage.actions[index]
		_player.teleport_to(prop.global_position + Vector2(0,20))
		await _frames(5)
		_check(prop.can_interact(), "真实故事物件可到场交互：" + str(action.object))
		prop.interact()
		await _frames()
		_check(_hud._dialogue_kind == "camp_action" and _hud._dialogue_text.text == action.prompt, "真实行动前显示现场处境，尚未提前讲述结果")
		var gold_before := GameState.gold
		var event_before := _action_events.size()
		await _touch(_hud._dialogue_yes)
		_check(q.quests[stage.id].evidence.has(action.id) and _hud._dialogue_kind == "story_result" and _hud._dialogue_panel.visible and get_tree().paused, "真实新证据打开可停留阅读的结果层")
		_check(_hud._dialogue_text.text == str(action.text), "结果层呈现这一项真实完成的完整所得")
		if index == 0:
			_check(GameState.gold == gold_before and not Data.paid(q,stage.id), "首个行动结果不会抢先支付整段奖励")
		else:
			_check(Data.paid(q,stage.id) and GameState.gold - gold_before == int(q.quests[stage.id].receipt.gold), "末个行动结果对应一次原子阶段付款和真实收据")
		var after := _state()
		_check(_action_events.size() == event_before + 1 and _hud._dialogue_yes.visible, "结果层有继续按钮，正式动作只发送一次")
		await _touch(_hud._dialogue_yes)
		_check(not _hud._dialogue_panel.visible and _state() == after and _action_events.size() == event_before + 1, "结果层继续只关闭，不重放证据、动作或奖励")
		EventBus.camp_quest_action_requested.emit("campaign|act|" + str(action.id))
		await _frames()
		_check(not _hud._dialogue_panel.visible and _state() == after, "重复已记行动不伪造第二个成功结果或付款")
	for prop: Node2D in props: prop.queue_free()
	await _frames()
	var after := _state()
	EventBus.camp_quest_action_requested.emit("campaign|act|watch_c2_forest:s4:beacon")
	await _frames()
	_check(not _hud._dialogue_panel.visible and _state() == after, "缺前置/不在场的失败行动不打开成功结果")

func _random_history_projection() -> void:
	var q: Dictionary = GameState.campaign_quest
	var id := "random_parcel:" + str(GameState.world_seed) + ":0"
	var stage := Catalog.stage(id)
	_check(Data.accept(q,id,1), "随机历史夹具接取带真实种子/序号的实例")
	_check(str(_qm._campaign.snapshot(id).history).is_empty(), "随机实例未行动前没有结果历史")
	var first: Dictionary = stage.actions[0]
	_check(Data.record(q,id,first.id,{"position":[234,567],"tick":11}), "随机实例使用带种子行动ID记录第一条证据")
	var before := _state()
	var view := _qm._campaign.snapshot(id)
	_check(not str(view.history).is_empty() and str(view.history).contains(str(first.text)), "随机实例历史显示已取得内容，不误查模板阶段ID")
	for future: Dictionary in stage.actions.slice(1):
		_check(not str(view.history).contains(str(future.text)), "随机实例历史不提前展示尚未取得的后续结果：" + str(future.id))
	_check(_state() == before, "读取随机实例已知经过不生成新证据或收据")

func _legacy_offer_truth() -> void:
	var original := GameState.camp_quest.duplicate(true)
	var original_outpost := GameState.outpost_quest.duplicate(true)
	GameState.outpost_quest = {}
	GameState.camp_quest = CampQuestData.sanitize({"id":CampQuestData.ID,"active":true,"target":{"region_id":"legacy_fixture","species":"火把哥布林","pos":[234,567]},"gold":39,"xp":44,"bonus":"onigiri"})
	_check(Outpost.valid_legacy(GameState.camp_quest), "预览夹具保留有效原调查合同")
	var before := _state()
	var offered := _qm._outpost.offer()
	var rules := str(offered.get("rules", ""))
	_check(rules.contains("原调查奖励") and rules.contains("不重复") and not rules.contains("全章基础39金币"), "未接前哨时仍识别旧合同，不能额外许诺新章39/44奖励")
	_check(_state() == before and GameState.outpost_quest.is_empty(), "查看旧合同兼容邀请不接取、不改承诺或支付")
	GameState.camp_quest = original
	GameState.outpost_quest = original_outpost
