## 生态模拟无头测试（纯逻辑，不依赖 autoload / 场景树 / 表现层）。
## 运行："$GODOT" --headless --path Code -s tests/sim_test.gd
## 输出逐项 PASS/FAIL，全部通过退出码 0。
extends SceneTree

const WORLD_W := 3300.0
const WORLD_H := 1400.0
const CELL_W := 1100.0
const CELL_H := 700.0

var _failures := 0
var _current := ""


func _init() -> void:
	randomize()
	_test_initial_setup()
	_test_split_mechanics()
	_test_elite_mechanics()
	_test_world_events()
	_test_reintroduction()
	_test_predation_and_boss()
	_test_nests()
	_test_capacity_breeding()
	_test_aging_and_corpses()
	_test_long_run_invariants()
	if _failures == 0:
		print("\n=== 全部测试通过 ===")
		quit(0)
	else:
		print("\n=== %d 项失败 ===" % _failures)
		quit(1)


# --- 测试用世界构造（与 main.tscn 六区域布局一致） ---

func _build_regions() -> Array:
	var configs := [
		["snow", "雪原", "snow", 1.7, 10, ["west", "center", "swamp"]],
		["swamp", "沼泽", "swamp", 1.7, 10, ["snow", "center", "lava"]],
		["lava", "熔岩洞窟", "lava", 3.0, 8, ["swamp", "east"]],
		["west", "西部荒野", "plains", 1.0, 10, ["snow", "center"]],
		["center", "中央林地", "forest", 1.3, 12, ["west", "snow", "swamp", "east"]],
		["east", "东部丘陵", "hill", 2.2, 12, ["center", "lava"]],
	]
	var regions: Array = []
	for i in configs.size():
		var c = configs[i]
		var region := SimRegion.new()
		region.id = c[0]
		region.display_name = c[1]
		region.terrain = c[2]
		region.threat = c[3]
		region.capacity = c[4]
		for n in c[5]:
			region.neighbor_ids.append(n)
		var col: float = i % 3
		var row: float = i / 3
		region.center = Vector2((col + 0.5) * CELL_W, (row + 0.5) * CELL_H)
		region.size = Vector2(CELL_W, CELL_H)
		regions.append(region)
	return regions


func _initial_population() -> Dictionary:
	return {
		"west": {"哥布林": 6},
		"center": {"哥布林": 3, "史莱姆": 4},
		"snow": {"野猪": 3, "雪蝎": 3},
		"swamp": {"史莱姆": 4, "雪蝎": 2},
		"east": {"兵蚁": 5, "野猪": 2},
		"lava": {"兵蚁": 3, "岩甲龟": 2},
	}


func _new_sim() -> EcologySim:
	var sim := EcologySim.new()
	sim.setup(_build_regions(), SpeciesCatalog.build_all(), _initial_population())
	return sim


# --- 断言工具 ---

func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  PASS  %s" % msg)
	else:
		_failures += 1
		print("  FAIL  %s" % msg)


# --- 用例 ---

## 精英个体：变异标记、体型/生命/经验放大、名称前缀（繁衍变异概率走随机路径，单测直接构造）
func _test_elite_mechanics() -> void:
	_current = "精英机制"
	print("[%s]" % _current)
	var sim := _new_sim()
	var species := sim.find_species("哥布林")
	var normal: MonsterInstance = sim.spawn_instance(species, "west")
	var elite: MonsterInstance = sim.spawn_instance(species, "west", 0, 0, 1.0, true)
	_check(elite.is_elite and not normal.is_elite, "精英标记写入（普通个体不受影响）")
	_check(absf(elite.size_scale - 1.45) < 0.001,
		"精英体型放大 1.45（实际 %.2f）" % elite.size_scale)
	_check(elite.max_hp() > normal.max_hp() * 1.4, "精英生命显著更高")
	# xp_reward 是 int 截断，低 xp_base 物种的比率会被抹平（如 5→7 = 1.4），阈值取 1.35
	var xp_ratio := float(elite.xp_reward()) / maxf(1.0, float(normal.xp_reward()))
	_check(xp_ratio >= 1.35, "精英经验显著更高（比率 %.2f）" % xp_ratio)
	_check(elite.display_name().begins_with("精英·"), "精英名称带前缀（%s）" % elite.display_name())


