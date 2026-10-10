## 熔岩龟王真实物理状态机回归：招式循环、固定几何、半血中断、收招和架盾语义。
## 目标站位可控但不直接调用出招/结算辅助函数；全部伤害由正常 _physics_process 派发。
extends Node2D

const BOSS := preload("res://scenes/monsters/guardian.tscn")
const PLAYER := preload("res://scenes/player/player.tscn")
var _checks := 0
var _fails := 0
var _next_id := 70000
var _boss: Guardian
var _target: Node2D
var _hint_count := 0
var _fx_count := 0
var _origin := Vector2.ZERO

class Target extends CharacterBody2D:
	var hits := 0
	var contexts: Array[Dictionary] = []
	func take_damage(_amount: float, _from := Vector2.INF, _source := "", context: Dictionary = {}) -> void:
		hits += 1
		contexts.append(context.duplicate())

func _ready() -> void:
	GameState.save_enabled = false
	WorldSim.stop()
	BiomeMap.configure(BiomeMap.DEFAULT_SEED)
	ObstacleField.restore_destroyed([])
	_origin = WorldConfig.spawn_pos()
	Engine.time_scale = 8.0
	Engine.physics_ticks_per_second = 480
	EventBus.hint_requested.connect(func(text: String) -> void:
		if text.contains("第二阶段"):
			_hint_count += 1)
	EventBus.fx_requested.connect(func(_kind: String, _pos: Vector2, _scale: float) -> void: _fx_count += 1)
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])

func _frames(count: int) -> void:
	for _frame in count:
		await get_tree().physics_frame

func _setup(id := "turtle_king", low_hp := false, real_player := false) -> void:
	WorldSim.sim = EcologySim.new()
	GameState.stats = CharacterStats.new()
	GameState.stats.strength = 60
	GameState.stats.intellect = 60
	GameState.player_snapshot = {}
	GameState.settings["auto_aim"] = false
	TouchInput.reset()
	if real_player:
		_target = PLAYER.instantiate()
		add_child(_target)
		_target.set_process(false)
		_target.get_node("Camera2D").enabled = false
		(_target as Player)._protect_timer = 0.0
		(_target as Player)._hurt_iframes = 0.0
		(_target as Player).facing = Vector2.LEFT
	else:
		var target := Target.new()
		target.collision_layer = 1
		target.collision_mask = 3
		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = 10.0
		shape.shape = circle
		target.add_child(shape)
		add_child(target)
		target.add_to_group("player")
		_target = target
	_target.global_position = _origin + Vector2(80, 0)
	_boss = BOSS.instantiate()
	add_child(_boss)
	_boss.set_physics_process(false)
	var inst := MonsterInstance.new()
	_next_id += 1
	inst.id = _next_id
	inst.species = load("res://data/species/%s.tres" % id)
	inst.age = 200
	inst.lifespan = inst.species.lifespan_max
	inst.size_scale = inst.species.boss_size_scale if inst.species.is_boss else 1.0
	inst.spawn_pos = _origin
	if low_hp:
		inst.hp_mirror = inst.max_hp() * 0.4
	WorldSim.sim.instances[inst.id] = inst
	_boss.setup(inst)
	_boss._player_ref = _target
	_boss.state = MonsterBase.S_CHASE
	await _frames(2)
	_boss.set_physics_process(true)

func _cleanup() -> void:
	TouchInput.reset()
	if is_instance_valid(_boss):
		_boss.queue_free()
	if is_instance_valid(_target):
		_target.queue_free()
	await _frames(2)

func _wait_state(wanted: int, budget := 500) -> bool:
	for _frame in budget:
		if _boss.state == wanted:
			return true
		await get_tree().physics_frame
	_check(false, "状态机未超时等待 state=%d (actual=%d)" % [wanted, _boss.state])
	return false

func _run() -> void:
	await _ordinary_guardian()
	await _ordinary_target_loss()
	await _migration_cleanup()
	await _phase_one_loop()
	await _stomp_escape()
	await _stomp_cover()
	await _real_dash()
	await _sweep_flank()
	await _phase_change_cancels()
	await _eruption_escape()
	await _eruption_hit_and_lifecycle()
	await _real_guard()
	await _cleanup()
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	print("=== BOSS MOVES %s (%d checks) ===" % ["PASS" if _fails == 0 else "FAIL", _checks])
	get_tree().quit(0 if _fails == 0 else 1)

