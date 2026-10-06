## Pure deterministic equipment/caps/transaction contracts. Run through run_headless.py.
extends SceneTree

const Catalog = preload("res://scripts/equipment/equipment_catalog.gd")
const Inventory = preload("res://scripts/equipment/equipment_inventory.gd")
const Stats = preload("res://scripts/character/character_stats.gd")
var assertions := 0
var failures := 0


func _init() -> void:
	_catalog()
	_stats()
	_transactions()
	_affix_filters()
	_sanitization()
	if failures == 0:
		print("EQUIPMENT DOMAIN TESTS PASSED (%d assertions)" % assertions)
	else:
		printerr("EQUIPMENT DOMAIN TESTS FAILED (%d/%d)" % [failures, assertions])
	quit(1 if failures else 0)


func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)


func near(a: float, b: float, message: String) -> void:
	check(absf(a - b) < 0.000001, message)


func _catalog() -> void:
	near(Catalog.level_factor(1), 0.6, "F low")
	near(Catalog.level_factor(10), 1.0, "F high")
	check(Catalog.required_level(1) == 1 and Catalog.required_level(4) == 1 and Catalog.required_level(5) == 2 and Catalog.required_level(10) == 3, "requirements")
	check(Catalog.item_level_for_terrain("plains") == 1 and Catalog.item_level_for_terrain("forest") == 3 and Catalog.item_level_for_terrain("snow") == 5 and Catalog.item_level_for_terrain("swamp") == 5 and Catalog.item_level_for_terrain("hill") == 7 and Catalog.item_level_for_terrain("lava", true) == 10, "terrain levels")
	check(Catalog.item_level_for_terrain("hill", true) == 8 and Catalog.item_level_for_terrain("hill", false, true) == 9, "elite and boss level")
	seed(19)
	var expected_global := randf()
	seed(19)
	Catalog.generate(22, 10, 3, "weapon")
	near(randf(), expected_global, "generation leaves global RNG untouched")
	for base: String in Catalog.BASES:
		for ilvl: int in [1, 5, 10]:
			for rarity: int in 5:
				for sample: int in 30:
					var item: Dictionary = Catalog.generate(sample, ilvl, rarity, base)
					check(item == Catalog.generate(sample, ilvl, rarity, base), "deterministic roll")
					check(not item.has("element"), "new generation adds no unbudgeted elemental roll")
					var actual: int = item["rarity"]
					check(item["affix_rolls"].size() == [0, 1, 2, 3, 2][actual], "suffix count")
					var main: String = Catalog.BASES[base]["main"]
					var budget: float = Catalog.BUDGETS[item["slot"]] * Catalog.level_factor(ilvl)
					near(float(item["fixed_affixes"][main]) * float(Catalog.COSTS[main]) * 100.0, 0.6 * budget, "fixed budget exact")
					var seen := {}
					var economic := 0
					var used := 0.6 * budget
					for affix: Dictionary in item["affix_rolls"]:
						check(not seen.has(affix["id"]), "unique suffix")
						seen[affix["id"]] = true
						check(Catalog.BASES[base]["pool"].has(affix["id"]), "legal pool")
						check(float(affix["roll"]) >= 0.85 and float(affix["roll"]) <= 1.0, "roll range")
						near(float(affix["value"]) * float(Catalog.COSTS[affix["id"]]) * 100.0, float(affix["budget"]) * float(affix["roll"]), "suffix conversion")
						used += float(affix["value"]) * float(Catalog.COSTS[affix["id"]]) * 100.0
						if affix["id"] in Catalog.ECONOMIC_AFFIXES:
							economic += 1
					check(economic <= 1, "one economic suffix")
					check(used <= budget + 0.00001, "budget not exceeded")
					check(actual != 4 or base in Catalog.ORANGE_BASES, "only three orange bases")
	for rarity: int in 5:
		var item: Dictionary = Catalog.generate(1, 10, rarity, "physical_sword")
		check(Catalog.sale_value(item) == 20 + 10 * rarity, "fixed sale economy")
		check(Catalog.decompose_value(item) == [1, 1, 2, 3, 3][rarity], "parts economy")
	for sample: int in 100:
		check(Catalog.generate(sample, 10, 4, "weapon")["base_id"] == "physical_sword", "orange slot filters base")
	check(Catalog.purchase_cost(Catalog.generate(1, 10, 0)) == 50, "white buy cost")
	check(Catalog.craft_cost(Catalog.generate(1, 10, 2)) == {"gold": 60, "parts": 6}, "blue craft cost")
	check(Catalog.generate(1, 10, 3, "no_such_base").is_empty(), "unknown generation rejected")


