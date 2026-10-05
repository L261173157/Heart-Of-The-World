## 真实 GameState 服务回归：同步存档回调、钱包/物品事务、迁移与坏字段隔离。
extends Node

const Catalog = preload("res://scripts/equipment/equipment_catalog.gd")
var checks := 0
var failures := 0
var watching := false
var expected: Dictionary = {}
var disk_before := PackedByteArray()
var callbacks := 0
var retry_source := ""
var prefix := ""


func _ready() -> void:
	GameState.save_enabled = false
	GameState.reset_all()
	prefix = "user://equipment-service-%d" % Time.get_ticks_usec()
	GameState.SAVE_PATH = prefix + ".json"
	EventBus.gold_changed.connect(_on_gold)
	EventBus.inventory_changed.connect(_on_inventory)
	_shop_and_equipment()
	_migration()
	_pending_collision()
	_preview_and_malformed_contracts()
	_future_schema()
	watching = false
	GameState.save_enabled = false
	EventBus.gold_changed.disconnect(_on_gold)
	EventBus.inventory_changed.disconnect(_on_inventory)
	if failures == 0:
		print("=== EQUIPMENT SERVICE PASS (%d checks) ===" % checks)
	else:
		printerr("=== EQUIPMENT SERVICE FAIL (%d/%d) ===" % [failures, checks])
	get_tree().quit(1 if failures else 0)


func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + label)


func _on_gold(_amount: int) -> void:
	_observe()


func _on_inventory() -> void:
	_observe()


func _observe() -> void:
	if not watching:
		return
	callbacks += 1
	_assert_memory("同步回调")
	check(GameState._world_reward_depth > 0, "回调仍位于完整事务边界内")
	check(not GameState.save_now(), "事务中同步保存不能声称已经落盘")
	check(FileAccess.get_file_as_bytes(GameState.SAVE_PATH) == disk_before, "同步保存请求不会产生半份交易档")
	var reentrant := GameState.equipment_action("buyback_clear", {"confirmed": true}, GameState.equipment_revision())
	check(not reentrant.get("ok", false) and reentrant.get("error", "") == "transaction_busy", "信号回调不可重入装备修改")
	if not retry_source.is_empty():
		check(not GameState.apply_inventory_transaction({}, {"onigiri": 4}, retry_source), "来源收据在回调前已关闭，不可重复发放")


func _begin_watch(values: Dictionary) -> void:
	expected = values
	disk_before = FileAccess.get_file_as_bytes(GameState.SAVE_PATH)
	callbacks = 0
	watching = true


func _end_watch() -> void:
	watching = false
	check(callbacks > 0, "实际信号回调执行")
	check(GameState._world_reward_depth == 0 and not GameState._equipment_busy, "事务退出后深度与防重入标志恢复")
	_assert_memory("提交完成")
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(GameState.SAVE_PATH))
	check(saved is Dictionary, "延后保存产出可读档")
	if saved is Dictionary:
		_assert_snapshot(saved)


func _assert_memory(label: String) -> void:
	if expected.has("gold"):
		check(GameState.gold == int(expected["gold"]), label + "可见完整钱包")
	for key: String in ["onigiri", "beaf", "equipment-parts"]:
		if expected.has(key):
			check(GameState.count_item(key) == int(expected[key]), label + "可见完整物品 " + key)
	if expected.has("owned_id"):
		check(GameState.equipment_state["items"].has(str(expected["owned_id"])) == bool(expected.get("owned", true)), label + "装备所有权已提交")
	if expected.has("buyback"):
		check(GameState.equipment_state["buyback"].size() == int(expected["buyback"]), label + "回购账本已提交")
	if expected.has("parts_pending"):
		check(_pending_total("equipment-parts") == int(expected["parts_pending"]), label + "溢出零件已提交")
	if expected.has("offers"):
		check(GameState.equipment_fixed_offers.size() == int(expected["offers"]), label + "已消费成品凭证已清除")


