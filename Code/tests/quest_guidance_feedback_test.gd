## 表现合同回归：真实 HUD/库存/任务结算；章节与路线状态是显式夹具，不冒充实走通关。
extends Node2D

const Data := preload("res://scripts/main/campaign_quest_data.gd")
const Catalog := preload("res://scripts/main/campaign_catalog.gd")
var _hud: CanvasLayer
var _player: Player
var _qm: QuestManager
var _checks := 0
var _fails := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.save_enabled = false
	GameState.reset_all()
	GameState.world_seed = 42
	WorldSim.stop()
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok: _fails += 1
	print("  %s %s" % ["PASS" if ok else "FAIL", label])

func _frames() -> void:
	for i in 3:
		await get_tree().process_frame

func _touch(control: Control) -> void:
	await _frames()
	var point := get_viewport().get_screen_transform() * control.get_global_rect().get_center()
	var press := InputEventScreenTouch.new()
	press.index = 0
	press.position = point
	press.pressed = true
	Input.parse_input_event(press)
	await get_tree().process_frame
	var release := InputEventScreenTouch.new()
	release.index = 0
	release.position = point
	release.pressed = false
	Input.parse_input_event(release)
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
	await _test_campaign_guidance()
	await _test_task_list()
	_test_hunt_clue()
	_test_completion_receipt()
	_test_item_feedback()
	_test_chest_feedback()
	_test_receipt_burst()
	_test_receipt_backdrop()
	_test_context_target()
	get_tree().paused = false
	WorldSim.stop()
	print("=== QUEST GUIDANCE FEEDBACK %s (%d checks) ===" % ["PASS" if _fails == 0 else "FAIL", _checks])
	get_tree().quit(0 if _fails == 0 else 1)

func _test_campaign_guidance() -> void:
	var evidence := {}
	for key: String in Data.Outpost.EVIDENCE: evidence[key] = true
	_check(Data.authorize_chapter1(GameState.campaign_quest, {"id":"lost_outpost_v1", "evidence":evidence, "outcome":"survey", "survey_confirmed":true}), "章节展示夹具建立已完成首章")
	_check(Data.accept_chapter(GameState.campaign_quest, "watch_c2_forest", 1), "章节展示夹具接取林地章")
	var campaign: CampaignQuest = _qm._campaign
	var view := campaign.snapshot("watch_c2_forest:s1")
	_check(view.next_action == "与草药师交谈" and view.target_title == "草药师", "章节下一步包含实际交谈对象")
	GameState.tracked_quest_id = str(view.id)
	_qm._push_hud()
	_check(_hud.quest_label.text.contains("与草药师交谈"), "生产快照经管理器到真实HUD不截去NPC")
	_check(campaign.visual_state().get("target_object_id", "") == view.target_object_id, "初始世界投影复用已推送追踪快照")
	EventBus.quest_track_requested.emit("")
	_check(campaign.visual_state().get("target_object_id", "") == "", "明确取消跟踪立即清除世界目标")
	EventBus.quest_track_requested.emit(str(view.id))
	var projection_source := FileAccess.get_file_as_string("res://scripts/main/campaign_quest.gd")
	var visual_function := projection_source.get_slice("func visual_state()", 1).get_slice("func _station_origins", 0)
	_check(not visual_function.contains("snapshots()") and not visual_function.contains("snapshot("), "世界投影不得重复生成昂贵任务导航快照")
	var q: Dictionary = GameState.campaign_quest
	# 有效证据由纯账本接口生成；只验证当前符标和局部进度的投影。
	for id: String in ["watch_c2_forest:s1:herbalist", "watch_c2_forest:s1:old_pact", "watch_c2_forest:s2:route_marks"]:
		var a: Dictionary = campaign._actions[id]
		_check(Data.record(q, str(a.stage), id, {"position":[40000,40000],"tick":0}), "展示夹具记录前置 " + id)
	q["puzzle_progress"] = {"watch_c2_forest:s2:runes":["dew"]}
	view = campaign.snapshot("watch_c2_forest:s2")
	_check(view.next_action == "触碰东方信号石" and view.step_progress == "符标 1/3", "机关展示使用当前真实符标与局部1/3")
	GameState.tracked_quest_id = str(view.id)
	_qm._push_hud()
	_check(_hud.quest_label.text.contains("东方信号石") and _hud.quest_label.text.contains("符标 1/3"), "HUD显示当前符标和局部进度")
	var before := JSON.stringify(q)
	campaign.snapshot("watch_c2_forest:s2")
	_check(JSON.stringify(q) == before, "章节展示投影不制造行动证据或奖励")
	var route_stage := "region_plains:s3"
	var route_action: Dictionary = campaign._actions[route_stage + ":walk"]
	q["optional_route_reanchor"] = {route_action.id:true}
	q["optional_routes"] = {route_action.id:["region_plains:work_near"]}
	var guide := campaign._optional.next_target(route_action)
	_check(str(guide.next_action).contains("返回") and str(guide.next_action).contains("接续"), "真实路线恢复投影保留返程接续指令")
	view = campaign.snapshot(route_stage)
	EventBus.quest_list_changed.emit([view], route_stage)
	EventBus.quest_updated.emit("不会被截断的结构化指引")
	_check(_hud.quest_label.text.contains("返回") and _hud.quest_label.text.contains("接续"), "路线返锚指令真正抵达HUD")
	await _frames()

