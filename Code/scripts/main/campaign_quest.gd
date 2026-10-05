## 《断开的守望》运行层：现场交互、证据、支付和远征线路均经稳定 ID 核验。
## 不生成怪物、不修改生态状态、不复用新闻播报作为事实。
class_name CampaignQuest
extends Node

signal changed
const Data := preload("res://scripts/main/campaign_quest_data.gd")
const Catalog := preload("res://scripts/main/campaign_catalog.gd")
const Inventory := preload("res://scripts/main/camp_quest_inventory.gd")
const ENABLED_BATCH := 4
var _optional: CampaignOptional
var _dynamic: CampaignDynamic
var _main: CampaignMain
var _mutating := false
var _actions: Dictionary = {}
var _stage_cache: Dictionary = {}

func _ready() -> void:
	name = "CampaignQuest"
	add_to_group("campaign_quest")
	_actions = Catalog.actions(GameState.world_seed)
	for stage: Dictionary in Catalog.all_stages(GameState.world_seed): _stage_cache[stage["id"]] = stage
	if GameState.campaign_quest.is_empty(): GameState.campaign_quest = Data.create(GameState.world_seed)
	Data.authorize_chapter1(ledger(), GameState.outpost_quest)
	EventBus.campaign_interaction_requested.connect(_on_interaction)
	EventBus.camp_quest_action_requested.connect(_on_action)
	EventBus.campaign_travel_completed.connect(_on_travel_completed)
	EventBus.outpost_state_changed.connect(_on_outpost_changed)
	_main = preload("res://scripts/main/campaign_main.gd").new()
	_main.setup(self)
	add_child(_main)
	_optional = preload("res://scripts/main/campaign_optional.gd").new()
	_optional.setup(self)
	add_child(_optional)
	_dynamic = preload("res://scripts/main/campaign_dynamic.gd").new()
	_dynamic.setup(self)
	add_child(_dynamic)
	_dynamic.configure_after_restore.call_deferred()
	_publish()

func ledger() -> Dictionary:
	return GameState.campaign_quest

func owns(stage_id: String) -> bool:
	return _stage_cache.has(stage_id) and ledger().get("quests", {}).has(stage_id)

func has_first_clue() -> bool:
	Data.authorize_chapter1(ledger(), GameState.outpost_quest)
	return Data.chapter1_complete(ledger())

func _on_outpost_changed(_state: Dictionary) -> void:
	if Data.authorize_chapter1(ledger(), GameState.outpost_quest): _save()

func _chapter_enabled(chapter: Dictionary) -> bool:
	return not chapter.is_empty() and int(chapter.get("batch", 99)) <= ENABLED_BATCH

func _chapter_available(chapter: Dictionary) -> bool:
	if not _chapter_enabled(chapter) or not has_first_clue(): return false
	var number := int(chapter.get("number", 0))
	if number == 2: return true
	for prior: Dictionary in Catalog.main_chapters():
		if int(prior["number"]) == number - 1:
			return Data.ready(ledger(), str(prior["id"]) + ":s4")
	return false

func accept_chapter(chapter_id: String) -> String:
	var chapter := Catalog.chapter(chapter_id)
	if not _chapter_available(chapter): return "还没有取得这段远征的路线线索"
	if _departure_origin().is_empty() and not _at_chapter_npc(chapter_id): return "请在营地巡守或本章联络员身旁确认接取"
	if chapter_id in ledger().get("paused_chains", []):
		ledger()["paused_chains"].erase(chapter_id)
		_save()
	if not Data.accept_chapter(ledger(), chapter_id, GameState.stats.level):
		return "这一章的证据和奖励约定已保留，可继续当前进度"
	GameState.tracked_quest_id = str(chapter["steps"][0]["id"])
	_save()
	return "已接取《%s》：%s" % [chapter["title"], chapter["steps"][0]["objective"]]

func abandon(stage_id: String) -> String:
	if not owns(stage_id): return ""
	var chain := str(_stage_cache[stage_id]["chain"])
	if not ledger().has("paused_chains"): ledger()["paused_chains"] = []
	if not chain in ledger()["paused_chains"]: ledger()["paused_chains"].append(chain)
	_save()
	return "已暂停此章；实物、救援、机关与奖励收据全部保留"

func _proof_exists(action_id: String) -> bool:
	var a: Dictionary = _actions.get(action_id, {})
	return not a.is_empty() and ledger().get("quests", {}).get(a["stage"], {}).get("evidence", {}).has(action_id)

func _next_action(stage_id: String) -> Dictionary:
	var stage: Dictionary = _stage_cache.get(stage_id, {})
	for a: Dictionary in stage.get("actions", []):
		if not a.get("optional", false) and not _proof_exists(str(a["id"])):
			return a
	return {}

func _available_object_actions(object_id: String) -> Array:
	var out: Array = []
	for a: Dictionary in _actions.values():
		if str(a["object"]) != object_id or _paused(str(a["chain"])): continue
		if _proof_exists(str(a["id"])): continue
		if Data.can_record(ledger(), str(a["stage"]), str(a["id"])): out.append(a)
	return out

