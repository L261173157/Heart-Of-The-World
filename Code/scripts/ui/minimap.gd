## 局部地形图：以玩家为中心、北向上。实时活体和巢穴只在当前视野内，
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
const VISIBLE_RADIUS := ExplorationFog.REVEAL_RADIUS
const QuestView := preload("res://scripts/ui/quest_presentation.gd")

var _terrain := MinimapTerrain.new()
var _exploration_seen: ExplorationFog
var _terrain_redraw := 0.0
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
var _quest_views: Array = []
var _seen_targets: Dictionary = {}
var _seen_target_identity: Dictionary = {}


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
	EventBus.quest_list_changed.connect(_on_quest_list_changed)
	EventBus.obstacle_destroyed.connect(_on_obstacle_destroyed)
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
		_seen_targets.clear()
		_seen_target_identity.clear()
	_sim_seen = WorldSim.sim
	_bounty_species = species_name
	_accum = REDRAW_INTERVAL


func _process(delta: float) -> void:
	if get_tree().paused:
		return
	if _has_player and _interior_index < 0:
		_terrain_redraw += delta
		if _terrain.step() > 0 and _terrain_redraw >= 0.10:
			_terrain_redraw = 0.0
			queue_redraw()
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
		_terrain.clear()
		_seen_targets.clear()
		_seen_target_identity.clear()
	_target = {}
	_interior_index = -1
	_markers.clear()
	var player := get_tree().get_first_node_in_group("player") as Node2D
	_has_player = player != null and player.visible and WorldSim.sim != null
	if _has_player:
		_player_pos = player.global_position
		_interior_index = ObstacleField.interior_index_at(_player_pos)
		if _interior_index >= 0:
			_terrain.clear()
			var exit_pos := ObstacleField.interior_pocket(_interior_index) + Vector2(0, 113)
			_target = {"id": "room_exit:%d" % _interior_index, "kind": "exit", "category": "室内出口",
				"name": "返回营地", "pos": exit_pos, "distance_px": _player_pos.distance_to(exit_pos)}
			_update_labels()
			queue_redraw()
			return
		if _exploration_seen != GameState.exploration:
			_exploration_seen = GameState.exploration
			_terrain.clear()
			_seen_targets.clear()
			_seen_target_identity.clear()
		var rect := _radar_rect()
		var extent := rect.size / _radar_scale()
		_terrain.prepare(Rect2(_player_pos - extent * 0.5, extent), GameState.world_seed,
			GameState.fog_version, _is_known_position,
			ExplorationFog.CELL if GameState.exploration.legacy.is_empty() else MinimapTerrain.CELL)
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
	var hidden_actors := {}
	# 表现层位置覆盖模拟出生点，追击、击退与迁徙不产生幽灵双点。
	for body in get_tree().get_nodes_in_group("monsters"):
		var monster := body as MonsterBase
		if monster != null and monster.inst != null and monster.inst.is_alive \
				and monster.state != MonsterBase.S_CORPSE and not monster.is_queued_for_deletion():
			if monster.is_visible_in_tree():
				live_positions[monster.inst.id] = monster.global_position
			else:
				hidden_actors[monster.inst.id] = true
	for inst: MonsterInstance in WorldSim.sim.instances.values():
		if not inst.is_alive or hidden_actors.has(inst.id):
			continue
		var pos: Vector2 = live_positions.get(inst.id, inst.spawn_pos)
		if not _is_visible_position(pos):
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
		if _is_visible_position(pos):
			result.append({"id": "nest:" + key, "kind": "nest", "pos": pos,
				"name": species.species_name + "巢穴", "species": species.species_name, "region_id": region.id})
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
	var tracked := _tracked_quests()
	if tracked.is_empty():
		return {}
	var quest: Dictionary = tracked[0]
	var id := str(quest.get("id", ""))
	var kind := str(quest.get("kind", ""))
	var stage := str(quest.get("chapter_stage", quest.get("camp_stage", "")))
	var guide_mode := str(quest.get("ui_guide_mode", ""))
	var returning := QuestView.requires_claim(quest) and int(quest.get("progress", 0)) >= int(quest.get("need", 1))
	# The quest ID survives reroutes and return stages; sight memory belongs to
	# the particular target, not to that long-lived quest ID.
	var identity := JSON.stringify([kind, quest.get("species", ""), quest.get("hunt_region", ""),
		quest.get("target_pos", []), quest.get("target_object_id", ""), stage, guide_mode, returning])
	if _seen_target_identity.get(id, "") != identity:
		_seen_targets.erase(id)
		_seen_target_identity[id] = identity
	if not returning and int(quest.get("progress", 0)) >= int(quest.get("need", 1)):
		_seen_targets.erase(id)
		return {}
	var best: Dictionary = {}
	var distance := INF
	for candidate: Dictionary in candidates:
		var position: Vector2 = candidate["pos"]
		if not _is_visible_position(position):
			continue
		var matches := false
		if returning:
			matches = str(candidate["id"]) == "landmark:" + str(quest.get("landmark_id", ""))
		elif kind == "outpost" and not str(quest.get("species", "")).is_empty():
			var same_population: bool = candidate.get("species", "") == quest.get("species", "") \
				and candidate.get("region_id", "") == quest.get("hunt_region", "")
			if guide_mode == "hunt":
				var candidate_id := str(candidate.get("id", ""))
				matches = same_population and candidate.get("kind", "") == "monster" \
					and bool(candidate.get("streamed", false)) \
					and candidate_id.begins_with("monster:") \
					and candidate_id.trim_prefix("monster:").to_int() in quest.get("target_instance_ids", [])
			else:
				# 调查/捣巢的目的地仍是真实巢穴，追过来的怪不能偷换这一行动目标。
				matches = same_population and candidate.get("kind", "") == "nest"
		elif kind == "camp_ecology":
			matches = candidate.get("species", "") == quest.get("species", "") \
				and candidate.get("region_id", "") == quest.get("hunt_region", "") \
				and candidate.get("kind", "") in ["monster", "nest"]
		elif kind == "hunt":
			matches = candidate.get("kind", "") == "monster" and candidate.get("species", "") == quest.get("species", "") \
				and (quest.get("hunt_region", "") == "" or candidate.get("region_id", "") == quest["hunt_region"])
		elif kind == "ransack":
			matches = candidate.get("kind", "") == "nest"
		elif kind == "collect":
			matches = candidate.get("kind", "") == "monster" and EconomyMath.material_for(str(candidate.get("species", ""))) == quest.get("item", "")
		var candidate_distance := _player_pos.distance_to(position)
		if matches and candidate_distance < distance:
			best = candidate.duplicate(true)
			distance = candidate_distance
	if not best.is_empty():
		best["category"] = "当前视野 · 交付" if returning else "当前视野 · 委托"
		if returning:
			best["name"] = str(quest.get("giver", best.get("name", "委托人")))
		best["distance_px"] = distance
		best["precise"] = true
		_seen_targets[id] = best.duplicate(true)
		return best
	if kind == "outpost" and guide_mode == "hunt" and _seen_targets.has(id):
		# 只保留确实看见过的坐标；不拿当前隐藏演员位置刷新箭头，也不把
		# 稳定巢址伪装成那只离巢个体的最后目击位置。
		var last_seen: Dictionary = _seen_targets[id].duplicate(true)
		last_seen["category"] = "最后所见 · 待核实"
		last_seen["precise"] = false
		last_seen["knowledge"] = "last_seen"
		return last_seen
	# The tracked quest may provide a coarse NPC clue, never a hidden live actor.
	var clue: Variant = quest.get("target_pos", [])
	if returning and (not clue is Array or clue.is_empty()):
		var giver_id := str(quest.get("landmark_id", ""))
		if giver_id in GameState.discovered_landmarks:
			var giver := LandmarkRegistry.landmark(giver_id)
			if not giver.is_empty():
				var giver_pos: Vector2 = giver["pos"]
				clue = [giver_pos.x, giver_pos.y]
	if clue is Array and clue.size() == 2:
		var position := Vector2(float(clue[0]), float(clue[1]))
		var visible := _is_visible_position(position)
		var remembered := str(quest.get("ui_knowledge", "npc_intel")) == "last_seen" or _seen_targets.has(id)
		var label := str(quest.get("target_name", "前哨线索")) if kind == "outpost" else ("返回营地" if returning or stage == "return" else "调查据点")
		return {"id": "quest_clue:" + id, "kind": "clue", "name": label,
			"category": "当前视野 · 委托" if visible else ("最后所见 · 线索" if remembered else "居民情报 · 区域"),
			"pos": position, "distance_px": _player_pos.distance_to(position), "precise": visible,
			"knowledge": "visible" if visible else ("last_seen" if remembered else "npc_intel")}
	if _seen_targets.has(id):
		var remembered: Dictionary = _seen_targets[id].duplicate(true)
		remembered["category"] = "最后所见 · 待核实"
		remembered["precise"] = false
		remembered["knowledge"] = "last_seen"
		return remembered
	return {}


