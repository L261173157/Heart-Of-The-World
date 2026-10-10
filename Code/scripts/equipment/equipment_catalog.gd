## 装备目录与确定性预算公式真源；属性使用比例值而非百分数。
## 实例身份与位置归账本管理，生成词条不消耗全局随机数。
class_name EquipmentCatalog
extends RefCounted

const RULES_VERSION := 1
const SLOTS := ["weapon", "offhand", "helmet", "armor", "boots", "charm"]
const SLOT_NAMES := {"weapon": "武器", "offhand": "副手", "helmet": "头盔", "armor": "衣服", "boots": "鞋子", "charm": "护符"}
const RARITY_NAMES := ["普通", "精良", "稀有", "史诗", "传说"]
const BUDGETS := {"weapon": 30.0, "offhand": 14.0, "helmet": 14.0, "armor": 20.0, "boots": 10.0, "charm": 12.0}
const COSTS := {"phys": 1.0, "magic": 1.0, "mp_regen": 1.0, "heal_power": 1.0, "guard": 1.0,
	"hp": 0.5, "mp": 0.5, "gold": 0.5, "xp": 0.5, "cdr": 2.0, "block_cost": 2.0,
	"lifesteal": 4.0, "move": 1.5}
const AFFIX_NAMES := {"phys": "物攻", "atk": "物攻", "magic": "魔攻", "hp": "生命", "mp": "精力",
	"mp_regen": "精力回复", "heal_power": "治疗", "cdr": "冷却缩减", "lifesteal": "吸血", "move": "移速",
	"gold": "金币", "xp": "经验", "guard": "格挡强度", "block_cost": "挡击耗蓝降低"}
const CAPS := {"phys": 0.28, "magic": 0.28, "hp": 0.50, "mp": 0.20, "mp_regen": 0.20,
	"heal_power": 0.20, "cdr": 0.20, "lifesteal": 0.12, "move": 0.12,
	"gold": 0.40, "xp": 0.24, "guard": 0.15, "block_cost": 0.10}
const ECONOMIC_AFFIXES := ["gold", "xp"]
const LEGACY_AFFIXES := ["atk", "hp", "cdr", "lifesteal", "move", "gold", "xp"]
const ORANGE_BASES := ["physical_sword", "shield", "focus"]
const BASES := {
	"physical_sword": {"name": "行者长剑", "slot": "weapon", "main": "phys", "mechanism": "combo",
		"pool": {"phys": 3, "cdr": 2, "lifesteal": 2, "xp": 1, "gold": 1}},
	"rune_sword": {"name": "符文剑", "slot": "weapon", "main": "magic",
		"pool": {"magic": 3, "cdr": 2, "mp_regen": 2, "xp": 1, "gold": 1}},
	"shield": {"name": "守卫盾", "slot": "offhand", "main": "guard", "mechanism": "shield",
		"pool": {"guard": 3, "block_cost": 3, "hp": 2, "mp_regen": 2}},
	"focus": {"name": "聚能法器", "slot": "offhand", "main": "mp", "mechanism": "focus",
		"pool": {"magic": 3, "mp": 2, "mp_regen": 3, "cdr": 2}},
	"helmet": {"name": "旅者头盔", "slot": "helmet", "main": "hp",
		"pool": {"hp": 3, "mp": 2, "mp_regen": 2, "cdr": 2, "xp": 1}},
	"armor": {"name": "旅者护甲", "slot": "armor", "main": "hp",
		"pool": {"hp": 3, "lifesteal": 2, "mp_regen": 2, "heal_power": 2}},
	"boots": {"name": "旅者长靴", "slot": "boots", "main": "move",
		"pool": {"move": 3, "hp": 2, "mp_regen": 2, "gold": 1}},
	"physical_charm": {"name": "勇武护符", "slot": "charm", "main": "mp_regen",
		"pool": {"phys": 3, "mp_regen": 2, "cdr": 2, "heal_power": 2, "xp": 1, "gold": 1}},
	"magic_charm": {"name": "奥能护符", "slot": "charm", "main": "mp_regen",
		"pool": {"magic": 3, "mp_regen": 2, "cdr": 2, "heal_power": 2, "xp": 1, "gold": 1}},
}
const SLOT_BASES := {"weapon": ["physical_sword", "rune_sword"], "offhand": ["shield", "focus"],
	"helmet": ["helmet"], "armor": ["armor"], "boots": ["boots"], "charm": ["physical_charm", "magic_charm"]}
const TERRAIN_LEVELS := {"plains": 1, "plain": 1, "forest": 3, "hill": 7, "swamp": 5, "snow": 5, "lava": 10}


static func level_factor(item_level: int) -> float:
	return 0.6 + 0.4 * float(clampi(item_level, 1, 10) - 1) / 9.0


