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

## 完章后的交谈与回营只保留指引，不重开章节或增加任务前置。
func guidance_pending() -> bool:
	if ledger().get("stage", "") != "completed": return false
	if not evidence("next_clue_received"): return true
	return not GameState.campaign_quest.get("quests", {}).get("watch_c2_forest:s1", {}).get("accepted", false)

func evidence(key: String) -> bool:
	return ledger().get("evidence", {}).get(key, false)

func visual_state() -> Dictionary:
	var state: Dictionary = ledger().get("evidence", {}).duplicate(true)
	state["evidence"] = ledger().get("evidence", {}).duplicate(true)
	state["stage"] = ledger().get("stage", "")
	state["active"] = is_active()
	state["id"] = Data.ID
	state["target_object_id"] = _target_object() if (is_active() or guidance_pending()) and GameState.tracked_quest_id == Data.ID else ""
	state["object_states"] = {}
	for id: String in Layout.OBJECTS:
		var key := str({"patrol_record":"patrol_read", "entrance_record":"entrance_read", "supply_record":"supply_read", "aid_bag":"aid_taken", "repair_tools":"tools_taken"}.get(id, ""))
		if not key.is_empty() and evidence(key): state["object_states"][id] = "read" if key.ends_with("read") else "taken"
	if evidence("signpost_repaired"):
		state["object_states"]["signpost"] = "claimed" if ledger().get("receipts", {}).get("restoration", {}).get("paid", false) else "ready"
	return state

