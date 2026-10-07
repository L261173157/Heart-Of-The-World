## 六章连续主线验收：原场景/原碰撞实走、真实触屏阅读与确认、原Boss战斗、独立冷存档。
## 生态与非目标AI冻结；Boss强构筑/自然寿终和库存边界明示，不能用作正常难度或新手时长证明。
extends "res://tests/campaign_story_acceptance_test.gd"

var _reading_checks := 0
var _result_checks := 0
const CAST := {"c2:herbalist":"白榆", "c2:liaison":"阿苇", "c3:survivor":"沈渡", "c4:scholar":"闻川", "c4:map_keeper":"罗墨", "c5:leader":"韩铎"}

func _reading_state() -> Dictionary:
	return {"outpost":_q().duplicate(true),"campaign":_cq().duplicate(true),"wallet":_wallet(),
		"pending":GameState.pending_items.duplicate(true),"items":GameState.item_source_receipts.duplicate(true)}

func _read_optional_pages(label: String) -> void:
	var opening: String = _hud._dialogue_text.text
	var command: String = _hud._dialogue_action_name
	var state := _reading_state()
	for name: String in ["DialogueQuestion_0", "DialogueRules"]:
		var button := _hud._dialogue_option_box.get_node_or_null(name) as Button
		if button == null: continue
		for attempt in 2:
			button = _hud._dialogue_option_box.get_node_or_null(name) as Button
			await _tap(button)
			_check(_hud._dialogue_reading_page == ("question" if name == "DialogueQuestion_0" else "rules")
				and get_tree().paused and not _hud._dialogue_text.text.is_empty(), "实际追问/细节页可重复阅读："+label)
			_check(_same(state,_reading_state()), "阅读页不提前记录、消费或支付："+label)
			await _tap(_hud._dialogue_no)
			_check(_hud._dialogue_panel.visible and get_tree().paused and _hud._dialogue_reading_page.is_empty()
				and _hud._dialogue_text.text == opening and _hud._dialogue_action_name == command, "返回原现场而不丢正式操作："+label)
			_check(_same(state,_reading_state()), "阅读返回保留全部账本与支付："+label)
			_reading_checks += 1

func _continue_result(label: String) -> void:
	if not _hud._dialogue_panel.visible or _hud._dialogue_kind != "story_result": return
	var before := _reading_state()
	_check(get_tree().paused and _hud._dialogue_yes.visible and _hud._dialogue_yes_label.text == "继续", "行动结果保留可读的继续按钮："+label)
	_check(_hud._dialogue_action_name.is_empty(), "结果页不携带第二次支付动作："+label)
	await _frames(6)
	_check(_same(before,_reading_state()) and _hud._dialogue_kind == "story_result", "结果等待读完，不自行关闭或再次发奖："+label)
	await _tap(_hud._dialogue_yes)
	_check(not _hud._dialogue_panel.visible and not get_tree().paused, "独立触屏继续关闭结果："+label)
	_check(_same(before.wallet,_wallet()) and _same(before.campaign.get("quests",{}),_cq().get("quests",{})), "继续不重复证据或奖励："+label)
	_result_checks += 1

## 开场也从新档实际出生位置走向周照；不会继承旧助手的取景传送。
func _home() -> void:
	var keeper := _keeper()
	_check(keeper != null,"新档营地存在周照")
	if keeper != null: await _walk_to(keeper.global_position+Vector2(38,0),"新档从出生点实走到周照")
	_hud._close_dialogue()
	await _frames()

func _accept_chapter() -> bool:
	await _home()
	_keeper().interact()
	await _frames()
	_check(_hud._dialogue_panel.visible and _hud._dialogue_yes.visible,"周照正式邀请具备独立确认")
	if not _hud._dialogue_yes.visible: return false
	var opening: String = _hud._dialogue_text.text
	for spoiler: String in ["世界之心", "韩铎", "撤守令", "共同归来"]:
		_check(not opening.contains(spoiler),"第一幕不提前剧透终章："+spoiler)
	_check(not _hud._dialogue_questions.is_empty(),"第一幕保留可选追问")
	await _read_optional_pages("周照首章邀请")
	await _tap(_hud._dialogue_no)
	_check(_q().is_empty() or not _q().get("active",false),"首章阅读后取消仍未接取")
	_keeper().interact()
	await _frames()
	await _tap(_hud._dialogue_yes)
	await _continue_result("接取首章")
	_hud._close_dialogue()
	_check(_q().get("active",false) and not _evidence("patrol_read"),"只在新确认后接取，不提前调查")
	return _q().get("active",false)