func _on_quest_list_changed(quests: Array, _tracked_id: String) -> void:
	_quest_views = quests.duplicate(true)
	_accum = REDRAW_INTERVAL


func _tracked_quests() -> Array:
	# No auto-fallback to another quest, bounty, enemy or discovered landmark.
	var tracked_id := GameState.tracked_quest_id
	if tracked_id.is_empty() or tracked_id == "__untracked__":
		return []
	for quest: Dictionary in _quest_views:
		if str(quest.get("id", "")) == tracked_id:
			return [quest]
	for quest: Dictionary in GameState.quests.get("active", []):
		if str(quest.get("id", "")) == tracked_id:
			return [quest]
	return []


func _is_known_position(pos: Vector2) -> bool:
	if not pos.is_finite() or not Rect2(Vector2.ZERO, WorldConfig.WORLD_SIZE).has_point(pos):
		return false
	return GameState.fog_knows_position(pos)


func _is_visible_position(pos: Vector2) -> bool:
	if not _has_player or _interior_index >= 0 or not _is_known_position(pos) \
			or _player_pos.distance_squared_to(pos) > VISIBLE_RADIUS * VISIBLE_RADIUS:
		return false
	# Exploration memory is not current sight. Respect the live camera footprint
	# and opaque collision walls when a real world/camera is present.
	var viewport := get_viewport()
	if viewport.get_camera_2d() != null:
		if not viewport.get_visible_rect().has_point(viewport.get_canvas_transform() * pos):
			return false
		var player := get_tree().get_first_node_in_group("player") as Node2D
		if player != null and _player_pos.distance_squared_to(pos) > 0.0001:
			var query := PhysicsRayQueryParameters2D.create(_player_pos, pos, 1)
			if player is CollisionObject2D:
				query.exclude = [player.get_rid()]
			if not player.get_world_2d().direct_space_state.intersect_ray(query).is_empty():
				return false
	return true


