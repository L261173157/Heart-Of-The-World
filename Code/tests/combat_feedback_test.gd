## 打击反馈真实闭环：输入→攻击形状/法弹→伤害→表现；另守住全局时间尺度的生命周期。
extends Node2D

const PLAYER := preload("res://scenes/player/player.tscn")
const GOBLIN := preload("res://scenes/monsters/goblin.tscn")
const HitStop := preload("res://scripts/combat/hit_stop_controller.gd")
var _checks := 0
var _fails := 0
var _player: Player
var _stop: Node
var _monsters: Array[MonsterBase] = []
var _damage_events := 0
var _stop_requests := 0
var _accepted_stops := 0
var _capture_dir := ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.save_enabled = false
	GameState.ecology_snapshot = null
	GameState.reset_all()
	GameState.settings.screen_shake = false
	TouchInput.reset()
	WorldSim.stop()
	WorldSim.sim = EcologySim.new()
	BiomeMap.configure(BiomeMap.DEFAULT_SEED)
	WorldSim.sim.instance_died.connect(_on_sim_death)
	_stop = HitStop.new()
	add_child(_stop)
	EventBus.hit_stop_requested.connect(_on_hit_stop)
	EventBus.damage_number.connect(_on_damage)
	_capture_dir = OS.get_environment("HOTW_COMBAT_CAPTURE_DIR")
	_run.call_deferred()

func _on_sim_death(inst: MonsterInstance, _cause: String) -> void:
	for monster in _monsters:
		if is_instance_valid(monster) and monster.inst == inst:
			monster.on_sim_death()

func _on_hit_stop(duration: float) -> void:
	_stop_requests += 1
	if _stop.request(duration):
		_accepted_stops += 1

func _on_damage(_pos: Vector2, _damage: int, hurt: bool, _effective: bool) -> void:
	if not hurt:
		_damage_events += 1

func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])

func _frames(n := 1) -> void:
	for i in n:
		await get_tree().physics_frame
		await get_tree().process_frame

func _wall(duration: float) -> void:
	await get_tree().create_timer(duration, true, false, true).timeout

func _monster(pos: Vector2) -> MonsterBase:
	var monster: MonsterBase = GOBLIN.instantiate()
	add_child(monster)
	monster.set_physics_process(false)
	var species: SpeciesData = preload("res://data/species/goblin.tres").duplicate()
	var inst := WorldSim.sim.spawn_instance(species, "feedback", 200, 0, 1.0, false, pos)
	monster.setup(inst)
	monster.global_position = pos
	monster.current_hp = 10000.0
	monster.collision_mask = 0
	_monsters.append(monster)
	return monster

func _capture(name: String) -> void:
	if _capture_dir == "" or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(_capture_dir)
	get_viewport().get_texture().get_image().save_png(_capture_dir.path_join(name + ".png"))

