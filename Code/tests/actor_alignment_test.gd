## 精灵定位回归：真实场景/物理/输入，最终吸附不能累计回写到下一帧锚点。
## 不调用定位辅助函数；同时守住小数物理位移、整数绘制和原有帧内容脚点。
extends Node2D

const PLAYER := preload("res://scenes/player/player.tscn")
const GOBLIN := preload("res://scenes/monsters/goblin.tscn")
const BOAR := preload("res://scenes/monsters/boar.tscn")
const MAX_ERROR := 0.71 # 单次二维四舍五入最大 sqrt(0.5²+0.5²)
const GRID_ERROR := 0.08 # 80 万世界坐标的单精度变换误差上限
const DIRS := [Vector2.RIGHT, Vector2(1, 1), Vector2.DOWN,
	Vector2(-1, 1), Vector2.LEFT, Vector2(-1, -1),
	Vector2.UP, Vector2(1, -1)]
var _checks := 0
var _fails := 0
var _watched: Array[Dictionary] = []
var _next_id := 0

func _ready() -> void:
	GameState.save_enabled = false
	GameState.ecology_snapshot = null
	GameState.reset_all()
	GameState.stats.intellect = 50 # 只扩资源池，运动数值与正常玩家相同
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

func _watch(actor: Node2D, base: Vector2, label: String) -> Dictionary:
	var entry := {"actor": actor, "base": base, "label": label, "error": 0.0,
		"grid": 0.0, "fractional": 0, "samples": 0}
	_watched.append(entry)
	return entry

func _observe() -> void:
	for entry in _watched:
		var actor: Node2D = entry.actor
		var sprite: AnimatedSprite2D = actor.get_node("Visual")
		# 预期锚点独立来自实例化前的场景位置，绝不读取已吸附的局部位置作基准。
		entry.error = maxf(entry.error, sprite.global_position.distance_to(actor.to_global(entry.base)))
		# 普通怪死亡会把整个本体侧转 90°；尸体只要求锚点误差有界，不重写旧侧倒演出。
		if not (actor is MonsterBase and actor.state == MonsterBase.S_CORPSE):
			entry.grid = maxf(entry.grid, sprite.global_position.distance_to(sprite.global_position.round()))
		if actor.global_position.distance_to(actor.global_position.round()) > 0.1:
			entry.fractional += 1
		entry.samples += 1

func _step(count := 1) -> void:
	for frame in count:
		await get_tree().physics_frame
		await get_tree().process_frame
		_observe()

func _finish(entry: Dictionary, require_fractional := true) -> void:
	_check(entry.samples > 0 and entry.error <= MAX_ERROR,
		"%s 锚点偏差 ≤0.71px（最大 %.3f / %d 帧）" % [entry.label, entry.error, entry.samples])
	_check(entry.grid <= GRID_ERROR, "%s 每帧最终位置仍在像素网格（最大 %.3f）" % [entry.label, entry.grid])
	if require_fractional:
		_check(entry.fractional > 2, "%s 不把物理本体取整（小数位置 %d 帧）" % [entry.label, entry.fractional])
	_watched.erase(entry)

func _player(pos: Vector2, base := Vector2.ZERO) -> Player:
	var actor: Player = PLAYER.instantiate()
	actor.get_node("Visual").position = base
	add_child(actor)
	actor.get_node("Camera2D").enabled = false
	actor.global_position = pos
	return actor

func _press(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)

