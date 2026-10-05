## 图形模式证据：加载真实世界、玩家、敌人和CPU粒子，不是静态贴图拼装。
## 由成功命中/格挡/三连橙装事件抓帧；三屏比由外层启动器分别运行。
extends Node2D

const MAIN := preload("res://scenes/main/main.tscn")
const GOBLIN := preload("res://scenes/monsters/goblin.tscn")
var _world: Node2D
var _player: Player
var _target: MonsterBase
var _expected := ""
var _capturing := false
var _captured := false
var _output := ""
var _proof_viewport: SubViewport
var _proof_size := Vector2i(1280, 720)
var _visual_failed := false

func _ready() -> void:
	GameState.save_enabled = false
	GameState.reset_all()
	GameState.settings.auto_aim = false
	GameState.settings.screen_shake = false
	GameState.settings["equipment_particles_reduced"] = OS.get_environment("HOTW_EQUIPMENT_REDUCED") == "1"
	_output = OS.get_environment("HOTW_EQUIPMENT_SHOT_DIR")
	if _output.is_empty():
		_output = "/tmp/equipment-visual"
	DirAccess.make_dir_recursive_absolute(_output)
	var requested := OS.get_environment("HOTW_EQUIPMENT_SHOT_SIZE").split("x")
	if requested.size() == 2:
		_proof_size = Vector2i(int(requested[0]), int(requested[1]))
	_proof_viewport = SubViewport.new()
	_proof_viewport.name = "ExactSizeGameViewport"
	_proof_viewport.size = _proof_size
	_proof_viewport.world_2d = World2D.new()
	_proof_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_proof_viewport)
	# 云桌面窗口可能被平铺管理器强制改尺寸。游戏保持请求尺寸真渲染，桌面只缩放预览。
	var preview := TextureRect.new()
	preview.texture = _proof_viewport.get_texture()
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.size = get_viewport_rect().size
	add_child(preview)
	_world = MAIN.instantiate()
	_proof_viewport.add_child(_world)
	_player = get_tree().get_first_node_in_group("player") as Player
	_player.set_process(false)
	_run.call_deferred()