func _run() -> void:
	_player = PLAYER.instantiate()
	add_child(_player)
	_player.teleport_to(Vector2(3000, 3000))
	_player.set_process(false) # 资源不回满，便于核对击中前后消耗
	_player.current_hp = 10000.0
	_player.current_mp = 10000.0
	_player._protect_timer = 0.0
	_player.facing = Vector2.RIGHT
	var camera: Camera2D = _player.get_node("Camera2D")
	camera.zoom = Vector2(2.5, 2.5) if _capture_dir != "" else Vector2.ONE
	camera.snap_to_player()
	var a := _monster(_player.position + Vector2(36, -12))
	var b := _monster(_player.position + Vector2(36, 12))
	await _frames(3)
	await _capture("combat-before")
	var hp_a := a.current_hp
	var hp_b := b.current_hp
	var requests := _stop_requests
	var accepted := _accepted_stops
	var audio := SfxManager._next_channel
	TouchInput.queue_attack()
	for i in 35:
		await _frames()
		if a.current_hp < hp_a and b.current_hp < hp_b:
			break
	_check(a.current_hp < hp_a and b.current_hp < hp_b, "触屏普攻真实形状命中两只怪")
	_check(_damage_events == 2, "单次攻击每目标恰好结算一次")
	_check(_accepted_stops == accepted + 1 and _stop_requests == requests + 1, "AOE 共享一次极短顿帧")
	_check(SfxManager._next_channel == (audio + 1) % SfxManager.CHANNEL_COUNT,
		"群体命中同一音频窗只播一次已有 SFX")
	_check(a._impact_feedback != null and a._impact_feedback.active \
		and b._impact_feedback != null and b._impact_feedback.active,
		"每个真实目标都有独立接触火花及白闪")
	_check(a.visual.material is ShaderMaterial and a._impact_feedback.position.length() <= 18.1,
		"命中材质作用于精灵且火花紧贴物理身体")
	_check(a.visual.global_position.distance_to(a.to_global(a._visual_anchor)) <= 0.71,
		"打击反馈不改写固定美术锚点")
	await _capture("combat-impact")
	await _wall(0.25)
	_check(not _stop.active and is_equal_approx(Engine.time_scale, 1.0), "命中后真实时间恢复")
	_check(a.visual.material == null and not a._impact_feedback.active, "白闪/火花自然清理")
	await _capture("combat-recovered")
	# 后续连击使用真正的键盘/触屏；冷却照常流逝而非调用伤害辅助函数。
	for swing in 2:
		# 观察真实冷却接近预输入窗，避免壁钟等待叠加截图/调度耗时跨过连击窗。
		for frame in 120:
			if _player._attack_cooldown <= 0.05:
				break
			await _frames()
		hp_a = a.current_hp
		hp_b = b.current_hp
		if swing == 0:
			Input.action_press("attack")
		else:
			TouchInput.queue_attack()
		await _frames(2)
		Input.action_release("attack")
		# 有真实前摇和逐帧扫掠后，顿帧会拉长壁钟时间；观察实际双目标结算。
		for frame in 80:
			if a.current_hp < hp_a and b.current_hp < hp_b:
				break
			await _frames()
		_check(a.current_hp < hp_a and b.current_hp < hp_b, "重复输入第%d刀重新命中" % (swing + 2))
	_check(_player._combo == 3, "三段连击时序保持")
	# 重击真实输入与原有消耗；空挥不制造命中顿帧。
	await _wall(0.25)
	var mp := _player.current_mp
	hp_a = a.current_hp
	TouchInput.queue_heavy()
	await _frames(2)
	_check(a.current_hp < hp_a and is_equal_approx(_player.current_mp, mp - CharacterStats.HEAVY_COST),
		"重击实际命中/原有费用保持")
	await _wall(0.3)
	# 空挥必须有挥击表现，但没有命中停顿。
	a.position = _player.position + Vector2(500, 0)
	b.position = _player.position + Vector2(500, 50)
	_player._heavy_cd = 0.0
	requests = _stop_requests
	TouchInput.queue_heavy()
	await _frames(2)
	_check(_stop_requests == requests and not _stop.active, "重击空挥不伪造命中顿帧")
	# 多颗真实法弹同帧接触一个身体，不通过辅助函数伪造多目标闭环。
	a.position = _player.position + Vector2(130, 0)
	b.position = _player.position + Vector2(350, 0)
	a._knockback = Vector2.ZERO
	a._knockback_rearm = 0.0
	hp_a = a.current_hp
	var events := _damage_events
	for i in 8:
		var bolt := PlayerBolt.new()
		add_child(bolt)
		bolt.position = a.position - Vector2(28, 0)
		bolt.launch(Vector2.RIGHT, 2.0)
	await _frames(6)
	_check(a.current_hp < hp_a and _damage_events == events + 8, "八枚真实法弹各只结算一次")
	var resist := a.inst.species.knockback_resist + a.inst.species.poise * (1.0 - a.inst.species.knockback_resist)
	_check(a._knockback.length() <= CombatMath.KNOCKBACK_BASE * (1.0 - resist) + 0.01,
		"同帧多来源击退有界，不累加弹飞")
	var impact_start := a.position
	_player.visible = false
	a.state = MonsterBase.S_PATROL
	a._patrol_wait = 1.0
	a._nav.avoidance_enabled = true
	a.set_physics_process(true)
	await _wall(0.35)
	print("RVO_KNOCKBACK displacement=", a.position.distance_to(impact_start), " remaining=", a._knockback.length())
	_check(a.position.distance_to(impact_start) > 0.1 and a.position.distance_to(impact_start) < 25.0 \
		and a._knockback.length() < 0.1, "真实RVO/物理击退短距衰减，不被多弹累加推飞")
	_check(a.visual.global_position.distance_to(a.to_global(a._visual_anchor)) <= 0.71,
		"真实击退后精灵仍与碰撞身体对齐")
	a.set_physics_process(false)
	_player.visible = true
	# 持续受击时 AI 仍能正常出招；hurt 只是一层表现而非硬直状态。
	a.position = _player.position + Vector2(28, 0)
	a._nav.avoidance_enabled = false
	a._knockback = Vector2.ZERO
	a._knockback_rearm = 0.0
	a._attack_cd = 0.0
	a.state = MonsterBase.S_ATTACK
	a.set_physics_process(true)
	var player_hp := _player.current_hp
	for i in 24:
		a.take_damage(1.0, Vector2.INF)
		await _frames()
	_check(_player.current_hp < player_hp, "高频受击仍经过正常前摇并还击，不形成永久硬直")
	a.set_physics_process(false)
	await _time_lifecycle()
	await _sustained_hitstop()
	await _death_and_settings(a, b, camera)
	await _teleport_contract()
	_stop.cancel()
	Engine.time_scale = 1.0
	get_tree().paused = false
	WorldSim.stop()
	print("=== COMBAT FEEDBACK %s (%d checks) ===" % ["PASS" if _fails == 0 else "FAIL", _checks])
	get_tree().quit(0 if _fails == 0 else 1)

