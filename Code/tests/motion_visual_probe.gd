## 真实世界运动取证；不冻结物理、生态、AI、相机或 HUD。
extends Node
const MAIN := preload("res://scenes/main/main.tscn")
const GOBLIN := preload("res://scenes/monsters/goblin.tscn")
func _ready() -> void:
	GameState.save_enabled = false
	GameState.reset_all()
	GameState.world_seed = 20260908
	GameState.ecology_snapshot = null
	BiomeMap.configure(GameState.world_seed)
	_run.call_deferred()
func _v(value: Vector2) -> Array:
	return [value.x, value.y]
func _shift(actor: Node) -> Vector2:
	var sync := actor.get_node_or_null("RenderSync")
	return sync.render_shift if sync != null else Vector2.ZERO
func _counts(camera: Camera2D) -> Dictionary:
	var visible_count := 0
	var processing_count := 0
	var physics_count := 0
	var view := get_viewport().get_visible_rect()
	var actors := get_tree().get_nodes_in_group("monsters")
	for actor in actors:
		var point: Vector2 = actor.get_global_transform_with_canvas().origin + _shift(actor) * camera.zoom
		if view.has_point(point):
			visible_count += 1
		var sync := actor.get_node_or_null("RenderSync")
		if sync != null:
			processing_count += int(sync.is_processing())
			physics_count += int(sync.is_physics_processing())
	return {"spawned":actors.size(), "visible":visible_count, "render_callbacks":processing_count, "physics_callbacks":physics_count}
func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var out := OS.get_environment("HOTW_MOTION_OUT")
	var world := MAIN.instantiate()
	add_child(world)
	var player: Player = world.get_node("Player")
	var camera: Camera2D = player.get_node("Camera2D")
	for i in 90:
		await get_tree().process_frame
	# 真实子类消费迁徙状态机；场景其余 AI 与生态仍运行。
	var monster: MonsterBase = GOBLIN.instantiate()
	world.get_node("Monsters").add_child(monster)
	var inst := MonsterInstance.new()
	inst.id = 900001
	inst.species = load("res://data/species/goblin.tres")
	inst.spawn_pos = player.global_position + Vector2(0, 100)
	monster.setup(inst)
	monster._player_ref = player
	monster.on_migrate("", monster.global_position + Vector2(1200, 0))
	TouchInput.joystick_active = true
	TouchInput.move_vector = Vector2.RIGHT
	var start := player.global_position
	var monster_start := monster.global_position
	var index := 0
	var capture_index := 0
	var clip_index := 0
	var next_capture := 0.5
	var elapsed := 0.0
	var rows: Array = []
	var variable := OS.get_environment("HOTW_MOTION_CADENCE") == "variable"
	while elapsed < 3.0:
		if variable:
			Engine.max_fps = [45, 120, 75, 60][index % 4]
		await RenderingServer.frame_post_draw
		var delta := get_process_delta_time()
		elapsed += delta
		rows.append({"frame":index, "time":elapsed, "delta":delta,
			"physics_frame":Engine.get_physics_frames(), "fraction":Engine.get_physics_interpolation_fraction(),
			"body":_v(player.global_position), "visual":_v(player.visual.global_position),
			"render_shift":_v(_shift(player)), "render_visual":_v(player.visual.global_position + _shift(player)),
			"visual_screen":_v(player.visual.get_global_transform_with_canvas().origin + _shift(player) * camera.zoom),
			"camera":_v(camera.get_screen_center_position()),
			"animation":player.visual.animation, "pose":player.visual.frame, "pose_progress":player.visual.frame_progress,
			"monster_body":_v(monster.global_position), "monster_visual":_v(monster.visual.global_position),
			"monster_render_shift":_v(_shift(monster)), "monster_render_visual":_v(monster.visual.global_position + _shift(monster)),
			"monster_screen":_v(monster.visual.get_global_transform_with_canvas().origin + _shift(monster) * camera.zoom),
			"monster_pose":monster.visual.frame, "monster_progress":monster.visual.frame_progress,
			"monster_animation":monster.visual.animation, "ai_count":get_tree().get_nodes_in_group("monsters").size(),
			"counts":_counts(camera), "hud_visible":world.get_node("HUD/Root").visible})
		if elapsed >= 0.5 and elapsed <= 1.5:
			get_viewport().get_texture().get_image().save_png(out.path_join("clip_%03d.png" % clip_index))
			clip_index += 1
		if elapsed >= next_capture and capture_index < 12:
			get_viewport().get_texture().get_image().save_png(out.path_join("frame_%02d.png" % capture_index))
			capture_index += 1
			next_capture += 0.2
		index += 1
	TouchInput.reset()
	var result := {"rows":rows, "player_distance":player.global_position.distance_to(start),
		"monster_distance":monster.global_position.distance_to(monster_start),
		"viewport":_v(get_viewport().get_visible_rect().size), "captures":capture_index}
	var file := FileAccess.open(out.path_join("trace.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(result))
	file.close()
	print("=== MOTION VISUAL PASS: player=", result.player_distance, " monster=", result.monster_distance, " frames=", index, " ===")
	get_tree().quit()
