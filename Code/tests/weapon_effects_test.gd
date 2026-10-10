## 赐福形态与玩家法弹回归：真实碰撞、生命周期、实际菜单和存档往返。
extends Node2D

class Target extends CharacterBody2D:
	var hits := 0
	var total := 0.0
	var knock := 0.0
	func take_damage(amount: float, _from := Vector2.INF, _heavy := false,
			p_knock := 1.0, _effective := false) -> void:
		hits += 1
		total += amount
		knock = p_knock

var _checks := 0
var _fails := 0
var _world: Node2D

func _ready() -> void:
	GameState.save_enabled = false
	WorldSim.stop()
	GameState.reset_all()
	_run.call_deferred()

func _run() -> void:
	_test_choices()
	await _test_save_and_ui()
	await _test_player_cast()
	await _test_radius_sweep()
	await _test_seek()
	await _test_split()
	await _test_pool()
	WorldSim.stop()
	print("=== WEAPON EFFECTS %s (%d checks) ===" % ["PASS" if _fails == 0 else "FAIL", _checks])
	get_tree().quit(0 if _fails == 0 else 1)

func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("  %s %s" % ["PASS" if ok else "FAIL", label])

func _frames(count := 3) -> void:
	for _i in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func _new_world() -> void:
	if is_instance_valid(_world):
		_world.queue_free()
		await _frames()
	PlayerBolt.clear_pool()
	_world = Node2D.new()
	add_child(_world)

func _target(pos: Vector2) -> Target:
	var body := Target.new()
	body.collision_layer = 2
	body.collision_mask = 0
	body.add_to_group("monsters")
	_shape(body, Vector2(18, 18))
	_world.add_child(body)
	body.position = pos
	return body

func _shape(body: CollisionObject2D, size: Vector2) -> void:
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = size
	shape.shape = rectangle
	body.add_child(shape)

func _wall(pos: Vector2, size: Vector2) -> StaticBody2D:
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	_shape(wall, size)
	_world.add_child(wall)
	wall.position = pos
	return wall

func _test_choices() -> void:
	var s := CharacterStats.new()
	s.pending_passive_picks = 5
	s.ensure_passive_choices()
	var offered_branch := false
	for id: String in s.passive_choices:
		offered_branch = offered_branch or id in CharacterStats.WEAPON_PASSIVES
	_check(offered_branch and s.passive_choices.size() == 3, "首升三选一至少含一个形态赐福")
	var choices := s.passive_choices.duplicate()
	var serial := s.passive_offer_id
	s.ensure_passive_choices()
	_check(s.passive_choices == choices and s.passive_offer_id == serial, "反复开卡不重抽")
	for id: String in CharacterStats.WEAPON_PASSIVES:
		var before := s.benefit_snapshot()
		var preview := s.preview_passive(id)
		_check(preview.has("effect") and s.benefit_snapshot() == before, id + "预览含形态取舍且无副作用")
		s.passive_choices.assign([id, "hp", "phys"])
		serial = s.passive_offer_id
		var pending := s.pending_passive_picks
		_check(s.claim_passive(id, serial), id + "合法卡领取")
		_check(not s.claim_passive(id, serial) and s.pending_passive_picks == pending - 1,
			id + "重复/旧凭证不再扣资格")
		s.add_passive(id)
		_check(s.passive_level(id) == 1 and s.benefit_snapshot() == preview["after"],
			id + "最多一阶，真实结果等于展示预览")
		_check(not s.passive_choices.has(id), id + "已学分支退出卡池")
	_check(is_equal_approx(s.sword_arc_bonus(), deg_to_rad(20)) and s.sword_damage_mult() == 0.85,
		"阔刃增半角20度且保留85%普攻伤害")
	s.passive_choices.assign(["bolt_seek", "bogus", "hp"])
	s.ensure_passive_choices()
	_check(s.passive_choices.size() == 3 and not s.passive_choices.has("bolt_seek")
		and not s.passive_choices.has("bogus"), "损坏/满阶卡安全重建，不提供空收益选择")
	s.add_passive("bogus")
	_check(not s.passives.has("bogus"), "未知赐福不注入角色")