## 世界事件检测：构造假快照喂 WorldEventWatcher.detect_events（纯函数，无需场景树）。
## 快照只带 regions（检测器从 regions 重算全球总数），helper: {区域id: {物种: 数}}
func _test_world_events() -> void:
	_current = "世界事件"
	print("[%s]" % _current)
	# 检测器是纯 RefCounted（无 autoload 依赖），-s 模式下显式 load 实例化
	var detector_script: GDScript = load("res://scripts/main/world_event_detector.gd")
	var detector: RefCounted = detector_script.new()

	# 首帧只记录不播报
	var first: Array[String] = detector.detect_events(_fake_summary({"west": {"史莱姆": 6}}))
	_check(first.is_empty(), "首帧快照不触发事件")

	# 入侵潮：east 从无兵蚁 → 4 只
	var invaded: Array[String] = detector.detect_events(
		_fake_summary({"west": {"史莱姆": 6}, "east": {"兵蚁": 4}}))
	_check(invaded.any(func(t: String) -> bool: return "兵蚁 大举迁入" in t),
		"区域入侵潮被播报（%s）" % str(invaded))

	# 同类入侵 30s 内节流：再来一次同样事件不重复
	var again: Array[String] = detector.detect_events(
		_fake_summary({"west": {"史莱姆": 5}, "east": {"兵蚁": 4}}))
	_check(not again.any(func(t: String) -> bool: return "大举迁入" in t),
		"同类事件冷却期内不刷屏")

	# 全球灭绝：史莱姆从世界上消失
	detector = detector_script.new()
	detector.detect_events(_fake_summary({"west": {"史莱姆": 6}}))
	var extinct: Array[String] = detector.detect_events(_fake_summary({"east": {"兵蚁": 4}}))
	_check(extinct.any(func(t: String) -> bool: return "史莱姆" in t and "消失" in t),
		"全球灭绝被播报（%s）" % str(extinct))


## 构造 sim_tick_completed 同构的假快照
func _fake_summary(regions_species: Dictionary) -> Dictionary:
	var regions: Array[Dictionary] = []
	var total := 0
	for rid in regions_species:
		var alive: int = 0
		for sp in regions_species[rid]:
			alive += regions_species[rid][sp]
		regions.append({
			"id": rid, "name": rid, "terrain": "plains", "threat": 1.0,
			"alive": alive, "capacity": 10, "species": regions_species[rid].duplicate(),
		})
		total += alive
	return {"tick": 1, "regions": regions, "total_alive": total}


func _test_initial_setup() -> void:
	_current = "初始种群"
	print("[%s]" % _current)
	var sim := _new_sim()
	var expected := {"west": 6, "center": 7, "snow": 6, "swamp": 6, "east": 7, "lava": 5}
	for region_id in expected:
		_check(sim.alive_count_in(region_id) == expected[region_id],
			"%s 初始存活 %d（期望 %d）" % [region_id, sim.alive_count_in(region_id), expected[region_id]])
	var lava: SimRegion = sim.get_region("lava")
	var inst: MonsterInstance = sim.instances.values()[0]
	_check(is_equal_approx(inst.threat_scale, sim.get_region(inst.region_id).threat),
		"个体威胁系数取自所在区域")
	_check(lava.contains_point(Vector2(2750, 350)) and not lava.contains_point(Vector2(550, 350)),
		"区域矩形包含判定正确")


func _test_split_mechanics() -> void:
	_current = "史莱姆分裂"
	print("[%s]" % _current)
	var sim := _new_sim()
	# 本用例验证"只有击杀才分裂"的精确数量，关闭捕食（雪蝎/野猪吃史莱姆会引入噪音）
	sim.predation_enabled = false
	var victim: MonsterInstance = null
	for inst: MonsterInstance in sim.instances.values():
		if inst.is_alive and inst.species.species_name == "史莱姆" and inst.region_id == "center":
			victim = inst
			break
	_check(victim != null, "找到林地史莱姆")
	var before: int = sim.alive_count_in("center", victim.species)
	var spawned: Array[MonsterInstance] = []
	sim.instance_spawned.connect(func(i): if i.generation > 0: spawned.append(i))
	sim.report_killed(victim.id)
	_check(spawned.size() == 2, "击杀原生代裂出 2 个子代（实际 %d）" % spawned.size())
	if spawned.size() > 0:
		var child := spawned[0]
		_check(child.generation == 1, "子代为第 1 代")
		_check(is_equal_approx(child.size_scale, 0.6), "子代体型 0.6（实际 %.2f）" % child.size_scale)
		_check(child.region_id == "center", "子代留在母代区域")
		# 子代不再分裂
		var children_before: int = spawned.size()
		sim.report_killed(child.id)
		_check(sim.alive_count_in("center", victim.species) == before - 1 + children_before - 1,
			"击杀子代不再分裂，数量守恒")
	# 自然老死不分裂：把一只史莱姆寿命改到立即老死
	var elder: MonsterInstance = null
	for inst: MonsterInstance in sim.instances.values():
		if inst.is_alive and inst.species.species_name == "史莱姆":
			elder = inst
			break
	elder.age = 0
	elder.lifespan = 1
	var gen0_count := 0
	for inst: MonsterInstance in sim.instances.values():
		if inst.is_alive and inst.species.species_name == "史莱姆" and inst.generation == 0:
			gen0_count += 1
	sim.tick()
	var gen0_after := 0
	for inst: MonsterInstance in sim.instances.values():
		if inst.is_alive and inst.species.species_name == "史莱姆" and inst.generation == 0:
			gen0_after += 1
	_check(gen0_after == gen0_count - 1, "自然老死的史莱姆不产生分裂（%d → %d）" % [gen0_count, gen0_after])


