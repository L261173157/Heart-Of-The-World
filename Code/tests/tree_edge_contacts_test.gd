## 树边接触回归：真实玩家/怪物场景与静态圆树干，保留生产身体和移动参数。
## 隔离导航/RVO，仅手动提供可达拐点速度；完整寻路闭环由 tree_edge_navigation 守闸。
## 三档世界坐标 × 玩家/普通/精英/大体型 × 八向，验证大坐标接触后能真实滑离。
## 怪物另走40/90px每秒的真实远档_move_and_collide两段滑行，保持6帧节流。
extends Node

const PLAYER := preload("res://scenes/player/player.tscn")
const GOBLIN := preload("res://scenes/monsters/goblin.tscn")
const FROG := preload("res://data/species/frog.tres")
const CENTERS := [Vector2.ZERO, Vector2(379472, 379568), Vector2(799472, 799568)]
const TREE_RADIUS := 9.0
const SPEED := 90.0
const FRAME_LIMIT := 240
## 80万坐标的单精度误差与初始贴边取证容差；不能允许身体穿过树干来“通过”。
const OVERLAP_TOLERANCE := 0.15
## 远档0.1秒两段扫掠的接触近似可略深于逐帧移动（原点也可达0.240px）；
## 0.30px覆盖80万坐标的额外舍入，仍小于0.5px恢复余量，远不足以穿过9px树干。
const FAR_OVERLAP_TOLERANCE := 0.30
var _cases: Array[Dictionary] = []
var _checks := 0
var _fails := 0
var _frames := 0
var _running := false


func _ready() -> void:
	GameState.save_enabled = false
	GameState.ecology_snapshot = null
	GameState.reset_all()
	WorldSim.stop()
	WorldSim.sim = EcologySim.new()
	BiomeMap.configure(BiomeMap.DEFAULT_SEED)
	ObstacleField.restore_destroyed([])
	TouchInput.reset()
	_run.call_deferred()


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])


func _run() -> void:
	for center: Vector2 in CENTERS:
		for variant in 4:
			for direction in 8:
				_make_case(center, variant, direction)
		for far_speed: float in [MonsterBase.PATROL_SPEED, 90.0]:
			for variant in range(1, 4):
				for direction in 8:
					_make_case(center, variant, direction, far_speed)
	for frame in 3:
		await get_tree().physics_frame
		await get_tree().process_frame
	_running = true


func _make_case(center: Vector2, variant: int, direction: int, far_speed := 0.0) -> void:
	# 独立物理世界使每例都使用精确相同的大坐标，不让邻例互碰或改换取整格。
	var viewport := SubViewport.new()
	viewport.world_2d = World2D.new()
	viewport.size = Vector2i(64, 64)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	var tree_body := StaticBody2D.new()
	tree_body.position = center
	tree_body.collision_layer = 1
	tree_body.collision_mask = 0
	var circle := CircleShape2D.new()
	circle.radius = TREE_RADIUS
	var trunk := CollisionShape2D.new()
	trunk.shape = circle
	tree_body.add_child(trunk)
	viewport.add_child(tree_body)
	var actor: CharacterBody2D
	var label := "玩家"
	if variant == 0:
		actor = PLAYER.instantiate()
		viewport.add_child(actor)
		actor.get_node("Camera2D").enabled = false
	else:
		var monster: MonsterBase = GOBLIN.instantiate()
		viewport.add_child(monster)
		var inst := MonsterInstance.new()
		inst.id = _cases.size() + 1
		inst.species = FROG
		inst.age = 8
		inst.size_scale = [1.0, 1.45, 2.2][variant - 1]
		inst.is_elite = variant == 2
		inst.spawn_pos = center + Vector2(100, 100)
		monster.setup(inst)
		monster._nav.avoidance_enabled = false
		actor = monster
		label = "蜥蜴体型%.2f" % inst.size_scale
	actor.set_process(false)
	actor.set_physics_process(false)
	var shape := actor.get_node("CollisionShape2D").shape as RectangleShape2D
	var half := shape.size * 0.5
	# 初始圆角贴边复用真实卡位的相对几何（16.2方体时为-10.3,-16.8）。
	# 每象限正反两向，覆盖上/下/左/右及顺逆时针滑离，身体本身不旋转。
	var angle := float(direction / 2) * PI * 0.5
	var mirror := -1.0 if direction % 2 == 1 else 1.0
	var start := Vector2((-half.x - 2.2) * mirror, -half.y - 8.7).rotated(angle)
	var corner := Vector2((half.x + TREE_RADIUS + 5.0) * mirror,
			-half.y - TREE_RADIUS - 0.5).rotated(angle)
	var goal := Vector2((half.x + TREE_RADIUS + 50.0) * mirror,
			half.y + TREE_RADIUS + 20.0).rotated(angle)
	actor.global_position = center + start
	if far_speed > 0.0:
		label += " 远档%.0fpx/s" % far_speed
	_cases.append({"actor": actor, "center": center, "half": half,
		"corner": center + corner, "goal": center + goal, "turned": false,
		"done": false, "contacts": 0, "overlap": 0.0,
		"far_speed": far_speed,
		"label": "%s 坐标%s 方向%d" % [label, center, direction]})


