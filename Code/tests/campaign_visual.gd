## 实际引擎视觉夹具：读取验收存档，取景传送与冻结AI仅用于截图，不代表战斗/新手时长。
extends Node2D
var world: Node2D
var player: Player
var qm: QuestManager
var hud: CanvasLayer
var out := "/tmp/campaign-render"
var canvas := Vector2i(1280,720)
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.save_enabled = false
	GameState.settings.screen_shake = false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
		if arg.begins_with("--size="):
			var values := arg.trim_prefix("--size=").split("x")
			canvas = Vector2i(int(values[0]),int(values[1]))
	DirAccess.make_dir_recursive_absolute(out)
	get_tree().root.content_scale_size = canvas
	get_tree().root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	get_tree().root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	_run.call_deferred()
func _process(_delta: float) -> void:
	if world == null: return
	WorldSim.set_process(false)
	for actor: Node in get_tree().get_nodes_in_group("monsters"): actor.set_physics_process(false)
func _frames(n: int) -> void:
	for i in n: await get_tree().process_frame
func _capture(label: String) -> void:
	await _frames(5)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := out.path_join("%s-%dx%d.png" % [label,canvas.x,canvas.y])
	img.save_png(path)
	print("CAMPAIGN_CAPTURE ",path," ",img.get_size())
func _view(id: String, label: String) -> void:
	world._fade_teleport(player,CampaignLayout.object_position(id)+Vector2(0,54))
	await _frames(110)
	await _capture(label)
func _run() -> void:
	world = preload("res://scenes/main/main.tscn").instantiate()
	add_child(world)
	player = world.get_node("Player")
	hud = world.get_node("HUD")
	qm = get_tree().get_first_node_in_group("quest_manager")
	await _frames(100)
	await _view("c2:old_pact","01-old-pact")
	EventBus.campaign_interaction_requested.emit("c2:old_pact")
	await _capture("02-reading")
	hud._close_dialogue()
	await _view("c2:forest_gate","03-archive-gate")
	await _view("c2:liaison","04-liaison")
	await _view("c2:beacon","05-beacon")
	print("=== CAMPAIGN RENDER PASS ===")
	get_tree().quit()