func _test_task_list() -> void:
	var first := {"id":"guidance_first", "title":"第一张委托", "kind":"campaign", "need":3, "progress":0, "gold":10, "xp":1, "ui_status":"进行中", "ui_objective":"规则A；保留完整说明", "history":"旧记录不是当前事实", "live_facts":"当前现场尚未目视", "ui_reward":"每段只领取一次", "next_action":"与留守巡守交谈", "target_title":"留守巡守", "step_progress":"0/1"}
	var selected := first.duplicate(true)
	selected.id = "guidance_selected"
	selected.title = "当前路线"
	selected.next_action = "返回北侧工点 · 原路接续"
	selected.step_progress = "路线 1/3"
	GameState.tracked_quest_id = str(selected.id)
	EventBus.quest_list_changed.emit([first, selected], str(selected.id))
	EventBus.quest_updated.emit("旧格式字符串不可用作结构")
	_check(_hud.quest_label.text.contains(selected.next_action), "结构化下一步含标点时不被切片")
	_hud._open_task_list()
	await _frames()
	var row: Node = _hud._task_rows.get_child(0)
	_check(row.name == "QuestRow_guidance_selected", "当前跟踪任务排在列表首位")
	_check(row.get_child(0).text.contains("路线 1/3") and row.get_child(1).text == selected.next_action, "列表首屏显示局部进度与完整下一步")
	var details: Control = row.get_node("QuestDetails_guidance_selected")
	_check(not details.visible and not details.get_child(0).is_visible_in_tree(), "历史/规则默认折叠")
	_check(_hud._task_rows.get_node("AutomaticBountySection").get_index() > _hud._task_rows.get_node("QuestRow_guidance_first").get_index(), "自动赏金在当前任务之后")
	var toggle: Button = row.find_child("DetailsToggle_guidance_selected", true, false)
	await _touch(toggle)
	_check(details.visible and details.get_child(0).text == first.ui_objective, "真实触屏展开完整规则没有删减")
	_check(details.get_child(2).text == first.history and details.get_child(3).text == first.live_facts, "展开后历史与当前事实分别保留")
	await _touch(toggle)
	_check(not details.visible, "再次触屏折叠详情")
	_hud._close_choice_layer()
	_check(not get_tree().paused, "关闭列表恢复世界")
	GameState.campaign_quest = Data.create(GameState.world_seed)
	GameState.tracked_quest_id = ""
	_qm._push_hud()

func _test_hunt_clue() -> void:
	var goblin: SpeciesData
	for species: SpeciesData in SpeciesCatalog.build_all():
		if species.species_name == "火把哥布林": goblin = species
	var region := SimRegion.new()
	region.id = "guidance_hunt"
	region.display_name = "北侧林地"
	region.center = _player.position + Vector2(5000, 0)
	region.size = Vector2(20000, 20000)
	region.capacity = 100
	var sim := EcologySim.new()
	sim.setup([region], [goblin], {})
	WorldSim.start(sim)
	WorldSim.set_process(false)
	for i in 3:
		sim.spawn_instance(goblin, region.id, 30, 0, 1.0, false, _player.position + Vector2(4000, i * 20))
	var quest := _qm._gen_quest("guidance_hunter", "hunt", "营地猎人")
	_check(not quest.is_empty(), "真实生成器提供本区活体猎杀委托")
	_qm.accept(quest)
	EventBus.quest_track_requested.emit(str(quest.id))
	var fog_before := GameState.explored.duplicate()
	var radar: Minimap = _hud.get_node("Root/Minimap")
	radar._refresh_navigation()
	_check(_hud.quest_label.text.contains("北侧林地") and _hud.quest_label.text.contains("火把哥布林"), "新猎杀HUD明确去哪找哪种目标")
	_check(radar._target.get("pos", Vector2.ZERO) == region.center and radar._target.get("kind", "") == "clue", "未见目标只导航居民给出的区域中心")
	_check(not radar._target.get("precise", true) and radar._category.text == "情报区域" and radar._distance.text == "大致方位", "搜索区域不是精确个体定位")
	for instance: MonsterInstance in sim.instances.values(): instance.spawn_pos += Vector2(5000, 5000)
	radar._refresh_navigation()
	_check(radar._target.get("pos", Vector2.ZERO) == region.center and GameState.explored == fog_before, "隐藏目标移动不会跟随位置或揭雾")
	_player.position = region.center
	var camera: Camera2D = _player.get_node("Camera2D")
	camera.reset_smoothing()
	camera.force_update_scroll()
	var cell := GameState.fog_cell_of(region.center)
	GameState.fog_reveal_cell(cell.x, cell.y)
	radar._refresh_navigation()
	_check(not radar._target.get("precise", true) and radar._category.text == "情报区域", "走到已探索区中心仍不把搜索区冒充已见个体")
	_qm.abandon(str(quest.id))
	WorldSim.stop()

