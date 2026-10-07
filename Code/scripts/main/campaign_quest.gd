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
var _tracked_target_id := ""

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
	EventBus.quest_list_changed.connect(_on_quest_targets_changed)
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


func _on_quest_targets_changed(quests: Array, tracked_id: String) -> void:
	# 复用管理器已经生成的快照；世界表现刷新不能再次计算所有任务/动态现场。
	_tracked_target_id = ""
	for quest: Dictionary in quests:
		if quest.get("id", "") == tracked_id and quest.get("kind", "") == "campaign":
			_tracked_target_id = str(quest.get("target_object_id", ""))
			return

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
	var first: Dictionary = chapter["steps"][0]["actions"][0]
	return "已接下《%s》 · %s" % [chapter["title"], _action_guidance(first, _object_title(str(first["object"])))]

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
		return _action_payload("路书还留在这里。上回没走完的路，要接着走吗？", "继续远征", "campaign|resume|" + str(object_chapter["id"]), object_id, {"rules":"已取得的证据、已完成的机关和已领取的奖励保留。"})
	for a: Dictionary in _actions.values():
		if a.get("kind", "") != "puzzle" or not object_id in a.get("puzzle_objects", []): continue
		if _proof_exists(a["id"]): return _info("符标已经稳稳亮起，通路仍然敞开。")
		if _paused(str(a["chain"])) or not Data.can_record(ledger(), a["stage"], a["id"]): return _info("符标上只剩半截刻痕，得先找到说明它们次序的记录。")
		return _action_payload("符标在指尖泛起微光。照着找到的刻痕，试一试它的位置。", "触碰符标", "campaign|rune|" + object_id, object_id, {"questions":a.get("questions",[]),"rules":"错误次序只清除当前未完成的序列；已经取得的证据保留。"})
	var available := _available_object_actions(object_id)
	if not available.is_empty():
		var a: Dictionary = available[0]
		if _main != null:
			var special: Dictionary = _main.payload(a)
			if not special.is_empty(): return QuestPresentation.with_narrative(special, a)
		if a["kind"] == "puzzle": return QuestPresentation.with_narrative(_info(QuestPresentation.action_prompt(a) + "\n刻痕次序：" + _order_text(a)), a)
		return _action_payload(QuestPresentation.action_prompt(a), str(a["verb"]), "campaign|act|" + str(a["id"]), object_id, a)
	for stage_id: String in ledger().get("quests", {}):
		if not _stage_cache.has(stage_id) or not Data.ready(ledger(), stage_id) or Data.paid(ledger(), stage_id): continue
		var finish: Dictionary = _stage_cache[stage_id]["actions"][-1]
		if str(finish["object"]) == object_id:
			return _action_payload("约好的报酬已经备好，带上它再动身吧。", "领取整笔奖励", "campaign|claim|" + stage_id, object_id, {"rules":"每段奖励仅领取一次；背包放不下的补给存入待领取。"})
	if object_id == "c6:ending_council" and Data.effective_ending(ledger()) == Data.REUNION: return epilogue_payload()
	if object_id in _station_origins(): return departure_payload(object_id, _object_title(object_id))
	for a: Dictionary in _actions.values():
		if str(a["object"]) == object_id and _proof_exists(str(a["id"])):
			return QuestPresentation.with_narrative(_info(str(a["text"])), {"rules":"这项行动已完成，不会再次发奖。"})
	var chapter := _chapter_for_object(object_id)
	if not chapter.is_empty() and _chapter_available(chapter) and not ledger().get("quests", {}).has(str(chapter["id"]) + ":s1"):
		return _info("营地巡守保管着这一段的路书，先去听听他的消息。")
	return _info("这里还留着远征队的痕迹。沿眼前的线索走，也许能找到他们留下的话。")

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
	return "奖励已领取，收据已保存" if paid else "已领取，或当前无法结算；未领取的奖励仍保留"

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
	var action_text := ""
	var step_progress := ""
	if next["kind"] == "puzzle" and not ready:
		step_progress = "%s %d/%d" % ["符标" if not next.get("puzzle_objects", []).is_empty() else "排列", ledger().get("puzzle_progress", {}).get(next["id"], []).size(), next.get("puzzle_order", []).size()]
	if next["kind"] == "route" and str(next.get("chapter","")) == "watch_c3_swamp" and not ready:
		var route := str(ledger().get("quests",{}).get(stage_id,{}).get("choice",""))
		var points: Array = CampaignLayout.route_waypoints(route)
		var route_state: Dictionary = ledger().get("main_routes",{}).get(next["id"],{})
		var cursor: int = route_state.get("visited",[]).size()
		if route_state.get("needs_anchor",false): cursor=maxi(0,cursor-1)
		if cursor < points.size():
			pos = points[cursor]
			target_title = ("返回已确认的" if route_state.get("needs_anchor",false) else "") + ("浅滩近路" if route=="near" else "枯木外缘") + "路标 %d/%d"%[cursor+1,points.size()]
			action_text = ("返回" if route_state.get("needs_anchor",false) else "前往") + ("浅滩" if route == "near" else "枯木") + "路标%d" % [cursor + 1]
			step_progress = "路标 %d/%d" % [route_state.get("visited", []).size(), points.size()]
	if _optional != null and _optional.handles_action(str(next["id"])) and not ready:
		var navigation: Dictionary = _optional.next_target(next)
		if not navigation.is_empty():
			object_id=str(navigation.get("object_id",object_id))
			pos=navigation.get("position",pos)
			target_title=str(navigation.get("label",target_title))
			action_text=str(navigation.get("next_action", ""))
			step_progress=str(navigation.get("step_progress",step_progress))
			target_title=str(navigation.get("target_title",target_title))
	if _dynamic != null and _dynamic.handles_action(str(next["id"])) and not ready:
		var navigation: Dictionary = _dynamic.next_target(next)
		if not navigation.is_empty():
			object_id=str(navigation.get("object_id",object_id))
			pos=navigation.get("position",pos)
			target_title=str(navigation.get("label",target_title))
			action_text=str(navigation.get("next_action", ""))
			step_progress=str(navigation.get("step_progress",step_progress))
			target_title=str(navigation.get("target_title",target_title))
	var progress_count := 0
	for id: String in stage["required"]:
		if _proof_exists(id): progress_count += 1
	var reward := Data.reward(ledger(), stage_id)
	if action_text.is_empty():
		action_text = _action_guidance(next, target_title)
	if ready:
		action_text = "到%s领取奖励" % _object_title(object_id)
	if step_progress.is_empty():
		step_progress = "%d/%d" % [progress_count, stage["required"].size()]
	return {"id": stage_id, "kind": "campaign", "title": str(stage["title"]), "giver": _object_title(object_id),
		"next_action":action_text,"target_title":target_title,"step_progress":step_progress,
		"need": stage["required"].size(), "progress": progress_count, "claim_at_npc": true,
		"chapter_stage": "claim" if ready else "act", "ui_state": "claimable" if ready else "in_progress",
		"ui_status": "奖励待领取" if ready else "远征记录", "ui_objective": ("到%s领取奖励，溢出补给存待领取" % _object_title(object_id)) if ready else (str(next["verb"]) + " · " + target_title),
		"ui_reward": "+%d金币 +%d经验%s；每段一次，接章时冻结基础预算" % [reward.get("gold",0), reward.get("xp",0), " +"+ItemCatalog.name_of(str(reward["bonus"])) if not str(reward.get("bonus", "")).is_empty() else ""],
		"gold":reward.get("gold",0),"xp":reward.get("xp",0),"bonus":reward.get("bonus",""),
		"target_object_id":object_id,"target_name":target_title,"target_pos":[pos.x,pos.y] if pos.is_finite() else [],"ui_guide_mode":"object","ui_knowledge":"npc_intel", "history":_earned_history(stage), "rules":str(next.get("rules", ""))}


