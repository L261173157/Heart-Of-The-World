## 有限卡片控制器短回归；真实注册场景/玩家/死亡/入包，不替代600秒战斗浸泡。
## 每例关闭场景自动处理，显式操作控制器；生态时钟单独走正式EcologySim.tick。
extends Node2D

const ARENA := preload("res://tests/pacing_arena_world.gd")
const WORLD := preload("res://scripts/main/game_world.gd")
const EXPECTED_ROSTER: Array[String] = [
	"火把哥布林", "火把哥布林", "火把哥布林",
	"地精矿工", "地精矿工", "地精矿工", "突袭蛇", "青甲龟", "山猪",
]
const DAMAGE := 1000000.0
const COOLDOWNS: Array[String] = ["_attack_cooldown", "_dash_cd", "_heavy_cd", "_bolt_cd", "_heal_cd", "_empower_cd"]

class Controller extends "res://tests/pacing_test.gd":
	var observed_checks: Array[Dictionary] = []
	# 只阻止自动600秒入口；被测选择器、卡片、死亡与资源方法原样继承。
	func _ready() -> void:
		pass
	func _process(_delta: float) -> void:
		pass
	func _check(ok: bool, label: String) -> void:
		observed_checks.append({"ok": ok, "label": label})
		if not ok: _fails += 1

var _checks := 0
var _fails := 0
var _controller: Controller
var _arena: Node2D
var _player: Player
var _sim: EcologySim
var _origin := Vector2.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.save_enabled = false
	GameState.SAVE_PATH = "user://pacing_controller_test.json"
	Engine.time_scale = 1.0
	_run.call_deferred()


func _run() -> void:
	await _fresh()
	_test_initial_resources()
	await _fresh()
	_test_card_boundaries()
	await _fresh()
	_test_finite_fixture()
	await _fresh()
	await _test_attack_attempts()
	await _fresh()
	_test_out_of_order_deaths()
	await _fresh()
	_test_scattered_deaths()
	await _fresh()
	_test_complete_cards()
	await _fresh()
	_test_incidental_rewards()
	await _fresh()
	_test_notifications_and_duplicates()
	await _fresh()
	_test_lost_actors()
	await _fresh()
	await _test_missing_body()
	await _fresh()
	await _test_transport()
	await _fresh()
	_test_reference_clock()
	await _fresh()
	_test_progress_guard()
	await _fresh()
	_test_free_roam()
	await _clear_fixture()
	print("=== PACING CONTROLLER %s (%d checks, %d failures) ===" % ["PASS" if _fails == 0 else "FAIL", _checks, _fails])
	get_tree().quit(0 if _fails == 0 else 1)


func _fresh() -> void:
	await _clear_fixture()
	WorldSim.stop()
	WorldSim.set_process(false)
	GameState.reset_all()
	GameState.save_enabled = false
	GameState.world_seed = BiomeMap.DEFAULT_SEED
	BiomeMap.configure(BiomeMap.DEFAULT_SEED)
	GameState.exploration = ExplorationFog.new(BiomeMap.DEFAULT_SEED)
	GameState.settings.screen_shake = false
	GameState.settings.damage_numbers = false
	_controller = Controller.new()
	_controller.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(_controller)
	_controller._prepare_starting_stats()
	_arena = ARENA.new()
	_arena.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(_arena)
	await _arena.wait_until_ready()
	_player = _arena.get_player()
	_sim = _arena._sim
	_origin = WorldConfig.spawn_pos()
	_controller._world = _arena
	_controller._player = _player
	_controller._robot_rng.seed = _controller.PACING_SEED
	_sim.instance_died.connect(_controller._on_sim_death)
	EventBus.monster_killed_by_player.connect(_controller._on_kill)
	EventBus.item_gained.connect(_controller._on_item_gained)


func _clear_fixture() -> void:
	get_tree().paused = false
	if is_instance_valid(_controller): _controller.queue_free()
	if is_instance_valid(_arena): _arena.queue_free()
	await get_tree().process_frame
	_controller = null
	_arena = null
	_player = null
	_sim = null
	WorldSim.stop()


