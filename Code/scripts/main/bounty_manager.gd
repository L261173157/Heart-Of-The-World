## 赏金任务管理器（挂载于 game_world）。
## 循环：随机挑一个当前存活物种 → 悬赏猎杀 N 只 → 完成发金币+经验 → 延迟换新单。
## 目标物种在世界中灭绝则立即换单——猎杀压力会真实改变生态，生态又反过来
## 改变任务板：玩法与核心卖点（生态自演化）互相咬合的最小闭环。
## 只读模拟快照（WorldSim.sim.instances），不改写模拟状态；沟通一律走 EventBus。
class_name BountyManager
extends Node

## game_world 的表现场景登记表（幽灵物种过滤用）
const _GameWorld := preload("res://scripts/main/game_world.gd")

const NEW_BOUNTY_DELAY := 8.0
const EXTINCT_CHECK_INTERVAL := 5.0

var _species_name := ""
var _target := 0
var _progress := 0
var _gold_reward := 0
var _xp_reward := 0
var _extinct_accum := 0.0


func _ready() -> void:
	EventBus.monster_killed_by_player.connect(_on_kill)
	_roll_later(1.0)


func _process(delta: float) -> void:
	if _species_name == "":
		return
	_extinct_accum += delta
	if _extinct_accum < EXTINCT_CHECK_INTERVAL:
		return
	_extinct_accum = 0.0
	if WorldSim.sim == null:
		EventBus.hint_requested.emit("赏金失效，正在更换…")
		_roll_later(2.0)
	elif not _species_alive():
		EventBus.hint_requested.emit("%s 已灭绝，赏金更换…" % _species_name)
		_roll_later(2.0)
	elif _species_alive_count() < _target - _progress:
		# 存活数已低于剩余需求（慢繁衍物种短期回不上来）：把剩下的全杀了
		# 也凑不够数，提前换单而不是让任务板对着空目标挂死几分钟
		EventBus.hint_requested.emit("%s 数量不足，赏金更换…" % _species_name)
		_roll_later(2.0)


func _roll_later(delay: float) -> void:
	_species_name = ""
	# 换单空窗期（2s 换单 + 8s 新单延迟）常驻栏如实显示，
	# 不再挂着已失效的旧赏金进度误导玩家
	EventBus.bounty_updated.emit("赏金交接中…")
	# ignore_time_scale：击杀顿帧会短时压低 time_scale，走默认计时器会把换单延迟
	# 拉长好几倍（Boss 击杀 0.05 倍速 + 连续精英顿帧时尤其明显）
	get_tree().create_timer(delay, true, false, true).timeout.connect(_roll_bounty)


## 从当前存活物种中随机挑一个作为目标（任务板始终指向活生生的世界）
func _roll_bounty() -> void:
	if WorldSim.sim == null:
		_roll_later(2.0)
		return
	# 排除唯一 Boss：全灭重生制下"猎杀 4~7 只"实际无法完成，只能干等换单；
	# 排除无表现场景的幽灵物种：模拟层活着但玩家看不见打不着，悬赏必然烂单；
	# 门槛 ≥3 只：濒危物种的"猎杀 N 只"注定烂单，悬赏指向繁衍健康的种群
	var alive_counts := {}
	for inst: MonsterInstance in WorldSim.sim.instances.values():
		if inst.is_alive and not inst.species.is_boss \
				and _GameWorld.MONSTER_SCENES.has(inst.species.species_name):
			var n: String = inst.species.species_name
			alive_counts[n] = int(alive_counts.get(n, 0)) + 1
	var candidates: Array = []
	for n: String in alive_counts:
		if int(alive_counts[n]) >= 3:
			candidates.append(n)
	if candidates.is_empty():
		_roll_later(3.0)
		return
	_species_name = candidates[randi() % candidates.size()]
	# 目标数钳到现存数量：剩 3 只时"猎杀 7 只"在物种回弹前永不可完成
	_target = mini(randi_range(4, 7), int(alive_counts[_species_name]))
	_progress = 0
	_gold_reward = EconomyMath.bounty_gold(_target, GameState.stats.level)
	_xp_reward = EconomyMath.bounty_xp(_target)
	_push()


func _push() -> void:
	EventBus.bounty_updated.emit("赏金：猎杀 %s  %d/%d" % [_species_name, _progress, _target])


func _on_kill(_xp: int, _gold: int, _monster_name: String, species_name: String) -> void:
	if _species_name == "":
		return
	if species_name != _species_name:
		return
	_progress += 1
	if _progress >= _target:
		GameState.add_gold(_gold_reward)
		GameState.add_xp(_xp_reward)
		EventBus.bounty_completed.emit(
			"赏金完成！%s +%d 金币 +%d 经验" % [_species_name, _gold_reward, _xp_reward])
		_roll_later(NEW_BOUNTY_DELAY)
	else:
		_push()


func _species_alive() -> bool:
	return _species_alive_count() > 0


## 目标物种当前存活数（换单判定：存活 < 剩余需求时提前换）
func _species_alive_count() -> int:
	if WorldSim.sim == null:
		return 0
	var count := 0
	for inst: MonsterInstance in WorldSim.sim.instances.values():
		if inst.is_alive and inst.species.species_name == _species_name:
			count += 1
	return count
