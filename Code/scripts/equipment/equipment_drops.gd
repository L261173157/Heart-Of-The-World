## 装备掉落的来源账本：纯数据、独立随机流，与战斗/生态的全局 RNG 隔离。
## 调用方须先验证真实活体/玩家击杀，并在同一世界奖励事务中保存生态与本账本。
class_name EquipmentDrops
extends RefCounted

const Catalog := preload("res://scripts/equipment/equipment_catalog.gd")
const GENERATOR_VERSION := 1
const STATE_VERSION := 1
const KINDS := ["ordinary", "elite", "boss"]
const SLOTS := ["weapon", "offhand", "helmet", "armor", "boots", "charm"]
const TERRAIN_LEVELS := {"plains": 1, "forest": 3, "snow": 5, "swamp": 5, "hill": 7, "lava": 10}
const FIRST_BOSS_BASES := ["physical_sword", "shield", "focus"]


static func empty_state() -> Dictionary:
	return {"version": STATE_VERSION, "ordinary_failures": 0, "elite_failures": 0,
		"boss_orange_failures": 0, "first_boss_consumed": false, "first_boss_status": "eligible",
		"sources": {}, "receipts": {}}


## 品质先确定，再选择合法槽位；不因副手有两种底材而多占一个槽位权重。
static func legal_slots(rarity: int) -> Array:
	return ["weapon", "offhand"] if rarity == 4 else SLOTS.duplicate()


static func source_level(terrain: String, kind: String) -> int:
	return mini(10, int(TERRAIN_LEVELS.get(terrain, 1)) + (2 if kind == "boss" else 1 if kind == "elite" else 0))


static func create_source(world_seed: int, kind: String, instance_id: int,
		ordinal: int, terrain: String, metadata: Dictionary = {}) -> Dictionary:
	if kind not in KINDS or instance_id <= 0 or ordinal < 0 or not TERRAIN_LEVELS.has(terrain):
		return {}
	var source := {"world_seed": world_seed, "kind": kind, "instance_id": instance_id,
		"ordinal": ordinal, "generator_version": GENERATOR_VERSION, "terrain": terrain,
		"ilvl": source_level(terrain, kind), "generation": maxi(0, _integer(metadata.get("generation", 0))),
		"splits_on_death": _true(metadata.get("splits_on_death", false))}
	source["source_id"] = source_id(source)
	return source


static func source_id(source: Dictionary) -> String:
	return "equipment:%d:%s:%d:%d:v%d" % [_integer(source.get("world_seed", 0)),
		str(source.get("kind", "")), _integer(source.get("instance_id", 0)),
		_integer(source.get("ordinal", 0)), _integer(source.get("generator_version", 0))]


## SHA256 前 52 位作稳定整数种子，JSON 的双精度载入也可无损保存。
## 不依赖语言 hash 算法、节点 ID 或当前时间。
static func seed_for(source: Dictionary, stream: String) -> int:
	return (source_id(source) + "|" + stream).sha256_text().substr(0, 13).hex_to_int()


