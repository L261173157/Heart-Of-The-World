## 首章独立验收：真实世界/流式活体/巢体伤害，历史与当前生态分开检查。
## 冷进程模式由 run_camp_pilot_lifecycle_test.py 串联，绝不使用真实玩家存档。
extends Node

const MAIN := preload("res://scenes/main/main.tscn")
const World := preload("res://scripts/main/game_world.gd")
const CAMP_ID := "camp_ecology_v1"
var _world: Node2D
var _player: Player
var _qm: Node
var _hud: CanvasLayer
var _checks := 0
var _fails := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.save_enabled = false
	WorldSim.set_process(false)
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok: _fails += 1
	print("  %s %s" % ["PASS" if ok else "FAIL", label])

func _frames(count := 3) -> void:
	for _i in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func _mount(fresh := false) -> void:
	if fresh:
		GameState.reset_all()
		GameState.world_seed = BiomeMap.DEFAULT_SEED
		seed(20261004)
	_world = MAIN.instantiate()
	add_child(_world)
	_player = _world.get_node("Player")
	_hud = _world.get_node("HUD")
	_world.hit_stop_enabled = false
	WorldSim.set_process(false)
	await _frames(8)
	_qm = get_tree().get_first_node_in_group("quest_manager")
	for child: Node in _world.get_children():
		if child is BountyManager: child.set_process(false)
	_player.set_physics_process(false)
	_freeze_monsters()

func _freeze_monsters() -> void:
	for body: Node in get_tree().get_nodes_in_group("monsters"):
		body.set_physics_process(false)

func _unmount() -> void:
	TouchInput.reset()
	get_tree().paused = false
	if is_instance_valid(_world): _world.queue_free()
	await _frames(3)

func _keeper() -> Node2D:
	for npc: Node in get_tree().get_nodes_in_group("npcs"):
		if str(npc.get("landmark_id")) == "camp_ecology": return npc
	return null

func _home() -> void:
	var keeper := _keeper()
	_check(keeper != null, "真实营地装配首章巡守NPC")
	if keeper != null: _player.teleport_to(keeper.global_position + Vector2(38, 0))
	_hud._close_dialogue()
	await _frames()

func _offer_ready() -> Dictionary:
	var offered := {}
	for _attempt in 240:
		offered = _qm.offer("camp_ecology", "camp_ecology", "营地巡守")
		if offered.get("kind", "") in ["quest", "camp_action"]: return offered
		await _frames(2)
	return offered

func _tap(button: Control) -> void:
	await _frames(3)
	var point := get_viewport().get_screen_transform() * button.get_global_rect().get_center()
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.position = point
	event.pressed = true
	Input.parse_input_event(event)
	await _frames()
	event = InputEventScreenTouch.new()
	event.index = 0
	event.position = point
	event.pressed = false
	Input.parse_input_event(event)
	await _frames()

func _accept() -> bool:
	await _home()
	var offered := await _offer_ready()
	_check(offered.get("kind", "") in ["quest", "camp_action"], "真实存量可达目标生成首章邀约或恢复原单")
	if offered.get("kind", "") not in ["quest", "camp_action"]: return false
	# 新角色的真实营地入口已是前哨。此旧试点契约先通过原生产接口
	# 建立一张待恢复的v12合同，再实测营地中的旧合同入口，不能把新版入口改回旧剧情。
	if GameState.camp_quest.is_empty():
		_qm.accept(offered["quest"])
		_qm.abandon(CAMP_ID)
		_check(not GameState.camp_quest.is_empty() and not GameState.camp_quest.get("active", true), "兼容夹具保留真实原合同，尚未恢复或支付")
	_player._attack_cooldown = 0.0
	_player.set_physics_process(true)
	TouchInput.queue_attack()
	await _frames(2)
	_player.set_physics_process(false)
	_check(not _hud._dialogue_panel.visible and _player._attack_cooldown > 0.0,
		"巡守身边真实普攻仍挥刀，不打开接单/领奖对话")
	if not await _open_legacy_dialogue(): return false
	_check(_hud._dialogue_panel.visible and _hud._dialogue_kind in ["quest", "camp_action"], "真实巡守对话呈现首章接取或恢复")
	var before_back := GameState.camp_quest.duplicate(true)
	await _tap(_hud._dialogue_no)
	_check(_hud._dialogue_panel.visible and _hud._dialogue_kind == "camp_choice" and get_tree().paused
		and GameState.camp_quest == before_back and GameState.outpost_quest.is_empty(), "旧合同阅读返回上一层，保持暂停且不接取/放弃/付款")
	if not await _open_legacy_dialogue(): return false
	await _tap(_hud._dialogue_yes)
	_check(GameState.camp_quest.get("active", false) and not GameState.camp_quest.get("paid", false), "独立新触点确认后写入活动未支付账本")
	for _attempt in 240:
		if not GameState.camp_quest.get("target", {}).is_empty(): return true
		await _frames(2)
	_check(false, "活动首章在有界等待内取得真实目标")
	return false

