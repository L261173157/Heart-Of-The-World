## 世界事件监视器（Node 壳）：订阅生态快照 → WorldEventDetector 纯逻辑检测 → EventBus.world_event 播报。
## 精英诞生由 game_world 在生成节点时直接播报（那边有个体信息）。
class_name WorldEventWatcher
extends Node

var _detector := WorldEventDetector.new()


func _ready() -> void:
	EventBus.sim_tick_completed.connect(_on_sim_tick)


func _on_sim_tick(summary: Dictionary) -> void:
	for text in _detector.detect_events(summary):
		EventBus.world_event.emit(text)
