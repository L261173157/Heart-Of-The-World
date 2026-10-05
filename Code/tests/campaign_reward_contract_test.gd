## 预算合同单测：只测试存档/纯逻辑，不声称真实场景行动或经济试玩完成。
extends SceneTree
const Data := preload("res://scripts/main/campaign_quest_data.gd")
const Catalog := preload("res://scripts/main/campaign_catalog.gd")
var checks := 0
var failures := 0
func _initialize() -> void:
	for target: int in range(2, 11):
		for level: int in [1, 3, 17, 50, 100]:
			var frozen := Data.reward_budget_v1(target, level)
			_check(frozen["gold"] == Data.Economy.bounty_gold(target, level) and frozen["xp"] == Data.Economy.bounty_xp(target), "v1金额对应当前获批经济；将来改平衡需新增预算版本")
	var q := Data.create(5544)
	var e: Dictionary = {}
	for key: String in Data.Outpost.EVIDENCE: e[key] = true
	Data.authorize_chapter1(q, {"id": "lost_outpost_v1", "evidence": e, "outcome": "survey", "survey_confirmed": true})
	_check(Data.accept_chapter(q, "watch_c2_forest", 3), "接取C2冻结预算")
	var original: Dictionary = q["chapters"]["watch_c2_forest"].duplicate(true)
	var clean := Data.sanitize(JSON.parse_string(JSON.stringify(q)), 5544)
	_check(clean["chapters"]["watch_c2_forest"] == original, "正常合同形状与金额不变")
	var legacy := q.duplicate(true)
	legacy["chapters"]["watch_c2_forest"].erase("target")
	var legacy_clean := Data.sanitize(legacy, 5544)
	_check(legacy_clean["chapters"].has("watch_c2_forest") and legacy_clean["chapters"]["watch_c2_forest"]["gold"] == original["gold"], "没有target的原C2合同保留金额")
	for field: String in ["gold", "xp", "level", "target"]:
		var bad := q.duplicate(true)
		bad["chapters"]["watch_c2_forest"][field] = 9999 if field in ["gold", "xp"] else (4 if field == "level" else 7)
		bad["quests"]["watch_c2_forest:s4"]["receipt"] = {"paid": true, "status": "paid", "gold": 20, "xp": 24, "bonus": "onigiri"}
		var sanitized := Data.sanitize(bad, 5544)
		_check(not sanitized["chapters"].has("watch_c2_forest"), "损坏" + field + "不能造出更大承诺")
		_check(Data.paid(sanitized, "watch_c2_forest:s4"), "损坏" + field + "不能擦去已付收据")
		_check(not Data.mark_paid(sanitized, "watch_c2_forest:s4"), "损坏" + field + "不能重付")
	var future := GDScript.new()
	future.source_code = FileAccess.get_file_as_string("res://scripts/main/campaign_quest_data.gd").replace("class_name CampaignQuestData\n", "").replace('const Economy := preload("res://scripts/ecology/economy_math.gd")', 'const Economy := preload("res://tests/fixtures/campaign_future_economy.gd")')
	_check(future.reload() == OK, "仅测试内替换未来经济源")
	var after: Dictionary = future.call("sanitize", q, 5544)
	_check(after["chapters"].get("watch_c2_forest", {}) == original, "未来EconomyMath不能使旧v1合同失效")
	var future_issue: Dictionary = future.call("_new_contract", 3, 6, "main")
	_check(future_issue == original, "v1发行只消费归档规则；新金额必须走新版本")
	var unknown := q.duplicate(true)
	unknown["chapters"]["watch_c2_forest"]["version"] = 2
	_check(not Data.sanitize(unknown, 5544)["chapters"].has("watch_c2_forest"), "未实现v2不得错按v1支付")
	print("CAMPAIGN_REWARD_CONTRACT_TEST ", "PASS " if failures == 0 else "FAIL ", checks)
	quit(0 if failures == 0 else 1)
func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
