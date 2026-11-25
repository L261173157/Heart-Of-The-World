## 新手引导与生态事件播报（纯观察者，不改写任何模拟状态）。
## 原则：只在真实事件发生时点亮提示——玩家亲眼所见才有教学意义；
## 完成标志持久化到存档（GameState.tutorial_flags），不重复打扰。
## 前 5 分钟的关键节拍：操作 → 生态面板 → 首次击杀各物种机制 →
## 首次分裂 / 首次迁徙（生态事件）→ 首次深入高星区域 → 首次死亡。
class_name Tutorial
extends Node

const OPENING_DELAY := 1.5
const SECOND_HINT_DELAY := 14.0
## 找怪引导的等待窗：出生斑块内没有营地（最近据点 ≈4000px，约 10 秒脚程），
## 玩家若一直没开杀多半是在"附近怎么没有怪"里迷失——到点仍未击杀就指路
const FIND_CAMP_DELAY := 30.0

## 每物种首次击杀的机制讲解（教学即卖点：把破解思路直接告诉玩家）；
## 22 物种全覆盖（美术 v5 纯 NA 名录）
const FIRST_KILL_TIPS := {
	"火把哥布林": "火把哥布林会呼朋唤友、一拥而上——引出巢穴，各个击破",
	"赤炎小魔": "赤炎小魔一死便裂成两只小的（小的不再分裂）——动手前想清楚",
	"突袭蛇": "突袭蛇冲锋前会停步变色——侧身让开，或引它撞墙，撞个踉跄",
	"青甲龟": "青甲龟冲锋前会缩颈蓄力——侧身让开，它撞了墙自会踉跄",
	"沼泽蛛": "沼泽蛛远处吐毒，一贴近便退——贴身缠斗，或绕到侧翼",
	"炸弹鱼": "炸弹鱼远处喷墨，一贴近便退——绕到侧翼，贴身出手",
	"长矛哥布林": "长矛哥布林越多下手越狠，还会不断窜入邻近地界——趁早拆散它们",
	"黑曜牛卫": "黑曜牛卫重击前蓄势许久（变橙并有范围圈）——走出圈外便是；它近乎独居，从不迁徙",
	"牛头王": "牛头王同长矛哥布林并肩时下手更狠——先清了四周的卫队，再单挑它",
	"熔岩龟王": "熔岩龟王岿然推不动，砸击前有范围圈——见圈便撤，莫贪刀",
	"冰霜小魔": "冰霜小魔死后也会分裂，又带寒冰之气——火系武器克它",
	"地精矿工": "地精矿工是荒野里慢吞吞的先锋，同伴一挨打便来援手——先清落单的",
	"蜥蜴刀客": "蜥蜴刀客成群围攻，一个挨打全都记仇——把它们拆开，各个击破",
	"弹弓地精": "弹弓地精远远喷吐孢子，一贴近便退——贴身缠斗可破",
	"巫毒萨满": "巫毒萨满远远洒下毒孢，一贴近便退——贴身缠斗可破",
	"雪原窃贼": "雪原窃贼会蓄力滑撞，又带寒冰之气——蓄势时侧身让开，或引它撞墙；火系武器克它",
	"白骨兵": "白骨兵在雪原成群游荡——人多便是它们全部的威风，莫叫它们围在当中",
	"山蜂": "山蜂突袭又快又急——它弓身蓄力的一瞬，赶紧侧身让开",
	"巨蝠": "巨蝠仗着数量围困猎物——范围重击正克它们",
	"投骨豺狼人": "投骨豺狼人远远甩出骨刺，一贴近便退缩——绕到侧翼，贴身出手",
	"火蜂": "火蜂的火羽伤人极重——寒冰附魔武器克它，贴身近战，莫同它对射",
	"巨魔王": "巨魔王是林地的霸王，冲撞范围极大——引它撞墙，撞个踉跄，那便是出手的良机",
	"雪原巨熊": "雪原巨熊冲锋前会人立而起——侧身让开，或引它撞墙",
	"山岳熊猫": "山岳熊猫群战时下手更狠——引出落单的再打",
	"鱼叉鲨": "鱼叉鲨远远瞪视灼人，一贴近便飘走——贴身缠斗可破",
	"熔岩萨满": "熔岩萨满吐息伤人极重——寒冰附魔克它，贴身近战，莫对射",
	"山猪": "山猪受惊便飞奔——营地周边的小猎物，一刀一个",
	"山羊": "山羊胆小怕人——林地食物链的底层",
	"野鸭": "野鸭机警聒噪——靠近就飞走的小家伙",
}

## 首次迁徙播报（生态事件新闻感）
const FIRST_MIGRATION_NEWS := {
	"长矛哥布林": "生态事件：长矛哥布林的大队正迁入邻近地界——虫群的扩张不会停",
	"火把哥布林": "生态事件：火把哥布林部落开始向邻区迁徙",
}


