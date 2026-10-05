## 独立整合验收：从真实前五章存档出发，在同一实际世界交织人物、区域、遭遇与世界线。
## 复用原玩家实走/触屏确认/远征；不注入完成证据、生态事实、支线奖励或已领取状态。
## 仅普通任务栏满载、背包满及强构筑为明确边界夹具；不宣称首次玩家时长或难度。
extends "res://tests/campaign_story_acceptance_test.gd"

var _optional: CampaignOptional
var _dynamic: CampaignDynamic
var _list: Array = []
var _legacy_before: Dictionary

func _cp(id: String) -> Node2D:
	if id=="home:patrol": return _keeper()
	return super._cp(id)

func _cw(id: String, offset := Vector2(0,56)) -> bool:
	if id == "home:patrol": return await _walk_home_context()
	return await super._cw(id,offset)

func _at_campaign_entry(terrain: String) -> bool:
	if terrain == "home": return _player.global_position.distance_to(WorldConfig.spawn_pos())<100
	return super._at_campaign_entry(terrain)

func _capture_list(rows: Array, _selected: String) -> void:
	_list=rows.duplicate(true)

func _earlier_main() -> Dictionary:
	var result: Dictionary={}
	for sid: String in _cq().get("quests",{}):
		if sid.begins_with("watch_") and not sid.begins_with(C6): result[sid]=_cq().quests[sid].duplicate(true)
	return result

func _stable_families() -> Dictionary:
	var result := {"quests":{},"outpost":_q().duplicate(true),"legacy_camp":GameState.camp_quest.duplicate(true),"ordinary":GameState.quests.duplicate(true),"service_receipts":_cq().get("service_receipts",{}).duplicate(true)}
	for sid: String in _cq().get("quests",{}):
		if not sid.begins_with("watch_"): result.quests[sid]=_cq().quests[sid].duplicate(true)
	return result

func _intact(before: Dictionary, label: String) -> void:
	_check(_same(before,_stable_families()),label+"不改其他家族证据、预算、收据和服务墓碑")

func _stage_start(sid: String, family: String) -> bool:
	var stage:=Catalog.stage(sid)
	var origin: String=_optional._start_object(stage) if family=="optional" else _dynamic._stage_object(stage)
	if not await _cw(origin): return false
	if not _cq().quests.get(sid,{}).get("accepted",false): await _ci(origin)
	_check(_cq().quests.get(sid,{}).get("accepted",false),"真实发布菜单接取 "+sid)
	return _cq().quests.get(sid,{}).get("accepted",false)

func _opt_stage(sid: String, choice := "") -> bool:
	if not await _stage_start(sid,"optional"): return false
	for a: Dictionary in Catalog.stage(sid).actions:
		if a.get("optional",false) or _optional._done(a): continue
		var object_id:=_optional.action_object(a)
		if a.kind=="route":
			if _cq().get("optional_route_reanchor",{}).get(a.id,false):
				if not await _walk_to(_optional._route_anchor(a),"实走返回先前核实的区域接续点",12): return false
			if not await _cw(str(_optional._route_points(a)[0])): return false
			for point: Vector2 in _optional.route_geometry(a):
				if not await _walk_to(point,"完整区域工程实走 "+sid,12): return false
				await _frames(4)
		if not await _cw(object_id): return false
		if a.kind=="choice":
			if not await _choice_ui(object_id,"campaign|optional|act|"+str(a.id)+"|"+choice,true): return false
		else: await _ci(object_id)
		_check(_optional._done(a),"实际人物/区域动作 "+str(a.id))
		if not _optional._done(a): return false
	_check(_campaign_data.ready(_cq(),sid),"人物/区域独立阶段完成 "+sid)
	return _campaign_data.ready(_cq(),sid)

func _dyn_action(aid: String) -> bool:
	var a: Dictionary=Catalog.actions(GameState.world_seed).get(aid,{})
	if not await _cw(str(a.object)): return false
	await _ci(str(a.object))
	_check(_dynamic._done(a),"世界/遭遇实际现场动作 "+aid)
	return _dynamic._done(a)

func _random_id() -> String:
	return "random_medicine:"+str(GameState.world_seed)+":0"

