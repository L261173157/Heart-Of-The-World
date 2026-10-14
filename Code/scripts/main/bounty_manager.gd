## 自动本地赏金：从玩家附近可达据点发单；进度/奖励基数以 GameState 为真源。
## 世界或菜单生命周期不重新抽未完成的单，生态耗尽按贡献结算，不白送整单。
class_name BountyManager
extends Node

const _GameWorld := preload("res://scripts/main/game_world.gd")
const NEW_BOUNTY_DELAY := 8.0
const EXTINCT_CHECK_INTERVAL := 5.0
const LOCAL_RADIUS := 6000.0
const NEIGHBOR_RADIUS := 12000.0
const MIN_STOCK := 3
const ROUTE_VISIT_LIMIT := 8000
const ROUTE_SLICE_USEC := 2000

# 兼容既有战斗探针；这些值只作 GameState.bounty 的展示镜像。
var _species_name := ""
var _target := 0
var _progress := 0
var _gold_reward := 0
var _xp_reward := 0
var _extinct_accum := 0.0
var _roll_delay := 0.0
var _route_connected: Dictionary = {}
var _route_blocked: Dictionary = {}
var _route_visits_left := ROUTE_VISIT_LIMIT
var _last_roll_msec := 0.0
var _rolling := false
var _route_slice_started := 0
var _max_route_slice_msec := 0.0


func _ready() -> void:
	EventBus.monster_killed_by_player.connect(_on_kill)
	if GameState.bounty.is_empty():
		_roll_later(1.0)
	else:
		_reconcile()
		_push()


func _inside_town_room() -> bool:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	return player != null and ObstacleField.interior_index_at(player.global_position) >= 0


func _process(delta: float) -> void:
	if _rolling:
		return
	if _roll_delay > 0.0:
		if _inside_town_room():
			return
		_roll_delay -= delta
		if _roll_delay <= 0.0:
			_roll_bounty()
		return
	_extinct_accum += delta
	if _extinct_accum >= EXTINCT_CHECK_INTERVAL:
		_extinct_accum = 0.0
		_reconcile()


func _save_changed() -> void:
	GameState._invalidate_world_save_cache()
	GameState._queue_save()


func _roll_later(delay: float) -> void:
	_roll_delay = delay
	_species_name = ""
	EventBus.bounty_target_changed.emit("")
	EventBus.bounty_updated.emit("赏金交接中…")


## 不用 SceneTreeTimer：暂停/退菜单后不会残留仍会抽单的脱离场景回调。
func _roll_bounty() -> void:
	if _rolling:
		return
	_roll_delay = 0.0
	if not GameState.bounty.is_empty():
		_reconcile()
		_push()
		return
	if _inside_town_room():
		_roll_delay = 1.0
		return
	_rolling = true
	var sim_before := WorldSim.sim
	var player_before := get_tree().get_first_node_in_group("player") as Node2D
	var position_before := player_before.global_position if player_before != null else Vector2.INF
	var nav_revision := ObstacleField.nav_revision()
	var started := Time.get_ticks_usec()
	var candidates := await _local_targets()
	_rolling = false
	if WorldSim.sim != sim_before or not GameState.bounty.is_empty():
		return
	var player_after := get_tree().get_first_node_in_group("player") as Node2D
	if player_after == null or not player_after.visible or _inside_town_room() or position_before.distance_to(player_after.global_position) > 1200.0:
		_roll_later(1.0)
		return
	# 分帧期间演员会移动、卸载或被替换；发单只消费仍匹配的活体与路径终点。
	# 玩家也必须仍在已证明连通的格中，机关变化则整次证据作废，稍后重试。
	var origin := WorldSim.sim.region_of_point(player_after.global_position) if WorldSim.sim != null else null
	if origin == null or ObstacleField.nav_revision() != nav_revision \
			or (not candidates.is_empty() and not _route_connected.has(_nav_cell(ObstacleField.nudge_free(player_after.global_position)))):
		_roll_later(1.0)
		return
	var actors := _loaded_actors()
	for candidate: Dictionary in candidates:
		var ids: Array[int] = []
		var nearest_distance := INF
		for id: int in candidate["target_ids"]:
			var inst: MonsterInstance = WorldSim.sim.instances.get(id)
			var location := _target_location(inst, actors, player_after.global_position, origin)
			if location.is_empty() or inst.region_id != candidate["region_id"] \
					or _nav_cell(location["pos"]) != candidate["verified_cells"].get(id):
				continue
			ids.append(id)
			nearest_distance = minf(nearest_distance, location["distance"])
			candidate["tier"] = location["tier"]
		candidate["target_ids"] = ids
		candidate["count"] = ids.size()
		candidate["distance"] = nearest_distance
	candidates = candidates.filter(func(c: Dictionary) -> bool: return int(c["count"]) >= MIN_STOCK)
	candidates.sort_custom(_nearer_target)
	_last_roll_msec = (Time.get_ticks_usec() - started) / 1000.0
	if candidates.is_empty():
		_roll_delay = EXTINCT_CHECK_INTERVAL
		EventBus.bounty_updated.emit("附近暂无合适赏金 · 继续探索")
		return
	# 就近档内随机，既不每单固定一种，也不让遥远的全局存量挤掉近处据点。
	var nearest: float = candidates[0]["distance"]
	var pool := candidates.filter(func(c: Dictionary) -> bool:
		return int(c["tier"]) == int(candidates[0]["tier"]) and float(c["distance"]) <= nearest + 1200.0)
	var chosen: Dictionary = pool[randi() % pool.size()]
	var need := mini(randi_range(4, 7), int(chosen["count"]))
	var gold := EconomyMath.bounty_gold(need, GameState.stats.level)
	var xp := EconomyMath.bounty_xp(need)
	GameState.bounty = {"species": chosen["species"], "region_id": chosen["region_id"],
		"need": need, "progress": 0, "gold": gold, "xp": xp,
		"original_need": need, "original_gold": gold, "original_xp": xp, "adjusted": false,
		"target_ids": chosen["target_ids"].slice(0, need)}
	_save_changed()
	_push()


