## 橙装真实战斗闭环：实际Player/MonsterBase/PlayerBolt碰撞，加存档及换装资源守闸。
extends Node2D

class NestProbe extends StaticBody2D:
	var hp := 1000.0
	func take_damage(amount: float, _from := Vector2.INF, _heavy := false,
			_knock := 1.0, _effective := false) -> void:
		hp -= amount

const PLAYER := preload("res://scenes/player/player.tscn")
const GOBLIN := preload("res://scenes/monsters/goblin.tscn")
var _player: Player
var _targets: Array[MonsterBase] = []
var _checks := 0
var _fails := 0
var _bursts: Array[String] = []
var _roots: Array[String] = []
var _origin := Vector2.ZERO

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.save_enabled = false
	GameState.reset_all()
	GameState.settings.auto_aim = false
	GameState.settings.screen_shake = false
	WorldSim.stop()
	WorldSim.sim = EcologySim.new()
	BiomeMap.configure(BiomeMap.DEFAULT_SEED)
	ObstacleField.restore_destroyed([])
	TouchInput.reset()
	_origin = WorldConfig.spawn_pos()
	EventBus.equipment_particles_requested.connect(func(kind: String, _p: Vector2, _d: Vector2): _bursts.append(kind))
	EventBus.player_bolt_live_hit.connect(func(root: String, _paid: float, _f: float, _p: Vector2): _roots.append(root))
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

func _gear(mechanism: String, level := 10) -> Dictionary:
	return {"mechanism": mechanism, "item_level": level, "rules_version": 1,
		"rarity": 4, "base_id": "physical_sword" if mechanism == "combo" else mechanism, "affixes": {}}

func _equip(mechanism: String, level := 10) -> void:
	_player.stats.equips = {"weapon" if mechanism == "combo" else "offhand": _gear(mechanism, level)}

func _monster(offset: Vector2) -> MonsterBase:
	var monster := GOBLIN.instantiate() as MonsterBase
	add_child(monster)
	monster.set_physics_process(false)
	var species: SpeciesData = load("res://data/species/goblin.tres").duplicate()
	var pos := _player.global_position + offset
	var inst := WorldSim.sim.spawn_instance(species, "equipment", 200, 0, 1.0, false, pos)
	monster.setup(inst)
	monster.global_position = pos
	monster.current_hp = 10000.0
	monster.collision_mask = 0
	monster._nav.avoidance_enabled = false
	_targets.append(monster)
	return monster

func _clear() -> void:
	if is_instance_valid(_player):
		while not _player._skill_action.is_empty():
			await _frames()
	for target in _targets:
		if is_instance_valid(target):
			target.queue_free()
	_targets.clear()
	for bolt in get_tree().get_nodes_in_group("player_bolts"):
		bolt.queue_free()
	await _frames(2)
	PlayerBolt.clear_pool()

func _reset() -> void:
	await _clear()
	TouchInput.reset()
	_player.teleport_to(_origin)
	_player.stats.equips = {}
	_player.stats.passives = {}
	_player.stats.strength = 5
	_player.stats.agility = 5
	_player.stats.intellect = 5
	_player.current_hp = 20.0
	_player.current_mp = 100.0
	_player._equipment_combo_cd = 0.0
	_player._equipment_focus_cd = 0.0
	_player._equipment_safe_wait = 0.0
	_player._attack_cooldown = 0.0
	_player._bolt_cd = 0.0
	_player._heavy_cd = 0.0
	_player._empower_timer = 0.0
	_player._hurt_iframes = 0.0
	_player._protect_timer = 0.0
	_player.facing = Vector2.RIGHT
	_player._guard_fresh_press_required = false
	_bursts.clear()
	_roots.clear()
	await _frames(2)

func _run() -> void:
	_player = PLAYER.instantiate()
	_player.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_player)
	_player.set_process(false)
	_player.get_node("Camera2D").enabled = false
	await _combo_contract()
	await _shield_contract()
	await _focus_contract()
	await _tradeoff_damage_contract()
	await _ineligible_target_contract()
	await _safe_change_contract()
	await _clear()
	_player.queue_free()
	await _frames(2)
	WorldSim.stop()
	print("=== EQUIPMENT COMBAT %s (%d checks) ===" % ["PASS" if _fails == 0 else "FAIL", _checks])
	get_tree().quit(0 if _fails == 0 else 1)

