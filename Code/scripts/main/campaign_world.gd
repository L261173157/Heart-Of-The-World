## 《断开的守望》场景表现。实体由 CampaignLayout 派生，进度只投影账本快照。
class_name CampaignWorld
extends Node2D

var state: Dictionary = {}
var objects_by_id: Dictionary = {}
var sites_by_terrain: Dictionary = {}


func _ready() -> void:
	name = "CampaignWorld"
	add_to_group("campaign_world")
	y_sort_enabled = true
	for terrain: String in CampaignLayout.sites():
		if terrain == "plains":
			continue
		var site: Dictionary = CampaignLayout.sites()[terrain]
		var ground := CampaignGround.new()
		ground.name = "Ground_" + terrain
		ground.position = site.center
		ground.terrain = terrain
		ground.z_index = -1
		add_child(ground)
		sites_by_terrain[terrain] = ground
	for item: Dictionary in CampaignLayout.objects():
		var prop := CampaignObject.new()
		prop.name = str(item.id).replace(":","_")
		prop.campaign_id = str(item.id)
		prop.definition = item.duplicate(true)
		prop.title = str(item.title)
		prop.kind = str(item.kind)
		prop.interaction_label = str(item.interaction_label)
		prop.position = item.position
		add_child(prop)
		objects_by_id[prop.campaign_id] = prop
	EventBus.campaign_state_changed.connect(refresh_state)
	EventBus.quest_list_changed.connect(_on_quest_list_changed)
	refresh_state(state)


func refresh_state(next_state: Dictionary) -> void:
	state = next_state.duplicate(true)
	var changed := CampaignLayout.set_open_gates(state.get("open_gates",[]))
	if not changed.is_empty():
		ObstacleField.invalidate_authored_cells(changed)
		EventBus.campaign_geometry_changed.emit(changed)
	for prop: CampaignObject in objects_by_id.values():
		prop.refresh_state(state)
	for ground: CampaignGround in sites_by_terrain.values():
		ground.refresh_state(state)


func _on_quest_list_changed(quests: Array, tracked_id: String) -> void:
	var previous := str(state.get("target_object_id", ""))
	var target_id := ""
	for quest: Dictionary in quests:
		if quest.get("id", "") == tracked_id and quest.get("kind", "") == "campaign":
			target_id = str(quest.get("target_object_id", ""))
	if previous == target_id: return
	state["target_object_id"] = target_id
	# 跟踪变化只刷新新旧目标，不重建全部场景或重复投影世界几何。
	for id: String in [previous, target_id]:
		if objects_by_id.has(id): objects_by_id[id].refresh_state(state)


func object_node(id: String) -> Node2D:
	return objects_by_id.get(id)


