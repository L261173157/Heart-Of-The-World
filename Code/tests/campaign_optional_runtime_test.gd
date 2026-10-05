## 人物/区域线的真实 CampaignWorld 物件与运行层回归。
## 受控位置/生态夹具明确用于分支覆盖；不宣称首次玩家时长或完整战斗验收。
extends Node
const Optional := preload("res://scripts/main/campaign_optional.gd")
const Catalog := preload("res://scripts/main/campaign_catalog.gd")
const Data := preload("res://scripts/main/campaign_quest_data.gd")
const World := preload("res://scripts/main/campaign_world.gd")
class FixtureHost extends CampaignQuest:
	var optional_enabled := true
	func _chapter_enabled(chapter: Dictionary) -> bool:
		return optional_enabled and not chapter.is_empty()
var _host: FixtureHost
var _optional: CampaignOptional
var _world: CampaignWorld
var _player: CharacterBody2D
var _checks := 0
var _fails := 0

func _ready() -> void:
	GameState.save_enabled = false
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		push_error("OPTIONAL FAIL " + label)

func _frames(count := 2) -> void:
	for _i in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func _fresh() -> void:
	GameState.campaign_quest = Data.create(GameState.world_seed)
	GameState.gold = 0
	var evidence := {}
	for id: String in Data.Outpost.EVIDENCE: evidence[id] = true
	Data.authorize_chapter1(GameState.campaign_quest, {"id": "lost_outpost_v1", "evidence": evidence, "outcome": "survey", "survey_confirmed": true})
	# 解锁主线是明确的账本夹具；本测试的被测行为是下方真实可选物件与分支。
	for chapter: Dictionary in Catalog.main_chapters():
		Data.accept_chapter(GameState.campaign_quest, chapter["id"], 30)
		for stage: Dictionary in chapter["steps"]:
			for a: Dictionary in stage["actions"]:
				var proof := {"position": [100,200], "tick": 1, "destination": a["object"]}
				if a["kind"] == "puzzle": proof["order"] = a["puzzle_order"]
				if a["kind"] == "choice":
					var option: Variant = a["choices"][0]
					proof["choice"] = option["id"] if option is Dictionary else option
				if a["kind"] == "obstacle":
					proof["obstacle_key"] = a["object"]
					proof["destroyed"] = true
				if a["kind"] == "encounter":
					proof["outcome"] = "absent"
					proof["verified"] = true
				if a["kind"] == "route":
					proof["route"] = "near"
					proof["traversed"] = true
				if a.has("quest_item"): proof["item"] = a["quest_item"]
				Data.record(GameState.campaign_quest, stage["id"], a["id"], proof)
			Data.mark_paid(GameState.campaign_quest, stage["id"])
	ObstacleField.restore_destroyed([])
	_optional._last_player_position = Vector2.INF
	_refresh()

func _refresh() -> void:
	if _world == null or _host == null or _optional == null: return
	var state := _host.visual_state()
	state["enabled_batch"] = 3 if _host.optional_enabled else 2 # 明确的未来批次夹具，不改变生产开关
	var patch := _optional.visual_state()
	for key: String in patch:
		if patch[key] is Dictionary:
			if not state.has(key): state[key] = {}
			state[key].merge(patch[key], true)
		elif patch[key] is Array:
			if not state.has(key): state[key] = []
			for value: Variant in patch[key]:
				if value not in state[key]: state[key].append(value)
	_world.refresh_state(state)

func _go(id: String) -> bool:
	var object := _world.object_node(id)
	_check(object != null, "注册实际对象 " + id)
	if object == null: return false
	for offset: Vector2 in [Vector2(0,48), Vector2(48,0), Vector2(-48,0), Vector2(0,-48), Vector2.ZERO]:
		_player.position = object.global_position + offset
		_optional._last_player_position = Vector2.INF
		await _frames()
		if bool(object.call("can_interact")): return true
	_check(false, "对象现场可交互 " + id)
	return false

func _cold() -> void:
	var before := _optional.visual_state()
	GameState.campaign_quest = Data.sanitize(JSON.parse_string(JSON.stringify(GameState.campaign_quest)), GameState.world_seed)
	_refresh()
	_check(JSON.stringify(before) == JSON.stringify(_optional.visual_state()), "冷恢复保持实体分支、服务、门与实物状态")

