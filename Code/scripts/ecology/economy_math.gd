## 经济公式（纯逻辑层，RefCounted 无 Node 依赖——未来随 EcologySim 整体搬服务端的单元）。
## 金币三大来源的公式全部收口在此：击杀掉落 / 赏金任务 / 商店买卖。
## 表现层（MonsterBase/BountyManager/GameState）只调用不计算；
## balance_test 直读真源断言经济带，改动公式自动进闸。
## 约定：全部确定性公式（无 RNG）——个体差异由 精英/Boss/体型/威胁系数 天然引入，
## 节奏测试不因掉落骰子抖动。
class_name EconomyMath


## Boss 掉落的年龄封顶（tick）：Boss 寿命长（2400+）且 strength 随年龄线性涨，
## 不封顶则长寿 Boss 单杀 3600+ 金——超过全部金币消耗口（商店满配 1950 金），
## 击杀一只就让经济失去意义。600 tick（≈10 游戏分钟）封顶后 ≈ 1270 金，
## 仍是"发一笔横财"的量级但买不穿商店。xp 侧 xp_per_age=0 同理已封顶
const BOSS_GOLD_AGE_CAP := 600.0


## --- 击杀掉落 ---
## 基础掉落随力量线性走（成年强怪更值钱），乘体型（分裂子代缩水）、
## 乘区域威胁（深入险地收益更高——风险收益对齐）。
## 原随机版 randi_range(3,8)*threat 均值 5.5×威胁；本公式妖鬼成年 ≈ 7，量级持平。
static func kill_gold(inst: MonsterInstance) -> int:
	var strength := inst.strength()
	if inst.species.is_boss:
		# Boss 的年龄增长项封顶（同 BOSS_GOLD_AGE_CAP 注释）
		strength = inst.species.base_strength \
				+ inst.species.strength_growth * minf(float(inst.age), BOSS_GOLD_AGE_CAP)
	var base := (3.0 + strength * 0.5) * inst.size_scale * inst.threat_scale
	if inst.species.is_boss:
		base *= 8.0
	elif inst.is_elite:
		base *= 4.0
	return maxi(1, roundi(base))


## --- 赏金任务（BountyManager 换单时计算） ---
## 目标数与玩家等级双驱动：后期任务更值钱，但不追平主线刷怪收益（任务是指路牌不是印钞机）
static func bounty_gold(target: int, player_level: int) -> int:
	return 12 + target * 6 + player_level * 3


static func bounty_xp(target: int) -> int:
	return 20 + target * 8


## --- 游商营地（GameState 购买） ---
## 强化定价：线性递增，一级≈7 只西部怪，满配三级≈两分钟中局刷怪（pacing 闸门校准）
static func upgrade_cost(current_level: int) -> int:
	return 50 + current_level * 40


## 装备折价：替换下来的装备按稀有度折金（捡到就比穿强 → 也有金币补偿）
static func sell_price(rarity: int) -> int:
	return 20 + clampi(rarity, 0, 3) * 10


## --- 物品经济（玩法 v7 P0）：掉落映射 / 买价 / 材料卖价 全收口在此 ---
## 与击杀金币同口径：全部确定性（无 RNG）——个体差异由 精英/Boss 乘数与
## Boss 附加件的 hash(world_seed|instance_id) 确定性抽取引入，节奏测试不抖动。
## 物品表现层元数据（名称/图标）在 ItemCatalog；恢复比例在 CharacterStats。

## 消耗品买价（商店补给页货源）。定价梯度 = 便宜的单位恢复效率高、
## 贵的买即时性与上限（中期 250 血：饭团 4.4 HP/金 → 生命药剂 1.7 HP/金），
## balance_test "每金恢复量"闸门守带
const ITEM_BUY := {
	"onigiri": 20, "sushi": 40, "water-pot": 25, "medipack": 80, "life-pot": 150,
}

## 材料卖价。量级锚定击杀金币的 3~5 成（野猪单杀金 ~7，兽肉 8）——材料是
## 击杀收益的补充而非替代；稀有卷轴（2.2+ 威胁区物种）给到 30，风险收益对齐
const ITEM_SELL := {
	"beaf": 8, "fish": 8, "shrimp": 8, "octopus": 10, "tea-leaf": 6,
	"scroll-fire": 30, "scroll-rock": 30,
}

## 物种 → 掉落材料（确定性；未列出的物种不掉材料——史莱姆/蝙蝠/幽灵等
## 无形体系不给物品收益，宁缺毋滥）。Boss 在 BOSS_MATERIAL 单列（乘数 ×3）
const SPECIES_MATERIAL := {
	"野猪": "beaf", "雪熊": "beaf", "鸡": "beaf", "浣熊": "beaf", "鹦鹉": "beaf", "松鼠": "beaf",
	"企鹅": "fish", "绿龟": "fish",
	"沼泽蟹": "shrimp",
	"红章鱼": "octopus",
	"萌芽怪": "tea-leaf", "仙人掌怪": "tea-leaf", "蘑菇怪": "tea-leaf", "曼德拉草": "tea-leaf",
	"火鸟": "scroll-fire", "火龙": "scroll-fire",
	"石像鬼": "scroll-rock", "甲虫": "scroll-rock",
}

const BOSS_MATERIAL := {"树人": "tea-leaf", "锹形虫王": "scroll-rock", "龟王": "fish"}

## Boss 附加消耗品池（击杀必附 1 件，确定性抽取）
const BOSS_BONUS_POOL := ["onigiri", "sushi", "medipack", "water-pot"]


## 合法物品 id（存档消毒 / 商店校验共用）
static func knows_item(id: String) -> bool:
	return ITEM_BUY.has(id) or ITEM_SELL.has(id)


## 物种的材料（"" = 不掉）；Boss 优先查 BOSS_MATERIAL
static func material_for(species_name: String) -> String:
	if BOSS_MATERIAL.has(species_name):
		return BOSS_MATERIAL[species_name]
	return str(SPECIES_MATERIAL.get(species_name, ""))


## 材料数量乘数：普通 1 / 精英 ×2 / Boss ×3（与金币精英 ×4 / Boss ×8 同向但更缓——
## 材料是补充收益，不宜像金币那样拉开量级）
static func drop_count(inst: MonsterInstance) -> int:
	if inst.species.is_boss:
		return 3
	if inst.is_elite:
		return 2
	return 1


## Boss 附加消耗品：hash(世界种子|实例 id) 确定性抽取（无 RNG——同一次击杀
## 在任何端上结果一致，随迁服务端语义不变）
static func boss_bonus_item(world_seed: int, instance_id: int) -> String:
	var h := hash("item-bonus|%d|%d" % [world_seed, instance_id])
	return BOSS_BONUS_POOL[absi(h) % BOSS_BONUS_POOL.size()]


## 消耗品买价（0 = 不可购买，即材料）
static func item_price(id: String) -> int:
	return int(ITEM_BUY.get(id, 0))


## 材料卖价（0 = 不可出售，即消耗品——只有材料有售出通道）
static func item_sell_price(id: String) -> int:
	return int(ITEM_SELL.get(id, 0))


## 单杀材料估值（balance_test 经济带断言用）：材料数 × 卖价
static func material_value_per_kill(species_name: String, is_elite := false) -> float:
	var mat := material_for(species_name)
	if mat == "":
		return 0.0
	var mult := 2.0 if is_elite else 1.0
	return float(item_sell_price(mat)) * mult
