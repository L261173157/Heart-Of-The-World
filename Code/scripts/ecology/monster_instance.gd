## 怪物个体（纯数据，RefCounted）。
## 只存模拟状态：年龄/寿命/所属区域/世代；节点的位置、血量等表现状态不在这里。
## 架构铁律：禁止持有 Node 引用，禁止调用场景树 API。
class_name MonsterInstance
extends RefCounted

var id: int = 0
var species: SpeciesData
var region_id: String = ""

var age: int = 0
var lifespan: int = 0
var is_alive: bool = true
## 死亡后尸体剩余 tick，corpse_ticks < 0 表示尚未死亡
var corpse_ticks: int = -1

## 分裂世代（0 为原生代；赤炎小魔子代逐代缩小且逐代不育）
var generation: int = 0
## 体型系数（分裂子代 < 1），线性缩放生命/攻击/经验与表现层视觉
var size_scale: float = 1.0
## 精英个体（繁衍时的罕见变异）：体型/生命/攻击/经验再乘放大系数，
## 表现层给金色 tint 与更高击杀奖励——让"种群在演化"从数字变成看得见的遭遇
var is_elite: bool = false
## 区域威胁系数（由 EcologySim 在出生/迁入时写入），越深的地域越强
var threat_scale: float = 1.0
## 出生位置提示（Vector2.INF = 未指定，表现层在区域锚点附近随机落点）；
## 分裂子代会继承母体死亡位置，"在尸体处裂开"
var spawn_pos: Vector2 = Vector2.INF
## 死亡位置（report_killed 时由表现层回填，供分裂子代继承）
var death_pos: Vector2 = Vector2.INF
## 当前血量镜像（表现层受击/成长时经 report_hp 回写；-1 = 从未同步，等同满血）。
## 只为存档往返存在：读档恢复的怪带伤开局，不再"白送满血回复"；模拟逻辑不读它，
## 运行期真实血量仍以 MonsterBase.current_hp 为准
var hp_mirror: float = -1.0


## Boss 的长寿用于生态占位，不能把几十分钟存活直接换成数倍攻击/移速。
## 前 200 tick 保留现有幼年/初生强度；此后 20 分钟只增加 100 个战斗成长 tick，
## 再封顶。独立于 maturity_age / lifespan：不改成年、自然死亡、重生或存档年龄。
## 普通怪仍使用原始线性成长；三项能力共用此曲线，避免只压伤害却留下追击失控。
const BOSS_COMBAT_BASE_AGE := 200.0
const BOSS_COMBAT_GROWTH_WINDOW := 1200.0
const BOSS_COMBAT_EXTRA_AGE := 100.0


func combat_age() -> float:
	if not species.is_boss:
		return float(age)
	var young_age := minf(float(age), BOSS_COMBAT_BASE_AGE)
	var later_growth := clampf((age - BOSS_COMBAT_BASE_AGE) / BOSS_COMBAT_GROWTH_WINDOW, 0.0, 1.0)
	return young_age + later_growth * BOSS_COMBAT_EXTRA_AGE


func strength() -> float:
	return species.base_strength + species.strength_growth * combat_age()


func agility() -> float:
	return species.base_agility + species.agility_growth * combat_age()


func intellect() -> float:
	return species.base_intellect + species.intellect_growth * combat_age()


func max_hp() -> float:
	return (20.0 + strength() * 5.0) * size_scale * threat_scale


func attack_power() -> float:
	return (3.0 + strength() * 0.8) * size_scale * threat_scale * species.offense_scale


func move_speed() -> float:
	return 40.0 + agility() * 12.0


func is_adult() -> bool:
	return age >= species.maturity_age


## 分裂子代不育（"逐代缩小且逐代不育"的设计契约）：只有原生代参与繁衍。
## 原生代 = 种群核心；分裂子代 = 玩家猎杀制造的临时压力种群——"越杀越多"
## 有自然上限（子代老化死亡清零），不能经繁衍把世代与体型洗白回原生代
func is_split_sterile() -> bool:
	return species.splits_on_death and generation > 0


func can_split() -> bool:
	return species.splits_on_death and generation < species.max_generation


func xp_reward() -> int:
	return int((species.xp_base + species.xp_per_age * age) * size_scale * threat_scale)


func display_name() -> String:
	if is_elite:
		return "精英·%s#%d" % [species.species_name, id]
	return "%s#%d" % [species.species_name, id]
