## 自动赏金位置契约：真实演员、真实导航格与异步发单边界。
extends Node2D

var _checks := 0
var _fails := 0
var _origin := Vector2.ZERO
var _player: Node2D
var _manager: BountyManager
var _actors: Array[MonsterBase] = []
var _instances: Array[MonsterInstance] = []
var _region: SimRegion
var _species: SpeciesData

## 不伪造可达性：完整运行生产 A* 后，在其异步返回边界移动真实演员。
class MovingTargets extends BountyManager:
	var actors: Array[MonsterBase] = []
	var moved_to := Vector2.INF
	var shift := Vector2.ZERO
	var unload := false
	var moved := false
	func _local_targets() -> Array[Dictionary]:
		var result: Array[Dictionary] = await super._local_targets()
		if not result.is_empty():
			await get_tree().process_frame
			for actor in actors:
				if unload: actor.free()
				elif not shift.is_zero_approx(): actor.global_position += shift
				else: actor.global_position = moved_to
			moved = true
		return result

func _ready() -> void:
	GameState.save_enabled = false
	GameState.reset_all()
	WorldSim.stop()
	BiomeMap.configure(BiomeMap.DEFAULT_SEED)
	ObstacleField.restore_destroyed([])
	_origin = WorldConfig.spawn_pos()
	_region = SimRegion.new()
	_region.id = "bounty_positions"
	_region.center = _origin
	_region.size = Vector2(100000, 100000)
	_region.terrain = "plains"
	_region.capacity = 100
	_species = preload("res://data/species/goblin.tres").duplicate()
	WorldSim.sim = EcologySim.new()
	WorldSim.sim.setup([_region], [_species], {})
	_player = Node2D.new()
	_player.position = _origin
	add_child(_player)
	_player.add_to_group("player")
	_manager = BountyManager.new()
	add_child(_manager)
	_manager.set_process(false)
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok: _fails += 1
	print("  %s %s" % ["PASS" if ok else "FAIL", label])

func _make_stock(anchor_offset: Vector2, body_offset: Vector2, loaded := 3) -> void:
	for actor in _actors:
		if is_instance_valid(actor): actor.free()
	_actors.clear()
	_instances.clear()
	WorldSim.sim = EcologySim.new()
	WorldSim.sim.setup([_region], [_species], {})
	for i in 3:
		var inst := WorldSim.sim.spawn_instance(_species, _region.id, 10, 0, 1.0, false,
			_origin + anchor_offset + Vector2(32 * i, 0))
		_instances.append(inst)
		if i >= loaded: continue
		var actor: MonsterBase = preload("res://scenes/monsters/goblin.tscn").instantiate()
		add_child(actor)
		actor.set_physics_process(false)
		actor.setup(inst)
		actor._nav.avoidance_enabled = false
		actor.global_position = _origin + body_offset + Vector2(32 * i, 0)
		_actors.append(actor)

