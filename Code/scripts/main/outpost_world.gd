## 首章作者场景。表现层只保留静态对象与账本投影，证据/任务物品均由任务层权威处理。
## 围墙、建筑底座与碎石障碍统一由 ObstacleField→ObstacleTileLayer 铺设。
class_name OutpostWorld
extends Node2D

var state: Dictionary = {}
var objects_by_id: Dictionary = {}
var _ground: OutpostGround


func _ready() -> void:
	name = "OutpostWorld"
	add_to_group("outpost_world")
	y_sort_enabled = true
	var ground := OutpostGround.new()
	_ground = ground
	ground.position = OutpostLayout.center()
	ground.z_index = -1
	add_child(ground)
	for building: Dictionary in OutpostLayout.structures():
		var base := Node2D.new()
		base.name = str(building["id"])
		base.position = building["position"]
		var sprite := Sprite2D.new()
		sprite.texture = load("res://assets/ts/structures_baked/%s.png" % building["asset"])
		sprite.offset = Vector2(0, -sprite.texture.get_height() / 2.0)
		base.add_child(sprite)
		add_child(base)
	# 门旗和存货都依附已有实心格；只补人类据点的可读性，不增加暗墙或路程。
	for offset: Vector2 in [Vector2(-64,512), Vector2(64,512), Vector2(-608,-256), Vector2(-608,-64)]:
		var flag := StationDressing.new()
		flag.position = OutpostLayout.center() + offset
		flag.kind = "flag"
		add_child(flag)
	for offset: Vector2 in [Vector2(256,0), Vector2(352,0), Vector2(480,0)]:
		var shelf := StationDressing.new()
		shelf.position = OutpostLayout.center() + offset
		shelf.kind = "shelf"
		add_child(shelf)
	var cot := StationDressing.new()
	cot.position = OutpostLayout.center() + Vector2(-448,-208)
	cot.kind = "bedroll"
	add_child(cot)
	for item: Dictionary in OutpostLayout.objects():
		var prop := OutpostObject.new()
		prop.name = str(item["id"])
		prop.outpost_id = str(item["id"])
		prop.title = str(item["title"])
		prop.kind = str(item["kind"])
		prop.interaction_label = str(item["interaction_label"])
		prop.position = item["position"]
		add_child(prop)
		objects_by_id[prop.outpost_id] = prop
	EventBus.outpost_state_changed.connect(refresh_state)
	EventBus.quest_list_changed.connect(_on_quest_list_changed)
	refresh_state(state)


## 巡守、路标与可读记录保留；已取走的散落物整件隐藏，底座不再伪装成拾取目标。
func refresh_state(next_state: Dictionary) -> void:
	state = next_state.duplicate(true)
	if is_instance_valid(_ground): _ground.refresh_state(state.get("evidence", state))
	for prop: OutpostObject in objects_by_id.values():
		prop.refresh_state(state)


func _on_quest_list_changed(quests: Array, tracked_id: String) -> void:
	var previous := str(state.get("target_object_id", ""))
	var target_id := ""
	for quest: Dictionary in quests:
		if quest.get("id", "") == tracked_id and quest.get("kind", "") == "outpost":
			target_id = str(quest.get("target_object_id", ""))
	if previous == target_id: return
	state["target_object_id"] = target_id
	# 跟踪变化只刷新新旧目标，不重建全部场景或重复投影世界几何。
	for id: String in [previous, target_id]:
		if objects_by_id.has(id): objects_by_id[id].refresh_state(state)


func object_node(id: String) -> Node2D:
	return objects_by_id.get(id)


