## 真实障碍铺设队列物理与恢复失败后的延迟生命周期回归。
extends SceneTree
var failures := 0
var checks := 0
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	root.get_node("GameState").save_enabled = false
	await _queued_destroy()
	await _deferred_restore()
	print("=== WORLD STREAM TRUTH %s checks=%d ===" % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)
func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL WORLD_STREAM_TRUTH ", label)
func _frames() -> void:
	for i in 3: await physics_frame
func _hits(parent: Node2D, cell: Vector2i) -> int:
	var query := PhysicsPointQueryParameters2D.new()
	query.position = (Vector2(cell) + Vector2(0.5,0.5)) * 32
	query.collision_mask = 1
	return parent.get_world_2d().direct_space_state.intersect_point(query).size()
func _queued_destroy() -> void:
	BiomeMap.configure(BiomeMap.DEFAULT_SEED)
	ObstacleField.restore_destroyed([])
	var parent := Node2D.new()
	root.add_child(parent)
	var layer = load("res://scripts/main/terrain/obstacle_tile_layer.gd").new()
	parent.add_child(layer)
	layer.set_process(false)
	var cell := Vector2i((BiomeMap.spawn_pos() + Vector2(450,220)) / 32)
	var origin := Vector2i(cell.x >> 4, cell.y >> 4) * 512
	layer._on_chunk_ready(origin)
	_check(not layer._lay_queue.is_empty(), "real rock initially queued")
	ObstacleField.damage_cell(cell)
	var kind := ObstacleField.damage_cell(cell)
	_check(not kind.is_empty(), "two real damage calls destroy rock")
	root.get_node("EventBus").obstacle_destroyed.emit(cell, (Vector2(cell)+Vector2(0.5,0.5))*32, kind)
	while not layer._lay_queue.is_empty(): layer._process(0)
	await _frames()
	_check(ObstacleField.sample_cell(cell).is_empty(), "authority stays destroyed")
	_check(layer.get_cell_source_id(cell) == -1, "queued destruction cannot restore visual")
	_check(_hits(parent, cell) == 0, "queued destruction cannot restore real physics")
	_check(not layer._laying.has(origin) and layer._bodies.has(origin), "remaining count commits even after cancellation")
	layer._on_chunk_freed(origin)
	layer._on_chunk_ready(origin)
	while not layer._lay_queue.is_empty() or not layer._clearing.is_empty(): layer._process(0)
	await _frames()
	_check(_hits(parent,cell) == 0 and layer.get_cell_source_id(cell) == -1, "unload/reload preserves destroyed truth")
	# 队列尚未消费即出窗再进窗，旧请求不得重复创建形状。
	ObstacleField.restore_destroyed([])
	layer._on_chunk_freed(origin)
	layer._on_chunk_ready(origin)
	layer._on_chunk_freed(origin)
	layer._on_chunk_ready(origin)
	while not layer._lay_queue.is_empty(): layer._process(0)
	await _frames()
	_check(layer._laying.is_empty(), "unload/reenter queue fully accounted")
	var entry: Dictionary = layer._bodies.get(origin,{})
	_check(not entry.is_empty() and entry["body"].get_child_count() == entry["shapes"].size(), "no old-generation duplicate shapes")
	_check(_hits(parent,cell) == 1, "restored rock has exactly one collider")
	# 事件抵达前真源也可能改变，提交须重新校验，不能只依赖事件清队列。
	layer._on_chunk_freed(origin)
	layer._on_chunk_ready(origin)
	ObstacleField.damage_cell(cell)
	ObstacleField.damage_cell(cell)
	while not layer._lay_queue.is_empty(): layer._process(0)
	await _frames()
	_check(_hits(parent,cell) == 0 and layer.get_cell_source_id(cell) == -1, "commit revalidates authoritative cell")
	# 实际 Area2D 物理刷新回调破坏最后待铺格，已有形状必须延迟挂载。
	ObstacleField.restore_destroyed([])
	layer._on_chunk_freed(origin)
	layer._on_chunk_ready(origin)
	var last: Dictionary = {}
	for index in range(layer._lay_queue.size() - 1, -1, -1):
		if layer._lay_queue[index]["cell"] == cell:
			last = layer._lay_queue[index]
			layer._lay_queue.remove_at(index)
			break
	while not layer._lay_queue.is_empty(): layer._process(0)
	_check(not last.is_empty() and layer._laying[origin]["remaining"] == 1, "最后待铺格夹具真实保留其余碰撞形状")
	layer._lay_queue.append(last)
	var trigger := Area2D.new()
	trigger.position = Vector2(-30000, -30000)
	trigger.collision_layer = 0
	trigger.collision_mask = 8
	var trigger_shape := CollisionShape2D.new()
	trigger_shape.shape = CircleShape2D.new()
	trigger_shape.shape.radius = 20
	trigger.add_child(trigger_shape)
	var contacted := [false]
	trigger.body_entered.connect(func(_body: Node2D):
		contacted[0] = true
		ObstacleField.damage_cell(cell)
		var destroyed_kind := ObstacleField.damage_cell(cell)
		root.get_node("EventBus").obstacle_destroyed.emit(cell, (Vector2(cell)+Vector2(0.5,0.5))*32, destroyed_kind))
	parent.add_child(trigger)
	var contact := StaticBody2D.new()
	contact.position = trigger.position
	contact.collision_layer = 8
	contact.collision_mask = 0
	var contact_shape := CollisionShape2D.new()
	contact_shape.shape = CircleShape2D.new()
	contact_shape.shape.radius = 10
	contact.add_child(contact_shape)
	parent.add_child(contact)
	await _frames()
	await process_frame
	_check(contacted[0], "真实物理进入回调确实发出破坏事件")
	_check(layer._bodies.has(origin) and not layer._laying.has(origin), "物理回调最后取消也能安全完成提交")
	_check(_hits(parent, cell) == 0, "物理回调取消后无幽灵碰撞")
	# 已排队的提交后出窗重入，旧提交不能挂载已经弃用的 body。
	layer._on_chunk_freed(origin)
	layer._on_chunk_ready(origin)
	while not layer._lay_queue.is_empty(): layer._process(0)
	layer._on_chunk_freed(origin)
	layer._on_chunk_ready(origin)
	while not layer._lay_queue.is_empty(): layer._process(0)
	await _frames()
	_check(layer._bodies.has(origin) and layer._laying.is_empty(), "延迟提交按碰撞体身份过滤旧窗口")
	parent.queue_free()
	await process_frame
