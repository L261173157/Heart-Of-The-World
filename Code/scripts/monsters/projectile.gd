## 远程弹幕（雪蝎吐息）：直线飞行，命中玩家结算伤害，超时自毁。
## 碰撞只检测玩家（layer 1），穿过其它怪物与地形（M0 占位表现）。
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