## 走当前真实营地的二层入口；每层使用新触点，不能直接跳过玩家的旧合同选择。
func _open_legacy_dialogue() -> bool:
	_keeper().interact()
	await _frames()
	_check(_hud._dialogue_kind == "camp_choice", "已有旧合同的巡守提供独立兼容入口")
	var legacy_button: Button
	for node: Node in _hud._dialogue_option_box.get_children():
		if node is Button and node.get_meta("quest_action", "") == "outpost:legacy": legacy_button = node
	_check(legacy_button != null, "原营地调查入口明确存在，未用新章吞掉旧单")
	if legacy_button == null: return false
	await _tap(legacy_button)
	await _tap(_hud._dialogue_yes)
	_check(_hud._dialogue_panel.visible and _hud._dialogue_kind in ["quest", "camp_action", "claim", "info"], "全新确认手势进入原合同阅读层")
	return _hud._dialogue_panel.visible

func _visit() -> void:
	var target: Dictionary = GameState.camp_quest.get("target", {})
	_check(not target.is_empty(), "调查使用保存的真实物种与据点")
	if target.is_empty(): return
	var pos := Vector2(float(target["pos"][0]), float(target["pos"][1]))
	_player.teleport_to(pos + Vector2(70, 0))
	_world._stream_pass()
	await _frames(5)
	_freeze_monsters()
	_qm.camp_investigate()
	await _frames()
	_hud._close_dialogue()
	_check(GameState.camp_quest.get("investigated", false), "必须真实到达现场才能留下调查历史")

func _living_target_bodies() -> Array:
	var out: Array = []
	var target: Dictionary = GameState.camp_quest.get("target", {})
	for body: Node in get_tree().get_nodes_in_group("monsters"):
		if body is MonsterBase and body.inst != null and body.inst.is_alive \
				and body.inst.region_id == target.get("region_id", "") \
				and body.inst.species.species_name == target.get("species", ""):
			out.append(body)
	return out

func _kill_one() -> int:
	var bodies := _living_target_bodies()
	_check(not bodies.is_empty(), "流式场景保有可实际受击的目标活体")
	if bodies.is_empty(): return -1
	var body: MonsterBase = bodies[0]
	var id := body.inst.id
	body.take_damage(1000000.0, _player.global_position)
	await _frames()
	_check(not body.inst.is_alive, "真实怪物受击由模拟权威登记死亡")
	return id

func _save() -> bool:
	GameState.save_enabled = true
	var saved := GameState.save_now()
	GameState.save_enabled = false
	return saved

func _wallet() -> Dictionary:
	return {"gold": GameState.gold, "xp": GameState.stats.xp, "level": GameState.stats.level,
		"inventory": GameState.inventory.duplicate(true)}

## JSON 解析把整数读为浮点；递归检查所有字段，仅数值类型按数学值比较。
func _same(a: Variant, b: Variant) -> bool:
	if typeof(a) in [TYPE_INT, TYPE_FLOAT] and typeof(b) in [TYPE_INT, TYPE_FLOAT]:
		return float(a) == float(b)
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return false
		for key: Variant in a:
			if not b.has(key) or not _same(a[key], b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size(): return false
		for index in a.size():
			if not _same(a[index], b[index]): return false
		return true
	return a == b

func _expected_path() -> String:
	return GameState.SAVE_PATH + ".camp_expected"

func _write_expected(value: Dictionary) -> void:
	var file := FileAccess.open(_expected_path(), FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()

func _expected() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(_expected_path()))

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		if OS.get_environment("HOTW_TEST_SAVE").is_empty():
			_check(false, "冷进程模式需要明确隔离存档路径")
		else:
			await _cold(args[0])
		await _finish()
		return
	GameState.SAVE_PATH = "user://camp_pilot_contract_%d.json" % OS.get_process_id()
	await _mount(true)
	if await _accept():
		await _ransack_contract()
	await _legacy_capacity_contract()
	_test_invalid_ledger()
	await _unmount()
	await _mount(true)
	if await _accept():
		await _target_loss_contract()
	await _unmount()
	await _mount(true)
	if await _accept():
		await _alternative_contract()
	await _unmount()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.SAVE_PATH))
	await _finish()

