## 攻击双通道与真实 Boss/宝箱：封印不吞刀，解封开箱仍一次扣钥匙领奖。
extends Node2D

const World := preload("res://scripts/main/game_world.gd")
const ORIGIN := Vector2(120000, 120000)
var _player: Player
var _boss: MonsterBase
var _chest: Node2D
var _checks := 0
var _fails := 0
var _claims := 0
var _last_hint := ""

func _ready() -> void:
	GameState.save_enabled = false
	GameState.reset_all()
	WorldSim.stop()
	WorldSim.sim = EcologySim.new()
	BiomeMap.configure(BiomeMap.DEFAULT_SEED)
	GameState.settings.auto_aim = false
	GameState.settings.screen_shake = false
	TouchInput.reset()
	EventBus.hint_requested.connect(func(text: String) -> void: _last_hint = text)
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok: _fails += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])

func _frames(count := 1) -> void:
	for _i in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func _attack(touch: bool) -> void:
	if touch:
		TouchInput.queue_attack()
	else:
		Input.action_press("attack")
	await _frames(1)
	if not touch: Input.action_release("attack")
	await _frames(23)

func _refresh(chest: Node) -> void:
	chest.locked = _boss.inst.is_alive
	chest.taken = _claims > 0

func _claim() -> void:
	_claims += 1

func _run() -> void:
	_player = preload("res://scenes/player/player.tscn").instantiate()
	add_child(_player)
	_player.get_node("Camera2D").enabled = false
	_player.set_process(false)
	_player.global_position = ORIGIN
	_boss = preload("res://scenes/monsters/ant.tscn").instantiate()
	add_child(_boss)
	_boss.set_physics_process(false)
	var inst := MonsterInstance.new()
	inst.id = 1
	inst.species = load("res://data/species/stag_beetle_king.tres")
	inst.age = 200
	inst.lifespan = 100000
	inst.size_scale = 2.2
	inst.spawn_pos = ORIGIN + Vector2(43, 0)
	WorldSim.sim.instances[inst.id] = inst
	_boss.setup(inst)
	_boss._nav.avoidance_enabled = false
	WorldSim.sim.instance_died.connect(func(dead: MonsterInstance, _cause: String) -> void:
		if dead == inst: _boss.on_sim_death())
	_chest = World.DungeonChest.new()
	_chest.boss_name = inst.species.species_name
	_chest.key_id = EconomyMath.KEY_SILVER
	_chest.refresh_state = _refresh
	_chest.notify_taken = _claim
	add_child(_chest)
	for touch in [false, true]:
		for direction in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
			_player.teleport_to(ORIGIN)
			_player.global_position = ORIGIN # 独立物理夹具，不由噪声障碍重定向。
			_player.facing = direction
			_player._attack_cooldown = 0
			_boss.global_position = ORIGIN + direction * 43
			_boss._knockback = Vector2.ZERO
			_boss.current_hp = inst.max_hp()
			_chest.global_position = ORIGIN - direction * 50
			await _frames(2)
			_check(_player._nearest_npc() == null, "封印箱不是攻击交互候选 %s %s" % [touch, direction])
			var hp := _boss.current_hp
			await _attack(touch)
			_check(_boss.current_hp < hp and _player._combo > 0,
				"%s真实扫掠命中Boss，43px目标/50px封印箱 %s" % ["触屏" if touch else "键盘", direction])
			_check(_claims == 0, "战斗输入不会领取封印箱")
	# 玩家攻击前查询可即时刷新刚倒下的 Boss，无须等0.5秒世界流式节拍。
	WorldSim.sim.report_killed(inst.id)
	_player._attack_cooldown = 0
	_chest.global_position = _player.global_position + Vector2(50, 0)
	await _attack(true)
	_check(not _chest.locked and not _chest.taken and _claims == 0 and "需要" in _last_hint,
		"刚击败Boss即进入缺钥匙交互，不挥刀也不领奖")
	GameState.add_item(EconomyMath.KEY_SILVER, 2)
	var before := GameState.gold
	await _attack(true)
	_check(_claims == 1 and _chest.taken and GameState.gold > before
		and GameState.count_item(EconomyMath.KEY_SILVER) == 1, "解封宝箱实际攻击交互一次扣钥匙领奖")
	before = GameState.gold
	await _attack(false)
	_check(_claims == 1 and GameState.gold == before and GameState.count_item(EconomyMath.KEY_SILVER) == 1,
		"重复按攻击不会再次扣钥匙/领奖")
	# 重生后旧解封表现必须立即锁回，不依赖上一帧的 locked 标记。
	inst.is_alive = true # 只构造重生已发生而表现尚未刷新这个边界。
	_claims = 0
	_chest.taken = false
	_chest.visible = true
	_chest.locked = false
	_check(_player._nearest_npc() == null and _chest.locked, "Boss重生后的旧解封画面不抢攻击")
	Input.action_release("attack")
	TouchInput.reset()
	WorldSim.stop()
	print("=== CHEST ATTACK PRIORITY %s (%d checks) ===" % ["PASS" if _fails == 0 else "FAIL", _checks])
	get_tree().quit(0 if _fails == 0 else 1)
