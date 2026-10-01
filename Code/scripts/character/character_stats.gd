## 角色养成数据（纯数据，Resource）。
## 对应《策划纲要》角色系统：
##   能力值 = 力量/敏捷/智力，等级由经验决定，每级 1 点自由分配；
##   力量→生命上限/生命回复/物理攻击，敏捷→移动速度/攻击速度，
##   智力→魔法上限/魔法回复/魔法攻击/治疗力。
## 寿命：年龄随游戏天数推进（升级延长/倒下缩短），寿命将尽时属性渐进衰老（LifespanMath）；
## 到点永久死亡（鬼魂玩法）后置在待定池。
## 所有衍生数值用方法即时计算，属性点分配立刻生效。
class_name CharacterStats
extends Resource

## changed 信号直接用 Resource 原生的（数据变更通知）
## levels_gained：本次经验跨了几级——升级赐福按次数发放，大额经验（首杀 Boss）
## 一次连升 N 级时漏发 N-1 次将无法事后补领（被动是叠乘成长）
signal leveled_up(new_level: int, levels_gained: int)

var level: int = 1
var xp: int = 0
var pending_points: int = 0
## 升级赐福属于角色进度，不能由随场景销毁的 HUD 持有。
## 当前三张卡一起入档；offer_id 拒绝旧按钮/重复回调再次领取。
var pending_passive_picks: int = 0
var passive_choices: Array[String] = []
var passive_offer_id: int = 0

var strength: int = 5
var agility: int = 5
var intellect: int = 5

## 游商营地永久强化等级（weapon/staff/vigor，GameState 购买与持久化，公式集中在此）
var upgrade_weapon: int = 0
var upgrade_staff: int = 0
var upgrade_vigor: int = 0

## --- 技能常量（v2 真源）：五技能 + 冲刺/连击的 费用/冷却/倍率/持续 ---
## player.gd（`Skill` 别名）、HUD 技能栏、combat_test / numbers_audit 全部从此引用；
## 改技能数值只动这里，测试与文档自动跟进（公式进闸）。

## 三段连击：窗口内连续普攻，第三段重击（高伤重击退）；超时重置
const COMBO_HEAVY_MULT := 1.5

## 连击维持窗口：随攻速自适应——窗口若贴着攻击间隔上限（曾为 0.9 == 0.9），
## 慢攻速构筑的续段余量只剩 0.05s，三段重击形同虚设；快攻构筑维持 0.9 不变
func combo_window() -> float:
	return maxf(0.9, attack_interval() + 0.35)
## 冲刺增伤窗口：冲刺取消攻击后摇后，下次普攻加成（高级技巧空间）
const DASH_BUFF_TIME := 1.0
const DASH_BUFF_MULT := 1.3
const DASH_COST := 12.0
const DASH_COOLDOWN := 1.2
## 重击：以自身为圆心的 AOE 挥砸（清火把哥布林/骷髅兵人海的保命大招）
const HEAVY_COST := 22.0
const HEAVY_COOLDOWN := 4.0
const HEAVY_RADIUS := 80.0
const HEAVY_MULT := 2.4
## 法弹：智力系远程（与沼泽蛛对射 / 风筝走位的构筑选择）。
## 倍率 2.0（2026-09-03 数值统一设计）：智力构筑 = 大 MP 池短窗爆发（~19s 倾泻）
## + 射程安全 + 强治疗，持续期回落到近战五成——定位爆发法术而非站桩替代
const BOLT_COST := 8.0
const BOLT_COOLDOWN := 0.8
const BOLT_MULT := 2.0
## 治疗：MP→HP 的资源博弈（MP 同时供冲刺/重击/法弹/治疗，取舍即深度）
const HEAL_COST := 25.0
const HEAL_COOLDOWN := 8.0
const HEAL_MULT := 3.0
## 武装强化：普攻增益状态（近战持续流构筑——贴身连击回血，
## 与重击的瞬间爆发、法弹的远程风筝形成三种输出节奏的分野）
const EMPOWER_COST := 30.0
const EMPOWER_COOLDOWN := 15.0
const EMPOWER_DURATION := 6.0
const EMPOWER_MULT := 1.6
## 每次普攻命中回复最大生命的比例（连击节奏越快收益越高）
const EMPOWER_HEAL_FRAC := 0.03

## --- 消耗品（玩法 v7 物品系统）：恢复比例真源，数值只动这里 ---
## 按最大生命/精力的比例恢复（不吃 heal_power——食物药品与技能治疗是两条线，
## 词条/被动不放大补给收益，性价比带稳定可守闸）；ItemCatalog.desc_of 动态拼接
const ITEM_HP_FRAC := {"onigiri": 0.35, "sushi": 0.5, "medipack": 0.8, "life-pot": 1.0}
const ITEM_MP_FRAC := {"water-pot": 0.5}