func _frames(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func _run() -> void:
	await get_tree().create_timer(1.5).timeout
	WorldSim.set_process(false) # 停生态时钟但保留权威sim；stop会清空sim。
	_world.set_process(false)
	for monster in get_tree().get_nodes_in_group("monsters"):
		monster.set_physics_process(false)
	var origin := WorldConfig.spawn_pos() + Vector2(420, 150)
	origin = ObstacleField.nudge_free(origin, 120.0)
	_player.teleport_to(origin)
	_player.current_hp = _player.stats.max_hp() * 0.65
	_player.current_mp = _player.stats.max_mp()
	_player.facing = Vector2.RIGHT
	_player.get_node("Camera2D").snap_to_player()
	var species: SpeciesData = load("res://data/species/goblin.tres").duplicate()
	var region: SimRegion = WorldSim.sim.region_of_point(origin)
	var inst := WorldSim.sim.spawn_instance(species, region.id, 200, 0, 1.0, false,
		origin + Vector2(51, 4))
	# 世界的正式spawn信号创建且setup同一个节点，避免额外手建未setup怪。
	await _frames(2)
	_target = _world._nodes.get(inst.id) as MonsterBase
	if _target == null:
		push_error("Equipment visual target failed to enter streamed world")
		get_tree().quit(1)
		return
	_target.global_position = origin + Vector2(51, 4)
	_target.current_hp = 10000.0
	_target.set_physics_process(false)
	_target.collision_mask = 0
	_target._nav.avoidance_enabled = false
	_target._begin_attack_warning(_player, 40.0, true)
	EventBus.equipment_particles_requested.connect(_on_burst)
	await _frames(8)
	Engine.time_scale = 0.3
	_expected = "hit"
	_player._try_attack()
	await _wait_capture()
	await get_tree().create_timer(0.5).timeout
	_expected = "block"
	_captured = false
	TouchInput.begin_guard()
	await get_tree().create_timer(0.12).timeout
	_player.take_damage(10.0, _target.global_position, "视觉验收",
		{"strength": 10.0, "incoming_direction": Vector2.RIGHT, "blockable": true,
		"attack_id": "equipment-visual-block"})
	await _wait_capture()
	TouchInput.cancel_guard()
	await get_tree().create_timer(0.5).timeout
	_player.stats.equips = {"weapon": {"mechanism": "combo", "base_id": "physical_sword",
		"rarity": 4, "item_level": 10, "rules_version": 1, "affixes": {}}}
	_player._combo = 2
	_player._combo_timer = 2.0
	_player._attack_cooldown = 0.0
	_expected = "orange"
	_captured = false
	_player._try_attack()
	await _wait_capture()
	Engine.time_scale = 1.0
	var layer := _world.get_node("EquipmentParticles") as EquipmentParticleLayer
	print("EQUIPMENT_VISUAL_PROOF ", layer.budget_snapshot(), " renderer=", RenderingServer.get_rendering_device())
	print("=== EQUIPMENT VISUAL %s ===" % ("FAIL" if _visual_failed else "PASS"))
	get_tree().quit(1 if _visual_failed else 0)

func _wait_capture() -> void:
	for _i in 300:
		if _captured:
			return
		await get_tree().process_frame
	push_error("Equipment visual capture timed out: " + _expected)
	get_tree().quit(1)

func _on_burst(kind: String, _pos: Vector2, _direction: Vector2) -> void:
	if kind != _expected or _capturing or _captured:
		return
	_capturing = true
	_capture.call_deferred(kind)

func _capture(kind: String) -> void:
	# 真粒子完成至少两次模拟提交后读回渲染图像，保持敌盾形危险提示同屏。
	await get_tree().create_timer(0.07).timeout
	await RenderingServer.frame_post_draw
	var viewport_size := _proof_viewport.get_visible_rect().size
	var tag := OS.get_environment("HOTW_EQUIPMENT_SHOT_TAG")
	if tag.is_empty():
		tag = "%dx%d" % [viewport_size.x, viewport_size.y]
	var suffix := "_reduced" if bool(GameState.settings.get("equipment_particles_reduced", false)) else ""
	var path := "%s/equipment_%s_%s%s.png" % [_output, tag, kind, suffix]
	var image := _proof_viewport.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("Equipment visual capture requires a real graphical renderer")
		get_tree().quit(1)
		return
	if image.get_size() != _proof_size:
		push_error("Equipment screenshot dimensions mismatch: %s != %s" % [image.get_size(), _proof_size])
		get_tree().quit(1)
		return
	var result := image.save_png(path)
	print("EQUIPMENT_SHOT ", path, " result=", result, " dimensions=", image.get_size())
	if kind == "orange" and OS.get_environment("HOTW_EQUIPMENT_PARTICLE_DIAGNOSTIC") == "1":
		await _capture_isolated_particles(path.trim_suffix(".png") + "_particles.png")
	_captured = result == OK
	_capturing = false


## 仅验收夹具：同一批真粒子冻结模拟并单独读回，不改变发行版表现。
func _capture_isolated_particles(path: String) -> void:
	var layer := _world.get_node("EquipmentParticles") as EquipmentParticleLayer
	layer.set_process(false)
	var hidden: Array[CanvasItem] = []
	for child in _world.get_children():
		if child == layer:
			continue
		_hide_other_visuals(child, hidden)
	for emitter in layer.get_children():
		emitter.speed_scale = 0.0
		if emitter.visible:
			print("EQUIPMENT_EMITTER_STATE visible=", emitter.is_visible_in_tree(),
				" emitting=", emitter.emitting, " position=", emitter.global_position,
				" screen=", emitter.get_global_transform_with_canvas().origin,
				" internal=", emitter.is_processing_internal(), " life=", emitter.lifetime)
	_proof_viewport.transparent_bg = true
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var proof := _proof_viewport.get_texture().get_image()
	proof.save_png(path)
	var visible_pixels := 0
	for y in proof.get_height():
		for x in proof.get_width():
			if proof.get_pixel(x, y).a > 0.01:
				visible_pixels += 1
	print("EQUIPMENT_PARTICLE_PIXELS ", visible_pixels, " path=", path)
	if visible_pixels <= 0:
		_visual_failed = true
		push_error("Actual CPU particles produced no rendered pixels")
		# 诊断分支不可当成功：分别验证显式模拟和局部坐标，定位引擎绘制/时序差异。
		for local in [false, true]:
			for emitter in layer.get_children():
				if not emitter.visible:
					continue
				emitter.local_coords = local
				emitter.restart(true)
				emitter.request_particles_process(0.07)
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var retry := _proof_viewport.get_texture().get_image()
			var retry_path := path.trim_suffix(".png") + ("_manual_local.png" if local else "_manual_global.png")
			retry.save_png(retry_path)
			var retry_pixels := 0
			for y in retry.get_height():
				for x in retry.get_width():
					if retry.get_pixel(x, y).a > 0.01:
						retry_pixels += 1
			print("EQUIPMENT_DIAGNOSTIC_MANUAL local=", local, " pixels=", retry_pixels)
	_proof_viewport.transparent_bg = false
	for child in hidden:
		child.show()
	for emitter in layer.get_children():
		emitter.speed_scale = 1.0
	layer.set_process(true)


func _hide_other_visuals(node: Node, hidden: Array[CanvasItem]) -> void:
	if node is CanvasItem:
		if node.visible:
			hidden.append(node)
			node.hide()
		return
	for child in node.get_children():
		_hide_other_visuals(child, hidden)