func _test_completion_receipt() -> void:
	var quest := _qm._gen_quest("guidance_nest", "ransack", "遗迹学者")
	_qm.accept(quest)
	var gold_before := GameState.gold
	_hud._toast_timer = 0.0
	_hud.toast_label.text = ""
	for i in int(quest.need): EventBus.nest_ransacked.emit("火把哥布林")
	_check(GameState.gold > gold_before and GameState.quests.active.is_empty(), "实际捣巢事件完成并支付任务")
	_check(_hud.toast_label.is_visible_in_tree() and _hud.toast_label.modulate.a == 1.0 and _hud.toast_label.text.contains("已自动领奖"), "自动结算收据出现在真实可见HUD")
	_check(_hud.toast_label.text.contains("+%d 金币" % (GameState.gold - gold_before)) and _hud.toast_label.text.contains("经验"), "可见收据说明真实金币经验")
	var receipt_text: String = _hud.toast_label.text
	_qm._push_hud()
	_check(_hud.toast_label.text == receipt_text, "任务列表更新不能吞掉已显示收据")
	EventBus.nest_ransacked.emit("火把哥布林")
	_check(GameState.gold == gold_before + int(quest.gold), "继续事件不重复领奖")

func _test_item_feedback() -> void:
	_hud._pending_items_hint_shown = false
	GameState.inventory["onigiri"] = 98
	_hud._toast_timer = 0.0
	GameState.add_item("onigiri", 3)
	var text: String = _hud.toast_label.text
	_check(text.contains("已入背包：饭团 ×1（共99）") and text.contains("待领取 ×2"), "真实98加3明确1入背包2待领取")
	_check(text.contains("菜单→背包→待领取"), "首次溢出说明入口")
	GameState.add_item("fish", 1)
	EventBus.hint_requested.emit("宝箱已打开")
	EventBus.quest_completed.emit("已完成：测试委托 · +1金币 +1经验")
	_check(_hud.toast_label.text.contains("菜单→背包→待领取"), "同帧掉落/宝箱/完成不能挤掉首次待领取入口")
	var saw_completion: bool = _hud.toast_label.text.contains("测试委托")
	for i in 4:
		_hud._process(2.1)
		saw_completion = saw_completion or _hud.toast_label.text.contains("测试委托")
	_check(saw_completion and _hud._toast_backlog.is_empty(), "排队收据与后续反馈最终完整显示")
	_hud._toast_timer = 0.0
	GameState.add_item("onigiri", 2)
	text = _hud.toast_label.text
	_check(text == "已存待领取：饭团 ×2" and not text.contains("菜单"), "后续全满仍明确保存但不重复教程")
	_hud._toast_timer = 0.0
	GameState.inventory["fish"] = 0
	GameState.add_item("fish", 1)
	_check(_hud.toast_label.text.contains("已入背包") and not _hud.toast_label.text.contains("待领取"), "普通入包不误报溢出")

func _drain_toasts() -> void:
	for i in _hud._toast_backlog.size() + 1: _hud._process(2.1)