## 每级强化幅度（+15%）
const UPGRADE_BONUS := 0.15

## --- 三选一被动（升级时抽卡，等级叠乘，构筑多样性的主力轴） ---
## id -> 已获等级
var passives: Dictionary = {}

const PASSIVE_POOL := [
	{"id": "lifesteal", "name": "噬血", "desc": "普攻命中回复生命"},
	{"id": "atk_speed", "name": "迅捷", "desc": "攻击间隔 -10%"},
	{"id": "move", "name": "疾风", "desc": "移动速度 +10%"},
	{"id": "cdr", "name": "洞悉", "desc": "技能冷却 -8%"},
	{"id": "hp", "name": "坚韧", "desc": "生命上限 +20"},
	{"id": "mp_regen", "name": "冥想", "desc": "魔法回复 +25%"},
	{"id": "phys", "name": "蛮力", "desc": "物理攻击 +10%"},
	{"id": "magic", "name": "奥能", "desc": "魔法攻击 +10%"},
	{"id": "gold", "name": "贪婪", "desc": "金币获取 +15%"},
	{"id": "xp", "name": "好学", "desc": "经验获取 +10%"},
	{"id": "heal_power", "name": "圣光", "desc": "治疗量 +30%"},
	{"id": "knock", "name": "重锤", "desc": "击退 +30%"},
]


func passive_level(id: String) -> int:
	return int(passives.get(id, 0))


func add_passive(id: String) -> void:
	passives[id] = passive_level(id) + 1
	changed.emit()


## 当前可选卡只生成一次：暂停/回菜单/冷启动均沿用，不得读档重抽。
func ensure_passive_choices() -> void:
	if pending_passive_picks <= 0:
		passive_choices.clear()
		return
	if not passive_choices.is_empty():
		return
	var pool: Array[String] = []
	for entry: Dictionary in PASSIVE_POOL:
		pool.append(entry["id"])
	pool.shuffle()
	passive_choices.assign(pool.slice(0, mini(3, pool.size())))
	passive_offer_id += 1


## 先完成「消耗一次资格 + 发放被动 + 下一组卡」，再通知观察者。
## changed 的订阅者即使同步保存，也只能看见完整事务，不会漏奖/重复发奖。
func claim_passive(id: String, offer_id: int) -> bool:
	if pending_passive_picks <= 0 or offer_id != passive_offer_id or not passive_choices.has(id):
		return false
	pending_passive_picks -= 1
	passives[id] = passive_level(id) + 1
	passive_choices.clear()
	ensure_passive_choices()
	changed.emit()
	return true


func passive_mult(id: String, per_level: float) -> float:
	return pow(per_level, passive_level(id))


## --- 装备（四槽位：武器/头盔/衣服/鞋子，各自单件替换制） ---
## equips: {槽位id: {"name", "rarity"(0~3), "element"(仅武器), "affixes": {词条id: 比例值}}}
var equips: Dictionary = {}


## 词条值 = 全槽位求和（掉落比较与衍生属性都从这取）
func equip_affix(id: String) -> float:
	var total := 0.0
	for slot in equips:
		total += float(equips[slot].get("affixes", {}).get(id, 0.0))
	return total


## 元素附魔只有武器槽会出（战斗侧消费单一来源）
func equip_element() -> String:
	return str(equips.get("weapon", {}).get("element", ""))


## 装备评分：各词条值直接求和（同量纲近似，用于掉落比较）
func equip_score(item: Dictionary) -> float:
	var total := 0.0
	for key in item.get("affixes", {}):
		total += absf(float(item["affixes"][key]))
	if str(item.get("element", "")) != "":
		total += 0.05
	return total

## --- 寿命（角色侧单位：游戏天，WorldSim 4 分钟/天；怪物侧为 tick） ---
## 策划：寿命随自然时间减少、能力提升延长、倒下缩短；到点永久死亡（鬼魂玩法）后置，
## 当前到点表现为"风烛残年"——生命/精力上限渐进衰减（见 LifespanMath）
const BASE_LIFESPAN_DAYS := 30.0
const LEVELED_LIFESPAN_GAIN := 2.0
const DEATH_LIFESPAN_LOSS := 1.0

var age_days: float = 0.0
var lifespan_days: float = BASE_LIFESPAN_DAYS


