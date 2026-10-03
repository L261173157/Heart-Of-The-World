## 战斗玩法回归：真实物理帧/真实子类/真实障碍形状，不绕过正常状态分派。
extends Node2D

const BOAR := preload("res://scenes/monsters/boar.tscn")
const ANT := preload("res://scenes/monsters/ant.tscn")
const DIRS := [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]
var _checks := 0
var _fails := 0
var _next_id := 0

class Target extends CharacterBody2D:
	var hits := 0
	var total_damage := 0.0
	func take_damage(amount: float, _from := Vector2.INF, _source := "",
			_attack_context: Dictionary = {}) -> void:
		hits += 1
		total_damage += amount

class BoltTarget extends StaticBody2D:
	var hits := 0
	var total_damage := 0.0
	func take_damage(amount: float, _from := Vector2.INF, _heavy := false,
			_knock := 1.0, _effective := false) -> void:
		hits += 1
		total_damage += amount

func _ready() -> void:
	GameState.save_enabled = false
	WorldSim.stop()
	WorldSim.sim = EcologySim.new()
	BiomeMap.configure(BiomeMap.DEFAULT_SEED)
	ObstacleField.restore_destroyed([])
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])

func _rect_shape(body: CollisionObject2D, size: Vector2) -> void:
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	body.add_child(shape)

func _target(pos: Vector2) -> Target:
	var target := Target.new()
	target.collision_layer = 1
	target.collision_mask = 3
	_rect_shape(target, Vector2(20, 20))
	add_child(target)
	target.position = pos
	return target

func _monster(id: String, scene: PackedScene, pos: Vector2, size := 1.0) -> MonsterBase:
	var monster: MonsterBase = scene.instantiate()
	add_child(monster)
	monster.set_physics_process(false)
	var inst := MonsterInstance.new()
	_next_id += 1
	inst.id = _next_id
	inst.species = load("res://data/species/%s.tres" % id).duplicate()
	inst.age = 200
	inst.size_scale = size
	inst.is_elite = is_equal_approx(size, 1.45)
	inst.spawn_pos = pos
	monster.setup(inst)
	monster.position = pos
	return monster

func _run() -> void:
	await _charges()
	await _charge_obstructions()
	await _real_player_charge()
	await _soldiers()
	await _bolts()
	WorldSim.stop()
	print("=== GAMEPLAY COMBAT %s (%d checks) ===" % ["PASS" if _fails == 0 else "FAIL", _checks])
	get_tree().quit(0 if _fails == 0 else 1)

func _charges() -> void:
	var cases: Array[Dictionary] = []
	# 所有当前冲锋物种、普通/精英/Boss、四方向、不同起步相位及实际速度。
	# 每个用例均从 CHASE 自行经过前摇；半数保留正常 RVO 回调。
	for id in ["boar", "penguin", "squirrel", "turtle", "bear", "treant"]:
		for size in ([2.2] if id == "treant" else [1.0, 1.45]):
			for dir: Vector2 in DIRS:
				for dist in [180.0, 195.0, 210.0]:
					for speed in [1.0, 4.0]:
						var n := cases.size()
						var target := _target(Vector2(1000 + (n % 24) * 1000, 1000 + (n / 24) * 1000))
						var monster := _monster(id, BOAR, target.position - dir * dist, size) as Boar
						monster._player_ref = target
						monster.inst.species.charge_speed_mult *= speed
						monster._nav.avoidance_enabled = (n + int(dist)) % 2 == 0
						monster.state = MonsterBase.S_CHASE
						cases.append({"m": monster, "p": target, "done": false, "tell": false,
							"charge": false, "label": "%s size%s dir%s distance%s speed%s RVO%s" %
							[id, size, dir, dist, speed, monster._nav.avoidance_enabled]})
	await get_tree().physics_frame
	for c in cases:
		c.m.set_physics_process(true)
	for frame in 160:
		await get_tree().physics_frame
		await get_tree().process_frame
		for c in cases:
			if c.done:
				continue
			var monster: Boar = c.m
			c.tell = c.tell or monster.state == Boar.S_TELL
			c.charge = c.charge or monster.state == Boar.S_CHARGE
			if monster._attack_cd > 0.0:
				c.done = true
				monster.set_physics_process(false)
				_check(c.tell and c.charge and c.p.hits == 1 and monster.state == Boar.S_TIRED,
					"冲锋命中且仅结算一次：" + c.label)
				var base := monster.inst.attack_power() * monster.inst.species.charge_damage_mult
				_check(c.p.total_damage >= base * 0.9 - 0.01 and c.p.total_damage <= base * 1.1 + 0.01,
					"冲锋保持伤害倍率：" + c.label)
	for c in cases:
		_check(c.done, "正常状态机冲锋完成：" + c.label)
		c.m.queue_free()
		c.p.queue_free()
	await get_tree().process_frame
	# 没有实体接触时仍需扫过命中窗：每帧 200px，前后端点均在范围外。
	for dir: Vector2 in DIRS:
		var target := _target(Vector2(40000, 40000))
		target.collision_layer = 0
		var monster := _monster("boar", BOAR, target.position - dir * 100) as Boar
		monster._player_ref = target
		monster._nav.avoidance_enabled = false
		monster.inst.species.charge_speed_mult = 12000.0 / monster.inst.move_speed()
		monster.state = MonsterBase.S_CHASE
		monster.set_physics_process(true)
		await get_tree().create_timer(0.7, true, true).timeout
		_check(target.hits == 1 and monster.state == Boar.S_TIRED, "高速扫过而非端点距离命中 %s" % dir)
		monster.queue_free()
		target.queue_free()
		await get_tree().process_frame