## 只有当地/相邻区、距离有界且确实有走通路径的据点参与自动发单。
## 邻区必须已探索；当地近处据点允许发单，但雷达仍遵守迷雾信息边界。
func _local_targets() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	_route_connected.clear()
	_route_blocked.clear()
	_route_visits_left = ROUTE_VISIT_LIMIT
	_route_slice_started = Time.get_ticks_usec()
	_max_route_slice_msec = 0.0
	var player := get_tree().get_first_node_in_group("player") as Node2D
	var sim := WorldSim.sim
	if sim == null or player == null or not player.visible or _inside_town_room():
		return result
	var player_pos := player.global_position
	var origin := sim.region_of_point(player_pos)
	if origin == null:
		return result
	var nav_revision := ObstacleField.nav_revision()
	# 每轮仅扫描一次演员组；字典保留引用，分帧回来读取的仍是当前坐标。
	var actors := _loaded_actors()
	var grouped := {}
	for inst: MonsterInstance in sim.instances.values():
		if Time.get_ticks_usec() - _route_slice_started >= ROUTE_SLICE_USEC:
			await get_tree().process_frame
			while get_tree().paused:
				await get_tree().process_frame
			_route_slice_started = Time.get_ticks_usec()
		if WorldSim.sim != sim or ObstacleField.nav_revision() != nav_revision:
			return []
		var location := _target_location(inst, actors, player_pos, origin)
		if location.is_empty():
			continue
		var key := inst.region_id + "|" + inst.species.species_name
		if not grouped.has(key):
			grouped[key] = {"species": inst.species.species_name, "region_id": inst.region_id,
				"count": 0, "tier": location["tier"], "distance": location["distance"],
				"pos": location["pos"], "instances": []}
		grouped[key]["count"] += 1
		grouped[key]["instances"].append({"inst": inst, "distance": location["distance"]})
		if float(location["distance"]) < float(grouped[key]["distance"]):
			grouped[key]["distance"] = location["distance"]
			grouped[key]["pos"] = location["pos"]
	for candidate: Dictionary in grouped.values():
		if int(candidate["count"]) >= MIN_STOCK:
			result.append(candidate)
	result.sort_custom(_nearer_target)
	# 已有近处可行单时无需给远处每个据点做路径搜索。
	var reachable: Array[Dictionary] = []
	for candidate: Dictionary in result:
		if not reachable.is_empty() and (candidate["tier"] != reachable[0]["tier"] \
				or float(candidate["distance"]) > float(reachable[0]["distance"]) + 1200.0):
			break
		var individuals: Array = candidate["instances"]
		individuals.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["distance"] < b["distance"])
		var ids: Array[int] = []
		var verified_cells := {}
		for individual: Dictionary in individuals:
			var inst: MonsterInstance = individual["inst"]
			var location := _target_location(inst, actors, player_pos, origin)
			if location.is_empty():
				continue
			var target_pos: Vector2 = location["pos"]
			var reached := await _route_exists(player_pos, target_pos)
			if WorldSim.sim != sim or ObstacleField.nav_revision() != nav_revision:
				return []
			location = _target_location(inst, actors, player_pos, origin)
			# 目标跨导航格后旧路径不再证明当前位置可达，留待下一轮重新找路。
			if reached and not location.is_empty() and _nav_cell(location["pos"]) == _nav_cell(target_pos):
				ids.append(inst.id)
				verified_cells[inst.id] = _nav_cell(target_pos)
			if ids.size() >= 7 or _route_visits_left <= 0:
				break
		if ids.size() >= MIN_STOCK:
			candidate["target_ids"] = ids
			candidate["verified_cells"] = verified_cells
			candidate["count"] = ids.size()
			candidate.erase("instances")
			reachable.append(candidate)
	return reachable


