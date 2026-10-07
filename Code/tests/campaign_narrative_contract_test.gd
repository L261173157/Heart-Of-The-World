## 叙事分层的纯目录合同。机械基线取自已核对 Git blob 的主线目录，不能为通过改写而刷新。
## 本测试检查目录完整性；现场确认、可选追问和不提前入账由 quest_narrative_ui_test 覆盖。
extends SceneTree

const Catalog := preload("res://scripts/main/campaign_catalog.gd")
const Layout := preload("res://scripts/ecology/campaign_layout.gd")
const Data := preload("res://scripts/main/campaign_quest_data.gd")
const Outpost := preload("res://scripts/main/outpost_quest_data.gd")
const PRESENTATION := ["title", "objective", "verb", "text", "prompt", "questions", "rules", "label", "answer", "consequence", "risk"]
const BASELINE := "res://tests/fixtures/campaign_narrative_mechanics_v1.json"
var _checks := 0
var _fails := 0

func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok: _fails += 1
	print("  %s %s" % ["PASS" if ok else "FAIL", label])

func _mechanics(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in value:
			if not str(key) in PRESENTATION: result[key] = _mechanics(value[key])
		return result
	if value is Array:
		var result: Array = []
		for child: Variant in value: result.append(_mechanics(child))
		return result
	return value

func _same(a: Variant, b: Variant) -> bool:
	if typeof(a) in [TYPE_INT, TYPE_FLOAT] and typeof(b) in [TYPE_INT, TYPE_FLOAT]: return float(a) == float(b)
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return false
		for key: Variant in a:
			if not b.has(key) or not _same(a[key], b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size(): return false
		for index in a.size():
			if not _same(a[index], b[index]): return false
		return true
	return a == b

func _initialize() -> void:
	var baseline: Variant = JSON.parse_string(FileAccess.get_file_as_string(BASELINE))
	_check(baseline is Dictionary and baseline.get("source_tree", "") == "24fa8381633150cc397ae631f050df2c0dca75bc", "机械基线来自改写前已核实的主线 Git tree")
	if baseline is Dictionary:
		var chains := Catalog.chains()
		_check(chains.size() == baseline.get("chains", []).size(), "所有家族链数量保持原合同")
		for index in mini(chains.size(), baseline.get("chains", []).size()):
			var expected: Dictionary = baseline["chains"][index]
			_check(_same(_mechanics(chains[index]), expected), str(expected.get("id", "")) + "全部非呈现字段不变：ID、前置、支路、物件、结果与开放条件")
	_check(Outpost.REWARDS_V1 == {"investigation":{"gold":6,"xp":8,"bonus":""}, "rescue":{"gold":9,"xp":12,"bonus":""}, "restoration":{"gold":24,"xp":24,"bonus":"onigiri"}}, "首章分段39金币44经验1饭团的原承诺未改")
	_check(Data.REWARD_VERSION == 1 and Data.REWARD_V1 == {"gold_base":12,"gold_target":6,"gold_level":3,"xp_base":20,"xp_target":8}, "战役冻结奖励版本与金额公式未改")
	_check(Outpost.ID == "lost_outpost_v1" and Outpost.VERSION == 1 and Catalog.ID == "campaign_watch_v1" and Catalog.VERSION == 1, "叙事改写未重建章节或存档身份")
	var objects: Dictionary = {}
	for object: Dictionary in Layout.objects(): objects[str(object.id)] = object
	for group: Array in [Catalog.main_chapters(), Catalog.side_chains()]:
		for chain: Dictionary in group:
			var question_count := 0
			for stage: Dictionary in chain["steps"]:
				for a: Dictionary in stage["actions"]:
					var id := str(a["id"])
					var prompt := str(a.get("prompt", ""))
					_check(objects.has(a.object) and str(a.title) == str(objects.get(a.object, {}).get("title", "")), id + "目录人物/物件名与真实世界实体一致")
					_check(prompt.length() >= 12 and prompt != str(a.get("text", "")), id + "行动前现场描述与行动后所得记录分离")
					_check(not str(a.get("text", "")).is_empty() and not str(a.get("verb", "")).is_empty(), id + "保留明确操作及已取得的结果")
					var labels: Array[String] = []
					for question: Dictionary in a.get("questions", []):
						question_count += 1
						var label := str(question.get("label", ""))
						_check(not label.is_empty() and not label in labels and str(question.get("answer", "")).length() >= 8, id + "可选追问有独立题目和实质回答")
						_check(not question.has("action") and not question.has("requires") and not question.has("cost"), id + "追问不混入状态动作、前置或消费")
						labels.append(label)
			if str(chain["id"]) != "watch_c6_lava":
				_check(question_count > 0, str(chain["id"]) + "NPC故事提供可跳过的背景追问")
	_independent_order_results()
	print("=== CAMPAIGN NARRATIVE CONTRACT %s (%d checks, %d failures) ===" % ["PASS" if _fails == 0 else "FAIL", _checks, _fails])
	quit(0 if _fails == 0 else 1)

## 完整合法纯账本夹具，只验证独立行动的反序合同与措辞，不声称实际走完施工路线。
func _independent_order_results() -> void:
	var q := Data.create(42)
	var chapter1 := {"id":Outpost.ID,"evidence":{},"outcome":"survey","survey_confirmed":true}
	for key: String in Outpost.EVIDENCE: chapter1.evidence[key] = true
	_check(Data.authorize_chapter1(q,chapter1), "反序叙事夹具保留合法首章证明")
	for chapter: Dictionary in Catalog.main_chapters():
		_check(Data.accept_chapter(q,chapter.id,7), "反序夹具主线前置：" + str(chapter.id))
		for stage: Dictionary in chapter.steps: _complete_fixture(q,stage)
	for region: Dictionary in Catalog.regional_arcs().slice(0,3):
		for stage: Dictionary in region.steps:
			_check(Data.accept(q,stage.id,7), "反序夹具区域前置：" + str(stage.id))
			_complete_fixture(q,stage)
	q.travel.visited = ["forest","swamp"]
	q.dynamic_runtime.relief_needs = {"world_relief:need_a":{"station":"region_plains_station","resolved":false},"world_relief:need_b":{"station":"region_forest_station","resolved":false}}
	_check(Data.accept(q,"world_relief:s1",7), "两处实际已启用服务的待办可建立接应前置")
	_complete_fixture(q,Catalog.stage("world_relief:s1"))
	for entry: Array in [["world_relief:s2",["supply_b","supply_a"]],["world_watchnet:s2",["node_3","node_2","node_1"]]]:
		if str(entry[0]).begins_with("world_watchnet"):
			_check(Data.accept(q,"world_watchnet:s1",7), "主线和三条区域完工后才允许守望网络配置")
			_complete_fixture(q,Catalog.stage("world_watchnet:s1"))
		var stage := Catalog.stage(str(entry[0]))
		_check(Data.accept(q,stage.id,7), "反序行动阶段合法接取：" + str(stage.id))
		var recorded: Array[String] = []
		for suffix: String in entry[1]:
			var a := Catalog.action(stage.id,str(stage.id)+":"+suffix)
			_check(a.get("requires",[]).is_empty() and Data.record(q,stage.id,a.id,_fixture_proof(q,a)), "没有顺序门槛的行动可先完成：" + str(a.id))
			recorded.append(str(a.id))
			for sibling: Dictionary in stage.actions:
				_check(q.quests[stage.id].evidence.has(sibling.id) == (str(sibling.id) in recorded), "反序不会伪造另一处的完成证据：" + str(sibling.id))
			for unearned: String in ["还剩", "最后一", "两处都", "两份都", "三处都", "全部完成", "都已留下"]:
				_check(not str(a.text).contains(unearned) and not str(a.get("prompt", "")).contains(unearned), str(a.id) + "仅描述当前物资/节点，不暗称其他节点完成：" + unearned)
			_check(Data.ready(q,stage.id) == (recorded.size() == stage.actions.size()), "只有全部独立证据齐备才算阶段完成")

func _complete_fixture(q: Dictionary, stage: Dictionary) -> void:
	for a: Dictionary in stage.actions:
		if a.get("optional",false): continue
		_check(Data.record(q,stage.id,a.id,_fixture_proof(q,a)), "合法纯账本叙事前置：" + str(a.id))
	_check(Data.ready(q,stage.id), "前置阶段证据完整：" + str(stage.id))

func _fixture_proof(q: Dictionary, a: Dictionary) -> Dictionary:
	var p := {"position":[234,567],"tick":11}
	var selected := Data.choice(q,a)
	match str(a.kind):
		"choice":
			var option: Variant = a.choices[0]
			selected = str(option.id) if option is Dictionary else str(option)
			if a.chain == "region_forest": selected = "outer"
			p.choice = selected
		"puzzle": p.order = a.puzzle_order.duplicate()
		"obstacle":
			p.obstacle_key = a.get("barrier_id",a.object)
			p.destroyed = true
		"encounter":
			p.outcome = "absent"
			p.verified = true
		"ecology":
			p.outcome = "survey"
			p.verified = true
		"route":
			p.route = selected if not selected.is_empty() else a.routes[0]
			p.traversed = true
			p.visit_ids = a.get("route_by_choice",{}).get(selected,a.get("route_waypoints",[])).duplicate()
		"configure": p.nodes = ["region_plains_station","region_forest_station","region_swamp_station"]
	if a.get("destination_by_choice",{}).has(selected): p.destination = a.destination_by_choice[selected]
	if a.has("consumes"): p.item = a.consumes
	if a.has("supply_id"):
		p.item = a.supply_id
		p.destination = a.object
	if a.get("obstacle_by_choice",{}).has(selected):
		p.obstacle_key = a.obstacle_by_choice[selected]
		p.destroyed = true
	return p
