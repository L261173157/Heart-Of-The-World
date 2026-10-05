## 完整背包实际引擎交互：菜单、分页、触屏滚动、确认、修订隔离、三种视口。
extends "res://tests/mobile_scroll_test.gd"

const Gear = preload("res://scripts/equipment/equipment_catalog.gd")
var _bag: Control

func _run() -> void:
	await _create_fixture()
	for canvas: Vector2i in [Vector2i(1280, 720), Vector2i(1560, 720), Vector2i(1024, 640)]:
		get_tree().root.size = canvas
		get_tree().root.content_scale_size = canvas
		get_tree().root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		get_tree().root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
		await _settle()
		await _test_bag_layout(canvas)
		await _test_affix_filter_ui(canvas)
	await _test_transactions()
	await _test_presets_and_batch()
	await _test_pending_and_craft()
	_hud.queue_free()
	_player.queue_free()
	await _settle()
	TouchInput.reset()
	get_tree().paused = false
	print("=== EQUIPMENT BAG UI %s (%d checks) ===" % ["PASS" if _fails == 0 else "FAIL", _checks])
	get_tree().quit(0 if _fails == 0 else 1)

func _create_fixture() -> void:
	GameState.stats.level = 20
	GameState.gold = 10000
	_player = preload("res://scenes/player/player.tscn").instantiate()
	_player.position = WorldConfig.spawn_pos()
	_player.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_player)
	_player.set_physics_process(false)
	_player.current_hp = 40
	_player.current_mp = 20
	GameState.inventory["equipment-parts"] = 99
	for i in 80:
		var slot: String = Gear.SLOTS[i % 6]
		var item := Gear.generate(8123 + i, 1 + i % 10, i % 4, slot)
		item["id"] = "ui_%03d" % i
		item["name"] = "%s · 旅程 %02d" % [item["name"], i]
		GameState.receive_equipment(item)
	for i in 6:
		GameState.equipment_action("equip", {"id": "ui_%03d" % i}, GameState.equipment_revision())
	_hud = preload("res://scenes/ui/hud.tscn").instantiate()
	add_child(_hud)
	_bag = _hud.get("_inv_layer")
	await _settle()

func _test_bag_layout(canvas: Vector2i) -> void:
	await _tap(_button("PauseBtn"))
	await _tap(_button("MenuInventory"))
	await _tap(_button("BagTab_loadout"))
	_check(_bag.visible and get_tree().paused, "菜单真实触控打开背包并暂停 " + str(canvas))
	var bounds := get_viewport().get_visible_rect()
	var panel: Control = _bag.find_child("BagPanel", true, false)
	var footer: Control = _bag.find_child("BagActionBar", true, false)
	print("BAG_LAYOUT canvas=", canvas, " panel=", panel.get_global_rect(), " min=", panel.get_combined_minimum_size(), " columns=", _bag.get("_columns").get_global_rect())
	_check(bounds.encloses(panel.get_global_rect()), "背包面板在视口内 " + str(canvas))
	_check(panel.get_global_rect().encloses(footer.get_global_rect()), "固定操作条完整可见 " + str(canvas))
	for slot: String in Gear.SLOTS:
		_check(_button("BagSlot_" + slot) != null, "显示六槽 " + slot)
	await _tap(_button("BagTab_gear"))
	_check(int(_bag.get("_pages")) >= 3, "真正装备分页，不创建无限控件")
	_check(_bag.find_children("BagItem_*", "Button", true, false).size() <= 24, "当前最多24装备行")
	await _tap(_button("BagNextPage"))
	_check(int(_bag.get("_page")) == 1, "真实触控进入下一页")
	var scroll: ScrollContainer = _bag.get("_list_scroll")
	var rows: VBoxContainer = _bag.get("_rows")
	var selected_before := str(_bag.get("_selected_id"))
	var point := _visible_row_point(scroll, rows)
	if point != Vector2.INF:
		await _finger_scroll(point, point + Vector2(0, -130))
	_check(scroll.scroll_vertical > 0, "真实行内手指拖动装备列表")
	_check(str(_bag.get("_selected_id")) == selected_before, "滚动抬手不误选装备")
	point = _visible_row_point(scroll, rows)
	var revision_before := GameState.equipment_revision()
	_touch(point, true, 7, false, false)
	_drag(point - Vector2(0, 35), 7)
	await _settle()
	var action := _button("BagFavorite")
	_touch(_center(action), true, 9, false, false)
	_touch(_center(action), false, 9, false, false)
	await _settle()
	_touch(point - Vector2(0, 35), false, 7, true, false)
	await _settle()
	_check(GameState.equipment_revision() == revision_before, "滚动时第二指不能触发操作条，系统取消不提交")

	_check(panel.get_global_rect().encloses(footer.get_global_rect()), "滚动长列表不会推走操作条")
	await _tap(_button("InventoryClose"))
	_check(not _bag.visible and _hud.pause_layer.visible and get_tree().paused, "背包返回保留上一层菜单")
	await _tap(_button("ResumeBtn"))
	_check(not get_tree().paused, "菜单返回游戏恢复暂停状态")
	for name_: String in FIXED:
		_check(_button(name_).visible, "固定六战斗键仍保留 " + name_)

