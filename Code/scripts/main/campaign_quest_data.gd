## 战役的纯数据账本。真实行为由表现层验证；此处只接受具名、同种子、顺序完整的证据。
## 接单预算、任务物件与支付收据独立保存。证据损坏不能造出结局，也不能重开已付奖励。
class_name CampaignQuestData
extends RefCounted

const Catalog := preload("res://scripts/main/campaign_catalog.gd")
const Outpost := preload("res://scripts/main/outpost_quest_data.gd")
const Economy := preload("res://scripts/ecology/economy_math.gd")
const Facts := preload("res://scripts/main/campaign_world_facts.gd")
const Encounters := preload("res://scripts/main/campaign_encounters.gd")
const ID := "campaign_watch_v1"
const VERSION := 1
const MAX_LEVEL := 100
const MAX_AMOUNT := 100000
const ENDING_STAGE := "watch_c6_lava:s4"
const ENDING_ACTION := ENDING_STAGE + ":ending"
const REUNION := "reunion"
## 此版本抄录批准时的 EconomyMath 预算，终身不随通用经济平衡改写。
## 新战役平衡必须新增 v2 规则并提升 REWARD_VERSION；绝不可修改以下 v1 常量。
const REWARD_VERSION := 1
const REWARD_V1 := {"gold_base": 12, "gold_target": 6, "gold_level": 3, "xp_base": 20, "xp_target": 8}

static func create(seed: int) -> Dictionary:
	return {"id": ID, "version": VERSION, "seed": seed, "chapter1_proof": {}, "chapters": {},
		"quests": {}, "random_used": {}, "active_random": "", "history": [], "paused_chains": [],
		"puzzle_progress": {}, "main_routes": {}, "main_kills": {}, "optional_routes": {}, "optional_route_steps": {}, "optional_route_reanchor": {}, "optional_route_passages": {}, "optional_targets": {}, "optional_bindings": {},
		"world_facts": Facts.sanitize({}, seed), "encounters": Encounters.sanitize({}, seed),
		"dynamic_runtime": {"known_objects": {}, "route_steps": {}, "relief_needs": {}, "bindings": {}}, "travel": {"visited": [], "unlocked": ["plains"], "arrivals": {}}, "services": {}, "service_receipts": {}, "flags": {}, "ending": ""}

static func sanitize(value: Variant, seed: int) -> Dictionary:
	if not value is Dictionary or not value.get("id") is String or value["id"] != ID or _integer(value.get("version"), -1) != VERSION or _integer(value.get("seed"), -1) != seed:
		return {}
	var raw: Dictionary = value
	var q := create(seed)
	q["service_receipts"] = _service_receipts(raw, seed)
	q["world_facts"] = Facts.sanitize(raw.get("world_facts", {}), seed)
	q["encounters"] = Encounters.sanitize(raw.get("encounters", {}), seed)
	q["dynamic_runtime"] = _dynamic_state(raw.get("dynamic_runtime", {}), seed)
	q["optional_bindings"] = _optional_bindings(raw.get("optional_bindings", {}), seed)
	authorize_chapter1(q, raw.get("chapter1_proof", {}))
	var contracts: Dictionary = raw.get("chapters", {}) if raw.get("chapters") is Dictionary else {}
	for chapter: Dictionary in Catalog.main_chapters():
		var id: String = chapter["id"]
		var saved: Variant = contracts.get(id)
		if not saved is Dictionary: continue
		var c: Dictionary = _contract(saved)
		if not c.is_empty() and c["family"] == "main" and c["target"] == 4 + int(chapter["number"]): q["chapters"][id] = c
	var saved_quests: Dictionary = raw.get("quests", {}) if raw.get("quests") is Dictionary else {}
	# 固定目录顺序保证跨段前置先被验证；不信任保存的 completed/active 等派生状态。
	for s: Dictionary in Catalog.all_stages(int(q.get("seed", 0))):
		var sid: String = s["id"]
		var saved: Variant = saved_quests.get(sid)
		if not saved is Dictionary: continue
		var state := _stage_state()
		state["receipt"] = _receipt(saved.get("receipt", {}))
		var contract: Dictionary = q["chapters"].get(s["chapter"], {}) if s["family"] == "main" else _contract(saved.get("contract", {}))
		if not contract.is_empty() and contract["family"] == s["family"] and (s["family"] == "main" or contract["target"] == (2 if s["family"] == "random" else 3)):
			state["accepted"] = true
			state["contract"] = contract.duplicate(true)
			state["reward"] = _stage_reward(s, contract)
		q["quests"][sid] = state
		if not state["accepted"] or not _stage_unlocked(q, s): continue
		var evidence: Dictionary = saved.get("evidence", {}) if saved.get("evidence") is Dictionary else {}
		for a: Dictionary in s["actions"]:
			var proof: Dictionary = _proof(evidence.get(a["id"]), a, seed)
			if not proof.is_empty() and _can_record(q, sid, a["id"], false) and _consistent_proof(q, a, proof):
				state["evidence"][a["id"]] = proof
				if a["kind"] == "choice" or _legacy_ending_proof(proof, a): state["choice"] = proof.get("choice", "")
	# 使用次数是独立的不可逆占位记录；放弃、读档和坏证据都不能把名额退回。
	var used: Dictionary = raw.get("random_used", {}) if raw.get("random_used") is Dictionary else {}
	for s: Dictionary in Catalog.all_stages(int(q.get("seed", 0))):
		if s["family"] != "random": continue
		var sid: String = s["id"]
		var state: Dictionary = q["quests"].get(sid, {})
		if _true(used.get(sid)) or state.get("accepted", false) or state.get("receipt", {}).get("paid", false): q["random_used"][sid] = true
	var active: String = str(raw.get("active_random", ""))
	if q["random_used"].has(active) and q["quests"].get(active, {}).get("accepted", false) and not paid(q, active): q["active_random"] = active
	# 缺失 active_random 只恢复唯一最早未支付实例，绝不产生第二张随机合同。
	if q["active_random"] == "":
		for s: Dictionary in Catalog.all_stages(int(q.get("seed", 0))):
			if s["family"] == "random" and q["quests"].get(s["id"], {}).get("accepted", false) and not paid(q, s["id"]):
				q["active_random"] = s["id"]
				break
	if raw.get("history") is Array:
		for entry: Variant in raw["history"].slice(0, 160):
			if entry is String and not entry in q["history"] and not Catalog.stage(entry).is_empty(): q["history"].append(entry)
	_restore_runtime_state(q, raw)
	return q

