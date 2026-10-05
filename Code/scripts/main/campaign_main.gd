## 第三至六章现场机制。只观察真实移动、障碍覆盖层与实名击杀，不代写生态。
class_name CampaignMain
extends Node
const Data := preload("res://scripts/main/campaign_quest_data.gd")
const Catalog := preload("res://scripts/main/campaign_catalog.gd")
var host: Node
var _last_position := Vector2.INF
var _death_causes: Dictionary = {}
var _sim: EcologySim
func setup(owner_node: Node) -> void:
	host = owner_node
func _ready() -> void:
	EventBus.monster_killed_at.connect(_on_kill)
	_sim = WorldSim.sim
	if _sim != null: _sim.instance_died.connect(_on_authoritative_death)
func _on_authoritative_death(inst: MonsterInstance, cause: String) -> void:
	if inst.species.is_boss: _death_causes[inst.id] = cause
func _exit_tree() -> void:
	if _sim != null and _sim.instance_died.is_connected(_on_authoritative_death): _sim.instance_died.disconnect(_on_authoritative_death)
func _q() -> Dictionary:
	return host.ledger()
func _on_kill(instance_id: int, species: String, region_id: String, position: Vector2) -> void:
	if WorldSim.sim == null or species not in ["牛头王", "熔岩龟王"]: return
	var inst: MonsterInstance = WorldSim.sim.instances.get(instance_id)
	if inst == null or inst.is_alive or inst.species.species_name != species or not inst.species.is_boss: return
	if _death_causes.get(instance_id, "") != EcologySim.DEATH_KILLED or inst.region_id != region_id or not position.is_finite() or not inst.death_pos.is_finite() or inst.death_pos.distance_to(position)>4.0: return
	var terrain := "hill" if species=="牛头王" else "lava"
	if str(CampaignLayout.sites()[terrain]["region_id"]) != region_id: return
	if not _q().has("main_kills"): _q()["main_kills"] = {}
	_q()["main_kills"][species] = {"instance_id":instance_id,"region_id":region_id,"position":[position.x,position.y],"tick":WorldSim.sim.tick_count,"player_kill":true}
	host._save()
func _physics_process(delta: float) -> void:
	var player := host._player() as Node2D
	if player == null: return
	var pos := player.global_position
	var previous_pos := _last_position
	var step := pos.distance_to(_last_position) if _last_position.is_finite() else 0.0
	_last_position = pos
	if get_tree().paused: return
	var sid := "watch_c3_swamp:s3"
	var aid := sid + ":reach"
	if not _q().get("quests",{}).has(sid) or _q()["quests"][sid].get("evidence",{}).has(aid) or host._paused("watch_c3_swamp"): return
	if not Data.can_record(_q(), sid, aid): return
	if step > maxf(48.0, 1400.0 * delta):
		if _q().get("main_routes",{}).has(aid):
			_q()["main_routes"][aid]["needs_anchor"] = true
			host._save()
		return
	var route := str(_q().get("quests",{}).get(sid,{}).get("choice",""))
	if route not in ["near","outer"]: return
	var points: Array = CampaignLayout.route_waypoints(route)
	if points.is_empty(): return
	if not _q().has("main_routes"): _q()["main_routes"] = {}
	var progress: Dictionary = _q()["main_routes"].get(aid,{"route":route,"visited":[]})
	var visited: Array = progress.get("visited",[])
	if progress.get("needs_anchor",false):
		# 死亡/合法远征保留已走过的路标；回到最后一处实走锚点再接续，跳跃本身不记下一点。
		var anchor: Vector2 = points[maxi(0,visited.size()-1)]
		if step>0.01 and pos.distance_to(anchor)<=60.0 and not ObstacleField.blocks(pos,10.0):
			progress.erase("needs_anchor")
			_q()["main_routes"][aid]=progress
			host._save()
		return
	if visited.size() >= points.size(): return
	if ObstacleField.blocks(pos,10.0): return
	if route == "near" and visited.size() == 2:
		# 检查真实运动线段从南向北穿过已敲开的缺口；冲刺可跨帧越过，不依赖12px落脚条。
		var crossing: Vector2 = points[2]
		if not _near_barrier_broken() or not previous_pos.is_finite() or previous_pos.y<=crossing.y or pos.y>crossing.y: return
		var fraction := (crossing.y-previous_pos.y)/(pos.y-previous_pos.y)
		var crossed := previous_pos.lerp(pos,fraction)
		if absf(crossed.x-crossing.x)>48.0 or ObstacleField.blocks(crossed,10.0): return
	elif pos.distance_to(points[visited.size()])>70.0: return
	visited.append(visited.size())
	progress["visited"] = visited
	_q()["main_routes"][aid] = progress
	host._save()