func offer(giver: String = "营地巡守") -> Dictionary:
	var text := "前哨的人一直没来取药。上回见他，腿伤还没好。\n我得守着营地。你能沿旧道去看看，他还在不在吗？"
	var questions: Array = [{"label": "最后在哪里见过他？", "answer": "去前哨的旧道上。他总把巡逻札记带在身边；沿路留意有没有落下的纸页。"}]
	var q := ledger()
	var action := "accept" if q.is_empty() else "resume"
	var label := "我去看看" if q.is_empty() else "继续寻找"
	if q.get("stage", "") == "completed":
		text = "他还守在前哨，路标也重新立起来了。这条路总算又有人照看。\n回去向他报个平安，也听听他接下来的打算。"
		questions = []
		action = "status"
		label = "查看前哨记录"
	elif is_active():
		text = "还没见到他吗？沿旧道慢慢找，别漏了路边的痕迹。" if not evidence("wounded_found") else ("你找到他了。先把伤照料好，路上的事以后再说。" if not evidence("rescued") else "他能重新站起来就好。前哨还有什么需要帮忙的，听听他的打算。")
		questions = [{"label": "接下来去哪里？", "answer": next_action()}]
		action = "status"
		label = "查看当前线索"
	var payload := {"kind": "quest", "giver": giver, "state": "available", "confirm_text": label, "text": text,
		"questions": questions, "rules": reward_policy(),
		"quest": {"id": Data.ID, "kind": "outpost", "title": Data.TITLE, "giver": giver, "need": 3, "progress": 0}}
	if Data.valid_legacy(GameState.camp_quest):
		payload["kind"] = "camp_choice"
		payload["origin"] = WorldConfig.spawn_pos()
		payload["options"] = [{"label": label, "action": "outpost:" + action, "enabled": true,
			"consequence": "沿现有线索继续寻找前哨", "risk": "可以暂时离开，已做过的事会保留"},
			{"label": "原营地调查 / 交付", "action": "outpost:legacy", "enabled": true,
				"consequence": "继续此前的调查，或领取已完成的报酬", "risk": "原委托的目标与报酬不变"}]
	elif action == "status":
		payload["kind"] = "info"
	return payload

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
	var reserved := Data.valid_legacy(GameState.camp_quest) if ledger().is_empty() else bool(ledger().get("legacy_reserved", false))
	if reserved:
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
		return {"kind": "info", "text": "走到物件旁再查看，墙后看不清这里的情况"}
	if ledger().is_empty():
		return {"kind": "info", "text": "这里留有巡逻的痕迹。营地巡守或许知道是谁留下的。"}
	if not is_active() and ledger().get("stage", "") != "completed":
		return {"kind": "camp_action", "action": "outpost:resume", "confirm_text": "继续寻找", "text": "前哨的事还没办完。要沿之前的线索继续吗？", "origin": Layout.object_position(id)}
	# 走错顺序仍可查看场景，但不提前讲出尚未发现的人、物与后续工作。
	if not object_state(id).get("known", false):
		return {"kind": "info", "giver": _object_name(id), "text": "这里似乎也有线索。先弄清手头的发现：" + next_action()}
	var text := ""
	var confirm := "记下线索"
	var questions: Array = []
	var rules := ""
	match id:
		"patrol_record":
			text = "纸页被露水浸皱，末行的字写得很急：『腿又疼了。先回前哨。』\n后面没有新的日期。旧道还向前延伸。"
			confirm = "循旧道去前哨"
		"entrance_record":
			text = "门前的泥里有一道拖痕，夹着几点暗红，朝院内延伸。\n正门堵着碎岩；沿西侧残墙走，能看见一个缺口。"
			confirm = "沿拖痕寻找巡守"
			questions = [{"label": "从哪里进去？", "answer": "敲碎正门的碎岩可以直走；也能绕到西侧缺口，沿残墙进入。两边都要留意附近的怪物。"}]
		"wounded_patrol":
			if evidence("signpost_repaired"):
				text = "你看，路标又立起来了。下个走过来的人，总算不会再错过这道门。\n我留在这里。还有一句话，想托你带回营地。"
				confirm = "听听后续线索"
				questions = [{"label": "你还要留在这里？", "answer": "『走散的人认得这道门。我守着，至少他们回来时，不会只看见一间空屋。』"}]
			elif evidence("rescued"):
				text = "好多了……绷带扎得很稳。\n门口的路标倒了，后来的人也会走岔。南侧拐角还放着前哨维修工具，帮我取来吧。" if not evidence("tools_taken") else "工具也找到了。动手立路标前，得看看附近的巢址；别让后来的人毫无防备地走过去。"
				questions = [{"label": "附近的巢要怎么处理？", "answer": "先看清楚再决定。少猎几只能让路好走些，也可以暂时毁巢。别以为巢倒了，周围的怪物就都没了。"}]
			elif not evidence("wounded_found"):
				text = "巡守按住腿上的破布，抬眼看向你。\n『营地来的？……先别扶我。巡守急救包还在补给区。院里的清单记着位置，替我找来。』"
				confirm = "我去找急救包"
				questions = [{"label": "你怎么伤成这样？", "answer": "『腿撑不住，最后一段是拖着回来的。先把血止住……别的等会儿再说。』"}]
			elif evidence("aid_taken"):
				text = "『是这个红结……打开吧，干净的绷带在最上面。』\n巡守松开压着伤口的手，等你包扎。"
				confirm = "用巡守急救包包扎"
				rules = "使用已取回的巡守急救包；不消耗背包里的普通药品。"
			else:
				text = "『补给区清单就在院里。照着找，急救包在东侧补给架北端，系着红结。』"
				confirm = "记住急救包的位置"
		"supply_record":
			text = "补给区清单上，『巡守急救包』一行被红圈勾出：东侧补给架北端。\n纸角压在木箱下，没有被风吹走。"
			confirm = "记下急救包位置"
			if evidence("rescued"):
				text += "\n下方还记着：前哨维修工具，南侧拐角。"
		"aid_bag":
			text = "巡守急救包的红结还没解开，里面能摸到卷好的绷带。\n伤员还在西侧棚屋等着。"
			confirm = "拿起巡守急救包"
			rules = "任务物件单独保管，不占普通补给上限；带回受伤的前哨巡守身旁使用。"
		"repair_tools":
			text = "前哨维修工具裹在旧布里：锤子、木钉，还有一副路标支架。"
			if evidence("rescued"): text += "\n巡守说，立路标前还得看看附近的巢址。"
			confirm = "拿起前哨维修工具"
			rules = "任务物件单独保管，不占普通补给上限。救援并完成现场调查后，可在路标处修复。"
		"survey_marker":
			text = "前哨观测点正对院外的小路。地上新旧足迹交错，得再看看附近有没有活跃的巢。"
			confirm = "观察周边痕迹"
			rules = "根据当前可达的现场继续调查；没有可行处理对象时，可凭实地勘察继续修复。"
		"signpost":
			if evidence("signpost_repaired"):
				text = "前哨路标稳稳立在路口，箭头又指向旧道。巡守在棚屋旁朝这边招了招手。"
				confirm = "领取修复报酬"
				rules = "前哨检查点已启用。" + ("修复尾款待领取；背包放不下的补给会存入背包→待领取。" if ledger()["stage"] == "claim" else "修复奖励已领取。")
			elif not evidence("rescued"):
				text = "损坏的前哨路标斜倒在地，木钉从支架里脱出。院内的拖痕更值得留意。"
				confirm = "检查损坏处"
			else:
				text = "支架还在，木板也没裂。把前哨维修工具带来，就能让这条路重新有个方向。"
				confirm = "修复前哨路标"
				rules = "先取回维修工具并调查附近巢址。修复后启用前哨检查点。"
		_:
			return {"kind": "info", "text": "这里没有可查看的前哨线索"}
	var state := object_state(id)
	var payload := {"kind": "camp_action", "action": "outpost:" + id, "giver": _object_name(id),
		"origin": Layout.object_position(id), "confirm_text": confirm, "text": text, "questions": questions, "rules": rules}
	if id == "wounded_patrol" and not evidence("signpost_repaired") and evidence("wounded_found") and (evidence("rescued") or not evidence("aid_taken")):
		payload["kind"] = "info"
	if id == "signpost" and not evidence("signpost_repaired") and not (Data.rescue_done(ledger()) and Data.has_ecology_result(ledger())):
		payload["kind"] = "info"
	if bool(state.get("done", false)) and id != "wounded_patrol" and not (id == "signpost" and ledger().get("stage", "") == "claim"):
		payload["kind"] = "info"
		payload["text"] = ("已读 · " if id.ends_with("record") else "已完成 · ") + text
	return payload

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
		"patrol_record": changed_evidence = "patrol_read"; message = "札记到这里就断了；沿旧道去前哨看看"
		"entrance_record":
			if not evidence("patrol_read"): return "先沿旧道找到遗落的巡逻札记"
			changed_evidence = "entrance_read"; message = "拖痕通向院内：敲开正门碎岩或绕西侧缺口，到棚屋找人"
		"wounded_patrol":
			if not evidence("entrance_read"): return "先调查门前的拖行痕迹"
			if evidence("signpost_repaired"):
				changed_evidence = "next_clue_received"; message = str(q.get("next_clue", _next_clue()))
			elif not evidence("wounded_found"):
				changed_evidence = "wounded_found"; message = "巡守还活着。去看补给区清单，替他找巡守急救包"
			elif evidence("rescued"): return "巡守的伤已经包扎好 · " + objective()
			elif not evidence("aid_taken"): return "先找回巡守急救包，再来替他包扎"
			else:
				changed_evidence = "rescued"
				message = "巡守：好多了。我还以为，这条路已经没人走了。"
				message += "工具也带来了？先看看附近的巢址，再把路标立起来吧。" if evidence("tools_taken") else "南侧拐角有前哨维修工具，帮我取来吧。"
		"supply_record":
			if not evidence("wounded_found"): return "先去西侧棚屋看看受伤的前哨巡守"
			changed_evidence = "supply_read"; message = "清单写着：巡守急救包在东侧补给架北端"
		"aid_bag", "repair_tools":
			if not evidence("supply_read"): return "先查看补给区清单，核对这件物品"
			changed_evidence = "aid_taken" if id == "aid_bag" else "tools_taken"
			message = "拿到巡守急救包了，回西侧棚屋替巡守包扎" if id == "aid_bag" else "拿到前哨维修工具了"
		"survey_marker":
			return investigate(true)
		"signpost":
			if evidence("signpost_repaired"):
				return claim()
			if not Data.rescue_done(q): return "先救治前哨巡守，再带来前哨维修工具"
			_sync_legacy()
			if not Data.has_ecology_result(q): return "先调查附近巢址，再回来立路标"
			changed_evidence = "signpost_repaired"; message = "路标重新立起来了，前哨检查点已启用。去和前哨巡守说一声吧"
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
	return "修复报酬已领取 · 与前哨巡守交谈" if ledger()["receipts"]["restoration"]["paid"] else "修复尾款仍待领取，请重新确认；背包放不下的补给会存入背包→待领取"

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
		"action": "outpost:investigate", "label": "调查巢址", "target_id": str(ledger().get("target", {}).get("key", "survey_marker"))}

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
	return "已记下巢边足迹，正在查看能否接近附近族群"

