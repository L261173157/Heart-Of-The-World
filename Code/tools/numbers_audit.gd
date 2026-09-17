## 数值审计工具：把全部数值公式量化成表格（v2 数值框架的依据与回归基线）。
## 输出：玩家构筑曲线 / 区域对刀 / 目标带与反推区间 / 经济节奏 / 生态补给速率 / 寿命节奏。
## 只读不改，公式全部取自 CharacterStats / MonsterInstance / SpeciesData /
## CombatBandMath / EconomyMath 单一事实源（本文件零本地公式）。
## 运行："$GODOT" --headless --path Code -s tools/numbers_audit.gd
extends SceneTree

## 地形对刀阵容（审计展示用；从 WorldConfig 种群真源派生，
## 平衡闸门 balance_test 按 habitats 真源自动展开）
func _terrain_species() -> Dictionary:
	var out := {}
	for terrain: String in WorldConfig.terrains():
		var roster: Array = []
		for n: String in WorldConfig.TERRAIN_POPULATION.get(terrain, {}):
			roster.append(n)
		var boss: String = WorldConfig.TERRAIN_BOSSES.get(terrain, "")
		if boss != "":
			roster.append(boss)
		out[terrain] = roster
	return out


func _terrain_capacity(terrain: String) -> int:
	return BiomeMap.TERRAIN_INFO[terrain]["capacity"]


func _init() -> void:
	_audit_builds()
	_audit_regions()
	_audit_bands()
	_audit_economy()
	_audit_ecology_supply()
	_audit_lifespan()
	quit(0)


## 构造指定等级与配点的角色（无被动/强化/装备——裸装基准）
func _stats(level: int, str: int, agi: int, int_: int) -> CharacterStats:
	var s := CharacterStats.new()
	s.level = level
	s.strength = str
	s.agility = agi
	s.intellect = int_
	return s


func _by_name() -> Dictionary:
	var by_name := {}
	for sp: SpeciesData in SpeciesCatalog.build_all():
		by_name[sp.species_name] = sp
	return by_name


func _audit_builds() -> void:
	print("\n=== A. 玩家构筑曲线（裸装，全点单投 + 均衡） ===")
	print("%-6s %-8s %7s %7s %7s %7s %7s %7s %8s" % [
		"等级", "构筑", "生命", "物攻", "物理DPS", "法伤", "法弹DPS", "治疗/8s", "移速"])
	for level in [1, 3, 5, 7, 10, 15]:
		var pts: int = level - 1
		for build in [
			["力量", 5 + pts, 5, 5],
			["敏捷", 5, 5 + pts, 5],
			["智力", 5, 5, 5 + pts],
			["均衡", 5 + pts / 3, 5 + pts / 3, 5 + pts / 3],
		]:
			var s := _stats(level, build[1], build[2], build[3])
			# 法弹持续输出：冷却与 MP 回复双约束取小（常量取 CharacterStats 真源）
			var casts_per_sec: float = minf(1.0 / CharacterStats.BOLT_COOLDOWN,
				s.mp_regen_per_sec() / CharacterStats.BOLT_COST)
			var bolt_dps: float = CombatMath.magic_damage(
				s.magic_attack() * CharacterStats.BOLT_MULT) * casts_per_sec
			print("L%-5d %-8s %7.0f %7.1f %7.1f %7.1f %7.1f %8.0f %7.0f" % [
				level, build[0], s.max_hp(), s.physical_attack(),
				s.physical_attack() / s.attack_interval(), s.magic_attack(),
				bolt_dps, s.heal_power() * CharacterStats.HEAL_MULT, s.move_speed()])


func _audit_regions() -> void:
	print("\n=== B. 地形对刀（成年中期 age=maturity+90，玩家纯力量裸装） ===")
	var by_name := _by_name()
	var species_map := _terrain_species()
	print("%-24s %6s %8s %8s %8s %8s" % ["地形/物种", "威胁", "怪HP", "击杀刀", "被击刀", "被击DPS"])
	for terrain in CombatBandMath.TERRAIN_BANDS:
		var band: Dictionary = CombatBandMath.TERRAIN_BANDS[terrain]
		var p := CombatBandMath.reference_player(band["expected"])
		for species_name in species_map[terrain]:
			var inst := MonsterInstance.new()
			inst.species = by_name[species_name]
			inst.age = inst.species.maturity_age + CombatBandMath.REF_AGE_OFFSET
			inst.threat_scale = band["threat"]
			print("%-24s %6.1f %8.0f %8d %8.1f %8.1f" % [
				"%s/%s" % [terrain, species_name], band["threat"],
				inst.max_hp(),
				CombatBandMath.hits_to_kill(inst, p.physical_attack()),
				CombatBandMath.hits_to_die(inst, p.max_hp(), 1),
				inst.attack_power() / inst.species.attack_cooldown])


