extends SceneTree
const Data := preload("res://scripts/main/campaign_quest_data.gd")
const Catalog := preload("res://scripts/main/campaign_catalog.gd")
var checks := 0
func _initialize() -> void:
	var q := Data.create(4187)
	_check(not Data.accept_chapter(q, "watch_c2_forest", 3), "未完成前哨不能接第二章")
	_check(not Data.authorize_chapter1(q, {"id": "lost_outpost_v1", "stage": "completed"}), "伪终态不授权")
	var e: Dictionary = {}
	for key: String in Data.Outpost.EVIDENCE: e[key] = true
	var first := {"id": "lost_outpost_v1", "evidence": e, "outcome": "survey", "survey_confirmed": true}
	_check(Data.authorize_chapter1(q, first), "真实前哨证据授权")
	_check(Data.accept_chapter(q, "watch_c2_forest", 3), "接单锁整章预算")
	var budget: Dictionary = q["chapters"]["watch_c2_forest"].duplicate(true)
	_check(not Data.accept_chapter(q, "watch_c2_forest", 80), "重复接单不增预算")
	var gold := 0
	var xp := 0
	for stage: Dictionary in Catalog.chapter("watch_c2_forest")["steps"]:
		gold += int(Data.reward(q, stage["id"])["gold"])
		xp += int(Data.reward(q, stage["id"])["xp"])
	_check(gold == budget["gold"] and xp == budget["xp"], "分段总额严格等于冻结预算")
	var c: Dictionary = Catalog.chapter("watch_c2_forest")
	for stage: Dictionary in c["steps"]:
		_check(not Data.ready(q, stage["id"]), "未行动不可领奖")
		for action: Dictionary in stage["actions"]:
			var proof := {"position": [100, 200], "tick": 4}
			if action["kind"] == "puzzle":
				q["puzzle_progress"][action["id"]] = ["north"]
				q["travel"]["visited"] = ["forest", "lava", "unknown"]
				q["travel"]["arrivals"] = {"forest": [1234, 2345], "lava": [1234, 2345], "unknown": [1234, 2345]}
				q["paused_chains"] = ["watch_c2_forest"]
				var cold := Data.sanitize(JSON.parse_string(JSON.stringify(q)), 4187)
				_check(cold["puzzle_progress"].get(action["id"]) == ["north"], "冷启动保留真实机关前缀")
				_check(cold["paused_chains"] == ["watch_c2_forest"] and Data.active_ids(cold).is_empty(), "暂停保留证据并停止追踪")
				_check(cold["travel"]["visited"] == ["forest"], "未知远征地形不恢复")
				_check(cold["travel"]["arrivals"] == {"forest": [1234.0, 2345.0]}, "落点仅保留已经到访且有资格的路线")
				_check(Data.accept_chapter(cold, "watch_c2_forest", 99) and cold["chapters"]["watch_c2_forest"] == budget, "继续不重算接单等级")
				proof["order"] = ["west", "north", "east"]
				_check(not Data.record(q, stage["id"], action["id"], proof), "错误机关顺序不得完成")
				proof["order"] = action["puzzle_order"]
			_check(Data.record(q, stage["id"], action["id"], proof), "真实顺序证据保存")
			_check(not Data.record(q, stage["id"], action["id"], proof), "同动作不能重复")
			q = Data.sanitize(JSON.parse_string(JSON.stringify(q)), 4187)
			_check(q["quests"][stage["id"]]["evidence"].has(action["id"]), "每动作JSON往返")
		_check(Data.ready(q, stage["id"]), "完整证据解锁阶段")
		_check(Data.mark_paid(q, stage["id"]), "阶段仅首次支付")
		_check(not Data.mark_paid(q, stage["id"]), "再次支付拒绝")
	_check(Data.chapter_complete(q, "watch_c2_forest"), "整章证据完整")
	var damaged := q.duplicate(true)
	damaged["quests"]["watch_c2_forest:s1"]["evidence"].clear()
	var clean := Data.sanitize(damaged, 4187)
	_check(not Data.chapter_complete(clean, "watch_c2_forest"), "缺失前置不免费完成")
	_check(Data.paid(clean, "watch_c2_forest:s4"), "坏证据不擦支付收据")
	_check(not Data.mark_paid(clean, "watch_c2_forest:s4"), "坏证据也不重复发款")
	_check(Data.sanitize(q, 4188).is_empty(), "跨种子拒绝")
	_check(Data.sanitize({"id": Data.ID, "version": 2, "seed": 4187}, 4187).is_empty(), "未来版本拒绝误迁移")
	print("CAMPAIGN_LEDGER_TEST PASS ", checks)
	quit(0)
func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		push_error("campaign ledger: " + message)
		quit(1)
