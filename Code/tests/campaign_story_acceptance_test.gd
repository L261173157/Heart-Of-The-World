## 第三至六章的真实场景验收。各阶段从前一独立进程实际完成的存档继续。
## 序列/选择通过可见按钮提交；路线和破障使用原玩家移动、攻击与碰撞。
extends "res://tests/campaign_acceptance_test.gd"

const Catalog := preload("res://scripts/main/campaign_catalog.gd")
const C3 := "watch_c3_swamp"
const C4 := "watch_c4_hill"
const C5 := "watch_c5_snow"
const C6 := "watch_c6_lava"

func _campaign_approach(prop: Node2D, offset: Vector2, query: PhysicsShapeQueryParameters2D) -> Vector2:
	for approach: Vector2 in [offset, Vector2(56,0), Vector2(-56,0), Vector2(0,-56), Vector2(44,44), Vector2(-44,44)]:
		# 18px是原步行到达容差，仍须完整留在此实际对象的94px交互范围内。
		if approach.length()+18.0 > CampaignLayout.INTERACT_DISTANCE: continue
		var at := prop.global_position + approach
		if _walk_blocked(at, query): continue
		var ray := PhysicsRayQueryParameters2D.create(at, prop.global_position, 1)
		ray.exclude = [_player.get_rid()]
		if not _world.get_world_2d().direct_space_state.intersect_ray(ray).is_empty(): continue
		if _walk_plan(_player.global_position,at,query).is_empty(): continue
		return at
	return Vector2.INF

func _cw(id: String, offset := Vector2(0, 56)) -> bool:
	var prop := _cp(id)
	_check(prop != null, "主线真实目标存在：" + id)
	if prop == null: return false
	var at := _campaign_approach(prop,offset,_walk_query())
	_check(at.is_finite(), "目标具有可实际站立、实走到达且视线畅通的交互点："+id)
	if not at.is_finite(): return false
	return await _walk_to(at, "主线实走" + id)

func _expected() -> Dictionary:
	var expected := super._expected()
	# 第一批曾只保存冻结金额，完整目录补录预算target；只允许从固定章节编号重建此已知新增键。
	var q: Dictionary = expected.get("campaign", {})
	for id: String in q.get("chapters", {}):
		if not q["chapters"][id].has("target"):
			q["chapters"][id]["target"] = 4 + int(Catalog.chapter(id).get("number", -100))
	for id: String in q.get("quests", {}):
		var contract: Dictionary = q["quests"][id].get("contract", {})
		if contract.get("family", "") == "main" and not contract.has("target"):
			contract["target"] = 4 + int(Catalog.chapter(str(Catalog.stage(id).get("chapter", ""))).get("number", -100))
	return expected

func _cold_campaign_expected() -> void:
	super._cold_campaign_expected()
	var saved: Dictionary = _expected().get("campaign", {})
	var pending: Dictionary = saved.get("main_routes", {}).duplicate(true)
	for key: String in pending.keys():
		var split := key.rsplit(":", true, 1)
		if saved.get("quests", {}).get(split[0], {}).get("evidence", {}).has(key): pending.erase(key)
	_check(_same(_cq().get("main_routes", {}), pending), "独立进程保留尚未走完的真实路线前缀")
	_check(_same(_cq().get("main_kills", {}), saved.get("main_kills", {})), "独立进程保留实名Boss贡献，不制造新讨伐")

func _proof(stage_id: String, action_id: String) -> Dictionary:
	return _cq().get("quests", {}).get(stage_id, {}).get("evidence", {}).get(action_id, {})