func _combo_contract() -> void:
	await _reset()
	_equip("combo", 1)
	_check(is_equal_approx(_player.stats.equip_mechanism("combo"), 0.6), "iLv1橙机制F=.6")
	var first := _monster(Vector2(47, -10))
	var second := _monster(Vector2(50, 12))
	await _frames(2)
	_player._combo = 2
	_player._combo_timer = 2.0
	var hp := _player.current_hp
	_player._try_attack()
	await _frames(20)
	_check(first.current_hp < 10000.0 and second.current_hp < 10000.0, "第三段真实扫掠同时命中两只活体")
	_check(is_equal_approx(_player.current_hp - hp, _player.stats.max_hp() * 0.006 * _player.stats.combo_output_mult()),
		"同一第三刀只按首个活体回复最大HP*.006并按新连击节奏归一")
	_check(_bursts.count("orange") == 1 and _bursts.count("hit") == 0,
		"一次根攻击仅一个主要橙色装备反馈")
	_check(_player._equipment_combo_cd > 1.5, "真实命中开启2秒游戏ICD")
	_player.stats.equips = {}
	_player.apply_loadout_change()
	var cd := _player._equipment_combo_cd
	_equip("combo", 10)
	_player.apply_loadout_change()
	_check(is_equal_approx(cd, _player._equipment_combo_cd), "脱下再穿保留橙装ICD")
	_player._attack_cooldown = 0.0
	_player._combo = 2
	_player._combo_timer = 2.0
	hp = _player.current_hp
	_player._try_attack()
	await _frames(20)
	_check(is_equal_approx(_player.current_hp, hp), "第二根第三刀在ICD内不回复")
	_check(is_equal_approx(_player.stats.heavy_damage_mult(), 0.9), "橙剑重击技能保留*.9代价")
	_player._equipment_combo_cd = 0.0
	_player._equipment_swing_checked = false
	_player._equipment_swing_f = 1.0
	_player._combo = 3
	_player._attack_timer = 0.2
	first.state = MonsterBase.S_CORPSE
	_player._on_attack_body_entered(first)
	_check(_player._equipment_combo_cd == 0.0 and _player.current_hp == hp,
		"尸体不能吃掉首个活体额度或制造回血")
	_player._attack_timer = 0.0

func _shield_contract() -> void:
	await _reset()
	_equip("shield", 10)
	_check(is_equal_approx(_player.stats.equipment_guard_counter_mult(1), 1.4)
		and is_equal_approx(_player.stats.equipment_guard_counter_mult(2), 1.8)
		and is_equal_approx(_player.stats.equipment_guard_counter_mult(3), 2.4),
		"橙盾只提高三层反击到2.2+.2F")
	_player.current_mp = 1000.0
	TouchInput.begin_guard()
	await _frames(8)
	var mp := _player.current_mp
	_player._tick_guard(1.0)
	_check(is_equal_approx(mp - _player.current_mp, 5.0), "橙盾真实持盾每秒5MP")
	for i in 3:
		_player.take_damage(10.0, _origin + Vector2(40, 0), "装备测试",
			{"strength": 10.0, "blockable": true, "incoming_direction": Vector2.RIGHT,
			"attack_id": "equipment-shield-%d" % i})
	_check(_player.guard_charge == 3 and _bursts.count("block") == 3, "三个有效独立格挡产生三层与三次真实格挡粒子事件")
	var target := _monster(Vector2(48, 0))
	await _frames(2)
	var hp := _player.current_hp
	TouchInput.release_guard()
	await _frames(22)
	var dealt := 10000.0 - target.current_hp
	var baseline := _player.stats.physical_attack() * 2.4
	_check(dealt >= baseline * 0.9 - 0.01 and dealt <= baseline * 1.1 + 0.01,
		"三层橙盾实际定向反击使用2.4倍率")
	_check(_player.current_hp == hp and _bursts.count("orange") == 1,
		"反击不触发普攻回血，仅有效命中发一次橙装粒子")
	await _reset()
	_equip("focus", 10)
	TouchInput.begin_guard()
	await _frames(8)
	_check(_player.guard_state == "guarding" and _player.stats.equipment_guard_drain_per_sec() == 4.0,
		"装备法器仍有基础物理盾，普通消耗4MP/s")
	TouchInput.cancel_guard()