func object_payload(object_id: String) -> Dictionary:
	if object_id=="side_troll:departure" and ENABLED_BATCH>=3: return departure_payload(object_id,_object_title(object_id))
	if _optional != null and _optional.handles_object(object_id):
		var payload: Dictionary = _optional.object_payload(object_id)
		return _troll_departure_menu(payload) if object_id=="side_troll:giver" and _at_origin(object_id) else payload
	if _dynamic != null and _dynamic.handles_object(object_id): return _dynamic.object_payload(object_id)
	if not _at_object(object_id): return _info("请走到物件身旁，确认没有墙体遮挡后再交互")
	var object_chapter := _chapter_for_object(object_id)
	if not object_chapter.is_empty() and _paused(str(object_chapter["id"])):
		return _action_payload("此前证据、机关和支付收据都保留，确认继续这一章？", "继续远征", "campaign|resume|" + str(object_chapter["id"]), object_id)
	for a: Dictionary in _actions.values():
		if a.get("kind", "") != "puzzle" or not object_id in a.get("puzzle_objects", []): continue
		if _proof_exists(a["id"]): return _info("这组机关的完成记录已保存，已发生的改变不会重置")
		if _paused(str(a["chain"])) or not Data.can_record(ledger(), a["stage"], a["id"]): return _info("先取得本段操作记录，再逐个操作现场机关")
		return _action_payload("按下这枚符标。错误次序只清除尚未完成的序列；已经取得的证据不会丢失。", "触碰符标", "campaign|rune|" + object_id, object_id)
	var available := _available_object_actions(object_id)
	if not available.is_empty():
		var a: Dictionary = available[0]
		if _main != null:
			var special: Dictionary = _main.payload(a)
			if not special.is_empty(): return special
		if a["kind"] == "puzzle": return _info("请依操作记录逐个触碰现场回路：" + _order_text(a) + "。每一步需要到达对应物件旁确认。")
		return _action_payload(str(a["text"]), str(a["verb"]), "campaign|act|" + str(a["id"]), object_id)
	for stage_id: String in ledger().get("quests", {}):
		if not _stage_cache.has(stage_id) or not Data.ready(ledger(), stage_id) or Data.paid(ledger(), stage_id): continue
		var finish: Dictionary = _stage_cache[stage_id]["actions"][-1]
		if str(finish["object"]) == object_id:
			return _action_payload("现场工作已经完成。整笔奖励保留在此，请为补给留出空间后领取；重复确认不会再次支付。", "领取整笔奖励", "campaign|claim|" + stage_id, object_id)
	if object_id in _station_origins(): return departure_payload(object_id, _object_title(object_id))
	for a: Dictionary in _actions.values():
		if str(a["object"]) == object_id and _proof_exists(str(a["id"])):
			return _info(str(a["text"]) + "\n这项现场行动已经记录，不会再次支付奖励。")
	var chapter := _chapter_for_object(object_id)
	if not chapter.is_empty() and _chapter_available(chapter) and not ledger().get("quests", {}).has(str(chapter["id"]) + ":s1"):
		return _info("请先在营地巡守处确认远征委托，再按线索调查")
	return _info("这里保留着远征队的痕迹。先完成当前线索，记录不会因等待而消失。")

func object_action(object_id: String, choice: String = "") -> String:
	var actions := _available_object_actions(object_id)
	if actions.is_empty(): return "当前没有可以在此提交的行动"
	return perform_action(str(actions[0]["id"]), choice)

func perform_action(action_id: String, choice: String = "") -> String:
	if _optional != null and _optional.handles_action(action_id): return _optional.perform_action(action_id,choice)
	if _dynamic != null and _dynamic.handles_action(action_id): return _dynamic.perform_action(action_id,choice)
	if _mutating: return ""
	var a: Dictionary = _actions.get(action_id, {})
	if a.is_empty(): return "未识别的战役行动"
	if not _at_object(str(a["object"])): return "需要亲自到达目标旁，不能远程提交现场证据"
	if _proof_exists(action_id): return "此项现场行动已记录"
	if _paused(str(a["chain"])) or not Data.can_record(ledger(), str(a["stage"]), action_id): return "先完成当前的线索与前置行动"
	if a["kind"] == "puzzle": return "请依次操作现场符标，不能在记录页直接解开机关"
	var proof := _position_proof(str(a["object"]))
	if _main != null:
		var checked: Dictionary = _main.proof(a,choice)
		if checked.has("error"): return str(checked["error"])
		proof = checked.get("proof",proof)
	if a["kind"] == "choice": proof["choice"] = choice
	_mutating = true
	GameState.begin_world_reward()
	if not Data.record(ledger(), str(a["stage"]), action_id, proof):
		GameState.end_world_reward()
		_mutating = false
		return "现场条件尚未满足，证据没有提交"
	_settle_ready()
	_save()
	GameState.end_world_reward()
	_mutating = false
	if a.get("ending",false) and Data.ready(ledger(),"watch_c6_lava:s4"):
		EventBus.npc_dialogue.emit(epilogue_payload())
	return str(a["text"])