func _test_affix_filter_ui(canvas: Vector2i) -> void:
	var original_state := GameState.equipment_state.duplicate(true)
	var filter_old := Gear.legacy_item({"name": "旧制物攻筛选样本", "rarity": 2, "affixes": {"atk": 0.2}}, "ui_filter_legacy", "weapon")
	filter_old["favorite"] = true
	GameState.receive_equipment(filter_old)
	var filter_white := Gear.generate(9191, 1, 0, "physical_sword")
	filter_white["id"] = "ui_filter_white"
	filter_white["favorite"] = true
	GameState.receive_equipment(filter_white)
	await _key(KEY_O)
	await _tap(_button("BagTab_gear"))
	await _show_filter_controls()
	var slot := _button("BagSlotFilter")
	var rarity := _button("BagRarityFilter")
	var affix := _button("BagAffixFilter")
	var panel: Control = _bag.find_child("BagPanel", true, false)
	_check(affix != null and is_equal_approx(slot.position.y, affix.position.y) and is_equal_approx(rarity.position.y, affix.position.y), "部位、品质、属性筛选保持同一行 " + str(canvas))
	_check(panel.get_global_rect().encloses(affix.get_global_rect()) and not affix.get_global_rect().intersects(rarity.get_global_rect()), "第三属性下拉框在面板内且不重叠 " + str(canvas))
	await _select_option("BagAffixFilter", "phys")
	_check(_bag.get("_filters").get("affix", "") == "phys", "真实键盘打开下拉菜单并选择物攻 " + str(canvas))
	var rows := _bag.find_children("BagItem_*", "Button", true, false)
	var all_match := not rows.is_empty()
	for row: Node in rows:
		var id: String = str(row.name).trim_prefix("BagItem_")
		var item: Dictionary = GameState.equipment_state.items.get(id, {})
		var key := "atk" if bool(item.get("legacy", false)) else "phys"
		all_match = all_match and float(item.get("affixes", {}).get(key, 0.0)) > 0.0
	_check(all_match, "实际分页行只显示正物攻，含旧制 atk 和新制 phys")
	await _select_option("BagSlotFilter", "weapon")
	await _select_option("BagRarityFilter", 2)
	await _select_option("BagTagFilter", "favorite")
	rows = _bag.find_children("BagItem_*", "Button", true, false)
	_check(rows.size() == 1 and str(rows[0].name) == "BagItem_ui_filter_legacy", "属性、部位、品质、收藏组合只显示匹配旧制物品")
	await _select_option("BagAffixFilter", "magic")
	_check(_bag.find_children("BagItem_*", "Button", true, false).is_empty(), "改变属性组合得到明确空结果")
	await _select_option("BagAffixFilter", "")
	await _select_option("BagRarityFilter", -1)
	await _select_option("BagTagFilter", "all")
	await _select_option("BagSlotFilter", "")
	_check(int(_bag.get("_pages")) >= 3, "清除属性及组合筛选恢复完整分页")
	await _key(KEY_ESCAPE)
	# 筛选夹具与原有交易 / 长列表测试隔离，不改变其物品顺序和滚动目标。
	GameState.equipment_state = original_state
	GameState._equipment_bump()
	EventBus.equipment_offer_changed.emit()

func _show_filter_controls() -> void:
	var compact := _button("BagCompactFilters")
	if compact != null and _button("BagAffixFilter") == null:
		await _tap(compact)
	var scroll: ScrollContainer = _bag.get("_list_scroll")
	scroll.scroll_vertical = 0
	await _settle()