## 就地重置全部养成字段（reset_all 用）：保持对象身份不变，
## 订阅者（Player/HUD/SfxManager/AchievementManager）持有的引用全部继续有效
func reset() -> void:
	level = 1
	xp = 0
	pending_points = 0
	pending_passive_picks = 0
	passive_choices.clear()
	passive_offer_id = 0
	strength = 5
	agility = 5
	intellect = 5
	upgrade_weapon = 0
	upgrade_staff = 0
	upgrade_vigor = 0
	passives = {}
	equips = {}
	age_days = 0.0
	lifespan_days = BASE_LIFESPAN_DAYS
	changed.emit()


func lifespan_remaining() -> float:
	return LifespanMath.remaining(age_days, lifespan_days)


## 风烛残年乘子（寿命充裕 = 1.0），仅作用于生命/精力上限
func aging_decay() -> float:
	return LifespanMath.decay_mult(age_days, lifespan_days)


## 升级所需经验：首级低门槛（十余杀即首升的即时正反馈），后期增陡
## （pacing_test 数据校准：真人速率 10min 约 Lv3~Lv4）
func xp_to_next() -> int:
	return int(60.0 * pow(float(level), 1.55))


func add_xp(amount: int) -> void:
	xp += int(amount * passive_mult("xp", 1.1) * (1.0 + equip_affix("xp")))
	var levels_gained := 0
	while xp >= xp_to_next():
		xp -= xp_to_next()
		level += 1
		pending_points += 1
		# 升级延长寿命（策划：能力提升延长寿命）
		lifespan_days += LEVELED_LIFESPAN_GAIN
		levels_gained += 1
	if levels_gained > 0:
		# 发信号前兑现全部跨级资格：UI 不在树内、或订阅者同步保存也不会漏发。
		pending_passive_picks += levels_gained
		ensure_passive_choices()
		leveled_up.emit(level, levels_gained)
	changed.emit()


# --- 衍生属性（v0 占位公式，M1 数值策划后统一调整） ---

func max_hp() -> float:
	return (100.0 + strength * 12.0 + passive_level("hp") * 20.0) \
			* (1.0 + upgrade_vigor * UPGRADE_BONUS) * (1.0 + equip_affix("hp")) * aging_decay()


func hp_regen_per_sec() -> float:
	return 1.0 + strength * 0.1


func max_mp() -> float:
	return (50.0 + intellect * 10.0) * aging_decay()


func mp_regen_per_sec() -> float:
	# 0.14/点（2026-09-03 数值统一设计）：智力可支撑 ~0.4 发/s 法弹持续输出，
	# 同时全构筑技能手感 +27%（MP 是冲刺/重击/法弹/治疗/强化的共享资源）
	return (1.2 + intellect * 0.14) * passive_mult("mp_regen", 1.25)


func physical_attack() -> float:
	return (10.0 + strength * 2.5) * (1.0 + upgrade_weapon * UPGRADE_BONUS) \
			* passive_mult("phys", 1.1) * (1.0 + equip_affix("atk"))


func magic_attack() -> float:
	return (8.0 + intellect * 2.0) * (1.0 + upgrade_staff * UPGRADE_BONUS) \
			* passive_mult("magic", 1.1)


func heal_power() -> float:
	return intellect * 2.0 * passive_mult("heal_power", 1.3)


## 移速基准 2026-09-08 下调（230→175）：角色仅 ~38px 高，230px/s ≈ 每秒 6 身位，
## iOS 真机手感呈"滑冰"；175 仍高于追击最快的蚂蚁(124)、慢于突袭蛇冲锋(~291)，
## 追逐/被追逐结构不变。手机屏小、视角缩放后感知更明显，以真机反馈为准。
func move_speed() -> float:
	return (150.0 + agility * 5.0) * passive_mult("move", 1.1) * (1.0 + equip_affix("move"))


## 攻击间隔（秒）：敏捷提高攻速，下限防止无脑堆敏捷；迅捷被动 -10%/级
func attack_interval() -> float:
	return clampf((0.9 - agility * 0.01) * passive_mult("atk_speed", 0.9), 0.25, 0.9)


## 技能冷却乘子（洞悉被动 -8%/级）
func cooldown_mult() -> float:
	return passive_mult("cdr", 0.92) * (1.0 - equip_affix("cdr"))


## 金币获取乘子（贪婪被动）
func gold_mult() -> float:
	return passive_mult("gold", 1.15) * (1.0 + equip_affix("gold"))


## 普攻吸血量（噬血被动，3/级）
func lifesteal_per_hit() -> float:
	return passive_level("lifesteal") * 3.0 + physical_attack() * equip_affix("lifesteal")


## 击退乘子（重锤被动）
func knockback_mult() -> float:
	return passive_mult("knock", 1.3)
