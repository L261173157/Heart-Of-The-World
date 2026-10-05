## 完整内容合同目录检查；本检查不替代真实行动、机关碰撞或冷启动验收。
extends SceneTree

const Catalog := preload("res://scripts/main/campaign_catalog.gd")
const Layout := preload("res://scripts/ecology/campaign_layout.gd")
const MAIN_IDS := ["watch_c2_forest", "watch_c3_swamp", "watch_c4_hill", "watch_c5_snow", "watch_c6_lava"]
const MAIN_TITLES := ["林间旧约", "沼泽双途", "丘陵封关", "雪原回声", "熔火之心"]
const SIDE_IDS := ["side_patrol", "side_herbalist", "side_hunter", "side_scholar", "side_merchant", "side_watchman", "side_letter", "side_troll"]
const REGION_IDS := ["region_plains", "region_forest", "region_swamp", "region_hill", "region_snow", "region_lava"]
const RANDOM_IDS := ["random_wounded", "random_parcel", "random_sign", "random_rocks", "random_medicine", "random_message", "random_nest", "random_migration", "random_camp", "random_runes"]
const WORLD_IDS := ["world_migration", "world_decline", "world_relief", "world_watchnet"]
var _checks := 0
var _fails := 0

func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok: _fails += 1
	print("%s %s" % ["PASS" if ok else "FAIL", label])

func _ids(chains: Array) -> Array:
	var ids := []
	for chain: Dictionary in chains: ids.append(chain.get("id", ""))
	return ids

func _family(chains: Array, expected: Array, steps: int, family: String) -> void:
	_check(_ids(chains) == expected, family + "链集合完整且使用合同稳定ID")
	for chain: Dictionary in chains:
		_check(not str(chain.get("title", "")).is_empty(), str(chain["id"]) + "有具名故事标题")
		_check(chain.get("steps", []).size() == steps, str(chain["id"]) + "阶段数量符合合同")
		for index in chain.get("steps", []).size():
			var stage: Dictionary = chain["steps"][index]
			_check(stage.get("id", "") == str(chain["id"]) + ":s" + str(index + 1), str(chain["id"]) + "阶段ID不随接取次数变化")
			_check(not str(stage.get("title", "")).is_empty() and not str(stage.get("objective", "")).is_empty(), str(stage["id"]) + "具有独立标题及可执行目标")
			_check(not stage.get("actions", []).is_empty(), str(stage["id"]) + "不是只有标题的空阶段")

func _init() -> void:
	_check(Catalog.ID == "campaign_watch_v1" and Catalog.VERSION == 1, "战役ID与目录版本符合合同")
	_family(Catalog.main_chapters(), MAIN_IDS, 4, "主线")
	_family(Catalog.side_chains(), SIDE_IDS, 2, "人物支线")
	_family(Catalog.regional_arcs(), REGION_IDS, 3, "区域线")
	_family(Catalog.world_arcs(), WORLD_IDS, 3, "世界线")
	_check(_ids(Catalog.random_templates()) == RANDOM_IDS, "十种有限随机模板全部具名登记")
	_check(Catalog.RANDOM_PER_TEMPLATE == 3 and Catalog.RANDOM_LIMIT == 30, "随机任务每模板最多3次、整档最多30次")
	for index in mini(MAIN_IDS.size(), Catalog.main_chapters().size()):
		var chapter: Dictionary = Catalog.main_chapters()[index]
		_check(chapter.get("number", 0) == index + 2 and chapter.get("title", "") == MAIN_TITLES[index], "主线章序/标题对应原合同：" + MAIN_IDS[index])
	var stage_ids := {}
	var action_ids := {}
	var objects := {}
	for item: Dictionary in Layout.objects():
		_check(not objects.has(item.get("id", "")), "场景物件ID唯一：" + str(item.get("id", "")))
		objects[item.get("id", "")] = item
	for stage: Dictionary in Catalog.all_stages():
		var sid := str(stage.get("id", ""))
		_check(not sid.is_empty() and not stage_ids.has(sid), "阶段ID全局唯一：" + sid)
		stage_ids[sid] = true
		var preceding := {}
		for action: Dictionary in stage.get("actions", []):
			var aid := str(action.get("id", ""))
			_check(not aid.is_empty() and not action_ids.has(aid), "包括随机实例在内的行动ID全局唯一：" + aid)
			action_ids[aid] = true
			_check(str(action.get("stage", "")) == sid, aid + "明确归属自己的阶段")
			_check(not str(action.get("text", "")).is_empty() and not str(action.get("verb", "")).is_empty(), aid + "具有现场说明及明确操作")
			for dependency: String in action.get("requires", []):
				_check(preceding.has(dependency), aid + "所有前置均来自同段先前的真实行动")
			preceding[aid] = true
			if stage.get("family", "") != "random":
				_check(objects.has(action.get("object", "")), aid + "指向实际作者物件而非空UI")
			if action.get("kind", "") == "puzzle":
				_check(not action.get("puzzle_order", []).is_empty(), aid + "具有明确可验证的机关解法")
				if not action.get("puzzle_objects", []).is_empty():
					_check(action.get("puzzle_order", []).size() == action.get("puzzle_objects", []).size(), aid + "分布式机关解法与实际操作点一一对应")
				for object_id: String in action.get("puzzle_objects", []):
					if stage.get("family", "") != "random": _check(objects.has(object_id), aid + "符记具有真实独立实体：" + object_id)
		for required: String in stage.get("required", []):
			_check(preceding.has(required), sid + "完成条件不会引用不存在的行动")
	_check(Catalog.main_chapters().size() * 4 + 4 == 24, "既有首章4环节加新增20环节合计24，未重复创建第一章奖励")
	_check(not stage_ids.has("lost_outpost_v1") and not stage_ids.has("camp_ecology_v1"), "旧首章和旧调查合同仍由原账本拥有，未复制新收据")
	print("CAMPAIGN_CONTENT_COUNTS ", JSON.stringify({"main_chapters_including_original": Catalog.main_chapters().size() + 1,
		"main_beats_including_original": Catalog.main_chapters().size() * 4 + 4,
		"side_chains": Catalog.side_chains().size(), "side_quests": Catalog.side_chains().size() * 2,
		"regional_arcs": Catalog.regional_arcs().size(), "regional_stages": Catalog.regional_arcs().size() * 3,
		"random_templates": Catalog.random_templates().size(), "world_arcs": Catalog.world_arcs().size(),
		"stages": stage_ids.size(), "actions": action_ids.size(), "physical_objects": objects.size()}))
	print("=== CAMPAIGN CONTENT CONTRACT %s (%d checks, %d failures) ===" % ["PASS" if _fails == 0 else "FAIL", _checks, _fails])
	quit(0 if _fails == 0 else 1)
