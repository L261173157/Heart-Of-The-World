## 三章式前哨任务。只消费真实调查/拾取/救援/战斗事件，不生成或复活生态个体。
class_name OutpostQuest
extends Node

signal changed
const Data := preload("res://scripts/main/outpost_quest_data.gd")
const Legacy := preload("res://scripts/main/camp_quest_data.gd")
const Inventory := preload("res://scripts/main/camp_quest_inventory.gd")
const Targets := preload("res://scripts/main/outpost_quest_targets.gd")
const Layout := preload("res://scripts/ecology/outpost_layout.gd")
const OBJECT_DISTANCE := 150.0
const SITE_DISTANCE := 300.0
const ACTION_DISTANCE := 1400.0
var _targets: OutpostQuestTargets
var _searching := false
var _search_complete := false
var _mutating := false
var _roster_ready := false
var _search_generation := 0

func _ready() -> void:
	_targets = Targets.new()
	add_child(_targets)
	_targets.set_process(false)
	EventBus.camp_quest_action_requested.connect(_on_action)
	EventBus.outpost_interaction_requested.connect(_on_object_interaction)
	EventBus.monster_killed_at.connect(_on_kill)
	EventBus.nest_ransacked_at.connect(_on_ransack)
	EventBus.sim_tick_completed.connect(_on_tick)
	_sync_legacy()
	_ensure_target.call_deferred()

func _exit_tree() -> void:
	_search_generation += 1
	_searching = false
	if is_instance_valid(_targets): _targets.clear_proofs()

func ledger() -> Dictionary:
	return GameState.outpost_quest

func is_active() -> bool:
	return not ledger().is_empty() and ledger().get("active", false) and ledger().get("stage", "") != "completed"

func evidence(key: String) -> bool:
	return ledger().get("evidence", {}).get(key, false)

func visual_state() -> Dictionary:
	var state: Dictionary = ledger().get("evidence", {}).duplicate(true)
	state["evidence"] = ledger().get("evidence", {}).duplicate(true)
	state["stage"] = ledger().get("stage", "")
	state["active"] = is_active()
	state["id"] = Data.ID
	state["target_object_id"] = _target_object() if is_active() and GameState.tracked_quest_id == Data.ID else ""
	state["object_states"] = {}
	for id: String in Layout.OBJECTS:
		var key := str({"patrol_record":"patrol_read", "entrance_record":"entrance_read", "supply_record":"supply_read", "aid_bag":"aid_taken", "repair_tools":"tools_taken"}.get(id, ""))
		if not key.is_empty() and evidence(key): state["object_states"][id] = "read" if key.ends_with("read") else "taken"
	if evidence("signpost_repaired"):
		state["object_states"]["signpost"] = "claimed" if ledger().get("receipts", {}).get("restoration", {}).get("paid", false) else "ready"
	return state

func offer(giver: String = "营地巡守") -> Dictionary:
	var text := "前哨巡逻队失联了。先沿旧道寻找巡逻记录，再去前哨救援。\n"
	var reserved := Data.valid_legacy(GameState.camp_quest) if ledger().is_empty() else bool(ledger().get("legacy_reserved", false))
	text += "原营地调查奖励仍在旧单领取；前哨行动另记进度。" if reserved else "全章奖励：39金币、44经验、饭团×1，随调查、救援、修复分段领取。"
	var q := ledger()
	var action := "accept" if q.is_empty() else "resume"
	var label := "接取失联前哨" if q.is_empty() else "继续前哨任务"
	if q.get("stage", "") == "completed":
		text = "前哨已恢复，奖励收据已保存。留守巡逻员仍在前哨。\n" + str(q.get("next_clue", ""))
		action = "status"
		label = "查看前哨记录"
	elif is_active():
		text = next_action() + "\n" + step_progress()
		action = "status"
		label = "查看当前进度"
	if Data.valid_legacy(GameState.camp_quest):
		return {"kind": "camp_choice", "giver": giver, "origin": WorldConfig.spawn_pos(), "text": text,
			"options": [{"label": label, "action": "outpost:" + action, "enabled": true,
				"consequence": "保留前哨的独立行动与分段收据", "risk": "可随时暂停并继续"},
				{"label": "原营地调查 / 交付", "action": "outpost:legacy", "enabled": true,
				"consequence": "查看或领取原委托，金额和贡献不变", "risk": "旧奖励只支付一次"}]}
	if action == "status":
		return {"kind": "info", "giver": giver, "text": text}
	return {"kind": "quest", "giver": giver, "state": "available", "confirm_text": label, "text": text,
		"quest": {"id": Data.ID, "kind": "outpost", "title": Data.TITLE, "giver": giver, "need": 3, "progress": 0}}

func accept() -> String:
	if ledger().get("stage", "") == "completed":
		return "前哨已恢复，历史行动与奖励不会重置"
	if ledger().is_empty():
		GameState.outpost_quest = Data.create(GameState.camp_quest)
		if ledger()["legacy_reserved"]:
			_note("原营地调查奖励保留在旧委托，本章不重复发放数值奖励")
	else:
		ledger()["active"] = true
	GameState.tracked_quest_id = Data.ID
	_sync_legacy()
	_save()
	_ensure_target()
	return "已接取：失联的前哨 · " + objective()

func abandon() -> String:
	if not is_active(): return ""
	ledger()["active"] = false
	_search_generation += 1
	_roster_ready = false
	_targets.clear_proofs()
	_save()
	return "已暂停前哨任务，专用物件、救援和支付收据全部保留"

func reward_policy() -> String:
	if ledger().get("legacy_reserved", false):
		return "原调查奖励仍按原巢边条件在旧委托领取；本章新增行动不重复发数值奖励"
	return "全章基础39金币、44经验、饭团×1（养成加成生效）。调查6金币/8经验，救援9金币/12经验，修复24金币/24经验/饭团；各段一次。"

