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
		return str(quest.get("ui_objective", "与营地巡守交谈"))
	if quest.get("settlement_blocked", false):
		return "奖励待发：请腾出%s空间，材料与奖励保留" % ItemCatalog.name_of(str(quest.get("blocked_item", "")))
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
			return "跟随雷达猎杀目标 · 达成自动领奖"
		"ransack":
			return "跟随雷达捣毁巢穴 · 达成自动领奖"
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
	return view


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