func _select_option(name_: String, value: Variant) -> void:
	await _show_filter_controls()
	var option: OptionButton = _button(name_) as OptionButton
	var target := -1
	for index in option.item_count:
		if option.get_item_metadata(index) == value: target = index
	_check(target >= 0, "筛选项存在：" + name_ + " / " + str(value))
	if target < 0: return
	option.grab_focus()
	await _key(KEY_ENTER)
	_check(option.get_popup().visible, "实际确认键打开筛选下拉菜单：" + name_)
	var focused := option.get_popup().get_focused_item()
	if focused < 0: focused = option.selected
	var movement := target - focused
	for step in absi(movement): await _key(KEY_DOWN if movement > 0 else KEY_UP)
	await _key(KEY_ENTER)
	await _settle()

func _open_fresh_gear() -> void:
	await _key(KEY_O)
	await _tap(_button("BagTab_gear"))
	if str(_bag.get("_gear_page")) != "bag": await _tap(_button("BagGear_bag"))
	_bag.set("_page", 0)
	_bag.set("_filters", {"slot": "", "rarity": -1, "sort": "newest"})
	_bag.set("_tag", "all")
	_bag.set("_selected_id", "")
	_bag.call("refresh")
	await _settle()

func _test_transactions() -> void:
	await _open_fresh_gear()
	var id := str(_bag.get("_selected_id"))
	var before_gold := GameState.gold
	await _tap(_button("BagFavorite"))
	_check(bool(GameState.equipment_state.items[id].favorite), "真实触控收藏物品")
	_check(_button("BagSell").disabled and _button("BagDecompose").disabled, "收藏同时阻止出售和分解")
	await _tap(_button("BagFavorite"))
	await _tap(_button("BagLock"))
	_check(bool(GameState.equipment_state.items[id].locked) and _button("BagSell").disabled, "锁定独立阻止破坏")
	await _tap(_button("BagLock"))
	await _tap(_button("BagSell"))
	_check(_bag.call("confirmation_active") and GameState.gold == before_gold, "出售先显示单独确认，尚未给金币")
	await _key(KEY_ESCAPE)
	_check(not _bag.call("confirmation_active") and _bag.visible, "Escape只取消确认，背包仍打开")
	await _tap(_button("BagSell"))
	var delayed: Callable = _button("BagConfirmAccept").pressed.get_connections()[0]["callable"]
	var extra := Gear.generate(9981, 1, 0, "weapon")
	extra["id"] = "ui_incoming"
	GameState.receive_equipment(extra)
	await _settle()
	_check(not _bag.call("confirmation_active"), "新修订自动撤下已过期确认")
	delayed.call()
	_check(GameState.equipment_state.items.has(id) and GameState.gold == before_gold, "旧确认回调不能出售旧件或新掉落")
	_bag.set("_selected_id", id)
	_bag.call("refresh")
	await _settle()
	var sale := Gear.sale_value(GameState.equipment_state.items[id])
	await _tap(_button("BagSell"))
	await _tap(_button("BagConfirmAccept"))
	_check(not GameState.equipment_state.items.has(id) and GameState.gold == before_gold + sale, "明确出售只结算一次")
	await _tap(_button("BagGear_buyback"))
	_check(_button("BagBuyback") != null, "售出件可在永久回购页查看")
	await _tap(_button("BagBuyback"))
	_check(GameState.equipment_state.items.has(id) and GameState.gold == before_gold, "原价购回同一ID且金币精确往返")
	await _tap(_button("BagGear_bag"))
	_bag.set("_selected_id", id)
	_bag.call("refresh")
	await _settle()
	await _tap(_button("BagDecompose"))
	var question := (_bag.find_child("BagConfirmText", true, false) as Label).text
	_check(question.contains("不可撤销") and not question.contains("确认出售"), "分解单独说明不可逆，无出售混用")
	await _tap(_button("BagConfirmCancel"))
	_check(GameState.equipment_state.items.has(id), "取消分解完整保留装备")
	# 鼠标和键盘与触控走同一按钮入口。
	await _mouse_click(_button("BagFavorite"))
	_check(bool(GameState.equipment_state.items[id].favorite), "真实鼠标同源收藏")
	_button("BagFavorite").grab_focus()
	await _key(KEY_ENTER)
	_check(not bool(GameState.equipment_state.items[id].favorite), "真实键盘同源取消收藏")
	await _key(KEY_ESCAPE)

