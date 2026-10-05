## 同步库存交易：先验支出，奖励溢出转入持久待领取，整个任务收据仍只支付一次。
class_name CampQuestInventory
extends RefCounted

static func can_apply(costs: Dictionary, rewards: Dictionary) -> bool:
	return GameState.can_apply_inventory_transaction(costs, rewards)

static func apply(costs: Dictionary, rewards: Dictionary) -> bool:
	return GameState.apply_inventory_transaction(costs, rewards)