func _rune(object_id: String) -> String:
	if not _at_object(object_id): return "请走到对应符标旁再操作"
	for a: Dictionary in _actions.values():
		var objects: Array = a.get("puzzle_objects", [])
		if str(a.get("chapter", "")).is_empty(): continue
		if not object_id in objects: continue
		if _proof_exists(a["id"]): return "这组机关已经完成"
		if _paused(str(a["chain"])) or not Data.can_record(ledger(), a["stage"], a["id"]): return "先继续远征并核对现场刻痕的次序"
		if not ledger().has("puzzle_progress"): ledger()["puzzle_progress"] = {}
		var progress: Array = ledger()["puzzle_progress"].get(a["id"], []).duplicate()
		var order: Array = a["puzzle_order"]
		var symbol: String = str(order[objects.find(object_id)])
		if progress.size() >= order.size() or symbol != str(order[progress.size()]):
			ledger()["puzzle_progress"][a["id"]] = []
			_save()
			return "次序不合，符光熄灭。请按" + _order_text(a) + "重新操作，已有记录保留"
		progress.append(symbol)
		ledger()["puzzle_progress"][a["id"]] = progress
		if progress == order:
			var proof := _position_proof(str(a["object"]))
			# 机关完成证据来自最后一枚现场符标，存档同时保留完整顺序。
			proof["position"] = [_player().global_position.x, _player().global_position.y]
			proof["order"] = progress.duplicate()
			Data.record(ledger(), a["stage"], a["id"], proof)
			_settle_ready()
		_save()
		return str(a["text"]) if progress == order else "符标响应（%d/%d），继续前往下一枚" % [progress.size(), order.size()]
	return "这不是当前机关的符标"

func _position_proof(object_id: String) -> Dictionary:
	var pos := _world_position(object_id)
	return {"position": [pos.x, pos.y], "tick": WorldSim.sim.tick_count if WorldSim.sim != null else 0}

func _settle_ready() -> void:
	for stage_id: String in ledger().get("quests", {}):
		if Data.ready(ledger(), stage_id): _pay(stage_id)

func _pay(stage_id: String) -> bool:
	var q: Dictionary = ledger().get("quests", {}).get(stage_id, {})
	if q.is_empty() or q.get("receipt", {}).get("paid", false) or not Data.ready(ledger(), stage_id): return false
	var reward: Dictionary = Data.reward(ledger(), stage_id)
	var bonus := str(reward.get("bonus", ""))
	var items := {bonus: 1} if not bonus.is_empty() else {}
	if not Inventory.can_apply({}, items): return false
	var gold := roundi(int(reward.get("gold", 0)) * GameState.stats.gold_mult())
	var xp := int(int(reward.get("xp", 0)) * GameState.stats.passive_mult("xp", 1.1) * (1.0 + GameState.stats.equip_affix("xp")))
	# 支付收据先于库存广播，世界奖励锁保证同步保存不会落半笔。
	if not Data.mark_paid(ledger(), stage_id, gold, xp): return false
	Inventory.apply({}, items)
	GameState.add_gold(int(reward.get("gold", 0)))
	GameState.add_xp(int(reward.get("xp", 0)))
	return true

func claim(stage_id: String) -> String:
	if _mutating or not owns(stage_id) or not Data.ready(ledger(), stage_id): return "尚未完成这段行动"
	var stage: Dictionary = _stage_cache[stage_id]
	var last: Dictionary = stage["actions"][-1]
	var claim_object := _optional.action_object(last) if _optional != null and _optional.handles_action(str(last["id"])) else str(last["object"])
	if not _at_object(claim_object): return "请到这一段的交付物件或联络员身旁领取"
	_mutating = true
	GameState.begin_world_reward()
	var paid := _pay(stage_id)
	_save()
	GameState.end_world_reward()
	_mutating = false
	return "整笔奖励已领取，收据已保存" if paid else "已领过，或奖励物品达到99上限；未领部分整笔保留"

func snapshots() -> Array:
	var result: Array = []
	for id: String in Data.active_ids(ledger()):
		if _stage_cache.has(id) and not _paused(str(_stage_cache[id]["chain"])): result.append(snapshot(id))
	return result