func _ordinary_guardian() -> void:
	for sp: SpeciesData in SpeciesCatalog.build_all():
		_check(sp.guardian_boss_moves == (sp.species_name == "熔岩龟王"), "三招只启用目标物种 " + sp.species_name)
	await _setup("guardian")
	await _wait_state(Guardian.S_WINDUP)
	_check(not _boss._boss_loop and _boss._ring.shape == 0
		and is_equal_approx(_boss._ring.radius, _boss.inst.species.attack_range * _boss.inst.species.guard_smash_range_mult),
		"普通守卫仍为原半径、原前摇圆形砸击")
	for _frame in 120:
		if (_target as Target).hits > 0:
			break
		await get_tree().physics_frame
	_check((_target as Target).hits == 1 and _boss.state == MonsterBase.S_CHASE, "普通守卫原重击落地后回追击")
	_boss.take_damage(_boss.current_hp * 0.6 / (1.0 - _boss.inst.species.defense_reduction))
	_check(_boss._boss_phase == 1 and _boss.state != Guardian.S_PHASE_CHANGE, "普通守卫残血不新增阶段")
	await _cleanup()

func _phase_one_loop() -> void:
	await _setup()
	var seen: Array[int] = []
	var target := _target as Target
	var children := _boss.get_child_count()
	for expected in [Guardian.MOVE_STOMP, Guardian.MOVE_SWEEP, Guardian.MOVE_STOMP]:
		_target.global_position = _boss.global_position + Vector2(80, 0)
		await _wait_state(Guardian.S_WINDUP)
		seen.append(_boss._current_move)
		var initial_hits := target.hits
		var fixed_origin := _boss._ring.global_position
		var fixed_boss := _boss.global_position
		_check(_boss._ring.visible and _boss._ring.shape == expected and _boss._guard_hint.visible,
			"真实循环出现对应地面几何和盾提示 move%d" % expected)
		_check(_boss._guard_hint.blockable == (expected == Guardian.MOVE_SWEEP), "扇扫可挡、震地不可挡提示一致")
		await _frames(20)
		_check(target.hits == initial_hits and _boss._ring.global_position.is_equal_approx(fixed_origin), "前摇无早伤害且范围不追人")
		await _wait_state(Guardian.S_RECOVER)
		_check(target.hits == initial_hits + 1, "圈内真实落地仅命中一次")
		_check(_boss._attack_context.is_empty() and not _boss._guard_hint.visible, "落地后清盾提示与伤害凭证")
		_check(_boss.global_position.distance_to(fixed_boss) < 0.1, "真实 RVO 回调不拖走蓄力 Boss")
		var hp := _boss.current_hp
		_boss.take_damage(2.0, _target.global_position)
		await _frames(24)
		_check(_boss.state == Guardian.S_RECOVER and _boss.current_hp < hp
			and _boss.global_position.distance_to(fixed_boss) < 0.1 and target.hits == initial_hits + 1,
			"收招至少0.4秒停步可反击且不重复命中")
		_check(not _boss._ring.visible, "命中短闪结束后隐藏地面范围")
		await _wait_state(MonsterBase.S_CHASE)
	_check(seen == [Guardian.MOVE_STOMP, Guardian.MOVE_SWEEP, Guardian.MOVE_STOMP], "第一阶段真实循环交替震地/扇扫")
	_check(_boss.get_child_count() <= children + 2, "重复招式仅复用一个范围节点和一个盾提示")
	await _cleanup()

func _stomp_escape() -> void:
	await _setup()
	await _wait_state(Guardian.S_WINDUP)
	_target.global_position = _boss._move_origin + Vector2(_boss._move_radius + 2.0, 0)
	await _wait_state(Guardian.S_RECOVER)
	_check((_target as Target).hits == 0, "圆圈边界外2px无隐藏扩张命中")
	await _cleanup()

func _sweep_flank() -> void:
	await _setup()
	await _wait_state(Guardian.S_WINDUP)
	await _wait_state(Guardian.S_RECOVER)
	_target.global_position = _boss.global_position + Vector2(80, 0)
	await _wait_state(Guardian.S_WINDUP)
	var target := _target as Target
	var initial_hits := target.hits
	var direction := _boss._move_direction
	var center := _boss._move_origin
	var flip := _boss.visual.flip_h
	_target.global_position = center - direction * 90.0
	await _frames(20)
	_check(_boss._current_move == Guardian.MOVE_SWEEP and _boss._move_direction == direction
		and _boss._ring.direction == direction and _boss.visual.flip_h == flip,
		"绕到背后时扇形与现有身体动作都保持出手方向")
	await _wait_state(Guardian.S_RECOVER)
	_check(target.hits == initial_hits, "扇形背面近距离不受伤，侧绕有真实收益")
	await _cleanup()