func object_state(id: String) -> Dictionary:
	var known := false
	var done := false
	match id:
		"patrol_record": known = not ledger().is_empty(); done = evidence("patrol_read")
		"entrance_record": known = evidence("patrol_read"); done = evidence("entrance_read")
		"wounded_patrol": known = evidence("entrance_read"); done = evidence("rescued")
		"supply_record": known = evidence("wounded_found"); done = evidence("supply_read")
		"aid_bag": known = evidence("supply_read"); done = evidence("aid_taken")
		"repair_tools": known = evidence("supply_read"); done = evidence("tools_taken")
		"survey_marker": known = Data.rescue_done(ledger()); done = Data.has_ecology_result(ledger())
		"signpost": known = evidence("entrance_read"); done = evidence("signpost_repaired")
	return {"known": known, "done": done, "available": known and is_active() and not done, "evidence": visual_state()}

func object_payload(id: String) -> Dictionary:
	if not _at_object(id):
		return {"kind": "info", "text": "请走到物件旁边，确认没有墙体遮挡后再交互"}
	if ledger().is_empty():
		return {"kind": "info", "text": "这里留有巡逻痕迹。先向营地巡守询问失联前哨的线索。"}
	if not is_active() and ledger().get("stage", "") != "completed":
		return {"kind": "camp_action", "action": "outpost:resume", "confirm_text": "继续前哨任务", "text": "此前证据与专用物件仍保留。要继续调查前哨吗？", "origin": Layout.object_position(id)}
	var text := ""
	var confirm := "记录线索"
	match id:
		"patrol_record":
			text = "巡逻记录：『前哨的路标倒了，正门有碎岩封堵。先沿旧道到门口核对入口图，伤员留在西侧棚屋。』\n这条记录只指出入口，未确认伤员和当地怪物的现状。"
		"entrance_record":
			text = "入口草图：正门有可清理的碎岩，敲开后可直接进入；西侧缺口能绕过正门，但要多走一段残墙边的路。两条路都不是安全保证，注意眼前的真实敌人。\n确认入口后，去西侧棚屋查看留守巡逻员。"
		"wounded_patrol":
			if evidence("signpost_repaired"):
				text = "留守巡逻员：谢谢，路标已经立好，我会留在这里。\n" + str(ledger().get("next_clue", _next_clue()))
				confirm = "记下区域线索"
			elif evidence("rescued"):
				text = "留守巡逻员：伤口包扎好了，我能继续守在这里。带回工具，核查周边生态，再把路标修好。\n" + objective()
			elif not evidence("wounded_found"):
				text = "巡逻员靠在棚屋边，腿上缠着破布：『补给被分放在两边。先看院中的补给记录，北边有我们专用的急救包，南边是修路标的工具。』\n他会留在原地，不需要护送。"
				confirm = "查看伤势与求助"
			elif evidence("aid_taken"):
				text = "专用急救包已找回。确认替这位留守巡逻员清理伤口并包扎？\n只使用这份任务急救包，不消耗普通药品；救援后他继续留守前哨。"
				confirm = "使用急救包救援"
			else:
				text = "留守巡逻员：急救包在北侧的废棚后，得先找到院中的补给记录。普通补给无法代替遗失的任务急救包。"
		"supply_record":
			text = "补给记录：带红结的急救包放在北侧废棚后；绑着绳子的修理工具留在南侧拐角。两处都能从院内走到，要绕开各自的残墙。\n这是两件独立的任务物件，不能买卖，也不占普通补给上限。"
		"aid_bag":
			text = "红结急救包封着巡逻队的标记。取回后，回到受伤巡逻员身旁救治。"
			confirm = "取回专用急救包"
		"repair_tools":
			text = "工具里有锤子、木钉和路标支架。取回后，救援并核查周边，再到路标旁修复。"
			confirm = "取回修理工具"
		"survey_marker":
			text = "在前哨院中核查周边活动痕迹。只记录当前亲眼核实的情况；若没有安全可行的处理对象，就提交现场勘察，不虚构猎杀或捣巢。"
			confirm = "现场勘察"
		"signpost":
			if evidence("signpost_repaired"):
				text = "路标已修好，前哨检查点已启用。\n" + ("修复尾款待领取。背包放不下的补给会存入背包→待领取。" if ledger()["stage"] == "claim" else "修复奖励已领取。")
				confirm = "领取修复尾款"
			else:
				text = "倒下的路标需要专用工具。确认修复前，需先救援巡逻员，并取得真实生态处理或现场勘察结果。\n修好后这里才成为可用检查点，不会把到访误算成修复。"
				confirm = "修复前哨路标"
		_:
			return {"kind": "info", "text": "未知前哨物件"}
	var state := object_state(id)
	if bool(state.get("done", false)) and id != "wounded_patrol" and not (id == "signpost" and ledger().get("stage", "") == "claim"):
		var label := "已读" if id.ends_with("record") else "已完成"
		return {"kind":"info", "giver":"前哨记录", "text":label + " · " + text}
	return {"kind": "camp_action", "action": "outpost:" + id, "giver": "留守巡逻员" if id == "wounded_patrol" else "前哨调查",
		"origin": Layout.object_position(id), "confirm_text": confirm, "text": text}