func _charge_obstructions() -> void:
	for dir: Vector2 in DIRS:
		var target := _target(Vector2(50000, 50000))
		var monster := _monster("treant", BOAR, target.position - dir * 200, 2.2) as Boar
		monster._player_ref = target
		monster._nav.avoidance_enabled = false
		monster.state = MonsterBase.S_CHASE
		var wall := StaticBody2D.new()
		wall.collision_layer = 1
		_rect_shape(wall, Vector2(10, 300) if dir.x != 0 else Vector2(300, 10))
		add_child(wall)
		wall.position = target.position - dir * 75
		monster.set_physics_process(true)
		await get_tree().create_timer(1.1, true, true).timeout
		_check(target.hits == 0 and monster.state == Boar.S_TIRED, "Boss 撞墙硬直不穿墙伤人 %s" % dir)
		monster.queue_free()
		target.queue_free()
		wall.queue_free()
		await get_tree().process_frame
	# 同伴拦截无硬直，超时无硬直；避免把全部非玩家接触粗暴归为墙。
	var target := _target(Vector2(50000, 50000))
	var monster := _monster("boar", BOAR, target.position - Vector2(200, 0)) as Boar
	var ally := _monster("boar", BOAR, target.position - Vector2(90, 0))
	monster._player_ref = target
	monster._nav.avoidance_enabled = false
	monster.state = MonsterBase.S_CHASE
	monster.set_physics_process(true)
	await get_tree().create_timer(1.0, true, true).timeout
	_check(target.hits == 0 and monster.state == MonsterBase.S_CHASE and monster._attack_cd > 0.0,
		"同伴截断冲锋但不白送撞墙硬直")
	monster.queue_free()
	ally.queue_free()
	target.queue_free()
	await get_tree().process_frame
	# 玩家在预警锁定方向之后躲开，必须真实落空而非追踪必中。
	target = _target(Vector2(50000, 50000))
	monster = _monster("boar", BOAR, target.position - Vector2(200, 0)) as Boar
	monster._player_ref = target
	monster._nav.avoidance_enabled = false
	monster.state = MonsterBase.S_CHASE
	monster.set_physics_process(true)
	await get_tree().create_timer(0.15, true, true).timeout
	target.position.y += 180
	await get_tree().create_timer(1.4, true, true).timeout
	_check(target.hits == 0 and monster.state != Boar.S_TIRED, "躲开锁定直线，冲锋超时不硬直")
	monster.queue_free()
	target.queue_free()
	await get_tree().process_frame

func _real_player_charge() -> void:
	# 真实玩家节点的受伤/击退/无敌帧契约不能被 Target 夹具掩盖。
	for dir: Vector2 in DIRS:
		for invincible in [false, true]:
			var player: Player = preload("res://scenes/player/player.tscn").instantiate()
			add_child(player)
			player.set_physics_process(false)
			player.set_process(false)
			player.get_node("Camera2D").enabled = false
			player.position = Vector2(50000, 50000)
			player.current_hp = 10000.0
			player._protect_timer = 0.0
			player._hurt_iframes = 0.0
			player._dash_timer = 1.0 if invincible else 0.0
			var monster := _monster("treant", BOAR, player.position - dir * 200, 2.2) as Boar
			monster.state = MonsterBase.S_CHASE
			monster.set_physics_process(true)
			await get_tree().create_timer(1.2, true, true).timeout
			_check(monster.state == Boar.S_TIRED and (is_equal_approx(player.current_hp, 10000.0)
				if invincible else player.current_hp < 10000.0),
				"真实玩家 %s 冲刺无敌%s 与巨体冲锋接触" % [dir, invincible])
			if not invincible:
				_check(player._knockback.dot(dir) > 0.0 and player.last_killed_by == monster.inst.display_name(),
					"真实玩家冲锋受伤保留击退和来源 %s" % dir)
			monster.queue_free()
			player.queue_free()
			await get_tree().process_frame

