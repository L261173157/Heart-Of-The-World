## 装备账本采用纯逻辑的写时复制事务：提交成功后，调用方一次公布
## 装备、钱包与材料的新状态；此层不依赖场景节点、全局变量或信号。
class_name EquipmentInventory
extends RefCounted

const Catalog = preload("res://scripts/equipment/equipment_catalog.gd")
const PAGE_SIZE := 24
const PARTS_ID := "equipment-parts"


static func empty_state() -> Dictionary:
	return {"items": {}, "equipped": {}, "presets": [
		{"name": "配置一", "slots": {}}, {"name": "配置二", "slots": {}},
		{"name": "配置三", "slots": {}}], "buyback": [], "next_id": 1,
		"revision": 0, "craft_nonce": 0}


static func sanitize_state(value: Variant) -> Dictionary:
	var state := empty_state()
	if not value is Dictionary:
		return state
	state["revision"] = _integer(value.get("revision", 0), 0)
	state["next_id"] = maxi(1, _integer(value.get("next_id", 1), 1))
	state["craft_nonce"] = _integer(value.get("craft_nonce", 0), 0)
	var raw_items: Variant = value.get("items", {})
	if raw_items is Dictionary:
		for key: Variant in raw_items:
			if not key is String or str(key).is_empty() or not raw_items[key] is Dictionary:
				continue
			var item: Dictionary = Catalog.sanitize_item(raw_items[key])
			if item.is_empty():
				continue
			item["id"] = str(key)
			state["items"][key] = item
			state["next_id"] = maxi(int(state["next_id"]), int(item.get("acquired_seq", 0)) + 1)
	var worn: Variant = value.get("equipped", {})
	if worn is Dictionary:
		for slot: String in Catalog.SLOTS:
			var id := str(worn.get(slot, ""))
			if state["items"].has(id) and str(state["items"][id].get("slot", "")) == slot:
				state["equipped"][slot] = id
	var presets: Variant = value.get("presets", [])
	if presets is Array:
		for index: int in mini(3, presets.size()):
			if not presets[index] is Dictionary:
				continue
			state["presets"][index]["name"] = str(presets[index].get("name", state["presets"][index]["name"])).left(40)
			var slots: Variant = presets[index].get("slots", {})
			if not slots is Dictionary:
				continue
			for slot: String in Catalog.SLOTS:
				# 缺失引用仍保留供玩家处理，不能悄悄换成另一件装备。
				if slots.get(slot, "") is String and not str(slots.get(slot, "")).is_empty():
					state["presets"][index]["slots"][slot] = slots[slot]
	var buyback: Variant = value.get("buyback", [])
	if buyback is Array:
		var seen := {}
		for entry: Variant in buyback:
			if not entry is Dictionary or not entry.get("item") is Dictionary:
				continue
			var item: Dictionary = Catalog.sanitize_item(entry["item"])
			var id := str(item.get("id", ""))
			if id.is_empty() or seen.has(id) or state["items"].has(id):
				continue
			seen[id] = true
			state["next_id"] = maxi(int(state["next_id"]), int(item.get("acquired_seq", 0)) + 1)
			state["buyback"].append({"item": item, "price": _integer(entry.get("price", 0), 0)})
	return state


static func equipped_items(state: Dictionary) -> Dictionary:
	var result := {}
	for slot: String in Catalog.SLOTS:
		var id := str(state.get("equipped", {}).get(slot, ""))
		if state.get("items", {}).has(id):
			result[slot] = state["items"][id].duplicate(true)
	return result


static func add_item(state: Dictionary, item: Dictionary) -> Dictionary:
	var clean: Dictionary = Catalog.sanitize_item(item)
	if clean.is_empty():
		return _failure("invalid_item")
	var after := state.duplicate(true)
	var id := str(clean.get("id", ""))
	if id.is_empty():
		id = "eq_%010d" % int(after.get("next_id", 1))
		while _id_exists(after, id):
			after["next_id"] = int(after.get("next_id", 1)) + 1
			id = "eq_%010d" % int(after["next_id"])
	elif _id_exists(after, id):
		return _failure("duplicate_id")
	clean["id"] = id
	clean["acquired_seq"] = int(after.get("next_id", 1))
	after["next_id"] = int(after.get("next_id", 1)) + 1
	after["items"][id] = clean
	after["revision"] = int(after.get("revision", 0)) + 1
	return {"ok": true, "state": after, "id": id, "item": clean.duplicate(true)}


