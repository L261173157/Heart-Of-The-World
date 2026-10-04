## 一条可放弃/恢复的营地生态试点。历史证据与实时世界快照严格分开。
## 不造怪、不改密度、不调用 report_killed/destroy_nest；只收真实演员动作事件。
class_name CampQuest
extends Node

signal changed
const Data := preload("res://scripts/main/camp_quest_data.gd")
const Inventory := preload("res://scripts/main/camp_quest_inventory.gd")
const Targets := preload("res://scripts/main/camp_quest_targets.gd")
const INVESTIGATE_DISTANCE := 300.0
const ACTION_DISTANCE := 1400.0
var _targets: CampQuestTargets
var _searching := false
var _paying := false
var _preview: Dictionary = {}

func _ready() -> void:
	_targets = Targets.new()
	add_child(_targets)
	EventBus.camp_quest_action_requested.connect(_on_action)
	EventBus.monster_killed_at.connect(_on_kill)
	EventBus.nest_ransacked_at.connect(_on_ransack)
	EventBus.sim_tick_completed.connect(_on_tick)
	if ledger().is_empty():
		_prepare_offer.call_deferred()

func ledger() -> Dictionary:
	return GameState.camp_quest

func is_active() -> bool:
	return not ledger().is_empty() and ledger().get("active", false) and not ledger().get("paid", false)

func offer(giver: String = "营地巡守") -> Dictionary:
	var q := ledger()
	if q.get("paid", false):
		return {"kind": "info", "state": "completed", "text": "营地外的动静 · 已领奖\n%s\n%s" % [history_text(), q.get("next_clue", "继续探索周边地区。") ]}
	if q.is_empty():
		if not _preview_current():
			_preview = {}
		if _preview.is_empty():
			if not _searching:
				_prepare_offer()
			return {"kind": "info", "state": "unavailable", "text": "正在核对真实种群和可达路线，请稍后再交谈。" if _searching else "附近暂无安全可达的调查目标。可继续探索，之后回来核对线索。"}
		return {"kind": "quest", "state": "available", "confirm_text": "接取调查", "quest": {
			"id": Data.ID, "landmark_id": Data.LANDMARK, "kind": "camp_ecology", "giver": giver,
			"title": Data.TITLE, "need": 1, "progress": 0, "gold": Data.REWARD_GOLD, "xp": Data.REWARD_XP, "bonus": Data.REWARD_BONUS},
			"text": "营地外有怪物活动。先到真实据点调查，再决定有限狩猎或捣毁巢穴；两种办法任选其一，最后回营地交付。\n营地可免费休息恢复；商人有补给。此事不限制自由探索。\n两种处理奖励相同：%d金币、%d经验、%s×1。若实地确认线索消失且无替代目标，则按调查与已有贡献结算（12–24金币、20–36经验，无补给）。" % [Data.REWARD_GOLD, Data.REWARD_XP, ItemCatalog.name_of(Data.REWARD_BONUS)]}
	if not is_active():
		return {"kind": "camp_action", "action": "resume", "state": "available", "confirm_text": "继续调查",
			"text": "继续「营地外的动静」？此前调查、行动和奖励记录都会保留。\n" + history_text()}
	if q["stage"] == "return":
		return {"kind": "claim", "state": "claimable", "quest": snapshot(), "confirm_text": "交付领奖",
			"text": "%s\n%s\n确认向营地提交记录并领取%s？" % [history_text(), "当前据点已离开视野；巢穴可能重建，种群可能继续变化", QuestPresentation.reward(snapshot())]}
	if q["stage"] == "choose" and context()["on_site"]:
		return choice_payload()
	if q.get("target", {}).is_empty() and not _searching:
		_select_target(false)
	return {"kind": "info", "state": "in_progress", "text": objective() + "\n" + history_text()}

func accept() -> String:
	# 新章节已含同一份生态预算，陈旧旧单对话不能在领奖后再开第二份。
	if not GameState.outpost_quest.is_empty() and ledger().is_empty():
		return "前哨章节已包含生态奖励，不能另开重复的营地调查"
	if ledger().get("paid", false):
		return "此调查已经领奖，新的线索不会再次发放旧奖励"
	if ledger().is_empty():
		if not _preview_current():
			_preview = {}
			return "暂无已核实的可达目标，请与营地巡守重新交谈"
		GameState.camp_quest = Data.sanitize({"id": Data.ID, "active": true, "target": _preview})
	else:
		ledger()["active"] = true
	GameState.tracked_quest_id = Data.ID
	_save()
	if ledger().get("target", {}).is_empty() and not _searching:
		_select_target(false)
	return "已接取：营地外的动静 · 先到据点明确调查，再选择处理方式"