func _test_presets_and_batch() -> void:
	await _key(KEY_O)
	await _tap(_button("BagTab_loadout"))
	await _scroll_to(_button("BagPreset_0"), _bag.get("_list_scroll"))
	await _tap(_button("BagPreset_0"))
	var old_loadout: Dictionary = GameState.equipment_state.equipped.duplicate(true)
	await _tap(_button("BagPresetSave"))
	await _tap(_button("BagConfirmAccept"))
	_check(GameState.equipment_state.presets[0].slots == old_loadout, "真实确认保存六槽完整方案")
	var field: LineEdit = _bag.find_child("BagPresetName", true, false)
	field.text = "巡游装配"
	await _tap(_button("BagPresetRename"))
	_check(GameState.equipment_state.presets[0].name == "巡游装配", "独立重命名不重录装备引用")
	var hp_before := _player.current_hp
	var mp_before := _player.current_mp
	await _scroll_to(_button("BagSlot_weapon"), _bag.get("_list_scroll"))
	await _tap(_button("BagSlot_weapon"))
	await _tap(_button("BagUnequip"))
	_check(not GameState.equipment_state.equipped.has("weapon") and GameState.equipment_state.items.has("ui_000"), "卸下旧件回包，不折金或消失")
	await _scroll_to(_button("BagPreset_0"), _bag.get("_list_scroll"))
	await _tap(_button("BagPreset_0"))
	await _tap(_button("BagPresetApply"))
	_check(GameState.equipment_state.equipped == old_loadout, "一次应用整套方案")
	_check(_player.current_hp <= hp_before and _player.current_mp <= mp_before, "应用方案不补生命和精力")
	await _scroll_to(_button("BagSlot_weapon"), _bag.get("_list_scroll"))
	await _tap(_button("BagSlot_weapon"))
	await _tap(_button("BagUnequip"))
	await _tap(_button("BagFindGear"))
	await _scroll_to(_button("BagItem_ui_000"), _bag.get("_list_scroll"))
	await _tap(_button("BagItem_ui_000"))
	_check(_button("BagClearReferences") != null and _button("BagSell") == null, "方案引用必须先单独移除，不能直接卖")
	await _tap(_button("BagClearReferences"))
	await _tap(_button("BagConfirmAccept"))
	_check(not GameState.equipment_state.presets[0].slots.values().has("ui_000") and GameState.equipment_state.items.has("ui_000"), "移除引用只改方案，装备仍保留")
	GameState.equipment_action("favorite", {"id": "ui_012", "value": true}, GameState.equipment_revision())
	GameState.equipment_action("lock", {"id": "ui_018", "value": true}, GameState.equipment_revision())
	await _settle()
	await _tap(_button("BagBatchMode"))
	await _tap(_button("BagSelectPage"))
	var selected: Array = _bag.get("_batch_ids").duplicate()
	_check(not selected.is_empty() and not selected.has("ui_012") and not selected.has("ui_018"), "批量默认排除收藏和锁定装备")
	var count_before: int = GameState.equipment_state.items.size()
	await _tap(_button("BagBatchSell"))
	_check(GameState.equipment_state.items.size() == count_before, "批量出售也必须经过独立确认")
	await _tap(_button("BagConfirmAccept"))
	_check(GameState.equipment_state.items.size() == count_before - selected.size(), "批量确认精确处理选中集合")
	await _tap(_button("BagGear_buyback"))
	var records_before: int = GameState.equipment_state.buyback.size()
	await _tap(_button("BagBuybackClear"))
	await _tap(_button("BagConfirmCancel"))
	_check(GameState.equipment_state.buyback.size() == records_before, "取消清空完整保留永久回购记录")
	await _tap(_button("BagBuybackClear"))
	await _tap(_button("BagConfirmAccept"))
	_check(GameState.equipment_state.buyback.is_empty(), "只有明确确认才永久清空回购记录")
	await _key(KEY_ESCAPE)

