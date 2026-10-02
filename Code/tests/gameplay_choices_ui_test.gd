## 玩法选择回归：真正的 GUI 触屏/键盘 → 养成、装备、任务、补给同源闭环。
extends Node2D

var _checks := 0
var _fails := 0
var _hud: CanvasLayer
var _player: Player
var _qm: QuestManager


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.save_enabled = false
	GameState.reset_all()
	WorldSim.stop()
	_test_preview_formulas()
	_hud = preload("res://scenes/ui/hud.tscn").instantiate()
	add_child(_hud)
	_player = preload("res://scenes/player/player.tscn").instantiate()
	add_child(_player)
	_player.set_physics_process(false)
	_qm = QuestManager.new()
	add_child(_qm)
	await _settle()
	await _test_resource_aware_quickuse()
	await _test_stat_and_passive_choices()
	await _test_equipment_offer()
	await _test_task_choices()
	await _test_codex_ecology()
	await _test_small_safe_area()
	_hud.queue_free()
	_player.queue_free()
	_qm.queue_free()
	await _settle()
	get_tree().paused = false
	WorldSim.stop()
	if _fails == 0:
		print("=== GAMEPLAY CHOICES UI PASSED (%d checks) ===" % _checks)
	get_tree().quit(0 if _fails == 0 else 1)


