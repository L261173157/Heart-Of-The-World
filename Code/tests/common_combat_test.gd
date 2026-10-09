## 普通怪战斗闭环：生产状态机、真实物理帧、身体、弹幕与碰撞。
## 锁向/时相、硬直上限、围攻节奏与生命周期必须同时成立，不靠输入窥探。
extends Node2D

const Slots := preload("res://scripts/combat/enemy_attack_slots.gd")
const ORIGIN := Vector2(90000, 90000)
var _checks := 0
var _fails := 0
var _next_id := 0

class Target extends CharacterBody2D:
	var hits := 0
	var damage := 0.0
	var last_context: Dictionary = {}
	func take_damage(amount: float, _from := Vector2.INF, _source := "",
			context: Dictionary = {}) -> bool:
		hits += 1
		damage += amount
		last_context = context.duplicate()
		return true


func _ready() -> void:
	GameState.save_enabled = false
	WorldSim.stop()
	WorldSim.sim = EcologySim.new()
	BiomeMap.configure(BiomeMap.DEFAULT_SEED)
	ObstacleField.restore_destroyed([])
	var region := SimRegion.new()
	region.id = "common_combat"
	region.center = ORIGIN
	region.size = Vector2(100000, 100000)
	region.capacity = 1000
	WorldSim.sim.regions[region.id] = region
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


func _target(pos := ORIGIN) -> Target:
	var target := Target.new()
	target.collision_layer = 1
	target.collision_mask = 0
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 5.0
	shape.shape = circle
	target.add_child(shape)
	add_child(target)
	target.add_to_group("player")
	target.position = pos
	return target


func _monster(id: String, scene: String, pos: Vector2, target: Node2D) -> MonsterBase:
	var monster: MonsterBase = load("res://scenes/monsters/%s.tscn" % scene).instantiate()
	add_child(monster)
	monster.set_physics_process(false)
	_next_id += 1
	var inst := MonsterInstance.new()
	inst.id = _next_id
	inst.region_id = "common_combat"
	inst.species = load("res://data/species/%s.tres" % id).duplicate()
	inst.age = 200
	inst.lifespan = 100000
	inst.spawn_pos = pos
	WorldSim.sim.instances[inst.id] = inst
	monster.setup(inst)
	monster.position = pos
	monster._player_ref = target
	monster._aggro_lock = 100.0
	monster.state = MonsterBase.S_CHASE
	return monster


func _clear(actors: Array) -> void:
	for actor: Node in actors:
		if is_instance_valid(actor):
			actor.queue_free()
	for child in get_children():
		if child is Projectile:
			child.queue_free()
	await _frames(2)
	Projectile.clear_pool()


func _await_warning(monster: MonsterBase, frames := 100) -> bool:
	for i in frames:
		await _frames()
		if not monster._attack_context.is_empty():
			return true
	return false


func _run() -> void:
	seed(20261009)
	await _melee_phases()
	await _locked_melee()
	await _stagger_limits()
	await _crowd_pressure()
	await _ranged_commitment()
	await _charge_commitment()
	await _lifecycle()
	WorldSim.stop()
	print("=== COMMON COMBAT %s (%d checks) ===" % ["PASS" if _fails == 0 else "FAIL", _checks])
	get_tree().quit(0 if _fails == 0 else 1)


func _melee_phases() -> void:
	for entry: Array in [["goblin", "goblin"], ["beetle", "ant"], ["slime", "slime"]]:
		for direction: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
			var target := _target()
			var monster := _monster(entry[0], entry[1], ORIGIN - direction * 24.0, target)
			monster.set_physics_process(true)
			_check(await _await_warning(monster), "%s %s 真实进入前摇" % [entry[0], direction])
			var strength := float(monster._attack_context.get("strength", 0.0))
			var facing := monster.visual.flip_h
			_check(target.hits == 0 and monster.visual.animation == &"attack"
				and monster._attack_cue.visible, "伤害之前动作和方向预警已经开始")
			_check(monster._attack_aim_dir.dot(direction) > 0.99, "四方向锁向消费真实目标位置")
			monster.inst.species.offense_scale *= 2.0
			for frame in 25:
				await _frames()
				if target.hits > 0:
					break
			_check(target.hits == 1 and monster._attack_recovery > 0.0
				and monster._attack_context.is_empty() and not monster._attack_cue.visible,
				"同一招仅在命中相结算一次并进入明确收招")
			_check(is_equal_approx(float(target.last_context.get("strength", -1)), strength)
				and target.damage >= strength * 0.9 and target.damage <= strength * 1.1,
				"护盾强度和实际伤害保持前摇快照，不被中途成长改写")
			var position_at_hit := monster.position
			await _frames(5)
			_check(monster.position.distance_to(position_at_hit) < 0.1
				and monster.visual.flip_h == facing and target.hits == 1,
				"真实RVO收招保持脚点/朝向且不重复伤害")
			await _frames(17)
			_check(monster._attack_recovery <= 0.0 and monster._attack_cd > 0.0
				and monster.position.distance_to(position_at_hit) > 0.5,
				"短收招后恢复侧移施压，不站桩等完整冷却")
			await _clear([monster, target])