class OutpostObject extends Node2D:
	const PATROL_FRAMES := preload("res://assets/creatures/frames/npc_watchman/npc_watchman_frames.res")
	const BAG := preload("res://assets/ts/icons/bag.png")
	const TOOLS := preload("res://assets/ts/icons/knock_axe.png")
	const BED := preload("res://assets/ts/structures_baked/bed.png")
	var outpost_id := ""
	var title := ""
	var context_title := ""
	var kind := ""
	var interaction_label := "调查"
	var rescued := false
	var repaired := false
	var taken := false
	var read := false
	var affordance_state := "available"
	var _tracked := false
	var state: Dictionary = {}
	var _label: Label
	var _patrol: AnimatedSprite2D
	var _near := false
	var _poll := 0.0

	func _ready() -> void:
		add_to_group("npcs")
		add_to_group("outpost_objects")
		if kind == "patrol":
			_patrol = AnimatedSprite2D.new()
			_patrol.name = "PatrolVisual"
			_patrol.sprite_frames = PATROL_FRAMES
			_patrol.scale = Vector2(2, 2)
			_patrol.play("idle")
			add_child(_patrol)
		_label = Label.new()
		_label.name = "ObjectLabel"
		_label.position = Vector2(-150, -86 if kind == "patrol" else -62)
		_label.size = Vector2(300, 30)
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_label.add_theme_font_size_override("font_size", 18)
		_label.add_theme_color_override("font_color", Color("f1dfb9"))
		_label.add_theme_color_override("font_outline_color", Color("26332d"))
		_label.add_theme_constant_override("outline_size", 4)
		add_child(_label)
		refresh_state({})

	func refresh_state(snapshot: Dictionary) -> void:
		var evidence: Dictionary = snapshot.get("evidence", snapshot)
		state = evidence.duplicate(true)
		title = str(OutpostLayout.OBJECTS[outpost_id]["title"])
		interaction_label = str(OutpostLayout.OBJECTS[outpost_id]["interaction_label"])
		rescued = bool(evidence.get("rescued", false))
		repaired = bool(evidence.get("signpost_repaired", false))
		taken = bool(evidence.get("aid_taken" if kind == "aid" else "tools_taken", false)) if kind in ["aid", "tools"] else false
		var read_key: String = {"patrol_record":"patrol_read", "entrance_record":"entrance_read", "supply_record":"supply_read"}.get(outpost_id, "")
		read = not str(read_key).is_empty() and bool(evidence.get(read_key, false))
		affordance_state = str(snapshot.get("object_states", {}).get(outpost_id, "taken" if taken else ("read" if read else "available")))
		_tracked = str(snapshot.get("target_object_id", "")) == outpost_id
		visible = not taken
		if taken: _near = false
		if kind == "patrol":
			title = "前哨巡守" if rescued else "受伤的前哨巡守"
			interaction_label = "交谈" if rescued or not evidence.get("aid_taken", false) else "救治巡守"
			if _patrol != null:
				_patrol.rotation = 0.0 if rescued else -PI / 2.0
				_patrol.scale = Vector2(2,2) if rescued else Vector2(1.65,1.65)
				_patrol.position = Vector2(0, -4) if rescued else Vector2(0, -12)
				_patrol.modulate = Color.WHITE if rescued else Color("c9b8ab")
		elif kind == "signpost":
			title = "前哨路标 · 已修复" if repaired else "损坏的前哨路标"
			interaction_label = "查看路标" if repaired else "修复路标"
		elif read:
			title += " · 已读"
			interaction_label = "重读"
		context_title = title.get_slice(" · ", 0)
		if affordance_state == "ready": title += " · 待领取"
		elif affordance_state == "claimed": title += " · 已领取"
		elif _tracked and not taken and not read: title = "! " + title
		if _label != null:
			_label.text = title
		queue_redraw()

	func _process(delta: float) -> void:
		if not visible: return
		_poll += delta
		if _poll < 0.16:
			return
		_poll = 0.0
		var player := get_tree().get_first_node_in_group("player") as Node2D
		var nearby := player != null and player.visible and global_position.distance_to(player.global_position) < 260.0
		var label_was_visible := _label.visible
		_label.visible = nearby and is_observed(player.global_position)
		var now_near := can_interact()
		if now_near != _near or label_was_visible != _label.visible:
			_near = now_near
			queue_redraw()

	## 精确对象线索只在当前视野内有效；不能隔墙或沿旧探索记录远程显形。
	func is_observed(from: Vector2) -> bool:
		if not is_visible_in_tree() or from.distance_to(global_position) > 680.0:
			return false
		var viewport := get_viewport()
		if viewport.get_camera_2d() != null and not viewport.get_visible_rect().has_point(viewport.get_canvas_transform() * global_position):
			return false
		var delta := global_position - from
		var steps := maxi(1, ceili(delta.length() / 12.0))
		for i in range(1, steps):
			if ObstacleField.blocks(from + delta * float(i) / float(steps), 0.0):
				return false
		return true

	func can_interact() -> bool:
		if not is_visible_in_tree() or is_queued_for_deletion():
			return false
		var player := get_tree().get_first_node_in_group("player") as Node2D
		if player == null or not player.is_visible_in_tree() or player.global_position.distance_to(global_position) > OutpostLayout.INTERACT_DISTANCE:
			return false
		if not is_observed(player.global_position):
			return false
		# 现场物理射线额外覆盖其它模块合法建立的实体碰撞。
		var query := PhysicsRayQueryParameters2D.create(player.global_position, global_position, 1)
		if player is CollisionObject2D:
			query.exclude = [player.get_rid()]
		return get_world_2d().direct_space_state.intersect_ray(query).is_empty()

	func interact() -> void:
		if can_interact():
			EventBus.outpost_interaction_requested.emit(outpost_id)

	func _draw() -> void:
		if taken: return
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1, 0.38))
		draw_circle(Vector2.ZERO, 20 if kind == "patrol" else 15, Color(0.08, 0.12, 0.11, 0.24))
		draw_set_transform(Vector2.ZERO)
		match kind:
			"record":
				# 掉落的纸页贴地，不是有奖励的通用宝箱。
				draw_rect(Rect2(-14, -12, 28, 18), Color("80674d"))
				draw_rect(Rect2(-11, -16, 24, 21), Color("e6d6a6"))
				draw_rect(Rect2(-8, -13, 18, 2), Color("967958"))
				for y in [-8, -3]:
					draw_rect(Rect2(-8, y, 14, 2), Color("967958"))
				draw_rect(Rect2(7, 0, 6, 5), Color("416b88"))
			"patrol":
				if not rescued:
					draw_texture_rect(BED, Rect2(-38, -28, 76, 48), false)
				else:
					draw_circle(Vector2(0, 0), 12, Color(0.45, 0.74, 0.59, 0.22))
			"aid":
				draw_rect(Rect2(-26, -14, 52, 27), Color("7e684d"))
				if not taken:
					draw_texture_rect(BAG, Rect2(-20, -41, 40, 40), false)
					draw_rect(Rect2(-10, -21, 20, 13), Color("e9d8b2"))
					draw_rect(Rect2(-2, -19, 4, 9), Color("963d42"))
					draw_rect(Rect2(-6, -16, 12, 3), Color("963d42"))
			"tools":
				draw_rect(Rect2(-28, -13, 56, 25), Color("725c43"))
				if not taken:
					draw_rect(Rect2(-20, -9, 40, 7), Color("ba9360"))
					draw_rect(Rect2(-17, 0, 37, 5), Color("a78456"))
					draw_texture_rect(TOOLS, Rect2(-21, -43, 42, 42), false)
			"signpost":
				_draw_sign()
			"survey":
				draw_arc(Vector2.ZERO, 24, 0, TAU, 16, Color("b8b89d"), 3.0)
				draw_line(Vector2(-18, 0), Vector2(18, 0), Color("d0b981"), 2.0)
				draw_line(Vector2(0, -18), Vector2(0, 18), Color("d0b981"), 2.0)
				draw_circle(Vector2.ZERO, 4, Color("657b72"))
		if _near:
			draw_arc(Vector2(0, 8), 28, 0, PI, 16, Color("a2bbb0") if read else Color("ead29a"), 2.0)
		if _tracked and _label != null and _label.visible:
			draw_arc(Vector2(0, 8), 32, 0, TAU, 24, Color("ead29a"), 1.5)

	func _draw_sign() -> void:
		draw_rect(Rect2(-4, -48 if repaired else -25, 8, 48 if repaired else 25), Color("765641"))
		draw_rect(Rect2(-2, -48 if repaired else -25, 3, 46 if repaired else 23), Color("bb9866"))
		draw_set_transform(Vector2(0, -39 if repaired else -17), 0.0 if repaired else 0.48)
		var shape := PackedVector2Array([Vector2(-28,-9), Vector2(22,-9), Vector2(33,0), Vector2(22,9), Vector2(-28,9)])
		draw_colored_polygon(shape, Color("b08a57"))
		draw_polyline(shape + PackedVector2Array([shape[0]]), Color("664c37"), 2.0)
		draw_rect(Rect2(-21,-4,31,3), Color("4b645f") if repaired else Color("78654d"))
		draw_set_transform(Vector2.ZERO)
		if repaired:
			draw_rect(Rect2(7, -29, 14, 16), Color("4e8baf"))
			draw_rect(Rect2(11, -26, 6, 4), Color("d8c99c"))