func _choice_ui(object_id: String, action_id: String, cancel_first := false, close_result := true) -> bool:
	if not await _ci(object_id, false): return false
	var option := _option(action_id)
	_check(option != null and not option.disabled, "实际分支选项可用：" + action_id)
	if option == null or option.disabled:
		_hud._close_dialogue()
		return false
	var before := _cq().duplicate(true)
	await _tap(option)
	_check(_same(before, _cq()), "选择分支只预览后果，不偷写承诺：" + action_id)
	if cancel_first:
		await _tap(_hud._dialogue_no)
		_check(_same(before, _cq()), "分支确认前返回不花任务物或改变证据：" + action_id)
		option = _option(action_id)
		if option == null: return false
		await _tap(option)
	await _tap(_hud._dialogue_yes)
	if close_result: _hud._close_dialogue()
	await _frames()
	return true

func _travel_story(terrain: String, origin_id: String, leave_reward_room := true) -> bool:
	if not await _cw(origin_id): return false
	_player.set_physics_process(true)
	await _frames(12)
	_player.set_physics_process(false)
	var world_processing := _world.is_processing()
	_world.set_process(false)
	var resources := _resources()
	var ecology := _world_clock()
	if not await _choice_ui(origin_id, "campaign|depart|" + terrain + "|" + origin_id, true):
		_world.set_process(world_processing)
		return false
	for _i in 180:
		await _frames(1)
		if _at_campaign_entry(terrain) and not _world._teleporting: break
	_check(_at_campaign_entry(terrain), "真实远征抵达下一地形当前安全接近点：" + terrain)
	_check(_same(resources, _resources()) and _same(ecology, _world_clock()), "跨章旅行保留资源、冷却与整个生态时钟：" + terrain)
	_world.set_process(world_processing)
	# C2已单独检验满99；后续章只留一个明确奖励位置，避免用自动溢出掩盖主线验证。
	if leave_reward_room and GameState.count_item("onigiri") == 99: GameState.remove_item("onigiri", 1)
	return _at_campaign_entry(terrain)

func _do_action(action: Dictionary, choice := "") -> bool:
	var id := str(action["id"])
	var object_id := str(action["object"])
	if not await _cw(object_id): return false
	if action["kind"] in ["choice", "encounter"]:
		if not await _choice_ui(object_id, "campaign|act|" + id + "|" + choice, true): return false
	else:
		await _ci(object_id)
	_check(not _proof(action["stage"], id).is_empty(), "实际动作留下唯一具名证据：" + id)
	if action["kind"] == "observe":
		var snapshot: Dictionary = _proof(action["stage"], id).get("snapshot", {})
		_check(not snapshot.is_empty() and snapshot.get("region_id", "") != "" and snapshot.get("species_counts") is Dictionary
			and int(snapshot.get("tick", -1)) >= 0, "实地观察保存具名区域、时刻与真实可见种群快照：" + id)
	return not _proof(action["stage"], id).is_empty()

func _stage_actions(chapter: String, number: int) -> Array:
	return Catalog.stage(chapter + ":s" + str(number)).get("actions", [])

func _normal_stage(chapter: String, number: int) -> bool:
	for action: Dictionary in _stage_actions(chapter, number):
		if not await _do_action(action): return false
	_check(_campaign_data.ready(_cq(), chapter + ":s" + str(number)), "具名节拍通过真实现场动作完成：" + chapter + ":s" + str(number))
	return _campaign_data.ready(_cq(), chapter + ":s" + str(number))

func _break_registered(id: String) -> bool:
	var cells: Array = _campaign_layout.barrier_cells(id)
	_check(not cells.is_empty(), "登记破障具有同源实际格：" + id)
	if cells.is_empty(): return false
	var cell: Vector2i = cells[cells.size() / 2]
	var at := (Vector2(cell) + Vector2.ONE * 0.5) * 32.0
	if not await _walk_to(at + Vector2(0, 52), "真实挥砍破障站位：" + id, 8.0): return false
	_check(ObstacleField.is_obstacle_cell(cell), "挥砍前该登记障碍真实存在：" + id)
	_player.facing = Vector2.UP
	for _hit in 4:
		if not ObstacleField.is_obstacle_cell(cell): break
		_player.set_physics_process(true)
		TouchInput.queue_attack()
		await _frames(20)
		_player.set_physics_process(false)
		_freeze_monsters()
	_check(not ObstacleField.is_obstacle_cell(cell), "原玩家普通攻击打碎登记障碍：" + id)
	return not ObstacleField.is_obstacle_cell(cell)

