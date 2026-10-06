## 真实世界/玩家/怪物节点验证：装备入包与死亡在同笔事务，拒绝尸体和伪击杀。
extends Node

const Drops := preload("res://scripts/equipment/equipment_drops.gd")
var _checks := 0
var _fails := 0
var _world: Node
var _player: Player
var _reentrant: MonsterBase
var _reentered := false
var _gear_victim_id := 0
var _boss_victim_id := 0
var _forged_actor: MonsterBase
var _forged_result: Dictionary = {}
var _nested_boss: MonsterBase
var _nested_boss_started := false
var _first_boss_owned_before_callback := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.save_enabled = false
	WorldSim.set_process(false)
	get_tree().paused = true
	# 独立启动也只写专用测试档；冷读子进程继承同一路径。
	if OS.get_environment("HOTW_TEST_SAVE").is_empty():
		GameState.SAVE_PATH = "user://equipment-kill-integration-test.json"
		OS.set_environment("HOTW_TEST_SAVE", GameState.SAVE_PATH)
	if "--equipment-cold-reader" in OS.get_cmdline_user_args():
		_cold_read.call_deferred()
	else:
		_run.call_deferred()


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("  %s %s" % ["PASS" if ok else "FAIL", label])


func _run() -> void:
	GameState.reset_all()
	GameState.world_seed = 20260908
	_load_old_boss_history_fixture()
	_world = preload("res://scenes/main/main.tscn").instantiate()
	# 根节点始终运行以等待异步帧；游戏子树必须尊重暂停，避免流式回收和旁路AI。
	_world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_world)
	_player = _world.get_node("Player")
	for i in 4:
		await get_tree().process_frame
	_check(not _world.can_process() and not _player.can_process(), "paused fixture suspends streaming and incidental actor updates")
	GameState.bounty = {}
	GameState.quests["active"] = []
	await _source_and_death()
	await _first_boss()
	await _negative_sources()
	await _split_sources()
	await _reentrancy()
	_cold_save()
	WorldSim.stop()
	_world.queue_free()
	await get_tree().process_frame
	get_tree().paused = false
	print("=== EQUIPMENT KILL INTEGRATION %s (%d checks) ===" % ["PASS" if _fails == 0 else "FAIL", _checks])
	get_tree().quit(0 if _fails == 0 else 1)


func _load_old_boss_history_fixture() -> void:
	var old := {"version": 17, "world_seed": GameState.world_seed, "gold": 0, "level": 1,
		"codex": {"巨魔王": 3, "牛头王": 2, "熔岩龟王": 1}}
	var file := FileAccess.open(GameState.SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(old))
	file.close()
	GameState._load()
	_check(GameState.codex.get("巨魔王", 0) == 3, "real old save keeps its existing Boss codex history")
	_check(GameState.first_boss_choices.is_empty() and GameState.equipment_state["items"].is_empty()
		and GameState.equipment_drop_state["receipts"].is_empty(), "loading old Boss history never manufactures a retrospective gear gift")
	_check(not GameState.equipment_drop_state["first_boss_consumed"]
		and GameState.equipment_drop_state["first_boss_status"] == "eligible", "old codex does not consume the new ledger first-kill entitlement")


func _spawn(species_id := "goblin", terrain := "plains", elite := false, generation := 0) -> MonsterBase:
	var region: SimRegion
	for candidate: SimRegion in WorldSim.sim.regions.values():
		if candidate.terrain == terrain:
			region = candidate
			break
	var species: SpeciesData = load("res://data/species/%s.tres" % species_id)
	var inst := WorldSim.sim.spawn_instance(species, region.id, 200, generation, 1.0, elite, region.center)
	for i in 2:
		await get_tree().process_frame
	_world._pending_stream.erase(inst.id)
	if not _world._nodes.has(inst.id):
		_world._spawn_monster_node(inst)
	for i in 2:
		await get_tree().process_frame
	var actor: MonsterBase = _world._nodes[inst.id]
	actor.set_physics_process(false)
	return actor


