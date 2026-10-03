## 敌方出招元数据：强度是本次招式的确定性、浮动前攻击力，不是最终扣血。
## 全局递增 ID 不依赖节点实例 ID，池化弹幕复用也不会把两发认成同一击。
extends RefCounted

static var _next_attack_id := 0


static func create(strength: float, blockable := true,
		incoming_direction := Vector2.ZERO) -> Dictionary:
	_next_attack_id += 1
	return {
		"strength": maxf(0.0, strength),
		"blockable": blockable,
		"incoming_direction": incoming_direction.normalized(),
		"attack_id": "enemy_attack_%d" % _next_attack_id,
	}