## 页码从零开始；持久账本不设容量，但每页场景节点有固定上限。
static func query(state: Dictionary, filters: Dictionary = {}, page := 0, page_size := PAGE_SIZE) -> Dictionary:
	var rows: Array[Dictionary] = []
	var source := str(filters.get("source", "bag"))
	if source == "buyback":
		var order: int = state.get("buyback", []).size()
		for entry: Dictionary in state.get("buyback", []):
			var item: Dictionary = entry["item"].duplicate(true)
			item["buyback_order"] = order
			order -= 1
			item["buyback_price"] = int(entry["price"])
			rows.append(item)
	else:
		for id: String in state.get("items", {}):
			var item: Dictionary = state["items"][id]
			if source == "bag" and is_equipped(state, id):
				continue
			rows.append(item)
	var matches: Array[Dictionary] = []
	for item: Dictionary in rows:
		if filters.has("slot") and str(filters["slot"]) not in ["", "all", str(item.get("slot", ""))]:
			continue
		if filters.has("rarity") and int(filters["rarity"]) >= 0 and int(item.get("rarity", 0)) != int(filters["rarity"]):
			continue
		if bool(filters.get("favorite", false)) and not bool(item.get("favorite", false)):
			continue
		if bool(filters.get("locked", false)) and not bool(item.get("locked", false)):
			continue
		var affix := str(filters.get("affix", ""))
		if not affix.is_empty() and not _matches_affix(item, affix):
			continue
		var search := str(filters.get("search", "")).strip_edges().to_lower()
		if not search.is_empty() and not search in (str(item.get("name", "")) + " " + str(item.get("id", ""))).to_lower():
			continue
		var row := item.duplicate(true)
		row["sale_price"] = Catalog.sale_value(item)
		row["decompose_parts"] = Catalog.decompose_value(item)
		row["equipped"] = is_equipped(state, str(item.get("id", "")))
		row["protection_reason"] = protection_reason(state, str(item.get("id", ""))) if source != "buyback" else ""
		row["preset_references"] = preset_references(state, str(item.get("id", "")))
		matches.append(row)
	var sort_key := str(filters.get("sort", "newest"))
	matches.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		match sort_key:
			"rarity":
				if int(a.get("rarity", 0)) != int(b.get("rarity", 0)):
					return int(a.get("rarity", 0)) > int(b.get("rarity", 0))
			"level":
				if int(a.get("item_level", 1)) != int(b.get("item_level", 1)):
					return int(a.get("item_level", 1)) > int(b.get("item_level", 1))
			"name":
				if str(a.get("name", "")) != str(b.get("name", "")):
					return str(a.get("name", "")) < str(b.get("name", ""))
		var order_a := int(a.get("buyback_order", a.get("acquired_seq", 0)))
		var order_b := int(b.get("buyback_order", b.get("acquired_seq", 0)))
		if order_a != order_b:
			return order_a > order_b
		return str(a.get("id", "")) > str(b.get("id", "")))
	var size := clampi(page_size, 1, PAGE_SIZE)
	var pages := maxi(1, ceili(float(matches.size()) / float(size)))
	var current := clampi(page, 0, pages - 1)
	return {"items": matches.slice(current * size, (current + 1) * size).duplicate(true),
		"total": matches.size(), "pages": pages, "page": current, "page_size": size}


## 属性筛选读取固定与随机贡献的聚合值；与角色公式相同地映射旧制 atk。
static func _matches_affix(item: Dictionary, requested: String) -> bool:
	var canonical := "phys" if requested == "atk" else requested
	if not Catalog.CAPS.has(canonical):
		return false
	var affixes: Variant = item.get("affixes", {})
	if not affixes is Dictionary:
		return false
	var legacy := bool(item.get("legacy", not item.has("base_id")))
	var key := "atk" if legacy and canonical == "phys" else canonical
	if legacy and key not in Catalog.LEGACY_AFFIXES:
		return false
	var value: Variant = affixes.get(key, 0.0)
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) > 0.0


static func is_equipped(state: Dictionary, id: String) -> bool:
	return id in state.get("equipped", {}).values()


static func preset_references(state: Dictionary, id: String) -> Array[int]:
	var result: Array[int] = []
	for index: int in state.get("presets", []).size():
		if id in state["presets"][index].get("slots", {}).values():
			result.append(index)
	return result


static func protection_reason(state: Dictionary, id: String) -> String:
	if not state.get("items", {}).has(id):
		return "missing_item"
	if is_equipped(state, id):
		return "equipped"
	var item: Dictionary = state["items"][id]
	if bool(item.get("quarantined", false)):
		return "quarantined"
	if bool(item.get("locked", false)):
		return "locked"
	if bool(item.get("favorite", false)):
		return "favorite"
	if not preset_references(state, id).is_empty():
		return "preset_reference"
	return ""