func _run() -> void:
	print("OPTIONAL SETUP begin")
	BiomeMap.configure(GameState.world_seed)
	_world = World.new()
	add_child(_world)
	print("OPTIONAL SETUP world")
	_player = CharacterBody2D.new()
	_player.add_to_group("player")
	add_child(_player)
	_host = FixtureHost.new()
	add_child(_host)
	print("OPTIONAL SETUP host")
	_attach_optional()
	_host.changed.connect(_refresh)
	print("OPTIONAL SETUP helper")
	await _frames()
	_check(Catalog.side_chains().size() == 8 and Catalog.regional_arcs().size() == 6, "八条人物线与六条区域线目录已装配")
	if Catalog.side_chains().size() != 8 or Catalog.regional_arcs().size() != 6:
		get_tree().quit(1)
		return
	print("OPTIONAL SETUP frames complete")
	for branch_set: int in 2:
		print("OPTIONAL SETUP fresh ", branch_set)
		_fresh()
		for chain: Dictionary in Catalog.side_chains():
			if not OS.get_environment("HOTW_OPTIONAL_ONLY").is_empty() and chain["id"] != OS.get_environment("HOTW_OPTIONAL_ONLY"): continue
			await _complete_chain(chain, branch_set)
		for chain: Dictionary in Catalog.regional_arcs():
			if not OS.get_environment("HOTW_OPTIONAL_ONLY").is_empty() and chain["id"] != OS.get_environment("HOTW_OPTIONAL_ONLY"): continue
			await _complete_chain(chain, branch_set)
	if OS.get_environment("HOTW_OPTIONAL_ONLY").is_empty():
		await _negative_controls()
		await _ecology_controls()
		await _forest_nest_control()
		await _troll_challenge_control()
	elif OS.get_environment("HOTW_OPTIONAL_ONLY") == "ecology":
		await _ecology_controls()
	if _fails == 0: print("=== CAMPAIGN OPTIONAL RUNTIME PASS (%d checks) ===" % _checks)
	get_tree().quit(1 if _fails > 0 else 0)

func _complete_chain(chain: Dictionary, branch_set: int) -> void:
	print("OPTIONAL CHAIN ", chain["id"], " branch ", branch_set)
	for stage: Dictionary in chain["steps"]:
		var origin := _optional._start_object(stage)
		if not await _go(origin): return
		var offered := _optional.object_payload(origin)
		_check(offered.get("kind", "") == "camp_action", "真实故事发布物件提供接取 " + str(stage["id"]))
		var before := JSON.stringify(GameState.campaign_quest)
		_optional.object_payload(origin)
		_check(before == JSON.stringify(GameState.campaign_quest), "只读与取消不接取/不消耗物件")
		_optional.accept_stage(stage["id"], origin)
		_check(GameState.campaign_quest.get("quests", {}).get(stage["id"], {}).get("accepted", false), "具名阶段接取 " + str(stage["id"]))
		for a: Dictionary in stage["actions"]:
			if a.get("optional", false): continue
			var choice := ""
			if a["kind"] == "choice":
				var choices: Array = a["choices"]
				var option: Variant = choices[mini(branch_set, choices.size()-1)]
				choice = str(option.get("id", "")) if option is Dictionary else str(option)
				# 耗尽夹具覆盖合法警示/绕行；有限狩猎另用实名活体夹具验收。
				if chain["id"] == "side_hunter": choice = "warning"
				if chain["id"] == "region_forest": choice = "outer"
			if a["kind"] == "puzzle":
				var runes: Array = a.get("puzzle_objects", [])
				_check(runes.size() == 3, "巨魔房间有三枚实际符记")
				if runes.size() != 3: return
				await _go(runes[1])
				_optional.touch_rune(a["id"], runes[1])
				_check(not _optional._done(a), "错误次序不开门、不取房间档案")
				for rune: String in runes:
					await _go(rune)
					_optional.touch_rune(a["id"], rune)
			elif a["kind"] == "route":
				await _go(_optional.action_object(a))
				_optional.perform_action(a["id"])
				_check(not _optional._done(a), "未实走登记路线不能仅点击站点验收")
				await _walk_route(a)
				_optional.perform_action(a["id"])
			else:
				var object_id := _optional.action_object(a)
				var destinations: Dictionary = a.get("destination_by_choice", a.get("branch_objects", {}))
				for other: String in destinations.values():
					if other == object_id: continue
					if not await _go(other): return
					var unchanged := JSON.stringify(GameState.campaign_quest)
					_optional.perform_action(a["id"])
					_check(unchanged == JSON.stringify(GameState.campaign_quest), "未选中的真实分支地点不能交付或施工")
				if not await _go(object_id): return
				var barriers: Dictionary = a.get("obstacle_by_choice", {})
				if barriers.has(_optional._choice(a)):
					_optional.perform_action(a["id"])
					_check(not _optional._done(a), "登记路障未破不能点击施工通过")
					for cell: Vector2i in CampaignLayout.barrier_cells(barriers[_optional._choice(a)]):
						ObstacleField.damage_cell(cell)
						ObstacleField.damage_cell(cell)
				_optional.perform_action(a["id"], choice)
			_check(_optional._done(a), "现场行动完成 " + str(a["id"]))
			var wallet: int = GameState.gold
			var saved := JSON.stringify(GameState.campaign_quest)
			_optional.perform_action(a["id"], choice)
			_check(wallet == GameState.gold and saved == JSON.stringify(GameState.campaign_quest), "反复点击不重复证据或付款")
		_check(Data.ready(GameState.campaign_quest, stage["id"]), "阶段前置和分支完整 " + str(stage["id"]))
		_check(Data.paid(GameState.campaign_quest, stage["id"]), "独立阶段收据已支付 " + str(stage["id"]))
		_cold()
		_capture_snapshot(stage["id"], branch_set)
	if chain["id"] in ["side_patrol", "side_merchant", "side_watchman"]:
		var final: Dictionary = chain["steps"][-1]["actions"][-1]
		var target := _optional.action_object(final)
		_check(_world.object_node(str(chain["id"]) + ":giver").global_position.distance_to(CampaignLayout.object_position(target) + Vector2(64,0)) < 0.1, "新增驻守演员实际位于所选站点")
		_check(_optional.visual_state()["services"].has(target), "所选站点具备真实服务入口")
		await _test_service(target)
		_capture_snapshot(str(chain["id"]) + ":s2", branch_set, "service")
	if chain["id"] == "side_herbalist":
		_check(not _optional._has_item("side_herbalist:medicine"), "唯一药包交付后不可再次用于另一需求")
	if chain["id"] == "side_merchant":
		_check(not _optional._has_item("side_merchant:crate"), "唯一封箱不能复制到另一站点")

