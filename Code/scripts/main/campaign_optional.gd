## 人物与区域线运行层：作者物件、唯一物资、实走路线与分支工程。
## 此节点不接普通随机委托、不制造族群；所有可用服务均由已验证证据投影。
class_name CampaignOptional
extends Node

const Presentation := preload("res://scripts/ui/quest_presentation.gd")
const Data := preload("res://scripts/main/campaign_quest_data.gd")
const Inventory := preload("res://scripts/main/camp_quest_inventory.gd")
const Catalog := preload("res://scripts/main/campaign_catalog.gd")
const Layout := preload("res://scripts/ecology/campaign_layout.gd")
const FAMILIES := ["side", "regional"]
const LOCAL_RADIUS := 1400.0
const MIN_GLOBAL_STOCK := 6
const FOREST_SEARCH_RADIUS := 6400.0
var _host: Node
var _mutating := false
var _sim: EcologySim
var _deaths: Dictionary = {}
var _death_instances: Dictionary = {}
var _poll := 0.0
var _last_player_position := Vector2.INF
var _last_teleport_serial := -1
var _action_cache: Array = []
var _action_map: Dictionary = {}
var _chain_cache: Dictionary = {}

func setup(host: Node) -> void:
	_host = host
	name = "CampaignOptional"
	_action_cache.clear()
	_action_map.clear()
	_chain_cache.clear()
	for chain: Dictionary in Catalog.chains():
		if str(chain.get("family", "")) not in FAMILIES: continue
		_chain_cache[chain["id"]] = chain
		for stage: Dictionary in chain.get("steps", []):
			for a: Dictionary in stage.get("actions", []):
				_action_cache.append(a)
				_action_map[a["id"]] = a

func _ready() -> void:
	EventBus.monster_killed_at.connect(_on_player_kill)
	EventBus.nest_ransacked_at.connect(_on_ransack)
	_bind_sim()

func _physics_process(delta: float) -> void:
	if not is_instance_valid(_host): return
	_bind_sim()
	_poll += delta
	if _poll < 0.12: return
	var elapsed := _poll
	_poll = 0.0
	_track_routes(elapsed)

func _bind_sim() -> void:
	if _sim == WorldSim.sim: return
	if _sim != null and _sim.instance_died.is_connected(_on_instance_died):
		_sim.instance_died.disconnect(_on_instance_died)
	_sim = WorldSim.sim
	_deaths.clear()
	_death_instances.clear()
	if _sim != null: _sim.instance_died.connect(_on_instance_died)

func _exit_tree() -> void:
	if _sim != null and _sim.instance_died.is_connected(_on_instance_died):
		_sim.instance_died.disconnect(_on_instance_died)

func _q() -> Dictionary:
	return _host.call("ledger") if is_instance_valid(_host) else {}

func _enabled(chain_id: String) -> bool:
	var chain: Dictionary = _chain_cache.get(chain_id, {})
	return not chain.is_empty() and str(chain.get("family", "")) in FAMILIES and bool(_host.call("_chapter_enabled", chain))

func _paused(chain_id: String) -> bool:
	return chain_id in _q().get("paused_chains", [])

func handles_object(object_id: String) -> bool:
	return object_id.begins_with("side_") or object_id.begins_with("region_")

func handles_action(action_id: String) -> bool:
	return action_id.begins_with("side_") or action_id.begins_with("region_")

func _object(object_id: String) -> Node2D:
	if not is_inside_tree(): return null
	for node: Node in get_tree().get_nodes_in_group("campaign_objects"):
		if node is Node2D and str(node.get("campaign_id")) == object_id:
			return node as Node2D
	return null

func _at(object_id: String) -> bool:
	var node := _object(object_id)
	return node != null and node.is_visible_in_tree() and not node.is_queued_for_deletion() and node.has_method("can_interact") and bool(node.call("can_interact"))

func _position(object_id: String) -> Vector2:
	var node := _object(object_id)
	if node != null: return node.global_position
	var bound: Array = _q().get("optional_bindings", {}).get("region_forest", {}).get("positions", {}).get(object_id, [])
	return Vector2(float(bound[0]), float(bound[1])) if bound.size() == 2 else Layout.object_position(object_id)

func _proof(object_id: String) -> Dictionary:
	var pos := _position(object_id)
	return {"position": [pos.x, pos.y], "tick": _sim.tick_count if _sim != null else 0, "destination": object_id}

func _title(object_id: String) -> String:
	var node := _object(object_id)
	return str(node.get("title")) if node != null else str(_host.call("_object_title", object_id))

func _info(text: String, object_id := "") -> Dictionary:
	return {"kind": "info", "giver": _title(object_id), "text": text}

func _choice(a: Dictionary) -> String:
	var sid := str(a.get("choice_stage", a.get("stage", "")))
	return str(_q().get("quests", {}).get(sid, {}).get("choice", ""))

func action_object(a: Dictionary) -> String:
	var destinations: Dictionary = a.get("destination_by_choice", a.get("branch_objects", {}))
	return str(destinations.get(_choice(a), a.get("object", "")))

func _done(a: Dictionary) -> bool:
	return _q().get("quests", {}).get(a.get("stage", ""), {}).get("evidence", {}).has(a.get("id", ""))

func _can(a: Dictionary) -> bool:
	var state: Dictionary = _q().get("quests", {}).get(a.get("stage", ""), {})
	if not state.get("accepted", false) or state.get("evidence", {}).has(a.get("id", "")): return false
	return _enabled(str(a.get("chain", ""))) and not _paused(str(a.get("chain", ""))) and Data.can_record(_q(), str(a.get("stage", "")), str(a.get("id", "")))

func _actions() -> Array:
	return _action_cache

func _start_object(stage: Dictionary) -> String:
	var chain := str(stage.get("chain", ""))
	if chain == "region_forest" and int(stage.get("index", 0)) == 0: return "region_forest:guide"
	if stage.get("family", "") == "regional":
		return chain + ([":survey_a", ":choice", ":station"][clampi(int(stage.get("index", 0)), 0, 2)])
	return chain + (":giver" if int(stage.get("index", 0)) == 0 else ":resolution")

func _next_stage(chain_id: String) -> Dictionary:
	for stage: Dictionary in Catalog.chain(chain_id).get("steps", []):
		if not Data.ready(_q(), str(stage["id"])): return stage
	return {}

func _action_payload(a: Dictionary) -> Dictionary:
	var object_id := action_object(a)
	var body := Presentation.action_prompt(a)
	if str(a.get("kind", "")) == "choice":
		var options: Array = []
		for option: Variant in a.get("choices", []):
			var id := str(option.get("id", "")) if option is Dictionary else str(option)
			var title := str(option.get("title", id)) if option is Dictionary else id
			options.append({"label": title, "action": "campaign|optional|act|" + str(a["id"]) + "|" + id,
				"enabled": true, "consequence": str(option.get("consequence", body)) if option is Dictionary else body,
				"risk": str(option.get("risk", "选定后，前往对应地点完成这件事")) if option is Dictionary else "选定后，前往对应地点完成这件事"})
		return Presentation.with_narrative({"kind": "camp_choice", "giver": _title(object_id), "origin": _position(object_id), "text": body, "options": options}, a)
	return Presentation.with_narrative({"kind": "camp_action", "giver": _title(object_id), "origin": _position(object_id), "text": body,
		"confirm_text": str(a.get("verb", "确认")), "action": "campaign|optional|act|" + str(a["id"])}, a)

