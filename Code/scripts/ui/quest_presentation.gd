## 委托表现真源：状态来自当前进度/收据，HUD 与 NPC 不各自猜测颜色和文案。
## 旧存档未带 claim_at_npc 的收集单仍按原规则自动交付。
class_name QuestPresentation
extends RefCounted

const AVAILABLE_COLOR := Color("ffe28a")
const PROGRESS_COLOR := Color("b8d9ed")
const CLAIMABLE_COLOR := Color("99f1b1")
const COMPLETED_COLOR := Color("bfebcb")


static func requires_claim(quest: Dictionary) -> bool:
	return quest.get("kind", "") in ["collect", "camp_ecology", "outpost", "campaign"] and quest.get("claim_at_npc", false) == true


static func state(quest: Dictionary) -> String:
	if requires_claim(quest) and int(quest.get("progress", 0)) >= int(quest.get("need", 1)):
		return "claimable"
	return "in_progress"


static func objective(quest: Dictionary) -> String:
	if quest.get("kind", "") in ["camp_ecology", "outpost", "campaign"]:
		return str(quest.get("ui_objective", "与营地巡守周照交谈"))
	if quest.get("settlement_blocked", false):
		return "奖励待发：当前无法结算，材料与奖励保留"
	if state(quest) == "claimable":
		return "返回%s，交付领奖" % quest.get("giver", "委托人")
	match str(quest.get("kind", "")):
		"collect":
			var action := "再收集 %d 个%s" % [maxi(0, int(quest.get("need", 1)) - int(quest.get("progress", 0))),
					ItemCatalog.name_of(str(quest.get("item", "")))]
			return action + ("，交给%s" % quest.get("giver", "委托人") if requires_claim(quest) else " · 达成自动交付")
		"hunt":
			if quest.get("hunt_waiting", false):
				return "等待本地目标恢复 · 已有进度保留"
			return "去%s寻找%s · 居民提供搜索区域，目视后雷达标记目标 · 达成自动领奖" % [hunt_area(quest), quest.get("species", "目标")]
		"ransack":
			return "寻找并捣毁巢穴 · 目视后雷达标记目标 · 达成自动领奖"
		_:
			return "发现尚未到访的地标 · 达成自动领奖"


static func reward(quest: Dictionary) -> String:
	var text := "+%d 金币  +%d 经验" % [int(quest.get("gold", 0)), int(quest.get("xp", 0))]
	var bonus := bonus_item(quest)
	if bonus != "":
		text += "  +" + ItemCatalog.name_of(bonus)
	return text


static func snapshot(quest: Dictionary) -> Dictionary:
	if quest.get("kind", "") in ["camp_ecology", "outpost", "campaign"]:
		return quest.duplicate(true)
	var view := quest.duplicate(true)
	view["ui_state"] = state(quest)
	view["ui_status"] = "奖励待发" if quest.get("settlement_blocked", false) else ("可交付" if view["ui_state"] == "claimable" else "进行中")
	view["ui_objective"] = objective(quest)
	view["ui_reward"] = reward(quest)
	view["next_action"] = next_action(quest)
	view["step_progress"] = "%d/%d" % [int(quest.get("progress", 0)), int(quest.get("need", 1))]
	view["target_title"] = str(quest.get("giver", "委托人")) if state(quest) == "claimable" else str(quest.get("species", ItemCatalog.name_of(str(quest.get("item", "")))))
	if quest.get("kind", "") == "hunt":
		view["ui_title"] = "猎杀委托"
		# 线索只来自居民所指区域的中心，绝不读取隐藏个体的当前坐标。
		var region := WorldSim.sim.get_region(str(quest.get("hunt_region", ""))) if WorldSim.sim != null else null
		if region != null and not quest.get("hunt_waiting", false):
			view["target_pos"] = [region.center.x, region.center.y]
			view["target_name"] = region.display_name + "搜索区域"
			view["ui_guide_mode"] = "hunt_area"
			view["ui_knowledge"] = "npc_intel"
	return view


static func hunt_area(quest: Dictionary) -> String:
	var region := WorldSim.sim.get_region(str(quest.get("hunt_region", ""))) if WorldSim.sim != null else null
	return region.display_name if region != null else "委托人附近"