func _ransack_contract() -> void:
	var before := _wallet()
	_qm.camp_choose("ransack")
	_qm.claim(CAMP_ID)
	_check(not GameState.camp_quest.get("investigated", false) and not GameState.camp_quest.get("paid", false)
		and _wallet() == before, "未调查不得越级选择/领奖或凭空获得资源")
	await _visit()
	_qm.camp_choose("ransack")
	_hud._close_dialogue()
	var target: Dictionary = GameState.camp_quest["target"].duplicate(true)
	var nest: NestNode
	for body: Node in get_tree().get_nodes_in_group("nests"):
		if body is NestNode and body.nest_key == target["key"]: nest = body
	var survivors := _living_target_bodies()
	_check(nest != null and survivors.size() >= 3, "调查目标由真实活动巢体及原有族群组成")
	if nest == null: return
	var live_before := survivors.size()
	for _hit in NestNode.NEST_HP: nest.take_damage(1.0, _player.global_position)
	await _frames()
	_check(not WorldSim.sim.nests[target["key"]]["active"] and int(WorldSim.sim.nests[target["key"]]["rebuild"]) > 0,
		"真实巢体伤害触发暂时抑制与有界重建计时")
	var angry := 0
	for body: MonsterBase in survivors:
		if is_instance_valid(body) and body.inst.is_alive and body._enrage_timer > 0: angry += 1
	_check(_living_target_bodies().size() == live_before and angry == live_before, "捣巢不清怪，原有活体全部存活并实际激怒")
	_check(GameState.camp_quest.get("outcome", "") == "ransack" and not GameState.camp_quest.get("paid", false)
		and not GameState.camp_quest.get("ransacks", []).is_empty(), "记入实际捣巢历史但现场不提前发任务奖励")
	var history: Array = GameState.camp_quest.get("ransacks", []).duplicate()
	var kills: Array = GameState.camp_quest.get("kills", []).duplicate()
	# 捣巢之后继续杀活体不把历史分支倒改为另一种行动。
	await _kill_one()
	_check(GameState.camp_quest.get("outcome", "") == "ransack" and GameState.camp_quest.get("ransacks", []) == history,
		"当前种群后续变化不会覆盖真实捣巢历史")
	# 真实生态 tick 重建；测试锁定年龄避免把其他随机死亡混成巢重建断言。
	for inst: MonsterInstance in WorldSim.sim.instances.values():
		if inst.is_alive: inst.lifespan = maxi(inst.lifespan, inst.age + EcologySim.NEST_REBUILD_TICKS + 20)
	for _tick in EcologySim.NEST_REBUILD_TICKS + 1: WorldSim.sim.tick()
	_check(WorldSim.sim.nests[target["key"]]["active"] and GameState.camp_quest.get("ransacks", []) == history,
		"真实tick重建后保留当时捣巢记录，当前巢状态恢复活动")
	await _home()
	var offered: Dictionary = _qm.offer("camp_ecology", "camp_ecology", "营地巡守")
	_check(offered.get("kind", "") == "claim", "返回真实营地后才出现单独领奖确认")
	if not await _open_legacy_dialogue(): return
	await _tap(_hud._dialogue_yes)
	_check(GameState.camp_quest.get("paid", false) and GameState.camp_quest.get("stage", "") == "completed",
		"营地真实触屏确认恰好支付并完成首章")
	before = _wallet()
	_qm.claim(CAMP_ID)
	_check(_wallet() == before and not str(GameState.camp_quest.get("next_clue", "")).is_empty(), "已支付重复请求无收益，留下明确下一线索")
	_check(GameState.camp_quest.get("kills", []).size() >= kills.size(), "历史贡献数组不会因当前巢恢复而缩减")