## 预览携带修订号和玩家看到的完整交易输入。
## 提交时重新核对整笔计划，钱包、成品或等级已变时拒绝旧预览。
static func preview(state: Dictionary, action: String, args: Dictionary = {}, context: Dictionary = {}) -> Dictionary:
	var planned := _plan(state, action, args, context)
	if not bool(planned.get("ok", false)):
		return planned
	planned["revision"] = int(state.get("revision", 0))
	planned["action"] = action
	planned["args"] = args.duplicate(true)
	planned["gold_before"] = _integer(context.get("gold", 0), 0)
	planned["materials_before"] = _materials(context)
	return planned


static func commit(state: Dictionary, offer: Dictionary, context: Dictionary = {}) -> Dictionary:
	if not bool(offer.get("ok", false)) or not offer.get("args") is Dictionary:
		return _failure("invalid_preview")
	if int(offer.get("revision", -1)) != int(state.get("revision", 0)):
		return _failure("stale_revision")
	var action := str(offer.get("action", ""))
	var current := preview(state, action, offer["args"], context)
	if not bool(current.get("ok", false)):
		return current
	if current != offer:
		return _failure("stale_preview")
	var after := state.duplicate(true)
	var args: Dictionary = offer["args"]
	match action:
		"equip":
			var id := str(args.get("id", ""))
			after["equipped"][str(after["items"][id]["slot"])] = id
		"unequip":
			after["equipped"].erase(str(args.get("slot", "")))
		"favorite", "lock":
			after["items"][str(args["id"])]["favorite" if action == "favorite" else "locked"] = bool(args.get("value", true))
		"preset_save":
			var index := int(args["index"])
			after["presets"][index]["slots"] = after["equipped"].duplicate(true)
			if args.has("name"):
				after["presets"][index]["name"] = str(args["name"]).left(40)
		"preset_rename":
			after["presets"][int(args["index"])]["name"] = str(args.get("name", "")).left(40)
		"preset_apply":
			after["equipped"] = after["presets"][int(args["index"])]["slots"].duplicate(true)
		"preset_clear":
			after["presets"][int(args["index"])]["slots"] = {}
		"presets_clear_reference":
			for preset: Dictionary in after["presets"]:
				for slot: Variant in preset["slots"].keys():
					if str(preset["slots"][slot]) == str(args.get("id", "")):
						preset["slots"].erase(slot)
		"sell", "decompose":
			for id: String in offer["ids"]:
				if action == "sell":
					after["buyback"].push_front({"item": after["items"][id].duplicate(true),
						"price": Catalog.sale_value(after["items"][id])})
				after["items"].erase(id)
		"buyback", "buyback_discard":
			var index := int(offer["details"]["buyback_index"])
			var entry: Dictionary = after["buyback"][index]
			if action == "buyback":
				after["items"][str(entry["item"]["id"])] = entry["item"].duplicate(true)
			after["buyback"].remove_at(index)
		"buyback_clear":
			after["buyback"].clear()
		"craft", "purchase":
			var added := add_item(after, offer["details"]["item"])
			if not bool(added.get("ok", false)):
				return added
			after = added["state"]
			after["craft_nonce"] = int(after.get("craft_nonce", 0)) + 1
	# 每笔成功事务只增加一次修订号；制作内部的入库已经加过，此处统一归一。
	after["revision"] = int(state.get("revision", 0)) + 1
	var materials: Dictionary = offer["materials_before"].duplicate(true)
	for key: String in offer["materials_delta"]:
		materials[key] = int(materials.get(key, 0)) + int(offer["materials_delta"][key])
	return {"ok": true, "state": after,
		"gold": int(offer["gold_before"]) + int(offer["gold_delta"]), "materials": materials,
		"gold_delta": int(offer["gold_delta"]), "parts_delta": int(offer["materials_delta"].get(PARTS_ID, 0)),
		"materials_delta": offer["materials_delta"].duplicate(true), "details": offer["details"].duplicate(true)}