static func _action_guidance(action: Dictionary, target: String) -> String:
	match str(action.get("kind", "")):
		"talk": return "与%s交谈" % target
		"read": return "阅读%s" % target
		"recover": return "取回%s" % target
		"rescue": return "救助%s" % target
		"repair": return "%s · %s" % [action.get("verb", "修复"), target]
		"puzzle": return ("触碰%s" if not action.get("puzzle_objects", []).is_empty() else "到%s排列记录") % target
		"route": return "前往%s" % target
		"choice": return "到%s选择方案" % target
		"obstacle": return "清除%s" % target
		_: return "%s · %s" % [action.get("verb", "调查"), target]

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
	var state := {"enabled_batch":ENABLED_BATCH,"open_gates":open_gates_from(ledger()),"evidence":{},"rescued":{},"repaired":{},"taken":{},"read":{},"object_states":{},"object_actions":{},"placements":{},"services":{},"active_runes":[]}
	for a: Dictionary in _actions.values():
		# 非主线的分支物件只能由专属运行层投影，不能把目录默认目标也冒记为已修复。
		if str(a.get("chapter", "")).is_empty(): continue
		if not _proof_exists(a["id"]):
			if not _paused(str(a["chain"])) and Data.can_record(ledger(), str(a["stage"]), str(a["id"])):
				state["object_states"][a["object"]] = "available"
				state["object_actions"][a["object"]] = a["verb"]
				for rune: String in a.get("puzzle_objects", []):
					state["object_states"][rune] = "available"
					state["object_actions"][rune] = "触碰符标"
			continue
		state["evidence"][a["id"]] = true
		if not state["object_states"].has(a["object"]): state["object_states"][a["object"]] = "completed"
		if a["kind"] == "rescue": state["rescued"][a["object"]] = true
		if a["kind"] == "repair": state["repaired"][a["object"]] = true
		if a["kind"] == "recover": state["taken"][a["object"]] = true
		if a["kind"] == "read": state["read"][a["object"]] = true
		if a["kind"] == "puzzle":
			state["active_runes"].append_array(a.get("puzzle_objects", []))
			for rune: String in a.get("puzzle_objects", []): state["object_states"][rune] = "completed"
		if a.has("service"): state["services"][a["service"]] = true
	for stage_id: String in ledger().get("quests", {}):
		if not _stage_cache.has(stage_id) or not Data.ready(ledger(), stage_id): continue
		var last: Dictionary = _stage_cache[stage_id]["actions"][-1]
		if str(last.get("chapter", "")).is_empty(): continue
		if Data.paid(ledger(), stage_id):
			if state["object_states"].get(last["object"], "") != "available": state["object_states"][last["object"]] = "claimed"
			continue
		state["object_states"][last["object"]] = "ready"
		state["object_actions"][last["object"]] = "领取奖励"
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
	state["target_object_id"] = _tracked_target_id
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
	if Data.effective_ending(ledger()) == Data.REUNION:
		options.append({"terrain":"shelter","chapter":"","title":"平原团聚避难所","repaired":true})
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
			"consequence":"沿旧旗上的路标，前往遗迹入口","risk":"旧旗留下已久，遗迹里如今有什么还不清楚"})
	for destination: Dictionary in travel_options():
		options.append({"label":"前往" + str(destination["title"]),"action":"campaign|depart|"+str(destination["terrain"])+"|"+origin_id,"enabled":true,
			"consequence":"接下这段远征，沿路书前往接应入口","risk":"建议Lv6或等效构筑并备足补给；龟王若仍在，须迎战" if destination["terrain"]=="lava" else "路书年代已久，前方是否安全还需当面查看"})
	if origin_id != "home:patrol":
		options.append({"label":"返回家园营地","action":"campaign|depart|home|"+origin_id,"enabled":true,"consequence":"沿已修复的远征线路返回","risk":"赶路不会回复生命或精力"})
		if _service_available(origin_id): options.append({"label":"联络站补给","action":"campaign|shop|"+origin_id,"enabled":true,"consequence":"查看联络站的补给与价钱","risk":"购买前仍需确认"})
	if Data.ready(ledger(),"watch_c6_lava:s4"):
		options.append({"label":"阅读结局后记","action":"campaign|epilogue_menu","enabled":true,"utility":true,"consequence":"翻阅这趟远征留下的后记","risk":"只记下已经发生的事"})
	if origin_id == "home:patrol" and OutpostQuestData.valid_legacy(GameState.camp_quest):
		options.append({"label":"原营地调查 / 交付","action":"outpost:legacy","enabled":true,
			"consequence":"翻出此前的营地委托，继续调查或领取报酬","risk":"已经领取的报酬不会重发"})
	if not _chapter_history_options().is_empty():
		options.append({"label":"翻阅已取得的远征记录","action":"campaign|history_menu","enabled":true,"utility":true,"consequence":"按已经走过的章节重读纸页和谈话","risk":"只读，不改变证据与报酬"})
	options.append({"label":"前哨任务 / 原记录","action":"outpost:menu","enabled":true,"consequence":"翻阅前哨留下的记录","risk":"已经领取的报酬不会重发"})
	var opening := "石安守住前哨了。林地阿苇还等着远征队的回信。带上旧路书，去问问。" if origin_id == "home:patrol" else "你带回的路书已经摊开。接下来往哪一站走？"
	if Data.ready(ledger(), "watch_c2_forest:s4") and origin_id == "home:patrol":
		opening = "你从远方带回了新的路标。路书上能走的几段都在这里，准备好了就动身吧。"
	if Data.ready(ledger(),"watch_c6_lava:s4"):
		opening = completed_summary(ledger()) + "\n后记已经收好。想起谁的话，可以再找他坐一会儿。"
		if not _reunion_greeting(origin_id).is_empty(): opening = _reunion_greeting(origin_id)
	var questions: Array = [{"label":"路上有人接应吗？","answer":"路书标着接应处，我们会沿那条路走。只是消息走得比人慢，到了再看看，别把旧信当成平安的保证。"}]
	if Data.effective_ending(ledger()) == Data.REUNION:
		questions = [{"label":"远方的灯还要人守吗？","answer":"低负载回路只自动转发灯码和短讯，补油、排水与除冰仍要人做。队员从平原轮流出发巡检，补给在避难所接待；远站亮灯不表示那里随时有人。"}]
	if origin_id == "home:patrol" and _proof_exists("watch_c5_snow:s3:causality"):
		questions.append({"label":"你认识韩铎吗？","answer":"周照摸了摸旧路书：「从前一起巡过路。后来他领远征队出去，我守家园，石安接前哨。他那道撤守令，你已经从两份日志里查清了；如今能把话带回来，总好过只让彼此猜。」"})
	return {"kind":"camp_choice","giver":giver,"origin":_origin_pos(origin_id),"text":opening,"options":options,
		"questions":questions,
		"rules":"选择路线后仍需确认。生命、精力和冷却不会因赶路重置；世界时刻继续保留。只显示已取得线索的路线，联络站修复后可往返。"}

