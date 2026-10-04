## 「失联的前哨」独立、版本化的证据/支付账本。任务物件从不进入可交易库存。
class_name OutpostQuestData
extends RefCounted

const ID := "lost_outpost_v1"
const TITLE := "失联的前哨"
const VERSION := 1
const Legacy := preload("res://scripts/main/camp_quest_data.gd")
const EVIDENCE := ["patrol_read", "entrance_read", "wounded_found", "supply_read", "aid_taken", "tools_taken", "rescued", "site_surveyed", "signpost_repaired", "next_clue_received"]
const RECEIPTS := ["investigation", "rescue", "restoration"]
## v1合同按当时EconomyMath.bounty_gold(4,1)=39/bounty_xp(3)=44拆分，后续平衡不可改旧承诺。
const REWARDS_V1 := {"investigation": {"gold": 6, "xp": 8, "bonus": ""},
	"rescue": {"gold": 9, "xp": 12, "bonus": ""},
	"restoration": {"gold": 24, "xp": 24, "bonus": "onigiri"}}

static func valid_legacy(value: Variant) -> bool:
	var old := Legacy.sanitize(value)
	return not old.is_empty() and (old.get("paid", false) or not old.get("target", {}).is_empty())

static func legacy_result(value: Variant) -> bool:
	var old := Legacy.sanitize(value)
	return valid_legacy(old) and (old.get("paid", false) or Legacy.has_result(old))

static func create(old: Dictionary = {}) -> Dictionary:
	var q := sanitize({"id": ID, "active": true, "legacy_reserved": valid_legacy(old), "legacy_contract": Legacy.sanitize(old)}, old)
	return q

static func sanitize(value: Variant, old: Dictionary = {}) -> Dictionary:
	if not value is Dictionary or str(value.get("id", "")) != ID:
		return {}
	var raw: Dictionary = value
	var q := {"id": ID, "version": VERSION, "active": false, "stage": "investigation", "evidence": {},
		"receipts": {}, "legacy_contract": {}, "legacy_reserved": false, "legacy_result": false, "target": {}, "choice": "", "outcome": "",
		"kills": [], "compact_kills": [], "compact_sites": {}, "ransacks": [], "surveys": [], "history": [], "survey_confirmed": false,
		"next_clue": "", "last_summary": false}
	for key: String in ["active", "last_summary", "survey_confirmed"]:
		q[key] = _true(raw.get(key))
	# 原委托就是奖励保管凭据；不能凭一个孤立布尔让旧单丢失承诺或让新链再付。
	var proof := Legacy.sanitize(raw.get("legacy_contract", {}))
	var current := Legacy.sanitize(old)
	# 不可逆支付证明优先于矛盾的较旧未付副本，不能因局部损坏重开付款。
	q["legacy_contract"] = proof if proof.get("paid", false) and not current.get("paid", false) else (current if valid_legacy(current) else proof)
	q["legacy_reserved"] = valid_legacy(q["legacy_contract"])
	q["legacy_result"] = q["legacy_reserved"] and (legacy_result(old) or legacy_result(proof))
	var evidence: Dictionary = raw.get("evidence", {}) if raw.get("evidence") is Dictionary else {}
	for key: String in EVIDENCE:
		q["evidence"][key] = _true(evidence.get(key))
	# 独立动作必须有前置证据；损坏的终态字段不能凭空救人或解锁检查点。
	for chain: Array in [["entrance_read", "patrol_read"], ["wounded_found", "entrance_read"], ["supply_read", "wounded_found"], ["aid_taken", "supply_read"], ["tools_taken", "supply_read"], ["rescued", "aid_taken"]]:
		q["evidence"][chain[0]] = q["evidence"][chain[0]] and q["evidence"][chain[1]]
	q["target"] = target_data(raw.get("target", {}))
	q["choice"] = str(raw.get("choice", "")) if str(raw.get("choice", "")) in ["hunt", "ransack"] else ""
	q["outcome"] = str(raw.get("outcome", "")) if str(raw.get("outcome", "")) in ["hunt", "ransack", "survey", "legacy"] else ""
	if raw.get("kills") is Array:
		for id: Variant in raw["kills"].slice(0, 256):
			if typeof(id) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(id)) and float(id) == floor(float(id)) and int(id) > 0 and not int(id) in q["kills"]:
				q["kills"].append(int(id))
	if raw.get("compact_kills") is Array:
		for id: Variant in raw["compact_kills"].slice(0, 256):
			if typeof(id) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(id)) and float(id) == floor(float(id)) and int(id) in q["kills"] and not int(id) in q["compact_kills"]:
				q["compact_kills"].append(int(id))
	var compact_sites: Dictionary = raw.get("compact_sites", {}) if raw.get("compact_sites") is Dictionary else {}
	for id: int in q["compact_kills"]:
		var site: Variant = compact_sites.get(str(id))
		if not site is Dictionary or not site.get("key") is String: continue
		var pos: Variant = site.get("pos")
		if not pos is Array or pos.size() != 2: continue
		if typeof(pos[0]) not in [TYPE_INT, TYPE_FLOAT] or typeof(pos[1]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(pos[0])) or not is_finite(float(pos[1])): continue
		q["compact_sites"][str(id)] = {"key": str(site["key"]).left(300), "pos": [float(pos[0]), float(pos[1])]}
	for key: String in ["ransacks", "surveys", "history"]:
		if raw.get(key) is Array:
			for entry: Variant in raw[key].slice(0, 128):
				if entry is String and not entry.left(300) in q[key]:
					q[key].append(entry.left(300))
	q["evidence"]["site_surveyed"] = q["evidence"]["site_surveyed"] and q["evidence"]["rescued"] and q["evidence"]["tools_taken"]
	q["survey_confirmed"] = q["survey_confirmed"] and q["evidence"]["site_surveyed"]
	if not has_ecology_result(q):
		q["outcome"] = ""
	q["evidence"]["signpost_repaired"] = q["evidence"]["signpost_repaired"] and has_ecology_result(q) and rescue_done(q)
	q["evidence"]["next_clue_received"] = q["evidence"]["next_clue_received"] and q["evidence"]["signpost_repaired"]
	var receipts: Dictionary = raw.get("receipts", {}) if raw.get("receipts") is Dictionary else {}
	for stage: String in RECEIPTS:
		var r: Dictionary = receipts.get(stage, {}) if receipts.get(stage) is Dictionary else {}
		# 支付收据不可因动作字段受损而重开；坏数额收敛为0，不能复付。
		q["receipts"][stage] = {"paid": _true(r.get("paid")) or str(r.get("status", "")) == "paid",
			"status": "paid" if _true(r.get("paid")) or str(r.get("status", "")) == "paid" else "pending",
			"gold": _amount(r.get("gold")), "xp": _amount(r.get("xp")),
			"bonus": "onigiri" if str(r.get("bonus", "")) == "onigiri" else "",
			"legacy_reserved": q["legacy_reserved"]}
	q["next_clue"] = str(raw.get("next_clue", "")).left(300)
	refresh_stage(q)
	return q