func _c3_prepare() -> void:
	if _player.global_position.distance_to(_cp("c2:beacon").global_position) > 5000.0:
		if not await _depart_forest(): return
	if not await _travel_story("swamp", "c2:beacon"): return
	if not await _normal_stage(C3, 1): return
	await _normal_stage(C3, 2)
	_check(_cq().get("quests", {}).get(C3 + ":s3", {}).get("choice", "") == "", "两条路实勘完成仍等待玩家明确选择")

func _c3_route(route: String, partial := false) -> void:
	var actions := _stage_actions(C3, 3)
	var old_choice := str(_cq().get("quests", {}).get(C3 + ":s3", {}).get("choice", ""))
	if old_choice == "":
		if not await _do_action(actions[0], route): return
	else:
		_check(old_choice == route, "冷启动保留原路线选择，不偷偷换路")
	var before := _cq().duplicate(true)
	_campaign.perform_action(C3 + ":s3:reach")
	_check(_same(before, _cq()), "选择路线不等于远程抵达接应点")
	var points: Array = _campaign_layout.route_waypoints(route)
	if old_choice == "":
		# 故意注入不连续位移作为否定夹具，证明不能用传送/静止等待冒充走完路线。
		_player.teleport_to(points[-1])
		await _frames(6)
		_campaign.perform_action(C3 + ":s3:reach")
		_check(_proof(C3 + ":s3", C3 + ":s3:reach").is_empty(), "直接传送到终点并等待也不能冒充真实通行")
		_player.teleport_to(points[0])
		await _frames(6)
		if route == "near":
			# 真实绕到北侧后靠近近路圆形检查点，不能把未破岩的外缘绕行冒记成近路。
			var center: Vector2 = _campaign_layout.site_center("swamp")
			for point: Vector2 in [points[1], center+Vector2(-576,224), center+Vector2(-576,-288), center+Vector2(0,-64), points[3], points[4]]:
				if not await _walk_to(point, "未破岩的真实外缘否定路线", 14.0): return
				await _frames(3)
			_campaign.perform_action(C3 + ":s3:reach")
			_check(_proof(C3 + ":s3", C3 + ":s3:reach").is_empty(), "岩障完整时真实绕行也不能冒记成近路通行")
			if not _proof(C3 + ":s3", C3 + ":s3:reach").is_empty(): return
			if not await _walk_to(points[0], "真实返回近路起点后再破岩", 14.0): return
	if route == "near" and old_choice == "" and not await _break_registered("c3:near_barrier"): return
	var count := 2 if partial else points.size()
	for i in count:
		if not await _walk_to(points[i], "真正实走" + route + "路线点" + str(i), 16.0): return
		await _frames(3)
	if partial:
		var visited: Array = _cq().get("main_routes", {}).get(C3 + ":s3:reach", {}).get("visited", [])
		_check(visited.size() >= 2 and visited.size() < points.size(), "部分真实路线保存前缀而不提前登记抵达")
		return
	for i in range(1, actions.size()):
		if not await _do_action(actions[i]): return
	var proof := _proof(C3 + ":s3", C3 + ":s3:reach")
	_check(proof.get("route", "") == route and proof.get("traversed", false), "实际通行证据仅对应本次选择路线：" + route)
	if not await _normal_stage(C3, 4): return
	_check(_cp("c3:survivor").get("rescued") and _cp("c3:beacon").get("repaired"), "沼泽幸存者与联络灯显示真实完成结果")

