## 《断开的守望》作者内容目录。ID 是存档合同，不随显示名或接单次数重写。
## 第一章继续由 OutpostQuestData 持有；这里不复制它的证据或39/44旧预算。
class_name CampaignCatalog
extends RefCounted

const ID := "campaign_watch_v1"
const VERSION := 1
const RANDOM_LIMIT := 30
const RANDOM_PER_TEMPLATE := 3

static func main_chapters() -> Array:
	return [
		_chapter("watch_c2_forest", "林间旧约", "forest", 2, [
			_step("古树下的旧约", "询问林地药师，再亲自读完古树下的旧约。", [
				_action("herbalist", "c2:herbalist", "林地药师", "talk", "询问旧哨所", "药师把一页叶脉拓本交给你：林下三枚符标仍沿用旧约的次序，先去古树寻找原文。"),
				_action("old_pact", "c2:old_pact", "古树下的旧约", "read", "读旧约", "旧约记着人类曾为巡林者保留过林下通路。文字没有许诺安全，只留下三枚符标与失散联络员的名字。", ["herbalist"])]),
			_step("林下通道", "读出北、东、西的符标次序，开启栅门后步行取回残页。", [
				_action("route_marks", "c2:route_marks", "旧路标刻痕", "read", "辨读刻痕", "刻痕由晨露、日影与归鸟串起：先北，再东，最后西。按错只会熄灭已亮的符标，可以重新尝试。"),
				_action("runes", "c2:forest_gate", "三枚林下符标", "puzzle", "核对符标", "三枚符标依次亮起，旧栅门的锁舌松开。残页仍在门后，需要你亲自走过去。", ["route_marks"], {"puzzle_order": ["north", "east", "west"], "puzzle_objects": ["c2:rune_north", "c2:rune_east", "c2:rune_west"]}),
				_action("torn_record", "c2:torn_record", "被撕开的守望记录", "recover", "拾起残页", "残页上的信号图并不完整。末行写着：联络员仍守着东侧歇脚处，补给没有送到。", ["runes"])]),
			_step("留在林地的人", "找到失联联络员，取回专用急救包，再回到他身边救治。", [
				_action("liaison", "c2:liaison", "负伤联络员", "talk", "查看伤势", "联络员无法继续行走。他指出树根后的封存急救箱，并请你把信号重新送上山脊。"),
				_action("aid_cache", "c2:aid_cache", "联络站急救箱", "recover", "取专用急救包", "你取出联络站封存的急救包。它只用于这次救援，不占背包，也不会被快捷补给消耗。", ["liaison"], {"quest_item": "c2:aid"}),
				_action("rescue", "c2:liaison", "负伤联络员", "rescue", "为联络员包扎", "你在联络员身旁完成包扎。他能留守联络站了，但仍不能代替你去修复烽灯。", ["aid_cache"])]),
			_step("第一束信号", "回收信号零件，在烽灯处亲手恢复第一束信号。", [
				_action("signal_parts", "c2:signal_parts", "封存的信号零件", "recover", "回收零件", "木匣内保留着遮光片与旧灯芯。零件齐了，灯塔还需要现场装配。", [], {"quest_item": "c2:signal_parts"}),
				_action("beacon", "c2:beacon", "林地烽灯", "repair", "修复烽灯", "林地烽灯重新亮起。联络员留下值守，证实远征队曾分赴沼泽与丘陵，并交给你沼泽接应点的旧坐标；灯亮不代表林路已经安全。", ["signal_parts"], {"service": "forest_station", "next_chapter": "watch_c3_swamp"})])]),
	]

static func side_chains() -> Array:
	return []

static func regional_arcs() -> Array:
	return []

static func random_templates() -> Array:
	return []

static func world_arcs() -> Array:
	return []

static func chapter(id: String) -> Dictionary:
	for entry: Dictionary in main_chapters():
		if entry["id"] == id: return entry
	return {}

static func all_stages() -> Array:
	var result: Array = []
	for group: Array in [main_chapters(), side_chains(), regional_arcs(), world_arcs()]:
		for chain: Dictionary in group:
			result.append_array(chain["steps"])
	for template: Dictionary in random_templates():
		for serial: int in range(1, RANDOM_PER_TEMPLATE + 1):
			var s: Dictionary = template["steps"][0].duplicate(true)
			s["id"] = str(template["id"]) + ":" + str(serial)
			s["template"] = template["id"]
			s["serial"] = serial
			for a: Dictionary in s["actions"]:
				a["stage"] = s["id"]
			result.append(s)
	return result

static func stage(id: String) -> Dictionary:
	for entry: Dictionary in all_stages():
		if entry["id"] == id: return entry
	return {}

static func actions() -> Dictionary:
	var out: Dictionary = {}
	for s: Dictionary in all_stages():
		for a: Dictionary in s["actions"]:
			out[a["id"]] = a
	return out

static func action(stage_id: String, action_id: String) -> Dictionary:
	for a: Dictionary in stage(stage_id).get("actions", []):
		if a["id"] == action_id: return a
	return {}

static func chains() -> Array:
	var result: Array = main_chapters()
	result.append_array(side_chains())
	result.append_array(regional_arcs())
	result.append_array(world_arcs())
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
		"steps": steps, "batch": 1 if family == "main" and number == 2 else (2 if family == "main" else (3 if family in ["side", "regional"] else 4))}

static func _step(title: String, objective: String, action_list: Array) -> Dictionary:
	return {"title": title, "objective": objective, "actions": action_list}

static func _action(id: String, object: String, title: String, kind: String, verb: String, text: String, requires: Array = [], extra: Dictionary = {}) -> Dictionary:
	var out := {"id": id, "object": object, "title": title, "kind": kind, "verb": verb, "text": text, "requires": requires}
	out.merge(extra, true)
	return out
