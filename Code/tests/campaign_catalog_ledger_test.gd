extends SceneTree
const Data := preload("res://scripts/main/campaign_quest_data.gd")
const Catalog := preload("res://scripts/main/campaign_catalog.gd")
var checks := 0
var failed := false
func _initialize() -> void:
	_check(Catalog.main_chapters().size() == 5, "五个新主线章节加既有第一章")
	_check(Catalog.side_chains().size() == 8 and Catalog.regional_arcs().size() == 6, "人物与区域数量固定")
	_check(Catalog.random_templates().size() == 10 and Catalog.world_arcs().size() == 4, "十遭遇与四世界事项")
	_check(Catalog.all_stages(7781).size() == 96, "有限目录九十六阶段槽")
	_check(Catalog.main_chapters().is_read_only() and Catalog.actions(7781).is_read_only(), "缓存不可变防消费者改写作者合同")
	var ids: Dictionary = {}
	for stage: Dictionary in Catalog.all_stages(7781):
		_check(not ids.has(stage["id"]), "稳定阶段ID不重复")
		ids[stage["id"]] = true
		for a: Dictionary in stage["actions"]:
			_check(not ids.has(a["id"]), "稳定行动ID不重复")
			ids[a["id"]] = true
			_check(a["text"].length() >= 20 and not a["verb"].is_empty(), "每项有明确作者说明与动词")
			_check(Catalog.action(stage["id"], a["id"]) == a, "行动查询同源")
	var q := _fresh()
	for c: Dictionary in Catalog.main_chapters():
		_check(Data.accept_chapter(q, c["id"], 7), "按真实前章证据接下一章")
		for stage: Dictionary in c["steps"]: _complete_stage(q, stage)
		q = _roundtrip(q)
		_check(Data.chapter_complete(q, c["id"]), "全章JSON往返证据完整")
	_check(q["ending"] == "distributed", "终局由真实选择与落实证据推导")
	for family: Array in [Catalog.side_chains(), Catalog.regional_arcs()]:
		for chain: Dictionary in family:
			for stage: Dictionary in chain["steps"]:
				_check(Data.accept(q, stage["id"], 7), "可选阶段独立接单")
				_complete_stage(q, stage)
			q = _roundtrip(q)
			_check(Data.ready(q, chain["id"] + (":s2" if chain["family"] == "side" else ":s3")), "可选链完整往返")
	_check(not q["services"].has("herbalist_reserve"), "伤者分支不能冒领站点储备服务")
	var random_q := _fresh()
	for template: Dictionary in Catalog.random_templates():
		for ordinal: int in range(3):
			var id: String = template["id"] + ":7781:" + str(ordinal)
			_check(Data.accept(random_q, id, 2), "每模板三份固定遭遇")
			_check(not Data.accept(random_q, "random_sign:7781:2", 9), "同时最多一个遭遇")
			var stage := Catalog.stage(id)
			var first: Dictionary = stage["actions"][0]
			_check(Data.record(random_q, id, first["id"], _proof(random_q, first)), "遭遇首个实际行动")
			random_q = _roundtrip(random_q)
			_check(random_q["quests"][id]["evidence"].has(first["id"]), "部分遭遇冷启动不丢证据")
			_complete_stage(random_q, stage)
			random_q = _roundtrip(random_q)
			_check(Data.paid(random_q, id), "遭遇一次性收据保留")
		_check(Data.next_random(random_q, template["id"]) == "", "三次耗尽不再发同类")
	_check(random_q["random_used"].size() == 30 and random_q["active_random"] == "", "三十个有限遭遇结清")
	_check(not Data.accept(random_q, "random_wounded:7781:0", 100), "付款后不可重新接取")
	var destroyed := random_q.duplicate(true)
	destroyed["quests"].clear()
	destroyed = Data.sanitize(destroyed, 7781)
	_check(destroyed["random_used"].size() == 30 and not Data.accept(destroyed, "random_wounded:7781:0", 1), "损坏任务内容不返还遭遇名额")
	var broken := q.duplicate(true)
	broken["chapters"]["watch_c2_forest"]["gold"] = 99999
	broken = Data.sanitize(broken, 7781)
	_check(not broken["chapters"].has("watch_c2_forest"), "损坏金额不膨胀冻结预算")
	_check(Data.paid(broken, "watch_c2_forest:s4"), "损坏合同仍保留支付墓碑")
	var malformed := q.duplicate(true)
	malformed["quests"]["watch_c2_forest:s1"]["evidence"]["watch_c2_forest:s1:herbalist"]["object"] = {"bad": true}
	_check(not Data.ready(Data.sanitize(malformed, 7781), "watch_c2_forest:s1"), "非字符串证据身份安全隔离")
	_check(Data.sanitize({"id": {}, "version": 1, "seed": 7781}, 7781).is_empty(), "畸形根ID不抛运行错误")
	if failed: quit(1)
	else:
		print("CAMPAIGN_CATALOG_LEDGER_TEST PASS ", checks)
		quit(0)
func _fresh() -> Dictionary:
	var q := Data.create(7781)
	var e: Dictionary = {}
	for key: String in Data.Outpost.EVIDENCE: e[key] = true
	Data.authorize_chapter1(q, {"id": "lost_outpost_v1", "evidence": e, "outcome": "survey", "survey_confirmed": true})
	return q
func _roundtrip(q: Dictionary) -> Dictionary:
	return Data.sanitize(JSON.parse_string(JSON.stringify(q)), 7781)
func _complete_stage(q: Dictionary, s: Dictionary) -> void:
	for a: Dictionary in s["actions"]:
		if a.get("optional", false) or q["quests"][s["id"]]["evidence"].has(a["id"]): continue
		_check(Data.record(q, s["id"], a["id"], _proof(q, a)), "纯合同模拟行为 " + a["id"])
	_check(Data.ready(q, s["id"]), "齐备证据阶段可结算 " + s["id"])
	_check(Data.mark_paid(q, s["id"]), "仅首结算 " + s["id"])
	_check(not Data.mark_paid(q, s["id"]), "拒绝重复结算 " + s["id"])
func _proof(q: Dictionary, a: Dictionary) -> Dictionary:
	var p := {"position": [234, 567], "tick": 11}
	var selected := Data.choice(q, a)
	match str(a["kind"]):
		"choice":
			var option: Variant = a["choices"][0]
			selected = str(option["id"]) if option is Dictionary else str(option)
			if a["chain"] == "side_hunter": selected = "warning"
			if a["chain"] == "region_forest": selected = "outer"
			p["choice"] = selected
		"puzzle": p["order"] = a["puzzle_order"].duplicate()
		"obstacle":
			p["obstacle_key"] = a.get("barrier_id", a["object"])
			p["destroyed"] = true
		"encounter":
			p["outcome"] = "absent"
			p["verified"] = true
		"ecology":
			p["outcome"] = "survey"
			p["verified"] = true
		"route":
			p["route"] = selected if not selected.is_empty() else a["routes"][0]
			p["traversed"] = true
			p["visit_ids"] = a.get("route_by_choice", {}).get(selected, a.get("route_waypoints", [])).duplicate()
	var destination: Dictionary = a.get("destination_by_choice", {})
	if destination.has(selected): p["destination"] = destination[selected]
	if a.has("consumes"): p["item"] = a["consumes"]
	if a.get("obstacle_by_choice", {}).has(selected):
		p["obstacle_key"] = a["obstacle_by_choice"][selected]
		p["destroyed"] = true
	return p
func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failed = true
		push_error(message)
