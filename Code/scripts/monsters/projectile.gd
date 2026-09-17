## 远程弹幕（沼泽蟹吐息）：直线飞行，命中玩家结算伤害，撞墙消散，超时自毁。
## 碰撞只检测玩家与地形（均 layer 1）；穿过其它怪物（虫海互相挡弹道会自杀）。
class_name Projectile
extends Area2D

const LIFE_TIME := 2.2

var direction := Vector2.RIGHT
var damage := 5.0
var speed := 270.0
## 射手名（死亡信息归因用）
var source_name := ""

var _life := LIFE_TIME


func launch(dir: Vector2, dmg: float, p_speed := 270.0, p_source := "") -> void:
	direction = dir.normalized()
	damage = dmg
	speed = p_speed
	source_name = p_source
	rotation = direction.angle()


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	position += direction * speed * delta
	_life -= delta
	if _life <= 0.0:
		queue_free()


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") and body.has_method("take_damage"):
		body.take_damage(damage, global_position, source_name)
		queue_free()
		return
	# 撞墙消散（不再穿地形，与玩家法弹对称；巢穴在独立层 4 不被检测）。
	# 障碍瓦片（TileMapLayer）同样消散——怪物弹幕不能替玩家开路
	if body is StaticBody2D or body is TileMapLayer:
		queue_free()
