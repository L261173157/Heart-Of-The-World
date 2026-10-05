## 战役的纯数据账本。真实行为由表现层验证；此处只接受具名、同种子、顺序完整的证据。
## 接单预算、任务物件与支付收据独立保存。证据损坏不能造出结局，也不能重开已付奖励。
class_name CampaignQuestData
extends RefCounted

const Catalog := preload("res://scripts/main/campaign_catalog.gd")
const Outpost := preload("res://scripts/main/outpost_quest_data.gd")
const Economy := preload("res://scripts/ecology/economy_math.gd")
const ID := "campaign_watch_v1"
const VERSION := 1
const MAX_LEVEL := 100
const MAX_AMOUNT := 100000
## 此版本抄录批准时的 EconomyMath 预算，终身不随通用经济平衡改写。
## 新战役平衡必须新增 v2 规则并提升 REWARD_VERSION；绝不可修改以下 v1 常量。
const REWARD_VERSION := 1
const REWARD_V1 := {"gold_base": 12, "gold_target": 6, "gold_level": 3, "xp_base": 20, "xp_target": 8}

static func create(seed: int) -> Dictionary:
	return {"id": ID, "version": VERSION, "seed": seed, "chapter1_proof": {}, "chapters": {},
		"quests": {}, "random_used": {}, "active_random": "", "history": [], "paused_chains": [],
		"puzzle_progress": {}, "travel": {"visited": [], "unlocked": ["plains"], "arrivals": {}}, "services": {}, "flags": {}, "ending": ""}

static func sanitize(value: Variant, seed: int) -> Dictionary:
	if not value is Dictionary or value.get("id") != ID or _integer(value.get("version"), -1) != VERSION or _integer(value.get("seed"), -1) != seed:
		return {}
	var raw: Dictionary = value
	var q := create(seed)
	authorize_chapter1(q, raw.get("chapter1_proof", {}))
	var contracts: Dictionary = raw.get("chapters", {}) if raw.get("chapters") is Dictionary else {}
	for chapter: Dictionary in Catalog.main_chapters():
		var id: String = chapter["id"]
		var saved: Variant = contracts.get(id)
		if not saved is Dictionary: continue
		var c: Dictionary = _contract(saved)
		if not c.is_empty(): q["chapters"][id] = c
	var saved_quests: Dictionary = raw.get("quests", {}) if raw.get("quests") is Dictionary else {}
	# 固定目录顺序保证跨段前置先被验证；不信任保存的 completed/active 等派生状态。
	for s: Dictionary in Catalog.all_stages():
		var sid: String = s["id"]
		var saved: Variant = saved_quests.get(sid)
		if not saved is Dictionary: continue
		var state := _stage_state()
		state["receipt"] = _receipt(saved.get("receipt", {}))
		var contract: Dictionary = q["chapters"].get(s["chapter"], {}) if s["family"] == "main" else _contract(saved.get("contract", {}))
		if not contract.is_empty():
			state["accepted"] = true
			state["contract"] = contract.duplicate(true)
			state["reward"] = _stage_reward(s, contract)
		q["quests"][sid] = state
		if not state["accepted"] or not _stage_unlocked(q, s): continue
		var evidence: Dictionary = saved.get("evidence", {}) if saved.get("evidence") is Dictionary else {}
		for a: Dictionary in s["actions"]:
			var proof: Dictionary = _proof(evidence.get(a["id"]), a, seed)
			if not proof.is_empty() and _can_record(q, sid, a["id"], false):
				state["evidence"][a["id"]] = proof
				if a["kind"] == "choice": state["choice"] = proof.get("choice", "")
	# 使用次数是独立的不可逆占位记录；放弃、读档和坏证据都不能把名额退回。
	var used: Dictionary = raw.get("random_used", {}) if raw.get("random_used") is Dictionary else {}
	for s: Dictionary in Catalog.all_stages():
		if s["family"] != "random": continue
		var sid: String = s["id"]
		var state: Dictionary = q["quests"].get(sid, {})
		if _true(used.get(sid)) or state.get("accepted", false) or state.get("receipt", {}).get("paid", false): q["random_used"][sid] = true
	var active: String = str(raw.get("active_random", ""))
	if q["random_used"].has(active) and q["quests"].get(active, {}).get("accepted", false) and not paid(q, active): q["active_random"] = active
	# 缺失 active_random 只恢复唯一最早未支付实例，绝不产生第二张随机合同。
	if q["active_random"] == "":
		for s: Dictionary in Catalog.all_stages():
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
	var raw: Dictionary = evidence.duplicate(true)
	raw["action_id"] = action_id
	raw["seed"] = q["seed"]
	raw["object"] = a["object"]
	raw["kind"] = a["kind"]
	if raw.get("position") is Vector2: raw["position"] = [raw["position"].x, raw["position"].y]
	var proof := _proof(raw, a, int(q["seed"]))
	if proof.is_empty(): return false
	q["quests"][stage_id]["evidence"][action_id] = proof
	if a["kind"] == "puzzle": q["puzzle_progress"].erase(action_id)
	if a["kind"] == "choice": q["quests"][stage_id]["choice"] = proof["choice"]
	_refresh_derived(q)
	if ready(q, stage_id) and not stage_id in q["history"]: q["history"].append(stage_id)
	return true