func _stats() -> void:
	var stats := Stats.new()
	var basic: Dictionary = stats.benefit_snapshot()
	var shield: Dictionary = Catalog.generate(222, 5, 2, "shield")
	near(float(shield["fixed_affixes"]["guard"]), 0.6 * 14.0 * (0.6 + 0.4 * 4.0 / 9.0) / 100.0, "real blue iLv5 shield primary")
	var shield_preview: Dictionary = stats.preview_equipment(shield)
	stats.equips["offhand"] = shield
	check(stats.benefit_snapshot() == shield_preview["after"], "blue shield preview equals actual guard formula")
	check(shield_preview["cap_details"].has("guard"), "shield preview includes cap detail")
	stats.equips.clear()
	var raw_old := {"name": "旧剑", "slot": "weapon", "rarity": 3, "element": "fire", "affixes": {"atk": 0.4, "hp": 0.4, "cdr": 0.3}}
	var legacy: Dictionary = Catalog.legacy_item(raw_old, "old", "weapon")
	stats.equips = {"weapon": legacy}
	near(stats.equip_affix("phys"), 0.4, "legacy over cap preserved")
	near(stats.equip_affix("atk"), 0.4, "old atk alias")
	near(stats.magic_attack(), float(basic["magic"]), "legacy attack never magic")
	check(stats.equip_element() == "fire", "legacy element preserved")
	for element: String in ["fire", "ice"]:
		var held := Catalog.generate(88, 5, 2, "physical_sword")
		held["element"] = element
		check(Catalog.sanitize_item(held).get("element", "") == element, "already held elemental payload is not deleted")
	var fresh: Dictionary = Catalog.generate(2, 10, 3, "armor")
	fresh["affixes"] = {"phys": 0.3, "hp": 0.4, "cdr": 0.2, "magic": 0.9, "mp": 0.8, "mp_regen": 0.8, "heal_power": 0.8, "guard": 0.8, "block_cost": 0.8}
	stats.equips["armor"] = fresh
	near(stats.equip_affix("phys"), 0.4, "legacy above cap blocks new")
	near(stats.equip_affix("hp"), 0.5, "new fills only remaining cap")
	near(stats.equip_affix("cdr"), 0.3, "grandfather CDR retained")
	near(stats.equip_affix("magic"), 0.28, "new magic cap")
	near(stats.max_mp(), float(basic["max_mp"]) * 1.2, "MP formula")
	near(stats.mp_regen_per_sec(), float(basic["mp_regen"]) * 1.2, "MP regen formula")
	near(stats.heal_power() * Stats.HEAL_MULT, float(basic["heal"]) * 1.2, "heal formula")
	near(stats.guard_strength(), 35.0 * 1.15, "guard cap and formula")
	near(stats.equipment_guard_hit_cost(20), Stats.guard_hit_cost(20) * 0.9, "guard impact cost cap")
	stats.equips.erase("weapon")
	near(stats.equip_affix("phys"), 0.28, "removing old piece removes grandfather exemption")
	near(stats.equip_affix("hp"), 0.4, "old values not cached")
	var before: Dictionary = stats.benefit_snapshot()
	var item: Dictionary = Catalog.generate(4, 10, 4, "physical_sword")
	var preview: Dictionary = stats.preview_equipment(item)
	check(stats.benefit_snapshot() == before, "preview never mutates live stats")
	stats.equips["weapon"] = item
	check(stats.benefit_snapshot() == preview["after"], "preview uses identical formulas")
	near(stats.equip_mechanism("combo"), 1.0, "combo F")
	near(stats.heavy_damage_mult(), 0.9, "combo tradeoff")
	near(stats.equipment_combo_heal(), stats.max_hp() * 0.01, "combo healing")
	stats.equips["offhand"] = Catalog.generate(4, 1, 4, "shield")
	near(stats.equipment_guard_counter_mult(3), 2.32, "shield max charge only")
	near(stats.equipment_guard_counter_mult(2), 1.8, "shield lower charge unchanged")
	near(stats.equipment_guard_drain_per_sec(), 5.0, "shield hold tradeoff")
	stats.equips["offhand"] = Catalog.generate(4, 10, 4, "focus")
	near(stats.equipment_focus_refund(0.4), 0.4, "refund capped at actual paid MP")
	near(stats.equipment_focus_refund(8.0), 1.0, "focus refund F")
	near(stats.equipment_bolt_damage_mult(), 0.95, "focus direct damage tradeoff")
	stats.upgrade_weapon = 2
	stats.upgrade_staff = 2
	stats.upgrade_vigor = 2
	stats.equips = {}
	near(stats.physical_attack(), float(basic["physical"]) * 1.3, "permanent phys upgrades untouched")
	near(stats.magic_attack(), float(basic["magic"]) * 1.3, "permanent magic upgrades untouched")
	near(stats.max_hp(), float(basic["max_hp"]) * 1.3, "permanent HP upgrades untouched")
	check(legacy["affixes"] == raw_old["affixes"], "legacy raw roll unchanged")


