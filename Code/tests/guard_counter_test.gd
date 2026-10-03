## 架盾反击闭环：真实双通道输入、物理帧、飞行弹幕、怪物前摇与定向扫掠。
## 测试进程必须使用独立 HOTW_TEST_SAVE；本场景另关闭所有保存。
extends Node2D

const PLAYER := preload("res://scenes/player/player.tscn")
const GOBLIN := preload("res://scenes/monsters/goblin.tscn")
var _checks := 0
var _fails := 0
var _player: Player
var _targets: Array[MonsterBase] = []
var _origin := Vector2.ZERO
var _attack_id := 100000
var _damage_events := 0
var _last_effective := false
var _guard_events: Array[Dictionary] = []

func _ready() -> void:
	GameState.save_enabled = false
	GameState.ecology_snapshot = null
	GameState.reset_all()
	GameState.settings.auto_aim = false
	GameState.settings.screen_shake = false
	WorldSim.stop()
	WorldSim.sim = EcologySim.new()
	BiomeMap.configure(BiomeMap.DEFAULT_SEED)
	ObstacleField.restore_destroyed([])
	TouchInput.reset()
	Projectile.clear_pool()
	_origin = WorldConfig.spawn_pos()
	EventBus.damage_number.connect(_on_damage)
	EventBus.player_guard_changed.connect(_on_guard)
	_run.call_deferred()

func _on_damage(_pos: Vector2, _damage: int, hurt: bool, effective: bool) -> void:
	if not hurt:
		_damage_events += 1
		_last_effective = effective

func _on_guard(state: String, charge: int, strength: float, break_remaining: float) -> void:
	_guard_events.append({"state": state, "charge": charge, "strength": strength, "break": break_remaining})

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
	Input.action_release("guard")
	TouchInput.reset()
	_player.teleport_to(_origin)
	_player.set_process(false)
	_player.current_hp = 1000.0
	_player.current_mp = 1000.0
	_player.stats.strength = 5
	_player.stats.agility = 5
	_player.stats.passives = {}
	_player.stats.equips = {}
	_player._hurt_iframes = 0.0
	_player._protect_timer = 0.0
	_player._attack_cooldown = 0.0
	_player._empower_timer = 0.0
	_player._dash_buff_timer = 0.0
	await _frames(2)
	TouchInput.joystick_active = true
	TouchInput.move_vector = Vector2.RIGHT
	await _frames(3)
	TouchInput.move_vector = Vector2.ZERO
	await _frames(10)

func _arm(keyboard := false) -> void:
	if keyboard:
		Input.action_press("guard")
	else:
		TouchInput.begin_guard()
	await _frames(8)

func _incoming(amount: float, strength: float, direction := Vector2.RIGHT,
		blockable := true, duplicate_id := -1) -> int:
	_attack_id += 1
	var id := _attack_id if duplicate_id < 0 else duplicate_id
	_player.take_damage(amount, _player.global_position + direction * 80.0, "测试敌人",
		{"strength": strength, "blockable": blockable, "incoming_direction": direction, "attack_id": id})
	return id

func _charge(count: int) -> void:
	for _i in count:
		_incoming(10.0, 10.0)

func _monster(offset: Vector2, species_id := "goblin", scene: PackedScene = GOBLIN) -> MonsterBase:
	var monster: MonsterBase = scene.instantiate()
	add_child(monster)
	monster.set_physics_process(false)
	var species: SpeciesData = load("res://data/species/%s.tres" % species_id).duplicate()
	var pos := _player.global_position + offset
	var inst := WorldSim.sim.spawn_instance(species, "guard", 200, 0, 1.0, false, pos)
	monster.setup(inst)
	monster.global_position = pos
	monster.current_hp = 10000.0
	monster.collision_mask = 0
	monster._nav.avoidance_enabled = false
	_targets.append(monster)
	return monster

func _clear_targets() -> void:
	for target in _targets:
		if is_instance_valid(target):
			target.queue_free()
	_targets.clear()
	await _frames(2)