func object_payload(object_id: String) -> Dictionary:
	if not handles_object(object_id): return {}
	var chain_id := object_id.get_slice(":", 0)
	if not _enabled(chain_id): return _info("这条线索还没有消息", object_id)
	if not _at(object_id): return _info("再走近些，从能看清的地方查看", object_id)
	var stage := _next_stage(chain_id)
	if _paused(chain_id):
		return {"kind": "camp_action", "giver": _title(object_id), "origin": _position(object_id), "text": "先前的线索都还在。接着从上次停下的地方往下查吗？", "confirm_text": "继续调查", "action": "campaign|optional|resume|" + chain_id + "|" + object_id}
	if not stage.is_empty() and not _q().get("quests", {}).get(stage["id"], {}).get("accepted", false) and object_id == _start_object(stage):
		return Presentation.with_narrative({"kind": "camp_action", "giver": _title(object_id), "origin": _position(object_id), "text": Presentation.action_prompt(stage.get("actions", [{}])[0]), "confirm_text": "顺着线索看看", "action": "campaign|optional|accept|" + str(stage["id"]) + "|" + object_id}, stage.get("actions", [{}])[0])
	for a: Dictionary in _actions():
		if not _can(a): continue
		if object_id in a.get("puzzle_objects", []):
			return Presentation.with_narrative({"kind": "camp_action", "giver": _title(object_id), "origin": _position(object_id), "text": "石上的符记微微发亮。想起旧旗留下的次序，再伸手触碰它。", "confirm_text": "触碰符记", "action": "campaign|optional|rune|" + str(a["id"]) + "|" + object_id}, a)
		if object_id == action_object(a):
			if a.get("kind", "") == "boss":
				var credit: Dictionary = _q().get("optional_targets", {}).get("side_troll", {})
				if not credit.get("kills", []).is_empty(): return _action_payload(a)
				return Presentation.with_narrative({"kind": "camp_action", "giver": _title(object_id), "origin": _position(object_id), "text": "这里可以查看巨魔王的踪迹。要不要挑战，由你决定；旧房间仍可继续调查。", "confirm_text": "查看并选择挑战", "action": "campaign|optional|challenge|" + str(a["id"])}, a)
			if a.get("kind", "") == "puzzle": return Presentation.with_narrative(_info("旧旗上的针脚还记得：先叶，再石，最后灯。去房门外逐一触碰它们", object_id), a)
			return _action_payload(a)
	var effects := visual_state()
	if effects.get("services", {}).has(object_id):
		var service_id := str(effects["services"][object_id])
		var claimed := Data.service_claimed(_q(), service_id)
		var text := "给你留的饭团已经领过了。还缺东西的话，可以看看站里的货。" if claimed else "站里能歇脚了，给你留了一个饭团。还需要什么，也可以看看这里的货。"
		if chain_id == "region_plains" and _q().get("quests", {}).get("region_plains:s2", {}).get("choice", "") == "outer":
			text += "接应站与外缘补给台共用的这一份已经领完，两边都没有再留第二份。" if claimed else "这份饭团也能从外缘补给台领，选一处就好。"
		if chain_id == "side_watchman":
			var branch := str(_q().get("quests", {}).get("side_watchman:s2", {}).get("choice", ""))
			var point := Layout.entry("hill") if branch == "near" else Layout.object_position("region_hill:survey_b")
			text += "认着新旗，从这里向%s走，是%s。那边如今怎样，还得路上留心。" % [_direction(_position(object_id), point), "丘陵接近点" if branch == "near" else "岩脊旧道另一端"]
		var options: Array = []
		if not claimed:
			options.append({"label":"领取驻站补给", "action":"campaign|optional|supply|" + object_id, "enabled":true, "consequence":"饭团×1", "risk":"放不下的补给存入背包→待领取"})
		options.append({"label":"站点商店", "action":"campaign|optional|shop|" + object_id, "enabled":true, "consequence":"查看物品与价格", "risk":"购买前明确选择并支付"})
		return {"kind":"camp_choice", "giver":_title(object_id), "origin":_position(object_id), "text":text, "options":options}
	for a: Dictionary in _actions():
		if _done(a) and object_id == action_object(a):
			return Presentation.with_narrative(_info(("已读 · " if a.get("kind", "") == "read" else "已完成 · ") + str(a.get("text", "")), object_id), a)
	return _info("这里暂时没有新发现。沿手头的线索继续看看", object_id)

func action(parts: Variant) -> String:
	# 宿主可传完整 campaign|optional|...，也可传去掉前两个字段的参数。
	var args: Array = []
	if not parts is Array and not parts is PackedStringArray: return "未识别的故事行动"
	for value: Variant in parts: args.append(str(value))
	if args.size() >= 2 and str(args[0]) == "campaign" and str(args[1]) == "optional": args = args.slice(2)
	if args.is_empty(): return "未识别的故事行动"
	match str(args[0]):
		"accept": return accept_stage(str(args[1]), str(args[2])) if args.size() >= 3 else "缺少接取地点"
		"resume": return resume(str(args[1]), str(args[2])) if args.size() >= 3 else "缺少继续地点"
		"act": return perform_action(str(args[1]), str(args[2]) if args.size() >= 3 else "") if args.size() >= 2 else "缺少行动编号"
		"rune": return touch_rune(str(args[1]), str(args[2])) if args.size() >= 3 else "缺少符记编号"
		"supply": return claim_service(str(args[1])) if args.size() >= 2 else "缺少服务站点"
		"challenge": return _challenge(str(args[1])) if args.size() >= 2 else "缺少挑战编号"
		"shop":
			if args.size() < 2 or not _at(str(args[1])) or not visual_state().get("services", {}).has(str(args[1])): return "服务尚未恢复，或需要到站点身旁"
			EventBus.npc_dialogue.emit({"kind": "shop", "giver": _title(str(args[1])), "text": "站里重新备上货了，价钱还是家园的价钱。看看路上还缺什么。"})
			return ""
	return "未识别的故事行动"

func accept_stage(stage_id: String, origin_id: String) -> String:
	var stage := Catalog.stage(stage_id)
	if stage.is_empty() or not _enabled(str(stage.get("chain", ""))): return "这条线索还没有消息"
	if origin_id != _start_object(stage) or not _at(origin_id): return "请走到线索所在处，再仔细看看"
	if not Data.accept(_q(), stage_id, GameState.stats.level): return "当前前置尚未完成，或这一段已经接取"
	GameState.tracked_quest_id = stage_id
	_host.call("_save")
	return "已接取：" + str(stage["title"])

func resume(chain_id: String, object_id: String) -> String:
	if not _enabled(chain_id) or object_id.get_slice(":", 0) != chain_id or not _at(object_id): return "请回到这条线索所在处继续"
	if _q().has("paused_chains"): _q()["paused_chains"].erase(chain_id)
	_host.call("_save")
	return "已继续，上次的调查进度保留"

func perform_action(action_id: String, choice := "") -> String:
	if _mutating: return ""
	var a: Dictionary = _action_map.get(action_id, {})
	if a.is_empty() or not handles_action(action_id) or not _can(a): return "先查看当前线索，再继续这一步"
	var object_id := action_object(a)
	if not _at(object_id): return "请走到选定地点，再查看或交付"
	if object_id in _q().get("optional_bindings", {}).get("region_forest", {}).get("positions", {}) and not _dry_body_segment(_position(object_id),_position(object_id)): return "原标记点当前无法干燥通行；请按现场道路从可行方向重新接近，不能隔墙施工"
	if a.get("kind", "") == "puzzle": return "请逐一操作现场符记，不能从记录页直接解开机关"
	var proof := _proof(object_id)
	if a.get("kind", "") == "choice": proof["choice"] = choice
	elif not _choice(a).is_empty(): proof["choice"] = _choice(a)
	var error := _verify(a, proof)
	if not error.is_empty(): return error
	return _commit(a, proof)