func _release(time: float) -> void:
	_controller._game_time = time
	_controller._spawn_due_cards()


func _body(card: int, slot: int) -> MonsterBase:
	return _arena._nodes[int(_arena.card_ids[card][slot])] as MonsterBase


func _kill(body: MonsterBase) -> void:
	body.take_damage(DAMAGE, _player.global_position)
	_check(not body.inst.is_alive and body.state == MonsterBase.S_CORPSE,
		"注册场景真实伤害完成生态死亡：" + body.inst.species.species_name)
	# 正式等级奖励可能打开被动选择；短夹具同机器人选择首项，避免暂停污染后续例。
	if get_tree().paused:
		var hud := _arena.get_node("HUD")
		if hud.passive_layer.visible: hud._pick_passive(0)
		get_tree().paused = false


func _spawn_incidental(name: String, offset := Vector2(40, 0)) -> MonsterBase:
	var species := _sim.find_species(name)
	var inst := _sim.spawn_instance(species, ARENA.REGION_ID,
		species.maturity_age + CombatBandMath.REF_AGE_OFFSET, 0, 1.0, false, _origin + offset)
	var body := WORLD.MONSTER_SCENES[name].instantiate() as MonsterBase
	_arena.get_node("Monsters").add_child(body)
	body.setup(inst)
	body.global_position = _origin + offset
	_arena._nodes[inst.id] = body
	return body


func _test_initial_resources() -> void:
	_check(_controller.ENCOUNTER_ROSTER == EXPECTED_ROSTER and ARENA.ROSTER == EXPECTED_ROSTER
		and _controller.MIN_COMPLETE_ROSTERS == 3, "声明固定平原3:3:1:1:1九演员与三完整卡底线")
	_check(GameState.stats.strength == 12 and GameState.stats.agility == 6 and GameState.stats.intellect == 6,
		"正式初始化属性在创建真实Player前应用")
	_controller._capture_starting_resources()
	_check(_controller._fails == 0 and _controller._starting_hp_ratio == 1.0
		and _controller._starting_mp_ratio == 1.0, "真实Player按声明属性满血满蓝开始")
	_player.current_hp = 160.0
	_controller._capture_starting_resources()
	_check(_controller._fails == 1 and _controller._starting_hp_ratio < 0.70,
		"旧160HP/244上限起步被初始资源断言拒绝")
	_player.current_hp = _player.stats.max_hp()
	_player.current_mp = _player.stats.max_mp() - 1.0
	_controller._capture_starting_resources()
	_check(_controller._fails == 2, "少量初始缺蓝也不能冒充满资源起步")
	_check(_controller._hurt_events == 0 and _controller._min_hp_ratio == 1.0,
		"捕获错误初始资源不制造受击事件或战斗压力")


func _test_card_boundaries() -> void:
	_check(_controller.ENCOUNTER_CARDS == 10 and _controller.CARD_SECONDS == 60.0
		and _controller.GAME_SECONDS == 600.0, "固定十张60秒卡与完整600游戏秒")
	for sample: Array in [[0.0, 9], [59.999, 9], [60.0, 18], [119.999, 18],
			[120.0, 27], [539.999, 81], [540.0, 90], [599.999, 90], [600.0, 90], [660.0, 90]]:
		_controller._game_time = float(sample[0])
		_check(_controller._available_encounter_slots() == int(sample[1]),
			"%.3f秒固定释放%d槽" % [sample[0], sample[1]])
	_release(600.0)
	_check(_controller._cards_started == 0 and _sim.instances.is_empty(), "600秒终点不补发遗漏卡片")
	for sample: Array in [[0.0, 1], [59.999, 1], [60.0, 2], [119.999, 2], [120.0, 3], [540.0, 10], [599.999, 10]]:
		_release(float(sample[0]))
		_check(_controller._cards_started == int(sample[1]) and _sim.instances.size() == int(sample[1]) * 9,
			"%.3f秒实际生成且仅生成%d张卡" % [sample[0], sample[1]])
	_check(_controller._roster_kills == 0 and _controller._reward_ids.is_empty() and _controller._kills == 0
		and _controller._completed_rosters() == 0 and GameState.inventory.is_empty(),
		"发出十卡90个活演员本身不能记任何击杀、完成卡或材料")


