## 导航回归：真实生态数据、流式位置、任务/赏金、迷雾和重复进出世界。
## "$GODOT" --headless --path Code res://tests/gameplay_navigation_test.tscn --quit-after 8000
extends Node

const MAIN_SCENE := preload("res://scenes/main/main.tscn")
var _checks := 0
var _fails := 0
var _radar: Minimap
var _player: Node2D
var _sim: EcologySim
var _goblin: SpeciesData
var _miner: SpeciesData
var _sheep: SpeciesData

## 只替代表现位置；生态权威仍使用真实 EcologySim/MonsterInstance。
class PositionedMonster extends MonsterBase:
	func _ready() -> void:
		add_to_group("monsters")
	func _exit_tree() -> void:
		pass
	func _physics_process(_delta: float) -> void:
		pass
	func _process(_delta: float) -> void:
		pass


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.save_enabled = false
	WorldSim.set_process(false)
	get_tree().paused = false
	_run.call_deferred()


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		push_error("FAIL " + label)


func _reveal(pos: Vector2) -> void:
	var cell := GameState.fog_cell_of(pos)
	GameState.fog_reveal_cell(cell.x, cell.y)


func _target_id() -> String:
	_radar._refresh_navigation()
	return str(_radar._target.get("id", ""))


func _run() -> void:
	GameState.reset_all()
	GameState.world_seed = 20260908
	BiomeMap.configure(GameState.world_seed)
	for species: SpeciesData in SpeciesCatalog.build_all():
		match species.species_name:
			"火把哥布林": _goblin = species
			"地精矿工": _miner = species
			"山羊": _sheep = species
	var region := SimRegion.new()
	region.id = "radar_test"
	region.center = Vector2(40000, 40000)
	region.size = Vector2(2000, 2000)
	region.capacity = 100
	_sim = EcologySim.new()
	_sim.setup([region], [_goblin, _miner, _sheep], {})
	WorldSim.start(_sim)
	_player = Node2D.new()
	_player.position = region.center
	_player.add_to_group("player")
	add_child(_player)
	_radar = Minimap.new()
	_radar.size = Vector2(240, 120)
	add_child(_radar)
	_check(_target_id().is_empty(), "空世界无虚构目标")
	_check(_radar._category.text == "附近暂无目标", "空目标有明确探索提示")
	var near := _sim.spawn_instance(_goblin, region.id, 30, 0, 1.0, false,
		_player.position + Vector2(320, 0))
	var next := _sim.spawn_instance(_goblin, region.id, 30, 0, 1.0, false,
		_player.position + Vector2(640, 0))
	var camp := _sim.spawn_instance(_miner, region.id, 30, 0, 1.0, false,
		_player.position + Vector2(3500, 0))
	var animal := _sim.spawn_instance(_sheep, region.id, 30, 0, 1.0, false,
		_player.position + Vector2(32, 0))
	var hidden := _sim.spawn_instance(_miner, region.id, 30, 0, 1.0, false, Vector2(90000, 90000))
	_check(_target_id().is_empty(), "未知迷雾不泄露任何活怪/营地")
	_reveal(near.spawn_pos)
	_reveal(camp.spawn_pos)
	var fog_before := GameState.explored.duplicate()
	var dirty_before := GameState.fog_dirty.duplicate()
	_check(_target_id() == "monster:%d" % near.id, "最近存活敌人优先，不把被动动物当敌人")
	_check(_radar._direction.text == "向东" and _radar._distance.text == "10格 · 直线",
		"方向与距离使用真实32像素网格")
	_check(GameState.explored == fog_before and GameState.fog_dirty == dirty_before,
		"观察雷达不改写迷雾也不消费其他观察者的脏格")
	_check(_radar._radar_point(_player.position).is_equal_approx(_radar._radar_rect().get_center()),
		"玩家始终位于局部窗中心")
	_check(_radar._radar_point(_player.position + Vector2(2400, 0)).distance_to(
		_radar._radar_point(_player.position)) >= 40, "2400像素遭遇距离在雷达上至少40像素")
	var display := PositionedMonster.new()
	display.inst = near
	display.position = _player.position + Vector2(0, -960)
	_reveal(display.position)
	var visual := AnimatedSprite2D.new()
	visual.name = "Visual"
	display.add_child(visual)
	add_child(display)
	_check(_target_id() == "monster:%d" % next.id, "流式节点当前距离覆盖旧出生点")
	_sim.report_killed(next.id)
	_check(_target_id() == "monster:%d" % near.id and _radar._direction.text == "向北",
		"死亡立刻换活目标，导航追随实际追击位置")
	_sim.report_killed(near.id)
	_check(_target_id() == "monster:%d" % camp.id and _radar._category.text == "附近怪群",
		"2400像素流式圈外仍能导航到模拟中的附近活怪群")
	_check(_radar._radar_rect().grow(-1).has_point(_radar._target_marker_position(camp.spawn_pos)),
		"屏外目标箭头被夹在雷达边框内")
	display.queue_free()
	await get_tree().process_frame
	EventBus.bounty_target_changed.emit(_miner.species_name)
	_check(_target_id() == "monster:%d" % camp.id and _radar._category.text == "赏金目标",
		"结构化赏金事件正确驱动优先级")
	var quest_enemy := _sim.spawn_instance(_goblin, region.id, 30, 0, 1.0, false,
		_player.position + Vector2(4500, 0))
	_reveal(quest_enemy.spawn_pos)
	GameState.quests["active"] = [{"kind": "hunt", "species": _goblin.species_name, "progress": 0, "need": 1}]
	_check(_target_id() == "monster:%d" % quest_enemy.id and _radar._category.text == "委托 · 猎杀",
		"活跃狩猎优先于更近赏金")
	GameState.quests["active"][0]["progress"] = 1
	_check(_target_id() == "monster:%d" % camp.id, "已完成尚未移出的委托不滞留旧目标")
	var original_pos := _radar._player_pos
	_radar._player_pos = Vector2(10000, 10000)
	var scoped: Array[Dictionary] = [
		{"id": "close", "kind": "monster", "pos": Vector2(10100, 10000), "name": "近怪",
			"species": _goblin.species_name, "ambient": false, "streamed": true},
		{"id": "far", "kind": "monster", "pos": Vector2(700000, 700000), "name": "远赏金",
			"species": _miner.species_name, "ambient": false, "streamed": false}]
	_check(_radar._select_target(scoped).get("id", "") == "close", "975807像素外旧赏金不抢走100像素外活怪")
	GameState.quests["active"] = [{"kind": "hunt", "species": _miner.species_name, "progress": 0, "need": 1}]
	_check(_radar._select_target(scoped).get("id", "") == "close", "已探索遥远委托也不能锁住本地游玩")
	_radar._player_pos = original_pos
	GameState.quests["active"] = [{"kind": "collect", "item": "tea-leaf", "progress": 0, "need": 3}]
	_check(_target_id() == "monster:%d" % camp.id and _radar._category.text == "委托 · 材料",
		"材料委托沿EconomyMath真源找仍存活的掉落来源")
	GameState.quests["active"] = [{"kind": "ransack", "progress": 0, "need": 1}]
	_reveal(_sim.camp_pos(region, _goblin))
	_check(_target_id().begins_with("nest:"), "捣巢委托锁定未摧毁巢穴")
	var first_nest := str(_radar._target.get("id", "")).trim_prefix("nest:")
	if not first_nest.is_empty():
		_sim.destroy_nest(first_nest.get_slice("|", 0), first_nest.get_slice("|", 1))
		_check(_target_id() != "nest:" + first_nest, "捣毁后立即跳过失活巢穴")
	GameState.quests["active"] = [{"kind": "explore", "progress": 0, "need": 2}]
	_sim.report_killed(camp.id)
	_sim.report_killed(quest_enemy.id)
	_check(_target_id().is_empty(), "探索任务不指向秘密地标，赏金活体耗尽后清除箭头")
	_check(not _radar._known_candidates().any(func(c: Dictionary) -> bool:
		return c["id"] == "monster:%d" % hidden.id), "远处未知赏金活体保持隐藏")
	EventBus.bounty_target_changed.emit("")
	_check(_radar._bounty_species.is_empty(), "赏金交接清掉结构化旧目标")
	# 发现内容才可作为回访目的地；已到达点不持续吸住导航。
	var landmark: Dictionary = LandmarkRegistry.landmarks()[0]
	GameState.discovered_landmarks.assign([landmark["id"]])
	_check(_target_id() == "landmark:" + landmark["id"], "无附近活怪时指引最近已发现地标")
	GameState.discovered_landmarks.clear()
	GameState.discovered_checkpoints.assign(["home"])
	_check(_target_id() == "checkpoint:home", "已发现营地显示并可回访")
	_player.position = WorldConfig.spawn_pos()
	_check(_target_id().is_empty(), "到达已发现营地后不留下零距离旧指引")
	GameState.discovered_checkpoints.clear()
	# 相同节点观察换世界，不沿用旧目标、旧营地坐标和旧迷雾。
	var replacement := EcologySim.new()
	replacement.setup([region], [_goblin, _miner, _sheep], {})
	WorldSim.start(replacement)
	GameState.explored = PackedByteArray()
	GameState.fog_dirty.clear()
	_check(_target_id().is_empty() and _radar._camp_positions.is_empty(), "换世界清除缓存和目标")
	_check(not _radar._is_known_position(near.spawn_pos), "同种子重置不残留已探索格")
	for pair: Array in [[Vector2.RIGHT, "向东"], [Vector2.DOWN, "向南"],
		[Vector2.LEFT, "向西"], [Vector2.UP, "向北"], [Vector2(1, -1), "向东北"]]:
		_check(Minimap._direction_text(pair[0] * 100) == pair[1], "中文方位正确 " + pair[1])
	for label: Label in [_radar._category, _radar._target_name, _radar._direction, _radar._distance]:
		_check(Rect2(Vector2.ZERO, _radar.size).encloses(label.get_rect()), "文字安全留在240×120边界 " + label.name)
		_check(label.position.x > _radar._radar_rect().end.x, "文字不覆盖雷达绘图区 " + label.name)
	_player.visible = false
	_radar._refresh_navigation()
	_check(not _radar._has_player and _radar._target.is_empty(), "玩家死亡隐藏期间不显示旧位置目标")
	_radar.queue_free()
	_player.queue_free()
	await get_tree().process_frame
	WorldSim.stop()
	get_tree().paused = true
	await _test_world_roundtrips()
	get_tree().paused = false
	if _fails == 0:
		print("=== GAMEPLAY NAVIGATION PASSED (%d checks) ===" % _checks)
	get_tree().quit(0 if _fails == 0 else 1)


