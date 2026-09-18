## 数值平衡校验 v2（纯公式层，不加载场景）。
## 运行："$GODOT" --headless --path Code -s tests/balance_test.gd
## 三层断言，全部取真源（本文件零手抄公式/零手抄阵容）：
##   A. 一致性——CombatBandMath 目标带 与 WorldConfig 区域配置 不漂移；
##   B. 区域对刀——每区域×物种（按 habitats 自动展开）落进目标带：
##      击杀刀数 ∈ kill 带（重甲物种走 kill_heavy 带）；被击承受 ≥ die_solo/die_pack；
##   C. 反推自洽——目标带反推出的 base_strength 区间非空，取中心实测确实落带
##      （P4 新物种数值由该公式生成，公式本身必须先被证明）；
##   D. 经济带——击杀掉落量级 / 商店可负担性（pacing "金币支撑 ≥2 次强化"的静态版）。
extends SceneTree

var _failures := 0


func _init() -> void:
	randomize()
	var species_list := SpeciesCatalog.build_all()
	var by_name := {}
	for s in species_list:
		by_name[s.species_name] = s
	var terrain_species := _expand_terrain_species(by_name)
	_check_consistency()
	for terrain: String in terrain_species:
		var band: Dictionary = CombatBandMath.TERRAIN_BANDS[terrain]
		for species: SpeciesData in terrain_species[terrain]:
			_check_species(terrain, band, species)
	_check_derivation(terrain_species)
	_check_economy(by_name)
	if _failures == 0:
		print("\n=== 平衡校验全部通过（带/反推/经济） ===")
		quit(0)
	else:
		print("\n=== %d 项超出手感区间 ===" % _failures)
		quit(1)


## 地形×物种按 habitats 自动展开（与 EcologySim 出生语义一致，杜绝手抄阵容漂移；
## v4 同地形多斑块共享一套手感带，按地形去重展开）；
## Boss 排除：唯一个体 + 体型放大，参考体型 1.0 的对刀不适用
func _expand_terrain_species(by_name: Dictionary) -> Dictionary:
	var out := {}
	for terrain: String in WorldConfig.terrains():
		var species_arr: Array = []
		for sp: SpeciesData in by_name.values():
			if sp.is_boss:
				continue
			var habitats: Array = sp.habitats
			if habitats.is_empty() or terrain in habitats:
				species_arr.append(sp)
		out[terrain] = species_arr
	return out


## A. 一致性：目标带的威胁系数必须和世界配置对得上（逐斑块核对，
## 斑块威胁按地形展开——BiomeMap.TERRAIN_INFO 与 TERRAIN_BANDS 防漂移）
func _check_consistency() -> void:
	var regions: Array = WorldConfig.region_defs()
	for region: Dictionary in regions:
		var band: Dictionary = CombatBandMath.TERRAIN_BANDS.get(region["terrain"], {})
		if band.is_empty():
			_fail("一致性", "%s 的地形 %s 缺目标带定义" % [region["id"], region["terrain"]])
			continue
		if not is_equal_approx(band["threat"], region["threat"]):
			_fail("一致性", "%s 威胁系数 带%.2f ≠ 世界%.2f" % [
				region["id"], band["threat"], region["threat"]])
	print("  PASS  一致性：目标带威胁 = 世界配置（%d 斑块）" % regions.size())


