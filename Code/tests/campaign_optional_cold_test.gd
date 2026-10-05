## 独立引擎进程冷读真实 GameState 文件，再装配实际 CampaignWorld。
## 此回归不复演生态/首次玩家体验；验证任务、实体工程与一次性收据的磁盘生命周期。
extends "res://tests/campaign_optional_runtime_test.gd"

func _run() -> void:
	var expected_path := OS.get_environment("HOTW_OPTIONAL_EXPECTED")
	var file := FileAccess.open(expected_path, FileAccess.READ)
	_check(file != null, "独立进程读取落盘检查清单")
	if file == null:
		get_tree().quit(1)
		return
	var expected: Dictionary = JSON.parse_string(file.get_as_text())
	file.close()
	var sid := str(expected.get("stage_id", ""))
	# GameState autoload 已经通过 HOTW_TEST_SAVE 从磁盘 _load，没有沿用生产者内存。
	_check(GameState.campaign_quest.get("id", "") == Data.ID, "autoload从真实存档恢复具名账本")
	_check(Data.ready(GameState.campaign_quest, sid) == expected.get("ready", false), "冷启动保持阶段完成证据 " + sid)
	_check(Data.paid(GameState.campaign_quest, sid) == expected.get("paid", false), "冷启动保持独立阶段支付收据 " + sid)
	if GameState.gold != int(expected.get("gold", -1)) or not _inventory_matches(expected.get("inventory", {})):
		print("OPTIONAL COLD WALLET expected=", expected.get("gold"), "/", expected.get("inventory"), " actual=", GameState.gold, "/", GameState.inventory)
	_check(GameState.gold == int(expected.get("gold", -1)) and _inventory_matches(expected.get("inventory", {})), "磁盘恢复不增减钱包或库存")
	BiomeMap.configure(GameState.world_seed)
	ObstacleField.restore_destroyed(GameState.destroyed_cells)
	_world = World.new()
	add_child(_world)
	_player = CharacterBody2D.new()
	_player.add_to_group("player")
	add_child(_player)
	_host = FixtureHost.new()
	add_child(_host)
	_attach_optional()
	_host.changed.connect(_refresh)
	_refresh()
	await _frames()
	_check(JSON.stringify(JSON.parse_string(JSON.stringify(_optional.visual_state()))) == JSON.stringify(expected.get("state", {})), "冷启动重新投影相同分支、服务与开门状态")
	_check(ObstacleField.destroyed_list() == expected.get("destroyed", []), "真实已破障覆盖层从磁盘恢复")
	for key: String in ["optional_routes", "optional_route_steps", "optional_route_reanchor"]:
		var pending: Dictionary = expected.get(key, {}).duplicate(true)
		# 完工后最终 route 证据承担持久历史，临时前缀按合同清理；未完工的必须逐项相同。
		for aid: String in pending.keys():
			var a: Dictionary = Catalog.actions().get(aid, {})
			if not a.is_empty() and Data.ready(GameState.campaign_quest, a["stage"]): pending.erase(aid)
		_check(JSON.parse_string(JSON.stringify(GameState.campaign_quest.get(key, {}))) == pending, "路线贡献及接续约束独立冷恢复 " + key)
	for id: String in expected.get("nodes", {}):
		var prior: Dictionary = expected["nodes"][id]
		var node: Node2D = _world.object_node(id)
		_check(node != null, "冷启动实际装配对象 " + id)
		if node == null: continue
		var at: Array = prior.get("position", [])
		_check(at.size() == 2 and node.global_position.distance_to(Vector2(float(at[0]), float(at[1]))) < 0.1, "持久NPC/站点位置恢复 " + id)
		for key: String in ["visible", "taken", "rescued", "repaired", "gate_open", "service", "title"]:
			_check(node.get(key) == prior.get(key), "对象持久状态 " + id + ":" + key)
	var before := JSON.stringify(GameState.campaign_quest)
	var gold_before := GameState.gold
	_host._settle_ready()
	_check(before == JSON.stringify(GameState.campaign_quest) and gold_before == GameState.gold, "冷启动重复结算不得再次支付任何已付阶段")
	if str(expected.get("suffix", "")) == "service":
		var final: Dictionary = Catalog.stage(sid)["actions"][-1]
		var target := _optional.action_object(final)
		await _go(target)
		var inventory := GameState.inventory.duplicate(true)
		_optional.claim_service(target)
		_check(inventory == GameState.inventory, "服务领取收据阻止独立进程重复发放")
	if str(expected.get("suffix", "")) == "route_resume":
		var a: Dictionary = Catalog.stage(sid)["actions"][0]
		var retained: Array = GameState.campaign_quest.get("optional_routes", {}).get(a["id"], []).duplicate()
		var anchor := _optional._route_anchor(a)
		_player.position = anchor
		_optional._track_routes()
		_optional._track_routes()
		_check(GameState.campaign_quest.get("optional_route_reanchor", {}).get(a["id"], false), "冷读后只传送到原点并等待不能解除接续要求")
		_player.move_and_collide(Vector2(8,0))
		_optional._track_routes()
		_check(not GameState.campaign_quest.get("optional_route_reanchor", {}).get(a["id"], false) and GameState.campaign_quest.get("optional_routes", {}).get(a["id"], []) == retained, "最后核实点的真实一步恢复接续且不丢贡献")
	if _fails == 0: print("=== CAMPAIGN OPTIONAL COLD PASS (%s, %d checks) ===" % [sid, _checks])
	get_tree().quit(1 if _fails > 0 else 0)

func _inventory_matches(value: Dictionary) -> bool:
	if value.size() != GameState.inventory.size(): return false
	for id: String in value:
		if int(value[id]) != int(GameState.inventory.get(id, 0)): return false
	return true