func object_action(id: String) -> String:
	if _mutating: return "正在记录本次行动"
	if not _at_object(id): return "请到物件身边明确交互，不能隔墙操作"
	if not is_active() and not (ledger().get("stage", "") == "completed" and id == "wounded_patrol"):
		return "先接取或继续失联前哨任务"
	var q := ledger()
	var e: Dictionary = q["evidence"]
	var message := ""
	var changed_evidence := ""
	match id:
		"patrol_record": changed_evidence = "patrol_read"; message = "已记录巡逻去向：前往前哨入口核对草图"
		"entrance_record":
			if not evidence("patrol_read"): return "先阅读沿途的巡逻记录，才能对照入口草图"
			changed_evidence = "entrance_read"; message = "已确认入口：可清理正门碎岩或绕行西侧缺口，再去棚屋查看巡逻员"
		"wounded_patrol":
			if not evidence("entrance_read"): return "先核对前哨入口草图"
			if evidence("signpost_repaired"):
				changed_evidence = "next_clue_received"; message = str(q.get("next_clue", _next_clue()))
			elif not evidence("wounded_found"):
				changed_evidence = "wounded_found"; message = "发现受伤巡逻员：先查看院中的补给记录"
			elif evidence("rescued"): return "巡逻员已获救并继续留守 · " + objective()
			elif not evidence("aid_taken"): return "需要先取回巡逻队的专用急救包"
			else: changed_evidence = "rescued"; message = "已用专用急救包包扎伤口，巡逻员留在前哨；普通药品未消耗"
		"supply_record":
			if not evidence("wounded_found"): return "先亲自查看受伤巡逻员，确认缺失的补给"
			changed_evidence = "supply_read"; message = "已确认两条补给路线：北侧急救包，南侧修理工具"
		"aid_bag", "repair_tools":
			if not evidence("supply_read"): return "先查看补给记录，核对这件物品的用途"
			changed_evidence = "aid_taken" if id == "aid_bag" else "tools_taken"
			message = "已取回专用急救包，请到伤员身边明确救援" if id == "aid_bag" else "已取回修理工具，修复需在路标处亲自完成"
		"survey_marker":
			return investigate(true)
		"signpost":
			if evidence("signpost_repaired"):
				return claim()
			if not Data.rescue_done(q): return "先取回两件专用补给，并亲手救援巡逻员"
			_sync_legacy()
			if not Data.has_ecology_result(q): return "先取得真实生态处理或现场勘察结果，再修路标"
			changed_evidence = "signpost_repaired"; message = "路标已修复，前哨检查点已启用；巡逻员会继续留守"
		_: return "未知前哨行动"
	if e.get(changed_evidence, false): return "这项行动已有记录 · " + objective()
	_mutating = true
	GameState.begin_world_reward()
	e[changed_evidence] = true
	_note(message)
	if changed_evidence == "signpost_repaired":
		q["next_clue"] = _next_clue()
		GameState.discover_checkpoint(Layout.CHECKPOINT_ID)
	_sync_legacy()
	_settle_ready(changed_evidence == "signpost_repaired")
	_save()
	GameState.end_world_reward()
	_mutating = false
	_ensure_target()
	return message + (" · 修复尾款待领取" if q["stage"] == "claim" else "")

func claim() -> String:
	if _mutating or not evidence("signpost_repaired") or not Data.has_ecology_result(ledger()):
		return "尚未完成前哨修复"
	if not _at_object("signpost"): return "请到修好的路标旁领取尾款"
	if ledger()["receipts"]["restoration"]["paid"]: return "修复奖励已经领取"
	_mutating = true
	GameState.begin_world_reward()
	_settle_ready(true)
	_save()
	GameState.end_world_reward()
	_mutating = false
	return "修复尾款已完整领取 · " + str(ledger()["next_clue"]) if ledger()["receipts"]["restoration"]["paid"] else "修复尾款仍待领取，请重新确认；背包放不下的补给会存入背包→待领取"

func _settle_ready(allow_restoration: bool = false) -> void:
	var q := ledger()
	for stage: String in Data.RECEIPTS:
		if stage == "restoration" and not allow_restoration: continue
		if q["receipts"][stage]["paid"]: continue
		var ready := Data.investigation_done(q) if stage == "investigation" else (Data.rescue_done(q) if stage == "rescue" else evidence("signpost_repaired") and Data.has_ecology_result(q))
		if not ready: continue
		var reward := Data.reward(stage, q["legacy_reserved"])
		var bonus := str(reward["bonus"])
		var items := {bonus: 1} if bonus != "" else {}
		if not Inventory.can_apply({}, items): continue
		var gold := roundi(int(reward["gold"]) * GameState.stats.gold_mult())
		var xp := int(int(reward["xp"]) * GameState.stats.passive_mult("xp", 1.1) * (1.0 + GameState.stats.equip_affix("xp")))
		# 收据先于同步库存广播提交；外层世界奖励锁阻止只存半笔交易。
		q["receipts"][stage] = {"paid": true, "status": "paid", "gold": gold, "xp": xp, "bonus": bonus, "legacy_reserved": q["legacy_reserved"]}
		Inventory.apply({}, items)
		GameState.add_gold(int(reward["gold"]))
		GameState.add_xp(int(reward["xp"]))
		_note(("已记录" if q["legacy_reserved"] else "已领取") + {"investigation": "第一段调查", "rescue": "第二段救援", "restoration": "第三段修复"}[stage] + ("；原调查奖励仍按旧单结算" if q["legacy_reserved"] else "奖励：%d金币、%d经验%s" % [gold, xp, "、饭团×1" if bonus != "" else ""]))
	Data.refresh_stage(q)
	if q["stage"] == "completed":
		q["last_summary"] = true

func _ensure_target() -> void:
	if not is_active() or not Data.rescue_done(ledger()) or Data.has_ecology_result(ledger()) or _searching:
		return
	if ledger().get("target", {}).is_empty() and not _search_complete:
		if ledger().get("legacy_reserved", false) and not GameState.camp_quest.get("target", {}).is_empty():
			ledger()["target"] = Data.target_data(GameState.camp_quest["target"])
			ledger()["evidence"]["site_surveyed"] = false
			_search_complete = true
			_note("沿用原调查线索，保留贡献并亲自复核现场")
			_save()
		else:
			_select_target(false)
	if not ledger().get("target", {}).is_empty() and not _roster_ready and not _searching:
		_refresh_roster(false)

