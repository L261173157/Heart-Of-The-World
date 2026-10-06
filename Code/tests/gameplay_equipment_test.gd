## 装备选择回归：真实击杀收据、全量所有权、显式换装/出售、背包触屏与旧档迁移。
extends Node2D

var _checks := 0
var _fails := 0
var _hints: Array[String] = []
var _player: Player

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.save_enabled = false
	GameState.SAVE_PATH = "user://gameplay_equipment_test.json"
	GameState.reset_all()
	WorldSim.stop()
	_player = preload("res://scenes/player/player.tscn").instantiate()
	add_child(_player)
	_player.set_physics_process(false)
	_player.set_process(false)
	EventBus.hint_requested.connect(func(message: String) -> void: _hints.append(message))
	_test_lock_choices()
	_test_pending_transactions()
	await _test_real_drop_path()
	_test_persistence()
	await _test_backpack()
	GameState.save_enabled = false
	GameState.reset_all()
	_check(GameState.equipment_state.items.is_empty() and GameState.equipment_state.equipped.is_empty()
			and GameState.pending_items.is_empty(), "新冒险清空所有权、装配与待领取")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.SAVE_PATH))
	WorldSim.stop()
	if _fails == 0:
		print("=== GAMEPLAY EQUIPMENT PASSED (%d checks) ===" % _checks)
	get_tree().quit(0 if _fails == 0 else 1)