static func authorize_chapter1(q: Dictionary, value: Variant) -> bool:
	var proof := Outpost.sanitize(value)
	if proof.is_empty() or not proof.get("evidence", {}).get("signpost_repaired", false) or not proof.get("evidence", {}).get("next_clue_received", false):
		return false
	q["chapter1_proof"] = proof
	_refresh_derived(q)
	return true

static func chapter1_complete(q: Dictionary) -> bool:
	var proof := Outpost.sanitize(q.get("chapter1_proof", {}))
	return not proof.is_empty() and proof.get("evidence", {}).get("signpost_repaired", false) and proof.get("evidence", {}).get("next_clue_received", false)

static func accept_chapter(q: Dictionary, chapter_id: String, level: int) -> bool:
	var c := Catalog.chapter(chapter_id)
	if c.is_empty() or not _chapter_unlocked(q, c): return false
	if q.get("chapters", {}).has(chapter_id):
		if chapter_id in q.get("paused_chains", []):
			q["paused_chains"].erase(chapter_id)
			return true
		return false
	var contract := _new_contract(level, 4 + int(c["number"]), "main")
	q["chapters"][chapter_id] = contract
	for s: Dictionary in c["steps"]:
		var existing: Dictionary = q["quests"].get(s["id"], _stage_state())
		existing["accepted"] = true
		existing["contract"] = contract.duplicate(true)
		existing["reward"] = _stage_reward(s, contract)
		q["quests"][s["id"]] = existing
	return true

static func accept(q: Dictionary, stage_id: String, level: int) -> bool:
	var s := Catalog.stage(stage_id)
	if s.is_empty(): return false
	if s["family"] == "main": return accept_chapter(q, s["chapter"], level)
	if not _stage_unlocked(q, s) or q.get("quests", {}).get(stage_id, {}).get("accepted", false) or paid(q, stage_id): return false
	if s["family"] == "random":
		if q.get("active_random", "") != "" or q.get("random_used", {}).size() >= Catalog.RANDOM_LIMIT or q.get("random_used", {}).has(stage_id): return false
		q["random_used"][stage_id] = true
		q["active_random"] = stage_id
	var state := _stage_state()
	state["accepted"] = true
	state["contract"] = _new_contract(level, 2 if s["family"] == "random" else 3, s["family"])
	state["reward"] = _stage_reward(s, state["contract"])
	q["quests"][stage_id] = state
	return true

static func can_record(q: Dictionary, stage_id: String, action_id: String) -> bool:
	return _can_record(q, stage_id, action_id, true)

static func _can_record(q: Dictionary, stage_id: String, action_id: String, live: bool) -> bool:
	var s := Catalog.stage(stage_id)
	var a := Catalog.action(stage_id, action_id)
	var state: Dictionary = q.get("quests", {}).get(stage_id, {})
	if s.is_empty() or a.is_empty() or not state.get("accepted", false) or not _stage_unlocked(q, s): return false
	if live and s["family"] == "random" and q.get("active_random", "") != stage_id: return false
	if state.get("evidence", {}).has(action_id): return false
	for dependency: String in a.get("requires", []):
		if not state.get("evidence", {}).has(dependency): return false
	if a.has("route") and state.get("choice", "") != a["route"]: return false
	return true

static func record(q: Dictionary, stage_id: String, action_id: String, evidence: Dictionary) -> bool:
	if not can_record(q, stage_id, action_id): return false
	var a := Catalog.action(stage_id, action_id)
	# 旧二选一只允许从既有收据恢复；实时入口不能再创建第二种结局。
	if action_id == ENDING_ACTION and evidence.has("choice"): return false
	var raw: Dictionary = evidence.duplicate(true)
	raw["action_id"] = action_id
	raw["seed"] = q["seed"]
	raw["object"] = a["object"]
	raw["kind"] = a["kind"]
	if raw.get("position") is Vector2: raw["position"] = [raw["position"].x, raw["position"].y]
	var proof := _proof(raw, a, int(q["seed"]))
	if proof.is_empty() or not _consistent_proof(q, a, proof): return false
	q["quests"][stage_id]["evidence"][action_id] = proof
	if a["kind"] == "puzzle": q["puzzle_progress"].erase(action_id)
	if a["kind"] == "choice": q["quests"][stage_id]["choice"] = proof["choice"]
	_refresh_derived(q)
	if ready(q, stage_id) and not stage_id in q["history"]: q["history"].append(stage_id)
	return true

static func ready(q: Dictionary, stage_id: String) -> bool:
	return _ready(q, stage_id, {})

static func _ready(q: Dictionary, stage_id: String, memo: Dictionary) -> bool:
	if memo.has(stage_id): return memo[stage_id]
	memo[stage_id] = false
	var s := Catalog.stage(stage_id)
	var state: Dictionary = q.get("quests", {}).get(stage_id, {})
	if s.is_empty() or not state.get("accepted", false) or not _stage_unlocked(q, s, memo): return false
	for a: Dictionary in s["actions"]:
		if state.get("evidence", {}).has(a["id"]):
			if _proof(state["evidence"][a["id"]], a, int(q.get("seed", -1))).is_empty() or not _consistent_proof(q, a, state["evidence"][a["id"]]): return false
			for dependency: String in a.get("requires", []):
				if not state["evidence"].has(dependency): return false
	for required: String in s["required"]:
		if not state.get("evidence", {}).has(required): return false
	for alternatives: Array in s.get("required_any", []):
		var found := false
		for required: String in alternatives:
			if state.get("evidence", {}).has(required): found = true
		if not found: return false
	memo[stage_id] = true
	return true

static func chapter_complete(q: Dictionary, chapter_id: String) -> bool:
	return _chapter_complete(q, chapter_id, {})

