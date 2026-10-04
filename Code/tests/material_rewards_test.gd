## 材料奖励合同：29个真实物种×普通/精英（Boss单列），冻结AI与生态时钟，
## 逐个走注册场景 take_damage → 死亡信号 → 自动入包，避免游猎物种比例污染掉落闸门。
## 独立预期来自已批准的材料设计，故意不调用被测 EconomyMath.material_for/drop_count。
## 63件是完整物种奖励队列的预算，不是「任何10分钟路线都最多70件」的承诺。
extends Node2D

const WORLD := preload("res://scripts/main/game_world.gd")
const WORLD_SEED := 20260908
const RANDOM_SEED := 20261004
const DAMAGE := 1000000.0
const EXPECTED_MATERIAL := {
	"突袭蛇": "beaf", "雪原巨熊": "beaf", "山猪": "beaf", "山羊": "beaf", "野鸭": "beaf", "山蜂": "beaf",
	"雪原窃贼": "fish", "青甲龟": "fish", "沼泽蛛": "shrimp", "炸弹鱼": "octopus",
	"地精矿工": "tea-leaf", "投骨豺狼人": "tea-leaf", "巫毒萨满": "tea-leaf", "弹弓地精": "tea-leaf",
	"火蜂": "scroll-fire", "熔岩萨满": "scroll-fire", "黑曜牛卫": "scroll-rock", "长矛哥布林": "scroll-rock",
	"巨魔王": "tea-leaf", "牛头王": "scroll-rock", "熔岩龟王": "fish",
}
const EXPECTED_NO_MATERIAL := ["火把哥布林", "赤炎小魔", "冰霜小魔", "蜥蜴刀客", "白骨兵", "巨蝠", "鱼叉鲨", "山岳熊猫"]
const EXPECTED_BOSSES := ["巨魔王", "牛头王", "熔岩龟王"]
const MATERIAL_IDS := ["beaf", "fish", "shrimp", "octopus", "tea-leaf", "scroll-fire", "scroll-rock"]
const BOSS_SUPPLIES := ["onigiri", "sushi", "medipack", "water-pot"]

var _checks := 0
var _fails := 0
var _cases := 0
var _cohort_materials := 0
var _cohort_keys := 0
var _cohort_supplies := 0
var _body: MonsterBase
var _sim: EcologySim
var _kill_events := 0
var _death_events := 0
var _kill_reentries := 0
var _item_reentries := 0
var _gained: Dictionary = {}
var _gain_events: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.save_enabled = false
	GameState.SAVE_PATH = "user://material_rewards_test.json"
	WorldSim.stop()
	WorldSim.set_process(false)
	get_tree().paused = true
	_run.call_deferred()


func _run() -> void:
	seed(RANDOM_SEED)
	GameState.reset_all()
	GameState.world_seed = WORLD_SEED
	BiomeMap.configure(WORLD_SEED)
	EventBus.monster_killed_by_player.connect(_on_reward_kill)
	EventBus.item_gained.connect(_on_item_gained)
	var species_list := SpeciesCatalog.build_all()
	var names: Array[String] = []
	var registered := true
	var expected_catalog := true
	var boss_count := 0
	for species: SpeciesData in species_list:
		names.append(species.species_name)
		registered = registered and WORLD.MONSTER_SCENES.has(species.species_name)
		expected_catalog = expected_catalog and (EXPECTED_MATERIAL.has(species.species_name) or species.species_name in EXPECTED_NO_MATERIAL)
		if species.is_boss:
			boss_count += 1
		_check(species.is_boss == (species.species_name in EXPECTED_BOSSES), "%s首领身份符合材料合同" % species.species_name)
	_check(names.size() == 29 and boss_count == 3 and registered and expected_catalog,
		"29物种全部来自真实目录和注册场景，3首领与8无材料物种不漏测")
	if not registered or not expected_catalog or names.size() != 29:
		_finish()
		return
	for name: String in EXPECTED_MATERIAL:
		_check(names.has(name), "%s材料来源仍存在于真实目录" % name)
	for name: String in EXPECTED_NO_MATERIAL:
		_check(names.has(name), "%s零材料来源仍存在于真实目录" % name)
	for species: SpeciesData in species_list:
		await _test_case(species, false)
		if not species.is_boss:
			await _test_case(species, true)
	_check(_cases == 55, "26普通/精英双变体与3首领共55次真实击杀")
	_check(_cohort_materials == 63, "完整物种队列材料精确63件（实得%d），不含钥匙/补给" % _cohort_materials)
	_check(_cohort_materials >= 5 and _cohort_materials <= 70,
		"完整物种奖励队列预算∈[5,70]（%d件；不是10分钟游猎产量）" % _cohort_materials)
	_check(_cohort_supplies == 3, "3只首领各附1件补给，共%d件" % _cohort_supplies)
	print("  材料队列：%d件 / 银钥匙观察值：%d件 / 首领补给：%d件" % [_cohort_materials, _cohort_keys, _cohort_supplies])
	_finish()