## B. 地形对刀：参考玩家（预期等级·纯力量裸装）vs 成年中期个体（体型 1.0）
func _check_species(terrain: String, band: Dictionary, species: SpeciesData) -> void:
	var p := CombatBandMath.reference_player(band["expected"])
	var inst := MonsterInstance.new()
	inst.species = species
	inst.age = species.maturity_age + CombatBandMath.REF_AGE_OFFSET
	inst.threat_scale = band["threat"]
	inst.size_scale = 1.0

	var hits: int = CombatBandMath.hits_to_kill(inst, p.physical_attack())
	var attackers := CombatBandMath.attackers_of(species)
	var die_hits: float = CombatBandMath.hits_to_die(inst, p.max_hp(), attackers)
	# 被动生物（美术 v5 完整包动物：只逃不战）承伤带豁免——它们本就不该构成
	# 压力源；击杀带照常（作为猎物须可被顺刀解决）
	if species.ambient:
		die_hits = 999.0
	# 重甲物种（护甲 ≥ 0.3）按专属重甲带校验（终区高压守卫：更长战斗、走位/技能换效率）
	var is_heavy := species.defense_reduction >= CombatBandMath.HEAVY_DEF
	var kill_band: Array = band["kill_heavy"] if is_heavy else band["kill"]
	var die_min: float = CombatBandMath.HEAVY_DIE_FLOOR if is_heavy \
			else (band["die_pack"] if attackers == 3 else band["die_solo"])
	var tag := "%s/%s(L%d)%s" % [terrain, species.species_name, band["expected"],
			"×3" if attackers == 3 else ""]
	if hits >= kill_band[0] and hits <= kill_band[1] and die_hits >= die_min:
		print("  PASS  %-20s 击杀 %2d 刀（带[%d,%d]），被击 %.1f 刀（≥%.1f）" % [
			tag, hits, kill_band[0], kill_band[1], die_hits, die_min])
	else:
		var why := ""
		if hits < kill_band[0] or hits > kill_band[1]:
			why += "击杀刀数 %d 超出带 [%d,%d]" % [hits, kill_band[0], kill_band[1]]
		if die_hits < die_min:
			why += ("；" if why != "" else "") + "被击 %.1f 刀低于下限 %.1f" % [die_hits, die_min]
		_fail(tag, why)


## C. 反推自洽：每地形取首个普通物种作代表——反推区间非空，
## 区间中心的 base_strength 实测击杀刀数必须回到带内（P4 数值生成的可信度证明）。
## 代表优先取非重甲（重甲走 kill_heavy 带，与反推的普通 kill 带口径不符——
## 美术 v5 后 lava 首个物种是石像鬼，重甲代表会把承伤下限顶成空区间）
func _check_derivation(terrain_species: Dictionary) -> void:
	for terrain: String in terrain_species:
		var species_arr: Array = terrain_species[terrain]
		if species_arr.is_empty():
			continue
		var rep: SpeciesData = species_arr[0]
		for candidate: SpeciesData in species_arr:
			if candidate.defense_reduction < CombatBandMath.HEAVY_DEF:
				rep = candidate
				break
		var band: Dictionary = CombatBandMath.TERRAIN_BANDS[terrain]
		var r := CombatBandMath.strength_range(terrain, rep)
		if r.y < r.x:
			_fail("反推", "%s 带内无解：区间 [%.2f, %.2f]（kill 带与承伤下限冲突）" % [
				terrain, r.x, r.y])
			continue
		# 用区间中心重建物种实测
		var tuned := rep.duplicate()
		tuned.base_strength = CombatBandMath.strength_center(terrain, rep)
		var inst := MonsterInstance.new()
		inst.species = tuned
		inst.age = rep.maturity_age + CombatBandMath.REF_AGE_OFFSET
		inst.threat_scale = band["threat"]
		var p := CombatBandMath.reference_player(band["expected"])
		var hits: int = CombatBandMath.hits_to_kill(inst, p.physical_attack())
		var kill_band: Array = band["kill_heavy"] if tuned.defense_reduction >= CombatBandMath.HEAVY_DEF else band["kill"]
		if hits >= kill_band[0] and hits <= kill_band[1]:
			print("  PASS  反推 %s：S∈[%.2f,%.2f] 中心 %.2f → 实测 %d 刀落带" % [
				terrain, r.x, r.y, tuned.base_strength, hits])
		else:
			_fail("反推", "%s 中心反推落带失败：实测 %d 刀 ∉ [%d,%d]" % [
				terrain, hits, kill_band[0], kill_band[1]])