func _ready() -> void:
	# 开场操作提示（已看过则不再打扰）。定时器随暂停冻结（create_timer 第二参
	# process_always=false：暂停期间不走表）：否则玩家在开场几秒内按 ESC 暂停，
	# 提示会在暂停菜单背后一闪而过但 flag 已写档，教学被永久跳过。
	# 定时器回调用方法引用（非 lambda）：lambda 捕获 self 不受"对象释放自动断连"保护，
	# 进世界 14s 内回主菜单时定时器到期会对已释放节点悬空调用
	if not _seen("open1"):
		# 触屏设备文案不提键位（iOS 首发的主要输入是虚拟摇杆与技能键）
		var controls := "移动 WASD　攻击 空格/J　架盾 F　交互 E"
		if DisplayServer.is_touchscreen_available():
			controls = "左侧摇杆移动　右侧攻击／按住架盾／冲刺；走近对象便可互动"
		get_tree().create_timer(OPENING_DELAY, false).timeout.connect(_hint_opening1.bind(controls))
	if not _seen("open2"):
		get_tree().create_timer(SECOND_HINT_DELAY, false).timeout.connect(_hint_opening2)
	if not _seen("find_camp"):
		get_tree().create_timer(FIND_CAMP_DELAY, false).timeout.connect(_hint_find_camp)

	EventBus.player_entered_region.connect(_on_region)
	EventBus.monster_killed_by_player.connect(_on_kill)
	# v7 物品：首获材料（指路卖钱出口）+ 低血有补给（快捷槽救急）
	EventBus.item_gained.connect(_on_item_gained)
	EventBus.player_hp_changed.connect(_on_hp_for_item_hint)
	# player_died 用方法引用（与上方定时器同因）：lambda 捕获 self 不受
	# "对象释放自动断连"保护，回菜单后下一局世界的死亡信号会悬空调用本节点
	EventBus.player_died.connect(_on_player_died)
	# 生态事件：只观察真实信号（模拟层事件 → 播报）
	if WorldSim.sim != null:
		WorldSim.sim.instance_spawned.connect(_on_spawned)
		WorldSim.sim.instance_migrated.connect(_on_migrated)


func _on_player_died() -> void:
	_hint("died", "你倒下了，生态不会停：它们仍在繁衍、迁徙、衰老")


func _on_item_gained(item_id: String, _count: int, _total: int) -> void:
	if not ItemCatalog.is_consumable(item_id) and not _seen("first_material"):
		_hint("first_material", "拾取了 %s——材料可在营地行商处整叠换金币" % ItemCatalog.name_of(item_id))


## 低血 + 背包里有恢复品时点一次快捷槽教学（不打扰战斗节奏，只提一次）
func _on_hp_for_item_hint(current: float, maximum: float) -> void:
	if current >= maximum * 0.4 or _seen("quick_slot"):
		return
	for id: String in ["life-pot", "medipack", "sushi", "onigiri", "water-pot"]:
		if GameState.count_item(id) > 0:
			_hint("quick_slot", "带上 %s 了！「更多」可明确使用或设为恢复快捷键" % ItemCatalog.name_of(id))
			return


func _hint_opening1(controls: String) -> void:
	_hint("open1", controls)


func _hint_opening2() -> void:
	if GameState.outpost_quest.is_empty():
		_hint("open2", "营中巡守周照一直望着旧道。走近交谈，问问哨所出了什么事")
	else:
		_hint("open2", "任务栏会记下当前线索；想重看人物的话，可以打开任务记录")


func _hint_find_camp() -> void:
	# 到点仍未开杀才点亮（flag 在 _hint 内写档，一次性）；已开杀说明玩家
	# 自己找到了怪，不再打扰
	if GameState.session_kills > 0 or _seen("find_camp") or not GameState.outpost_quest.is_empty():
		return
	_hint("find_camp", "想沿旧道出发，先同营中巡守周照聊聊。他正等着哨所的消息")


func _on_region(region_id: String, display_name: String) -> void:
	# v4 群系世界：引导按地形触发（多斑块同地形共享引导节拍）
	var region: SimRegion = WorldSim.sim.get_region(region_id) if WorldSim.sim != null else null
	var terrain: String = region.terrain if region != null else ""
	if terrain == "forest" and not _seen("goto_center"):
		_hint("goto_center", "%s：危险与奖励一起升高——怪物强度看星级" % display_name)
	elif terrain != "plains" and not _seen("deep_zone"):
		_hint("deep_zone", "深入高星群系之前先练级；小地图只显示眼下视野里的族群")


func _on_kill(_xp: int, _gold: int, _monster_name: String, species_name: String) -> void:
	var tip: String = FIRST_KILL_TIPS.get(species_name, "")
	if tip != "" and not _seen("kill_" + species_name):
		_hint("kill_" + species_name, tip)


func _on_spawned(inst: MonsterInstance) -> void:
	if not _is_local_event(inst.region_id):
		return
	if inst.generation > 0 and not _seen("split_seen"):
		_hint("split_seen", "分裂发生了！小赤炎小魔不再分裂——每条血脉的总收益有上限")


func _on_migrated(inst: MonsterInstance, to_region_id: String) -> void:
	if not _is_local_event(to_region_id):
		return
	var news: String = FIRST_MIGRATION_NEWS.get(inst.species.species_name, "")
	if news != "" and not _seen("migrate_" + inst.species.species_name):
		_hint("migrate_" + inst.species.species_name, news)


## 全局模拟持续运行，远处迁徙不能提前消耗玩家的首次亲历教学。
func _is_local_event(region_id: String) -> bool:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null or WorldSim.sim == null or ObstacleField.interior_index_at(player.global_position) >= 0:
		return false
	var region := WorldSim.sim.region_of_point(player.global_position)
	return region != null and region.id == region_id


func _seen(key: String) -> bool:
	return GameState.tutorial_flags.has(key)


func _hint(key: String, text: String) -> void:
	GameState.set_tutorial_flag(key)
	EventBus.hint_requested.emit(text)