func choice_payload() -> Dictionary:
	var f := _current_facts()
	var remaining := maxi(0, 2 - ledger().get("kills", []).size())
	var hunt: bool = f["nest_active"] and int(f["viable_count"]) >= remaining + 1
	var nest: bool = f["nest_active"] and int(f["viable_count"]) > 0
	var payload := {"kind": "camp_choice", "giver": "巢址旁的发现", "origin": _position(ledger()["target"]),
		"text": "新鲜足迹从巢边散向小路。已有狩猎%d/2。\n%s\n让这段路好走些，你打算怎么做？" % [mini(ledger()["kills"].size(), 2), live_text()],
		"options": [{"label": "有限狩猎", "action": "outpost:choose_hunt", "enabled": hunt,
			"disabled_reason": "当前存量不足以保留至少一只，可改选捣巢或重新核查", "consequence": "再猎杀%d只，保留巢穴与幸存族群" % remaining, "risk": "巢穴仍会繁衍，今后还可能出现新的个体"},
			{"label": "暂时捣巢", "action": "outpost:choose_ransack", "enabled": nest,
			"disabled_reason": "没有有效巢穴或可应对存活个体", "consequence": "暂停当地繁衍120刻", "risk": "存活怪物不会被清除，附近同族狂怒60秒；巢穴会重建"},
			{"label": "重新核查现场", "action": "outpost:investigate", "enabled": true, "utility": true,
			"consequence": "保留已有行动，记录变化", "risk": "再看看足迹与巢穴，原有行动保留"}]}

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
	EventBus.hint_requested.emit("周边调查已有结果 · 带工具修复损坏的前哨路标")

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
	if f.is_empty(): return "附近的情况还没看清，需要到场调查"
	var nest_text := "眼前巢穴活跃" if f.get("nest_active", false) else ("眼前巢穴已毁" if f.get("nest_visible", false) else "巢址当前不在视野内")
	return "眼前可见%d只；%s。视野外的情况还不清楚。" % [f["visible_count"], nest_text]

