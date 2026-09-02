## 哥布林：群体围攻——任意一只受击，侦测圈外的邻近同伴也会闻声赶来（仇恨连锁），
## 数量是它们的武器；单独引怪是对付群体的基本打法。
class_name Goblin
extends MonsterBase

const ASSIST_RADIUS := 260.0


func _ready() -> void:
	super()
	EventBus.combat_ally_hit.connect(_on_ally_hit)


func _on_ally_hit(species_name: String, hit_position: Vector2) -> void:
	if species_name != inst.species.species_name or state == S_CORPSE:
		return
	if global_position.distance_to(hit_position) > ASSIST_RADIUS:
		return
	if state == S_PATROL or state == S_MIGRATING:
		state = S_CHASE
	_aggro_lock = 3.0