static func _chapter_complete(q: Dictionary, chapter_id: String, memo: Dictionary) -> bool:
	var chapter := Catalog.chapter(chapter_id)
	if chapter.is_empty(): return false
	for s: Dictionary in chapter["steps"]:
		if not _ready(q, s["id"], memo): return false
	return true

static func reward(q: Dictionary, stage_id: String) -> Dictionary:
	return q.get("quests", {}).get(stage_id, {}).get("reward", {"gold": 0, "xp": 0, "bonus": ""}).duplicate(true)

static func paid(q: Dictionary, stage_id: String) -> bool:
	return q.get("quests", {}).get(stage_id, {}).get("receipt", {}).get("paid", false)

## 调用者必须先用同一快照原子提交金币、经验和全部物品；满包或保存失败不可调用。
static func mark_paid(q: Dictionary, stage_id: String, actual_gold: int = -1, actual_xp: int = -1) -> bool:
	if not ready(q, stage_id) or paid(q, stage_id): return false
	var promised := reward(q, stage_id)
	q["quests"][stage_id]["receipt"] = {"paid": true, "status": "paid", "gold": clampi(actual_gold if actual_gold >= 0 else int(promised["gold"]), 0, MAX_AMOUNT),
		"xp": clampi(actual_xp if actual_xp >= 0 else int(promised["xp"]), 0, MAX_AMOUNT), "bonus": promised["bonus"]}
	if q.get("active_random", "") == stage_id: q["active_random"] = ""
	return true

static func active_ids(q: Dictionary) -> Array:
	var result: Array = []
	for s: Dictionary in Catalog.all_stages(int(q.get("seed", 0))):
		var state: Dictionary = q.get("quests", {}).get(s["id"], {})
		if state.get("accepted", false) and not paid(q, s["id"]) and _stage_unlocked(q, s) and not s["chain"] in q.get("paused_chains", []):
			if s["family"] != "random" or q.get("active_random", "") == s["id"]: result.append(s["id"])
	return result

static func next_random(q: Dictionary, template_id: String) -> String:
	for s: Dictionary in Catalog.all_stages(int(q.get("seed", 0))):
		if s["family"] == "random" and s.get("template", "") == template_id and not q.get("random_used", {}).has(s["id"]): return s["id"]
	return ""

static func _chapter_unlocked(q: Dictionary, chapter: Dictionary, memo: Dictionary = {}) -> bool:
	if int(chapter["number"]) == 2: return chapter1_complete(q)
	for previous: Dictionary in Catalog.main_chapters():
		if int(previous["number"]) == int(chapter["number"]) - 1: return _chapter_complete(q, previous["id"], memo)
	return false

static func _stage_unlocked(q: Dictionary, s: Dictionary, memo: Dictionary = {}) -> bool:
	if s["family"] == "main" and not _chapter_unlocked(q, Catalog.chapter(s["chapter"]), memo): return false
	if s["family"] == "world" and not _world_unlocked(q, s["chain"], memo): return false
	if s.get("previous", "") != "" and not _ready(q, s["previous"], memo): return false
	var chain := Catalog.chain(s["chain"])
	var unlock: String = str(s.get("unlock_after", chain.get("unlock_after", "")))
	if unlock == "chapter1": return chapter1_complete(q)
	if unlock != "" and not _chapter_complete(q, unlock, memo): return false
	return true

static func reward_budget_v1(target: int, level: int) -> Dictionary:
	return {"gold": int(REWARD_V1["gold_base"]) + target * int(REWARD_V1["gold_target"]) + level * int(REWARD_V1["gold_level"]),
		"xp": int(REWARD_V1["xp_base"]) + target * int(REWARD_V1["xp_target"])}

static func _new_contract(level: int, target: int, family: String) -> Dictionary:
	var frozen_level := clampi(level, 1, MAX_LEVEL)
	var budget := reward_budget_v1(target, frozen_level)
	return {"accepted": true, "version": REWARD_VERSION, "level": frozen_level, "gold": budget["gold"],
		"xp": budget["xp"], "family": family, "target": target}

static func _contract(value: Variant) -> Dictionary:
	if not value is Dictionary or not _true(value.get("accepted")) or _integer(value.get("version"), -1) != 1: return {}
	var level := _integer(value.get("level"), -1)
	var gold := _integer(value.get("gold"), -1)
	var xp := _integer(value.get("xp"), -1)
	var family: String = str(value.get("family", ""))
	if level < 1 or level > MAX_LEVEL or gold < 0 or gold > MAX_AMOUNT or xp < 0 or xp > MAX_AMOUNT or family not in ["main", "side", "regional", "random", "world"]: return {}
	# v1公式归档：接单版本不随日后EconomyMath调整而改写；错误金额不能放大承诺。
	var target := _integer(value.get("target"), int((xp - int(REWARD_V1["xp_base"])) / int(REWARD_V1["xp_target"])))
	var promised := reward_budget_v1(target, level)
	if target < 2 or target > 10 or xp != promised["xp"] or gold != promised["gold"]: return {}
	return {"accepted": true, "version": 1, "level": level, "gold": gold, "xp": xp, "family": family, "target": target}

static func _stage_reward(s: Dictionary, contract: Dictionary) -> Dictionary:
	var gold: int = contract["gold"]
	var xp: int = contract["xp"]
	var bonus := ""
	if s["family"] == "world" and int(s["index"]) < 2:
		return {"gold": 0, "xp": 0, "bonus": ""}
	if s["family"] == "main":
		var weights := [15, 25, 25, 35]
		var index: int = s["index"]
		if index == 3:
			for i: int in range(3):
				gold -= int(float(contract["gold"]) * float(weights[i]) / 100.0)
				xp -= int(float(contract["xp"]) * float(weights[i]) / 100.0)
			bonus = "onigiri"
		else:
			gold = int(float(gold) * float(weights[index]) / 100.0)
			xp = int(float(xp) * float(weights[index]) / 100.0)
	return {"gold": gold, "xp": xp, "bonus": bonus}

static func _stage_state() -> Dictionary:
	return {"accepted": false, "contract": {}, "evidence": {}, "choice": "", "reward": {"gold": 0, "xp": 0, "bonus": ""},
		"receipt": {"paid": false, "status": "pending", "gold": 0, "xp": 0, "bonus": ""}}