func _deferred_restore() -> void:
	var gs := root.get_node("GameState")
	gs.reset_all()
	gs.world_seed = BiomeMap.DEFAULT_SEED
	# 此夹具保留旧代次；代次选择另由冷存档回归覆盖。
	if "world_generation" in gs: gs.set("world_generation",1)
	BiomeMap.configure(gs.world_seed)
	root.get_node("WorldSim").set_process(false)
	paused = true
	var spawn := BiomeMap.spawn_pos()
	gs.ecology_snapshot = {"instances":[{"id":1,"species":"火把哥布林","region":"p_0_0","age":50,"lifespan":100,"alive":false,"corpse":1,"spawn_pos":[spawn.x,spawn.y]}],"next_id":2}
	var world = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(world)
	for i in 5: await process_frame
	_check_world_nodes(world, "after fallback")
	var live: MonsterInstance = world._sim.instances[1]
	world._spawn_monster_node.call_deferred(live)
	world._spawn_monster_node.call_deferred(live)
	await process_frame
	_check_world_nodes(world, "duplicate callbacks")
	for i in 35: world._sim.tick()
	await process_frame
	_check_world_nodes(world, "after corpse expiry")
	world.queue_free()
	await process_frame
	paused = false
	await physics_frame
	await process_frame
func _check_world_nodes(world: Node, label: String) -> void:
	var counts := {}
	for node: Node in world.get_node("Monsters").get_children():
		var inst: MonsterInstance = node.get("inst")
		if inst == null or node.is_queued_for_deletion(): continue
		counts[inst.id] = int(counts.get(inst.id,0)) + 1
		_check(world._sim.instances.get(inst.id) == inst, label + " authoritative object identity")
		_check(world._nodes.get(inst.id) == node, label + " registered node identity")
	for id: int in counts:
		_check(counts[id] == 1, label + " unique id %d" % id)