func payload(a: Dictionary) -> Dictionary:
	var kind := str(a["kind"])
	if kind == "choice":
		var options: Array = []
		for choice: Dictionary in a.get("choices",[]):
			options.append({"label":choice["title"],"action":"campaign|act|"+str(a["id"])+"|"+str(choice["id"]),"enabled":true,
				"consequence":_choice_consequence(str(choice["id"])),"risk":"确认后保留选择和世界中的实际结果；不会重复发奖"})
		return {"kind":"camp_choice","giver":a["title"],"text":a["text"],"origin":host._world_position(str(a["object"])),"options":options}
	if kind == "encounter":
		var options: Array = []
		var living := _live_boss(str(a["boss_species"]))
		for outcome: String in a.get("choices",[]):
			var enabled := false
			if outcome == "bypass": enabled = true
			elif outcome == "absent": enabled = living.is_empty()
			elif outcome == "defeated": enabled = living.is_empty() and _q().get("main_kills",{}).has(a["boss_species"])
			options.append({"label":{"defeated":"核实本人讨伐记录","bypass":"操作西翼绕行绞盘","absent":"记录当前空城"}[outcome],
				"action":"campaign|act|"+str(a["id"])+"|"+outcome,"enabled":enabled,
				"consequence":"记录真实绕行，不计作击杀" if outcome=="bypass" else ("记录当前没有活体，不计作讨伐" if outcome=="absent" else "核对本存档中该城塞实名击杀凭证"),
				"risk":"Boss以后仍按原生态规则复生，历史行动与奖励不重置"})
		return {"kind":"camp_choice","giver":a["title"],"text":("当前城塞仍有存活的%s。" % a["boss_species"] if not living.is_empty() else "已核对当前城塞，没有这位Boss的存活实例。")+"\n"+str(a["text"]),"origin":host._world_position(str(a["object"])),"options":options}
	if kind == "puzzle" and a.get("puzzle_objects",[]).is_empty():
		var options: Array = []
		for symbol: String in a.get("puzzle_order",[]):
			var label: String = {"split":"分队","withdrawal":"撤守","lost":"失联"}.get(symbol,symbol)
			options.append({"label":"放入「%s」记录"%label,"action":"campaign|sequence|"+str(a["id"])+"|"+symbol,"enabled":true,"consequence":"按已取得的实物日志排列因果","risk":"顺序错误只重置未完成排列，不消耗记录"})
		return {"kind":"camp_choice","giver":a["title"],"text":"把此前实物证据按发生次序放入：先分队，再撤守，最后失联。\n已放置%d/%d张；每次都需要明确确认。"%[_q().get("puzzle_progress",{}).get(a["id"],[]).size(),a["puzzle_order"].size()],"origin":host._world_position(str(a["object"])),"options":options}
	return {}
func proof(a: Dictionary, choice: String) -> Dictionary:
	var proof: Dictionary = host._position_proof(str(a["object"]))
	match str(a["kind"]):
		"route":
			var route := str(_q().get("quests",{}).get(a["stage"],{}).get("choice",""))
			var visited: Array = _q().get("main_routes",{}).get(a["id"],{}).get("visited",[])
			if route not in ["near","outer"] or visited.size() < CampaignLayout.route_waypoints(route).size():
				return {"error":"请沿已选路线实走：近路穿过石障缺口，外缘经过西侧两处转折；仅在终点确认不能代替通行"}
			if route=="near" and not _near_barrier_broken(): return {"error":"近路需要实际敲开登记石障并走过缺口，外缘绕行不能记成近路"}
			proof.merge({"route":route,"traversed":true})
		"obstacle":
			var cells: Array = CampaignLayout.barrier_cells(str(a["object"]))
			if cells.is_empty(): return {"error":"没有找到此处登记的可破坏障碍"}
			var broken := false
			for cell: Vector2i in cells:
				if "%d,%d"%[cell.x,cell.y] in ObstacleField.destroyed_list(): broken = true
			if not broken: return {"error":"需要用真实攻击打碎这里的冰障，再核验开出的缺口"}
			proof.merge({"obstacle_key":str(a["object"]),"destroyed":true})
		"encounter":
			if not choice in a.get("choices",[]): return {"error":"请明确选择当前真实可行的接近方式"}
			if choice != "bypass" and not _live_boss(str(a["boss_species"])).is_empty(): return {"error":"Boss仍在城塞活动，不能登记为空城或已经讨伐"}
			proof.merge({"outcome":choice,"verified":true})
			if choice == "defeated":
				var kill: Dictionary = _q().get("main_kills",{}).get(a["boss_species"],{})
				if kill.is_empty() or str(kill.get("region_id","")) != str(CampaignLayout.sites()[_terrain(a)]["region_id"]): return {"error":"当前没有可核实的本人城塞击杀凭证；空城调查仍可如实记录"}
				proof["instance_id"] = kill["instance_id"]
				proof["player_kill"] = true
		"observe":
			var region: SimRegion = WorldSim.sim.region_of_point(host._world_position(str(a["object"]))) if WorldSim.sim != null else null
			if region == null: return {"error":"当前世界尚未就绪，不能编造观察记录"}
			var counts: Dictionary = {}
			for node: Node in get_tree().get_nodes_in_group("monsters"):
				if not node is MonsterBase: continue
				var actor := node as MonsterBase
				if actor.state == MonsterBase.S_CORPSE or not actor.is_visible_in_tree(): continue
				var inst: MonsterInstance = actor.get("inst")
				if inst == null or not inst.is_alive or inst.region_id != region.id: continue
				var player := host._player() as Node2D
				if player == null or player.global_position.distance_to(actor.global_position)>640.0: continue
				if not get_viewport().get_visible_rect().has_point(get_viewport().get_canvas_transform()*actor.global_position): continue
				var ray := PhysicsRayQueryParameters2D.create(player.global_position,actor.global_position,1)
				if player is CollisionObject2D: ray.exclude=[(player as CollisionObject2D).get_rid()]
				if not player.get_world_2d().direct_space_state.intersect_ray(ray).is_empty(): continue
				counts[inst.species.species_name] = int(counts.get(inst.species.species_name,0))+1
			proof["snapshot"] = {"region_id":region.id,"species_counts":counts,"tick":WorldSim.sim.tick_count,"outcome":"observed"}
		"choice": proof["choice"] = choice
	return {"proof":proof}