static func _receipt(value: Variant) -> Dictionary:
	var raw: Dictionary = value if value is Dictionary else {}
	var was_paid: bool = _true(raw.get("paid")) or str(raw.get("status", "")) == "paid"
	return {"paid": was_paid, "status": "paid" if was_paid else "pending", "gold": clampi(_integer(raw.get("gold"), 0), 0, MAX_AMOUNT),
		"xp": clampi(_integer(raw.get("xp"), 0), 0, MAX_AMOUNT), "bonus": "onigiri" if str(raw.get("bonus", "")) == "onigiri" else ""}

## 只兼容原版终章该项行动的两种历史签署记录；不放宽其它行动的类型检查。
static func _legacy_ending_proof(raw: Dictionary, action: Dictionary) -> bool:
	return action.get("id", "") == ENDING_ACTION and action.get("kind", "") == "conclude" and raw.get("kind", "") == "choice" and raw.get("choice", "") in ["distributed", "centralized"]

## 历史选择属于存档证据，当前驻地和服务只消费统一的团聚结局。
static func effective_ending(q: Dictionary) -> String:
	return REUNION if ready(q, ENDING_STAGE) else ""

static func _proof(value: Variant, action: Dictionary, seed: int) -> Dictionary:
	if not value is Dictionary: return {}
	var raw: Dictionary = value
	if not raw.get("action_id") is String or not raw.get("object") is String or not raw.get("kind") is String: return {}
	if raw["action_id"] != action["id"] or _integer(raw.get("seed"), -1) != seed or raw["object"] != action["object"] or (raw["kind"] != action["kind"] and not _legacy_ending_proof(raw, action)): return {}
	if action["id"] == ENDING_ACTION and raw.has("choice") and not _legacy_ending_proof(raw, action): return {}
	var tick := _integer(raw.get("tick"), -1)
	var position: Variant = raw.get("position")
	if tick < 0 or not position is Array or position.size() != 2: return {}
	for coordinate: Variant in position:
		if typeof(coordinate) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(coordinate)) or absf(float(coordinate)) > 10000000.0: return {}
	var p := {"action_id": action["id"], "seed": seed, "object": action["object"], "kind": raw["kind"], "tick": tick,
		"position": [float(position[0]), float(position[1])]}
	match str(action["kind"]):
		"puzzle":
			if not raw.get("order") is Array or raw["order"] != action.get("puzzle_order", []): return {}
			p["order"] = raw["order"].duplicate()
		"choice":
			var choice: String = str(raw.get("choice", ""))
			var valid := false
			for option: Variant in action.get("choices", []):
				if option is Dictionary:
					if str(option.get("id", "")) == choice: valid = true
				elif option is String and option == choice: valid = true
			if not valid: return {}
			p["choice"] = choice
		"obstacle":
			if not raw.get("obstacle_key") is String or raw["obstacle_key"].is_empty() or not _true(raw.get("destroyed")): return {}
			p["obstacle_key"] = raw["obstacle_key"].left(180)
			p["destroyed"] = true
		"boss":
			if _integer(raw.get("instance_id"), -1) <= 0 or not _true(raw.get("player_kill")) or not raw.get("region_id") is String or raw["region_id"].is_empty(): return {}
			p["instance_id"] = _integer(raw["instance_id"], -1)
			p["player_kill"] = true
			p["region_id"] = raw["region_id"].left(180)
		"route":
			if not raw.get("route") in action.get("routes", []) or not _true(raw.get("traversed")): return {}
			p["route"] = raw["route"]
			p["traversed"] = true
		"encounter":
			if not raw.get("outcome") in action.get("choices", []) or not _true(raw.get("verified")): return {}
			if raw["outcome"] == "defeated" and (_integer(raw.get("instance_id"), -1) <= 0 or not _true(raw.get("player_kill"))): return {}
			p["outcome"] = raw["outcome"]
			p["verified"] = true
			if raw["outcome"] == "defeated":
				p["instance_id"] = _integer(raw["instance_id"], -1)
				p["player_kill"] = true
		"configure":
			if not raw.get("nodes") is Array or raw["nodes"].size() != int(action.get("node_count", 3)): return {}
			var selected: Array = []
			for node: Variant in raw["nodes"]:
				if not node is String or not node in _regional_services() or node in selected: return {}
				selected.append(node)
			p["nodes"] = selected
		"ecology":
			var outcome: String = str(raw.get("outcome", ""))
			if outcome not in ["hunt", "ransack", "survey"] or not _true(raw.get("verified")): return {}
			p["outcome"] = outcome
			p["verified"] = true
	for key: String in ["region_id", "species", "target_key", "witness", "outcome", "item", "reason", "destination", "choice"]:
		if raw.get(key) is String: p[key] = raw[key].left(300)
	if raw.has("target_position"):
		var target_position := _position(raw["target_position"])
		if not target_position.is_empty(): p["target_position"] = target_position
	if raw.has("unit_ids"): p["unit_ids"] = _unit_ids(raw["unit_ids"])
	if raw.get("counts") is Dictionary: p["counts"] = _counts(raw["counts"])
	if raw.get("snapshot") is Dictionary:
		var snapshot: Dictionary = raw["snapshot"]
		p["snapshot"] = {"region_id": str(snapshot.get("region_id", "")).left(180), "tick": maxi(0, _integer(snapshot.get("tick"), 0)),
			"outcome": "observed", "species_counts": _counts(snapshot.get("species_counts", {}))}
	if raw.get("events") is Array: p["events"] = Facts._events(raw["events"], seed, 64)
	if raw.get("visit_ids") is Array:
		p["visit_ids"] = []
		for id: Variant in raw["visit_ids"].slice(0, 16):
			if id is String and not id in p["visit_ids"]: p["visit_ids"].append(id.left(180))
	if raw.get("nodes") is Array:
		p["nodes"] = []
		for id: Variant in raw["nodes"].slice(0, 3):
			if id is String and id in _regional_services() and not id in p["nodes"]: p["nodes"].append(id)
	if raw.get("obstacle_key") is String and _true(raw.get("destroyed")):
		p["obstacle_key"] = raw["obstacle_key"].left(180)
		p["destroyed"] = true
	return p

