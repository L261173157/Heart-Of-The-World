## 前哨章节的有界实名目标簿。旧营地1400px现场合同保持不变。
## 巢穴仍是调查/捣巢的真实地点；族群个体可在10k范围内正常巡猎。
class_name OutpostQuestTargets
extends CampQuestTargets

const MAX_ROSTER := 24
const TRACK_STEP := 192.0
var required_stock := 3
## 路径证明只留在运行时；冷启必须复核，不能把保存的ID当作当前可达证明。
var _verified: Dictionary = {}
var _proof_sim: EcologySim
var busy := false
var _proof_generation := 0

func _exit_tree() -> void:
	clear_proofs()

func _process(_delta: float) -> void:
	if WorldSim.sim != _proof_sim:
		_verified.clear()
		return
	for id: int in _verified.keys():
		var proof: Dictionary = _verified[id]
		var inst: MonsterInstance = WorldSim.sim.instances.get(id)
		if inst == null or not inst.is_alive:
			_verified.erase(id) # 同步击杀事件已结束，下一帧即可清理。
			continue
		if not _member_current(inst, proof["target"]) or not _track_position(inst, proof):
			_verified.erase(id)

func clear_proofs() -> void:
	_proof_generation += 1
	_verified.clear()
	_proof_sim = null

func retain_target(target: Dictionary) -> void:
	for id: int in _verified.keys():
		if not id in target.get("target_ids", []): _verified.erase(id)

## 巢穴消失也保留确定的历史巢址；保存坐标不能替代地区/物种真源。
func site_position(target: Dictionary) -> Vector2:
	if WorldSim.sim == null: return Vector2.INF
	var region: SimRegion = WorldSim.sim.get_region(str(target.get("region_id", "")))
	var species: SpeciesData = WorldSim.sim.find_species(str(target.get("species", "")))
	if region == null or species == null or target.get("key", "") != region.id + "|" + species.species_name: return Vector2.INF
	if is_inside_tree():
		for body: Node in get_tree().get_nodes_in_group("nests"):
			if body is NestNode and body.nest_key == target["key"] and body.region_id == region.id and body.species_name == species.species_name:
				var actual: Vector2 = body.global_position
				if actual.is_finite() and actual.distance_to(WorldConfig.spawn_pos()) <= PILOT_RADIUS: return actual
	var pos := WorldSim.sim.camp_pos(region, species)
	return pos if pos.distance_to(WorldConfig.spawn_pos()) <= PILOT_RADIUS else Vector2.INF

func valid_site(target: Dictionary) -> bool:
	var canonical := site_position(target)
	var pos: Array = target.get("pos", [])
	return canonical.is_finite() and pos.size() == 2 and Vector2(pos[0], pos[1]).distance_to(canonical) <= 4.0

func actor_position(inst: MonsterInstance) -> Vector2:
	return super.actor_position(inst) if is_inside_tree() and inst != null else Vector2.INF

func _member_current(inst: MonsterInstance, target: Dictionary) -> bool:
	if not is_inside_tree() or inst == null or not _feasible(inst) or inst.region_id != target.get("region_id", "") or inst.species.species_name != target.get("species", ""):
		return false
	var pos := actor_position(inst)
	return pos.is_finite() and pos.distance_to(WorldConfig.spawn_pos()) <= PILOT_RADIUS and not ObstacleField.nav_blocked_at(pos)

func current_stock_ids(target: Dictionary) -> Array[int]:
	var result: Array[int] = []
	if WorldSim.sim == null or WorldSim.sim != _proof_sim:
		return result
	# 永不退回全世界同种匹配；新生/替代ID只能在明确路径核查后入簿。
	for id: Variant in target.get("target_ids", []):
		var inst: MonsterInstance = WorldSim.sim.instances.get(int(id))
		if not _member_current(inst, target) or not _verified.has(int(id)):
			continue
		var proof: Dictionary = _verified[int(id)]
		if proof["inst"] == inst and proof["target"]["key"] == target.get("key", "") and _track_position(inst, proof):
			result.append(int(id))
	return result

func _track_position(inst: MonsterInstance, proof: Dictionary) -> bool:
	var pos := actor_position(inst)
	if not _local_segment(proof["pos"], pos):
		return false
	proof["pos"] = pos
	return true

func _local_segment(from: Vector2, to: Vector2) -> bool:
	if not from.is_finite() or not to.is_finite() or from.distance_to(to) > TRACK_STEP:
		return false
	var steps := maxi(1, ceili(from.distance_to(to) / 12.0))
	for i in range(steps + 1):
		if ObstacleField.nav_blocked_at(from.lerp(to, float(i) / float(steps))):
			return false
	return true

## 原实名目标沿正常可走移动延续证明。跳位、离开半径、迁区或死亡不能重新入簿。
func accepts_kill(id: int, target: Dictionary, species: String, region: String, pos: Vector2) -> bool:
	if WorldSim.sim == null or WorldSim.sim != _proof_sim or not id in target.get("target_ids", []) or not _verified.has(id):
		return false
	var inst: MonsterInstance = WorldSim.sim.instances.get(id)
	if inst == null or inst.is_alive or inst.species.species_name != species or inst.region_id != region \
		or species != target.get("species", "") or region != target.get("region_id", "") \
		or not inst.death_pos.is_finite() or inst.death_pos.distance_to(pos) > 4.0 \
		or pos.distance_to(WorldConfig.spawn_pos()) > PILOT_RADIUS:
		return false
	var proof: Dictionary = _verified[id]
	return proof["inst"] == inst and proof["target"]["key"] == target.get("key", "") and _local_segment(proof["pos"], pos)