func _phase_change_cancels() -> void:
	await _setup()
	await _wait_state(Guardian.S_WINDUP)
	var initial_hints := _hint_count
	var initial_fx := _fx_count
	var age := _boss.inst.age
	_boss.take_damage(_boss.inst.max_hp() * 0.6 / (1.0 - _boss.inst.species.defense_reduction), _target.global_position)
	_check(_boss._boss_phase == 2 and _boss.state == Guardian.S_PHASE_CHANGE,
		"真实受伤跨半血触发唯一第二阶段")
	_check(_boss._attack_context.is_empty() and not _boss._guard_hint.visible and _boss._ring.shape == 3,
		"转阶段立即取消待落地攻击和盾警告，换无伤金环")
	var remaining_hp := _boss.current_hp
	await _frames(55)
	_check(_boss.state == Guardian.S_PHASE_CHANGE and (_target as Target).hits == 0
		and _fx_count == initial_fx, "阶段提示至少0.9秒不伤人、不暗中落下旧攻击")
	await _wait_state(MonsterBase.S_CHASE)
	_check(_hint_count == initial_hints + 1 and is_equal_approx(_boss.current_hp, remaining_hp)
		and _boss.inst.age == age and is_equal_approx(_boss.inst.hp_mirror, remaining_hp),
		"转阶段只提示一次，不改生命镜像、生态年龄或回复血量")
	await _wait_state(Guardian.S_WINDUP)
	_check(_boss._current_move == Guardian.MOVE_ERUPTION, "第二阶段真实循环首先启用脚下喷发")
	_boss.take_damage(2.0, _target.global_position)
	_check(_boss.state == Guardian.S_WINDUP and _hint_count == initial_hints + 1, "后续受击不重复变身或吞掉新前摇")
	await _cleanup()

func _eruption_escape() -> void:
	var initial_hints := _hint_count
	await _setup("turtle_king", true)
	_check(_boss._boss_phase == 2 and _hint_count == initial_hints, "低血存档/流式恢复直接延续阶段，无重复变身")
	await _wait_state(Guardian.S_WINDUP)
	var point := _target.global_position
	_check(_boss._current_move == Guardian.MOVE_ERUPTION and _boss._ring.global_position == point
		and _boss._ring.radius < 70.0 and _boss._guard_hint.warning == "unblockable", "喷发是有限半径的固定十字落点、不可格挡")
	_target.global_position = point + Vector2(0, _boss._move_radius + 3.0)
	await _frames(40)
	_check(_boss._move_origin == point and _boss._ring.global_position == point
		and (_target as Target).hits == 0, "移动后喷发标记不追随、不提前结算")
	await _wait_state(Guardian.S_RECOVER)
	_check((_target as Target).hits == 0, "离开固定喷发落点即可完整规避")
	await _cleanup()

func _eruption_hit_and_lifecycle() -> void:
	await _setup("turtle_king", true)
	await _wait_state(Guardian.S_WINDUP)
	var strength := float(_boss._attack_context["strength"])
	await _wait_state(Guardian.S_RECOVER)
	var target := _target as Target
	_check(target.hits == 1 and not bool(target.contexts[0]["blockable"])
		and is_equal_approx(float(target.contexts[0]["strength"]), strength),
		"留在喷发落点真实命中，伤害强度和不可挡提示同源")
	_target.global_position = _boss.global_position + Vector2(80, 0)
	await _wait_state(Guardian.S_WINDUP)
	_check(_boss._current_move == Guardian.MOVE_SWEEP, "第二阶段喷发后恢复可绕背扇扫")
	_target.visible = false
	await _frames(2)
	_check(_boss.state == MonsterBase.S_PATROL and not _boss._ring.visible
		and _boss._attack_context.is_empty(), "目标消失中断招式并清理全部伤害/范围")
	_target.visible = true
	_boss.state = MonsterBase.S_CHASE
	_boss._attack_cd = 0.0
	await _wait_state(Guardian.S_WINDUP)
	_check(_boss._current_move == Guardian.MOVE_STOMP, "第二阶段完整循环回到近身震地")
	_boss.on_sim_death()
	await _frames(90)
	_check(_boss.state == MonsterBase.S_CORPSE and not _boss._ring.visible
		and not _boss._guard_hint.visible and target.hits == 1,
		"前摇中死亡无延迟伤害、无遗留圈或盾提示")
	await _cleanup()