func _on_obstacle_destroyed(cell: Vector2i, _pos: Vector2, _kind: String) -> void:
	_terrain.invalidate_obstacle(cell)
	_accum = REDRAW_INTERVAL


func _update_labels() -> void:
	if _category == null:
		return
	if _target.is_empty():
		_category.text = ("目标待发现" if not _tracked_quests().is_empty() else "未跟踪委托") if _has_player else "等待启程"
		_target_name.text = "点击查看地图" if _has_player else ""
		_direction.text = "北向上"
		_distance.text = "1格 = 32像素"
		return
	var category := str(_target["category"])
	_category.text = "上次目击" if category.begins_with("最后所见") else ("情报区域" if category.begins_with("居民情报") else ("交付目标" if category.ends_with("交付") else ("当前目标" if category.begins_with("当前视野") else category)))
	_target_name.text = _target["name"]
	_direction.text = _direction_text((_target["pos"] as Vector2) - _player_pos)
	# 格长来自实际地表网格，不把像素冒充米；近距离向上取整防止未到先显示 0。
	_distance.text = ("%d格 · 直线" % ceili(float(_target["distance_px"]) / ObstacleField.CELL)) if _target.get("precise", true) else "大致方位"


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
	var legend := [[54.0, Color.WHITE, "你"], [106.0, TARGET_COLOR, "委托"]]
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
		_draw_terrain_and_fog(rect)

	var center := rect.get_center()
	draw_line(Vector2(center.x, rect.position.y), Vector2(center.x, rect.end.y), Color(0.6, 0.75, 0.8, 0.15))
	draw_line(Vector2(rect.position.x, center.y), Vector2(rect.end.x, center.y), Color(0.6, 0.75, 0.8, 0.15))
	for marker: Dictionary in _markers:
		var point := _radar_point(marker["pos"])
		if marker["kind"] == "monster":
			draw_circle(point, 2.3, MONSTER_COLOR if not marker["ambient"] else Color("c1b6a0"))
		elif marker["kind"] == "nest":
			draw_arc(point, 2.5, 0, TAU, 8, Color("c8b489"), 1.0)
		else:
			draw_rect(Rect2(point - Vector2(2.5, 2.5), Vector2(5, 5)), OBJECTIVE_COLOR)
	if not _target.is_empty() and _target.get("precise", true):
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


