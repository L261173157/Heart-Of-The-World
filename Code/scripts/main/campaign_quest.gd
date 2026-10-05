## 《断开的守望》运行层：现场交互、证据、支付和远征线路均经稳定 ID 核验。
## 不生成怪物、不修改生态状态、不复用新闻播报作为事实。
class_name CampaignQuest
extends Node

signal changed
const Data := preload("res://scripts/main/campaign_quest_data.gd")
const Catalog := preload("res://scripts/main/campaign_catalog.gd")
const Inventory := preload("res://scripts/main/camp_quest_inventory.gd")
const ENABLED_BATCH := 1
var _mutating := false
var _actions: Dictionary = {}
var _stage_cache: Dictionary = {}

func _ready() -> void:
	name = "CampaignQuest"
	add_to_group("campaign_quest")
	_actions = Catalog.actions()
	for stage: Dictionary in Catalog.all_stages(): _stage_cache[stage["id"]] = stage
	if GameState.campaign_quest.is_empty(): GameState.campaign_quest = Data.create(GameState.world_seed)
	Data.authorize_chapter1(ledger(), GameState.outpost_quest)
	EventBus.campaign_interaction_requested.connect(_on_interaction)
	EventBus.camp_quest_action_requested.connect(_on_action)
	EventBus.campaign_travel_completed.connect(_on_travel_completed)
	EventBus.outpost_state_changed.connect(_on_outpost_changed)
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
	if not _at_object(object_id): return _info("请走到物件身旁，确认没有墙体遮挡后再交互")
	var object_chapter := _chapter_for_object(object_id)
	if not object_chapter.is_empty() and _paused(str(object_chapter["id"])):
		return _action_payload("此前证据、机关和支付收据都保留，确认继续这一章？", "继续远征", "campaign|resume|" + str(object_chapter["id"]), object_id)
	for a: Dictionary in _actions.values():
		if a.get("kind", "") != "puzzle" or not object_id in a.get("puzzle_objects", []): continue
		if _proof_exists(a["id"]): return _info("符标与石门的开启记录已保存")
		if _paused(str(a["chain"])) or not Data.can_record(ledger(), a["stage"], a["id"]): return _info("先核对路标上的次序，再逐个操作符标")
		return _action_payload("按下这枚符标。错误次序只清除尚未完成的序列；已经取得的证据不会丢失。", "触碰符标", "campaign|rune|" + object_id, object_id)
	var available := _available_object_actions(object_id)
	if not available.is_empty():
		var a: Dictionary = available[0]
		if a["kind"] == "puzzle": return _info("按刻痕提示依次触碰北、东、西三枚符标，再到门后的档案处取回残页")
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
	if _mutating: return ""
	var a: Dictionary = _actions.get(action_id, {})
	if a.is_empty(): return "未识别的战役行动"
	if not _at_object(str(a["object"])): return "需要亲自到达目标旁，不能远程提交现场证据"
	if _proof_exists(action_id): return "此项现场行动已记录"
	if _paused(str(a["chain"])) or not Data.can_record(ledger(), str(a["stage"]), action_id): return "先完成当前的线索与前置行动"
	if a["kind"] == "puzzle": return "请依次操作现场符标，不能在记录页直接解开机关"
	var proof := _position_proof(str(a["object"]))
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
	return str(a["text"])

func _rune(object_id: String) -> String:
	if not _at_object(object_id): return "请走到对应符标旁再操作"
	for a: Dictionary in _actions.values():
		var objects: Array = a.get("puzzle_objects", [])
		if not object_id in objects: continue
		if _proof_exists(a["id"]): return "石门已经打开"
		if _paused(str(a["chain"])) or not Data.can_record(ledger(), a["stage"], a["id"]): return "先继续远征并核对现场刻痕的次序"
		if not ledger().has("puzzle_progress"): ledger()["puzzle_progress"] = {}
		var progress: Array = ledger()["puzzle_progress"].get(a["id"], []).duplicate()
		var order: Array = a["puzzle_order"]
		var symbol: String = str(order[objects.find(object_id)])
		if progress.size() >= order.size() or symbol != str(order[progress.size()]):
			ledger()["puzzle_progress"][a["id"]] = []
			_save()
			return "次序不合，符光熄灭。按北、东、西重新操作，已有记录保留"
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
		return "三枚符标亮起，档案石门已打开。请亲自走进去取回残页" if progress == order else "符标响应（%d/%d），继续前往下一枚" % [progress.size(), order.size()]
	return "这不是当前机关的符标"