func _transactions() -> void:
	var state: Dictionary = Inventory.empty_state()
	var ctx := {"gold": 1000, "materials": {"equipment-parts": 20, "beaf": 99}, "level": 3, "can_swap": true}
	var ids: Array[String] = []
	for slot: String in Catalog.SLOTS:
		var added: Dictionary = Inventory.add_item(state, Catalog.generate(42, 10, 3, slot))
		check(bool(added["ok"]), "add every slot")
		ids.append(added["id"])
		state = added["state"]
	var unchanged := state.duplicate(true)
	var equip: Dictionary = Inventory.preview(state, "equip", {"id": ids[0]}, ctx)
	var result: Dictionary = Inventory.commit(state, equip, ctx)
	check(bool(result["ok"]) and result["state"]["equipped"]["weapon"] == ids[0], "equip ledger reference")
	check(state == unchanged, "commit copy-on-write")
	state = result["state"]
	check(not bool(Inventory.commit(state, equip, ctx)["ok"]), "double-click stale revision")
	check(Inventory.query(state)["total"] == 5 and Inventory.query(state, {"source": "all"})["total"] == 6, "bag excludes worn; all includes")
	check(not bool(Inventory.preview(state, "sell", {"ids": [ids[0]]}, ctx)["ok"]), "equipped disposal protected")
	var low := ctx.duplicate(true)
	low["level"] = 1
	check(not bool(Inventory.preview(state, "equip", {"id": ids[1]}, low)["ok"]), "level requirement")
	low = ctx.duplicate(true)
	low["can_swap"] = false
	check(not bool(Inventory.preview(state, "equip", {"id": ids[1]}, low)["ok"]), "combat swapping rejected")
	state = _apply(state, "preset_save", {"index": 0, "name": "我的配置"}, ctx)
	state = _apply(state, "unequip", {"slot": "weapon"}, ctx)
	check(Inventory.protection_reason(state, ids[0]) == "preset_reference", "preset protects unequipped piece")
	state = _apply(state, "equip", {"id": ids[1]}, ctx)
	state = _apply(state, "preset_apply", {"index": 0}, ctx)
	check(state["equipped"] == {"weapon": ids[0]}, "preset switches all six slots atomically")
	var broken := state.duplicate(true)
	broken["presets"][1]["slots"] = {"helmet": "missing", "weapon": ids[0]}
	check(not bool(Inventory.preview(broken, "preset_apply", {"index": 1}, ctx)["ok"]), "missing preset blocks complete switch")
	state = _apply(state, "favorite", {"id": ids[2], "value": true}, ctx)
	check(not bool(Inventory.preview(state, "sell", {"ids": [ids[2], ids[3]]}, ctx)["ok"]), "bulk operation all-or-nothing")
	state = _apply(state, "favorite", {"id": ids[2], "value": false}, ctx)
	state = _apply(state, "lock", {"id": ids[2], "value": true}, ctx)
	check(Inventory.protection_reason(state, ids[2]) == "locked", "locked protected")
	state = _apply(state, "lock", {"id": ids[2], "value": false}, ctx)
	var sale: Dictionary = Inventory.preview(state, "sell", {"ids": [ids[2], ids[3]]}, ctx)
	check(sale["gold_delta"] == 100, "sale exact base currency")
	result = Inventory.commit(state, sale, ctx)
	check(bool(result["ok"]) and result["gold"] == 1100 and result["state"]["buyback"].size() == 2, "atomic sale and wallet")
	state = result["state"]
	ctx["gold"] = result["gold"]
	var buy: Dictionary = Inventory.preview(state, "buyback", {"id": ids[2]}, ctx)
	check(buy["gold_delta"] == -50, "buyback original sale price")
	result = Inventory.commit(state, buy, ctx)
	state = result["state"]
	ctx["gold"] = result["gold"]
	check(state["items"].has(ids[2]) and state["buyback"].size() == 1, "buyback retains exact original ID")
	check(not bool(Inventory.preview(state, "sell", {"ids": [ids[2], ids[2]]}, ctx)["ok"]), "duplicate IDs cannot double sell")
	var stale: Dictionary = Inventory.preview(state, "decompose", {"ids": [ids[2]]}, ctx)
	var changed := ctx.duplicate(true)
	changed["gold"] = 999
	check(not bool(Inventory.commit(state, stale, changed)["ok"]), "changed wallet invalidates preview")
	result = Inventory.commit(state, stale, ctx)
	state = result["state"]
	ctx["materials"] = result["materials"]
	check(result["materials"]["equipment-parts"] == 23 and not state["items"].has(ids[2]), "decompose consumes one ID and awards exact parts")
	ctx["offered_item"] = Catalog.generate(18, 10, 2, "focus")
	var craft: Dictionary = Inventory.preview(state, "craft", {}, ctx)
	check(craft["gold_delta"] == -60 and craft["materials_delta"]["equipment-parts"] == -6, "craft preview exact costs")
	changed = ctx.duplicate(true)
	changed["offered_item"] = Catalog.generate(19, 10, 2, "focus")
	check(not bool(Inventory.commit(state, craft, changed)["ok"]), "craft changed roll rejects old preview")
	result = Inventory.commit(state, craft, ctx)
	check(bool(result["ok"]) and result["state"]["items"].size() == state["items"].size() + 1 and result["materials"]["equipment-parts"] == 17, "craft atomic item/parts/gold")
	check(not bool(Inventory.commit(result["state"], craft, ctx)["ok"]), "craft duplicate receipt rejected")
	changed = ctx.duplicate(true)
	changed["gold"] = 0
	check(not bool(Inventory.preview(state, "craft", {}, changed)["ok"]), "craft insufficient gold")
	changed = ctx.duplicate(true)
	changed["materials"]["equipment-parts"] = 5
	check(not bool(Inventory.preview(state, "craft", {}, changed)["ok"]), "craft insufficient parts")
	ctx["offered_item"] = Catalog.generate(18, 10, 0, "focus")
	check(Inventory.preview(state, "purchase", {}, ctx)["gold_delta"] == -50, "white purchase deterministic price")
	check(not bool(Inventory.preview(state, "craft", {}, ctx)["ok"]), "cannot craft white via mismatched source")
	# Unlimited inventories and buyback are paged; normal operations do not prune.
	var large: Dictionary = Inventory.empty_state()
	for index: int in 100:
		var added: Dictionary = Inventory.add_item(large, Catalog.generate(index, 1, 0))
		large = added["state"]
	var page: Dictionary = Inventory.query(large, {}, 100)
	check(page["total"] == 100 and page["pages"] == 5 and page["page"] == 4 and page["items"].size() == 4, "large inventory pagination")
	result = Inventory.commit(large, Inventory.preview(large, "sell", {"ids": large["items"].keys()}, ctx), ctx)
	check(bool(result["ok"]) and result["state"]["buyback"].size() == 100, "no stealth buyback cap")
	large = Inventory.sanitize_state(result["state"])
	check(large["buyback"].size() == 100 and Inventory.query(large, {"source": "buyback"})["items"].size() == 24, "buyback roundtrip and paging")
	var ten_thousand := Inventory.empty_state()
	var template: Dictionary = Catalog.generate(7, 10, 3, "boots")
	for index: int in 10000:
		var item: Dictionary = Catalog.mint_item(template, "large_%05d" % index)
		item["acquired_seq"] = index + 1
		ten_thousand["items"][item["id"]] = item
	ten_thousand = Inventory.sanitize_state(ten_thousand)
	var large_page: Dictionary = Inventory.query(ten_thousand, {}, 416)
	check(large_page["total"] == 10000 and large_page["items"].size() == 16 and large_page["pages"] == 417, "ten thousand records stay available with bounded page rows")
	state = _apply(state, "unequip", {"slot": "weapon"}, ctx)
	state = _apply(state, "presets_clear_reference", {"id": ids[0]}, ctx)
	check(Inventory.preset_references(state, ids[0]).is_empty(), "explicit reference clear")


