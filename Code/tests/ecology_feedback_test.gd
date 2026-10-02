## 生态反馈真实接线回归：模拟 tick/report_killed → Watcher → EventBus；不以改文案替代行为测试。
extends Node

var _checks := 0
var _fails := 0
var _watcher: WorldEventWatcher
var _player: Node2D
var _tutorial: Tutorial
var _messages: Array[String] = []
var _extinct: Array[String] = []
var _recovered: Array[String] = []


func _ready() -> void:
	GameState.save_enabled = false
	WorldSim.set_process(false)
	EventBus.world_event.connect(func(text: String) -> void: _messages.append(text))
	EventBus.species_extinct.connect(func(species: String) -> void: _extinct.append(species))
	EventBus.species_recovered.connect(func(species: String) -> void: _recovered.append(species))
	_run.call_deferred()


func _run() -> void:
	_test_real_migration_and_locality()
	_test_real_birth_and_saturation()
	_test_permanent_and_recoverable_extinction()
	_test_split_and_first_tick_kill()
	_test_priority_budget_and_structural_events()
	_test_restore_and_local_tutorial()
	_test_observer_preserves_simulation()
	_reset()
	if _fails == 0:
		print("=== ECOLOGY FEEDBACK PASSED (%d checks) ===" % _checks)
	else:
		print("=== ECOLOGY FEEDBACK FAILED %d/%d ===" % [_fails, _checks])
	get_tree().quit(0 if _fails == 0 else 1)


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])


func _reset() -> void:
	for node: Node in [_watcher, _tutorial, _player]:
		if is_instance_valid(node):
			node.free()
	_watcher = null
	_tutorial = null
	_player = null
	WorldSim.stop()
	GameState.save_enabled = false
	GameState.reset_all()
	GameState.tutorial_flags = {"open1": true, "open2": true, "find_camp": true}
	_messages.clear()
	_extinct.clear()
	_recovered.clear()


func _region(id: String, center: Vector2, capacity := 30) -> SimRegion:
	var region := SimRegion.new()
	region.id = id
	region.display_name = "同名平原"
	region.terrain = "plains"
	region.center = center
	region.size = Vector2(8000, 8000)
	region.capacity = capacity
	return region


func _species(names: Array) -> Array[SpeciesData]:
	var result: Array[SpeciesData] = []
	for source: SpeciesData in SpeciesCatalog.build_all():
		if source.species_name not in names:
			continue
		var species: SpeciesData = source.duplicate(true)
		species.habitats = []
		species.prey = []
		species.breeding_rate = 0.0
		species.migrate_count = 0
		species.lifespan_min = 100000
		species.lifespan_max = 100000
		result.append(species)
	return result


func _world(names: Array, initial: Dictionary, local_capacity := 30) -> EcologySim:
	_reset()
	seed(20261002)
	var local := _region("local", Vector2(10000, 10000), local_capacity)
	var source := _region("source", Vector2(30000, 10000))
	var remote := _region("remote", Vector2(500000, 500000))
	var sim := EcologySim.new()
	sim.predation_enabled = false
	sim.reintroduction_enabled = false
	sim.setup([local, source, remote], _species(names), initial)
	WorldSim.start(sim)
	_player = Node2D.new()
	_player.position = local.center
	_player.add_to_group("player")
	add_child(_player)
	_watcher = WorldEventWatcher.new()
	add_child(_watcher)
	return sim


func _alive(sim: EcologySim, species: String) -> MonsterInstance:
	for inst: MonsterInstance in sim.instances.values():
		if inst.is_alive and inst.species.species_name == species:
			return inst
	return null


func _contains(fragment: String) -> bool:
	return _messages.any(func(text: String) -> bool: return text.contains(fragment))