func _walk_route(a: Dictionary) -> void:
	var points := _optional._route_points(a)
	if points.is_empty():
		_check(false, "路线缺少物理验收点")
		return
	await _go(points[0])
	_optional._track_routes()
	var retained: Array = _optional._q().get("optional_routes", {}).get(a["id"], []).duplicate()
	# 反证：直接跳到其后每个角点并停一帧，不得得到实走凭证。
	var fake_points: Array = _optional.route_geometry(a)
	fake_points.append(_world.object_node(points[-1]).global_position)
	for point: Vector2 in fake_points:
		_player.position = point
		_optional._track_routes()
		_optional._track_routes()
	_optional.perform_action(a["id"])
	_check(not _optional._done(a), "逐点传送后等待不能冒充真实路线行走")
	_check(_optional._q().get("optional_routes", {}).get(a["id"], []) == retained and _optional._q().get("optional_route_reanchor", {}).get(a["id"], false), "死亡或远征跳位保留已核实贡献，只标记需要接续")
	_cold()
	_check(_optional._q().get("optional_routes", {}).get(a["id"], []) == retained and _optional._q().get("optional_route_reanchor", {}).get(a["id"], false), "冷恢复保留路线前缀和接续要求")
	_capture_snapshot(a["stage"], 0 if _optional._choice(a) == "near" else 1, "route_resume")
	await _go(points[0])
	_optional._track_routes()
	var destinations: Array = _optional.route_geometry(a)
	for id: String in points.slice(1): destinations.append(_world.object_node(id).global_position + Vector2(0,48))
	for destination: Vector2 in destinations:
		await _walk_safe(destination)
		_optional._track_routes()
	if _optional._q().get("optional_routes", {}).get(a["id"], []) != points:
		print("OPTIONAL ROUTE INCOMPLETE ", a["id"], " branch=", _optional._choice(a), " visits=", _optional._q().get("optional_routes", {}), " corners=", _optional._q().get("optional_route_steps", {}), " anchor=", _optional._q().get("optional_route_reanchor", {}), " at=", _player.position)
	_check(_optional._q().get("optional_routes", {}).get(a["id"], []) == points, "沿登记路线有序实走到达各点")

