## Boss 年龄平衡：真实三种 AI 出招/玩家承伤/碰撞命中/技能耗蓝与击杀时间。
## 输出试验冻结 Boss AI 以隔离输出带，承伤与规避另走活体状态机；不把木桩时间当通关承诺。
extends Node2D

const PLAYER := preload("res://scenes/player/player.tscn")
const BOSSES := [
	{"id": "treant", "scene": preload("res://scenes/monsters/boar.tscn"), "terrain": "forest"},
	{"id": "stag_beetle_king", "scene": preload("res://scenes/monsters/ant.tscn"), "terrain": "hill"},
	{"id": "turtle_king", "scene": preload("res://scenes/monsters/guardian.tscn"), "terrain": "lava"},
]
const BUILDS := ["strength", "agility", "intellect"]
const AGES := [200, 800, 1400, 2999]
const STEP := 1.0 / 60.0
var _checks := 0
var _fails := 0
var _next_id := 0
var _player: Player
var _boss: MonsterBase
var _young_ttk := {}

func _ready() -> void:
	GameState.save_enabled = false
	WorldSim.stop()
	BiomeMap.configure(BiomeMap.DEFAULT_SEED)
	ObstacleField.restore_destroyed([])
	# 加速墙钟但维持 1/60 游戏秒物理步长，仍走正常状态机和碰撞派发。
	Engine.time_scale = 8.0
	Engine.physics_ticks_per_second = 480
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])

func _run() -> void:
	seed(20261002)
	await _vfx_parent_lifecycle()
	_curve_and_ecology()
	for entry: Dictionary in BOSSES:
		await _growth_sync(entry)
		for age: int in AGES:
			for build: String in BUILDS:
				await _incoming_attack(entry, age, build)
			await _avoid_attack(entry, age)
	for age: int in AGES:
		await _incoming_attack(BOSSES[1], age, "strength", true)
		await _incoming_attack(BOSSES[0], age, "intellect", false, true)
	for entry: Dictionary in BOSSES:
		for age: int in AGES:
			for build: String in BUILDS:
				await _output_trial(entry, age, build)
	await _cleanup()
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	print("=== BOSS AGE BALANCE %s (%d checks) ===" % ["PASS" if _fails == 0 else "FAIL", _checks])
	get_tree().quit(0 if _fails == 0 else 1)

func _vfx_parent_lifecycle() -> void:
	var holder := Node2D.new()
	add_child(holder)
	var old_fx := Sprite2D.new()
	holder.add_child(old_fx)
	VfxPool.release(old_fx, "boss_lifecycle")
	holder.queue_free()
	await get_tree().process_frame
	_check(VfxPool.take("boss_lifecycle") == null, "已释放父场景的特效引用安全丢弃")
	var fresh_fx := Sprite2D.new()
	add_child(fresh_fx)
	VfxPool.release(fresh_fx, "boss_lifecycle")
	_check(VfxPool.take("boss_lifecycle") == fresh_fx and fresh_fx.visible, "失效引用之后仍可正常回收/复用")
	fresh_fx.queue_free()
	await get_tree().process_frame

func _instance(sp: SpeciesData, age: int, threat: float) -> MonsterInstance:
	var inst := MonsterInstance.new()
	inst.species = sp
	inst.age = age
	inst.lifespan = sp.lifespan_max
	inst.size_scale = sp.boss_size_scale if sp.is_boss else 1.0
	inst.threat_scale = threat
	return inst