## 小规模静态陈设。箱/木束落在同源货架格上；床卷是可踩的软铺盖。
class StationDressing extends Node2D:
	const WOOD := preload("res://assets/ts/Terrain/Resources/Wood/Wood Resource/Wood Resource.png")
	const FLOOR := preload("res://assets/ts/structures_baked/interior_floor.png")
	const BED := preload("res://assets/ts/structures_baked/bed.png")
	var kind := ""

	func _draw() -> void:
		match kind:
			"flag":
				draw_rect(Rect2(-3,-70,6,62),Color("6d5644"))
				draw_rect(Rect2(-1,-71,2,61),Color("c0a071"))
				draw_colored_polygon(PackedVector2Array([Vector2(2,-68),Vector2(28,-64),Vector2(23,-49),Vector2(3,-53)]),Color("477d98"))
				draw_line(Vector2(5,-65),Vector2(23,-62),Color("82b1b6"),2.0)
				draw_rect(Rect2(10,-61,5,7),Color("dbca93"))
			"shelf":
				draw_texture_rect(FLOOR,Rect2(-24,-31,48,32),false,Color("b1a386"))
				draw_rect(Rect2(-25,-31,50,4),Color("bd9465"))
				draw_rect(Rect2(-25,-2,50,4),Color("65513f"))
				draw_line(Vector2(-21,-25),Vector2(18,-5),Color("d1aa76"),4.0)
				draw_texture_rect(WOOD,Rect2(-31,-64,62,62),false)
			"bedroll":
				draw_texture_rect(BED,Rect2(-28,-18,56,35),false,Color("91a99e"))


