## 审计回归：真实成长/冷进程、生产装配、物理碰撞与导航服务器回调。
extends Node2D

const ORIGIN := Vector2(90000, 90000)
var _checks := 0
var _fails := 0
var _region: SimRegion
var _species: Array[SpeciesData] = []
var _player: Node2D
var _hints := 0

func _ready() -> void:
	GameState.save_enabled = false
	GameState.reset_all()
	WorldSim.stop()
	BiomeMap.configure(BiomeMap.DEFAULT_SEED)
	ObstacleField.restore_destroyed([])
	_region = SimRegion.new()
	_region.id = "actor_audit"
	_region.terrain = "plains"
	_region.center = ORIGIN
	_region.size = Vector2(100000, 100000)
	_region.capacity = 100
	for key: String in ["turtle_king", "boar", "goblin"]:
		var species: SpeciesData = load("res://data/species/%s.tres" % key).duplicate()
		species.habitats = ["plains"]
		species.breeding_rate = 0.0
		species.migrate_count = 0
		species.prey = []
		species.lifespan_min = 100000
		species.lifespan_max = 100000
		_species.append(species)
	WorldSim.sim = EcologySim.new()
	WorldSim.sim.setup([_region], _species, {})
	EventBus.hint_requested.connect(func(message: String) -> void:
		if message.contains("第二阶段"): _hints += 1)
	if "--actor-cold-reader" in OS.get_cmdline_user_args():
		_cold_reader.call_deferred()
	else:
		_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok: _fails += 1
	print("  %s %s" % ["PASS" if ok else "FAIL", label])

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
		await get_tree().process_frame

func _body(inst: MonsterInstance, scene: String) -> MonsterBase:
	var actor: MonsterBase = load("res://scenes/monsters/%s.tscn" % scene).instantiate()
	add_child(actor) # 生产顺序：ready 先于 setup。
	actor.set_physics_process(false)
	actor.setup(inst)
	actor.global_position = inst.spawn_pos
	return actor

func _spawn(index: int, scene: String, pos := ORIGIN) -> MonsterBase:
	var inst := WorldSim.sim.spawn_instance(_species[index], _region.id, 200, 0, 1.0, false, pos)
	return _body(inst, scene)

func _run() -> void:
	_player = Node2D.new()
	add_child(_player)
	_player.add_to_group("player")
	_player.position = ORIGIN
	await _phase_growth_reload()
	await _boar_reload()
	await _nests()
	await _far_slide()
	await _avoidance_lifecycle()
	await _charge_after_lod()
	_player.free()
	await _frames(2)
	WorldSim.stop()
	print("=== ACTOR LIFECYCLE AUDIT %s (%d checks) ===" % ["PASS" if _fails == 0 else "FAIL", _checks])
	get_tree().quit(0 if _fails == 0 else 1)