func _curve_and_ecology() -> void:
	for sp: SpeciesData in SpeciesCatalog.build_all():
		var inst := _instance(sp, 0, 1.0)
		if not sp.is_boss:
			for age: int in [0, 200, 800, 1400, sp.lifespan_max]:
				inst.age = age
				_check(is_equal_approx(inst.strength(), sp.base_strength + sp.strength_growth * age)
					and is_equal_approx(inst.agility(), sp.base_agility + sp.agility_growth * age)
					and is_equal_approx(inst.intellect(), sp.base_intellect + sp.intellect_growth * age),
					"普通怪线性成长原样保留 %s age%d" % [sp.species_name, age])
			continue
		var last := -1.0
		for age in 4001:
			inst.age = age
			var effective := inst.combat_age()
			if effective < last or effective > 300.0 or (age <= 200 and effective != age):
				_check(false, "Boss 曲线连续单调且独立封顶 %s age%d" % [sp.species_name, age])
				break
			last = effective
		_check(is_equal_approx(last, 300.0), "Boss 成长上限 300 %s" % sp.species_name)
		inst.age = sp.lifespan_max
		var hp := inst.max_hp()
		var atk := inst.attack_power()
		var speed := inst.move_speed()
		inst.age = 100000
		_check(is_equal_approx(inst.max_hp(), hp) and is_equal_approx(inst.attack_power(), atk)
			and is_equal_approx(inst.move_speed(), speed), "超长寿命不穿透战斗上限 %s" % sp.species_name)
		_check(inst.is_adult() and inst.age == 100000 and inst.lifespan == sp.lifespan_max
			and inst.xp_reward() == int((sp.xp_base + sp.xp_per_age * inst.age) * inst.size_scale),
			"成长查询不改生态年龄/寿命/成年/奖励 %s" % sp.species_name)
		_check(inst.move_speed() <= 150.0, "Boss 常态移速 ≤150，基础玩家 175 仍可撤离 %s" % sp.species_name)
		# 生命周期走真实 tick + 序列化，不修改 Boss 的自然寿命或生态龄。
		var region := SimRegion.new()
		region.id = "arena"
		region.terrain = sp.habitats[0]
		region.center = WorldConfig.spawn_pos()
		var sim := EcologySim.new()
		sim.setup([region], [sp], {"arena": {sp.species_name: 1}})
		var live: MonsterInstance = sim.instances.values()[0]
		live.age = live.lifespan - 2
		var remaining_age := live.age
		sim.tick()
		_check(live.is_alive and live.age == remaining_age + 1, "封顶后生态年龄照常前进 %s" % sp.species_name)
		var saved := sim.to_dict()
		var restored := EcologySim.new()
		_check(restored.restore_from_dict([region], [sp], saved), "Boss 老龄快照可恢复 %s" % sp.species_name)
		var loaded: MonsterInstance = restored.instances[live.id]
		_check(loaded.age == live.age and loaded.lifespan == live.lifespan
			and is_equal_approx(loaded.attack_power(), live.attack_power()), "往返保留实际年龄/寿命/封顶强度 %s" % sp.species_name)
		restored.tick()
		_check(not loaded.is_alive, "战斗封顶不延长自然寿命 %s" % sp.species_name)
	for entry: Dictionary in BOSSES:
		var sp: SpeciesData = load("res://data/species/%s.tres" % entry.id)
		var threat: float = CombatBandMath.TERRAIN_BANDS[entry.terrain].threat
		for age: int in AGES:
			var inst := _instance(sp, age, threat)
			var old_strength := sp.base_strength + sp.strength_growth * age
			var old_attack := (3.0 + old_strength * 0.8) * inst.size_scale * threat * sp.offense_scale
			var mult := sp.charge_damage_mult if sp.ai_archetype == "charger" else 1.0
			print("AUDIT %s age%d HP %.2f->%.2f attack %.2f->%.2f real_hit_base %.2f->%.2f speed %.2f->%.2f" % [
				sp.species_name, age, (20.0 + old_strength * 5.0) * inst.size_scale * threat, inst.max_hp(),
				old_attack, inst.attack_power(), old_attack * mult, inst.attack_power() * mult,
				40.0 + (sp.base_agility + sp.agility_growth * age) * 12.0, inst.move_speed()])

## 每个构筑只用本地预期等级的点数，50 金体质强化 +50 金对应输出强化；
## 1 坚韧 +1 对应输出被动，余下升级选经济卡，无装备/元素克制/罕见叠层依赖。
func _reference_stats(entry: Dictionary, build: String) -> CharacterStats:
	var stats := CharacterStats.new()
	stats.level = int(CombatBandMath.TERRAIN_BANDS[entry.terrain].expected)
	stats.set(build, 5 + stats.level - 1)
	stats.upgrade_vigor = 1
	stats.passives = {"hp": 1, "gold": maxi(0, stats.level - 3)}
	if build == "intellect":
		stats.upgrade_staff = 1
		stats.passives["magic"] = 1
	else:
		stats.upgrade_weapon = 1
		stats.passives["atk_speed" if build == "agility" else "phys"] = 1
	return stats

func _setup(entry: Dictionary, age: int, build: String, hp_mirror := -1.0) -> void:
	GameState.save_enabled = false
	GameState.stats = _reference_stats(entry, build)
	GameState.player_snapshot = {}
	GameState.gold = 0
	GameState.settings["auto_aim"] = true
	WorldSim.sim = EcologySim.new()
	_player = PLAYER.instantiate()
	add_child(_player)
	_player.set_physics_process(false)
	_player.set_process(false)
	_player.get_node("Camera2D").enabled = false
	_player.position = WorldConfig.spawn_pos()
	_player._protect_timer = 0.0
	_player._hurt_iframes = 0.0
	var sp: SpeciesData = load("res://data/species/%s.tres" % entry.id)
	var inst := _instance(sp, age, float(CombatBandMath.TERRAIN_BANDS[entry.terrain].threat))
	_next_id += 1
	inst.id = _next_id
	inst.hp_mirror = hp_mirror
	inst.spawn_pos = _player.position - Vector2(220, 0)
	WorldSim.sim.instances[inst.id] = inst
	_boss = entry.scene.instantiate()
	add_child(_boss)
	_boss.set_physics_process(false)
	_boss.setup(inst)
	_boss.position = inst.spawn_pos
	_boss._nav.avoidance_enabled = false
	_boss._player_ref = _player
	_boss.state = MonsterBase.S_CHASE
	TouchInput.reset()