func _alternative_contract() -> void:
	await _visit()
	_qm.camp_choose("hunt")
	_hud._close_dialogue()
	var first := await _kill_one()
	var previous: Dictionary = GameState.camp_quest["target"].duplicate(true)
	for inst: MonsterInstance in WorldSim.sim.instances.values():
		if inst.is_alive and inst.region_id == previous["region_id"] and inst.species.species_name == previous["species"]:
			inst.lifespan = inst.age + 1
	WorldSim.sim.tick()
	await _frames()
	_qm.camp_investigate()
	for _attempt in 240:
		if not _qm._camp._searching: break
		await _frames(2)
	var next: Dictionary = GameState.camp_quest["target"]
	_check(next["key"] != previous["key"] and GameState.camp_quest.get("stage", "") == "investigate"
		and not GameState.camp_quest.get("investigated", false), "实际首个族群消失后提供附近真实替代，仍须重新到场调查")
	_check(GameState.camp_quest.get("kills", []).has(first), "转向真实替代据点不丢失原实例击杀贡献")
	await _visit()
	_qm.camp_choose("hunt")
	_hud._close_dialogue()
	var second := await _kill_one()
	_check(GameState.camp_quest.get("kills", []).has(first) and GameState.camp_quest.get("kills", []).has(second)
		and GameState.camp_quest.get("stage", "") == "return" and GameState.camp_quest.get("outcome", "") == "hunt",
		"一只原目标加一只替代目标即累计完成，不把真实贡献重置成新两只")
	_check(WorldSim.sim.nests[next["key"]]["active"] and not _living_target_bodies().is_empty(),
		"替代有限猎杀完成时仍保留新巢和真实幸存个体")

func _target_loss_contract() -> void:
	var wallet := _wallet()
	_qm.camp_investigate()
	_check(not GameState.camp_quest.get("investigated", false) and _wallet() == wallet,
		"远离据点不能通过调查调用伪造访问记录")
	await _visit()
	_qm.camp_choose("hunt")
	_hud._close_dialogue()
	var id := await _kill_one()
	var progress: Array = GameState.camp_quest.get("kills", []).duplicate()
	_check(progress.has(id), "现场变化测试从真实首杀贡献开始")
	# 控制剩余寿命只为重现旧世界自然消失，真正死亡/巢状态仍由 tick 驱动。
	# 不创建、移动或提高任何活体密度，也不发玩家动作信号。
	WorldSim.sim.reintroduction_enabled = false
	for inst: MonsterInstance in WorldSim.sim.instances.values():
		if inst.is_alive and inst.spawn_pos.distance_to(WorldConfig.spawn_pos()) <= 12000.0:
			inst.lifespan = inst.age + 1
	WorldSim.sim.tick()
	await _frames()
	_check(GameState.camp_quest.get("kills", []) == progress and GameState.camp_quest.get("stage", "") == "act",
		"真实生态耗尽不冒充玩家猎杀、不吞已有贡献、不自动结算")
	await _home()
	wallet = _wallet()
	_qm.camp_investigate()
	_qm.claim(CAMP_ID)
	_check(_wallet() == wallet and not GameState.camp_quest.get("paid", false),
		"目标消失后在营地远程复核不能直接领取调查补偿")
	await _visit()
	for _attempt in 240:
		if not _qm._camp._searching: break
		await _frames(2)
	_check(GameState.camp_quest.get("stage", "") == "return" and GameState.camp_quest.get("outcome", "") == "survey"
		and GameState.camp_quest.get("kills", []) == progress, "实际重访耗尽据点且无替代时才形成保留首杀的真实调查结案")
	_check(int(GameState.camp_quest.get("gold", 0)) == 18 and str(GameState.camp_quest.get("bonus", "")) == "",
		"调查结案按真实调查加首杀贡献给奖，不冒领完整处理奖励")
	var count_before := WorldSim.sim.instances.size()
	var selector := CampQuestTargets.new()
	_world.add_child(selector)
	var unavailable: Dictionary = await selector.select_target()
	_check(unavailable.is_empty() and WorldSim.sim.instances.size() == count_before,
		"已耗尽旧世界没有合适目标时明确空结果，不补造生命或抬高密度")
	selector.queue_free()
	await _home()
	_qm.claim(CAMP_ID)
	_check(GameState.camp_quest.get("paid", false), "调查补偿仍须回营地明确交付")