static func _integer(value: Variant, fallback: int) -> int:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or float(value) != floor(float(value)): return fallback
	return int(value)

static func _true(value: Variant) -> bool:
	return typeof(value) == TYPE_BOOL and value


## 只恢复合法谜题前缀；未知机关、越过前置的前缀和已完成机关的残余输入都丢弃。
static func _restore_runtime_state(q: Dictionary, raw: Dictionary) -> void:
	var progress: Dictionary = raw.get("puzzle_progress", {}) if raw.get("puzzle_progress") is Dictionary else {}
	for a: Dictionary in Catalog.actions(int(q.get("seed", 0))).values():
		if a["kind"] != "puzzle" or not _can_record(q, a["stage"], a["id"], false): continue
		var input: Variant = progress.get(a["id"])
		if not input is Array or input.size() >= a["puzzle_order"].size(): continue
		var valid := true
		for index: int in range(input.size()):
			if not input[index] is String or input[index] != a["puzzle_order"][index]: valid = false
		if valid: q["puzzle_progress"][a["id"]] = input.duplicate()
	if raw.get("paused_chains") is Array:
		for id: Variant in raw["paused_chains"]:
			if id is String and not Catalog.chain(id).is_empty() and not id in q["paused_chains"]: q["paused_chains"].append(id)
	_restore_progress(q, raw)
	_refresh_derived(q)
	var travel: Dictionary = raw.get("travel", {}) if raw.get("travel") is Dictionary else {}
	if travel.get("visited") is Array:
		for terrain: Variant in travel["visited"]:
			if terrain is String and (terrain in q["travel"]["unlocked"] or terrain == "home" or (terrain == "shelter" and effective_ending(q) == REUNION) or (terrain == "side_troll" and chapter_complete(q, "watch_c2_forest"))) and not terrain in q["travel"]["visited"]: q["travel"]["visited"].append(terrain)
	if not q["travel"].has("arrivals"): q["travel"]["arrivals"] = {}
	if travel.get("arrivals") is Dictionary:
		for terrain: String in q["travel"]["visited"]:
			if terrain not in ["home", "forest", "swamp", "hill", "snow", "lava", "side_troll", "shelter"]: continue
			var position := _arrival_position(travel["arrivals"].get(terrain))
			if not position.is_empty(): q["travel"]["arrivals"][terrain] = position

static func _refresh_derived(q: Dictionary) -> void:
	q["flags"] = {}
	q["ending"] = ""
	# 支付证明先收拢为独立墓碑，服务可用性随后只由有效行动证据重新投影。
	q["service_receipts"] = _service_receipts(q, int(q.get("seed", 0)))
	q["services"] = {}
	if not q.has("travel"): q["travel"] = {"visited": [], "unlocked": []}
	q["travel"]["unlocked"] = ["plains"]
	if chapter1_complete(q): q["travel"]["unlocked"].append("forest")
	for chapter: Dictionary in Catalog.main_chapters():
		if chapter_complete(q, chapter["id"]):
			for next: Dictionary in Catalog.main_chapters():
				if int(next["number"]) == int(chapter["number"]) + 1: q["travel"]["unlocked"].append(next["terrain"])
	for s: Dictionary in Catalog.all_stages(int(q.get("seed", 0))):
		var state: Dictionary = q.get("quests", {}).get(s["id"], {})
		for a: Dictionary in s["actions"]:
			if not state.get("evidence", {}).has(a["id"]): continue
			q["flags"][a["id"]] = true
			if a.has("opens"): q["flags"][a["opens"]] = true
			if a.has("service") and (not a.has("service_choices") or choice(q, a) in a["service_choices"]):
				var service: String = a["service"]
				var claimed := service_claimed(q, service)
				q["services"][service] = {"enabled": true, "claimed": claimed, "status": "claimed" if claimed else "available", "stock_item": "onigiri"}
			if a.get("ending", false) and ready(q, s["id"]):
				q["ending"] = state.get("choice", "") if not str(state.get("choice", "")).is_empty() else REUNION
	if effective_ending(q) == REUNION:
		# 原站点仍是亮着的转发设备；此标记不搬走独立支线居民或更改补给领取墓碑。
		for id: String in ["forest_station", "swamp_station", "hill_station", "snow_station", "ending_station"]:
			if q["services"].has(id):
				q["services"][id]["mode"] = "automatic_relay"
				q["services"][id]["staffed"] = false


static func choice(q: Dictionary, action: Dictionary) -> String:
	var stage_id: String = str(action.get("choice_stage", action.get("stage", "")))
	return str(q.get("quests", {}).get(stage_id, {}).get("choice", ""))

static func _consistent_proof(q: Dictionary, a: Dictionary, proof: Dictionary) -> bool:
	var selected := choice(q, a)
	if a["kind"] == "choice": selected = str(proof.get("choice", ""))
	var destinations: Dictionary = a.get("destination_by_choice", a.get("branch_objects", {}))
	if not destinations.is_empty():
		if not destinations.has(selected) or proof.get("destination", "") != destinations[selected]: return false
	if a["kind"] == "route":
		if not selected.is_empty() and proof.get("route", "") != selected: return false
		var points: Array = a.get("route_by_choice", {}).get(selected, a.get("route_waypoints", []))
		# 主线的逐物理步路线由 main_routes 记录索引；可选工程逐个保留登记物件ID。
		if a.get("chapter", "") == "" and not points.is_empty() and proof.get("visit_ids", []) != points: return false
	var barriers: Dictionary = a.get("obstacle_by_choice", {})
	if barriers.has(selected) and (proof.get("obstacle_key", "") != barriers[selected] or not proof.get("destroyed", false)): return false
	var consumes: String = str(a.get("consumes", a.get("consumes_quest_item", "")))
	if not consumes.is_empty():
		if proof.get("item", "") != consumes or not _has_quest_item(q, a["chain"], consumes, a["id"]): return false
	if a["kind"] == "ecology" and proof.get("outcome", "") == "hunt":
		var events: Array = proof.get("events", [])
		if events.is_empty(): return false
		for event: Dictionary in events:
			if event.get("kind", "") != "death" or event.get("cause", "") != "killed" or not event.get("instance_id", -1) in proof.get("unit_ids", []): return false
	if a.has("supply_id"):
		if proof.get("item", "") != a["supply_id"] or proof.get("destination", "") != a["object"]: return false
	if a["kind"] == "configure":
		for node: String in proof.get("nodes", []):
			if not ready(q, node.trim_suffix("_station") + ":s3"): return false
	return true

