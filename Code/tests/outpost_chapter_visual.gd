## 实际引擎截图夹具：取景使用传送，并冻结生态/敌人AI以固定画面。
## 只验布局、真实阅读交互与账本表现，不作实玩节奏或战斗难度证明。
extends Node2D

var _world: Node2D
var _player: Player
var _hud: CanvasLayer
var _qm: Node
var _out := "/tmp/outpost-chapter-visual"
var _canvas := Vector2i(1280, 720)
var _layout_only := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.save_enabled = false
	GameState.reset_all()
	GameState.world_seed = BiomeMap.DEFAULT_SEED
	GameState.settings.screen_shake = false
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--layout-only": _layout_only = true
		if arg.begins_with("--out="): _out = arg.trim_prefix("--out=")
		if arg.begins_with("--size="):
			var parts := arg.trim_prefix("--size=").split("x")
			_canvas = Vector2i(int(parts[0]), int(parts[1]))
	DirAccess.make_dir_recursive_absolute(_out)
	get_tree().root.content_scale_size = _canvas
	get_tree().root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	get_tree().root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	_run.call_deferred()

func _frames(count := 3) -> void:
	for i in count: await get_tree().process_frame

func _process(_delta: float) -> void:
	if _world == null: return
	WorldSim.set_process(false)
	for actor: Node in get_tree().get_nodes_in_group("monsters"):
		actor.set_physics_process(false)

func _capture(label: String) -> void:
	await _frames(5)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := _out.path_join("%s-%dx%d.png" % [label, _canvas.x, _canvas.y])
	img.save_png(path)
	print("OUTPOST_RENDERED_CAPTURE ", path, " pixels=", img.get_size())

func _view(position: Vector2, label: String) -> void:
	_player.teleport_to(position)
	await _frames(75)
	await _capture(label)

func _run() -> void:
	_world = preload("res://scenes/main/main.tscn").instantiate()
	EventBus.hint_requested.connect(func(message: String) -> void: print("OUTPOST_RENDER_HINT ", message))
	add_child(_world)
	WorldSim.set_process(false)
	_player = _world.get_node("Player")
	_hud = _world.get_node("HUD")
	_qm = get_tree().get_first_node_in_group("quest_manager")
	await _frames(120)
	if not _layout_only:
		await _chapter_views()
		return
	await _view(OutpostLayout.object_position("patrol_record") + Vector2(0, 56), "01-trail-record")
	await _view(OutpostLayout.entrances()["front"] + Vector2(0, 144), "02-front-approach")
	await _view(OutpostLayout.entrances()["side"] + Vector2(-80, 0), "03-side-approach")
	await _view(OutpostLayout.object_position("wounded_patrol") + Vector2(0, 56), "04-wounded-patrol")
	await _view(OutpostLayout.object_position("aid_bag") + Vector2(0, 56), "05-medical-supply")
	await _view(OutpostLayout.object_position("repair_tools") + Vector2(0, 56), "06-repair-supply")
	print("=== OUTPOST CHAPTER RENDER COMPLETE ===")
	get_tree().quit()

func _touch(control: Control) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 91
	event.position = control.get_global_rect().get_center()
	event.pressed = true
	get_viewport().push_input(event, true)
	await _frames(1)
	event = event.duplicate()
	event.pressed = false
	get_viewport().push_input(event, true)
	await _frames(3)

func _prop(id: String) -> Node2D:
	for node: Node in get_tree().get_nodes_in_group("outpost_objects"):
		if str(node.get("outpost_id")) == id: return node
	return null

func _action(id: String, capture_name := "") -> bool:
	_hud._close_dialogue()
	var prop := _prop(id)
	if prop == null: return _fail("缺少真实前哨物件：" + id)
	await _view(prop.global_position + Vector2(64, 40), "world-" + id)
	prop.interact()
	await _frames(3)
	if not _hud._dialogue_panel.visible: return _fail("真实物件未打开阅读：" + id)
	if capture_name != "": await _capture(capture_name)
	await _touch(_hud._dialogue_yes)
	print("OUTPOST_RENDER_ACTION ", id, " evidence=", GameState.outpost_quest.get("evidence", {}), " dialogue=", _hud._dialogue_panel.visible, " distance=", _player.global_position.distance_to(prop.global_position), " eligible=", prop.can_interact())
	return true