func _negative_controls() -> void:
	_fresh()
	_check(_optional._segment_near(Vector2(-100,0), Vector2(100,0), Vector2.ZERO, 90), "冲刺跨过路线核实圆使用扫过线段，不因两端在圆外漏记")
	var chain: Dictionary = Catalog.side_chains()[0]
	var stage: Dictionary = chain["steps"][0]
	var action_data: Dictionary = stage["actions"][0]
	_player.position = Vector2.ZERO
	var saved := JSON.stringify(GameState.campaign_quest)
	_optional.accept_stage(stage["id"], _optional._start_object(stage))
	_optional.perform_action(action_data["id"])
	_check(saved == JSON.stringify(GameState.campaign_quest), "远程接取与行动被拒绝")
	await _go(_optional._start_object(stage))
	_host.optional_enabled = false
	_optional.accept_stage(stage["id"], _optional._start_object(stage))
	_check(saved == JSON.stringify(GameState.campaign_quest), "批次未开放不能激活内容")
	_host.optional_enabled = true
	var ordinary: Array = GameState.quests.get("active", []).duplicate(true)
	GameState.quests["active"] = [{"id": "fixture_a"}, {"id": "fixture_b"}, {"id": "fixture_c"}]
	_optional.accept_stage(stage["id"], _optional._start_object(stage))
	_check(GameState.campaign_quest.get("quests", {}).get(stage["id"], {}).get("accepted", false), "普通三任务栏已满仍可独立接取作者故事")
	GameState.quests["active"] = ordinary
	var node := _world.object_node(action_data["object"])
	node.hide()
	saved = JSON.stringify(GameState.campaign_quest)
	_optional.perform_action(action_data["id"])
	_check(saved == JSON.stringify(GameState.campaign_quest), "隐藏对象不能用旧对话提交")
	node.show()
	var original_position := node.global_position
	node.global_position += Vector2(500,0)
	_optional.perform_action(action_data["id"])
	_check(saved == JSON.stringify(GameState.campaign_quest), "对象当前已移位时旧气泡不能按历史坐标交付")
	node.global_position = original_position
	GameState.campaign_quest["paused_chains"].append(chain["id"])
	_optional.perform_action(action_data["id"])
	_check(not _optional._done(action_data), "暂停任务不接受现场证据")
	_optional.resume(chain["id"], action_data["object"])
	_optional.perform_action(action_data["id"])
	_check(_optional._done(action_data), "真实物件身旁继续保留旧进度")