func _check(ok: bool, label: String) -> void:
	_checks += 1
	print("  %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_fails += 1


func _test_preview_formulas() -> void:
	var s := CharacterStats.new()
	s.strength = 15
	s.agility = 18
	s.intellect = 12
	s.upgrade_weapon = 2
	s.upgrade_staff = 3
	s.upgrade_vigor = 4
	s.age_days = 28
	s.lifespan_days = 30
	s.passives = {"phys": 2, "hp": 3, "cdr": 2, "mp_regen": 3, "atk_speed": 5}
	s.equips = {"weapon": _item("旧剑", {"atk": 0.17, "lifesteal": 0.04}),
		"armor": {"affixes": {"hp": 0.2, "cdr": 0.06}}}
	for attribute: String in ["strength", "agility", "intellect"]:
		var before := s.benefit_snapshot()
		var preview := s.preview_attribute(attribute)
		_check(s.benefit_snapshot() == before, attribute + "预览不改写原角色")
		s.set(attribute, int(s.get(attribute)) + 1)
		_check(preview["after"] == s.benefit_snapshot(), attribute + "预览等于真实公式含升级装备被动衰老")
		s.set(attribute, int(s.get(attribute)) - 1)
	for passive: Dictionary in CharacterStats.PASSIVE_POOL:
		var id: String = passive["id"]
		var preview := s.preview_passive(id)
		var rank := s.passive_level(id)
		s.add_passive(id)
		_check(preview["after"] == s.benefit_snapshot(), id + "赐福预览等于实际领取收益")
		s.passives[id] = rank
	var replacement := _item("寒冰剑", {"gold": 0.3, "xp": 0.2}, "ice")
	var preview := s.preview_equipment(replacement)
	_check(s.equip_element() == "fire", "比较装备不会改动当前武器元素")
	s.equips["weapon"] = replacement
	_check(preview["after"] == s.benefit_snapshot(), "装备比较调用实际衍生公式")
	s.agility = 100
	_check(s.preview_attribute("agility")["after"]["attack_interval"] == s.attack_interval(),
			"攻速到下限后预览不会虚构收益")


func _test_resource_aware_quickuse() -> void:
	GameState.inventory = {"onigiri": 3, "life-pot": 1, "water-pot": 3}
	_player.current_hp = _player.stats.max_hp()
	_player.current_mp = 10
	_player._push_hud()
	EventBus.inventory_changed.emit()
	_check(_hud._quick_id == "water-pot", "满血缺蓝时快捷槽跳过全部食物选择水壶")
	await _touch(_hud._quick_btn)
	_check(GameState.count_item("water-pot") == 2 and _player.current_mp > 10,
			"真实触屏补给应用在玩家精力且只扣一瓶")
	_check(GameState.count_item("life-pot") == 1, "满血补蓝没有误耗生命药")
	_player.current_mp = _player.stats.max_mp()
	_player._push_hud()
	_check(_hud._quick_id == "" and _hud._quick_btn.disabled, "满血满蓝禁用无效补给")
	_player.current_hp = 20
	_player._push_hud()
	_check(_hud._quick_id == "life-pot", "仅资源变化立即刷新为可用生命补给")
	await _touch(_hud._quick_btn)
	_check(is_equal_approx(_player.current_hp, _player.stats.max_hp())
			and GameState.count_item("life-pot") == 0, "真实触摸大药恢复生命并实时移除用尽图标")
	_check(_hud._quick_id == "", "补满生命后不继续选择无效食物")


func _test_stat_and_passive_choices() -> void:
	GameState.stats.pending_points = 2
	GameState.stats.passives = {"phys": 1}
	GameState.stats.changed.emit()
	var base := GameState.stats.strength
	await _touch(_hud.get_node("Root/StatButtons/BtnStrength"))
	_check(_hud._stat_layer.visible and get_tree().paused and GameState.stats.strength == base,
			"真实属性按钮先预览且不立刻消费")
	_check(_hud._stat_preview.text.contains("→") and _hud._stat_preview.text.contains("生命上限")
			and _hud._stat_owned.text.contains("蛮力1级"), "分点面板显示实际收益及已获被动")
	await _capture("stat-preview")
	await _press_key(KEY_ESCAPE)
	_check(not _hud._stat_layer.visible and not get_tree().paused and GameState.stats.pending_points == 2,
			"取消预览保留属性点并恢复世界")
	await _touch(_hud.get_node("Root/StatButtons/BtnStrength"))
	var expected: Dictionary = GameState.stats.preview_attribute("strength")["after"]
	await _touch(_hud._stat_confirm)
	_hud._stat_confirm.pressed.emit()
	_check(GameState.stats.strength == base + 1 and GameState.stats.pending_points == 1,
			"真实确认只分配一点，延迟重复回调无效")
	_check(GameState.stats.benefit_snapshot() == expected, "真实确认后战斗属性等于展示预览")
	_hud._open_stat_preview("intellect")
	GameState.stats.pending_passive_picks = 1
	GameState.stats.passive_choices.assign(["phys", "cdr", "hp"])
	GameState.stats.passive_offer_id += 1
	_hud._open_passive_pick()
	await _settle()
	_check(_hud.passive_layer.visible and not _hud._stat_layer.visible,
			"赐福中断分点时只保留最高层")
	_check((_hud.passive_cards[0] as Button).text.contains("→")
			and _hud._passive_owned.text.contains("蛮力1级"), "赐福卡显示当下到领取后及已获构筑")
	await _capture("blessing-preview")
	expected = GameState.stats.preview_passive("phys")["after"]
	await _touch(_hud.passive_cards[0])
	_check(GameState.stats.benefit_snapshot() == expected and GameState.stats.pending_passive_picks == 0,
			"真实触屏赐福所得和预览一致")
	_check(not get_tree().paused and not _hud._stat_layer.visible and not _hud.passive_layer.visible,
			"赐福领取后中断层没有复现或残留暂停")


func _item(item_name: String, affixes: Dictionary, element := "fire") -> Dictionary:
	return {"slot": "weapon", "name": item_name, "rarity": 2, "affixes": affixes, "element": element}


func _test_equipment_offer() -> void:
	var current := _item("吸血火刃", {"atk": 0.2, "lifesteal": 0.05})
	var candidate := _item("寻金冰刃", {"gold": 0.3, "xp": 0.2}, "ice")
	GameState.receive_equipment(current)
	GameState.receive_equipment(candidate)
	_check(not _hud._inv_layer.visible and not get_tree().paused
			and _hud._equipment_badge.text == "待比较", "战斗新装备只提示背包，不自动打断")
	await _press_key(KEY_O)
	await _settle()
	var benefit: Label = _hud._equipment_offer.find_child("EquipmentBenefit", true, false)
	_check(benefit.text.contains("物理攻击") and benefit.text.contains("金币倍率")
			and benefit.text.contains("火焰 → 寒冰"), "装备比较同时显示得失和真实元素切换")
	await _capture("equipment-candidate")
	var token := GameState.equipment_offer_id
	var old_gold := GameState.gold
	var keep: Button = _hud._equipment_offer.find_child("KeepEquipment", true, false)
	await _reveal(keep)
	await _touch(keep)
	_check(GameState.pending_equipment.is_empty() and GameState.stats.equips["weapon"] == current
			and GameState.gold > old_gold, "真实保留按钮出售候选且保留当前构筑")
	GameState.receive_equipment(candidate)
	_hud._resolve_equipment_offer(false, token)
	await _settle()
	_check(not GameState.pending_equipment.is_empty(), "旧候选按钮的延迟回调不能处理新候选")
	var equip: Button = _hud._equipment_offer.find_child("EquipCandidate", true, false)
	var expected: Dictionary = GameState.stats.preview_equipment(candidate)["after"]
	await _reveal(equip)
	await _touch(equip)
	_check(GameState.pending_equipment.is_empty() and GameState.stats.equips["weapon"] == candidate,
			"真实装备候选按钮完成明确换装")
	_check(GameState.stats.benefit_snapshot() == expected and _hud._equipment_badge.text == "",
			"真实换装收益与预览一致且待处理提示消失")
	await _press_key(KEY_ESCAPE)
	_hud._close_inventory()
	_check(not get_tree().paused, "背包重复关闭不残留暂停")


func _test_task_choices() -> void:
	GameState.quests["active"] = [
		{"id": "ui_one", "kind": "explore", "title": "探索附近地标", "need": 2, "progress": 0},
		{"id": "ui_two", "kind": "ransack", "title": "摧毁附近巢穴", "need": 2, "progress": 1},
		{"id": "ui_three", "kind": "explore", "title": "探索第三处", "need": 3, "progress": 0},
	]
	GameState.tracked_quest_id = "ui_one"
	_qm._push_hud()
	await _settle()
	await _touch(_hud.quest_label)
	_check(_hud._task_layer.visible and GameState.quests["active"].size() == 3,
			"真实触摸 HUD 任务行只打开列表，不放弃首单")
	await _capture("task-list")
	var track: Button = _hud._task_rows.find_child("Track_ui_two", true, false)
	await _reveal(track)
	await _touch(track)
	_check(GameState.tracked_quest_id == "ui_two" and GameState.quests["active"].size() == 3,
			"真实跟踪按钮选择第二单且不更改任务数")
	_check(_hud.quest_label.text.contains("摧毁附近巢穴"), "HUD 任务行即时改为已选目标")
	var abandon: Button = _hud._task_rows.find_child("Abandon_ui_one", true, false)
	await _reveal(abandon)
	await _touch(abandon)
	_check(GameState.quests["active"].size() == 3,
			"首次放弃点击只要求确认，不意外删除任务")
	var confirm_abandon: Button = _hud._task_rows.find_child("ConfirmAbandon_ui_one", true, false)
	await _reveal(confirm_abandon)
	await _touch(confirm_abandon)
	_check(GameState.quests["active"].size() == 2 and GameState.tracked_quest_id == "ui_two",
			"明确放弃按钮仅删除指定单，保留正在跟踪的另一单")
	for i in 3:
		await _press_key(KEY_ESCAPE)
		_hud._close_choice_layer()
		_check(not get_tree().paused and not _hud._task_layer.visible, "任务列表重复关闭幂等")
		await _touch(_hud.quest_label)
		_check(_hud._task_layer.visible, "任务列表可反复触屏打开")
	_hud._close_choice_layer()


func _test_codex_ecology() -> void:
	var extinct := SpeciesData.new()
	extinct.species_name = "永久消失者"
	var recoverable := SpeciesData.new()
	recoverable.species_name = "自然消失者"
	var endangered := SpeciesData.new()
	endangered.species_name = "濒危者"
	var region := SimRegion.new()
	region.id = "ui_ecology"
	region.capacity = 20
	region.center = Vector2(500, 500)
	var species: Array[SpeciesData] = [extinct, recoverable, endangered]
	var sim := EcologySim.new()
	sim.setup([region], species, {region.id: {endangered.species_name: 3}})
	sim.player_extinct[extinct.species_name] = true
	WorldSim.sim = sim
	GameState.codex = {extinct.species_name: 1, recoverable.species_name: 1, endangered.species_name: 1}
	await _press_key(KEY_C)
	_check(_hud.codex_layer.visible and _hud.codex_content.text.contains("本世界不会自然复苏")
			and _hud.codex_content.text.contains("仍可能自然复苏"), "实际图鉴区分玩家永久灭绝与自然可恢复")
	_check(_hud.codex_content.text.contains("全球仅3只")
			and _hud.codex_content.text.contains("杀光将永久灭绝"), "图鉴濒危信息给实际数量及猎杀后果")
	await _press_key(KEY_ESCAPE)
	WorldSim.stop()


func _test_small_safe_area() -> void:
	var root: Control = _hud.get_node("Root")
	root.set_anchors_preset(Control.PRESET_TOP_LEFT)
	root.position = Vector2(30, 20)
	for canvas: Vector2 in [Vector2(1160, 680), Vector2(1560, 720)]:
		root.size = canvas
		_hud._open_task_list()
		await _settle()
		var panel: Control = _hud._task_layer.get_node("Panel")
		var close: Control = _hud._task_layer.find_child("ChoiceClose", true, false)
		_check(root.get_global_rect().encloses(panel.get_global_rect())
				and panel.get_global_rect().encloses(close.get_global_rect()), "小任务面板及关闭按钮保持安全区内")
		_hud._close_choice_layer()
		_hud._open_stat_preview("intellect")
		await _settle()
		panel = _hud._stat_layer.get_node("Panel")
		_check(root.get_global_rect().encloses(panel.get_global_rect()), "实际收益多行预览保持安全区内")
		_hud._close_choice_layer()


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _reveal(control: Control) -> void:
	var parent := control.get_parent()
	while parent != null and not parent is ScrollContainer:
		parent = parent.get_parent()
	if parent is ScrollContainer:
		(parent as ScrollContainer).ensure_control_visible(control)
	await _settle()


func _press_key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	get_viewport().push_input(event)
	await get_tree().process_frame
	event = event.duplicate()
	event.pressed = false
	get_viewport().push_input(event)
	await _settle()


func _touch(control: Control) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.position = get_viewport().get_screen_transform() * control.get_global_rect().get_center()
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await _settle()


func _capture(stem: String) -> void:
	var directory := OS.get_environment("HOTW_CHOICE_SHOTS")
	if directory.is_empty() or DisplayServer.get_name() == "headless":
		return
	await _settle()
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(directory)
	var result := get_viewport().get_texture().get_image().save_png(directory.path_join(stem + ".png"))
	_check(result == OK, "图形证据已保存：" + stem)
