## 新手引导与生态事件播报（纯观察者，不改写任何模拟状态）。
## 原则：只在真实事件发生时点亮提示——玩家亲眼所见才有教学意义；
## 完成标志持久化到存档（GameState.tutorial_flags），不重复打扰。
## 前 5 分钟的关键节拍：操作 → 生态面板 → 首次击杀各物种机制 →
## 首次分裂 / 首次迁徙（生态事件）→ 首次深入高星区域 → 首次死亡。
class_name Tutorial
extends Node

const OPENING_DELAY := 1.5
const SECOND_HINT_DELAY := 14.0

## 每物种首次击杀的机制讲解（教学即卖点：把破解思路直接告诉玩家）
const FIRST_KILL_TIPS := {
	"哥布林": "哥布林会呼叫同伴围攻——把它们引出营地逐个击破",
	"史莱姆": "史莱姆被击杀会裂成两只小的（子代不再分裂）——刷它之前想清楚",
	"野猪": "野猪冲锋前会停步变色预警——侧移躲开，或引它撞墙打出硬直",
	"雪蝎": "雪蝎会远距离吐毒、被贴近就后撤——贴身缠斗或绕侧切入",
	"兵蚁": "兵蚁越多伤害越高，还会持续入侵邻近地图——尽早拆散蚁群",
	"岩甲龟": "岩甲龟重击前摇很长（蓄力变橙）——走出范围即可；它近乎独居、永不迁徙",
}

## 首次迁徙播报（生态事件新闻感）
const FIRST_MIGRATION_NEWS := {
	"兵蚁": "生态事件：兵蚁军团正在迁入邻近地图——蚁群的扩张不会停",
	"哥布林": "生态事件：哥布林部落开始向邻区迁徙",
}


func _ready() -> void:
	# 开场操作提示（已看过则不再打扰）
	if not _seen("open1"):
		# 触屏设备文案不提键位（iOS 首发的主要输入是虚拟摇杆与技能键）
		var controls := "移动 WASD　攻击 空格/J　冲刺 Shift/K（冲刺中无敌！）"
		if DisplayServer.is_touchscreen_available():
			controls = "左侧摇杆移动　右侧按键攻击/冲刺（冲刺中无敌！）"
		get_tree().create_timer(OPENING_DELAY).timeout.connect(func() -> void:
			_hint("open1", controls)
		)
	if not _seen("open2"):
		get_tree().create_timer(SECOND_HINT_DELAY).timeout.connect(func() -> void:
			_hint("open2", "左上「生态监测」实时显示六块地图的种群——这个世界自己在活着")
		)

	EventBus.player_entered_region.connect(_on_region)
	EventBus.monster_killed_by_player.connect(_on_kill)
	EventBus.player_died.connect(func() -> void:
		_hint("died", "你死了，但生态不会停：它们仍在繁衍、迁徙、衰老")
	)
	# 生态事件：只观察真实信号（模拟层事件 → 播报）
	if WorldSim.sim != null:
		WorldSim.sim.instance_spawned.connect(_on_spawned)
		WorldSim.sim.instance_migrated.connect(_on_migrated)


func _on_region(region_id: String, display_name: String) -> void:
	if region_id == "center" and not _seen("goto_center"):
		_hint("goto_center", "%s：危险与奖励一起升高——怪物强度看星级" % display_name)
	elif region_id != "west" and not _seen("deep_zone"):
		_hint("deep_zone", "深入高星区域前先练级——右上小地图可看全图与怪物动向")


func _on_kill(_xp: int, _gold: int, monster_name: String) -> void:
	var species_name := monster_name.get_slice("#", 0)
	if species_name.begins_with("精英·"):
		species_name = species_name.trim_prefix("精英·")
	var tip: String = FIRST_KILL_TIPS.get(species_name, "")
	if tip != "" and not _seen("kill_" + species_name):
		_hint("kill_" + species_name, tip)


func _on_spawned(inst: MonsterInstance) -> void:
	if inst.generation > 0 and not _seen("split_seen"):
		_hint("split_seen", "分裂发生了！小史莱姆不再分裂——每条血脉的总收益有上限")


func _on_migrated(inst: MonsterInstance, _to_region_id: String) -> void:
	var news: String = FIRST_MIGRATION_NEWS.get(inst.species.species_name, "")
	if news != "" and not _seen("migrate_" + inst.species.species_name):
		_hint("migrate_" + inst.species.species_name, news)


func _seen(key: String) -> bool:
	return GameState.tutorial_flags.has(key)


func _hint(key: String, text: String) -> void:
	GameState.set_tutorial_flag(key)
	EventBus.hint_requested.emit(text)
