## 真实刚体/AI击退：追击不能吃掉外力，墙体和Boss稳定性不依赖截图判读。
extends Node2D
const PLAYER := preload("res://scenes/player/player.tscn")
const GOBLIN := preload("res://scenes/monsters/goblin.tscn")
var _checks := 0
var _fails := 0
var _player: Player
var _bodies: Array[MonsterBase] = []

func _ready() -> void:
	GameState.save_enabled = false
	GameState.reset_all()
	WorldSim.stop()
	WorldSim.sim = EcologySim.new()
	BiomeMap.configure(BiomeMap.DEFAULT_SEED)
	TouchInput.reset()
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok: _fails += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])

func _step(n := 1) -> void:
	for i in n:
		await get_tree().physics_frame
		await get_tree().process_frame

func _monster(pos: Vector2, boss := false) -> MonsterBase:
	var body: MonsterBase = GOBLIN.instantiate()
	add_child(body)
	var species: SpeciesData = preload("res://data/species/goblin.tres").duplicate()
	species.is_boss = boss
	body.setup(WorldSim.sim.spawn_instance(species, "impact", 200, 0, 1.0, false, pos))
	body.global_position = pos
	body.current_hp = 10000.0
	body._nav.avoidance_enabled = false
	body.collision_mask = 1
	body.set_physics_process(false)
	_bodies.append(body)
	return body

func _run() -> void:
	_player = PLAYER.instantiate()
	add_child(_player)
	_player.teleport_to(Vector2(3000,3000))
	_player.set_process(false)
	_player._protect_timer = 999.0
	_player.current_mp = 10000.0
	_player.facing = Vector2.RIGHT
	# 实际攻击输入和碰撞先触发外力，再交给正常追击状态推进。
	var body := _monster(_player.position + Vector2(40,0))
	await _step(4)
	TouchInput.queue_attack()
	var before_hp := body.current_hp
	for i in 80:
		await _step()
		if body.current_hp < before_hp: break
	_check(body.current_hp < before_hp, "普攻真实输入与碰撞触发受击")
	body.state = MonsterBase.S_CHASE
	body.set_physics_process(true)
	var start := body.global_position
	await _step(7)
	var normal_move := body.global_position.x - start.x
	_check(normal_move > 4.0 and normal_move < 24.0,
		"追击中的普通命中确实短距离向后退而非被追击速度抵消")
	_check(body.visual.global_position.distance_to(body.to_global(body._visual_anchor)) <= 0.71,
		"真实击退保持身体和美术锚点对齐")
	body.set_physics_process(false)
	# 单个伤害入口保留种族抗性，并为近战/重击/法弹提供可读的分级。
	var speeds: Array[float] = []
	for profile in [1.0, 1.5, 0.6]:
		body._knockback = Vector2.ZERO
		body._knockback_rearm = 0.0
		body.take_damage(1.0, body.global_position - Vector2(20,0), false, profile)
		speeds.append(body._knockback.length())
	_check(speeds[1] > speeds[0] and speeds[0] > speeds[2] and speeds[2] > 0.0,
		"重击、普攻、魔弹外力有清楚强弱顺序")
	body._knockback_rearm = 0.0
	body.take_damage(1.0, body.global_position - Vector2(20,0), true, 1000000.0)
	_check(body._knockback.length() <= CombatMath.KNOCKBACK_MAX_SPEED,
		"极高击退赐福也受位移包络限制")
	var impulse := body._knockback
	var rearm := body._knockback_rearm
	for i in 30:
		body.take_damage(1.0, body.global_position + Vector2(20,0), true, 100.0)
	_check(body._knockback == impulse and body._knockback_rearm == rearm,
		"同窗多弹不会反复改向/叠力/延期")
	# 真实墙体阻挡最高外力。
	var wall := StaticBody2D.new()
	wall.position = body.position + Vector2(25,0)
	wall.collision_layer = 1
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(12,160)
	shape.shape = rect
	wall.add_child(shape)
	add_child(wall)
	body.state = MonsterBase.S_PATROL
	body._patrol_wait = 10.0
	await _step(2)
	body.set_physics_process(true)
	await _step(20)
	_check(body.position.x < wall.position.x - 6.0 and body._knockback.length() < 0.1,
		"最高击退经真实身体碰撞抵墙并自然收回")
	body.set_physics_process(false)
	var boss := _monster(_player.position + Vector2(0,150), true)
	for i in 20:
		boss.take_damage(1.0, boss.position - Vector2(20,0), true, 1000000.0)
	_check(boss._knockback == Vector2.ZERO and boss._impact_feedback.active,
		"Boss保留命中反馈而不发生亚像素抖动")
	TouchInput.reset()
	WorldSim.stop()
	print("=== KNOCKBACK RESPONSE %s (%d checks) ===" % ["PASS" if _fails == 0 else "FAIL",_checks])
	get_tree().quit(0 if _fails == 0 else 1)
