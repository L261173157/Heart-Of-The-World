## 战斗公式（纯静态方法，无状态）。
## 策划纲要：武器/装备的攻防为百分比修正、防御力为降低伤害百分比。
## M0 只有角色裸属性 + ±10% 随机浮动；装备百分比修正 M1 接入。
class_name CombatMath


## 击退基础速度（px/s）：玩家命中怪物的击退基数，重击翻倍、
## 抗性并联合成后衰减——手感目标带见 CombatBandMath
const KNOCKBACK_BASE := 170.0
## 普通目标约16px、重击最多30px；击退赐福不能无限放大移位。
const KNOCKBACK_HEAVY_MULT := 1.5
const KNOCKBACK_MAX_SPEED := 230.0
const KNOCKBACK_BOSS_MAX_SPEED := 12.0
const KNOCKBACK_MIN_SPEED := 18.0
const KNOCKBACK_RETRIGGER := 0.20


static func roll_variance(base: float, spread := 0.1) -> float:
	return base * randf_range(1.0 - spread, 1.0 + spread)


## 物理伤害：±10% 随机浮动，下限 1。
## 护甲减免不在公式里——实战护甲统一在 MonsterBase.take_damage 二次应用
## （自带 clamp+min1），此处再收 defense 参数会导致双重减免
static func physical_damage(attack: float) -> float:
	return maxf(1.0, roll_variance(attack))


## 法术伤害：与物理同构（怪物法伤在 Projectile/MonsterBase 侧无二次护甲）
static func magic_damage(attack: float) -> float:
	return maxf(1.0, roll_variance(attack))


## 元素克制表（攻方元素 → 被克制的守方元素）。
## 显式表而非"不同即克制"：未来加入第三元素（如雷）时不会自动全互克
const COUNTERS := {"fire": "ice", "ice": "fire"}


## 元素克制倍率：火克冰、冰克火（×1.5），同元素互抗（×0.8），无元素/无克制 ×1.0
static func elemental_multiplier(player_element: String, monster_element: String) -> float:
	if player_element == "" or monster_element == "":
		return 1.0
	if player_element == monster_element:
		return 0.8
	if COUNTERS.get(player_element, "") == monster_element:
		return 1.5
	return 1.0
