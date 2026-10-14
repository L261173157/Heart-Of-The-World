## 历史收据编码缓存契约：内容/顺序/防重不变，新增与公共替换路径不复用旧字节。
extends SceneTree

const Drops := preload("res://scripts/equipment/equipment_drops.gd")
const Encoding := preload("res://scripts/equipment/equipment_receipt_encoding.gd")
var failures := 0
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	print("  %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok: failures += 1

func same(encoded: PackedByteArray, state: Dictionary) -> bool:
	return JSON.stringify(JSON.parse_string(encoded.get_string_from_utf8()), "", true) == JSON.stringify(JSON.parse_string(JSON.stringify(state)), "", true)

func settle(state: Dictionary, id: int, kind := "ordinary") -> Dictionary:
	var source := Drops.create_source(20260908, kind, id, 0, "plains")
	Drops.begin_combat(state, source, {}, "weapon")
	source["player_kill"] = true
	return Drops.settle(state, source)

func _initialize() -> void:
	var minimal_encoding := Encoding.new()
	check(same(minimal_encoding.encode({}), {"receipts": {}}), "空字典规范化为空收据对象且 JSON 完整")
	check(same(minimal_encoding.encode({"receipts": {}}), {"receipts": {}}), "只有空收据成员时没有前导逗号")
	var minimal := {"receipts": {"来源": {"items": [], "text": "中文\\引号\""}}}
	check(same(minimal_encoding.encode(minimal), minimal), "只有非空收据成员时完整保留内容")
	check(same(minimal_encoding.encode(minimal), minimal), "最小账本重复保存仍为完整 JSON")
	check(same(minimal_encoding.encode({"ordinary_failures": 2}), {"ordinary_failures": 2, "receipts": {}}), "仅元数据时补空收据且分隔正确")
	var state := Drops.empty_state()
	for id in range(1, 1001): settle(state, id)
	var first := settle(state, 1001, "boss")
	var source := Drops.create_source(20260908, "elite", 2000, 0, "forest")
	Drops.begin_combat(state, source, {}, "boots")
	var encoding := Encoding.new()
	check(same(encoding.encode(state), state), "1000真实击杀+未选首奖+尚未结算来源完整编码")
	var count: int = encoding.encoded_receipts
	check(same(encoding.encode(state), state) and encoding.encoded_receipts == count, "不变收据不重新编码")
	var stored: Dictionary = state.receipts[first.source_id]
	check(stored.is_read_only() and stored.first_boss_choices.is_read_only() and stored.first_boss_choices[0].is_read_only(), "收据及深层载荷递归只读")
	check(not first.is_read_only(), "调用方返回副本仍可消费")
	first.first_boss_choices.clear()
	check(stored.first_boss_choices.size() == 3, "消费返回副本不影响持久首奖载荷")
	settle(state, 2_000_001)
	check(same(encoding.encode(state), state) and encoding.encoded_receipts == count + 1, "字典排序中途插入只编码新增收据")
	state.ordinary_failures = 24
	state.first_boss_status = "claimed"
	state.sources[source.source_id].preferred_slot = "helmet"
	check(same(encoding.encode(state), state), "保底/首奖状态/未结算来源改动每次读取")
	var keys: Array = state.receipts.keys()
	var key: String = keys[0]
	var mutable: Dictionary = state.receipts[key].duplicate(true)
	mutable.rarity = 3
	state.receipts[key] = mutable
	check(same(encoding.encode(state), state), "同数量条目替换不使用旧编码")
	mutable.items.append({"text": "引号\"\\中文🌲"})
	check(same(encoding.encode(state), state), "可变条目深层原地修改不缓存")
	var outer_only := {"source_id": key, "items": [{"text": "旧值"}]}
	outer_only.make_read_only()
	state.receipts[key] = outer_only
	check(same(encoding.encode(state), state), "只有顶层只读的外部收据可以编码")
	outer_only.items[0].text = "新值"
	check(same(encoding.encode(state), state), "顶层只读但深层可变的收据不能复用旧字节")
	var cold := Drops.sanitize_state(JSON.parse_string(JSON.stringify(state)))
	check(same(encoding.encode(cold), cold), "更换同大小账本对象清除旧缓存")
	var replay := Drops.create_source(20260908, "boss", 1001, 0, "plains")
	replay.player_kill = true
	var repeated := Drops.settle(cold, replay)
	check(repeated.duplicate and repeated.first_boss_choices.size() == 3 and cold.first_boss_status == "claimed", "编码后冷恢复仍拒绝重奖并保留原首奖载荷")
	cold.receipts.erase(key)
	check(same(encoding.encode(cold), cold) and not encoding._entries.has(key), "删除来源不保留旧缓存引用")
	cold.receipts.clear()
	check(same(encoding.encode(cold), cold) and encoding._entries.is_empty(), "清空账本不残留旧世界载荷")
	print("=== EQUIPMENT RECEIPT ENCODING %s (%d checks) ===" % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)