func _test_real_migration_and_locality() -> void:
	var sim := _world(["火把哥布林", "山羊"],
		{"source": {"火把哥布林": 4}, "remote": {"山羊": 2}})
	var goblin := sim.find_species("火把哥布林")
	goblin.expansion_threshold = 3
	goblin.migrate_count = 2
	sim.get_region("source").neighbor_ids = ["local"]
	sim.tick()
	_check(sim.alive_count_in("local", goblin) == 2 and _contains("迁入2只火把哥布林"),
		"真实两只迁徙被播报，不依赖旧版 0→3 阈值")
	_check(not _contains("繁衍"), "迁入不伪报为出生")
	_messages.clear()
	goblin.expansion_threshold = 1
	goblin.migrate_count = 1
	_watcher._detector._cooldowns.clear()
	sim.tick()
	_check(sim.alive_count_in("local", goblin) == 3 and _contains("迁入1只火把哥布林"),
		"已有种群的一只真实迁入同样可见，不要求从零增长")
	_messages.clear()
	# 远方真实繁衍与饱和都不挤占本地新闻。
	var goat := sim.find_species("山羊")
	goat.breeding_rate = 1.0
	for inst: MonsterInstance in sim.instances.values():
		inst.age = inst.species.maturity_age
	sim.get_region("remote").capacity = 4
	sim.tick()
	_check(sim.alive_count_in("remote") == 4 and _messages.is_empty(), "远方真实出生和饱和保持安静")


func _test_real_birth_and_saturation() -> void:
	var sim := _world(["火把哥布林"], {"local": {"火把哥布林": 2}}, 4)
	_check(_messages.is_empty(), "挂载不把初始种群冒充新事件")
	var species := sim.find_species("火把哥布林")
	species.breeding_rate = 1.0
	for inst: MonsterInstance in sim.instances.values():
		inst.age = species.maturity_age
	sim.tick()
	_check(sim.alive_count_in("local") == 4 and _contains("繁衍出2只幼体"), "真实繁衍信号聚合出生数量")
	_check(_messages.size() == 2 and _messages[0].contains("繁衍") and _messages[1].contains("种群已满"),
		"出生原因优先，饱和只在本地转满时播报")
	_messages.clear()
	_watcher._detector._cooldowns.clear()
	sim.tick()
	_check(_messages.is_empty(), "即使30秒冷却已过，持续饱和也不重播")
	# 真实腾位后再繁衍回满，可再次形成饱和转变。
	species.breeding_rate = 0.0
	sim.report_killed(_alive(sim, species.species_name).id)
	sim.tick()
	_messages.clear()
	_watcher._detector._cooldowns.clear()
	species.breeding_rate = 1.0
	sim.tick()
	_check(_contains("种群已满"), "离开饱和后重新转满仍能播报")


func _test_permanent_and_recoverable_extinction() -> void:
	var sim := _world(["火把哥布林"], {"local": {"火把哥布林": 1}})
	sim.reintroduction_enabled = true
	sim.report_killed(_alive(sim, "火把哥布林").id)
	sim.tick()
	_check(sim.player_extinct.has("火把哥布林") and _contains("你的猎杀") and _contains("永久灭绝"),
		"首次 tick 前真实最后一杀明确永久后果")
	_check(_extinct == ["火把哥布林"] and not _contains("仍可能"), "永久灭绝结构化信号一次，文案不许暗示恢复")
	_check(WorldEventDetector.species_status_text("火把哥布林", 0, sim.player_extinct).contains("不会自然复苏"),
		"图鉴状态读取同一永久名单")
	sim = _world(["山羊"], {"local": {"山羊": 1}})
	sim.reintroduction_enabled = true
	var last := _alive(sim, "山羊")
	last.lifespan = last.age + 1
	# 无空位时重引入不能在同一 tick 掩盖自然归零；模拟仍保持启用恢复。
	for region: SimRegion in sim.regions.values():
		region.capacity = 0
	sim.tick()
	_check(not sim.player_extinct.has("山羊") and _contains("暂时消失") and _contains("仍可能"),
		"真实衰老归零与玩家永久灭绝明确区分")
	_check(_extinct == ["山羊"] and not _contains("永久"), "自然归零仍保留成就信号，不伪报不可逆")
	_messages.clear()
	sim.get_region("local").capacity = 30
	for tick in 200:
		if sim.alive_count_of_species("山羊") > 0:
			break
		sim.tick()
	_check(sim.alive_count_of_species("山羊") == 2 and _recovered == ["山羊"] and _contains("重返世界"),
		"真实自然重引入经 Watcher 接回复苏反馈")
	_check(not _contains("繁衍"), "成年重引入不伪报幼体出生")