func _ecology_controls() -> void:
	_fresh()
	var at := CampaignLayout.object_position("side_hunter:target")
	var region := SimRegion.new()
	region.id = BiomeMap.region_id_at(at)
	region.center = at
	region.capacity = 40
	var species := load("res://data/species/goblin.tres") as SpeciesData
	if species == null:
		_check(false, "既有哥布林物种夹具可加载")
		return
	var sim := EcologySim.new()
	var list: Array[SpeciesData] = [species]
	sim.setup([region], list, {})
	WorldSim.start(sim)
	WorldSim.set_process(false)
	_optional._bind_sim()
	var bodies: Array[MonsterBase] = []
	for index in 7:
		var point := at + Vector2(-80 + index * 32, 80)
		var inst := sim.spawn_instance(species, region.id, 0, 0, 1.0, false, point)
		var body := preload("res://scenes/monsters/goblin.tscn").instantiate() as MonsterBase
		add_child(body)
		body.setup(inst)
		body.global_position = point
		body.set_physics_process(false)
		bodies.append(body)
	var first: Dictionary = Catalog.stage("side_hunter:s1")
	await _go("side_hunter:giver")
	_optional.accept_stage(first["id"], "side_hunter:giver")
	for a: Dictionary in first["actions"]:
		await _go(a["object"])
		_optional.perform_action(a["id"])
	await _go("side_hunter:resolution")
	_optional.accept_stage("side_hunter:s2", "side_hunter:resolution")
	_optional.perform_action("side_hunter:s2:choice", "local")
	var target := _optional._saved_target("side_hunter")
	_check(target.get("unit_ids", []).size() == 7, "有限狩猎锁定真实七只可达当前演员ID")
	var natural := bodies[-1].inst
	bodies[-1].global_position += Vector2(160,64)
	sim._die(natural, EcologySim.DEATH_AGING)
	_check(_optional._deaths.get(natural.id, {}).get("position", []) == [bodies[-1].global_position.x, bodies[-1].global_position.y], "加载演员自然死亡按当前现场记录，不以旧出生坐标代替")
	EventBus.monster_killed_at.emit(natural.id, natural.species.species_name, natural.region_id, bodies[-1].global_position)
	_check(GameState.campaign_quest.get("optional_targets", {}).get("side_hunter", {}).get("kills", []).is_empty(), "自然死亡加伪位置事件不得冒认玩家讨伐")
	# 真 MonsterBase 受击、死亡、EcologySim 死因与 EventBus 位置事件闭环。
	bodies[0].take_damage(99999, bodies[0].global_position + Vector2(20,0))
	var kills: Array = GameState.campaign_quest.get("optional_targets", {}).get("side_hunter", {}).get("kills", [])
	_check(kills.size() == 1 and int(kills[0].get("instance_id", -1)) == bodies[0].inst.id, "真实伤害击杀登记ID产生唯一有限处理信用")
	var pinned: Dictionary = kills[0].duplicate(true) if not kills.is_empty() else {}
	GameState.campaign_quest = Data.sanitize(JSON.parse_string(JSON.stringify(GameState.campaign_quest)), GameState.world_seed)
	var restored_kills: Array = GameState.campaign_quest.get("optional_targets", {}).get("side_hunter", {}).get("kills", [])
	_check(restored_kills.size() == 1 and restored_kills[0].get("instance_id", -1) == pinned.get("instance_id", -2) and restored_kills[0].get("cause", "") == "killed" and restored_kills[0].get("position", []) == pinned.get("position", []), "真实击杀贡献在最终交付前冷恢复保留")
	await _go("side_hunter:target")
	_optional.perform_action("side_hunter:s2:result")
	var result: Dictionary = GameState.campaign_quest.get("quests", {}).get("side_hunter:s2", {}).get("evidence", {}).get("side_hunter:s2:result", {})
	_check(result.get("outcome", "") == "hunt", "回到实名目标现场提交真实有限处理，不记自然死亡")
	_check(_optional._target_alive(target).size() >= 1, "有限处理仍保留当地真实余量")
	_capture_snapshot("side_hunter:s2", 0) # 以真实有限处理分支替换早先耗尽警示夹具的同名快照
	# 独立分支夹具：再次接受健康群体，再让自然变化只留下一个真实幸存者。
	_fresh()
	for index in 3:
		var point := at + Vector2(-64 + index * 48,-64)
		var inst := sim.spawn_instance(species, region.id, 0, 0, 1.0, false, point)
		var body := preload("res://scenes/monsters/goblin.tscn").instantiate() as MonsterBase
		add_child(body)
		body.setup(inst)
		body.global_position = point
		body.set_physics_process(false)
		bodies.append(body)
	await _accept_and_finish_stage("side_hunter:s1")
	await _go("side_hunter:resolution")
	_optional.accept_stage("side_hunter:s2", "side_hunter:resolution")
	_optional.perform_action("side_hunter:s2:choice", "local")
	var fading := _optional._saved_target("side_hunter")
	_check(not fading.is_empty(), "变化前的健康群体可接受有限处理分支")
	var live: Array = _optional._target_alive(fading)
	for id: int in live.slice(1):
		var inst: MonsterInstance = sim.instances[id]
		sim._die(inst, EcologySim.DEATH_AGING)
		EventBus.monster_killed_at.emit(id, species.species_name, region.id, _optional._actor_position(inst))
	await _go("side_hunter:target")
	_optional.perform_action("side_hunter:s2:result")
	var investigation: Dictionary = GameState.campaign_quest.get("quests", {}).get("side_hunter:s2", {}).get("evidence", {}).get("side_hunter:s2:result", {})
	_check(investigation.get("outcome", "") == "survey" and sim.alive_count_of_species(species.species_name) == 1, "余量只剩一只时依法调查结案，不强迫最后猎杀")
	_check(GameState.campaign_quest.get("optional_targets", {}).get("side_hunter", {}).get("kills", []).is_empty(), "自然耗减及伪事件没有转为玩家信用")
	_capture_snapshot("side_hunter:s2", 0, "depleted")
	for body: MonsterBase in bodies: body.queue_free()
	WorldSim.stop()
	await _frames()

func _test_service(object_id: String) -> void:
	if not await _go(object_id): return
	var service_id := str(_optional.visual_state().get("services", {}).get(object_id, ""))
	GameState.inventory["onigiri"] = 99
	_optional.claim_service(object_id)
	_check(GameState.inventory["onigiri"] == 99 and not GameState.campaign_quest.get("services", {}).get(service_id, {}).get("claimed", false), "满包整份服务奖励保留待领")
	GameState.inventory["onigiri"] = 98
	_optional.claim_service(object_id)
	_check(GameState.inventory["onigiri"] == 99 and GameState.campaign_quest.get("services", {}).get(service_id, {}).get("claimed", false), "腾出空间后实际领取一份驻站物资")
	_cold()
	_optional.claim_service(object_id)
	_check(GameState.inventory["onigiri"] == 99, "冷启动不能重复领取驻站补给")
	_service_damage_control(service_id, object_id)