func _prepare_mixed() -> void:
	_check(_campaign_data.ready(_cq(),C5+":s4"),"输入是实际前五章完成档")
	# 足够的奖励空位是库存边界夹具，不改任何已冻结金额。
	if GameState.count_item("onigiri")>90: GameState.remove_item("onigiri",GameState.count_item("onigiri")-90)
	if not await _opt_stage("side_letter:s1"): return
	if not await _stage_start("side_letter:s2","optional"): return
	if not await _opt_stage("region_snow:s1") or not await _opt_stage("region_snow:s2","outer"): return
	if not await _stage_start("region_snow:s3","optional"): return
	var route_action: Dictionary=Catalog.actions()["region_snow:s3:walk"]
	var route: Array=_optional.route_geometry(route_action)
	if not await _cw(str(_optional._route_points(route_action)[0])): return
	for i in 2:
		if not await _walk_to(route[i],"跨家族前保留真实区域路线前缀",10): return
		await _frames(4)
	_check(not _cq().optional_routes.get(route_action.id,[]).is_empty() and not _optional._done(route_action),"未完成路线留有真实前缀")
	var id:=_random_id()
	# 未见实例只向其实际登记场地走，生产发现器自己显现并保存对象目击。
	if not await _walk_to(CampaignLayout.object_position(id+":giver")+Vector2(0,56),"走近真实有限遭遇发布点",12): return
	await _frames(12)
	for role: String in CampaignEncounters.REQUIRED_ROLES["random_medicine"]:
		if not await _cw(id+":"+role): return
		await _frames(12)
	if not await _cw(id+":giver"): return
	await _ci(id+":giver")
	_check(_cq().get("active_random","")==id,"正常宿主接取有限遭遇，无注入实例")
	if _cq().get("active_random","")!=id: return
	if not await _dyn_action(id+":request") or not await _dyn_action(id+":medicine"): return
	_campaign.abandon(id)
	await _ci(id+":parts")
	_check(not "random_medicine" in _cq().paused_chains,"部分物资到手后原地暂停/继续遭遇保留名额")
	_campaign.abandon("region_snow:s3")
	if not await _cw("region_snow:station"): return
	await _ci("region_snow:station")
	_check(not "region_snow" in _cq().paused_chains,"未验收区域在原站现场暂停/继续")
	_campaign.abandon("side_letter:s2")
	var stable:=_stable_families()
	if not await _travel_story("forest","c5:beacon",false): return
	_intact(stable,"未完工时跨章远征")
	if not await _stage_start("world_relief:s1","dynamic"): return
	if not await _dyn_action("world_relief:s1:need_a"): return
	_check(_cq().quests.size()>=23,"同一真实世界已有主线与四个新增家族")
	_check(_cq().get("world_facts",{}).get("triggers",{}).get("world_migration",{}).is_empty(),"没有实际迁移触发时不伪造迁徙世界任务")
	_check(not _cq().quests.has("world_watchnet:s1"),"区域数量不足时不伪造终局守望网")

func _cap_and_death() -> void:
	if not await _cw("c2:beacon"): return
	var stable:=_stable_families()
	# 三张旧式单纯粹用于容量边界，不是本测试完成的作者故事。
	var ordinary:=GameState.quests.duplicate(true)
	GameState.quests.active=[]
	for i in QuestManager.MAX_ACTIVE:
		GameState.quests.active.append({"id":"cross_cap_"+str(i),"kind":"hunt","title":"容量边界夹具","giver":"旧式委托人","need":99,"progress":0,"gold":0,"xp":0,"target_species":"容量测试","landmark_id":"capacity_"+str(i)})
	_campaign.accept_chapter(C6)
	_check(_cq().quests.get(C6+":s1",{}).get("accepted",false),"旧式满栏时真正接取终章主线")
	_qm._push_hud()
	var expected: Array=_campaign.snapshots()
	_check(expected.size()>=4,"主线、区域、随机、世界四家族同时活动")
	var ids: Array=[]
	for row: Dictionary in _list: ids.append(row.id)
	_check(_list.size()==QuestManager.MAX_ACTIVE+expected.size(),"旧式三任务满栏不会裁掉任何主线/世界快照")
	for row: Dictionary in expected: _check(str(row.id) in ids,"跨家族任务确实进入真实HUD列表 "+str(row.id))
	GameState.quests=ordinary
	_qm._push_hud()
	_hud._toggle_pause()
	_check(get_tree().paused,"实际暂停层正常打开")
	_hud._toggle_pause()
	_player._hurt_iframes=0
	_player._protect_timer=0
	_player.take_damage(1000000,Vector2.INF)
	_check(_player._is_dead,"部分进度期间真实玩家死亡")
	_intact(stable,"真实死亡")
	_player._respawn()
	_player.set_physics_process(false)
	await _frames(8)
	_intact(stable,"真实复活")

