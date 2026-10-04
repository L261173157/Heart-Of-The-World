## 单物品99容量的同步交易：先计入本次材料支出，再核查全部奖励。
## 只在完整可提交时改库存，单次广播，避免扣料信号引发另一单抢占空位。
class_name CampQuestInventory
extends RefCounted

static func can_apply(costs: Dictionary, rewards: Dictionary) -> bool:
	for item: String in costs:
		if not EconomyMath.knows_item(item) or int(costs[item]) < 0 or GameState.count_item(item) < int(costs[item]):
			return false
	for item: String in rewards:
		if not EconomyMath.knows_item(item) or int(rewards[item]) < 0 \
				or GameState.count_item(item) - int(costs.get(item, 0)) + int(rewards[item]) > GameState.ITEM_MAX:
			return false
	return true

static func apply(costs: Dictionary, rewards: Dictionary) -> bool:
	if not can_apply(costs, rewards):
		return false
	for item: String in costs:
		var remaining := GameState.count_item(item) - int(costs[item])
		if remaining == 0:
			GameState.inventory.erase(item)
		else:
			GameState.inventory[item] = remaining
	for item: String in rewards:
		GameState.inventory[item] = GameState.count_item(item) + int(rewards[item])
	GameState._queue_save()
	for item: String in rewards:
		EventBus.item_gained.emit(item, int(rewards[item]), GameState.count_item(item))
	if not costs.is_empty() or not rewards.is_empty():
		EventBus.inventory_changed.emit()
	return true