func _physics_process(delta: float) -> void:
	if not _running:
		return
	_frames += 1
	var all_done := true
	for entry in _cases:
		if entry.done:
			continue
		all_done = false
		if entry.far_speed > 0.0 and _frames % MonsterBase.LOD_STEP != 0:
			continue
		var actor: CharacterBody2D = entry.actor
		if actor.global_position.distance_to(entry.goal) <= 3.0:
			entry.done = true
			actor.velocity = Vector2.ZERO
			continue
		if actor.global_position.distance_to(entry.corner) <= 2.5:
			entry.turned = true
		var target: Vector2 = entry.goal if entry.turned else entry.corner
		if entry.far_speed > 0.0:
			# 拐点处仅截断最后不足一个步长的运动，避免夹具反复越过目标；
			# 其余步长与生产LOD相同。预扫证明真实树干接触，不能靠无碰撞空走通过。
			var motion := (target - actor.global_position).limit_length(
					float(entry.far_speed) * delta * MonsterBase.LOD_STEP)
			entry.contacts += int(actor.test_move(actor.global_transform, motion))
			(actor as MonsterBase)._far_move(motion)
		else:
			actor.velocity = actor.global_position.direction_to(target) * SPEED
			actor.move_and_slide()
			entry.contacts += actor.get_slide_collision_count()
		# 矩形与圆的独立几何验算，避免仅依赖同一物理查询产生假阴性。
		var gap: Vector2 = (actor.global_position - entry.center).abs() - entry.half
		gap = Vector2(maxf(gap.x, 0.0), maxf(gap.y, 0.0))
		entry.overlap = maxf(entry.overlap, TREE_RADIUS - gap.length())
	if all_done or _frames >= FRAME_LIMIT:
		_running = false
		_finish.call_deferred()


func _finish() -> void:
	for entry in _cases:
		_check(entry.done and entry.turned and entry.contacts > 0,
			"%s 接触树干后绕拐点抵达（接触%d次）" % [entry.label, entry.contacts])
		var tolerance := FAR_OVERLAP_TOLERANCE if entry.far_speed > 0.0 else OVERLAP_TOLERANCE
		_check(entry.overlap <= tolerance,
			"%s 未穿过树干（最大误差%.3fpx）" % [entry.label, entry.overlap])
	TouchInput.reset()
	WorldSim.stop()
	print("=== TREE EDGE CONTACTS %s (%d checks, %d frames) ===" % [
		"PASS" if _fails == 0 else "FAIL", _checks, _frames])
	get_tree().quit(0 if _fails == 0 else 1)