func _cleanup() -> void:
	TouchInput.reset()
	if is_instance_valid(_player):
		_player.queue_free()
	if is_instance_valid(_boss):
		_boss.queue_free()
	for bolt in get_tree().get_nodes_in_group("player_bolts"):
		bolt.queue_free()
	await get_tree().process_frame
	WorldSim.stop()

func _growth_sync(entry: Dictionary) -> void:
	_setup(entry, 2999, "strength", 100000.0)
	_check(is_equal_approx(_boss.current_hp, _boss.inst.max_hp()), "旧档超上限生命按新上限钳制 " + entry.id)
	await _cleanup()
	_setup(entry, 2999, "strength", 42.0)
	_check(is_equal_approx(_boss.current_hp, 42.0), "旧档低血量原样保留 " + entry.id)
	await _cleanup()
	_setup(entry, 200, "strength")
	# 正常受伤后的成长只补上限差，不额外抹掉伤口。
	_boss.take_damage(30.0)
	var wound := _boss.inst.max_hp() - _boss.current_hp
	_boss.inst.age = 800
	_boss._player_ref = null
	_player.visible = false
	_boss.set_physics_process(true)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_boss.set_physics_process(false)
	_check(is_equal_approx(_boss.inst.max_hp() - _boss.current_hp, wound)
		and is_equal_approx(_boss.inst.hp_mirror, _boss.current_hp), "实际成长只补上限差并同步伤口 " + entry.id)
	_boss.inst.age = 1400
	_boss.set_physics_process(true)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_boss.set_physics_process(false)
	var capped_hp := _boss.current_hp
	_boss.inst.age = 2999
	_boss.set_physics_process(true)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_boss.set_physics_process(false)
	_check(is_equal_approx(_boss.current_hp, capped_hp), "封顶后不额外回血 " + entry.id)
	await _cleanup()

func _incoming_attack(entry: Dictionary, age: int, build: String, naked := false, enraged := false) -> void:
	_setup(entry, age, build)
	if naked:
		_player.stats.upgrade_vigor = 0
		_player.stats.upgrade_weapon = 0
		_player.stats.passives.clear()
		_player.current_hp = _player.stats.max_hp()
	if enraged:
		_boss.take_damage(_boss.current_hp * 0.8 / (1.0 - _boss.inst.species.defense_reduction))
	var start_hp := _player.current_hp
	if naked and age == 1400:
		var sp := _boss.inst.species
		var legacy := (3.0 + (sp.base_strength + sp.strength_growth * age) * 0.8) * _boss.inst.size_scale * _boss.inst.threat_scale * sp.offense_scale
		_check(legacy * 0.9 > start_hp and _boss.inst.attack_power() * 1.1 < start_hp, "旧 20 分钟最低伤害仍秒杀 232 血；新最高伤害可承受")
	var multiplier := _boss.inst.species.charge_damage_mult if _boss is Boar else 1.0
	var expected := _boss.inst.attack_power() * multiplier
	await get_tree().physics_frame
	_boss.set_physics_process(true)
	var telegraph := false
	var max_speed := 0.0
	for frame in 360:
		await get_tree().physics_frame
		telegraph = telegraph or _boss._melee_windup > 0.0 or _boss.state == 10
		max_speed = maxf(max_speed, _boss.velocity.length())
		if _player.current_hp < start_hp:
			break
	_boss.set_physics_process(false)
	var damage := start_hp - _player.current_hp
	var tag := "%s age%d %s Lv%d%s" % [entry.id, age, build, _player.stats.level, " naked" if naked else (" enraged" if enraged else "")]
	_check(telegraph and damage >= expected * 0.9 - 0.01 and damage <= expected * 1.1 + 0.01,
		"真实前摇→可达攻击→玩家承伤倍率 " + tag)
	_check(_player.current_hp > 0.0 and expected * 1.1 < start_hp,
		"参考构筑能承受最高随机单击 " + tag)
	_check(_player.last_killed_by == _boss.inst.display_name() and _player._knockback.length() > 0.0,
		"真实受伤来源和击退 " + tag)
	_check(max_speed > 0.0 and max_speed <= (496.0 if enraged else 355.0), "真实常态/冲锋/狂暴速度上限 " + tag)
	print("HIT %s HP %.2f damage %.2f max_roll %.2f speed %.2f" % [tag, start_hp, damage, expected * 1.1, max_speed])
	await _cleanup()