func _focus_contract() -> void:
	await _reset()
	_equip("focus", 10)
	var target := _monster(Vector2(90, 0))
	await _frames(2)
	_player.current_mp = 20.0
	_player._try_cast_bolt()
	_check(is_equal_approx(_player.current_mp, 20.0 - CharacterStats.BOLT_COST), "法弹先实际支付蓝量")
	await _frames(24)
	_check(target.current_hp < 10000.0 and is_equal_approx(_player.current_mp, 21.0 - CharacterStats.BOLT_COST),
		"实际飞行主弹首次活体命中返1MP")
	_check(_roots.size() == 1 and _bursts.count("orange") == 1 and _bursts.count("hit") == 0,
		"主弹只结算一次根凭证及一组橙装粒子")
	_check(is_equal_approx(_player.stats.equipment_bolt_damage_mult(), 0.95), "法器保留法弹*.95代价")
	var mp := _player.current_mp
	EventBus.player_bolt_live_hit.emit(_roots[0], 999.0, 1.0, target.global_position)
	_check(_player.current_mp == mp, "已消费根事件重放不返蓝")
	_player._equipment_focus_cd = 0.0
	_player._equipment_pending_bolts["paid-quarter"] = {"f": 1.0, "paid": 0.25}
	EventBus.player_bolt_live_hit.emit("paid-quarter", 10.0, 1.0, target.global_position)
	_check(is_equal_approx(_player.current_mp - mp, 0.25), "返蓝同时受权威实际支付凭证上限限制")
	await _clear()
	_player._equipment_focus_cd = 0.0
	var shard_target := _monster(Vector2(90, 0))
	await _frames(2)
	mp = _player.current_mp
	var roots_before := _roots.size()
	var shard := PlayerBolt.spawn(self, _origin + Vector2(22, 0), Vector2.RIGHT, 10.0, "",
		{"root_id": "forged-shard", "paid_mp": 12.0, "focus_f": 1.0})
	shard._generation = 1
	_player._equipment_pending_bolts["forged-shard"] = {"f": 1.0, "paid": 12.0}
	await _frames(24)
	_check(shard_target.current_hp < 10000.0 and _roots.size() == roots_before and _player.current_mp == mp,
		"真实碎片碰撞造成伤害，但不能派发橙装根触发")
	await _clear()
	_player._bolt_cd = 0.0
	_player.current_mp = 20.0
	_player._try_cast_bolt()
	_check(not _player.can_change_loadout(), "仍在飞行的玩家主弹立即阻止换装")
	await _frames(105)
	_check(_player.current_mp == 20.0 - CharacterStats.BOLT_COST, "打空主弹不返蓝")

func _tradeoff_damage_contract() -> void:
	await _reset()
	var target := _monster(Vector2(48, 0))
	await _frames(2)
	seed(431)
	_player._try_heavy_attack()
	await _frames(36)
	var plain := 10000.0 - target.current_hp
	target.current_hp = 10000.0
	_equip("combo", 10)
	_player._heavy_cd = 0.0
	_player.current_mp = 100.0
	seed(431)
	_player._try_heavy_attack()
	await _frames(36)
	var orange := 10000.0 - target.current_hp
	_check(absf(orange / plain - 0.9) < 0.001, "真实重击伤害保留橙剑*.9，而非仅面板显示")
	_check(_player._equipment_combo_cd == 0.0, "重击技能不会借三连橙剑制造回血触发")
	await _clear()
	_player.stats.equips = {}
	_player.stats.passives = {"bolt_split": 1, "bolt_seek": 1}
	_player._bolt_cd = 0.0
	_player.current_mp = 100.0
	seed(877)
	_player._try_cast_bolt()
	await _frames(11)
	var plain_bolt := get_tree().get_first_node_in_group("player_bolts") as PlayerBolt
	var plain_main := plain_bolt.damage
	var plain_shard := plain_bolt._split_damage
	_check(plain_bolt._seek and plain_bolt._split
		and is_equal_approx(plain_bolt._speed, PlayerBolt.SPEED * CharacterStats.BOLT_SEEK_SPEED),
		"寻星减速/碎星主弹代价同时保留")
	await _clear()
	_equip("focus", 10)
	_player._bolt_cd = 0.0
	_player.current_mp = 100.0
	seed(877)
	_player._try_cast_bolt()
	await _frames(11)
	var focus_bolt := get_tree().get_first_node_in_group("player_bolts") as PlayerBolt
	_check(is_equal_approx(focus_bolt.damage / plain_main, 0.95)
		and is_equal_approx(focus_bolt._split_damage / plain_shard, 0.95),
		"实际主弹及其伤害来源快照都乘*.95，没有重复乘碎星代价")
	_check(focus_bolt._seek and focus_bolt._split, "法器没有替换既有寻星/碎星玩法")
	await _clear()