func _commit(a: Dictionary, proof: Dictionary) -> String:
	_mutating = true
	GameState.begin_world_reward()
	var recorded := Data.record(_q(), str(a["stage"]), str(a["id"]), proof)
	if recorded:
		if a.get("ecology_mode", "") == "nest_clue": _bind_forest_markers()
		_host.call("_settle_ready")
		_host.call("_save")
	GameState.end_world_reward()
	_mutating = false
	if recorded and a.get("ecology_mode", "") == "nest_clue" and not _q().get("optional_bindings", {}).has("region_forest"):
		return "巡线员摇摇头：这附近暂时没有能指给你的巢址。先到原来的调查点看看，林缘那条绕行路还可以考虑。"
	if recorded and a.get("ecology_mode", "") == "hunter_counts":
		return str(a.get("text", "现场行动已记录")) + "\n" + str(proof.get("witness", ""))
	return str(a.get("text", "现场行动已记录")) if recorded else "证据不完整，行动未记入账本"

func _verify(a: Dictionary, proof: Dictionary) -> String:
	var consumes := str(a.get("consumes", a.get("consumes_quest_item", "")))
	if not consumes.is_empty():
		if not _has_item(consumes): return "需要的物资还没取到，或已交到另一处"
		proof["item"] = consumes
	if a.has("quest_item"): proof["item"] = str(a["quest_item"])
	var kind := str(a.get("kind", ""))
	if kind == "choice":
		var branch := str(proof.get("choice", ""))
		var chain_id := str(a.get("chain", ""))
		if (chain_id == "side_hunter" and branch == "local") or (chain_id == "region_forest" and branch in ["near", "nest", "ransack"]):
			var target := _choose_local_target(chain_id + (":target" if chain_id == "side_hunter" else ":survey_a"), chain_id == "region_forest")
			if target.is_empty(): return "现在不适合动手：附近没有能够稳妥处理并留下余量的目标。请改选警示或绕行"
			for key: String in ["target_key", "region_id", "species", "unit_ids"]: proof[key] = target[key]
			proof["target_position"] = target["position"]
	if kind == "boss":
		var kills: Array = _q().get("optional_targets", {}).get(str(a.get("chain", "")), {}).get("kills", [])
		if kills.is_empty(): return "还没有亲自击败这次选定的巨魔王；若它已经离开，可继续调查旧房间"
		var event: Dictionary = kills[0]
		proof["instance_id"] = int(event.get("instance_id", -1))
		proof["player_kill"] = true
		proof["region_id"] = str(event.get("from_region", ""))
		proof["species"] = str(event.get("species", ""))
		proof["events"] = kills.duplicate(true)
	var barriers: Dictionary = a.get("obstacle_by_choice", {})
	if kind == "obstacle" or barriers.has(_choice(a)):
		var key := str(barriers.get(_choice(a), a.get("barrier_id", a.get("object", ""))))
		if not _barrier_destroyed(key): return "这处路障还有碎岩挡着，请先打通缺口"
		proof["obstacle_key"] = key
		proof["destroyed"] = true
	if kind == "route":
		if _q().get("optional_route_reanchor", {}).get(a["id"], false): return "已走过的路线保留；先回到最后核实点，实走一步后继续验收"
		var needed := _route_points(a)
		if needed.is_empty(): return "这条路线缺少登记验收点，不能虚记完工"
		var visited: Array = _q().get("optional_routes", {}).get(a["id"], [])
		for id: String in needed:
			if id not in visited: return "请实走选定路线的各个标记点，再到站点验收"
		var geometry := route_geometry(a)
		if int(_q().get("optional_route_steps", {}).get(a["id"], 0)) < geometry.size(): return "请沿实地标出的转折走完选定通路，不能只到两个端点"
		if not _passage(a).is_empty() and not _passage_proven(a): return "请亲自穿过本次修开的登记缺口或机关门；外侧绕行不能代替验收"
		proof["visit_ids"] = visited.duplicate()
		proof["route"] = _choice(a)
		proof["traversed"] = true
		proof["witness"] = "walked:" + ",".join(needed)
	var mode := str(a.get("ecology_mode", ""))
	if mode == "hunter_counts" or (str(a.get("chain", "")) == "side_hunter" and kind == "observe"):
		var counts := _local_snapshot(action_object(a))
		proof["counts"] = counts.get("counts", {})
		proof["unit_ids"] = counts.get("unit_ids", [])
		proof["events"] = counts.get("events", [])
		proof["region_id"] = counts.get("region_id", "")
		proof["witness"] = _counts_text(counts)
	if mode == "watch_sight" or (str(a.get("chain", "")) == "side_watchman" and kind == "observe"):
		var from := _position("side_watchman:giver")
		proof["witness"] = "old:%s;near:%s;high:%s" % ["visible" if _clear_segment(from,_position("side_watchman:old_flag")) else "blocked", "visible" if _clear_segment(from, _position("side_watchman:watch_near")) else "blocked", "visible" if _clear_segment(from, _position("side_watchman:watch_high")) else "blocked"]
	if mode == "troll_state" or (str(a.get("chain", "")) == "side_troll" and kind == "observe"):
		var bosses := _local_bosses("巨魔王", _position(action_object(a)), 2200.0)
		proof["unit_ids"] = bosses
		proof["witness"] = "present" if not bosses.is_empty() else "not_present"
	if kind == "ecology": return _verify_ecology(a, proof)
	if mode == "nest_survey":
		var nests := _nearby_nests(_position(action_object(a)))
		proof["witness"] = "active_nests:" + ",".join(nests)
		proof["counts"] = {"active_nests": nests.size()}
	if mode == "lava_boundary" or (str(a.get("chain", "")) == "region_lava" and kind == "observe"):
		var sample := _liquid_boundary(_position(action_object(a)))
		proof["witness"] = "lava_samples:%d;safe_samples:%d" % [sample.lava, sample.safe]
		proof["counts"] = sample
	return ""

func _has_item(item: String) -> bool:
	var obtained := false
	for a: Dictionary in _actions():
		if not _done(a): continue
		if str(a.get("quest_item", "")) == item: obtained = true
		if str(a.get("consumes", a.get("consumes_quest_item", ""))) == item: return false
	return obtained

func _barrier_destroyed(id: String) -> bool:
	var cells := Layout.barrier_cells(id)
	if cells.is_empty(): return false
	var destroyed := ObstacleField.destroyed_list()
	for cell: Vector2i in cells:
		if "%d,%d" % [cell.x, cell.y] not in destroyed: return false
	return true

func _route_points(a: Dictionary) -> Array:
	var routes: Dictionary = a.get("route_by_choice", {})
	if routes.has(_choice(a)): return routes[_choice(a)].duplicate()
	return a.get("route_waypoints", []).duplicate()

