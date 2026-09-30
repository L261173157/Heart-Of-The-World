## 成就管理器（挂载于 game_world，纯订阅判定 + GameState 持久化）。
## 成就表刻意偏重生态事件——把"我在改变这个世界"的感知钉进玩家的里程碑。
class_name AchievementManager
extends Node

## id → {title, desc}；解锁条件在 _ready 的订阅里逐条判定
const ACHIEVEMENTS := {
	"first_elite": {"title": "金色猎手", "desc": "首次击杀精英个体"},
	"first_boss": {"title": "顶点陨落", "desc": "讨伐任一生态位 Boss"},
	"turtle_king": {"title": "洞窟之主", "desc": "讨伐熔岩龟王"},
	"ant_queen": {"title": "断绝虫巢", "desc": "讨伐牛头王"},
	"treant": {"title": "森林哀歌", "desc": "讨伐巨魔王"},
	"witness_extinct": {"title": "见证灭绝", "desc": "亲历一个物种从世界上消失"},
	"witness_revive": {"title": "见证复苏", "desc": "亲历灭绝物种重返世界"},
	"level5": {"title": "初出茅庐", "desc": "达到 5 级"},
	"level10": {"title": "老练猎人", "desc": "达到 10 级"},
	"first_upgrade": {"title": "武装起来", "desc": "首次在游商营地购买强化"},
	"kills100": {"title": "百人斩", "desc": "累计击杀 100 只怪物"},
	"night_walker": {"title": "夜行者", "desc": "在夜晚存活到黎明"},
	"codex_full": {"title": "博物学家", "desc": "图鉴集齐全部物种"},
}


func _ready() -> void:
	EventBus.monster_killed_by_player.connect(_on_kill)
	# 灭绝/复苏走结构化信号（world_event_watcher 与播报文案解耦后改文案不断链）。
	# 方法引用连接：lambda 捕获 self 不随对象释放断连，回菜单后下一局世界的
	# 生态信号会悬空调用已释放的本节点（世界子节点连长命信号的统一纪律）
	EventBus.species_extinct.connect(_on_species_extinct)
	EventBus.species_recovered.connect(_on_species_recovered)
	EventBus.day_phase_changed.connect(_on_day_phase)
	# 夜间读档时 resume_clock 的入夜信号早于本节点挂载；若不补记，玩家从
	# 存档中的夜晚活到黎明也不会解锁“夜行者”，同一段生存挑战因读档被吞掉。
	if WorldSim.is_night:
		set_meta("night_started", true)
	GameState.stats.leveled_up.connect(_on_leveled_up)
	# 商店购买没有专用信号，借升级通知的时机检查强化等级
	GameState.stats.changed.connect(_check_shop_achievement)


func _on_species_extinct(_species: String) -> void:
	unlock("witness_extinct")


func _on_species_recovered(_species: String) -> void:
	unlock("witness_revive")


func _on_leveled_up(level: int, _levels: int) -> void:
	if level >= 5:
		unlock("level5")
	if level >= 10:
		unlock("level10")


func unlock(id: String) -> void:
	if GameState.achievements.has(id) or not ACHIEVEMENTS.has(id):
		return
	GameState.achievements[id] = true
	GameState._queue_save()
	var title: String = ACHIEVEMENTS[id]["title"]
	EventBus.achievement_unlocked.emit(title)
	print("[成就] %s" % title)


## 物种判定走结构化 species_name（精英獾王也算讨伐蚁后——旧字符串前缀
## 判定漏掉精英个体）；精英识别仍看展示名前缀
func _on_kill(_xp: int, _gold: int, monster_name: String, species_name: String) -> void:
	if monster_name.begins_with("精英·"):
		unlock("first_elite")
	# Boss 判定走模拟层物种真源（is_boss）而非名字硬编码清单——
	# 新增 Boss 物种自动获得 first_boss，精英个体同样计入；
	# 此前 first_boss 从未被解锁（死成就），古木魔像更是零击杀反馈
	var world := get_parent()
	if world != null and world._sim != null:
		var species: SpeciesData = world._sim.find_species(species_name)
		if species != null and species.is_boss:
			unlock("first_boss")
	if species_name == "牛头王":
		unlock("ant_queen")
	if species_name == "熔岩龟王":
		unlock("turtle_king")
	if species_name == "巨魔王":
		unlock("treant")
	if _total_kills() >= 100:
		unlock("kills100")
	if _codex_complete():
		unlock("codex_full")


func _on_day_phase(night: bool) -> void:
	# 入夜标记起计时，熬到下一次相位切换（黎明）时解锁
	if night:
		set_meta("night_started", true)
	elif has_meta("night_started"):
		remove_meta("night_started")
		unlock("night_walker")


func _check_shop_achievement() -> void:
	if GameState.upgrade_level("weapon") + GameState.upgrade_level("staff") \
			+ GameState.upgrade_level("vigor") > 0:
		unlock("first_upgrade")


func _total_kills() -> int:
	var total := 0
	for species_name in GameState.codex:
		total += int(GameState.codex[species_name])
	return total


func _codex_complete() -> bool:
	var world := get_parent()
	if world == null or world._sim == null:
		return false
	for species: SpeciesData in world._sim.species_list:
		if not GameState.codex.has(species.species_name):
			return false
	return true