func _loaded_actors() -> Dictionary:
	var result := {}
	for node: Node in get_tree().get_nodes_in_group("monsters"):
		if node is MonsterBase and node.inst != null and not node.is_queued_for_deletion() \
				and WorldSim.sim != null and WorldSim.sim.instances.get(node.inst.id) == node.inst:
			result[node.inst.id] = node
	return result


## 出生点是固定据点；已加载演员以真实身体位置为准，卸载后回到模拟位置。
## 旧世界或同 ID 的异实例节点不得污染当前实例的定位，也绝不回写 spawn_pos。
func _target_position(inst: MonsterInstance, actors: Dictionary) -> Vector2:
	var actor: Variant = actors.get(inst.id)
	if is_instance_valid(actor) and actor is MonsterBase and actor.inst == inst \
			and actor.is_inside_tree() and not actor.is_queued_for_deletion():
		return actor.global_position if actor.state != MonsterBase.S_CORPSE else Vector2.INF
	return inst.spawn_pos


func _target_location(inst: MonsterInstance, actors: Dictionary, player_pos: Vector2, origin: SimRegion) -> Dictionary:
	if inst == null or WorldSim.sim == null or WorldSim.sim.instances.get(inst.id) != inst or not _feasible(inst):
		return {}
	var pos := _target_position(inst, actors)
	if not pos.is_finite():
		return {}
	var tier := 0 if inst.region_id == origin.id else 1
	if tier == 1 and inst.region_id not in origin.neighbor_ids:
		return {}
	var distance := player_pos.distance_to(pos)
	if distance > (LOCAL_RADIUS if tier == 0 else NEIGHBOR_RADIUS):
		return {}
	if tier == 1:
		var cell := GameState.fog_cell_of(pos)
		if not GameState.fog_is_explored(cell.x, cell.y):
			return {}
	return {"pos": pos, "distance": distance, "tier": tier}


func _nearer_target(a: Dictionary, b: Dictionary) -> bool:
	return a["tier"] < b["tier"] if a["tier"] != b["tier"] else a["distance"] < b["distance"]


func _nav_cell(pos: Vector2) -> Vector2i:
	return Vector2i((pos / ObstacleField.CELL).floor())


## 难度门槛来自既有 CombatBandMath，实际年龄/威胁/装备均参与对刀估算。
func _feasible(inst: MonsterInstance) -> bool:
	if not inst.is_alive or inst.species.is_boss or inst.species.ambient \
			or not _GameWorld.MONSTER_SCENES.has(inst.species.species_name):
		return false
	var band: Dictionary = CombatBandMath.TERRAIN_BANDS["plains"]
	for candidate: Dictionary in CombatBandMath.TERRAIN_BANDS.values():
		if int(candidate["expected"]) <= GameState.stats.level \
				and int(candidate["expected"]) > int(band["expected"]):
			band = candidate
	var heavy := inst.species.defense_reduction >= CombatBandMath.HEAVY_DEF
	var kill_band: Array = band["kill_heavy" if heavy else "kill"]
	var pressure := CombatBandMath.attackers_of(inst.species)
	var minimum: float = CombatBandMath.HEAVY_DIE_FLOOR if heavy else band["die_pack" if pressure == 3 else "die_solo"]
	return CombatBandMath.hits_to_kill(inst, GameState.stats.physical_attack()) <= int(kill_band[1]) \
		and CombatBandMath.hits_to_die(inst, GameState.stats.max_hp(), pressure) >= minimum


## 有界四向 A*，走同一障碍/深水导航格；失败宁缺毋滥，绝不发不可达自动单。
## 按需读导航块缓存，避免为 80 万像素世界建立全图导航。
func _route_exists(from: Vector2, to: Vector2) -> bool:
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
			await get_tree().process_frame
			while get_tree().paused:
				await get_tree().process_frame
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