static func _plan(state: Dictionary, action: String, args: Dictionary, context: Dictionary) -> Dictionary:
	var result := {"ok": true, "gold_delta": 0, "materials_delta": {}, "details": {}}
	var items: Dictionary = state.get("items", {})
	var id := str(args.get("id", ""))
	var level := maxi(1, _integer(context.get("level", 1), 1))
	match action:
		"equip", "favorite", "lock":
			if not items.has(id):
				return _failure("missing_item")
			if action == "equip":
				if not bool(context.get("can_swap", false)):
					return _failure("unsafe_loadout")
				if not _can_wear(items[id], level):
					return _failure("requirement")
				if is_equipped(state, id):
					return _failure("already_equipped")
			result["details"]["item"] = items[id].duplicate(true)
		"unequip":
			if not bool(context.get("can_swap", false)):
				return _failure("unsafe_loadout")
			if not state.get("equipped", {}).has(str(args.get("slot", ""))):
				return _failure("empty_slot")
		"preset_save", "preset_apply", "preset_clear", "preset_rename":
			var index := _integer(args.get("index", -1), -1)
			if index < 0 or index >= 3:
				return _failure("invalid_preset")
			if action == "preset_apply":
				if not bool(context.get("can_swap", false)):
					return _failure("unsafe_loadout")
				for slot: String in state["presets"][index]["slots"]:
					var target := str(state["presets"][index]["slots"][slot])
					if not items.has(target):
						return _failure("missing_preset_item")
					if str(items[target].get("slot", "")) != slot or not _can_wear(items[target], level):
						return _failure("requirement")
				result["details"]["equipped"] = state["presets"][index]["slots"].duplicate(true)
		"presets_clear_reference":
			if id.is_empty() or preset_references(state, id).is_empty():
				return _failure("no_preset_reference")
		"sell", "decompose":
			var requested: Variant = args.get("ids", [])
			if not requested is Array or requested.is_empty():
				return _failure("empty_selection")
			var ids: Array[String] = []
			for value: Variant in requested:
				if not value is String or ids.has(value):
					return _failure("invalid_selection")
				var reason := protection_reason(state, value)
				if not reason.is_empty():
					return _failure(reason)
				ids.append(value)
				if action == "sell":
					result["gold_delta"] += Catalog.sale_value(items[value])
				else:
					result["materials_delta"][PARTS_ID] = int(result["materials_delta"].get(PARTS_ID, 0)) + Catalog.decompose_value(items[value])
			result["ids"] = ids
			result["details"]["count"] = ids.size()
		"buyback", "buyback_discard":
			var found := -1
			for index: int in state.get("buyback", []).size():
				if str(state["buyback"][index]["item"].get("id", "")) == id:
					found = index
					break
			if found < 0 or items.has(id):
				return _failure("missing_buyback")
			result["gold_delta"] = -int(state["buyback"][found]["price"]) if action == "buyback" else 0
			result["details"]["buyback_index"] = found
			result["details"]["item"] = state["buyback"][found]["item"].duplicate(true)
		"buyback_clear":
			result["details"]["count"] = state.get("buyback", []).size()
		"craft", "purchase":
			var offered: Variant = context.get("offered_item", {})
			if not offered is Dictionary or offered.is_empty():
				return _failure("missing_craft_offer")
			var item: Dictionary = Catalog.sanitize_item(offered)
			if item.is_empty() or bool(item.get("legacy", false)) or bool(item.get("quarantined", false)):
				return _failure("invalid_craft_offer")
			if not str(item.get("id", "")).is_empty() and _id_exists(state, str(item["id"])):
				return _failure("duplicate_id")
			if int(item.get("rarity", -1)) != (2 if action == "craft" else 0):
				return _failure("invalid_craft_offer")
			if action == "craft":
				var cost: Dictionary = Catalog.craft_cost(item)
				result["gold_delta"] = -int(cost["gold"])
				result["materials_delta"][PARTS_ID] = -int(cost["parts"])
			else:
				result["gold_delta"] = -Catalog.purchase_cost(item)
			result["details"]["item"] = item.duplicate(true)
		_:
			return _failure("unknown_action")
	if _integer(context.get("gold", 0), 0) + int(result["gold_delta"]) < 0:
		return _failure("insufficient_gold")
	var materials := _materials(context)
	for key: String in result["materials_delta"]:
		if int(materials.get(key, 0)) + int(result["materials_delta"][key]) < 0:
			return _failure("insufficient_materials")
	return result


static func _can_wear(item: Dictionary, level: int) -> bool:
	return str(item.get("slot", "")) in Catalog.SLOTS and not bool(item.get("quarantined", false)) \
		and int(item.get("required_level", 1)) <= level


static func _materials(context: Dictionary) -> Dictionary:
	var result := {}
	var raw: Variant = context.get("materials", {})
	if raw is Dictionary:
		for key: Variant in raw:
			if key is String:
				result[key] = _integer(raw[key], 0)
	return result


static func _id_exists(state: Dictionary, id: String) -> bool:
	if state.get("items", {}).has(id):
		return true
	for entry: Dictionary in state.get("buyback", []):
		if str(entry["item"].get("id", "")) == id:
			return true
	return false


static func _integer(value: Variant, fallback: int) -> int:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
		return fallback
	return maxi(fallback, int(value))


static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "error": reason}