func snapshot(stage_id: String) -> Dictionary:
	var stage: Dictionary = _stage_cache.get(stage_id, {})
	if stage.is_empty(): return {}
	var next := _next_action(stage_id)
	var ready := Data.ready(ledger(), stage_id)
	if next.is_empty(): next = stage["actions"][-1]
	var object_id := str(next["object"])
	if _optional != null and _optional.handles_action(str(next["id"])): object_id=_optional.action_object(next)
	if next["kind"] == "puzzle" and not ready:
		var progress: Array = ledger().get("puzzle_progress", {}).get(next["id"], [])
		var objects: Array = next.get("puzzle_objects", [])
		if not objects.is_empty(): object_id = objects[mini(progress.size(), objects.size()-1)]
	var pos := _world_position(object_id)
	var target_title := _object_title(object_id)
	if next["kind"] == "route" and str(next.get("chapter","")) == "watch_c3_swamp" and not ready:
		var route := str(ledger().get("quests",{}).get(stage_id,{}).get("choice",""))
		var points: Array = CampaignLayout.route_waypoints(route)
		var route_state: Dictionary = ledger().get("main_routes",{}).get(next["id"],{})
		var cursor: int = route_state.get("visited",[]).size()
		if route_state.get("needs_anchor",false): cursor=maxi(0,cursor-1)
		if cursor < points.size():
			pos = points[cursor]
			target_title = ("返回已确认的" if route_state.get("needs_anchor",false) else "") + ("浅滩近路" if route=="near" else "枯木外缘") + "路标 %d/%d"%[cursor+1,points.size()]
	if _optional != null and _optional.handles_action(str(next["id"])) and not ready:
		var navigation: Dictionary = _optional.next_target(next)
		if not navigation.is_empty():
			object_id=str(navigation.get("object_id",object_id))
			pos=navigation.get("position",pos)
			target_title=str(navigation.get("label",target_title))
	if _dynamic != null and _dynamic.handles_action(str(next["id"])) and not ready:
		var navigation: Dictionary = _dynamic.next_target(next)
		if not navigation.is_empty():
			object_id=str(navigation.get("object_id",object_id))
			pos=navigation.get("position",pos)
			target_title=str(navigation.get("label",target_title))
	var progress_count := 0
	for id: String in stage["required"]:
		if _proof_exists(id): progress_count += 1
	var reward := Data.reward(ledger(), stage_id)
	return {"id": stage_id, "kind": "campaign", "title": str(stage["title"]), "giver": _object_title(object_id),
		"need": stage["required"].size(), "progress": progress_count, "claim_at_npc": true,
		"chapter_stage": "claim" if ready else "act", "ui_state": "claimable" if ready else "in_progress",
		"ui_status": "奖励待领取" if ready else "远征记录", "ui_objective": ("腾出补给空间后，到%s领取整笔奖励" % _object_title(object_id)) if ready else (str(next["verb"]) + " · " + target_title),
		"ui_reward": "+%d金币 +%d经验%s；每段一次，接章时冻结基础预算" % [reward.get("gold",0), reward.get("xp",0), " +"+ItemCatalog.name_of(str(reward["bonus"])) if not str(reward.get("bonus", "")).is_empty() else ""],
		"gold":reward.get("gold",0),"xp":reward.get("xp",0),"bonus":reward.get("bonus",""),
		"target_object_id":object_id,"target_name":target_title,"target_pos":[pos.x,pos.y] if pos.is_finite() else [],"ui_guide_mode":"object","ui_knowledge":"npc_intel", "history":str(stage["objective"])}

static func open_gates_from(q: Dictionary) -> Array[String]:
	var result: Array[String] = []
	if q.get("quests", {}).get("watch_c2_forest:s2", {}).get("evidence", {}).has("watch_c2_forest:s2:runes"):
		result.append("c2:forest_gate")
	if q.get("quests",{}).get("watch_c4_hill:s2",{}).get("evidence",{}).has("watch_c4_hill:s2:winch"): result.append("c4:archive_gate")
	if q.get("quests",{}).get("watch_c6_lava:s2",{}).get("evidence",{}).has("watch_c6_lava:s2:passage"): result.append("c6:core_gate")
	# 可选机关也必须在Player.ready前读取同一持久化证据；否则已开的旧房间会被误判封闭。
	var actions:=Catalog.actions(int(q.get("seed",0)))
	for stage_id: String in q.get("quests",{}):
		for action_id: String in q["quests"][stage_id].get("evidence",{}):
			var a: Dictionary=actions.get(action_id,{})
			if a.is_empty() or a.get("stage","")!=stage_id or not str(a.get("chapter","")).is_empty(): continue
			if not a.has("opens") and not a.has("opens_choice"): continue
			if int(Catalog.chain(str(a.get("chain",""))).get("batch",99))>ENABLED_BATCH: continue
			var gate:=open_gate_for_action(q,a)
			if not gate.is_empty() and gate not in result: result.append(gate)
	return result

## 冷启动与运行时视觉共用目录的开门语义；只消费已经验证保存的行动证据和选择。
static func open_gate_for_action(q: Dictionary,a: Dictionary) -> String:
	if not q.get("quests",{}).get(a.get("stage",""),{}).get("evidence",{}).has(a.get("id","")): return ""
	var by_choice: Dictionary=a.get("opens_choice",{})
	return str(by_choice.get(Data.choice(q,a),a.get("opens","")))

