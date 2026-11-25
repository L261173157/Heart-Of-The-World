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

func offer(giver: String = "营中巡守周照") -> Dictionary:
	var text := "周照把一纸委托推到你面前。「少侠从前替人捎过附近的短途信，脚力我信得过。这趟算我雇你，工钱不会短了你的，路也要走得远些。\n石安许久没来取药，我心里放心不下。营里离不开人，烦你沿旧道走一遭，看他可还安在。」"
	var questions: Array = [{"label": "最后在哪里见过石安？", "answer": "「去哨所的旧道上。他总带着一本巡守手札；沿路留意有没有落下的纸页。先找到人，别的差事不急。」"}, {"label": "这趟差事要走多远？", "answer": "「先到哨所。往后走多远，少侠自己拿主意。我只盼出门的人，都平平安安回来。」"}]
	var q := ledger()
	var action := "accept" if q.is_empty() else "resume"
	var label := "我去看看" if q.is_empty() else "继续寻找"
	if q.get("stage", "") == "completed":
		text = "他还守在哨所，路标也重新立起来了。这条路总算又有人照看了。\n回去向他报个平安，也听听他往后的打算。"
		questions = []
		action = "status"
		label = "察看哨所记录"
	elif is_active():
		text = "还没见着他么？沿旧道慢慢找，别漏了路边的痕迹。" if not evidence("wounded_found") else ("你寻见他了。先把伤照料好，路上的事往后再说。" if not evidence("rescued") else "他能重新站起来就好。哨所还有什么要帮忙的，听听他的打算。")
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
			"consequence": "沿着眼下的线索接着寻哨所", "risk": "可以暂时离开，做过的事都会留着"},
			{"label": "原营地调查 / 交付", "action": "outpost:legacy", "enabled": true,
				"consequence": "继续此前的调查，或领取已完成的报酬", "risk": "原委托的目标与报酬不变"}]
	elif action == "status":
		payload["kind"] = "info"
	return payload

func accept() -> String:
	if ledger().get("stage", "") == "completed":
		return "哨所已复原，从前做过的事与领过的赏不会重来"
	if ledger().is_empty():
		GameState.outpost_quest = Data.create(GameState.camp_quest)
		if ledger()["legacy_reserved"]:
			_note("原调查奖励仍留在旧委托里，本章不重复另发")
	else:
		ledger()["active"] = true
	GameState.tracked_quest_id = Data.ID
	_sync_legacy()
	_save()
	_ensure_target()
	return "已接下：哨音久绝 · " + objective()

func abandon() -> String:
	if not is_active(): return ""
	ledger()["active"] = false
	_search_generation += 1
	_roster_ready = false
	_targets.clear_proofs()
	_save()
	return "哨所一节暂且搁下，专用物件、救人的经过和领赏的凭据都留着"