func abandon() -> String:
	if not is_active():
		return ""
	ledger()["active"] = false
	_save()
	return "已暂停营地调查 · 再与斥候交谈可继续，历史行动仍保留"

func context() -> Dictionary:
	var on_site := _on_site()
	var stage := str(ledger().get("stage", ""))
	return {"stage": stage, "on_site": on_site, "can_investigate": is_active() and on_site and stage in ["investigate", "choose", "act"],
		"action": "choose" if stage == "choose" else "investigate",
		"label": "选择处理方式" if stage == "choose" else "调查据点"}

func target() -> Dictionary:
	if not is_active():
		return {}
	var q := ledger()
	if q["stage"] == "return":
		return {"position": WorldConfig.spawn_pos(), "kind": "camp", "species": "", "region_id": "", "live_facts": {}}
	var t: Dictionary = q.get("target", {})
	if t.is_empty():
		return {}
	return {"position": _position(t), "kind": "camp_ecology", "species": t["species"], "region_id": t["region_id"],
		"live_facts": facts() if _on_site() else {}, "knowledge": "visible" if _on_site() else ("last_seen" if q["investigated"] else "npc_intel")}

func investigate() -> String:
	if not is_active() or ledger()["stage"] not in ["investigate", "choose", "act"]:
		return "当前没有待调查的营地线索"
	if not _on_site():
		return "请先抵达线索据点附近，再明确调查"
	var q := ledger()
	var t: Dictionary = q["target"]
	var key := str(t["key"])
	q["investigated"] = true
	if not key in q["surveys"]:
		q["surveys"].append(key)
		_note("已到场调查：%s；当时%s" % [t["species"], live_text()])
	var current := facts()
	# 没有怪物/巢穴或剩余实力不适合当前玩家，只能走已实地确认的变更流程。
	if int(current["viable_count"]) < 1 or not current["nest_active"] or (q["choice"] == "hunt" and not _hunt_possible(current)):
		_save()
		if not _searching:
			_select_target(true)
		return "已记录现场变化，正在核对附近替代线索；此前贡献保留"
	if q["stage"] != "act":
		q["stage"] = "choose"
		_save()
		EventBus.npc_dialogue.emit(choice_payload())
		return "调查完成 · 选择一种处理方式即可"
	_save()
	return "现场已复核：" + live_text()

func choice_payload() -> Dictionary:
	var player := _player()
	var current := facts()
	var remaining := maxi(0, int(ledger().get("target", {}).get("need", 2)) - _hunt_progress())
	var hunt_enabled := _hunt_possible(current)
	var nest_enabled: bool = current["nest_active"] and int(current["alive_count"]) > 0
	var reason := "需至少%d只可应对目标，当前%d只；可改选捣巢或重新调查" % [remaining + 1, current["viable_count"]]
	var payload := {"kind": "camp_choice", "giver": "营地调查记录", "faceset": 0,
		"origin": player.global_position if player != null else WorldConfig.spawn_pos(),
		"text": "现场：%s\n累计真实猎杀%d/2。选一项可用处理；返回营地手动交付。" % [live_text(), mini(_hunt_progress(), 2)],
		"options": [
			{"label": "有限狩猎" if hunt_enabled else "有限狩猎（当前不可用）", "action": "choose_hunt", "enabled": hunt_enabled,
				"disabled_reason": "" if hunt_enabled else reason,
				"consequence": "再猎杀%d只目标，保留巢穴和至少1只存活个体" % remaining,
				"risk": "种群会继续繁衍；已有贡献保留，现场变化时可重新调查" if hunt_enabled else reason},
			{"label": "捣毁巢穴" if nest_enabled else "捣毁巢穴（当前不可用）", "action": "choose_ransack", "enabled": nest_enabled,
				"disabled_reason": "" if nest_enabled else "当前没有有效巢穴或存活种群，请重新调查",
				"consequence": "当地繁衍暂停120刻，存活怪物不会被清除", "risk": "附近已加载同族狂怒60秒；巢穴之后重建，压制并非永久"}]}
	if not hunt_enabled:
		payload["options"].append({"label": "寻找其他狩猎线索", "action": "find_hunt_clue", "utility": true, "enabled": true,
			"consequence": "保留调查和猎杀贡献，核对其他可达据点", "risk": "不改变当前种群或巢穴；无替代时按实地调查交付"})
	return payload