func _time_lifecycle() -> void:
	_player.set_physics_process(false)
	await _wall(0.3)
	for base in [1.0, 0.4, 3.0]:
		Engine.time_scale = base
		_check(_stop.request(10.0), "尺度%s接受首个请求" % base)
		var deadline: int = _stop._deadline_usec
		_check(is_equal_approx(Engine.time_scale, base * 0.35),
			"尺度%s保留35%%世界速度，不再近乎冻结" % base)
		_check(deadline - Time.get_ticks_usec() <= 45000,
			"终结技级请求的计划截止不超过45ms")
		for i in 12:
			_stop.request(10.0)
		_check(_stop._deadline_usec == deadline, "尺度%s重叠命中不延长截止时间" % base)
		await _wall(0.11)
		_check(not _stop.active and is_equal_approx(Engine.time_scale, base),
			"尺度%s在后续渲染回调恢复先前慢动作/加速" % base)
		_check(not _stop.request(0.04), "恢复间隔拒绝立即再停，避免连锁冻结")
		await _wall(0.18)
	# 普通命中只占21ms，快速请求不能堆积或挤掉至少200ms正常运动。
	Engine.time_scale = 1.0
	_check(_stop.request(0.035), "普通命中接受短促反馈")
	var deadline: int = _stop._deadline_usec
	_check(deadline - Time.get_ticks_usec() <= 21000 and
		_stop._next_allowed_usec - deadline == 200000, "普通命中21ms后至少200ms恢复运动")
	await _wall(0.05)
	_check(not _stop.active and is_equal_approx(Engine.time_scale, 1.0), "普通命中真实时钟恢复")
	for i in 20:
		_check(not _stop.request(0.05), "密集多目标请求%d不延长恢复间隔" % i)
	_check(_stop._deadline_usec == deadline, "拒绝请求不累加全局冻结预算")
	await _wall(0.2)
	Engine.time_scale = 0.6
	_stop.request(0.075)
	get_tree().paused = true
	await _wall(0.03)
	_check(not _stop.active and is_equal_approx(Engine.time_scale, 0.6), "暂停立即释放顿帧")
	_check(not _stop.request(0.05), "暂停期间不接受新顿帧")
	get_tree().paused = false
	await _wall(0.25)
	_stop.request(0.075)
	Engine.time_scale = 0.8
	await _wall(0.03)
	_check(not _stop.active and is_equal_approx(Engine.time_scale, 0.8), "外部新时间尺度不被旧恢复覆盖")
	await _wall(0.25)
	Engine.time_scale = 0.7
	var transient := HitStop.new()
	add_child(transient)
	transient.request(0.075)
	transient.queue_free()
	await get_tree().process_frame
	_check(is_equal_approx(Engine.time_scale, 0.7), "持有顿帧的场景卸载恢复原尺度")
	Engine.time_scale = 1.0