func _run() -> void:
	_player = PLAYER.instantiate()
	add_child(_player)
	_player.get_node("Camera2D").enabled = false
	await _reset()
	_formula_contract()
	await _raising_movement_regen()
	await _direction_and_identity()
	await _break_and_decay()
	await _counter_targets()
	await _counter_passive_isolation()
	await _counter_wall()
	await _projectile_contract()
	await _enemy_warnings()
	await _environment_contract()
	await _skin_and_lifecycle()
	TouchInput.reset()
	Input.action_release("guard")
	await _clear_targets()
	_player.queue_free()
	await _frames(30)
	Projectile.clear_pool()
	WorldSim.stop()
	print("=== GUARD COUNTER %s (%d checks) ===" % ["PASS" if _fails == 0 else "FAIL", _checks])
	get_tree().quit(0 if _fails == 0 else 1)

func _formula_contract() -> void:
	_check(is_equal_approx(_player.stats.guard_strength(), 35.0), "初始5力量盾强为35")
	_player.stats.strength = 12
	_check(is_equal_approx(_player.stats.guard_strength(), 56.0), "盾强实时按20+3STR成长")
	_player.stats.strength = 5
	_check(is_equal_approx(CharacterStats.guard_hit_cost(35.0), 15.0), "命中耗蓝8+0.2S")
	for charge in range(1, 4):
		_check(is_equal_approx(CharacterStats.guard_counter_mult(charge), [1.4, 1.8, 2.2][charge - 1]), "反击%d层固定倍率" % charge)
	_check(_player.stats.guard_warning(27.99) == "normal" and _player.stats.guard_warning(28.0) == "near"
		and _player.stats.guard_warning(35.0) == "near" and _player.stats.guard_warning(35.01) == "break"
		and _player.stats.guard_warning(1.0, false) == "unblockable", "预警阈值覆盖黄/红/不可挡边界")

func _raising_movement_regen() -> void:
	await _reset()
	var serial := _player.activity_serial
	TouchInput.begin_guard()
	await _frames()
	_check(_player.guard_state == "raising" and _player.activity_serial > serial, "真实按住先进入0.1秒举盾且记录活动")
	_check(not _player.can_begin_town_return(), "举盾期间禁止开始回城")
	_incoming(9.0, 9.0)
	_check(is_equal_approx(_player.current_hp, 991.0) and _player.guard_charge == 0, "前摇未完成不能提前格挡")
	await _reset()
	await _arm()
	_check(_player.guard_state == "guarding" and not _player.can_begin_town_return(), "持续按住超过0.1秒进入防御并阻止回城")
	TouchInput.joystick_active = true
	TouchInput.move_vector = Vector2.RIGHT
	await _frames(12)
	_check(absf(_player.velocity.length() - _player.stats.move_speed() * 0.5) < 0.1, "真实移动物理速度为正常一半")
	TouchInput.move_vector = Vector2.ZERO
	await _frames(10)
	_player.current_hp = _player.stats.max_hp()
	_player.current_mp = 30.0
	_player.stats.passives = {"mp_regen": 5}
	_player.set_process(true)
	await _frames(60)
	_check(absf(_player.current_mp - 26.0) < 0.25, "持续1秒仅消耗4MP，回复赐福也不抵消架盾消耗")
	_player.set_process(false)
	TouchInput.release_guard()
	await _frames(2)
	_check(_player.guard_state == "idle" and not _player._weapon_visual.active, "零蓄力松手仅收盾")
	await _reset()
	var target := _monster(Vector2(62, 0))
	await _frames(2)
	TouchInput.queue_attack()
	await _frames(3)
	TouchInput.begin_guard()
	await _frames(8)
	_check(_player.guard_state == "guarding" and not _player._weapon_visual.active
		and _player._attack_timer <= 0.0 and target.current_hp == 10000.0,
		"普通挥刀前摇中举盾立即取消旧判定，不把挡和刀叠加")
	_check(_player._attack_cooldown > 0.0, "举盾取消旧普攻不返还已经消耗的攻击冷却")
	await _clear_targets()