func _walk_safe(destination: Vector2) -> void:
	var start := Vector2i((_player.position / 32.0).floor())
	var goal := Vector2i((destination / 32.0).floor())
	var queue: Array[Vector2i] = [start]
	var previous := {start: start}
	var index := 0
	var bounds := Rect2i(start.min(goal) - Vector2i(24,24), (start-goal).abs() + Vector2i(49,49))
	while index < queue.size() and queue.size() < 12000 and not previous.has(goal):
		var cell: Vector2i = queue[index]
		index += 1
		for delta: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next := cell + delta
			var position := Vector2(next) * 32.0 + Vector2(16,16)
			if previous.has(next) or not bounds.has_point(next) or ObstacleField.nav_blocked_cell(next) or ObstacleField.liquid_kind_at(position) == "lava": continue
			previous[next] = cell
			queue.append(next)
	if not previous.has(goal):
		_check(false, "真实导航未找到所选路线下一点 " + str(destination))
		return
	var path: Array[Vector2] = [destination]
	var cursor := goal
	while cursor != start:
		path.push_front(Vector2(cursor)*32.0 + Vector2(16,16))
		cursor = previous[cursor]
	for point: Vector2 in path:
		var safety := 0
		while _player.position.distance_to(point) > 1.0 and safety < 16:
			safety += 1
			var next := _player.position.move_toward(point, 16)
			_player.move_and_collide(next - _player.position)
			_optional._track_routes()
			await _frames(1)

func _accept_and_finish_stage(stage_id: String) -> void:
	var stage := Catalog.stage(stage_id)
	await _go(_optional._start_object(stage))
	_optional.accept_stage(stage_id, _optional._start_object(stage))
	for a: Dictionary in stage.get("actions", []):
		if a.get("optional", false): continue
		await _go(_optional.action_object(a))
		_optional.perform_action(a["id"])

func _forest_nest_control() -> void:
	_fresh()
	var at := CampaignLayout.object_position("region_forest:survey_a")
	var region := SimRegion.new()
	region.id = BiomeMap.region_id_at(at)
	region.center = at
	region.size = Vector2(100,100)
	region.terrain = "forest"
	region.capacity = 40
	var species := load("res://data/species/goblin.tres") as SpeciesData
	var sim := EcologySim.new()
	var species_list: Array[SpeciesData] = [species]
	sim.setup([region], species_list, {})
	WorldSim.start(sim)
	WorldSim.set_process(false)
	_optional._bind_sim()
	var bodies: Array[MonsterBase] = []
	for index in 6:
		var point := at + Vector2(-80 + index * 32, 80)
		var inst := sim.spawn_instance(species, region.id, 0, 0, 1.0, false, point)
		var body := preload("res://scenes/monsters/goblin.tscn").instantiate() as MonsterBase
		add_child(body)
		body.setup(inst)
		body.global_position = point
		body.set_physics_process(false)
		bodies.append(body)
	var nest := NestNode.new()
	add_child(nest)
	nest.setup(region.id, species.species_name, species.tint, sim.camp_pos(region, species))
	await _accept_and_finish_stage("region_forest:s1")
	await _go("region_forest:choice")
	_optional.accept_stage("region_forest:s2", "region_forest:choice")
	_optional.perform_action("region_forest:s2:choice", "near")
	_check(not _optional._saved_target("region_forest").is_empty(), "林地近线核实真实活动巢和实名存量")
	EventBus.nest_ransacked_at.emit(species.species_name, region.id, nest.global_position)
	await _go("region_forest:work_near")
	_optional.perform_action("region_forest:s2:work")
	_check(not Data.ready(GameState.campaign_quest, "region_forest:s2"), "伪捣巢事件不能替代真实巢体受击")
	for _i in 4: nest.take_damage(9999)
	_check(GameState.campaign_quest.get("optional_targets", {}).get("region_forest", {}).get("ransack", false), "真实NestNode四次受击产生临时捣巢证据")
	_cold()
	_optional.perform_action("region_forest:s2:work")
	var result: Dictionary = GameState.campaign_quest.get("quests", {}).get("region_forest:s2", {}).get("evidence", {}).get("region_forest:s2:work", {})
	_check(result.get("outcome", "") == "ransack" and sim.nests[region.id + "|" + species.species_name].get("rebuild", 0) == EcologySim.NEST_REBUILD_TICKS, "真实捣巢提交保留原120刻临时抑制，不永久清场")
	_check(sim.alive_count_in(region.id) == 6, "捣巢不凭空杀死当地怪物")
	_capture_snapshot("region_forest:s2", 0)
	await _go("region_forest:station")
	_optional.accept_stage("region_forest:s3", "region_forest:station")
	var last := Catalog.stage("region_forest:s3")
	for a: Dictionary in last["actions"]:
		if a["kind"] == "route": await _walk_route(a)
		else: await _go(_optional.action_object(a))
		_optional.perform_action(a["id"])
	_check(Data.ready(GameState.campaign_quest, "region_forest:s3"), "真实捣巢近线仍需独立实走修标完成第三段")
	_capture_snapshot("region_forest:s3", 0)
	for body: MonsterBase in bodies: body.queue_free()
	WorldSim.stop()
	await _frames()

