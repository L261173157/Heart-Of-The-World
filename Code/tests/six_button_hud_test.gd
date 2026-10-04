## Real scene/input contracts for six fixed controls, explicit presets and reading stacks.
extends Node2D
class LongestOutpostFacts extends OutpostQuest:
	func facts() -> Dictionary:
		return {"visible_count": 24, "nest_visible": false}

var hud: CanvasLayer
var player: Player
var checks := 0
var failures := 0
var confirmations := 0
var branch_actions: Array[String] = []
const FIXED := ["AttackBtn", "ShieldBtn", "DashBtn", "ShortcutBtn", "QuickSlotBtn", "MoreBtn"]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.save_enabled = false
	GameState.reset_all()
	WorldSim.stop()
	TouchInput.reset()
	hud = preload("res://scenes/ui/hud.tscn").instantiate()
	add_child(hud)
	player = preload("res://scenes/player/player.tscn").instantiate()
	player.position = WorldConfig.spawn_pos()
	add_child(player)
	await settle()
	check(hud._hud_plate.get_global_rect().encloses(hud.hp_bar.get_global_rect()), "initial HUD mount contains HP before any synthetic resize")
	check(hud._hud_plate.get_global_rect().encloses(hud.mp_bar.get_global_rect()), "initial HUD mount contains MP before any synthetic resize")
	var menu_text: String = hud.get_node("Root/PauseBtn").text
	var embedded_font: FontFile = preload("res://assets/fonts/NotoSansSC-Regular.ttf")
	check(menu_text == "三" and embedded_font.has_char(menu_text.unicode_at(0)), "menu bars use a glyph present in the embedded iOS font")
	await layout_contracts()
	await actions_and_presets()
	await reading_contracts()
	await automatic_bounty_list_contract()
	await reading_toggle_contract()
	await fresh_gesture_contract()
	await alternate_clue_contract()
	await minimap_contracts()
	await minimap_occlusion_contract()
	await outpost_ui_contract()
	await outpost_population_navigation_contract()
	await outpost_choice_text_layout_contract()
	get_tree().paused = false
	hud.queue_free()
	player.queue_free()
	await settle()
	TouchInput.reset()
	await initial_world_mount_contract()
	if failures == 0:
		print("=== SIX BUTTON HUD PASS (%d checks) ===" % checks)
	get_tree().quit(0 if failures == 0 else 1)

func check(ok: bool, description: String) -> void:
	checks += 1
	print("%s %s" % ["PASS" if ok else "FAIL", description])
	if not ok: failures += 1

func button(id: String) -> Button:
	return hud.get_node("Root/" + id)

func layout_contracts() -> void:
	var root: Control = hud.get_node("Root")
	for canvas: Vector2 in [Vector2(1280, 720), Vector2(1560, 720), Vector2(1280, 960), Vector2(1160, 680), Vector2(1024, 576)]:
		root.set_anchors_preset(Control.PRESET_TOP_LEFT)
		root.position = Vector2(44, 18)
		root.size = canvas
		await settle()
		var visible_actions := 0
		for id: String in FIXED:
			var control := button(id)
			visible_actions += int(control.is_visible_in_tree())
			check(root.get_global_rect().encloses(control.get_global_rect()), "%s within landscape safe area %s" % [id, canvas])
			check(minf(control.size.x, control.size.y) >= 80, id + " has full thumb target")
			check(not control.get_global_rect().intersects(root.get_node("Joystick").get_global_rect()), id + " leaves joystick clear")
		for i in FIXED.size():
			for j in range(i + 1, FIXED.size()):
				check(not button(FIXED[i]).get_global_rect().grow(4).intersects(button(FIXED[j]).get_global_rect().grow(4)), FIXED[i] + "/" + FIXED[j] + " separated")
		check(visible_actions == 6, "exactly six fixed actions")
		check(hud._hud_plate.get_global_rect().encloses(hud.hp_bar.get_global_rect()), "HP fill stays inside its backing plate")
		check(hud._hud_plate.get_global_rect().encloses(hud.mp_bar.get_global_rect()), "MP fill stays inside its backing plate")
		check(not hud._hud_plate.get_global_rect().intersects(hud._tracked_plate.get_global_rect()), "status and tracked step remain distinct bounded panels")
		check(button("AttackBtn").size.x > button("ShieldBtn").size.x, "attack largest")
		for id: String in ["BtnShop", "BtnEco", "BtnBag", "BtnCodex", "ReturnTownBtn"]:
			check(not button(id).is_visible_in_tree(), id + " removed from persistent HUD")
	root.position = Vector2.ZERO
	root.size = Vector2(1280, 720)
	await settle()