func _test_save_and_ui() -> void:
	GameState.reset_all()
	GameState.stats.level = 5
	GameState.stats.pending_passive_picks = 3
	GameState.stats.passives = {"bolt_seek": 1, "phys": 2}
	GameState.stats.passive_choices.assign(["sword_sweep", "bolt_split", "hp"])
	GameState.stats.passive_offer_id = 27
	GameState.gold = 231
	GameState.save_enabled = true
	_check(GameState.save_now(false), "形态赐福写入隔离存档")
	GameState.save_enabled = false
	GameState.stats.reset()
	GameState._load()
	_check(GameState.stats.passive_level("bolt_seek") == 1 and GameState.stats.passive_level("phys") == 2
		and GameState.stats.passive_choices == ["sword_sweep", "bolt_split", "hp"]
		and GameState.stats.passive_offer_id == 27 and GameState.gold == 231,
		"重载保留赐福、三张卡、凭证和既有养成")
	var hud: CanvasLayer = preload("res://scenes/ui/hud.tscn").instantiate()
	add_child(hud)
	await get_tree().process_frame
	_check(not hud.passive_layer.visible and not get_tree().paused
		and GameState.stats.pending_passive_picks == 3, "冷读档保留赐福资格，不自动打开选卡")
	await _touch_control(hud.get_node("Root/PauseBtn"))
	await _touch_control(hud.pause_layer.find_child("MenuGrowth", true, false))
	await _touch_control(hud._stats_overview_layer.find_child("OpenBlessing", true, false))
	_check(hud.passive_layer.visible and get_tree().paused, "明确成长菜单打开三选一赐福阅读层")
	var card: Button = hud.passive_cards[1]
	_check(card.text.contains("上限1") and card.text.contains("80%") and card.text.contains("35%")
		and card.text.contains("不再分裂"), "真实三选一卡显示效果、上限与伤害取舍")
	# 走真实触屏 GUI，不直接调用 claim_passive。
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.position = card.get_global_rect().get_center()
	touch.pressed = true
	get_viewport().push_input(touch, true)
	await get_tree().process_frame
	touch = InputEventScreenTouch.new()
	touch.index = 0
	touch.position = card.get_global_rect().get_center()
	touch.pressed = false
	get_viewport().push_input(touch, true)
	await get_tree().process_frame
	_check(GameState.stats.passive_level("bolt_split") == 1 and GameState.stats.pending_passive_picks == 2,
		"真实触屏选取碎星且仅消耗一次")
	_check(hud._passive_owned.text.contains("碎星1阶（满）"), "已获构筑显示满阶形态")
	hud.queue_free()
	get_tree().paused = false
	await get_tree().process_frame
	# 旧档没有新字段，不丢原数字赐福，不凭空解锁分支。
	var file := FileAccess.open(GameState.SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": 6, "level": 5, "passives": {"hp": 2, "magic": 1}, "gold": 123}))
	file.close()
	GameState._load()
	_check(GameState.stats.passives == {"hp": 2, "magic": 1} and GameState.stats.pending_passive_picks == 1
		and GameState.gold == 123, "旧档保留成长并只补遗失领取资格")
	file = FileAccess.open(GameState.SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": 8, "level": 5, "passives": {"bolt_seek": 99, "unknown": 9},
		"pending_passive_picks": 2, "passive_choices": ["bolt_seek", "hp", "phys"], "passive_offer_id": 50}))
	file.close()
	GameState._load()
	_check(GameState.stats.passives == {"bolt_seek": 1} and not GameState.stats.passive_choices.has("bolt_seek")
		and GameState.stats.passive_offer_id == 51 and GameState.stats.pending_passive_picks == 2,
		"损坏档限一阶、移除未知项、作废满阶旧凭证，剩余资格保留")
	GameState.reset_all()

