## Official-Godot rendered fixtures, not timing/playtest evidence. Scene actions use
## real world/HUD APIs; teleport only stages the camera at the selected real nest.
## Run graphically with -- --size=1280x720 --out=/absolute/directory.
extends Node2D

var _world: Node
var _hud: CanvasLayer
var _player: Player
var _manager: QuestManager
var _out := "/tmp/camp-pilot-visual"
var _canvas := Vector2i(1280, 720)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.save_enabled = false
	GameState.reset_all()
	GameState.world_seed = BiomeMap.DEFAULT_SEED
	GameState.settings.screen_shake = false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		if arg.begins_with("--size="):
			var parts := arg.trim_prefix("--size=").split("x")
			_canvas = Vector2i(int(parts[0]), int(parts[1]))
	DirAccess.make_dir_recursive_absolute(_out)
	get_tree().root.content_scale_size = _canvas
	get_tree().root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	get_tree().root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	_run.call_deferred()

func _frames(count := 3) -> void:
	for i in count:
		await get_tree().process_frame

func _capture(label: String) -> void:
	await _frames(4)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := _out.path_join("%s-%dx%d.png" % [label, _canvas.x, _canvas.y])
	img.save_png(path)
	print("RENDERED_CAPTURE ", path, " pixels=", img.get_size())

func _touch(control: Control) -> void:
	var touch := InputEventScreenTouch.new()
	touch.index = 90
	touch.position = control.get_global_rect().get_center()
	touch.pressed = true
	get_viewport().push_input(touch, true)
	await _frames(1)
	touch = InputEventScreenTouch.new()
	touch.index = 90
	touch.position = control.get_global_rect().get_center()
	touch.pressed = false
	get_viewport().push_input(touch, true)
	await _frames(2)

func _run() -> void:
	_world = preload("res://scenes/main/main.tscn").instantiate()
	add_child(_world)
	_player = get_tree().get_first_node_in_group("player")
	_manager = get_tree().get_first_node_in_group("quest_manager")
	_hud = _world.get_node("HUD")
	await _frames(120)
	# Cold graphical startup can finish navigation prewarming after the world appears.
	# Do not label a pending-info screenshot as an available quest briefing.
	var ready_offer: Dictionary = {}
	for attempt in 1200:
		ready_offer = _manager.offer("camp_ecology", "camp_ecology", "营地巡守")
		if ready_offer.get("kind") == "quest":
			break
		await _frames(1)
	if ready_offer.get("kind") != "quest":
		push_error("Visual fixture could not obtain a real feasible camp offer")
		get_tree().quit(1)
		return
	var keeper: Node2D
	for npc in get_tree().get_nodes_in_group("npcs"):
		if npc.get("landmark_id") == "camp_ecology":
			keeper = npc
			break
	if keeper == null:
		push_error("Visual fixture has no camp giver")
		get_tree().quit(1)
		return
	_player.teleport_to(keeper.global_position + Vector2(50, 24))
	await _frames(3)
	await _capture("01-camp-controls")
	keeper.interact()
	await _capture("02-camp-briefing")
	_hud._close_dialogue()
	await _frames(3)
	var offered: Dictionary = _manager.offer("camp_ecology", "camp_ecology", "营地巡守")
	if offered.get("kind") == "quest":
		_manager.accept(offered["quest"])
	await _frames(4)
	await _capture("03-tracked-clue")
	_hud._open_task_list()
	await _capture("08-task-list-bounty")
	_hud._close_choice_layer()
	_hud._toggle_more()
	await _capture("04-more-abilities")
	_hud._toggle_more()
	_hud._toggle_pause()
	await _capture("05-main-menu")
	_hud._close_top_layer_or_toggle_pause()
	var target: Dictionary = _manager.camp_target()
	if target.is_empty():
		push_error("Visual fixture must not omit the branch stage")
		get_tree().quit(1)
		return
	if not target.is_empty():
		_player.teleport_to(target["position"] + Vector2(80, 0))
		await _frames(45)
		_manager.camp_investigate()
		await _capture("06-ecology-choice")
		var nest_option := _hud._dialogue_option_box.get_node_or_null("Branch_choose_ransack") as Button
		if nest_option == null or not nest_option.is_visible_in_tree():
			push_error("Visual fixture did not reach a real branch-choice surface")
			get_tree().quit(1)
			return
		await _touch(nest_option)
		await _capture("07-branch-confirmation")
		await _touch(_hud._dialogue_no)
		if str(GameState.camp_quest.get("choice", "")) != "":
			push_error("Returning from branch preview must not commit")
			get_tree().quit(1)
			return
	_hud._close_dialogue()
	print("=== CAMP PILOT RENDER COMPLETE ===")
	get_tree().quit()