func sequence(action_id: String, symbol: String) -> String:
	var a: Dictionary = host._actions.get(action_id,{})
	if a.is_empty() or str(a.get("chapter","")).is_empty() or a["kind"] != "puzzle" or not a.get("puzzle_objects",[]).is_empty(): return "未知的证据排列"
	if not host._at_object(str(a["object"])) or host._paused(str(a["chain"])) or not Data.can_record(_q(),a["stage"],action_id): return "请带齐证据，回到核对板旁再排列"
	var order: Array = a["puzzle_order"]
	var progress: Array = _q().get("puzzle_progress",{}).get(action_id,[]).duplicate()
	if progress.size() >= order.size() or symbol != str(order[progress.size()]):
		_q()["puzzle_progress"][action_id] = []
		host._save()
		return "次序与日志不合，未完成排列已清空；记录本身保留"
	progress.append(symbol)
	_q()["puzzle_progress"][action_id] = progress
	if progress == order:
		GameState.begin_world_reward()
		var evidence: Dictionary = host._position_proof(str(a["object"]))
		evidence["order"] = progress
		Data.record(_q(),a["stage"],action_id,evidence)
		host._settle_ready()
		host._save()
		GameState.end_world_reward()
		return str(a["text"])
	host._save()
	return "已排列%d/%d张，继续核对下一份日志"%[progress.size(),order.size()]
func _live_boss(species: String) -> Array:
	var result: Array = []
	if WorldSim.sim == null: return ["world_not_ready"]
	for inst: MonsterInstance in WorldSim.sim.instances.values():
		if inst.is_alive and inst.species.is_boss and inst.species.species_name == species: result.append(inst.id)
	return result
func _terrain(a: Dictionary) -> String:
	return str(Catalog.stage(str(a["stage"])).get("terrain",""))
func _choice_consequence(choice: String) -> String:
	return {"near":"选择较短通道，需亲手破除实际碎岩路障并走过缺口","outer":"沿西侧外缘绕过岩障，需实际走完两个转折","distributed":"四位新增远征队员分别驻守林地、沼泽、丘陵、雪原，提供分布补给","centralized":"四位新增幸存者迁到平原新增避难所，补给接待集中于此"}.get(choice,"保留此次明确选择")
func state() -> Dictionary:
	var state := {"open_gates":[],"rescued":{},"placements":{},"ending":""}
	if host._proof_exists("watch_c4_hill:s2:winch"): state["open_gates"].append("c4:archive_gate")
	if host._proof_exists("watch_c4_hill:s4:keeper"): state["rescued"]["c4:map_keeper"] = true
	if host._proof_exists("watch_c6_lava:s2:passage"): state["open_gates"].append("c6:core_gate")
	if Data.ready(_q(),"watch_c2_forest:s4"):
		state["placements"]["side_troll:departure"] = {"hidden":false}
	if Data.ready(_q(),"watch_c6_lava:s4"):
		var ending := str(_q().get("quests",{}).get("watch_c6_lava:s4",{}).get("choice",""))
		state["ending"] = ending
		for npc: String in CampaignLayout.ending_positions(ending):
			var pos: Vector2 = CampaignLayout.ending_positions(ending)[npc]
			state["placements"][npc] = {"position":[pos.x,pos.y],"service":"远征补给","hidden":false}
		state["placements"]["ending:shelter"] = {"hidden":ending!="centralized"}
	return state


func _near_barrier_broken() -> bool:
	var destroyed: Array = ObstacleField.destroyed_list()
	for cell: Vector2i in CampaignLayout.barrier_cells("c3:near_barrier"):
		if "%d,%d"%[cell.x,cell.y] in destroyed: return true
	return false