func _check(ok: bool, label: String) -> void:
	_checks += 1
	print("  %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok: _fails += 1


func _item(slot: String, item_name: String, affixes: Dictionary, rarity := 1, id := "") -> Dictionary:
	return EquipmentCatalog.legacy_item({"slot": slot, "name": item_name, "rarity": rarity, "affixes": affixes}, id, slot)


func _action(action: String, payload: Dictionary) -> Dictionary:
	return GameState.equipment_action(action, payload, GameState.equipment_revision())


func _test_lock_choices() -> void:
	var weapon := _item("weapon", "吸血火刃", {"atk": 0.05, "lifesteal": 0.03}, 1, "choice:fire")
	weapon["element"] = "fire"
	var money := _item("weapon", "寻金之刃", {"gold": 0.25, "xp": 0.25}, 3, "choice:gold")
	_check(GameState.receive_equipment(weapon) == "stored" and GameState.stats.equips.is_empty(), "首件掉落只入包，不填空槽")
	_check(_action("equip", {"id": "choice:fire"}).get("ok", false), "明确穿戴指定所有权ID")
	_check(GameState.set_equipment_locked("weapon", true), "锁定当前物品用于防误处理")
	var gold_before := GameState.gold
	_check(GameState.receive_equipment(money) == "stored", "高金币经验词条装备也完整入包")
	_check(GameState.stats.equips.weapon.id == "choice:fire" and GameState.stats.equip_element() == "fire", "新掉落不覆盖攻击吸血构筑及元素")
	_check(GameState.gold == gold_before and GameState.equipment_state.items.size() == 2, "新装备既不出售也不丢失")
	_check(GameState.set_equipment_locked("weapon", false), "可明确解除物品锁定")
	var third := _item("weapon", "后续掉落", {"atk": 0.3}, 3, "choice:third")
	GameState.receive_equipment(third)
	_check(GameState.stats.equips.weapon.id == "choice:fire" and GameState.gold == gold_before, "解锁不恢复自动换装或自动出售")
	_check(_action("equip", {"id": "choice:gold"}).get("ok", false), "可主动选择收益方向不同的构筑")
	_check(GameState.equipment_state.items.has("choice:fire") and GameState.gold == gold_before, "换下旧件回背包，金币不变")
	_check(not GameState.set_equipment_locked("unknown", false) and not GameState.set_equipment_locked("helmet", false), "非法槽和空槽不能操作物品锁")
	for slot: String in ["offhand", "helmet", "armor", "boots", "charm"]:
		var id := "choice:" + slot
		GameState.receive_equipment(_item(slot, "部位装配·" + slot, {}, 0, id))
		_check(_action("equip", {"id": id}).get("ok", false), "六槽独立支持空词条穿戴：" + slot)
	_check(GameState.stats.equips.size() == 6 and GameState.equipment_state.items.size() == 8, "六槽引用与八件所有权数量守恒")


func _test_pending_transactions() -> void:
	GameState.reset_all()
	for index in 4:
		var item := _item("weapon", "连续掉落%d" % index, {"atk": 0.05}, 1, "owned:%d" % index)
		if index == 1: item["element"] = "ice"
		_check(GameState.receive_equipment(item) == "stored", "连续掉落每件都保留：%d" % index)
	_check(GameState.equipment_state.items.size() == 4 and GameState.gold == 0 and GameState.stats.equips.is_empty(), "没有单候选上限、自动折金或自动穿戴")
	var revision := GameState.equipment_revision()
	_check(not GameState.equipment_action("equip", {"id": "owned:1"}, revision - 1).get("ok", false), "过期修订号不能改变装配")
	_check(_action("equip", {"id": "owned:1"}).get("ok", false) and GameState.stats.equip_element() == "ice", "显式装配真正应用元素")
	_check(not GameState.equipment_action("sell", {"ids": ["owned:0"], "confirmed": true}, revision).get("ok", false), "换装后旧回调不能误卖其它物品")
	_check(not _action("sell", {"ids": ["owned:0"]}).get("ok", false), "出售必须确认所选物品")
	var price := EquipmentCatalog.sale_value(GameState.equipment_state.items["owned:0"])
	revision = GameState.equipment_revision()
	_check(_action("sell", {"ids": ["owned:0"], "confirmed": true}).get("ok", false), "明确出售恰好一件")
	_check(GameState.gold == price and GameState.equipment_state.items.size() == 3
			and GameState.equipment_state.buyback.size() == 1, "出售金额精确且同一物品进入永久回购")
	_check(not GameState.equipment_action("sell", {"ids": ["owned:0"], "confirmed": true}, revision).get("ok", false)
			and GameState.gold == price, "快速重复确认不重复结算")
	var expected := GameState.equipment_state.duplicate(true)
	GameState.save_enabled = true
	_check(GameState.save_now(), "全部所有权与回购记录可保存")
	GameState.equipment_state = EquipmentInventory.empty_state()
	GameState._load()
	_check(GameState.equipment_state.items.keys() == expected.items.keys()
			and GameState.equipment_state.equipped == expected.equipped
			and GameState.equipment_state.buyback[0].item.id == "owned:0", "加载恢复未穿、现用和已售三种明确位置")
	_check(_action("buyback", {"id": "owned:0"}).get("ok", false), "恢复后可原价购回同一实例")
	_check(GameState.gold == 0 and GameState.equipment_state.items.size() == 4 and GameState.equipment_state.buyback.is_empty(), "出售回购往返数量与金币严格守恒")
	_check(GameState.save_now(), "购回结果落盘")
	GameState._load()
	_check(GameState.equipment_state.items.size() == 4 and not _action("buyback", {"id": "owned:0"}).get("ok", false), "重载不复活已消费回购记录")
	GameState.save_enabled = false


## 实际怪物 take_damage → 击杀 → 来源锁定奖励事务；重复命中不能重发收据。
func _test_real_drop_path() -> void:
	GameState.reset_all()
	for slot: String in GameState.EQUIP_SLOTS:
		var id := "drop:kept:" + slot
		GameState.receive_equipment(_item(slot, "保留构筑·" + slot, {"atk": 0.01}, 1, id))
		_check(_action("equip", {"id": id}).get("ok", false), "实战前明确装配：" + slot)
	var kept := GameState.stats.equips.duplicate(true)
	var species := SpeciesData.new()
	species.species_name = "装备测试首领"
	species.is_boss = true
	species.xp_base = 0
	species.xp_per_age = 0.0
	var sim := EcologySim.new()
	var arena := SimRegion.new()
	arena.id = "arena"
	arena.center = Vector2(500, 500)
	arena.size = Vector2(1600, 1600)
	arena.capacity = 10
	sim.setup([arena], [species], {"arena": {species.species_name: 1}})
	WorldSim.sim = sim
	var inst: MonsterInstance = sim.instances.values()[0]
	var monster := preload("res://scenes/monsters/guardian.tscn").instantiate() as MonsterBase
	add_child(monster)
	monster.setup(inst)
	monster.set_physics_process(false)
	sim.instance_died.connect(func(dead: MonsterInstance, _cause: String) -> void:
		if dead == inst: monster.on_sim_death())
	var gold_before := GameState.gold
	monster.take_damage(100000.0, _player.global_position, false, 1.0, false, _player)
	_check(monster.state == MonsterBase.S_CORPSE and not inst.is_alive, "真实玩家来源伤害走完击杀与生态死亡链路")
	_check(GameState.stats.equips == kept, "真实首领掉落也不更改六槽装配")
	_check(GameState.gold == gold_before + EconomyMath.kill_gold(inst)
			and GameState.first_boss_choices.size() == 3 and GameState.equipment_state.items.size() == 6, "首领三选一保存在待领取，未选时不入包也不折金")
	_check(GameState.equipment_drop_state.receipts.size() == 1 and not GameState.first_boss_choice_source.is_empty(), "真实击杀只产生一个有来源的装备收据")
	var receipt_state := GameState.equipment_drop_state.duplicate(true)
	var choices := GameState.first_boss_choices.duplicate(true)
	var settled_gold := GameState.gold
	monster.take_damage(100000.0, _player.global_position, false, 1.0, false, _player)
	_check(GameState.gold == settled_gold and GameState.stats.equips == kept
			and GameState.first_boss_choices == choices and GameState.equipment_drop_state == receipt_state, "重复命中尸体不会增发金币、装备或选择资格")
	monster.queue_free()
	await get_tree().process_frame
	WorldSim.stop()


func _test_persistence() -> void:
	GameState.save_enabled = true
	_check(GameState.save_now(), "六槽装配与首领选择可保存")
	var stored: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GameState.SAVE_PATH))
	var kept := GameState.stats.equips.duplicate(true)
	GameState.equipment_state = EquipmentInventory.empty_state()
	GameState.stats.equips = {}
	GameState._load()
	_check(_same_data(GameState.stats.equips, kept) and GameState.first_boss_choices.size() == 3, "读档恢复六槽与未领取的首领奖励")
	# 构造真实v7原始四槽，不让新schema掩盖迁移路径。
	stored["version"] = 7
	stored["campaign_min_reader"] = 7
	stored.erase("equipment_schema")
	stored.erase("equipment_state")
	stored.erase("equipment_locks")
	stored.erase("first_boss_choices")
	stored["equips"] = {}
	for slot: String in ["weapon", "helmet", "armor", "boots"]:
		stored["equips"][slot] = {"slot": slot, "name": "旧装·" + slot, "rarity": 1, "affixes": {"atk": 0.05}}
	stored["pending_equipment"] = {"slot": "weapon", "name": "旧候选", "rarity": 2, "affixes": {"lifesteal": 0.02}, "element": "ice"}
	_write_save(stored)
	GameState._load()
	_check(GameState.stats.equips.size() == 4 and GameState.equipment_state.items.size() == 5
			and not GameState.stats.equips.has("offhand") and not GameState.stats.equips.has("charm"), "旧四槽和候选零丢失迁移；新两槽为空")
	var migrated: Array = GameState.equipment_state.items.keys()
	GameState._load()
	_check(GameState.equipment_state.items.keys() == migrated and GameState.pending_equipment.is_empty(), "重复迁移确定性ID且旧候选进入全量背包")
	stored["equipment_locks"] = {"weapon": "false", "helmet": [], "armor": false, "unknown": false}
	stored["pending_equipment"] = {"slot": "unknown", "name": "坏候选", "affixes": []}
	stored["bounty"] = {"species": "火把哥布林", "region_id": "test", "need": "oops"}
	stored["tracked_quest_id"] = []
	_write_save(stored)
	GameState._load()
	_check(GameState.equipment_state.items.size() == 4 and GameState.bounty.is_empty()
			and GameState.tracked_quest_id.is_empty(), "非法旧候选赏金追踪类型安全丢弃，四件合法装不受影响")
	_check(GameState.equipment_locks.is_empty() and not GameState.equipment_migration_notice.is_empty(), "旧槽自动模式退休且迁移有清晰提示")
	stored.erase("equips")
	stored.erase("pending_equipment")
	stored["equip"] = {"slot": "weapon", "name": "旧版单武器", "rarity": 1, "affixes": {"atk": 0.1}}
	_write_save(stored)
	GameState._load()
	_check(GameState.stats.equips.size() == 1 and GameState.equipment_state.items.size() == 1
			and GameState.stats.equips.weapon.name == "旧版单武器", "旧单武器迁移不串入上档装备")
	GameState.save_enabled = false