static func required_level(item_level: int) -> int:
	return ceili(float(clampi(item_level, 1, 10)) / 4.0)


static func item_level_for_terrain(terrain: String, elite := false, boss := false) -> int:
	return clampi(int(TERRAIN_LEVELS.get(terrain, 1)) + (2 if boss else (1 if elite else 0)), 1, 10)


static func generate(seed_value: int, item_level: int, rarity: int, slot_or_base := "weapon") -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var base_id := slot_or_base
	var quality := clampi(rarity, 0, 4)
	if SLOT_BASES.has(base_id):
		var choices: Array = SLOT_BASES[base_id].duplicate()
		if quality == 4:
			var orange_choices: Array = []
			for candidate: String in choices:
				if candidate in ORANGE_BASES:
					orange_choices.append(candidate)
			if not orange_choices.is_empty():
				choices = orange_choices
		base_id = str(choices[rng.randi_range(0, choices.size() - 1)])
	if not BASES.has(base_id):
		return {}
	if quality == 4 and base_id not in ORANGE_BASES:
		quality = 3
	var base: Dictionary = BASES[base_id]
	var ilvl := clampi(item_level, 1, 10)
	var budget := float(BUDGETS[base["slot"]]) * level_factor(ilvl)
	var main_id := str(base["main"])
	var fixed := {main_id: 0.6 * budget / float(COSTS[main_id]) / 100.0}
	var affixes := fixed.duplicate(true)
	var count: int = [0, 1, 2, 3, 2][quality]
	var share: float = [0.0, 0.2, 0.16, 0.4 / 3.0, 0.1][quality]
	var pool: Dictionary = base["pool"].duplicate(true)
	var rolls: Array[Dictionary] = []
	for unused: int in count:
		var affix := _weighted_pick(pool, rng)
		if affix.is_empty():
			break
		var roll := rng.randf_range(0.85, 1.0)
		var value := share * budget * roll / float(COSTS[affix]) / 100.0
		rolls.append({"id": affix, "value": value, "roll": roll, "budget": share * budget})
		affixes[affix] = float(affixes.get(affix, 0.0)) + value
		pool.erase(affix)
		if affix in ECONOMIC_AFFIXES:
			for economic: String in ECONOMIC_AFFIXES:
				pool.erase(economic)
	var item := {"rules_version": RULES_VERSION, "base_id": base_id, "slot": str(base["slot"]),
		"name": str(base["name"]), "rarity": quality, "item_level": ilvl, "required_level": required_level(ilvl),
		"affixes": affixes, "fixed_affixes": fixed, "affix_rolls": rolls, "seed": seed_value,
		"favorite": false, "locked": false, "acquired_seq": 0, "legacy": false, "mechanism": ""}
	if quality == 4:
		item["mechanism"] = str(base.get("mechanism", ""))
	# 新制预算不额外掷免费元素；已有火/冰物品与战斗效果由读取/计算路径保留。
	return item


static func _weighted_pick(pool: Dictionary, rng: RandomNumberGenerator) -> String:
	var total := 0
	for weight: Variant in pool.values():
		total += int(weight)
	if total <= 0:
		return ""
	var choice := rng.randi_range(1, total)
	for id: String in pool:
		choice -= int(pool[id])
		if choice <= 0:
			return id
	return ""


static func mint_item(item: Dictionary, id: String) -> Dictionary:
	var clean := sanitize_item(item)
	if clean.is_empty() or id.is_empty():
		return {}
	clean["id"] = id
	return clean


static func legacy_item(raw: Dictionary, id: String, slot: String) -> Dictionary:
	var item := raw.duplicate(true)
	item["slot"] = slot
	item["legacy"] = true
	item["rules_version"] = 0
	item["id"] = id
	item["required_level"] = 1
	return sanitize_item(item)


