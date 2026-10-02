## 装备选择回归：真实击杀掉落、默认保留构筑、显式自动换装、背包触屏/键盘与存档迁移。
extends Node2D

var _checks := 0
var _fails := 0
var _hints: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.save_enabled = false
	GameState.SAVE_PATH = "user://gameplay_equipment_test.json"
	GameState.reset_all()
	EventBus.hint_requested.connect(func(message: String) -> void: _hints.append(message))
	_test_lock_choices()
	_test_pending_transactions()
	await _test_real_drop_path()
	_test_persistence()
	await _test_backpack()
	GameState.save_enabled = false
	GameState.reset_all()
	_check(GameState.equipment_locks.is_empty(), "新冒险清空装备锁定选择")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.SAVE_PATH))
	WorldSim.stop()
	if _fails == 0:
		print("=== GAMEPLAY EQUIPMENT PASSED (%d checks) ===" % _checks)
	get_tree().quit(0 if _fails == 0 else 1)


func _check(ok: bool, label: String) -> void:
	_checks += 1
	print("  %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_fails += 1


func _item(slot: String, name: String, affixes: Dictionary, rarity := 1) -> Dictionary:
	return {"slot": slot, "name": name, "rarity": rarity, "affixes": affixes}


func _test_lock_choices() -> void:
	var weapon := _item("weapon", "吸血火刃", {"atk": 0.05, "lifesteal": 0.03})
	weapon["element"] = "fire"
	var money := _item("weapon", "寻金之刃", {"gold": 0.25, "xp": 0.25}, 3)
	_check(GameState.try_equip(weapon), "首件掉落填入空槽")
	_check(GameState.is_equipment_locked("weapon"), "首件装备默认锁定")
	var gold_before := GameState.gold
	_check(not GameState.try_equip(money), "高总和金币/经验词条不覆盖攻击/吸血构筑")
	_check(GameState.stats.equips["weapon"] == weapon and GameState.stats.equip_element() == "fire",
			"锁定完整保留词条与元素")
	_check(GameState.gold == gold_before and GameState.pending_equipment == money, "锁定槽候选尚未出售")
	var offer_id := GameState.equipment_offer_id
	_check(GameState.resolve_pending_equipment(false, offer_id), "明确保留构筑才出售候选")
	_check(GameState.gold == gold_before + EconomyMath.sell_price(3), "手动出售只折金一次")
	_check(not GameState.resolve_pending_equipment(false, offer_id), "重复选择不重复给金币")
	_check(GameState.set_equipment_locked("weapon", false), "可明确开启自动换装")
	_check(not GameState.set_equipment_locked("weapon", false), "重复相同选择幂等")
	gold_before = GameState.gold
	_check(GameState.try_equip(money), "明确解锁后按词条总和自动替换")
	_check(GameState.gold == gold_before + roundi(EconomyMath.sell_price(1) * GameState.stats.gold_mult()),
			"自动替换按既有经济规则出售旧件")
	_check(not GameState.is_equipment_locked("weapon"), "自动换装保留玩家明确的模式选择")
	_check(GameState.set_equipment_locked("weapon", true), "可以重新锁定当前装备")
	_check(not GameState.set_equipment_locked("unknown", false), "非法槽位不能切换")
	_check(not GameState.set_equipment_locked("helmet", false), "空槽无需切换模式")
	_check(GameState.try_equip(_item("helmet", "普通头盔", {})), "空槽零词条装备也能穿上")
	_check(GameState.is_equipment_locked("helmet") and GameState.is_equipment_locked("weapon"),
			"各槽位锁定独立")


func _test_pending_transactions() -> void:
	GameState.reset_all()
	var old := _item("weapon", "高分寻金刀", {"gold": 0.3, "xp": 0.3}, 3)
	var candidate := _item("weapon", "低分冰刃", {"atk": 0.05}, 1)
	candidate["element"] = "ice"
	GameState.receive_equipment(old)
	var gold_before := GameState.gold
	_check(GameState.receive_equipment(candidate) == "pending", "默认锁定保留低分候选供玩家选构筑")
	var first_id := GameState.equipment_offer_id
	var overflow := _item("weapon", "连续掉落火刃", {"atk": 0.15}, 2)
	overflow["element"] = "fire"
	_check(GameState.receive_equipment(overflow) == "sold", "单候选占位期间新掉落按明确规则折金")
	_check(GameState.pending_equipment == candidate and GameState.equipment_offer_id == first_id,
			"连续掉落不覆盖尚未选择的候选或更换凭证")
	_check(GameState.gold == gold_before + roundi(EconomyMath.sell_price(2) * GameState.stats.gold_mult()),
			"候选满位的新掉落不无声丢失且只结算一次")
	_check(not GameState.resolve_pending_equipment(true, first_id - 1), "无效凭证不能改变装备和候选")
	_check(GameState.resolve_pending_equipment(true, first_id), "玩家可明确选择总分更低但适合构筑的装备")
	_check(GameState.stats.equips["weapon"] == candidate and GameState.stats.equip_element() == "ice",
			"主动换装真正应用词条与元素")
	_check(GameState.pending_equipment.is_empty() and GameState.is_equipment_locked("weapon"),
			"处理后释放候选位且保护玩家主动选择")
	var after_swap := GameState.gold
	_check(not GameState.resolve_pending_equipment(false, first_id) and GameState.gold == after_swap,
			"快速换装后重放出售不会重复出售新装备")
	GameState.receive_equipment(overflow)
	_check(GameState.equipment_offer_id > first_id, "后续候选取得新的凭证")
	_check(not GameState.resolve_pending_equipment(false, first_id) and GameState.pending_equipment == overflow,
			"延迟旧按钮事件不会把新候选卖掉")
	var current_id := GameState.equipment_offer_id
	GameState.save_enabled = true
	_check(GameState.save_now(), "待比较候选可独立保存")
	var stored: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GameState.SAVE_PATH))
	GameState.pending_equipment.clear()
	GameState._load()
	_check(GameState.pending_equipment == overflow and GameState.equipment_offer_id == current_id,
			"加载完整恢复未决候选和凭证")
	_check(GameState.resolve_pending_equipment(false, current_id), "恢复候选仍可明确出售")
	_check(GameState.save_now(), "已处理候选落盘")
	GameState._load()
	_check(GameState.pending_equipment.is_empty() and not GameState.resolve_pending_equipment(false, current_id),
			"重载不复活已售候选")
	stored["version"] = 8
	stored.erase("pending_equipment")
	stored.erase("equipment_offer_id")
	stored.erase("bounty")
	stored.erase("tracked_quest_id")
	_write_save(stored)
	GameState._load()
	_check(GameState.pending_equipment.is_empty() and GameState.bounty.is_empty() and GameState.tracked_quest_id.is_empty(),
			"v8 迁移不凭空创建候选、赏金或追踪目标")
	stored["pending_equipment"] = {"slot": "unknown", "name": "坏候选", "affixes": []}
	stored["bounty"] = {"species": "火把哥布林", "region_id": "test", "need": "oops"}
	stored["tracked_quest_id"] = []
	_write_save(stored)
	GameState._load()
	_check(GameState.pending_equipment.is_empty() and GameState.bounty.is_empty() and GameState.tracked_quest_id.is_empty(),
			"坏候选/赏金/追踪类型安全丢弃，不能变成免费奖励")
	GameState.save_enabled = false


