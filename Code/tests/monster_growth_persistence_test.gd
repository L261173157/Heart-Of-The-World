## 怪物成长血量：真实节点、生态 tick、卸载/重建、独立进程读档保持相同伤口。
extends Node2D

const ENTRIES := [
	{"id": "goblin", "scene": "goblin", "age": 200, "generation": 0, "size": 1.0},
	{"id": "stag_beetle_king", "scene": "ant", "age": 1398, "generation": 0, "size": 2.2},
	{"id": "slime", "scene": "slime", "age": 20, "generation": 1, "size": 0.6},
]
const ORIGIN := Vector2(120000, 120000)
var _checks := 0
var _fails := 0
var _player: Player
var _nodes: Array[MonsterBase] = []
var _species: Array[SpeciesData] = []
var _region: SimRegion

func _ready() -> void:
	GameState.save_enabled = false
	WorldSim.stop()
	GameState.reset_all()
	BiomeMap.configure(BiomeMap.DEFAULT_SEED)
	ObstacleField.restore_destroyed([])
	_configure()
	if "--cold-growth-reader" in OS.get_cmdline_user_args():
		_cold_reader.call_deferred()
	else:
		_run.call_deferred()

func _configure() -> void:
	_region = SimRegion.new()
	_region.id = "growth_yard"
	_region.terrain = "plains"
	_region.center = ORIGIN
	_region.size = Vector2(8000, 8000)
	_region.capacity = 100
	_region.threat = 1.3
	for entry: Dictionary in ENTRIES:
		var sp: SpeciesData = load("res://data/species/%s.tres" % entry.id).duplicate()
		sp.habitats = ["plains"]
		sp.breeding_rate = 0.0
		sp.migrate_count = 0
		sp.prey = []
		sp.lifespan_min = 100000
		sp.lifespan_max = 100000
		_species.append(sp)

func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("  %s %s" % ["PASS" if ok else "FAIL", label])

func _frames(count := 1) -> void:
	for _i in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func _body(inst: MonsterInstance, scene_name: String) -> MonsterBase:
	var body: MonsterBase = load("res://scenes/monsters/%s.tscn" % scene_name).instantiate()
	add_child(body)
	body.set_physics_process(false)
	body.setup(inst)
	body._nav.avoidance_enabled = false
	body.collision_mask = 0
	body.global_position = inst.spawn_pos
	_nodes.append(body)
	return body

func _clear() -> void:
	for body in _nodes:
		if is_instance_valid(body):
			body.queue_free()
	_nodes.clear()
	await _frames(2)
	WorldSim.stop()

func _run() -> void:
	_player = preload("res://scenes/player/player.tscn").instantiate()
	add_child(_player)
	_player.set_process(false)
	_player.set_physics_process(false)
	_player.get_node("Camera2D").enabled = false
	_player.global_position = ORIGIN
	for index in ENTRIES.size():
		for wounded: bool in [false, true]:
			await _lifecycle(index, wounded)
	await _damage_between_tick_and_node()
	await _legacy_full_health()
	_player.queue_free()
	await _frames(2)
	WorldSim.stop()
	print("=== MONSTER GROWTH PERSISTENCE %s (%d checks) ===" % ["PASS" if _fails == 0 else "FAIL", _checks])
	get_tree().quit(0 if _fails == 0 else 1)