func _test_player_cast() -> void:
	await _new_world()
	GameState.stats.passives = {"bolt_seek": 1, "bolt_split": 1}
	var player: Player = preload("res://scenes/player/player.tscn").instantiate()
	_world.add_child(player)
	player.set_process(false) # 本段隔离自然回蓝，精确核对施法费用。
	player.position = Vector2(500, 500)
	player.current_mp = player.stats.max_mp()
	player.facing = Vector2.RIGHT
	await _frames()
	var mp := player.current_mp
	TouchInput.queue_bolt()
	await _frames(2)
	_check(get_tree().get_nodes_in_group("player_bolts").is_empty(), "真实触屏法弹前摇不提前出弹")
	await _frames(10)
	var bolts := get_tree().get_nodes_in_group("player_bolts")
	_check(bolts.size() == 1 and bolts[0]._seek and bolts[0]._split
		and player._bolt_cd > 0.0 and absf(player.current_mp - (mp - CharacterStats.BOLT_COST)) < 0.2,
		"真实触屏法弹沿用8精力与冷却，同时装配两种已获形态")
	TouchInput.queue_bolt()
	await _frames(2)
	_check(get_tree().get_nodes_in_group("player_bolts").size() == 1
		and player.current_mp > mp - CharacterStats.BOLT_COST - 0.01,
		"真实重复触屏仍被冷却挡住，不多扣精力或额外出弹")
	GameState.stats.passives = {}

func _test_radius_sweep() -> void:
	# 端点和中心线都不碰墙，只有帧中间的圆形弹核擦到角。
	for origin: Vector2 in [Vector2.ZERO, Vector2(50000, 50000), Vector2(790000, 790000)]:
		for direction: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
			await _new_world()
			var wall_pos := origin + Vector2(3.5, 57.9).rotated(direction.angle())
			_wall(wall_pos, Vector2(1, 100) if direction.y == 0 else Vector2(100, 1))
			await _frames()
			var bolt := PlayerBolt.spawn(_world, origin, direction, 10)
			bolt.set_physics_process(false)
			bolt._physics_process(1.0 / 60.0)
			_check(bolt._hit and bolt.position.distance_to(origin) < 7.0,
				"8px圆核连续扫掠拦截两端不相交的薄墙角擦 " + str(direction) + " @" + str(origin))
	await _new_world()
	_wall(Vector2(85, 0), Vector2(1, 80))
	var target := _target(Vector2(160, 0))
	await _frames()
	var bolt := PlayerBolt.spawn(_world, Vector2.ZERO, Vector2.RIGHT, 20)
	bolt.set_physics_process(false)
	bolt._physics_process(0.5)
	_check(bolt._hit and bolt.position.x < 85 and target.hits == 0,
		"长帧连续扫掠先撞1px墙，不跃过墙命中后方目标")
	await _new_world()
	_wall(Vector2.ZERO, Vector2(30, 30))
	await _frames()
	bolt = PlayerBolt.spawn(_world, Vector2.ZERO, Vector2.RIGHT, 20, "", {"split": true})
	bolt.set_physics_process(false)
	bolt._physics_process(0.25)
	_check(bolt._hit and bolt.position == Vector2.ZERO, "出生在墙内立即消散，不被cast_motion初始重叠排除")
	await _frames()
	_check(get_tree().get_nodes_in_group("player_bolts").is_empty(), "出生撞墙不会分裂")