func find_hunt_clue() -> String:
	if not is_active() or ledger()["stage"] != "choose" or not ledger().get("investigated", false) or not _on_site():
		return "先到现场调查，再核对其他狩猎线索"
	if _searching:
		return "正在核对其他可达线索"
	var current := facts()
	if _hunt_possible(current):
		return "当前有限狩猎仍可完成，无需换线索"
	_note("现场不足以有限狩猎并保留族群，主动核对其他线索；当前种群与巢穴保持原状")
	_save()
	_select_target(true)
	return "已保留现场记录与猎杀贡献，核对其他可达据点"

func choose(branch: String) -> String:
	if not is_active() or not ledger().get("investigated", false) or ledger()["stage"] != "choose" or not _on_site():
		return "先到现场调查，再选择处理方式"
	if branch not in ["hunt", "ransack"]:
		return "无效的处理方式"
	var current := facts()
	if branch == "ransack" and (not current["nest_active"] or int(current["alive_count"]) <= 0):
		return "当前已没有有效巢穴或存活种群，请重新调查"
	if branch == "hunt" and not _hunt_possible(current):
		return "当前不足以有限狩猎并保留族群，可选择捣巢或重新调查"
	ledger()["choice"] = branch
	ledger()["stage"] = "act"
	_note("选择：" + ("有限狩猎，保留巢穴" if branch == "hunt" else "捣毁巢穴，暂时压制繁衍"))
	_save()
	return objective()

func claim() -> String:
	var q := ledger()
	if not is_active() or q["stage"] != "return" or not Data.has_result(q) or _paying:
		return "此调查尚未完成交付，或已经领奖"
	if not _at_giver():
		return "请返回营地巡守身边，手动交付调查记录"
	var bonus := str(q.get("bonus", ""))
	var rewards := {bonus: 1} if not bonus.is_empty() else {}
	if not Inventory.can_apply({}, rewards):
		return "补给已达99上限，请先使用一件再交付；记录与全部奖励保留"
	_paying = true
	GameState.begin_world_reward()
	q["paid"] = true
	q["last_summary"] = true
	q["paid_gold"] = roundi(int(q["gold"]) * GameState.stats.gold_mult())
	q["paid_xp"] = int(int(q["xp"]) * GameState.stats.passive_mult("xp", 1.1) * (1.0 + GameState.stats.equip_affix("xp")))
	q["active"] = false
	q["stage"] = "completed"
	q["next_clue"] = _next_clue()
	Inventory.apply({}, rewards)
	GameState.add_gold(int(q["gold"]))
	GameState.add_xp(int(q["xp"]))
	_note("已返回营地交付，奖励已领取")
	_save()
	GameState.end_world_reward()
	_paying = false
	SfxManager.play("quest")
	SfxManager.play("gold3")
	EventBus.fx_requested.emit("flash_yellow", _player().global_position, 1.3)
	EventBus.quest_completed.emit("✓ 营地外的动静 · 交付领奖成功 · " + q["next_clue"])
	return "交付成功 · " + str(q["next_clue"])

func _next_clue() -> String:
	var home := WorldConfig.spawn_pos()
	var origin: SimRegion = WorldSim.sim.region_of_point(home) if WorldSim.sim != null else null
	var chosen: SimRegion
	if origin != null:
		for id: String in origin.neighbor_ids:
			var region: SimRegion = WorldSim.sim.get_region(id)
			if region == null:
				continue
			if chosen == null or (region.terrain != origin.terrain and chosen.terrain == origin.terrain) \
					or (region.terrain == chosen.terrain and region.center.distance_squared_to(home) < chosen.center.distance_squared_to(home)):
				chosen = region
	if chosen != null:
		var delta := chosen.center - home
		var east_west := "东" if delta.x >= 0.0 else "西"
		var north_south := "南" if delta.y >= 0.0 else "北"
		var direction := east_west if absf(delta.x) > absf(delta.y) * 2.0 else (
			north_south if absf(delta.y) > absf(delta.x) * 2.0 else east_west + north_south)
		var area := "另一片" + chosen.display_name if chosen.terrain == origin.terrain else "邻近" + chosen.display_name
		return "后续线索：营地%s的%s可自由探索，了解当地生态。" % [direction, area]
	return "后续线索：周边地区还有不同的生态，可随时自由探索。"