## 下一步是独立数据；详情中的标点不承担结构，避免截去具体对象或返程提示。
static func next_action(quest: Dictionary) -> String:
	if quest.has("next_action"):
		return str(quest["next_action"])
	if quest.get("settlement_blocked", false):
		return "稍后重试领取奖励"
	if state(quest) == "claimable":
		return "返回%s交付领奖" % quest.get("giver", "委托人")
	match str(quest.get("kind", "")):
		"collect": return "再收集%d个%s" % [maxi(0, int(quest.get("need", 1)) - int(quest.get("progress", 0))), ItemCatalog.name_of(str(quest.get("item", "")))]
		"hunt":
			return "等待本地目标恢复" if quest.get("hunt_waiting", false) else "去%s寻找%s" % [hunt_area(quest), quest.get("species", "目标")]
		"ransack": return "寻找并捣毁巢穴"
		"explore": return "发现尚未到访的地标"
		_: return str(quest.get("ui_objective", "与委托人交谈"))


static func npc_status(landmark_id: String) -> Dictionary:
	for quest: Dictionary in GameState.quests.get("active", []):
		if str(quest.get("landmark_id", "")) != landmark_id:
			continue
		if quest.get("settlement_blocked", false):
			return {"state": "pending", "marker": "· 奖励待发", "color": PROGRESS_COLOR}
		if state(quest) == "claimable":
			return {"state": "claimable", "marker": "? 可交付", "color": CLAIMABLE_COLOR}
		return {"state": "in_progress", "marker": "· 进行中 %d/%d" % [
				int(quest.get("progress", 0)), int(quest.get("need", 1))], "color": PROGRESS_COLOR}
	if GameState.quests.get("receipts", {}).has(landmark_id):
		return {"state": "completed", "marker": "✓ 已完成 · 新委托", "color": COMPLETED_COLOR}
	return {"state": "available", "marker": "! 可接委托", "color": AVAILABLE_COLOR}


static func receipt_text(receipt: Dictionary) -> String:
	if receipt.is_empty():
		return ""
	return "✓ 已领奖：%s（+%d 金币 +%d 经验%s）" % [receipt.get("title", "委托"),
			int(receipt.get("gold", 0)), int(receipt.get("xp", 0)),
			" +" + ItemCatalog.name_of(str(receipt["bonus"])) if str(receipt.get("bonus", "")) != "" else ""]


## 展示与实际交易共用确定性物品奖励，满仓提示不能猜测另一件补给。
static func bonus_item(quest: Dictionary) -> String:
	if quest.get("kind", "") in ["camp_ecology", "outpost", "campaign"]:
		return str(quest.get("bonus", ""))
	if quest.get("kind", "") == "collect":
		return EconomyMath.KEY_GOLD
	if not quest.get("hunt_adjusted", false) and hash("quest-bonus|%s" % quest.get("id", "")) % 10 < 3:
		var pool: Array = EconomyMath.BOSS_BONUS_POOL
		return pool[hash("quest-bonus2|%s" % quest.get("id", "")) % pool.size()]
	return ""


## 叙事只读载荷：问题不会携带命令，也不写入任务或存档。
static func action_prompt(action: Dictionary) -> String:
	return str(action.get("prompt", action.get("text", "")))


static func dialogue_questions(payload: Dictionary) -> Array:
	var quest: Dictionary = payload.get("quest", {}) if payload.get("quest", {}) is Dictionary else {}
	var source: Variant = payload.get("questions", quest.get("questions", []))
	var result: Array = []
	if not source is Array:
		return result
	for entry: Variant in source:
		if not entry is Dictionary:
			continue
		var label := str(entry.get("label", "")).strip_edges()
		var answer := str(entry.get("answer", "")).strip_edges()
		if not label.is_empty() and not answer.is_empty():
			result.append({"label": label, "answer": answer})
	return result


static func dialogue_rules(payload: Dictionary) -> String:
	var quest: Dictionary = payload.get("quest", {}) if payload.get("quest", {}) is Dictionary else {}
	return str(payload.get("rules", quest.get("rules", ""))).strip_edges()


static func with_narrative(payload: Dictionary, action: Dictionary) -> Dictionary:
	var result := payload.duplicate(true)
	result["questions"] = dialogue_questions(payload if payload.has("questions") else action)
	result["rules"] = dialogue_rules(payload if payload.has("rules") else action)
	return result