func _real_guard() -> void:
	await _setup("turtle_king", false, true)
	var player := _target as Player
	await _wait_state(Guardian.S_WINDUP)
	player.facing = Vector2.LEFT
	TouchInput.begin_guard()
	await _frames(12)
	var hp := player.current_hp
	_check(player.guard_state == "guarding" and _boss._guard_hint.warning == "unblockable", "真实触屏架盾已生效但震地明确不可挡")
	await _wait_state(Guardian.S_RECOVER)
	_check(player.current_hp < hp and player.guard_charge == 0, "圆形震地实际穿盾但不增加反击层")
	player.teleport_to(_boss.global_position + Vector2(90, 0))
	player.facing = Vector2.LEFT
	player._hurt_iframes = 0.0
	await _frames(2)  # 传送取消后先有真实松手帧，再接受新的按住。
	TouchInput.begin_guard()
	await _wait_state(Guardian.S_WINDUP)
	_check(_boss._current_move == Guardian.MOVE_SWEEP and _boss._guard_hint.blockable
		and _boss._guard_hint.warning == "normal", "扇扫按当前玩家盾强显示可挡")
	hp = player.current_hp
	var mp := player.current_mp
	await _wait_state(Guardian.S_RECOVER)
	_check(is_equal_approx(player.current_hp, hp) and player.guard_charge == 1 and player.current_mp < mp,
		"真实扇扫正面架盾抵伤/扣蓝/蓄一层反击闭环")
	await _cleanup()

func _stomp_cover() -> void:
	await _setup()
	await _wait_state(Guardian.S_WINDUP)
	# 前摇后才放入真实 StaticBody2D，验证落地射线不沿用陈旧的视线缓存。
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	var collider := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(8, 100)
	collider.shape = rect
	wall.add_child(collider)
	add_child(wall)
	wall.global_position = _boss.global_position + Vector2(65, 0)
	await _wait_state(Guardian.S_RECOVER)
	_check((_target as Target).hits == 0, "实际实体掩体挡住近身砸击，不穿墙结算")
	wall.queue_free()
	await _cleanup()

func _real_dash() -> void:
	await _setup("turtle_king", false, true)
	var player := _target as Player
	await _wait_state(Guardian.S_WINDUP)
	var hp := player.current_hp
	var mp := player.current_mp
	TouchInput.joystick_active = true
	TouchInput.move_vector = Vector2.RIGHT
	TouchInput.queue_dash()
	await _wait_state(Guardian.S_RECOVER)
	_check(is_equal_approx(player.current_hp, hp)
		and is_equal_approx(mp - player.current_mp, CharacterStats.DASH_COST)
		and player.global_position.distance_to(_boss._move_origin) > _boss._move_radius,
		"真实触屏冲刺花费精力并移出圆圈规避重击")
	await _cleanup()

func _ordinary_target_loss() -> void:
	await _setup("guardian")
	await _wait_state(Guardian.S_WINDUP)
	var old_id := int(_boss._attack_context["attack_id"])
	await _frames(33)
	_target.visible = false
	await _frames(2)
	_check(_boss.state == MonsterBase.S_PATROL and _boss._attack_context.is_empty()
		and not _boss._ring.visible and not _boss._guard_hint.visible
		and _boss._attack_slot_target_id == 0 and is_zero_approx(_boss._action_anim_timer),
		"普通守卫目标隐藏即取消旧前摇、私有圈、身体动作和出手名额")
	_target.visible = true
	await _wait_state(Guardian.S_WINDUP)
	_check(int(_boss._attack_context["attack_id"]) != old_id
		and _boss._state_timer > _boss.inst.species.guard_windup_time * 0.9
		and _boss._attack_slot_target_id == _target.get_instance_id(),
		"目标重现必须重新取得名额并完整预警，不复用旧攻击")
	await _frames(22)
	_check((_target as Target).hits == 0 and _boss.state == Guardian.S_WINDUP,
		"旧攻击原到期时刻不会结算已取消伤害")
	for _frame in 60:
		if (_target as Target).hits > 0:
			break
		await get_tree().physics_frame
	_check((_target as Target).hits == 1, "重新获得名额后的新完整前摇仍能正常命中")
	await _cleanup()

func _migration_cleanup() -> void:
	for species_id in ["guardian", "turtle_king"]:
		await _setup(species_id)
		await _wait_state(Guardian.S_WINDUP)
		_boss.on_migrate("test", _boss.global_position + Vector2(600, 0))
		_check(_boss.state == MonsterBase.S_MIGRATING and not _boss._ring.visible
			and not _boss._guard_hint.visible and _boss._attack_context.is_empty()
			and is_zero_approx(_boss._state_timer) and is_zero_approx(_boss._action_anim_timer),
			"迁移回调清理守卫私有前摇和范围 " + species_id)
		await _frames(60)
		_check((_target as Target).hits == 0, "迁移后无旧招式延迟伤害 " + species_id)
		await _cleanup()
