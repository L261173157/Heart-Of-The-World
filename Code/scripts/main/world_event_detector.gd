## 生态反馈纯观察者：快照判定存量变化，真实信号说明变化原因，不改模拟规则。
## 常规新闻只关心玩家所在区域；灭绝/复苏保留结构化事件供成就消费。
class_name WorldEventDetector
extends RefCounted

const EVENT_COOLDOWN := 30.0

var _initialized := false
var _global_totals := {}
var _region_species := {}
var _region_full := {}
var _permanent := {}
var _cooldowns := {}
var _boss_names := {}
## 一个 tick 内同类真实事件合并，避免每个个体各发一条新闻。
var _changes := {}
var _deaths := {}


func _init(p_boss_names: Array = []) -> void:
	for boss_name in p_boss_names:
		_boss_names[boss_name] = true


func record_spawn(species: String, region_id: String, generation: int, age: int) -> void:
	# 成年重引入不是出生，读档重放也不能从快照差分伪造出生。
	if generation > 0:
		_record("split", species, region_id)
	elif age == 0:
		_record("birth", species, region_id)


func record_migration(species: String, region_id: String) -> void:
	_record("migrate", species, region_id)


func record_death(species: String, region_id: String, cause: String) -> void:
	_deaths[species] = {"region_id": region_id, "cause": cause}
	if cause == EcologySim.DEATH_KILLED:
		_record("kill", species, region_id)


func _record(kind: String, species: String, region_id: String) -> void:
	if _boss_names.has(species):
		return
	var key := "%s|%s|%s" % [kind, region_id, species]
	if not _changes.has(key):
		_changes[key] = {"kind": kind, "species": species, "region_id": region_id, "count": 0}
	_changes[key]["count"] += 1


## context 只带观察数据：local_region_id / player_extinct / reintroduction_enabled。
## first snapshot 只建基线；空世界也算有效基线。priority 仅控制文本顺序，不改成就。
func detect_events(summary: Dictionary, context: Dictionary = {}) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var totals := {}
	var regions_state := {}
	var full_state := {}
	var local_id: String = context.get("local_region_id", "")
	var permanent: Dictionary = context.get("player_extinct", {})
	var can_recover: bool = context.get("reintroduction_enabled", true)
	for region: Dictionary in summary["regions"]:
		var rid: String = region["id"]
		regions_state[rid] = (region["species"] as Dictionary).duplicate()
		full_state[rid] = int(region["capacity"]) > 0 and int(region["alive"]) >= int(region["capacity"])
		for species: String in region["species"]:
			totals[species] = int(totals.get(species, 0)) + int(region["species"][species])
	if _initialized:
		var tracked := _global_totals.duplicate()
		for species: String in permanent:
			tracked[species] = tracked.get(species, 0)
		for species: String in tracked:
			if _boss_names.has(species):
				continue
			var newly_permanent := permanent.has(species) and not _permanent.has(species)
			if int(totals.get(species, 0)) == 0 and (int(tracked[species]) > 0 or newly_permanent):
				var player_caused := permanent.has(species)
				var text := "× %s 暂时消失，仍可能从世界边缘迁回" % species
				if player_caused:
					text = "× 你的猎杀使%s在本世界永久灭绝，不会自然复苏" % species
				elif not can_recover:
					text = "× %s 已消失，当前世界未启用自然复苏" % species
				var was_local := int((_region_species.get(local_id, {}) as Dictionary).get(species, 0)) > 0
				_append(events, "extinct", species, text, 100 if player_caused else (70 if was_local else 20))
				events.back()["permanent"] = player_caused
				events.back()["cause"] = "player" if player_caused else str(_deaths.get(species, {}).get("cause", "unknown"))
		for species: String in totals:
			if _boss_names.has(species):
				continue
			if int(totals[species]) > 0 and int(_global_totals.get(species, 0)) == 0:
				var is_local := int((regions_state.get(local_id, {}) as Dictionary).get(species, 0)) > 0
				_append(events, "revive", species, "%s 重返世界，现存%d只" % [species, totals[species]], 65 if is_local else 20)
		for change: Dictionary in _changes.values():
			var species: String = change["species"]
			var rid: String = change["region_id"]
			var kind: String = change["kind"]
			var count: int = change["count"]
			var total: int = totals.get(species, 0)
			if kind == "kill" and total > 0 and total < EcologySim.ENDANGERED_THRESHOLD:
				_emit(events, "endangered:" + species, "endangered", species,
					"你的猎杀后，%s全球仅剩%d只；杀光将永久灭绝" % [species, total], 90)
			if rid != local_id or local_id == "":
				continue
			match kind:
				"kill":
					var local_count: int = (regions_state.get(rid, {}) as Dictionary).get(species, 0)
					if local_count == 0 and total >= EcologySim.ENDANGERED_THRESHOLD:
						_emit(events, "cleared:" + species, "cleared", species,
							"猎杀后本区%s已清空，世界其他区域仍有%d只" % [species, total], 85)
				"split":
					_emit(events, "split:" + species, "split", species,
						"你的猎杀触发分裂：本区新增%d只%s子代" % [count, species], 80)
				"migrate":
					_emit(events, "migrate:" + rid, "migrate", species,
						"本区迁入%d只%s，族群正在扩张" % [count, species], 60)
				"birth":
					_emit(events, "birth:" + rid, "birth", species,
						"本区%s繁衍出%d只幼体" % [species, count], 40)
		if local_id != "" and bool(full_state.get(local_id, false)) and not bool(_region_full.get(local_id, false)):
			_emit(events, "full:" + local_id, "full", "", "本区种群已满，繁衍暂无空间", 10)
	_initialized = true
	_global_totals = totals
	_region_species = regions_state
	_region_full = full_state
	_permanent = permanent.duplicate()
	_changes.clear()
	_deaths.clear()
	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["priority"] > b["priority"])
	return events


static func species_status_text(species: String, count: int, player_extinct: Dictionary,
		is_boss := false, reintroduction_enabled := true) -> String:
	if count <= 0:
		if is_boss:
			return "等待重生"
		if player_extinct.has(species):
			return "玩家灭绝 · 本世界不会自然复苏"
		return "暂时消失 · 仍可能自然复苏" if reintroduction_enabled else "已消失 · 未启用自然复苏"
	if not is_boss and count < EcologySim.ENDANGERED_THRESHOLD:
		return "濒危 · 全球仅%d只，杀光将永久灭绝" % count
	return "全球%d只" % count


func _append(events: Array[Dictionary], kind: String, species: String, text: String, priority: int) -> void:
	events.append({"kind": kind, "species": species, "text": text, "priority": priority})


func _emit(events: Array[Dictionary], key: String, kind: String, species: String, text: String, priority: int) -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	if now - float(_cooldowns.get(key, -9999.0)) < EVENT_COOLDOWN:
		return
	_cooldowns[key] = now
	_append(events, kind, species, text, priority)
