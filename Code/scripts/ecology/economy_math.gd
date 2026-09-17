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
