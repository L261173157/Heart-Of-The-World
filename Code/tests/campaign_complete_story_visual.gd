## 真实渲染证据：读取完整主线实走所得检查点；仅取景传送，冻结AI，不冒充自然试玩。
## 对话、追问、分支预览、结果继续和后记按钮均使用SubViewport真实触屏。
extends "res://tests/quest_pickup_feedback_visual.gd"

var _phase := "opening"
var _campaign: Node

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.save_enabled = false
	WorldSim.set_process(false)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): _out = arg.trim_prefix("--out=")
		if arg.begins_with("--size="):
			var dims := arg.trim_prefix("--size=").split("x")
			_canvas=Vector2i(int(dims[0]),int(dims[1]))
		if arg.begins_with("--phase="): _phase=arg.trim_prefix("--phase=")
	if _phase=="opening":
		GameState.reset_all()
		GameState.world_seed=BiomeMap.DEFAULT_SEED
	GameState.settings.screen_shake=false
	DirAccess.make_dir_recursive_absolute(_out)
	_viewport=SubViewport.new()
	_viewport.size=_canvas
	_viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	_viewport.world_2d=World2D.new()
	add_child(_viewport)
	var preview:=TextureRect.new()
	preview.texture=_viewport.get_texture()
	preview.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(preview)
	_run.call_deferred()

func _capture(label: String) -> void:
	await _frames(5)
	await RenderingServer.frame_post_draw
	var img:=_viewport.get_texture().get_image()
	var path:=_out.path_join("%s-%dx%d.png" % [label,_canvas.x,_canvas.y])
	_check(img.get_size()==_canvas,"native viewport dimensions "+label)
	_check(img.save_png(path)==OK,"native screenshot saved "+label)
	print("COMPLETE_STORY_CAPTURE ",path," pixels=",img.get_size())

func _cp(id: String) -> Node2D:
	for node: Node in get_tree().get_nodes_in_group("campaign_objects"):
		if str(node.get("campaign_id"))==id: return node
	return null

func _at_campaign(id: String, label: String, interact:=false) -> bool:
	_hud._close_dialogue()
	var prop:=_cp(id)
	_check(prop!=null,"rendered actual campaign object "+id)
	if prop==null: return false
	await _view(prop.global_position+Vector2(0,64),label+"-world")
	if interact:
		prop.interact()
		await _frames(4)
		_check(_hud._dialogue_panel.visible and get_tree().paused,"actual rendered dialogue "+id)
		await _capture(label+"-dialogue")
	return true

func _run() -> void:
	_world=preload("res://scenes/main/main.tscn").instantiate()
	_viewport.add_child(_world)
	_player=_world.get_node("Player")
	_player.set_physics_process(false)
	_player.set_process(false)
	_hud=_world.get_node("HUD")
	_qm=get_tree().get_first_node_in_group("quest_manager")
	_campaign=_qm._campaign
	EventBus.camp_quest_action_requested.connect(_record_action)
	await _frames(60)
	match _phase:
		"opening": await _opening()
		"forest": await _forest()
		"swamp": await _swamp()
		"snow": await _snow()
		"reunion": await _reunion()
		_: _check(false,"unknown render checkpoint")
	_hud._close_dialogue()
	get_tree().paused=false
	WorldSim.stop()
	print("=== CAMPAIGN COMPLETE STORY VISUAL %s (%d checks, %d failures) ===" % ["PASS" if _fails==0 else "FAIL",_checks,_fails])
	get_tree().quit(0 if _fails==0 else 1)

func _opening() -> void:
	var keeper: Node2D
	for node: Node in get_tree().get_nodes_in_group("npcs"):
		if str(node.get("landmark_id"))=="camp_ecology": keeper=node
	_check(keeper!=null,"new game actual Zhou Zhao exists")
	if keeper==null: return
	await _view(keeper.global_position+Vector2(38,0),"01-zhou-zhao")
	keeper.interact()
	await _frames(4)
	_check(_hud._dialogue_panel.visible and _hud._dialogue_yes.visible,"new game visible invitation and confirm")
	await _capture("02-first-invitation")
	await _reading_views("03-first-reading",true)
	var before:=_reading_state()
	await _touch(_hud._dialogue_no)
	_check(_reading_state()==before,"opening Back does not accept quest")
	keeper.interact()
	await _frames(4)
	await _touch(_hud._dialogue_yes)
	_hud._close_dialogue()
	await _action("patrol_record","04-first-clue")

func _forest() -> void:
	_check(Data.chapter1_complete(GameState.campaign_quest),"forest render consumes earned first chapter")
	if not await _at_campaign("c2:herbalist","05-bai-yu",true): return
	await _reading_views("06-forest-reading")
	await _touch(_hud._dialogue_yes)
	await _continue_story_result("bai-yu")
	if not await _at_campaign("c2:old_pact","07-old-pact",true): return
	await _touch(_hud._dialogue_yes)
	await _continue_story_result("old-pact")
	await _at_campaign("c2:liaison","08-a-wei")