class CampaignObject extends Node2D:
	const NPC_FRAMES := {
		"herbalist":preload("res://assets/creatures/frames/npc_herbalist/npc_herbalist_frames.res"),
		"watchman":preload("res://assets/creatures/frames/npc_watchman/npc_watchman_frames.res"),
		"scholar":preload("res://assets/creatures/frames/npc_scholar/npc_scholar_frames.res"),
		"merchant":preload("res://assets/creatures/frames/npc_merchant/npc_merchant_frames.res"),
		"hunter":preload("res://assets/creatures/frames/npc_hunter/npc_hunter_frames.res"),
		"keeper":preload("res://assets/creatures/frames/npc_keeper/npc_keeper_frames.res"),
	}
	const REUNION_NAMES := {"c2:liaison":"阿苇", "c3:survivor":"沈渡", "c4:map_keeper":"罗墨", "c5:leader":"韩铎"}
	const BAG := preload("res://assets/ts/icons/bag.png")
	const TOOLS := preload("res://assets/ts/icons/knock_axe.png")
	const SHELTER := preload("res://assets/ts/structures_baked/ts_house1.png")
	const BED := preload("res://assets/ts/structures_baked/bed.png")
	var campaign_id := ""
	var definition: Dictionary = {}
	var title := ""
	var context_title := ""
	var kind := ""
	var interaction_label := "调查"
	var rescued := false
	var repaired := false
	var taken := false
	var read := false
	var affordance_state := "available"
	var _has_current_action := false
	var _tracked := false
	var activated := false
	var gate_open := false
	var service := ""
	var _label: Label
	var _actor: AnimatedSprite2D
	var _near := false
	var _poll := 0.0

	func _ready() -> void:
		add_to_group("npcs")
		add_to_group("campaign_objects")
		if kind in ["npc","injured"]:
			_actor = AnimatedSprite2D.new()
			_actor.name = "CharacterVisual"
			_actor.sprite_frames = NPC_FRAMES.get(str(definition.get("portrait","watchman")),NPC_FRAMES.watchman)
			_actor.scale = Vector2(2,2)
			_actor.play("idle")
			add_child(_actor)
		_label = Label.new()
		_label.name = "ObjectLabel"
		_label.position = Vector2(-170,-88 if _actor != null else -72)
		_label.size = Vector2(340,30)
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_label.add_theme_font_size_override("font_size",18)
		_label.add_theme_color_override("font_color",Color("f1dfb9"))
		_label.add_theme_color_override("font_outline_color",Color("26332d"))
		_label.add_theme_constant_override("outline_size",4)
		add_child(_label)
		refresh_state({})

	func refresh_state(snapshot: Dictionary) -> void:
		title = str(definition.title)
		interaction_label = str(definition.interaction_label)
		rescued = bool(snapshot.get("rescued",{}).get(campaign_id,false))
		repaired = bool(snapshot.get("repaired",{}).get(campaign_id,false))
		taken = bool(snapshot.get("taken",{}).get(campaign_id,false))
		read = bool(snapshot.get("read",{}).get(campaign_id,false))
		affordance_state = str(snapshot.get("object_states",{}).get(campaign_id, "taken" if taken else ("read" if read else "available")))
		_has_current_action = snapshot.get("object_actions",{}).has(campaign_id)
		_tracked = str(snapshot.get("target_object_id", "")) == campaign_id
		activated = campaign_id in snapshot.get("active_runes",[])
		gate_open = campaign_id in snapshot.get("open_gates",[])
		service = ""
		position = definition.position
		var placement: Dictionary = snapshot.get("placements",{}).get(campaign_id,{})
		if not placement.is_empty():
			var point: Variant = placement.get("position",null)
			if point is Vector2:
				position = point
			elif point is Array and point.size() == 2:
				position = Vector2(float(point[0]),float(point[1]))
			service = str(placement.get("service",""))
			title = str(placement.get("title",title))
		var hidden := bool(definition.get("initial_hidden",false)) and placement.is_empty()
		if campaign_id == "ending:shelter":
			hidden = str(snapshot.get("ending","")) != "reunion" and placement.is_empty()
		if definition.has("instance_id"):
			hidden = str(snapshot.get("active_encounter", "")) != str(definition.instance_id)
		visible = not bool(placement.get("hidden",hidden))
		# 分批交付时隐藏尚未启用的作者任务，不能展示只有占位回复的居民。
		var batch := int(snapshot.get("enabled_batch",4))
		if (campaign_id.begins_with("side_") or campaign_id.begins_with("region_")) and batch<3: visible=false
		if (campaign_id.begins_with("random_") or campaign_id.begins_with("world_")) and batch<4: visible=false
		if batch<2 and campaign_id.begins_with("c") and not campaign_id.begins_with("c2:"): visible=false
		if kind == "injured" and rescued:
			title = title.trim_prefix("受伤的").trim_prefix("负伤的")
			interaction_label = "交谈"
			title += " · 已获救"
		if _actor != null:
			var wounded := kind == "injured" and not rescued
			_actor.rotation = -PI/2.0 if wounded else 0.0
			_actor.position = Vector2(0,-12) if wounded else Vector2(0,-4)
			_actor.scale = Vector2(1.65,1.65) if wounded else Vector2(2,2)
			_actor.modulate = Color("c9b8ab") if wounded else Color.WHITE
		context_title = title.get_slice(" · ", 0)
		if repaired:
			title += " · 已修复"
			interaction_label = "查看驻站"
		if taken:
			title += " · 已取空" if kind in ["aid", "parts", "cargo"] else " · 已取"
			interaction_label = ""
		elif read:
			title += " · 已读"
			interaction_label = "重读"
		if gate_open:
			title += " · 已开启"
		if not service.is_empty():
			title += " · " + service
			interaction_label = "驻站服务"
		if _has_current_action:
			interaction_label = str(snapshot.get("object_actions",{}).get(campaign_id, interaction_label))
		if affordance_state == "ready": title = "? " + title + " · 待领取"
		elif affordance_state == "claimed": title = "✓ " + title + " · 已领取"
		elif affordance_state == "completed": title = "✓ " + title
		elif _has_current_action and affordance_state == "available": title = "! " + title
		# 空容器保留为空箱；已取纸页没有可读内容，只有真正后续行动才保留目标。
		if taken and not _has_current_action and service.is_empty():
			_near = false
			if kind == "record": visible = false
		if _label != null:
			# 团聚四人间隔160px；完整身份/状态仍留在交互与目录，头顶只显示短姓名和服务。
			var reunited := str(snapshot.get("ending", "")) == "reunion" and REUNION_NAMES.has(campaign_id)
			_label.clip_text = reunited
			_label.text = str(REUNION_NAMES[campaign_id]) + " · 补给" if reunited else title
			_label.position.x = -70.0 if reunited else -170.0
			_label.size.x = 140.0 if reunited else 340.0
		queue_redraw()

	func _process(delta: float) -> void:
		if not visible:
			return
		_poll += delta
		if _poll < 0.16:
			return
		_poll = 0.0
		var player := get_tree().get_first_node_in_group("player") as Node2D
		if player == null:
			_label.visible = false
			return
		var nearby := player.visible and global_position.distance_squared_to(player.global_position) < 260.0 * 260.0
		var label_was_visible := _label.visible
		_label.visible = nearby and is_observed(player.global_position)
		var now_near := nearby and can_interact()
		if now_near != _near or label_was_visible != _label.visible:
			_near = now_near
			queue_redraw()

	## 已探索过不等于当前可见；精确目标只来自眼前的真实节点。
	func is_observed(from: Vector2) -> bool:
		if not is_visible_in_tree() or from.distance_squared_to(global_position) > 680.0 * 680.0:
			return false
		var viewport := get_viewport()
		if viewport.get_camera_2d() != null and not viewport.get_visible_rect().has_point(viewport.get_canvas_transform() * global_position):
			return false
		var delta := global_position - from
		var steps := maxi(1,ceili(delta.length()/12.0))
		for i in range(1,steps):
			if ObstacleField.blocks(from + delta * float(i)/float(steps),0.0):
				return false
		return true

	func can_interact() -> bool:
		if taken and not _has_current_action and service.is_empty(): return false
		if not is_visible_in_tree() or is_queued_for_deletion():
			return false
		var player := get_tree().get_first_node_in_group("player") as Node2D
		if player == null or not player.is_visible_in_tree() or player.global_position.distance_to(global_position) > CampaignLayout.INTERACT_DISTANCE:
			return false
		if not is_observed(player.global_position):
			return false
		var query := PhysicsRayQueryParameters2D.create(player.global_position,global_position,1)
		if player is CollisionObject2D:
			query.exclude = [player.get_rid()]
		return get_world_2d().direct_space_state.intersect_ray(query).is_empty()

	func interact() -> void:
		if can_interact():
			EventBus.campaign_interaction_requested.emit(campaign_id)

	func _draw() -> void:
		draw_set_transform(Vector2.ZERO,0.0,Vector2(1,0.38))
		draw_circle(Vector2.ZERO,20 if _actor != null else 17,Color(0.08,0.12,0.11,0.24))
		draw_set_transform(Vector2.ZERO)
		match kind:
			"record":
				draw_rect(Rect2(-16,-13,30,18),Color("795c43"))
				if taken:
					return
				draw_rect(Rect2(-12,-19,24,24),Color("e6d6a6"))
				for y in [-14,-9,-4]:
					draw_rect(Rect2(-8,y,15,2),Color("967958"))
				draw_rect(Rect2(6,0,6,5),Color("416b88"))
			"injured":
				if not rescued:
					draw_texture_rect(BED,Rect2(-38,-28,76,48),false)
			"aid", "parts", "cargo":
				_draw_crate()
			"rune":
				_draw_rune()
			"gate":
				# 真石门由同源障碍瓦片承担，这里是门前的解锁铭牌。
				draw_rect(Rect2(-23,-24,46,25),Color("787e70"))
				draw_rect(Rect2(-18,-21,36,3),Color("b2b9a0"))
				draw_circle(Vector2(0,-10),5,Color("81d3b8") if gate_open else Color("766552"))
			"shelter":
				draw_texture_rect(SHELTER,Rect2(-80,-176,160,160),false)
				draw_rect(Rect2(-30,-10,60,18),Color("87936e"))
			"flag":
				draw_rect(Rect2(-3,-58,6,62),Color("89623f"))
				draw_colored_polygon(PackedVector2Array([Vector2(3,-56),Vector2(31,-50),Vector2(23,-33),Vector2(3,-39)]),Color("5fab92") if repaired else Color("b89b66"))
			"beacon":
				_draw_beacon()
			"survey", "valve", "brazier":
				draw_arc(Vector2.ZERO,24,0,TAU,16,Color("b8b89d"),3)
				draw_line(Vector2(-18,0),Vector2(18,0),Color("d0b981"),3)
				draw_line(Vector2(0,-18),Vector2(0,18),Color("d0b981"),3)
		if _near:
			draw_arc(Vector2(0,8),28,0,PI,16,Color("a2bbb0") if read or affordance_state == "claimed" else Color("ead29a"),2)
		if _tracked and _label != null and _label.visible and (not taken or _has_current_action):
			draw_arc(Vector2(0,8),32,0,TAU,24,Color("ead29a"),1.5)

	func _draw_crate() -> void:
		draw_rect(Rect2(-28,-19,56,33),Color("705a42"))
		draw_rect(Rect2(-29,-21,58,7),Color("b48a5c"))
		for x in [-25,19]:
			draw_rect(Rect2(x,-15,6,29),Color("997346"))
		if taken:
			draw_rect(Rect2(-20,-12,40,16),Color("3c3e34"))
			return
		if kind == "aid":
			draw_texture_rect(BAG,Rect2(-20,-47,40,40),false)
			draw_rect(Rect2(-10,-23,20,15),Color("e9d8b2"))
			draw_rect(Rect2(-2,-21,4,11),Color("963d42"))
			draw_rect(Rect2(-6,-17,12,3),Color("963d42"))
		else:
			draw_texture_rect(TOOLS,Rect2(-21,-45,42,42),false)

	func _draw_rune() -> void:
		var color := Color("78d5c3") if activated else Color("9eb1a1")
		draw_colored_polygon(PackedVector2Array([Vector2(-21,5),Vector2(-17,-31),Vector2(0,-43),Vector2(18,-28),Vector2(22,6)]),Color("687869"))
		draw_line(Vector2(-15,-27),Vector2(0,-38),Color("a4b09b"),3)
		var origin := Vector2(0,-17)
		if campaign_id.ends_with("center"):
			draw_arc(origin,8,0,TAU,12,color,3)
			draw_circle(origin,3,color)
			return
		if campaign_id.ends_with("leaf"):
			draw_colored_polygon(PackedVector2Array([origin+Vector2(-9,5),origin+Vector2(-5,-7),origin+Vector2(8,-9),origin+Vector2(5,4)]),color)
			draw_line(origin+Vector2(-8,9),origin+Vector2(4,-5),Color("577560"),2)
			return
		if campaign_id.ends_with("stone"):
			draw_polyline(PackedVector2Array([origin+Vector2(0,-10),origin+Vector2(10,0),origin+Vector2(0,9),origin+Vector2(-10,0),origin+Vector2(0,-10)]),color,3)
			return
		if campaign_id.ends_with("lamp"):
			draw_rect(Rect2(origin+Vector2(-8,0),Vector2(16,4)),color)
			draw_line(origin+Vector2(0,-11),origin+Vector2(0,-2),color,4)
			draw_line(origin+Vector2(0,3),origin+Vector2(0,10),color,3)
			return
		var direction := Vector2.UP if campaign_id.ends_with("north") else (Vector2.RIGHT if campaign_id.ends_with("east") else Vector2.LEFT)
		draw_line(origin-direction*8,origin+direction*9,color,3)
		draw_line(origin+direction*9,origin+direction*3+direction.orthogonal()*5,color,3)
		draw_line(origin+direction*9,origin+direction*3-direction.orthogonal()*5,color,3)

	func _draw_beacon() -> void:
		draw_rect(Rect2(-24,-10,48,18),Color("778273"))
		draw_rect(Rect2(-7,-61,14,54),Color("876b46"))
		draw_rect(Rect2(-3,-61,4,54),Color("b89960"))
		draw_rect(Rect2(-22,-65,44,9),Color("a3a384"))
		draw_line(Vector2(-22,-65),Vector2(-13,-43),Color("77664f"),5)
		draw_line(Vector2(22,-65),Vector2(13,-43),Color("77664f"),5)
		if repaired:
			draw_circle(Vector2(0,-72),20,Color(0.39,0.82,0.77,0.16))
			draw_colored_polygon(PackedVector2Array([Vector2(-11,-66),Vector2(-6,-83),Vector2(2,-92),Vector2(8,-77),Vector2(12,-65)]),Color("8be2cc"))
			draw_line(Vector2(0,-70),Vector2(1,-83),Color("f0eebc"),4)
		else:
			draw_line(Vector2(-12,-70),Vector2(11,-65),Color("403c36"),5)