func snapshot() -> Dictionary:
	var q := ledger()
	if q.is_empty():
		return {}
	var t: Dictionary = q.get("target", {})
	var done: bool = q["stage"] in ["return", "completed"]
	var view := {"id": Data.ID, "landmark_id": Data.LANDMARK, "kind": "camp_ecology", "giver": "营地巡守",
		"title": Data.TITLE, "progress": 1 if done else 0, "need": 1, "claim_at_npc": true,
		"gold": q["gold"], "xp": q["xp"], "bonus": q["bonus"], "camp_stage": q["stage"],
		"ui_state": "claimable" if done else "in_progress", "ui_status": "可交付" if done else "进行中",
		"ui_objective": objective(), "history": history_text(), "live_facts": live_text() if _on_site() else "当前据点状态未在视野内；历史行动记录不代表现状",
		"target_pos": [WorldConfig.spawn_pos().x, WorldConfig.spawn_pos().y] if done else t.get("pos", []),
		"species": "" if done else t.get("species", ""), "hunt_region": t.get("region_id", ""),
		"ui_knowledge": "visible" if _on_site() else ("last_seen" if q.get("investigated", false) else "npc_intel")}
	view["ui_reward"] = QuestPresentation.reward(view)
	return view

func objective() -> String:
	var q := ledger()
	if q.is_empty():
		return "与营地巡守交谈"
	if _searching:
		return "正在核对真实种群与可达路线 · 可继续探索"
	var t: Dictionary = q.get("target", {})
	if t.is_empty():
		return "附近暂无安全可达线索 · 可继续探索，回营地复核"
	var where := str(t["species"]) + "据点"
	match str(q["stage"]):
		"investigate": return "前往%s，靠近后点调查 · 未调查不会结算" % where
		"choose": return "已调查%s · 选择有限狩猎或捣毁巢穴" % where
		"act":
			var f := facts()
			if _on_site() and (f["viable_count"] == 0 or not f["nest_active"] or (q["choice"] == "hunt" and not _hunt_possible(f))):
				return "现场已变化 · 到据点重新调查，既有贡献保留"
			if q["choice"] == "hunt":
				return "有限狩猎 %s · 累计%d/2 · 保留巢穴和剩余族群%s" % [t["species"], _hunt_progress(), "" if _on_site() else " · 现状待到场确认"]
			return "捣毁%s的巢穴 · 暂停繁衍，存活个体仍会狂怒%s" % [t["species"], "" if _on_site() else " · 现状待到场确认"]
		"return": return "已有行动记录 · 返回营地巡守，手动交付领奖"
		_: return str(q.get("next_clue", "自由探索周边地区"))

func facts() -> Dictionary:
	var t: Dictionary = ledger().get("target", {})
	var result := {"alive_count": 0, "viable_count": 0, "nest_active": false, "rebuild_ticks": 0}
	if t.is_empty() or WorldSim.sim == null:
		return result
	for inst: MonsterInstance in WorldSim.sim.instances.values():
		if inst.is_alive and inst.region_id == t["region_id"] and inst.species.species_name == t["species"]:
			result["alive_count"] += 1
			if _targets != null and _targets._feasible(inst) and _actor_position(inst).distance_to(_position(t)) <= ACTION_DISTANCE:
				result["viable_count"] += 1
	var nest: Dictionary = WorldSim.sim.nests.get(t["key"], {})
	result["nest_active"] = nest.get("active", false)
	result["rebuild_ticks"] = int(nest.get("rebuild", 0))
	return result

func live_text() -> String:
	var f := facts()
	return "当前存活%d只；%s" % [f["alive_count"], "巢穴活跃，可继续繁衍" if f["nest_active"] else (
		"巢穴暂毁，约%d刻后重建；幸存者仍可能狂怒" % f["rebuild_ticks"] if f["rebuild_ticks"] > 0 else "未见有效巢穴")]

