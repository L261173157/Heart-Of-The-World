## 营地试点的独立历史账本。消毒不引用场景树，不迁移或改写旧委托。
class_name CampQuestData
extends RefCounted

const ID := "camp_ecology_v1"
const LANDMARK := "camp_ecology"
const TITLE := "营地外的动静"
const REWARD_GOLD := 39
const REWARD_XP := 44
const REWARD_BONUS := "onigiri"
const STAGES := ["investigate", "choose", "act", "return", "completed"]

static func sanitize(value: Variant) -> Dictionary:
	if not value is Dictionary or value.is_empty():
		return {}
	var raw: Dictionary = value
	if str(raw.get("id", "")) != ID:
		return {}
	var out := {"id": ID, "version": 1, "stage": "investigate", "active": false,
		"paid": false, "last_summary": false, "paid_gold": 0, "paid_xp": 0, "investigated": false, "choice": "", "outcome": "",
		"target": {}, "kills": [], "ransacks": [], "surveys": [], "history": [],
		"gold": REWARD_GOLD, "xp": REWARD_XP, "bonus": REWARD_BONUS, "next_clue": ""}
	for key: String in ["active", "paid", "last_summary", "investigated"]:
		out[key] = typeof(raw.get(key)) == TYPE_BOOL and bool(raw[key])
	var stage := str(raw.get("stage", "investigate"))
	out["stage"] = stage if stage in STAGES else "investigate"
	for key: String in ["choice", "outcome"]:
		var allowed := ["", "hunt", "ransack"] if key == "choice" else ["", "hunt", "ransack", "survey"]
		out[key] = str(raw.get(key, "")) if str(raw.get(key, "")) in allowed else ""
	for key: String in ["gold", "xp", "paid_gold", "paid_xp"]:
		if typeof(raw.get(key)) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(raw[key])):
			out[key] = clampi(int(raw[key]), 0, 100000)
	out["bonus"] = str(raw.get("bonus", "onigiri")) if EconomyMath.knows_item(str(raw.get("bonus", "onigiri"))) else ""
	out["next_clue"] = str(raw.get("next_clue", "")).left(300)
	out["target"] = _target(raw.get("target", {}))
	if raw.get("kills") is Array:
		for id: Variant in raw["kills"]:
			if typeof(id) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(id)) and float(id) == floor(float(id)) and int(id) > 0 and not int(id) in out["kills"]:
				out["kills"].append(int(id))
	for key: String in ["ransacks", "surveys", "history"]:
		if raw.get(key) is Array:
			for entry: Variant in raw[key].slice(0, 128):
				if entry is String:
					out[key].append(entry.left(300))
	# 已记录的到场证据可修复单个损坏布尔字段，不清空同一账本的有效历史。
	if typeof(raw.get("investigated")) != TYPE_BOOL and not out["target"].is_empty():
		out["investigated"] = str(out["target"]["key"]) in out["surveys"]
	# completed 只在已支付时写入，是独立的终态收据。paid 损坏也不能重开付款。
	if out["paid"] or out["stage"] == "completed":
		out["paid"] = true
		out["stage"] = "completed"
		out["active"] = false
	elif out["target"].is_empty() or (out["stage"] in ["choose", "act", "return"] and (not out["investigated"] or not str(out["target"].get("key", "")) in out["surveys"])):
		out["stage"] = "investigate"
		out["investigated"] = false
		out["outcome"] = ""
	elif out["stage"] == "return" and not has_result(out):
		out["stage"] = "act" if out["choice"] != "" else "choose"
		out["outcome"] = ""
	return out

static func _target(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var raw: Dictionary = value
	var pos: Variant = raw.get("pos")
	if not pos is Array or pos.size() != 2:
		return {}
	for component: Variant in pos:
		if not typeof(component) in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(component)):
			return {}
	if not raw.get("region_id") is String or not raw.get("species") is String:
		return {}
	var region := str(raw.get("region_id", ""))
	var species := SpeciesCatalog.migrate_name(str(raw.get("species", "")))
	if region.is_empty() or species.is_empty():
		return {}
	return {"region_id": region, "species": species, "pos": [float(pos[0]), float(pos[1])],
		"key": region + "|" + species, "need": 2,
		"kill_start": maxi(0, _integer(raw.get("kill_start"), 0))}

static func _integer(value: Variant, fallback: int) -> int:
	return int(value) if typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) else fallback

## 返回阶段必须有对应到场与实际行动证据；仅布尔标志不能造出领奖资格。
static func has_result(q: Dictionary) -> bool:
	var t: Dictionary = q.get("target", {})
	if t.is_empty() or not q.get("investigated", false) or not str(t.get("key", "")) in q.get("surveys", []):
		return false
	match str(q.get("outcome", "")):
		"hunt": return q.get("kills", []).size() >= int(t.get("need", 2))
		"ransack": return str(t.get("key", "")) in q.get("ransacks", [])
		"survey": return true
	return false
