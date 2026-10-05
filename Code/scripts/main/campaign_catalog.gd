## 《断开的守望》作者内容目录。ID 是存档合同，不随显示名或接单次数重写。
## 第一章继续由 OutpostQuestData 持有；这里不复制它的证据或39/44旧预算。
class_name CampaignCatalog
extends RefCounted

const ID := "campaign_watch_v1"
const VERSION := 1
const RANDOM_LIMIT := 30
const RANDOM_PER_TEMPLATE := 3
static var _groups: Dictionary = {}
static var _stages: Dictionary = {}
static var _stage_maps: Dictionary = {}
static var _action_maps: Dictionary = {}

static func main_chapters() -> Array:
	if not _groups.has("main_chapters"): _groups["main_chapters"] = _seal(_main_chapters())
	return _groups["main_chapters"]

static func _main_chapters() -> Array:
	return [
		_chapter("watch_c2_forest", "林间旧约", "forest", 2, [
			_step("古树下的旧约", "询问林地药师，再亲自读完古树下的旧约。", [
				_action("herbalist", "c2:herbalist", "林地药师", "talk", "询问旧哨所", "药师把一页叶脉拓本交给你：林下三枚符标仍沿用旧约的次序，先去古树寻找原文。"),
				_action("old_pact", "c2:old_pact", "古树下的旧约", "read", "读旧约", "旧约记着人类曾为巡林者保留过林下通路。文字没有许诺安全，只留下三枚符标与失散联络员的名字。", ["herbalist"])]),
			_step("林下通道", "读出北、东、西的符标次序，开启栅门后步行取回残页。", [
				_action("route_marks", "c2:route_marks", "旧路标刻痕", "read", "辨读刻痕", "刻痕由晨露、日影与归鸟串起：先北，再东，最后西。按错只会熄灭已亮的符标，可以重新尝试。"),
				_action("runes", "c2:forest_gate", "三枚林下符标", "puzzle", "核对符标", "三枚符标依次亮起，旧栅门的锁舌松开。残页仍在门后，需要你亲自走过去。", ["route_marks"], {"puzzle_order": ["north", "east", "west"], "puzzle_objects": ["c2:rune_north", "c2:rune_east", "c2:rune_west"], "opens": "c2:forest_gate"}),
				_action("torn_record", "c2:torn_record", "被撕开的守望记录", "recover", "拾起残页", "残页上的信号图并不完整。末行写着：联络员仍守着东侧歇脚处，补给没有送到。", ["runes"])]),
			_step("留在林地的人", "找到失联联络员，取回专用急救包，再回到他身边救治。", [
				_action("liaison", "c2:liaison", "负伤联络员", "talk", "查看伤势", "联络员无法继续行走。他指出树根后的封存急救箱，并请你把信号重新送上山脊。"),
				_action("aid_cache", "c2:aid_cache", "联络站急救箱", "recover", "取专用急救包", "你取出联络站封存的急救包。它只用于这次救援，不占背包，也不会被快捷补给消耗。", ["liaison"], {"quest_item": "c2:aid"}),
				_action("rescue", "c2:liaison", "负伤联络员", "rescue", "为联络员包扎", "你在联络员身旁完成包扎。他能留守联络站了，但仍不能代替你去修复烽灯。", ["aid_cache"])]),
			_step("第一束信号", "回收信号零件，在烽灯处亲手恢复第一束信号。", [
				_action("signal_parts", "c2:signal_parts", "封存的信号零件", "recover", "回收零件", "木匣内保留着遮光片与旧灯芯。零件齐了，灯塔还需要现场装配。", [], {"quest_item": "c2:signal_parts"}),
				_action("beacon", "c2:beacon", "林地烽灯", "repair", "修复烽灯", "林地烽灯重新亮起。联络员留下值守，证实远征队曾分赴沼泽与丘陵，并交给你沼泽接应点的旧坐标；灯亮不代表林路已经安全。", ["signal_parts"], {"service": "forest_station", "next_chapter": "watch_c3_swamp"})])]),
		_chapter("watch_c3_swamp", "沼泽双途", "swamp", 3, [
			_step("漂来的行囊", "对照沉睡图腾与枯木灵龛上的记号，寻找漂来的远征行囊。", [
				_action("totem", "c3:totem_record", "沉睡图腾旁的绳结", "read", "辨认绳结", "绳结被水浸过，打结法却与前哨记录一致。它指向枯木灵龛旁搁浅的旧行囊。"),
				_action("shrine", "c3:shrine_record", "灵龛上的留字", "read", "读留字", "木片写着：近路曾经可走，外缘曾有接应。两句话都没有日期，不能代替眼前的调查。", ["totem"]),
				_action("satchel", "c3:satchel", "远征队行囊", "recover", "回收行囊", "你取出防水封套。里面是两份互相矛盾的路书与一封没有寄出的回信。", ["shrine"], {"quest_item": "c3:satchel_record"})]),
			_step("两份路书", "读旧路书，分别到近路与外缘核对眼前通路和族群。", [
				_action("old_route", "c3:old_route", "浸水路书", "read", "读两份路书", "一份路书沿浅滩直切，另一份绕过枯木外缘。记录只代表那次远征，今天的障碍与怪物仍要分别查看。"),
				_action("route_near", "c3:route_near", "浅滩近路勘察点", "observe", "勘察近路", "你记下浅滩近路现在的通行条件和可见活动，保留眼前事实，没有把旧猎数当成现在的存量。", ["old_route"]),
				_action("route_outer", "c3:route_outer", "枯木外缘勘察点", "observe", "勘察外缘", "外缘距离更长，转折也更多。你把当前观察与近路记录并列，接下来由你选择接近方式。", ["old_route"])]),
			_step("接应点", "明确选择一条已勘察路线，亲自走到幸存者身边并完成接应。", [
				_action("route_choice", "c3:route_choice", "接应路线图", "choice", "选择路线", "近路较短，外缘绕行较长。两条路线都只能依据已勘察的现状选择，不保证永久安全。", [], {"choices": [{"id": "near", "title": "走浅滩近路"}, {"id": "outer", "title": "绕枯木外缘"}]}),
				_action("reach", "c3:survivor", "沼泽幸存者", "route", "确认已到接应点", "你沿选定线路到达接应点。幸存者认出行囊封套，请你取来留在一旁的急救物资。", ["route_choice"], {"routes": ["near", "outer"], "route_by_choice": {"near": ["c3:route_near", "c3:survivor"], "outer": ["c3:route_outer", "c3:survivor"]}}),
				_action("aid", "c3:aid_cache", "接应点急救物资", "recover", "取接应物资", "接应物资仍封在油布里，足够完成这次救助。它不进入交易背包。", ["reach"], {"quest_item": "c3:aid"}),
				_action("rescue", "c3:survivor", "沼泽幸存者", "rescue", "完成现场接应", "你把物资交到幸存者手中并处理伤处。接应点恢复了留驻人员，先前穿过的道路并未自动整修。", ["aid"])]),
			_step("未完成的回信", "核实行囊来历，取得回信中的丘陵线索，恢复沼泽联络。", [
				_action("account", "c3:survivor", "沼泽幸存者", "talk", "核实行囊来历", "幸存者承认两份路书来自两次不同撤离。远征队没有全员失踪，有人转往丘陵档案接近区。"),
				_action("reply", "c3:reply_record", "未完成的回信", "recover", "收起回信", "回信留下丘陵学者的名字与绞盘构造草图。你带走的是原件，没人替远征队补写结局。", ["account"], {"quest_item": "c3:reply"}),
				_action("beacon", "c3:beacon", "沼泽联络灯", "repair", "接通联络灯", "接应点的联络灯亮起。幸存者愿意留守，你获得前往丘陵接近点的路线资格。", ["reply"], {"service": "swamp_station", "next_chapter": "watch_c4_hill"})])]),
		_chapter("watch_c4_hill", "丘陵封关", "hill", 4, [
			_step("封门者的名册", "找到遗迹学者，核对旧名册里真正负责封存档案的人。", [
				_action("scholar", "c4:scholar", "丘陵遗迹学者", "talk", "询问封门者", "学者说城塞南门一直存在通路；被封起来的是后来加设的档案接近区。封门者留下了名册。"),
				_action("roster", "c4:roster", "封存名册", "read", "核对名册", "名册上有沼泽回信的署名，也有一位地图保管员。档案不是战利品，银钥匙开不了这道新栅门。", ["scholar"])]),
			_step("断开的绞盘", "回收绞盘零件，在原位装好绞盘，打开档案区局部门。", [
				_action("parts", "c4:winch_parts", "散落的绞盘零件", "recover", "回收绞盘零件", "齿轮与轴销被分开收存，部件齐全后才能重新拉起档案区栅门。", [], {"quest_item": "c4:winch_parts"}),
				_action("winch", "c4:winch", "断开的绞盘", "repair", "安装并拉动绞盘", "绞盘咬合，新增档案栅门被拉起。原有城塞南门和循环宝箱仍按原来的规则使用。", ["parts"], {"opens": "c4:archive_gate"})]),
			_step("牛头王的城塞", "实地核对牛头王，战斗、局部绕行或空城调查后亲取档案。", [
				_action("fortress", "c4:fortress_record", "城塞值守记录", "read", "核对城塞现状", "档案位于旧城塞附近。先核对牛头王当前是否在场：战胜它、完成环境绕行，或在确无目标时据实调查，都不能互相冒认。"),
				_action("passage", "c4:bypass_control", "档案区接近机关", "encounter", "确认接近方式", "你将接近档案区的实际经过写入记录。绕行不记讨伐，空城不记击杀；存在的Boss仍按自己的生态规则活动。", ["fortress"], {"boss_species": "牛头王", "choices": ["defeated", "bypass", "absent"], "opens": "c4:archive_gate"}),
				_action("archive", "c4:archive", "丘陵远征档案", "recover", "取出远征档案", "档案记载了第二次分队：有人留下维护通路，有人带着总图进入雪原。你从档案台取走原件。", ["passage"], {"quest_item": "c4:archive"})]),
			_step("第二次分队", "帮助地图保管员，取雪原坐标并恢复丘陵信标。", [
				_action("keeper", "c4:map_keeper", "地图保管员", "talk", "扶起地图保管员", "你扶起困在散页间的保管员，替他收拢身旁地图。他没有受伤用药的要求，只请你把下一程坐标带出去。"),
				_action("coordinates", "c4:snow_coordinates", "雪原坐标页", "recover", "取雪原坐标", "地图标出冰封祭坛旁的接近点，队长最后一次回信来自那里。旧坐标不证明他现在仍在那里。", ["keeper"], {"quest_item": "c4:snow_coordinates"}),
				_action("beacon", "c4:beacon", "丘陵信标", "repair", "恢复丘陵信标", "信标恢复联络。地图保管员守住新增接应点，雪原远征线路已可明确选择。", ["coordinates"], {"service": "hill_station", "next_chapter": "watch_c5_snow"})])]),
		_chapter("watch_c5_snow", "雪原回声", "snow", 5, [
			_step("冰封祭坛", "读祭坛留字，真正打碎登记冰障，再取出冰后的铭片。", [
				_action("altar", "c5:altar_record", "祭坛留字", "read", "读祭坛留字", "留字说明铭片被藏在薄冰后，而不是冻在不可破坏的祭坛墙里。先找到登记的薄冰障碍。"),
				_action("ice", "c5:ice_barrier", "铭片前的薄冰障", "obstacle", "核验冰障已破", "你打碎真实冰障，通向铭片的接近路径出现了缺口。记录只属于这块登记冰障。", ["altar"]),
				_action("tablet", "c5:tablet", "雪下守望铭片", "recover", "拾取铭片", "铭片背面刻着队长的接应标记，指向避风处。雪原没有等待你讨伐的故事Boss。", ["ice"], {"quest_item": "c5:tablet"})]),
			_step("雪下的守望", "找到队长，回收专用急救箱，回到身旁明确救助。", [
				_action("leader", "c5:leader", "远征队长", "talk", "检查队长状况", "队长把自己留在最后一个接应点。他指向隔着冰脊保存的急救箱，暂时无力解释两本日志的矛盾。"),
				_action("aid", "c5:aid_cache", "远征急救箱", "recover", "取远征药包", "你从封存箱取出专用药包。它只属于队长的救援，不会扣掉背包里设为快捷补给的药。", ["leader"], {"quest_item": "c5:aid"}),
				_action("rescue", "c5:leader", "远征队长", "rescue", "救助队长", "完成包扎后，队长能继续留在站点。他承认撤守是一次有意的选择，却并没有预料之后的失联。", ["aid"])]),
			_step("相互矛盾的日志", "实读撤守日志与路线日志，将分队、撤守、失联按因果排列。", [
				_action("withdrawal", "c5:withdrawal_log", "撤守日志", "read", "读撤守日志", "撤守日志：分队以后，各处仍尝试维持旧节点；直到无法兼顾，队长才签下撤守令。"),
				_action("route_log", "c5:route_log", "路线日志", "read", "读路线日志", "路线日志：撤守令之后，联络设备逐一失效。正确顺序是先分队，再撤守，最后失联，不是失联迫使所有人同时逃离。"),
				_action("causality", "c5:evidence_board", "远征证据板", "puzzle", "排列因果记录", "你把两本日志与丘陵档案排在一起：分队、撤守、失联。矛盾来自记录时间不同，没有被你改写为某人的背叛。", ["withdrawal", "route_log"], {"puzzle_order": ["split", "withdrawal", "lost"]})]),
			_step("最后的坐标", "听队长说明两种派驻方案，亲取熔岩坐标并恢复雪原信标。", [
				_action("plans", "c5:leader", "远征队长", "talk", "听取派驻方案", "队长提出两条路：把新增巡守分散到已修复节点，或把新增幸存者集中安置。世界之心是联络装置，不能使怪物复活，也不能替人维持所有据点。\n出发建议：Lv6或等效构筑，先回营强化并备足补给。只赶主线可能仍为Lv3；活体龟王必须真正战胜。"),
				_action("coordinates", "c5:lava_coordinates", "最后的坐标页", "recover", "收好熔岩坐标", "坐标页给出熔岩城塞外的安全接近点。核心的旧操作口诀写着：西侧撤守，东侧接应，中央信号。", ["plans"], {"quest_item": "c5:lava_coordinates"}),
				_action("beacon", "c5:beacon", "雪原回声信标", "repair", "接通雪原信标", "雪原信标回应了来路。队长留守新增休整点，你获得熔岩接近点的远征资格。", ["coordinates"], {"service": "snow_station", "next_chapter": "watch_c6_lava"})])]),
		_chapter("watch_c6_lava", "熔火之心", "lava", 6, [
			_step("熔河之间", "阅读灼热边界记录，亲自沿接近路线抵达城塞外围。", [
				_action("hazard", "c6:hazard_record", "熔河边界记录", "read", "了解灼热边界", "熔岩可踏入，但会持续灼烧。竹水壶只能补蓝，不能让人免疫熔岩。接近线沿石脊绕过可见熔流。"),
				_action("approach", "c6:route_approach", "城塞接近石脊", "observe", "确认抵达石脊", "你亲自到达城塞外的石脊，把眼前可走的边缘写入记录。坐标没有把你直接送到龟王身边。", ["hazard"])]),
			_step("龟王盘踞之地", "核对熔岩龟王的真实状态，战胜在场龟王或核实空场后取得核心记录。", [
				_action("fortress", "c6:fortress_record", "中枢外围记录", "read", "核对龟王现状", "熔岩龟王仍属于原城塞。核心记录另存于新增接近区，不要求金钥匙，也不要求等待Boss复生。"),
				_action("passage", "c6:bypass_control", "中枢外围绕行机关", "encounter", "确认中枢通路", "你记录了真实战斗或核实后的空场调查。只有亲自造成的Boss死亡才计为讨伐；通路的完成不会消灭未来的复生。", ["fortress"], {"boss_species": "熔岩龟王", "choices": ["defeated", "absent"], "opens": "c6:core_gate"}),
				_action("core_record", "c6:core_record", "世界之心操作记录", "recover", "取核心记录", "操作图重申：先西侧撤守，再东侧接应，最后中央信号。沿途实物记录已经解释了这个次序。", ["passage"], {"quest_item": "c6:core_record"})]),
			_step("世界之心", "按西、东、中顺序操作中枢，再亲自启动联络装置。", [
				_action("core_order", "c6:heart", "世界之心中枢", "puzzle", "核对中枢次序", "西侧的撤守铭牌亮起，东侧接应纹路接通，最后是中央信号。中枢获得了启动条件，还需要你明确启动。", [], {"puzzle_order": ["west", "east", "center"], "puzzle_objects": ["c6:core_west", "c6:core_east", "c6:core_center"]}),
				_action("activate", "c6:heart", "世界之心", "repair", "启动世界之心", "古老中枢重新连通已经修复的节点。它恢复的是联络能力，野外种群、巢穴和迁徙仍然按真实世界运行。", ["core_order"], {"service": "heart_station"})]),
			_step("此后的道路", "明确决定新增人员的派驻方式，在中枢旁落实这份安排。", [
				_action("ending", "c6:ending_council", "派驻议事台", "choice", "决定此后的道路", "分散派驻让新增巡守留在已修复节点；集中安置让新增幸存者聚在一个避难据点。既有检查点、回城和前哨巡守都继续保留。", [], {"choices": [{"id": "distributed", "title": "分散派驻"}, {"id": "centralized", "title": "集中安置"}]}),
				_action("settle", "c6:beacon", "最终派驻名册", "repair", "落实派驻安排", "你把选定方案记入最终名册。后记只列出真正完成的救援、修复和支线；未走过的路仍留白。", ["ending"], {"service": "ending_station", "ending": true})])]),

	]