func _assert_snapshot(saved: Dictionary) -> void:
	if expected.has("gold"):
		check(int(saved.get("gold", -1)) == int(expected["gold"]), "存档钱包是交易后结果")
	for key: String in ["onigiri", "beaf", "equipment-parts"]:
		if expected.has(key):
			check(int(saved.get("inventory", {}).get(key, 0)) == int(expected[key]), "存档包含交易后物品 " + key)
	if expected.has("owned_id"):
		check(saved.get("equipment_state", {}).get("items", {}).has(str(expected["owned_id"])) == bool(expected.get("owned", true)), "存档装备所有权与钱包一致")
	if expected.has("buyback"):
		check(saved.get("equipment_state", {}).get("buyback", []).size() == int(expected["buyback"]), "存档回购与所有权一致")
	if expected.has("offers"):
		check(saved.get("equipment_fixed_offers", {}).size() == int(expected["offers"]), "存档不恢复已消费成品凭证")


func _pending_total(id: String) -> int:
	var result := 0
	for entry: Dictionary in GameState.pending_items.values():
		if str(entry.get("item_id", "")) == id:
			result += int(entry.get("count", 0))
	return result


func _action(action: String, payload: Dictionary) -> Dictionary:
	return GameState.equipment_action(action, payload, GameState.equipment_revision())


func _shop_and_equipment() -> void:
	GameState.gold = 200
	GameState.stats.passives = {"gold": 1}
	GameState.save_enabled = true
	check(GameState.save_now(), "建立隔离基准档")
	_begin_watch({"gold": 180, "onigiri": 1})
	check(GameState.buy_item("onigiri"), "真实购买补给成功")
	_end_watch()
	GameState.inventory["beaf"] = 3
	check(GameState.save_now(), "建立卖材料前完整档")
	var sale := roundi(3 * EconomyMath.item_sell_price("beaf") * GameState.stats.gold_mult())
	var wallet := GameState.gold + sale
	_begin_watch({"gold": wallet, "beaf": 0})
	check(GameState.sell_material("beaf") == 3, "真实普通材料出售成功且保留原倍率")
	_end_watch()
	var white: Dictionary = Catalog.mint_item(Catalog.generate(51, 1, 0), "service:white")
	check(GameState.receive_equipment(white) == "stored", "白装只进入背包")
	check(GameState.save_now(), "建立装备出售前完整档")
	_begin_watch({"gold": wallet + 20, "owned_id": "service:white", "owned": false, "buyback": 1})
	check(_action("sell", {"ids": ["service:white"], "confirmed": true}).get("ok", false), "装备固定20金不受贪婪放大")
	_end_watch()
	_begin_watch({"gold": wallet, "owned_id": "service:white", "owned": true, "buyback": 0})
	check(_action("buyback", {"id": "service:white"}).get("ok", false), "装备原价同ID购回")
	_end_watch()
	GameState.inventory["equipment-parts"] = 99
	check(GameState.receive_equipment(Catalog.mint_item(Catalog.generate(53, 5, 2, "shield"), "service:blue")) == "stored", "蓝装供分解")
	check(GameState.save_now(), "建立分解前完整档")
	_begin_watch({"gold": wallet, "equipment-parts": 99, "parts_pending": 2, "owned_id": "service:blue", "owned": false})
	check(_action("decompose", {"ids": ["service:blue"], "confirmed": true}).get("ok", false), "满99分解一次原子转待领取")
	_end_watch()
	GameState.equipment_explored_ilvl = 5
	var craft: Dictionary = GameState.equipment_offer("craft", "offhand", "focus")
	check(not craft.is_empty(), "制作完整成品先固定")
	check(GameState.save_now(), "建立制作前完整档")
	_begin_watch({"gold": wallet - 40, "equipment-parts": 93, "owned_id": str(craft["item"]["id"]), "owned": true, "offers": 0})
	check(_action("craft", {"token": str(craft["token"])}).get("ok", false), "真实制作原子扣钱扣料入库")
	_end_watch()
	check(not _action("craft", {"token": str(craft["token"])}).get("ok", false), "消费后旧制作凭据不可重复领取")


