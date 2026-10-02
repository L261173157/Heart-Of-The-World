## 真实双通道输入→物理扫掠→MonsterBase 伤害；覆盖原画尺度、八向、时相、墙与生命周期。
extends Node2D

const PLAYER := preload("res://scenes/player/player.tscn")
const GOBLIN := preload("res://scenes/monsters/goblin.tscn")
var _checks := 0
var _fails := 0
var _player: Player
var _targets: Array[MonsterBase] = []
var _origin := Vector2.ZERO
var _capture_dir := ""


func _ready() -> void:
	GameState.save_enabled = false
	GameState.ecology_snapshot = null
	GameState.reset_all()
	GameState.settings.auto_aim = false
	GameState.settings.screen_shake = false
	WorldSim.stop()
	WorldSim.sim = EcologySim.new()
	TouchInput.reset()
	_origin = WorldConfig.spawn_pos()
	_capture_dir = OS.get_environment("HOTW_DIRECTIONAL_CAPTURE_DIR")
	_run.call_deferred()


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])


func _frames(count := 1) -> void:
	for i in count:
		await get_tree().physics_frame
		await get_tree().process_frame


func _monster(offset: Vector2) -> MonsterBase:
	var monster: MonsterBase = GOBLIN.instantiate()
	add_child(monster)
	monster.set_physics_process(false)
	var species: SpeciesData = preload("res://data/species/goblin.tres").duplicate()
	var pos := _player.global_position + offset
	var inst := WorldSim.sim.spawn_instance(species, "sword", 200, 0, 1.0, false, pos)
	monster.setup(inst)
	monster.global_position = pos
	monster.current_hp = 10000.0
	monster.collision_mask = 0
	_targets.append(monster)
	return monster


func _clear_targets() -> void:
	for target in _targets:
		if is_instance_valid(target):
			target.queue_free()
	_targets.clear()
	await _frames(2)


func _face(direction: Vector2) -> void:
	_player.teleport_to(_origin)
	_player._attack_cooldown = 0.0
	TouchInput.joystick_active = true
	TouchInput.move_vector = direction
	await _frames(3)
	TouchInput.move_vector = Vector2.ZERO
	await _frames(5)


func _capture(label: String) -> void:
	if _capture_dir == "" or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(_capture_dir)
	get_viewport().get_texture().get_image().save_png(_capture_dir.path_join(label + ".png"))


func _run() -> void:
	_player = PLAYER.instantiate()
	add_child(_player)
	_player.set_process(false)
	_player.current_mp = 10000.0
	var camera: Camera2D = _player.get_node("Camera2D")
	camera.zoom = Vector2(3.0, 3.0) if _capture_dir != "" else Vector2.ONE
	var directions := [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN,
		Vector2(1, 1).normalized(), Vector2(-1, 1).normalized(),
		Vector2(-1, -1).normalized(), Vector2(1, -1).normalized()]
	for index in directions.size():
		var direction: Vector2 = directions[index]
		await _face(direction)
		camera.snap_to_player()
		var near := _monster(direction * 62.0)
		var far := _monster(direction * 88.0)
		var back := _monster(-direction * 62.0)
		await _frames(2)
		if index % 2 == 0:
			TouchInput.queue_attack()
		else:
			Input.action_press("attack")
		await _frames(2)
		Input.action_release("attack")
		_check(_player._weapon_visual.active and _player._weapon_visual.aim.dot(direction) > 0.999,
			"方向%d 真输入锁定可见武器与判定同向" % index)
		_check(_player.visual.animation == &"hurt" and _player.visual.material == _player._weapon_body_material,
			"方向%d 去掉烘焙剑的Guard身体配单把独立方向剑" % index)
		_check(near.current_hp == 10000.0 and _player.attack_shape.disabled,
			"方向%d 蓄势时没有提前伤害" % index)
		var first_hit := -1.0
		var captured := false
		for frame in 23:
			await _frames()
			if near.current_hp < 10000.0 and first_hit < 0.0:
				first_hit = _player._attack_elapsed
			if _player._weapon_visual.striking and not captured:
				captured = true
				await _capture("sword-direction-%d" % index)
		_check(first_hit >= Player.ATTACK_WINDUP and first_hit <= Player.ATTACK_WINDOW + 0.001,
			"方向%d 原画66px内的远端怪仅在挥刃时受伤" % index)
		_check(far.current_hp == 10000.0 and back.current_hp == 10000.0,
			"方向%d 刀尖外和身后均不受伤" % index)
		_check(_player._hit_this_swing.size() == 1, "方向%d 每刀每目标只结算一次" % index)
		_check(not _player._weapon_visual.active and _player.attack_shape.disabled and _player.visual.material == null,
			"方向%d 收招清理武器和判定" % index)
		_check(_player.visual.global_position.distance_to(_player.to_global(_player._visual_anchor)) <= 0.71 \
			and is_equal_approx(_player._shadow.position.y, _player._feet_y),
			"方向%d 身体/阴影固定锚点不漂移" % index)
		await _clear_targets()
	await _wall_contract()
	await _sweep_upgrade_contract()
	await _maximum_speed_contract()
	await _cancel_contract()
	TouchInput.reset()
	_player.queue_free()
	await _frames(2)
	print("=== DIRECTIONAL ATTACK %s (%d checks) ===" % ["PASS" if _fails == 0 else "FAIL", _checks])
	get_tree().quit(0 if _fails == 0 else 1)