func _direction_and_identity() -> void:
	for angle in [0.0, 59.9, 60.0, 60.1, 90.0, 180.0, -60.0, -60.1]:
		await _reset()
		await _arm()
		var direction := Vector2.RIGHT.rotated(deg_to_rad(angle))
		var before := _player.current_hp
		_incoming(10.0, 10.0, direction)
		var front := absf(angle) <= 60.0
		_check(is_equal_approx(_player.current_hp, before if front else before - 10.0), "120度正面角边界%.1f度真实承伤" % angle)
		_check(_player.guard_charge == (1 if front else 0), "角度%.1f仅成功正挡获得蓄力" % angle)
		if not front:
			_check(_player.guard_state != "guarding", "侧后%.1f中断防御" % angle)
	await _reset()
	await _arm()
	var mp := _player.current_mp
	var serial := _player.activity_serial
	var id := _incoming(31.5, 35.0)
	_incoming(38.5, 35.0)
	_incoming(31.5, 35.0, Vector2.RIGHT, true, id)
	_check(_player.current_hp == 1000.0 and _player.guard_charge == 2, "±10%实际伤害不改变S=G可挡类别；同帧两个攻击各加一层")
	_check(is_equal_approx(mp - _player.current_mp, 30.0) and _player._hurt_iframes <= 0.0, "重复attack_id不重复收费/充能，挡住不发受击无敌帧")
	_check(_player.activity_serial > serial, "成功防御也中止回城活动序列")
	_charge(3)
	_check(_player.guard_charge == 3, "连续独立攻击蓄力封顶三层")
	_incoming(7.0, 7.0, Vector2.LEFT)
	_check(_player.current_hp == 993.0 and _player.guard_charge == 0, "同帧正挡后背击仍生效且清空蓄力")

func _break_and_decay() -> void:
	for amount in [36.0, 44.0]:
		await _reset()
		await _arm()
		var mp := _player.current_mp
		_incoming(amount, 40.0)
		_check(absf(_player.current_hp - (1000.0 - amount * (1.0 - 35.0 / 40.0))) < 0.001,
			"S>G随机伤害%.0f按实际伤害溢出比例透盾" % amount)
		_check(is_equal_approx(mp - _player.current_mp, 15.0) and _player.guard_state == "broken"
			and _player.guard_charge == 0 and absf(_player._guard_break_timer - 0.6) < 0.02,
			"破盾以G计费且硬直0.6秒")
		await _frames(20)
		_check(_player.guard_state == "broken", "破盾0.33秒仍不可恢复")
		await _frames(20)
		_check(_player.guard_state != "broken", "破盾0.6秒自然结束")
	await _reset()
	await _arm()
	_incoming(0.1, 35.01)
	_check(_player.current_hp == 999.0, "微量溢出仍至少造成1HP")
	await _reset()
	await _arm()
	_player.current_mp = 9.99
	_incoming(11.0, 10.0)
	_check(_player.current_hp == 989.0 and _player.guard_state == "broken" and _player.guard_charge == 0,
		"命中费用不足承受全额伤害并破盾")
	await _reset()
	await _arm()
	_player.current_mp = 10.0
	_incoming(11.0, 10.0)
	_check(_player.current_hp == 1000.0 and is_zero_approx(_player.current_mp), "MP恰好支付费用时本次成功挡住")
	await _frames(2)
	_check(_player.guard_state == "broken", "成功挡后MP耗尽在持续持盾帧破盾")
	await _reset()
	await _arm()
	_player.current_mp = 0.01
	await _frames(2)
	_check(_player.guard_state == "broken" and _player.current_mp >= 0.0, "自然消耗耗尽不产生负MP且破盾")
	await _reset()
	await _arm()
	_charge(3)
	await _frames(170)
	_check(_player.guard_charge == 3, "成功格挡后未满3秒保留三层")
	await _frames(20)
	_check(_player.guard_charge == 2, "3秒无新格挡开始逐层衰减")
	await _frames(125)
	_check(_player.guard_charge == 0, "持续无格挡最终清空全部蓄力")

