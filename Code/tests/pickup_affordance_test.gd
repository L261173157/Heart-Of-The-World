## 真实物件与可见对话的生命周期；场景重建与独立进程读档复用同一检查。
## 位置受控以覆盖交互，不冒充玩家完整徒步流程；已有章节契约继续测真实路径。
extends "res://tests/campaign_optional_runtime_test.gd"
const OutpostData := preload("res://scripts/main/outpost_quest_data.gd")
var outpost_world: OutpostWorld
var outpost: OutpostQuest
var hud: CanvasLayer

func _run() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var font: FontFile = preload("res://assets/fonts/NotoSansSC-Regular.ttf")
	for marker: String in ["!", "?", "✓"]:
		_check(font.has_char(marker.unicode_at(0)), "任务状态标记由嵌入字体提供 " + marker)
	WorldSim.stop()
	WorldSim.sim = null
	BiomeMap.configure(GameState.world_seed)
	ObstacleField.restore_destroyed(GameState.destroyed_cells)
	_player = preload("res://scenes/player/player.tscn").instantiate()
	_player.get_node("Camera2D").enabled = false
	add_child(_player)
	_player.set_physics_process(false)
	_player.set_process(false)
	hud = preload("res://scenes/ui/hud.tscn").instantiate()
	add_child(hud)
	await _mount_affordances()
	if OS.get_environment("HOTW_PICKUP_PHASE") != "read":
		_fresh()
		GameState.outpost_quest = {}
		outpost.accept()
		_check(outpost.snapshot().step_progress == "调查 0/2", "初始调查计数不是章节0/3")
		for id: String in ["patrol_record", "entrance_record", "wounded_patrol", "supply_record", "aid_bag", "repair_tools"]:
			await _outpost_action(id)
			if id == "patrol_record": _check(outpost.snapshot().step_progress == "调查 1/2", "第一条记录立即推进本组动作")
			if id == "aid_bag":
				var view := outpost.snapshot()
				_check(view.step_progress == "救援 3/5" and view.target_object_id == "wounded_patrol" and str(view.next_action).contains(str(view.target_title)) and str(view.next_action).contains("急救包") and not outpost.evidence("rescued"), "拾取后显示真实救援3/5、带药返回实际巡守，未抢先救治")
		await _complete_chain(Catalog.chain("side_herbalist"), 0)
		await _complete_chain(Catalog.chain("region_plains"), 1)
		await _assert_service("region_plains:work_outer", false)
		await _assert_service("region_plains:station", false)
		await _go("region_plains:work_outer")
		GameState.inventory["onigiri"] = 99
		EventBus.npc_dialogue.emit(_optional.object_payload("region_plains:work_outer"))
		await _frames()
		var supply := _option_containing("supply|")
		_check(supply != null and not supply.disabled, "真实可见首次补给按钮可用")
		if supply != null:
			await _tap_visible(supply)
			await _tap_visible(hud._dialogue_yes)
		hud._close_dialogue()
		await _frames()
		_check(Data.service_claimed(GameState.campaign_quest, "region_plains_station"), "真实按钮写入共享补给收据")
	await _assert_completed_affordances("同场景重开" if OS.get_environment("HOTW_PICKUP_PHASE") != "read" else "独立进程冷启动")
	await _reload_affordances()
	await _assert_completed_affordances("场景重建")
	if OS.get_environment("HOTW_PICKUP_PHASE") != "read":
		GameState.save_enabled = true
		_check(GameState.save_now(), "真实GameState持久化物件状态")
		GameState.save_enabled = false
	get_tree().paused = false
	if _fails == 0: print("=== PICKUP AFFORDANCE PASS (%d checks) ===" % _checks)
	get_tree().quit(0 if _fails == 0 else 1)

func _mount_affordances() -> void:
	_world = World.new()
	add_child(_world)
	outpost_world = OutpostWorld.new()
	add_child(outpost_world)
	_host = FixtureHost.new()
	add_child(_host)
	_attach_optional()
	_host.changed.connect(_refresh)
	outpost = OutpostQuest.new()
	add_child(outpost)
	_refresh()
	outpost_world.refresh_state(outpost.visual_state())
	await _frames()

func _reload_affordances() -> void:
	hud._close_dialogue()
	_host.queue_free()
	_world.queue_free()
	outpost.queue_free()
	outpost_world.queue_free()
	await _frames(3)
	await _mount_affordances()

func _outpost_action(id: String) -> void:
	var prop := outpost_world.object_node(id)
	_player.position = prop.global_position + Vector2(0, 40)
	await _frames(12)
	_check(prop.can_interact(), "真实前哨物件首次可交互 " + id)
	prop.interact()
	await _frames()
	_check(hud._dialogue_panel.visible and hud._dialogue_yes.visible and not hud._dialogue_yes.disabled, "真实首次确认按钮 " + id)
	if hud._dialogue_yes.visible: await _tap_visible(hud._dialogue_yes)
	hud._close_dialogue()
	await _frames(12)