func _c4() -> void:
	if not await _travel_story("hill", "c3:beacon"): return
	if not await _normal_stage(C4, 1) or not await _normal_stage(C4, 2): return
	var actions := _stage_actions(C4, 3)
	if not await _do_action(actions[0]): return
	var population := _world_clock()
	if not await _do_action(actions[1], "bypass"): return
	_check(_proof(C4 + ":s3", C4 + ":s3:passage").get("outcome", "") == "bypass", "丘陵实际西翼机关记录绕行而不是讨伐")
	_check(_same(population, _world_clock()), "丘陵绕行不移走、杀死或重造原Boss与种群")
	if not await _do_action(actions[2]): return
	await _normal_stage(C4, 4)

func _board_sequence(action: Dictionary, partial := false, resume := false) -> bool:
	if not await _cw(action["object"]): return false
	var order: Array = action["puzzle_order"]
	if not resume:
		var wallet := _wallet()
		if not await _choice_ui(action["object"], "campaign|sequence|" + str(action["id"]) + "|" + str(order[-1])): return false
		_check(_proof(action["stage"], action["id"]).is_empty() and _wallet() == wallet, "错误日志因果顺序不完成机关或发奖")
	else:
		_check(_cq().get("puzzle_progress", {}).get(action["id"], []) == [order[0]], "证据板首张因果在独立冷进程保留")
	for index in range(1 if resume else 0, 1 if partial else order.size()):
		var symbol: String = order[index]
		if not await _choice_ui(action["object"], "campaign|sequence|" + str(action["id"]) + "|" + symbol): return false
	if partial:
		_check(_proof(action["stage"], action["id"]).is_empty() and _cq().get("puzzle_progress", {}).get(action["id"], []) == [order[0]], "首张因果实际发布/保存，但未提前完成日志谜题")
		return _proof(action["stage"], action["id"]).is_empty()
	_check(_proof(action["stage"], action["id"]).get("order", []) == order, "现场证据板按实读日志正确排列因果")
	return not _proof(action["stage"], action["id"]).is_empty()

func _c5(partial := false) -> void:
	if not await _travel_story("snow", "c4:beacon"): return
	var first := _stage_actions(C5, 1)
	if not await _do_action(first[0]): return
	if not await _cw("c5:ice_barrier"): return
	var before := _cq().duplicate(true)
	_campaign.object_action("c5:ice_barrier")
	_check(_same(before, _cq()), "未实际破冰不能按确认按钮伪造冰障摧毁")
	if not await _break_registered("c5:ice_barrier"): return
	if not await _do_action(first[1]) or not await _do_action(first[2]): return
	if not await _normal_stage(C5, 2): return
	var logs := _stage_actions(C5, 3)
	if not await _do_action(logs[0]) or not await _do_action(logs[1]): return
	if not await _board_sequence(logs[2], partial): return
	if partial: return
	await _normal_stage(C5, 4)

func _c5_finish() -> void:
	if not await _board_sequence(_stage_actions(C5, 3)[2], false, true): return
	await _normal_stage(C5, 4)

