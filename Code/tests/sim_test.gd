## 生态模拟无头测试（纯逻辑，不依赖 autoload / 场景树 / 表现层）。
## 运行："$GODOT" --headless --path Code -s tests/sim_test.gd
## 输出逐项 PASS/FAIL，全部通过退出码 0。
extends SceneTree

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
	_test_predation_structures()
	_test_player_extinction()
	_test_predation_reachability()
	_test_nests()
	_test_capacity_breeding()
	_test_aging_and_corpses()
	_test_hp_mirror_roundtrip()
	_test_restore_adversarial()
	_test_migration_split_region()
	_test_long_run_invariants()
	_test_obstacle_field()
	_test_liquid_field()
	_test_landmarks()
	_test_seed_sweep()
	if _failures == 0:
		print("\n=== 全部测试通过 ===")
		quit(0)
	else:
		print("\n=== %d 项失败 ===" % _failures)
		quit(1)


# --- 测试用世界构造：直读 WorldConfig/BiomeMap 真源（区域布局 + 初始种群） ---
## 区域与种群都从 WorldConfig（由 BiomeMap 确定性派生）读取，改配置测试自动跟随；
## 区域 id 是斑块 id（p_i_j），坐标断言一律用斑块中心采样而非写死数字

func _build_regions() -> Array:
	var regions: Array = []
	for def: Dictionary in WorldConfig.region_defs():
		var region := SimRegion.new()
		region.id = def["id"]
		region.display_name = def["name"]
		region.terrain = def["terrain"]
		region.threat = def["threat"]
		region.center = def["center"]
		region.size = def["size"]
		region.capacity = def["capacity"]
		for neighbor: String in def["neighbors"]:
			region.neighbor_ids.append(neighbor)
		regions.append(region)
	return regions


func _initial_population() -> Dictionary:
	return WorldConfig.initial_population().duplicate(true)


## 指定地形的首个斑块 id（用例取样用）
func _patch_id_of(terrain: String) -> String:
	return BiomeMap.patches_of_terrain(terrain)[0]["id"]


func _new_sim() -> EcologySim:
	var sim := EcologySim.new()
	sim.setup(_build_regions(), _fresh_species(), _initial_population())
	return sim


## 用例专属物种副本：build_all 走 load()，Godot 资源缓存使每次调用返回同一批
## 实例——用例里改写参数（关繁衍/改重生倒计时）会持续污染其后所有用例
## （长程不变量曾跑在被篡改的数据上而测试顺序一变结论就变）。
## 每个 sim/用例持有 duplicate() 副本，改动不外泄
func _fresh_species() -> Array[SpeciesData]:
	var list: Array[SpeciesData] = []
	for s: SpeciesData in SpeciesCatalog.build_all():
		list.append(s.duplicate())
	return list


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
	var species := sim.find_species("妖鬼")
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
	var first: Array[Dictionary] = detector.detect_events(_fake_summary({"west": {"红史莱姆": 6}}))
	_check(first.is_empty(), "首帧快照不触发事件")

	# 入侵潮：east 从无甲虫 → 4 只（断言结构化字段而非文案——文案改写不断链）
	var invaded: Array[Dictionary] = detector.detect_events(
		_fake_summary({"west": {"红史莱姆": 6}, "east": {"甲虫": 4}}))
	_check(invaded.any(func(e: Dictionary) -> bool:
		return e["kind"] == "invade" and e["species"] == "甲虫"),
		"区域入侵潮被播报（%s）" % str(invaded))

	# 同类入侵 30s 内节流：再来一次同样事件不重复
	var again: Array[Dictionary] = detector.detect_events(
		_fake_summary({"west": {"红史莱姆": 5}, "east": {"甲虫": 4}}))
	_check(not again.any(func(e: Dictionary) -> bool: return e["kind"] == "invade"),
		"同类事件冷却期内不刷屏")

	# 全球灭绝：红史莱姆从世界上消失
	detector = detector_script.new()
	detector.detect_events(_fake_summary({"west": {"红史莱姆": 6}}))
	var extinct: Array[Dictionary] = detector.detect_events(_fake_summary({"east": {"甲虫": 4}}))
	_check(extinct.any(func(e: Dictionary) -> bool:
		return e["kind"] == "extinct" and e["species"] == "红史莱姆"),
		"全球灭绝被播报（%s）" % str(extinct))
	_check(extinct.all(func(e: Dictionary) -> bool:
		return e["kind"] != "extinct" or not str(e["text"]).contains("永远")),
		"未知死因的灭绝播报不谎称永久")


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
	# 期望值从 initial_population() 真源动态求和（改配置测试自动跟随）；
	# 100 斑块逐区断言太吵，聚合为全图总量 + 抽样斑块核对
	var expected := 0
	for region_id: String in WorldConfig.initial_population():
		for species_name in WorldConfig.initial_population()[region_id]:
			expected += int(WorldConfig.initial_population()[region_id][species_name])
	var actual := 0
	for region: SimRegion in sim.regions.values():
		actual += sim.alive_count_in(region.id)
	_check(actual == expected, "全图初始存活 %d（期望 %d）" % [actual, expected])
	var inst: MonsterInstance = sim.instances.values()[0]
	_check(is_equal_approx(inst.threat_scale, sim.get_region(inst.region_id).threat),
		"个体威胁系数取自所在斑块")
	# 噪声群系归属：斑块中心采样必属本斑块（BiomeMap 与模拟装配一致性）
	var snow: Dictionary = BiomeMap.patches_of_terrain("snow")[0]
	var snow_id: String = snow["id"]
	_check(sim.region_of_point(snow["center"]).id == snow_id,
		"斑块中心采样归属正确（%s）" % snow_id)
	_check(sim.get_region(BiomeMap.region_id_at(snow["center"])) != null
			and sim.get_region(BiomeMap.region_id_at(snow["center"])).terrain == "snow",
		"模拟区域装配与 BiomeMap 采样一致")
	_check(BiomeMap.spawn_patch()["terrain"] == "plains", "出生角斑块恒为平原（新手安全区）")