func _assert_completed_affordances(phase: String) -> void:
	for id: String in ["aid_bag", "repair_tools"]:
		var prop := outpost_world.object_node(id)
		_player.position = prop.global_position + Vector2(0, 40)
		await _frames(12)
		_check(not outpost_world._ground.supply_pad_visible(id), phase + " 已取物件下方地垫不再渲染 " + id)
		_check(prop.taken and not prop.visible and not prop.can_interact() and not prop._near, phase + " 散落物、底座和拾取高亮整体消失 " + id)
		hud._close_dialogue()
		prop.interact()
		await _frames()
		_check(not hud._dialogue_panel.visible, phase + " 旧对象不能重开拾取对话 " + id)
		_check(not str(_player._current_context().get("label", "")).contains("取回"), phase + " 无残留情境拾取按钮 " + id)
		_check(outpost.object_payload(id).get("kind", "") == "info", phase + " 旧载荷请求不能重建领取动作 " + id)
	for id: String in ["patrol_record", "entrance_record", "supply_record"]:
		var prop := outpost_world.object_node(id)
		_player.position = prop.global_position + Vector2(0, 40)
		await _frames(12)
		_check(prop.visible and prop.read and prop.get_node("ObjectLabel").text.contains("已调查" if id == "entrance_record" else "已读") and prop.can_interact(), phase + " 已读札记保留且可重读 " + id)
		prop.interact()
		await _frames()
		_check(hud._dialogue_panel.visible and not hud._dialogue_yes.visible, phase + " 重读不冒充未完成行动 " + id)
		hud._close_dialogue()
	var crate := _world.object_node("side_herbalist:medicine")
	_player.position = crate.global_position + Vector2(0, 40)
	await _frames(12)
	_check(crate.visible and crate.taken and not crate.can_interact() and not crate._near, phase + " 已取空药箱保留但没有拾取高亮")
	_check(crate.get_node("ObjectLabel").visible and crate.get_node("ObjectLabel").text.contains("已取空"), phase + " 空容器实际可见文字明确")
	crate.interact()
	await _frames()
	_check(not hud._dialogue_panel.visible, phase + " 空箱不打开再次领取按钮")
	await _go("side_herbalist:record")
	_check(_world.object_node("side_herbalist:record").get_node("ObjectLabel").text.contains("已读"), phase + " 战役已读记录状态")
	for id: String in ["region_plains:work_outer", "region_plains:station"]:
		await _assert_service(id, true)
	# 主线同样投影已读和已取：先前章节为明确的授权夹具，拾取行为由上方实际可选线验证。
	_check(_world.object_node("c2:old_pact").read and _world.object_node("c2:old_pact").title.contains("已读"), phase + " 主线已读词汇一致")
	_check(_world.object_node("c2:route_marks").read and not _world.object_node("c2:route_marks").title.contains("已领取"), phase + " 非领奖地点的已读行动没有伪造奖励状态")
	_check(_world.object_node("c2:aid_cache").taken and not _world.object_node("c2:aid_cache").can_interact(), phase + " 主线空箱不再提供拾取")

func _assert_service(id: String, claimed: bool) -> void:
	await _go(id)
	await _frames(12)
	var prop := _world.object_node(id)
	var payload := _optional.object_payload(id)
	_check(prop.affordance_state == ("claimed" if claimed else "ready"), "共享端点同步状态 " + id)
	_check(prop.get_node("ObjectLabel").visible and prop.title.contains("已领取" if claimed else "待领取"), "共享端点可见状态 " + id)
	var message := str(payload.get("text", ""))
	var acknowledges_receipt := message.contains("已领取") or message.contains("已经领过")
	_check(acknowledges_receipt == claimed, "共享端点正文如实说明是否已经领过 " + id)
	_check(not claimed or (not message.contains("选一处就好") and not message.contains("也能从外缘补给台领")), "共享端点已领后不能再邀请从另一端领取 " + id)
	EventBus.npc_dialogue.emit(payload)
	await _frames()
	_check(hud._dialogue_panel.visible, "真实驻站菜单打开 " + id)
	_check((_option_containing("supply|") == null) == claimed, "真实领取按钮与收据一致 " + id)
	var shop := _option_containing("shop|")
	_check(shop != null and shop.visible and not shop.disabled, "领取后商店服务仍可用 " + id)
	hud._close_dialogue()
	await _frames()

func _option_containing(value: String) -> Button:
	for child: Node in hud._dialogue_option_box.get_children():
		if child is Button and str(child.name).contains(value): return child
	return null

func _tap_visible(button: Control) -> void:
	await _frames(3)
	var point := get_viewport().get_screen_transform() * button.get_global_rect().get_center()
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.position = point
	touch.pressed = true
	Input.parse_input_event(touch)
	await _frames()
	touch = InputEventScreenTouch.new()
	touch.index = 0
	touch.position = point
	touch.pressed = false
	Input.parse_input_event(touch)
	await _frames(3)