func _test_world_roundtrips() -> void:
	GameState.reset_all()
	GameState.world_seed = 20260908
	BiomeMap.configure(GameState.world_seed)
	GameState.ecology_snapshot = null
	for round in 3:
		var world := MAIN_SCENE.instantiate()
		add_child(world)
		await get_tree().process_frame
		await get_tree().process_frame
		var radar: Minimap = world.get_node("HUD/Root/Minimap")
		world._reveal_fog()
		radar._refresh_navigation()
		_check(not radar._target.is_empty(), "正常出生/继续冒险有真实附近方向 第%d轮" % round)
		if not radar._target.is_empty():
			var id: String = radar._target["id"]
			_check(id.begins_with("monster:"), "正常出生导航指向存活怪物 第%d轮" % round)
			var live: MonsterInstance = WorldSim.sim.instances.get(id.trim_prefix("monster:").to_int())
			_check(live != null and live.is_alive, "真实世界目标仍存活 第%d轮" % round)
			var player: Player = world.get_node("Player")
			var before: float = radar._target["distance_px"]
			player.position = player.position.move_toward(radar._target["pos"], 160)
			radar._refresh_navigation()
			_check(float(radar._target.get("distance_px", INF)) < before, "向目标正常移动后距离缩短 第%d轮" % round)
		# 真正读写存档后重建世界，重复验证不靠保留旧Control/Node引用。
		GameState.save_enabled = true
		_check(GameState.save_now(), "真实导航世界快照保存成功 第%d轮" % round)
		GameState.save_enabled = false
		world.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
		GameState._load()
		_check(WorldSim.sim == null, "世界退出释放雷达依赖 第%d轮" % round)