func _c6_prepare_empty() -> void:
	if not await _travel_story("lava", "c5:beacon"): return
	if not await _normal_stage(C6, 1): return
	var stages := _stage_actions(C6, 2)
	if not await _do_action(stages[0]): return
	if not await _cw(stages[1]["object"]): return
	var before := _cq().duplicate(true)
	_campaign.perform_action(stages[1]["id"], "absent")
	_check(_same(before, _cq()), "活着的原熔岩龟王不能登记为空城")
	var boss: MonsterInstance
	for inst: MonsterInstance in WorldSim.sim.instances.values():
		if inst.is_alive and inst.species.species_name == "熔岩龟王": boss = inst
	_check(boss != null, "自然空城边界夹具从原世界真实活Boss开始")
	if boss == null: return
	# 仅此边界夹具缩短既有Boss剩余寿命；死亡仍由原模拟tick权威产生，未刷怪或发玩家杀敌事件。
	boss.lifespan = boss.age + 1
	WorldSim.sim.tick()
	await _frames(3)
	_check(not boss.is_alive and not _cq().get("main_kills", {}).has("熔岩龟王"), "真实自然死亡不产生个人讨伐凭据")
	EventBus.monster_killed_at.emit(boss.id, boss.species.species_name, boss.region_id, boss.spawn_pos)
	_check(not _cq().get("main_kills", {}).has("熔岩龟王"), "自然死亡ID即使重放贡献回调也不能冒领讨伐")
	if not await _do_action(stages[1], "absent") or not await _do_action(stages[2]): return
	var core := _stage_actions(C6, 3)
	var order: Array = core[0]["puzzle_objects"]
	var wallet := _wallet()
	if not await _cw(str(order[-1])): return
	await _ci(str(order[-1]))
	_check(_proof(C6 + ":s3", C6 + ":s3:core_order").is_empty() and _wallet() == wallet,
		"终章核心错误首符既不解锁也不发奖，允许现场重试")
	for object_id: String in order:
		if not await _cw(object_id): return
		await _ci(object_id)
	_check(not _proof(C6 + ":s3", C6 + ":s3:core_order").is_empty(), "世界之心按西、东、中真实物件顺序解锁")
	if not await _do_action(core[1]): return
	_check(_cq().get("quests", {}).get(C6 + ":s4", {}).get("choice", "") == "", "核心启动仍不替玩家决定最终派驻")

func _c6_live() -> void:
	if not await _travel_story("lava", "c5:beacon"): return
	if not await _normal_stage(C6, 1): return
	var actions := _stage_actions(C6, 2)
	if not await _do_action(actions[0]): return
	if not await _cw(actions[1]["object"]): return
	var before := _cq().duplicate(true)
	_campaign.perform_action(actions[1]["id"], "defeated")
	_check(_same(before, _cq()), "真实活龟王不能仅靠对话按钮登记本人讨伐")
	var boss: MonsterInstance
	for inst: MonsterInstance in WorldSim.sim.instances.values():
		if inst.is_alive and inst.species.species_name == "熔岩龟王": boss = inst
	_check(boss != null, "正向讨伐使用原世界原锚点原ID的活熔岩龟王")
	if boss == null: return
	_world._stream_pass()
	await _frames(4)
	var body: MonsterBase = _world._nodes.get(boss.id)
	_check(body != null and body.inst == boss, "原Boss实际战斗实体装配，不使用任务替身")
	if body == null: return
	# 原Boss占地随体型放大。固定56px目标的格心可能仍落在真实身体里；
	# 只从实际可站立的近身点中选路，不缩碰撞、不移动Boss或穿过原城塞。
	var melee_candidates: Array[Vector2] = []
	var query := _walk_query()
	for radius: float in [72.0, 88.0]:
		for direction: Vector2 in [Vector2.DOWN,Vector2.LEFT,Vector2.RIGHT,Vector2.UP]:
			var at := body.global_position + direction * radius
			var grid_center := (at / 32.0).floor() * 32.0 + Vector2(16,16)
			if not _walk_blocked(at,query) and not _walk_blocked(grid_center,query): melee_candidates.append(at)
	melee_candidates.sort_custom(func(a: Vector2,b: Vector2) -> bool:
		return _player.global_position.distance_squared_to(a) < _player.global_position.distance_squared_to(b))
	_check(not melee_candidates.is_empty(), "原Boss近身存在不穿透实际体型碰撞的合法战位")
	if melee_candidates.is_empty(): return
	if not await _walk_to(melee_candidates[0], "实际走入原城塞Boss近身战位", 8.0): return
	var contract: Dictionary = _cq()["chapters"][C6].duplicate(true)
	# 明示强构筑夹具：验证原Boss AI、玩家输入、碰撞、权威死亡和贡献收据，不宣称普通角色难度。
	GameState.stats.level = 20
	GameState.stats.strength = 120
	GameState.stats.agility = 20
	GameState.stats.intellect = 20
	GameState.stats.changed.emit()
	_player.current_hp = _player.stats.max_hp()
	_player.current_mp = _player.stats.max_mp()
	_player._protect_timer = 0.0
	_player._hurt_iframes = 0.0
	body.set_physics_process(true)
	_player.set_physics_process(true)
	var actual_windups := 0
	var healthy := _player.current_hp
	for _opening in 36:
		await _frames(1)
		if body.state == MonsterBase.S_ATTACK or body.state == Guardian.S_WINDUP: actual_windups += 1
	_check(_player.current_hp < healthy, "原Boss实际蓄力并命中玩家，原攻击判定保持有效")
	for _step in 180:
		if not boss.is_alive or _player._is_dead: break
		_player.facing = _player.global_position.direction_to(body.global_position)
		TouchInput.joystick_active = true
		TouchInput.move_vector = _player.facing if _player.global_position.distance_to(body.global_position) > 58.0 else Vector2.ZERO
		TouchInput.queue_attack()
		await _frames(6)
		if body.state == MonsterBase.S_ATTACK or body.state == Guardian.S_WINDUP: actual_windups += 1
	TouchInput.reset()
	_player.set_physics_process(false)
	body.set_physics_process(false)
	_check(not _player._is_dead and not boss.is_alive, "强构筑夹具通过实际输入/碰撞战胜活动中的原Boss")
	_check(actual_windups > 0, "讨伐期间原Boss实际运行攻击AI，而非静止木桩")
	var kill: Dictionary = _cq().get("main_kills", {}).get("熔岩龟王", {})
	_check(int(kill.get("instance_id", -1)) == boss.id and kill.get("player_kill", false)
		and kill.get("region_id", "") == boss.region_id, "原Boss真实权威死亡产生匹配ID/区域的个人贡献")
	_check(_same(contract, _cq()["chapters"][C6]), "战斗构筑夹具不会改变已经冻结的章节奖励预算")
	if boss.is_alive: return
	if not await _do_action(actions[1], "defeated") or not await _do_action(actions[2]): return
	_check(_proof(C6 + ":s2", C6 + ":s2:passage").get("outcome", "") == "defeated", "只有实际讨伐后才能确认本人击杀路径")