func _write_fixture(path: String, data: Dictionary) -> PackedByteArray:
	var bytes := JSON.stringify(data).to_utf8_buffer()
	var file := FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "测试夹具文件可写")
	if file != null:
		file.store_buffer(bytes)
		file.close()
	return bytes


func _migration() -> void:
	GameState.save_enabled = false
	GameState.SAVE_PATH = prefix + "-legacy.json"
	var old := {"version": 17, "campaign_min_reader": 17, "world_seed": 87654321,
		"level": 3, "gold": 400, "passives": {}, "inventory": {},
		"equips": {"weapon": {"name": "原值旧刃", "rarity": 3, "affixes": {"atk": 0.6, "hp": 0.7}, "element": "ice", "legacy_extension": ["keep", 42]}},
		"pending_equipment": {"slot": "armor", "name": "原值旧候选", "rarity": 2, "affixes": {"hp": 0.6}, "candidate_extension": "keep"}}
	var original := _write_fixture(GameState.SAVE_PATH, old)
	GameState._load()
	var id := "legacy:87654321:equipped:weapon"
	check(GameState.equipment_state["items"].has(id), "迁移生成稳定历史ID")
	var item: Dictionary = GameState.equipment_state["items"].get(id, {})
	check(is_equal_approx(float(item.get("affixes", {}).get("atk", 0.0)), 0.6), "迁移保留超边界历史原词条0.6")
	check(is_equal_approx(GameState.stats.equip_affix("atk"), 0.5), "历史实际效果仍沿用旧0.5边界")
	check(item.get("legacy_extension", []) == ["keep", 42.0], "旧制未知元数据保留")
	check(GameState.stats.equip_element() == "ice", "旧元素保持")
	var pending: Dictionary = GameState.equipment_state["items"].get("legacy:87654321:pending", {})
	check(is_equal_approx(float(pending.get("affixes", {}).get("hp", 0.0)), 0.6) and pending.get("candidate_extension", "") == "keep", "旧候选原值及扩展字段保留")
	GameState.save_enabled = true
	check(GameState.save_now(), "原值迁移成功保存")
	check(FileAccess.get_file_as_bytes(GameState.SAVE_PATH + ".pre-equipment-v17.bak") == original, "迁移备份字节与原档完全一致")
	GameState._load()
	check(is_equal_approx(float(GameState.equipment_state["items"][id]["affixes"]["atk"]), 0.6), "新档重读仍保留历史原词条")


func _pending_collision() -> void:
	GameState.save_enabled = false
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GameState.SAVE_PATH))
	data["pending_item_sequence"] = 0
	data["inventory"] = {"onigiri": 99}
	data["pending_items"] = {"pending:1": {"item_id": "onigiri", "count": 3, "source": "first"}, "pending:2": {"item_id": "onigiri", "count": 7, "source": "second"}}
	data["equipment_fixed_offers"] = {"invalid": {"kind": "craft", "item": ["bad"]}}
	GameState.SAVE_PATH = prefix + "-sequence.json"
	_write_fixture(GameState.SAVE_PATH, data)
	GameState._load()
	check(_pending_total("onigiri") == 10 and GameState.equipment_fixed_offers.is_empty(), "坏成品字段隔离且旧溢出记录完整")
	GameState.save_enabled = true
	check(GameState.save_now(), "重建低序列号基准档")
	retry_source = "service:overflow-receipt"
	_begin_watch({"gold": GameState.gold, "onigiri": 99})
	check(GameState.apply_inventory_transaction({}, {"onigiri": 4}, retry_source), "低序列号仍可无损生成新溢出收据")
	_end_watch()
	retry_source = ""
	check(GameState.pending_items.has("pending:1") and GameState.pending_items.has("pending:2") and GameState.pending_items.has("pending:3"), "重建ID避开已有两条收据")
	check(_pending_total("onigiri") == 14 and GameState.pending_items["pending:1"]["source"] == "first" and GameState.pending_items["pending:2"]["source"] == "second", "已有和新增余额守恒且原来源不变")
	GameState._load()
	check(_pending_total("onigiri") == 14, "所有溢出余额及收据保存后往返")


