## 真实玩家输入/碰撞驱动的新战斗节奏；不以手动调用伤害函数替代释放闭环。
extends Node2D

const PLAYER := preload("res://scenes/player/player.tscn")
const GOBLIN := preload("res://scenes/monsters/goblin.tscn")
var _player: Player
var _target: MonsterBase
var _checks := 0
var _fails := 0
var _origin := Vector2.ZERO

func _ready() -> void:
	seed(20261009)
	GameState.save_enabled = false
	GameState.reset_all()
	GameState.settings.auto_aim = false
	GameState.settings.screen_shake = false
	WorldSim.stop()
	WorldSim.sim = EcologySim.new()
	BiomeMap.configure(BiomeMap.DEFAULT_SEED)
	TouchInput.reset()
	_origin = WorldConfig.spawn_pos()
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])

func _frames(count := 1) -> void:
	for _i in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func _reset() -> void:
	Input.action_release("attack")
	TouchInput.reset()
	for bolt in get_tree().get_nodes_in_group("player_bolts"):
		bolt.queue_free()
	if is_instance_valid(_target):
		_target.queue_free()
	if is_instance_valid(_player):
		_player.queue_free()
	await _frames(2)
	GameState.stats = CharacterStats.new()
	_player = PLAYER.instantiate()
	add_child(_player)
	_player.get_node("Camera2D").enabled = false
	_player.set_process(false)
	_player.teleport_to(_origin)
	_player.current_mp = 1000.0
	await _frames(2)

func _monster(defense := 0.0, offset := Vector2(48, 0)) -> void:
	_target = GOBLIN.instantiate()
	add_child(_target)
	_target.set_physics_process(false)
	_target.set_process(false)
	var species: SpeciesData = preload("res://data/species/goblin.tres").duplicate()
	species.defense_reduction = defense
	var instance := WorldSim.sim.spawn_instance(species, "hero_timing", 200, 0, 1.0, false, _origin + offset)
	_target.setup(instance)
	_target.global_position = _origin + offset
	_target.current_hp = 10000.0
	_target.collision_mask = 0
	await _frames(2)

func _run() -> void:
	await _combo_budget()
	await _healing_snapshot_contract()
	await _buffer_contract()
	await _skill_buffer_contract()
	await _heavy_contract()
	await _bolt_contract()
	await _cancel_contract()
	await _save_contract()
	await _release_callback_contract()
	await _reset()
	_player.queue_free()
	await _frames(2)
	WorldSim.stop()
	print("=== HERO COMBAT TIMING %s (%d checks) ===" % ["PASS" if _fails == 0 else "FAIL", _checks])
	get_tree().quit(0 if _fails == 0 else 1)

func _combo_budget() -> void:
	for agility in [5, 35, 100]:
		for defense in [0.0, 0.4, 0.8]:
			await _reset()
			_player.stats.agility = agility
			await _monster(defense)
			var start_frames: Array[int] = []
			var previous := 100.0
			var damage := 0.0
			var hp := _target.current_hp
			for frame in 240:
				if frame % 3 == 0:
					TouchInput.queue_attack()
				await _frames()
				if _player._attack_elapsed < previous:
					start_frames.append(frame)
					if start_frames.size() == 4:
						break
				previous = _player._attack_elapsed
				damage += hp - _target.current_hp
				hp = _target.current_hp
			var base_interval := maxf(Player.ATTACK_WINDOW, _player.stats.attack_interval())
			var baseline_dps: float = _player.stats.physical_attack() * 3.5 * (1.0 - defense) / (base_interval * 3.0)
			var actual_cycle := float(start_frames[-1] - start_frames[0]) / 60.0 if start_frames.size() == 4 else 999.0
			var ratio: float = damage / actual_cycle / baseline_dps
			var nominal_cycle := 0.0
			for step in range(1, 4):
				nominal_cycle += _player.stats.combo_attack_interval(step)
			_check(start_frames.size() == 4 and absf(actual_cycle - nominal_cycle) <= 0.051,
				"敏捷%d护甲%.1f真实输入连续三刀按目标节奏 %.3fs（实际%.3fs）" % [agility, defense, nominal_cycle, actual_cycle])
			_check(ratio >= 0.86 and ratio <= 1.10,
				"敏捷%d护甲%.1f实际扣血DPS %.2f，旧基线%.2f，比值%.3f；护甲后不膨胀" % [agility, defense, damage / actual_cycle, baseline_dps, ratio])
			_check(_player._combo == 1, "真实第四次出招重新从第一段开始")

