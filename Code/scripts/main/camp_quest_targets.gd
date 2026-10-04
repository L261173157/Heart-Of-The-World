## 复用赏金已经验证的真实战力门槛与分帧有界 A*，不启动赏金生命周期。
## 试点10k半径覆盖真实8k据点；不改变怪物分布，不暴露遥远全局存量。
class_name CampQuestTargets
extends BountyManager

const PILOT_RADIUS := 10000.0
const SITE_RADIUS := 1400.0

func _ready() -> void:
	pass

func _process(_delta: float) -> void:
	pass

func select_target(excluded: Array = []) -> Dictionary:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null or WorldSim.sim == null or _inside_town_room():
		return {}
	var start := player.global_position
	var home := WorldConfig.spawn_pos()
	var groups := {}
	var sim_before := WorldSim.sim
	for inst: MonsterInstance in sim_before.instances.values():
		if not _feasible(inst):
			continue
		var key := inst.region_id + "|" + inst.species.species_name
		if key in excluded or not sim_before.nests.get(key, {}).get("active", false):
			continue
		if not groups.has(key):
			var region: SimRegion = sim_before.get_region(inst.region_id)
			var pos: Vector2 = sim_before.camp_pos(region, inst.species)
			if pos.distance_to(home) > PILOT_RADIUS:
				continue
			groups[key] = {"region_id": inst.region_id, "species": inst.species.species_name,
				"pos": [pos.x, pos.y], "key": key, "need": 2, "kill_start": 0,
				"distance": start.distance_to(pos), "target_ids": []}
		if _member_current(inst, groups[key]):
			groups[key]["target_ids"].append(inst.id)
	var candidates: Array = groups.values().filter(func(c: Dictionary) -> bool: return c["target_ids"].size() >= 3)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["distance"] < b["distance"])
	_route_connected.clear()
	_route_blocked.clear()
	_route_slice_started = Time.get_ticks_usec()
	for candidate: Dictionary in candidates:
		# 每个候选仍有界；坏据点耗尽自己的预算不阻止真实可行的下一据点。
		_route_visits_left = ROUTE_VISIT_LIMIT
		var pos := Vector2(candidate["pos"][0], candidate["pos"][1])
		var nest_reachable := await _route_exists(start, pos)
		if not is_inside_tree() or WorldSim.sim != sim_before:
			return {}
		if not nest_reachable:
			continue
		var verified_ids: Array[int] = []
		for id: int in candidate["target_ids"]:
			var inst: MonsterInstance = sim_before.instances.get(id)
			if not _member_current(inst, candidate):
				continue
			# 使用加载演员的实际位置；出生锚点不能证明追逐离巢的怪仍在现场。
			var reachable := await _route_exists(start, actor_position(inst))
			if not is_inside_tree() or WorldSim.sim != sim_before:
				return {}
			if reachable and _member_current(inst, candidate) and _verified_position(inst):
				verified_ids.append(id)
			if verified_ids.size() >= 7:
				break
		if not is_instance_valid(player):
			return {}
		# 对同一批已走通的ID逐个复核存活、位置和战力，不能用两组独立数量凑3只。
		candidate["target_ids"] = verified_ids.filter(func(id: int) -> bool:
			var inst: MonsterInstance = sim_before.instances.get(id)
			return _member_current(inst, candidate) and _verified_position(inst))
		if current_stock_ids(candidate).size() < 3 or not sim_before.nests.get(candidate["key"], {}).get("active", false):
			continue
		candidate.erase("distance")
		return candidate
	return {}


## 筛选、确认发单和陈旧对话复核共用同一个实时个体条件。
func current_stock_ids(target: Dictionary) -> Array[int]:
	var ids: Array[int] = []
	if target.is_empty() or WorldSim.sim == null:
		return ids
	var candidates: Array = target.get("target_ids", WorldSim.sim.instances.keys())
	for id: Variant in candidates:
		var inst: MonsterInstance = WorldSim.sim.instances.get(id)
		if _member_current(inst, target):
			ids.append(inst.id)
	return ids

func _member_current(inst: MonsterInstance, target: Dictionary) -> bool:
	if inst == null or not _feasible(inst) or inst.region_id != target.get("region_id", "") or inst.species.species_name != target.get("species", ""):
		return false
	var position := actor_position(inst)
	var pos: Array = target.get("pos", [0.0, 0.0])
	return position.is_finite() and not ObstacleField.nav_blocked_at(position) and position.distance_to(WorldConfig.spawn_pos()) <= PILOT_RADIUS \
		and position.distance_to(Vector2(pos[0], pos[1])) <= SITE_RADIUS

func actor_position(inst: MonsterInstance) -> Vector2:
	for actor: Node in get_tree().get_nodes_in_group("monsters"):
		if actor is Node2D and actor.get("inst") == inst:
			return (actor as Node2D).global_position
	return inst.spawn_pos

func _verified_position(inst: MonsterInstance) -> bool:
	var cell := Vector2i((actor_position(inst) / ObstacleField.CELL).floor())
	return _route_connected.has(cell) and not _nav_blocked(cell)


## 生命周期保护：旧赏金工具的等待恢复后可能已切换世界；缓存树并逐次检查。
func _route_exists(from: Vector2, to: Vector2) -> bool:
	if not is_inside_tree():
		return false
	var tree := get_tree()
	var start := Vector2i((ObstacleField.nudge_free(from) / ObstacleField.CELL).floor())
	var goal := Vector2i((to / ObstacleField.CELL).floor())
	if _nav_blocked(goal):
		return false
	# 已验证连通的格可作新起点，营地其余个体只需补最后一小段路径。
	var distance := start.distance_squared_to(goal)
	for connected: Vector2i in _route_connected:
		var delta := connected.distance_squared_to(goal)
		if delta < distance:
			start = connected
			distance = delta
	var bounds := Rect2i(start.min(goal) - Vector2i(24, 24), (start - goal).abs() + Vector2i(49, 49))
	var open: Array = [[0.0, start]]
	var cost := {start: 0}
	var visited := {}
	while not open.is_empty() and _route_visits_left > 0:
		var elapsed := Time.get_ticks_usec() - _route_slice_started
		if elapsed >= ROUTE_SLICE_USEC:
			_max_route_slice_msec = maxf(_max_route_slice_msec, elapsed / 1000.0)
			await tree.process_frame
			if not is_inside_tree():
				return false
			while tree.paused:
				await tree.process_frame
				if not is_inside_tree():
					return false
			_route_slice_started = Time.get_ticks_usec()
		var entry: Array = _heap_pop(open)
		var cell: Vector2i = entry[1]
		if visited.has(cell):
			continue
		_route_connected[cell] = true
		if cell == goal:
			return true
		visited[cell] = true
		_route_visits_left -= 1
		for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next := cell + offset
			if not bounds.has_point(next) or visited.has(next) \
					or _nav_blocked(next):
				continue
			var step := int(cost[cell]) + 1
			if step >= int(cost.get(next, 1000000)):
				continue
			cost[next] = step
			var d := (next - goal).abs()
			# 同长度候选优先靠近终点，避免空地上退化为铺满矩形的广搜。
			_heap_push(open, [float(step + d.x + d.y) + float(d.x + d.y) * 0.000001, next])
	return false

