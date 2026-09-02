## 寿命统一公式（纯静态，角色与怪物共用）。
## 角色侧：LifespanMath 驱动 CharacterStats 的寿命/衰老（单位：游戏天）；
## 怪物侧：EcologySim 的老死判定（单位：tick）。
## 永久死亡机制（策划：到点变鬼魂）待定池后置，当前到点只做属性衰老。
## 放在 ecology/ 内保持"整体平移服务器"的自包含（角色侧反向依赖纯逻辑层是允许方向）。
class_name LifespanMath
extends RefCounted

## 风烛残年衰减下限与触发窗口（剩余寿命 ≤ 窗口即开始衰减）
const DECAY_FLOOR := 0.6
const DECAY_WINDOW := 5.0


static func remaining(age: float, lifespan: float) -> float:
	return lifespan - age


static func is_expired(age: float, lifespan: float) -> bool:
	return age >= lifespan


## 衰减乘子：寿命充裕为 1.0；剩余 ≤ DECAY_WINDOW 天内从 1.0 线性滑向
## DECAY_FLOOR（衰老是渐进的压力不是悬崖），到点后维持下限
static func decay_mult(age: float, lifespan: float) -> float:
	var left := remaining(age, lifespan)
	if left >= DECAY_WINDOW:
		return 1.0
	var t := clampf(left / DECAY_WINDOW, 0.0, 1.0)
	return lerpf(DECAY_FLOOR, 1.0, t)