func _test_chest_feedback() -> void:
	_drain_toasts()
	_hud._pending_items_hint_shown = false
	var tutorial := Tutorial.new()
	GameState.tutorial_flags = {"open1":true, "open2":true, "find_camp":true}
	add_child(tutorial)
	var chest := preload("res://scripts/main/game_world.gd").DungeonChest.new()
	chest.locked = false
	chest.key_id = EconomyMath.KEY_SILVER
	add_child(chest)
	for id: String in EconomyMath.BOSS_BONUS_POOL + EconomyMath.COLLECT_POOL_RARE:
		GameState.inventory[id] = 99
	GameState.inventory[chest.key_id] = 1
	var hash_value: int = hash("chest|%s|%d" % [chest.key_id, GameState.stats.level])
	var supply: String = EconomyMath.BOSS_BONUS_POOL[absi(hash_value) % EconomyMath.BOSS_BONUS_POOL.size()]
	var material: String = EconomyMath.COLLECT_POOL_RARE[absi(hash_value >> 8) % EconomyMath.COLLECT_POOL_RARE.size()]
	chest.interact()
	_check(chest.taken and GameState.count_item(chest.key_id) == 0, "真实宝箱交互扣钥匙并完成一次开箱")
	var shown: String = _hud.toast_label.text
	_check(shown.contains("菜单→背包→待领取") and shown.contains(ItemCatalog.name_of(supply)), "真实宝箱双件满仓与教学连发保留首次待领取入口")
	for i in _hud._toast_backlog.size() + 1:
		_hud._process(2.1)
		shown += "\n" + _hud.toast_label.text
	_check(shown.contains("已存待领取：%s ×1" % ItemCatalog.name_of(supply)) and shown.contains("已存待领取：%s ×1" % ItemCatalog.name_of(material)), "双件宝箱的每张真实溢出收据都可见")
	_check(shown.contains("城塞宝箱") and _hud._toast_backlog.is_empty(), "宝箱摘要在收据后显示且队列排空")
	tutorial.free()
	chest.free()

func _test_receipt_burst() -> void:
	_drain_toasts()
	_hud._pending_items_hint_shown = false
	GameState.inventory["onigiri"] = 99
	for i in 100:
		GameState.add_item("onigiri", 1)
		EventBus.hint_requested.emit("普通现场提示%d" % i)
	_check(_hud.toast_label.text.contains("菜单→背包→待领取"), "百次连续溢出仍保留首次入口")
	_check(_hud._toast_backlog.size() <= 2, "连续同类奖励只保留一张数量合并收据和一个提示组")
	var queued_pending := 0
	for entry: Dictionary in _hud._toast_backlog:
		queued_pending += int(entry.get("pending_count", 0))
	_check(queued_pending == 98, "已显示两件后其余98件精确合并不丢数量")
	_drain_toasts()
	_check(_hud._toast_backlog.is_empty(), "密集掉落后的有限队列可及时排空")

func _test_receipt_backdrop() -> void:
	_drain_toasts()
	GameState.inventory["onigiri"] = 99
	GameState.add_item("onigiri", 1)
	var label: Label = _hud.toast_label
	var style := label.get_theme_stylebox("normal") as StyleBoxFlat
	_check(label.has_theme_stylebox_override("normal") and style != null and style.bg_color.a >= 0.95, "真实满仓收据具有近乎不透明的专用底板")
	_check(style != null and style.get_content_margin(SIDE_LEFT) == 0 and style.get_expand_margin(SIDE_LEFT) == 10 and style.get_expand_margin(SIDE_BOTTOM) == 10, "底板向外留边且不改变文字换行尺寸")
	_check(label.mouse_filter == Control.MOUSE_FILTER_IGNORE, "收据底板不拦截触控")
	_hud._process(1.75)
	_check(is_equal_approx(_hud._toast_timer, 0.25) and is_equal_approx(label.modulate.a, 0.5) and label.get_theme_stylebox("normal") == style, "底板与文字共享原有淡出，计时不改变")
	get_tree().paused = true
	_hud._process(1.0)
	_check(is_equal_approx(_hud._toast_timer, 0.25) and is_equal_approx(label.modulate.a, 0.5), "暂停时收据文字与底板一起冻结")
	get_tree().paused = false
	_hud._process(0.3)
	_check(label.modulate.a == 0.0, "收据到期后底板随文字完全消失")
	EventBus.hint_requested.emit("普通现场提示")
	_check(not label.has_theme_stylebox_override("normal") and label.modulate.a == 1.0, "普通提示恢复原样，不遗留收据底板")
	EventBus.quest_completed.emit("已完成：背景检查 · +1金币 +1经验")
	_check(label.has_theme_stylebox_override("normal"), "完成收据同样与世界姓名隔离")
	EventBus.hint_requested.emit("排队的普通提示")
	_hud._process(2.1)
	_check(label.text == "排队的普通提示" and not label.has_theme_stylebox_override("normal"), "排队切换到普通提示时也移除底板")

func _test_context_target() -> void:
	EventBus.context_interaction_changed.emit({"available":true, "target_id":"campaign:c2:herbalist", "target_title":"草药师", "label":"交谈"})
	_check(_hud._context_target_label.text == "草药师" and (_hud._context_btn.get_node("Caption") as Label).text == "交谈", "独立交互显示实际对象并保留简短动作")