func _phase_growth_reload() -> void:
	var actor := _spawn(0, "guardian") as Guardian
	GameState.SAVE_PATH = "user://actor_phase_cache_%d.json" % OS.get_process_id()
	GameState.save_enabled = true
	_check(GameState.save_now(), "阶段变化前预热真实存档缓存")
	GameState.save_enabled = false
	actor.take_damage(actor.current_hp * 0.5 / (1.0 - actor.inst.species.defense_reduction))
	_check(actor._boss_phase == 2 and _hints == 1, "真实受击只触发一次第二阶段")
	GameState.save_enabled = true
	_check(GameState.save_now(false), "阶段变化后真实缓存存档成功")
	GameState.save_enabled = false
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GameState.SAVE_PATH))
	_check(int(saved.ecology.instances[0].get("guardian_phase", 1)) == 2,
		"同tick缓存存档不会遗失刚触发的阶段")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.SAVE_PATH))
	var inst := actor.inst
	var wound := inst.max_hp() - actor.current_hp
	WorldSim.sim._process_aging_and_corpses()
	actor._sync_growth_hp()
	_check(actor.current_hp > inst.max_hp() * 0.5 and is_equal_approx(inst.max_hp() - actor.current_hp, wound),
		"真实成长跨回半血以上且保持绝对伤口")
	actor.free()
	actor = _body(inst, "guardian") as Guardian
	_check(actor._boss_phase == 2 and actor.state != Guardian.S_PHASE_CHANGE, "同实例重建保持阶段2且不补发转换空窗")
	actor.take_damage(2.0)
	_check(_hints == 1 and actor.state != Guardian.S_PHASE_CHANGE, "重建再受击不重复提示或转换")
	actor.free()
	# 再长一段，保证存档比例严格大于50%，不能靠当前HP推导蒙混通过。
	for i in 100: WorldSim.sim._process_aging_and_corpses()
	var snapshot := WorldSim.sim.to_dict()
	var low_boar := _spawn(1, "boar") as Boar
	low_boar.take_damage(low_boar.current_hp * 0.8 / (1.0 - low_boar.inst.species.defense_reduction))
	var boar_id := low_boar.inst.id
	low_boar.free()
	snapshot = WorldSim.sim.to_dict()
	var packet := {"world": snapshot, "id": inst.id, "hp": inst.hp_mirror, "boar_id": boar_id}
	_check(inst.hp_mirror > inst.max_hp() * 0.5, "冷读夹具仍在半血以上")
	var path := "user://actor_lifecycle_roundtrip_%d.json" % OS.get_process_id()
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(packet))
	file.close()
	var output: Array = []
	var code := OS.execute(OS.get_executable_path(), PackedStringArray([
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"res://tests/actor_lifecycle_audit_test.tscn", "--quit-after", "500", "--",
		"--actor-cold-reader", ProjectSettings.globalize_path(path)]), output, true)
	var text := "".join(output)
	print(text)
	_check(code == 0 and "=== ACTOR COLD READER PASS ===" in text and not "SCRIPT ERROR" in text,
		"独立进程持久化阶段2与成长后HP")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	# 旧档没有阶段键，低血和满血保持兼容；坏字段不崩溃/注入其它物种。
	for phase: Variant in [null, "2", [], {}, -10, 99, 1, 2, 1.9, 2.9, NAN, INF]:
		var old: Dictionary = snapshot.duplicate(true)
		var entry: Dictionary = old.instances[0]
		entry.hp = inst.max_hp() * 0.8
		if phase == null: entry.erase("guardian_phase")
		else: entry.guardian_phase = phase
		var restored := EcologySim.new()
		_check(restored.restore_from_dict([_region], _species, old), "阶段坏字段不破坏世界恢复 %s" % str(phase))
		WorldSim.sim = restored
		var body := _body(restored.instances[inst.id], "guardian") as Guardian
		var expected := 2 if typeof(phase) in [TYPE_FLOAT, TYPE_INT] and is_finite(float(phase)) and int(phase) >= 2 else 1
		_check(body._boss_phase == expected, "阶段字段严格类型/边界恢复 %s" % str(phase))
		body.free()
	var legacy: Dictionary = snapshot.duplicate(true)
	legacy.instances[0].erase("guardian_phase")
	legacy.instances[0].hp = inst.max_hp() * 0.2
	var restored := EcologySim.new()
	restored.restore_from_dict([_region], _species, legacy)
	WorldSim.sim = restored
	var body := _body(restored.instances[inst.id], "guardian") as Guardian
	_check(body._boss_phase == 2 and body.state != Guardian.S_PHASE_CHANGE, "旧低血档迁移阶段2但不补发动画")
	if restored.has_method("report_guardian_phase"):
		restored.call("report_guardian_phase", inst.id, 1)
		_check(int(body.inst.get("guardian_phase")) == 2, "权威入口拒绝阶段倒退")
		var other: MonsterInstance = restored.instances[boar_id]
		restored.call("report_guardian_phase", other.id, 2)
		_check(int(other.get("guardian_phase")) == 1, "非守卫物种不接受阶段报告")
		var new_boss := restored.spawn_instance(_species[0], _region.id, 200, 0, 1.0, false, ORIGIN)
		restored.report_killed(new_boss.id)
		restored.call("report_guardian_phase", new_boss.id, 2)
		_check(int(new_boss.get("guardian_phase")) == 1, "死亡Boss不接受迟到阶段报告")
	body.free()

