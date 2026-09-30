## 骷髅兵：协同近战——攻击快、护甲厚，附近同伴越多伤害越高（蚁群协同）；
## 同伴受击也会响应。生态上是入侵物种：快繁快死 + 低阈值强扩张，
## 会持续从丘陵涌入熔岩洞窟，挤压石魔像的生存空间。
## 协同参数（群体半径/每只加成/上限/支援半径）读 SpeciesData——
## 地精矿工/雪怪/獾王共用本原型，可按物种调参
class_name Ant
extends MonsterBase


func _perform_attack(player: Node2D) -> void:
	var bonus := 1.0 + inst.species.pack_bonus_per \
			* mini(inst.species.pack_bonus_max, _pack_count())
	if player.has_method("take_damage"):
		player.take_damage(CombatMath.physical_damage(inst.attack_power() * bonus), global_position, inst.display_name())


## 蚁群计数短缓存：蚁海互攻时避免每次攻击都全量组遍历
var _pack_count_cache := -1
var _pack_count_timer := 0.0


func _physics_process(delta: float) -> void:
	if _pack_count_timer > 0.0:
		_pack_count_timer -= delta
	else:
		_pack_count_cache = -1
	super(delta)


func _pack_count() -> int:
	if _pack_count_cache >= 0:
		return _pack_count_cache
	# 物种注册表只含本物种（基类维护），免掉全怪组遍历的过滤开销
	var count := 0
	var list: Array = _species_registry.get(inst.species.species_name)
	if list != null:
		for other: MonsterBase in list:
			if other == self or other.state == S_CORPSE:
				continue
			if global_position.distance_to(other.global_position) <= inst.species.pack_radius:
				count += 1
	_pack_count_cache = count
	_pack_count_timer = 0.5
	return count


func ally_assist_radius() -> float:
	return inst.species.assist_radius