## 团聚后的每个人仍保留自己的牵挂；这里只呈现回访，不额外模拟巡检时钟。
func _reunion_greeting(origin_id: String) -> String:
	return {
		"c2:liaison":"阿苇把沈渡的回话压在杯下。「这回真送到了。他就在这儿，用不着再隔着沼泽猜。下一趟轮到我巡林灯，回来还能接着听他说。」",
		"c3:survivor":"沈渡挪出一张凳子。「给闻川捎句话，欠着的那顿饭还算数。以前总怕信送不到，这回总算能约个日子了。轮值回来，就到这里坐。」",
		"c4:map_keeper":"罗墨把原图和撤守令并排铺开。「韩铎就在对面，我们一页页核对。哪一处救下了人，哪一处没顾上，都留原件，谁也不往纸外躲。」",
		"c5:leader":"韩铎合上日志。「撤守令是我下的，救下了谁、漏算了什么，我都会把原件摊开交代。往后按班去巡检，不让谁再一个人硬撑。阿苇他们回来时，这里会有人等。」"
	}.get(origin_id, "")


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

## 旧档已完成章节也能重读当前叙事；菜单只列已验证的行动，绝不补记证据或再次结算。
func _chapter_history_options(chapter_id: String = "") -> Array:
	var options: Array = []
	for chapter: Dictionary in Catalog.main_chapters():
		if not chapter_id.is_empty() and str(chapter["id"]) != chapter_id: continue
		var found := false
		for stage: Dictionary in chapter["steps"]:
			for a: Dictionary in stage["actions"]:
				if not _proof_exists(str(a["id"])): continue
				found = true
				if not chapter_id.is_empty():
					options.append({"label":str(stage["title"])+" · "+str(a["verb"]),"action":"campaign|history_action|"+str(a["id"]),"enabled":true,"utility":true})
		if found and chapter_id.is_empty():
			options.append({"label":str(chapter["title"]),"action":"campaign|history_chapter|"+str(chapter["id"]),"enabled":true,"utility":true})
	return options