func _kill(actor: MonsterBase, player: Node = null) -> void:
	actor.take_damage(1000000.0, _player.global_position, false, 1.0, false, player)


func _source_and_death() -> void:
	var actor := await _spawn("goblin", "forest", true)
	_gear_victim_id = actor.inst.id
	GameState.equipment_drop_state["elite_failures"] = 4
	GameState.equipment_preferred_slot = "offhand"
	var xp := GameState.stats.xp
	var gold := GameState.gold
	var exp_xp := actor.inst.xp_reward()
	var exp_gold := EconomyMath.kill_gold(actor.inst)
	actor.take_damage(1.0, _player.global_position, false, 1.0, false, _player)
	var key: String = Drops.create_source(GameState.world_seed, "elite", actor.inst.id, 0, "forest")["source_id"]
	var locked: Dictionary = GameState.equipment_drop_state["sources"].get(key, {})
	_check(locked.get("preferred_slot") == "offhand" and locked.get("ilvl") == 4, "first real hit seals source level and preference")
	GameState.equipment_preferred_slot = "helmet"
	actor.take_damage(1.0, _player.global_position, false, 1.0, false, _player)
	_check(GameState.equipment_drop_state["sources"][key]["preferred_slot"] == "offhand", "midfight preference cannot reroll source")
	var before_items: int = GameState.equipment_state["items"].size()
	_kill(actor, _player)
	var receipt: Dictionary = GameState.equipment_drop_state["receipts"].get(key, {})
	_check(not actor.inst.is_alive and actor.state == MonsterBase.S_CORPSE, "authoritative ecology and actor die together")
	_check(GameState.gold >= gold + exp_gold and GameState.stats.xp == xp + exp_xp, "same kill grants existing gold and XP")
	_check(receipt.get("items", []).size() == 1 and GameState.equipment_state["items"].size() == before_items + 1, "pity gear enters bag exactly once")
	_check(GameState.stats.equips.is_empty(), "even an empty loadout never auto equips a drop")
	_check(GameState.equipment_drop_state["elite_failures"] == 0, "actual elite gear resets elite pity")
	_check(GameState._world_reward_depth == 0 and GameState._ecology_cache == null, "death and all loot end one world save transaction")
	var frozen := GameState.equipment_drop_state.duplicate(true)
	var after_gold := GameState.gold
	_kill(actor, _player)
	actor._die_by_player()
	_check(GameState.equipment_drop_state == frozen and GameState.gold == after_gold, "corpse damage and direct death callback are inert")


func _first_boss() -> void:
	var boss := await _spawn("treant", "forest")
	_boss_victim_id = boss.inst.id
	_nested_boss = await _spawn("treant", "forest")
	GameState.equipment_drop_state["boss_orange_failures"] = 7
	var count: int = GameState.equipment_state["items"].size()
	EventBus.monster_killed_by_player.connect(_during_first_boss_reward)
	_kill(boss, _player)
	EventBus.monster_killed_by_player.disconnect(_during_first_boss_reward)
	var first_source := EquipmentDrops.create_source(GameState.world_seed, "boss", boss.inst.id, 0, "forest")
	var first_receipt: Dictionary = GameState.equipment_drop_state["receipts"][first_source["source_id"]]
	_check(GameState.first_boss_choices.size() == 3 and first_receipt["items"].is_empty(), "first Boss creates saved choice entitlement instead of bag drop")
	_check(GameState.codex.get("巨魔王", 0) == 5 and first_receipt["first_boss"], "old-history world earns first choice only after actual new-ledger Boss kill")
	_check(GameState.equipment_drop_state["first_boss_status"] == "pending" and _first_boss_owned_before_callback, "first Boss reserves global entitlement and clears orange drought before observers")
	_check(_nested_boss_started and not _nested_boss.inst.is_alive and GameState.first_boss_choice_source == first_source["source_id"], "nested Boss death cannot steal first Boss entitlement")
	var choices := GameState.first_boss_choices.duplicate(true)
	for item: Dictionary in choices:
		_check(item.get("rarity") == 4 and item.get("item_level") == 5 and not str(item.get("id", "")).is_empty(), "pre-rolled choice has stable ID and source iLv")
	_check(GameState.first_boss_choices == choices and GameState.equipment_state["items"].size() == count + 1, "next Boss ordinary drop cannot replace unclaimed first choices")