func _test_case(species: SpeciesData, elite: bool) -> void:
	# 每个样本清空库存，99容量不会把多发、漏发或错误映射钳成看似正确的总量。
	GameState.inventory.clear()
	GameState.stats.reset()
	GameState.gold = 0
	GameState.equipment_locks.clear()
	GameState.pending_equipment.clear()
	_gained.clear()
	_gain_events.clear()
	_kill_events = 0
	_death_events = 0
	_kill_reentries = 0
	_item_reentries = 0
	var arena := SimRegion.new()
	arena.id = "material_reward_arena"
	arena.center = WorldConfig.spawn_pos()
	arena.size = Vector2(2000, 2000)
	arena.terrain = species.habitats[0] if not species.habitats.is_empty() else "plains"
	arena.capacity = 20
	_sim = EcologySim.new()
	var one_species: Array[SpeciesData] = [species]
	_sim.setup([arena], one_species, {})
	WorldSim.sim = _sim
	_sim.instance_died.connect(_on_sim_death)
	var inst := _sim.spawn_instance(species, arena.id, species.maturity_age,
			0, species.boss_size_scale if species.is_boss else 1.0, elite, arena.center)
	_body = WORLD.MONSTER_SCENES[species.species_name].instantiate() as MonsterBase
	add_child(_body)
	_body.setup(inst)
	_body.process_mode = Node.PROCESS_MODE_DISABLED
	var label := "%s/%s" % [species.species_name, "首领" if species.is_boss else ("精英" if elite else "普通")]
	var material: String = EXPECTED_MATERIAL.get(species.species_name, "")
	var count := (3 if species.is_boss else (2 if elite else 1)) if material != "" else 0
	var expected: Dictionary = {material: count} if material != "" else {}
	_body.take_damage(DAMAGE, arena.center + Vector2(80, 0))
	_check(not inst.is_alive and _body.state == MonsterBase.S_CORPSE and _death_events == 1 and _kill_events == 1,
		label + "真实受击完成且仅完成一次奖励/生态死亡")
	_check(_kill_reentries == 1 and (_item_reentries == 1 if not _gained.is_empty() else _item_reentries == 0),
		label + "击杀与物品同步回调确实重入伤害")
	var actual := _material_inventory()
	_check(actual == expected, "%s材料独立合同：%s（实得%s）" % [label, str(expected), str(actual)])
	var materials_once := true
	for id: String in MATERIAL_IDS:
		materials_once = materials_once and int(_gained.get(id, 0)) == int(expected.get(id, 0)) \
				and int(_gain_events.get(id, 0)) == (1 if expected.has(id) else 0)
	_check(materials_once, label + "材料获得信号与库存精确一致，回调不重复发放")
	var keys := GameState.count_item("silver-key")
	_check(GameState.count_item("gold-key") == 0 and (keys in [0, 1] if elite else keys == 0),
		label + "金钥匙不由击杀产生，银钥匙仅精英可得0或1件")
	var supply_count := 0
	var permitted := true
	for id: String in GameState.inventory:
		var amount := GameState.count_item(id)
		if id in BOSS_SUPPLIES:
			supply_count += amount
		else:
			permitted = permitted and (id == material or id == "silver-key")
	_check(permitted and supply_count == (1 if species.is_boss else 0),
		label + "首领仅附一件允许补给，其余物品不混入材料")
	var all_signals_once := true
	for id: String in GameState.inventory:
		all_signals_once = all_signals_once and int(_gained.get(id, 0)) == GameState.count_item(id) \
				and int(_gain_events.get(id, 0)) == 1
	_check(all_signals_once and _gained.size() == GameState.inventory.size(), label + "钥匙/补给也恰好入包并播报一次")
	var settled_inventory := GameState.inventory.duplicate(true)
	var settled_gained := _gained.duplicate(true)
	var settled_events := _gain_events.duplicate(true)
	_body.take_damage(DAMAGE, arena.center + Vector2(80, 0))
	_sim.report_killed(inst.id, _body.global_position)
	_check(GameState.inventory == settled_inventory and _gained == settled_gained and _gain_events == settled_events \
			and _kill_events == 1 and _death_events == 1,
		label + "尸体第二次受击和重复死亡报告均无奖励副作用")
	for id: String in actual:
		_cohort_materials += int(actual[id])
	_cohort_keys += keys
	_cohort_supplies += supply_count
	_cases += 1
	_body.queue_free()
	await get_tree().process_frame
	_body = null
	WorldSim.stop()
	_sim = null


func _material_inventory() -> Dictionary:
	var out := {}
	for id: String in MATERIAL_IDS:
		var count := GameState.count_item(id)
		if count > 0:
			out[id] = count
	return out


func _on_reward_kill(_xp: int, _gold: int, _name: String, _species: String) -> void:
	_kill_events += 1
	# 先置标再重入，坏版本也能有界失败，不以栈溢出充当回归证据。
	if _kill_reentries == 0 and is_instance_valid(_body):
		_kill_reentries += 1
		_body.take_damage(DAMAGE)


func _on_item_gained(id: String, count: int, _total: int) -> void:
	_gained[id] = int(_gained.get(id, 0)) + count
	_gain_events[id] = int(_gain_events.get(id, 0)) + 1
	if _item_reentries == 0 and is_instance_valid(_body):
		_item_reentries += 1
		_body.take_damage(DAMAGE)


func _on_sim_death(inst: MonsterInstance, cause: String) -> void:
	if is_instance_valid(_body) and _body.inst == inst:
		_death_events += 1
		_check(cause == EcologySim.DEATH_KILLED, "实际奖励对应玩家击杀死因")
		_body.on_sim_death()


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])


func _finish() -> void:
	WorldSim.stop()
	print("=== MATERIAL REWARDS %s (%d checks, %d failures) ===" % ["PASS" if _fails == 0 else "FAIL", _checks, _fails])
	get_tree().quit(0 if _fails == 0 else 1)