func _counter_targets() -> void:
	for charge in range(1, 4):
		await _reset()
		await _arm(charge == 2)
		_charge(charge)
		var near := _monster(Vector2(62, 0))
		var back := _monster(Vector2(-62, 0))
		var far := _monster(Vector2(88, 0))
		await _frames(2)
		var events := _damage_events
		if charge == 2:
			Input.action_release("guard")
		else:
			TouchInput.release_guard()
		await _frames(2)
		_check(_player.guard_state == "counter" and _player.guard_charge == 0
			and _player._weapon_visual.active and not _player.can_begin_town_return(), "松手%d层以快照开始一次反击" % charge)
		_check(near.current_hp == 10000.0 and _player.attack_shape.disabled, "反击%d层蓄势没有提前伤害" % charge)
		_check(_player._weapon_visual.combo == (3 if charge == 3 else 1),
			"反击%d层独立武器使用对应连击视觉级别，满层明确为3" % charge)

		var first_hit := -1.0
		var frames_seen := {}
		for _i in 24:
			await _frames()
			if _player._attack_anim_linger > 0.0:
				frames_seen[_player.visual.frame] = true
			if near.current_hp < 10000.0 and first_hit < 0.0:
				first_hit = _player._attack_elapsed
		_check(frames_seen.size() == 4, "反击%d层在真实命中流程完整播放四帧" % charge)
		var base: float = _player.stats.physical_attack() * [1.4, 1.8, 2.2][charge - 1]
		var dealt := 10000.0 - near.current_hp
		_check(dealt >= base * 0.9 - 0.01 and dealt <= base * 1.1 + 0.01, "反击%d层伤害仅使用对应物理倍率" % charge)
		_check(first_hit >= Player.ATTACK_WINDUP and first_hit <= Player.ATTACK_WINDOW + 0.001,
			"反击%d层沿用0.16至0.26秒实际扫掠窗" % charge)
		_check(back.current_hp == 10000.0 and far.current_hp == 10000.0 and _damage_events == events + 1,
			"反击%d层仅一次命中正前66px内目标" % charge)
		TouchInput.release_guard()
		await _frames(25)
		_check(_damage_events == events + 1 and _player.guard_state == "idle" and not _player._weapon_visual.active,
			"反击%d层重复松手不补刀且自然收尾" % charge)
		await _clear_targets()

func _counter_passive_isolation() -> void:
	await _reset()
	_player.stats.passives = {"sword_sweep": 1, "lifesteal": 3, "knock": 1}
	_player.stats.equips = {"weapon": {"element": "fire", "affixes": {"lifesteal": 0.5}}}
	_player._combo = 2
	_player._combo_timer = 5.0
	await _arm()
	_charge(3)
	_player._dash_buff_timer = 5.0
	_player._empower_timer = 5.0
	_player.current_hp = 40.0
	var target := _monster(Vector2(45, 0))
	target.inst.species.defense_reduction = 0.25
	target.inst.species.element = "ice"
	var flank := _monster(Vector2.RIGHT.rotated(deg_to_rad(78.0)) * 65.0)
	await _frames(2)
	TouchInput.release_guard()
	await _frames(25)
	var base := _player.stats.physical_attack() * 2.2 * 1.5 * 0.75
	var dealt := 10000.0 - target.current_hp
	_check(dealt >= base * 0.9 - 0.01 and dealt <= base * 1.1 + 0.01,
		"三层反击不叠第三刀/冲刺/强化/阔刃倍率，仍保留元素和单次护甲")
	_check(_player.current_hp == 40.0 and _last_effective, "反击不触发吸血或强化回血，但仍有克制反馈")
	_check(flank.current_hp == 10000.0 and is_equal_approx(_player._attack_half_arc, Player.ATTACK_HALF_ARC),
		"阔刃不扩大反击固定扇形")
	_check(target._knockback.length() > 0.0, "反击仍走目标击退/抗性语义")
	_check(_player._combo == 0, "防御反击不占普通第三刀连击进度")
	await _clear_targets()

func _counter_wall() -> void:
	await _reset()
	await _arm()
	_charge(1)
	var target := _monster(Vector2(62, 0))
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(10, 160)
	shape.shape = rect
	wall.add_child(shape)
	add_child(wall)
	wall.global_position = _player.global_position + Vector2(32, 0)
	await _frames(2)
	TouchInput.release_guard()
	await _frames(25)
	_check(target.current_hp == 10000.0, "反击实体墙后目标不受伤")
	wall.queue_free()
	await _clear_targets()