func _soldiers() -> void:
	for id in ["beetle", "sprout", "cyclope", "stag_beetle_king"]:
		for pack in [0, 5]:
			var target := _target(Vector2(1000, 1000))
			var monster := _monster(id, ANT, target.position + Vector2(25, 0)) as Ant
			monster._player_ref = target
			monster._nav.avoidance_enabled = false
			monster.state = MonsterBase.S_ATTACK
			var allies: Array[MonsterBase] = []
			for n in pack:
				var ally := _monster(id, ANT, monster.position + Vector2(0, 60 + n * 5))
				allies.append(ally)
			monster.set_physics_process(true)
			await get_tree().create_timer(0.1, true, true).timeout
			_check(target.hits == 0 and monster._melee_windup > 0.0, "%s 真实近战前摇不提前扣血" % id)
			await get_tree().create_timer(0.2, true, true).timeout
			_check(target.hits == 1 and monster.visual.animation == &"attack" and monster._action_anim_timer > 0.0,
				"%s 协同%s 实际攻击分派启动挥击" % [id, pack])
			_check(monster.visual.flip_h, "%s 挥击面向实际玩家" % id)
			var base := monster.inst.attack_power() * (1.0 + monster.inst.species.pack_bonus_per
				* mini(pack, monster.inst.species.pack_bonus_max))
			_check(target.total_damage >= base * 0.9 - 0.01 and target.total_damage <= base * 1.1 + 0.01,
				"%s 协同%s 原有加成/上限不变" % [id, pack])
			monster.queue_free()
			target.queue_free()
			for ally in allies:
				ally.queue_free()
			await get_tree().process_frame

func _find_cells() -> Dictionary:
	var found := {}
	for patch: Dictionary in BiomeMap.patches():
		var center := Vector2i(patch.center / ObstacleField.CELL)
		for x in range(25, 250, 3):
			for y in range(25, 250, 3):
				var cell := center + Vector2i(x, y)
				var sample := ObstacleField.sample_cell(cell)
				if not sample.is_empty() and not found.has(sample.kind):
					found[sample.kind] = cell
			if found.has("rock") and found.has("crystal") and found.has("tree"):
				return found
	return found

func _fire(pos: Vector2, dir: Vector2) -> PlayerBolt:
	var bolt := PlayerBolt.new()
	add_child(bolt)
	bolt.position = pos
	bolt.launch(dir, 40.0)
	return bolt

func _bolts() -> void:
	var cells := _find_cells()
	for kind in ["rock", "crystal", "tree"]:
		_check(cells.has(kind), "种子生成真实 %s 障碍夹具" % kind)
		if not cells.has(kind):
			continue
		for dir: Vector2 in DIRS:
			ObstacleField.restore_destroyed([])
			var cell: Vector2i = cells[kind]
			var pos := (Vector2(cell) + Vector2(0.5, 0.5)) * ObstacleField.CELL
			# 真正的障碍层工厂及每格形状注册；加一个远处形状，防误用 body 原点或首形状。
			var layer := ObstacleTileLayer.new()
			add_child(layer)
			var body := ObstacleTileLayer._make_obstacle_body()
			var decoy := CollisionShape2D.new()
			decoy.shape = CircleShape2D.new()
			decoy.position = pos + Vector2(200, 200)
			body.add_child(decoy)
			var shape := CollisionShape2D.new()
			var circle := CircleShape2D.new()
			circle.radius = ObstacleField.KIND_INFO[kind].r
			shape.shape = circle
			shape.position = pos
			body.add_child(shape)
			layer.add_child(body)
			layer._bodies[Vector2i.ZERO] = {"body": body, "shapes": {cell: shape}}
			var events: Array = []
			var on_destroyed := func(c: Vector2i, _p: Vector2, k: String) -> void: events.append([c, k])
			EventBus.obstacle_destroyed.connect(on_destroyed)
			await get_tree().physics_frame
			for n in 2:
				var bolt := _fire(pos - dir * 61.0, dir)
				await get_tree().create_timer(0.25, true, true).timeout
				_check(not is_instance_valid(bolt), "%s %s 第%d发被真实 StaticBody2D 阻挡" % [kind, dir, n + 1])
				if kind != "tree" and n == 0:
					_check(ObstacleField._obstacle_hp.get(cell, -1) == 1 and events.is_empty(),
						"%s %s 首发仅扣一次耐久" % [kind, dir])
			if kind == "tree":
				_check(ObstacleField.is_obstacle_cell(cell) and events.is_empty(), "永久树墙不被法弹破坏")
			else:
				_check(not ObstacleField.is_obstacle_cell(cell) and events == [[cell, kind]],
					"%s %s 两发破坏命中格并仅广播一次" % [kind, dir])
				_check(not is_instance_valid(shape), "%s %s 真实障碍层移除碰撞形状" % [kind, dir])
			EventBus.obstacle_destroyed.disconnect(on_destroyed)
			layer.queue_free()
			await get_tree().process_frame
	# 普通边界墙仍挡弹，巢穴仍走伤害分支；重叠形状不让单发重复扣血。
	for nest in [false, true]:
		var body := BoltTarget.new()
		body.collision_layer = 4 if nest else 1
		if nest:
			body.add_to_group("nests")
		_rect_shape(body, Vector2(20, 20))
		_rect_shape(body, Vector2(20, 20))
		add_child(body)
		body.position = Vector2(50000, 50000)
		await get_tree().physics_frame
		var bolt := _fire(body.position - Vector2(60, 0), Vector2.RIGHT)
		await get_tree().create_timer(0.25, true, true).timeout
		_check(not is_instance_valid(bolt) and body.hits == (1 if nest else 0),
			"法弹巢穴单次命中" if nest else "普通墙消弹不冒充可破坏障碍")
		body.queue_free()
		await get_tree().process_frame