static func _rng(source: Dictionary, stream: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_for(source, stream)
	return rng


## 首次有效战斗锁定缺槽及偏好。之后的 UI 改动、卸载重生、读档均不能重选。
static func begin_combat(state: Dictionary, source: Dictionary,
		equipped: Dictionary, preferred_slot: String) -> Dictionary:
	if not _valid_source(source):
		return {}
	_ensure_state(state)
	var key: String = source["source_id"]
	if state["sources"].has(key):
		return state["sources"][key].duplicate(true)
	if state["receipts"].has(key):
		return {}
	var locked := source.duplicate(true)
	locked.erase("player_kill")
	locked.erase("actor_instance_id")
	locked.erase("player_instance_id")
	locked["preferred_slot"] = preferred_slot if preferred_slot in SLOTS else ""
	var empties: Array = []
	for slot: String in SLOTS:
		var item: Variant = equipped.get(slot, {})
		if item == null or (item is Dictionary and item.is_empty()) or (item is String and item.is_empty()):
			empties.append(slot)
	locked["empty_slots"] = empties
	state["sources"][key] = locked
	return locked.duplicate(true)


## 返回保存过的完整收据；duplicate 时调用者不可再次入包或生成选择资格。
static func settle(state: Dictionary, source: Dictionary) -> Dictionary:
	if not _valid_source(source) or not _true(source.get("player_kill", false)):
		return {}
	_ensure_state(state)
	var key: String = source["source_id"]
	if state["receipts"].has(key):
		var previous: Dictionary = state["receipts"][key].duplicate(true)
		previous["duplicate"] = true
		return previous
	if not state["sources"].has(key):
		return {}
	var locked: Dictionary = state["sources"][key]
	# 同 ID 的地形/世代参数不能在首次交战之后偷偷替换。
	if not _same_source(locked, source):
		return {}
	var receipt := {"source_id": key, "duplicate": false, "kind": locked["kind"],
		"ilvl": locked["ilvl"], "items": [], "first_boss_choices": [], "rarity": -1,
		"pity_forced": false, "first_boss": false}
	if locked["kind"] == "boss" and not state["first_boss_consumed"] and state["first_boss_status"] == "eligible":
		state["first_boss_consumed"] = true
		state["first_boss_status"] = "pending"
		state["boss_orange_failures"] = 0
		receipt["rarity"] = 4
		receipt["first_boss"] = true
		for base: String in FIRST_BOSS_BASES:
			receipt["first_boss_choices"].append(_make_item(locked, 4, base, "first_boss:" + base))
	else:
		var rolled := roll_rarity(locked, state)
		var rarity: int = rolled["rarity"]
		receipt["rarity"] = rarity
		receipt["pity_forced"] = rolled["pity_forced"]
		_advance_pity(state, locked["kind"], rarity)
		if rarity >= 1:
			var slot := select_slot(locked, rarity)
			receipt["items"].append(_make_item(locked, rarity, slot, "item"))
	state["receipts"][key] = receipt.duplicate(true)
	# 已结算来源由收据代替，不让交战快照无限重复占用存档。
	state["sources"].erase(key)
	return receipt


## 只抽品质，便于精确检验基础概率与保底边界；不改动计数器。
static func roll_rarity(source: Dictionary, state: Dictionary) -> Dictionary:
	var rng := _rng(source, "rarity")
	var kind: String = source.get("kind", "ordinary")
	var forced := false
	var rarity := -1
	if kind == "ordinary":
		forced = _integer(state.get("ordinary_failures", 0)) >= 24
		var roll := rng.randi_range(0, 7 if forced else 99)
		rarity = (1 if roll < 7 else 2) if forced else (-1 if roll < 92 else 1 if roll < 99 else 2)
	elif kind == "elite":
		forced = _integer(state.get("elite_failures", 0)) >= 4
		var roll := rng.randi_range(0, 4 if forced else 99)
		rarity = (2 if roll < 4 else 3) if forced else (-1 if roll < 55 else 2 if roll < 91 else 3)
	elif kind == "boss":
		forced = _integer(state.get("boss_orange_failures", 0)) >= 7
		rarity = 4 if forced or rng.randi_range(0, 99) >= 90 else 3
	return {"rarity": rarity, "pity_forced": forced}


static func _advance_pity(state: Dictionary, kind: String, rarity: int) -> void:
	if kind == "ordinary":
		state["ordinary_failures"] = 0 if rarity >= 1 else mini(24, int(state["ordinary_failures"]) + 1)
	elif kind == "elite":
		state["elite_failures"] = 0 if rarity >= 1 else mini(4, int(state["elite_failures"]) + 1)
	elif kind == "boss":
		state["boss_orange_failures"] = 0 if rarity == 4 else mini(7, int(state["boss_orange_failures"]) + 1)


static func select_slot(locked: Dictionary, rarity: int) -> String:
	var legal := legal_slots(rarity)
	var rng := _rng(locked, "slot")
	var empties: Array = []
	for slot: String in locked.get("empty_slots", []):
		if slot in legal and slot not in empties:
			empties.append(slot)
	if not empties.is_empty():
		return empties[rng.randi_range(0, empties.size() - 1)]
	var preferred: String = locked.get("preferred_slot", "")
	if preferred in legal:
		if rng.randi_range(0, 1) == 0:
			return preferred
		legal.erase(preferred)
	return legal[rng.randi_range(0, legal.size() - 1)]


static func _make_item(source: Dictionary, rarity: int, slot_or_base: String, stream: String) -> Dictionary:
	var item: Dictionary = Catalog.generate(seed_for(source, stream), int(source["ilvl"]), rarity, slot_or_base)
	item["source_id"] = source["source_id"]
	item["source_kind"] = source["kind"]
	# 创建时即规范成存档的数值精度，首屏比较与重载后的预生成候选完全相同。
	var canonical: Dictionary = JSON.parse_string(JSON.stringify(item))
	canonical["seed"] = seed_for(source, stream)
	return Catalog.mint_item(canonical, "gear:" + (source_id(source) + "|" + stream).sha256_text().substr(0, 32))


static func _same_source(a: Dictionary, b: Dictionary) -> bool:
	for field: String in ["source_id", "world_seed", "kind", "instance_id", "ordinal", "generator_version",
			"terrain", "ilvl", "generation", "splits_on_death"]:
		if a.get(field) != b.get(field):
			return false
	return true


static func _valid_source(source: Dictionary) -> bool:
	return source.get("kind", "") in KINDS and _integer(source.get("instance_id", 0)) > 0 \
		and _integer(source.get("ordinal", -1), -1) >= 0 \
		and _integer(source.get("generator_version", 0)) == GENERATOR_VERSION \
		and TERRAIN_LEVELS.has(source.get("terrain", "")) \
		and _integer(source.get("ilvl", 0)) == source_level(source.get("terrain", ""), source.get("kind", "")) \
		and str(source.get("source_id", "")) == source_id(source)


static func _ensure_state(state: Dictionary) -> void:
	for key: String in empty_state():
		if not state.has(key):
			state[key] = empty_state()[key]


static func _integer(value: Variant, fallback := 0) -> int:
	if typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)):
		return int(value)
	return fallback