func _projectile_contract() -> void:
	await _reset()
	await _arm()
	var origin := _player.global_position
	var p := Projectile.spawn(self, origin + Vector2(100, 0), Vector2.LEFT, 38.5, 300.0,
		"正面射手", "bone", {"strength": 35.0, "blockable": true})
	var first_id: Variant = p.attack_context.attack_id
	await _frames(30)
	_check(_player.current_hp == 1000.0 and _player.guard_charge == 1 and not p.is_inside_tree(),
		"真实正面飞行弹幕用反飞行方向和稳定强度格挡并回池")
	var back := Projectile.spawn(self, origin - Vector2(100, 0), Vector2.RIGHT, 9.0, 300.0,
		"背面射手", "acorn", {"strength": 9.0, "blockable": true})
	_check(back == p and back.attack_context.attack_id != first_id
		and back.attack_context.incoming_direction == Vector2.LEFT, "同一弹体回池复用重建攻击ID与来向")
	await _frames(30)
	_check(_player.current_hp == 991.0 and _player.guard_charge == 0 and _player.guard_state == "idle",
		"复用弹幕真实从背后飞来时不能被正面盾挡住")
	await _reset()
	await _arm()
	var blocked := Projectile.spawn(self, _player.global_position + Vector2(100, 0), Vector2.LEFT,
		5.0, 300.0, "不可挡测试", "bomb", {"strength": 50.0, "blockable": false})
	var blocked_id: Variant = blocked.attack_context.attack_id
	await _frames(30)
	_check(_player.current_hp == 995.0 and _player.guard_charge == 0, "不可挡弹幕元数据真实穿过盾结算")
	await _reset()
	await _arm()
	var plain := Projectile.spawn(self, _player.global_position + Vector2(100, 0), Vector2.LEFT, 10.0, 300.0)
	_check(plain == blocked and plain.attack_context.blockable and plain.attack_context.strength == 10.0
		and plain.attack_context.attack_id != blocked_id, "复用默认发射不会残留前一发不可挡/强度/ID")
	await _frames(30)
	_check(_player.current_hp == 1000.0 and _player.guard_charge == 1, "清理元数据后的复用弹幕可以正常格挡")
	Projectile.clear_pool()

func _enemy_warnings() -> void:
	var cases := [
		{"id": "goblin", "scene": GOBLIN, "distance": 36.0, "strength": 10.0, "warning": "normal"},
		{"id": "goblin", "scene": GOBLIN, "distance": 36.0, "strength": 30.0, "warning": "near"},
		{"id": "goblin", "scene": GOBLIN, "distance": 36.0, "strength": 40.0, "warning": "break"},
		{"id": "boar", "scene": preload("res://scenes/monsters/boar.tscn"), "distance": 180.0, "strength": 30.0, "warning": "near"},
		{"id": "spider", "scene": preload("res://scenes/monsters/spider.tscn"), "distance": 180.0, "strength": 40.0, "warning": "break"},
		{"id": "guardian", "scene": preload("res://scenes/monsters/guardian.tscn"), "distance": 45.0, "strength": 10.0, "warning": "unblockable"},
	]
	for c in cases:
		await _reset()
		await _arm()
		var monster := _monster(Vector2(c.distance, 0), c.id, c.scene)
		var multiplier := monster.inst.species.charge_damage_mult if c.id == "boar" else monster._melee_damage_mult()
		monster.inst.species.offense_scale *= float(c.strength) / (monster.inst.attack_power() * multiplier)
		monster._player_ref = _player
		monster.state = MonsterBase.S_CHASE
		monster.set_physics_process(true)
		var saw_warning := false
		var snapshot := {}
		for _i in 100:
			await _frames()
			if monster._guard_hint != null and monster._guard_hint.visible:
				saw_warning = true
				snapshot = monster._attack_context.duplicate(true)
				break
		_check(saw_warning, "%s真实状态机进入可见前摇" % c.id)
		if saw_warning:
			_check(monster._guard_hint.warning == c.warning
				and absf(monster._guard_hint.strength - float(c.strength)) < 0.01,
				"%s真实招式预警=%s且使用含招式倍率的稳定S" % [c.id, c.warning])
			_check(monster._guard_hint.blockable == (c.warning != "unblockable")
				and snapshot.has("attack_id"), "%s前摇具有明确可挡标识与唯一攻击ID" % c.id)
			# 改变活体攻击力不能改写已经亮出的这一招；真正击中仍消费前摇快照。
			monster.inst.species.offense_scale *= 2.0
			for _i in 110:
				await _frames()
				if _player.current_hp < 1000.0 or _player.guard_charge > 0:
					break
			monster.set_physics_process(false)
			if c.warning in ["normal", "near"]:
				_check(_player.current_hp == 1000.0 and _player.guard_charge == 1,
					"%s真实出招遵循旧预警强度而非中途属性变化" % c.id)
			else:
				_check(_player.current_hp < 1000.0 and _player.guard_charge == 0,
					"%s真实%s出招不能被完全挡住" % [c.id, c.warning])
				var original_strength := float(snapshot["strength"])
				var lower := maxf(1.0, original_strength * 0.9)
				var upper := maxf(1.0, original_strength * 1.1)
				if bool(snapshot["blockable"]):
					var overflow_ratio := 1.0 - _player.stats.guard_strength() / original_strength
					lower = maxf(1.0, lower * overflow_ratio)
					upper = maxf(1.0, upper * overflow_ratio)
				var dealt := 1000.0 - _player.current_hp
				_check(dealt >= lower - 0.01 and dealt <= upper + 0.01,
					"%s%s实际扣血%.3f受原S=%.1f的[%.3f,%.3f]约束，排除翻倍活体攻击力" %
					[c.id, c.warning, dealt, original_strength, lower, upper])

			_check(not monster._guard_hint.visible, "%s出招完成及时收回盾形预警" % c.id)
		await _clear_targets()
		Projectile.clear_pool()

