## 赏金任务管理器（挂载于 game_world）。
## 循环：随机挑一个当前存活物种 → 悬赏猎杀 N 只 → 完成发金币+经验 → 延迟换新单。
## 目标物种在世界中灭绝则立即换单——猎杀压力会真实改变生态，生态又反过来
## 改变任务板：玩法与核心卖点（生态自演化）互相咬合的最小闭环。
## 只读模拟快照（WorldSim.sim.instances），不改写模拟状态；沟通一律走 EventBus。
class_name BountyManager
extends Node

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
	if WorldSim.sim == null or not _species_alive():
		EventBus.hint_requested.emit("%s 已灭绝，赏金更换…" % _species_name)
		_roll_later(2.0)


func _roll_later(delay: float) -> void:
	_species_name = ""
	get_tree().create_timer(delay).timeout.connect(_roll_bounty)


## 从当前存活物种中随机挑一个作为目标（任务板始终指向活生生的世界）
func _roll_bounty() -> void:
	if WorldSim.sim == null:
		_roll_later(2.0)
		return
	# 排除唯一 Boss：全灭重生制下"猎杀 4~7 只"实际无法完成，只能干等换单
	var candidates := {}
	for inst: MonsterInstance in WorldSim.sim.instances.values():
		if inst.is_alive and not inst.species.is_boss:
			candidates[inst.species.species_name] = true
	if candidates.is_empty():
		_roll_later(3.0)
		return
	var names := candidates.keys()
	_species_name = names[randi() % names.size()]
	_target = randi_range(4, 7)
	_progress = 0
	_gold_reward = 12 + _target * 6 + GameState.stats.level * 3
	_xp_reward = 20 + _target * 8
	_push()


func _push() -> void:
	EventBus.bounty_updated.emit("赏金：猎杀 %s  %d/%d" % [_species_name, _progress, _target])


func _on_kill(_xp: int, _gold: int, monster_name: String) -> void:
	if _species_name == "":
		return
	var species_name := monster_name.get_slice("#", 0)
	if species_name.begins_with("精英·"):
		species_name = species_name.trim_prefix("精英·")
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
	for inst: MonsterInstance in WorldSim.sim.instances.values():
		if inst.is_alive and inst.species.species_name == _species_name:
			return true
	return false
