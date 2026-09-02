## 世界事件检测（纯逻辑，RefCounted，无 Node / 无 autoload 依赖 → 可在 -s 单测中直接实例化）。
## 对比相邻两次生态快照，产出戏剧性事件文本：全球灭绝 / 复苏 / 区域入侵潮（0→≥3）/ 区域饱和；
## 同类事件 30s 节流防刷屏。Node 壳（world_event_watcher.gd）只负责订阅快照与转发 EventBus。
class_name WorldEventDetector
extends RefCounted

const EVENT_COOLDOWN := 30.0
const INVASION_THRESHOLD := 3

## 上一次快照：物种全球总数 { species: int } 与各区域物种构成 { rid: {species: int} }
var _global_totals := {}
var _region_species := {}
var _cooldowns := {}


## 对比上一快照产出事件文本列表；首帧（无历史）只记录不播报
func detect_events(summary: Dictionary) -> Array[String]:
	var events: Array[String] = []
	var totals := {}
	var regions_state := {}
	for region: Dictionary in summary["regions"]:
		var rid: String = region["id"]
		regions_state[rid] = (region["species"] as Dictionary).duplicate()
		for species_name: String in region["species"]:
			totals[species_name] = totals.get(species_name, 0) + region["species"][species_name]
	if not _global_totals.is_empty():
		for species_name: String in _global_totals:
			if _global_totals[species_name] > 0 and totals.get(species_name, 0) == 0:
				_emit(events, "extinct:%s" % species_name,
					"✕ %s 已从世界上永远消失…" % species_name)
		for species_name: String in totals:
			if totals[species_name] > 0 and _global_totals.get(species_name, 0) == 0:
				_emit(events, "revive:%s" % species_name,
					"%s 的身影重新出现在世界上" % species_name)
		for region: Dictionary in summary["regions"]:
			var rid: String = region["id"]
			var last_set: Dictionary = _region_species.get(rid, {})
			for species_name: String in region["species"]:
				if region["species"][species_name] >= INVASION_THRESHOLD \
						and not last_set.has(species_name):
					_emit(events, "invade:%s:%s" % [species_name, rid],
						"⚠ %s 大举迁入%s！" % [species_name, region["name"]])
			if region["alive"] >= region["capacity"]:
				_emit(events, "full:%s" % rid, "%s 种群饱和，扩张在即" % region["name"])
	_global_totals = totals
	_region_species = regions_state
	return events


## 同类事件节流：冷却窗口内只播一次
func _emit(events: Array[String], key: String, text: String) -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	if now - float(_cooldowns.get(key, -9999.0)) < EVENT_COOLDOWN:
		return
	_cooldowns[key] = now
	events.append(text)