## D. 经济带：掉落量级 / 强化可负担性（pacing_test 动态闸门的静态对应）
func _check_economy(by_name: Dictionary) -> void:
	# 入门经济：西部妖鬼成年单杀 3~10 金（低于 3 无积累感，高于 10 破坏升级节奏）
	var goblin: SpeciesData = by_name.get("妖鬼")
	var inst := MonsterInstance.new()
	inst.species = goblin
	inst.age = goblin.maturity_age + CombatBandMath.REF_AGE_OFFSET
	inst.threat_scale = 1.0
	var west_gold := EconomyMath.kill_gold(inst)
	if west_gold >= 3 and west_gold <= 10:
		print("  PASS  经济：西部单杀 %d 金 ∈ [3,10]" % west_gold)
	else:
		_fail("经济", "西部单杀 %d 金超出 [3,10]" % west_gold)
	# 可负担性：两次强化（tier0+tier1）≤ 25 只入门怪（10 分钟节奏测试击杀 ≥25 的静态版）
	var cost2 := EconomyMath.upgrade_cost(0) + EconomyMath.upgrade_cost(1)
	if cost2 <= 25 * west_gold:
		print("  PASS  经济：两次强化 %d 金 ≤ 25 杀（%d 金）" % [cost2, 25 * west_gold])
	else:
		_fail("经济", "两次强化 %d 金 > 25 杀上限（%d 金）" % [cost2, 25 * west_gold])
	# 定价单调：强化越买越贵
	if EconomyMath.upgrade_cost(0) < EconomyMath.upgrade_cost(1) \
			and EconomyMath.upgrade_cost(1) < EconomyMath.upgrade_cost(2):
		print("  PASS  经济：强化定价单调递增")
	else:
		_fail("经济", "强化定价非单调")
	# Boss 经济闸门：长寿 Boss（年龄=寿命上限）单杀 ≤ 1300 金——
	# 超过全部消费口（商店满配 1950 金）会让击杀一只 Boss 后金币失去意义
	# （EconomyMath.BOSS_GOLD_AGE_CAP 年龄封顶的守门断言）
	var king: SpeciesData = by_name.get("龟王")
	var boss := MonsterInstance.new()
	boss.species = king
	boss.age = king.lifespan_max
	boss.size_scale = king.boss_size_scale
	boss.threat_scale = 3.0
	var boss_gold := EconomyMath.kill_gold(boss)
	if boss_gold <= 1300:
		print("  PASS  经济：长寿 Boss 单杀 %d 金 ≤ 1300（年龄封顶生效）" % boss_gold)
	else:
		_fail("经济", "长寿 Boss 单杀 %d 金 > 1300，年龄封顶失效" % boss_gold)
	# 物品经济（v7）：材料单杀估值带——低于 5 无拾取感、高于 35 会让金币掉落
	# 沦为配角（卷轴 30 是 2.2+ 威胁区专属的高位值，风险收益对齐）
	for species_name: String in EconomyMath.SPECIES_MATERIAL:
		var value := EconomyMath.material_value_per_kill(species_name)
		if value < 5.0 or value > 35.0:
			_fail("经济", "%s 材料单杀估值 %.0f 超出 [5,35]" % [species_name, value])
	print("  PASS  经济：%d 个物种材料单杀估值 ∈ [5,35]" % EconomyMath.SPECIES_MATERIAL.size())
	# 消耗品性价比（基准 5 力量 160 血）：梯度 = 便宜的单位恢复效率高；
	# 带宽 [1.0, 3.5]——下限防"生命药剂纯陷阱"，上限防饭团碾压治疗技能
	var stats := CharacterStats.new()
	var hp := stats.max_hp()
	var prev_eff := INF
	var ok := true
	for id: String in ["onigiri", "sushi", "medipack", "life-pot"]:
		var frac := float(CharacterStats.ITEM_HP_FRAC[id])
		var eff := frac * hp / float(EconomyMath.item_price(id))
		if eff < 1.0 or eff > 3.5 or eff >= prev_eff:
			ok = false
			_fail("经济", "%s 每金恢复 %.2f HP 违反带 [1.0,3.5] 或梯度递减" % [id, eff])
		prev_eff = eff
	if ok:
		print("  PASS  经济：消耗品性价比 ∈ [1.0,3.5] 且越贵单位效率越低")


func _fail(tag: String, why: String) -> void:
	_failures += 1
	print("  FAIL  %-20s %s" % [tag, why])