static func _has_quest_item(q: Dictionary, chain_id: String, item: String, except_action: String = "") -> bool:
	var obtained := false
	for s: Dictionary in Catalog.all_stages(int(q.get("seed", 0))):
		if s["chain"] != chain_id: continue
		for a: Dictionary in s["actions"]:
			if a["id"] == except_action or not q.get("quests", {}).get(s["id"], {}).get("evidence", {}).has(a["id"]): continue
			if a.get("quest_item", "") == item: obtained = true
			if a.get("consumes", a.get("consumes_quest_item", "")) == item: return false
	return obtained

static func _world_unlocked(q: Dictionary, chain_id: String, memo: Dictionary = {}) -> bool:
	if chain_id in ["world_migration", "world_decline"]:
		return not q.get("world_facts", {}).get("triggers", {}).get(chain_id, {}).is_empty()
	if chain_id == "world_relief":
		# 完成需求确认后，服务被使用也不会撤销已经获得的世界调查资格。
		if q.get("quests", {}).get(chain_id + ":s1", {}).get("accepted", false): return true
		# 第一章就在平原；历史目的地表可能重复，且不得把世界调查点当成新地形。
		var visited: Dictionary = {"plains": true} if chapter1_complete(q) else {}
		for terrain: Variant in q.get("travel", {}).get("visited", []):
			if str(terrain) in ["plains", "forest", "swamp", "hill", "snow", "lava"]: visited[str(terrain)] = true
		var needs: Dictionary = q.get("dynamic_runtime", {}).get("relief_needs", {})
		var stations: Array = []
		for id: String in ["world_relief:need_a", "world_relief:need_b"]:
			var need: Dictionary = needs.get(id, {})
			var station: String = str(need.get("station", ""))
			if need.is_empty() or need.get("resolved", true) or not q.get("services", {}).get(station, {}).get("enabled", false) or station in stations: return false
			stations.append(station)
		return visited.size() >= 3 and stations.size() == 2
	if chain_id == "world_watchnet":
		if not _chapter_complete(q, "watch_c6_lava", memo): return false
		var completed := 0
		for arc: Dictionary in Catalog.regional_arcs():
			if _ready(q, arc["id"] + ":s3", memo): completed += 1
		return completed >= 3
	return false

static func _regional_services() -> Array:
	return ["region_plains_station", "region_forest_station", "region_swamp_station", "region_hill_station", "region_snow_station", "region_lava_station"]

static func _position(value: Variant) -> Array:
	if not value is Array or value.size() != 2: return []
	for coordinate: Variant in value:
		if typeof(coordinate) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(coordinate)) or absf(float(coordinate)) > 10000000.0: return []
	return [float(value[0]), float(value[1])]

static func _unit_ids(value: Variant) -> Array:
	var out: Array = []
	if value is Array:
		for id: Variant in value.slice(0, 128):
			var number := _integer(id, -1)
			if number > 0 and not number in out: out.append(number)
	return out

static func _counts(value: Variant) -> Dictionary:
	var out: Dictionary = {}
	if not value is Dictionary: return out
	for key: Variant in value.keys().slice(0, 64):
		var number := _integer(value[key], -1)
		if key is String and key.length() <= 80 and number >= 0 and number <= 1000000: out[key] = number
	return out

static func _target(value: Variant, seed: int) -> Dictionary:
	if not value is Dictionary: return {}
	if value.has("seed") and _integer(value.get("seed"), -1) != seed: return {}
	var position := _position(value.get("target_position", value.get("position")))
	var ids := _unit_ids(value.get("unit_ids"))
	var region: String = str(value.get("region_id", "")).left(180)
	var species: String = str(value.get("species", "")).left(80)
	if position.is_empty() or ids.is_empty() or region.is_empty() or species.is_empty() or str(value.get("target_key", "")) != region + "|" + species: return {}
	return {"target_key": region + "|" + species, "region_id": region, "species": species, "unit_ids": ids,
		"target_position": position, "tick": maxi(0, _integer(value.get("tick"), 0))}

## Independent receipt: legacy corner counts never imply passage through a repaired opening.
## Completed action evidence stays compatible; only unfinished regional walks need this receipt.
static func regional_passage_proof(value: Variant, a: Dictionary, selected: String, seed: int, check_geometry := true) -> Dictionary:
	if not value is Dictionary or a.get("id", "") not in ["region_swamp:s3:walk", "region_hill:s3:walk"]: return {}
	var chain := str(a.get("chain", ""))
	var id := chain+":near_barrier" if selected=="near" else ("region_hill:shortcut_gate" if chain=="region_hill" and selected=="outer" else "")
	if id.is_empty() or _integer(value.get("seed"), -1) != seed or value.get("route") != selected or value.get("passage") != id: return {}
	var start := _position(value.get("from"))
	var finish := _position(value.get("to"))
	if start.is_empty() or finish.is_empty(): return {}
	var from := Vector2(start[0],start[1])
	var to := Vector2(finish[0],finish[1])
	if from.distance_to(to) > 350.0 or from.distance_to(to) < 0.001: return {}
	var receipt := {"seed":seed,"route":selected,"passage":id,"from":start,"to":finish}
	# GameState restores this ledger before configuring BiomeMap. Keep typed receipts
	# here; the runtime always revalidates them against the active seeded cells.
	if not check_geometry: return receipt
	if BiomeMap.current_seed() != seed: return {}
	var passage := CampaignLayout.regional_passage(chain.trim_prefix("region_"), selected)
	if passage.is_empty(): return {}
	var before: float = (from-passage.center).dot(passage.direction)
	var after: float = (to-passage.center).dot(passage.direction)
	if before > 0.0 or after < 0.0 or after-before < 0.001: return {}
	var crossed := from.lerp(to,-before/(after-before))
	if absf((crossed-passage.center).cross(passage.direction)) > float(passage.half_width): return {}
	return receipt