static func side_chains() -> Array:
	if not _groups.has("side_chains"): _groups["side_chains"] = _seal(_side_chains())
	return _groups["side_chains"]

static func _side_chains() -> Array:
	return []

static func regional_arcs() -> Array:
	if not _groups.has("regional_arcs"): _groups["regional_arcs"] = _seal(_regional_arcs())
	return _groups["regional_arcs"]

static func _regional_arcs() -> Array:
	return []

static func random_templates() -> Array:
	if not _groups.has("random_templates"): _groups["random_templates"] = _seal(_random_templates())
	return _groups["random_templates"]

static func _random_templates() -> Array:
	return []

static func world_arcs() -> Array:
	if not _groups.has("world_arcs"): _groups["world_arcs"] = _seal(_world_arcs())
	return _groups["world_arcs"]

static func _world_arcs() -> Array:
	return []

static func chapter(id: String) -> Dictionary:
	for entry: Dictionary in main_chapters():
		if entry["id"] == id: return entry
	return {}

static func all_stages(seed: int = 0) -> Array:
	if _stages.has(seed): return _stages[seed]
	if _stages.size() >= 16:
		_stages.clear()
		_stage_maps.clear()
		_action_maps.clear()
	var result: Array = []
	for group: Array in [main_chapters(), side_chains(), regional_arcs(), world_arcs()]:
		for entry: Dictionary in group: result.append_array(entry["steps"])
	for template: Dictionary in random_templates():
		for serial: int in range(RANDOM_PER_TEMPLATE):
			var source: Dictionary = template["steps"][0]
			var instance_id := str(template["id"]) + ":" + str(seed) + ":" + str(serial)
			var entry: Dictionary = _remap(source, str(template["id"]), instance_id)
			entry["id"] = instance_id
			entry["chain"] = str(template["id"])
			entry["template"] = template["id"]
			entry["serial"] = serial
			entry["seed"] = seed
			entry["previous"] = ""
			entry["required"] = []
			for action_entry: Dictionary in entry["actions"]:
				action_entry["id"] = str(action_entry["id"]).replace(instance_id + ":s1:", instance_id + ":")
				action_entry["stage"] = instance_id
				action_entry["chain"] = str(template["id"])
				for i: int in range(action_entry["requires"].size()):
					action_entry["requires"][i] = str(action_entry["requires"][i]).replace(instance_id + ":s1:", instance_id + ":")
				if not action_entry.get("optional", false): entry["required"].append(action_entry["id"])
			result.append(entry)
	var stage_map: Dictionary = {}
	var action_map: Dictionary = {}
	for entry: Dictionary in result:
		stage_map[entry["id"]] = entry
		for a: Dictionary in entry["actions"]: action_map[a["id"]] = a
	_stages[seed] = _seal(result)
	_stage_maps[seed] = _seal(stage_map)
	_action_maps[seed] = _seal(action_map)
	return _stages[seed]