func _refresh_roster(show_choice: bool) -> void:
	if _searching or not is_active() or ledger().get("stage", "") != "ecology": return
	_searching = true
	var q := ledger()
	var original: Dictionary = q["target"]
	if not _targets.valid_site(original):
		var canonical := _targets.site_position(original)
		if canonical.is_finite():
			# 仅修复线索坐标，不把当前位置记成到场；实际历史贡献仍保留。
			original = original.duplicate(true)
			original["pos"] = [canonical.x, canonical.y]
			q["target"] = original
			# 已有真址调查作为历史保留；修复线索本身绝不新增一次到场。
			if not original.get("key", "") in q["surveys"]: q["evidence"]["site_surveyed"] = false
		else:
			q["target"] = {}
			q["evidence"]["site_surveyed"] = false
			_searching = false
			_search_complete = false
			_roster_ready = false
			_select_target(false)
			return
	var generation := _search_generation
	var sim_before := WorldSim.sim
	var found := await _targets.verify_target(original, true)
	if not is_inside_tree(): return
	_searching = false
	if generation != _search_generation or WorldSim.sim != sim_before:
		_roster_ready = false
		_ensure_target.call_deferred()
		return
	if ledger() != q or q["target"] != original or not is_active() or Data.has_ecology_result(q) or q.get("stage", "") != "ecology": return
	q["target"] = Data.target_data(found)
	_roster_ready = true
	_targets.retain_target(q["target"])
	if show_choice:
		var f := _current_facts()
		if not f["nest_active"] or int(f["viable_count"]) == 0:
			_note("已到场记录巢址变化，原实名族群暂未核实可行处理对象；既有贡献保留")
			_save()
			_select_target(true)
			return
		_save()
		if _on_site(): EventBus.npc_dialogue.emit(choice_payload())
	else: _save()

func _select_target(after_survey: bool) -> void:
	if _searching or not is_active() or ledger().get("stage", "") != "ecology": return
	_searching = true
	changed.emit()
	var q := ledger()
	var generation := _search_generation
	var sim_before := WorldSim.sim
	_targets.required_stock = maxi(0, 2 - q.get("kills", []).size()) + 1
	var found := await _targets.select_target(q.get("surveys", []) if after_survey else [])
	if not is_inside_tree(): return
	_searching = false
	if generation != _search_generation or WorldSim.sim != sim_before:
		_roster_ready = false
		_ensure_target.call_deferred()
		return
	_search_complete = true
	if ledger() != q or not is_active() or Data.has_ecology_result(q): return
	if not found.is_empty():
		q["target"] = Data.target_data(found)
		_roster_ready = true
		_targets.retain_target(q["target"])
		q["choice"] = ""
		q["evidence"]["site_surveyed"] = false
		_note("已核对一处可达生态线索，仍需亲自到场调查：" + str(found["species"]))
	elif not after_survey and q.get("legacy_reserved", false) and _targets.site_position(GameState.camp_quest.get("target", {})).is_finite():
		# 原委托仍有已知线索：必须亲赴原现场复核，不能在前哨把远方线索伪记为到访。
		q["target"] = Data.target_data(GameState.camp_quest["target"])
		q["evidence"]["site_surveyed"] = false
		_note("未核实新的可行目标，沿用原调查线索并亲自到场复核")
	elif after_survey:
		q["survey_confirmed"] = true
		_finish("survey")
		return
	_save()

func context() -> Dictionary:
	var on_site := _on_site()
	return {"on_site": on_site, "can_investigate": is_active() and ledger().get("stage", "") == "ecology" and on_site,
		"action": "outpost:investigate", "label": "核查前哨生态", "target_id": str(ledger().get("target", {}).get("key", "survey_marker"))}

func investigate(at_marker: bool = false) -> String:
	if not is_active() or not Data.rescue_done(ledger()): return "先救援巡逻员并取回修理工具，再核查生态"
	_sync_legacy()
	if Data.has_ecology_result(ledger()): return "已有真实生态历史结果 · 前往倒下的路标明确修复"
	if _searching: return "正在核对可达路线，可继续在前哨活动"
	var q := ledger()
	if q["target"].is_empty():
		if not at_marker or not _at_object("survey_marker"): return "请到前哨院中的勘察点，明确记录现场情况"
		if not _search_complete:
			_ensure_target()
			return "先核对可达生态线索，之后在勘察点记录现场"
		q["evidence"]["site_surveyed"] = true
		_note("亲自在前哨勘察，重新核对当前可达处理对象；不以旧搜索结果断言现在没有目标")
		_save()
		_select_target(true)
		return "已到场勘察，正在重新核对当前生态；没有可行对象时按实地记录继续"
	if not _on_site(): return "请先抵达已指明的生态据点，再现场调查"
	q["evidence"]["site_surveyed"] = true
	if not q["target"]["key"] in q["surveys"]: q["surveys"].append(q["target"]["key"])
	_note("已亲自调查%s巢址；周边个体会巡猎，旧位置与线索不代表当前目视存量" % q["target"]["species"])
	_save()
	_refresh_roster(true)
	return "已调查真实巢址，正在复核实名族群与可达处理方案"

func choice_payload() -> Dictionary:
	var f := _current_facts()
	var remaining := maxi(0, 2 - ledger().get("kills", []).size())
	var hunt: bool = f["nest_active"] and int(f["viable_count"]) >= remaining + 1
	var nest: bool = f["nest_active"] and int(f["viable_count"]) > 0
	var payload := {"kind": "camp_choice", "giver": "前哨生态记录", "origin": _position(ledger()["target"]),
		"text": "巢址已调查，已有猎杀%d/2。\n%s\n个体会持续巡猎；任选可行方案，不需回营。" % [mini(ledger()["kills"].size(), 2), live_text()],
		"options": [{"label": "有限狩猎", "action": "outpost:choose_hunt", "enabled": hunt,
			"disabled_reason": "当前存量不足以保留至少一只，可改选捣巢或重新核查", "consequence": "再猎杀%d只，保留巢穴与幸存族群" % remaining, "risk": "种群会继续繁衍，需真实行动"},
			{"label": "暂时捣巢", "action": "outpost:choose_ransack", "enabled": nest,
			"disabled_reason": "没有有效巢穴或可应对存活个体", "consequence": "暂停当地繁衍120刻", "risk": "存活怪物不会被清除，附近同族狂怒60秒；巢穴会重建"},
			{"label": "重新核查现场", "action": "outpost:investigate", "enabled": true, "utility": true,
			"consequence": "保留已有行动，记录变化", "risk": "不会虚构猎杀或立即清空据点"}]}

	if not hunt:
		payload["options"].append({"label": "寻找其他狩猎线索", "action": "outpost:find_hunt_clue", "enabled": true, "utility": true,
			"consequence": "保留调查与猎杀贡献，核对其他可达据点", "risk": "不改变当前种群；没有可行替代时按已完成的现场勘察修复前哨"})
	return payload