## 保留身份、已生成词条及未知字段；未知基底隔离而不删除。
## 旧制词条原值保留，旧存档的安全边界只在实际计算属性时应用。
static func sanitize_item(raw: Variant) -> Dictionary:
	if not raw is Dictionary or raw.is_empty():
		return {}
	var item: Dictionary = raw.duplicate(true)
	var slot := str(raw.get("slot", ""))
	item["slot"] = slot
	item["id"] = str(raw.get("id", ""))
	item["name"] = str(raw.get("name", "未知装备")).left(120)
	item["legacy"] = _safe_bool(raw.get("legacy"), not raw.has("base_id"))
	item["rules_version"] = 0 if bool(item["legacy"]) else _safe_int(raw.get("rules_version", RULES_VERSION), RULES_VERSION)
	item["rarity"] = clampi(_safe_int(raw.get("rarity", 0), 0), 0, 3 if bool(item["legacy"]) else 4)
	item["item_level"] = clampi(_safe_int(raw.get("item_level", 1), 1), 1, 10)
	item["required_level"] = 1 if bool(item["legacy"]) else required_level(int(item["item_level"]))
	item["favorite"] = _safe_bool(raw.get("favorite"), false)
	item["locked"] = _safe_bool(raw.get("locked"), false)
	item["acquired_seq"] = maxi(0, _safe_int(raw.get("acquired_seq", 0), 0))
	item["affixes"] = {}
	var affixes: Variant = raw.get("affixes", {})
	if affixes is Dictionary:
		for key: Variant in affixes:
			if key is String and typeof(affixes[key]) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(affixes[key])):
				item["affixes"][key] = maxf(0.0, float(affixes[key]))
	if raw.has("fixed_affixes"):
		item["fixed_affixes"] = {}
		var fixed: Variant = raw["fixed_affixes"]
		var invalid_fixed := not fixed is Dictionary
		if fixed is Dictionary:
			for key: Variant in fixed:
				if key is String and typeof(fixed[key]) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(fixed[key])):
					item["fixed_affixes"][key] = maxf(0.0, float(fixed[key]))
				else: invalid_fixed = true
		if invalid_fixed: item["raw_fixed_affixes"] = fixed.duplicate(true) if fixed is Dictionary or fixed is Array else fixed
	item["mechanism"] = ""
	item["quarantined"] = _safe_bool(raw.get("quarantined"), false) or slot not in SLOTS
	if not bool(item["legacy"]):
		var base_id := str(raw.get("base_id", ""))
		item["base_id"] = base_id
		if not BASES.has(base_id) or int(item["rules_version"]) != RULES_VERSION:
			item["quarantined"] = true
		elif str(BASES[base_id]["slot"]) != slot:
			item["quarantined"] = true
		elif int(item["rarity"]) == 4 and base_id in ORANGE_BASES:
			item["mechanism"] = str(BASES[base_id].get("mechanism", ""))
		elif int(item["rarity"]) == 4:
			item["quarantined"] = true
		# 新掉落策略在生成时决定；已有合法附魔必须完整保留。
		if str(raw.get("element", "")) not in ["fire", "ice"] or slot != "weapon":
			item.erase("element")
	else:
		var element := str(raw.get("element", ""))
		if element not in ["fire", "ice"]:
			item.erase("element")
	return item


static func sale_value(item: Dictionary) -> int:
	return 20 + clampi(_safe_int(item.get("rarity", 0), 0), 0, 4) * 10


static func decompose_value(item: Dictionary) -> int:
	return [1, 1, 2, 3, 3][clampi(_safe_int(item.get("rarity", 0), 0), 0, 4)]


static func purchase_cost(item: Dictionary) -> int:
	return 30 + 2 * clampi(_safe_int(item.get("item_level", 1), 1), 1, 10)


static func craft_cost(item: Dictionary) -> Dictionary:
	return {"gold": 20 + 4 * clampi(_safe_int(item.get("item_level", 1), 1), 1, 10), "parts": 6}


static func item_description(item: Dictionary) -> String:
	if item.is_empty():
		return "空"
	var parts: Array[String] = []
	var affixes: Variant = item.get("affixes", {})
	if affixes is Dictionary:
		for id: Variant in affixes:
			if typeof(affixes[id]) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(affixes[id])):
				parts.append("%s +%.2f%%" % [AFFIX_NAMES.get(id, id), float(affixes[id]) * 100.0])
	var element := str(item.get("element", ""))
	if element in ["fire", "ice"]:
		parts.append("火附魔" if element == "fire" else "冰附魔")
	var mechanism := str(item.get("mechanism", ""))
	if not mechanism.is_empty():
		parts.append(mechanism_description(item))
	var label := "旧制" if bool(item.get("legacy", not item.has("base_id"))) else "iLv%d · 需要Lv%d" % [int(item.get("item_level", 1)), int(item.get("required_level", 1))]
	return "%s·%s（%s）\n%s" % [RARITY_NAMES[clampi(int(item.get("rarity", 0)), 0, 4)], str(item.get("name", "未知装备")), label, " / ".join(parts)]


static func mechanism_description(item: Dictionary) -> String:
	var factor := level_factor(int(item.get("item_level", 1)))
	match str(item.get("mechanism", "")):
		"combo":
			return "连击第三击基础回复%.2f%%最大生命（随普攻节奏折算；2秒间隔）；重击伤害−10%%" % factor
		"shield":
			return "满蓄反击倍率%.2f；持续举盾每秒耗5精力" % (2.2 + 0.2 * factor)
		"focus":
			return "主法弹有效命中返还至多%.2f精力（1.6秒间隔）；主法弹伤害−5%%" % factor
	return ""


static func _safe_int(value: Variant, fallback: int) -> int:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
		return fallback
	return int(value)


static func _safe_bool(value: Variant, fallback: bool) -> bool:
	return value if value is bool else fallback