func reward_policy() -> String:
	var reserved := Data.valid_legacy(GameState.camp_quest) if ledger().is_empty() else bool(ledger().get("legacy_reserved", false))
	if reserved:
		return "原调查奖励仍照原先巢边的规矩，在旧委托处领取，本章不重复另发"
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
		return {"kind": "info", "text": "走到物件跟前再看，隔着墙看不真切"}
	if ledger().is_empty():
		return {"kind": "info", "text": "这里留有巡守走过的痕迹。营中巡守周照兴许知道是谁留下的。"}
	if not is_active() and ledger().get("stage", "") != "completed":
		return {"kind": "camp_action", "action": "outpost:resume", "confirm_text": "继续寻找", "text": "哨所的事还没办完。要接着照先前的线索找下去么？", "origin": Layout.object_position(id)}
	# 走错顺序仍可查看场景，但不提前讲出尚未发现的人、物与后续工作。
	if not object_state(id).get("known", false):
		return {"kind": "info", "giver": _object_name(id), "text": "这里似乎也有线索。先把手头的发现弄明白：" + next_action()}
	var text := ""
	var confirm := "记下线索"
	var questions: Array = []
	var rules := ""
	match id:
		"patrol_record":
			text = "纸页叫露水浸得发皱，末行的字写得很急：『腿又疼了。先回哨所。』\n后头再没有新的日期。旧道还往前伸着。"
			confirm = "循旧道去哨所"
		"entrance_record":
			text = "门前泥里有一道拖痕，夹着几点暗红，一直延到院里。\n正门叫碎岩堵着；沿西边残墙走，能看见一个缺口。"
			confirm = "沿拖痕寻找巡守"
			questions = [{"label": "从哪里进去？", "answer": "敲碎正门的碎岩可以直走；也能绕到西边缺口，沿着残墙进去。两条路都要留神近旁的怪物。"}]
		"wounded_patrol":
			if evidence("signpost_repaired"):
				text = "石安摸了摸路标的底座，才朝你点头。「稳当。俺从前做石匠，最怕给人留个虚底。\n你吃过饭没？俺还守在这儿，晚来的人认得这道门。替俺给周照带句话。」"
				confirm = "听听后续线索"
				questions = [{"label": "你还要守在这儿？", "answer": "『这道门总要有人认得。俺还守得动，你把远路接起来，回来讲给俺听听。』"}]
				if CampaignQuestData.effective_ending(GameState.campaign_quest) == CampaignQuestData.REUNION:
					text = "石安听完四人平安回到平原的消息，把椅子往门边挪了挪。\n『都回来了？好。灯能传话，人也有地方歇脚。哨所俺还守着。你头一回来的时候，俺连觉都不敢睡；如今总算能眯上一会儿。』"
					questions = [{"label": "路上会一路太平么？", "answer": "『哪有一路太平的路。临行看看天、看看脚印，备好补给。有人答应回来巡查，已经强过只剩一张旧图。』"}]
			elif evidence("rescued"):
				text = "好多了……绷带扎得真稳。" if not evidence("tools_taken") else "工具也寻着了。动手立路标之前，得看看近旁的巢穴；别叫后来的人毫无防备地走过去。"
				questions = [{"label": "附近的巢要怎么处理？", "answer": "先看明白了再定。少猎几只，路上能清净些；也可以暂且捣了巢。可别当巢一倒，四周的怪物就都没了。"}]
			elif not evidence("wounded_found"):
				text = "石安按住腿上的破布，抬眼望向你。\n『是周照叫你来的？……先别扶俺。巡守药囊还在物资处。院里的清单记着搁在哪儿，劳你替俺寻来。』"
				confirm = "俺去寻药囊"
				questions = [{"label": "你怎么伤成这样？", "answer": "『腿撑不住，末了那一段是拖着回来的。先把血止住……别的待会儿再说。』"}]
			elif evidence("aid_taken"):
				text = "『是这个红结……打开吧，干净绷带在最上头。』\n巡守松开压着伤口的手，等你包扎。"
				confirm = "用巡守药囊包扎"
				rules = "用的是取回的巡守药囊；不扣行囊里的寻常伤药。"
			else:
				text = "『物资清单就搁在院里。照着找，药囊在东边物资架的北头，系着红结。』"
				confirm = "记下药囊的位置"
		"supply_record":
			text = "物资清单上，『巡守药囊』一行叫红圈勾了出来：东边物资架的北头。\n纸角压在木箱底下，没叫风吹走。"
			confirm = "记下药囊位置"
			if evidence("rescued"):
				text += "\n下头还记着：哨所工具包，南边拐角。"
		"aid_bag":
			text = "巡守药囊的红结还没解开，里头摸得着卷好的绷带。\n伤员还在西边棚屋里等着。"
			confirm = "拿上巡守药囊"
			rules = "任务物件单独保管，不占寻常补给的上限；带回受伤的巡守石安身边用。"
		"repair_tools":
			text = "哨所工具包，裹在一块旧布里：一把锤子、几枚木钉，还有一副路标支架。"
			if evidence("rescued"): text += "\n巡守说了，立路标之前还得看看近旁的巢穴。"
			confirm = "拿上哨所工具包"
			rules = "任务物件单独保管，不占寻常补给的上限。救了人、看明白了近旁的光景之后，便可到路标处动手。"
		"survey_marker":
			text = "哨所瞭望处正对着院外的小路。地上新旧足迹交错，得再看看近旁还有没有活跃的巢穴。"
			confirm = "观察周边痕迹"
			rules = "照眼下走得到的地方接着察看；没有对得上的活物时，凭实地看过便可接着修路标。"
		"signpost":
			if evidence("signpost_repaired"):
				text = "哨所路标稳稳立在路口，箭头又指回了旧道。巡守在棚屋旁朝这边招了招手。"
				confirm = "领取修复报酬"
				rules = "哨所检查点已开启。" + ("修路标的尾款还没领；行囊装不下的补给，会存进行囊→待领取。" if ledger()["stage"] == "claim" else "修路标的赏已经领了。")
			elif not evidence("rescued"):
				text = "倒下的哨所路标斜在地上，木钉从支架里脱了出来。院里的拖痕更值得留意。"
				confirm = "检查损坏处"
			else:
				text = "支架还在，木板也没裂。把哨所工具包带来，便能让这条路重新有个方向。"
				confirm = "修好哨所路标"
				rules = "先取回工具包，再察看近旁的巢穴。修好之后，哨所检查点便开启。"
		_:
			return {"kind": "info", "text": "这里没有看得出的哨所线索"}
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
	if _mutating: return "正在记下这一回的行动"
	if not _at_object(id): return "请走到物件跟前再动手，隔着墙使不上力"
	if not is_active() and not (ledger().get("stage", "") == "completed" and id == "wounded_patrol"):
		return "先接下或接着办哨所这一节"
	var q := ledger()
	var e: Dictionary = q["evidence"]
	var message := ""
	var changed_evidence := ""
	match id:
		"patrol_record": changed_evidence = "patrol_read"; message = "手札到这里就断了；沿旧道去哨所看看"
		"entrance_record":
			if not evidence("patrol_read"): return "先沿旧道寻回道旁的手札"
			changed_evidence = "entrance_read"; message = "拖痕通到院里：敲开正门碎岩，或绕西边缺口，到棚屋里寻人"
		"wounded_patrol":
			if not evidence("entrance_read"): return "先察看门前的拖痕"
			if evidence("signpost_repaired"):
				changed_evidence = "next_clue_received"; message = str(q.get("next_clue", _next_clue()))
			elif not evidence("wounded_found"):
				changed_evidence = "wounded_found"; message = "巡守还活着。去看物资清单，替他寻巡守药囊"
			elif evidence("rescued"): return "巡守的伤已经包扎好 · " + objective()
			elif not evidence("aid_taken"): return "先寻回巡守药囊，再来替他包扎"
			else:
				changed_evidence = "rescued"
				message = "石安：好多了。俺还当这条路已经没人走了。"
				message += "工具也带来了？先看看近旁的巢穴，再把路标立起来吧。" if evidence("tools_taken") else "南边拐角放着哨所工具包，劳你替俺取来。"
		"supply_record":
			if not evidence("wounded_found"): return "先到西边棚屋里看看受伤的巡守石安"
			changed_evidence = "supply_read"; message = "清单上写着：巡守药囊在东边物资架的北头"
		"aid_bag", "repair_tools":
			if not evidence("supply_read"): return "先看物资清单，对一对这件物件"
			changed_evidence = "aid_taken" if id == "aid_bag" else "tools_taken"
			message = "拿到巡守药囊了，回西边棚屋替巡守包扎" if id == "aid_bag" else "拿到哨所工具包了"
		"survey_marker":
			return investigate(true)
		"signpost":
			if evidence("signpost_repaired"):
				return claim()
			if not Data.rescue_done(q): return "先救治巡守石安，再把哨所工具包带来"
			_sync_legacy()
			if not Data.has_ecology_result(q): return "先察看近旁的巢穴，再回来立路标"
			changed_evidence = "signpost_repaired"; message = "路标重新立起来了，哨所检查点已开启。去同哨所巡守石安说一声吧"
		_: return "不认识的哨所行动"
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
		return "路标还没修好"
	if not _at_object("signpost"): return "请到修好的路标旁领取尾款"
	if ledger()["receipts"]["restoration"]["paid"]: return "修路标的赏已经领了"
	_mutating = true
	GameState.begin_world_reward()
	_settle_ready(true)
	_save()
	GameState.end_world_reward()
	_mutating = false
	return "修路标的赏已领 · 同哨所巡守石安交谈" if ledger()["receipts"]["restoration"]["paid"] else "修路标的尾款还没领到，请再确认一回；行囊装不下的补给，会存进行囊→待领取"

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
			_note("沿用原调查的线索，出过的力都算数，再亲自到现场复核")
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
			_note("已到巢穴跟前记下变化，原先点名的那一族眼下没寻着对得上的活物；出过的力都算数")
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
		_note("已对上一处走得到的生态线索，仍须亲自到跟前往看：" + str(found["species"]))
	elif not after_survey and q.get("legacy_reserved", false) and _targets.site_position(GameState.camp_quest.get("target", {})).is_finite():
		# 原委托仍有已知线索：必须亲赴原现场复核，不能在前哨把远方线索伪记为到访。
		q["target"] = Data.target_data(GameState.camp_quest["target"])
		q["evidence"]["site_surveyed"] = false
		_note("没寻着新的对得上的去处，沿用原调查的线索，亲自到现场复核")
	elif after_survey:
		q["survey_confirmed"] = true
		_finish("survey")
		return
	_save()