## 显示已知地形而非统一蓝色底；当前视野亮、历史记忆暗，未知固定雾纹无真源采样。
func _draw_terrain_and_fog(rect: Rect2) -> void:
	var scale_px := MinimapTerrain.CELL * _radar_scale()
	var start := ExplorationFog.cell_of(_player_pos - rect.size * 0.5 / _radar_scale())
	var end := ExplorationFog.cell_of(_player_pos + rect.size * 0.5 / _radar_scale())
	var step := ExplorationFog.CELL * _radar_scale()
	# 粗地被先填满探索轮廓；精细水岸和障碍随后覆盖。旧地形记忆同样受细雾裁切。
	for y in range(start.y, end.y + 1):
		for x in range(start.x, end.x + 1):
			var pos := (Vector2(x, y) + Vector2.ONE * 0.5) * ExplorationFog.CELL
			var base := Vector2i((pos / MinimapTerrain.BASE_CELL).floor())
			if not _is_known_position(pos) or not _terrain.base_cells.has(base):
				continue
			var color: Color = _terrain.base_cells[base]
			var brightness := _terrain_brightness(pos)
			color = Color(color.r * brightness, color.g * brightness, color.b * brightness)
			var tile := Rect2(_radar_point(Vector2(x, y) * ExplorationFog.CELL), Vector2.ONE * (step + 0.2))
			draw_rect(tile.intersection(rect), color)
	for key: Vector2i in _terrain.cells:
		var pos := (Vector2(key) + Vector2.ONE * 0.5) * MinimapTerrain.CELL
		if not _is_known_position(pos):
			continue
		var brightness := _terrain_brightness(pos)
		var color: Color = _terrain.cells[key]["color"]
		color = Color(color.r * brightness, color.g * brightness, color.b * brightness)
		var tile := Rect2(_radar_point(Vector2(key) * MinimapTerrain.CELL), Vector2.ONE * (scale_px + 0.2))
		draw_rect(tile.intersection(rect), color)
	# 已知边缘的短线形成不规则海岸式雾沿，不能将未知格底色误画成地形。
	for y in range(start.y, end.y + 1):
		for x in range(start.x, end.x + 1):
			var pos := (Vector2(x, y) + Vector2.ONE * 0.5) * ExplorationFog.CELL
			if not _is_known_position(pos):
				# 薄雾颗粒完全由格坐标决定，不读取该处的群系/液体/障碍。
				if posmod(x * 7 + y * 11, 9) == 0:
					var mist := Rect2(_radar_point(pos) - Vector2.ONE * 0.4, Vector2.ONE * 0.8)
					if rect.encloses(mist):
						draw_rect(mist, Color("18242d"))
				continue
			var top_left := _radar_point(Vector2(x, y) * ExplorationFog.CELL)
			for edge: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
				if _is_known_position(pos + Vector2(edge) * ExplorationFog.CELL):
					continue
				var from := top_left
				var to := top_left
				if edge == Vector2i.UP or edge == Vector2i.DOWN:
					from.y += step if edge == Vector2i.DOWN else 0.0
					to = from + Vector2(step, 0)
				else:
					from.x += step if edge == Vector2i.RIGHT else 0.0
					to = from + Vector2(0, step)
				if rect.has_point(from) and rect.has_point(to):
					draw_line(from, to, Color("6c887a"), 0.75)
	var ring_radius := VISIBLE_RADIUS * _radar_scale()
	if ring_radius * 2.0 < minf(rect.size.x, rect.size.y):
		draw_arc(rect.get_center(), ring_radius, 0.0, TAU, 48, Color(0.73, 0.85, 0.76, 0.30), 0.75)


func _terrain_brightness(pos: Vector2) -> float:
	var distance := pos.distance_to(_player_pos)
	if distance > VISIBLE_RADIUS:
		return 0.37
	return lerpf(1.0, 0.70, smoothstep(VISIBLE_RADIUS - 240.0, VISIBLE_RADIUS, distance))