func _sustained_hitstop() -> void:
	await _wall(0.3)
	Engine.time_scale = 1.0
	var controller := HitStop.new()
	add_child(controller)
	var started := Time.get_ticks_usec()
	var restored := 0
	var accepted := 0
	var recovery_valid := true
	var request_deadlines_valid := true
	var previous_sample := started
	var largest_interval := 0
	var hold_started := 0
	var slowed_usec := 0
	var holds_bounded := true
	# 真实逐帧密集命中；保持世界在运行，不用推进私有时钟假装经过时间。
	while Time.get_ticks_usec() - started < 1200000:
		var was_active: bool = controller.active
		var duration: float = [0.035, 0.05, 0.075][accepted % 3]
		if controller.request(duration):
			accepted += 1
			hold_started = Time.get_ticks_usec()
			if restored > 0:
				recovery_valid = recovery_valid and Time.get_ticks_usec() - restored >= 200000 - largest_interval
			request_deadlines_valid = request_deadlines_valid and controller._deadline_usec - Time.get_ticks_usec() <= 45000
		was_active = was_active or controller.active
		await _wall(0.001) # 帧末定时器观察已执行的恢复，不读取内部恢复时间。
		var sampled := Time.get_ticks_usec()
		largest_interval = maxi(largest_interval, sampled - previous_sample)
		previous_sample = sampled
		if was_active and not controller.active:
			restored = sampled
			var held := sampled - hold_started
			slowed_usec += held
			holds_bounded = holds_bounded and held <= 45000 + largest_interval * 2
	_check(accepted >= 3 and accepted <= 6, "持续1.2秒密集命中保留反馈且不会连锁停顿")
	_check(recovery_valid and request_deadlines_valid, "普通/重击/终结技共用真实恢复间隔与时长预算")
	if controller.active:
		slowed_usec += Time.get_ticks_usec() - hold_started
	_check(holds_bounded and float(slowed_usec) / float(Time.get_ticks_usec() - started) < 0.35,
		"实际观察到的减速持续有界且大部分壁钟时间保持正常运动")
	controller.cancel()
	await _wall(0.3)
	_check(controller.request(0.035), "延迟恢复用例接受命中")
	controller.set_process(false)
	await _wall(0.3)
	controller._process(0.0)
	_check(not controller.active and is_equal_approx(Engine.time_scale, 1.0), "长帧后归还时间尺度")
	_check(not controller.request(0.035) and controller._next_allowed_usec - Time.get_ticks_usec() >= 190000,
		"长帧恢复仍预留200ms运动，不可立即再次顿帧")
	controller.queue_free()
	await get_tree().process_frame