func _interact(id: String, confirm := true) -> void:
	await super._interact(id,false)
	if not _hud._dialogue_panel.visible: return
	await _read_optional_pages("前哨："+id)
	if not confirm: return
	if _hud._dialogue_yes.visible: await _tap(_hud._dialogue_yes)
	await _continue_result("前哨："+id)
	_hud._close_dialogue()
	await _frames()

func _ci(id: String, confirm := true) -> bool:
	if not await super._ci(id,false): return false
	if not _hud._dialogue_panel.visible: return true
	await _read_optional_pages(id)
	if not confirm: return true
	if _hud._dialogue_yes.visible: await _tap(_hud._dialogue_yes)
	await _continue_result(id)
	_hud._close_dialogue()
	await _frames()
	return true

func _choice_ui(object_id: String, action_id: String, cancel_first := false, close_result := true) -> bool:
	if not await _ci(object_id,false): return false
	var button := _option(action_id)
	_check(button != null and not button.disabled,"真实可见路线/服务选项："+action_id)
	if button == null or button.disabled: return false
	var before := _reading_state()
	await _tap(button)
	_check(_same(before,_reading_state()),"选项只预览，未确认不提交："+action_id)
	if cancel_first:
		await _tap(_hud._dialogue_no)
		_check(_same(before,_reading_state()),"退回分支预览不改变路线或奖励："+action_id)
		button = _option(action_id)
		if button == null: return false
		await _tap(button)
	await _tap(_hud._dialogue_yes)
	if close_result:
		await _continue_result(action_id)
		_hud._close_dialogue()
	await _frames()
	return true

func _original_boss(species: String) -> MonsterInstance:
	for inst: MonsterInstance in WorldSim.sim.instances.values():
		if inst.is_alive and inst.species.species_name == species: return inst
	return null

func _fight_original(boss: MonsterInstance) -> bool:
	_world._stream_pass()
	await _frames(4)
	var body: MonsterBase = _world._nodes.get(boss.id)
	_check(body != null and body.inst == boss,"丘陵使用原锚点原ID的牛头王战斗实体")
	if body == null: return false
	var candidates: Array[Vector2] = []
	var query := _walk_query()
	for radius: float in [72.0,88.0,104.0]:
		for direction: Vector2 in [Vector2.DOWN,Vector2.LEFT,Vector2.RIGHT,Vector2.UP]:
			var at := body.global_position+direction*radius
			if not _walk_blocked(at,query) and not _walk_plan(_player.global_position,at,query).is_empty(): candidates.append(at)
	candidates.sort_custom(func(a: Vector2,b: Vector2) -> bool: return _player.global_position.distance_squared_to(a)<_player.global_position.distance_squared_to(b))
	_check(not candidates.is_empty(),"丘陵原Boss有不穿透原碰撞的近身路线")
	if candidates.is_empty() or not await _walk_to(candidates[0],"实走进入牛头王战位",8.0): return false
	# 强构筑夹具仅缩短战斗；不改Boss血量、位置、碰撞、AI、身份或权威死亡路径。
	GameState.stats.level = 20
	GameState.stats.strength = 120
	GameState.stats.agility = 20
	GameState.stats.intellect = 20
	GameState.stats.changed.emit()
	_player.current_hp = _player.stats.max_hp()
	_player.current_mp = _player.stats.max_mp()
	_player._protect_timer = 0
	_player._hurt_iframes = 0
	body.set_physics_process(true)
	_player.set_physics_process(true)
	var active_attacks := 0
	for step in 240:
		if not boss.is_alive or _player._is_dead: break
		_player.facing = _player.global_position.direction_to(body.global_position)
		TouchInput.joystick_active = true
		TouchInput.move_vector = _player.facing if _player.global_position.distance_to(body.global_position)>58.0 else Vector2.ZERO
		if step > 8: TouchInput.queue_attack()
		await _frames(6)
		if body.state == MonsterBase.S_ATTACK or body.state == Guardian.S_WINDUP: active_attacks += 1
	TouchInput.reset()
	_player.set_physics_process(false)
	body.set_physics_process(false)
	_check(not boss.is_alive and not _player._is_dead and active_attacks>0,"真实移动/攻击/原Boss出招完成丘陵讨伐")
	var kill: Dictionary = _cq().get("main_kills",{}).get("牛头王",{})
	_check(kill.get("instance_id",-1)==boss.id and kill.get("player_kill",false),"丘陵击杀具名ID收据来自真实权威死亡")
	return not boss.is_alive