func _test_split_and_first_tick_kill() -> void:
	var sim := _world(["赤炎小魔"], {"local": {"赤炎小魔": 1}})
	sim.report_killed(_alive(sim, "赤炎小魔").id)
	sim.tick()
	_check(sim.alive_count_of_species("赤炎小魔") == 2 and not sim.player_extinct.has("赤炎小魔"),
		"真实最后原生代被杀仍由权威模拟先生成分裂子代")
	_check(_extinct.is_empty() and not _contains("在本世界永久灭绝"), "死亡信号早于分裂，不提前误判灭绝")
	_check(_contains("猎杀触发分裂") and _contains("新增2只"), "玩家击杀到子代新增的因果得到真实播报")
	_check(_contains("全球仅剩2只"), "继续猎杀前能看到全球濒危风险")


func _test_priority_budget_and_structural_events() -> void:
	var sim := _world(["火把哥布林", "山羊", "山猪", "野鸭"],
		{"local": {"火把哥布林": 6}, "remote": {"山羊": 1, "山猪": 1, "野鸭": 1}})
	for name: String in ["山羊", "山猪", "野鸭"]:
		var inst := _alive(sim, name)
		inst.lifespan = inst.age + 1
	sim.report_killed(_alive(sim, "火把哥布林").id)
	sim.tick()
	_check(_messages.size() == WorldEventWatcher.MAX_ANNOUNCEMENTS_PER_TICK, "同 tick 远方灭绝潮有明确文本上限")
	_check(_messages[0].contains("全球仅剩5只火把哥布林") or _messages[0].contains("火把哥布林全球仅剩5只"),
		"本地玩家猎杀后果优先于远方自然新闻")
	_check(_extinct.size() == 3, "文本预算不吞掉任何结构化灭绝事件")


func _test_restore_and_local_tutorial() -> void:
	var sim := _world(["长矛哥布林"], {"source": {"长矛哥布林": 4}})
	var youngest := _alive(sim, "长矛哥布林")
	youngest.age = 0
	var saved := sim.to_dict()
	_watcher.free()
	_watcher = null
	WorldSim.stop()
	var restored := EcologySim.new()
	restored.predation_enabled = false
	restored.reintroduction_enabled = false
	restored.restore_from_dict(sim.regions.values(), sim.species_list, saved)
	WorldSim.start(restored)
	_watcher = WorldEventWatcher.new()
	add_child(_watcher)
	restored.tick()
	_check(_messages.is_empty(), "真实恢复重放只建立基线，不伪报出生或复苏")
	_tutorial = Tutorial.new()
	add_child(_tutorial)
	var species := restored.find_species("长矛哥布林")
	species.expansion_threshold = 3
	species.migrate_count = 2
	restored.get_region("source").neighbor_ids = ["remote"]
	restored.tick()
	_check(not GameState.tutorial_flags.has("migrate_长矛哥布林"), "远处真实迁徙不提前消耗首次亲历教学")
	# 第二轮迁徙到玩家本区，才算玩家的首次可感知事件。
	species.expansion_threshold = 1
	restored.get_region("source").neighbor_ids = ["local"]
	restored.tick()
	_check(GameState.tutorial_flags.has("migrate_长矛哥布林"), "真实本地迁徙仍能触发首次教学")
	_check(WorldEventDetector.species_status_text("巨魔王", 0, {}, true) == "等待重生", "Boss 不冒充自然或永久灭绝")


func _test_observer_preserves_simulation() -> void:
	var sim := _world(["火把哥布林"], {"source": {"火把哥布林": 6}})
	var species := sim.find_species("火把哥布林")
	species.breeding_rate = 0.5
	species.expansion_threshold = 4
	species.migrate_count = 2
	sim.get_region("source").neighbor_ids = ["local"]
	var control := EcologySim.new()
	control.predation_enabled = false
	control.reintroduction_enabled = false
	control.restore_from_dict(sim.regions.values(), sim.species_list, sim.to_dict())
	seed(80101)
	sim.tick()
	seed(80101)
	control.tick()
	_check(sim.to_dict() == control.to_dict(), "同种子同快照有无反馈观察者的生态结果完全一致")