func context() -> Dictionary:
	var on_site := _on_site()
	return {"on_site": on_site, "can_investigate": is_active() and ledger().get("stage", "") == "ecology" and on_site,
		"action": "outpost:investigate", "label": "察看巢穴", "target_id": str(ledger().get("target", {}).get("key", "survey_marker"))}

func investigate(at_marker: bool = false) -> String:
	if not is_active() or not Data.rescue_done(ledger()): return "先救巡守、取回工具包，再察看生态"
	_sync_legacy()
	if Data.has_ecology_result(ledger()): return "这一处的生态已有结果 · 到倒下的路标跟前动手修"
	if _searching: return "正在找走得通的路，可先在哨所里走动"
	var q := ledger()
	if q["target"].is_empty():
		if not at_marker or not _at_object("survey_marker"): return "请到哨所院里的勘察点，把眼前的光景记下来"
		if not _search_complete:
			_ensure_target()
			return "先对上走得到的生态线索，再到勘察点记下现场"
		q["evidence"]["site_surveyed"] = true
		_note("亲自在哨所勘察，重新对一遍眼下走得到、对得上的活物；不拿旧时的结果就断言此刻没有目标")
		_save()
		_select_target(true)
		return "已到跟前往看，正在重新对眼下的生态；没有对得上的活物时，照实地所见接着办"
	if not _on_site(): return "请先走到指明的生态据点，再到现场察看"
	q["evidence"]["site_surveyed"] = true
	if not q["target"]["key"] in q["surveys"]: q["surveys"].append(q["target"]["key"])
	_note("已亲自察看%s巢穴；周边的会四处巡猎，旧位置与线索，作不得眼下还剩多少的数" % q["target"]["species"])
	_save()
	_refresh_roster(true)
	return "已记下巢边的足迹，正在看能不能靠近近旁的那一族"

