## 哥布林：群体围攻——任意一只受击，侦测圈外的邻近同伴也会闻声赶来（仇恨连锁），
## 数量是它们的武器；单独引怪是对付群体的基本打法。
class_name Goblin
extends MonsterBase

const ASSIST_RADIUS := 260.0


func ally_assist_radius() -> float:
	return ASSIST_RADIUS