## 生态韧性：灭绝物种按概率重引入（成年对，栖息地匹配）
func _test_reintroduction() -> void:
	_current = "灭绝重引入"
	print("[%s]" % _current)
	var region := SimRegion.new()
	region.id = "isle"
	region.display_name = "孤岛"
	region.terrain = "forest"
	region.threat = 1.0
	region.capacity = 8
	var species := SpeciesData.new()
	species.species_name = "候鸟"
	species.habitats = ["forest"]
	species.lifespan_min = 200
	species.lifespan_max = 200
	species.maturity_age = 5
	species.breeding_rate = 0.0
	species.migrate_count = 0
	var sim := EcologySim.new()
	sim.setup([region], [species], {})
	# 世界里本就没有该物种（等效灭绝），tick 到重引入触发（5%/tick，200 tick 内置信度 >99.99%）
	var ticks := 0
	while sim.alive_count_in("isle") == 0 and ticks < 200:
		sim.tick()
		ticks += 1
	_check(sim.alive_count_in("isle") >= 1,
		"灭绝物种被重引入（%d tick 后存活 %d）" % [ticks, sim.alive_count_in("isle")])
	var reintroduced: Array[MonsterInstance] = []
	for inst: MonsterInstance in sim.instances.values():
		if inst.is_alive:
			reintroduced.append(inst)
	if not reintroduced.is_empty():
		_check(reintroduced.size() == EcologySim.REINTRODUCE_COUNT,
			"重引入为成年对（%d 只）" % reintroduced.size())
		_check(reintroduced[0].age >= species.maturity_age, "重引入个体已成年（age=%d）" % reintroduced[0].age)
	# 开关关闭时不重引入
	var sim2 := EcologySim.new()
	sim2.reintroduction_enabled = false
	sim2.setup([region], [species], {})
	for i in 50:
		sim2.tick()
	_check(sim2.alive_count_in("isle") == 0, "关闭开关后不重引入（50 tick 存活 %d）" % sim2.alive_count_in("isle"))


## 捕食关系 + Boss 重生（生态链核心机制）
func _test_predation_and_boss() -> void:
	_current = "捕食与Boss"
	print("[%s]" % _current)
	var by_name := {}
	for s: SpeciesData in SpeciesCatalog.build_all():
		by_name[s.species_name] = s

	# 捕食：兵蚁压制同区哥布林（关繁衍排除噪音）
	var region := SimRegion.new()
	region.id = "pen"
	region.display_name = "围栏"
	region.terrain = "hill"
	region.threat = 1.0
	region.capacity = 20
	var goblin: SpeciesData = by_name["哥布林"]
	var ant: SpeciesData = by_name["兵蚁"]
	goblin.breeding_rate = 0.0
	ant.breeding_rate = 0.0
	var sim := EcologySim.new()
	# GDScript lambda 对局部变量是值捕获，计数必须走引用类型（Dictionary）
	var counters := {"predated": 0}
	sim.instance_died.connect(func(_i, cause: String) -> void:
		if cause == "predated":
			counters["predated"] += 1)
	sim.setup([region], [goblin, ant], {"pen": {"哥布林": 10, "兵蚁": 2}})
	for i in 60:
		sim.tick()
	_check(counters["predated"] > 0, "捕食死亡发生（60 tick 共 %d 次）" % counters["predated"])
	_check(sim.alive_count_in("pen", goblin) < 10,
		"哥布林被压制（剩 %d < 10）" % sim.alive_count_in("pen", goblin))

	# Boss 重生：龟王被讨伐后按倒计时归来
	var lava := SimRegion.new()
	lava.id = "den"
	lava.display_name = "巢穴"
	lava.terrain = "lava"
	lava.threat = 1.0
	lava.capacity = 10
	var king: SpeciesData = by_name["龟王"]
	king.boss_respawn_ticks = 5
	var sim2 := EcologySim.new()
	sim2.setup([lava], [king], {"den": {"龟王": 1}})
	var boss_inst: MonsterInstance = null
	for inst: MonsterInstance in sim2.instances.values():
		if inst.species == king:
			boss_inst = inst
	_check(boss_inst != null and boss_inst.is_alive, "龟王以 Boss 姿态入场")
	_check(absf(boss_inst.size_scale - 2.2) < 0.001, "Boss 体型 2.2（实际 %.2f）" % boss_inst.size_scale)
	sim2.report_killed(boss_inst.id)
	_check(sim2.alive_count_in("den", king) == 0, "Boss 被讨伐")
	for i in 8:
		sim2.tick()
	_check(sim2.alive_count_in("den", king) == 1, "Boss 按倒计时重生（8 tick）")