func _position_proof(object_id: String) -> Dictionary:
	var pos := CampaignLayout.object_position(object_id)
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
	if not _at_object(str(last["object"])): return "请到这一段的交付物件或联络员身旁领取"
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
	if next["kind"] == "puzzle" and not ready:
		var progress: Array = ledger().get("puzzle_progress", {}).get(next["id"], [])
		var objects: Array = next.get("puzzle_objects", [])
		if not objects.is_empty(): object_id = objects[mini(progress.size(), objects.size()-1)]
	var pos := CampaignLayout.object_position(object_id)
	var progress_count := 0
	for id: String in stage["required"]:
		if _proof_exists(id): progress_count += 1
	var reward := Data.reward(ledger(), stage_id)
	return {"id": stage_id, "kind": "campaign", "title": str(stage["title"]), "giver": _object_title(object_id),
		"need": stage["required"].size(), "progress": progress_count, "claim_at_npc": true,
		"chapter_stage": "claim" if ready else "act", "ui_state": "claimable" if ready else "in_progress",
		"ui_status": "奖励待领取" if ready else "远征记录", "ui_objective": ("腾出补给空间后，到%s领取整笔奖励" % _object_title(object_id)) if ready else (str(next["verb"]) + " · " + _object_title(object_id)),
		"ui_reward": "+%d金币 +%d经验%s；每段一次，接章时冻结基础预算" % [reward.get("gold",0), reward.get("xp",0), " +"+ItemCatalog.name_of(str(reward["bonus"])) if not str(reward.get("bonus", "")).is_empty() else ""],
		"gold":reward.get("gold",0),"xp":reward.get("xp",0),"bonus":reward.get("bonus",""),
		"target_object_id":object_id,"target_name":_object_title(object_id),"target_pos":[pos.x,pos.y] if pos.is_finite() else [],"ui_guide_mode":"object","ui_knowledge":"npc_intel", "history":str(stage["objective"])}

static func open_gates_from(q: Dictionary) -> Array[String]:
	var result: Array[String] = []
	if q.get("quests", {}).get("watch_c2_forest:s2", {}).get("evidence", {}).has("watch_c2_forest:s2:runes"):
		result.append("c2:forest_gate")
	return result

func visual_state() -> Dictionary:
	var state := {"open_gates":open_gates_from(ledger()),"evidence":{},"rescued":{},"repaired":{},"taken":{},"placements":{},"services":{},"active_runes":[]}
	for a: Dictionary in _actions.values():
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
			if index >= 0: state["active_runes"].append(a["puzzle_objects"][index])
	return state

func _station_origins() -> Array:
	var result: Array = ["home:patrol"]
	for chapter: Dictionary in Catalog.main_chapters():
		if Data.ready(ledger(), str(chapter["id"]) + ":s4"):
			for a: Dictionary in chapter["steps"][3]["actions"]:
				if a["kind"] == "repair": result.append(a["object"])
			if chapter["id"] == "watch_c2_forest": result.append("c2:liaison")
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
	return id in _station_origins() and _at_object(id)

func travel_options() -> Array:
	var options: Array = []
	for chapter: Dictionary in Catalog.main_chapters():
		if _chapter_available(chapter):
			options.append({"terrain":chapter["terrain"],"chapter":chapter["id"],"title":chapter["title"],"repaired":Data.ready(ledger(),str(chapter["id"])+":s4")})
	return options

