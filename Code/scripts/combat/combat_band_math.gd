## 数值目标带与反推公式（v2 数值框架核心，纯静态无状态）。
## 设计流：先定"手感目标带"（每区域 击杀刀数带 / 被击刀数下限），
## 再由反推公式算出物种 base_strength 落点——数值从体验目标反推，而非手调后碰运气。
## 三方共用同一真源：balance_test 断言 / numbers_audit 出表 / P4 新物种数值推导。
class_name CombatBandMath

## 每地形目标带：expected = 预期玩家等级；kill = 击杀刀数带 [lo, hi]；
## kill_heavy = 重甲物种（defense_reduction >= HEAVY_DEF）的击杀带；
## die_solo / die_pack = 被单体/群体(3只)击杀的最低承受刀数。
## v4 起按地形键控（同地形多斑块共享一套手感带）；威胁系数与 BiomeMap.
## TERRAIN_INFO 一致（balance_test 有一致性断言防漂移）。
## 带形设计：越深入的地形 击杀带越高（怪更肉）且承伤下限越低（刀刃更狠）——
## 强度曲线从"挠痒"到"高压"渐进，装备/被动成长是越界的钥匙。
const TERRAIN_BANDS := {
	"plains": {"expected": 1,  "threat": 1.0, "kill": [2, 5],  "kill_heavy": [4, 8],   "die_solo": 6.0, "die_pack": 2.5},
	"forest": {"expected": 3,  "threat": 1.3, "kill": [2, 6],  "kill_heavy": [4, 9],   "die_solo": 5.0, "die_pack": 2.2},
	"snow":   {"expected": 5,  "threat": 1.7, "kill": [3, 7],  "kill_heavy": [5, 10],  "die_solo": 4.5, "die_pack": 2.0},
	"swamp":  {"expected": 5,  "threat": 1.7, "kill": [3, 7],  "kill_heavy": [5, 10],  "die_solo": 4.5, "die_pack": 2.0},
	"hill":   {"expected": 7,  "threat": 2.2, "kill": [4, 9],  "kill_heavy": [6, 13],  "die_solo": 4.0, "die_pack": 1.8},
	"lava":   {"expected": 10, "threat": 3.0, "kill": [5, 12], "kill_heavy": [10, 26], "die_solo": 3.5, "die_pack": 1.8},
}

## 重甲判定线：护甲达到此值的物种按 kill_heavy 带校验（终区高压守卫的专属手感）
const HEAVY_DEF := 0.3
## 重甲物种承伤下限（全局统一）：大前摇重击可冲刺闪避——压力来自持久战而非爆发，
## 承伤下限放宽到 3.0（普通物种按区域带 3.5~6.0）
const HEAVY_DIE_FLOOR := 3.0
## 群体攻击原型（按 3 只同时在场估算承伤压力）
const PACK_ARCHETYPE := "melee_swarm"
## 对刀基准：成年中期个体（age = maturity + REF_AGE_OFFSET tick）
const REF_AGE_OFFSET := 90


## 参考玩家（对刀基准）：纯力量加点、裸装、无被动——升级收益全喂战斗轴
static func reference_player(level: int) -> CharacterStats:
	var s := CharacterStats.new()
	s.level = level
	s.strength = 5 + (level - 1)
	return s


## 群体估算只数：melee_swarm 原型按 3 只围攻，其余单体
static func attackers_of(species: SpeciesData) -> int:
	return 3 if species.ai_archetype == PACK_ARCHETYPE else 1


## 击杀刀数：护甲折算进有效生命（ceil 语义 = 刀刀命中恰好击杀）
static func hits_to_kill(inst: MonsterInstance, player_attack: float) -> int:
	var eff_hp: float = inst.max_hp() / (1.0 - clampf(inst.species.defense_reduction, 0.0, 0.8))
	return ceili(eff_hp / player_attack)


## 被击刀数：玩家生命能扛住几刀（群体按同帧围攻只数放大压力）
static func hits_to_die(inst: MonsterInstance, player_hp: float, attackers: int) -> float:
	return player_hp / (inst.attack_power() * attackers)


## 反推：在该目标带内落地所需的 base_strength 区间 [lo, hi]（hi < lo = 带内无解，
## 说明 kill 带与 die 下限冲突或玩家参考变了，设计侧信号）。
## 只反推 base_strength；攻防手感分家交给 defense_reduction / offense_scale 微调。
static func strength_range(terrain: String, species: SpeciesData, age := -1) -> Vector2:
	# 非法地形名直接取键会让返回的 null 在后续 band["expected] 处崩溃——
	# 显式守卫 + 空区间（strength_center 的 maxf(0.5,·) 会收敛到 0.5 下限）
	var band: Dictionary = TERRAIN_BANDS.get(terrain, {})
	if band.is_empty():
		push_warning("CombatBandMath：未知地形 %s（应来自 BiomeMap.TERRAIN_INFO 的键）" % terrain)
		return Vector2(0.0, -1.0)
	var player := reference_player(band["expected"])
	var a_age: int = species.maturity_age + REF_AGE_OFFSET if age < 0 else age
	var threat: float = band["threat"]
	var size := 1.0
	var def: float = clampf(species.defense_reduction, 0.0, 0.8)
	# hits(S) = A·S + B（击杀刀数对力量线性）
	var pa: float = player.physical_attack()
	var a: float = 5.0 * size * threat / ((1.0 - def) * pa)
	var b: float = (20.0 + species.strength_growth * a_age * 5.0) * size * threat / ((1.0 - def) * pa)
	var s_lo: float = (band["kill"][0] - b) / a
	var s_hi: float = (band["kill"][1] - b) / a
	# 被击下限 → 力量上限（怪越强玩家越快死）；重甲物种走全局放宽下限
	var attackers := attackers_of(species)
	var is_heavy := species.defense_reduction >= HEAVY_DEF
	var die_min: float = HEAVY_DIE_FLOOR if is_heavy \
			else band["die_pack" if attackers == 3 else "die_solo"]
	var atk_cap: float = player.max_hp() / (die_min \
			* size * threat * species.offense_scale * attackers)
	var s_cap: float = (atk_cap - 3.0) / 0.8 - species.strength_growth * a_age
	return Vector2(maxf(s_lo, 0.5), minf(s_hi, s_cap))


## 反推落地：取带内区间中心作为 base_strength（P4 新物种数值的生成入口）
static func strength_center(terrain: String, species: SpeciesData, age := -1) -> float:
	return maxf(0.5, (strength_range(terrain, species, age).x + strength_range(terrain, species, age).y) * 0.5)
