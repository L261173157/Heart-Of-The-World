## 真实攻击输入路径和物理碰撞验证装备来源归属；不直接调用目标 take_damage。
extends Node2D

var _player: Player
var _targets: Array[MonsterBase] = []
var _origin: Vector2
var _checks := 0
var _fails := 0


func _ready() -> void:
	GameState.save_enabled = false
	GameState.reset_all()
	GameState.settings.auto_aim = false
	GameState.settings.screen_shake = false
	WorldSim.stop()
	WorldSim.sim = EcologySim.new()
	BiomeMap.configure(BiomeMap.DEFAULT_SEED)
	ObstacleField.restore_destroyed([])
	_origin = WorldConfig.spawn_pos()
	var region := SimRegion.new()
	region.id = "equipment_sources"
	region.terrain = "plains"
	region.center = _origin
	region.size = Vector2(2000, 2000)
	region.capacity = 500
	var species: SpeciesData = load("res://data/species/goblin.tres")
	WorldSim.sim.setup([region], [species], {})
	WorldSim.sim.instance_died.connect(_on_death)
	_player = preload("res://scenes/player/player.tscn").instantiate()
	add_child(_player)
	_player.teleport_to(_origin)
	_run.call_deferred()


func _on_death(inst: MonsterInstance, _cause: String) -> void:
	for actor: MonsterBase in _targets:
		if is_instance_valid(actor) and actor.inst == inst:
			actor.on_sim_death()


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("  %s %s" % ["PASS" if ok else "FAIL", label])


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
		await get_tree().process_frame


func _target(offset: Vector2) -> MonsterBase:
	var actor: MonsterBase = preload("res://scenes/monsters/goblin.tscn").instantiate()
	add_child(actor)
	actor.set_physics_process(false)
	var species: SpeciesData = load("res://data/species/goblin.tres")
	var inst := WorldSim.sim.spawn_instance(species, "equipment_sources", 200, 0, 1.0, false, _origin + offset)
	actor.setup(inst)
	actor.global_position = _origin + offset
	actor.current_hp = 1.0
	actor._nav.avoidance_enabled = false
	actor.collision_mask = 0
	_targets.append(actor)
	return actor


func _reset() -> void:
	for actor: MonsterBase in _targets:
		if is_instance_valid(actor):
			actor.queue_free()
	_targets.clear()
	for bolt: Node in get_tree().get_nodes_in_group("player_bolts"):
		bolt.queue_free()
	await _frames(2)
	PlayerBolt.clear_pool()
	TouchInput.reset()
	_player.teleport_to(_origin)
	_player.facing = Vector2.RIGHT
	_player.current_hp = _player.stats.max_hp()
	_player.current_mp = _player.stats.max_mp()
	_player._attack_cooldown = 0.0
	_player._heavy_cd = 0.0
	_player._bolt_cd = 0.0
	_player._hurt_iframes = 0.0
	_player._protect_timer = 0.0
	_player._dash_timer = 0.0
	_player._is_dead = false
	_player.stats.passives = {}
	_player.cancel_guard(false, true)
	GameState.equipment_drop_state["ordinary_failures"] = 24


func _receipt(actor: MonsterBase) -> bool:
	var source := EquipmentDrops.create_source(GameState.world_seed, "ordinary", actor.inst.id, 0, "plains")
	return GameState.equipment_drop_state["receipts"].has(source["source_id"])


func _locked_preference(actor: MonsterBase) -> String:
	var source := EquipmentDrops.create_source(GameState.world_seed, "ordinary", actor.inst.id, 0, "plains")
	return str(GameState.equipment_drop_state["sources"].get(source["source_id"], {}).get("preferred_slot", ""))