func _cold_reader() -> void:
	var args := OS.get_cmdline_user_args()
	var packet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[args.find("--actor-cold-reader") + 1]))
	_check(WorldSim.sim.restore_from_dict([_region], _species, packet.world), "冷进程恢复真实序列化")
	var actor := _body(WorldSim.sim.instances[int(packet.id)], "guardian") as Guardian
	_check(actor._boss_phase == 2 and actor.current_hp > actor.inst.max_hp() * 0.5,
		"冷进程高于半血仍恢复第二阶段")
	_check(is_equal_approx(actor.current_hp, float(packet.hp)) and _hints == 0
		and actor.state != Guardian.S_PHASE_CHANGE, "冷进程不回血/重复提示/补发转换窗")
	actor.free()
	var boar := _body(WorldSim.sim.instances[int(packet.boar_id)], "boar") as Boar
	_check(boar._enraged and boar.current_hp < boar.inst.max_hp() * 0.3
		and boar._speed_mult() == 1.4, "冷进程低血冲锋怪立即恢复狂暴")
	boar.free()
	WorldSim.stop()
	print("=== ACTOR COLD READER %s ===" % ("PASS" if _fails == 0 else "FAIL"))
	get_tree().quit(0 if _fails == 0 else 1)

func _boar_reload() -> void:
	var actor := _spawn(1, "boar") as Boar
	actor.take_damage(actor.current_hp * 0.8 / (1.0 - actor.inst.species.defense_reduction))
	_check(actor._enraged, "真实受击进入冲锋狂暴")
	var inst := actor.inst
	actor.free()
	actor = _body(inst, "boar") as Boar
	_check(actor._enraged and is_equal_approx(actor._speed_mult(), 1.4), "低血重建直接恢复狂暴倍率")
	_check(actor.modulate.is_equal_approx(Color(1.0, 0.55, 0.45)), "低血重建直接恢复狂暴色")
	actor.free()
	actor = _spawn(1, "boar") as Boar
	_check(not actor._enraged and actor._speed_mult() == 1.0, "满血冲锋怪不误入狂暴")
	actor.free()
	await _frames(2)

func _nests() -> void:
	for terrain: String in ["plains", "swamp", "snow"]:
		_region.terrain = terrain
		WorldSim.sim.regions[_region.id] = _region
		var nest := NestNode.new()
		add_child(nest)
		nest.setup(_region.id, _species[2].species_name, Color.WHITE, ORIGIN)
		_check(nest._visual.is_playing(), "生产装配立即开始巢穴动画 %s" % terrain)
		var changed := false
		var frame := nest._visual.frame
		for i in 25:
			await _frames(1)
			changed = changed or nest._visual.frame != frame
		_check(changed, "巢穴真实时间推进动画帧 %s" % terrain)
		nest.free()
	_region.terrain = "plains"

func _wall(pos: Vector2, size: Vector2) -> StaticBody2D:
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	wall.add_child(shape)
	add_child(wall)
	wall.position = pos
	return wall

func _far_slide() -> void:
	for origin: Vector2 in [Vector2(3000, 3000), Vector2(750000, 750000)]:
		var actor := _spawn(2, "goblin", origin)
		actor._nav.avoidance_enabled = false
		actor.get_node("CollisionShape2D").shape = RectangleShape2D.new()
		(actor.get_node("CollisionShape2D").shape as RectangleShape2D).size = Vector2(8, 8)
		var wall := _wall(origin + Vector2(14, 0), Vector2(8, 200))
		await _frames(2)
		actor._far_move(Vector2(10, 10))
		var moved := actor.position - origin
		print("FAR_SLIDE origin=%s motion=(10,10) actual=%s" % [origin, moved])
		_check(moved.x > 0.0 and moved.x < 10.0 and absf(moved.y - 10.0) <= 0.1,
			"斜撞真实墙只滑剩余位移 %s" % origin)
		actor.position = origin
		var corner := _wall(origin + Vector2(0, 14), Vector2(200, 8))
		await _frames(2)
		actor._far_move(Vector2(10, 10))
		moved = actor.position - origin
		_check(moved.x <= 6.0 and moved.y <= 6.0 and moved.length() > 0.0,
			"真实双墙角不会重复滑动或穿角 %s" % origin)
		actor.free()
		wall.free()
		corner.free()

func _avoidance_lifecycle() -> void:
	for enabled: bool in [true, false]:
		await _avoidance_mode_lifecycle(enabled)