func _nav_blocked(cell: Vector2i) -> bool:
	if not _route_blocked.has(cell):
		_route_blocked[cell] = ObstacleField.nav_blocked_cell(cell)
	return bool(_route_blocked[cell])


func _heap_push(heap: Array, entry: Array) -> void:
	heap.append(entry)
	var i := heap.size() - 1
	while i > 0:
		var parent := (i - 1) / 2
		if heap[parent][0] <= entry[0]:
			break
		heap[i] = heap[parent]
		i = parent
	heap[i] = entry


func _heap_pop(heap: Array) -> Array:
	var result: Array = heap[0]
	var last: Array = heap.pop_back()
	if heap.is_empty():
		return result
	var i := 0
	while i * 2 + 1 < heap.size():
		var child := i * 2 + 1
		if child + 1 < heap.size() and heap[child + 1][0] < heap[child][0]:
			child += 1
		if last[0] <= heap[child][0]:
			break
		heap[i] = heap[child]
		i = child
	heap[i] = last
	return result


## 据点剩余存量降到需求以下时下调目标；已有击杀始终保留，原始奖励不复乘。
func _reconcile() -> void:
	if WorldSim.sim == null or GameState.bounty.is_empty():
		return
	var bounty: Dictionary = GameState.bounty
	var available := _species_alive_count()
	var progress := int(bounty["progress"])
	if available + progress >= int(bounty["need"]):
		if progress >= int(bounty["need"]):
			_complete()
		return
	if progress == 0 and available == 0:
		GameState.bounty = {}
		_save_changed()
		_roll_later(2.0)
		return
	bounty["need"] = progress + available
	bounty["adjusted"] = true
	var fraction := float(bounty["need"]) / maxi(1, int(bounty["original_need"]))
	bounty["gold"] = floori(int(bounty["original_gold"]) * fraction)
	bounty["xp"] = floori(int(bounty["original_xp"]) * fraction)
	_save_changed()
	if progress >= int(bounty["need"]):
		_complete()
	else:
		_push()


func _push() -> void:
	if GameState.bounty.is_empty():
		return
	var bounty: Dictionary = GameState.bounty
	_species_name = str(bounty["species"])
	_target = int(bounty["need"])
	_progress = int(bounty["progress"])
	_gold_reward = int(bounty["gold"])
	_xp_reward = int(bounty["xp"])
	var region := WorldSim.sim.get_region(str(bounty["region_id"])) if WorldSim.sim != null else null
	var where := " · 本地线索 " + region.display_name if region != null else ""
	var note := " · 按量结算" if bounty.get("adjusted", false) else ""
	EventBus.bounty_target_changed.emit(_species_name)
	EventBus.bounty_updated.emit("赏金：猎杀 %s %d/%d%s%s" % [_species_name, _progress, _target, where, note])


## 据点是本地猎杀线索；沿用物种悬赏语义，同物种的异地击杀也计贡献。
func _on_kill(_xp: int, _gold: int, _monster_name: String, species_name: String) -> void:
	if GameState.bounty.is_empty() or species_name != GameState.bounty.get("species", ""):
		return
	GameState.bounty["progress"] = int(GameState.bounty["progress"]) + 1
	_save_changed()
	if int(GameState.bounty["progress"]) >= int(GameState.bounty["need"]):
		_complete()
	else:
		_push()


func _complete() -> void:
	if GameState.bounty.is_empty():
		return
	var completed := GameState.bounty.duplicate(true)
	# 先销单再奖励/广播：同步保存或重复信号不能再次领取同一份报酬。
	GameState.bounty = {}
	_save_changed()
	GameState.add_gold(int(completed["gold"]))
	GameState.add_xp(int(completed["xp"]))
	EventBus.bounty_completed.emit("赏金%s！%s +%d 金币 +%d 经验" % [
		"按量结算" if completed.get("adjusted", false) else "完成",
		completed["species"], completed["gold"], completed["xp"]])
	_roll_later(NEW_BOUNTY_DELAY)


func _species_alive() -> bool:
	return _species_alive_count() > 0


func _species_alive_count() -> int:
	if WorldSim.sim == null or GameState.bounty.is_empty():
		return 0
	var count := 0
	for inst: MonsterInstance in WorldSim.sim.instances.values():
		if GameState.bounty.has("target_ids") and not inst.id in GameState.bounty["target_ids"]:
			continue
		if inst.is_alive and inst.species.species_name == GameState.bounty.get("species", "") \
				and inst.region_id == GameState.bounty.get("region_id", "") and _feasible(inst):
			count += 1
	return count