func _test_finite_fixture() -> void:
	_check(not _arena.spawn_card(-1) and not _arena.spawn_card(10), "竞技场拒绝负卡号与第十一张卡")
	_release(0.0)
	_check(not _arena.spawn_card(0) and _sim.instances.size() == 9, "同一卡号重复发卡不能增加演员")
	var ids: Array = _arena.card_ids[0].slice(0, 9)
	var snapshots := {}
	var hp := _player.current_hp
	var mp := _player.current_mp
	for i in COOLDOWNS.size(): _player.set(COOLDOWNS[i], 1.5 + i)
	for slot in 9:
		var body := _body(0, slot)
		var inst := body.inst
		_check(inst.species.species_name == EXPECTED_ROSTER[slot] and not inst.is_elite and not inst.species.is_boss
			and inst.age == inst.species.maturity_age + 90 and inst.generation == 0 and inst.size_scale == 1.0,
			"第%d槽保持正式普通物种、成熟+90参考年龄与一倍体型" % slot)
		_check(body.get_scene_file_path() == WORLD.MONSTER_SCENES[EXPECTED_ROSTER[slot]].resource_path
			and body.current_hp == inst.max_hp(), "第%d槽使用正式注册场景与未削弱满生命" % slot)
		snapshots[inst.id] = [body, body.current_hp, body.global_position, inst.age]
	_release(540.0)
	_check(_sim.instances.size() == 90 and _arena._nodes.size() == 90 and _controller._fixture_card_by_id.size() == 90
		and _controller._encounter_admissions == 90, "十张卡恰好90个唯一真实演员，无额外供给")
	for card in 10:
		var card_ids: Array = _arena.card_ids[card]
		var valid := card_ids.size() == 9
		for slot in card_ids.size():
			if slot >= 9:
				valid = false
				continue
			var body := _arena._nodes.get(int(card_ids[slot])) as MonsterBase
			if not is_instance_valid(body):
				valid = false
				continue
			var inst := body.inst
			valid = valid and inst.is_alive and not inst.is_elite and not inst.species.is_boss \
				and inst.species.species_name == EXPECTED_ROSTER[slot] \
				and inst.age == inst.species.maturity_age + 90 and inst.size_scale == 1.0 \
				and inst.generation == 0 and inst.threat_scale == 1.0 \
				and body.current_hp == inst.max_hp() \
				and body.get_scene_file_path() == WORLD.MONSTER_SCENES[EXPECTED_ROSTER[slot]].resource_path
		_check(valid, "第%d张完整卡全部保持正式场景、普通参考属性与未削弱满血" % (card + 1))
	for id in ids:
		var snap: Array = snapshots[id]
		var body := _arena._nodes[id] as MonsterBase
		_check(body == snap[0] and body.inst.is_alive and body.current_hp == snap[1]
			and body.global_position == snap[2] and body.inst.age == snap[3], "后续发卡不清理、移位、治疗或老化既有演员ID%d" % id)
	var retained := _player.current_hp == hp and _player.current_mp == mp
	for i in COOLDOWNS.size(): retained = retained and float(_player.get(COOLDOWNS[i])) == 1.5 + i
	_check(retained, "后续发卡不恢复玩家HP/MP或六项冷却")
	_check(_sim.tick_count == 0 and not WorldSim.is_processing(), "有限战斗夹具不推进自然老化、出生或捕食")
	var empty := true
	for inst: MonsterInstance in _sim.instances.values(): empty = empty and inst.is_alive
	_check(empty and GameState.inventory.is_empty(), "发卡后90个演员仍活着，未以表格伪造奖励")