static func investigation_done(q: Dictionary) -> bool:
	return q.get("evidence", {}).get("patrol_read", false) and q.get("evidence", {}).get("entrance_read", false)

static func rescue_done(q: Dictionary) -> bool:
	var e: Dictionary = q.get("evidence", {})
	return investigation_done(q) and e.get("wounded_found", false) and e.get("supply_read", false) and e.get("aid_taken", false) and e.get("tools_taken", false) and e.get("rescued", false)

static func has_ecology_result(q: Dictionary) -> bool:
	if not rescue_done(q):
		return false
	if q.get("legacy_reserved", false) and q.get("legacy_result", false):
		return true
	if not q.get("evidence", {}).get("site_surveyed", false):
		return false
	if q.get("outcome", "") == "survey":
		return q.get("survey_confirmed", false)
	var t: Dictionary = q.get("target", {})
	if t.is_empty() or not t.get("key", "") in q.get("surveys", []):
		return false
	if q.get("outcome", "") == "hunt":
		return q.get("kills", []).size() >= 2
	if q.get("outcome", "") == "ransack":
		return t["key"] in q.get("ransacks", [])
	return false

static func refresh_stage(q: Dictionary) -> void:
	if not investigation_done(q): q["stage"] = "investigation"
	elif not rescue_done(q): q["stage"] = "rescue"
	elif not has_ecology_result(q): q["stage"] = "ecology"
	elif not q.get("evidence", {}).get("signpost_repaired", false): q["stage"] = "repair"
	elif not q.get("receipts", {}).get("restoration", {}).get("paid", false): q["stage"] = "claim"
	else:
		q["stage"] = "completed"
		q["active"] = false

static func reward(stage: String, reserved: bool) -> Dictionary:
	if reserved:
		return {"gold": 0, "xp": 0, "bonus": ""}
	return REWARDS_V1.get(stage, {"gold": 0, "xp": 0, "bonus": ""}).duplicate(true)

static func _true(value: Variant) -> bool:
	return typeof(value) == TYPE_BOOL and value

static func _amount(value: Variant) -> int:
	return clampi(int(value), 0, 100000) if typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) else 0

## 前哨独立保存实名目标；旧营地消毒器有意不接受这些新增字段。
static func target_data(value: Variant) -> Dictionary:
	var target := Legacy._target(value)
	if target.is_empty(): return target
	target["target_ids"] = []
	if value.get("target_ids") is Array:
		for id: Variant in value["target_ids"].slice(0, 128):
			if typeof(id) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(id)) and float(id) == floor(float(id)) and int(id) > 0 and not int(id) in target["target_ids"]:
				target["target_ids"].append(int(id))
	return target