static func _true(value: Variant) -> bool:
	return typeof(value) == TYPE_BOOL and value


## 仅接纳可验证的来源与已生成收据；损坏项逐项隔离，不重掷、不补造历史首奖。
static func sanitize_state(raw: Variant) -> Dictionary:
	var clean := empty_state()
	if not raw is Dictionary:
		return clean
	clean["ordinary_failures"] = clampi(_integer(raw.get("ordinary_failures", 0)), 0, 24)
	clean["elite_failures"] = clampi(_integer(raw.get("elite_failures", 0)), 0, 4)
	clean["boss_orange_failures"] = clampi(_integer(raw.get("boss_orange_failures", 0)), 0, 7)
	clean["first_boss_consumed"] = typeof(raw.get("first_boss_consumed")) == TYPE_BOOL and raw["first_boss_consumed"]
	clean["first_boss_status"] = ("pending" if str(raw.get("first_boss_status", "")) == "pending" else "claimed") \
		if clean["first_boss_consumed"] else "eligible"
	var sources: Variant = raw.get("sources", {})
	if sources is Dictionary:
		for key: Variant in sources:
			var source: Variant = sources[key]
			if not key is String or not source is Dictionary or not _valid_source(source) \
					or str(source.get("source_id", "")) != key:
				continue
			var locked := create_source(_integer(source["world_seed"]), source["kind"],
				_integer(source["instance_id"]), _integer(source["ordinal"]), source["terrain"], source)
			locked["preferred_slot"] = source.get("preferred_slot", "") if source.get("preferred_slot", "") in SLOTS else ""
			locked["empty_slots"] = []
			if source.get("empty_slots", []) is Array:
				for slot: Variant in source["empty_slots"]:
					if slot is String and slot in SLOTS and slot not in locked["empty_slots"]:
						locked["empty_slots"].append(slot)
			clean["sources"][key] = locked
	var receipts: Variant = raw.get("receipts", {})
	if receipts is Dictionary:
		for key: Variant in receipts:
			var receipt: Variant = receipts[key]
			if not key is String or not key.begins_with("equipment:") or not receipt is Dictionary \
					or str(receipt.get("source_id", "")) != key:
				continue
			# 即使某个装备载荷坏掉也保留“已领取”证据，避免重新开奖。
			var kept := {"source_id": key, "duplicate": false, "kind": str(receipt.get("kind", "")),
				"ilvl": clampi(_integer(receipt.get("ilvl", 1)), 1, 10),
				"rarity": clampi(_integer(receipt.get("rarity", -1), -1), -1, 4),
				"pity_forced": _true(receipt.get("pity_forced", false)),
				"first_boss": _true(receipt.get("first_boss", false)), "items": [], "first_boss_choices": []}
			for list_key: String in ["items", "first_boss_choices"]:
				var items: Variant = receipt.get(list_key, [])
				if items is Array:
					for item: Variant in items:
						if item is Dictionary and kept[list_key].size() < (3 if list_key == "first_boss_choices" else 1):
							var safe_item: Dictionary = Catalog.sanitize_item(item)
							if not safe_item.is_empty():
								safe_item["seed"] = _integer(safe_item.get("seed", 0))
								safe_item["source_id"] = key
								safe_item["source_kind"] = kept["kind"]
								kept[list_key].append(safe_item)
			if kept["first_boss"] or not kept["first_boss_choices"].is_empty():
				kept["first_boss"] = true
				clean["first_boss_consumed"] = true
				if clean["first_boss_status"] not in ["pending", "claimed"]:
					clean["first_boss_status"] = "pending"
			clean["receipts"][key] = kept
			clean["sources"].erase(key)
	return clean