func _track_routes(elapsed := 1.0 / 60.0) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null or not player.is_visible_in_tree(): return
	var current := player.global_position
	var previous := _last_player_position
	var movement := _last_player_position.distance_to(current) if _last_player_position.is_finite() else 0.0
	var teleported: bool = player is Player and _last_teleport_serial >= 0 and player.teleport_serial != _last_teleport_serial
	var dead: bool = player is Player and player._is_dead
	if player is Player: _last_teleport_serial = player.teleport_serial
	var discontinuous: bool = dead or teleported or _last_player_position.is_finite() and (movement > maxf(48.0, 1400.0 * minf(elapsed, 0.25)) or not _clear_route_segment(_last_player_position, current))
	_last_player_position = current
	for a: Dictionary in _actions():
		if a.get("kind", "") != "route" or not _can(a): continue
		var points := _route_points(a)
		if points.is_empty(): continue
		var visits: Array = _q().get("optional_routes", {}).get(a["id"], []).duplicate()
		var geometry := route_geometry(a)
		var step := int(_q().get("optional_route_steps", {}).get(a["id"], 0))
		# 死亡/远征保留已经核实的贡献，只要求重新走回最后核实点接续。
		if discontinuous and (not visits.is_empty() or step > 0):
			if not _q().has("optional_route_reanchor"): _q()["optional_route_reanchor"] = {}
			if not _q()["optional_route_reanchor"].get(a["id"], false):
				_q()["optional_route_reanchor"][a["id"]] = true
				_host.call("_save")
			continue
		if discontinuous: continue
		if _q().get("optional_route_reanchor", {}).get(a["id"], false):
			if movement > 0.1 and _segment_near(previous, current, _route_anchor(a), 90.0):
				_q()["optional_route_reanchor"].erase(a["id"])
				_host.call("_save")
			continue
		if not visits.is_empty() and not _passage_proven(a) and _crossed_passage(a, previous, current):
			if not _q().has("optional_route_passages"): _q()["optional_route_passages"] = {}
			_q()["optional_route_passages"][a["id"]] = {"seed":GameState.world_seed,"route":_choice(a),"passage":_passage(a)["id"],"from":[previous.x,previous.y],"to":[current.x,current.y]}
			_host.call("_save")
		if step < geometry.size() and not visits.is_empty() and _segment_near(previous, current, geometry[step], 90.0):
			step += 1
			_set_route_step(a["id"], step)
			_host.call("_save")
		# 抵达终点不能跳过路上的转折；原始施工点仍须在现场先核对。
		if visits.size() >= points.size() or (not visits.is_empty() and step < geometry.size()): continue
		var next := str(points[visits.size()])
		if not _at(next): continue
		visits.append(next)
		if not _q().has("optional_routes"): _q()["optional_routes"] = {}
		_q()["optional_routes"][a["id"]] = visits
		_host.call("_save")

func _passage(a: Dictionary) -> Dictionary:
	var chain: Dictionary = _chain_cache.get(str(a.get("chain", "")), {})
	return Layout.regional_passage(str(chain.get("terrain", "")), _choice(a)) if a.get("kind", "") == "route" else {}

func _passage_proven(a: Dictionary) -> bool:
	var passage := _passage(a)
	if passage.is_empty(): return true
	return not Data.regional_passage_proof(_q().get("optional_route_passages", {}).get(a["id"]), a, _choice(a), GameState.world_seed).is_empty()

func _crossed_passage(a: Dictionary, previous: Vector2, current: Vector2) -> bool:
	var passage := _passage(a)
	if passage.is_empty() or not previous.is_finite() or not current.is_finite(): return false
	if passage.kind == "barrier":
		if not _barrier_destroyed(passage.id): return false
	else:
		if passage.id not in visual_state().get("open_gates", []): return false
		for cell: Vector2i in Layout.gate_cells(passage.id):
			if not Layout.obstacle_kind(cell).is_empty(): return false
	var candidate := {"seed":GameState.world_seed,"route":_choice(a),"passage":passage.id,"from":[previous.x,previous.y],"to":[current.x,current.y]}
	if Data.regional_passage_proof(candidate, a, _choice(a), GameState.world_seed).is_empty(): return false
	var count := maxi(1,ceili(previous.distance_to(current)/8.0))
	for index in range(count+1):
		if ObstacleField.blocks(previous.lerp(current,float(index)/count),10.0): return false
	return _clear_route_segment(previous,current)

func _route_anchor(a: Dictionary) -> Vector2:
	var points := _route_points(a)
	var visits: Array = _q().get("optional_routes", {}).get(a["id"], [])
	if not points.is_empty() and visits.size() == points.size(): return _position(str(points[-1]))
	var geometry := route_geometry(a)
	var step := int(_q().get("optional_route_steps", {}).get(a["id"], 0))
	if step > 0 and step <= geometry.size(): return geometry[step - 1]
	return _position(str(visits[-1])) if not visits.is_empty() else _position(action_object(a))

func touch_rune(action_id: String, object_id: String) -> String:
	var a: Dictionary = _action_map.get(action_id, {})
	if a.is_empty() or not _can(a) or not _at(object_id): return "先到当前可操作的符记旁"
	var objects: Array = a.get("puzzle_objects", [])
	var order: Array = a.get("puzzle_order", [])
	if object_id not in objects or objects.size() != order.size() or order.is_empty(): return "这不是登记机关的操作点"
	if not _q().has("puzzle_progress"): _q()["puzzle_progress"] = {}
	var progress: Array = _q()["puzzle_progress"].get(action_id, []).duplicate()
	var symbol := str(order[objects.find(object_id)])
	if progress.size() >= order.size() or symbol != str(order[progress.size()]):
		_q()["puzzle_progress"][action_id] = []
		_host.call("_save")
		return "次序不合，符光熄灭了。想想旧旗：先叶，再石，最后灯"
	progress.append(symbol)
	_q()["puzzle_progress"][action_id] = progress
	if progress != order:
		_host.call("_save")
		return "符记响应（%d/%d）" % [progress.size(), order.size()]
	var proof := _proof(object_id)
	proof["order"] = progress
	return _commit(a, proof)

func _actor_position(inst: MonsterInstance) -> Vector2:
	for actor: Node in get_tree().get_nodes_in_group("monsters"):
		if actor is Node2D and actor.get("inst") == inst: return actor.global_position
	return inst.spawn_pos

func _clear_segment(from: Vector2, to: Vector2) -> bool:
	if not from.is_finite() or not to.is_finite(): return false
	var count := maxi(1, ceili(from.distance_to(to) / 12.0))
	for index in range(count + 1):
		if ObstacleField.nav_blocked_at(from.lerp(to, float(index) / count)): return false
	return true

func _feasible(inst: MonsterInstance) -> bool:
	if inst == null or not inst.is_alive or inst.species.is_boss or inst.species.ambient: return false
	var band: Dictionary = CombatBandMath.TERRAIN_BANDS["plains"]
	for candidate: Dictionary in CombatBandMath.TERRAIN_BANDS.values():
		if int(candidate["expected"]) <= GameState.stats.level and int(candidate["expected"]) > int(band["expected"]): band = candidate
	var heavy := inst.species.defense_reduction >= CombatBandMath.HEAVY_DEF
	var kills: Array = band["kill_heavy" if heavy else "kill"]
	var attackers := CombatBandMath.attackers_of(inst.species)
	var floor_value: float = CombatBandMath.HEAVY_DIE_FLOOR if heavy else band["die_pack" if attackers == 3 else "die_solo"]
	return CombatBandMath.hits_to_kill(inst, GameState.stats.physical_attack()) <= int(kills[1]) and CombatBandMath.hits_to_die(inst, GameState.stats.max_hp(), attackers) >= floor_value

