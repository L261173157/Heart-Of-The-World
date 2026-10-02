## 玩家法弹：可读的 16px 实心弹核与同半径碰撞，拖尾只表示运动方向。
## 寻星仅追踪前方可见目标；碎星只在命中活体后产生两枚不递归的直线碎片。
class_name PlayerBolt
extends Area2D

const LIFE_TIME := 1.5
const SPEED := 420.0
const HIT_RADIUS := 8.0
const SHARD_LIFE_TIME := 0.65
const SEEK_INTERVAL := 0.12
const SEEK_RADIUS := 220.0
const SEEK_TURN_SPEED := 2.2
const SEEK_HALF_ANGLE := 0.8726646  # 50°，只微调玩家给出的前方方向
const POOL_MAX := 24
static var _pool: Array[PlayerBolt] = []
static var _pool_epoch := 0

var direction := Vector2.RIGHT
var damage := 5.0
var player_element := ""
var _life := LIFE_TIME
var _hit := false
var _pooled := false  # 兼容工具/测试的 new()+launch()，独立创建仍由 queue_free 回收
var _spawn_epoch := 0
var _speed := SPEED
var _seek := false
var _split := false
var _generation := 0
var _split_damage := 0.0
var _seek_timer := 0.0
var _target: Node2D
var _launch_direction := Vector2.RIGHT
var _ignore_rid := RID()
var _seek_scans := 0
var _seek_shape: CircleShape2D
var _hit_shape: CircleShape2D


static func spawn(parent: Node, pos: Vector2, dir: Vector2, dmg: float,
		p_element := "", effects: Dictionary = {}) -> PlayerBolt:
	var p: PlayerBolt = _pool.pop_back() if not _pool.is_empty() else PlayerBolt.new()
	p._pooled = true
	# 空闲节点无树宿主；拥有它们的世界退出时统一清池，不留静态对象。
	if not parent.tree_exiting.is_connected(clear_pool):
		parent.tree_exiting.connect(clear_pool, CONNECT_ONE_SHOT)
	parent.add_child(p)
	p.global_position = pos
	p.launch(dir, dmg, p_element, effects)
	return p


static func clear_pool() -> void:
	_pool_epoch += 1
	for p: PlayerBolt in _pool:
		if is_instance_valid(p):
			p.free()
	_pool.clear()


func launch(dir: Vector2, dmg: float, p_element := "", effects: Dictionary = {}) -> void:
	direction = dir.normalized() if not dir.is_zero_approx() else Vector2.RIGHT
	_launch_direction = direction
	_seek = bool(effects.get("seek", false))
	_split = bool(effects.get("split", false))
	damage = dmg * (CharacterStats.BOLT_SPLIT_DAMAGE if _split else 1.0)
	_split_damage = dmg * CharacterStats.BOLT_SHARD_DAMAGE
	_speed = SPEED * (CharacterStats.BOLT_SEEK_SPEED if _seek else 1.0)
	player_element = p_element
	rotation = direction.angle()
	_life = LIFE_TIME
	_hit = false
	_spawn_epoch = _pool_epoch
	_generation = 0
	_target = null
	_ignore_rid = RID()
	_seek_timer = 0.0
	_seek_scans = 0
	modulate = Color.WHITE
	scale = Vector2.ONE
	show()
	monitoring = true
	set_physics_process(true)
	queue_redraw()


func _ready() -> void:
	add_to_group("player_bolts")
	collision_layer = 0
	collision_mask = 7  # 怪物 2、巢穴 4、地形 1；忽略同层玩家
	body_shape_entered.connect(_on_body_shape_entered)
	var glow := Sprite2D.new()
	glow.name = "CoreGlow"
	glow.texture = preload("res://assets/ts/fx_generated/orb_core.png")
	glow.scale = Vector2(0.65, 0.65)
	glow.modulate.a = 0.6
	glow.show_behind_parent = true
	add_child(glow)
	var shape := CollisionShape2D.new()
	shape.name = "HitShape"
	_hit_shape = CircleShape2D.new()
	_hit_shape.radius = HIT_RADIUS
	shape.shape = _hit_shape
	add_child(shape)
	_seek_shape = CircleShape2D.new()
	_seek_shape.radius = SEEK_RADIUS


func _draw() -> void:
	var tint := Color(0.69, 0.42, 1.0) if not _seek else Color(0.36, 0.73, 1.0)
	var tail := 18.0 if _generation > 0 else 27.0
	draw_colored_polygon(PackedVector2Array([Vector2(-tail, 0), Vector2(-4, -5),
		Vector2(4, 0), Vector2(-4, 5)]), Color(tint, 0.55))
	draw_circle(Vector2.ZERO, HIT_RADIUS, tint)
	draw_circle(Vector2.ZERO, 5.5, Color(0.9, 0.83, 1.0))
	draw_circle(Vector2(1, -1), 2.5, Color(1.0, 1.0, 0.98))
	if _split:
		draw_line(Vector2(-12, -7), Vector2(-7, -4), Color(1.0, 0.76, 1.0), 2.0)
		draw_line(Vector2(-12, 7), Vector2(-7, 4), Color(1.0, 0.76, 1.0), 2.0)