func _buffer_contract() -> void:
	await _reset()
	TouchInput.queue_attack()
	await _frames(2)
	# 离转好还有0.20秒以内：只接受一个后续手势，两通道同帧不叠两刀。
	while _player._attack_cooldown > 0.15:
		await _frames()
	Input.action_press("attack")
	TouchInput.queue_attack()
	await _frames()
	Input.action_release("attack")
	await _frames(12)
	_check(_player._combo == 2 and _player._attack_buffer_timer == 0.0,
		"冷却末段键盘与触屏重叠预输入只兑现第二刀，成功起手清空队列")
	await _frames(50)
	_check(_player._combo == 2 and _player._attack_timer == 0.0, "放手后没有第三刀幽灵输入")
	await _reset()
	TouchInput.queue_attack()
	await _frames(2)
	TouchInput.queue_attack()
	await _frames(40)
	_check(_player._combo == 1, "过早预输入到期后不在遥远将来补刀")

func _heavy_contract() -> void:
	await _reset()
	await _monster()
	var mp := _player.current_mp
	TouchInput.queue_heavy()
	await _frames(2)
	_check(_player._skill_action == "heavy" and _target.current_hp == 10000.0
		and _player.current_mp == mp - CharacterStats.HEAVY_COST, "重击起手支付一次且蓄势没有瞬发伤害")
	await _frames(10)
	_check(_target.current_hp == 10000.0 and _player.visual.frame <= 1, "重击前摇保持原画蓄势身体，不提前伤害")
	await _frames(8)
	var hp := _target.current_hp
	_check(hp < 10000.0 and _player._skill_released, "重击跨过释放点真实AOE只结算一次")
	var paid := _player.current_mp
	TouchInput.queue_bolt()
	await _frames(4)
	_check(_player._skill_action == "heavy" and _player.visual.frame == 3
		and _target.current_hp == hp and _player.current_mp == paid, "重击收势不重伤、不叠放法弹、不额外扣蓝")
	await _frames(14)
	_check(_player._skill_action.is_empty() and not _player._skill_feedback.visible
		and not _player._weapon_visual.active, "重击收势结束清理武器与蓄力提示")

func _bolt_contract() -> void:
	await _reset()
	await _monster(0.0, Vector2(105, 0))
	Input.action_press("cast_bolt")
	await _frames(2)
	Input.action_release("cast_bolt")
	_check(_player._skill_action == "bolt" and get_tree().get_nodes_in_group("player_bolts").is_empty(),
		"键盘法弹先出现施法身体与聚能，释放前没有弹体")
	_player.facing = Vector2.LEFT
	await _frames(10)
	var bolts := get_tree().get_nodes_in_group("player_bolts")
	_check(bolts.size() == 1 and bolts[0].direction.dot(Vector2.RIGHT) > 0.999,
		"法弹只从锁定施法方向释放一次，不随收势走位反向")
	await _frames(20)
	_check(_target.current_hp < 10000.0 and _player._skill_action.is_empty(),
		"真实法弹飞行碰撞扣血，施法收势独立结束")

func _cancel_contract() -> void:
	for kind in ["heavy", "bolt"]:
		for cancel in ["dash", "guard", "pause", "teleport", "death", "focus"]:
			await _reset()
			await _monster()
			if kind == "heavy":
				TouchInput.queue_heavy()
			else:
				TouchInput.queue_bolt()
			await _frames(3)
			TouchInput.queue_attack()
			await _frames() # 中断必须同时作废已消费进玩家缓冲的普攻。
			var paid := _player.current_mp
			var cd: float = _player._heavy_cd if kind == "heavy" else _player._bolt_cd
			match cancel:
				"dash":
					TouchInput.queue_dash()
					await _frames()
				"guard":
					_player.begin_guard()
				"pause":
					get_tree().paused = true
					await get_tree().process_frame
					get_tree().paused = false
				"teleport":
					_player.teleport_to(_origin + Vector2(0, 200))
				"death":
					_player._die()
				"focus":
					_player.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
			await _frames(42)
			_check(_player._skill_action.is_empty() and _target.current_hp == 10000.0
				and get_tree().get_nodes_in_group("player_bolts").is_empty() and _player._combo == 0,
				"%s %s中断释放前没有迟到伤害或幽灵弹" % [kind, cancel])
			_check(_player.current_mp <= paid and cd > 0.0 and not _player._skill_feedback.visible,
				"%s %s中断不退款、保留已支付冷却、清理蓄力提示" % [kind, cancel])


