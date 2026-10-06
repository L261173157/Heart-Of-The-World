## 真实库存结算的显示收据：区分可用与待领取，不能用最终99反推本次收入。
extends Node

var checks := 0
var failures := 0
var receipts: Array[Dictionary] = []
var reenter := false

func _ready() -> void:
	GameState.save_enabled = false
	GameState.reset_all()
	EventBus.item_reward_received.connect(_received)
	EventBus.item_gained.connect(_legacy_callback)
	GameState.add_item("onigiri", 98)
	check(receipts.back() == {"id":"onigiri", "stored":98, "pending":0, "total":98}, "普通结算完整收入进入可用库存")
	GameState.add_item("onigiri", 3)
	check(receipts.back() == {"id":"onigiri", "stored":1, "pending":2, "total":99}, "98加3明确一件入包两件待领取")
	GameState.add_item("onigiri", 2)
	check(receipts.back() == {"id":"onigiri", "stored":0, "pending":2, "total":99}, "满99后收入全部标记待领取")
	check(_pending("onigiri") == 4, "全部溢出余额守恒")
	var before := receipts.size()
	check(GameState.apply_inventory_transaction({}, {"onigiri":3}, "feedback:once"), "一次性来源完整支付")
	check(not GameState.apply_inventory_transaction({}, {"onigiri":3}, "feedback:once"), "来源重复支付被拒绝")
	check(receipts.size() == before + 1 and _pending("onigiri") == 7, "重复来源既不发收入提示也不增加余额")
	GameState.remove_item("onigiri", 2)
	var first := str(GameState.pending_items.keys()[0])
	var result := GameState.equipment_action("claim_pending", {"id":first}, GameState.equipment_revision())
	check(result.get("claimed", 0) == 2 and GameState.count_item("onigiri") == 99 and _pending("onigiri") == 5, "部分领取仅转移空位且保留其他收据")
	check(receipts.size() == before + 1, "待领取转移不冒充新掉落重复播报")
	# 成本先扣除，收入提示仍按这笔结算真正增加的可用数量计算。
	check(GameState.apply_inventory_transaction({"onigiri":4}, {"onigiri":6}), "同物品成本和收入可原子结算")
	check(receipts.back() == {"id":"onigiri", "stored":4, "pending":2, "total":99}, "成本腾出四格，六份收入准确分配")
	# 旧事件的同步订阅者可继续消费；新事件必须描述本笔已提交快照。
	GameState.remove_item("onigiri", 1)
	reenter = true
	GameState.add_item("onigiri", 3)
	reenter = false
	check(receipts.back() == {"id":"onigiri", "stored":1, "pending":2, "total":99}, "同步消费不会篡改本笔显示收据")
	check(GameState.count_item("onigiri") == 98, "测试确实执行了真实同步消费")
	GameState.gold = 100
	before = receipts.size()
	check(GameState.buy_item("onigiri"), "有空位实际购买")
	check(receipts.size() == before + 1 and receipts.back() == {"id":"onigiri", "stored":1, "pending":0, "total":99}, "购买也遵循准确收入显示契约")
	check(not GameState.buy_item("onigiri") and receipts.size() == before + 1, "满格拒绝购买不虚报收入")
	GameState._future_save_version = 999
	before = receipts.size()
	GameState.add_item("onigiri", 5)
	check(receipts.size() == before, "只读未来档拒绝收入时没有误导提示")
	GameState._future_save_version = 0
	EventBus.item_reward_received.disconnect(_received)
	EventBus.item_gained.disconnect(_legacy_callback)
	print("=== REWARD FEEDBACK %s (%d checks) ===" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(1 if failures else 0)

func _received(id: String, stored: int, pending: int, total: int) -> void:
	receipts.append({"id":id, "stored":stored, "pending":pending, "total":total})
	check(GameState._world_reward_depth > 0, "反馈发出时仍处于保存事务内")

func _legacy_callback(id: String, _count: int, _total: int) -> void:
	if reenter: GameState.remove_item(id, 1)

func _pending(id: String) -> int:
	var count := 0
	for row: Dictionary in GameState.pending_items.values():
		if str(row.get("item_id", "")) == id: count += int(row.get("count", 0))
	return count

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + label)