func _legacy_capacity_contract() -> void:
	_hud._close_dialogue()
	var npc := World.LandmarkNPC.new()
	npc.landmark_id = "camp_contract_legacy"
	npc.kind = "古树"
	npc.giver = "容量检验员"
	npc.quest_kind = "collect"
	npc.interact_fn = _qm.offer
	npc.position = _player.position + Vector2(35, 0)
	_world.add_child(npc)
	await _frames()
	GameState.quests = {"active": [], "completed": {}, "receipts": {}}
	GameState.inventory = {"gold-key": 99, "fish": 3}
	var manual := {"id": "cap_manual", "landmark_id": npc.landmark_id, "giver": npc.giver,
		"kind": "collect", "title": "手动容量边界", "item": "fish", "need": 2,
		"progress": 0, "gold": 17, "xp": 3, "claim_at_npc": true}
	_qm.accept(manual)
	var before := _wallet()
	_qm.claim("cap_manual")
	_check(_wallet() == before and GameState.quests["active"].size() == 1,
		"旧手动收集奖励满99时保留材料/金币/经验/任务，无部分结算")
	GameState.remove_item("gold-key", 1)
	_check(GameState.quests["active"].size() == 1, "手动单腾位仍等待用户明确交付")
	_qm.claim("cap_manual")
	_check(GameState.quests["active"].is_empty() and GameState.count_item("gold-key") == 99
		and GameState.count_item("fish") == 1, "手动重试仅扣所需材料并补齐奖励到99")
	var legacy := manual.duplicate(true)
	legacy["id"] = "cap_legacy"
	legacy["progress"] = 0
	legacy.erase("claim_at_npc")
	GameState.add_item("fish", 1)
	before = _wallet()
	_qm.accept(legacy)
	_check(_wallet() == before and GameState.quests["active"].size() == 1,
		"旧自动单满奖品时不截断奖励，不吞材料和已达成进度")
	GameState.remove_item("gold-key", 1)
	_check(GameState.quests["active"].is_empty() and GameState.count_item("gold-key") == 99
		and GameState.count_item("fish") == 0, "旧自动单腾位后自动重试完成，无需改变旧领奖方式")
	var same := manual.duplicate(true)
	same["id"] = "cap_same_item"
	same["item"] = "gold-key"
	same["need"] = 1
	same["progress"] = 0
	_qm.accept(same)
	_qm.claim("cap_same_item")
	_check(GameState.quests["active"].is_empty() and GameState.count_item("gold-key") == 99,
		"容量预检先计本次消耗，同物品99减1加1仍可完整交付")
	var abandoned := manual.duplicate(true)
	abandoned["id"] = "cap_abandon"
	_qm.accept(abandoned)
	_qm.abandon("cap_abandon")
	_check(GameState.quests["active"].is_empty(), "旧委托明确放弃仍移除旧活动单")
	npc.queue_free()

func _test_invalid_ledger() -> void:
	var invalid := CampQuestData.sanitize({"id": CAMP_ID, "stage": "return", "active": true,
		"investigated": false, "outcome": "survey", "target": {"species": "地精矿工", "region_id": "p_0_0", "pos": [INF, 1]}})
	_check(invalid["stage"] == "investigate" and invalid["outcome"] == "" and invalid["target"].is_empty()
		and not invalid["paid"], "坏档未调查/无效坐标不能消毒成可领奖任务")
	invalid = CampQuestData.sanitize({"id": CAMP_ID, "stage": "return", "active": true,
		"investigated": true, "target": {"species": "地精矿工", "region_id": "p_0_0", "pos": [INF, 1]}})
	_check(invalid.get("stage", "") != "return" or not invalid.get("investigated", false),
		"坏档只有调查布尔值而无有效目标/现场证据，不能恢复默认满额奖励")