static func _restore_progress(q: Dictionary, raw: Dictionary) -> void:
	var main_routes: Dictionary = raw.get("main_routes", {}) if raw.get("main_routes") is Dictionary else {}
	var optional_routes: Dictionary = raw.get("optional_routes", {}) if raw.get("optional_routes") is Dictionary else {}
	var corners: Dictionary = raw.get("optional_route_steps", {}) if raw.get("optional_route_steps") is Dictionary else {}
	var optional_reanchor: Dictionary = raw.get("optional_route_reanchor", {}) if raw.get("optional_route_reanchor") is Dictionary else {}
	var passages: Dictionary = raw.get("optional_route_passages", {}) if raw.get("optional_route_passages") is Dictionary else {}
	for a: Dictionary in Catalog.actions(int(q.get("seed", 0))).values():
		if a["kind"] != "route" or not _can_record(q, a["stage"], a["id"], false): continue
		var selected := choice(q, a)
		var passage := regional_passage_proof(passages.get(a["id"]), a, selected, int(q.get("seed", 0)), false)
		if not passage.is_empty(): q["optional_route_passages"][a["id"]] = passage
		if a.get("chapter", "") != "":
			var progress: Variant = main_routes.get(a["id"])
			if not progress is Dictionary or progress.get("route") != selected or not progress.get("visited") is Array: continue
			var indices: Array = progress["visited"]
			if indices.size() > 5: continue
			var valid := true
			for i: int in range(indices.size()):
				if _integer(indices[i], -1) != i: valid = false
			if valid:
				q["main_routes"][a["id"]] = {"route": selected, "visited": indices.duplicate()}
				if _true(progress.get("needs_anchor")): q["main_routes"][a["id"]]["needs_anchor"] = true
		else:
			var points: Array = a.get("route_by_choice", {}).get(selected, a.get("route_waypoints", []))
			var count := _integer(corners.get(a["id"]), -1)
			var limit := int(a.get("route_corner_count_by_choice", {}).get(selected, 0))
			if a["id"] == "region_forest:s3:walk" and selected == "near" and q.get("optional_bindings", {}).has("region_forest"):
				limit = q["optional_bindings"]["region_forest"]["near_route"].size()
			if count >= 0 and count <= limit: q["optional_route_steps"][a["id"]] = count
			var visited: Variant = optional_routes.get(a["id"])
			if not visited is Array or visited.size() > points.size(): continue
			var valid := true
			for i: int in range(visited.size()):
				if visited[i] != points[i]: valid = false
			if valid:
				q["optional_routes"][a["id"]] = visited.duplicate()
				if _true(optional_reanchor.get(a["id"])) and (not visited.is_empty() or int(q["optional_route_steps"].get(a["id"], 0)) > 0):
					q["optional_route_reanchor"][a["id"]] = true
	var kills: Dictionary = raw.get("main_kills", {}) if raw.get("main_kills") is Dictionary else {}
	for species: String in ["牛头王", "熔岩龟王"]:
		var death: Variant = kills.get(species)
		if not death is Dictionary: continue
		var position := _position(death.get("position"))
		var id := _integer(death.get("instance_id"), -1)
		var tick := _integer(death.get("tick"), -1)
		if id <= 0 or tick < 0 or position.is_empty() or not _true(death.get("player_kill")) or not death.get("region_id") is String or death["region_id"].is_empty(): continue
		q["main_kills"][species] = {"instance_id": id, "region_id": death["region_id"].left(180), "position": position, "tick": tick, "player_kill": true}
	var targets: Dictionary = raw.get("optional_targets", {}) if raw.get("optional_targets") is Dictionary else {}
	for chain_id: String in ["side_hunter", "side_troll", "region_forest"]:
		var credit: Variant = targets.get(chain_id)
		if not credit is Dictionary: continue
		if chain_id == "side_troll" and not _can_record(q, "side_troll:s1", "side_troll:s1:challenge", false): continue
		if chain_id == "side_hunter" and q.get("quests", {}).get("side_hunter:s2", {}).get("choice", "") != "local": continue
		if chain_id == "region_forest" and q.get("quests", {}).get("region_forest:s2", {}).get("choice", "") != "near": continue
		var target: Dictionary = _target(credit.get("target", {}), int(q["seed"])) if chain_id == "side_troll" else {}
		if chain_id != "side_troll":
			for s: Dictionary in Catalog.chain(chain_id).get("steps", []):
				for proof: Dictionary in q.get("quests", {}).get(s["id"], {}).get("evidence", {}).values():
					var candidate := _target(proof, int(q["seed"]))
					if not candidate.is_empty(): target = candidate
		if target.is_empty(): continue
		var clean := {"kills": []}
		if chain_id == "side_troll": clean["target"] = target
		for event: Dictionary in Facts._events(credit.get("kills"), int(q["seed"]), 64):
			if event.get("kind") != "death" or event.get("cause") != "killed" or not event.get("instance_id") in target["unit_ids"] or event.get("species") != target["species"] or event.get("from_region") != target["region_id"]: continue
			var duplicate := false
			for existing: Dictionary in clean["kills"]:
				if existing["instance_id"] == event["instance_id"]: duplicate = true
			if not duplicate: clean["kills"].append(event)
		if chain_id == "region_forest" and _true(credit.get("ransack")) and credit.get("target_key") == target["target_key"]:
			clean["ransack"] = true
			clean["target_key"] = target["target_key"]
			clean["tick"] = maxi(0, _integer(credit.get("tick"), 0))
		q["optional_targets"][chain_id] = clean