func choice_payload() -> Dictionary:
	var f := _current_facts()
	var remaining := maxi(0, 2 - ledger().get("kills", []).size())
	var hunt: bool = f["nest_active"] and int(f["viable_count"]) >= remaining + 1
	var nest: bool = f["nest_active"] and int(f["viable_count"]) > 0
	var payload := {"kind": "camp_choice", "giver": "巢址旁的发现", "origin": _position(ledger()["target"]),
		"text": "新鲜的足迹从巢边散向小路。已猎%d/2。\n%s\n要叫这一段路好走些，你打算怎么办？" % [mini(ledger()["kills"].size(), 2), live_text()],
		"options": [{"label": "留余狩猎", "action": "outpost:choose_hunt", "enabled": hunt,
			"disabled_reason": "眼下的数目留不出至少一只，可改选捣巢，或再看一遍", "consequence": "再猎%d只，留下巢穴和余下的族群" % remaining, "risk": "巢穴还会繁衍，日后兴许又冒出新的"},
			{"label": "暂时捣巢", "action": "outpost:choose_ransack", "enabled": nest,
			"disabled_reason": "没有管用的巢穴，或没有应付得了的活物", "consequence": "暂停当地繁衍120刻", "risk": "活着的怪物不会消失，近旁同族会狂怒60秒；巢穴还会重筑"},
			{"label": "再看一遍现场", "action": "outpost:investigate", "enabled": true, "utility": true,
			"consequence": "保留已有行动，记录变化", "risk": "再看看足迹与巢穴，原有行动保留"}]}

	if not hunt:
		payload["options"].append({"label": "寻别的狩猎线索", "action": "outpost:find_hunt_clue", "enabled": true, "utility": true,
			"consequence": "保留查探与猎杀的功劳，对一对别的走得到的据点", "risk": "不动眼下的族群；没有别的对得上的去处，便照已看过的现场修哨所"})
	return payload