func _wall_contract() -> void:
	await _face(Vector2.RIGHT)
	var monster := _monster(Vector2(62, 0))
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(10, 180)
	shape.shape = rect
	wall.add_child(shape)
	add_child(wall)
	wall.global_position = _player.global_position + Vector2(32, 0)
	await _frames(2)
	TouchInput.queue_attack()
	await _frames(2)
	_check(_player._weapon_visible_reach(Vector2.RIGHT) < 28.0, "真实墙同时裁短可见刀锋")
	await _frames(23)
	_check(monster.current_hp == 10000.0, "命中扇形内的怪也不能隔墙受伤")
	wall.queue_free()
	await _frames(2)
	_player._attack_cooldown = 0.0
	TouchInput.queue_attack()
	await _frames(23)
	_check(monster.current_hp < 10000.0, "去掉真实墙后同一输入/目标能命中")
	await _clear_targets()


func _sweep_upgrade_contract() -> void:
	for upgraded in [false, true]:
		await _face(Vector2.RIGHT)
		_player.stats.passives = {"sword_sweep": 1} if upgraded else {}
		var center := _monster(Vector2(42, 0)) # 最近目标让自动辅助保持正前方。
		var flank := _monster(Vector2.RIGHT.rotated(deg_to_rad(78.0)) * 65.0)
		await _frames(2)
		TouchInput.queue_attack()
		await _frames(23)
		_check(center.current_hp < 10000.0, "宽弧%s 正面真实目标保持可击中" % upgraded)
		_check((flank.current_hp < 10000.0) == upgraded, "宽弧%s 真实碰撞覆盖侧翼增量" % upgraded)
		_check(is_equal_approx(_player._attack_half_arc, deg_to_rad(78.0 if upgraded else 58.0)),
			"宽弧%s 表现和判定共用有界角度" % upgraded)
		await _clear_targets()
	_player.stats.passives = {}


func _maximum_speed_contract() -> void:
	await _face(Vector2.RIGHT)
	var center := _monster(Vector2(40, 0))
	var edge := _monster(Vector2.RIGHT.rotated(deg_to_rad(62.0)) * 62.0)
	await _frames(2)
	_player.stats.agility = 100
	var edge_hits := 0
	var last_hp := edge.current_hp
	var swing_count := 0
	var last_elapsed := 1.0
	for frame in 105:
		# 模拟持续真实预输入；不直接重启攻击、不手动推进判定辅助函数。
		if frame % 3 == 0:
			TouchInput.queue_attack()
		await _frames()
		if _player._attack_elapsed < last_elapsed:
			swing_count += 1
		if edge.current_hp < last_hp:
			edge_hits += 1
		last_hp = edge.current_hp
		last_elapsed = _player._attack_elapsed
	TouchInput.clear_queues()
	await _frames(25)
	_check(center.current_hp < 10000.0 and swing_count >= 5, "最高攻速连续真输入产生至少五刀")
	_check(edge_hits >= swing_count - 1, "最高攻速预输入不会截断每刀末端侧翼")
	_check(_player._attack_cooldown <= Player.ATTACK_WINDOW, "最高攻速只补足末端时相，不额外强加长冷却")
	_player.stats.agility = 5
	await _clear_targets()


func _cancel_contract() -> void:
	await _face(Vector2.UP)
	var target := _monster(Vector2(0, -62))
	await _frames(2)
	TouchInput.queue_attack()
	await _frames(3)
	_player.teleport_to(_origin + Vector2(160, 0))
	await _frames(22)
	_check(target.current_hp == 10000.0 and not _player._weapon_visual.active and _player.visual.material == null,
		"传送取消蓄势，不在旧地或落点补刀")
	await _clear_targets()
	await _face(Vector2.DOWN)
	TouchInput.queue_attack()
	await _frames(3)
	TouchInput.queue_dash()
	await _frames(2)
	_check(_player._dash_timer > 0.0 and _player._attack_anim_linger > 0.0 \
		and _player.visual.material == _player._weapon_body_material,
		"冲刺取消冷却仍保留既有短窗 dash-strike")
	await _frames(25)
	_check(not _player._weapon_visual.active and _player.attack_shape.disabled and _player.visual.material == null,
		"冲刺挥砍不会留下武器或伤害形状")
	await _face(Vector2.RIGHT)
	TouchInput.queue_attack()
	await _frames(3)
	_player._die()
	_check(not _player._weapon_visual.active and _player.visual.material == null,
		"死亡立即收起方向武器和身体去剑材质")
	_player._respawn()
	await _frames(2)
	_check(_player.visual.material == null and _player.visual.animation == &"idle",
		"复活恢复未遮罩完整站姿")
	await _frames(35) # 让真实死亡/复活音效与短暂特效完成后再释放测试世界。