func _release(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = false
	Input.parse_input_event(event)

func _run() -> void:
	await _eight_directions()
	await _combat_wall_lifecycle()
	await _authored_anchor()
	await _monster_paths()
	_frame_anchors()
	TouchInput.reset()
	WorldSim.stop()
	print("=== ACTOR ALIGNMENT %s (%d checks) ===" % ["PASS" if _fails == 0 else "FAIL", _checks])
	get_tree().quit(0 if _fails == 0 else 1)

func _eight_directions() -> void:
	var player := _player(Vector2(21888.25, 60301.375))
	TouchInput.joystick_active = true
	for index in DIRS.size():
		var dir: Vector2 = DIRS[index].normalized()
		# 同一角色连续运动、不重设 Visual；大坐标和八方向覆盖误差正负变化。
		if index == 4:
			player.global_position = Vector2(753707.25, 738957.375)
		var entry := _watch(player, Vector2.ZERO, "八方向 %d 行走/两次冲刺/停步" % index)
		TouchInput.move_vector = dir * 0.413
		var start := player.global_position
		await _step(48)
		_check((player.global_position - start).dot(dir) > 40.0, "方向 %d 真正小数速度行走" % index)
		for repeat in 2:
			# 使用真实冷却，不直接把 _dash_cd 清零伪造连续冲刺。
			for cooldown_frame in 90:
				if player._dash_cd <= 0.0:
					break
				await _step()
			var before_dash := player.global_position
			if repeat == 0:
				_press("dash")
			else:
				TouchInput.queue_dash()
			await _step()
			_release("dash")
			_check(player._dash_timer > 0.0, "方向 %d 第 %d 次真实输入启动冲刺" % [index, repeat + 1])
			await _step(14)
			_check(player._dash_timer <= 0.0 and (player.global_position - before_dash).dot(dir) > 85.0,
				"方向 %d 第 %d 次冲刺完成且位移未被吸附破坏" % [index, repeat + 1])
		TouchInput.move_vector = Vector2.ZERO
		await _step(8)
		_finish(entry)
	TouchInput.reset()
	player.queue_free()
	await get_tree().process_frame

func _combat_wall_lifecycle() -> void:
	var player := _player(Vector2(21888.25, 60301.375))
	var entry := _watch(player, Vector2.ZERO, "冲刺战斗/墙/击退/暂停/死亡重生")
	TouchInput.joystick_active = true
	TouchInput.move_vector = Vector2.RIGHT * 0.413
	await _step(90) # 先累计真实行走，旧实现会让本体和技能源已明显分离
	TouchInput.queue_dash()
	await _step()
	var cast_body := player.global_position
	var mp_before := player.current_mp
	TouchInput.queue_attack()
	TouchInput.queue_bolt()
	TouchInput.queue_heavy()
	await _step()
	var bolts := get_tree().get_nodes_in_group("player_bolts")
	_check(bolts.size() == 1 and player.current_mp < mp_before and player._heavy_cd > 0.0,
		"冲刺过程中真实消费法弹/重击输入与资源")
	if bolts.size() == 1:
		var bolt: PlayerBolt = bolts[0]
		# 从真实弹体已走寿命倒推发射点，避免依赖本帧新节点是否已经物理更新。
		var origin := bolt.global_position - bolt.direction * PlayerBolt.SPEED * (PlayerBolt.LIFE_TIME - bolt._life)
		_check(origin.distance_to(cast_body + Vector2.RIGHT * 22.0) < 0.1,
			"法弹实际发射点与冲刺当帧本体 +22px 一致")
	var ring_ok := false
	for child in get_children():
		if child is Line2D and child.visible:
			ring_ok = ring_ok or child.global_position.distance_to(cast_body) < 0.1
	_check(ring_ok, "重击真实冲击环以冲刺当帧本体为圆心")
	var attack_seen := false
	var attack_origin_ok := true
	for frame in 20:
		await _step()
		if player._attack_timer > 0.0:
			attack_seen = true
			attack_origin_ok = attack_origin_ok and player.attack_hitbox.global_position.distance_to(
				player.global_position + player.facing * Player.ATTACK_REACH) < 0.1
	_check(attack_seen and attack_origin_ok, "冲刺缓冲攻击真实兑现，命中框始终与本体 +26px 一致")
	TouchInput.move_vector = Vector2.ZERO
	await _step(75)
	# 真正 StaticBody2D 墙挡住冲刺；不是人工截断位置。
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	var collider := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(12.0, 180.0)
	collider.shape = rect
	wall.add_child(collider)
	add_child(wall)
	wall.global_position = player.global_position + Vector2(60.0, 0.0)
	await _step(2)
	var before_wall := player.global_position
	TouchInput.move_vector = Vector2.RIGHT
	TouchInput.queue_dash()
	await _step(16)
	_check(player.get_slide_collision_count() > 0 and player.global_position.x < wall.global_position.x - 15.0
		and player.global_position.x > before_wall.x + 20.0, "真实冲刺撞墙保持身体/碰撞一致")
	TouchInput.move_vector = Vector2.ZERO
	await _step(3)
	var before_hurt := player.global_position
	player.take_damage(1.0, player.global_position + Vector2(30.0, 0.0), "alignment test")
	await _step(18)
	_check(player.global_position.x < before_hurt.x - 8.0, "真实受击击退移动而精灵不留在旧位置")
	wall.queue_free()
	await get_tree().process_frame
	# SceneTree 暂停和恢复：自身不需要改 process_mode；process_always 定时器唤醒测试。
	var pause_body := player.global_position
	var pause_visual := player.visual.global_position
	get_tree().paused = true
	await get_tree().create_timer(0.08, true).timeout
	_check(player.global_position == pause_body and player.visual.global_position == pause_visual,
		"暂停期间本体和精灵同时静止")
	get_tree().paused = false
	TouchInput.move_vector = Vector2(-0.271, 0.413)
	await _step(24)
	TouchInput.reset()
	await _step(4)
	player._hurt_iframes = 0.0
	player.take_damage(player.stats.max_hp() + 1.0, player.global_position + Vector2.RIGHT, "alignment test")
	_check(player._is_dead, "真实致死伤害进入死亡态")
	await _step(140)
	_check(not player._is_dead and player.visible and player.current_hp > 0.0,
		"自然死亡计时完成并真实重生")
	_finish(entry)
	# 正常快照保存/旧节点释放/重新实例化，不能把渲染修正写入存档。
	TouchInput.joystick_active = true
	TouchInput.move_vector = Vector2(0.413, 0.271)
	await _step(35)
	TouchInput.reset()
	await _step(4)
	var saved := player.save_snapshot()
	var saved_pos := player.global_position
	GameState.player_snapshot = saved
	player.queue_free()
	await get_tree().process_frame
	player = PLAYER.instantiate()
	add_child(player)
	player.get_node("Camera2D").enabled = false
	entry = _watch(player, Vector2.ZERO, "存档快照重载")
	await _step(3)
	_check(player.global_position.distance_to(saved_pos) < 0.1, "场景重载恢复小数本体位置，不保存精灵补偿")
	_finish(entry)
	player.queue_free()
	GameState.player_snapshot = null
	await get_tree().process_frame

func _authored_anchor() -> void:
	var base := Vector2(3.25, -2.5)
	var player := _player(Vector2(774085.375, 696114.25), base)
	var entry := _watch(player, base, "非零美术局部锚点")
	TouchInput.joystick_active = true
	TouchInput.move_vector = Vector2(-0.413, 0.271)
	await _step(80)
	TouchInput.queue_dash()
	await _step(16)
	TouchInput.reset()
	await _step(5)
	_finish(entry)
	player.queue_free()
	await get_tree().process_frame

func _monster(species: String, scene: PackedScene, pos: Vector2, base := Vector2.ZERO) -> MonsterBase:
	var monster: MonsterBase = scene.instantiate()
	monster.get_node("Visual").position = base
	add_child(monster)
	var inst := MonsterInstance.new()
	_next_id += 1
	inst.id = _next_id
	inst.species = load("res://data/species/%s.tres" % species).duplicate()
	inst.age = 200
	inst.spawn_pos = pos
	monster.setup(inst)
	return monster

func _monster_paths() -> void:
	var player := _player(Vector2(753707.25, 738957.375))
	player.set_physics_process(false)
	var specs := [
		{"name": "近圈直接移动", "offset": Vector2(170.25, 0.375), "rvo": false, "species": "goblin"},
		{"name": "近圈真实 RVO 回调", "offset": Vector2(-190.25, 30.375), "rvo": true, "species": "goblin"},
		{"name": "远圈 LOD/恢复近圈", "offset": Vector2(1500.25, 40.375), "rvo": true, "species": "goblin"},
		{"name": "Boss 原生死亡", "offset": Vector2(100.25, 250.375), "rvo": false, "species": "treant"},
	]
	var cases: Array[Dictionary] = []
	for spec in specs:
		var base := Vector2(2.25, -1.5) if spec.rvo else Vector2.ZERO
		var monster := _monster(spec.species, BOAR if spec.species == "treant" else GOBLIN,
			player.global_position + spec.offset, base)
		monster._player_ref = player
		monster._nav.avoidance_enabled = spec.rvo
		# 通过真正的迁徙状态机持续行走，不调用 _update_anim/_post_move/移动辅助函数。
		monster.on_migrate("", monster.global_position + Vector2(3000.0, 900.0))
		var c := {"monster": monster, "entry": _watch(monster, base, spec.name),
			"start": monster.global_position, "rvo_calls": 0, "lod_seen": false}
		if spec.rvo:
			monster._nav.velocity_computed.connect(func(_v: Vector2) -> void: c.rvo_calls += 1)
		cases.append(c)
	for frame in 90:
		await _step()
		for c in cases:
			c.lod_seen = c.lod_seen or c.monster._lod_skip != 0
	for index in cases.size():
		var c := cases[index]
		_check(c.monster.global_position.distance_to(c.start) > 30.0, "%s 真实 AI 位移" % specs[index].name)
	_check(cases[1].rvo_calls > 20, "真实 NavigationServer 避让回调至少 20 帧")
	_check(cases[2].lod_seen, "远圈真实进入 LOD 节流分支")
	var far: MonsterBase = cases[2].monster
	far.global_position = player.global_position + Vector2(100.25, -180.375)
	far.on_migrate("", far.global_position + Vector2(3000.0, 900.0))
	await _step(24)
	_check(far._lod_skip == 0 and cases[2].rvo_calls > 5, "远圈回到近圈后恢复真实 RVO")
	# 真实受击入口推动击退，随后自然死亡通知；普通怪侧倒和 Boss 原生 die 都覆盖。
	for c in cases:
		c.monster.take_damage(1.0, c.monster.global_position + Vector2(30, 0))
	await _step(24)
	for c in cases:
		c.monster.on_sim_death()
	await _step(85)
	for c in cases:
		_check(c.monster.state == MonsterBase.S_CORPSE, "%s 保持尸体态" % c.entry.label)
		_finish(c.entry)
		c.monster.queue_free()
	player.queue_free()
	await get_tree().process_frame

func _frame_anchors() -> void:
	# 真正读取已交付像素，仅在测试做 CPU 检查，生产代码不能 GPU 读回。
	# meta 必须吻合 idle 首帧实际脚底；每动作共享裁切画布，不能动作切换时再居中。
	var frames_to_check: Dictionary = Player.HERO_SKINS.duplicate()
	for path in ["oni", "treant"]:
		frames_to_check[path] = load("res://assets/creatures/frames/%s/%s_frames.res" % [path, path])
	for key: String in frames_to_check:
		var frames: SpriteFrames = frames_to_check[key]
		var image := frames.get_frame_texture("idle", 0).get_image()
		var feet := -1
		for y in image.get_height():
			for x in image.get_width():
				if image.get_pixel(x, y).a > 0.5:
					feet = maxi(feet, y)
		_check(feet >= 0 and feet == int(frames.get_meta("feet", -2)), "%s 帧 meta 脚点等于真实不透明像素" % key)
		var stable := true
		var count := 0
		for anim in frames.get_animation_names():
			for frame in frames.get_frame_count(anim):
				var texture := frames.get_frame_texture(anim, frame)
				stable = stable and texture.get_size() == Vector2(image.get_size())
				count += 1
		_check(stable and count > 10, "%s %d 帧保持共同画布原点（动作不重新居中）" % [key, count])
		var layout := MonsterBase.shadow_layout(frames, Vector2(2.0, 2.0))
		_check(absf(layout.y - (feet + 1.0 - image.get_height() * 0.5) * 2.0) < 0.01,
			"%s 阴影脚点与实际像素独立计算一致" % key)