## 用实际怪物场景与 take_damage → _die_by_player → try_equip 链路，覆盖重复命中。
func _test_real_drop_path() -> void:
	GameState.reset_all()
	for slot: String in GameState.EQUIP_SLOTS:
		GameState.try_equip(_item(slot, "保留构筑·" + slot, {"atk": 0.01, "lifesteal": 0.01}))
	var kept := GameState.stats.equips.duplicate(true)
	var species := SpeciesData.new()
	species.species_name = "装备测试首领"
	species.is_boss = true  # 必掉史诗，避免随机概率使测试漏跑掉落路径
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
		if dead == inst:
			monster.on_sim_death())
	var gold_before := GameState.gold
	monster.take_damage(100000.0)
	_check(monster.state == MonsterBase.S_CORPSE and not inst.is_alive, "真实伤害走完击杀与生态死亡链路")
	_check(GameState.stats.equips == kept, "真实首领掉落也遵守四槽锁定")
	_check(GameState.gold == gold_before + EconomyMath.kill_gold(inst) and not GameState.pending_equipment.is_empty(),
			"真实击杀保留首领掉落供比较，尚未折金")
	_check(_hints.any(func(message: String) -> bool: return message.contains("待比较") and message.contains("换装或出售")),
			"掉落反馈明确指向背包选择，不谎称已出售")
	var settled_gold := GameState.gold
	monster.take_damage(100000.0)
	_check(GameState.gold == settled_gold and GameState.stats.equips == kept,
			"同帧重复命中尸体不会再掉落或重复折金")
	monster.queue_free()
	await get_tree().process_frame
	WorldSim.stop()


func _test_persistence() -> void:
	GameState.set_equipment_locked("boots", false)
	GameState.save_enabled = true
	_check(GameState.save_now(), "装备选择可保存")
	var stored: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GameState.SAVE_PATH))
	var kept := GameState.stats.equips.duplicate(true)
	GameState.stats.equips = {}
	GameState.equipment_locks = {}
	GameState._load()
	_check(GameState.stats.equips == kept, "读档恢复完整四槽装备")
	_check(GameState.is_equipment_locked("weapon") and not GameState.is_equipment_locked("boots"),
			"读档分别保留锁定和明确开启的自动模式")
	# v7 旧存档没有选择字段：升级后立即保护原构筑，不能等玩家先打开背包。
	stored["version"] = 7
	stored.erase("equipment_locks")
	_write_save(stored)
	GameState._load()
	for slot: String in GameState.EQUIP_SLOTS:
		_check(GameState.is_equipment_locked(slot), "旧档已占用槽默认锁定：" + slot)
	stored["equipment_locks"] = {"weapon": "false", "helmet": [], "armor": false, "unknown": false}
	_write_save(stored)
	GameState._load()
	_check(GameState.is_equipment_locked("weapon") and GameState.is_equipment_locked("helmet"),
			"坏类型不能意外解锁已占槽")
	_check(not GameState.is_equipment_locked("armor") and not GameState.equipment_locks.has("unknown"),
			"合法布尔 false 生效，未知槽丢弃")
	stored.erase("equips")
	stored["equip"] = _item("weapon", "旧版单武器", {"atk": 0.1})
	stored.erase("equipment_locks")
	_write_save(stored)
	GameState._load()
	_check(GameState.stats.equips.size() == 1 and GameState.is_equipment_locked("weapon"),
			"旧单武器迁移同样默认锁定，读档不串入上档装备")
	GameState.save_enabled = false


