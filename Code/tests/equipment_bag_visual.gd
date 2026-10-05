## 真实世界 + HUD 的固定尺寸 SubViewport；截图尺寸不受云桌面窗口管理器限制。
extends Node

const Gear = preload("res://scripts/equipment/equipment_catalog.gd")
var output := ""
var failed := false
var _view: SubViewport
var _world: Node2D
var _hud: CanvasLayer
var _bag: Control

func _ready() -> void:
	output = OS.get_environment("HOTW_EQUIPMENT_BAG_SHOT_DIR")
	if output.is_empty(): output = ProjectSettings.globalize_path("user://equipment-bag-visual")
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.save_enabled = false
	GameState.reset_all()
	GameState.stats.level = 20
	GameState.gold = 1086
	GameState.inventory["equipment-parts"] = 18
	GameState.ecology_snapshot = null
	for i in 80:
		var item := Gear.generate(8123 + i, 1 + i % 10, i % 4, Gear.SLOTS[i % 6])
		item["id"] = "visual_%03d" % i
		GameState.receive_equipment(item)
	_view = SubViewport.new()
	_view.size = Vector2i(1280, 720)
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_view.world_2d = World2D.new()
	add_child(_view)
	var preview := TextureRect.new()
	preview.texture = _view.get_texture()
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(preview)
	_world = preload("res://scenes/main/main.tscn").instantiate()
	_world.process_mode = Node.PROCESS_MODE_PAUSABLE
	_view.add_child(_world)
	_hud = _world.get_node("HUD")
	_bag = _hud.get("_inv_layer")
	_run.call_deferred()

func _run() -> void:
	for frame in 30: await get_tree().process_frame
	for i in 6:
		GameState.equipment_action("equip", {"id": "visual_%03d" % i}, GameState.equipment_revision())
	_hud.call("_toggle_pause")
	_hud.call("_toggle_inventory")
	for canvas: Vector2i in [Vector2i(1280, 720), Vector2i(1560, 720), Vector2i(1024, 640)]:
		_view.size = canvas
		_bag.set("_tab", "loadout")
		_bag.call("refresh")
		await _capture("%dx%d-loadout" % [canvas.x, canvas.y], canvas)
		_bag.set("_tab", "gear")
		_bag.set("_gear_page", "bag")
		_bag.set("_selected_id", "")
		_bag.call("refresh")
		await _capture("%dx%d-gear" % [canvas.x, canvas.y], canvas)
		if canvas == Vector2i(1280, 720):
			(_bag.get("_detail_scroll") as ScrollContainer).scroll_vertical = 100000
			await _capture("1280x720-caps", canvas)
			(_bag.get("_detail_scroll") as ScrollContainer).scroll_vertical = 0
		_hud.get("_gesture_gate").set("armed", true)
		var item: Dictionary = GameState.equipment_state.items[str(_bag.get("_selected_id"))]
		_bag.call("_ask", "decompose", {"ids": [item.id]}, "永久分解「%s」获得 %d 装备零件？\n分解不可撤销，不会进入回购列表。" % [item.name, Gear.decompose_value(item)], "确认永久分解", int(_bag.get("_revision")), int(_bag.get("_serial")))
		await _capture("%dx%d-confirm" % [canvas.x, canvas.y], canvas)
		_bag.call("cancel_confirmation")
	_view.size = Vector2i(1280, 720)
	_bag.set("_gear_page", "craft")
	_bag.call("refresh")
	await _capture("1280x720-craft", _view.size)
	_bag.set("_offer_kind", "purchase")
	_bag.set("_selected_slot", "weapon")
	_bag.set("_selected_base", "rune_sword")
	_bag.call("refresh")
	await _capture("1280x720-white", _view.size)
	_bag.set("_tab", "loadout")
	_bag.set("_selected_preset", 0)
	GameState.equipment_action("preset_save", {"index": 0, "name": "平原巡猎"}, GameState.equipment_revision())
	_bag.call("refresh")
	await _capture("1280x720-preset", _view.size)
	GameState.first_boss_choices = []
	for index in 3:
		var item := Gear.generate(717 + index, 7, 4, Gear.ORANGE_BASES[index])
		item["id"] = "visual_boss_%d" % index
		GameState.first_boss_choices.append(item)
	GameState._equipment_bump()
	_bag.set("_tab", "pending")
	_bag.set("_selected_choice", 1)
	_bag.call("refresh")
	await _capture("1280x720-pending", _view.size)
	WorldSim.stop()
	_world.queue_free()
	await get_tree().process_frame
	print("=== EQUIPMENT BAG VISUAL %s ===" % ["FAIL" if failed else "PASS"])
	get_tree().quit(1 if failed else 0)

func _capture(label: String, expected: Vector2i) -> void:
	for frame in 8: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := _view.get_texture().get_image()
	if img == null or img.is_empty():
		failed = true
		push_error("背包截图需要真实图形渲染")
		get_tree().quit(1)
		return
	if img.get_size() != expected:
		failed = true
		push_error("背包截图尺寸不符：%s != %s" % [img.get_size(), expected])
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output)
	var path := output + "/" + label + ".png"
	var error := img.save_png(path)
	print("EQUIPMENT_BAG_SCREENSHOT ", path, " size=", img.get_size(), " error=", error)

	if error != OK:
		failed = true
		push_error("背包截图保存失败：" + path)
		get_tree().quit(1)