func _run() -> void:
	await _frames(2)
	await _incoming_sources()
	await _reset()
	var main := _target(Vector2(38, 0))
	await _frames(2)
	_player._try_attack()
	await _frames(30)
	_check(not main.inst.is_alive and _receipt(main), "actual primary sword collision settles attributed source")
	await _reset()
	var heavy := _target(Vector2(60, 0))
	await _frames(2)
	_player._try_heavy_attack()
	await _frames(24)
	_check(not heavy.inst.is_alive and _receipt(heavy), "actual paid heavy AOE settles attributed source")
	await _reset()
	var counter := _target(Vector2(38, 0))
	await _frames(2)
	_player.begin_guard()
	await _frames(12)
	_player.guard_charge = 3
	_player.release_guard()
	await _frames(30)
	_check(not counter.inst.is_alive and _receipt(counter), "actual guard release counter collision settles attributed source")
	await _reset()
	var bolt := _target(Vector2(90, 0))
	await _frames(2)
	_player._try_cast_bolt()
	await _frames(30)
	_check(not bolt.inst.is_alive and _receipt(bolt), "actual paid projectile flight carries Player weak provenance")
	await _reset()
	var root := _target(Vector2(90, 0))
	var shard := _target(Vector2(145, 32))
	_player.stats.passives = {"bolt_split": 1}
	await _frames(2)
	_player._try_cast_bolt()
	await _frames(45)
	_check(not root.inst.is_alive and _receipt(root), "split spell main projectile attributed")
	_check(not shard.inst.is_alive and _receipt(shard), "actual generated shard flight retains kill provenance")
	await _reset()
	var unattributed := _target(Vector2(90, 0))
	await _frames(2)
	PlayerBolt.spawn(self, _origin + Vector2(22, 0), Vector2.RIGHT, 100.0)
	await _frames(30)
	_check(not unattributed.inst.is_alive and not _receipt(unattributed), "unattributed projectile cannot gain equipment receipt")
	_check(GameState.equipment_drop_state["ordinary_failures"] == 24, "unattributed projectile cannot consume pity")
	await _reset()
	var fake_target := _target(Vector2(90, 0))
	var fake_player := Node2D.new()
	add_child(fake_player)
	await _frames(2)
	PlayerBolt.spawn(self, _origin + Vector2(22, 0), Vector2.RIGHT, 100.0, "", {"player_source": weakref(fake_player)})
	await _frames(30)
	_check(not fake_target.inst.is_alive and not _receipt(fake_target), "forged non-Player projectile provenance cannot gain gear")
	fake_player.queue_free()
	await _reset()
	var dead_target := _target(Vector2(90, 0))
	await _frames(2)
	_player._try_cast_bolt()
	await _frames(11) # 先完成真实施法，再验证已经飞出的弹体跨死亡归因。
	_player._die()
	await _frames(30)
	_check(not dead_target.inst.is_alive and not _receipt(dead_target), "projectile arriving after player death cannot create gear")
	await _reset()
	WorldSim.stop()
	print("=== EQUIPMENT ATTACK SOURCES %s (%d checks) ===" % ["PASS" if _fails == 0 else "FAIL", _checks])
	get_tree().quit(0 if _fails == 0 else 1)


func _incoming_sources() -> void:
	await _reset()
	var attacker := _target(Vector2(30, 0))
	await _frames(2)
	GameState.equipment_preferred_slot = "offhand"
	var hp := _player.current_hp
	attacker._perform_attack(_player)
	_check(_player.current_hp < hp and _locked_preference(attacker) == "offhand", "actual incoming melee damage locks source before outgoing attack")
	GameState.equipment_preferred_slot = "boots"
	_player._try_attack()
	await _frames(30)
	_check(not attacker.inst.is_alive and _receipt(attacker), "incoming-tagged source settles after preference changes")
	await _reset()
	var blocked := _target(Vector2(30, 0))
	await _frames(2)
	GameState.equipment_preferred_slot = "helmet"
	Input.action_press("guard")
	await _frames(12)
	hp = _player.current_hp
	blocked._perform_attack(_player)
	_check(is_equal_approx(_player.current_hp, hp) and _player.guard_charge == 1 and _locked_preference(blocked) == "helmet", "successful zero-HP-damage block still locks first combat preference")
	GameState.equipment_preferred_slot = "charm"
	Input.action_release("guard")
	await _frames(30)
	_check(not blocked.inst.is_alive and _receipt(blocked), "real release counter settles the shield-tagged source")
	await _reset()
	var ranged := _target(Vector2(120, 0))
	await _frames(2)
	GameState.equipment_preferred_slot = "armor"
	var context := ranged._damage_context(_player, 5.0)
	var enemy_bolt := Projectile.spawn(self, ranged.global_position - Vector2(16, 0), Vector2.LEFT,
		5.0, 270.0, ranged.inst.display_name(), "", context)
	var first_attack_id: String = enemy_bolt.attack_context["attack_id"]
	_check(enemy_bolt.attack_context.has("equipment_source") and _locked_preference(ranged).is_empty(), "enemy projectile carries source without prematurely locking at launch")
	hp = _player.current_hp
	await _frames(30)
	_check(_player.current_hp < hp and _locked_preference(ranged) == "armor", "actual enemy projectile collision locks firing source")
	var recycled := Projectile.spawn(self, _origin + Vector2(400, 300), Vector2.RIGHT, 1.0)
	_check(not recycled.attack_context.has("equipment_source") and recycled.attack_context["attack_id"] != first_attack_id, "pooled enemy projectile clears stale equipment source and attack ID")
	recycled.queue_free()
	await _reset()
	var immune := _target(Vector2(30, 0))
	await _frames(2)
	_player._protect_timer = 1.0
	immune._perform_attack(_player)
	_check(_locked_preference(immune).is_empty(), "invulnerable rejected enemy hit does not lock preference")
	_player._protect_timer = 0.0
	var duplicate_context := immune._damage_context(_player, 5.0)
	_player._guard_seen_attacks[duplicate_context["attack_id"]] = true
	_player.take_damage(5.0, immune.global_position, immune.inst.display_name(), duplicate_context)
	_check(_locked_preference(immune).is_empty(), "already-consumed enemy action cannot create source lock")
	await _reset()
	Projectile.clear_pool()