static func ready(q: Dictionary, stage_id: String) -> bool:
	var s := Catalog.stage(stage_id)
	var state: Dictionary = q.get("quests", {}).get(stage_id, {})
	if s.is_empty() or not state.get("accepted", false) or not _stage_unlocked(q, s): return false
	for a: Dictionary in s["actions"]:
		if state.get("evidence", {}).has(a["id"]):
			if _proof(state["evidence"][a["id"]], a, int(q.get("seed", -1))).is_empty(): return false
			for dependency: String in a.get("requires", []):
				if not state["evidence"].has(dependency): return false
	for required: String in s["required"]:
		if not state.get("evidence", {}).has(required): return false
	for alternatives: Array in s.get("required_any", []):
		var found := false
		for required: String in alternatives:
			if state.get("evidence", {}).has(required): found = true
		if not found: return false
	return true

static func chapter_complete(q: Dictionary, chapter_id: String) -> bool:
	var chapter := Catalog.chapter(chapter_id)
	if chapter.is_empty(): return false
	for s: Dictionary in chapter["steps"]:
		if not ready(q, s["id"]): return false
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
	for s: Dictionary in Catalog.all_stages():
		var state: Dictionary = q.get("quests", {}).get(s["id"], {})
		if state.get("accepted", false) and not paid(q, s["id"]) and _stage_unlocked(q, s) and not s["chain"] in q.get("paused_chains", []):
			if s["family"] != "random" or q.get("active_random", "") == s["id"]: result.append(s["id"])
	return result

static func next_random(q: Dictionary, template_id: String) -> String:
	for s: Dictionary in Catalog.all_stages():
		if s["family"] == "random" and s.get("template", "") == template_id and not q.get("random_used", {}).has(s["id"]): return s["id"]
	return ""

static func _chapter_unlocked(q: Dictionary, chapter: Dictionary) -> bool:
	if int(chapter["number"]) == 2: return chapter1_complete(q)
	for previous: Dictionary in Catalog.main_chapters():
		if int(previous["number"]) == int(chapter["number"]) - 1: return chapter_complete(q, previous["id"])
	return false

static func _stage_unlocked(q: Dictionary, s: Dictionary) -> bool:
	if s["family"] == "main" and not _chapter_unlocked(q, Catalog.chapter(s["chapter"])): return false
	if s.get("previous", "") != "" and not ready(q, s["previous"]): return false
	var chain := Catalog.chain(s["chain"])
	var unlock: String = str(s.get("unlock_after", chain.get("unlock_after", "")))
	if unlock == "chapter1": return chapter1_complete(q)
	if unlock != "" and not chapter_complete(q, unlock): return false
	return true

static func reward_budget_v1(target: int, level: int) -> Dictionary:
	return {"gold": int(REWARD_V1["gold_base"]) + target * int(REWARD_V1["gold_target"]) + level * int(REWARD_V1["gold_level"]),
		"xp": int(REWARD_V1["xp_base"]) + target * int(REWARD_V1["xp_target"])}

static func _new_contract(level: int, target: int, family: String) -> Dictionary:
	var frozen_level := clampi(level, 1, MAX_LEVEL)
	var budget := reward_budget_v1(target, frozen_level)
	return {"accepted": true, "version": REWARD_VERSION, "level": frozen_level, "gold": budget["gold"],
		"xp": budget["xp"], "family": family}

static func _contract(value: Variant) -> Dictionary:
	if not value is Dictionary or not _true(value.get("accepted")) or _integer(value.get("version"), -1) != 1: return {}
	var level := _integer(value.get("level"), -1)
	var gold := _integer(value.get("gold"), -1)
	var xp := _integer(value.get("xp"), -1)
	var family: String = str(value.get("family", ""))
	if level < 1 or level > MAX_LEVEL or gold < 0 or gold > MAX_AMOUNT or xp < 0 or xp > MAX_AMOUNT or family not in ["main", "side", "regional", "random", "world"]: return {}
	# 第一批只有 C2：旧格式没有 target 字段，固定按目标6核验，不扩展原合同形状。
	if family != "main" or (value.has("target") and _integer(value.get("target"), -1) != 6): return {}
	var promised := reward_budget_v1(6, level)
	if gold != promised["gold"] or xp != promised["xp"]: return {}
	return {"accepted": true, "version": 1, "level": level, "gold": gold, "xp": xp, "family": family}

static func _stage_reward(s: Dictionary, contract: Dictionary) -> Dictionary:
	var gold: int = contract["gold"]
	var xp: int = contract["xp"]
	var bonus := ""
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
	var was_paid: bool = _true(raw.get("paid")) or raw.get("status") == "paid"
	return {"paid": was_paid, "status": "paid" if was_paid else "pending", "gold": clampi(_integer(raw.get("gold"), 0), 0, MAX_AMOUNT),
		"xp": clampi(_integer(raw.get("xp"), 0), 0, MAX_AMOUNT), "bonus": "onigiri" if raw.get("bonus") == "onigiri" else ""}