func _lifecycle(index: int, wounded: bool) -> void:
	await _clear()
	var sim := EcologySim.new()
	sim.reintroduction_enabled = false
	sim.setup([_region], _species, {})
	WorldSim.sim = sim
	var entry: Dictionary = ENTRIES[index]
	var sp := _species[index]
	var actors: Array[MonsterBase] = []
	var instances: Array[MonsterInstance] = []
	for offset: Vector2 in [Vector2(500, 0), Vector2(1500, 0), Vector2(500, 200)]:
		var inst := sim.spawn_instance(sp, _region.id, entry.age, entry.generation,
			entry.size, false, ORIGIN + offset)
		instances.append(inst)
		var body := _body(inst, entry.scene)
		if wounded:
			body.take_damage(7.0)
		actors.append(body)
	var wound := instances[0].max_hp() - actors[0].current_hp
	# 先让一次真实成长建立满血镜像，覆盖“从未受击但已有 hp_mirror”的旧漏洞。
	sim.tick()
	for body in actors:
		body.set_physics_process(true)
	await _frames(7)
	for body in actors:
		body.set_physics_process(false)
	_check(is_equal_approx(actors[0].current_hp, actors[2].current_hp), "%s 同龄同伤初值一致" % entry.id)
	actors[2].queue_free()
	await _frames(2)
	# 近档与远档始终在树；第三只仅剩纯模拟实例。世界推进不依赖可见节点。
	for body in [actors[0], actors[1]]:
		body.set_physics_process(true)
	for _i in 100:
		sim.tick()
	await _frames(7)
	for body in [actors[0], actors[1]]:
		body.set_physics_process(false)
	var expected := instances[0].max_hp() - wound
	for i in 3:
		_check(is_equal_approx(instances[i].max_hp(), instances[0].max_hp()), "%s 同龄上限%d" % [entry.id, i])
		_check(is_equal_approx(instances[i].hp_mirror, expected), "%s %s镜像%d 保留绝对伤口" % [entry.id, "受伤" if wounded else "无伤", i])
	_check(is_equal_approx(actors[0].current_hp, expected) and is_equal_approx(actors[1].current_hp, expected),
		"%s 近/远档同步但不重复增加成长生命" % entry.id)
	var rebuilt := _body(instances[2], entry.scene)
	_check(is_equal_approx(rebuilt.current_hp, expected), "%s 卸载重建不凭空缺血或治愈伤口" % entry.id)
	var packet := {"world": sim.to_dict(), "expected": []}
	for inst in instances:
		packet.expected.append({"id": inst.id, "hp": expected, "max": inst.max_hp(), "scene": entry.scene})
	var path := "user://growth_roundtrip_%d.json" % OS.get_process_id()
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(packet))
	file.close()
	var output: Array = []
	var code := OS.execute(OS.get_executable_path(), PackedStringArray([
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"res://tests/monster_growth_persistence_test.tscn", "--quit-after", "3000", "--", "--cold-growth-reader",
		ProjectSettings.globalize_path(path)]), output, true)
	var complete := false
	for text: String in output:
		print(text)
		complete = complete or "=== MONSTER GROWTH COLD READER PASS ===" in text
	_check(code == 0 and complete, "%s %s独立进程恢复同一生态血量" % [entry.id, "受伤" if wounded else "无伤"])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _cold_reader() -> void:
	var args := OS.get_cmdline_user_args()
	var path: String = args[args.find("--cold-growth-reader") + 1]
	var packet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var sim := EcologySim.new()
	WorldSim.sim = sim
	_check(sim.restore_from_dict([_region], _species, packet.world), "独立进程恢复生态文件")
	for item: Dictionary in packet.expected:
		var inst: MonsterInstance = sim.instances[int(item.id)]
		var body := _body(inst, item.scene)
		_check(is_equal_approx(body.current_hp, float(item.hp)) and is_equal_approx(inst.max_hp(), float(item.max)), "独立进程真实节点血量/上限一致")
	await _clear()
	print("=== MONSTER GROWTH COLD READER %s ===" % ("PASS" if _fails == 0 else "FAIL"))
	get_tree().quit(0 if _fails == 0 else 1)

func _damage_between_tick_and_node() -> void:
	await _clear()
	var sim := EcologySim.new()
	sim.reintroduction_enabled = false
	sim.setup([_region], _species, {})
	WorldSim.sim = sim
	var inst := sim.spawn_instance(_species[0], _region.id, 200, 0, 1.0, false, ORIGIN + Vector2(500, 0))
	var body := _body(inst, "goblin")
	body.take_damage(10.0)
	var wound := inst.max_hp() - body.current_hp
	for _i in 10:
		sim.tick()
	# 模拟已经涨龄，节点还未处理物理帧，此刻真实命中不应抹掉刚增长的血量。
	body.take_damage(5.0)
	var expected := inst.max_hp() - wound - 5.0 * (1.0 - inst.species.defense_reduction)
	_check(is_equal_approx(body.current_hp, expected) and is_equal_approx(inst.hp_mirror, expected), "tick后节点刷新前命中不覆盖成长镜像")
	body.set_physics_process(true)
	await _frames(2)
	body.set_physics_process(false)
	_check(is_equal_approx(body.current_hp, expected), "命中后下个物理步不重复补成长")

func _legacy_full_health() -> void:
	await _clear()
	var sim := EcologySim.new()
	sim.reintroduction_enabled = false
	sim.setup([_region], _species, {})
	WorldSim.sim = sim
	var inst := sim.spawn_instance(_species[0], _region.id, 200, 0, 1.0, false, ORIGIN)
	for _i in 10:
		sim.tick()
	_check(inst.hp_mirror == -1.0, "从未加载的满血-1语义保留")
	var snap := sim.to_dict()
	_check(not (snap.instances[0] as Dictionary).has("hp"), "旧档兼容：满血缺hp键")
	var restored := EcologySim.new()
	WorldSim.sim = restored
	_check(restored.restore_from_dict([_region], _species, snap), "无hp旧快照仍可恢复")
	var body := _body(restored.instances[inst.id], "goblin")
	_check(is_equal_approx(body.current_hp, body.inst.max_hp()), "旧满血档真实节点仍满血")
	await _clear()