func actions_and_presets() -> void:
	player.current_hp = 35
	player.current_mp = 0
	player._push_hud()
	GameState.inventory = {"life-pot": 2, "water-pot": 2}
	hud._set_recovery("heal")
	await tap(button("QuickSlotBtn"))
	check(GameState.count_item("life-pot") == 2 and GameState.count_item("water-pot") == 2, "insufficient MP never substitutes consumable")
	check(hud._quick_id == "heal" and hud._recovery_unavailable_reason() == "精力不足", "recovery explains MP unavailability")
	hud._set_recovery("item:life-pot")
	await tap(button("QuickSlotBtn"))
	check(GameState.count_item("life-pot") == 1 and player.current_hp > 35, "chosen recovery item used once")
	GameState.inventory.erase("life-pot")
	player.current_hp = 35
	player.current_mp = player.stats.max_mp()
	player._push_hud()
	await tap(button("QuickSlotBtn"))
	check(player.current_hp < 36 and player._heal_cd == 0, "missing selected item never substitutes heal skill")
	check(hud._recovery_unavailable_reason() == "物品用尽", "empty chosen item explained")
	await tap(button("MoreBtn"))
	check(hud._more_panel.visible and not get_tree().paused, "More independently opens while world continues")
	for id: String in ["HeavyBtn", "BoltBtn", "HealBtn", "EmpowerBtn"]:
		check(hud._more_panel.find_child(id, true, false).is_visible_in_tree(), id + " remains reachable from More")
	hud._set_shortcut("heavy")
	hud._more_panel.hide()
	await tap(button("ShortcutBtn"))
	check(player._heavy_cd > 0, "configured shortcut casts actual heavy attack")
	hud._set_shortcut("bolt")
	player.current_mp = player.stats.max_mp()
	player._push_hud()
	await tap(button("ShortcutBtn"))
	check(player._bolt_cd > 0, "same fixed shortcut can cast bolt")

func reading_contracts() -> void:
	hud._toggle_pause()
	check(get_tree().paused and hud.pause_layer.visible, "menu pauses")
	hud._toggle_inventory()
	check(hud._inv_layer.visible and not hud.pause_layer.visible and get_tree().paused, "inventory child replaces menu surface")
	hud._close_top_layer_or_toggle_pause()
	check(hud.pause_layer.visible and not hud._inv_layer.visible and get_tree().paused, "Back one level restores menu and pause")
	hud._close_top_layer_or_toggle_pause()
	check(not get_tree().paused, "Back from menu restores running world")
	GameState.stats.pending_passive_picks = 1
	hud._on_leveled_up(2, 1)
	check(not hud.passive_layer.visible and not get_tree().paused, "combat level-up does not open modal")
	TouchInput.queue_attack()
	TouchInput.queue_heal()
	hud._open_dialogue({"kind": "info", "giver": "巡守", "text": "请阅读调查线索。"})
	check(get_tree().paused and GameState.dialogue_open, "reading dialogue pauses")
	check(not hud._dialogue_panel.get_node("PortraitFrame").visible and not hud._dialogue_faceset.visible, "dialogue without a portrait never shows an empty frame")
	check(hud._dialogue_text.position.x == 32, "portrait-free dialogue reclaims its text column")
	check(not TouchInput.consume_attack() and not TouchInput.consume_heal(), "dialogue flushes buffered combat inputs")
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.position = button("AttackBtn").get_global_rect().get_center()
	mouse.pressed = true
	get_viewport().push_input(mouse, true)
	mouse = mouse.duplicate()
	mouse.pressed = false
	get_viewport().push_input(mouse, true)
	check(not TouchInput.consume_attack(), "native mouse attack cannot queue combat through reading modal")
	hud._close_dialogue()
	check(not get_tree().paused and not GameState.dialogue_open, "closing reading commits nothing and restores world")
	get_tree().paused = true
	hud._open_dialogue({"kind": "info", "text": "已有暂停"})
	hud._close_dialogue()
	check(get_tree().paused, "dialogue preserves existing external pause")
	get_tree().paused = false