func select_target(excluded: Array = []) -> Dictionary:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if busy or player == null or WorldSim.sim == null or _inside_town_room(): return {}
	var generation := _proof_generation
	var selection_sim := WorldSim.sim
	var groups := {}
	for inst: MonsterInstance in WorldSim.sim.instances.values():
		if not _feasible(inst): continue
		var key := inst.region_id + "|" + inst.species.species_name
		if key in excluded or not WorldSim.sim.nests.get(key, {}).get("active", false): continue
		if not groups.has(key):
			var region: SimRegion = WorldSim.sim.get_region(inst.region_id)
			if region == null: continue
			var pos := site_position({"region_id": inst.region_id, "species": inst.species.species_name, "key": key})
			if not pos.is_finite(): continue
			groups[key] = {"region_id": inst.region_id, "species": inst.species.species_name,
				"pos": [pos.x, pos.y], "key": key, "need": 2, "kill_start": 0,
				"target_ids": [], "distance": player.global_position.distance_to(pos)}
		if _member_current(inst, groups[key]): groups[key]["target_ids"].append(inst.id)
	var candidates: Array = groups.values().filter(func(c: Dictionary) -> bool: return not c["target_ids"].is_empty())
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["distance"] < b["distance"])
	var nest_fallback := {}
	for candidate: Dictionary in candidates:
		var found := await verify_target(candidate, false)
		if not is_inside_tree() or WorldSim.sim != selection_sim or generation != _proof_generation: return {}
		if found["target_ids"].size() >= required_stock:
			return found
		if nest_fallback.is_empty() and not found["target_ids"].is_empty(): nest_fallback = found
	if not nest_fallback.is_empty():
		nest_fallback["target_ids"] = current_stock_ids(nest_fallback)
		if nest_fallback["target_ids"].is_empty() or not selection_sim.nests.get(nest_fallback["key"], {}).get("active", false): return {}
	return nest_fallback

## 明确核查才会新增ID；每个ID同时满足实名、战力、实际位置和有界路径条件。
func verify_target(target: Dictionary, include_new: bool = true) -> Dictionary:
	var result := target.duplicate(true)
	result.erase("distance")
	result["target_ids"] = []
	if not is_inside_tree(): return result
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if busy or player == null or WorldSim.sim == null or target.is_empty(): return result
	busy = true
	var generation := _proof_generation
	var sim_before := WorldSim.sim
	var start := player.global_position
	var site_data: Array = target.get("pos", [])
	if site_data.size() != 2:
		busy = false
		return result
	var site := Vector2(site_data[0], site_data[1])
	var region: SimRegion = sim_before.get_region(str(target.get("region_id", "")))
	var species: SpeciesData
	for entry: SpeciesData in sim_before.species_list:
		if entry.species_name == target.get("species", ""): species = entry; break
	if region == null or species == null or target.get("key", "") != region.id + "|" + species.species_name or not valid_site(target):
		busy = false
		return result
	_route_connected.clear()
	_route_blocked.clear()
	_route_visits_left = ROUTE_VISIT_LIMIT
	_route_slice_started = Time.get_ticks_usec()
	var reachable := site.distance_to(WorldConfig.spawn_pos()) <= PILOT_RADIUS and await _route_exists(start, site)
	if not is_inside_tree() or WorldSim.sim != sim_before or generation != _proof_generation:
		busy = false
		return result
	if not reachable or not sim_before.nests.get(target.get("key", ""), {}).get("active", false):
		busy = false
		return result
	var candidates: Array = sim_before.instances.keys() if include_new else target.get("target_ids", [])
	var proofs := {}
	for id: Variant in candidates:
		var inst: MonsterInstance = sim_before.instances.get(int(id))
		if not _member_current(inst, target): continue
		var pos := actor_position(inst)
		var actor_reachable := await _route_exists(start, pos)
		if not is_inside_tree() or WorldSim.sim != sim_before or generation != _proof_generation:
			busy = false
			return result
		if actor_reachable:
			if _member_current(inst, target) and _local_segment(pos, actor_position(inst)):
				proofs[int(id)] = {"inst": inst, "pos": actor_position(inst), "target": {"key": target["key"], "region_id": target["region_id"], "species": target["species"]}}
		if proofs.size() >= MAX_ROSTER or _route_visits_left <= 0: break
	if generation != _proof_generation or WorldSim.sim != sim_before or not sim_before.nests.get(target.get("key", ""), {}).get("active", false):
		busy = false
		return result
	if WorldSim.sim != _proof_sim:
		_verified.clear()
		_proof_sim = WorldSim.sim
	for id: int in proofs:
		var inst: MonsterInstance = sim_before.instances.get(id)
		if _member_current(inst, target) and _track_position(inst, proofs[id]):
			_verified[id] = proofs[id]
			result["target_ids"].append(id)
	busy = false
	return result