## 巢穴机制：捣毁 → 区域繁衍停止；rebuild 归零 → 巢穴重建恢复繁衍。
## 附：元素克制乘子（CombatMath 纯函数）
func _test_nests() -> void:
	_current = "巢穴与元素"
	print("[%s]" % _current)
	var region := SimRegion.new()
	region.id = "pen"
	region.display_name = "围栏"
	region.terrain = "plains"
	region.threat = 1.0
	region.capacity = 20
	var species := SpeciesData.new()
	species.species_name = "爆育蚁"
	species.habitats = ["plains"]
	species.breeding_rate = 1.0
	species.maturity_age = 1
	species.migrate_count = 0
	species.prey = []
	var sim := EcologySim.new()
	sim.predation_enabled = false
	sim.reintroduction_enabled = false
	var counters := {"destroyed": 0, "rebuilt": 0}
	sim.nest_changed.connect(func(_r: String, _s: String, active: bool) -> void:
		if active:
			counters["rebuilt"] += 1
		else:
			counters["destroyed"] += 1)
	sim.setup([region], [species], {"pen": {"爆育蚁": 2}})
	_check(counters["rebuilt"] >= 1, "初始立足自动建巢")
	for i in 5:
		sim.tick()
	var grown := sim.alive_count_in("pen")
	_check(grown > 2, "巢穴完好时繁衍正常（%d > 2）" % grown)
	# 捣毁 → 繁衍停止（先压数量给重建后的繁衍留承载空间）
	var kill_count := 0
	for inst: MonsterInstance in sim.instances.values():
		if kill_count >= 8:
			break
		if inst.is_alive:
			sim.report_killed(inst.id)
			kill_count += 1
	_check(sim.destroy_nest("pen", "爆育蚁"), "捣毁巢穴成功")
	_check(counters["destroyed"] >= 1, "捣毁发出 nest_changed(false)")
	_check(not sim.destroy_nest("pen", "爆育蚁"), "重复捣毁被拒绝")
	var at_destroy: int = sim.alive_count_in("pen")
	for i in 20:
		sim.tick()
	_check(sim.alive_count_in("pen") <= at_destroy,
		"巢穴被捣毁后繁衍停止（%d ≤ %d）" % [sim.alive_count_in("pen"), at_destroy])
	# 缩短重建倒计时 → 巢穴重建恢复繁衍
	sim.nests["pen|爆育蚁"]["rebuild"] = 2
	for i in 4:
		sim.tick()
	_check(bool(sim.nests["pen|爆育蚁"]["active"]), "rebuild 归零后巢穴重建")
	for i in 6:
		sim.tick()
	_check(sim.alive_count_in("pen") > at_destroy, "重建后繁衍恢复")

	# 元素克制乘子（纯函数）
	_check(is_equal_approx(CombatMath.elemental_multiplier("fire", "ice"), 1.5),
		"火克冰 ×1.5")
	_check(is_equal_approx(CombatMath.elemental_multiplier("ice", "fire"), 1.5),
		"冰克火 ×1.5")
	_check(is_equal_approx(CombatMath.elemental_multiplier("fire", "fire"), 0.8),
		"同元素互抗 ×0.8")
	_check(is_equal_approx(CombatMath.elemental_multiplier("", "fire"), 1.0),
		"无元素 ×1.0")