func _avoid_attack(entry: Dictionary, age: int) -> void:
	_setup(entry, age, "agility")
	# 真实输入侧向冲刺，分别在冲锋前摇、近战前摇、守卫蓄力中使用。
	_boss.position = _player.position - Vector2(160 if _boss is Boar else 60, 0)
	var start_hp := _player.current_hp
	var start_mp := _player.current_mp
	await get_tree().physics_frame
	_boss.set_physics_process(true)
	var issued := false
	var spent := 0.0
	for frame in 150:
		if not issued and (_boss._melee_windup > 0.0 or _boss.state == 10):
			TouchInput.joystick_active = true
			TouchInput.move_vector = Vector2.UP if _boss is Boar else Vector2.RIGHT
			TouchInput.queue_dash()
			_player.set_physics_process(true)
			issued = true
		await get_tree().physics_frame
		if issued:
			spent += STEP
			if spent > 1.2:
				break
	_check(issued and is_equal_approx(_player.current_hp, start_hp)
		and is_equal_approx(start_mp - _player.current_mp, CharacterStats.DASH_COST),
		"真实冲刺输入可避开出招 %s age%d" % [entry.id, age])
	if _boss is Boar:
		# 狂暴是实际受伤触发，保留其风险同时限制晚龄冲锋。
		_boss.take_damage(_boss.current_hp * 0.8 / (1.0 - _boss.inst.species.defense_reduction))
		var charged_speed := _boss.inst.move_speed() * _boss._speed_mult() * _boss.inst.species.charge_speed_mult
		_check(_boss._enraged and charged_speed <= 496.0, "残血狂暴仍有界 %s age%d" % [entry.id, age])
	await _cleanup()

func _output_trial(entry: Dictionary, age: int, build: String) -> void:
	_setup(entry, age, build)
	# 真实碰撞体 + 玩家正常物理帧；只冻结 AI，不重写怪物生命/护甲/伤害。
	# 近战从真实碰撞体边缘外 6px 攻击，避免 64px 对小碰撞体恰好落空；法弹 220px。
	var shape := (_boss.get_node("CollisionShape2D") as CollisionShape2D).shape as RectangleShape2D
	var contact_distance := shape.size.x * 0.5 + 10.0 + 6.0
	_boss.position = _player.position + Vector2(220 if build == "intellect" else contact_distance, 0)
	_boss.anchor = _boss.position
	_player.facing = Vector2.RIGHT
	_player.set_physics_process(true)
	_player.set_process(true)
	var reference_level := _player.stats.level
	var initial_hp := _boss.current_hp
	var initial_mp := _player.current_mp
	var elapsed := 0.0
	var first_hit := -1.0
	var min_mp := initial_mp
	while elapsed < 90.0 and _boss.inst.is_alive:
		if build == "intellect":
			TouchInput.queue_bolt()
		else:
			TouchInput.queue_attack()
			# 只使用初始蓝量和自然回复；保留耗蓝/冷却，不注入无限资源。
			TouchInput.queue_empower()
			TouchInput.queue_heavy()
		await get_tree().physics_frame
		elapsed += STEP
		min_mp = minf(min_mp, _player.current_mp)
		if first_hit < 0.0 and _boss.current_hp < initial_hp:
			first_hit = elapsed
	var tag := "%s age%d %s Lv%d" % [entry.id, age, build, reference_level]
	_check(first_hit >= 0.0 and first_hit <= 1.0, "真实攻击距离内碰撞命中 " + tag)
	_check(not _boss.inst.is_alive and elapsed >= 4.0 and elapsed <= 65.0,
		"护甲/技能/耗蓝全链击杀时间 4–65 秒 " + tag)
	var key := "%s:%s" % [entry.id, build]
	if age == AGES[0]:
		_young_ttk[key] = elapsed
	else:
		_check(elapsed <= float(_young_ttk[key]) * 1.65, "老龄击杀时间仍在初生的 1.65 倍内 " + tag)
	_check(min_mp >= 0.0 and min_mp < initial_mp, "技能消耗真实且无负魔法 " + tag)
	print("TTK %s HP %.2f time %.2f first_hit %.2f min_MP %.2f" % [tag, initial_hp, elapsed, first_hit, min_mp])
	await _cleanup()
