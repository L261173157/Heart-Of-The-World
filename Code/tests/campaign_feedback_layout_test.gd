## 仅 UI 合同夹具，不代表实走通关：真实 HUD 回调、字体和三种视口验证摘要/反馈完整可读。
extends Node2D
const Data := preload("res://scripts/main/campaign_quest_data.gd")
const Catalog := preload("res://scripts/main/campaign_catalog.gd")
const FIXED := ["AttackBtn", "ShieldBtn", "DashBtn", "ShortcutBtn", "QuickSlotBtn", "MoreBtn"]
var _hud: CanvasLayer
var _checks := 0
var _fails := 0
func _ready() -> void:
	GameState.save_enabled = false
	GameState.reset_all()
	WorldSim.stop()
	_run.call_deferred()
func _run() -> void:
	_hud = preload("res://scenes/ui/hud.tscn").instantiate()
	add_child(_hud)
	var current := _ledger(5)
	var ledgers: Array[Dictionary] = [_ledger(1), current, _legacy_view(current, "distributed"), _legacy_view(current, "centralized")]
	for canvas: Vector2i in [Vector2i(1280, 720), Vector2i(1560, 720), Vector2i(1024, 640)]:
		get_tree().root.size = canvas
		get_tree().root.content_scale_size = canvas
		get_tree().root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		get_tree().root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
		await _settle()
		var bounds := get_viewport().get_visible_rect()
		_check(bounds.size == Vector2(canvas), "真实视口 " + str(canvas))
		for q: Dictionary in ledgers:
			GameState.campaign_quest = q
			_hud.set("_task_snapshot", [])
			EventBus.quest_updated.emit(CampaignQuest.completed_summary(q, true))
			await _settle()
			var label: Label = _hud.get("quest_label")
			var expected := CampaignQuest.completed_summary(q, true)
			_check(label.text == expected and label.text.count("\n") == 1, "HUD 实际回调保留两行紧凑摘要")
			_check(label.get_line_count() <= 2 and bounds.encloses(label.get_global_rect()), "两行摘要完整处于屏幕")
			for line: String in label.text.split("\n"):
				var width := label.get_theme_font("font").get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x
				_check(width <= label.size.x, "摘要整行字体宽度可见 " + line)
			_check(CampaignQuest.completed_summary(q).length() > expected.length(), "居民对话仍保留完整细节")
		_hud.call("_toast_combat", "恢复预设：饭团")
		await _settle()
		var toast: Label = _hud.get("_combat_toast")
		_check(bounds.encloses(toast.get_global_rect()) and toast.position.y > canvas.y * 0.6, "反馈在屏幕下方空档")
		_check(toast.mouse_filter == Control.MOUSE_FILTER_IGNORE, "反馈不拦截触屏")
		for button_name: String in FIXED:
			var button: Button = _hud.get_node("Root").find_child(button_name, true, false)
			_check(button.visible and not toast.get_global_rect().intersects(button.get_global_rect()), "反馈不覆盖固定六键 " + button_name)
	_hud.queue_free()
	await _settle()
	print("=== CAMPAIGN FEEDBACK LAYOUT %s (%d checks) ===" % ["PASS" if _fails == 0 else "FAIL", _checks])
	get_tree().quit(0 if _fails == 0 else 1)
func _settle() -> void:
	for i in 3:
		await get_tree().process_frame
func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok: _fails += 1
	print("  %s %s" % ["PASS" if ok else "FAIL", label])
## 仅呈现夹具：历史账本用当前合法前置和两种原始证据形状构造，不声称旧版实走。
func _legacy_view(current: Dictionary, historical: String) -> Dictionary:
	var raw := current.duplicate(true)
	var ending: Dictionary = raw.quests["watch_c6_lava:s4"]
	ending.choice = historical
	ending.evidence["watch_c6_lava:s4:ending"].kind = "choice"
	ending.evidence["watch_c6_lava:s4:ending"].choice = historical
	raw.ending = historical
	var restored := Data.sanitize(raw, int(raw.seed))
	_check(restored.quests["watch_c6_lava:s4"].choice == historical and Data.effective_ending(restored) == "reunion", "UI旧证据保留原选择，当前后记统一团聚")
	return restored

func _ledger(chapters: int) -> Dictionary:
	var q := Data.create(7781)
	var e: Dictionary = {}
	for key: String in Data.Outpost.EVIDENCE: e[key] = true
	Data.authorize_chapter1(q, {"id": "lost_outpost_v1", "evidence": e, "outcome": "survey", "survey_confirmed": true})
	for chapter: Dictionary in Catalog.main_chapters().slice(0, chapters):
		_check(Data.accept_chapter(q, chapter["id"], 7), "UI 合同夹具接受章节")
		for stage: Dictionary in chapter["steps"]:
			for action: Dictionary in stage["actions"]:
				if action.get("optional", false): continue
				_check(Data.record(q, stage["id"], action["id"], _proof(q, action)), "UI 合同夹具记录")
			_check(Data.mark_paid(q, stage["id"]), "UI 合同夹具收据")
	return q
func _proof(q: Dictionary, a: Dictionary) -> Dictionary:
	var p := {"position": [234, 567], "tick": 11}
	var selected := Data.choice(q, a)
	match str(a["kind"]):
		"choice":
			var option: Variant = a["choices"][0]
			selected = str(option["id"]) if option is Dictionary else str(option)
			if a["chain"] == "region_forest": selected = "outer"
			p["choice"] = selected
		"puzzle": p["order"] = a["puzzle_order"].duplicate()
		"obstacle":
			p["obstacle_key"] = a.get("barrier_id", a["object"])
			p["destroyed"] = true
		"encounter":
			p["outcome"] = "absent"
			p["verified"] = true
		"ecology":
			p["outcome"] = "survey"
			p["verified"] = true
		"route":
			p["route"] = selected if not selected.is_empty() else a["routes"][0]
			p["traversed"] = true
			p["visit_ids"] = a.get("route_by_choice", {}).get(selected, a.get("route_waypoints", [])).duplicate()
	var destination: Dictionary = a.get("destination_by_choice", {})
	if destination.has(selected): p["destination"] = destination[selected]
	if a.has("consumes"): p["item"] = a["consumes"]
	if a.get("obstacle_by_choice", {}).has(selected):
		p["obstacle_key"] = a["obstacle_by_choice"][selected]
		p["destroyed"] = true
	return p