func _fail(message: String) -> bool:
	push_error(message)
	get_tree().quit(1)
	return false

func _chapter_views() -> void:
	var keeper: Node2D
	for npc: Node in get_tree().get_nodes_in_group("npcs"):
		if str(npc.get("landmark_id")) == "camp_ecology": keeper = npc
	if keeper == null:
		_fail("缺少真实营地巡守")
		return
	_player.teleport_to(keeper.global_position + Vector2(56, 32))
	await _frames(3)
	keeper.interact()
	await _capture("01-chapter-briefing")
	await _touch(_hud._dialogue_yes)
	if GameState.outpost_quest.is_empty():
		_fail("新的确认手势未能接取前哨")
		return
	if not await _action("patrol_record", "02-patrol-record"): return
	await _view(OutpostLayout.entrances()["front"] + Vector2(0, 144), "03-blocked-front-route")
	if not await _action("entrance_record", "04-entry-investigation"): return
	await _view(OutpostLayout.entrances()["side"] + Vector2(-80, 0), "05-side-route")
	if not await _action("wounded_patrol", "06-wounded-request"): return
	if not await _action("supply_record", "07-supply-routes"): return
	if not await _action("aid_bag", "08-quest-aid-pickup"): return
	if not await _action("repair_tools", "09-quest-tool-pickup"): return
	if not await _action("wounded_patrol", "10-explicit-rescue"): return
	if not _qm.outpost_evidence("rescued"):
		_fail("截图流程没有真实完成现场救援")
		return
	await _capture("11-rescued-resident")
	for attempt in 1200:
		if not _qm.outpost_target().get("species", "").is_empty(): break
		await _frames(1)
	var target: Dictionary = _qm.outpost_target()
	if str(target.get("species", "")).is_empty():
		_fail("正常世界截图流程没有真实可行生态目标")
		return
	var pos: Vector2 = target["position"]
	_player.teleport_to(pos + Vector2(0, 110))
	await _frames(60)
	_qm.outpost_action("investigate")
	await _capture("12-ecology-choice")
	var option: Button
	for child: Node in _hud._dialogue_option_box.get_children():
		if child is Button and child.get_meta("quest_action", "") == "outpost:choose_ransack": option = child
	if option == null or option.disabled:
		_fail("正常世界截图未能选择真实巢穴分支")
		return
	await _touch(option)
	await _capture("13-ecology-confirmation")
	await _touch(_hud._dialogue_yes)
	# 实际普攻破巢，镜头定位并不伪造任务事件或写入完成字段。
	_player.teleport_to(pos + Vector2(0, 48))
	await _frames(3)
	for attempt in 16:
		if GameState.outpost_quest.get("stage", "") == "repair": break
		_player.facing = _player.global_position.direction_to(pos)
		TouchInput.queue_attack()
		await _frames(65)
	if GameState.outpost_quest.get("stage", "") != "repair" or GameState.outpost_quest.get("outcome", "") != "ransack":
		_fail("真实普攻没有完成捣巢，不能伪造修复画面")
		return
	if not await _action("signpost", "14-explicit-repair"): return
	if not _qm.outpost_evidence("signpost_repaired") or not OutpostLayout.CHECKPOINT_ID in GameState.discovered_checkpoints:
		_fail("实际修复没有解锁前哨检查点")
		return
	await _capture("15-restored-checkpoint")
	if not await _action("wounded_patrol", "16-regional-next-clue"): return
	await _capture("17-permanent-resident")
	print("=== OUTPOST CHAPTER RENDER COMPLETE ===")
	get_tree().quit()
