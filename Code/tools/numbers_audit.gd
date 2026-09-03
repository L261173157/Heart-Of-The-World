## 数值审计工具：把全部数值公式量化成表格（M1 数值统一设计的依据与回归基线）。
## 输出：玩家构筑曲线 / 区域对刀 / 经济节奏 / 生态补给速率 / 寿命节奏。
## 只读不改，公式全部取自 CharacterStats / MonsterInstance / SpeciesData 单一事实源。
## 运行："$GODOT" --headless --path Code -s tools/numbers_audit.gd
extends SceneTree

const REGION_LEVEL := {"west": 1, "center": 3, "snow": 5, "swamp": 5, "east": 7, "lava": 10}
const REGION_THREAT := {"west": 1.0, "center": 1.3, "snow": 1.7, "swamp": 1.7, "east": 2.2, "lava": 3.0}
const REGION_SPECIES := {
	"west": ["哥布林"], "center": ["哥布林", "史莱姆"],
	"snow": ["野猪", "雪蝎", "冰晶史莱姆"], "swamp": ["史莱姆", "雪蝎"],
	"east": ["兵蚁", "野猪", "蚁后"], "lava": ["兵蚁", "岩甲龟", "龟王"],
}
const REGION_CAPACITY := {"west": 10, "center": 12, "snow": 10, "swamp": 10, "east": 12, "lava": 8}

## 法弹：MP 8 / 冷却 0.8s / 倍率 2.0（与 player.gd 常量一致；改动时同步）
const BOLT_COST := 8.0
const BOLT_CD := 0.8
const BOLT_MULT := 2.0
const HEAL_COST := 25.0
const HEAL_CD := 8.0
const HEAL_MULT := 3.0


func _init() -> void:
	_audit_builds()
	_audit_regions()
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
			# 法弹持续输出：冷却与 MP 回复双约束取小
			var casts_per_sec: float = minf(1.0 / BOLT_CD, s.mp_regen_per_sec() / BOLT_COST)
			var bolt_dps: float = CombatMath.magic_damage(s.magic_attack() * BOLT_MULT) * casts_per_sec
			print("L%-5d %-8s %7.0f %7.1f %7.1f %7.1f %7.1f %8.0f %7.0f" % [
				level, build[0], s.max_hp(), s.physical_attack(),
				s.physical_attack() / s.attack_interval(), s.magic_attack(),
				bolt_dps, s.heal_power() * HEAL_MULT, s.move_speed()])


func _audit_regions() -> void:
	print("\n=== B. 区域对刀（成年中期 age=maturity+90，玩家纯力量裸装） ===")
	var by_name := {}
	for sp: SpeciesData in SpeciesCatalog.build_all():
		by_name[sp.species_name] = sp
	print("%-24s %6s %8s %8s %8s %8s" % ["区域/物种", "威胁", "怪HP", "击杀刀", "被击刀", "被击DPS"])
	for region_id in REGION_LEVEL:
		var level: int = REGION_LEVEL[region_id]
		var strength: int = 5 + (level - 1)
		var p := _stats(level, strength, 5, 5)
		for species_name in REGION_SPECIES[region_id]:
			var inst := MonsterInstance.new()
			inst.species = by_name[species_name]
			inst.age = inst.species.maturity_age + 90
			inst.threat_scale = REGION_THREAT[region_id]
			var eff_hp: float = inst.max_hp() / (1.0 - clampf(inst.species.defense_reduction, 0.0, 0.8))
			var hits: int = ceili(eff_hp / p.physical_attack())
			var hits_die: float = p.max_hp() / inst.attack_power()
			print("%-24s %6.1f %8.0f %8d %8.1f %8.1f" % [
				"%s/%s" % [region_id, species_name], REGION_THREAT[region_id],
				inst.max_hp(), hits, hits_die, inst.attack_power() / inst.species.attack_cooldown])


func _audit_economy() -> void:
	print("\n=== C. 经济节奏 ===")
	var by_name := {}
	for sp: SpeciesData in SpeciesCatalog.build_all():
		by_name[sp.species_name] = sp
	print("升级经验：")
	var total_xp := 0
	for level in range(1, 15):
		var need := int(60.0 * pow(float(level), 1.55))
		total_xp += need
		if level <= 10 or level == 14:
			print("  L%d→L%d 需要 %4d xp（累计 %5d）" % [level, level + 1, need, total_xp])
	print("区域单杀均值（成年中期）与每级所需击杀数：")
	for region_id in REGION_LEVEL:
		var level: int = REGION_LEVEL[region_id]
		var need := int(60.0 * pow(float(level), 1.55))
		var xp_sum := 0.0
		var gold_sum := 0.0
		for species_name in REGION_SPECIES[region_id]:
			var sp: SpeciesData = by_name[species_name]
			var inst := MonsterInstance.new()
			inst.species = sp
			inst.age = sp.maturity_age + 90
			inst.threat_scale = REGION_THREAT[region_id]
			xp_sum += inst.xp_reward()
			gold_sum += 5.5 * REGION_THREAT[region_id] * (8.0 if sp.is_boss else 1.0)
		var count: int = REGION_SPECIES[region_id].size()
		print("  %-6s L%-2d 单杀均值 %4.0f xp / %3.0f 金 → 本级约需 %3.0f 杀" % [
			region_id, level, xp_sum / count, gold_sum / count, need / (xp_sum / count)])
	print("商店：三类×5 级全满 %d 金（每类 650）" % (3 * 650))
	print("死亡代价：掉 20%% 金币 + 寿命 -1 天；装备折价 20~50 金")


func _audit_ecology_supply() -> void:
	print("\n=== D. 生态补给速率（满承载成年种群的出生上限） ===")
	var by_name := {}
	for sp: SpeciesData in SpeciesCatalog.build_all():
		by_name[sp.species_name] = sp
	var total := 0.0
	for region_id in REGION_SPECIES:
		var region_rate := 0.0
		for species_name in REGION_SPECIES[region_id]:
			var sp: SpeciesData = by_name[species_name]
			region_rate += REGION_CAPACITY[region_id] * sp.breeding_rate * 60.0
		total += region_rate
		print("  %-6s 承载 %2d → 出生上限 %5.1f 只/分" % [region_id, REGION_CAPACITY[region_id], region_rate])
	print("  全图出生上限合计 %.1f 只/分（节奏机器人实测猎杀 ~24 只/分）" % total)


func _audit_lifespan() -> void:
	print("\n=== E. 寿命节奏（1 游戏天 = 4 分钟真实） ===")
	for level in [1, 5, 10, 15]:
		var days: float = 30.0 + 2.0 * (level - 1)
		print("  L%-2d 寿命 %2.0f 天 ≈ %.1f 小时真实时间（死亡每次 -1 天）" % [
			level, days, days * 4.0 / 60.0])
	print("  风烛残年窗口 5 天 = 20 分钟真实（上限衰减 100%%→60%%）")
