## 确定性掉落：固定来源统计、最坏保底、空槽/偏好、收据恢复及非法来源。
extends SceneTree

const Drops := preload("res://scripts/equipment/equipment_drops.gd")
const Catalog := preload("res://scripts/equipment/equipment_catalog.gd")
var checks := 0
var failures := 0


func _initialize() -> void:
	_test_source()
	_test_base_rates()
	_test_pity()
	_test_slot_weights()
	_test_receipts()
	_test_invalid()
	print("=== EQUIPMENT DROPS %s (%d checks) ===" % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)


func source(id: int, kind := "ordinary", terrain := "plains", seed_value := 24681357) -> Dictionary:
	return Drops.create_source(seed_value, kind, id, 0, terrain)


func locked(state: Dictionary, id: int, kind := "ordinary", terrain := "plains", equips: Dictionary = {}, preferred := "") -> Dictionary:
	var src := Drops.begin_combat(state, source(id, kind, terrain), equips, preferred)
	src["player_kill"] = true
	return src


func _test_source() -> void:
	var a := source(18, "elite", "forest")
	check(a == source(18, "elite", "forest"), "same world source has stable descriptor")
	check(a["source_id"] != source(18, "elite", "forest", 24681358)["source_id"], "world seed isolates source")
	check(a["source_id"] != source(19, "elite", "forest")["source_id"], "instance ID isolates source")
	check(a["source_id"] != Drops.create_source(24681357, "elite", 18, 1, "forest")["source_id"], "ordinal isolates source")
	for terrain: String in Drops.TERRAIN_LEVELS:
		for kind: String in Drops.KINDS:
			var expected := mini(10, int(Drops.TERRAIN_LEVELS[terrain]) + (2 if kind == "boss" else 1 if kind == "elite" else 0))
			check(source(18, kind, terrain)["ilvl"] == expected, "source level %s %s" % [terrain, kind])
	a["age"] = 1000000
	a["player_level"] = 90
	a["standing_terrain"] = "lava"
	check(Drops.seed_for(a, "rarity") == Drops.seed_for(source(18, "elite", "forest"), "rarity"), "age/player level/standing do not affect source RNG")
	seed(8317)
	var expected_global := randi()
	seed(8317)
	Drops.roll_rarity(a, Drops.empty_state())
	Drops.select_slot(a, 2)
	check(randi() == expected_global, "drop RNG never consumes global combat random stream")


func _test_base_rates() -> void:
	const COUNT := 60000
	var expected := {"ordinary": {-1: 0.92, 1: 0.07, 2: 0.01},
		"elite": {-1: 0.55, 2: 0.36, 3: 0.09}, "boss": {3: 0.90, 4: 0.10}}
	for kind: String in Drops.KINDS:
		var counts: Dictionary = {}
		var state := Drops.empty_state()
		for i in COUNT:
			var rarity: int = Drops.roll_rarity(source(i + 1, kind), state)["rarity"]
			counts[rarity] = int(counts.get(rarity, 0)) + 1
		check(counts.size() == expected[kind].size(), "%s produces exactly its approved rarity classes" % kind)
		for rarity: int in expected[kind]:
			var observed := float(counts.get(rarity, 0)) / COUNT
			check(absf(observed - expected[kind][rarity]) < 0.006, "%s base rate rarity%d %.4f" % [kind, rarity, observed])
		print("  BASE %s %s" % [kind, counts])