func _negative_sources() -> void:
	var natural := await _spawn()
	var before := GameState.equipment_drop_state.duplicate(true)
	var before_gold := GameState.gold
	WorldSim.sim._die(natural.inst, EcologySim.DEATH_AGING)
	_kill(natural, _player)
	_check(GameState.equipment_drop_state == before and GameState.gold == before_gold, "natural death and corpse cannot create equipment or pity")
	var prey := await _spawn()
	WorldSim.sim._die(prey.inst, EcologySim.DEATH_PREDATED)
	_kill(prey, _player)
	_check(GameState.equipment_drop_state == before and GameState.gold == before_gold, "predation does not become player reward")
	var live := await _spawn()
	live._die_by_player()
	_check(live.inst.is_alive and GameState.gold == before_gold, "direct fake death of positive-HP actor is rejected")
	var fake := Node2D.new()
	add_child(fake)
	_kill(live, fake)
	_check(GameState.equipment_drop_state == before, "non-player lethal provenance cannot progress equipment pity")
	fake.queue_free()
	var dead_player_target := await _spawn()
	_player._is_dead = true
	_kill(dead_player_target, _player)
	_player._is_dead = false
	_check(GameState.equipment_drop_state == before, "dead Player provenance cannot create equipment")
	var synthetic: MonsterBase = preload("res://scenes/monsters/goblin.tscn").instantiate()
	_world.monsters.add_child(synthetic)
	var made_up := MonsterInstance.new()
	made_up.id = 99999999
	made_up.species = load("res://data/species/goblin.tres")
	made_up.spawn_pos = _player.global_position
	synthetic.setup(made_up)
	before_gold = GameState.gold
	_kill(synthetic, _player)
	_check(GameState.equipment_drop_state == before and GameState.gold == before_gold, "unregistered synthetic monster cannot issue player rewards")
	synthetic.queue_free()
	# 先由玩家留下真实交战来源，之后非玩家致死。观察者即使拼出真实 ID，也不能
	# 把“历史交战”偷换成本次归因；服务层须核实 actor 的本次击杀凭证。
	_forged_actor = await _spawn()
	_forged_actor.take_damage(1.0, _player.global_position, false, 1.0, false, _player)
	var attributed_before := GameState.equipment_drop_state.duplicate(true)
	EventBus.monster_killed_by_player.connect(_during_unattributed_reward)
	_kill(_forged_actor)
	EventBus.monster_killed_by_player.disconnect(_during_unattributed_reward)
	_check(_forged_result.is_empty() and GameState.equipment_drop_state == attributed_before,
		"observer cannot forge current kill from a previously player-tagged source")


func _split_sources() -> void:
	var child := await _spawn("slime", "plains", false, 1)
	var before: int = GameState.equipment_drop_state["receipts"].size()
	GameState.equipment_drop_state["ordinary_failures"] = 24
	_kill(child, _player)
	_check(GameState.equipment_drop_state["receipts"].size() == before + 1
		and GameState.equipment_drop_state["ordinary_failures"] == 0, "real finite split descendant consumes exactly one eligible pity roll")
	var after := GameState.equipment_drop_state.duplicate(true)
	_kill(child, _player)
	_check(GameState.equipment_drop_state == after and child.inst.is_split_sterile(), "split corpse cannot farm receipt or pity and lineage remains sterile")


func _reentrancy() -> void:
	_reentrant = await _spawn("goblin", "plains", true)
	GameState.equipment_drop_state["elite_failures"] = 4
	var before: int = GameState.equipment_drop_state["receipts"].size()
	var before_items: int = GameState.equipment_state["items"].size()
	EventBus.monster_killed_by_player.connect(_during_reward)
	_kill(_reentrant, _player)
	EventBus.monster_killed_by_player.disconnect(_during_reward)
	_check(_reentered and GameState.equipment_drop_state["receipts"].size() == before + 1 and GameState.equipment_state["items"].size() == before_items + 1, "synchronous reward observer cannot duplicate death or consume pity twice")