func _physics_process(delta: float) -> void:
	if _hit:
		return
	if _seek:
		_seek_timer -= delta
		if _seek_timer <= 0.0:
			_seek_timer = SEEK_INTERVAL
			_acquire_target()
		if is_instance_valid(_target) and _target_alive(_target):
			var desired := (_target.global_position - global_position).angle()
			direction = Vector2.from_angle(rotate_toward(direction.angle(), desired, SEEK_TURN_SPEED * delta))
		else:
			_target = null
	rotation = direction.angle()
	# 与弹核同半径的连续扫掠，覆盖薄墙/角擦/掉帧和出生重叠；不只扫中心线。
	var step := direction * _speed * delta
	var hit := _sweep(global_position, global_position + step)
	if not hit.is_empty():
		global_position = hit["position"]
		if hit.has("collider"):
			_on_body_shape_entered(hit["rid"], hit["collider"], int(hit["shape"]), 0)
		else:
			_release()  # 极端浮点接触已确认阻挡却无接触体时保守停止，不穿过去
			_impact(false)
	if _hit:
		return
	position += step
	_life -= delta
	if _life <= 0.0:
		_release()


func _sweep(from: Vector2, to: Vector2) -> Dictionary:
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _hit_shape
	query.collision_mask = collision_mask
	var excluded: Array[RID] = []
	if _ignore_rid.is_valid():
		excluded.append(_ignore_rid)
	var space := get_world_2d().direct_space_state
	var motion := to - from
	for _i in 12:  # 跳过同处尸体/玩家，不扫描全场或沿弹道固定步长采样
		query.exclude = excluded
		query.transform = Transform2D(0.0, from)
		query.motion = Vector2.ZERO
		query.margin = 0.0
		# cast_motion 会忽略初始重叠，必须先单独检查出生点。
		var overlaps := space.intersect_shape(query, 24)
		var initial := _blocking_overlap(overlaps, excluded)
		if not initial.is_empty():
			initial["position"] = from
			return initial
		query.exclude = excluded
		query.motion = motion
		var fractions := space.cast_motion(query)
		if fractions[0] >= 1.0:
			return {}
		var stop := from + motion * fractions[0]
		# 在引擎给出的首个非安全位置取形状索引，保留多格障碍的具体 shape。
		query.transform = Transform2D(0.0, from + motion * fractions[1])
		query.motion = Vector2.ZERO
		# 大世界坐标可达80万：float位置间隔约0.0625px；仅接触体解析容差，
		# 不改变上面cast_motion的真实8px半径与停止距离。
		query.margin = 0.25
		overlaps = space.intersect_shape(query, 24)
		var excluded_before := excluded.size()
		var hit := _blocking_overlap(overlaps, excluded)
		if not hit.is_empty():
			hit["position"] = stop
			return hit
		if excluded.size() == excluded_before:
			return {"position": stop}
	return {"position": from}


func _blocking_overlap(overlaps: Array[Dictionary], excluded: Array[RID]) -> Dictionary:
	var first: Dictionary = {}
	for hit: Dictionary in overlaps:
		var body := hit["collider"] as Node2D
		if body == null or body.is_in_group("player") or _is_corpse(body):
			if not excluded.has(hit["rid"]):
				excluded.append(hit["rid"])
			continue
		# 同时挤在掩体内的怪物不能抢在墙前吃到伤害。
		if body is TileMapLayer or (body is StaticBody2D and not body.is_in_group("nests")):
			return hit
		if first.is_empty():
			first = hit
	return first


func _target_alive(target: Node2D) -> bool:
	return is_instance_valid(target) and target.is_inside_tree() and not target.is_queued_for_deletion() \
		and target.visible and target.has_method("take_damage") and not _is_corpse(target)


func _is_corpse(body: Node2D) -> bool:
	return body is MonsterBase and (body as MonsterBase).state == MonsterBase.S_CORPSE


func _acquire_target() -> void:
	_target = null
	_seek_scans += 1
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _seek_shape
	query.transform = Transform2D(0.0, global_position)
	query.collision_mask = 6
	var nearest := SEEK_RADIUS * SEEK_RADIUS
	# 局部物理查询且最多 24 个候选，每 0.12 秒一次，不按帧扫描 monsters 全组。
	for item: Dictionary in get_world_2d().direct_space_state.intersect_shape(query, 24):
		var body := item["collider"] as Node2D
		if not _target_alive(body) or not (body.is_in_group("monsters") or body.is_in_group("nests")):
			continue
		var offset := body.global_position - global_position
		var distance := offset.length_squared()
		if distance >= nearest or distance < 1.0 \
				or absf(direction.angle_to(offset)) > SEEK_HALF_ANGLE \
				or absf(_launch_direction.angle_to(offset)) > deg_to_rad(70.0):
			continue
		# 只认真正可见目标。墙/树等挡住法弹也挡住索敌，不隔墙拐弯。
		var sight := PhysicsRayQueryParameters2D.create(global_position, body.global_position, 1)
		if not get_world_2d().direct_space_state.intersect_ray(sight).is_empty():
			continue
		nearest = distance
		_target = body