func _locked_melee() -> void:
	var target := _target()
	var monster := _monster("goblin", "goblin", ORIGIN - Vector2(27, 0), target)
	monster.set_physics_process(true)
	await _await_warning(monster)
	var original_dir := monster._attack_aim_dir
	var original_flip := monster.visual.flip_h
	# 场景中目标在前摇内绕到背面，仍在原攻击半径内。
	target.position = monster.position - Vector2(27, 0)
	await _frames(14)
	_check(target.hits == 0 and monster._attack_recovery > 0.0,
		"范围内绕背真实躲过已锁定扇区，空挥仍付收招")
	_check(monster.visual.flip_h == original_flip and original_dir == Vector2.RIGHT,
		"空挥不瞬间翻面追踪新位置")
	await _clear([monster, target])


func _stagger_limits() -> void:
	var target := _target()
	var monster := _monster("goblin", "goblin", ORIGIN - Vector2(27, 0), target)
	monster.set_physics_process(true)
	await _await_warning(monster)
	monster.take_damage(1.0, target.position)
	var stagger := monster._stagger_timer
	var rearm := monster._stagger_rearm
	_check(stagger > 0.0 and monster._melee_windup == 0.0
		and monster._attack_context.is_empty() and monster._attack_slot_target_id == 0,
		"轻型怪真实受击取消前摇、预警和攻击占位")
	for hit in 30:
		monster.take_damage(0.01, target.position, true)
	_check(monster._stagger_timer == stagger and monster._stagger_rearm == rearm,
		"同窗高频多段/重击不刷新或叠加硬直")
	await _frames(10)
	_check(monster._stagger_timer <= 0.0 and monster._stagger_rearm > 0.0,
		"硬直按时结束，免重复窗继续存在")
	var moved := monster.position
	await _frames(15)
	_check(monster._melee_windup > 0.0 or target.hits > 0 or monster.position.distance_to(moved) > 1.0,
		"怪物恢复真实行动，不被连续轻伤锁死")
	await _clear([monster, target])
	for entry: Array in [["boar", "boar", false], ["guardian", "guardian", true], ["stag_beetle_king", "ant", true]]:
		target = _target()
		monster = _monster(entry[0], entry[1], ORIGIN - Vector2(100, 0), target)
		monster.take_damage(1.0, target.position)
		_check(monster._stagger_timer == 0.0, "%s 中/重型抵抗普通攻击硬直" % entry[0])
		monster.take_damage(1.0, target.position, true)
		_check((monster._stagger_timer == 0.0) == bool(entry[2]), "%s 重击受韧性/Boss约束" % entry[0])
		await _clear([monster, target])


func _crowd_pressure() -> void:
	var target := _target()
	var monsters: Array[MonsterBase] = []
	for i in 8:
		var monster := _monster("goblin", "goblin", ORIGIN + Vector2.RIGHT.rotated(i * TAU / 8.0) * 34.0, target)
		monster.set_physics_process(true)
		monsters.append(monster)
	var started := {}
	var ids := {}
	var last_start := -100
	var max_slots := 0
	var separated := true
	var moved := false
	var first_pos := monsters[6].position
	for frame in 240:
		await _frames()
		var active := 0
		var new_starts: Array[int] = []
		for monster in monsters:
			if monster._attack_slot_target_id != 0:
				active += 1
			if not monster._attack_context.is_empty():
				var attack_id: String = monster._attack_context["attack_id"]
				if not ids.has(attack_id):
					ids[attack_id] = true
					started[monster.inst.id] = true
					new_starts.append(monster._attack_started_frame)
		new_starts.sort()
		for started_frame in new_starts:
			separated = separated and started_frame - last_start >= 6
			last_start = started_frame
		max_slots = maxi(max_slots, active)
		moved = moved or first_pos.distance_to(monsters[6].position) > 5.0
	_check(max_slots == 2 and separated, "八怪同屏真实起手最多两只、起手相隔至少0.1秒")
	_check(started.size() >= 6 and moved and target.hits > 0,
		"等待者仍绕侧施压，多数怪轮到攻击且实际命中")
	_check(monsters.size() == 8 and monsters.all(func(m: MonsterBase) -> bool: return m.inst.is_alive),
		"围攻限制只调出手节奏，不删怪/改变生态存活")
	var actors: Array = []
	actors.append_array(monsters)
	actors.append(target)
	await _clear(actors)