func _chapter_history_payload(chapter_id: String = "") -> Dictionary:
	var payload := {"kind":"camp_choice","giver":"已取得的远征记录","text":"路书只收着你亲自找到的纸页和已经听过的话。想起哪一段，就翻到哪一页。","options":_chapter_history_options(chapter_id),"rules":"只读回顾；不改动进度、物品、奖励或历史选择。"}
	if not chapter_id.is_empty(): payload["back_action"] = "campaign|history_menu"
	return payload


func action(action_id: String) -> String:
	var parts := action_id.split("|")
	if parts.size() < 2 or parts[0] != "campaign": return perform_action(action_id)
	match str(parts[1]):
		"history_menu":
			EventBus.npc_dialogue.emit(_chapter_history_payload())
		"history_chapter":
			if parts.size()>2: EventBus.npc_dialogue.emit(_chapter_history_payload(str(parts[2])))
		"history_action":
			if parts.size()>2 and _proof_exists(str(parts[2])):
				var archived: Dictionary = _actions[str(parts[2])]
				if not str(archived.get("chapter", "")).is_empty():
					var text := str(archived.get("text", ""))
					if archived["id"] == Data.ENDING_ACTION and Data.effective_ending(ledger()) == Data.REUNION: text = epilogue_pages()[1]
					EventBus.npc_dialogue.emit(QuestPresentation.with_narrative({"kind":"info","giver":archived.get("title", "远征记录"),"text":text,"back_action":"campaign|history_chapter|"+str(archived["chapter"])}, archived))
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
				EventBus.npc_dialogue.emit({"kind":"shop","giver":_object_title(str(parts[2])),"text":"补给已经摆出来了。看看有什么用得上，路上别空着背包。","rules":"价格与家园商店一致，购买前仍需确认。"})
	return ""