func target() -> Dictionary:
	if not is_active() and not guidance_pending(): return {}
	var id := _target_object()
	if id == "home:patrol":
		for npc: Node in get_tree().get_nodes_in_group("npcs"):
			if npc is Node2D and npc.get("landmark_id") == "camp_ecology" and npc.get("quest_kind") == "outpost":
				return {"position": npc.global_position, "kind": "outpost", "object_id": id, "name": "营地巡守",
					"species": "", "region_id": "", "knowledge": "npc_intel", "live_facts": {}}
		return {}
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
	if ledger().get("stage", "") == "completed": return "home:patrol" if evidence("next_clue_received") else "wounded_patrol"
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
	return next_action()

func step_progress() -> String:
	if ledger().get("stage", "") == "completed": return "后续线索"
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
	if ledger().is_empty(): return "与营地巡守交谈，询问失联的前哨"
	if ledger().get("stage", "") == "completed": return "回营地与营地巡守交谈，询问林地路书" if evidence("next_clue_received") else "与前哨巡守交谈，了解后续线索"
	if ledger().get("stage", "") == "claim": return "到前哨路标领取修复报酬"
	if _searching: return "正在寻找附近可达的巢址线索"
	match _target_object():
		"patrol_record": return "沿旧道寻找遗落的巡逻札记"
		"entrance_record": return "调查门前的拖行痕迹"
		"wounded_patrol": return "把巡守急救包带给受伤的前哨巡守" if evidence("wounded_found") else "沿拖痕到西侧棚屋寻找受伤的前哨巡守"
		"supply_record": return "查看院内的补给区清单"
		"aid_bag": return "到东侧补给架北端寻找巡守急救包"
		"repair_tools": return "到南侧拐角取回前哨维修工具"
		"survey_marker": return "到前哨观测点观察周边痕迹"
		"ecology":
			var species := str(ledger()["target"]["species"])
			if not evidence("site_surveyed"): return "到%s据点调查巢址" % species
			if ledger()["choice"] == "hunt":
				if not _hunt_possible(_current_facts()): return "回%s巢址重新核查，已有狩猎%d/2保留" % [species, mini(ledger()["kills"].size(), 2)]
				return "狩猎%s %d/2，保留巢穴与至少一只幸存个体" % [species, mini(ledger()["kills"].size(), 2)]
			if ledger()["choice"] == "ransack": return "捣毁%s巢穴，留意附近幸存怪物" % species
			return "在%s巢址选择有限狩猎或暂时捣巢" % species
	return "带工具修复损坏的前哨路标"

