## 每阶段独立进程：真实迁移、唯一所有权、待领取、回购、失败原子写与未来读者保护。
extends Node

var checks := 0
var failures := 0
var phase := ""
var player: Player

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1 or OS.get_environment("HOTW_TEST_SAVE").is_empty():
		get_tree().quit(1)
		return
	phase = args[0]
	GameState.save_enabled = false
	player = preload("res://scenes/player/player.tscn").instantiate()
	add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	player._equipment_safe_wait = 0.0
	match phase:
		"migrate": _migrate()
		"resume": _resume()
		"verify": _verify()
		"failure": _failure()
		"retry": _retry()
		"future", "future_schema": _future()
	print("EQUIPMENT_PERSISTENCE %s %s (%d checks)" % [phase, "PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("  %s %s" % ["PASS" if ok else "FAIL", label])

func action(kind: String, payload: Dictionary = {}) -> Dictionary:
	return GameState.equipment_action(kind, payload, GameState.equipment_revision())

func pending_total(id: String) -> int:
	var result := 0
	for entry: Dictionary in GameState.pending_items.values():
		if entry.item_id == id: result += int(entry.count)
	return result

func _migrate() -> void:
	check(GameState.equipment_state.items.size() == 5, "旧四槽和单候选全部转为五个唯一实例")
	check(GameState.equipment_state.equipped.size() == 4, "四件旧装备维持原装配位置，候选在包中")
	check(GameState.stats.equip_element() == "fire", "原武器元素保持")
	check(is_equal_approx(GameState.stats.equip_affix("atk"), .31), "原值汇总不受新28%帽削弱")
	for item: Dictionary in GameState.equipment_state.items.values():
		check(item.legacy and int(item.required_level) == 1, "每件旧装标记旧制且需求等级1")
	check(GameState.pending_equipment.is_empty(), "旧候选已入包，不保留可重复领取入口")
	var count: int = GameState.equipment_state.items.size()
	GameState._load()
	check(GameState.equipment_state.items.size() == count, "同一旧档再次迁移仍是同五个ID")
	check(GameState.apply_inventory_transaction({}, {"onigiri": 7}, "test:reward:one"), "满格奖励原子结算进入待领取")
	check(GameState.count_item("onigiri") == 99 and pending_total("onigiri") == 7, "99库存和7待领取合计106，守恒")
	check(not GameState.apply_inventory_transaction({}, {"onigiri": 7}, "test:reward:one"), "重复来源不可二次发货")
	check(action("preset_save", {"index": 0, "name": "旧装备"}).ok, "三个配置之一保存旧实例引用")
	var chosen := GameState.equipment_offer("craft", "offhand", "shield")
	check(not chosen.is_empty(), "蓝盾预览可生成")
	check(chosen == GameState.equipment_offer("craft", "offhand", "shield"), "取消重开使用同一完整预览")
	var source := EquipmentDrops.create_source(GameState.world_seed, "boss", 12345, 0, "hill")
	EquipmentDrops.begin_combat(GameState.equipment_drop_state, source, GameState.stats.equips, "boots")
	source["player_kill"] = true
	var receipt := EquipmentDrops.settle(GameState.equipment_drop_state, source)
	GameState.first_boss_choices = receipt.first_boss_choices
	GameState.first_boss_choice_source = receipt.source_id
	check(GameState.first_boss_choices.size() == 3 and receipt.items.is_empty(), "纯来源夹具只预留一次三选一不额外发紫装")
	GameState.equipment_drop_state.ordinary_failures = 24
	GameState.equipment_drop_state.elite_failures = 4
	GameState.equipment_drop_state.boss_orange_failures = 7
	GameState.gold = 800
	GameState.inventory["equipment-parts"] = 99
	GameState.save_enabled = true
	check(GameState.save_now(), "首次迁移完整保存成功")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GameState.SAVE_PATH))
	check(int(saved.campaign_min_reader) == GameState.SAVE_VERSION and int(saved.version) == GameState.SAVE_VERSION, "历史读者可识别的最小读取版本与当前格式一致")
	check(FileAccess.get_file_as_bytes(GameState.SAVE_PATH + ".pre-equipment-v17.bak") == FileAccess.get_file_as_bytes(GameState.SAVE_PATH + ".legacy"), "原始旧档字节备份未改变")
	var f := FileAccess.open(GameState.SAVE_PATH + ".expected", FileAccess.WRITE)
	f.store_string(JSON.stringify(saved))
	f.close()