func find_hunt_clue() -> String:
	if not is_active() or ledger().get("stage", "") != "ecology" or not evidence("site_surveyed") or not _on_site():
		return "先到现场调查，再核对其他狩猎线索"
	if _searching: return "正在核对其他可达线索"
	if _hunt_possible(_current_facts()): return "当前有限狩猎仍可完成，无需换线索"
	_note("现场不足以有限狩猎并保留族群，主动核对其他可达线索；当前种群与巢穴不变")
	_save()
	_select_target(true)
	return "已保留现场记录与贡献，正在核对其他可达据点"

func _hunt_possible(f: Dictionary) -> bool:
	return f.get("nest_active", false) and int(f.get("viable_count", 0)) >= maxi(0, 2 - ledger().get("kills", []).size()) + 1

func choose(branch: String) -> String:
	if not is_active() or ledger().get("stage", "") != "ecology" or not evidence("site_surveyed") or not _on_site(): return "先抵达真实生态据点并明确调查"
	if branch not in ["hunt", "ransack"]: return "未知生态处理方式"
	var f := _current_facts()
	if not f["nest_active"] or int(f["viable_count"]) <= 0: return "现场已变化，请重新核查"
	if branch == "hunt" and int(f["viable_count"]) < maxi(0, 2 - ledger()["kills"].size()) + 1: return "当前不足以有限狩猎并保留族群，可选暂时捣巢"
	ledger()["choice"] = branch
	_note("选择" + ("有限狩猎，保留巢穴" if branch == "hunt" else "暂时捣巢，保留幸存个体"))
	if branch == "hunt" and ledger()["kills"].size() >= 2:
		_finish("hunt")
	else: _save()
	return objective()

func _on_kill(id: int, species: String, region: String, pos: Vector2) -> void:
	if not _accepts_ecology_action(): return
	var q := ledger()
	var t: Dictionary = q["target"]
	if id in q["kills"] or not _targets.accepts_kill(id, t, species, region, pos): return
	q["kills"].append(id)
	var old_target: Dictionary = q.get("legacy_contract", {}).get("target", {})
	if not old_target.is_empty() and _targets.valid_site(old_target) and old_target["key"] == t["key"] and t["key"] in q["surveys"] and pos.distance_to(_targets.site_position(old_target)) <= ACTION_DISTANCE:
		if not id in q["compact_kills"]: q["compact_kills"].append(id)
		var site := _targets.site_position(old_target)
		q["compact_sites"][str(id)] = {"key": t["key"], "pos": [site.x, site.y]}
	_note("真实猎杀记录：%s，累计%d只" % [species, q["kills"].size()])
	var f := _current_facts()
	if q["choice"] == "hunt" and q["kills"].size() >= 2 and f["nest_active"] and int(f["alive_count"]) > 0:
		_finish("hunt")
	else: _save()

func _on_ransack(species: String, region: String, pos: Vector2) -> void:
	if not _accepts_ecology_action(): return
	var q := ledger()
	var t: Dictionary = q["target"]
	if species != t["species"] or region != t["region_id"] or pos.distance_to(_position(t)) > SITE_DISTANCE or WorldSim.sim == null: return
	var nest: Dictionary = WorldSim.sim.nests.get(t["key"], {})
	if nest.is_empty() or nest.get("active", true) or int(nest.get("rebuild", 0)) <= 0 or _targets.current_stock_ids(t).is_empty(): return
	# 信号之外仍验证真实NestNode已执行破坏，不能只用模拟字段拼造结案。
	var destroyed_body := false
	for body: Node in get_tree().get_nodes_in_group("nests"):
		if body is NestNode and body.nest_key == t["key"] and body._destroyed and body.global_position.distance_to(pos) <= 4.0:
			destroyed_body = true
	if not destroyed_body: return
	if not t["key"] in q["ransacks"]: q["ransacks"].append(t["key"])
	_finish("ransack")

func _accepts_ecology_action() -> bool:
	var t: Dictionary = ledger().get("target", {})
	return is_active() and ledger().get("stage", "") == "ecology" and evidence("site_surveyed") and not t.is_empty() \
		and _targets.valid_site(t) and t.get("key", "") in ledger().get("surveys", []) and ledger().get("choice", "") != ""

func _finish(outcome: String) -> void:
	ledger()["outcome"] = outcome
	_note({"hunt": "已完成真实有限狩猎；当时巢穴与幸存族群保留", "ransack": "已实际暂时捣巢；并未清除存活怪物", "survey": "已完成现场勘察，未核实安全可行的替代处理对象"}.get(outcome, "已沿用原调查的真实历史结果"))
	_carry_result_to_legacy()
	Data.refresh_stage(ledger())
	_save()
	EventBus.hint_requested.emit("前哨生态已有结果 · 到倒下的路标处明确修复")

func sync_legacy_contract() -> void:
	if ledger().is_empty() or not ledger().get("legacy_reserved", false): return
	_sync_legacy()
	_save()

func _restore_legacy_contract() -> void:
	if Data.valid_legacy(ledger().get("legacy_contract", {})) and (not Data.valid_legacy(GameState.camp_quest) or (ledger()["legacy_contract"].get("paid", false) and not GameState.camp_quest.get("paid", false))):
		GameState.camp_quest = Legacy.sanitize(ledger()["legacy_contract"])

