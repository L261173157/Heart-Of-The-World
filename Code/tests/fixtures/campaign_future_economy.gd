## 只供合同不变性回归：模拟将来通用经济大幅调整，不改生产 EconomyMath。
extends RefCounted
static func bounty_gold(target: int, level: int) -> int:
	return 9000 + target * 90 + level * 70
static func bounty_xp(target: int) -> int:
	return 8000 + target * 80