func visual_state() -> Dictionary:
	var state := {"enabled_batch":ENABLED_BATCH,"open_gates":open_gates_from(ledger()),"evidence":{},"rescued":{},"repaired":{},"taken":{},"placements":{},"services":{},"active_runes":[]}
	for a: Dictionary in _actions.values():
		# 非主线的分支物件只能由专属运行层投影，不能把目录默认目标也冒记为已修复。
		if str(a.get("chapter", "")).is_empty(): continue
		if not _proof_exists(a["id"]): continue
		state["evidence"][a["id"]] = true
		if a["kind"] == "rescue": state["rescued"][a["object"]] = true
		if a["kind"] == "repair": state["repaired"][a["object"]] = true
		if a["kind"] == "recover": state["taken"][a["object"]] = true
		if a["kind"] == "puzzle": state["active_runes"].append_array(a.get("puzzle_objects", []))
		if a.has("service"): state["services"][a["service"]] = true
	for key: String in ledger().get("puzzle_progress", {}):
		var a: Dictionary = _actions.get(key, {})
		if a.is_empty(): continue
		for symbol: String in ledger()["puzzle_progress"][key]:
			var index: int = a["puzzle_order"].find(symbol)
			if index >= 0 and index < a.get("puzzle_objects", []).size(): state["active_runes"].append(a["puzzle_objects"][index])
	if _main != null:
		var extra: Dictionary = _main.state()
		state["open_gates"].append_array(extra["open_gates"])
		state["rescued"].merge(extra["rescued"],true)
		state["placements"].merge(extra["placements"],true)
		state["ending"] = extra["ending"]
	for helper: Node in [_optional,_dynamic]:
		if helper == null: continue
		var patch: Dictionary = helper.visual_state()
		for key: String in patch:
			if patch[key] is Dictionary:
				if not state.has(key): state[key]={}
				state[key].merge(patch[key],true)
			elif patch[key] is Array:
				if not state.has(key): state[key]=[]
				for value: Variant in patch[key]:
					if not value in state[key]: state[key].append(value)
			else: state[key]=patch[key]
	return state

func _station_origins() -> Array:
	var result: Array = ["home:patrol"]
	for chapter: Dictionary in Catalog.main_chapters():
		if Data.ready(ledger(), str(chapter["id"]) + ":s4"):
			for a: Dictionary in chapter["steps"][3]["actions"]:
				if a["kind"] == "repair": result.append(a["object"])
			if chapter["id"] == "watch_c2_forest": result.append("c2:liaison")
	if ENABLED_BATCH >= 3 and Data.ready(ledger(),"watch_c2_forest:s4"):
		result.append_array(["side_troll:departure","side_troll:giver"])
	if Data.ready(ledger(),"watch_c6_lava:s4"):
		result.append_array(["c3:survivor","c4:map_keeper","c5:leader","ending:shelter"])
	return result

func _departure_origin() -> String:
	for id: String in _station_origins():
		if _at_origin(id): return id
	return ""

func _at_origin(id: String) -> bool:
	if id == "home:patrol":
		var patrol := _home_patrol()
		var player := _player() as Player
		return patrol != null and not patrol.is_queued_for_deletion() and patrol.is_visible_in_tree() and player != null and player.is_visible_in_tree() and not player._is_dead and player.global_position.distance_to(patrol.global_position) < 96.0 and player._attack_has_line_of_sight(patrol.global_position)
	if _dynamic != null and (_dynamic.is_service_origin(id) or _dynamic.is_expedition_origin(id)): return _at_object(id)
	return id in _station_origins() and _at_object(id)

func travel_options() -> Array:
	var options: Array = []
	if Data.ready(ledger(),"watch_c6_lava:s4") and str(ledger()["quests"]["watch_c6_lava:s4"].get("choice",""))=="centralized":
		options.append({"terrain":"shelter","chapter":"","title":"集中安置的避难所","repaired":true})
	for chapter: Dictionary in Catalog.main_chapters():
		if _chapter_available(chapter):
			options.append({"terrain":chapter["terrain"],"chapter":chapter["id"],"title":chapter["title"],"repaired":Data.ready(ledger(),str(chapter["id"])+":s4")})
	return options

func departure_payload(origin_id: String, giver: String = "远征联络员") -> Dictionary:
	if not _at_origin(origin_id): return _info("请到远征联络员身旁确认路线")
	var options: Array = []
	if _dynamic != null: options.append_array(_dynamic.expedition_options(origin_id))
	if origin_id == "side_troll:departure":
		options.append({"label":"沿旧旗线索前往遗迹","action":"campaign|depart|side_troll|"+origin_id,"enabled":true,
			"consequence":"前往实际巨魔王遗迹的安全接近点，不把Boss移到林地联络站","risk":"旧旗是历史路线线索，远方现状仍待亲自核实"})
	for destination: Dictionary in travel_options():
		options.append({"label":"前往" + str(destination["title"]),"action":"campaign|depart|"+str(destination["terrain"])+"|"+origin_id,"enabled":true,
			"consequence":"确认接取本章并前往安全接应入口；当前生命、精力、冷却与生态时刻连续保留","risk":"建议Lv6或等效构筑，先强化并备足补给；活体龟王必须挑战" if destination["terrain"]=="lava" else "旧路书只提供历史位置，到场后才核实真实状态"})
	if origin_id != "home:patrol":
		options.append({"label":"返回家园营地","action":"campaign|depart|home|"+origin_id,"enabled":true,"consequence":"沿已修复的远征线路返回","risk":"不会回复生命或精力"})
		if _service_available(origin_id): options.append({"label":"联络站补给","action":"campaign|shop|"+origin_id,"enabled":true,"consequence":"使用既有商店价格在此购买补给","risk":"仅在这座真实联络站提供服务"})
	if Data.ready(ledger(),"watch_c6_lava:s4"):
		options.append({"label":"阅读结局后记","action":"campaign|epilogue_menu","enabled":true,"utility":true,"consequence":"按当前存档回顾真实结果","risk":"未完成或未发生的事件不会编入结局"})
	if origin_id == "home:patrol" and OutpostQuestData.valid_legacy(GameState.camp_quest):
		options.append({"label":"原营地调查 / 交付","action":"outpost:legacy","enabled":true,
			"consequence":"继续或领取原有营地合同，金额、目标与贡献不变","risk":"旧奖励仍按原条件只支付一次"})
	options.append({"label":"前哨任务 / 原记录","action":"outpost:menu","enabled":true,"consequence":"保留原前哨记录与奖励收据","risk":"不会重新发奖"})
	return {"kind":"camp_choice","giver":giver,"origin":_origin_pos(origin_id),"text":(completed_summary(ledger()) + "\n可以阅读分项后记，或选择已确认的远征线路。") if Data.ready(ledger(),"watch_c6_lava:s4") else "《断开的守望》远征线路\n已获得的旧路线坐标可以引导你前往各章接应点。远方现状需要到场核实，抵达后只揭示附近区域。修复联络站后可往返。", "options":options}