func _sync_legacy() -> void:
	if ledger().is_empty() or not ledger().get("legacy_reserved", false): return
	_restore_legacy_contract()
	var old := GameState.camp_quest
	if Data.valid_legacy(old):
		ledger()["legacy_contract"] = old.duplicate(true)
	if Data.legacy_result(old):
		ledger()["legacy_result"] = true
		if Data.rescue_done(ledger()):
			ledger()["outcome"] = "legacy"
			_note("沿用原营地调查的生态历史结果，不要求重做；这不代表据点当前仍保持原状")
	else:
		# 旧单贡献只追加去重；选择尚未发生时也不会拿它伪造当前现场调查。
		for id: Variant in old.get("kills", []):
			if not id in ledger()["kills"]: ledger()["kills"].append(id)
	Data.refresh_stage(ledger())

func _carry_result_to_legacy() -> void:
	_restore_legacy_contract()
	var q := ledger()
	var old := GameState.camp_quest
	if not q.get("legacy_reserved", false) or not Data.valid_legacy(old) or old.get("paid", false) or old.get("stage", "") == "completed" or Legacy.has_result(old): return
	# 新章的10k巡猎许可不能扩大旧1400px合同；原目标与原奖励始终不变。
	var t: Dictionary = old.get("target", {})
	if t.is_empty() or not t["key"] in q["surveys"]: return
	for id: Variant in q.get("compact_kills", []):
		var proof: Variant = q.get("compact_sites", {}).get(str(id), {})
		if proof is Dictionary and proof.get("key", "") == t["key"] and proof.get("pos", []).size() == 2 			and _position(proof).distance_to(_position(t)) <= 4.0 and id in q["kills"] and not id in old["kills"]:
			old["kills"].append(id)
	# 换线索后仍保留原巢边贡献，但别处结案不能证明原巢的当前幸存条件。
	q["legacy_contract"] = old.duplicate(true)
	if q["target"].is_empty() or q["target"]["key"] != t["key"] or _position(q["target"]).distance_to(_position(t)) > 4.0: return
	var compatible := ""
	if q["outcome"] == "hunt" and old["kills"].size() >= int(t.get("need", 2)):
		compatible = "hunt"
	elif q["outcome"] == "ransack" and t["key"] in q["ransacks"]:
		compatible = "ransack"
		if not t["key"] in old["ransacks"]: old["ransacks"].append(t["key"])
	if compatible != "":
		if not t["key"] in old["surveys"]: old["surveys"].append(t["key"])
		old["investigated"] = true
		old["outcome"] = compatible
		old["choice"] = q["choice"]
		old["stage"] = "return"
		var note := "前哨行动也满足原巢边合同；原承诺奖励仍返回营地手动交付"
		if not note in old["history"]: old["history"].append(note)
	else:
		_note("前哨已取得独立生态结果；原紧凑委托仍按原巢边规则继续，原承诺奖励未结算")
	q["legacy_result"] = Legacy.has_result(old)
	q["legacy_contract"] = old.duplicate(true)

func _current_facts() -> Dictionary:
	var t: Dictionary = ledger().get("target", {})
	var f := {"alive_count": 0, "viable_count": 0, "nest_active": false, "rebuild_ticks": 0}
	if t.is_empty() or WorldSim.sim == null: return f
	var ids := _targets.current_stock_ids(t)
	f["alive_count"] = ids.size()
	f["viable_count"] = ids.size()
	var nest: Dictionary = WorldSim.sim.nests.get(t["key"], {})
	f["nest_active"] = nest.get("active", false)
	f["rebuild_ticks"] = int(nest.get("rebuild", 0))
	return f

## 对外事实仅包含摄像机、迷雾、完整视线内实际演员；路线簿不是透视雷达。
func facts() -> Dictionary:
	var t: Dictionary = ledger().get("target", {})
	if t.is_empty(): return {}
	var visible_ids: Array[int] = []
	for id: int in _targets.current_stock_ids(t):
		for actor: Node in get_tree().get_nodes_in_group("monsters"):
			if actor is MonsterBase and actor.inst != null and actor.inst.id == id and actor.is_visible_in_tree() and _visible_position(actor.global_position):
				visible_ids.append(id)
	var result := {"visible_count": visible_ids.size(), "visible_ids": visible_ids, "nest_visible": false}
	for nest: Node in get_tree().get_nodes_in_group("nests"):
		if nest is NestNode and nest.nest_key == t["key"] and nest.is_visible_in_tree() and _visible_position(nest.global_position):
			result["nest_visible"] = true
			result["nest_active"] = not nest._destroyed
	return result

func _visible_position(pos: Vector2) -> bool:
	var player := _player()
	if player == null or not player.is_visible_in_tree() or not GameState.fog_knows_position(pos) or player.global_position.distance_to(pos) > 1000.0: return false
	var viewport := get_viewport()
	if viewport.get_camera_2d() == null or not viewport.get_visible_rect().has_point(viewport.get_canvas_transform() * pos): return false
	return _near_position(pos, 1000.0)

func live_text() -> String:
	var f := facts()
	if f.is_empty(): return "当前生态现场尚待调查，旧记录不代表现状"
	var nest_text := "眼前巢穴活跃" if f.get("nest_active", false) else ("眼前巢穴已毁" if f.get("nest_visible", false) else "巢址当前不在视野内")
	return "当前目视已核实个体%d只；%s。未目视个体只作已核实线索，不能据此断言当前现场存量" % [f["visible_count"], nest_text]