func _scroll_to(control: Control, scroll: ScrollContainer) -> void:
	for attempt in 36:
		if scroll.get_global_rect().grow(-4).has_point(_center(control)): return
		var distance := _center(control).y - scroll.get_global_rect().get_center().y
		var start := scroll.get_global_rect().get_center()
		var old_scroll := scroll.scroll_vertical
		await _finger_scroll(start, start - Vector2(0, clampf(distance, -90, 90)))
		if scroll.scroll_vertical == old_scroll: return

func _test_pending_and_craft() -> void:
	GameState.add_item("onigiri", 99)
	GameState.add_item("onigiri", 17)
	GameState.first_boss_choices = []
	for index in 3:
		var item := Gear.generate(177 + index, 3, 4, Gear.ORANGE_BASES[index])
		item["id"] = "ui_boss_%d" % index
		GameState.first_boss_choices.append(item)
	GameState._equipment_bump()
	await _key(KEY_O)
	await _tap(_button("BagTab_pending"))
	_check(_button("BagBossChoice_0") != null, "首Boss三橙候选留在待领取，不强弹模态")
	var detail_scroll: ScrollContainer = _bag.get("_detail_scroll")
	for attempt in 16:
		var target := _button("BagBossChoice_1")
		if detail_scroll.get_global_rect().grow(-4).has_point(_center(target)): break
		var distance := _center(target).y - detail_scroll.get_global_rect().get_center().y
		var start := detail_scroll.get_global_rect().get_center()
		var old_scroll := detail_scroll.scroll_vertical
		await _finger_scroll(start, start - Vector2(0, clampf(distance, -60, 60)))
		print("BOSS_UI_SCROLL before=", old_scroll, " after=", detail_scroll.scroll_vertical, " target=", target.get_global_rect(), " clip=", detail_scroll.get_global_rect())
		if detail_scroll.scroll_vertical == old_scroll: break
	await _tap(_button("BagBossChoice_1"))
	await _tap(_button("BagBossClaim"))
	await _tap(_button("BagConfirmAccept"))
	_check(GameState.first_boss_choices.is_empty() and GameState.equipment_state.items.has("ui_boss_1"), "明确三选一领取对应稳定ID")
	var pending_before := GameState.pending_items.duplicate(true)
	GameState.remove_item("onigiri", 5)
	_bag.call("refresh")
	await _settle()
	await _tap(_button("BagClaimPending"))
	_check(GameState.count_item("onigiri") == 99 and not GameState.pending_items.is_empty(), "溢出收据可部分领取，余量保留")
	_check(GameState.pending_items != pending_before, "领取只扣对应收据余量")
	await _tap(_button("BagTab_gear"))
	await _tap(_button("BagGear_craft"))
	var fixed: Dictionary = _bag.get("_offer")
	await _key(KEY_O)
	await _key(KEY_O)
	var reopened: Dictionary = _bag.get("_offer")
	_check(fixed == reopened, "关闭重开成品预览不重抽")
	var gold_before := GameState.gold
	var parts_before := GameState.count_item("equipment-parts")
	var count_before: int = GameState.equipment_state.items.size()
	await _tap(_button("BagCraftCommit"))
	_check(GameState.equipment_state.items.size() == count_before + 1, "真实制作按钮增加一件完整成品")
	_check(GameState.gold == gold_before - int(fixed.price) and GameState.count_item("equipment-parts") == parts_before - 6, "制作精确扣固定报价金币和六零件")
	await _scroll_to(_button("BagPurchaseWhite"), _bag.get("_list_scroll"))
	await _tap(_button("BagPurchaseWhite"))
	var text := ""
	for label: Node in (_bag.get("_detail") as Control).find_children("*", "Label", true, false): text += label.text + "\n"
	_check(text.contains("无随机词条"), "白装预览只显示固定主属性，不把聚合词条重复当随机属性")

	await _key(KEY_ESCAPE)

func _key(code: Key) -> void:
	var key := InputEventKey.new()
	key.keycode = code
	key.physical_keycode = code
	key.pressed = true
	get_viewport().push_input(key)
	await _settle()
	key = key.duplicate()
	key.pressed = false
	get_viewport().push_input(key)
	await _settle()

func _mouse_click(button: Button) -> void:
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.position = get_viewport().get_screen_transform() * _center(button)
	mouse.pressed = true
	Input.parse_input_event(mouse)
	await _settle()
	mouse = mouse.duplicate()
	mouse.pressed = false
	Input.parse_input_event(mouse)
	await _settle()