func _ineligible_target_contract() -> void:
	await _reset()
	_equip("combo", 10)
	var nest := NestProbe.new()
	nest.add_to_group("nests")
	nest.collision_layer = 4
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 12.0
	shape.shape = circle
	nest.add_child(shape)
	add_child(nest)
	nest.global_position = _origin + Vector2(48, 0)
	await _frames(2)
	var hp := _player.current_hp
	_player._combo = 2
	_player._combo_timer = 2.0
	_player._try_attack()
	await _frames(22)
	_check(nest.hp < 1000.0 and _player.current_hp == hp and _player._equipment_combo_cd == 0.0,
		"第三刀实际命中巢穴型碰撞体无橙剑回血/ICD")
	_equip("focus", 10)
	_player.current_mp = 20.0
	_player._bolt_cd = 0.0
	var nest_hp := nest.hp
	_player._try_cast_bolt()
	await _frames(22)
	_check(nest.hp < nest_hp and _player.current_mp == 20.0 - CharacterStats.BOLT_COST
		and _player._equipment_focus_cd == 0.0, "主弹实际命中巢穴型碰撞体无返蓝/ICD")
	nest.remove_from_group("nests")
	nest.collision_layer = 1
	_player._bolt_cd = 0.0
	_player.current_mp = 20.0
	_player._try_cast_bolt()
	await _frames(22)
	_check(_player.current_mp == 20.0 - CharacterStats.BOLT_COST and _player._equipment_focus_cd == 0.0,
		"主弹实际撞静态障碍无返蓝/ICD")
	nest.queue_free()
	await _frames(2)


func _safe_change_contract() -> void:
	await _reset()
	_player._equipment_safe_wait = 0.0
	_check(_player.can_change_loadout(), "安静且没有动作时可换装")
	_player._try_attack()
	_check(not _player.can_change_loadout() and _player._equipment_safe_wait == 5.0,
		"攻击起手设置5秒游戏脱战锁")
	var remaining := _player._equipment_safe_wait
	_player._equipment_combo_cd = 1.2
	_player._equipment_focus_cd = 0.7
	get_tree().paused = true
	await get_tree().create_timer(0.12, true).timeout
	_check(is_equal_approx(remaining, _player._equipment_safe_wait)
		and _player._equipment_combo_cd == 1.2 and _player._equipment_focus_cd == 0.7,
		"打开暂停背包的真实时间不推进脱战及橙装ICD计时")
	get_tree().paused = false
	await _frames(24)
	_player._tick_equipment_combat(4.1)
	_check(not _player.can_change_loadout(), "累计不足5游戏秒仍锁定")
	_player._tick_equipment_combat(0.6)
	_check(_player.can_change_loadout(), "满5游戏秒且无未结算动作解除锁定")
	var enemy := _monster(Vector2(120, 0))
	enemy._player_ref = _player
	enemy.state = MonsterBase.S_CHASE
	_check(not _player.can_change_loadout(), "实际活体追击立即阻止换装")
	_player._tick_equipment_combat(0.1)
	enemy.state = MonsterBase.S_PATROL
	_check(not _player.can_change_loadout() and _player._equipment_safe_wait == 5.0,
		"追击结束仍须完整5秒而不是立刻换装")
	await _clear()
	_player._equipment_combo_cd = 1.2
	_player._equipment_focus_cd = 0.7
	_player._equipment_safe_wait = 3.8
	_player._empower_timer = 2.4
	_player._heavy_cd = 3.3
	_player.current_hp = 23.0
	_player.current_mp = 17.0
	_player.stats.strength = 15
	_player.stats.intellect = 15
	_player.apply_loadout_change()
	_check(_player.current_hp == 23.0 and _player.current_mp == 17.0,
		"换高上限装备不补血蓝也不按比例提升")
	_check(_player._equipment_combo_cd == 1.2 and _player._equipment_focus_cd == 0.7
		and _player._heavy_cd == 3.3 and _player._empower_timer == 2.4,
		"换装不刷新橙装CD、技能CD或既有增益")
	var snapshot := _player.save_snapshot()
	_player._equipment_combo_cd = 0.0
	_player._equipment_focus_cd = 0.0
	_player._equipment_safe_wait = 0.0
	_player._restore_combat_timers(snapshot.combat_timers)
	_check(is_equal_approx(_player._equipment_combo_cd, 1.2)
		and is_equal_approx(_player._equipment_focus_cd, 0.7)
		and is_equal_approx(_player._equipment_safe_wait, 3.8), "快照读写保留两项橙装CD和脱战剩余游戏时间")
	_player.current_hp = 10000.0
	_player.current_mp = 10000.0
	_player.stats.strength = 5
	_player.stats.intellect = 5
	_player.apply_loadout_change()
	_check(_player.current_hp == _player.stats.max_hp() and _player.current_mp == _player.stats.max_mp(),
		"换低上限装备仅钳制溢出资源")