func snapshot() -> Dictionary:
	if ledger().is_empty(): return {}
	var t := target()
	var pos: Vector2 = t.get("position", Vector2.INF)
	var reward := Data.reward("restoration", ledger()["legacy_reserved"])
	var view := {"id": Data.ID, "landmark_id": Legacy.LANDMARK, "kind": "outpost", "title": Data.TITLE,
		"giver": "前哨巡守", "need": 3, "progress": (1 if Data.investigation_done(ledger()) else 0) + (1 if Data.rescue_done(ledger()) else 0) + (1 if evidence("signpost_repaired") else 0),
		"claim_at_npc": true, "chapter_stage": ledger()["stage"], "ui_state": "claimable" if ledger()["stage"] == "claim" else "in_progress",
		"ui_status": "尾款待领取" if ledger()["stage"] == "claim" else "前哨章节", "ui_objective": objective(),
		"next_action": next_action(), "target_title": t.get("name", ""), "step_progress": step_progress(),
		"ui_reward": reward_policy(), "gold": reward["gold"], "xp": reward["xp"], "bonus": reward["bonus"],
		"target_object_id": t.get("object_id", ""), "target_name": t.get("name", ""), "target_pos": [pos.x, pos.y] if pos.is_finite() else [],
		"species": t.get("species", ""), "hunt_region": t.get("region_id", ""), "target_instance_ids": t.get("target_instance_ids", []),
		"ui_guide_mode": t.get("guide_mode", "object"), "ui_target_label": t.get("knowledge_label", t.get("name", "")),
		"ui_knowledge": t.get("knowledge", "unknown"), "history": history_text(), "live_facts": live_text(), "rules": _journal_rules()}
	if ledger().get("stage", "") == "completed":
		view["ui_state"] = "completed"
		view["ui_status"] = "前哨已恢复"
		view["claim_at_npc"] = false
		view["can_abandon"] = false
		view["guidance_pending"] = guidance_pending()
	return view

func _journal_rules() -> String:
	var rules := "可暂停后继续，已调查的线索与已获得的物件会保留。"
	if evidence("wounded_found"): rules += "\n巡守急救包与维修工具单独保管，不占普通补给上限；救援只使用任务急救包。"
	if Data.rescue_done(ledger()): rules += "\n有限狩猎需击杀2只并保留巢穴及至少1只幸存个体；暂时捣巢抑制繁衍120刻，附近同族狂怒60秒，幸存怪物仍在。"
	if evidence("signpost_repaired"): rules += "\n前哨检查点已启用；修复报酬中放不下的补给进入背包→待领取。"
	return rules

func npc_status() -> Dictionary:
	if ledger().get("stage", "") == "completed": return {"state": "completed", "marker": "✓ 前哨已恢复", "color": QuestPresentation.COMPLETED_COLOR}
	return {"state": "in_progress" if is_active() else "available", "marker": "· 失联前哨进行中" if is_active() else "! 失联的前哨", "color": QuestPresentation.PROGRESS_COLOR if is_active() else QuestPresentation.AVAILABLE_COLOR}

func history_text() -> String:
	return "记录：" + "；".join(ledger().get("history", []))

func receipt_text() -> String:
	return "✓ 失联的前哨已完成 · " + next_action()

func _on_object_interaction(id: String) -> void:
	EventBus.npc_dialogue.emit(object_payload(id))

func _on_action(action: String) -> void:
	if not action.begins_with("outpost:"): return
	var id := action.trim_prefix("outpost:")
	var prior_evidence: Dictionary = ledger().get("evidence", {}).duplicate(true)
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
	if not message.is_empty():
		var earned_story := false
		for key: String in ["rescued", "signpost_repaired", "next_clue_received"]:
			if evidence(key) and not prior_evidence.get(key, false): earned_story = true
		if earned_story and not GameState.dialogue_open:
			# 只读回响：故事已经由原动作入账，继续/返回都不会再次执行它。
			EventBus.npc_dialogue.emit({"kind": "story_result", "giver": _object_name(id), "text": message,
				"confirm_text": "继续", "origin": Layout.object_position(id)})
		else:
			EventBus.hint_requested.emit(message)

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
	if id == "wounded_patrol" and evidence("rescued"): return "前哨巡守"
	if id == "signpost" and evidence("signpost_repaired"): return "前哨路标"
	return str(Layout.OBJECTS.get(id, {}).get("title", "前哨线索"))

func _next_clue() -> String:
	var here: SimRegion = WorldSim.sim.region_of_point(Layout.center()) if WorldSim.sim != null else null
	if here != null:
		for id: String in here.neighbor_ids:
			var region: SimRegion = WorldSim.sim.get_region(id)
			if region != null and region.terrain != here.terrain:
				var d: Vector2 = region.center - Layout.center()
				var direction := ("东" if d.x >= 0 else "西") + ("南" if d.y >= 0 else "北")
				return "回营地找营地巡守，他有通往林地联络站的旧路书。替我告诉那边的人：前哨又有人守着了。\n往前哨%s走是%s；那边的现状，还得亲自去看看。" % [direction, region.display_name]
	return "回营地找营地巡守，他有通往林地联络站的旧路书。替我告诉那边的人：前哨又有人守着了。"

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