func _swamp() -> void:
	_check(Data.ready(GameState.campaign_quest,"watch_c3_swamp:s2"),"swamp render consumes actual earned two route surveys")
	if not await _at_campaign("c3:route_choice","09-swamp-map",true): return
	var before:=_reading_state()
	for route: String in ["near","outer"]:
		var button:=_option_button("campaign|act|watch_c3_swamp:s3:route_choice|"+route)
		_check(button!=null,"real swamp alternative visible "+route)
		if button==null: return
		_hud._dialogue_option_scroll.ensure_control_visible(button)
		await _frames(4)
		await _touch(button)
		await _capture("10-swamp-"+route+"-preview")
		_check(_reading_state()==before,"preview cannot commit swamp route")
		await _touch(_hud._dialogue_no)
		_check(_reading_state()==before,"Back cannot commit swamp route")
	_hud._close_dialogue()
	await _at_campaign("c3:survivor","11-shen-du")

func _snow() -> void:
	_check(Data.ready(GameState.campaign_quest,"watch_c5_snow:s2"),"snow render consumes earned rescue, not synthetic completion")
	await _at_campaign("c5:leader","12-han-duo")
	if not await _at_campaign("c5:evidence_board","13-causality",true): return
	if not _hud._dialogue_questions.is_empty():
		await _reading_views("14-causality-reading",true)
	else:
		var rules:=_hud._dialogue_option_box.get_node_or_null("DialogueRules") as Button
		_check(rules!=null,"causality order has a real details page")
		if rules!=null:
			_hud._dialogue_option_scroll.ensure_control_visible(rules)
			await _frames(4)
			await _touch(rules)
			await _capture("14-causality-rules")

func _reunion() -> void:
	_check(Data.ready(GameState.campaign_quest,"watch_c6_lava:s4") and Data.effective_ending(GameState.campaign_quest)=="reunion","reunion render consumes truly completed single ending")
	var center:=Vector2.ZERO
	for id: String in ["c2:liaison","c3:survivor","c4:map_keeper","c5:leader"]:
		var actor:=_cp(id)
		_check(actor!=null and actor.global_position==CampaignLayout.ending_positions("reunion")[id],"actual reunion placement "+id)
		center+=actor.global_position
	center/=4.0
	await _view(center+Vector2(0,48),"15-reunion-all-four")
	var cast_names := {"c2:liaison":"阿苇","c3:survivor":"沈渡","c4:map_keeper":"罗墨","c5:leader":"韩铎"}
	var labels: Array[Label] = []
	for id: String in cast_names:
		var label := _cp(id).get_node("ObjectLabel") as Label
		_check(label.is_visible_in_tree() and label.text.contains(cast_names[id]),"all four actual reunion names are visible: "+str(cast_names[id]))
		_check(label.size.x<=156.0 and label.get_minimum_size().x<=label.size.x,"reunion name fits bounded width without clipping: "+str(cast_names[id]))
		var ink_width := label.get_theme_font("font").get_string_size(label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,label.get_theme_font_size("font_size")).x + 2*label.get_theme_constant("outline_size")
		_check(ink_width<=label.size.x,"full visible reunion text including outline fits label: "+str(cast_names[id]))
		for previous: Label in labels:
			_check(not label.get_global_rect().intersects(previous.get_global_rect()),"actual reunion name rectangles do not overlap")
		labels.append(label)
	if not await _at_campaign("c5:leader","16-reunion-leader",true): return
	var epilogue:=_option_button("campaign|epilogue_menu")
	_check(epilogue!=null,"reunion offers actual epilogue menu")
	if epilogue==null: return
	_hud._dialogue_option_scroll.ensure_control_visible(epilogue)
	await _frames(4)
	await _touch(epilogue)
	_check(_hud._dialogue_yes.visible,"epilogue utility preview still requires separate confirmation")
	await _touch(_hud._dialogue_yes)
	await _capture("17-epilogue-index")
	var state:=_reading_state()
	var pages: Array=_campaign.epilogue_pages()
	for index in pages.size():
		var button:=_option_button("campaign|epilogue|"+str(index))
		_check(button!=null,"epilogue actual page button")
		if button==null: return
		_hud._dialogue_option_scroll.ensure_control_visible(button)
		await _frames(4)
		await _touch(button)
		_check(_reading_state()==state and _hud._dialogue_yes.visible,"epilogue page preview does not modify ledger")
		await _touch(_hud._dialogue_yes)
		_check(_hud._dialogue_text.text==pages[index] and _on_screen(_hud._dialogue_text_scroll),"exact epilogue page fits native viewport")
		await _capture("18-epilogue-page-"+str(index))
		await _touch(_hud._dialogue_no)
		_check(_reading_state()==state,"epilogue reading/Back changes no reward or evidence")
	_hud._close_dialogue()
	await _view(_prop("wounded_patrol").global_position+Vector2(0,64),"19-shi-an-still-outpost")
	for id: String in ["c2:beacon","c3:beacon","c4:beacon","c5:beacon","c6:beacon"]:
		_check(_cp(id).get("repaired"),"repaired beacon survives reunion "+id)
	await _at_campaign("c6:beacon","20-repaired-final-beacon",true)
	_check(_option_button("campaign|shop|c6:beacon")==null,"empty remote station does not promise resident shop")