func _healing_snapshot_contract() -> void:
	await _reset()
	await _monster()
	_player.stats.passives = {"lifesteal": 1}
	_player._empower_timer = 5.0
	_player.current_hp = 20.0
	var snapshot := _player.stats.benefit_snapshot()
	var scale := _player.stats.combo_output_mult()
	_check(is_equal_approx(snapshot.attack_interval, _player.stats.combo_mean_interval())
		and is_equal_approx(snapshot.lifesteal, _player.stats.lifesteal_per_hit() * scale),
		"收益预览显示真实平均连击间隔与每刀归一吸血")
	var expected := (_player.stats.lifesteal_per_hit() + _player.stats.max_hp() * CharacterStats.EMPOWER_HEAL_FRAC) * scale
	TouchInput.queue_attack()
	await _frames(24)
	_check(is_equal_approx(_player.current_hp - 20.0, expected),
		"真实强化刀命中只结算归一后的吸血与强化回复，提速不提高持续回血")


func _save_contract() -> void:
	for kind in ["heavy", "bolt"]:
		await _reset()
		_player.current_mp = _player.stats.max_mp()
		if kind == "heavy":
			TouchInput.queue_heavy()
		else:
			TouchInput.queue_bolt()
		await _frames(4)
		var snapshot := _player.save_snapshot()
		var paid := _player.current_mp
		_player.queue_free()
		await _frames(2)
		GameState.player_snapshot = snapshot
		_player = PLAYER.instantiate()
		add_child(_player)
		_player.get_node("Camera2D").enabled = false
		_player.set_process(false)
		GameState.player_snapshot = {}
		var cd: float = _player._heavy_cd if kind == "heavy" else _player._bolt_cd
		await _frames(35)
		_check(_player._skill_action.is_empty() and get_tree().get_nodes_in_group("player_bolts").is_empty()
			and _player.current_mp == paid and cd > 0.0, "%s存档恢复保留费用与冷却，不恢复半招或产生幽灵释放" % kind)


func _skill_buffer_contract() -> void:
	for kind in ["heavy", "bolt"]:
		await _reset()
		if kind == "heavy":
			TouchInput.queue_heavy()
		else:
			TouchInput.queue_bolt()
		await _frames()
		while _player._skill_duration() - _player._skill_elapsed > 0.15:
			await _frames()
		TouchInput.queue_attack()
		await _frames(12)
		_check(_player._skill_action.is_empty() and _player._combo == 1
			and _player._attack_buffer_timer == 0.0, "%s收势末段普攻预输入在动作结束兑现一次" % kind)
		await _frames(25)
		_check(_player._combo == 1, "%s收势预输入没有重复排入第二刀" % kind)


func _release_callback_contract() -> void:
	await _reset()
	await _monster()
	var pause_on_impact := func(_pos: Vector2, _amount: int, is_player: bool, _effective: bool) -> void:
		if not is_player:
			get_tree().paused = true
	EventBus.damage_number.connect(pause_on_impact)
	TouchInput.queue_heavy()
	for frame in 40:
		await _frames()
		if get_tree().paused:
			break
	_check(get_tree().paused and _target.current_hp < 10000.0 and _player._skill_action.is_empty()
		and not _player._skill_feedback.visible and not _player._weapon_visual.active,
		"真实重击命中回调暂停时，释放栈返回后不复活已取消的技能表现")
	var hp := _target.current_hp
	EventBus.damage_number.disconnect(pause_on_impact)
	get_tree().paused = false
	await _frames(30)
	_check(_target.current_hp == hp and _player._skill_action.is_empty(),
		"命中回调中断恢复后不追加第二次技能伤害")