func can_travel(terrain: String, origin_id: String) -> bool:
	if not _at_origin(origin_id): return false
	if terrain.begins_with("worldsite:"): return _dynamic != null and _dynamic.can_travel_site(origin_id,terrain.trim_prefix("worldsite:"))
	if terrain.begins_with("watchnet:"): return _dynamic != null and _dynamic.can_travel_node(origin_id,terrain.trim_prefix("watchnet:"))
	if terrain == "home": return origin_id != "home:patrol"
	if terrain == "side_troll": return ENABLED_BATCH>=3 and origin_id=="side_troll:departure" and Data.ready(ledger(),"watch_c2_forest:s4")
	for option: Dictionary in travel_options():
		if str(option["terrain"]) == terrain: return true
	return false

func request_travel(terrain: String, origin_id: String = "home:patrol") -> String:
	if not can_travel(terrain, origin_id): return "尚未取得这条路线，或尚未修复当前联络站"
	if terrain != "home":
		for chapter: Dictionary in Catalog.main_chapters():
			if chapter["terrain"] == terrain:
				accept_chapter(str(chapter["id"]))
	EventBus.campaign_travel_requested.emit(terrain, origin_id)
	return ""

func _on_travel_completed(terrain: String) -> void:
	if terrain.begins_with("worldsite:") or terrain.begins_with("watchnet:"):
		_save()
		EventBus.hint_requested.emit("已抵达已获线索的安全接近处，请亲自核实现场；生态保持连续")
		return
	if not ledger().has("travel"): ledger()["travel"] = {"visited":[]}
	if not ledger()["travel"].has("visited"): ledger()["travel"]["visited"] = []
	if not terrain in ledger()["travel"]["visited"]: ledger()["travel"]["visited"].append(terrain)
	if not ledger()["travel"].has("arrivals"): ledger()["travel"]["arrivals"] = {}
	var player := _player()
	if player != null: ledger()["travel"]["arrivals"][terrain] = [player.global_position.x,player.global_position.y]
	_save()
	EventBus.hint_requested.emit("已到达远征接应入口；旧记录并不保证前方安全")

func action(action_id: String) -> String:
	var parts := action_id.split("|")
	if parts.size() < 2 or parts[0] != "campaign": return perform_action(action_id)
	match str(parts[1]):
		"epilogue_menu":
			if Data.ready(ledger(),"watch_c6_lava:s4"): EventBus.npc_dialogue.emit(epilogue_payload())
		"epilogue":
			if parts.size()>2 and Data.ready(ledger(),"watch_c6_lava:s4"):
				var pages: Array[String] = epilogue_pages()
				var index := int(parts[2])
				if index>=0 and index<pages.size(): EventBus.npc_dialogue.emit({"kind":"info","giver":"《断开的守望》后记","text":pages[index],"back_action":"campaign|epilogue_menu"})
		"optional": return _optional.action(parts) if _optional!=null else ""
		"dynamic": return _dynamic.action(parts) if _dynamic!=null else ""
		"act": return perform_action(str(parts[2]), str(parts[3]) if parts.size()>3 else "") if parts.size()>2 else ""
		"sequence": return _main.sequence(str(parts[2]),str(parts[3])) if parts.size()>3 and _main!=null else ""
		"claim": return claim(str(parts[2])) if parts.size()>2 else ""
		"resume": return accept_chapter(str(parts[2])) if parts.size()>2 else ""
		"rune": return _rune(str(parts[2])) if parts.size()>2 else ""
		"depart": return request_travel(str(parts[2]),str(parts[3])) if parts.size()>3 else ""
		"shop":
			if parts.size()>2 and _at_origin(str(parts[2])) and str(parts[2]) != "home:patrol" and _service_available(str(parts[2])):
				EventBus.npc_dialogue.emit({"kind":"shop","giver":_object_title(str(parts[2])),"text":"联络站已经恢复补给接待。价格与家园商店一致，购买仍由你确认。"})
	return ""

func _on_action(action_id: String) -> void:
	if not action_id.begins_with("campaign|"): return
	var result := action(action_id)
	if not result.is_empty(): EventBus.hint_requested.emit(result)