func _local_snapshot(object_id: String) -> Dictionary:
	var position := _position(object_id)
	var region_id := BiomeMap.region_id_at(position)
	var result := {"region_id": region_id, "unit_ids": [], "events": [], "counts": {"seen_alive": 0, "player_killed": 0, "aging": 0, "predated": 0}, "coverage": "本次实际观察以来"}
	if _sim == null: return result
	for inst: MonsterInstance in _sim.instances.values():
		if not inst.is_alive or inst.region_id != region_id: continue
		var actual := _actor_position(inst)
		if actual.distance_to(position) <= 680.0 and _loaded_actor(inst) != null and _clear_segment(position, actual): result["unit_ids"].append(inst.id)
	result["counts"]["seen_alive"] = result["unit_ids"].size()
	var events: Array = _retained_events()
	for event: Dictionary in events:
		if event.get("kind", "") != "death" or event.get("from_region", event.get("region_id", "")) != region_id: continue
		var event_pos: Array = event.get("position", [])
		if event_pos.size() != 2 or Vector2(float(event_pos[0]), float(event_pos[1])).distance_to(position) > LOCAL_RADIUS: continue
		result["events"].append(event.duplicate(true))
		var cause := str(event.get("cause", ""))
		if cause == "killed": result["counts"]["player_killed"] += 1
		elif cause in ["aging", "predated"]: result["counts"][cause] += 1
	return result

func _retained_events() -> Array:
	# 有界事实账本只说明保留窗口；不把它叫作全档历史总数。
	for node: Node in get_tree().get_nodes_in_group("campaign_world_facts"):
		if node.has_method("snapshot"):
			var snapshot: Dictionary = node.call("snapshot")
			return snapshot.get("events", []).duplicate(true)
	return _deaths.values()

func _counts_text(snapshot: Dictionary) -> String:
	var counts: Dictionary = snapshot.get("counts", {})
	return "此刻可见%d只。这段观察期间，你猎杀%d只，衰老%d只，遭捕食%d只；更早的变化与离开后的去向仍不清楚。" % [counts.get("seen_alive", 0), counts.get("player_killed", 0), counts.get("aging", 0), counts.get("predated", 0)]

func _choose_local_target(object_id: String, require_nest := false) -> Dictionary:
	if _sim == null: return {}
	var origin := _position(object_id)
	var groups := {}
	var totals := {}
	for inst: MonsterInstance in _sim.instances.values():
		if inst.is_alive: totals[inst.species.species_name] = int(totals.get(inst.species.species_name, 0)) + 1
		if not _feasible(inst) or _loaded_actor(inst) == null: continue
		var actual := _actor_position(inst)
		if actual.distance_to(origin) > LOCAL_RADIUS or not _clear_segment(origin, actual): continue
		var key := inst.region_id + "|" + inst.species.species_name
		var bound_key := str(_q().get("optional_bindings", {}).get("region_forest", {}).get("target_key", ""))
		if require_nest and not bound_key.is_empty() and key != bound_key: continue
		if not groups.has(key): groups[key] = {"target_key": key, "region_id": inst.region_id, "species": inst.species.species_name, "unit_ids": [], "tick": _sim.tick_count, "position": [origin.x, origin.y]}
		groups[key]["unit_ids"].append(inst.id)
	for key: String in groups:
		var target: Dictionary = groups[key]
		if int(totals.get(target["species"], 0)) < MIN_GLOBAL_STOCK or target["unit_ids"].size() < 2: continue
		if require_nest:
			if not _sim.nests.get(key, {}).get("active", false) or not _nest_visible(key, origin): continue
			var region: SimRegion = _sim.get_region(target["region_id"])
			var species: SpeciesData = _sim.find_species(target["species"])
			var nest_pos: Vector2 = _sim.camp_pos(region, species)
			if nest_pos.distance_to(origin) > LOCAL_RADIUS or not _clear_segment(origin, nest_pos): continue
			target["position"] = [nest_pos.x, nest_pos.y]
		return target
	return {}

func _saved_target(chain_id: String) -> Dictionary:
	if chain_id == "side_troll":
		return _q().get("optional_targets", {}).get(chain_id, {}).get("target", {}).duplicate(true)
	for stage: Dictionary in Catalog.chain(chain_id).get("steps", []):
		for proof: Dictionary in _q().get("quests", {}).get(stage["id"], {}).get("evidence", {}).values():
			if proof.has("target_key") and not str(proof.get("target_key", "")).is_empty() and proof.has("unit_ids"): return proof
	return {}

func _target_alive(target: Dictionary) -> Array:
	var result: Array = []
	if _sim == null: return result
	var point: Array = target.get("target_position", target.get("position", []))
	if point.size() != 2: return result
	var origin := Vector2(float(point[0]), float(point[1]))
	for id: Variant in target.get("unit_ids", []):
		var inst: MonsterInstance = _sim.instances.get(int(id))
		if inst == null or not inst.is_alive or inst.region_id != target.get("region_id", "") or inst.species.species_name != target.get("species", ""): continue
		var pos := _actor_position(inst)
		if pos.distance_to(origin) <= LOCAL_RADIUS and _clear_segment(origin, pos): result.append(int(id))
	return result

func _verify_ecology(a: Dictionary, proof: Dictionary) -> String:
	var chain_id := str(a.get("chain", ""))
	var branch := _choice(a)
	proof["verified"] = true
	if branch in ["warning", "bypass", "outer", "detour"]:
		proof["outcome"] = "survey"
		proof["reason"] = "现场路线警示与绕行，不记猎杀"
		return ""
	var target := _saved_target(chain_id)
	if target.is_empty():
		# 没有经过事实核查的处理对象，只能由明确的警示/绕行分支结案。
		return "附近没有能确认的处理目标，请选择警示或绕行"
	proof["target_key"] = target.get("target_key", "")
	proof["region_id"] = target.get("region_id", "")
	proof["species"] = target.get("species", "")
	var credit: Dictionary = _q().get("optional_targets", {}).get(chain_id, {})
	var kills: Array = credit.get("kills", [])
	if chain_id == "side_hunter" and not kills.is_empty():
		proof["outcome"] = "hunt"
		proof["unit_ids"] = kills.map(func(event: Dictionary) -> int: return int(event.get("instance_id", -1)))
		proof["events"] = kills.duplicate(true)
		return ""
	if chain_id == "side_hunter" and (_target_alive(target).size() < 2 or (_sim != null and _sim.alive_count_of_species(str(target.get("species", ""))) < MIN_GLOBAL_STOCK)):
		proof["outcome"] = "survey"
		proof["reason"] = "当前实名余量不足以有限处理并保留族群；撤下悬赏，现场调查结案，不新增讨伐功劳"
		proof["unit_ids"] = _target_alive(target)
		return ""
	if chain_id == "region_forest":
		if credit.get("ransack", false):
			proof["outcome"] = "ransack"
			return ""
		var nest: Dictionary = _sim.nests.get(str(target.get("target_key", "")), {}) if _sim != null else {}
		if not nest.get("active", false):
			proof["outcome"] = "survey"
			proof["reason"] = "接取后现场巢穴已不活跃，据实记录变化；没有新增捣巢功劳"
			return ""
	if _target_alive(target).is_empty():
		proof["outcome"] = "survey"
		proof["reason"] = "实名目标已不在当前现场，据实复查结案；不臆断消失原因，不新增玩家猎杀"
		return ""
	return "目标仍在附近；请按选定的数目处理，之后回到这里核对变化"