static func _proof(value: Variant, action: Dictionary, seed: int) -> Dictionary:
	if not value is Dictionary: return {}
	var raw: Dictionary = value
	if raw.get("action_id") != action["id"] or _integer(raw.get("seed"), -1) != seed or raw.get("object") != action["object"] or raw.get("kind") != action["kind"]: return {}
	var tick := _integer(raw.get("tick"), -1)
	var position: Variant = raw.get("position")
	if tick < 0 or not position is Array or position.size() != 2: return {}
	for coordinate: Variant in position:
		if typeof(coordinate) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(coordinate)) or absf(float(coordinate)) > 10000000.0: return {}
	var p := {"action_id": action["id"], "seed": seed, "object": action["object"], "kind": action["kind"], "tick": tick,
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
		"ecology":
			var outcome: String = str(raw.get("outcome", ""))
			if outcome not in ["hunt", "ransack", "survey"] or not _true(raw.get("verified")): return {}
			p["outcome"] = outcome
			p["verified"] = true
	for key: String in ["region_id", "species", "target_key", "witness", "outcome", "item", "reason", "destination"]:
		if raw.get(key) is String: p[key] = raw[key].left(300)
	return p

static func _integer(value: Variant, fallback: int) -> int:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or float(value) != floor(float(value)): return fallback
	return int(value)

static func _true(value: Variant) -> bool:
	return typeof(value) == TYPE_BOOL and value


## 只恢复合法谜题前缀；未知机关、越过前置的前缀和已完成机关的残余输入都丢弃。
static func _restore_runtime_state(q: Dictionary, raw: Dictionary) -> void:
	var progress: Dictionary = raw.get("puzzle_progress", {}) if raw.get("puzzle_progress") is Dictionary else {}
	for a: Dictionary in Catalog.actions().values():
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
	_refresh_derived(q)
	var travel: Dictionary = raw.get("travel", {}) if raw.get("travel") is Dictionary else {}
	if travel.get("visited") is Array:
		for terrain: Variant in travel["visited"]:
			if terrain is String and (terrain in q["travel"]["unlocked"] or terrain == "home" or (terrain == "side_troll" and chapter_complete(q, "watch_c2_forest"))) and not terrain in q["travel"]["visited"]: q["travel"]["visited"].append(terrain)
	if not q["travel"].has("arrivals"): q["travel"]["arrivals"] = {}
	if travel.get("arrivals") is Dictionary:
		for terrain: String in q["travel"]["visited"]:
			if terrain not in ["home", "forest", "swamp", "hill", "snow", "lava", "side_troll"]: continue
			var position := _arrival_position(travel["arrivals"].get(terrain))
			if not position.is_empty(): q["travel"]["arrivals"][terrain] = position
	var services: Dictionary = raw.get("services", {}) if raw.get("services") is Dictionary else {}
	for id: String in q["services"]:
		var prior: Variant = services.get(id)
		if prior is Dictionary and (_true(prior.get("claimed")) or prior.get("status") == "claimed"):
			q["services"][id]["claimed"] = true
			q["services"][id]["status"] = "claimed"

static func _refresh_derived(q: Dictionary) -> void:
	q["flags"] = {}
	q["ending"] = ""
	if not q.has("services"): q["services"] = {}
	if not q.has("travel"): q["travel"] = {"visited": [], "unlocked": []}
	q["travel"]["unlocked"] = ["plains"]
	if chapter1_complete(q): q["travel"]["unlocked"].append("forest")
	for chapter: Dictionary in Catalog.main_chapters():
		if chapter_complete(q, chapter["id"]):
			for next: Dictionary in Catalog.main_chapters():
				if int(next["number"]) == int(chapter["number"]) + 1: q["travel"]["unlocked"].append(next["terrain"])
	for s: Dictionary in Catalog.all_stages():
		var state: Dictionary = q.get("quests", {}).get(s["id"], {})
		for a: Dictionary in s["actions"]:
			if not state.get("evidence", {}).has(a["id"]): continue
			q["flags"][a["id"]] = true
			if a.has("opens"): q["flags"][a["opens"]] = true
			if a.has("service"):
				var service: String = a["service"]
				if not q["services"].has(service): q["services"][service] = {"enabled": true, "claimed": false, "status": "available", "stock_item": "onigiri"}
			if a.get("ending", false) and ready(q, s["id"]): q["ending"] = state.get("choice", "")


## 远征落点仅记录已经到访的真实世界位置；它本身永不赋予线路资格。
static func _arrival_position(value: Variant) -> Array:
	if not value is Array or value.size() != 2: return []
	for coordinate: Variant in value:
		if typeof(coordinate) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(coordinate)) or float(coordinate) < 0.0 or float(coordinate) > 800000.0: return []
	return [float(value[0]), float(value[1])]
