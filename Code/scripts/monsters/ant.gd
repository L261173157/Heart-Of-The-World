## 兵蚁：协同近战——攻击快、护甲厚，附近同伴越多伤害越高（蚁群协同）；
## 同伴受击也会响应。生态上是入侵物种：快繁快死 + 低阈值强扩张，
## 会持续从丘陵涌入熔岩洞窟，挤压岩甲龟的生存空间。
class_name Ant
extends MonsterBase

const PACK_RADIUS := 130.0
const PACK_BONUS_PER := 0.1
const PACK_BONUS_MAX := 3
const ASSIST_RADIUS := 200.0


func _ready() -> void:
	super()
	EventBus.combat_ally_hit.connect(_on_ally_hit)


func _perform_attack(player: Node2D) -> void:
	var bonus := 1.0 + PACK_BONUS_PER * mini(PACK_BONUS_MAX, _pack_count())
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
	var count := 0
	for body in get_tree().get_nodes_in_group("monsters"):
		var other := body as MonsterBase
		if other == self or other == null or other.inst == null:
			continue
		if other.state == S_CORPSE or other.inst.species != inst.species:
			continue
		if global_position.distance_to(other.global_position) <= PACK_RADIUS:
			count += 1
	_pack_count_cache = count
	_pack_count_timer = 0.5
	return count


func _on_ally_hit(species_name: String, hit_position: Vector2) -> void:
	if species_name != inst.species.species_name or state == S_CORPSE:
		return
	if global_position.distance_to(hit_position) > ASSIST_RADIUS:
		return
	if state == S_PATROL or state == S_MIGRATING:
		state = S_CHASE
	_aggro_lock = 3.0
