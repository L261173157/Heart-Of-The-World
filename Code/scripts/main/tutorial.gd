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
	"妖鬼": "妖鬼会呼叫同伴围攻——把它们引出营地逐个击破",
	"红史莱姆": "红史莱姆被击杀会裂成两只小的（子代不再分裂）——刷它之前想清楚",
	"野猪": "野猪冲锋前会停步变色预警——侧移躲开，或引它撞墙打出硬直",
	"绿龟": "绿龟冲锋前会缩颈蓄力——侧移躲开，它撞墙会自己打出硬直",
	"沼泽蟹": "沼泽蟹会远距离吐毒、被贴近就后撤——贴身缠斗或绕侧切入",
	"红章鱼": "红章鱼会远距离喷墨、被贴近就后撤——绕侧贴脸输出",
	"甲虫": "甲虫越多伤害越高，还会持续入侵邻近地图——尽早拆散虫群",
	"石像鬼": "石像鬼重击前摇很长（蓄力变橙+范围圈）——走出范围即可；它近乎独居、永不迁徙",
	"锹形虫王": "锹形虫王与甲虫协同增伤——先清掉周围的卫队，再单挑它",
	"龟王": "龟王完全霸体推不动，砸击有范围圈预警——看圈外撤，别贪刀",
	"冰史莱姆": "冰史莱姆死后也会分裂，且带寒冰元素——火系武器克制它",
	"萌芽怪": "萌芽怪是荒野的慢速前排，同伴受击还会赶来支援——先清落单的",
	"绿蛙": "绿蛙成群围攻且同伴受击即连锁仇恨——分割蛙群，逐个击破",
	"曼德拉草": "曼德拉草远程喷吐孢子、被贴近就后撤——贴身缠斗是破解思路",
	"蘑菇怪": "蘑菇怪远程喷洒毒孢子、被贴近就后撤——贴身缠斗是破解思路",
	"企鹅": "企鹅会蓄力滑撞且带寒冰元素——前摇时侧移，或引它撞墙；火系武器克制它",
	"幽灵": "幽灵在雪原成群游荡——数量就是它们的全部威胁，别被围在中间",
	"松鼠": "松鼠突袭又快又急——它弓身蓄力的一瞬赶紧侧移",
	"蝙蝠": "蝙蝠靠数量淹没猎物——范围重击是它们的克星",
	"仙人掌怪": "仙人掌怪远距离甩针刺、被贴近会退缩——绕侧贴脸输出",
	"火鸟": "火鸟的火羽伤害很高——寒冰附魔武器克制它，贴身近战别跟它对射",
	"树人": "树人是林地的顶点，冲撞范围极大——引它撞墙出硬直，那是输出的黄金窗口",
}

## 首次迁徙播报（生态事件新闻感）
const FIRST_MIGRATION_NEWS := {
	"甲虫": "生态事件：甲虫军团正在迁入邻近地图——虫群的扩张不会停",
	"妖鬼": "生态事件：妖鬼部落开始向邻区迁徙",
}


func _ready() -> void:
	# 开场操作提示（已看过则不再打扰）。定时器随暂停冻结（create_timer 第二参
	# process_always=false：暂停期间不走表）：否则玩家在开场几秒内按 ESC 暂停，
	# 提示会在暂停菜单背后一闪而过但 flag 已写档，教学被永久跳过。
	# 定时器回调用方法引用（非 lambda）：lambda 捕获 self 不受"对象释放自动断连"保护，
	# 进世界 14s 内回主菜单时定时器到期会对已释放节点悬空调用
	if not _seen("open1"):
		# 触屏设备文案不提键位（iOS 首发的主要输入是虚拟摇杆与技能键）
		var controls := "移动 WASD　攻击 空格/J　冲刺 Shift/K（冲刺中无敌！）"
		if DisplayServer.is_touchscreen_available():
			controls = "左侧摇杆移动　右侧按键攻击/冲刺（冲刺中无敌！）"
		get_tree().create_timer(OPENING_DELAY, false).timeout.connect(_hint_opening1.bind(controls))
	if not _seen("open2"):
		get_tree().create_timer(SECOND_HINT_DELAY, false).timeout.connect(_hint_opening2)
	if not _seen("find_camp"):
		get_tree().create_timer(FIND_CAMP_DELAY, false).timeout.connect(_hint_find_camp)

	EventBus.player_entered_region.connect(_on_region)
	EventBus.monster_killed_by_player.connect(_on_kill)
	EventBus.player_died.connect(func() -> void:
		_hint("died", "你死了，但生态不会停：它们仍在繁衍、迁徙、衰老")
	)
	# 生态事件：只观察真实信号（模拟层事件 → 播报）
	if WorldSim.sim != null:
		WorldSim.sim.instance_spawned.connect(_on_spawned)
		WorldSim.sim.instance_migrated.connect(_on_migrated)


func _hint_opening1(controls: String) -> void:
	_hint("open1", controls)


func _hint_opening2() -> void:
	_hint("open2", "左上「生态监测」实时显示各片群系的种群——这个世界自己在活着")


func _hint_find_camp() -> void:
	# 到点仍未开杀才点亮（flag 在 _hint 内写档，一次性）；已开杀说明玩家
	# 自己找到了怪，不再打扰
	if GameState.session_kills > 0 or _seen("find_camp"):
		return
	_hint("find_camp", "怪物以族群营地栖居荒野，附近未必有——看小地图的彩色怪群点，朝最近的进发")


func _on_region(region_id: String, display_name: String) -> void:
	# v4 群系世界：引导按地形触发（多斑块同地形共享引导节拍）
	var region: SimRegion = WorldSim.sim.get_region(region_id) if WorldSim.sim != null else null
	var terrain: String = region.terrain if region != null else ""
	if terrain == "forest" and not _seen("goto_center"):
		_hint("goto_center", "%s：危险与奖励一起升高——怪物强度看星级" % display_name)
	elif terrain != "plains" and not _seen("deep_zone"):
		_hint("deep_zone", "深入高星群系前先练级——右上小地图的彩色怪群点就是各族群的营地")


func _on_kill(_xp: int, _gold: int, _monster_name: String, species_name: String) -> void:
	var tip: String = FIRST_KILL_TIPS.get(species_name, "")
	if tip != "" and not _seen("kill_" + species_name):
		_hint("kill_" + species_name, tip)


func _on_spawned(inst: MonsterInstance) -> void:
	if inst.generation > 0 and not _seen("split_seen"):
		_hint("split_seen", "分裂发生了！小红史莱姆不再分裂——每条血脉的总收益有上限")


func _on_migrated(inst: MonsterInstance, _to_region_id: String) -> void:
	var news: String = FIRST_MIGRATION_NEWS.get(inst.species.species_name, "")
	if news != "" and not _seen("migrate_" + inst.species.species_name):
		_hint("migrate_" + inst.species.species_name, news)


func _seen(key: String) -> bool:
	return GameState.tutorial_flags.has(key)


func _hint(key: String, text: String) -> void:
	GameState.set_tutorial_flag(key)
	EventBus.hint_requested.emit(text)