func _test_attack_attempts() -> void:
	_release(0.0)
	var target := _body(0, 0)
	# 只隔离出刀入口：防止法弹/重击立即伤害其它卡片演员。
	_player._heavy_cd = 100.0
	_player._bolt_cd = 100.0
	var hp := target.current_hp
	for i in 32: _controller._robot_step()
	_check(_controller._transports == 1 and _player._attack_timer == 0.0,
		"正式机器人先安全接近，未经过两个物理帧不得出刀")
	await get_tree().physics_frame
	for i in 32: _controller._robot_step()
	_check(_player._attack_timer == 0.0, "仅一个真实物理帧仍不得提前出刀")
	for i in 2: await get_tree().physics_frame
	for i in 32: _controller._robot_step()
	_check(_player._attack_timer > 0.0 and _player.activity_serial > 0, "真实机器人启动正式玩家挥刀")
	_check(target.inst.is_alive and target.current_hp == hp and _controller._roster_kills == 0
		and _controller._reward_ids.is_empty() and _controller._completed_rosters() == 0,
		"96次机器人操作和攻击尝试不能伪造真实死亡或完整卡")


func _test_out_of_order_deaths() -> void:
	_release(0.0)
	var first := _body(0, 0)
	_check(_controller._nearest_monster() == first, "选取声明顺序中首个未完成演员")
	_kill(_body(0, 8))
	_kill(_body(0, 4))
	_check(_controller._roster_kills == 2 and _controller._incidental_kills == 0
		and _controller._encounter_target_id == first.inst.id, "未被选中的同卡不同物种真实死亡同样计入该卡")
	_check(_controller._completed_rosters() == 0 and _controller._choose_encounter_instance() == first.inst,
		"乱序死亡不跳过仍活着的首槽，也不提前完成整卡")
	for slot in [7, 6, 5, 3, 2, 1, 0]: _kill(_body(0, slot))
	_check(_controller._completed_rosters() == 1 and _controller._roster_kills == 9
		and _controller._choose_encounter_instance() == null, "任意死亡顺序只在同一卡九个声明ID全部死亡后完成")
	_check(_controller._expected_materials == {"tea-leaf": 3, "beaf": 2, "fish": 1}
		and GameState.inventory == _controller._expected_materials, "乱序整卡实际六材料全部入包")


func _test_scattered_deaths() -> void:
	_release(180.0)
	for card in 3:
		for slot in 8: _kill(_body(card, slot))
	for slot in 3: _kill(_body(3, slot))
	_check(_controller._roster_kills == 27 and _controller._reward_ids.size() == 27
		and _controller._completed_rosters() == 0, "跨四张卡零散27次真实死亡不能冒充三张完整卡")
	for card in 3: _kill(_body(card, 8))
	_check(_controller._completed_rosters() == 3 and _controller._roster_kills == 30,
		"补齐前三卡各自缺少的ID后才达到三张完整卡")


func _test_complete_cards() -> void:
	_release(120.0)
	for card in 3:
		for slot in 9: _kill(_body(card, slot))
	_check(_controller._completed_rosters() == 3 and _controller._roster_kills == 27
		and _controller._incidental_kills == 0 and _controller._reward_ids.size() == 27 and _controller._kills == 27,
		"三张完整卡恰好27次唯一玩家死亡")
	var expected := {"tea-leaf": 9, "beaf": 6, "fish": 3}
	_check(_controller._expected_materials == expected and _controller._gained_items == expected
		and GameState.inventory == expected, "三张普通卡独立预期18材料，与真实发放及库存一致")
	_controller._check_material_conservation()
	_check(_controller._fails == 0, "三张真实完整卡通过原材料守恒闸")