func _troll_challenge_control() -> void:
	_fresh()
	var at := CampaignLayout.object_position("side_troll:target")
	var region := SimRegion.new()
	region.id = BiomeMap.region_id_at(at)
	region.center = at
	region.terrain = "forest"
	region.capacity = 10
	var species := load("res://data/species/treant.tres") as SpeciesData
	var sim := EcologySim.new()
	var species_list: Array[SpeciesData] = [species]
	sim.setup([region], species_list, {})
	WorldSim.start(sim)
	WorldSim.set_process(false)
	_optional._bind_sim()
	await _accept_and_finish_stage("side_troll:s1")
	_check(Data.ready(GameState.campaign_quest, "side_troll:s1"), "巨魔不存在时调查故事也可完成")
	await _go("side_troll:target")
	var saved := JSON.stringify(GameState.campaign_quest)
	_optional._challenge("side_troll:s1:challenge")
	_check(saved == JSON.stringify(GameState.campaign_quest), "没有Boss时自选挑战不生成、复活或伪造目标")
	var point := at + Vector2(-96,96)
	var inst := sim.spawn_instance(species, region.id, 0, 0, 1.0, false, point)
	var body := preload("res://scenes/monsters/guardian.tscn").instantiate() as MonsterBase
	add_child(body)
	body.setup(inst)
	body.global_position = point
	body.set_physics_process(false)
	_optional._challenge("side_troll:s1:challenge")
	_check(_optional._saved_target("side_troll").get("unit_ids", []) == [inst.id], "自选挑战绑定真实巨魔王当前ID")
	_cold()
	sim._die(inst, EcologySim.DEATH_AGING)
	EventBus.monster_killed_at.emit(inst.id, species.species_name, region.id, point)
	_check(GameState.campaign_quest.get("optional_targets", {}).get("side_troll", {}).get("kills", []).is_empty(), "巨魔王自然老死后补发玩家事件也不授讨伐")
	body.queue_free()
	await _frames()
	# 下一位Boss仅为明确测试夹具；生产运行层从不调用spawn_instance。
	inst = sim.spawn_instance(species, region.id, 0, 0, 1.0, false, point)
	body = preload("res://scenes/monsters/guardian.tscn").instantiate() as MonsterBase
	add_child(body)
	body.setup(inst)
	body.global_position = point
	body.set_physics_process(false)
	_optional._challenge("side_troll:s1:challenge")
	body.take_damage(999999, point + Vector2(24,0))
	var kills: Array = GameState.campaign_quest.get("optional_targets", {}).get("side_troll", {}).get("kills", [])
	_check(kills.size() == 1 and kills[0].get("instance_id", -1) == inst.id, "真实巨魔王受击死亡才给可选挑战信用")
	_cold()
	await _go("side_troll:target")
	var wallet := GameState.gold
	_optional.perform_action("side_troll:s1:challenge")
	_check(GameState.campaign_quest.get("quests", {}).get("side_troll:s1", {}).get("evidence", {}).has("side_troll:s1:challenge"), "回到实地提交可选Boss战绩")
	_check(GameState.gold == wallet, "可选Boss战绩不重复发放已付故事奖励")
	_capture_snapshot("side_troll:s1", 0, "challenge")
	body.queue_free()
	WorldSim.stop()
	await _frames()