func _test_seek() -> void:
	await _new_world()
	var target := _target(Vector2(155, 65))
	await _frames()
	var bolt := PlayerBolt.spawn(_world, Vector2.ZERO, Vector2.RIGHT, 20, "", {"seek": true})
	await _frames(9)
	_check(bolt.direction.y > 0.1 and bolt._seek_scans <= 3 and bolt._speed == PlayerBolt.SPEED * 0.85,
		"真实物理帧向前方活体微调且索敌节流/速度取舍生效")
	await _frames(30)
	_check(target.hits == 1 and is_equal_approx(target.total, 20.0) and target.knock == 0.6,
		"寻星真实命中偏轴目标一次，伤害保留且击退轻于近战")
	await _new_world()
	target = _target(Vector2(155, 60))
	_wall(Vector2(70, 20), Vector2(2, 190))
	await _frames()
	bolt = PlayerBolt.spawn(_world, Vector2.ZERO, Vector2.RIGHT, 20, "", {"seek": true})
	await _frames(4)
	_check(bolt._target == null and bolt.direction == Vector2.RIGHT, "两像素薄墙后目标不会被锁定")
	await _frames(24)
	_check(target.hits == 0 and not bolt.is_inside_tree(), "真实薄墙拦截寻星，无穿墙伤害")
	await _new_world()
	target = _target(Vector2(200, 40))
	var rear := _target(Vector2(-40, 0))
	await _frames()
	bolt = PlayerBolt.spawn(_world, Vector2.ZERO, Vector2.RIGHT, 20, "", {"seek": true})
	await _frames(3)
	_check(bolt._target == target, "正面活体成为目标")
	target.queue_free()
	await _frames(5)
	_check(is_instance_valid(bolt) and bolt._target == null and bolt.direction.x > 0.0 and rear.hits == 0,
		"目标死亡/删除后安全直飞，不反向追身后敌人")
	await _frames(95)
	_check(not bolt.is_inside_tree(), "失去目标的法弹照常超时回收")
	await _new_world()
	if WorldSim.sim == null:
		WorldSim.sim = EcologySim.new()
	var corpse: MonsterBase = preload("res://scenes/monsters/slime.tscn").instantiate()
	_world.add_child(corpse)
	var inst := MonsterInstance.new()
	inst.species = load("res://data/species/slime.tres")
	inst.age = 200
	inst.spawn_pos = Vector2(70, 0)
	corpse.setup(inst)
	corpse.position = inst.spawn_pos
	corpse.set_physics_process(false)
	corpse.state = MonsterBase.S_CORPSE
	target = _target(Vector2(150, 0))
	await _frames()
	bolt = PlayerBolt.spawn(_world, Vector2.ZERO, Vector2.RIGHT, 20, "", {"seek": true})
	await _frames(36)
	_check(target.hits == 1, "真实MonsterBase尸体既不索敌也不吸收飞向后方活体的弹")

func _test_split() -> void:
	await _new_world()
	var main := _target(Vector2(85, 0))
	# 第二份重叠形状验证同帧多回调不能多次分裂。
	_shape(main, Vector2(18, 18))
	var upper := _target(Vector2(175, -51))
	var lower := _target(Vector2(175, 51))
	await _frames()
	PlayerBolt.spawn(_world, Vector2.ZERO, Vector2.RIGHT, 100, "", {"split": true, "seek": true})
	await _frames(17)
	var shards: Array = get_tree().get_nodes_in_group("player_bolts")
	var shard_count := 0
	for item: PlayerBolt in shards:
		if item._generation == 1:
			shard_count += 1
			_check(not item._split and not item._seek and item.damage == 35.0
				and item._life <= PlayerBolt.SHARD_LIFE_TIME, "每枚碎片35%伤害、短寿命、无追踪无递归")
	_check(main.hits == 1 and main.total == 80.0 and shard_count == 2,
		"同帧重叠形状只造成80%主伤害并产生恰好两片")
	await _frames(35)
	_check(upper.hits == 1 and lower.hits == 1 and upper.total == 35.0 and lower.total == 35.0
		and upper.knock == 0.35, "两枚碎片真实命中侧后目标，各一次且轻击退")
	_check(get_tree().get_nodes_in_group("player_bolts").is_empty(), "碎片命中后不再生成下一代")
	await _new_world()
	main = _target(Vector2(85, 0))
	upper = _target(Vector2(175, -51))
	lower = _target(Vector2(175, 51))
	_wall(Vector2(115, 0), Vector2(3, 220))
	await _frames()
	PlayerBolt.spawn(_world, Vector2.ZERO, Vector2.RIGHT, 100, "", {"split": true})
	await _frames(50)
	_check(main.hits == 1 and upper.hits == 0 and lower.hits == 0
		and get_tree().get_nodes_in_group("player_bolts").is_empty(), "分裂不越过目标后的墙，撞墙不再次分裂")

