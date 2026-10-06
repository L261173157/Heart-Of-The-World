## 专用测试故障注入：真实库存接口拒绝扣钥匙，验证调用方不提前消费收据。
extends "res://autoload/game_state.gd"

var reject_key := true
var remove_attempts := 0

func remove_item(id: String, count: int = 1) -> bool:
	remove_attempts += 1
	if reject_key: return false
	return super.remove_item(id, count)