func _on_instance_died(inst: MonsterInstance, cause: String) -> void:
	if _sim == null or _sim != WorldSim.sim: return
	var position := inst.death_pos if inst.death_pos.is_finite() else _actor_position(inst)
	_death_instances[inst.id] = inst
	_deaths[inst.id] = {"kind": "death", "instance_id": inst.id, "species": inst.species.species_name,
		"from_region": inst.region_id, "to_region": "", "cause": cause, "tick": _sim.tick_count,
		"seed": GameState.world_seed, "position": [position.x, position.y], "source": "EcologySim.instance_died"}
	if _deaths.size() > 256:
		var oldest: Variant = _deaths.keys()[0]
		_death_instances.erase(oldest)
		_deaths.erase(oldest)

func _on_player_kill(id: int, species: String, region: String, pos: Vector2) -> void:
	if _sim == null or _sim != WorldSim.sim or id <= 0 or not _deaths.has(id): return
	var death: Dictionary = _deaths[id]
	var inst: MonsterInstance = _sim.instances.get(id)
	if inst == null or _death_instances.get(id) != inst or inst.is_alive or death.get("cause", "") != "killed" or inst.species.species_name != species or inst.region_id != region or not inst.death_pos.is_finite() or inst.death_pos.distance_to(pos) > 4.0: return
	for chain_id: String in ["side_hunter", "side_troll"]:
		if not _enabled(chain_id) or _paused(chain_id): continue
		var credit_action := chain_id + (":s2:result" if chain_id == "side_hunter" else ":s1:challenge")
		if not _can(_action_map.get(credit_action, {})): continue
		var target := _saved_target(chain_id)
		if id not in target.get("unit_ids", []) or target.get("species", "") != species or target.get("region_id", "") != region: continue
		var original: Array = target.get("target_position", target.get("position", []))
		if original.size() != 2 or pos.distance_to(Vector2(float(original[0]), float(original[1]))) > LOCAL_RADIUS: continue
		if not _q().has("optional_targets"): _q()["optional_targets"] = {}
		var credit: Dictionary = _q()["optional_targets"].get(chain_id, {"kills": []})
		if not credit.get("kills", []).is_empty(): continue # 每单最多一只的有限配额
		# 结算时再次检查余量，不能把最后一只普通活体作为作者任务的猎杀目标。
		if not inst.species.is_boss and (_target_alive(target).is_empty() or _sim.alive_count_of_species(species) + 1 < MIN_GLOBAL_STOCK): continue
		credit["kills"].append(death.duplicate(true))
		_q()["optional_targets"][chain_id] = credit
		_host.call("_save")

func _on_ransack(species: String, region: String, pos: Vector2) -> void:
	if not _enabled("region_forest") or _paused("region_forest") or _sim == null or _sim != WorldSim.sim: return
	if not _can(_action_map.get("region_forest:s2:work", {})): return
	var target := _saved_target("region_forest")
	if target.get("species", "") != species or target.get("region_id", "") != region: return
	var key := str(target.get("target_key", ""))
	var nest: Dictionary = _sim.nests.get(key, {})
	if nest.is_empty() or nest.get("active", true) or int(nest.get("rebuild", 0)) <= 0: return
	var genuine := false
	for node: Node in get_tree().get_nodes_in_group("nests"):
		if node is NestNode and node.nest_key == key and node._destroyed and node.global_position.distance_to(pos) <= 4.0: genuine = true
	if not genuine: return
	if not _q().has("optional_targets"): _q()["optional_targets"] = {}
	_q()["optional_targets"]["region_forest"] = {"kills": [], "ransack": true, "target_key": key, "tick": _sim.tick_count}
	_host.call("_save")

func _local_bosses(species: String, center: Vector2, radius: float) -> Array:
	var ids: Array = []
	if _sim == null: return ids
	for inst: MonsterInstance in _sim.instances.values():
		if inst.is_alive and inst.species.is_boss and inst.species.species_name == species and _actor_position(inst).distance_to(center) <= radius: ids.append(inst.id)
	return ids

func _liquid_boundary(center: Vector2) -> Dictionary:
	var counts := {"lava": 0, "safe": 0}
	for x in range(-8, 9):
		for y in range(-8, 9):
			var point := center + Vector2(x, y) * 32.0
			if ObstacleField.liquid_kind_at(point) == "lava": counts["lava"] += 1
			elif not ObstacleField.blocks(point, 0.0): counts["safe"] += 1
	return counts

func visual_state() -> Dictionary:
	var state := {"open_gates": [], "placements": {}, "services": {}, "taken": {}, "read": {}, "object_states": {}, "object_actions": {}, "rescued": {}, "repaired": {}, "active_runes": []}
	for id: String in _q().get("optional_bindings", {}).get("region_forest", {}).get("positions", {}):
		state["placements"][id] = {"position": _q()["optional_bindings"]["region_forest"]["positions"][id]}
	for a: Dictionary in _actions():
		if not _enabled(str(a.get("chain", ""))) or not _done(a): continue
		var object_id := action_object(a)
		var chain := str(a.get("chain", ""))
		var kind := str(a.get("kind", ""))
		var branch := _choice(a)
		state["object_states"][object_id] = "taken" if kind == "recover" else ("read" if kind == "read" else "completed")
		if kind == "recover": state["taken"][object_id] = true
		if kind == "read": state["read"][object_id] = true
		if kind in ["repair", "deliver", "route"]: state["repaired"][object_id] = true
		if kind == "rescue" or (chain == "side_herbalist" and kind == "deliver" and branch == "patient"): state["rescued"][object_id] = true
		var opens := CampaignQuest.open_gate_for_action(_q(),a)
		if not opens.is_empty() and opens not in state["open_gates"]: state["open_gates"].append(opens)
		if kind == "puzzle": state["active_runes"].append_array(a.get("puzzle_objects", []))
		if a.has("service") and not (chain == "side_herbalist" and branch == "patient"):
			var endpoints: Array = a.get("service_endpoints_by_choice", {}).get(branch, [object_id])
			for endpoint: String in endpoints:
				state["services"][endpoint] = str(a["service"])
				state["placements"][endpoint] = {"service": "补给", "title": "外缘共享补给台" if endpoint == "region_plains:work_outer" else _base_title(endpoint)}
			if chain in ["side_patrol", "side_merchant", "side_watchman"]:
				var resident := chain + ":giver"
				var point := Layout.object_position(object_id) + Vector2(64, 0)
				state["placements"][resident] = {"position": point, "title": _base_title(resident), "service": "驻守"}
				state["services"][resident] = str(a["service"])
		if chain == "side_scholar" and kind == "repair":
			state["placements"]["side_scholar:record"] = {"title": "铭文已补记并保留" if branch == "preserve" else "已拆取机关件的铭文缺口"}
		if chain == "side_watchman" and kind == "repair":
			state["placements"][object_id] = {"title": "新信号旗 · 沿近路回营" if branch == "near" else "新信号旗 · 向外缘高处", "service": "方位线索"}
		if chain == "side_hunter" and kind == "ecology" and branch == "warning": state["repaired"]["side_hunter:warning_sign"] = true
	for aid: String in _q().get("puzzle_progress", {}):
		var a: Dictionary = _action_map.get(aid, {})
		if a.is_empty() or not handles_action(aid) or not _enabled(str(a.get("chain", ""))): continue
		var order: Array = a.get("puzzle_order", [])
		var objects: Array = a.get("puzzle_objects", [])
		for symbol: String in _q()["puzzle_progress"][aid]:
			var index := order.find(symbol)
			if index >= 0 and index < objects.size() and objects[index] not in state["active_runes"]: state["active_runes"].append(objects[index])
	var unlock_memo: Dictionary = {}
	for chain_id: String in _chain_cache:
		if not _enabled(chain_id) or _paused(chain_id): continue
		var stage := _next_stage(chain_id)
		if stage.is_empty() or _q().get("quests", {}).get(stage["id"], {}).get("accepted", false) or not Data._stage_unlocked(_q(), stage, unlock_memo): continue
		var origin := _start_object(stage)
		state["object_states"][origin] = "available"
		state["object_actions"][origin] = "接取委托"
	# 当前动作可复用先前取空的位置；只有这个新动作或真实服务允许继续交互。
	for a: Dictionary in _actions():
		if not _can(a): continue
		var id := action_object(a)
		state["object_states"][id] = "available"
		state["object_actions"][id] = str(a.get("verb", "调查"))
		for rune: String in a.get("puzzle_objects", []):
			state["object_states"][rune] = "available"
			state["object_actions"][rune] = "触碰符记"
	for id: String in state["services"]:
		state["object_states"][id] = "claimed" if Data.service_claimed(_q(), str(state["services"][id])) else "ready"
		state["object_actions"][id] = "驻站服务"
	return state