func target() -> Dictionary:
	if not is_active(): return {}
	var id := _target_object()
	if id == "ecology":
		var t: Dictionary = ledger()["target"]
		return {"position": _position(t), "kind": "outpost", "object_id": "ecology:" + t["key"], "name": str(t["species"]) + "据点",
			"species": t["species"], "region_id": t["region_id"], "target_instance_ids": _targets.current_stock_ids(t),
			"guide_mode": ("hunt" if ledger()["choice"] == "hunt" else "nest") if evidence("site_surveyed") else "investigate",
			"knowledge": "visible" if facts().get("nest_visible", false) else ("last_seen" if evidence("site_surveyed") else "npc_intel"),
			"knowledge_label": "已调查巢址 / 寻找已核实族群" if ledger()["choice"] == "hunt" else "真实巢址 / 现场调查", "live_facts": facts()}
	if id == "": return {}
	return {"position": Layout.object_position(id), "kind": "outpost", "object_id": id, "name": _object_name(id),
		"species": "", "region_id": "", "knowledge": "visible" if _at_object(id) else "npc_intel", "live_facts": {}}

func _target_object() -> String:
	if not evidence("patrol_read"): return "patrol_record"
	if not evidence("entrance_read"): return "entrance_record"
	if not evidence("wounded_found"): return "wounded_patrol"
	if not evidence("supply_read"): return "supply_record"
	if not evidence("aid_taken"): return "aid_bag"
	if not evidence("rescued"): return "wounded_patrol"
	if not evidence("tools_taken"): return "repair_tools"
	if not Data.has_ecology_result(ledger()): return "ecology" if not ledger().get("target", {}).is_empty() else "survey_marker"
	return "signpost"

func objective() -> String:
	if ledger().is_empty(): return "与营地巡守交谈，接取失联前哨"
	if _searching: return "第三段 · 正在核对真实生态线索与可达路线"
	if ledger()["stage"] == "completed": return str(ledger().get("next_clue", "前哨已恢复，巡逻员仍在原处留守"))
	if ledger()["stage"] == "claim": return "路标与检查点已恢复 · 到路标旁领取修复尾款"
	match _target_object():
		"patrol_record": return "第一段 · 沿旧道阅读巡逻记录"
		"entrance_record": return "第一段 · 在前哨入口核对草图，找可步行进入的缺口"
		"wounded_patrol": return "第二段 · 回到巡逻员身旁，明确使用专用急救包救援" if evidence("wounded_found") else "第二段 · 清理正门碎岩或绕行西侧缺口，查看留守巡逻员"
		"supply_record": return "第二段 · 查看院中的补给记录，确认两条回收路线"
		"aid_bag": return "第二段 · 绕过北侧残墙，取回专用急救包"
		"repair_tools": return "第二段 · 走南侧路径，取回修理工具"
		"survey_marker": return "第三段 · 到前哨院中的勘察点，亲自核查现场"
		"ecology":
			if not evidence("site_surveyed"): return "第三段 · 到%s据点明确调查；现状待到场确认" % ledger()["target"]["species"]
			if ledger()["choice"] == "hunt":
				if not _hunt_possible(_current_facts()): return "第三段 · 族群或路线已变化，回已调查巢址重新核查；猎杀%d/2保留" % mini(ledger()["kills"].size(), 2)
				return "第三段 · 真实有限狩猎%d/2，寻找已核实族群，保留巢穴与幸存个体" % mini(ledger()["kills"].size(), 2)
			if ledger()["choice"] == "ransack": return "第三段 · 实际捣毁目标巢穴，暂时抑制繁衍；幸存个体不清除"
			return "第三段 · 选择当前可行的有限狩猎或暂时捣巢"
		_: return "第三段 · 到倒下的路标旁亲手修复，启用前哨检查点"

## 章节计数保留原合同，界面另用正在执行的一组动作计数。
func step_progress() -> String:
	if not Data.investigation_done(ledger()):
		return "调查 %d/2" % (int(evidence("patrol_read")) + int(evidence("entrance_read")))
	if not Data.rescue_done(ledger()):
		var count := 0
		for key: String in ["wounded_found", "supply_read", "aid_taken", "rescued", "tools_taken"]:
			count += int(evidence(key))
		return "救援 %d/5" % count
	if not Data.has_ecology_result(ledger()) and ledger().get("choice", "") == "hunt":
		return "狩猎 %d/2" % mini(ledger().get("kills", []).size(), 2)
	return "修复 %d/2" % (int(Data.has_ecology_result(ledger())) + int(evidence("signpost_repaired")))

func next_action() -> String:
	if ledger().get("stage", "") == "completed": return "与前哨巡守交谈，了解下一处线索"
	if ledger().get("stage", "") == "claim": return "到前哨路标领取修复尾款"
	if _searching: return "正在核对可达的生态线索"
	match _target_object():
		"patrol_record": return "沿旧道阅读巡逻记录"
		"entrance_record": return "到前哨入口阅读入口草图"
		"wounded_patrol": return "回到巡逻员旁救治" if evidence("wounded_found") else "到西侧棚屋查看巡逻员"
		"supply_record": return "阅读院中的补给记录"
		"aid_bag": return "到北侧废棚取急救包"
		"repair_tools": return "到南侧拐角取修理工具"
		"survey_marker": return "到院中勘察点核查现场"
		"ecology": return objective().trim_prefix("第三段 · ")
	return "到前哨路标旁修复"

func snapshot() -> Dictionary:
	if ledger().is_empty(): return {}
	var t := target()
	var pos: Vector2 = t.get("position", Vector2.INF)
	var reward := Data.reward("restoration", ledger()["legacy_reserved"])
	var view := {"id": Data.ID, "landmark_id": Legacy.LANDMARK, "kind": "outpost", "title": Data.TITLE,
		"giver": "留守巡逻员", "need": 3, "progress": (1 if Data.investigation_done(ledger()) else 0) + (1 if Data.rescue_done(ledger()) else 0) + (1 if evidence("signpost_repaired") else 0),
		"claim_at_npc": true, "chapter_stage": ledger()["stage"], "ui_state": "claimable" if ledger()["stage"] == "claim" else "in_progress",
		"ui_status": "尾款待领取" if ledger()["stage"] == "claim" else "前哨章节", "ui_objective": objective(),
		"next_action": next_action(), "target_title": t.get("name", ""), "step_progress": step_progress(),
		"ui_reward": reward_policy(), "gold": reward["gold"], "xp": reward["xp"], "bonus": reward["bonus"],
		"target_object_id": t.get("object_id", ""), "target_name": t.get("name", ""), "target_pos": [pos.x, pos.y] if pos.is_finite() else [],
		"species": t.get("species", ""), "hunt_region": t.get("region_id", ""), "target_instance_ids": t.get("target_instance_ids", []),
		"ui_guide_mode": t.get("guide_mode", "object"), "ui_target_label": t.get("knowledge_label", t.get("name", "")),
		"ui_knowledge": t.get("knowledge", "unknown"), "history": history_text(), "live_facts": live_text()}
	return view

