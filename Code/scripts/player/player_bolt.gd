## 玩家法弹（智力系远程）：直线飞行，命中怪物结算魔法伤害，超时自毁。
## 与雪蝎弹幕（Projectile）对称的玩家侧投射物——碰撞只检测怪物（layer 2），
## 让"堆智力"成为与"堆力量近战"并行的构筑路线。
class_name PlayerBolt
extends Area2D

const LIFE_TIME := 1.1
const SPEED := 420.0

var direction := Vector2.RIGHT
var damage := 5.0
## 玩家元素（launch 传入）：命中时按目标元素算克制倍率
var player_element := ""

var _life := LIFE_TIME


func launch(dir: Vector2, dmg: float, p_element := "") -> void:
	direction = dir.normalized()
	damage = dmg
	player_element = p_element
	rotation = direction.angle()


func _ready() -> void:
	add_to_group("player_bolts")
	# 只检测怪物与巢穴（layer 2）；Area2D 默认 mask=1 会打不中任何目标
	collision_layer = 0
	collision_mask = 2
	body_entered.connect(_on_body_entered)
	# 淡金色小光点（占位几何，素材期替换）
	var visual := Polygon2D.new()
	visual.polygon = PackedVector2Array([
		Vector2(10, 0), Vector2(2, -5), Vector2(-8, 0), Vector2(2, 5),
	])
	visual.color = Color(1.0, 0.92, 0.55)
	add_child(visual)
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 6.0
	shape.shape = circle
	add_child(shape)


func _physics_process(delta: float) -> void:
	position += direction * SPEED * delta
	_life -= delta
	if _life <= 0.0:
		queue_free()


func _on_body_entered(body: Node2D) -> void:
	if (body.is_in_group("monsters") or body.is_in_group("nests")) and body.has_method("take_damage"):
		var dealt: float = damage
		var effective := false
		var monster := body as MonsterBase
		if monster != null and monster.inst != null:
			var em: float = CombatMath.elemental_multiplier(player_element, monster.inst.species.element)
			dealt *= em
			effective = em > 1.0
		body.take_damage(dealt, global_position, false, 1.0, effective)
		queue_free()