func _read_defeat() -> void:
	var proof := _proof(C6 + ":s2", C6 + ":s2:passage")
	var kill: Dictionary = _cq().get("main_kills", {}).get("熔岩龟王", {})
	_check(proof.get("outcome", "") == "defeated" and proof.get("instance_id", -1) == kill.get("instance_id", -2), "个人讨伐分支与原Boss实名贡献冷启动一致")
	var boss: MonsterInstance = WorldSim.sim.instances.get(int(kill.get("instance_id", -1)))
	_check(boss != null and not boss.is_alive, "原Boss死亡在世界存档保留，没有为剧情强制复活")

func _ending(choice: String) -> void:
	var old_checkpoints := GameState.discovered_checkpoints.duplicate()
	var outpost := _q().duplicate(true)
	var patrol_position := _prop("wounded_patrol").global_position
	var actions := _stage_actions(C6, 4)
	if not await _do_action(actions[0], choice) or not await _do_action(actions[1]): return
	_check(_campaign_data.ready(_cq(), C6 + ":s4"), "明确结局选择加现场落实完成最后节拍：" + choice)
	_verify_ending_world(choice)
	_check(_same(outpost, _q()) and _prop("wounded_patrol").global_position == patrol_position, "两种结局均保留首章原巡守和原始奖励合同")
	_check(GameState.discovered_checkpoints == old_checkpoints, "结局不撤销原检查点")
	var wallet := _wallet()
	_campaign.perform_action(actions[0]["id"], "centralized" if choice == "distributed" else "distributed")
	_campaign.claim(C6 + ":s4")
	_check(_wallet() == wallet and _cq().get("quests", {}).get(C6 + ":s4", {}).get("choice", "") == choice, "终局重复/另一选择回调不改既定结局或复付")
	await _ending_services(choice)