func _hill_alternative(outcome: String) -> void:
	if not await _travel_story("hill","c3:beacon"): return
	if not await _normal_stage(C4,1) or not await _normal_stage(C4,2): return
	var actions := _stage_actions(C4,3)
	if not await _do_action(actions[0]) or not await _cw(actions[1].object): return
	var boss := _original_boss("牛头王")
	_check(boss != null,"三种丘陵路线从原世界活牛头王开始")
	if boss == null: return
	var before := _cq().duplicate(true)
	_campaign.perform_action(actions[1].id,"defeated")
	_check(_same(before,_cq()),"未经本人战斗不能对话冒领牛头王讨伐")
	if outcome == "defeated":
		if not await _fight_original(boss): return
	elif outcome == "absent":
		# 明示自然寿终边界：只缩短既有实例余寿，死亡走原生态tick，不伪造玩家贡献。
		boss.lifespan = boss.age+1
		WorldSim.sim.tick()
		await _frames(3)
		_check(not boss.is_alive and not _cq().get("main_kills",{}).has("牛头王"),"牛头王真实自然死亡不生成个人讨伐")
	var population := _world_clock()
	if not await _do_action(actions[1],outcome) or not await _do_action(actions[2]): return
	_check(_proof(C4+":s3",C4+":s3:passage").get("outcome","")==outcome,"丘陵实际分支保存准确经历："+outcome)
	if outcome == "bypass": _check(boss.is_alive and _same(population,_world_clock()),"西侧绕行保留原活Boss与整个生态")
	await _normal_stage(C4,4)

func _complete_core() -> void:
	var actions := _stage_actions(C6,3)
	for id: String in actions[0].puzzle_objects:
		if not await _cw(id): return
		await _ci(id)
	await _do_action(actions[1])

func _canonical_cast() -> void:
	for id: String in CAST:
		var prop := _cp(id)
		_check(prop != null and str(prop.get("title")).contains(CAST[id]),"世界实体与正史人名一致："+str(CAST[id]))
	_check(str(_prop("wounded_patrol").get("title")).contains("石安"),"石安仍是第一章前哨巡守")

func _epilogue_pages() -> void:
	if not await _cw("c5:leader") or not await _ci("c5:leader",false): return
	var menu := _option("campaign|epilogue_menu")
	_check(menu != null,"团聚后的真实人物菜单提供后记")
	if menu == null: return
	await _tap(menu)
	_check(_hud._dialogue_yes.visible and _hud._dialogue_selected_option.get("action","")=="campaign|epilogue_menu", "后记入口同样先预览，再以独立手势确认")
	await _tap(_hud._dialogue_yes)
	var state := _reading_state()
	var pages: Array = _campaign.epilogue_pages()
	_check(pages.size()>=4,"后记分成可独立翻阅的短页")
	for index in pages.size():
		for repeat in 2:
			var button := _option("campaign|epilogue|"+str(index))
			_check(button != null,"真实后记页按钮存在："+str(index))
			if button == null: return
			await _tap(button)
			_check(_same(state,_reading_state()) and _hud._dialogue_yes.visible, "后记页选择只预览且不改任何账本")
			await _tap(_hud._dialogue_yes)
			_check(_hud._dialogue_text.text == pages[index] and get_tree().paused,"所选后记页准确上屏："+str(index))
			_check(_same(state,_reading_state()),"重复翻页不改结局/证据/支付")
			await _tap(_hud._dialogue_no)
			_check(_hud._dialogue_kind == "camp_choice" and get_tree().paused,"返回后记目录而非退出世界暂停")
	_hud._close_dialogue()

func _visit_shi_an() -> void:
	if not await _cw("c5:leader"): return
	_player.set_physics_process(true)
	await _frames(12)
	_player.set_physics_process(false)
	if not await _choice_ui("c5:leader","campaign|depart|home|c5:leader",true): return
	for attempt in 180:
		await _frames(1)
		if _player.global_position.distance_to(WorldConfig.spawn_pos())<10.0 and not _world._teleporting: break
	_check(_player.global_position.distance_to(WorldConfig.spawn_pos())<10.0,"团聚后从真实人物菜单乘原返程渠道回营地")
	# 从营地南侧旧路绕过实心房屋，再循首章旧路实走返回前哨。
	if not await _walk_to(WorldConfig.spawn_pos()+Vector2(0,768),"团聚后实走出营地南侧"): return
	if not await _walk_to(WorldConfig.spawn_pos()+Vector2(704,768),"团聚后绕过原营地房屋"): return
	if not await _walk_prop("wounded_patrol"): return
	var before := _reading_state()
	await _interact("wounded_patrol",false)
	var words: String = _hud._dialogue_text.text
	_check(words.contains("四人") and words.contains("平原") and words.contains("前哨我还守着"),"石安现场对话真实回应团聚，并承诺仍留前哨")
	_check(not words.contains("听听后续线索") and _same(before.wallet,_wallet()) and _same(before.outpost,_q()),"石安后日谈不重做首章或支付旧奖励")
	_hud._close_dialogue()