func _apply(state: Dictionary, action: String, args: Dictionary, ctx: Dictionary) -> Dictionary:
	var preview: Dictionary = Inventory.preview(state, action, args, ctx)
	var result: Dictionary = Inventory.commit(state, preview, ctx)
	check(bool(result.get("ok", false)), action + " success: " + str(result.get("error", "")))
	return result.get("state", state)


func _sanitization() -> void:
	check(Inventory.sanitize_state([]) == Inventory.empty_state(), "invalid ledger isolated")
	check(Catalog.sanitize_item("malformed").is_empty(), "invalid item scalar isolated")
	var corrupt: Dictionary = Catalog.generate(1, 5, 2, "shield")
	corrupt["acquired_seq"] = {"bad": 1}
	corrupt["legacy"] = "false"
	var normalized: Dictionary = Catalog.sanitize_item(corrupt)
	check(normalized["acquired_seq"] == 0 and normalized["legacy"] == false, "bad metadata cannot crash sorting or turn new gear into legacy")
	var broken := Inventory.empty_state()
	broken["items"] = {"unknown": {"slot": "weapon", "base_id": "future_base", "affixes": {"phys": 0.2}, "future_data": [1, 2, 3]},
		"old": {"slot": "weapon", "affixes": {"atk": 0.6, "hp": "bad", "cdr": INF}, "element": "ice"}}
	broken["equipped"] = {"weapon": "old", "armor": "unknown"}
	broken["presets"][0]["slots"] = {"weapon": "lost_id"}
	var clean: Dictionary = Inventory.sanitize_state(broken)
	check(clean["items"].size() == 2 and clean["items"]["unknown"]["future_data"] == [1, 2, 3], "unknown item preserved")
	check(clean["items"]["unknown"]["quarantined"], "unknown base quarantined")
	check(not bool(Inventory.preview(clean, "equip", {"id": "unknown"}, {"level": 10, "can_swap": true})["ok"]), "quarantined cannot equip")
	check(clean["equipped"] == {"weapon": "old"}, "wrong slot reference ignored")
	check(clean["presets"][0]["slots"]["weapon"] == "lost_id", "missing preset reference remains visible")
	near(float(clean["items"]["old"]["affixes"]["atk"]), 0.6, "raw historical roll retained")
	check(not clean["items"]["old"]["affixes"].has("hp") and not clean["items"]["old"]["affixes"].has("cdr"), "invalid numeric affixes isolated")
	var stats := Stats.new()
	stats.equips = Inventory.equipped_items(clean)
	near(stats.equip_affix("atk"), 0.5, "old effective safety boundary preserved")
	var roundtrip: Dictionary = Inventory.sanitize_state(JSON.parse_string(JSON.stringify(clean)))
	check(roundtrip["equipped"] == clean["equipped"] and roundtrip["presets"] == clean["presets"] and roundtrip["items"].keys().size() == 2, "JSON identity/references stable")
	check(Inventory.sanitize_state(roundtrip) == roundtrip, "sanitization idempotent")
	near(roundtrip["items"]["old"]["affixes"]["atk"], 0.6, "JSON legacy raw roll retained")