func find_hunt_clue() -> String:
	if not is_active() or ledger().get("stage", "") != "ecology" or not evidence("site_surveyed") or not _on_site():
		return "先到现场察看，再对别的狩猎线索"
	if _searching: return "正在找别的走得通的线索"
	if _hunt_possible(_current_facts()): return "眼下留余狩猎还办得成，不必换线索"
	_note("眼下的数目不够留余狩猎又留下族群，可以选暂时捣巢")
	_save()
	_select_target(true)
	return "现场的记录与功劳都留着，正在找别的走得到的据点"

func _hunt_possible(f: Dictionary) -> bool:
	return f.get("nest_active", false) and int(f.get("viable_count", 0)) >= maxi(0, 2 - ledger().get("kills", []).size()) + 1

func choose(branch: String) -> String:
	if not is_active() or ledger().get("stage", "") != "ecology" or not evidence("site_surveyed") or not _on_site(): return "先走到真正的生态据点，再当面察看"
	if branch not in ["hunt", "ransack"]: return "不认识的处置法子"
	var f := _current_facts()
	if not f["nest_active"] or int(f["viable_count"]) <= 0: return "现场有了变化，请再看一遍"
	if branch == "hunt" and int(f["viable_count"]) < maxi(0, 2 - ledger()["kills"].size()) + 1: return "眼下的数目不够留余狩猎又留下族群，可以选暂时捣巢"
	ledger()["choice"] = branch
	_note("选择" + ("留余狩猎，留下巢穴" if branch == "hunt" else "暂时捣巢，保留幸存个体"))
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
	_note("亲手猎得：%s，累计%d只" % [species, q["kills"].size()])
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
	_note({"hunt": "留余狩猎已办成；那时巢穴与余下的族群都留着", "ransack": "暂时捣巢已动手；活着的怪物并未除尽", "survey": "现场已看过，没寻着稳妥又对得上的别的处置对象"}.get(outcome, "沿用了原调查当日的实情"))
	_carry_result_to_legacy()
	Data.refresh_stage(ledger())
	_save()
	EventBus.hint_requested.emit("近旁已察看明白 · 带上工具修好倒下的哨所路标")

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
			_note("沿用原营地调查当日的生态结果，不必重做；这不代表据点眼下还是老样子")
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
		var note := "哨所这边的行动也合了原先巢边的约定；说好的赏钱仍须回营地面交"
		if not note in old["history"]: old["history"].append(note)
	else:
		_note("哨所已另有了生态结果；原先那桩小委托仍照巢边的规矩办，说好的赏钱还没结")
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
	if f.is_empty(): return "近旁的光景还没看清，须到跟前往看"
	var nest_text := "眼前巢穴活跃" if f.get("nest_active", false) else ("眼前巢穴已毁" if f.get("nest_visible", false) else "巢穴眼下不在视野里")
	return "眼前可见%d只；%s。视野外的情况还不清楚。" % [f["visible_count"], nest_text]