class CampaignGround extends Node2D:
	var terrain := ""
	var restored := false
	var ending := ""

	func refresh_state(snapshot: Dictionary) -> void:
		restored = bool(snapshot.get("repaired",{}).get("c%d:beacon" % ({"forest":2,"swamp":3,"hill":4,"snow":5,"lava":6}.get(terrain,1)),false))
		ending = str(snapshot.get("ending",""))
		queue_redraw()

	func _draw() -> void:
		# 路只作稀疏旧脚印，不用纯色大地毯盖掉真正群系。
		for path: PackedVector2Array in CampaignLayout.paths(terrain):
			for i in range(path.size()-1):
				_draw_path(path[i]-position,path[i+1]-position)
		for offset: Vector2 in [Vector2(-72,576),Vector2(72,576)]:
			_draw_flag(offset)
		if terrain == "forest":
			for segment: Array in [[Vector2(-512,448),Vector2(480,448)],[Vector2(-512,128),Vector2(512,128)],[Vector2(352,-224),Vector2(352,352)],[Vector2(160,-448),Vector2(160,224)]]:
				_draw_path(segment[0],segment[1])

	func _draw_path(a: Vector2,b: Vector2) -> void:
		var steps := maxi(1,int(a.distance_to(b)/36.0))
		var tint := Color(0.77,0.72,0.54,0.18) if terrain != "snow" else Color(0.39,0.49,0.52,0.22)
		for i in range(steps+1):
			var p := a.lerp(b,float(i)/float(steps))
			draw_rect(Rect2(p+Vector2(-17,-3),Vector2(12,6)),tint)
			draw_rect(Rect2(p+Vector2(5,6),Vector2(11,6)),tint)

	func _draw_flag(at: Vector2) -> void:
		draw_rect(Rect2(at+Vector2(-3,-65),Vector2(6,65)),Color("775d43"))
		draw_rect(Rect2(at+Vector2(-1,-65),Vector2(2,61)),Color("c0a071"))
		var flag := PackedVector2Array([at+Vector2(3,-64),at+Vector2(31,-58),at+Vector2(23,-43),at+Vector2(3,-49)])
		draw_colored_polygon(flag,Color("518e88") if restored else Color("637d83"))
		draw_line(at+Vector2(8,-58),at+Vector2(22,-54),Color("e2d6a5"),3)