func _verify_ending_world(choice: String) -> void:
	for id: String in _campaign_layout.ending_positions(choice):
		var npc := _cp(id)
		_check(npc != null and npc.global_position == _campaign_layout.ending_positions(choice)[id], "结局实际驻地变更：" + id)
		_check(npc != null and not str(npc.get("service")).is_empty(), "结局新增居民具有真实服务状态：" + id)
	var shelter := _cp("ending:shelter")
	_check(shelter != null and shelter.is_visible_in_tree() == (choice == "centralized"), "避难所实体显隐真正对应所选结局")

func _ending_services(choice: String) -> void:
	var wallet := _wallet()
	var cast := {"forest":"c2:liaison","swamp":"c3:survivor","hill":"c4:map_keeper","snow":"c5:leader"}
	var origin := "c6:beacon"
	if choice == "centralized":
		if not await _travel_story("shelter", origin, false): return
	for terrain: String in cast:
		var id: String = cast[terrain]
		if choice == "distributed":
			if not await _travel_story(terrain, origin, false): return
		if not await _cw(id): return
		if not await _choice_ui(id, "campaign|shop|" + id, false, false): return
		_check(_hud._dialogue_kind == "shop" and _hud._dialogue_yes.visible, "真实驻地居民打开补给确认层：" + id)
		if _hud._dialogue_yes.visible: await _tap(_hud._dialogue_yes)
		_check(_hud.shop_panel.visible, "结局驻地实际可进入原有商店：" + id)
		if _hud.shop_panel.visible: _hud._toggle_shop()
		_hud._close_dialogue()
		origin = id
	_check(_wallet() == wallet, "四处服务访问与往返不会重复支付终章或偷偷买卖物品")

func _run() -> void:
	Engine.time_scale = 4.0
	var args := OS.get_cmdline_user_args()
	if OS.get_environment("HOTW_TEST_SAVE").is_empty() or args.size() != 1:
		_check(false, "主线阶段须由独立进程驱动器提供真实前置存档")
		_finish()
		return
	await _mount(false)
	_cold_campaign_expected()
	if _fails > 0:
		await _unmount()
		_finish()
		return
	match args[0]:
		"c3_prepare": await _c3_prepare()
		"c3_near_partial": await _c3_route("near", true)
		"c3_outer_partial": await _c3_route("outer", true)
		"c3_near": await _c3_route("near")
		"c3_outer": await _c3_route("outer")
		"c4": await _c4()
		"c5": await _c5()
		"c5_partial": await _c5(true)
		"c5_finish": await _c5_finish()
		"c6_prepare_empty": await _c6_prepare_empty()
		"c6_live": await _c6_live()
		"read_defeat": _read_defeat()
		"ending_distributed": await _ending("distributed")
		"ending_centralized": await _ending("centralized")
		"read_ending":
			_check(_campaign_data.ready(_cq(), C6 + ":s4"), "独立冷进程仍保留六章完成和结局")
			_verify_ending_world(str(_cq().get("quests",{}).get(C6+":s4",{}).get("choice","")))
		_:
			_check(false, "未知完整主线验收阶段：" + args[0])
	if _fails == 0 and args[0] not in ["read_ending", "read_defeat"]:
		_check(_save(), "真实主线/分支/结局原子写盘：" + args[0])
		_write_campaign_expected()
	await _unmount()
	_finish()

func _finish() -> void:
	print("CAMPAIGN_STORY_WALKED_PIXELS ", snappedf(_walked, 1.0))
	print("=== CAMPAIGN STORY ACCEPTANCE %s (%d checks, %d failures) ===" % ["PASS" if _fails == 0 else "FAIL", _checks, _fails])
	get_tree().quit(0 if _fails == 0 else 1)