func _future_schema() -> void:
	GameState.save_enabled = false
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GameState.SAVE_PATH))
	data["version"] = 18
	data["campaign_min_reader"] = 18
	data["equipment_schema"] = 2
	data["future_equipment_payload"] = {"must_remain": ["未知格式", 123]}
	data["inventory"] = {"beaf": 3}
	GameState.SAVE_PATH = prefix + "-future-schema.json"
	var original := _write_fixture(GameState.SAVE_PATH, data)
	GameState._load()
	check(GameState.equipment_read_only(), "相同游戏版本的未来装备格式独立进入只读")
	var gold_before := GameState.gold
	var items_before := GameState.inventory.duplicate(true)
	check(not GameState.buy_item("onigiri") and GameState.gold == gold_before and GameState.inventory == items_before, "只读补给购买不扣钱且不谎报成功")
	check(GameState.sell_material("beaf") == 0 and GameState.gold == gold_before and GameState.inventory == items_before, "只读出售不删材料或修改钱包")
	check(not GameState.remove_item("beaf", 1), "只读不能消费已有物品")
	check(not GameState.apply_inventory_transaction({}, {"onigiri": 2}), "只读阻止新的物品交易")
	check(not _action("buyback_clear", {"confirmed": true}).get("ok", false), "只读阻止装备交易")
	GameState.save_enabled = true
	check(not GameState.save_now() and FileAccess.get_file_as_bytes(GameState.SAVE_PATH) == original, "未来装备未知数据按原字节保留，不能覆盖")

func _preview_and_malformed_contracts() -> void:
	GameState.save_enabled = false
	GameState.reset_all()
	GameState.gold = 500
	GameState.inventory["equipment-parts"] = 99
	var blue: Dictionary = GameState.equipment_offer("craft", "weapon")
	var other_blue: Dictionary = GameState.equipment_offer("craft", "boots")
	var white: Dictionary = GameState.equipment_offer("purchase", "helmet")
	check(_action("purchase", {"token": white.token}).get("ok", false), "另一笔白装购买成功")
	check(blue == GameState.equipment_offer("craft", "weapon"), "白装购买不重抽尚未购买蓝武器预览")
	check(other_blue == GameState.equipment_offer("craft", "boots"), "白装购买不重抽另一蓝靴预览")
	check(_action("craft", {"token": other_blue.token}).get("ok", false), "另一部位蓝装兑换成功")
	check(blue == GameState.equipment_offer("craft", "weapon"), "另一部位兑换也不重抽原预览")
	var broken := Catalog.generate(551, 1, 2, "weapon")
	broken["id"] = "bad-fixed-field"
	broken["fixed_affixes"] = []
	check(GameState.receive_equipment(broken) == "stored", "坏显示字段的实例保持所有权")
	var saved: Dictionary = GameState.equipment_state.items["bad-fixed-field"]
	check(saved.fixed_affixes is Dictionary and saved.has("raw_fixed_affixes"), "显示字段安全隔离且保存原始坏值")
	var bag: Control = preload("res://scripts/ui/equipment_bag.gd").new()
	bag.size = Vector2(1280, 720)
	add_child(bag)
	bag.set("_tab", "gear")
	bag.call("refresh")
	check(bag.get("_actions").get_child_count() > 0, "坏字段仍能安全打开真实装备详情")
	bag.queue_free()
	GameState.save_enabled = true
	check(GameState.save_now(), "后续未来格式检查保持有效基准档")
