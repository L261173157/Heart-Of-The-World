## 近身出招协调：每个真实目标最多两只同时承诺攻击，起手错开 0.1 秒。
## 只保存弱引用、只扫描最多两个占位者；不扫描生态种群，不读取玩家输入。
## 占位在收招/断招/死亡/退场时归还，脱树的弱引用也会在下次请求时剔除。
extends RefCounted

const MAX_ATTACKERS := 2
const START_GAP_SECONDS := 0.1
static var _targets: Dictionary = {}


static func acquire(actor: Node, target: Node) -> bool:
	var frame := Engine.get_physics_frames()
	# 这里只扫描玩家目标记录（单机通常1条），绝不遍历怪物或模拟实例。
	for old_key: int in _targets.keys():
		var old: Dictionary = _targets[old_key]
		if old["target"].get_ref() == null or (old["actors"].is_empty() and frame >= int(old["next_frame"])):
			_targets.erase(old_key)
	var key := target.get_instance_id()
	if not _targets.has(key):
		_targets[key] = {"target": weakref(target), "actors": [], "next_frame": 0}
	var entry: Dictionary = _targets[key]
	var actors: Array = entry["actors"]
	for i in range(actors.size() - 1, -1, -1):
		var node: Node = actors[i].get_ref()
		if not is_instance_valid(node) or not node.is_inside_tree() or node.is_queued_for_deletion():
			actors.remove_at(i)
		elif node == actor:
			return true
	if actors.size() >= MAX_ATTACKERS or frame < int(entry["next_frame"]):
		return false
	actors.append(weakref(actor))
	entry["next_frame"] = frame + maxi(1, int(ceil(START_GAP_SECONDS * Engine.physics_ticks_per_second)))
	return true


static func release(actor: Node, target_id: int) -> void:
	if not _targets.has(target_id):
		return
	var entry: Dictionary = _targets[target_id]
	var actors: Array = entry["actors"]
	for i in range(actors.size() - 1, -1, -1):
		var node: Node = actors[i].get_ref()
		if not is_instance_valid(node) or node == actor:
			actors.remove_at(i)
	# 早期打断仍保留起手间隔；到期后由下一次请求清理空记录，弱引用不保活目标。
	if actors.is_empty() and (entry["target"].get_ref() == null \
			or Engine.get_physics_frames() >= int(entry["next_frame"])):
		_targets.erase(target_id)