func history_text() -> String:
	var entries: Array = ledger().get("history", [])
	return "历史记录：" + ("；".join(entries) if not entries.is_empty() else "尚未进行现场调查或处理")

func npc_status() -> Dictionary:
	if ledger().get("paid", false):
		return {"state": "completed", "marker": "✓ 已完成 · 区域线索", "color": QuestPresentation.COMPLETED_COLOR}
	if is_active():
		if ledger()["stage"] == "return":
			var bonus := str(ledger().get("bonus", ""))
			if bonus != "" and not Inventory.can_apply({}, {bonus: 1}):
				return {"state": "pending", "marker": "· 补给已满 · 待交付", "color": QuestPresentation.PROGRESS_COLOR}
			return {"state": "claimable", "marker": "? 可交付", "color": QuestPresentation.CLAIMABLE_COLOR}
		return {"state": "in_progress", "marker": "· 调查进行中", "color": QuestPresentation.PROGRESS_COLOR}
	if not ledger().is_empty():
		return {"state": "available", "marker": "! 可继续调查", "color": QuestPresentation.AVAILABLE_COLOR}
	if not _preview_current():
		return {"state": "unavailable", "marker": "· 核查线索中" if _searching else "· 暂无合适线索", "color": QuestPresentation.PROGRESS_COLOR}
	return {"state": "available", "marker": "! 可接调查", "color": QuestPresentation.AVAILABLE_COLOR}

func _prepare_offer() -> void:
	if _searching or not ledger().is_empty():
		return
	_searching = true
	_preview = await _targets.select_target()
	if not is_inside_tree():
		return
	_searching = false
	changed.emit()

func _select_target(after_survey: bool) -> void:
	_searching = true
	changed.emit()
	var q := ledger()
	var excluded: Array = q.get("surveys", []) if after_survey else []
	var found := await _targets.select_target(excluded)
	if not is_inside_tree():
		return
	_searching = false
	if not is_active() or ledger() != q:
		return
	if not found.is_empty():
		found["kill_start"] = 0
		q["target"] = found
		q["investigated"] = false
		q["choice"] = ""
		q["stage"] = "investigate"
		if after_survey:
			_note("转向附近替代据点，先前贡献保留")
		EventBus.hint_requested.emit("营地线索：%s据点 · 先到现场调查" % found["species"])
	elif after_survey and q.get("investigated", false):
		# 只接受实际到场记录；被删掉的未访问目标无法在营地白领调查奖励。
		_finish("survey")
		return
	_save()

func _on_kill(id: int, species: String, region: String, pos: Vector2) -> void:
	if not is_active() or ledger()["stage"] != "act" or not ledger()["investigated"]:
		return
	var q := ledger()
	var t: Dictionary = q["target"]
	if species != t["species"] or region != t["region_id"] or pos.distance_to(_position(t)) > ACTION_DISTANCE or id in q["kills"]:
		return
	var inst: MonsterInstance = WorldSim.sim.instances.get(id) if WorldSim.sim != null else null
	if inst == null or inst.is_alive or inst.species.species_name != species or inst.region_id != region \
			or not inst.death_pos.is_finite() or inst.death_pos.distance_to(pos) > 4.0:
		return
	q["kills"].append(id)
	_note("实际猎杀%s（累计%d只）" % [species, q["kills"].size()])
	if _hunt_progress() >= int(t["need"]) and facts()["nest_active"] and int(facts()["alive_count"]) > 0:
		_finish("hunt")
	else:
		_save()

func _on_ransack(species: String, region: String, pos: Vector2) -> void:
	if not is_active() or ledger()["stage"] != "act" or not ledger()["investigated"]:
		return
	var q := ledger()
	var t: Dictionary = q["target"]
	if species != t["species"] or region != t["region_id"] or pos.distance_to(_position(t)) > INVESTIGATE_DISTANCE:
		return
	if facts()["nest_active"]:
		return
	if not t["key"] in q["ransacks"]:
		q["ransacks"].append(t["key"])
		_note("实际捣毁%s的巢穴；仅暂时抑制繁衍，存活怪物未被清除" % species)
	# 玩家已明确以实际行动改变方案，记录真实结果，不要求再去杀两只。
	_finish("ransack")