func _test_capacity_breeding() -> void:
	_current = "承载上限"
	print("[%s]" % _current)
	var region := SimRegion.new()
	region.id = "pen"
	region.display_name = "试验围栏"
	region.terrain = "plains"
	region.threat = 1.0
	region.capacity = 4
	region.center = Vector2.ZERO
	var species := SpeciesData.new()
	species.species_name = "爆育种"
	species.habitats = ["plains"]
	species.breeding_rate = 1.0  # 每 tick 必然出生
	species.maturity_age = 1
	species.migrate_count = 0
	var sim := EcologySim.new()
	sim.setup([region], [species], {"pen": {"爆育种": 2}})
	for i in 10:
		sim.tick()
	_check(sim.alive_count_in("pen") <= 4,
		"繁衍被区域承载截断（10 tick 后 %d <= 4）" % sim.alive_count_in("pen"))


func _test_aging_and_corpses() -> void:
	_current = "老化与尸体"
	print("[%s]" % _current)
	var region := SimRegion.new()
	region.id = "yard"
	region.display_name = "试验场"
	region.terrain = "plains"
	region.threat = 1.0
	region.capacity = 10
	var species := SpeciesData.new()
	species.species_name = "短命种"
	species.habitats = ["plains"]
	species.lifespan_min = 2
	species.lifespan_max = 2
	species.corpse_duration = 3
	species.maturity_age = 1
	species.breeding_rate = 0.0
	species.migrate_count = 0
	var sim := EcologySim.new()
	# 本用例验证"灭绝后清空"，关闭灭绝重引入（生态韧性是另一用例）
	sim.reintroduction_enabled = false
	var died_causes := {}
	sim.instance_died.connect(func(_i, cause): died_causes[cause] = died_causes.get(cause, 0) + 1)
	sim.setup([region], [species], {"yard": {"短命种": 3}})
	for i in 8:
		sim.tick()
	_check(int(died_causes.get("aging", 0)) == 3, "3 只全部老死")
	_check(sim.alive_count_in("yard") == 0, "无存活")
	_check(sim.instances.size() == 0, "尸体 %d tick 后全部消散，实例表清空" % species.corpse_duration)


func _test_long_run_invariants() -> void:
	_current = "长程模拟不变量（2000 tick）"
	print("[%s]" % _current)
	var sim := _new_sim()
	# GDScript lambda 对局部变量是值捕获，计数必须走引用类型（Dictionary）
	var counters := {"guardian_migrated": 0, "ant_migrated": 0}
	sim.instance_migrated.connect(func(inst: MonsterInstance, _to: String) -> void:
		if inst.species.species_name == "岩甲龟":
			counters["guardian_migrated"] += 1
		if inst.species.species_name == "兵蚁":
			counters["ant_migrated"] += 1
	)
	var ok_habitat := true
	var ok_capacity := true
	var ok_split_gen := true
	for i in 2000:
		sim.tick()
		if i % 100 == 0:
			for region: SimRegion in sim.regions.values():
				if sim.alive_count_in(region.id) > region.capacity:
					ok_capacity = false
			for inst: MonsterInstance in sim.instances.values():
				if inst.is_alive and not _region_terrain_ok(inst, sim):
					ok_habitat = false
				if inst.generation > 1:
					ok_split_gen = false
	_check(ok_capacity, "任意时刻各区域存活数不超过承载")
	_check(ok_habitat, "存活个体始终处于本种族栖息地")
	_check(ok_split_gen, "分裂世代不超过 max_generation")
	_check(counters["guardian_migrated"] == 0, "岩甲龟永不迁徙（迁徙 %d 次）" % counters["guardian_migrated"])
	_check(counters["ant_migrated"] > 0, "兵蚁发生扩张迁徙（%d 次）" % counters["ant_migrated"])
	_check(sim.tick_count == 2000, "tick 计数一致")
	var total_alive := 0
	for inst: MonsterInstance in sim.instances.values():
		if inst.is_alive:
			total_alive += 1
	print("  INFO  2000 tick 后总存活 %d" % total_alive)
	_check(total_alive > 0, "世界未整体灭绝")


func _region_terrain_ok(inst: MonsterInstance, sim: EcologySim) -> bool:
	return sim.get_region(inst.region_id) != null \
			and inst.region_id != "" \
			and (inst.species.habitats.is_empty()
				or inst.species.habitats.has(sim.get_region(inst.region_id).terrain))