func _test_pity() -> void:
	var boundaries := {"ordinary": ["ordinary_failures", 24], "elite": ["elite_failures", 4], "boss": ["boss_orange_failures", 7]}
	for kind: String in Drops.KINDS:
		var state := Drops.empty_state()
		state["first_boss_consumed"] = true
		state["first_boss_status"] = "consumed"
		var key: String = boundaries[kind][0]
		var boundary: int = boundaries[kind][1]
		state[key] = boundary
		var forced_counts: Dictionary = {}
		for i in 16000:
			var roll := Drops.roll_rarity(source(i + 1, kind), state)
			check(roll["pity_forced"] and int(roll["rarity"]) >= (4 if kind == "boss" else 1), "%s guaranteed boundary #%d" % [kind, i])
			forced_counts[roll["rarity"]] = int(forced_counts.get(roll["rarity"], 0)) + 1
		if kind == "ordinary":
			check(absf(float(forced_counts.get(1, 0)) / 16000.0 - 0.875) < 0.015, "ordinary forced rarity ratio 7:1")
		elif kind == "elite":
			check(absf(float(forced_counts.get(2, 0)) / 16000.0 - 0.8) < 0.015, "elite forced rarity ratio 4:1")
		state[key] = 0
		var longest := 0
		var drops := 0
		for i in 30000:
			var rarity: int = Drops.roll_rarity(source(i + 1, kind), state)["rarity"]
			Drops._advance_pity(state, kind, rarity)
			longest = maxi(longest, int(state[key]))
			if rarity == 4 if kind == "boss" else rarity >= 1:
				drops += 1
		check(longest <= boundary, "%s never exceeds fail bound" % kind)
		check(longest == boundary, "%s deterministic sequence exercises worst drought" % kind)
		var expected_rate: float = {"ordinary": 0.091362, "elite": 0.473848, "boss": 0.175583}[kind]
		check(absf(float(drops) / 30000.0 - expected_rate) < 0.009, "%s long-run pity rate %.5f" % [kind, float(drops) / 30000.0])
		print("  PITY %s drops=%d max_fail=%d" % [kind, drops, longest])
	var separate := Drops.empty_state()
	separate["ordinary_failures"] = 12
	separate["elite_failures"] = 3
	separate["boss_orange_failures"] = 6
	Drops._advance_pity(separate, "ordinary", 1)
	check(separate["ordinary_failures"] == 0 and separate["elite_failures"] == 3 and separate["boss_orange_failures"] == 6, "ordinary gear resets only ordinary pity")
	Drops._advance_pity(separate, "boss", 3)
	check(separate["boss_orange_failures"] == 7, "purple Boss increments orange drought")
	Drops._advance_pity(separate, "boss", 4)
	check(separate["boss_orange_failures"] == 0, "only orange clears Boss drought")


func _test_slot_weights() -> void:
	var counts := {}
	var full: Dictionary = {}
	for slot: String in Drops.SLOTS:
		full[slot] = {"id": "old:" + slot}
	for i in 18000:
		var src := source(i + 1)
		src["preferred_slot"] = "helmet"
		src["empty_slots"] = []
		var slot := Drops.select_slot(src, 3)
		counts[slot] = int(counts.get(slot, 0)) + 1
	for slot: String in Drops.SLOTS:
		check(absf(float(counts.get(slot, 0)) / 18000.0 - (0.5 if slot == "helmet" else 0.1)) < 0.02, "preferred slot ratio " + slot)
	var state := Drops.empty_state()
	full.erase("boots")
	var first := locked(state, 718, "boss", "forest", full, "weapon")
	check(Drops.select_slot(first, 3) == "boots", "compatible empty slot outranks preferred")
	var rebound := Drops.begin_combat(state, source(718, "boss", "forest"), {}, "charm")
	check(rebound["preferred_slot"] == "weapon" and rebound["empty_slots"] == ["boots"], "preference and empties lock first combat")
	var orange_counts := {"weapon": 0, "offhand": 0}
	for i in 16000:
		var src := source(i + 1, "boss")
		src["preferred_slot"] = "boots"
		src["empty_slots"] = ["helmet", "boots"]
		var slot := Drops.select_slot(src, 4)
		check(slot in ["weapon", "offhand"], "orange stays legal despite invalid preference")
		orange_counts[slot] += 1
	check(absf(float(orange_counts["weapon"]) / 16000.0 - 0.5) < 0.02, "orange template count does not skew slots")
	for i in 100:
		var item := Catalog.generate(i, 5, 4, "weapon")
		check(item.get("rarity") == 4 and item.get("base_id") == "physical_sword", "orange weapon stays orange without rune downgrade")