func _write_save(data: Dictionary) -> void:
	var file := FileAccess.open(GameState.SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()


func _test_backpack() -> void:
	GameState.reset_all()
	for slot: String in GameState.EQUIP_SLOTS:
		GameState.try_equip(_item(slot, "吸血攻击构筑", {"atk": 0.05, "lifesteal": 0.03}))
	var hud := preload("res://scenes/ui/hud.tscn").instantiate()
	add_child(hud)
	await get_tree().process_frame
	await get_tree().process_frame
	var bolt_key := InputEventKey.new()
	bolt_key.physical_keycode = KEY_I
	_check(InputMap.event_is_action(bolt_key, "cast_bolt") and not InputMap.event_is_action(bolt_key, "toggle_inventory"),
			"法弹 I 不再与背包抢键")
	var root: Control = hud.get_node("Root")
	root.set_anchors_preset(Control.PRESET_TOP_LEFT)
	root.position = Vector2.ZERO
	for canvas: Vector2 in [Vector2(1280, 720), Vector2(1560, 720), Vector2(1160, 680)]:
		root.size = canvas
		hud._toggle_inventory()
		await get_tree().process_frame
		await get_tree().process_frame
		var panel: Control = hud._inv_layer.get_child(1)
		_check(root.get_global_rect().encloses(panel.get_global_rect()), "背包面板在横屏安全区内：%s" % canvas)
		var close: Control = hud._inv_layer.find_child("InventoryClose", true, false)
		_check(panel.get_global_rect().encloses(close.get_global_rect()), "装备长列表不把关闭按钮推出面板")
		hud._close_inventory()
	root.size = Vector2(1280, 720)
	await _press_key(KEY_O)
	_check(hud._inv_layer.visible and get_tree().paused, "真实 O 键打开背包并暂停世界")
	var button: Button = hud._equipment_lock_buttons["weapon"]
	_check(button.text.contains("已锁定") and button.button_pressed, "装备行显示默认锁定状态")
	_check((hud._equipment_labels["weapon"] as Label).text.contains("吸血"), "装备行可直接比较现有词条")
	for slot: String in GameState.EQUIP_SLOTS:
		var target: Button = hud._equipment_lock_buttons[slot]
		_check(target.size.x >= 80 and target.size.y >= 64, "移动端开关有足够触控面积：" + slot)
	# 真实屏幕触摸分发点击首行开关，和键盘共用同一 toggled 状态入口。
	await _touch_button(button)
	_check(not GameState.is_equipment_locked("weapon") and button.text.contains("自动换装"),
			"真实触屏明确开启该槽自动换装")
	button.grab_focus()
	await _press_key(KEY_ENTER)
	_check(GameState.is_equipment_locked("weapon"), "真实 Enter 同源重新锁定装备")
	await _press_key(KEY_ENTER)
	_check(not GameState.is_equipment_locked("weapon"), "真实 Enter 同源开启自动模式")
	button.toggled.emit(false)
	button.toggled.emit(false)
	_check(not GameState.is_equipment_locked("weapon"), "重复相同 UI 事件不会反向锁回")
	# 挂起/重载时不依赖关闭面板提交；选择在点击时即进入存档真源。
	GameState.save_enabled = true
	_check(GameState.save_now(), "面板未关闭也可提交选择")
	GameState.equipment_locks = {}
	GameState._load()
	_check(not GameState.is_equipment_locked("weapon") and GameState.is_equipment_locked("armor"),
			"中断后重载保留明确选择，其他槽不受影响")
	GameState.save_enabled = false
	await _press_key(KEY_ESCAPE)
	_check(not hud._inv_layer.visible and not get_tree().paused, "Escape 关闭背包并恢复世界")
	button.toggled.emit(true)
	_check(not GameState.is_equipment_locked("weapon"), "隐藏面板延迟回调不篡改选择")
	for repeat in 3:
		await _press_key(KEY_O)
		_check(hud._inv_layer.visible and button.text.contains("自动换装"), "反复打开显示已保存模式")
		hud._close_inventory()
		hud._close_inventory()
		_check(not get_tree().paused and not hud._inv_layer.visible, "重复关闭幂等且不残留暂停")
	hud.queue_free()
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
	await get_tree().process_frame


func _touch_button(button: Button) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.position = get_viewport().get_screen_transform() * button.get_global_rect().get_center()
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await get_tree().process_frame