func _base_title(object_id: String) -> String:
	for definition: Dictionary in Layout.objects():
		if definition.get("id", "") == object_id: return str(definition.get("title", ""))
	return "接应站"

func _challenge(action_id: String) -> String:
	var a: Dictionary = _action_map.get(action_id, {})
	if a.is_empty() or a.get("kind", "") != "boss" or not _can(a) or not _at(action_object(a)): return "请在已接取故事的遗迹现场核对挑战"
	var ids := _local_bosses(str(a.get("boss_species", "巨魔王")), _position(action_object(a)), 2200.0)
	if ids.is_empty(): return "附近没找到可挑战的巨魔王。先去旧房间看看吧，不必在这里等"
	var inst: MonsterInstance = _sim.instances.get(int(ids[0]))
	var pos := _actor_position(inst)
	if not _q().has("optional_targets"): _q()["optional_targets"] = {}
	var previous: Dictionary = _q()["optional_targets"].get("side_troll", {})
	if not previous.get("kills", []).is_empty(): return "这次挑战已有战绩，请在遗迹处确认"
	_q()["optional_targets"]["side_troll"] = {"kills": [], "target": {"target_key": inst.region_id + "|" + inst.species.species_name, "region_id": inst.region_id, "species": inst.species.species_name, "unit_ids": [inst.id], "target_position": [pos.x, pos.y], "tick": _sim.tick_count}}
	_host.call("_save")
	return "已选定附近这只巨魔王。若决定动手，击败它后回来记录；也可以先去调查旧房间。"

func _loaded_actor(inst: MonsterInstance) -> Node2D:
	for actor: Node in get_tree().get_nodes_in_group("monsters"):
		if actor is Node2D and actor.get("inst") == inst and actor.is_visible_in_tree() and not actor.is_queued_for_deletion(): return actor as Node2D
	return null

func _nearby_nests(center: Vector2) -> Array[String]:
	var result: Array[String] = []
	if _sim == null: return result
	for key: String in _sim.nests:
		if not _sim.nests[key].get("active", false): continue
		var region: SimRegion = _sim.get_region(key.get_slice("|", 0))
		var species: SpeciesData = _sim.find_species(key.get_slice("|", 1))
		if region == null or species == null: continue
		var pos := _sim.camp_pos(region, species)
		if pos.distance_to(center) <= 680.0 and _nest_visible(key, center): result.append(key)
	return result

func route_geometry(a: Dictionary) -> Array:
	if a.get("chain", "") == "region_forest" and _choice(a) == "near":
		var bound: Array = _q().get("optional_bindings", {}).get("region_forest", {}).get("near_route", [])
		if not bound.is_empty():
			var path: Array = []
			for point: Array in bound: path.append(Vector2(float(point[0]), float(point[1])))
			return path
	var chain: Dictionary = _chain_cache.get(str(a.get("chain", "")), {})
	var routes: Dictionary = Layout.region_routes(str(chain.get("terrain", "")))
	var output: Array = []
	for point: Vector2 in routes.get(_choice(a), []): output.append(point)
	return output

func _set_route_step(action_id: String, count: int) -> void:
	if not _q().has("optional_route_steps"): _q()["optional_route_steps"] = {}
	_q()["optional_route_steps"][action_id] = count

func claim_service(object_id: String) -> String:
	if _mutating or not _at(object_id): return "请走到驻站补给旁领取"
	var service_id := str(visual_state().get("services", {}).get(object_id, ""))
	var service: Dictionary = _q().get("services", {}).get(service_id, {})
	if service_id.is_empty() or not service.get("enabled", false): return "这里还没有备好补给"
	if service.get("claimed", false) or _q().get("service_receipts", {}).get(service_id, {}).get("claimed", false): return "给你留的这份补给已经领过了"
	var item := str(service.get("stock_item", "onigiri"))
	if item != "onigiri": return "本站物资编号不符合当前服务合同"
	if not Inventory.can_apply({}, {item: 1}): return "当前无法记录补给，尚未领取；请确认存档可写后重试"
	_mutating = true
	GameState.begin_world_reward()
	var prior_service := service.duplicate(true)
	if not _q().has("service_receipts"): _q()["service_receipts"] = {}
	var prior_receipt: Dictionary = _q()["service_receipts"].get(service_id, {}).duplicate(true)
	service["claimed"] = true
	service["status"] = "claimed"
	_q()["service_receipts"][service_id] = {"claimed": true, "status": "claimed"}
	if not Inventory.apply({}, {item: 1}):
		_q()["services"][service_id] = prior_service
		if prior_receipt.is_empty(): _q()["service_receipts"].erase(service_id)
		else: _q()["service_receipts"][service_id] = prior_receipt
		GameState.end_world_reward()
		_mutating = false
		return "库存条件已变化，整份驻站补给仍保留"
	_host.call("_save")
	GameState.end_world_reward()
	_mutating = false
	return "已领取驻站饭团×1"

func _direction(from: Vector2, to: Vector2) -> String:
	var delta := to - from
	if delta.length() < 64: return "附近"
	var directions := ["东", "东南", "南", "西南", "西", "西北", "北", "东北"]
	return directions[posmod(roundi(delta.angle() / (PI / 4.0)), 8)]

func _clear_route_segment(from: Vector2, to: Vector2) -> bool:
	if not _clear_segment(from, to): return false
	var count := maxi(1, ceili(from.distance_to(to) / 12.0))
	for index in range(count + 1):
		if ObstacleField.liquid_kind_at(from.lerp(to, float(index) / count)) == "lava": return false
	return true