func _environment_contract() -> void:
	await _reset()
	var center := WorldConfig.farthest_terrain_center("lava")
	var found := Vector2.INF
	for i in 600:
		var angle := float(i) * 2.399963
		var candidate := center + Vector2(cos(angle), sin(angle)) * (300.0 + float(i % 40) * 250.0)
		if ObstacleField.liquid_kind_at(candidate) == "lava" and not ObstacleField.blocks(candidate, 10.0):
			found = candidate
			break
	_check(found != Vector2.INF, "确定性测试种子可以定位真实熔岩点")
	if found == Vector2.INF:
		return
	_player.teleport_to(found)
	await _frames(2)
	await _arm()
	_charge(1)
	var hp := _player.current_hp
	await _frames(35)
	_check(_player.current_hp < hp and _player.guard_charge == 0 and _player.guard_state == "idle",
		"真实熔岩物理计时不可挡并清空持盾蓄力")

func _skin_and_lifecycle() -> void:
	for skin: String in Player.HERO_SKINS:
		for charge in [1, 3]:
			await _reset()
			_player.visual.sprite_frames = Player.HERO_SKINS[skin]
			await _arm()
			_check(_player.visual.animation == &"hurt" and _player.visual.frame == 0
				and _player.visual.material == null, "%s持续盾姿使用完整原始Guard帧" % skin)
			_charge(charge)
			TouchInput.release_guard()
			var seen := {}
			var source_ok := true
			var expected := &"attack3" if charge == 3 else &"attack1"
			for _i in 22:
				await _frames()
				if _player._attack_anim_linger > 0.0:
					seen[_player.visual.frame] = true
					source_ok = source_ok and _player.visual.animation == expected and _player.visual.material == null
			_check(source_ok and seen.size() == 4,
				"%s%d层反击实际经过%s四张身体原画帧，无盾姿替身或裁切" % [skin, charge, expected])
			_check(_player.visual.global_position.distance_to(_player.to_global(_player._visual_anchor)) <= 0.71,
				"%s%d层持盾反击身体锚点不漂移" % [skin, charge])
	await _reset()
	await _arm()
	_charge(1)
	var target := _monster(Vector2(62, 0))
	TouchInput.release_guard()
	await _frames(3)
	_player.teleport_to(_origin + Vector2(200, 0))
	await _frames(25)
	_check(target.current_hp == 10000.0 and _player.guard_state == "idle" and not _player._weapon_visual.active,
		"反击前摇期间传送清理旧地与落点攻击")
	await _clear_targets()
	await _reset()
	await _arm()
	_charge(2)
	_player._die()
	_check(_player.guard_state == "idle" and _player.guard_charge == 0 and not _player._weapon_visual.active,
		"死亡同步清除盾姿/蓄力/反击")
	_player._respawn()
	TouchInput.release_guard()
	await _frames(25)
	_check(_player.guard_state == "idle" and _player.guard_charge == 0 and not _player._weapon_visual.active,
		"复活后旧松手不会兑现反击")
	var states := {}
	for event in _guard_events:
		states[event.state] = true
	_check(states.has_all(["idle", "raising", "guarding", "counter", "broken"]), "HUD事件覆盖完整盾牌状态机")