func _test_split_mechanics() -> void:
	_current = "红史莱姆分裂"
	print("[%s]" % _current)
	var sim := _new_sim()
	var center_id := _patch_id_of("forest")
	# 本用例验证"只有击杀才分裂"的精确数量，关闭捕食（沼泽蟹/野猪吃红史莱姆会引入噪音）
	sim.predation_enabled = false
	var victim: MonsterInstance = null
	for inst: MonsterInstance in sim.instances.values():
		if inst.is_alive and inst.species.species_name == "红史莱姆" and inst.region_id == center_id:
			victim = inst
			break
	_check(victim != null, "找到林地红史莱姆")
	var before: int = sim.alive_count_in(center_id, victim.species)
	var spawned: Array[MonsterInstance] = []
	sim.instance_spawned.connect(func(i): if i.generation > 0: spawned.append(i))
	sim.report_killed(victim.id)
	_check(spawned.size() == 2, "击杀原生代裂出 2 个子代（实际 %d）" % spawned.size())
	if spawned.size() > 0:
		var child := spawned[0]
		_check(child.generation == 1, "子代为第 1 代")
		_check(is_equal_approx(child.size_scale, 0.6), "子代体型 0.6（实际 %.2f）" % child.size_scale)
		_check(child.region_id == center_id, "子代留在母代区域")
		# 子代不再分裂
		var children_before: int = spawned.size()
		sim.report_killed(child.id)
		_check(sim.alive_count_in(center_id, victim.species) == before - 1 + children_before - 1,
			"击杀子代不再分裂，数量守恒")
	# 自然老死不分裂：把一只红史莱姆寿命改到立即老死
	var elder: MonsterInstance = null
	for inst: MonsterInstance in sim.instances.values():
		if inst.is_alive and inst.species.species_name == "红史莱姆":
			elder = inst
			break
	elder.age = 0
	elder.lifespan = 1
	var gen0_count := 0
	for inst: MonsterInstance in sim.instances.values():
		if inst.is_alive and inst.species.species_name == "红史莱姆" and inst.generation == 0:
			gen0_count += 1
	sim.tick()
	var gen0_after := 0
	for inst: MonsterInstance in sim.instances.values():
		if inst.is_alive and inst.species.species_name == "红史莱姆" and inst.generation == 0:
			gen0_after += 1
	_check(gen0_after == gen0_count - 1, "自然老死的红史莱姆不产生分裂（%d → %d）" % [gen0_count, gen0_after])
	# 分裂子代不育："逐代缩小且逐代不育"契约——子代成年后不参与繁衍，
	# 否则杀一只裂两只、长大再繁衍洗白回原生代，"越杀越多"没有自然出口
	var child2 := spawned[0] if spawned.size() > 0 and spawned[0].is_alive else null
	if child2 == null:
		child2 = sim.spawn_instance(victim.species, center_id, 0, 1, 0.6)
	child2.age = victim.species.maturity_age + 10  # 强制成年
	# 对照组：一只成年原生代（初始种群随机年龄可能恰好全部未成年，显式构造保证可比）
	sim.spawn_instance(victim.species, center_id, victim.species.maturity_age + 10, 0, 1.0)
	_check(child2.is_adult() and child2.is_split_sterile(), "成年分裂子代标记为不育")
	var sterile_adults := 0
	var fertile_adults := 0
	for inst: MonsterInstance in sim.instances.values():
		if inst.is_alive and inst.species.splits_on_death and inst.is_adult():
			if inst.is_split_sterile():
				sterile_adults += 1
			else:
				fertile_adults += 1
	_check(sterile_adults > 0 and fertile_adults > 0, "繁衍统计只计原生代成年（不育 %d / 可育 %d）" % [sterile_adults, fertile_adults])