func _during_reward(_xp: int, _gold: int, _display: String, _species: String) -> void:
	_reentered = true
	_kill(_reentrant, _player)


func _during_unattributed_reward(_xp: int, _gold: int, _display: String, _species: String) -> void:
	var fabricated := _forged_actor._equipment_source(_player)
	fabricated["player_kill"] = true
	_forged_result = GameState.settle_equipment_drop(fabricated)


func _during_first_boss_reward(_xp: int, _gold: int, _display: String, _species: String) -> void:
	if _nested_boss_started:
		return
	_nested_boss_started = true
	_first_boss_owned_before_callback = GameState.first_boss_choices.size() == 3 \
		and GameState.equipment_drop_state["boss_orange_failures"] == 0
	_kill(_nested_boss, _player)


func _cold_save() -> void:
	GameState.save_enabled = true
	_check(GameState.save_now(), "actual world reward state saves successfully")
	var expected := {"gold": GameState.gold, "xp": GameState.stats.xp,
		"gear_victim_id": _gear_victim_id, "boss_victim_id": _boss_victim_id,
		"drops": GameState.equipment_drop_state, "choices": GameState.first_boss_choices,
		"items": GameState.equipment_state["items"]}
	var file := FileAccess.open(GameState.SAVE_PATH + ".expected", FileAccess.WRITE)
	file.store_string(JSON.stringify(expected))
	file.close()
	var output: Array = []
	var code := OS.execute(OS.get_executable_path(), PackedStringArray([
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"res://tests/equipment_kill_integration_test.tscn", "--quit-after", "3000", "--", "--equipment-cold-reader"
	]), output, true)
	var completed := false
	for line: String in output:
		print(line)
		completed = completed or "EQUIPMENT KILL COLD PASS" in line
	_check(code == 0 and completed, "independent cold process preserves actual deaths loot pity and pending choices")
	GameState.save_enabled = false


func _cold_read() -> void:
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GameState.SAVE_PATH + ".expected"))
	_check(GameState.gold == int(expected["gold"]) and GameState.stats.xp == int(expected["xp"]), "cold process loads kill gold and XP")
	_check(_same_data(GameState.equipment_drop_state, expected["drops"]), "cold process preserves complete source and pity ledger")
	_check(_same_data(GameState.first_boss_choices, expected["choices"]), "cold process preserves exact first Boss pre-rolls")
	_check(_same_data(GameState.equipment_state["items"], expected["items"]), "cold process preserves bag drops with stable identity")
	_world = preload("res://scenes/main/main.tscn").instantiate()
	# 根节点始终运行以等待异步帧；游戏子树必须尊重暂停，避免流式回收和旁路AI。
	_world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_world)
	for i in 4:
		await get_tree().process_frame
	for key: String in ["gear_victim_id", "boss_victim_id"]:
		var inst: MonsterInstance = WorldSim.sim.instances.get(int(expected[key]))
		_check(inst != null and not inst.is_alive, "cold process does not revive rewarded source " + key)
	print("EQUIPMENT KILL COLD %s" % ["PASS" if _fails == 0 else "FAIL"])
	get_tree().quit(0 if _fails == 0 else 1)


func _same_data(a: Variant, b: Variant) -> bool:
	if typeof(a) in [TYPE_INT, TYPE_FLOAT] and typeof(b) in [TYPE_INT, TYPE_FLOAT]:
		return absf(float(a) - float(b)) <= 0.000000000001
	if typeof(a) != typeof(b):
		return false
	if a is Dictionary:
		if a.size() != b.size():
			return false
		for key: Variant in a:
			if not b.has(key) or not _same_data(a[key], b[key]):
				print("  COLD FIELD DIFF ", key)
				return false
		return true
	if a is Array:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not _same_data(a[i], b[i]):
				return false
		return true
	return a == b
