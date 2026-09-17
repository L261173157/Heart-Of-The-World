## 世界事件监视器（Node 壳）：订阅生态快照 → WorldEventDetector 纯逻辑检测 → EventBus.world_event 播报。
## 精英诞生由 game_world 在生成节点时直接播报（那边有个体信息）。
class_name WorldEventWatcher
extends Node

var _detector: WorldEventDetector


func _ready() -> void:
	# 注入 Boss 名单：Boss 有重生循环，灭绝/复苏播报对其是假信息
	var boss_names: Array = []
	if WorldSim.sim != null:
		for species: SpeciesData in WorldSim.sim.species_list:
			if species.is_boss:
				boss_names.append(species.species_name)
	_detector = WorldEventDetector.new(boss_names)
	EventBus.sim_tick_completed.connect(_on_sim_tick)


func _on_sim_tick(summary: Dictionary) -> void:
	for event: Dictionary in _detector.detect_events(summary):
		EventBus.world_event.emit(event["text"])
		# 结构化旁路：成就等判定消费 kind/species，与播报文案解耦（改文案不断链）
		if event["kind"] == "extinct":
			EventBus.species_extinct.emit(event["species"])
		elif event["kind"] == "revive":
			EventBus.species_recovered.emit(event["species"])