func _on_action(action_id: String) -> void:
	if not action_id.begins_with("campaign|"): return
	var known := _story_evidence_ids()
	var result := action(action_id)
	if result.is_empty(): return
	# 只观察正式行动新取得的证据；失败、重复点击、接单和翻页都不会生成结果页。
	# 结局/配置行动可能已经打开下一阅读层，不能在这里覆盖它。
	if not GameState.dialogue_open:
		for id: String in _story_evidence_ids():
			if known.has(id) or not _actions.has(id): continue
			var earned: Dictionary = _actions[id]
			EventBus.npc_dialogue.emit({"kind":"story_result","giver":earned.get("title", "远征记录"),
				"text":result,"confirm_text":"继续"})
			return
	EventBus.hint_requested.emit(result)


func _story_evidence_ids() -> Dictionary:
	var known: Dictionary = {}
	for row: Dictionary in ledger().get("quests", {}).values():
		for id: String in row.get("evidence", {}):
			known[id] = true
	return known

func _on_interaction(object_id: String) -> void:
	EventBus.npc_dialogue.emit(object_payload(object_id))

func _info(text: String) -> Dictionary:
	return {"kind":"info","giver":"远征记录","text":text}

func _action_payload(text: String, verb: String, action_id: String, object_id: String, narrative: Dictionary = {}) -> Dictionary:
	return QuestPresentation.with_narrative({"kind":"camp_action","giver":_object_title(object_id),"text":text,"confirm_text":verb,"action":action_id,"origin":CampaignLayout.object_position(object_id)}, narrative)