func _finish(outcome: String) -> void:
	var q := ledger()
	q["outcome"] = outcome
	q["stage"] = "return"
	if outcome == "survey":
		q["gold"] = 12 + mini(q["kills"].size(), 2) * 6
		q["xp"] = 20 + mini(q["kills"].size(), 2) * 8
		q["bonus"] = ""
		_note("实地确认线索已变化，当前未核实可达的替代线索；按调查与实际贡献交付")
	else:
		_note("已完成有限狩猎；当时巢穴与剩余族群保留" if outcome == "hunt" else "已完成暂时捣巢压制；不代表当前仍无巢穴")
	_save()
	EventBus.hint_requested.emit("营地调查已有结果 · 返回斥候身边手动交付")

func _on_action(action: String) -> void:
	var message := ""
	match action:
		"investigate": message = investigate()
		"choose":
			if is_active() and ledger()["stage"] == "choose" and _on_site():
				EventBus.npc_dialogue.emit(choice_payload())
		"choose_hunt": message = choose("hunt")
		"choose_ransack": message = choose("ransack")
		"find_hunt_clue": message = find_hunt_clue()
		"resume": message = accept()
	if not message.is_empty():
		EventBus.hint_requested.emit(message)

func _on_tick(_summary: Dictionary) -> void:
	if is_active():
		changed.emit()

func _hunt_progress() -> int:
	return ledger().get("kills", []).size()

func _on_site() -> bool:
	var player := _player()
	var t: Dictionary = ledger().get("target", {})
	if player == null or not player.visible or t.is_empty() or player.global_position.distance_to(_position(t)) > INVESTIGATE_DISTANCE:
		return false
	# 同源阻挡格补上物理瓦片尚未流式生成的窗口，不能隔墙调查。
	var delta := _position(t) - player.global_position
	var steps := maxi(1, ceili(delta.length() / 12.0))
	for i in range(1, steps + 1):
		var p := player.global_position + delta * float(i) / float(steps)
		if ObstacleField.is_obstacle_cell(Vector2i((p / ObstacleField.CELL).floor())):
			return false
	var ray := PhysicsRayQueryParameters2D.create(player.global_position, _position(t), 1)
	if player is CollisionObject2D:
		ray.exclude = [(player as CollisionObject2D).get_rid()]
	return player.get_world_2d().direct_space_state.intersect_ray(ray).is_empty()

func _at_giver() -> bool:
	var player := _player()
	if player == null:
		return false
	for npc: Node in get_tree().get_nodes_in_group("npcs"):
		if npc is Node2D and npc.get("landmark_id") == Data.LANDMARK and (npc as Node2D).is_visible_in_tree() \
				and player.global_position.distance_to(npc.global_position) <= 220.0:
			return true
	return false

func _player() -> Node2D:
	return get_tree().get_first_node_in_group("player") as Node2D

func _position(t: Dictionary) -> Vector2:
	var pos: Array = t.get("pos", [0.0, 0.0])
	return Vector2(float(pos[0]), float(pos[1]))

func _note(text: String) -> void:
	if not text in ledger()["history"]:
		ledger()["history"].append(text)

func _save() -> void:
	GameState._invalidate_world_save_cache()
	GameState._queue_save()
	changed.emit()

func _hunt_possible(f: Dictionary) -> bool:
	var remaining := maxi(0, int(ledger().get("target", {}).get("need", 2)) - _hunt_progress())
	return f["nest_active"] and int(f["viable_count"]) >= remaining + 1

func _actor_position(inst: MonsterInstance) -> Vector2:
	return _targets.actor_position(inst)

func _preview_current() -> bool:
	if _preview.is_empty() or WorldSim.sim == null or not WorldSim.sim.nests.get(_preview["key"], {}).get("active", false):
		return false
	return _targets.current_stock_ids(_preview).size() >= 3

func receipt_text() -> String:
	var q := ledger()
	if not q.get("paid", false):
		return ""
	var bonus := str(q.get("bonus", ""))
	return "✓ 已领奖：营地外的动静（+%d金币 +%d经验%s）· %s" % [q.get("paid_gold", q["gold"]),
		q.get("paid_xp", q["xp"]), " +" + ItemCatalog.name_of(bonus) if bonus != "" else "", q.get("next_clue", "自由探索")]