func _run() -> void:
	_make_stock(Vector2(160, 0), Vector2(15000, 0))
	var targets := await _manager._local_targets()
	_check(targets.is_empty(), "已加载演员远离6000px，本地出生锚点不能继续冒充目标")
	_check(_instances[0].spawn_pos == _origin + Vector2(160, 0), "查询不把演员位置回写出生锚点")
	_make_stock(Vector2(15000, 0), Vector2(160, 0))
	targets = await _manager._local_targets()
	_check(targets.size() == 1 and targets[0].count == 3, "已加载演员走到近处，即使出生锚点遥远仍可发单")
	if targets.size() == 1:
		_check(absf(float(targets[0].distance) - 160.0) < 1.0, "候选距离排序使用实际演员位置")
	var blocked := Vector2.INF
	for i in range(40, 160):
		var cell := Vector2i((_origin / ObstacleField.CELL).floor()) + Vector2i(i, i / 2)
		if ObstacleField.nav_blocked_cell(cell):
			blocked = (Vector2(cell) + Vector2(0.5, 0.5)) * ObstacleField.CELL
			break
	_check(blocked.is_finite(), "夹具找到真实阻挡导航格")
	_make_stock(Vector2(160, 0), Vector2(160, 0))
	for actor in _actors: actor.global_position = blocked
	targets = await _manager._local_targets()
	_check(targets.is_empty(), "A*检查实际演员所在阻挡格，不检查旧的可走出生点")
	_make_stock(Vector2(160, 0), Vector2(160, 0), 0)
	targets = await _manager._local_targets()
	_check(targets.size() == 1 and targets[0].count == 3, "未加载个体仍使用权威位置形成可达赏金")
	_make_stock(Vector2(160, 0), Vector2(15000, 0), 1)
	targets = await _manager._local_targets()
	_check(targets.is_empty(), "两只未加载近处加一只已加载远处不足三只库存")
	for destination: Vector2 in [_origin + Vector2(15000, 0), blocked]:
		_make_stock(Vector2(160, 0), Vector2(160, 0))
		GameState.bounty = {}
		var moving := MovingTargets.new()
		moving.actors = _actors.duplicate()
		moving.moved_to = destination
		add_child(moving)
		moving.set_process(false)
		await moving._roll_bounty()
		_check(moving.moved, "异步复核夹具确实先完成真实可达搜索")
		_check(GameState.bounty.is_empty(), "发单前重新验证移动后实际位置 %s" % destination)
		_check(_instances[0].spawn_pos == _origin + Vector2(160, 0), "异步复核不修改出生锚点")
		moving.free()
	_make_stock(Vector2(160, 0), Vector2(160, 0))
	GameState.bounty = {}
	var drifting := MovingTargets.new()
	drifting.actors = _actors.duplicate()
	drifting.shift = Vector2(1, 0)
	add_child(drifting)
	drifting.set_process(false)
	await drifting._roll_bounty()
	_check(drifting.moved and not GameState.bounty.is_empty(), "演员同导航格内小步移动仍接受已验证路径")
	drifting.free()
	_make_stock(Vector2(15000, 0), Vector2(160, 0))
	GameState.bounty = {}
	var unloading := MovingTargets.new()
	unloading.actors = _actors.duplicate()
	unloading.unload = true
	add_child(unloading)
	unloading.set_process(false)
	await unloading._roll_bounty()
	_check(unloading.moved and GameState.bounty.is_empty(), "搜索后卸载转为远处权威位置，旧演员路径不能发单")
	unloading.free()
	_make_stock(Vector2(15000, 0), Vector2(160, 0))
	var stale := MonsterInstance.new()
	stale.id = _instances[0].id
	stale.region_id = _region.id
	stale.species = _species
	stale.spawn_pos = _origin + Vector2(15000, 0)
	var orphan: MonsterBase = preload("res://scenes/monsters/goblin.tscn").instantiate()
	add_child(orphan)
	orphan.set_physics_process(false)
	orphan.setup(stale)
	targets = await _manager._local_targets()
	_check(targets.size() == 1 and targets[0].count == 3, "旧世界同ID演员不能覆盖当前权威演员的位置")
	orphan.free()
	# 固定演员的真实发单依旧成立，不因谨慎复核使全部赏金消失。
	_make_stock(Vector2(15000, 0), Vector2(160, 0))
	GameState.bounty = {}
	await _manager._roll_bounty()
	_check(not GameState.bounty.is_empty() and GameState.bounty.target_ids.size() == 3,
		"稳定的近处实际演员经过完整流程收到赏金")
	for actor in _actors: actor.free()
	_manager.free()
	_player.free()
	WorldSim.stop()
	print("=== BOUNTY POSITION AUDIT %s (%d checks) ===" % ["PASS" if _fails == 0 else "FAIL", _checks])
	get_tree().quit(0 if _fails == 0 else 1)