class OutpostGround extends Node2D:
	var aid_taken := false
	var tools_taken := false

	func refresh_state(evidence: Dictionary) -> void:
		aid_taken = bool(evidence.get("aid_taken", false))
		tools_taken = bool(evidence.get("tools_taken", false))
		queue_redraw()

	func supply_pad_visible(id: String) -> bool:
		return not (aid_taken if id == "aid_bag" else tools_taken)

	const FLOOR := preload("res://assets/ts/structures_baked/interior_floor.png")

	func _draw() -> void:
		# 营地到前哨的淡旧路与札记同源，不在地图上泄露精确对象位置。
		var trail := OutpostLayout.path_to_front()
		for i in range(trail.size() - 1):
			_draw_path(trail[i] - position, trail[i + 1] - position)
		# 稀疏旧步道与补给木垫。没有大面积纯色地毯，保留原群系纹理。
		for line: Array in [
			[Vector2(0, 704), Vector2(0, 384)],
			[Vector2(-656, -160), Vector2(-240, -160)],
			[Vector2(-240, -160), Vector2(-192, 384)],
			[Vector2(-192, 384), Vector2(384, 416)],
			[Vector2(384, 416), Vector2(448, 160)],
			[Vector2(-224, -192), Vector2(-160, -464)],
			[Vector2(-160, -464), Vector2(448, -464)],
			[Vector2(448, -464), Vector2(448, -256)],
		]:
			_draw_path(line[0], line[1])
		for local: Vector2 in [Vector2(448,-320), Vector2(448,320), Vector2(-352,-192), Vector2(256,96)]:
			if local == Vector2(448,-320) and not supply_pad_visible("aid_bag"): continue
			if local == Vector2(448,320) and not supply_pad_visible("repair_tools"): continue
			for y in range(-1, 2):
				for x in range(-1, 2):
					draw_texture_rect(FLOOR, Rect2(local + Vector2(x * 24 - 12, y * 24 - 12), Vector2(24,24)), false, Color(0.85,0.91,0.87,0.75))
		# 入口拖痕以及西侧残墙旁的小路，都指向真实缺口。
		for i in 7:
			draw_rect(Rect2(-137 + i * 6, 556 - i * 10, 3, 12), Color(0.31,0.32,0.22,0.6))

	func _draw_path(start: Vector2, end: Vector2) -> void:
		var steps := maxi(1, ceili(start.distance_to(end) / 16.0))
		for i in steps:
			var point := start.lerp(end, float(i) / steps).snapped(Vector2(8,8))
			var spread := 16.0 + float(i % 3) * 4.0
			draw_rect(Rect2(point - Vector2(spread,12), Vector2(spread * 2,24)), Color(0.58,0.48,0.30,0.28))
			if i % 3 == 0:
				draw_rect(Rect2(point + Vector2(-8,4),Vector2(5,3)), Color(0.70,0.65,0.46,0.55))