func departure_payload(origin_id: String, giver: String = "远征联络员") -> Dictionary:
	if not _at_origin(origin_id): return _info("请到远征联络员身旁确认路线")
	var options: Array = []
	for destination: Dictionary in travel_options():
		options.append({"label":"前往" + str(destination["title"]),"action":"campaign|depart|"+str(destination["terrain"])+"|"+origin_id,"enabled":true,
			"consequence":"确认接取本章并前往安全接应入口；当前生命、精力、冷却与生态时刻连续保留","risk":"旧路书只提供历史位置，到场后才核实真实状态"})
	if origin_id != "home:patrol":
		options.append({"label":"返回家园营地","action":"campaign|depart|home|"+origin_id,"enabled":true,"consequence":"沿已修复的远征线路返回","risk":"不会回复生命或精力"})
		options.append({"label":"联络站补给","action":"campaign|shop|"+origin_id,"enabled":true,"consequence":"使用既有商店价格在此购买补给","risk":"仅在这座真实联络站提供服务"})
	if origin_id == "home:patrol" and OutpostQuestData.valid_legacy(GameState.camp_quest):
		options.append({"label":"原营地调查 / 交付","action":"outpost:legacy","enabled":true,
			"consequence":"继续或领取原有营地合同，金额、目标与贡献不变","risk":"旧奖励仍按原条件只支付一次"})
	options.append({"label":"前哨任务 / 原记录","action":"outpost:menu","enabled":true,"consequence":"保留原前哨记录与奖励收据","risk":"不会重新发奖"})
	return {"kind":"camp_choice","giver":giver,"origin":_origin_pos(origin_id),"text":"《断开的守望》远征线路\n前哨抄录的林间旧约指向古树联络点。你可以明确选择出发，到达后只揭示脚下附近区域。修复联络站后可往返。", "options":options}

func can_travel(terrain: String, origin_id: String) -> bool:
	if not _at_origin(origin_id): return false
	if terrain == "home": return origin_id != "home:patrol"
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
		"act": return perform_action(str(parts[2]), str(parts[3]) if parts.size()>3 else "") if parts.size()>2 else ""
		"claim": return claim(str(parts[2])) if parts.size()>2 else ""
		"resume": return accept_chapter(str(parts[2])) if parts.size()>2 else ""
		"rune": return _rune(str(parts[2])) if parts.size()>2 else ""
		"depart": return request_travel(str(parts[2]),str(parts[3])) if parts.size()>3 else ""
		"shop":
			if parts.size()>2 and _at_origin(str(parts[2])) and str(parts[2]) != "home:patrol":
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
	return CampaignLayout.object_position(origin_id)

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


static func completed_summary(q: Dictionary) -> String:
	var latest: Dictionary = {}
	for chapter: Dictionary in Catalog.main_chapters():
		if Data.chapter_complete(q, str(chapter["id"])): latest = chapter
	if latest.is_empty(): return ""
	return "%s · 已完成\n联络站已恢复，可在站点确认远征或返回家园" % str(latest["title"])


## 落点按种子目录的稳定次序选择，实时避让当前敌人；绝不挪怪或清空生态。
func travel_destination(terrain: String) -> Vector2:
	if terrain == "home": return WorldConfig.spawn_pos()
	if WorldSim.sim == null: return Vector2.INF
	var positions: Dictionary = {}
	for node: Node in get_tree().get_nodes_in_group("monsters"):
		if node is MonsterBase and (node as MonsterBase).inst != null and (node as MonsterBase).inst.is_alive:
			positions[(node as MonsterBase).inst.id] = (node as Node2D).global_position
	for point: Vector2 in CampaignLayout.entry_candidates(terrain):
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


## 出发交谈核验实际营地巡守，不能用原始摆放坐标替代已经避障/移动的居民。
func _home_patrol() -> Node2D:
	for node: Node in get_tree().get_nodes_in_group("npcs"):
		if node is Node2D and node.get("landmark_id")=="camp_ecology" and node.get("quest_kind")=="outpost":
			return node as Node2D
	return null
