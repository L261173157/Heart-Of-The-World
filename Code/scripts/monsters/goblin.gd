## 火把哥布林：群体围攻——任意一只受击，侦测圈外的邻近同伴也会闻声赶来（仇恨连锁），
## 数量是它们的武器；单独引怪是对付群体的基本打法。
## 支援半径读 SpeciesData（火把哥布林/蜥蜴刀客/白骨兵/巨蝠/小魔鬼共用本原型，可按物种调参）
class_name Goblin
extends MonsterBase


func ally_assist_radius() -> float:
	return inst.species.assist_radius


## 围攻原型的近圈择侧幅度，保持各物种的移动性格。
func _pressure_flank_mult() -> float:
	return 1.0