func _ranged_commitment() -> void:
	# 静止目标也必须能被真实弹幕击中；释放射线不能把目标自己的身体当掩体。
	var target := _target()
	var monster := _monster("spider", "spider", ORIGIN - Vector2(180, 0), target) as Spider
	monster.set_physics_process(true)
	await _frames(70)
	_check(target.hits == 1 and target.last_context.get("incoming_direction", Vector2.ZERO) == Vector2.LEFT,
		"静止实体目标真实承受一次吐息，玩家身体不误作释放掩体")
	await _clear([monster, target])
	target = _target()
	monster = _monster("spider", "spider", ORIGIN - Vector2(180, 0), target) as Spider
	monster.set_physics_process(true)
	_check(await _await_warning(monster), "远程实际进入吐息前摇")
	var original := monster.position
	var strength: float = monster._attack_context.get("strength", 0.0)
	target.position.y += 100.0
	var bolt: Projectile
	for frame in 30:
		await _frames()
		for child in get_children():
			if child is Projectile:
				bolt = child
		if bolt != null:
			break
	_check(bolt != null and bolt.direction.dot(Vector2.RIGHT) > 0.99,
		"真实弹幕沿预警锁定线发射，不在释放帧重新瞄准")
	if bolt != null:
		_check(bolt.attack_context.incoming_direction == Vector2.LEFT
			and is_equal_approx(float(bolt.attack_context.strength), float(strength)),
			"锁定弹道保留护盾来向和稳定强度")
	_check(monster._attack_recovery > 0.0 and monster.position.distance_to(original) < 0.1,
		"吐息前摇/出手/收招原地完成，RVO不漂移")
	await _frames(30)
	_check(target.hits == 0 and monster.position.distance_to(original) > 1.0,
		"走位确实躲开弹幕，远程收招后恢复间距侧移")
	await _clear([monster, target])
	# 前摇中新建真实墙体，不能消费过期LOS缓存发射。
	target = _target()
	monster = _monster("spider", "spider", ORIGIN - Vector2(180, 0), target) as Spider
	monster.set_physics_process(true)
	await _await_warning(monster)
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(12, 200)
	shape.shape = rect
	wall.add_child(shape)
	add_child(wall)
	wall.position = ORIGIN - Vector2(90, 0)
	await _frames(23)
	var projectiles := 0
	for child in get_children():
		if child is Projectile:
			projectiles += 1
	_check(projectiles == 0 and target.hits == 0 and monster._attack_context.is_empty(),
		"前摇中的新掩体抑制真实弹幕并清理旧招式")
	await _clear([monster, target, wall])


func _charge_commitment() -> void:
	var target := _target()
	var monster := _monster("boar", "boar", ORIGIN - Vector2(180, 0), target) as Boar
	monster.set_physics_process(true)
	await _await_warning(monster)
	_check(monster.state == Boar.S_TELL and monster._attack_cue.visible,
		"冲锋锁定直线与实际蓄力状态同相")
	monster.take_damage(1.0, target.position, true)
	_check(monster._stagger_timer > 0.0 and monster.state == MonsterBase.S_CHASE
		and not monster._attack_cue.visible, "重击可打断中型冲锋前摇，撤掉旧射线")
	await _frames(70)
	for frame in 50:
		if monster.state == Boar.S_CHARGE:
			break
		await _frames()
	if monster.state == Boar.S_CHARGE:
		monster._stagger_rearm = 0.0
		monster.take_damage(1.0, target.position, true)
		_check(monster.state == Boar.S_CHARGE and monster._stagger_timer == 0.0,
			"已启动冲锋保持承诺，不被受击任意重置方向")
	else:
		_check(target.hits > 0, "中型怪从被打断前摇后恢复真实冲锋并命中")
	await _clear([monster, target])


func _lifecycle() -> void:
	for entry: Array in [["goblin", "goblin", 27.0], ["spider", "spider", 180.0], ["boar", "boar", 180.0]]:
		for action in ["death", "migration", "hidden", "despawn"]:
			var target := _target()
			var monster := _monster(entry[0], entry[1], ORIGIN - Vector2(float(entry[2]), 0), target)
			monster.set_physics_process(true)
			_check(await _await_warning(monster), "%s %s 生命周期用例确实开始攻击" % [entry[0], action])
			var target_id := target.get_instance_id()
			match action:
				"death": monster.on_sim_death()
				"migration": monster.on_migrate("common_combat", ORIGIN + Vector2(200, 0))
				"hidden": target.visible = false
				"despawn": monster.queue_free()
			await _frames(2)
			var slot: Dictionary = Slots._targets.get(target_id, {})
			_check(slot.is_empty() or slot.actors.is_empty(), "%s %s 及时归还攻击占位" % [entry[0], action])
			if is_instance_valid(monster):
				_check(monster._attack_context.is_empty() and not monster._attack_cue.visible,
					"%s %s 没有残留盾形/朝向/攻击ID" % [entry[0], action])
				if action in ["migration", "hidden"]:
					_check(monster.modulate == monster._base_modulate,
						"%s %s 中断后恢复常态颜色，不遗留前摇橙" % [entry[0], action])
				await _clear([monster, target])
			else:
				await _clear([target])
	# 早期取消不能让另一个怪物在同帧接替；真实出招入口调用同一协调器。
	var target := _target()
	var first := _monster("goblin", "goblin", ORIGIN - Vector2(27, 0), target)
	var second := _monster("goblin", "goblin", ORIGIN + Vector2(27, 0), target)
	_check(first._try_attack_slot(target), "第一只获得有限攻击占位")
	first.on_sim_death()
	_check(not second._try_attack_slot(target), "首只当帧死亡仍保留最短起手间隔")
	await _frames(7)
	_check(second._try_attack_slot(target), "起手间隔结束后立即允许后继者，不泄漏占位")
	await _clear([first, second, target])