func _write_save(data: Dictionary) -> void:
	var file := FileAccess.open(GameState.SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()


func _test_backpack() -> void:
	GameState.reset_all()
	for slot: String in GameState.EQUIP_SLOTS:
		GameState.receive_equipment(_item(slot, "吸血攻击构筑", {"atk": 0.05, "lifesteal": 0.03}, 1, "ui_" + slot))
	var hud := preload("res://scenes/ui/hud.tscn").instantiate()
	add_child(hud)
	await _settle()
	var bolt_key := InputEventKey.new()
	bolt_key.physical_keycode = KEY_I
	_check(InputMap.event_is_action(bolt_key, "cast_bolt") and not InputMap.event_is_action(bolt_key, "toggle_inventory"), "法弹I不与背包抢键")
	var root: Control = hud.get_node("Root")
	root.set_anchors_preset(Control.PRESET_TOP_LEFT)
	root.position = Vector2.ZERO
	for canvas: Vector2 in [Vector2(1280, 720), Vector2(1560, 720), Vector2(1160, 680)]:
		root.size = canvas
		hud._toggle_inventory()
		await _settle()
		var panel: Control = hud._inv_layer.find_child("BagPanel", true, false)
		_check(root.get_global_rect().encloses(panel.get_global_rect()), "背包面板保持横屏安全区：%s root=%s panel=%s" % [canvas, root.get_global_rect(), panel.get_global_rect()])
		var close: Control = hud._inv_layer.find_child("InventoryClose", true, false)
		_check(panel.get_global_rect().encloses(close.get_global_rect()), "装备长列表不会把关闭按钮推出面板")
		hud._close_inventory()
	root.size = Vector2(1280, 720)
	await _press_key(KEY_O)
	_check(hud._inv_layer.visible and get_tree().paused, "真实O键打开背包并暂停世界")
	for slot: String in GameState.EQUIP_SLOTS:
		var target: Button = hud._inv_layer.find_child("BagSlot_" + slot, true, false)
		_check(target.size.x >= 80 and target.size.y >= 64, "六槽具有足够触控面积：" + slot)
	await _touch_button(hud._inv_layer.find_child("BagTab_gear", true, false))
	await _touch_button(hud._inv_layer.find_child("BagItem_ui_weapon", true, false))
	var detail: Control = hud._inv_layer.find_child("BagDetail", true, false)
	_check(_label_text(detail).contains("吸血") and _label_text(detail).contains("实际属性"), "真实装备详情显示词条和实际收益")
	await _touch_button(hud._inv_layer.find_child("BagEquip", true, false))
	_check(GameState.stats.equips.get("weapon", {}).get("id", "") == "ui_weapon" and GameState.equipment_state.items.size() == 6, "真实触屏只装配指定物品，所有权不减少")
	await _touch_button(hud._inv_layer.find_child("BagTab_loadout", true, false))
	await _touch_button(hud._inv_layer.find_child("BagSlot_weapon", true, false))
	var lock_button: Button = hud._inv_layer.find_child("BagLock", true, false)
	lock_button.grab_focus()
	await _press_key(KEY_ENTER)
	_check(GameState.is_equipment_locked("weapon"), "真实Enter锁定当前物品")
	var bag: Control = hud._inv_layer
	var old_revision := GameState.equipment_revision()
	var old_serial := int(bag.get("_serial"))
	GameState.save_enabled = true
	_check(GameState.save_now(), "背包未关闭也可保存明确选择")
	GameState.equipment_state = EquipmentInventory.empty_state()
	GameState._load()
	_check(GameState.is_equipment_locked("weapon") and GameState.equipment_state.items.size() == 6, "中断重载保持锁定与所有未穿装备")
	GameState.save_enabled = false
	await _press_key(KEY_ESCAPE)
	_check(not bag.visible and not get_tree().paused, "Escape关闭背包恢复世界")
	bag.call("_perform", "lock", {"id": "ui_weapon", "value": false}, old_revision, old_serial)
	_check(GameState.is_equipment_locked("weapon"), "隐藏面板的延迟回调不能篡改物品锁")
	for repeat in 3:
		await _press_key(KEY_O)
		_check(bag.visible and GameState.is_equipment_locked("weapon"), "反复打开保持已保存装配")
		hud._close_inventory()
		hud._close_inventory()
		_check(not get_tree().paused and not bag.visible, "重复关闭幂等且不残留暂停")
	hud.queue_free()
	await _settle()


func _label_text(node: Node) -> String:
	var text: String = node.text if node is Label else ""
	for child: Node in node.get_children(): text += "\n" + _label_text(child)
	return text


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


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


func _touch_button(button: Button) -> void:
	var parent := button.get_parent()
	while parent != null and not parent is ScrollContainer: parent = parent.get_parent()
	if parent is ScrollContainer: parent.ensure_control_visible(button)
	await _settle()
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.position = get_viewport().get_screen_transform() * button.get_global_rect().get_center()
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await _settle()


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