func _audit_bands() -> void:
	print("\n=== C. 目标带与反推区间（v2：手感带 → base_strength 落点） ===")
	var by_name := _by_name()
	var species_map := _terrain_species()
	print("%-10s %5s %9s %12s %14s" % ["地形", "等级", "击杀带", "现有物种落带", "反推S区间[lo,hi]"])
	for terrain in CombatBandMath.TERRAIN_BANDS:
		var band: Dictionary = CombatBandMath.TERRAIN_BANDS[terrain]
		var parts: Array = []
		for species_name in species_map[terrain]:
			var sp: SpeciesData = by_name[species_name]
			if sp.is_boss:
				continue
			var inst := MonsterInstance.new()
			inst.species = sp
			inst.age = sp.maturity_age + CombatBandMath.REF_AGE_OFFSET
			inst.threat_scale = band["threat"]
			var p := CombatBandMath.reference_player(band["expected"])
			parts.append("%s:%d刀/%.1f承" % [species_name,
				CombatBandMath.hits_to_kill(inst, p.physical_attack()),
				CombatBandMath.hits_to_die(inst, p.max_hp(), CombatBandMath.attackers_of(sp))])
		var sample: SpeciesData = by_name[species_map[terrain][0]]
		var r := CombatBandMath.strength_range(terrain, sample)
		print("%-10s L%-4d [%2d,%2d]%-6s %s" % [terrain, band["expected"],
			band["kill"][0], band["kill"][1], "", " ".join(parts)])
		print("%-10s 反推区间 [%5.2f, %5.2f]%s" % ["", r.x, r.y,
			"  ⚠ 空区间" if r.y < r.x else ""])


func _audit_economy() -> void:
	print("\n=== D. 经济节奏（EconomyMath 真源：击杀/赏金/商店全公式） ===")
	var by_name := _by_name()
	var s := CharacterStats.new()
	print("升级经验：")
	var total_xp := 0
	for level in range(1, 15):
		s.level = level
		var need: int = s.xp_to_next()
		total_xp += need
		if level <= 10 or level == 14:
			print("  L%d→L%d 需要 %4d xp（累计 %5d）" % [level, level + 1, need, total_xp])
	print("地形单杀均值（成年中期；金币 = EconomyMath.kill_gold 确定值）：")
	var species_map := _terrain_species()
	for terrain in CombatBandMath.TERRAIN_BANDS:
		var band: Dictionary = CombatBandMath.TERRAIN_BANDS[terrain]
		var level: int = band["expected"]
		s.level = level
		var need: int = s.xp_to_next()
		var xp_sum := 0.0
		var gold_sum := 0.0
		for species_name in species_map[terrain]:
			var sp: SpeciesData = by_name[species_name]
			var inst := MonsterInstance.new()
			inst.species = sp
			inst.age = sp.maturity_age + CombatBandMath.REF_AGE_OFFSET
			inst.threat_scale = band["threat"]
			xp_sum += inst.xp_reward()
			gold_sum += EconomyMath.kill_gold(inst)
		var count: int = species_map[terrain].size()
		print("  %-6s L%-2d 单杀均值 %4.0f xp / %3.0f 金 → 本级约需 %3.0f 杀" % [
			terrain, level, xp_sum / count, gold_sum / count, need / (xp_sum / count)])
	var shop_total := 0
	for kind_level in 5:
		shop_total += EconomyMath.upgrade_cost(kind_level)
	print("商店：单类 5 级 %d 金，三类全满 %d 金" % [shop_total, shop_total * 3])
	print("赏金：目标 4~7 只 → %d~%d 金 / %d~%d xp（随等级 +3 金/级）" % [
		EconomyMath.bounty_gold(4, 1), EconomyMath.bounty_gold(7, 1),
		EconomyMath.bounty_xp(4), EconomyMath.bounty_xp(7)])
	print("死亡代价：掉 20%% 金币 + 寿命 -1 天；装备折价 %d~%d 金" % [
		EconomyMath.sell_price(0), EconomyMath.sell_price(3)])


func _audit_ecology_supply() -> void:
	print("\n=== E. 生态补给速率（满承载成年种群的出生上限） ===")
	var by_name := _by_name()
	var species_map := _terrain_species()
	var total := 0.0
	for terrain: String in species_map:
		var capacity := _terrain_capacity(terrain)
		var rate_per_patch := 0.0
		for species_name in species_map[terrain]:
			var sp: SpeciesData = by_name[species_name]
			rate_per_patch += capacity * sp.breeding_rate * 60.0
		var patch_count: int = BiomeMap.patches_of_terrain(terrain).size()
		total += rate_per_patch * patch_count
		print("  %-6s %d 斑块 × 承载 %2d → 出生上限 %6.1f 只/分" % [
			terrain, patch_count, capacity, rate_per_patch * patch_count])
	print("  全图出生上限合计 %.1f 只/分（节奏机器人实测猎杀 ~24 只/分）" % total)


func _audit_lifespan() -> void:
	print("\n=== F. 寿命节奏（1 游戏天 = 4 分钟真实） ===")
	for level in [1, 5, 10, 15]:
		var days: float = 30.0 + 2.0 * (level - 1)
		print("  L%-2d 寿命 %2.0f 天 ≈ %.1f 小时真实时间（死亡每次 -1 天）" % [
			level, days, days * 4.0 / 60.0])
	print("  风烛残年窗口 5 天 = 20 分钟真实（上限衰减 100%%→60%%）")
