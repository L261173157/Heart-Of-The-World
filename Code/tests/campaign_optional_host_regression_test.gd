## 独立复核宿主真实投影，而非比较旧快照中已经错误的 repaired 基线。
## 调用者用 HOTW_TEST_SAVE 指向 optional lifecycle 生产的任一完整 s3 快照，
## 建议分别使用 region_lava_s3__0__stage.json 与 __1__stage.json 两次冷启动。
## 只读原文件；后半段仅在内存移除巨魔支线，用真实发布菜单覆盖首次到达。
extends Node
const Data := preload("res://scripts/main/campaign_quest_data.gd")
const Catalog := preload("res://scripts/main/campaign_catalog.gd")
var checks := 0
var failures := 0
var world: CampaignWorld
var host: CampaignQuest
var player: CharacterBody2D
var travel_requests: Array = []

func _ready() -> void:
	GameState.save_enabled = false
	_run.call_deferred()

func _check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("OPTIONAL HOST REGRESSION FAIL " + text)

func _run() -> void:
	_check(not OS.get_environment("HOTW_TEST_SAVE").is_empty(), "必须由真实磁盘快照冷启动")
	_check(Data.ready(GameState.campaign_quest, "region_lava:s3"), "冷启动读取完整人物与区域分支快照")
	if failures > 0:
		get_tree().quit(1)
		return
	var gold_before := GameState.gold
	var inventory_before := GameState.inventory.duplicate(true)
	BiomeMap.configure(GameState.world_seed)
	ObstacleField.restore_destroyed(GameState.destroyed_cells)
	world = CampaignWorld.new()
	add_child(world)
	player = CharacterBody2D.new()
	player.add_to_group("player")
	add_child(player)
	host = CampaignQuest.new()
	add_child(host)
	await get_tree().physics_frame
	world.refresh_state(host.visual_state())
	var branch_checks := 0
	for a: Dictionary in Catalog.actions(GameState.world_seed).values():
		if not host._optional.handles_action(str(a["id"])) or not host._optional._done(a): continue
		var alternatives: Dictionary = a.get("destination_by_choice", {})
		if alternatives.is_empty(): continue
		var selected := host._optional.action_object(a)
		for id: String in alternatives.values():
			if id == selected: continue
			var node := world.object_node(id)
			_check(node != null, "未选物件确实装配 " + id)
			if node == null: continue
			_check(not bool(node.get("repaired")), "未选分支不得被宿主标为施工完成 " + id)
			_check(not bool(node.get("rescued")), "未选救援对象保持原状 " + id)
			_check(str(node.get("service")).is_empty(), "未选站点不得开放服务 " + id)
			branch_checks += 1
		if a.get("kind", "") in ["repair", "deliver"]:
			_check(bool(world.object_node(selected).get("repaired")), "所选分支确实落到实际节点 " + selected)
	_check(branch_checks >= 10, "覆盖完整分支负例，避免空快照假通过")
	_check(world.object_node("side_scholar:shortcut_gate").get("gate_open") == (Data.choice(GameState.campaign_quest, Catalog.actions()["side_scholar:s2:resolve"]) == "component"), "学者开门严格服从实际选择")
	_check(GameState.gold == gold_before and GameState.inventory == inventory_before, "冷装配及只读验证不增加奖励")

	# 生命周期快照中的巨魔故事已结束；单独创建未接取状态来覆盖真实首次菜单。
	for sid: String in ["side_troll:s1", "side_troll:s2"]:
		GameState.campaign_quest["quests"].erase(sid)
	GameState.campaign_quest["optional_targets"].erase("side_troll")
	GameState.campaign_quest = Data.sanitize(GameState.campaign_quest, GameState.world_seed)
	world.refresh_state(host.visual_state())
	var giver := world.object_node("side_troll:giver")
	player.position = giver.global_position + Vector2(0,48)
	await get_tree().physics_frame
	_check(bool(giver.call("can_interact")), "真实远端发布人现场可交互")
	var before := JSON.stringify(GameState.campaign_quest)
	var payload := host.object_payload("side_troll:giver")
	_check(payload.get("kind", "") == "camp_choice", "实际宿主对象菜单同时承载故事及返程")
	var actions: Array = []
	for option: Dictionary in payload.get("options", []): actions.append(str(option.get("action", "")))
	var story := "campaign|optional|accept|side_troll:s1|side_troll:giver"
	var forest := "campaign|depart|forest|side_troll:giver"
	var home := "campaign|depart|home|side_troll:giver"
	_check(story in actions, "返程包装不能吞掉首次接取故事的真实行动")
	_check(forest in actions and home in actions, "远端现场菜单提供林地及家园两个返程入口")
	_check(before == JSON.stringify(GameState.campaign_quest), "读取及取消菜单不接单、不移动或发奖")
	EventBus.campaign_travel_requested.connect(_on_travel)
	host.action(forest)
	host.action(home)
	_check(travel_requests == [["forest", "side_troll:giver"], ["home", "side_troll:giver"]], "实际菜单行动通过宿主路线闸门发出正确返程请求")
	host.action(story)
	_check(GameState.campaign_quest.get("quests", {}).get("side_troll:s1", {}).get("accepted", false), "包装内故事行动经宿主正常接取")
	var next := host.object_payload("side_troll:giver")
	var next_actions: Array = []
	for option: Dictionary in next.get("options", []): next_actions.append(str(option.get("action", "")))
	_check("campaign|optional|act|side_troll:s1:request" in next_actions and forest in next_actions, "接取后仍同时可以问旧旗或返程")
	player.position += Vector2(2000,0)
	var count := travel_requests.size()
	host.action(home)
	_check(travel_requests.size() == count, "离开远端发布人后陈旧返程按钮不能远程触发")
	if failures == 0: print("=== CAMPAIGN OPTIONAL HOST REGRESSION PASS (%d checks) ===" % checks)
	get_tree().quit(0 if failures == 0 else 1)

func _on_travel(terrain: String, origin: String) -> void:
	travel_requests.append([terrain, origin])