func _death_and_settings(a: MonsterBase, b: MonsterBase, camera: Camera2D) -> void:
	await _wall(0.3)
	a.take_damage(1.0, _player.position)
	get_tree().paused = true
	await _wall(0.03)
	_check(not a._impact_feedback.active and a.visual.material == null, "暂停收回受击材质")
	get_tree().paused = false
	await _wall(0.12)
	var kills := GameState.session_kills
	a.take_damage(100000.0, _player.position, true)
	await _capture("combat-final-blow")
	a.take_damage(100000.0, _player.position, true)
	_check(a.state == MonsterBase.S_CORPSE and a.visual.material == null and a._knockback == Vector2.ZERO,
		"致死命中立刻清理白闪/击退，不污染尸体")
	_check(GameState.session_kills == kills + 1, "尸体重复命中不重复结算奖励")
	await _wall(0.3)
	Engine.time_scale = 0.55
	_stop.request(0.075)
	_player._hurt_iframes = 0.0
	_player._protect_timer = 0.0
	_player.take_damage(100000.0, b.position, "反馈测试")
	_check(_player._is_dead and not _stop.active and is_equal_approx(Engine.time_scale, 0.55),
		"玩家真实死亡路径释放顿帧且保存慢动作")
	_check(not _stop.request(0.05), "死亡期间拒绝迟到顿帧")
	_player._respawn()
	_check(not _stop._player_dead, "真实重生同步解除死亡锁")
	var respawn_wait := Time.get_ticks_usec()
	while (Time.get_ticks_usec() < _stop._next_allowed_usec or _stop.active) \
			and Time.get_ticks_usec() - respawn_wait < 1000000:
		await get_tree().process_frame
	_check(_stop.request(0.035), "真实重生后可再次命中反馈")
	_stop.cancel()
	Engine.time_scale = 1.0
	GameState.settings.screen_shake = true
	EventBus.camera_shake_requested.emit(1000.0)
	_check(camera._strength <= 9.0, "相机请求幅度有上限")
	GameState.settings.screen_shake = false
	await _frames(2)
	_check(camera._strength == 0.0 and camera.offset == Vector2.ZERO, "关闭震屏清除在途抖动")
	var bus := AudioServer.get_bus_index("SFX")
	AudioServer.set_bus_mute(bus, true)
	SfxManager._last_hit_sfx = -9999.0
	EventBus.damage_number.emit(_player.position, 1, false, false)
	_check(AudioServer.is_bus_mute(bus) and SfxManager._channels.all(func(ch): return ch.bus == &"SFX"),
		"反馈使用已有 SFX 总线，静音设置保持")
	AudioServer.set_bus_mute(bus, false)

func _teleport_contract() -> void:
	_player._protect_timer = 0.0
	_player._attack_cooldown = 0.0
	_player.position = Vector2(5000, 5000)
	_player._try_attack()
	_check(not _player.can_begin_town_return(), "攻击中不允许起手回城")
	var hp := _player.current_hp
	var mp := _player.current_mp
	var cd := _player._attack_cooldown
	var serial := _player.activity_serial
	var landing := Vector2(6000.25, 6100.5)
	var landing_target := _monster(landing + Vector2(30, 0))
	var landing_hp := landing_target.current_hp
	_player.teleport_to(landing)
	await _frames(2)
	_check(landing_target.current_hp == landing_hp, "传送结束旧攻击时不会在目的地补刀")
	_check(_player.velocity == Vector2.ZERO and _player._knockback == Vector2.ZERO \
		and _player.attack_shape.disabled and _player._attack_timer == 0.0,
		"传送清理移动/攻击判定，不带旧碰撞到目的地")
	_check(_player.current_hp == hp and _player.current_mp == mp and _player._attack_cooldown == cd,
		"传送不返还生命/精力/冷却")
	_check(_player.activity_serial > serial and _player.can_begin_town_return(), "传送活动序号与起手状态同步")
	_check(_player.visual.global_position.distance_to(_player.to_global(_player._visual_anchor)) <= 0.71,
		"非整数传送保持固定锚点")
