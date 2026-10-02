## 局部雷达：以玩家为中心、北向上。模拟活体补足流式圈外的附近怪群，
## 已探索迷雾/已发现地标仍是信息边界；不改探索、任务或生态状态。
class_name Minimap
extends Control

const REDRAW_INTERVAL := 0.25
const RADAR_RADIUS := 2400.0
const NEARBY_RADIUS := 6000.0
const ARRIVAL_RADIUS := 96.0
const TARGET_COLOR := Color("ffd166")
const MONSTER_COLOR := Color("ff8477")
const OBJECTIVE_COLOR := Color("75dcb8")
const QuestView := preload("res://scripts/ui/quest_presentation.gd")

var _accum := 0.0
var _sim_seen: EcologySim
var _bounty_species := ""
var _player_pos := Vector2.ZERO
var _has_player := false
var _interior_index := -1
var _target: Dictionary = {}
var _markers: Array[Dictionary] = []
var _camp_positions: Dictionary = {}
var _category: Label
var _target_name: Label
var _direction: Label
var _distance: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 不消费/清空全局 fog_dirty：局部窗只读少量格，读档、重置与同种子换档
	# 都无需依赖纹理缓存失效，也不会把另一个观察者的脏格吃掉。
	_category = _make_label("TargetCategory", 14, Color("a4c8d0"))
	_target_name = _make_label("TargetName", 16, Color.WHITE)
	_direction = _make_label("TargetDirection", 16, TARGET_COLOR)
	_distance = _make_label("TargetDistance", 14, Color("d9e3e4"))
	resized.connect(_layout_labels)
	EventBus.bounty_target_changed.connect(_on_bounty_target_changed)
	_layout_labels()
	_refresh_navigation()