func _on_interaction(object_id: String) -> void:
	EventBus.npc_dialogue.emit(object_payload(object_id))

func _info(text: String) -> Dictionary:
	return {"kind":"info","giver":"远征记录","text":text}

func _action_payload(text: String, verb: String, action_id: String, object_id: String) -> Dictionary:
	return {"kind":"camp_action","giver":_object_title(object_id),"text":text,"confirm_text":verb,"action":action_id,"origin":CampaignLayout.object_position(object_id)}

func _object_title(object_id: String) -> String:
	for obj: Dictionary in CampaignLayout.objects():
		if obj["id"] == object_id: return str(obj["title"])
	return "营地巡守" if object_id == "home:patrol" else "远征线索"

func _chapter_for_object(object_id: String) -> Dictionary:
	for a: Dictionary in _actions.values():
		if a["object"] == object_id: return Catalog.chapter(str(a["chapter"]))
	return {}

func _origin_pos(origin_id: String) -> Vector2:
	if origin_id=="home:patrol":
		var patrol := _home_patrol()
		return patrol.global_position if patrol!=null else Vector2.INF
	return _world_position(origin_id)

func _at_object(object_id: String) -> bool:
	for node: Node in get_tree().get_nodes_in_group("campaign_objects"):
		if node is Node2D and str(node.get("campaign_id")) == object_id:
			return node.is_visible_in_tree() and node.has_method("can_interact") and bool(node.call("can_interact"))
	return false

func _player() -> Node2D:
	return get_tree().get_first_node_in_group("player") as Node2D

func _save() -> void:
	GameState._invalidate_world_save_cache()
	GameState._queue_save()
	_publish()

func _publish() -> void:
	EventBus.campaign_state_changed.emit(visual_state())
	changed.emit()


func _paused(chain_id: String) -> bool:
	return chain_id in ledger().get("paused_chains", [])

func _at_chapter_npc(chapter_id: String) -> bool:
	var chapter := Catalog.chapter(chapter_id)
	if chapter.is_empty(): return false
	for obj: Dictionary in CampaignLayout.objects():
		if str(obj.get("terrain", "")) == str(chapter["terrain"]) and str(obj.get("kind", "")) in ["npc", "injured"] and _at_object(str(obj["id"])):
			return true
	return false


static func completed_summary(q: Dictionary, compact := false) -> String:
	var latest: Dictionary = {}
	for chapter: Dictionary in Catalog.main_chapters():
		if Data.chapter_complete(q, str(chapter["id"])): latest = chapter
	if latest.is_empty(): return ""
	if str(latest["id"])=="watch_c6_lava":
		var ending := str(q.get("quests",{}).get("watch_c6_lava:s4",{}).get("choice",""))
		var detail := "在联络站选择前往避难所，探望四位新增居民" if ending=="centralized" else "四位远征队员留守林地、沼泽、丘陵、雪原，继续提供补给"
		if compact: detail = "沿联络站线路探望避难所队员" if ending=="centralized" else "四地驻站提供补给，详见后记"
		return "《断开的守望》已通关 · %s\n%s"%["集中安置" if ending=="centralized" else "分散派驻", detail]
	return "%s · 已完成\n%s" % [str(latest["title"]), "联络站可远征或返回家园" if compact else "联络站已恢复，可在站点确认远征或返回家园"]


func _world_position(object_id: String) -> Vector2:
	for node: Node in get_tree().get_nodes_in_group("campaign_objects"):
		if node is Node2D and str(node.get("campaign_id")) == object_id: return (node as Node2D).global_position
	return CampaignLayout.object_position(object_id)


func _order_text(action_data: Dictionary) -> String:
	var words: Array[String] = []
	for symbol: String in action_data.get("puzzle_order",[]):
		words.append(str({"north":"北","east":"东","west":"西","center":"中","split":"分队","withdrawal":"撤守","lost":"失联"}.get(symbol,symbol)))
	return "→".join(words)


func _service_available(origin_id: String) -> bool:
	if not Data.ready(ledger(),"watch_c6_lava:s4"): return origin_id not in ["side_troll:departure","side_troll:giver"]
	var ending := str(ledger().get("quests",{}).get("watch_c6_lava:s4",{}).get("choice",""))
	if ending == "centralized": return origin_id in ["ending:shelter","c2:liaison","c3:survivor","c4:map_keeper","c5:leader"]
	return origin_id not in ["side_troll:departure","side_troll:giver"]


## 落点按种子目录的稳定次序选择，实时避让当前敌人；绝不挪怪或清空生态。
func travel_destination(terrain: String) -> Vector2:
	if terrain == "home": return WorldConfig.spawn_pos()
	if WorldSim.sim == null: return Vector2.INF
	var positions: Dictionary = {}
	for node: Node in get_tree().get_nodes_in_group("monsters"):
		if node is MonsterBase and (node as MonsterBase).inst != null and (node as MonsterBase).inst.is_alive:
			positions[(node as MonsterBase).inst.id] = (node as Node2D).global_position
	var candidates: Array = CampaignLayout.entry_candidates(terrain)
	if terrain.begins_with("worldsite:") and _dynamic!=null:
		candidates=_dynamic.expedition_candidates(terrain.trim_prefix("worldsite:"))
	elif terrain.begins_with("watchnet:") and _dynamic!=null:
		candidates=[_dynamic.node_destination(terrain.trim_prefix("watchnet:"))]
	for point: Vector2 in candidates:
		if not point.is_finite() or ObstacleField.blocks(point,16.0) or not ObstacleField.liquid_kind_at(point).is_empty(): continue
		var safe := true
		for inst: MonsterInstance in WorldSim.sim.instances.values():
			if not inst.is_alive or inst.species.ambient: continue
			var current: Vector2 = positions.get(inst.id,inst.spawn_pos)
			if current.is_finite() and current.distance_to(point)<700.0:
				safe=false
				break
		if safe: return point
	return Vector2.INF