func next_target(a: Dictionary) -> Dictionary:
	var guide := _next_target(a)
	if a.get("kind", "") == "puzzle" and not _done(a):
		var progress: Array = _q().get("puzzle_progress", {}).get(a.get("id", ""), [])
		var runes: Array = a.get("puzzle_objects", [])
		if not runes.is_empty():
			var rune := str(runes[mini(progress.size(), runes.size() - 1)])
			guide = {"object_id":rune, "position":_position(rune), "label":_base_title(rune), "step_progress":"符记 %d/%d" % [progress.size(), runes.size()]}
	var id := str(guide.get("object_id", ""))
	var title := _base_title(id) if not id.is_empty() else "实地路线"
	guide["target_title"] = title
	guide["next_action"] = str(guide.get("label", "")) if a.get("kind", "") == "route" else str(a.get("verb", "调查")) + " · " + title
	if a.get("kind", "") == "route":
		var visits: Array = _q().get("optional_routes", {}).get(a.get("id", ""), [])
		guide["step_progress"] = "路线 %d/%d" % [visits.size(), _route_points(a).size()]
	return guide

func _next_target(a: Dictionary) -> Dictionary:
	var id := action_object(a)
	if a.get("kind", "") != "route" or _done(a): return {"object_id": id, "position": _position(id), "label": _title(id)}
	if _q().get("optional_route_reanchor", {}).get(a.get("id", ""), false):
		return {"object_id": "", "position": _route_anchor(a), "label": "返回最后核实点，实走一步接续"}
	var visits: Array = _q().get("optional_routes", {}).get(a.get("id", ""), [])
	var points := _route_points(a)
	if visits.is_empty() and not points.is_empty():
		id = str(points[0])
		return {"object_id": id, "position": _position(id), "label": "回到所选施工点开始验收 · " + _title(id)}
	var geometry := route_geometry(a)
	var step := int(_q().get("optional_route_steps", {}).get(a.get("id", ""), 0))
	if step < geometry.size():
		return {"object_id": "", "position": geometry[step], "label": "沿实地路线到第%d/%d处转折" % [step + 1, geometry.size()]}
	if not _passage_proven(a):
		var passage := _passage(a)
		var approach: Vector2 = passage.center - passage.direction * 96.0
		# Near repairs share a wall with the independent, possibly closed hill gate.
		if passage.kind == "barrier": approach.y -= 32.0
		var player := get_tree().get_first_node_in_group("player") as Node2D
		var at_start := player != null and player.global_position.distance_to(approach) <= 48.0
		return {"object_id":"","position":approach + passage.direction * 192.0 if at_start else approach,"label":"穿过新修开的缺口或机关门"}
	return {"object_id": id, "position": _position(id), "label": "抵达接应站并确认验收"}

func _segment_near(from: Vector2, to: Vector2, point: Vector2, radius: float) -> bool:
	if not point.is_finite() or not to.is_finite(): return false
	var closest := Geometry2D.get_closest_point_to_segment(point, from, to) if from.is_finite() else to
	return closest.distance_to(point) <= radius


## NPC 的历史位置线索只绑定已有巢址；抵达后仍以当前已加载活体核验。
## 只保存一次作者标识和干燥身体通路，不移动巢穴、不补怪、不以坐标当目击。
func _bind_forest_markers() -> bool:
	if _q().get("optional_bindings", {}).has("region_forest"): return true
	if _sim == null: return false
	var anchor := Layout.object_position("region_forest:station")
	var region_id := str(Layout.sites().get("forest", {}).get("region_id", ""))
	var candidates: Array = []
	for key: String in _sim.nests:
		if key.get_slice("|", 0) != region_id: continue
		var region: SimRegion = _sim.get_region(region_id)
		var species: SpeciesData = _sim.find_species(key.get_slice("|", 1))
		if region == null or species == null or species.is_boss or species.ambient: continue
		var camp := _sim.camp_pos(region, species)
		if camp.distance_to(anchor) > FOREST_SEARCH_RADIUS: continue
		candidates.append({"target_key": key, "camp": camp, "distance": camp.distance_squared_to(anchor)})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.distance < b.distance if a.distance != b.distance else a.target_key < b.target_key)
	for candidate: Dictionary in candidates:
		var camp: Vector2 = candidate.camp
		for turn in 16:
			var direction := (anchor-camp).normalized().rotated(float(turn)*TAU/16.0)
			var work := _grid_center(camp + direction*160.0)
			var survey := _grid_center(camp + direction*288.0)
			var choice := _grid_center(camp + direction*416.0)
			if not _dry_body_segment(camp, choice) or not _dry_body_segment(work, survey) or not _dry_body_segment(survey, choice): continue
			var path := _forest_dry_path(work, anchor)
			if path.is_empty(): continue
			var positions := {}
			for pair: Array in [["region_forest:survey_a",survey],["region_forest:work_near",work],["region_forest:choice",choice]]:
				positions[pair[0]] = [pair[1].x,pair[1].y]
			var serialized: Array = []
			for point: Vector2 in path: serialized.append([point.x,point.y])
			if not _q().has("optional_bindings"): _q()["optional_bindings"] = {}
			_q()["optional_bindings"]["region_forest"] = {"seed":GameState.world_seed,"source":"region_forest:guide","target_key":candidate.target_key,"camp":[camp.x,camp.y],"positions":positions,"near_route":serialized}
			return true
	return false

func _grid_center(point: Vector2) -> Vector2:
	return Vector2(Vector2i(floori(point.x/32.0),floori(point.y/32.0)))*32.0+Vector2(16,16)

func _dry_body_segment(from: Vector2, to: Vector2) -> bool:
	if not from.is_finite() or not to.is_finite(): return false
	var count := maxi(1,ceili(from.distance_to(to)/12.0))
	for index in range(count+1):
		var point := from.lerp(to,float(index)/count)
		if ObstacleField.blocks(point,12.0) or ObstacleField.nav_blocked_at(point) or ObstacleField.liquid_kind_at(point) != "": return false
	return true

func _forest_dry_path(from: Vector2, to: Vector2) -> Array[Vector2]:
	var first := Vector2i(floori(from.x/32.0),floori(from.y/32.0))
	var last := Vector2i(floori(to.x/32.0),floori(to.y/32.0))
	var low := Vector2i(mini(first.x,last.x)-16,mini(first.y,last.y)-16)
	var high := Vector2i(maxi(first.x,last.x)+16,maxi(first.y,last.y)+16)
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(low,high-low+Vector2i.ONE)
	grid.cell_size = Vector2(32,32)
	grid.offset = Vector2(16,16)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	grid.update()
	for x in range(low.x,high.x+1):
		for y in range(low.y,high.y+1):
			var cell := Vector2i(x,y)
			var point := Vector2(cell)*32.0+Vector2(16,16)
			grid.set_point_solid(cell,ObstacleField.blocks(point,12.0) or ObstacleField.nav_blocked_at(point) or ObstacleField.liquid_kind_at(point)!="")
	var raw := grid.get_point_path(first,last)
	if raw.is_empty(): return []
	var result: Array[Vector2] = [from]
	var index := 0
	while index < raw.size()-1:
		var next := index+1
		if not _dry_body_segment(raw[index],raw[next]): return []
		while next+1 < raw.size() and _dry_body_segment(raw[index],raw[next+1]): next += 1
		result.append(raw[next])
		index = next
	if result[-1].distance_to(to)>0.1:
		if not _dry_body_segment(result[-1],to): return []
		result.append(to)
	return result if result.size()<=128 else []


func _nest_visible(key: String, origin: Vector2) -> bool:
	for node: Node in get_tree().get_nodes_in_group("nests"):
		if node is NestNode and node.nest_key==key and not node._destroyed and node.is_visible_in_tree() and not node.is_queued_for_deletion():
			return node.global_position.distance_to(origin)<=680.0 and _clear_segment(origin,node.global_position)
	return false