func _earned_history(stage: Dictionary) -> String:
	var records: Array[String] = []
	# 当前章的前段即使已领奖，也保留可回读的实得经过；未来步骤不在此处展开。
	var entries: Array = [stage] if stage.get("family", "") == "random" else Catalog.chain(str(stage.get("chain", ""))).get("steps", [stage])
	for entry: Dictionary in entries:
		for action: Dictionary in entry.get("actions", []):
			if _proof_exists(str(action.get("id", ""))):
				records.append(str(action.get("text", "")))
	return "已知经过：\n" + "\n".join(records) if not records.is_empty() else ""

func _object_title(object_id: String) -> String:
	for obj: Dictionary in CampaignLayout.objects():
		if obj["id"] == object_id: return str(obj["title"])
	return "营地巡守周照" if object_id == "home:patrol" else "远征线索"

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
		var detail := "在联络站前往「平原团聚避难所」，探望阿苇、沈渡、罗墨和韩铎；远方信标保持低负载自动转发，由队员轮流巡检"
		if compact: detail = "四人在平原避难所团聚，远方信标自动转发"
		return "《断开的守望》已通关 · 归途团聚\n%s" % detail
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
	if Data.effective_ending(ledger()) != Data.REUNION: return origin_id not in ["side_troll:departure","side_troll:giver"]
	return origin_id in ["ending:shelter","c2:liaison","c3:survivor","c4:map_keeper","c5:leader"]


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
	if Data.effective_ending(ledger()) != Data.REUNION: return "团聚名册还没有传回各站"
	var lines: Array[String] = ["《断开的守望》· 此后的道路", "沿途留下的纸页终于接在一起：远征队先分队，人手顾不过来，韩铎才下令撤守。设备随后失灵，留下的人听不到彼此。世界之心重新接通了信标，却没有抹去各人走过的路。"]
	var historical_choice := str(ledger().get("quests",{}).get("watch_c6_lava:s4",{}).get("choice",""))
	var earlier_arrangement := "最初分散守站的安排仍记在旧名册上。后来，四人商定回营轮值。" if historical_choice == "distributed" else ("旧名册保留了集中安置的安排，四人又约好了后续轮值。" if historical_choice == "centralized" else "")
	lines.append(earlier_arrangement + "阿苇、沈渡、罗墨和韩铎在平原避难所团聚，四人都在这里接待来访与补给。远方信标保持亮着，以低负载自动转发消息；他们约好轮流出发巡检，不再各自留守。想去探望，可在联络站选择「平原团聚避难所」。")
	for chapter: String in ["watch_c4_hill","watch_c6_lava"]:
		var stage := chapter+(":s3" if chapter=="watch_c4_hill" else ":s2")
		var outcome := str(ledger().get("quests",{}).get(stage,{}).get("evidence",{}).get(stage+":passage",{}).get("outcome",""))
		var species := "牛头王" if chapter=="watch_c4_hill" else "熔岩龟王"
		var record := "封关档案" if chapter=="watch_c4_hill" else "中枢留存记录"
		lines.append(("丘陵城塞：" if chapter=="watch_c4_hill" else "熔岩城塞：")+str({"defeated":"你击败了%s，带出了%s。" % [species,record],"absent":"你核对城塞时，没有发现%s。你查过空城，带出了%s。" % [species,record],"bypass":"你转动西侧绕行绞盘，从侧路取出了封关档案。"}.get(outcome,"你把沿途查明的经过带了回来。")))
	var sides := 0
	var regions := 0
	for chain: Dictionary in Catalog.side_chains():
		if Data.ready(ledger(),str(chain["id"])+":s2"): sides+=1
	for chain: Dictionary in Catalog.regional_arcs():
		if Data.ready(ledger(),str(chain["id"])+":s3"): regions+=1
	var swamp_route := str(ledger().get("quests",{}).get("watch_c3_swamp:s3",{}).get("choice",""))
	var route_memory := "沼泽的浅滩石障被你打开，沈渡记得那条亲自走通的近路。" if swamp_route=="near" else "你沿沼泽西侧外缘接应沈渡，他记得那两个绕过危险的转折。"
	lines.append("除此之外，%d份托付有了回应，%d处区域的通路或接应点完成了修整。%s那些未曾走近的人和地方，还留着各自的故事。"%[sides,regions,route_memory])
	lines.append("石安仍守在最初的前哨路旁。旧检查点照常可用，你也仍能返回家园。路上的生灵继续来去，往后每一次出发，都还值得先看一眼脚下。")
	return "\n".join(lines)