func _affix_filters() -> void:
	var state := Inventory.empty_state()
	var white := Catalog.mint_item(Catalog.generate(1001, 1, 0, "physical_sword"), "filter_white")
	white["favorite"] = true
	var random := Catalog.mint_item(Catalog.generate(1002, 3, 2, "magic_charm"), "filter_random")
	random["affixes"] = {"mp_regen": 0.07, "phys": 0.02}
	random["fixed_affixes"] = {"mp_regen": 0.07}
	random["affix_rolls"] = [{"id": "phys", "value": 0.02}]
	var legacy := Catalog.legacy_item({"name": "旧制物攻刀", "affixes": {"atk": 0.3, "magic": 0.7}, "rarity": 2}, "filter_legacy", "weapon")
	legacy["favorite"] = true
	var magic := Catalog.mint_item(Catalog.generate(1003, 1, 0, "rune_sword"), "filter_magic")
	var zero := Catalog.mint_item(Catalog.generate(1004, 1, 0, "physical_sword"), "filter_zero")
	zero["affixes"] = {"phys": 0.0}
	var negative := zero.duplicate(true)
	negative["id"] = "filter_negative"
	negative["affixes"] = {"phys": -0.2}
	var string_value := zero.duplicate(true)
	string_value["id"] = "filter_string"
	string_value["affixes"] = {"phys": "0.2"}
	var nonfinite := zero.duplicate(true)
	nonfinite["id"] = "filter_nonfinite"
	nonfinite["affixes"] = {"phys": INF}
	var malformed := zero.duplicate(true)
	malformed["id"] = "filter_malformed"
	malformed["affixes"] = []
	for item: Dictionary in [white, random, legacy, magic, zero, negative, string_value, nonfinite, malformed]:
		state["items"][item["id"]] = item
	var before := state.duplicate(true)
	var phys := Inventory.query(state, {"affix": "phys"})
	var ids: Array = phys["items"].map(func(item: Dictionary) -> String: return item["id"])
	check(phys["total"] == 3 and ids.has("filter_white") and ids.has("filter_random") and ids.has("filter_legacy"), "attribute filter covers fixed primary, random suffix and legacy atk")
	check(Inventory.query(state, {"affix": "atk"}) == phys, "old query atk aliases canonical phys")
	check(Inventory.query(state, {"affix": "magic"})["total"] == 1, "attribute filter excludes unrelated positive attributes")
	check(Inventory.query(state, {"affix": "magic", "search": "旧制物攻刀"})["total"] == 0, "unsupported legacy magic remains raw data but cannot match effective attribute")
	check(Inventory.query(state, {"affix": "phys", "slot": "weapon"})["total"] == 2, "attribute and slot filters intersect")
	check(Inventory.query(state, {"affix": "phys", "slot": "weapon", "rarity": 2, "favorite": true})["items"][0]["id"] == "filter_legacy", "attribute slot quality favorite all intersect")
	check(Inventory.query(state, {"affix": "phys", "rarity": 0, "favorite": true})["items"][0]["id"] == "filter_white", "white primary survives quality favorite intersection")
	check(Inventory.query(state, {"affix": "phys", "locked": true})["total"] == 0, "attribute locked intersection preserves empty result")
	check(Inventory.query(state, {"affix": "not_an_attribute"})["total"] == 0, "unknown attribute returns no results")
	check(Inventory.query(state, {"affix": ""})["total"] == state["items"].size(), "empty attribute leaves prior query unchanged")
	state["equipped"]["weapon"] = "filter_white"
	check(Inventory.query(state, {"affix": "phys"})["total"] == 2 and Inventory.query(state, {"affix": "phys", "source": "all"})["total"] == 3, "attribute filtering retains bag versus worn source semantics")
	state["buyback"] = [{"item": legacy, "price": 40}, {"item": magic, "price": 20}]
	var back := Inventory.query(state, {"source": "buyback", "affix": "phys"})
	check(back["total"] == 1 and back["items"][0]["id"] == "filter_legacy" and back["items"][0]["buyback_price"] == 40, "buyback attribute filter retains original ID and price")
	check(before["items"] == state["items"], "attribute queries never rewrite item values")
	var page := Inventory.query(state, {"affix": "phys", "source": "all"}, 1, 2)
	check(page["total"] == 3 and page["pages"] == 2 and page["items"].size() == 1, "filtered pagination retains bounded complete results")