func _test_incidental_rewards() -> void:
	_release(0.0)
	for i in 27: _kill(_spawn_incidental("山猪"))
	_check(_controller._roster_kills == 0 and _controller._incidental_kills == 27
		and _controller._completed_rosters() == 0, "27只非声明ID真实死亡只能记顺带，不能冒充卡片")
	_check(_controller._reward_ids.size() == 27 and _controller._kills == 27
		and _controller._expected_materials == {"beaf": 27} and _controller._gained_items == {"beaf": 27}
		and GameState.count_item("beaf") == 27, "非夹具的27件实际材料仍全部纳入预算和守恒")
	_controller._check_material_conservation()
	_check(_controller._fails == 0, "顺带玩家击杀完整通过材料守恒检查")


func _test_notifications_and_duplicates() -> void:
	_release(0.0)
	for i in 27: EventBus.monster_killed_by_player.emit(0, 0, "无真实生态死亡", "火把哥布林")
	_check(_controller._kills == 27 and _controller._roster_kills == 0 and _controller._reward_ids.is_empty()
		and _controller._completed_rosters() == 0, "27次奖励通知不能冒充任何声明ID死亡")
	_controller._kills = 0 # 隔离下一项重复死亡输入，不修复被测生产路径。
	var body := _body(0, 0)
	_kill(body)
	_sim.report_killed(body.inst.id, body.global_position)
	_check(_controller._roster_kills == 1 and _controller._duplicate_rewards == 0, "生态重复报告本身幂等")
	for i in 27: _sim.instance_died.emit(body.inst, EcologySim.DEATH_KILLED)
	_check(_controller._roster_kills == 1 and _controller._reward_ids.size() == 1
		and _controller._duplicate_rewards == 27 and _controller._completed_rosters() == 0,
		"27次已死ID信号重放无法伪造完整卡，并被计为异常")


func _test_lost_actors() -> void:
	_release(0.0)
	var body := _body(0, 0)
	_sim._die(body.inst, EcologySim.DEATH_PREDATED)
	_check(not body.inst.is_alive and _controller._encounter_unavailable
		and _controller._roster_kills == 0 and _controller._reward_ids.is_empty(),
		"声明演员非玩家死亡立即失败，不发奖或记卡")
	var before := _sim.instances.size()
	_release(60.0)
	_check(_sim.instances.size() == before and _controller._cards_started == 1
		and _controller._choose_encounter_instance() == null, "丢失失败后不生成替代演员或继续补卡")


func _test_missing_body() -> void:
	_release(0.0)
	var body := _body(0, 0)
	var id := body.inst.id
	body.queue_free()
	await get_tree().process_frame
	_check(_controller._nearest_monster() == null and _controller._encounter_unavailable
		and _sim.instances[id].is_alive, "声明ID仍活着但注册场景丢失时明确失败")
	_release(60.0)
	_check(_sim.instances.size() == 9 and _controller._encounter_admissions == 9
		and _controller._roster_kills == 0 and GameState.inventory.is_empty(),
		"真实身体缺失不会生成替身、虚构死亡或奖励")


func _test_transport() -> void:
	_release(0.0)
	var destination := _origin + Vector2(200, 0)
	_player.current_hp = _player.stats.max_hp() * 0.45
	_player.current_mp = _player.stats.max_mp() * 0.4
	for i in COOLDOWNS.size(): _player.set(COOLDOWNS[i], 1.25 + float(i))
	var hp := _player.current_hp
	var mp := _player.current_mp
	_check(_controller._transport_for_encounter(destination), "空闲玩家携带非零冷却可正式安全接近")
	_check(_player.global_position == destination and _player.current_hp == hp and _player.current_mp == mp,
		"安全接近保持低HP/MP，不治疗回蓝")
	var retained := true
	for i in COOLDOWNS.size(): retained = retained and is_equal_approx(float(_player.get(COOLDOWNS[i])), 1.25 + float(i))
	_check(retained and _controller._transport_integrity, "安全接近保留普攻及五技能六项冷却")
	for state: Array in [["_attack_timer", 0.2], ["_attack_anim_linger", 0.2], ["_dash_timer", 0.2],
			["_hurt_iframes", 0.2], ["_knockback", Vector2(5, 0)], ["_move_vel", Vector2(5, 0)], ["guard_state", "raising"]]:
		var old: Variant = _player.get(state[0])
		_player.set(state[0], state[1])
		var transports := _controller._transports
		_check(not _controller._transport_for_encounter(_origin) and _controller._transports == transports
			and _player.global_position == destination and _player.get(state[0]) == state[1],
			"动作/受击不可被安全接近取消：" + str(state[0]))
		_player.set(state[0], old)
	var victim := _body(0, 0)
	var victim_hp := victim.current_hp
	for i in 3: await get_tree().physics_frame
	_check(_player._attack_timer == 0.0 and _player._attack_anim_linger == 0.0
		and _player.attack_shape.disabled and victim.current_hp == victim_hp,
		"真实物理帧后没有残留挥刀判定或顺带伤害")