func _finish_world() -> void:
	# 死亡后使用既有回城和家园入口，没有测试传送去任务对象。
	if not await _walk_home_context(true): return
	if not await _travel_story("swamp","home:patrol",false): return
	if not await _dyn_action("world_relief:s1:need_b"): return
	if not await _travel_story("forest","c3:beacon",false): return
	if not await _stage_start("world_relief:s2","dynamic"): return
	if not await _dyn_action("world_relief:s2:supply_a"): return
	if not await _travel_story("swamp","c2:beacon",false): return
	if not await _dyn_action("world_relief:s2:supply_b"): return
	if not await _travel_story("forest","c3:beacon",false): return
	if not await _stage_start("world_relief:s3","dynamic"): return
	if not await _dyn_action("world_relief:s3:return_a"): return
	if not await _travel_story("swamp","c2:beacon",false): return
	if not await _dyn_action("world_relief:s3:return_b"): return
	if not await _travel_story("home","c3:beacon",false): return
	if not await _dyn_action("world_relief:s3:settle"): return
	_check(_campaign_data.ready(_cq(),"world_relief:s3"),"真实两地确认、两份交付、两地回访及协调台有限结案")
	if not await _choice_ui("world_relief:coordination_post","campaign|dynamic|supply|world_relief:coordination_post"): return
	_check(_campaign_data.service_claimed(_cq(),"world_relief_station"),"世界服务产生唯一领取墓碑")
	if not await _opt_stage("side_patrol:s1") or not await _opt_stage("side_patrol:s2","camp"): return
	if not await _cw("side_patrol:station_camp"): return
	await _choice_ui("side_patrol:station_camp","campaign|optional|supply|side_patrol:station_camp")
	_check(_campaign_data.service_claimed(_cq(),"patrol_station"),"人物服务产生独立领取墓碑")

func _resume_snow() -> void:
	if not await _travel_story("snow","home:patrol",false): return
	for id: String in ["side_letter:resolution","region_snow:station",_random_id()+":giver"]:
		if not await _cw(id): return
		await _ci(id)
	_check(not "side_letter" in _cq().paused_chains and not "region_snow" in _cq().paused_chains and not "random_medicine" in _cq().paused_chains,"三家族实际现场恢复而非重新接单")
	if not await _opt_stage("side_letter:s2"): return
	if not await _opt_stage("region_snow:s3"): return
	if not await _dyn_action(_random_id()+":deliver"): return
	_check(_cq().get("active_random","").is_empty() and int(_cq().get("encounters",{}).get("counts",{}).get("random_medicine",0))==1,"同一遭遇一次关闭且名额不因冷读/放弃/死亡重置")
	if not await _cw("region_snow:station"): return
	await _choice_ui("region_snow:station","campaign|optional|supply|region_snow:station")
	_check(_campaign_data.service_claimed(_cq(),"region_snow_station"),"区域服务第三个独立领取墓碑")

func _finale() -> void:
	var stable:=_stable_families()
	await _c6_live()
	_intact(stable,"真实终章原Boss挑战")
	if _fails>0: return
	var core:=_stage_actions(C6,3)
	for id: String in core[0].puzzle_objects:
		if not await _cw(id): return
		await _ci(id)
	if not await _do_action(core[1]): return
	_intact(stable,"终章中枢启动")

func _write_campaign_expected() -> void:
	super._write_campaign_expected()
	var value:=_expected()
	value["legacy_camp"]=GameState.camp_quest.duplicate(true)
	value["ordinary"]=GameState.quests.duplicate(true)
	_write_expected(value)

func _cold_extra() -> void:
	var expected:=_expected()
	for key: String in ["legacy_camp","ordinary"]:
		if expected.has(key): _check(_same(GameState.camp_quest if key=="legacy_camp" else GameState.quests,expected[key]),"冷读保持旧合同/普通任务 "+key)
	var saved: Dictionary=_expected().campaign
	for key: String in ["service_receipts","encounters"]:
		var retained: Dictionary=saved.get(key,{}).duplicate(true)
		# 冷恢复为非狩猎实例补齐三个可选的空身份列表；不允许删改任何真实内容。
		if key=="encounters":
			for row: Dictionary in retained.get("instances",{}).values():
				for optional_key: String in ["credited_ids","target_ids","deaths"]:
					if not row.proof.has(optional_key): row.proof[optional_key]=[]
		if not _same(_cq().get(key,{}),retained): print("CROSS_COLD_DIFF ",JSON.stringify({"key":key,"expected":retained,"actual":_cq().get(key,{})}))
		_check(_same(_cq().get(key,{}),retained),"独立冷读完整保留跨家族 "+key)
	for key: String in ["optional_routes","optional_route_steps","optional_route_reanchor"]:
		var pending: Dictionary=saved.get(key,{}).duplicate(true)
		for aid: String in pending.keys():
			var action: Dictionary=Catalog.actions(GameState.world_seed).get(aid,{})
			if not action.is_empty() and _campaign_data.ready(_cq(),str(action.stage)): pending.erase(aid)
		_check(_same(_cq().get(key,{}),pending),"独立冷读保留尚未完成的区域前缀 "+key)
	var wallet:=_wallet()
	_campaign._settle_ready()
	_check(_wallet()==wallet,"混合家族冷装配无重复阶段支付")
	_check(_same(_q(),_legacy_before),"旧第一章原证据与收据保持不变")