func tap(control: Control) -> void:
	var at := control.get_global_rect().get_center()
	var touch := InputEventScreenTouch.new()
	touch.index = 7
	touch.position = get_viewport().get_screen_transform() * at
	touch.pressed = true
	Input.parse_input_event(touch)
	await physics(2)
	touch = touch.duplicate()
	touch.pressed = false
	Input.parse_input_event(touch)
	await physics(2)

func settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
func physics(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
	await get_tree().process_frame

func fresh_gesture_contract() -> void:
	EventBus.dialogue_confirmed.connect(func(_quest: Dictionary) -> void: confirmations += 1)
	var original := InputEventScreenTouch.new()
	original.index = 91
	original.position = get_viewport().get_screen_transform() * Vector2(450, 420)
	original.pressed = true
	Input.parse_input_event(original)
	hud._open_dialogue({"kind": "quest", "giver": "巡守", "text": "需要新的确认手势。", "quest": {"id": "fresh-test"}})
	await settle()
	await tap(hud._dialogue_yes)
	check(confirmations == 0 and hud._dialogue_panel.visible, "held original touch cannot confirm new dialogue with another finger")
	original = original.duplicate()
	original.pressed = false
	Input.parse_input_event(original)
	hud._on_dialogue_action("confirm")
	check(confirmations == 0, "original release frame cannot become confirmation")
	await settle()
	await tap(hud._dialogue_yes)
	check(confirmations == 1 and not hud._dialogue_panel.visible, "fresh post-release tap confirms once")
	hud._on_dialogue_action("confirm")
	check(confirmations == 1, "stale dialogue callback cannot double accept")

func minimap_contracts() -> void:
	var map: Minimap = hud.get_node("Root/Minimap")
	map._has_player = true
	map._interior_index = -1
	map._player_pos = player.global_position
	var position := player.global_position + Vector2(32, 0)
	var cell := GameState.fog_cell_of(position)
	GameState.fog_reveal_cell(cell.x, cell.y)
	var candidates: Array[Dictionary] = [{"id": "monster:42", "kind": "monster", "name": "火把哥布林", "species": "火把哥布林", "region_id": "test", "pos": position}]
	GameState.quests["active"] = [{"id": "tracked", "kind": "hunt", "species": "火把哥布林", "progress": 0, "need": 2}]
	map._quest_views = []
	GameState.tracked_quest_id = "__untracked__"
	check(map._select_target(candidates).is_empty(), "untracked quest never falls back to an unrelated visible enemy")
	GameState.tracked_quest_id = "tracked"
	var target := map._select_target(candidates)
	check(target.get("precise", false) and target.get("id", "") == "monster:42", "visible tracked target has a precise marker")
	candidates[0]["pos"] = player.global_position + Vector2(9000, 0)
	target = map._select_target(candidates)
	check(not target.get("precise", true) and target.get("knowledge", "") == "last_seen", "out-of-view target becomes explicitly stale last-seen knowledge")
	GameState.quests["active"][0]["progress"] = 2
	check(map._select_target(candidates).is_empty(), "completed hunt cannot keep stale target or remembered marker")
	GameState.tracked_quest_id = "camp-clue"
	var far := player.global_position + Vector2(8000, 0)
	map._quest_views = [{"id": "camp-clue", "kind": "camp_ecology", "camp_stage": "investigate", "progress": 0, "need": 1, "target_pos": [far.x, far.y], "ui_knowledge": "npc_intel"}]
	var before := GameState.explored.duplicate()
	target = map._select_target([])
	check(not target.get("precise", true) and target.get("knowledge", "") == "npc_intel", "NPC clue provides only coarse guidance outside sight")
	check(before == GameState.explored, "coarse quest intelligence does not reveal fog")
	map._quest_views[0]["target_pos"] = [position.x, position.y]
	map._quest_views[0]["species"] = "火把哥布林"
	map._quest_views[0]["hunt_region"] = "test"
	map._quest_views[0]["ui_knowledge"] = "visible"
	candidates[0]["pos"] = position
	target = map._select_target(candidates)
	check(target.get("precise", false) and map._seen_targets.has("camp-clue"), "visible original camp establishes sight memory")
	map._quest_views[0]["target_pos"] = [far.x, far.y]
	map._quest_views[0]["hunt_region"] = "replacement-region"
	map._quest_views[0]["ui_knowledge"] = "npc_intel"
	target = map._select_target(candidates)
	map._target = target
	map._update_labels()
	check(target.get("knowledge", "") == "npc_intel" and map._category.text == "情报区域", "same quest rerouted to unvisited target is new NPC intelligence")
	check(not map._seen_targets.has("camp-clue") and target.get("pos", Vector2.ZERO) == far, "reroute removes old ghost position and last-seen cache")
	GameState.quests["active"] = []
	GameState.tracked_quest_id = ""

func minimap_occlusion_contract() -> void:
	var map: Minimap = hud.get_node("Root/Minimap")
	map.set_process(false)
	map._has_player = true
	map._interior_index = -1
	map._player_pos = player.global_position
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	wall.position = player.global_position + Vector2(120, 0)
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 8
	shape.shape = circle
	wall.add_child(shape)
	add_child(wall)
	var hidden := player.global_position + Vector2(133.5, 0)
	var cell := GameState.fog_cell_of(hidden)
	GameState.fog_reveal_cell(cell.x, cell.y)
	await physics(2)
	check(get_viewport().get_camera_2d() != null, "occlusion regression uses a real active camera")
	check(not map._is_visible_position(hidden), "full sight ray rejects a small target immediately behind cover")
	wall.position = player.global_position + Vector2(18, 0)
	circle.radius = 5
	await physics(2)
	hidden = player.global_position + Vector2(28, 0)
	check(not map._is_visible_position(hidden), "nearby target within 32px is still occluded by cover")
	check(map._is_visible_position(player.global_position + Vector2(10, 0)), "clear short sight ray remains visible while excluding player body")
	wall.queue_free()
	await settle()
	map.set_process(true)

func reading_toggle_contract() -> void:
	GameState.stats.equips.erase("weapon")
	GameState.receive_equipment({"slot": "weapon", "name": "测试铁剑", "rarity": 1, "affixes": {"atk": 0.05}})
	hud._toggle_inventory()
	await settle()
	var lock: Button = hud._equipment_lock_buttons["weapon"]
	var scroll := lock.get_parent()
	while scroll != null and not scroll is ScrollContainer:
		scroll = scroll.get_parent()
	if scroll is ScrollContainer:
		scroll.ensure_control_visible(lock)
	await settle()
	check(lock.button_pressed and GameState.is_equipment_locked("weapon"), "real equipment toggle initially mirrors locked state")
	await tap(lock)
	check(not lock.button_pressed and not GameState.is_equipment_locked("weapon"), "raw touch toggles equipment control and actual lock exactly once")
	lock.grab_focus()
	var key := InputEventKey.new()
	key.keycode = KEY_ENTER
	key.physical_keycode = KEY_ENTER
	key.pressed = true
	get_viewport().push_input(key, true)
	await settle()
	key = key.duplicate()
	key.pressed = false
	get_viewport().push_input(key, true)
	await settle()
	check(lock.button_pressed and GameState.is_equipment_locked("weapon"), "native Enter still toggles same equipment control exactly once")
	hud._close_inventory()

func alternate_clue_contract() -> void:
	EventBus.camp_quest_action_requested.connect(func(action: String) -> void: branch_actions.append(action))
	var root: Control = hud.get_node("Root")
	var payload := {"kind": "camp_choice", "giver": "营地调查记录", "text": "目标存量不足；可保留据点，另找狩猎线索。", "options": [
		{"action": "choose_hunt", "label": "有限狩猎", "enabled": false, "disabled_reason": "需要3只，当前仅2只", "consequence": "保留巢穴和至少1只存活个体", "risk": "数量仍会变化"},
		{"action": "choose_ransack", "label": "捣毁巢穴", "consequence": "暂停繁衍120刻", "risk": "幸存者狂怒60秒"},
		{"action": "find_hunt_clue", "label": "寻找其他狩猎线索", "utility": true, "consequence": "保留已有历史贡献，核对附近真实线索", "risk": "当前据点不会被改变"}]}
	for size: Vector2 in [Vector2(1024, 640), Vector2(1024, 576), Vector2(1280, 720)]:
		root.size = size
		hud._open_dialogue(payload)
		await settle()
		check(root.get_global_rect().encloses(hud._dialogue_panel.get_global_rect()), "three-option branch panel stays inside landscape " + str(size))
		check(hud._dialogue_option_scroll.get_global_rect().end.y < hud._dialogue_no.get_global_rect().position.y, "scrollable branch cards cannot overlap fixed Back/Confirm row")
		var disabled: Button = hud._dialogue_option_box.find_child("Branch_choose_hunt", true, false)
		check(disabled.disabled and disabled.text.contains("需要3只"), "infeasible branch remains visibly disabled with stock reason")
		hud._preview_dialogue_option(payload["options"][0])
		check(hud._dialogue_selected_option.is_empty(), "disabled branch cannot force a confirmation preview")
		hud._close_dialogue()
	root.size = Vector2(1024, 640)
	hud._open_dialogue(payload)
	await settle()
	var alternate: Button = hud._dialogue_option_box.find_child("Branch_find_hunt_clue", true, false)
	hud._dialogue_option_scroll.ensure_control_visible(alternate)
	await settle()
	await tap(alternate)
	check(branch_actions.is_empty() and hud._dialogue_selected_option.get("action", "") == "find_hunt_clue", "alternative clue requires explicit review before committing")
	hud._on_dialogue_action("decline")
	check(branch_actions.is_empty() and hud._dialogue_selected_option.is_empty(), "Back from alternative preview changes no quest or world state")
	alternate = hud._dialogue_option_box.find_child("Branch_find_hunt_clue", true, false)
	hud._dialogue_option_scroll.ensure_control_visible(alternate)
	await settle()
	await tap(alternate)
	await tap(hud._dialogue_yes)
	check(branch_actions == ["find_hunt_clue"] and not get_tree().paused, "fresh confirmation sends exactly one explicit alternative-clue request")
	root.size = Vector2(1280, 720)
	await settle()

func initial_world_mount_contract() -> void:
	GameState.reset_all()
	var world := preload("res://scenes/main/main.tscn").instantiate()
	add_child(world)
	await physics(3)
	await settle()
	var mounted: CanvasLayer = world.get_node("HUD")
	check(mounted._hud_plate.get_global_rect().encloses(mounted.hp_bar.get_global_rect()), "actual game-world initial mount keeps HP inside plate without resizing root")
	check(mounted._hud_plate.get_global_rect().encloses(mounted.mp_bar.get_global_rect()), "actual game-world initial mount keeps MP inside plate without resizing root")
	world.queue_free()
	await settle()
	WorldSim.stop()

func automatic_bounty_list_contract() -> void:
	hud._task_snapshot = []
	GameState.quests["active"] = []
	GameState.tracked_quest_id = "__untracked__"
	GameState.bounty = {"species": "火把哥布林", "region_id": "test", "progress": 1, "need": 3,
		"gold": 42, "xp": 20, "original_need": 3, "original_gold": 42, "original_xp": 20}
	var saved := GameState.bounty.duplicate(true)
	var gold_before := GameState.gold
	EventBus.bounty_updated.emit("赏金：猎杀 火把哥布林 1/3 · 本地线索 营地附近")
	hud._open_task_list()
	await settle()
	var section: Control = hud._task_rows.find_child("AutomaticBountySection", true, false)
	var detail: Label = section.get_node("AutomaticBountyDetail")
	check(section.is_visible_in_tree() and detail.text.contains("1/3"), "automatic bounty remains readable when NPC task list is empty")
	check(detail.text.contains("42 金币") and detail.text.contains("20 经验"), "automatic bounty exposes original saved reward base")
	check(section.find_children("*", "Button", true, false).is_empty(), "automatic bounty section is read-only with no new tracking or abandonment")
	check(GameState.bounty == saved and GameState.gold == gold_before and GameState.tracked_quest_id == "__untracked__", "opening bounty details changes no progress, rewards, or tracked target")
	GameState.bounty["progress"] = 2
	EventBus.bounty_updated.emit("赏金：猎杀 火把哥布林 2/3 · 本地线索 营地附近")
	detail = hud._task_rows.find_child("AutomaticBountyDetail", true, false)
	check(detail.text.contains("2/3") and detail.text.contains("42 金币"), "visible task list refreshes bounty progress without changing reward base")
	hud._close_choice_layer()
	check(GameState.bounty["progress"] == 2 and GameState.gold == gold_before, "closing bounty reading never settles or discards the automatic bounty")
	GameState.bounty = {}
	EventBus.bounty_updated.emit("附近暂无合适赏金 · 继续探索")

## 新章节复用同一组输入/阅读组件，不能退回匿名据点或旧目标的目击缓存。
func outpost_ui_contract() -> void:
	var map: Minimap = hud.get_node("Root/Minimap")
	map._has_player = true
	map._interior_index = -1
	map._player_pos = player.global_position
	var at := player.global_position + Vector2(24, 0)
	var cell := GameState.fog_cell_of(at)
	GameState.fog_reveal_cell(cell.x, cell.y)
	GameState.tracked_quest_id = "lost_outpost_v1"
	var q := {"id": "lost_outpost_v1", "kind": "outpost", "title": "失联的前哨", "progress": 0, "need": 3,
		"chapter_stage": "investigation", "target_object_id": "patrol_record", "target_name": "遗落的巡逻札记",
		"target_pos": [at.x, at.y], "ui_knowledge": "npc_intel", "ui_objective": "调查路上的札记", "bonus": ""}
	map._quest_views = [q]
	var view := map._select_target([])
	check(view.get("name") == "遗落的巡逻札记" and view.get("precise", false), "前哨可见物件保留真实目标名称与精确指引")
	var far := at + Vector2(9000, 0)
	q["target_pos"] = [far.x, far.y]
	view = map._select_target([])
	map._seen_targets[q["id"]] = {"pos": at, "name": "旧札记", "kind": "clue"}
	q["target_object_id"] = "entrance_record"
	q["target_name"] = "门前的拖行痕迹"
	var fog_before := GameState.explored.duplicate()
	view = map._select_target([])
	check(view.get("name") == "门前的拖行痕迹" and not view.get("precise", true), "下一调查物件离屏仅给粗线索，不泄露精确目标")
	check(view.get("knowledge") == "npc_intel" and not map._seen_targets.has(q["id"]), "同一章节切换物件清除上一物件的目击缓存")
	check(GameState.explored == fog_before, "章节指引不揭开隐藏地图")
	check(QuestPresentation.objective(q) == "调查路上的札记" and QuestPresentation.bonus_item(q) == "", "章节表现不继承旧随机委托奖励或匿名目标")
	q["ui_objective"] = "第二段 · 绕过北侧残墙，取回专用急救包"
	hud._on_quest_list_changed([q], q["id"])
	hud._on_quest_updated("")
	check(hud.quest_label.text.contains("取回专用急救包") and not hud.quest_label.text.ends_with("第二段"), "追踪栏保留真实下一步，不能只显示章节序号")
	var actions_before := branch_actions.size()
	hud._open_dialogue({"kind": "camp_action", "action": "outpost:aid_bag", "giver": "巡守急救包", "text": "这是专用任务物资，不消耗背包药品。", "confirm_text": "取回急救包"})
	await settle()
	check(get_tree().paused and GameState.dialogue_open, "主动查看任务物件暂停世界")
	hud._on_dialogue_action("confirm")
	check(hud._dialogue_panel.visible and branch_actions.size() == actions_before, "前哨拾取不继承打开物件的旧确认")
	hud._on_dialogue_action("decline")
	check(not hud._dialogue_panel.visible and not get_tree().paused and branch_actions.size() == actions_before, "关闭前哨物件不提交取物动作并恢复暂停状态")
	hud._task_snapshot = [q]
	hud._open_task_list()
	hud._request_quest_action(q["id"], true)
	var labels := ""
	for label: Node in hud._task_rows.find_children("*", "Label", true, false): labels += str(label.text)
	check(labels.contains("任务物件和已支付记录仍会保留"), "前哨放弃确认明确保留物件/世界后果与支付证据")
	hud._close_choice_layer()
	map._quest_views = []
	hud._task_snapshot = []
	GameState.tracked_quest_id = "__untracked__"
	GameState.outpost_quest = {"stage": "completed", "last_summary": true, "evidence": {"next_clue_received": false}}
	hud._on_quest_updated("✓ 失联的前哨已完成")
	check(hud.quest_label.text.contains("留守巡守交流后续线索"), "完成修复后仍提示常驻巡守提供区域线索")
	GameState.outpost_quest["evidence"]["next_clue_received"] = true
	hud._on_quest_updated("✓ 失联的前哨已完成")
	check(hud.quest_label.text.contains("可以自由探索"), "听完后续线索不强迫开启新任务或锁住探索")
	GameState.outpost_quest = {}

func outpost_population_navigation_contract() -> void:
	var map: Minimap = hud.get_node("Root/Minimap")
	map._has_player = true
	map._interior_index = -1
	map._player_pos = player.global_position
	var seen := player.global_position + Vector2(24, 0)
	var nest := player.global_position + Vector2(96, 0)
	for point: Vector2 in [seen, nest]:
		var cell := GameState.fog_cell_of(point)
		GameState.fog_reveal_cell(cell.x, cell.y)
	var q := {"id": "lost_outpost_v1", "kind": "outpost", "progress": 2, "need": 3,
		"chapter_stage": "ecology", "species": "地精矿工", "hunt_region": "p_0_0", "target_instance_ids": [42],
		"target_object_id": "ecology:p_0_0|地精矿工", "target_name": "已调查巢址", "target_pos": [nest.x, nest.y],
		"ui_knowledge": "npc_intel", "ui_guide_mode": "investigate"}
	map._quest_views = [q]
	GameState.tracked_quest_id = q["id"]
	var candidates: Array[Dictionary] = [
		{"id": "monster:42", "kind": "monster", "pos": seen, "name": "地精矿工", "species": "地精矿工", "region_id": "p_0_0", "streamed": true},
		{"id": "monster:99", "kind": "monster", "pos": seen + Vector2(2, 0), "name": "地精矿工", "species": "地精矿工", "region_id": "p_0_0", "streamed": true},
		{"id": "nest:p_0_0|地精矿工", "kind": "nest", "pos": nest, "name": "地精矿工巢穴", "species": "地精矿工", "region_id": "p_0_0"},
	]
	var view := map._select_target(candidates)
	check(view.get("kind") == "nest", "尚需调查时优先真实巢址，近处游荡个体不偷换目的地")
	q["ui_guide_mode"] = "hunt"
	view = map._select_target(candidates)
	check(view.get("id") == "monster:42" and view.get("precise", false), "猎杀导航只标记当前可见且已核实的具体实例")
	candidates[0]["streamed"] = false
	view = map._select_target(candidates)
	check(not view.get("precise", true) and view.get("knowledge") == "last_seen", "未加载的模拟出生坐标不是当前可见演员，不能成为精确目标")
	candidates[0]["streamed"] = true
	candidates[0]["pos"] = seen + Vector2(9000, 0)
	view = map._select_target(candidates)
	check(view.get("pos") == seen and view.get("knowledge") == "last_seen" and not view.get("precise", true), "离巢目标遮蔽后保留真实旧目击，不追踪隐藏现坐标或假换巢址")
	check(view.get("id") != "monster:99", "同物种未纳入核实名单的可见个体不会接管导航")
	q["ui_guide_mode"] = "nest"
	view = map._select_target(candidates)
	check(view.get("kind") == "nest" and view.get("pos") == nest, "改选捣巢清除个体旧目击，恢复真实巢穴导航")
	map._quest_views = []
	GameState.tracked_quest_id = "__untracked__"

func outpost_choice_text_layout_contract() -> void:
	var chapter := LongestOutpostFacts.new()
	GameState.outpost_quest = preload("res://scripts/main/outpost_quest_data.gd").create({})
	var payload := chapter.choice_payload()
	var root: Control = hud.get_node("Root")
	for size: Vector2 in [Vector2(1024, 640), Vector2(1280, 720), Vector2(1560, 720)]:
		root.size = size
		hud._open_dialogue(payload)
		await settle()
		var bottom: float = hud._dialogue_text.position.y + hud._dialogue_text.get_minimum_size().y
		check(bottom <= hud._dialogue_option_scroll.position.y - 4, "最长真实生态说明在%s不覆盖分支卡片" % size)
		check(hud._dialogue_text.text.contains("不能据此断言当前现场存量"), "精简文案仍明确目视知识边界")
		hud._close_dialogue()
	root.size = Vector2(1280, 720)
	GameState.outpost_quest = {}
	chapter.free()
	await settle()