func _capture_snapshot(stage_id: String, branch_set: int, suffix := "stage") -> void:
	var directory := OS.get_environment("HOTW_OPTIONAL_SNAPSHOT_DIR")
	if directory.is_empty(): return
	DirAccess.make_dir_recursive_absolute(directory)
	var stem := "%s__%d__%s" % [stage_id.replace(":", "_"), branch_set, suffix]
	var path := directory.path_join(stem + ".json")
	var old_path := GameState.SAVE_PATH
	var old_enabled := GameState.save_enabled
	GameState.SAVE_PATH = path
	GameState.destroyed_cells.assign(ObstacleField.destroyed_list())
	GameState.save_enabled = true
	var written := GameState.save_now()
	GameState.save_enabled = old_enabled
	GameState.SAVE_PATH = old_path
	_check(written and FileAccess.file_exists(path), "真实GameState原子落盘完成阶段 " + stage_id)
	var nodes := {}
	for id: String in _world.objects_by_id:
		if not id.begins_with("side_") and not id.begins_with("region_"): continue
		var node: Node2D = _world.object_node(id)
		nodes[id] = {"position": [node.global_position.x, node.global_position.y], "visible": node.visible,
			"taken": node.get("taken"), "rescued": node.get("rescued"), "repaired": node.get("repaired"),
			"gate_open": node.get("gate_open"), "service": node.get("service"), "title": node.get("title")}
	var expected := {"stage_id": stage_id, "branch": branch_set, "suffix": suffix, "ready": Data.ready(GameState.campaign_quest, stage_id),
		"paid": Data.paid(GameState.campaign_quest, stage_id), "gold": GameState.gold, "inventory": GameState.inventory.duplicate(true),
		"state": _optional.visual_state(), "nodes": nodes, "destroyed": ObstacleField.destroyed_list(),
		"optional_routes": GameState.campaign_quest.get("optional_routes", {}).duplicate(true),
		"optional_route_steps": GameState.campaign_quest.get("optional_route_steps", {}).duplicate(true),
		"optional_route_reanchor": GameState.campaign_quest.get("optional_route_reanchor", {}).duplicate(true)}
	var file := FileAccess.open(directory.path_join(stem + ".expected.json"), FileAccess.WRITE)
	_check(file != null, "独立冷启动检查清单可写")
	if file != null:
		file.store_string(JSON.stringify(expected))
		file.close()

func _attach_optional() -> void:
	# 集成后复用宿主自己的节点，不能让夹具再接第二份击杀/路线监听。
	for property: Dictionary in _host.get_property_list():
		if str(property.get("name", "")) == "_optional":
			var existing: Variant = _host.get("_optional")
			if existing is CampaignOptional:
				_optional = existing
				return
	_optional = Optional.new()
	_optional.setup(_host)
	add_child(_optional)

func _service_damage_control(service_id: String, object_id: String) -> void:
	_check(GameState.campaign_quest.get("service_receipts", {}).get(service_id, {}).get("claimed", false), "实际领取保留独立且不可逆的驻站物资收据")
	for a: Dictionary in _optional._actions():
		if a.get("service", "") != service_id or not _optional._done(a): continue
		var original: Dictionary = GameState.campaign_quest["quests"][a["stage"]]["evidence"][a["id"]].duplicate(true)
		var broken := GameState.campaign_quest.duplicate(true)
		broken["quests"][a["stage"]]["evidence"].erase(a["id"])
		broken = Data.sanitize(broken, GameState.world_seed)
		_check(broken.get("service_receipts", {}).get(service_id, {}).get("claimed", false) and not broken.get("services", {}).get(service_id, {}).get("enabled", false), "损坏施工证据禁用服务但不擦除已领物资收据")
		broken["quests"][a["stage"]]["evidence"][a["id"]] = original
		broken["services"][service_id] = {"enabled": true, "claimed": false, "status": "available", "stock_item": "onigiri"}
		var repaired := Data.sanitize(broken, GameState.world_seed)
		_check(repaired.get("services", {}).get(service_id, {}).get("claimed", false), "恢复有效施工证据不会把物资重新变成未领取")
		var prior := GameState.campaign_quest
		GameState.campaign_quest = repaired
		_refresh()
		GameState.inventory["onigiri"] = 98
		_optional.claim_service(object_id)
		_check(GameState.inventory["onigiri"] == 98, "真实服务入口拒绝损坏后恢复存档的重复领取")
		GameState.inventory["onigiri"] = 99
		GameState.campaign_quest = prior
		_refresh()
		return