func target() -> Dictionary:
	if not is_active() and not guidance_pending(): return {}
	var id := _target_object()
	if id == "home:patrol":
		for npc: Node in get_tree().get_nodes_in_group("npcs"):
			if npc is Node2D and npc.get("landmark_id") == "camp_ecology" and npc.get("quest_kind") == "outpost":
				return {"position": npc.global_position, "kind": "outpost", "object_id": id, "name": "营中巡守周照",
					"species": "", "region_id": "", "knowledge": "npc_intel", "live_facts": {}}
		return {}
	if id == "ecology":
		var t: Dictionary = ledger()["target"]
		return {"position": _position(t), "kind": "outpost", "object_id": "ecology:" + t["key"], "name": str(t["species"]) + "据点",
			"species": t["species"], "region_id": t["region_id"], "target_instance_ids": _targets.current_stock_ids(t),
			"guide_mode": ("hunt" if ledger()["choice"] == "hunt" else "nest") if evidence("site_surveyed") else "investigate",
			"knowledge": "visible" if facts().get("nest_visible", false) else ("last_seen" if evidence("site_surveyed") else "npc_intel"),
			"knowledge_label": "已察看的巢穴 / 寻已对上的族群" if ledger()["choice"] == "hunt" else "真正的巢穴 / 现场察看", "live_facts": facts()}
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
	if ledger().is_empty(): return "同营中巡守周照交谈，打听断了音信的哨所"
	if ledger().get("stage", "") == "completed": return "回营地同营中巡守周照交谈，打听去林地的路书" if evidence("next_clue_received") else "同哨所巡守石安交谈，打听后续线索"
	if ledger().get("stage", "") == "claim": return "到哨所路标旁领取修复报酬"
	if _searching: return "正在找近旁走得到的巢穴线索"
	match _target_object():
		"patrol_record": return "沿旧道寻回道旁的手札"
		"entrance_record": return "察看门前的拖痕"
		"wounded_patrol": return "把巡守药囊带给受伤的巡守石安" if evidence("wounded_found") else "沿拖痕到西边棚屋寻受伤的巡守石安"
		"supply_record": return "察看院里的物资清单"
		"aid_bag": return "到东边物资架的北头寻巡守药囊"
		"repair_tools": return "到南边拐角取回哨所工具包"
		"survey_marker": return "到哨所瞭望处察看四周痕迹"
		"ecology":
			var species := str(ledger()["target"]["species"])
			if not evidence("site_surveyed"): return "到%s据点察看巢穴" % species
			if ledger()["choice"] == "hunt":
				if not _hunt_possible(_current_facts()): return "回%s巢穴再看一遍，已猎的%d/2作数" % [species, mini(ledger()["kills"].size(), 2)]
				return "猎%s %d/2，留下巢穴和至少一只" % [species, mini(ledger()["kills"].size(), 2)]
			if ledger()["choice"] == "ransack": return "捣毁%s巢穴，留神近旁活着的怪物" % species
			return "在%s巢穴选定留余狩猎，或暂时捣巢" % species
	return "带上工具修好倒下的哨所路标"

func snapshot() -> Dictionary:
	if ledger().is_empty(): return {}
	var t := target()
	var pos: Vector2 = t.get("position", Vector2.INF)
	var reward := Data.reward("restoration", ledger()["legacy_reserved"])
	var view := {"id": Data.ID, "landmark_id": Legacy.LANDMARK, "kind": "outpost", "title": Data.TITLE,
		"giver": "哨所巡守石安", "need": 3, "progress": (1 if Data.investigation_done(ledger()) else 0) + (1 if Data.rescue_done(ledger()) else 0) + (1 if evidence("signpost_repaired") else 0),
		"claim_at_npc": true, "chapter_stage": ledger()["stage"], "ui_state": "claimable" if ledger()["stage"] == "claim" else "in_progress",
		"ui_status": "尾款待领取" if ledger()["stage"] == "claim" else "哨所一节", "ui_objective": objective(),
		"next_action": next_action(), "target_title": t.get("name", ""), "step_progress": step_progress(),
		"ui_reward": reward_policy(), "gold": reward["gold"], "xp": reward["xp"], "bonus": reward["bonus"],
		"target_object_id": t.get("object_id", ""), "target_name": t.get("name", ""), "target_pos": [pos.x, pos.y] if pos.is_finite() else [],
		"species": t.get("species", ""), "hunt_region": t.get("region_id", ""), "target_instance_ids": t.get("target_instance_ids", []),
		"ui_guide_mode": t.get("guide_mode", "object"), "ui_target_label": t.get("knowledge_label", t.get("name", "")),
		"ui_knowledge": t.get("knowledge", "unknown"), "history": history_text(), "live_facts": live_text(), "rules": _journal_rules()}
	if ledger().get("stage", "") == "completed":
		view["ui_state"] = "completed"
		view["ui_status"] = "哨所已复原"
		view["claim_at_npc"] = false
		view["can_abandon"] = false
		view["guidance_pending"] = guidance_pending()
	return view