func _final_contract(visit_outpost := false) -> void:
	_check(_campaign_data.chapter1_complete(_cq()),"第一章完整真实证据保留至团聚")
	for chapter: Dictionary in Catalog.main_chapters():
		for stage: Dictionary in chapter.steps:
			_check(_campaign_data.ready(_cq(),stage.id) and _cq().quests[stage.id].receipt.get("paid",false),"六章各节拍完成且只有已支付收据："+str(stage.id))
	_verify_ending_world("reunion")
	_canonical_cast()
	var reunion_labels: Array[Label] = []
	for id: String in ["c2:liaison","c3:survivor","c4:map_keeper","c5:leader"]:
		var label := _cp(id).get_node("ObjectLabel") as Label
		_check(label.text.contains(CAST[id]) and label.size.x<=156.0 and label.get_minimum_size().x<=label.size.x,"团聚短名完整保留且不超出160px驻地间隔："+str(CAST[id]))
		var ink_width := label.get_theme_font("font").get_string_size(label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,label.get_theme_font_size("font_size")).x + 2*label.get_theme_constant("outline_size")
		_check(ink_width<=label.size.x,"团聚完整姓名/服务字形和描边均可放入名牌："+str(CAST[id]))
		for previous: Label in reunion_labels:
			_check(not label.get_global_rect().intersects(previous.get_global_rect()),"团聚四人实际名牌矩形互不重叠")
		reunion_labels.append(label)
	for id: String in ["c2:beacon","c3:beacon","c4:beacon","c5:beacon","c6:beacon","c6:heart"]:
		_check(bool(_cp(id).get("repaired")),"团聚后已修灯与中枢仍亮："+id)
	_check(_prop("wounded_patrol").global_position == OutpostLayout.object_position("wounded_patrol"),"石安保留原前哨驻地")
	var before := _reading_state()
	for chapter: Dictionary in Catalog.main_chapters():
		for stage: Dictionary in chapter.steps: _campaign.claim(stage.id)
	_campaign._settle_ready()
	_check(_same(before,_reading_state()),"重放全部章节结算不再发一次奖励或改证据")
	await _epilogue_pages()
	if visit_outpost: await _visit_shi_an()

func _run() -> void:
	Engine.time_scale = 4.0
	var args := OS.get_cmdline_user_args()
	if args.size()!=1 or OS.get_environment("HOTW_TEST_SAVE").is_empty():
		_check(false,"完整主线验收须明确隔离存档与阶段")
		_finish()
		return
	var phase: String = args[0]
	await _mount(phase=="chapter1")
	if phase!="chapter1": _cold_campaign_expected()
	var original := _q().duplicate(true)
	var paid := {}
	for id: String in _cq().get("quests",{}):
		if _cq().quests[id].get("receipt",{}).get("paid",false): paid[id]=_cq().quests[id].duplicate(true)
	if _fails==0:
		match phase:
			"chapter1": await _chapter_one_seed()
			"depart": await _depart_forest()
			"rune_partial": await _forest_rune_partial()
			"runes": await _forest_runes()
			"rescue": await _forest_rescue()
			"beacon99": await _forest_beacon()
			"claim": await _forest_claim()
			"c3_prepare": await _c3_prepare()
			"c3_near_partial": await _c3_route("near",true)
			"c3_outer_partial": await _c3_route("outer",true)
			"c3_near": await _c3_route("near")
			"c3_outer": await _c3_route("outer")
			"c4_bypass": await _hill_alternative("bypass")
			"c4_absent": await _hill_alternative("absent")
			"c4_defeated": await _hill_alternative("defeated")
			"c5_partial": await _c5(true)
			"c5_finish": await _c5_finish()
			"c6_live":
				await _c6_live()
				if _fails==0: await _complete_core()
			"c6_absent": await _c6_prepare_empty()
			"reunion":
				await _ending("reunion")
				if _fails==0: await _final_contract()
			"read": await _final_contract(true)
			_: _check(false,"未知完整主线阶段："+phase)
	if phase!="chapter1": _check(_same(original,_q()),"后续主线不改写首章真实故事与支付")
	for id: String in paid:
		_check(_same(paid[id],_cq().quests.get(id,{})),"本段不改写已完成节拍的证据或收据："+id)
	if _fails==0 and phase!="read":
		_check(_save(),"完整主线阶段真实原子落盘："+phase)
		_write_campaign_expected()
	print("COMPLETE_STORY_UI_READING ",_reading_checks," CONTINUE ",_result_checks)
	await _unmount()
	_finish()

func _finish() -> void:
	print("COMPLETE_STORY_WALKED_PIXELS ",snappedf(_walked,1.0))
	print("=== CAMPAIGN COMPLETE STORY %s (%d checks, %d failures) ===" % ["PASS" if _fails==0 else "FAIL",_checks,_fails])
	get_tree().quit(0 if _fails==0 else 1)