func _test_receipts() -> void:
	var state := Drops.empty_state()
	state["boss_orange_failures"] = 7
	var src := locked(state, 9001, "boss", "hill")
	var first := Drops.settle(state, src)
	check(first["items"].is_empty() and first["first_boss_choices"].size() == 3, "first Boss replaces ordinary roll with exactly 3 candidates")
	check(first["rarity"] == 4 and state["boss_orange_failures"] == 0, "first Boss clears orange drought")
	var bases: Array = []
	for item: Dictionary in first["first_boss_choices"]:
		bases.append(item.get("base_id"))
		check(item.get("rarity") == 4 and item.get("item_level") == 9, "first Boss candidates source-scaled orange")
	check(bases == Drops.FIRST_BOSS_BASES, "first Boss has physical sword shield focus")
	var restored := Drops.sanitize_state(JSON.parse_string(JSON.stringify(state)))
	var repeated := Drops.settle(restored, src)
	if repeated["first_boss_choices"] != first["first_boss_choices"]:
		for i in 3:
			for field: String in first["first_boss_choices"][i]:
				if first["first_boss_choices"][i][field] != repeated["first_boss_choices"][i].get(field):
					print("  RECEIPT DIFF ", field, " ", first["first_boss_choices"][i][field], " / ", repeated["first_boss_choices"][i].get(field))
	check(repeated["duplicate"] and repeated["first_boss_choices"] == first["first_boss_choices"], "reload receipt never rerolls first Boss")
	check(restored["boss_orange_failures"] == 0, "duplicate source never advances pity")
	var second := Drops.settle(restored, locked(restored, 9002, "boss", "lava"))
	check(second["items"].size() == 1 and second["first_boss_choices"].is_empty(), "later Boss exactly one ordinary gear")
	var pending := Drops.empty_state()
	var prepared := locked(pending, 888, "elite", "snow", {"weapon": {"id": "old"}}, "offhand")
	var cold := Drops.sanitize_state(JSON.parse_string(JSON.stringify(pending)))
	seed(987)
	for i in 30:
		randi()
	check(Drops.settle(pending, prepared) == Drops.settle(cold, prepared), "unsettled source survives reload and unrelated random calls")
	var new_ledger := Drops.sanitize_state({})
	check(not new_ledger["first_boss_consumed"] and new_ledger["first_boss_status"] == "eligible", "new reward ledger starts eligible without fabricating a historical gift")
	check(restored["first_boss_consumed"] and restored["first_boss_status"] == "pending", "actual pending first Boss receipt survives restore")
	restored["first_boss_status"] = "claimed"
	var claimed := Drops.sanitize_state(JSON.parse_string(JSON.stringify(restored)))
	check(claimed["first_boss_consumed"] and claimed["first_boss_status"] == "claimed", "actual claimed first Boss receipt survives restore")


func _test_invalid() -> void:
	var state := Drops.empty_state()
	check(Drops.settle(state, source(1)).is_empty() and state == Drops.empty_state(), "unattributed source cannot reward or advance pity")
	var forged := source(2)
	forged["player_kill"] = true
	check(Drops.settle(state, forged).is_empty(), "unlocked forged kill cannot settle")
	var src := locked(state, 3)
	var before := state.duplicate(true)
	src["ilvl"] = 10
	check(Drops.settle(state, src).is_empty() and state == before, "tampered source level leaves ledger untouched")
	var split := Drops.create_source(24681357, "ordinary", 4, 0, "plains", {"splits_on_death": true, "generation": 1})
	state["ordinary_failures"] = 24
	var split_locked := Drops.begin_combat(state, split, {}, "weapon")
	split_locked["player_kill"] = true
	var split_receipt := Drops.settle(state, split_locked)
	check(split_receipt.get("items", []).size() == 1 and state["ordinary_failures"] == 0, "finite split descendant has the same eligible pity roll as any real instance")
	var after_split := state.duplicate(true)
	check(Drops.settle(state, split_locked).get("duplicate", false) and state == after_split, "each finite split instance may settle exactly once")
	var dirty := Drops.sanitize_state({"ordinary_failures": "bad", "elite_failures": 100,
		"boss_orange_failures": -100, "first_boss_consumed": "true", "sources": [], "receipts": "bad"})
	check(dirty["ordinary_failures"] == 0 and dirty["elite_failures"] == 4 and dirty["boss_orange_failures"] == 0 and not dirty["first_boss_consumed"], "malformed persisted fields safely isolated")
	for bad: Variant in [null, false, true, 7, "false", [], {}, INF, NAN]:
		var fuzz := Drops.sanitize_state({"ordinary_failures": bad, "elite_failures": bad,
			"boss_orange_failures": bad, "first_boss_consumed": bad, "first_boss_status": bad,
			"sources": {"bad": bad}, "receipts": {"equipment:bad": bad}})
		check(fuzz["sources"].is_empty() and fuzz["receipts"].is_empty(), "malformed optional field quarantine")
