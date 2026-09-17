## 玩家法弹（智力系远程）：直线飞行，命中怪物结算魔法伤害，超时自毁。
## 与沼泽蟹弹幕（Projectile）对称的玩家侧投射物——碰撞只检测怪物（layer 2），
## 让"堆智力"成为与"堆力量近战"并行的构筑路线。
class_name PlayerBolt
extends Area2D

## 寿命对齐沼泽蟹弹幕射程（270×2.2≈594px）：此前 420×1.1≈460px 够不着，
## "与沼泽蟹对射"的智力构筑实际打不出——延寿到 630px 让对射成立，不动 DPS 结构
const LIFE_TIME := 1.5
const SPEED := 420.0

var direction := Vector2.RIGHT
var damage := 5.0
## 玩家元素（launch 传入）：命中时按目标元素算克制倍率
var player_element := ""

var _life := LIFE_TIME
## 单次命中守卫：queue_free 到帧末才释放，同一物理帧与多个重叠碰撞体的
## body_entered 会全部派发——没有守卫时一发弹对怪堆结算多次伤害
var _hit := false


func launch(dir: Vector2, dmg: float, p_element := "") -> void:
	direction = dir.normalized()
	damage = dmg
	player_element = p_element
	rotation = direction.angle()


func _ready() -> void:
	add_to_group("player_bolts")
	# 检测怪物（layer 2）、巢穴（layer 4）与地形墙（layer 1，撞墙消散）；
	# mask 含 1 会同时检测到玩家身体——handler 只认 monsters/nests 组，自然忽略
	collision_layer = 0
	collision_mask = 7
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
	if _hit:
		return
	# 撞墙消散（法弹不再穿地形——隔墙输出曾是申报的 M0 设计债，2026-09-04 清偿）；
	# 巢穴也是 StaticBody2D 但属攻击目标，交给下方怪物/巢穴分支结算
	if body is StaticBody2D and not body.is_in_group("nests"):
		_hit = true
		queue_free()
		return
	# 障碍瓦片（世界 v5）：可破坏类型吃弹破块（TileMapLayer 碰撞体非 StaticBody2D，
	# 曾被上方分支漏掉直穿）；命中格按弹体前缘换算
	if body is TileMapLayer:
		_hit = true
		var cell := Vector2i(floori(global_position.x / 32.0), floori(global_position.y / 32.0))
		var kind := ObstacleField.damage_cell(cell)
		if kind != "":
			EventBus.obstacle_destroyed.emit(cell,
					(Vector2(cell) + Vector2(0.5, 0.5)) * 32.0, kind)
			if randf() < ObstacleField.DESTROY_GOLD_CHANCE:
				var amount := randi_range(int(ObstacleField.DESTROY_GOLD_RANGE[0]),
						int(ObstacleField.DESTROY_GOLD_RANGE[1]))
				GameState.add_gold(amount)
				EventBus.world_event.emit("💎 碎石中拾得 %d 金币" % amount)
		queue_free()
		return
	if (body.is_in_group("monsters") or body.is_in_group("nests")) and body.has_method("take_damage"):
		# 尸体不吸收法弹（与普攻/重击同口径）：死亡当帧碰撞层到帧末才清零，
		# 不查尸体状态会让刚死的目标"白吃"一发本可打到后面活怪的弹
		var corpse := body as MonsterBase
		if corpse != null and corpse.state == MonsterBase.S_CORPSE:
			return
		_hit = true
		var dealt: float = damage
		var effective := false
		var monster := body as MonsterBase
		if monster != null and monster.inst != null:
			var em: float = CombatMath.elemental_multiplier(player_element, monster.inst.species.element)
			dealt *= em
			effective = em > 1.0
		body.take_damage(dealt, global_position, false, 1.0, effective)
		# 命中魔光（美术 v5 fx 全量）：克制时换元素色系
		EventBus.fx_requested.emit(
			"flame" if effective and player_element == "fire"
			else "frost" if effective and player_element == "ice"
			else "magic",
			global_position, 0.9)
		queue_free()