func _avoidance_mode_lifecycle(enabled: bool) -> void:
	_player.position = ORIGIN
	var actor := _spawn(2, "goblin", ORIGIN + Vector2(400, 0))
	_check(actor._nav.avoidance_enabled, "新装配近档默认启用避让")
	actor._nav.avoidance_enabled = enabled
	actor.on_migrate(_region.id, ORIGIN + Vector2(800, 0))
	var counts := {"callbacks": 0}
	actor._nav.velocity_computed.connect(func(_v: Vector2) -> void: counts.callbacks += 1)
	actor.set_physics_process(true)
	await _frames(5)
	counts.callbacks = 0
	var start := actor.position
	await _frames(60)
	print("RVO_NEAR selected=%s callbacks_60=%d displacement=%.3f" % [enabled, counts.callbacks, actor.position.distance_to(start)])
	_check(actor._nav.avoidance_enabled == enabled
		and (counts.callbacks >= 50 if enabled else counts.callbacks == 0),
		"近档真实帧保留所选避让模式 %s" % enabled)
	_check(actor.position.distance_to(start) > 5.0, "近档所选路径仍有真实迁徙位移 %s" % enabled)
	_player.position = ORIGIN - Vector2(2000, 0)
	await _frames(2)
	counts.callbacks = 0
	start = actor.position
	await _frames(60)
	print("RVO_FAR selected=%s callbacks_60=%d displacement=%.3f" % [enabled, counts.callbacks, actor.position.distance_to(start)])
	_check(counts.callbacks == 0 and not actor._nav.avoidance_enabled, "远档60帧退出RVO求解")
	_check(actor.position.distance_to(start) > 5.0, "远档迁徙仍有实际位移")
	start = actor.position
	actor._on_nav_velocity(Vector2(10000, 0))
	_check(actor.position.is_equal_approx(start) and not actor._awaiting_rvo, "远档迟到回调不补走旧位移")
	_player.position = actor.position + Vector2(500, 0)
	await _frames(3)
	counts.callbacks = 0
	await _frames(30)
	_check(actor._nav.avoidance_enabled == enabled
		and (counts.callbacks >= 25 if enabled else counts.callbacks == 0),
		"远转近恢复进入前的避让模式 %s" % enabled)
	# 真实受击外力仍走碰撞，旧RVO回调不产生第二段移动。
	actor.on_migrate(_region.id, actor.position + Vector2(1000, 0))
	start = actor.position
	actor.take_damage(1.0, actor.position + Vector2(100, 0), true)
	await _frames(1)
	_check(actor.position.x < start.x, "恢复近档后真实受击仍向来源反向击退")
	actor.on_sim_death()
	await _frames(2)
	counts.callbacks = 0
	start = actor.position
	await _frames(60)
	print("RVO_CORPSE selected=%s callbacks_60=%d displacement=%.3f" % [enabled, counts.callbacks, actor.position.distance_to(start)])
	_check(counts.callbacks == 0 and not actor._nav.avoidance_enabled, "尸体60帧退出RVO求解")
	actor._on_nav_velocity(Vector2(10000, 0))
	_check(actor.position.is_equal_approx(start) and not actor._awaiting_rvo, "死亡迟到回调不移动尸体")
	actor.free()


func _charge_after_lod() -> void:
	_player.position = ORIGIN
	var actor := _spawn(1, "boar", ORIGIN + Vector2(2000, 0)) as Boar
	actor.set_physics_process(true)
	await _frames(8)
	_check(not actor._nav.avoidance_enabled, "冲锋原型在远档同样退出避让")
	var start := actor.position
	_player.position = start + Vector2(180, 0)
	var wall := _wall(start + Vector2(90, 0), Vector2(8, 180))
	var saw_tell := false
	var saw_charge := false
	var saw_wall_stun := false
	var peak_speed := 0.0
	for i in 120:
		await _frames(1)
		saw_tell = saw_tell or actor.state == Boar.S_TELL
		saw_charge = saw_charge or actor.state == Boar.S_CHARGE
		peak_speed = maxf(peak_speed, actor.velocity.length())
		if saw_charge and actor.state == Boar.S_TIRED:
			saw_wall_stun = true
			break
	_check(actor._nav.avoidance_enabled and saw_tell and saw_charge, "远转近后真实状态机仍进入前摇与冲锋")
	_check(peak_speed > actor.inst.move_speed() * 1.5 and saw_wall_stun,
		"冲锋仍保持专属高速并在真实撞墙后硬直")
	_check(actor.position.x < wall.position.x, "近档恢复后的冲锋不能穿墙")
	actor.free()
	wall.free()
