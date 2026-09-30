## 种族配置（纯数据，Resource）。
## 对应《策划纲要》怪物系统的族群特性：繁殖速度、资源消耗、友好值、智力值。
## M0 用代码内建六种族配置（见 SpeciesCatalog）；M1 改为 .tres 资源文件做数据驱动。
## 时间单位均为 tick（当前 1 tick = 1 秒，由 WorldSim 驱动）。
class_name SpeciesData
extends Resource

@export var species_name: String = "火把哥布林"

## 表现层用：占位视觉/小地图统一取色
@export var tint: Color = Color(0.35, 0.7, 0.25)

## 表现层用：帧动画覆盖（共用表现场景但形象不同的种族，如冰晶史莱姆→蓝色赤炎小魔帧；
## 空 = 用场景默认 SpriteFrames）。纯表现数据，模拟层不读
@export var frames_override: SpriteFrames
## 视觉缩放（美术 v6 原生直出）：凑「最终整数渲染缩放」用——场景基准 2.0 ×
## visual_scale 四舍五入 = 目标整数档（0.5=×1 档小型、1.0=×2 档标准/大型）；
## Boss 为画幅补偿（×boss_size_scale 后落目标档）。只管像素密度，不管占地
@export var visual_scale := 1.0
## 占地/碰撞系数（2026-09-20 从 visual_scale 拆出）：驱动 body_k 碰撞体与
## 血条抬升。改美术密度/渲染缩放不碰它——手感真源，改动需平衡性依据
@export var body_scale := 1.0
## 远程弹体贴图名（Enemy Pack 弹体首帧烘焙件，bake_structures 产
## structures_baked/<名>.png；空 = 默认箭矢。弹体素材须朝右，launch 旋转对齐）
@export var projectile_tex: String = ""
## 被动生物（美术 v5 完整包动物）：永不主动攻击玩家，玩家靠近即逃；
## 是猎物基底与生态氛围（承伤带在 balance_test 豁免，击杀带照常）
@export var ambient := false

## AI 原型（表现层据此选择行为分支，纯数据标记）：
## melee_swarm 群体围攻 / charger 蓄力冲锋 / splitter 接触分裂 /
## ranged 远程风筝 / soldier 协同近战 / guardian 重击守卫
@export var ai_archetype: String = "melee_swarm"

## 栖息地形（须与 SimRegion.terrain 匹配才能出生/繁衍/迁入；空 = 任意地形）
@export var habitats: Array[String] = []

## 初始能力值与随年龄增长速度（策划：能力值等级随年龄增加）
@export var base_strength: float = 2.0
@export var base_agility: float = 4.0
@export var base_intellect: float = 1.0
@export var strength_growth: float = 0.05
@export var agility_growth: float = 0.02
@export var intellect_growth: float = 0.01

## 寿命（tick），个体在区间内随机
@export var lifespan_min: int = 240
@export var lifespan_max: int = 480

## 繁殖：成年（maturity_age）后，每 tick 每个成年个体以 breeding_rate 概率触发一次出生
@export var maturity_age: int = 30
@export var breeding_rate: float = 0.02

## 扩张：区域存活数超过 expansion_threshold 时向邻居迁出 migrate_count 个；
## migrate_count <= 0 的种族永不迁徙（如独居守卫者）
@export var expansion_threshold: int = 10
@export var migrate_count: int = 2

## 尸体留存 tick 数（策划：尸体存在时间与种族和寿命相关，v0 用固定值）
@export var corpse_duration: int = 30

## 击杀奖励（经验随年龄增长；金币掉落在表现层随机）
@export var xp_base: int = 10
@export var xp_per_age: float = 0.1

## --- 战斗参数（表现层消费；v0 占位，改动只动这里不动调用方） ---