func _make_label(node_name: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.name = node_name
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.clip_text = true
	add_child(label)
	return label


func _layout_labels() -> void:
	var left := _radar_rect().end.x + 10.0
	var width := maxf(0.0, size.x - left - 8.0)
	var labels: Array[Label] = [_category, _target_name, _direction, _distance]
	for i in labels.size():
		labels[i].position = Vector2(left, 25.0 + i * 21.0)
		labels[i].size = Vector2(width, 21.0)
	queue_redraw()


func _on_bounty_target_changed(species_name: String) -> void:
	# 信号携带语义，不从中文赏金文案反解析物种。
	if _sim_seen != WorldSim.sim:
		_camp_positions.clear()
	_sim_seen = WorldSim.sim
	_bounty_species = species_name
	_accum = REDRAW_INTERVAL


func _process(delta: float) -> void:
	if get_tree().paused:
		return
	_accum += delta
	if _accum >= REDRAW_INTERVAL:
		_accum = 0.0
		_refresh_navigation()


## 每轮从权威活体重选，击杀/捣巢/任务完成后最多一帧雷达周期移除旧指引。
## 约 880 个体只做坐标/距离过滤；不构建全世界营地纹理，不保留节点引用。
func _refresh_navigation() -> void:
	if _sim_seen != WorldSim.sim:
		_sim_seen = WorldSim.sim
		_bounty_species = ""
		_camp_positions.clear()
	_target = {}
	_interior_index = -1
	_markers.clear()
	var player := get_tree().get_first_node_in_group("player") as Node2D
	_has_player = player != null and player.visible and WorldSim.sim != null
	if _has_player:
		_player_pos = player.global_position
		_interior_index = ObstacleField.interior_index_at(_player_pos)
		if _interior_index >= 0:
			var exit_pos := ObstacleField.interior_pocket(_interior_index) + Vector2(0, 113)
			_target = {"id": "room_exit:%d" % _interior_index, "kind": "exit", "category": "室内出口",
				"name": "返回营地", "pos": exit_pos, "distance_px": _player_pos.distance_to(exit_pos)}
			_update_labels()
			queue_redraw()
			return
		var candidates := _known_candidates()
		_target = _select_target(candidates)
		for candidate: Dictionary in candidates:
			if _inside_radar(candidate["pos"]):
				_markers.append(candidate)
	_update_labels()
	queue_redraw()


func _known_candidates() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var live_positions := {}
	# 表现层位置覆盖模拟出生点，追击、击退与迁徙不产生幽灵双点。
	for body in get_tree().get_nodes_in_group("monsters"):
		var monster := body as MonsterBase
		if monster != null and monster.inst != null and monster.inst.is_alive \
				and monster.state != MonsterBase.S_CORPSE and not monster.is_queued_for_deletion():
			live_positions[monster.inst.id] = monster.global_position
	for inst: MonsterInstance in WorldSim.sim.instances.values():
		if not inst.is_alive:
			continue
		var pos: Vector2 = live_positions.get(inst.id, inst.spawn_pos)
		if not _is_known_position(pos):
			continue
		result.append({"id": "monster:%d" % inst.id, "kind": "monster", "pos": pos,
			"name": inst.species.species_name, "species": inst.species.species_name,
			"ambient": inst.species.ambient, "streamed": live_positions.has(inst.id), "region_id": inst.region_id})
	for key: String in WorldSim.sim.nests:
		if not bool(WorldSim.sim.nests[key].get("active", false)):
			continue
		var region: SimRegion = WorldSim.sim.regions.get(key.get_slice("|", 0))
		var species: SpeciesData = WorldSim.sim.find_species(key.get_slice("|", 1))
		if region == null or species == null:
			continue
		if not _camp_positions.has(key):
			_camp_positions[key] = WorldSim.sim.camp_pos(region, species)
		var pos: Vector2 = _camp_positions[key]
		if _is_known_position(pos):
			result.append({"id": "nest:" + key, "kind": "nest", "pos": pos,
				"name": species.species_name + "巢穴"})
	for id: String in GameState.discovered_landmarks:
		var lm := LandmarkRegistry.landmark(id)
		if not lm.is_empty():
			result.append({"id": "landmark:" + id, "kind": "landmark",
				"pos": lm["pos"], "name": lm["kind"]})
	var checkpoints := WorldConfig.checkpoints()
	for id: String in GameState.discovered_checkpoints:
		if checkpoints.has(id):
			var checkpoint: Dictionary = checkpoints[id]
			result.append({"id": "checkpoint:" + id, "kind": "checkpoint",
				"pos": checkpoint["position"], "name": checkpoint["name"]})
	return result


## 任务只指向已知、仍有效的对象。探索任务不泄露未发现地标；没有已知
## 任务线索时仍给附近活怪/已发现目的地，不让全世界随机赏金把雷达锁死。
func _select_target(candidates: Array[Dictionary]) -> Dictionary:
	var best: Dictionary = {}
	var best_priority := 99
	var best_distance := INF
	for candidate: Dictionary in candidates:
		var distance := _player_pos.distance_to(candidate["pos"])
		var priority := 99
		var category := ""
		var target_name := str(candidate["name"])
		for quest: Dictionary in _tracked_quests():
			if distance > NEARBY_RADIUS and (GameState.tracked_quest_id.is_empty() \
					or str(quest.get("id", "")) != GameState.tracked_quest_id):
				continue
			if int(quest.get("progress", 0)) >= int(quest.get("need", 1)):
				# 新收集单材料齐备但尚未交付：追踪已发现的委托人，不能当成
				# 自动结算单跳过，也不为返程指引揭露未发现地标。
				var giver_id := str(quest.get("landmark_id", ""))
				if QuestView.requires_claim(quest) and candidate["kind"] == "landmark" \
						and candidate["id"] == "landmark:" + giver_id \
						and giver_id in GameState.discovered_landmarks:
					priority = 0
					category = "委托 · 交付"
					target_name = str(quest.get("giver", candidate["name"]))
				continue
			if quest.get("kind", "") == "hunt" and candidate["kind"] == "monster" \
					and candidate["species"] == quest.get("species", "") \
					and (quest.get("hunt_region", "") == "" or candidate.get("region_id", "") == quest["hunt_region"]):
				priority = 0
				category = "委托 · 猎杀"
			elif quest.get("kind", "") == "ransack" and candidate["kind"] == "nest":
				priority = 0
				category = "委托 · 捣巢"
			elif quest.get("kind", "") == "collect" and candidate["kind"] == "monster" \
					and EconomyMath.material_for(candidate["species"]) == quest.get("item", ""):
				priority = 0
				category = "委托 · 材料"
		if priority > 0 and candidate["kind"] == "monster" and _bounty_species != "" \
				and candidate["species"] == _bounty_species \
				and distance <= (BountyManager.NEIGHBOR_RADIUS if not GameState.bounty.is_empty() else NEARBY_RADIUS) \
				and (GameState.bounty.is_empty() or candidate.get("region_id", "") == GameState.bounty.get("region_id", "")) \
				and (not GameState.bounty.has("target_ids") \
					or str(candidate["id"]).trim_prefix("monster:").to_int() in GameState.bounty["target_ids"]):
			priority = 1
			category = "赏金目标"
		if priority > 1 and candidate["kind"] == "monster" and not candidate["ambient"] \
				and distance <= NEARBY_RADIUS:
			priority = 2
			category = "附近敌人" if candidate["streamed"] else "附近怪群"
		if priority > 3 and candidate["kind"] in ["landmark", "checkpoint"] and distance > ARRIVAL_RADIUS:
			priority = 3
			category = "已发现地标" if candidate["kind"] == "landmark" else "已发现营地"
		if priority < best_priority or (priority == best_priority and distance < best_distance):
			if priority == 99:
				continue
			best = candidate.duplicate()
			best["category"] = category
			best["name"] = target_name
			best["distance_px"] = distance
			best_priority = priority
			best_distance = distance
	return best


## 只有选中的委托能抢占自动附近目标；兼容缺少追踪字段的旧存档首单。
func _tracked_quests() -> Array:
	var active: Array = GameState.quests.get("active", [])
	for quest: Dictionary in active:
		if str(quest.get("id", "")) == GameState.tracked_quest_id:
			return [quest]
	return [active[0]] if not active.is_empty() else []


func _is_known_position(pos: Vector2) -> bool:
	if not pos.is_finite() or not Rect2(Vector2.ZERO, WorldConfig.WORLD_SIZE).has_point(pos):
		return false
	var cell := GameState.fog_cell_of(pos)
	return GameState.fog_is_explored(cell.x, cell.y)


func _update_labels() -> void:
	if _category == null:
		return
	if _target.is_empty():
		_category.text = "附近暂无目标" if _has_player else "等待启程"
		_target_name.text = "继续探索" if _has_player else ""
		_direction.text = "北向上"
		_distance.text = "1格 = 32像素"
		return
	_category.text = _target["category"]
	_target_name.text = _target["name"]
	_direction.text = _direction_text((_target["pos"] as Vector2) - _player_pos)
	# 格长来自实际地表网格，不把像素冒充米；近距离向上取整防止未到先显示 0。
	_distance.text = "%d格 · 直线" % ceili(float(_target["distance_px"]) / ObstacleField.CELL)


static func _direction_text(delta: Vector2) -> String:
	if delta.length() <= 24.0:
		return "就在附近"
	var directions := ["东", "东南", "南", "西南", "西", "西北", "北", "东北"]
	var index := posmod(roundi(delta.angle() / (PI / 4.0)), 8)
	return "向" + directions[index]


func _radar_rect() -> Rect2:
	return Rect2(6, 25, maxf(1.0, size.x * 0.44 - 2.0), maxf(1.0, size.y - 32.0))


func _radar_scale() -> float:
	if _interior_index >= 0:
		return _radar_rect().size.y / 480.0
	return _radar_rect().size.y / (RADAR_RADIUS * 2.0)


func _radar_point(pos: Vector2) -> Vector2:
	return _radar_rect().get_center() + (pos - _player_pos) * _radar_scale()


func _inside_radar(pos: Vector2) -> bool:
	return _radar_rect().grow(-5.0).has_point(_radar_point(pos))


## 超出局部窗的已知目标仍沿真实方位落在边框内，不伪装成近处怪点。
func _target_marker_position(pos: Vector2) -> Vector2:
	var rect := _radar_rect().grow(-7.0)
	var center := rect.get_center()
	var delta := _radar_point(pos) - center
	var half := rect.size * 0.5
	var factor := maxf(absf(delta.x) / half.x, absf(delta.y) / half.y)
	return center + delta / maxf(1.0, factor)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("14242bed"))
	draw_rect(Rect2(Vector2.ZERO, size), Color("7a8f85"), false, 1.0)
	var font := get_theme_default_font()
	draw_string(font, Vector2(8, 18), "附近", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("a4c8d0"))
	var legend := [[54.0, Color.WHITE, "你"], [94.0, MONSTER_COLOR, "怪"],
		[134.0, OBJECTIVE_COLOR, "地标"], [191.0, TARGET_COLOR, "目标"]]
	for item: Array in legend:
		draw_circle(Vector2(item[0], 13), 2.5, item[1])
		draw_string(font, Vector2(item[0] + 6, 18), item[2], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("d9e3e4"))
	var rect := _radar_rect()
	draw_rect(rect, Color("090f17"))
	if not _has_player:
		return
	if _interior_index >= 0:
		var room_center := ObstacleField.interior_pocket(_interior_index)
		var room_rect := Rect2(_radar_point(room_center - Vector2(160, 128)), Vector2(320, 256) * _radar_scale())
		draw_rect(room_rect.intersection(rect), Color("4e4436"))
		draw_rect(room_rect.intersection(rect), Color("b9a27d"), false, 1.0)
	else:
		# 只画局部窗相交的迷雾格，通常 4~9 格；不泄露未知地形、营地或地标。
		var step := WorldConfig.WORLD_SIZE.x / float(GameState.FOG_GRID)
		var world_start := _player_pos - rect.size * 0.5 / _radar_scale()
		var world_end := _player_pos + rect.size * 0.5 / _radar_scale()
		for gy in range(maxi(0, floori(world_start.y / step)), mini(GameState.FOG_GRID, ceili(world_end.y / step))):
			for gx in range(maxi(0, floori(world_start.x / step)), mini(GameState.FOG_GRID, ceili(world_end.x / step))):
				if GameState.fog_is_explored(gx, gy):
					var cell_rect := Rect2(_radar_point(Vector2(gx, gy) * step), Vector2.ONE * step * _radar_scale())
					draw_rect(cell_rect.intersection(rect), Color("294149"))
	var center := rect.get_center()
	draw_line(Vector2(center.x, rect.position.y), Vector2(center.x, rect.end.y), Color(0.6, 0.75, 0.8, 0.15))
	draw_line(Vector2(rect.position.x, center.y), Vector2(rect.end.x, center.y), Color(0.6, 0.75, 0.8, 0.15))
	for marker: Dictionary in _markers:
		var point := _radar_point(marker["pos"])
		if marker["kind"] == "monster":
			draw_circle(point, 2.3, MONSTER_COLOR if not marker["ambient"] else Color("c1b6a0"))
		elif marker["kind"] != "nest":
			draw_rect(Rect2(point - Vector2(2.5, 2.5), Vector2(5, 5)), OBJECTIVE_COLOR)
	if not _target.is_empty():
		var point := _target_marker_position(_target["pos"])
		var delta: Vector2 = (_target["pos"] as Vector2) - _player_pos
		if delta.length() > 24.0:
			var direction := delta.normalized()
			var side := direction.orthogonal()
			draw_line(center, point, Color(1, 0.82, 0.4, 0.55), 1.0)
			draw_colored_polygon(PackedVector2Array([point + direction * 5,
				point - direction * 4 + side * 3.5, point - direction * 4 - side * 3.5]), TARGET_COLOR)
		else:
			draw_arc(point, 6.0, 0, TAU, 16, TARGET_COLOR, 1.5)
	draw_circle(center, 4.5, Color("14242b"))
	draw_circle(center, 3.0, Color.WHITE)
	draw_string(font, rect.position + Vector2(4, 15), "北", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("d9e3e4"))
	draw_rect(rect, Color("58727c"), false, 1.0)