func _journal_rules() -> String:
	var rules := "可以暂且搁下，回头再办；查过的线索、到手的物件都会留着。"
	if evidence("wounded_found"): rules += "\n巡守药囊与工具包单独保管，不占寻常补给的上限；包扎只用这只任务药囊。"
	if Data.rescue_done(ledger()): rules += "\n留余狩猎须猎2只，并留下巢穴和至少1只；暂时捣巢压住繁衍120刻，近旁同族狂怒60秒，活着的怪物仍在。"
	if evidence("signpost_repaired"): rules += "\n哨所检查点已开启；修路标的赏里装不下的补给，存进行囊→待领取。"
	return rules

func npc_status() -> Dictionary:
	if ledger().get("stage", "") == "completed": return {"state": "completed", "marker": "✓ 哨所已复原", "color": QuestPresentation.COMPLETED_COLOR}
	return {"state": "in_progress" if is_active() else "available", "marker": "· 哨音久绝进行中" if is_active() else "! 哨音久绝", "color": QuestPresentation.PROGRESS_COLOR if is_active() else QuestPresentation.AVAILABLE_COLOR}

func history_text() -> String:
	return "记录：" + "；".join(ledger().get("history", []))

func receipt_text() -> String:
	return "✓ 哨音久绝 · 已完成 · " + next_action()

func _on_object_interaction(id: String) -> void:
	EventBus.npc_dialogue.emit(object_payload(id))

func _on_action(action: String) -> void:
	if not action.begins_with("outpost:"): return
	var id := action.trim_prefix("outpost:")
	var prior_evidence: Dictionary = ledger().get("evidence", {}).duplicate(true)
	var message := ""
	match id:
		"accept", "resume": message = accept()
		"menu": EventBus.npc_dialogue.emit(offer("营中巡守周照"))
		"status": EventBus.npc_dialogue.emit({"kind": "info", "giver": "哨所记录", "text": objective() + "\n" + history_text()})
		"legacy":
			var manager := get_parent()
			EventBus.npc_dialogue.emit(manager.call("legacy_camp_offer", "营中巡守周照"))
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
	if id == "wounded_patrol" and evidence("rescued"): return "哨所巡守石安"
	if id == "signpost" and evidence("signpost_repaired"): return "哨所路标"
	return str(Layout.OBJECTS.get(id, {}).get("title", "哨所线索"))

func _next_clue() -> String:
	var here: SimRegion = WorldSim.sim.region_of_point(Layout.center()) if WorldSim.sim != null else null
	if here != null:
		for id: String in here.neighbor_ids:
			var region: SimRegion = WorldSim.sim.get_region(id)
			if region != null and region.terrain != here.terrain:
				var d: Vector2 = region.center - Layout.center()
				var direction := ("东" if d.x >= 0 else "西") + ("南" if d.y >= 0 else "北")
				return "回营去找营中巡守周照，他有去林间驿站的旧路书。替俺告诉那边的人：哨所又有人守着了。\n哨所往%s走是%s；那边眼下的光景，还得亲自去看看。" % [direction, region.display_name]
	return "回营去找营中巡守周照，他有去林间驿站的旧路书。替俺告诉那边的人：哨所又有人守着了。"

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