func _test_reference_clock() -> void:
	_release(0.0)
	var region := SimRegion.new()
	region.id = "clock_reference"
	region.terrain = "plains"
	region.center = _origin
	region.size = Vector2(10000, 10000)
	region.capacity = 100
	_controller._reference_sim = EcologySim.new()
	_controller._reference_sim.setup([region], SpeciesCatalog.build_all(), {region.id: WorldConfig.TERRAIN_POPULATION["plains"]})
	_controller._reference_sim.tick_completed.connect(_controller._on_summary)
	var ages := {}
	for inst: MonsterInstance in _sim.instances.values(): ages[inst.id] = inst.age
	_check(_controller._reference_sim != _sim and _controller._reference_sim.predation_enabled
		and _controller._reference_sim.reintroduction_enabled, "参考生态独立且保留正常捕食/重引入规则")
	var previous := 0.0
	for sample: Array in [[0.5, 0], [0.999, 0], [1.0, 1], [1.999, 1], [2.0, 2], [60.0, 60], [600.0, 600]]:
		_controller._game_time = float(sample[0])
		_controller._advance_reference(float(sample[0]) - previous)
		previous = float(sample[0])
		_check(_controller._reference_sim.tick_count == int(sample[1]), "%.3f游戏秒只推进%d真实参考tick" % [sample[0], sample[1]])
	_controller._advance_reference(0.0)
	_check(_controller._reference_sim.tick_count == 600 and _controller._alive_window.size() == 60,
		"600秒恰好600次真实tick且零delta不重复，保留末60tick样本")
	var unchanged := _sim.tick_count == 0 and _sim.instances.size() == 9
	for inst: MonsterInstance in _sim.instances.values(): unchanged = unchanged and inst.age == ages[inst.id] and inst.is_alive
	_check(unchanged and _controller._roster_kills == 0 and _controller._kills == 0,
		"参考生态600tick不老化/繁殖/杀死战斗演员，不制造卡片进度")
	_check(WorldSim.game_day == 2 and is_equal_approx(WorldSim.day_time, 0.65),
		"正式昼夜时钟按同一600游戏秒推进")


func _test_progress_guard() -> void:
	_controller._roster_kills = 27
	_controller._check_material_conservation()
	var rejected := false
	for result: Dictionary in _controller.observed_checks:
		if "阵容进度" in str(result["label"]) and not bool(result["ok"]): rejected = true
	_check(rejected and _controller._completed_rosters() == 0, "篡改27杀计数被唯一死亡守恒拒绝，不能产生完整卡")


func _test_free_roam() -> void:
	_controller._free_roam = true
	var boar := _spawn_incidental("山猪", Vector2(40, 0))
	_spawn_incidental("火把哥布林", Vector2(200, 0))
	_check(_controller._nearest_monster() == boar and _controller._nearest_populated_center() == boar.inst.spawn_pos,
		"自由游猎诊断保留最近任意物种行为")
	_kill(boar)
	_check(_controller._roster_kills == 0 and _controller._incidental_kills == 1
		and _controller._completed_rosters() == 0 and _controller._expected_materials == {"beaf": 1},
		"自由游猎不冒充固定卡片，但仍记全部真实材料")


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok: _fails += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