func _test_pool() -> void:
	await _new_world()
	var ignored_target := _target(Vector2(1000, 1000))
	var bolt := PlayerBolt.spawn(_world, Vector2(500, 500), Vector2.DOWN, 70, "fire", {"seek": true, "split": true})
	bolt._ignore_rid = ignored_target.get_rid()
	bolt._target = ignored_target
	bolt._seek_scans = 9
	bolt._seek_timer = 0.1
	bolt.modulate = Color.RED
	bolt.scale = Vector2(2, 2)
	bolt._generation = 1
	bolt._life = 0.01
	bolt._release()
	bolt._release()
	_check(PlayerBolt._pool.is_empty(), "物理回调内回收先同步关闸，不提前借出")
	await _frames()
	_check(PlayerBolt._pool.size() == 1, "重复回收只入池一次")
	var reused := PlayerBolt.spawn(_world, Vector2(700, 500), Vector2.LEFT, 10)
	_check(reused == bolt and reused.visible and reused.monitoring and reused.is_physics_processing()
		and not reused._hit and not reused._seek and not reused._split and reused._target == null
		and reused._generation == 0 and reused._life == PlayerBolt.LIFE_TIME and reused.damage == 10.0
		and reused.player_element == "" and not reused._ignore_rid.is_valid() and reused.direction == Vector2.LEFT
		and reused._seek_scans == 0 and reused._seek_timer == 0.0 and reused.modulate == Color.WHITE,
		"池复用重置特效/寻敌/分裂代数/目标/忽略体/寿命/伤害/可见碰撞全部状态")
	var shape: CollisionShape2D = reused.get_node("HitShape")
	_check((shape.shape as CircleShape2D).radius == PlayerBolt.HIT_RADIUS and reused.scale == Vector2.ONE,
		"16px实心弹核与真实圆形碰撞同尺度")
	reused._release()
	PlayerBolt.clear_pool()
	await _frames()
	_check(not is_instance_valid(reused) and PlayerBolt._pool.is_empty(), "清池使尚未完成的旧回收失效")
	for i in PlayerBolt.POOL_MAX + 5:
		var p := PlayerBolt.spawn(_world, Vector2(i * 30, 900), Vector2.RIGHT, 5)
		p._release()
	await _frames()
	_check(PlayerBolt._pool.size() == PlayerBolt.POOL_MAX, "批量回收池上限守住24个")
	_world.queue_free()
	await _frames()
	_check(PlayerBolt._pool.is_empty(), "世界退场自动释放静态池，无漏对象")
	await _new_world()
	var target := _target(Vector2(80, 0))
	await _frames()
	bolt = PlayerBolt.spawn(_world, Vector2.ZERO, Vector2.RIGHT, 100, "", {"split": true})
	bolt._on_body_shape_entered(target.get_rid(), target, 0, 0)
	_world.queue_free()
	await _frames()
	_check(PlayerBolt._pool.is_empty() and get_tree().get_nodes_in_group("player_bolts").is_empty(),
		"命中待分裂瞬间退出世界不会生成孤立碎片或污染下一世界")


func _touch_control(control: Control) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var touch := InputEventScreenTouch.new()
	touch.index = 71
	touch.position = get_viewport().get_screen_transform() * control.get_global_rect().get_center()
	touch.pressed = true
	Input.parse_input_event(touch)
	await get_tree().process_frame
	touch = touch.duplicate()
	touch.pressed = false
	Input.parse_input_event(touch)
	await get_tree().process_frame
	await get_tree().process_frame