static func stage(id: String) -> Dictionary:
	var seed := 0
	if id.begins_with("random_"):
		var parts := id.split(":")
		if parts.size() != 3 or not parts[1].is_valid_int() or not parts[2].is_valid_int(): return {}
		seed = int(parts[1])
	all_stages(seed)
	return _stage_maps[seed].get(id, {})

static func actions(seed: int = 0) -> Dictionary:
	all_stages(seed)
	return _action_maps[seed]

static func action(stage_id: String, action_id: String) -> Dictionary:
	for a: Dictionary in stage(stage_id).get("actions", []):
		if a["id"] == action_id: return a
	return {}

static func chains() -> Array:
	var result: Array = main_chapters().duplicate()
	result.append_array(side_chains())
	result.append_array(regional_arcs())
	result = result.duplicate()
	result.append_array(world_arcs())
	result.append_array(random_templates())
	return result

static func chain(id: String) -> Dictionary:
	for entry: Dictionary in chains():
		if entry["id"] == id: return entry
	return {}

static func _chapter(id: String, title: String, terrain: String, number: int, steps: Array) -> Dictionary:
	return _chain(id, title, terrain, "main", number, steps)

static func _chain(id: String, title: String, terrain: String, family: String, number: int, steps: Array) -> Dictionary:
	var previous := ""
	for i: int in range(steps.size()):
		var s: Dictionary = steps[i]
		s["id"] = id + ":s" + str(i + 1)
		s["chain"] = id
		s["chapter"] = id if family == "main" else ""
		s["family"] = family
		s["index"] = i
		s["terrain"] = terrain
		s["previous"] = previous
		s["required"] = []
		for a: Dictionary in s["actions"]:
			a["id"] = s["id"] + ":" + str(a["id"])
			a["stage"] = s["id"]
			a["chapter"] = s["chapter"]
			a["chain"] = id
			var dependencies: Array = []
			for required: String in a.get("requires", []):
				dependencies.append(s["id"] + ":" + required)
			a["requires"] = dependencies
			if not a.get("optional", false): s["required"].append(a["id"])
		previous = s["id"]
	return {"id": id, "title": title, "terrain": terrain, "family": family, "number": number,
		"steps": steps, "unlock_after": "" if family == "main" else {"plains": "chapter1", "forest": "chapter1", "swamp": "watch_c2_forest", "hill": "watch_c3_swamp", "snow": "watch_c4_hill", "lava": "watch_c5_snow", "local": "chapter1", "world": "chapter1"}.get(terrain, ""), "batch": 1 if family == "main" and number == 2 else (2 if family == "main" else (3 if family in ["side", "regional"] else 4))}

static func _step(title: String, objective: String, action_list: Array) -> Dictionary:
	return {"title": title, "objective": objective, "actions": action_list}

static func _action(id: String, object: String, title: String, kind: String, verb: String, text: String, requires: Array = [], extra: Dictionary = {}) -> Dictionary:
	var out := {"id": id, "object": object, "title": title, "kind": kind, "verb": verb, "text": text, "requires": requires}
	out.merge(extra, true)
	return out


static func _remap(value: Variant, old_prefix: String, new_prefix: String) -> Variant:
	if value is String: return value.replace(old_prefix + ":", new_prefix + ":")
	if value is Array:
		var array: Array = []
		for child: Variant in value: array.append(_remap(child, old_prefix, new_prefix))
		return array
	if value is Dictionary:
		var dictionary: Dictionary = {}
		for key: Variant in value: dictionary[key] = _remap(value[key], old_prefix, new_prefix)
		return dictionary
	return value

static func _seal(value: Variant) -> Variant:
	if value is Array:
		for child: Variant in value: _seal(child)
		value.make_read_only()
	elif value is Dictionary:
		for child: Variant in value.values(): _seal(child)
		value.make_read_only()
	return value