## 索敌半径 / 攻击距离 / 攻击冷却
@export var detect_radius: float = 170.0
@export var attack_range: float = 32.0
@export var attack_cooldown: float = 1.2
## 残血逃跑比例（<=0 永不逃跑，如狂暴/守卫型）
@export var flee_hp_ratio: float = 0.25
## 护甲：受到伤害的减免比例（0~0.8）
@export var defense_reduction: float = 0.0
## 击退抗性（0~1，1 = 免疫击退）
@export var knockback_resist: float = 0.0
## 削韧/霸体（0~1）：击退的额外抗性，与 knockback_resist 并联合成
## （kb + poise×(1-kb)，边际递减）；1 = 完全霸体（石魔像/窟魔王：任何攻击都推不动）
@export var poise: float = 0.0
## 进攻倍率（v2 数值框架）：力量同时驱动生命与攻击，攻防手感要分家时用它——
## 脆皮炮台 <1（地精矿工/孢子类），重击威胁 >1（雪怪/守卫类）；
## 数值设计目标带反推（CombatBandMath）消费同一字段
@export var offense_scale: float = 1.0

## --- AI 原型细分参数（各原型专属行为的调参入口；默认值 = 原脚本常量，
## .tres 未覆盖即沿用默认。此前写死在子类脚本里，Boss 型与普通型共用
## 同一原型时无法按物种调参——铁律"战斗参数全部读 SpeciesData"的补全） ---

## charger 原型：冲锋触发距离 / 前摇时长 / 速度倍率 / 最长时限 /
## 命中判定距离 / 伤害倍率 / 撞墙硬直时长
@export var charge_trigger_dist: float = 320.0
@export var charge_tell_time: float = 0.5
@export var charge_speed_mult: float = 2.6
@export var charge_max_time: float = 0.9
@export var charge_hit_dist: float = 38.0
@export var charge_damage_mult: float = 2.0
@export var tired_time: float = 1.3
## guardian 原型：重击前摇时长 / 砸击判定半径倍率（attack_range × 此值）
@export var guard_windup_time: float = 0.8
@export var guard_smash_range_mult: float = 1.7
## ranged 原型：与目标保持的距离（被贴近即后撤拉开）
@export var keep_away_dist: float = 120.0
## melee_swarm / soldier 原型：同伴受击的支援半径（仇恨连锁，0 = 无支援）
@export var assist_radius: float = 0.0
## soldier 原型（骷髅兵）：协同增伤的群体半径 / 每只同伴加成 / 加成上限
@export var pack_radius: float = 130.0
@export var pack_bonus_per: float = 0.1
@export var pack_bonus_max: int = 3

## --- 捕食关系（生态链核心）---
## 本物种捕食的物种名列表；同区域每 tick 每个捕食者按 PREDATION_CHANCE 猎杀一只猎物。
## 玩家杀死捕食者 → 猎物失去压制而爆发 → 挤占区域承载 → 入侵邻区：生态级联的引擎。
@export var prey: Array[String] = []

## --- 生态位 Boss（顶点掠食者）---
## is_boss 物种：个体庞大（size_scale 由初始种群指定）、不迁徙不逃跑、奖励丰厚；
## 全灭后按 boss_respawn_ticks 倒计时在其栖息地重生
@export var is_boss: bool = false
@export var boss_respawn_ticks: int = 300
## Boss 体型放大系数（初始入场与重生共用同一数据源，避免两处魔法数漂移）
@export var boss_size_scale: float = 2.2

## --- 分裂繁殖（赤炎小魔型）：被玩家击杀时裂成子代，"越杀越多" ---
## 仅被击杀触发（自然老死不分裂）；子代到 max_generation 代后失去分裂能力
@export var splits_on_death: bool = false
@export var split_count: int = 2
@export var split_size_scale: float = 0.6
@export var max_generation: int = 1

## 友好值（0 敌对 ~ 100 友善）—— M0 未参与逻辑
@export var friendliness: float = 0.0

## 元素属性（"" 无 / "fire" 火焰 / "ice" 寒冰）——区域克制玩法的怪物侧：
## 雪原系冰抗火弱，熔岩系火抗冰弱；玩家元素来自装备词条
@export var element: String = ""