## 捕食链健康度：每条捕食边（prey 引用）双方 habitats 必须共享地形——
## 否则该边永不可能同区触发（曾经的死链：甲虫吃妖鬼但栖息地无交集，
## "玩家清剿捕食者→猎物爆发"的生态级联在 5/8 条边上完全不存在）
func _test_predation_reachability() -> void:
	_current = "捕食链健康度"
	print("[%s]" % _current)
	var species_list := SpeciesCatalog.build_all()
	var by_name := {}
	for species in species_list:
		by_name[species.species_name] = species
	for predator: SpeciesData in species_list:
		for prey_name: String in predator.prey:
			var prey: SpeciesData = by_name.get(prey_name)
			if prey == null:
				_check(false, "%s 的 prey「%s」不存在" % [predator.species_name, prey_name])
				continue
			if prey.is_boss:
				_check(false, "%s 的 prey「%s」是 Boss（永不被捕食，应从配置移除）" % [
					predator.species_name, prey_name])
				continue
			var shared := false
			for habitat: String in predator.habitats:
				if habitat in prey.habitats:
					shared = true
					break
			_check(shared, "捕食边可同区触发：%s → %s（共享 %s）" % [
				predator.species_name, prey_name,
				"、".join(PackedStringArray(predator.habitats.filter(func(h): return h in prey.habitats)))])
	# 栖息地拼写存在于真实地图地形（拼错 = 静默永不繁衍）
	var terrains := {}
	for def: Dictionary in WorldConfig.region_defs():
		terrains[def["terrain"]] = true
	for species: SpeciesData in species_list:
		if species.habitats.is_empty():
			continue
		var valid := 0
		for habitat: String in species.habitats:
			if terrains.has(habitat):
				valid += 1
		_check(valid > 0, "%s 的 habitats 在真实地图上有效（%d/%d）" % [
			species.species_name, valid, species.habitats.size()])


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

	# 捕食：甲虫压制同区妖鬼（关繁衍排除噪音；改写作用于本用例的副本）
	var region := SimRegion.new()
	region.id = "pen"
	region.display_name = "围栏"
	region.terrain = "hill"
	region.threat = 1.0
	region.capacity = 20
	var by_name := {}
	for s: SpeciesData in _fresh_species():
		by_name[s.species_name] = s
	var goblin: SpeciesData = by_name["妖鬼"]
	var ant: SpeciesData = by_name["甲虫"]
	goblin.breeding_rate = 0.0
	ant.breeding_rate = 0.0
	var sim := EcologySim.new()
	# GDScript lambda 对局部变量是值捕获，计数必须走引用类型（Dictionary）
	var counters := {"predated": 0}
	sim.instance_died.connect(func(_i, cause: String) -> void:
		if cause == "predated":
			counters["predated"] += 1)
	sim.setup([region], [goblin, ant], {"pen": {"妖鬼": 10, "甲虫": 2}})
	# 强制捕食者成年 + 长寿：初始年龄 5~60 随机，双未成年时零捕食是假阴性
	for inst: MonsterInstance in sim.instances.values():
		if inst.species == ant:
			inst.age = ant.maturity_age + 5
			inst.lifespan = 100000
	for i in 60:
		sim.tick()
	_check(counters["predated"] > 0, "捕食死亡发生（60 tick 共 %d 次）" % counters["predated"])
	_check(sim.alive_count_in("pen", goblin) < 10,
		"妖鬼被压制（剩 %d < 10）" % sim.alive_count_in("pen", goblin))

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
	sim.nest_changed.connect(func(_r: String, _s: String, active: bool, _ransacked: bool) -> void:
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


## 血量镜像随存档往返：受击回写（report_hp）→ to_dict 只给带伤个体记 hp 键 →
## restore 保留，读档的怪带伤开局不"白送满血"；坏值（负数/字符串）回退满血
func _test_hp_mirror_roundtrip() -> void:
	_current = "血量镜像存档往返"
	print("[%s]" % _current)
	var region := SimRegion.new()
	region.id = "yard"
	region.display_name = "试验场"
	region.terrain = "plains"
	region.threat = 1.0
	region.capacity = 10
	var species := SpeciesData.new()
	species.species_name = "受击种"
	species.habitats = ["plains"]
	species.maturity_age = 1
	species.breeding_rate = 0.0
	species.migrate_count = 0
	var sim := EcologySim.new()
	sim.reintroduction_enabled = false
	sim.setup([region], [species], {})
	var hurt := sim.spawn_instance(species, "yard", 10)
	var fresh := sim.spawn_instance(species, "yard", 10)
	sim.report_hp(hurt.id, 12.5)
	_check(absf(hurt.hp_mirror - 12.5) < 0.001, "report_hp 回写镜像")
	var snap := sim.to_dict()
	var hurt_entry := {}
	var fresh_entry := {}
	for e: Dictionary in snap["instances"]:
		if e["id"] == hurt.id:
			hurt_entry = e
		elif e["id"] == fresh.id:
			fresh_entry = e
	_check(hurt_entry.has("hp") and absf(float(hurt_entry.get("hp", 0.0)) - 12.5) < 0.001,
		"带伤个体序列化 hp 键")
	_check(not fresh_entry.has("hp"), "未受伤个体不带 hp 键（旧档无键 = 满血，兼容）")
	var sim2 := EcologySim.new()
	_check(sim2.restore_from_dict([region], [species.duplicate()], snap), "快照可恢复")
	var hurt2: MonsterInstance = sim2.instances.get(hurt.id)
	var fresh2: MonsterInstance = sim2.instances.get(fresh.id)
	_check(hurt2 != null and absf(hurt2.hp_mirror - 12.5) < 0.001, "读档带伤开局（hp 往返）")
	_check(fresh2 != null and fresh2.hp_mirror < 0.0, "未受伤个体读档仍为满血语义（-1）")
	# 坏值防御：hp 写负数/字符串 → 回退满血，不崩不吐脏值
	hurt_entry["hp"] = -5.0
	fresh_entry["hp"] = "full"
	var sim3 := EcologySim.new()
	_check(sim3.restore_from_dict([region], [species.duplicate()], snap), "坏 hp 快照仍可恢复")
	var hurt3: MonsterInstance = sim3.instances.get(hurt.id)
	var fresh3: MonsterInstance = sim3.instances.get(fresh.id)
	_check(hurt3 != null and hurt3.hp_mirror < 0.0 and fresh3 != null and fresh3.hp_mirror < 0.0,
		"非法 hp（负数/字符串）被忽略回退满血")


## 玩家灭杀致绝 = 永久灭绝（世界线记忆，随存档往返）：重引入对其失效；
## 自然兴衰（老死/竞争/捕食）归零不计入名单，仍可"从世界边缘迁徙回来"
func _test_player_extinction() -> void:
	_current = "玩家灭杀永久灭绝"
	print("[%s]" % _current)
	var region := SimRegion.new()
	region.id = "isle"
	region.display_name = "孤岛"
	region.terrain = "plains"
	region.threat = 1.0
	region.capacity = 20
	var hunted := _mortal_species("围猎种", 100000)  # 不老死：灭绝只能由玩家造成
	var faded := _mortal_species("短命种", 3)  # 自然老死灭绝
	var sim := EcologySim.new()
	sim.setup([region], [hunted, faded], {"isle": {"围猎种": 2, "短命种": 2}})
	# 短命种年龄钉到寿命之上：setup 的随机年龄依赖全局 RNG 序列（营地避障
	# 重试等消耗点会让序列漂移），赌"随机年龄≥寿命"曾偶发死前繁衍挂断言
	for inst: MonsterInstance in sim.instances.values():
		if inst.species == faded:
			inst.age = inst.lifespan + 1
	# 玩家把围猎种赶尽杀绝
	var ids: Array = []
	for inst: MonsterInstance in sim.instances.values():
		if inst.species == hunted and inst.is_alive:
			ids.append(inst.id)
	for id in ids:
		sim.report_killed(id)
	_check(sim.alive_count_of_species("围猎种") == 0, "围猎种被玩家灭杀归零")
	_check(sim.player_extinct.has("围猎种"), "玩家灭杀致绝记入世界线永久名单")
	# 短命种自然老死（不计入名单）
	for i in 6:
		sim.tick()
	_check(sim.alive_count_of_species("短命种") == 0, "短命种自然老死归零")
	_check(not sim.player_extinct.has("短命种"), "自然灭绝不计入永久名单")
	# 名单随存档往返；围猎种永不重引入，短命种会被重引入（事件计数， lambda 值捕获走 Dictionary；
	# 物种比较必须按名字——restore 后 sim2 持有的是 duplicate() 副本，对象引用永不相等）
	var snap := sim.to_dict()
	var sim2 := EcologySim.new()
	sim2.restore_from_dict([region], [hunted.duplicate(), faded.duplicate()], snap)
	_check(sim2.player_extinct.has("围猎种"), "永久灭绝名单随存档往返")
	var spawned := {"hunted": 0, "faded": 0}
	sim2.instance_spawned.connect(func(inst: MonsterInstance) -> void:
		if inst.species.species_name == "短命种":
			spawned["faded"] += 1
		elif inst.species.species_name == "围猎种":
			spawned["hunted"] += 1)
	for i in 300:
		sim2.tick()
	_check(int(spawned["hunted"]) == 0,
		"玩家灭杀致绝 300 tick 零重引入（5%/tick 无豁免时置信度 >99.99%）")
	_check(int(spawned["faded"]) > 0, "自然灭绝物种仍被重引入（%d 次）" % spawned["faded"])


## 测试用短命物种构造（不繁衍不迁徙，寿命可指定）
func _mortal_species(p_name: String, lifespan: int) -> SpeciesData:
	var s := SpeciesData.new()
	s.species_name = p_name
	s.habitats = ["plains"]
	s.lifespan_min = lifespan
	s.lifespan_max = lifespan
	s.maturity_age = 1
	s.breeding_rate = 0.0
	s.migrate_count = 0
	s.prey = []
	return s


## 捕食结构约束（2026-09-03 修复的回归锁）：濒危豁免 + 饱食限流。
## 修复前探针实证：6 个猎物物种 95%+ 时间处于灭绝态（灭绝→重引入脉冲循环）
func _test_predation_structures() -> void:
	_current = "捕食结构约束"
	print("[%s]" % _current)
	var by_name := {}
	for s: SpeciesData in _fresh_species():
		by_name[s.species_name] = s
	var goblin: SpeciesData = by_name["妖鬼"]
	var ant: SpeciesData = by_name["甲虫"]
	goblin.breeding_rate = 0.0
	ant.breeding_rate = 0.0

	# 濒危豁免：猎物全球 < ENDANGERED_THRESHOLD 时捕食者找不到它——
	# 100 tick × 3 成年捕食者 × 8% 若无豁免几乎必然击杀（P(零杀)≈0.03%）
	var region := SimRegion.new()
	region.id = "pen1"
	region.display_name = "豁免围栏"
	region.terrain = "hill"
	region.threat = 1.0
	region.capacity = 30
	var sim := EcologySim.new()
	sim.setup([region], [goblin, ant], {"pen1": {"妖鬼": 4, "甲虫": 3}})
	# lambda 值捕获：计数走 Dictionary（int 局部变量的写入会丢失，断言会变成永真）
	var exempt_kills := {"n": 0}
	sim.instance_died.connect(func(_i, cause: String) -> void:
		if cause == "predated":
			exempt_kills["n"] += 1)
	for i in 100:
		sim.tick()
	_check(int(exempt_kills["n"]) == 0, "濒危猎物（<6 只）豁免捕食（100 tick 击杀 %d）" % exempt_kills["n"])

	# 饱食限流：首次猎杀成功的瞬间，捕食者进入 PREDATOR_SATIETY_TICKS 饱食
	var region2 := SimRegion.new()
	region2.id = "pen2"
	region2.display_name = "饱食围栏"
	region2.terrain = "hill"
	region2.threat = 1.0
	region2.capacity = 40
	var sim2 := EcologySim.new()
	sim2.setup([region2], [goblin, ant], {"pen2": {"妖鬼": 20, "甲虫": 1}})
	var predator: MonsterInstance = null
	for inst: MonsterInstance in sim2.instances.values():
		if inst.species == ant:
			predator = inst
	# 强制成年 + 长寿，排除初始随机年龄导致的"幼体不捕食"假阴性
	predator.age = ant.maturity_age + 5
	predator.lifespan = 100000
	# lambda 值捕获：计数必须走引用类型（Dictionary），int 局部变量的写入会丢失
	var satiety_at_first := {"v": -1}
	sim2.instance_died.connect(func(_i, cause: String) -> void:
		if cause == "predated" and satiety_at_first["v"] == -1:
			satiety_at_first["v"] = int(sim2._satiety.get(predator.id, -1)))
	for i in 120:
		sim2.tick()
	_check(int(satiety_at_first["v"]) == EcologySim.PREDATOR_SATIETY_TICKS,
		"猎杀成功即进入饱食（首次击杀时饱食 %d，期望 %d）" % [
			int(satiety_at_first["v"]), EcologySim.PREDATOR_SATIETY_TICKS])


## 坏档恢复对抗：巢穴缺键 / spawn_pos 元素非数值 / 布尔写字符串——
## restore 必须消毒（缺 active 键曾在 _process_nests 每 tick 刷 Invalid access）
func _test_restore_adversarial() -> void:
	_current = "坏档恢复防御"
	print("[%s]" % _current)
	var sim := EcologySim.new()
	var west_id := _patch_id_of("plains")
	sim.setup(_build_regions(), _fresh_species(), {})
	sim.spawn_instance(sim.find_species("妖鬼"), west_id)
	var snap := sim.to_dict()
	var entries: Array = snap["instances"]
	entries[0]["spawn_pos"] = ["x", {}]
	entries[0]["elite"] = "false"
	entries[0]["alive"] = "false"
	snap["nests"] = {"%s|妖鬼" % west_id: {"active": true}, "%s|萌芽怪" % west_id: {"rebuild": 5}}
	var sim2 := EcologySim.new()
	_check(sim2.restore_from_dict(_build_regions(), _fresh_species(), snap),
		"坏键快照仍可恢复（实例非空）")
	var nest1: Dictionary = sim2.nests.get("%s|妖鬼" % west_id, {})
	_check(nest1.has("active") and nest1.has("rebuild"), "缺 rebuild 的巢穴被补全为规范结构")
	var nest2: Dictionary = sim2.nests.get("%s|萌芽怪" % west_id, {})
	_check(bool(nest2.get("active", false)), "缺 active 的巢穴默认为有效巢")
	var restored: MonsterInstance = null
	for inst: MonsterInstance in sim2.instances.values():
		restored = inst
	if restored != null:
		_check(restored.is_alive and not restored.is_elite,
			"字符串布尔被防御：alive 坏值按活回落（与缺键同口径），elite 坏值不判 true")
		# 非数值 spawn_pos 被忽略回 INF 后，按「存活实例必有位置」不变量
		# 由营地补齐（否则该实例滞留待生成池永不生成节点）
		_check(restored.spawn_pos != Vector2.INF, "活体实例坏位置被忽略后按营地补齐（流式可生成）")
	for i in 30:
		sim2.tick()
	_check(true, "坏档恢复后 30 tick 无键访问错误")
	# 全死快照（alive 明确 false）必须恢复失败：0 活体世界若被当作"恢复成功"
	# 写回存档，「继续冒险」将永远面对空世界（碰不到任何怪物且不会自愈）——
	# 返回 false 让 game_world 回退 setup 重新撒放
	var dead_snap: Dictionary = snap.duplicate(true)
	for entry: Dictionary in dead_snap["instances"]:
		entry["alive"] = false
	var sim3 := EcologySim.new()
	_check(not sim3.restore_from_dict(_build_regions(), _fresh_species(), dead_snap),
		"全死快照恢复失败（回退 setup，防固化空世界）")


## 迁徙途中被截杀的分裂子代落区：region_id 已指向新区（出发瞬间写入）而
## 死亡位置还在旧区——子代应按死亡位置归属（旧实现"记在新区、生在旧位置"）
func _test_migration_split_region() -> void:
	_current = "迁徙途中击杀的分裂落区"
	print("[%s]" % _current)
	var species_list := _fresh_species()
	var slime: SpeciesData = null
	for s: SpeciesData in species_list:
		if s.species_name == "红史莱姆":
			slime = s
	var sim := EcologySim.new()
	sim.setup(_build_regions(), species_list, {})
	var snow: Dictionary = BiomeMap.patches_of_terrain("snow")[0]
	var snow_id: String = snow["id"]
	# 迁徙指向：邻斑里挑一个非雪原的（让"模拟归属"与"死亡位置归属"确实不同）
	var neighbor_id: String = snow["neighbors"][0]
	for nid: String in snow["neighbors"]:
		if BiomeMap.patch(nid)["terrain"] != "snow":
			neighbor_id = nid
			break
	var mother := sim.spawn_instance(slime, snow_id)
	mother.region_id = neighbor_id  # 模拟迁徙出发瞬间（模拟层已改指向、节点还在雪原）
	# 截杀点取斑块中心（斑块内部深处，远离犬牙边界，杜绝归属歧义）
	sim.report_killed(mother.id, snow["center"])
	var children: Array[MonsterInstance] = []
	for inst: MonsterInstance in sim.instances.values():
		if inst.is_alive and inst.species.species_name == "红史莱姆" and inst.generation > 0:
			children.append(inst)
	_check(children.size() == 2, "分裂出 2 子代（实际 %d）" % children.size())
	var all_in_snow := not children.is_empty()
	for c: MonsterInstance in children:
		if c.region_id != snow_id:
			all_in_snow = false
	_check(all_in_snow, "子代按死亡位置归属雪原斑块（而非模拟指向的邻斑）")


func _test_long_run_invariants() -> void:
	_current = "长程模拟不变量（2000 tick）"
	print("[%s]" % _current)
	var sim := _new_sim()
	# GDScript lambda 对局部变量是值捕获，计数必须走引用类型（Dictionary）
	var counters := {"guardian_migrated": 0, "ant_migrated": 0}
	sim.instance_migrated.connect(func(inst: MonsterInstance, _to: String) -> void:
		if inst.species.species_name == "石像鬼":
			counters["guardian_migrated"] += 1
		if inst.species.species_name == "甲虫":
			counters["ant_migrated"] += 1
	)
	var ok_habitat := true
	var ok_capacity := true
	var ok_split_gen := true
	# 逐物种存活占比采样（每 10 tick 一次）：长程只断言总量 >0 测不出
	# "猎物被压进灭绝→重引入脉冲循环"（2026-09-03 修复前 6 物种 95%+ 时间灭绝）
	var occupancy := {}
	for s: SpeciesData in sim.species_list:
		occupancy[s.species_name] = 0
	var samples := 0
	for i in 2000:
		sim.tick()
		if i % 10 == 0:
			samples += 1
			var alive_names := {}
			for inst: MonsterInstance in sim.instances.values():
				if inst.is_alive:
					alive_names[inst.species.species_name] = true
			for n: String in occupancy:
				if alive_names.has(n):
					occupancy[n] += 1
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
	var min_occ := 1.0
	var healthy := 0
	for n: String in occupancy:
		var occ: float = float(occupancy[n]) / samples
		min_occ = minf(min_occ, occ)
		if occ >= 0.8:
			healthy += 1
	# 阈值口径：修复前坍缩物种存活占比 3~15%，20% 地板对回归仍是决定性拦截；
	# 上限留足随机余量——2000 tick 自然动态下偶发深潜实测可到 28%（六连跑 1 次触 30% 旧阈）
	_check(min_occ >= 0.2, "逐物种存活占比 ≥20%%（最低 %.0f%%）——灭绝脉冲循环回归锁" % (min_occ * 100.0))
	print("  INFO  逐物种存活占比最低 %.0f%%，≥80%% 物种 %d/%d" % [min_occ * 100.0, healthy, occupancy.size()])
	_check(healthy >= occupancy.size() - 6, "多数物种存活占比 ≥80%%（%d/%d）" % [healthy, occupancy.size()])
	_check(counters["guardian_migrated"] == 0, "石像鬼永不迁徙（迁徙 %d 次）" % counters["guardian_migrated"])
	_check(counters["ant_migrated"] > 0, "甲虫发生扩张迁徙（%d 次）" % counters["ant_migrated"])
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


## 世界 v5：多种子扫描——「新的冒险」每档全新世界的结构性不变量。
## 覆盖：家园角强制平原 / 六地形覆盖兜底 / Boss 斑块存在 / 同种子确定性 /
## 非默认种子的营地归属 / 区域多边形（marching-squares）与 region_id_at 一致。
## 收尾恢复 DEFAULT_SEED（离线工具与其余约定仍假定默认世界）
func _test_seed_sweep() -> void:
	for seed_value in [BiomeMap.DEFAULT_SEED, 1, 42, 987654321, -20260908]:
		BiomeMap.configure(seed_value)
		var tag := "种子 %d" % seed_value
		_check(BiomeMap.spawn_patch()["terrain"] == "plains", "%s：出生角斑块恒为平原" % tag)
		var corner_ok := true
		var terrains := {}
		for def: Dictionary in BiomeMap.patches():
			terrains[def["terrain"]] = true
			if def["i"] + def["j"] <= 1 and def["terrain"] != "plains":
				corner_ok = false
		_check(corner_ok, "%s：家园角 2×2 强制平原" % tag)
		var coverage_ok := true
		for t in BiomeMap.TERRAIN_INFO:
			if not terrains.has(t):
				coverage_ok = false
		_check(coverage_ok, "%s：六地形全部有斑块（兜底生效）" % tag)
		for t in ["forest", "hill", "lava"]:
			_check(not BiomeMap.farthest_patch(t).is_empty(), "%s：%s 存在最远 Boss 斑块" % [tag, t])
		# 同种子确定性：configure 重入后采样结果逐位一致
		var probe := Vector2(123456.0, 654321.0)
		var expect_terrain := BiomeMap.terrain_at(probe)
		var expect_spawn := BiomeMap.spawn_pos()
		BiomeMap.configure(seed_value)
		_check(BiomeMap.terrain_at(probe) == expect_terrain and BiomeMap.spawn_pos() == expect_spawn,
				"%s：同种子采样确定性" % tag)
	# 非默认种子的生态装配冒烟：全部区域 × 物种营地落在自己斑块内
	# （camp_pos 的归属校验与折半回退在任何种子下都必须成立）
	BiomeMap.configure(42)
	var sim := _new_sim()
	var camp_bad := 0
	for region: SimRegion in sim.regions.values():
		for species: SpeciesData in sim.species_list:
			var camp: Vector2 = sim.camp_pos(region, species)
			if camp != region.center and BiomeMap.region_id_at(camp) != region.id:
				camp_bad += 1
	_check(camp_bad == 0, "非默认种子营地全部归属本斑块（越界 %d 处）" % camp_bad)
	# 区域多边形一致性：随机采样远离边界的点（次近距离差 > 3 格栅格），
	# 点在多边形中的归属必须与 region_id_at 一致（Area2D 检测的地基）
	BiomeMap.configure(BiomeMap.DEFAULT_SEED)
	var polys := {}
	for def: Dictionary in BiomeMap.patches():
		polys[def["id"]] = BiomeMap.patch_polygons(def["id"], 1000.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260908
	var checked := 0
	var mismatch := ""
	for i in 500:
		var p := Vector2(rng.randf_range(0.0, 800000.0), rng.randf_range(0.0, 800000.0))
		var f := BiomeMap.field_at(p)
		if sqrt(f["d2"]) - sqrt(f["d1"]) < 3000.0:
			continue  # 边界 3 格内：阶梯近似与真边界的合法偏差带，不判
		var got := ""
		for id in polys:
			for loop: PackedVector2Array in polys[id]:
				if _point_in_polygon(p, loop):
					got = id
					break
			if got != "":
				break
		checked += 1
		if got != f["id1"]:
			mismatch = "期望 %s 多边形 %s @%s" % [f["id1"], got, p]
			break
	_check(mismatch == "", "多边形归属与 region_idat 一致（%s）" % mismatch)
	_check(checked >= 100, "多边形一致性采样充分（%d 点）" % checked)


## 射线法点在（凹）多边形内判定（多边形一致性断言用）
func _point_in_polygon(p: Vector2, poly: PackedVector2Array) -> bool:
	var inside := false
	var j := poly.size() - 1
	for i in poly.size():
		var a := poly[j]
		var b := poly[i]
		if (a.y > p.y) != (b.y > p.y):
			var x := a.x + (p.y - a.y) / (b.y - a.y) * (b.x - a.x)
			if p.x < x:
				inside = not inside
		j = i
	return inside


## 世界 v5 障碍场不变量：同种子确定性 / 覆盖率分带（调参守闸）/ 斑块中心与
## 出生点净空 / KIND 图集映射一致 / 采样窗自由区连通（走廊保证，无孤立口袋）
func _test_obstacle_field() -> void:
	BiomeMap.configure(BiomeMap.DEFAULT_SEED)
	# ① 确定性：configure 重入后同格采样逐位一致
	var probes: Array[Vector2i] = [Vector2i(100, 200), Vector2i(460, 300),
		Vector2i(1250, 10007), Vector2i(3, 1)]
	var expect: Array = []
	for c in probes:
		expect.append(ObstacleField.sample_cell(c).get("kind", ""))
	BiomeMap.configure(BiomeMap.DEFAULT_SEED)
	var same := true
	for i in probes.size():
		if ObstacleField.sample_cell(probes[i]).get("kind", "") != expect[i]:
			same = false
	_check(same, "障碍场同种子确定性")
	# ② KIND_ATLAS 与 KIND_INFO 键集一致（图集布局与铺格层防漂移）
	var atlas_ok := ObstacleField.KIND_ATLAS.size() == ObstacleField.KIND_INFO.size()
	for k in ObstacleField.KIND_INFO:
		if not ObstacleField.KIND_ATLAS.has(k):
			atlas_ok = false
	_check(atlas_ok, "障碍图集映射与类型表一致")
	# ③ 覆盖率分带（每地形 2 个斑块样窗，阈值见 ObstacleField.RECIPES 注释）
	var bands := {
		"plains": [0.02, 0.07], "forest": [0.15, 0.34], "snow": [0.06, 0.22],
		"swamp": [0.06, 0.22], "hill": [0.10, 0.30], "lava": [0.06, 0.22],
	}
	for terrain: String in bands:
		var patches := BiomeMap.patches_of_terrain(terrain)
		var cov := 0.0
		var n := 0
		for p: Dictionary in patches.slice(0, 2):
			var c: Vector2 = p["center"]
			# 中心 600px 抑制区外取样（1600px 偏移）
			cov += ObstacleField.coverage_in(Rect2(c + Vector2(1600, 1600), Vector2(6400, 6400)))
			n += 1
		cov /= float(n)
		var band: Array = bands[terrain]
		_check(cov >= band[0] and cov <= band[1],
				"%s 障碍覆盖率 %.1f%% 在带 [%d%%, %d%%]" % [terrain, cov * 100.0,
					int(band[0] * 100.0), int(band[1] * 100.0)])
	# ④ 净空：全部斑块中心 + 出生点（复活/出生保底）
	var clear_ok := true
	for p: Dictionary in BiomeMap.patches():
		if ObstacleField.blocks(p["center"], 20.0):
			clear_ok = false
	_check(clear_ok, "全部斑块中心 600px 净空")
	_check(not ObstacleField.blocks(BiomeMap.spawn_pos(), 40.0), "出生点 1200px 净空")
	# ⑤ 自由区连通：样本窗内"封闭口袋"占比 ≤5%（走廊 ≥2 格宽 + 岩脊分段的实证；
	#    导航阻挡口径（含死点填充）——与导航层同口径的连通性才有意义）。
	#    口袋 = 完全不碰窗口边界的自由分量：细长走廊穿出窗口再折回不算孤岛
	#    （窗口边界会把边界连通的走廊误切成多段，口径必须豁免边界分量）
	for terrain: String in ["plains", "forest", "hill"]:
		var p: Dictionary = BiomeMap.patches_of_terrain(terrain)[0]
		var c: Vector2 = p["center"]
		var pocket := _pocket_ratio(Rect2(c + Vector2(1600, 1600), Vector2(3200, 3200)))
		_check(pocket <= 0.05, "%s 采样窗封闭口袋占比 %.1f%%（走廊无孤岛）" % [terrain, pocket * 100.0])


## 样本窗自由格中"不触边界的封闭分量"占比（BFS，导航阻挡口径）
func _pocket_ratio(rect: Rect2) -> float:
	var c0 := Vector2i(floori(rect.position.x / 32.0), floori(rect.position.y / 32.0))
	var c1 := Vector2i(floori(rect.end.x / 32.0), floori(rect.end.y / 32.0))
	var w := c1.x - c0.x
	var h := c1.y - c0.y
	if w <= 0 or h <= 0:
		return 1.0
	var blocked := PackedByteArray()
	blocked.resize(w * h)
	var free := 0
	for y in h:
		for x in w:
			var b := int(ObstacleField.is_nav_blocked(c0 + Vector2i(x, y)))
			blocked[y * w + x] = b
			if b == 0:
				free += 1
	if free == 0:
		return 0.0
	var seen := PackedByteArray()
	seen.resize(w * h)
	var pocket_cells := 0
	var queue: Array[int] = []
	for start in w * h:
		if blocked[start] == 1 or seen[start] == 1:
			continue
		var comp := 0
		var touches_border := false
		queue = [start]
		seen[start] = 1
		while not queue.is_empty():
			var idx: int = queue.pop_back()
			comp += 1
			var x := idx % w
			var y := idx / w
			if x == 0 or y == 0 or x == w - 1 or y == h - 1:
				touches_border = true
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx := x + d.x
				var ny := y + d.y
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue
				var nidx := ny * w + nx
				if blocked[nidx] == 0 and seen[nidx] == 0:
					seen[nidx] = 1
					queue.append(nidx)
		if not touches_border:
			pocket_cells += comp
	return float(pocket_cells) / float(free)


## 世界 v5 地标不变量：确定性 / 全斑块覆盖 / id 唯一 / 落点通行且在所属斑块
func _test_landmarks() -> void:
	BiomeMap.configure(BiomeMap.DEFAULT_SEED)
	var lms: Array = LandmarkRegistry.landmarks()
	_check(lms.size() >= 100 and lms.size() <= 190, "地标总量 %d 在 [100, 190]" % lms.size())
	var ids := {}
	var pos_ok := true
	var patch_covered := {}
	for lm: Dictionary in lms:
		ids[lm["id"]] = true
		patch_covered[lm["patch_id"]] = true
		if ObstacleField.blocks(lm["pos"], 12.0):
			pos_ok = false
	_check(ids.size() == lms.size(), "地标 id 唯一（%d/%d）" % [ids.size(), lms.size()])
	_check(pos_ok, "全部地标落点通行（不压障碍）")
	_check(patch_covered.size() == BiomeMap.patches().size(), "全部斑块各有地标（%d/%d）" % [
		patch_covered.size(), BiomeMap.patches().size()])
	# 确定性：重入同种子后逐位一致
	var first: Vector2 = lms[0]["pos"]
	LandmarkRegistry._cache = []  # 模拟冷启动
	var again: Array = LandmarkRegistry.landmarks()
	_check(again.size() == lms.size() and again[0]["pos"] == first and again[0]["id"] == lms[0]["id"],
			"地标同种子确定性")


## 世界 v5 液体场：可见水与阻挡深水同源（painter._material 一致性契约）/
## 熔岩池存在且可通行 / 覆盖带 / 抑制区 / 可破坏覆盖层往返
func _test_liquid_field() -> void:
	BiomeMap.configure(BiomeMap.DEFAULT_SEED)
	# ① painter 与液体真源逐点一致（画出来的水 == 判得到的水）：随机采样
	# snow/hill/lava 三液体群系的点，_material()==2 ⇔ liquid_kind_in()!=""
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260909
	var mismatches := 0
	var sampled := 0
	for terrain: String in ["snow", "hill", "lava", "plains", "swamp"]:
		var patches := BiomeMap.patches_of_terrain(terrain)
		if patches.is_empty():
			continue
		var center: Vector2 = patches[rng.randi() % patches.size()]["center"]
		for i in 40:
			var p := center + Vector2(rng.randf_range(-20000.0, 20000.0),
					rng.randf_range(-20000.0, 20000.0))
			p = p.clamp(Vector2(1000, 1000), BiomeMap.WORLD_SIZE - Vector2(1000, 1000))
			var pid := BiomeMap.region_id_at(p)
			var t := BiomeMap.terrain_of_patch(pid)
			var gtx := floori(p.x / 16.0)
			var gty := floori(p.y / 16.0)
			var m: int = TerrainPainter._material(t, gtx, gty, p, pid)
			var liquid: String = ObstacleField.liquid_kind_in(t, p, pid)
			sampled += 1
			if (m == 2) != (liquid != ""):
				mismatches += 1
	_check(mismatches == 0, "地表水材质与液体场逐点一致（%d/%d 不符）" % [mismatches, sampled])
	# ② 深水阻挡覆盖带（snow/hill 样窗内 water 阻挡格占比）+ 熔岩池可通行
	for terrain: String in ["snow", "hill"]:
		var p: Dictionary = BiomeMap.patches_of_terrain(terrain)[0]
		var c: Vector2 = p["center"]
		var cov := ObstacleField.coverage_in(Rect2(c + Vector2(2000, 2000), Vector2(6400, 6400)))
		_check(cov < 0.30, "%s 深水+障碍覆盖 %.1f%% 未失控（<30%%）" % [terrain, cov * 100.0])
	var lava_p: Dictionary = BiomeMap.patches_of_terrain("lava")[0]
	var lc: Vector2 = lava_p["center"]
	var lava_liquid := 0
	var water_kind := 0
	var cell0 := Vector2i(int(lc.x / 32.0) + 20, int(lc.y / 32.0) + 20)
	for dy in 80:
		for dx in 80:
			var cell := cell0 + Vector2i(dx, dy)
			var pos := (Vector2(cell) + Vector2(0.5, 0.5)) * 32.0
			if ObstacleField.liquid_kind_in("lava", pos, lava_p["id"]) == "lava":
				lava_liquid += 1
			var s2 := ObstacleField.sample_cell(cell)
			if not s2.is_empty() and s2["kind"] == "water":
				water_kind += 1
	_check(lava_liquid > 0, "熔岩地带存在熔岩池（%d 格）" % lava_liquid)
	_check(water_kind == 0, "熔岩带无深水阻挡瓦（灼烧不阻挡；池内水晶/骨堆属配方障碍）")
	# ③ 抑制区无液体（复活点/出生点保底）
	var clear := true
	for p: Dictionary in BiomeMap.patches():
		var pid: String = p["id"]
		if ObstacleField.liquid_kind_in(p["terrain"], p["center"], pid) != "":
			clear = false
	_check(clear, "全部斑块中心无液体（抑制区生效）")
	# ④ 可破坏覆盖层：耐久递减 → 摧毁 → 存档往返恢复
	var none := Vector2i(1073741823, 1073741823)
	var rock_cell := none
	for dy in 200:
		for dx in 200:
			var cell := Vector2i(int(lc.x / 32.0) - 100 + dx, int(lc.y / 32.0) - 100 + dy)
			var s2 := ObstacleField.sample_cell(cell)
			if not s2.is_empty() and ObstacleField.DESTRUCTIBLE.has(s2["kind"]):
				rock_cell = cell
				break
		if rock_cell != none:
			break
	if rock_cell != none:
		var first: String = ObstacleField.damage_cell(rock_cell)
		_check(first == "", "可破坏障碍首击仅掉耐久不摧毁")
		var second: String = ObstacleField.damage_cell(rock_cell)
		_check(second != "", "第二击摧毁（返回类型 %s）" % second)
		_check(ObstacleField.sample_cell(rock_cell).is_empty(), "摧毁后采样为空")
		var saved_list := ObstacleField.destroyed_list()
		_check(saved_list.size() == 1, "摧毁列表序列化（%d 条）" % saved_list.size())
		ObstacleField.restore_destroyed(saved_list)
		_check(ObstacleField.sample_cell(rock_cell).is_empty(), "往返恢复后仍为摧毁态")
		ObstacleField.restore_destroyed([])
		_check(not ObstacleField.sample_cell(rock_cell).is_empty(), "清空覆盖层后障碍复原")
		ObstacleField.restore_destroyed(saved_list)  # 留下摧毁态防影响后续用例
	else:
		_check(false, "熔岩带 200×200 格内未找到可破坏障碍（采样异常）")
