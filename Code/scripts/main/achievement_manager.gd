## 成就管理器（挂载于 game_world，纯订阅判定 + GameState 持久化）。
## 成就表刻意偏重生态事件——把"我在改变这个世界"的感知钉进玩家的里程碑。
class_name AchievementManager
extends Node

## id → {title, desc}；解锁条件在 _ready 的订阅里逐条判定
const ACHIEVEMENTS := {
	"first_elite": {"title": "金色猎手", "desc": "首次击杀精英个体"},
	"first_boss": {"title": "顶点陨落", "desc": "讨伐任一生态位 Boss"},
	"turtle_king": {"title": "洞窟之主", "desc": "讨伐龟王"},
	"ant_queen": {"title": "断绝蚁巢", "desc": "讨伐蚁后"},
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
	EventBus.world_event.connect(_on_world_event)
	EventBus.day_phase_changed.connect(_on_day_phase)
	GameState.stats.leveled_up.connect(
		func(level: int) -> void:
			if level >= 5:
				unlock("level5")
			if level >= 10:
				unlock("level10")
	)
	# 商店购买没有专用信号，借升级通知的时机检查强化等级
	GameState.stats.changed.connect(_check_shop_achievement)


func unlock(id: String) -> void:
	if GameState.achievements.has(id) or not ACHIEVEMENTS.has(id):
		return
	GameState.achievements[id] = true
	GameState._queue_save()
	var title: String = ACHIEVEMENTS[id]["title"]
	EventBus.achievement_unlocked.emit(title)
	print("[成就] %s" % title)


func _on_kill(_xp: int, _gold: int, monster_name: String) -> void:
	if monster_name.begins_with("精英·"):
		unlock("first_elite")
	if monster_name.begins_with("蚁后"):
		unlock("ant_queen")
	if monster_name.begins_with("龟王"):
		unlock("turtle_king")
	if GameState.stats.level >= 1 and _total_kills() >= 100:
		unlock("kills100")
	if _codex_complete():
		unlock("codex_full")


func _on_world_event(text: String) -> void:
	if "消失" in text:
		unlock("witness_extinct")
	if "重新出现" in text:
		unlock("witness_revive")


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
