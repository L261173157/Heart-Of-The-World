## 生态信号 → 因果观察器 → 有界播报；快照是状态真源，信号只解释真实发生过什么。
class_name WorldEventWatcher
extends Node

const MAX_ANNOUNCEMENTS_PER_TICK := 2

var _detector: WorldEventDetector
var _local_region_id := ""


func _ready() -> void:
	var boss_names: Array = []
	if WorldSim.sim != null:
		for species: SpeciesData in WorldSim.sim.species_list:
			if species.is_boss:
				boss_names.append(species.species_name)
	_detector = WorldEventDetector.new(boss_names)
	EventBus.player_entered_region.connect(_on_region)
	EventBus.sim_tick_completed.connect(_on_sim_tick)
	if WorldSim.sim != null:
		# 首次区域事件早于本节点挂载，须从玩家实际位置补齐本地上下文。
		var player := get_tree().get_first_node_in_group("player") as Node2D
		if player != null:
			var context_pos := WorldConfig.spawn_pos() if ObstacleField.interior_index_at(player.global_position) >= 0 else player.global_position
			var region := WorldSim.sim.region_of_point(context_pos)
			if region != null:
				_local_region_id = region.id
		# 挂载时即建立基线，首个 tick 前的真实击杀/出生不会被吞掉；读档重放已结束。
		_detector.detect_events(WorldSim.sim._build_summary(), _context())
		WorldSim.sim.instance_spawned.connect(_on_spawned)
		WorldSim.sim.instance_migrated.connect(_on_migrated)
		WorldSim.sim.instance_died.connect(_on_died)


func _context() -> Dictionary:
	var player := get_tree().get_first_node_in_group("player") as Node2D if is_inside_tree() else null
	var indoor := player != null and ObstacleField.interior_index_at(player.global_position) >= 0
	return {"local_region_id": "" if indoor else _local_region_id,
		"player_extinct": WorldSim.sim.player_extinct if WorldSim.sim != null else {},
		"reintroduction_enabled": WorldSim.sim.reintroduction_enabled if WorldSim.sim != null else true}


func _on_region(region_id: String, _display_name: String) -> void:
	_local_region_id = region_id


func _on_spawned(inst: MonsterInstance) -> void:
	_detector.record_spawn(inst.species.species_name, inst.region_id, inst.generation, inst.age)


func _on_migrated(inst: MonsterInstance, to_region_id: String) -> void:
	_detector.record_migration(inst.species.species_name, to_region_id)


func _on_died(inst: MonsterInstance, cause: String) -> void:
	# 此信号早于分裂与 player_extinct 落定；下个完成 tick 再看权威结果，不能此刻宣判灭绝。
	_detector.record_death(inst.species.species_name, inst.region_id, cause)


func _on_sim_tick(summary: Dictionary) -> void:
	var announced := 0
	for event: Dictionary in _detector.detect_events(summary, _context()):
		if announced < MAX_ANNOUNCEMENTS_PER_TICK:
			EventBus.world_event.emit(event["text"])
			announced += 1
		# 成就旁路不受文本预算影响，也不从文案反解析因果。
		if event["kind"] == "extinct":
			EventBus.species_extinct.emit(event["species"])
		elif event["kind"] == "revive":
			EventBus.species_recovered.emit(event["species"])