func npc_status() -> Dictionary:
	if ledger().get("stage", "") == "completed": return {"state": "completed", "marker": "✓ 前哨已恢复", "color": QuestPresentation.COMPLETED_COLOR}
	return {"state": "in_progress" if is_active() else "available", "marker": "· 失联前哨进行中" if is_active() else "! 失联的前哨", "color": QuestPresentation.PROGRESS_COLOR if is_active() else QuestPresentation.AVAILABLE_COLOR}

func history_text() -> String:
	return "记录：" + "；".join(ledger().get("history", []))

func receipt_text() -> String:
	return "✓ 失联的前哨已完成 · " + reward_policy() + " · " + str(ledger().get("next_clue", ""))

func _on_object_interaction(id: String) -> void:
	EventBus.npc_dialogue.emit(object_payload(id))

func _on_action(action: String) -> void:
	if not action.begins_with("outpost:"): return
	var id := action.trim_prefix("outpost:")
	var message := ""
	match id:
		"accept", "resume": message = accept()
		"menu": EventBus.npc_dialogue.emit(offer("营地巡守"))
		"status": EventBus.npc_dialogue.emit({"kind": "info", "giver": "前哨记录", "text": objective() + "\n" + history_text()})
		"legacy":
			var manager := get_parent()
			EventBus.npc_dialogue.emit(manager.call("legacy_camp_offer", "营地巡守"))
		"investigate": message = investigate()
		"choose_hunt": message = choose("hunt")
		"choose_ransack": message = choose("ransack")
		"find_hunt_clue": message = find_hunt_clue()
		_: message = object_action(id)
	if not message.is_empty(): EventBus.hint_requested.emit(message)

func _on_tick(_summary: Dictionary) -> void:
	if not is_active(): return
	if ledger().get("stage", "") == "ecology": _targets._process(0.0)
	var before := str(ledger()["stage"])
	_sync_legacy()
	if before != ledger()["stage"]: _save()
	else: changed.emit()

func _at_object(id: String) -> bool:
	for object: Node in get_tree().get_nodes_in_group("outpost_objects"):
		if object is Node2D and str(object.get("outpost_id")) == id and (object as Node2D).is_visible_in_tree():
			if object.has_method("can_interact") and not bool(object.call("can_interact")): return false
			return _near_position((object as Node2D).global_position, OBJECT_DISTANCE)
	return false

func _on_site() -> bool:
	var t: Dictionary = ledger().get("target", {})
	return not t.is_empty() and _targets.valid_site(t) and _near_position(_targets.site_position(t), SITE_DISTANCE)

func _near_position(pos: Vector2, distance: float) -> bool:
	var player := _player()
	if player == null or not player.is_visible_in_tree() or player.global_position.distance_to(pos) > distance: return false
	var delta := pos - player.global_position
	var steps := maxi(1, ceili(delta.length() / 12.0))
	for i in range(1, steps + 1):
		if ObstacleField.nav_blocked_at(player.global_position + delta * float(i) / float(steps)): return false
	var ray := PhysicsRayQueryParameters2D.create(player.global_position, pos, 1)
	if player is CollisionObject2D: ray.exclude = [(player as CollisionObject2D).get_rid()]
	return player.get_world_2d().direct_space_state.intersect_ray(ray).is_empty()

func _player() -> Node2D:
	return get_tree().get_first_node_in_group("player") as Node2D

func _position(target_data: Dictionary) -> Vector2:
	var pos: Array = target_data.get("pos", [0.0, 0.0])
	return Vector2(float(pos[0]), float(pos[1]))

func _object_name(id: String) -> String:
	return {"patrol_record": "沿途巡逻记录", "entrance_record": "前哨入口草图", "wounded_patrol": "留守巡逻员", "supply_record": "补给记录", "aid_bag": "专用急救包", "repair_tools": "修理工具", "survey_marker": "前哨勘察点", "signpost": "前哨路标"}.get(id, "前哨线索")

func _next_clue() -> String:
	var here: SimRegion = WorldSim.sim.region_of_point(Layout.center()) if WorldSim.sim != null else null
	if here != null:
		for id: String in here.neighbor_ids:
			var region: SimRegion = WorldSim.sim.get_region(id)
			if region != null and region.terrain != here.terrain:
				var d: Vector2 = region.center - Layout.center()
				var direction := ("东" if d.x >= 0 else "西") + ("南" if d.y >= 0 else "北")
				return "后续线索：前哨%s方向有%s，可继续探索当地生态；这只是区域线索，未确认远处的当前状态。" % [direction, region.display_name]
	return "后续线索：前哨外的邻近区域还有新的巡逻路线，可以自由探索；远处现状尚未确认。"

func _note(text: String) -> void:
	if not text in ledger()["history"]: ledger()["history"].append(text)

func _save() -> void:
	Data.refresh_stage(ledger())
	_targets.set_process(is_active() and ledger().get("stage", "") == "ecology")
	if not is_active() or ledger().get("stage", "") != "ecology":
		if _searching: _search_generation += 1
		_targets.clear_proofs()
	GameState._invalidate_world_save_cache()
	GameState._queue_save()
	EventBus.outpost_state_changed.emit(visual_state())
	changed.emit()