func _resume() -> void:
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GameState.SAVE_PATH + ".expected"))
	check(same(GameState.equipment_state, expected.equipment_state), "独立冷读五件唯一实例、三预设和修订号不变")
	check(same(GameState.first_boss_choices, expected.first_boss_choices), "独立冷读不重抽三橙词条")
	check(same(GameState.equipment_drop_state, expected.equipment_drop_state), "来源、三保底与首次Boss收据冷读不变")
	check(same(GameState.pending_items, expected.pending_items), "待领取余额与来源冷读不变")
	check(same(GameState.equipment_fixed_offers, expected.equipment_fixed_offers), "制作预览跨进程不重抽")
	var pending_id := str(GameState.pending_items.keys()[0])
	GameState.remove_item("onigiri", 2)
	check(action("claim_pending", {"id": pending_id}).get("claimed", 0) == 2, "有两格只领两件")
	check(GameState.count_item("onigiri") == 99 and pending_total("onigiri") == 5, "部分领取后余额5持久保留")
	var before := GameState.pending_items.duplicate(true)
	check(not action("claim_pending", {"id": pending_id}).ok and GameState.pending_items == before, "容量为零不吞待领取")
	var first_id := str(GameState.first_boss_choices[0].id)
	check(action("first_boss_choose", {"id": first_id}).ok, "仅明确选定橙装进入背包")
	check(GameState.first_boss_choices.is_empty() and not action("first_boss_choose", {"id": first_id}).ok, "重复选择无二次发货")
	check(GameState.equipment_state.items.has(first_id), "选定实例ID保持")
	var old_id := str(GameState.equipment_state.equipped.weapon)
	check(action("unequip", {"slot": "weapon"}).ok, "显式卸下原件回包")
	check(not action("sell", {"ids": [old_id], "confirmed": true}).ok, "配置引用保护出售")
	check(not action("presets_clear_reference", {"id": old_id}).ok, "解除配置引用本身也需明确确认")
	check(action("presets_clear_reference", {"id": old_id, "confirmed": true}).ok, "明确解除所有对应引用")
	var gold_before := GameState.gold
	var item_before: Dictionary = GameState.equipment_state.items[old_id].duplicate(true)
	check(action("sell", {"ids": [old_id], "confirmed": true}).ok, "单独确认出售")
	check(GameState.gold == gold_before + 50, "售价不受贪婪或装备金币倍率放大")
	check(action("buyback", {"id": old_id}).ok, "按实收原价购回")
	check(GameState.gold == gold_before and GameState.equipment_state.items[old_id] == item_before, "购回同ID同原值且无套利")
	var candidate := "legacy:%d:pending" % GameState.world_seed
	check(action("decompose", {"ids": [candidate], "confirmed": true}).ok, "明确分解旧候选")
	check(GameState.count_item("equipment-parts") == 99 and pending_total("equipment-parts") == 2, "零件满99时蓝装分解2份全部进待领取")
	var offer: Dictionary = GameState.equipment_fixed_offers.values()[0]
	var offer_id := str(offer.item.id)
	check(action("craft", {"token": str(offer.token)}).ok, "固定成品只购买一次")
	check(GameState.equipment_state.items.has(offer_id) and GameState.count_item("equipment-parts") == 93, "扣六份现有零件，成品仍是预览同ID")
	check(not action("craft", {"token": str(offer.token)}).ok, "旧成品凭据不能再次购买")
	GameState.save_enabled = true
	check(GameState.save_now(), "领取及交易全部原子保存")

func _verify() -> void:
	check(GameState.equipment_state.items.size() == 6, "冷读后五件旧装-分解一件+橙一件+蓝一件=六件")
	check(pending_total("onigiri") == 5 and pending_total("equipment-parts") == 2, "两种待领取余额持续存在")
	check(GameState.equipment_drop_state.first_boss_status == "claimed", "首次Boss已选状态区分未选")
	check(GameState.first_boss_choices.is_empty() and GameState.equipment_fixed_offers.is_empty(), "已消费两类预览不复活")
	check(GameState.equipment_state.buyback.is_empty(), "已经购回的历史条目不重复出现")
	check(GameState.equipment_state.presets[0].slots.size() == 3, "明确解除只移去一条预设引用")

func _failure() -> void:
	var bytes := FileAccess.get_file_as_bytes(GameState.SAVE_PATH)
	var before_count := pending_total("onigiri")
	check(GameState.apply_inventory_transaction({}, {"onigiri": 3}, "failure:reward"), "故障前在内存结算一次")
	GameState.save_enabled = true
	check(not GameState.save_now(), "真实文件大小限制下写盘失败不得声称保存成功")
	check(FileAccess.get_file_as_bytes(GameState.SAVE_PATH) == bytes, "写入/flush失败保留原存档字节")
	check(pending_total("onigiri") == before_count + 3, "失败保留内存待领取便于重试")
	check(not GameState.apply_inventory_transaction({}, {"onigiri": 3}, "failure:reward"), "失败不会允许同收据在内存重付")

func _retry() -> void:
	check(pending_total("onigiri") == 5, "失败后独立冷读回到最后完整磁盘事务")
	check(GameState.apply_inventory_transaction({}, {"onigiri": 3}, "failure:reward"), "旧磁盘不存在该收据，可重新完成那一次操作")
	GameState.save_enabled = true
	check(GameState.save_now(), "恢复可写后成功保存")
	GameState._load()
	check(pending_total("onigiri") == 8 and not GameState.apply_inventory_transaction({}, {"onigiri": 3}, "failure:reward"), "成功持久收据不再重复发放")

func _future() -> void:
	var bytes := FileAccess.get_file_as_bytes(GameState.SAVE_PATH)
	check(GameState.equipment_read_only(), "未来或损坏读者格式进入只读")
	check(GameState.equipment_state.items.size() == 6, "即使格式标记损坏，仍可只读保留所有实例")
	check(not action("buyback_clear", {"confirmed": true}).ok, "未来只读禁改拥有账本")
	check(not GameState.apply_inventory_transaction({}, {"onigiri": 1}), "未来只读禁改物品交易")
	GameState.save_enabled = true
	check(not GameState.save_now() and FileAccess.get_file_as_bytes(GameState.SAVE_PATH) == bytes, "未来版本保存拒绝且完整保留未知数据")

func same(a: Variant, b: Variant) -> bool:
	if typeof(a) in [TYPE_INT, TYPE_FLOAT] and typeof(b) in [TYPE_INT, TYPE_FLOAT]: return float(a) == float(b)
	if typeof(a) != typeof(b): return false
	if a is Dictionary:
		if a.size() != b.size(): return false
		for key: Variant in a:
			if not b.has(key) or not same(a[key], b[key]): return false
		return true
	if a is Array:
		if a.size() != b.size(): return false
		for i: int in a.size():
			if not same(a[i], b[i]): return false
		return true
	return a == b