func epilogue_pages() -> Array[String]:
	var lines := epilogue().split("\n")
	if lines.size()<7: return [epilogue()]
	return [str(lines[1]),str(lines[2]),str(lines[3])+"\n"+str(lines[4]),str(lines[5])+"\n"+str(lines[6])]

func epilogue_payload() -> Dictionary:
	var options: Array = []
	var titles := ["失联的来由","他们在哪里","穿过两座城塞","留下的路"]
	for i in titles.size():
		options.append({"label":titles[i],"action":"campaign|epilogue|"+str(i),"enabled":true,"utility":true,"consequence":"回看这段经过","risk":""})
	return {"kind":"camp_choice","giver":"《断开的守望》· 后记","text":completed_summary(ledger()),"options":options,
		"rules":"后记按已经完成的行动回顾。阅读不会改变团聚驻地、进度或奖励；城塞首领今后复生，也不会撤销既有救援、修复与支付收据。世界之心只恢复联络，不改变野外种群。"}


func _troll_departure_menu(story: Dictionary) -> Dictionary:
	var options: Array = story.get("options",[]).duplicate(true)
	if story.get("kind","")=="camp_action" and story.has("action"):
		options.append({"label":story.get("confirm_text","继续遗迹故事"),"action":story["action"],"enabled":true,
			"consequence":"继续听他说下去，办完眼前的事","risk":"确认后才继续这段委托"})
	options.append({"label":"返回林地联络站","action":"campaign|depart|forest|side_troll:giver","enabled":true,
		"consequence":"沿已经走通的远征线路返回","risk":"赶路不会回复生命或精力"})
	options.append({"label":"返回家园营地","action":"campaign|depart|home|side_troll:giver","enabled":true,
		"consequence":"明确选择返回家园","risk":"赶路不会回复生命或精力"})
	return QuestPresentation.with_narrative({"kind":"camp_choice","giver":story.get("giver","遗迹守望者"),"text":QuestPresentation.action_prompt(story),"origin":_world_position("side_troll:giver"),"options":options}, story)


## 出发交谈核验实际营地巡守，不能用原始摆放坐标替代已经避障/移动的居民。
func _home_patrol() -> Node2D:
	for node: Node in get_tree().get_nodes_in_group("npcs"):
		if node is Node2D and node.get("landmark_id")=="camp_ecology" and node.get("quest_kind")=="outpost":
			return node as Node2D
	return null