## 后记只消费此存档实际完成的行动；未发生的生态事件不虚构，也不催促补齐。
func epilogue() -> String:
	if not Data.ready(ledger(),"watch_c6_lava:s4"): return "世界之心的最终派驻尚未确认"
	var ending := str(ledger()["quests"]["watch_c6_lava:s4"].get("choice",""))
	var lines: Array[String] = ["《断开的守望》· 此后的道路", "沿途原件已经核实：先分队，再有意撤守，最后联络失效。世界之心恢复的是通信，没有复活或清空野外族群。"]
	if ending=="centralized":
		lines.append("集中安置：林地联络员、沼泽幸存者、地图保管员和远征队长都迁入平原新增避难所，并在此接待补给。可在这份线路菜单选择「集中安置的避难所」。")
	else:
		lines.append("分散派驻：林地联络员、沼泽幸存者、地图保管员、远征队长分别留守林地、沼泽、丘陵和雪原，四处均可当面补给。")
	for chapter: String in ["watch_c4_hill","watch_c6_lava"]:
		var stage := chapter+(":s3" if chapter=="watch_c4_hill" else ":s2")
		var outcome := str(ledger().get("quests",{}).get(stage,{}).get("evidence",{}).get(stage+":passage",{}).get("outcome",""))
		lines.append(("丘陵城塞：" if chapter=="watch_c4_hill" else "熔岩城塞：")+str({"defeated":"有本人的实名讨伐记录","absent":"如实完成空城调查，没有冒记击杀","bypass":"完成西翼环境绕行，未冒记讨伐"}.get(outcome,"保留已核实记录")))
	var sides := 0
	var regions := 0
	for chain: Dictionary in Catalog.side_chains():
		if Data.ready(ledger(),str(chain["id"])+":s2"): sides+=1
	for chain: Dictionary in Catalog.regional_arcs():
		if Data.ready(ledger(),str(chain["id"])+":s3"): regions+=1
	lines.append("另已收尾%d条人物故事、修复%d处区域工程；没有完成的故事仍留在原处。"%[sides,regions])
	lines.append("旧前哨巡逻员继续守在原处，既有检查点和回城仍保留。生态继续运行，已完成的故事与奖励不会倒退。")
	return "\n".join(lines)


func epilogue_pages() -> Array[String]:
	var lines := epilogue().split("\n")
	if lines.size()<7: return [epilogue()]
	return [str(lines[1]),str(lines[2]),str(lines[3])+"\n"+str(lines[4]),str(lines[5])+"\n"+str(lines[6])]

func epilogue_payload() -> Dictionary:
	var options: Array = []
	var titles := ["远征失联的真相","四位队员的去向","两座城塞的实际经过","留下的改变"]
	for i in titles.size():
		options.append({"label":titles[i],"action":"campaign|epilogue|"+str(i),"enabled":true,"utility":true,"consequence":"读取实际完成记录","risk":"不会改写选择或重新支付"})
	return {"kind":"camp_choice","giver":"《断开的守望》· 后记","text":completed_summary(ledger()),"options":options}


func _troll_departure_menu(story: Dictionary) -> Dictionary:
	var options: Array = story.get("options",[]).duplicate(true)
	if story.get("kind","")=="camp_action" and story.has("action"):
		options.append({"label":story.get("confirm_text","继续遗迹故事"),"action":story["action"],"enabled":true,
			"consequence":"按上方说明继续这处人物故事","risk":"仍需原有现场证据；奖励不会重复支付"})
	options.append({"label":"返回林地联络站","action":"campaign|depart|forest|side_troll:giver","enabled":true,
		"consequence":"沿已经取得的远征线路返回","risk":"生命、精力、冷却与生态仍连续"})
	options.append({"label":"返回家园营地","action":"campaign|depart|home|side_troll:giver","enabled":true,
		"consequence":"明确选择返回家园","risk":"不会回复生命或精力"})
	return {"kind":"camp_choice","giver":story.get("giver","遗迹守望者"),"text":story.get("text","遗迹记录仍保留"),"origin":_world_position("side_troll:giver"),"options":options}


## 出发交谈核验实际营地巡守，不能用原始摆放坐标替代已经避障/移动的居民。
func _home_patrol() -> Node2D:
	for node: Node in get_tree().get_nodes_in_group("npcs"):
		if node is Node2D and node.get("landmark_id")=="camp_ecology" and node.get("quest_kind")=="outpost":
			return node as Node2D
	return null