static func _dynamic_state(value: Variant, seed: int) -> Dictionary:
	var out := {"known_objects": {}, "route_steps": {}, "relief_needs": {}, "bindings": {}}
	if not value is Dictionary: return out
	var allowed: Dictionary = {}
	var services: Array = []
	for a: Dictionary in Catalog.actions(seed).values():
		allowed[a["object"]] = true
		for id: String in a.get("puzzle_objects", []): allowed[id] = true
		for id: String in a.get("destination_by_choice", {}).values(): allowed[id] = true
		for id: String in a.get("route_waypoints", []): allowed[id] = true
		if a.has("service") and not a["service"] in services: services.append(a["service"])
	var known: Dictionary = value.get("known_objects", {}) if value.get("known_objects") is Dictionary else {}
	for id: String in allowed:
		var record: Variant = known.get(id)
		if not record is Dictionary: continue
		var position := _position(record.get("position"))
		var tick := _integer(record.get("tick"), -1)
		if not position.is_empty() and tick >= 0: out["known_objects"][id] = {"position": position, "tick": tick}
	var bindings: Dictionary = value.get("bindings", {}) if value.get("bindings") is Dictionary else {}
	for id: String in allowed:
		if not id.begins_with("random_nest:") and not (id.begins_with("random_migration:") and id.ends_with(":target")) and id not in ["world_migration:route_a", "world_migration:route_b", "world_migration:observer", "world_decline:last_site", "world_decline:evidence_post", "world_decline:warning_sign"]: continue
		var binding: Variant = bindings.get(id)
		if not binding is Dictionary: continue
		var position := _position(binding.get("position"))
		var tick := _integer(binding.get("tick"), -1)
		if not position.is_empty() and tick >= 0 and binding.get("region_id") is String and not binding["region_id"].is_empty():
			out["bindings"][id] = {"position": position, "region_id": binding["region_id"].left(180), "tick": tick}
	var steps: Dictionary = value.get("route_steps", {}) if value.get("route_steps") is Dictionary else {}
	for a: Dictionary in Catalog.actions(seed).values():
		if a["kind"] != "route" or not a["stage"].begins_with("random_"): continue
		var count := _integer(steps.get(a["id"]), -1)
		var limit: int = a.get("route_waypoints", []).size()
		if count >= 0 and count <= limit: out["route_steps"][a["id"]] = count
	var needs: Dictionary = value.get("relief_needs", {}) if value.get("relief_needs") is Dictionary else {}
	for id: String in ["world_relief:need_a", "world_relief:need_b"]:
		var need: Variant = needs.get(id)
		if not need is Dictionary or _integer(need.get("seed"), -1) != seed: continue
		var tick := _integer(need.get("tick"), -1)
		if tick < 0 or not need.get("station") is String or not need["station"] in services or not need.get("need") is String or not need["need"] in ["supply", "rescue"] or typeof(need.get("resolved")) != TYPE_BOOL: continue
		out["relief_needs"][id] = {"seed": seed, "tick": tick, "station": need["station"], "need": need["need"], "resolved": need["resolved"]}
	return out


## 远征落点仅记录已经到访的真实世界位置；它本身永不赋予线路资格。
static func _arrival_position(value: Variant) -> Array:
	if not value is Array or value.size() != 2: return []
	for coordinate: Variant in value:
		if typeof(coordinate) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(coordinate)) or float(coordinate) < 0.0 or float(coordinate) > 800000.0: return []
	return [float(value[0]), float(value[1])]


## 补给付款与站点可用性分账：站点动作损坏可暂时失效，已领取物资永不重新发放。
static func _service_receipts(raw: Dictionary, seed: int) -> Dictionary:
	var out: Dictionary = {}
	var receipts: Dictionary = raw.get("service_receipts", {}) if raw.get("service_receipts") is Dictionary else {}
	var legacy: Dictionary = raw.get("services", {}) if raw.get("services") is Dictionary else {}
	for a: Dictionary in Catalog.actions(seed).values():
		if not a.has("service"): continue
		var id: String = a["service"]
		if _claimed_value(receipts.get(id)) or _claimed_value(legacy.get(id)):
			out[id] = {"claimed": true, "status": "claimed"}
	return out

static func _claimed_value(value: Variant) -> bool:
	if typeof(value) == TYPE_BOOL: return value
	if not value is Dictionary: return false
	return _true(value.get("claimed")) or str(value.get("status", "")) == "claimed"

static func service_claimed(q: Dictionary, service_id: String) -> bool:
	return _claimed_value(q.get("service_receipts", {}).get(service_id)) or _claimed_value(q.get("services", {}).get(service_id))

## 必须与库存增加处于同一奖励事务；满包、取消或保存回滚时不能独立提交本方法的结果。
static func mark_service_claimed(q: Dictionary, service_id: String) -> bool:
	if service_claimed(q, service_id) or not q.get("services", {}).get(service_id, {}).get("enabled", false): return false
	var known := false
	for a: Dictionary in Catalog.actions(int(q.get("seed", 0))).values():
		if a.get("service", "") == service_id: known = true
	if not known: return false
	if not q.has("service_receipts"): q["service_receipts"] = {}
	q["service_receipts"][service_id] = {"claimed": true, "status": "claimed"}
	q["services"][service_id]["claimed"] = true
	q["services"][service_id]["status"] = "claimed"
	return true


static func _optional_bindings(value: Variant, seed: int) -> Dictionary:
	if not value is Dictionary: return {}
	var raw: Variant = value.get("region_forest")
	if not raw is Dictionary or _integer(raw.get("seed"),-1)!=seed or raw.get("source","")!="region_forest:guide": return {}
	if not raw.get("target_key") is String or raw["target_key"].get_slice_count("|")!=2: return {}
	var camp := _position(raw.get("camp"))
	if camp.is_empty() or not raw.get("positions") is Dictionary or not raw.get("near_route") is Array: return {}
	var positions := {}
	var center := Vector2(float(camp[0]),float(camp[1]))
	for id: String in ["region_forest:survey_a","region_forest:work_near","region_forest:choice"]:
		var point := _position(raw["positions"].get(id))
		if point.is_empty() or Vector2(float(point[0]),float(point[1])).distance_to(center)>512.0: return {}
		positions[id]=point
	var route: Array = []
	if raw["near_route"].size()<2 or raw["near_route"].size()>128: return {}
	for item: Variant in raw["near_route"]:
		var point := _position(item)
		if point.is_empty() or Vector2(float(point[0]),float(point[1])).distance_to(center)>7200.0: return {}
		route.append(point)
	if route[0] != positions["region_forest:work_near"]: return {}
	return {"region_forest":{"seed":seed,"source":"region_forest:guide","target_key":raw["target_key"].left(180),"camp":camp,"positions":positions,"near_route":route}}