func _on_body_shape_entered(_body_rid: RID, body: Node2D, body_shape: int, _local_shape: int) -> void:
	if _hit or is_queued_for_deletion():
		return
	if body is CollisionObject2D and (body as CollisionObject2D).get_rid() == _ignore_rid:
		return
	if body is StaticBody2D and body.has_meta("obstacle"):
		var owner_id := (body as StaticBody2D).shape_find_owner(body_shape)
		var shape_node := (body as StaticBody2D).shape_owner_get_owner(owner_id) as Node2D
		_release()
		if shape_node != null:
			_damage_obstacle(shape_node.global_position)
		_impact(false)
		return
	if body is TileMapLayer:
		_release()
		_damage_obstacle(global_position + direction * HIT_RADIUS)
		_impact(false)
		return
	if body is StaticBody2D and not body.is_in_group("nests"):
		_release()
		_impact(false)
		return
	if (body.is_in_group("monsters") or body.is_in_group("nests")) and body.has_method("take_damage"):
		if _is_corpse(body):
			return
		var dealt := damage
		var effective := false
		var monster := body as MonsterBase
		if monster != null and monster.inst != null:
			var em := CombatMath.elemental_multiplier(player_element, monster.inst.species.element)
			dealt *= em
			effective = em > 1.0
		if _split and _generation == 0:
			var ignored := (body as CollisionObject2D).get_rid() if body is CollisionObject2D else RID()
			_spawn_shards.call_deferred(get_parent(), global_position, direction, _split_damage,
				player_element, ignored, _spawn_epoch)
		_release()  # 同步关闸，信号/死亡回调也不能重复命中或重复分裂
		body.take_damage(dealt, global_position, false, 0.35 if _generation > 0 else 0.6, effective)
		EventBus.hit_stop_requested.emit(0.025)
		_impact(effective)


func _impact(effective: bool) -> void:
	EventBus.fx_requested.emit("flame" if effective and player_element == "fire"
		else "frost" if effective and player_element == "ice" else "magic", global_position,
		0.6 if _generation > 0 else 0.9)


static func _spawn_shards(parent: Variant, pos: Vector2, dir: Vector2, dmg: float,
		p_element: String, ignored: RID, epoch: int) -> void:
	if epoch != _pool_epoch or not is_instance_valid(parent) or not parent.is_inside_tree() \
			or parent.is_queued_for_deletion():
		return
	for side in [-1.0, 1.0]:
		# 从撞点原地发出；绝不向前瞬移越过紧贴目标的墙。
		var shard := spawn(parent, pos, dir.rotated(deg_to_rad(25.0) * side), dmg, p_element)
		shard._generation = 1
		shard._ignore_rid = ignored
		shard._life = SHARD_LIFE_TIME
		shard.queue_redraw()


func _release() -> void:
	if _hit or is_queued_for_deletion():
		return
	_hit = true
	_target = null
	set_physics_process(false)
	hide()
	if not _pooled:
		queue_free()
		return
	_finish_release.call_deferred(_spawn_epoch)


func _finish_release(epoch: int) -> void:
	var parent := get_parent()
	if is_queued_for_deletion():
		return
	if epoch != _pool_epoch or parent == null or not is_inside_tree() \
			or parent.is_queued_for_deletion() or _pool.size() >= POOL_MAX:
		queue_free()
		return
	monitoring = false
	parent.remove_child(self)
	_pool.append(self)


func _damage_obstacle(hit_position: Vector2) -> void:
	var cell := Vector2i(floori(hit_position.x / ObstacleField.CELL),
		floori(hit_position.y / ObstacleField.CELL))
	var kind := ObstacleField.damage_cell(cell)
	if kind == "":
		return
	EventBus.obstacle_destroyed.emit(cell,
		(Vector2(cell) + Vector2(0.5, 0.5)) * ObstacleField.CELL, kind)
	EventBus.camera_shake_requested.emit(3.0)
	if randf() < ObstacleField.DESTROY_GOLD_CHANCE:
		var amount := randi_range(int(ObstacleField.DESTROY_GOLD_RANGE[0]),
			int(ObstacleField.DESTROY_GOLD_RANGE[1]))
		GameState.add_gold(amount)
		EventBus.world_event.emit("💎 碎石中拾得 %d 金币" % amount)
