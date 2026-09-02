## 战斗公式（纯静态方法，无状态）。
## 策划纲要：武器/装备的攻防为百分比修正、防御力为降低伤害百分比。
## M0 只有角色裸属性 + ±10% 随机浮动；装备百分比修正 M1 接入。
class_name CombatMath


static func roll_variance(base: float, spread := 0.1) -> float:
	return base * randf_range(1.0 - spread, 1.0 + spread)


## defense_reduction: 0.0~0.8 的减伤比例
static func physical_damage(attack: float, defense_reduction := 0.0) -> float:
	var reduction: float = clampf(defense_reduction, 0.0, 0.8)
	return maxf(1.0, roll_variance(attack) * (1.0 - reduction))


static func magic_damage(attack: float, defense_reduction := 0.0) -> float:
	var reduction: float = clampf(defense_reduction, 0.0, 0.8)
	return maxf(1.0, roll_variance(attack) * (1.0 - reduction))


## 元素克制倍率：火克冰、冰克火（×1.5），同元素互抗（×0.8），无元素/无克制 ×1.0
static func elemental_multiplier(player_element: String, monster_element: String) -> float:
	if player_element == "" or monster_element == "":
		return 1.0
	if player_element == monster_element:
		return 0.8
	return 1.5