func _read_final() -> void:
	var ending:=str(_cq().quests[C6+":s4"].choice)
	_verify_ending_world(ending)
	var patrol:=_cp("side_patrol:giver")
	_check(patrol!=null and patrol.global_position.distance_to(CampaignLayout.object_position("side_patrol:station_camp")+Vector2(64,0))<0.1,"最终派驻不搬走独立人物线已选驻守NPC")
	for id: String in ["region_snow:station","world_relief:need_a","world_relief:need_b","world_relief:coordination_post"]:
		var node:=_cp(id)
		_check(node!=null and bool(node.get("repaired")) and not str(node.get("service")).is_empty(),"终局冷读保持另一家族的真实施工和服务实体 "+id)
	_check(_campaign.epilogue().contains("另已收尾2条人物故事、修复1处区域工程"),"后记只汇总实际完成的两条人物/一处区域，不假装全目录完成")
	for service: String in ["world_relief_station","patrol_station","region_snow_station"]:
		_check(_campaign_data.service_claimed(_cq(),service),"最终冷读保持唯一服务墓碑 "+service)
	var wallet:=_wallet()
	var stable:=_stable_families()
	var objects: Array=["region_snow:station"] if ending=="distributed" else ["side_patrol:station_camp","world_relief:coordination_post"]
	for id: String in objects:
		if not await _cw(id): return
		var family: String="dynamic" if id.begins_with("world_") else "optional"
		if not await _choice_ui(id,"campaign|"+family+"|supply|"+id): return
		_check(_wallet()==wallet,"终局独立冷读后实际重复领取不发第二份 "+id)
	_intact(stable,"终局冷读后重试三个家族服务")

func _run() -> void:
	Engine.time_scale=4
	var args:=OS.get_cmdline_user_args()
	if args.size()!=1 or OS.get_environment("HOTW_TEST_SAVE").is_empty():
		_check(false,"必须明确真实前置存档及阶段")
		_finish()
		return
	await _mount(false)
	_optional=_campaign._optional
	_dynamic=_campaign._dynamic
	_legacy_before=_q().duplicate(true)
	var main_before:=_earlier_main()
	var prior_tombstones: Dictionary=_cq().get("service_receipts",{}).duplicate(true)
	EventBus.quest_list_changed.connect(_capture_list)
	_cold_campaign_expected()
	_cold_extra()
	_check(CampaignQuest.ENABLED_BATCH==4 and GameState.SAVE_VERSION==17,"整部验收必须针对最终EN4/SAVE17")
	if _fails==0:
		match args[0]:
			"prepare": await _prepare_mixed()
			"world":
				await _cap_and_death()
				await _finish_world()
			"resume": await _resume_snow()
			"finale": await _finale()
			"distributed", "centralized":
				var stable:=_stable_families()
				await _ending(args[0])
				_intact(stable,"最终派驻及四处服务访问")
			"read": await _read_final()
			_: _check(false,"未知整合阶段")
	_check(_same(main_before,_earlier_main()),"本段全部活动保持早期主线证据及支付不变")
	_check(_same(_legacy_before,_q()),"本段全部活动保持既有第一章原合同不变")
	for id: String in prior_tombstones:
		_check(_same(prior_tombstones[id],_cq().get("service_receipts",{}).get(id,{})),"本段不擦除已有服务领取墓碑 "+id)
	if _fails==0 and args[0]!="read":
		_check(_save(),"混合家族真实存档原子落盘")
		_write_campaign_expected()
	await _unmount()
	_finish()

func _finish() -> void:
	print("CAMPAIGN_CROSS_FAMILY_WALKED_PIXELS ",snappedf(_walked,1))
	print("=== CAMPAIGN CROSS FAMILY %s (%d checks, %d failures) ===" % ["PASS" if _fails==0 else "FAIL",_checks,_fails])
	get_tree().quit(0 if _fails==0 else 1)