func _cold(phase: String) -> void:
	await _mount(phase == "--cold-write")
	match phase:
		"--cold-write":
			if not await _accept(): return
			await _visit()
			_qm.camp_choose("hunt")
			_hud._close_dialogue()
			var id := await _kill_one()
			_check(GameState.camp_quest.get("kills", []).has(id) and GameState.camp_quest.get("stage", "") == "act",
				"首杀来自真实实例，有限猎杀未做完前不越级")
			var ledger := GameState.camp_quest.duplicate(true)
			_player._hurt_iframes = 0.0
			_player.take_damage(1000000.0, Vector2.INF)
			_check(_player._is_dead and GameState.camp_quest == ledger, "真实死亡保存调查/分支/首杀历史不回退")
			_check(_save(), "带生态死亡快照和首杀账本真实写盘")
			_write_expected({"ledger": ledger, "first_id": id})
		"--cold-pending":
			var expected := _expected()
			_check(_same(GameState.camp_quest, expected["ledger"]), "独立冷进程保留调查/分支/首杀全账本")
			_check(not _player._is_dead and _player.global_position.distance_to(WorldConfig.spawn_pos()) < 1.0,
				"死亡窗口存档冷启动使用真实安全复活快照")
			var dead: MonsterInstance = WorldSim.sim.instances.get(int(expected["first_id"]))
			_check(dead == null or not dead.is_alive, "冷恢复不会把已计首杀的真实目标复活")
			var ledger := GameState.camp_quest.duplicate(true)
			_qm.abandon(CAMP_ID)
			_check(not GameState.camp_quest.get("active", true) and GameState.camp_quest.get("kills", []) == ledger["kills"],
				"新首章放弃只取消活动，保留真实贡献")
			if not await _accept(): return
			_check(GameState.camp_quest.get("kills", []) == ledger["kills"] and GameState.camp_quest.get("investigated", false),
				"重新接取恢复原调查与首杀，不重新计分")
			await _visit()
			GameState.add_item("onigiri", 99)
			var id := await _kill_one()
			var target: Dictionary = GameState.camp_quest["target"]
			_check(GameState.camp_quest.get("kills", []).has(id) and GameState.camp_quest.get("stage", "") == "return"
				and WorldSim.sim.nests[target["key"]]["active"], "有限猎杀真实完成，保留巢穴并等待回营地")
			_check(not GameState.camp_quest.get("paid", false) and GameState.count_item("onigiri") == 99,
				"奖品满99时完成状态不截断奖励或提前标支付")
			await _home()
			var wallet := _wallet()
			_qm.claim(CAMP_ID)
			_check(_wallet() == wallet and not GameState.camp_quest.get("paid", false), "营地满背包领取全事务保持原状")
			_check(_save(), "完整但容量待领状态真实写盘")
			_write_expected({"ledger": GameState.camp_quest.duplicate(true), "wallet": _wallet()})
		"--cold-claim":
			var expected := _expected()
			_check(_same(GameState.camp_quest, expected["ledger"]) and _same(_wallet(), expected["wallet"]),
				"独立冷进程完整恢复容量待领账本及金币/经验/库存")
			await _home()
			var wallet := _wallet()
			_qm.claim(CAMP_ID)
			_check(_wallet() == wallet and not GameState.camp_quest.get("paid", false), "冷加载后仍不能部分领奖")
			GameState.remove_item("onigiri", 1)
			_qm.claim(CAMP_ID)
			_check(GameState.camp_quest.get("paid", false) and GameState.count_item("onigiri") == 99,
				"空出一格后明确领取，一次支付全部奖励")
			_check(_save(), "已支付收据真实写盘")
			_write_expected({"ledger": GameState.camp_quest.duplicate(true), "wallet": _wallet()})
		"--cold-paid":
			var expected := _expected()
			_check(_same(GameState.camp_quest, expected["ledger"]) and _same(_wallet(), expected["wallet"]),
				"已支付收据独立冷进程完整恢复")
			await _home()
			var wallet := _wallet()
			_qm.claim(CAMP_ID)
			_qm.abandon(CAMP_ID)
			var offered: Dictionary = _qm.offer("camp_ecology", "camp_ecology", "营地巡守")
			_check(_wallet() == wallet and GameState.camp_quest.get("paid", false)
				and offered.get("kind", "") != "quest", "已付任务冷加载后重复领取/放弃/交谈不重复发奖")
		"--cold-old":
			var expected := _expected()
			_check(GameState.camp_quest.is_empty(), "无新账本的v10旧档不制造历史进度或免费完成")
			_check(_same(GameState.quests, expected["quests"]) and GameState.tracked_quest_id == expected["tracked_quest_id"],
				"旧档活动委托/进度/完成计数/交付方式及追踪保持原样")
			_check(GameState.gold == int(expected["gold"]) and _same(GameState.inventory, expected["inventory"])
				and GameState.world_seed == int(expected["world_seed"]), "旧档加入首章不重置种子或改写原金币库存")
		_:
			_check(false, "未知冷进程模式")
	await _unmount()

func _finish() -> void:
	print("=== CAMP PILOT CONTRACT %s (%d checks, %d failures) ===" % ["PASS" if _fails == 0 else "FAIL", _checks, _fails])
	get_tree().quit(0 if _fails == 0 else 1)
