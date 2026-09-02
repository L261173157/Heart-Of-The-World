## 战斗与表现层自动化验证（作为普通场景运行，加载真实主场景）。
## 运行："$GODOT" --headless --path Code res://tests/combat_test.tscn --quit-after 30000
## 驱动玩家逐物种猎杀，验证：击杀奖励入账、史莱姆击杀分裂出子代、
## 雪蝎弹幕出现、野猪冲锋/岩甲龟蓄力状态触发、玩家确实受到伤害。
## 全部通过 quit(0)，否则 quit(1)。
extends Node2D

const MAIN_SCENE := preload("res://scenes/main/main.tscn")

const TARGET_ORDER := ["哥布林", "史莱姆", "野猪", "雪蝎", "兵蚁", "岩甲龟"]
const STEP_INTERVAL := 0.12
const TIME_LIMIT := 150.0

var _sim: EcologySim
var _player: Player
var _world: Node2D
var _fails := 0
var _kills := {}
var _queue_index := 0
var _species_tries := 0
var _timer := 0.0
var _elapsed := 0.0
var _min_hp_ratio := 1.0
var _saw_projectile := false
var _saw_custom_states := {}
var _dash_verified := false
var _dash_fails := 0
var _heavy_verified := false
var _heavy_fails := 0
var _bolt_verified := false
var _bolt_fails := 0
## 法弹命中异步校验：靶怪与发射前血量（collision_mask 漏配曾致法弹永不命中，此处锁回归）
var _bolt_target: MonsterBase
var _bolt_hp_before := 0.0
var _bolt_check_timer := -1.0
var _heal_verified := false
var _heal_fails := 0
var _combo_verified := false
var _combo_fails := 0
var _saw_bounty := false


## 冲刺技能验证：MP 消耗 + 位移窗口 + 无敌帧 + 冷却拦截
func _verify_dash() -> void:
	_player.current_mp = _player.stats.max_mp()
	var mp_before: float = _player.current_mp
	_player._try_dash()
	if not (_player._dash_timer > 0.0):
		_dash_fails += 1
		print("  FAIL  冲刺未进入位移窗口")
	elif not (_player.current_mp < mp_before):
		_dash_fails += 1
		print("  FAIL  冲刺未消耗 MP")
	var hp_before: float = _player.current_hp
	_player.take_damage(50.0)
	if not is_equal_approx(_player.current_hp, hp_before):
		_dash_fails += 1
		print("  FAIL  冲刺无敌帧未生效")
	_player._dash_timer = 0.0
	var mp_second: float = _player.current_mp
	_player._try_dash()
	if _player.current_mp < mp_second:
		_dash_fails += 1
		print("  FAIL  冷却未拦截连续冲刺")
	_dash_verified = true
	if _dash_fails == 0:
		print("  PASS  冲刺技能（MP 消耗/无敌帧/冷却拦截）")


## 重击技能验证：MP 消耗 + 冷却进入 + 冷却拦截（伤害闭环由击杀统计间接覆盖）
func _verify_heavy() -> void:
	_player.current_mp = _player.stats.max_mp()
	var mp_before: float = _player.current_mp
	_player._try_heavy_attack()
	if not (_player.current_mp < mp_before):
		_heavy_fails += 1
		print("  FAIL  重击未消耗 MP")
	if not (_player._heavy_cd > 0.0):
		_heavy_fails += 1
		print("  FAIL  重击未进入冷却")
	var mp_second: float = _player.current_mp
	_player._try_heavy_attack()
	if _player.current_mp < mp_second:
		_heavy_fails += 1
		print("  FAIL  冷却未拦截连续重击")
	_heavy_verified = true
	if _heavy_fails == 0:
		print("  PASS  重击技能（MP 消耗/冷却拦截）")


## 法弹验证：MP 消耗 + 冷却拦截 + PlayerBolt 弹体确实生成
func _verify_bolt() -> void:
	_player.current_mp = _player.stats.max_mp()
	var mp_before: float = _player.current_mp
	var bolts_before := get_tree().get_nodes_in_group("player_bolts").size()
	_player._try_cast_bolt()
	if not (_player.current_mp < mp_before):
		_bolt_fails += 1
		print("  FAIL  法弹未消耗 MP")
	if not (_player._bolt_cd > 0.0):
		_bolt_fails += 1
		print("  FAIL  法弹未进入冷却")
	var mp_second: float = _player.current_mp
	_player._try_cast_bolt()
	if _player.current_mp < mp_second:
		_bolt_fails += 1
		print("  FAIL  冷却未拦截连续法弹")
	var bolts_after := get_tree().get_nodes_in_group("player_bolts").size()
	if bolts_after <= bolts_before:
		_bolt_fails += 1
		print("  FAIL  法弹弹体未生成")
	# 命中验证：贴脸对准靶怪补射一发（弹体出生即与其碰撞体重叠，规避走位抖动），稍后校验掉血
	var target := _find_alive_any()
	if target == null:
		_bolt_fails += 1
		print("  FAIL  场上无活体可验证法弹命中")
	else:
		var dir := (target.global_position - _player.global_position).normalized()
		if dir == Vector2.ZERO:
			dir = Vector2.RIGHT
		_player.global_position = target.global_position - dir * 30.0
		_player.facing = dir
		_player._bolt_cd = 0.0
		_player.current_mp = _player.stats.max_mp()
		_bolt_hp_before = target.current_hp
		_player._try_cast_bolt()
		_bolt_target = target
		_bolt_check_timer = 0.0
	_bolt_verified = true
	if _bolt_fails == 0:
		print("  PASS  法弹技能（MP 消耗/冷却拦截/弹体生成；命中判定稍后输出）")


## 治疗验证：MP 消耗 + 回血量与智力挂钩 + 冷却拦截
func _verify_heal() -> void:
	_player.current_mp = _player.stats.max_mp()
	_player.current_hp = _player.stats.max_hp() * 0.5
	var hp_before: float = _player.current_hp
	var mp_before: float = _player.current_mp
	_player._try_heal()
	if not (_player.current_mp < mp_before):
		_heal_fails += 1
		print("  FAIL  治疗未消耗 MP")
	if not (_player.current_hp > hp_before):
		_heal_fails += 1
		print("  FAIL  治疗未回血")
	var mp_second: float = _player.current_mp
	_player.current_hp = _player.stats.max_hp() * 0.5
	_player._try_heal()
	if _player.current_mp < mp_second:
		_heal_fails += 1
		print("  FAIL  冷却未拦截连续治疗")
	_heal_verified = true
	if _heal_fails == 0:
		print("  PASS  治疗技能（MP 消耗/回血/冷却拦截）")


## 连击与朝向吸附：三段循环计数 + 攻击朝扇形内最近怪修正
func _verify_combo() -> void:
	# 三段连击循环：1 → 2 → 0
	_player._combo = 0
	for expected in [1, 2, 0]:
		_player._attack_cooldown = 0.0
		_player._combo_timer = 1.0
		_player._try_attack()
		if _player._combo != expected:
			_combo_fails += 1
			print("  FAIL  连击计数未按 1→2→0 循环（期望 %d，实际 %d）" % [expected, _player._combo])
	# 朝向吸附：把玩家放到最近怪旁边，朝向偏 40°（仍在 ±60° 扇形内），攻击应吸回目标
	var target := _find_alive_any()
	if target == null:
		_combo_fails += 1
		print("  FAIL  场上无活体可验证吸附")
	else:
		var to_target := (target.global_position - _player.global_position).normalized()
		if to_target == Vector2.ZERO:
			to_target = Vector2.RIGHT
		_player.facing = to_target.rotated(deg_to_rad(40.0))
		_player._attack_cooldown = 0.0
		_player._combo_timer = 1.0
		_player._try_attack()
		if _player.facing.angle_to(to_target) >= deg_to_rad(5.0):
			_combo_fails += 1
			print("  FAIL  扇形内攻击未吸附到目标朝向")
	if _combo_fails == 0:
		print("  PASS  三段连击循环与朝向吸附")


func _find_alive_any() -> MonsterBase:
	for body in get_tree().get_nodes_in_group("monsters"):
		var monster := body as MonsterBase
		if monster != null and monster.inst != null and monster.state != MonsterBase.S_CORPSE:
			return monster
	return null


func _ready() -> void:
	_world = MAIN_SCENE.instantiate()
	add_child(_world)
	await get_tree().process_frame
	await get_tree().process_frame
	_sim = WorldSim.sim
	_player = get_tree().get_first_node_in_group("player")
	if _player == null:
		_fail("找不到玩家节点")
		_finish()
		return
	# 测试加速：大幅提高输出，缩短逐物种猎杀时间；关闭自动存档避免污染真实进度
	GameState.save_enabled = false
	GameState.stats.strength = 50
	EventBus.monster_killed_by_player.connect(_on_kill)
	EventBus.bounty_updated.connect(func(_text: String) -> void: _saw_bounty = true)


func _process(delta: float) -> void:
	if _player == null:
		return
	_elapsed += delta
	# 法弹命中异步校验：贴脸发射几乎瞬间命中，0.35s 余量足够
	if _bolt_check_timer >= 0.0:
		_bolt_check_timer += delta
		if _bolt_check_timer >= 0.35:
			var hit: bool = _bolt_target == null or not is_instance_valid(_bolt_target) \
					or _bolt_target.current_hp < _bolt_hp_before
			if hit:
				print("  PASS  法弹命中靶怪并造成伤害")
			else:
				_bolt_fails += 1
				print("  FAIL  法弹未对靶怪造成伤害（检查 PlayerBolt collision_mask）")
			_bolt_check_timer = -1.0
			_bolt_target = null
	# 记录承伤后立刻回满：验证战斗闭环但不让死亡干扰流程
	_min_hp_ratio = minf(_min_hp_ratio, _player.current_hp / _player.stats.max_hp())
	_player.current_hp = _player.stats.max_hp()
	_scan_special_states()
	_timer -= delta
	if _timer <= 0.0:
		_timer = STEP_INTERVAL
		_step()
	if _elapsed >= TIME_LIMIT or _queue_index >= TARGET_ORDER.size():
		_finish()


func _step() -> void:
	if _queue_index >= TARGET_ORDER.size():
		return
	if not _dash_verified:
		_verify_dash()
		return
	if not _heavy_verified:
		_verify_heavy()
		return
	if not _bolt_verified:
		_verify_bolt()
		return
	if not _heal_verified:
		_verify_heal()
		return
	if not _combo_verified:
		_verify_combo()
		_combo_verified = true
		return
	var species_name: String = TARGET_ORDER[_queue_index]
	var target := _find_alive(species_name)
	if target == null:
		_species_tries += 1
		if _species_tries > 80:
			# 全图找不到活体：若此前已击杀过则视为通过（种群可能被顺带清空）
			if _kills.get(species_name, 0) > 0:
				print("  PASS  %s 已击杀（顺带清空，跳过）" % species_name)
				_advance()
			else:
				_fail("找不到 %s 活体，无法验证" % species_name)
				_advance()
		return
	_species_tries = 0
	var dir := (target.global_position - _player.global_position).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	# 雪蝎：先在射程内观察吐息（远程机制验证），再上前击杀
	if species_name == "雪蝎" and not _saw_projectile and _elapsed < TIME_LIMIT - 30.0:
		_player.global_position = target.global_position - dir * 170.0
		_player.facing = dir
		return
	_player.global_position = target.global_position - dir * 20.0
	_player.facing = dir
	_player._try_attack()


func _find_alive(species_name: String) -> MonsterBase:
	var best: MonsterBase = null
	var best_dist := INF
	for body in get_tree().get_nodes_in_group("monsters"):
		var monster := body as MonsterBase
		if monster == null or monster.inst == null or monster.state == MonsterBase.S_CORPSE:
			continue
		if monster.inst.species.species_name != species_name:
			continue
		var dist := _player.global_position.distance_to(monster.global_position)
		if dist < best_dist:
			best = monster
			best_dist = dist
	return best


## 扫描特殊机制状态：弹幕节点存在、野猪冲锋/蓄力、岩甲龟蓄力
func _scan_special_states() -> void:
	if not _saw_projectile:
		for child in _world.get_node("Monsters").get_children():
			if child is Projectile:
				_saw_projectile = true
				break
	for body in get_tree().get_nodes_in_group("monsters"):
		var monster := body as MonsterBase
		if monster == null or monster.inst == null:
			continue
		if monster.state >= 10:
			_saw_custom_states[monster.inst.species.species_name] = monster.state


func _on_kill(xp_reward: int, _gold: int, monster_name: String) -> void:
	var species_name := monster_name.get_slice("#", 0)
	_kills[species_name] = _kills.get(species_name, 0) + 1
	if xp_reward <= 0:
		_fail("%s 击杀经验非正数" % species_name)
	if _queue_index < TARGET_ORDER.size() and species_name == TARGET_ORDER[_queue_index]:
		# 击杀信号发出时分裂尚未发生（report_killed 在信号之后执行），延迟一帧验证
		_verify_species.call_deferred(species_name)
		_advance()


func _verify_species(species_name: String) -> void:
	print("  PASS  击杀 %s（+经验入账）" % species_name)
	if species_name == "史莱姆":
		# 击杀后生态层应裂出第 1 代子代
		var has_child := false
		for inst: MonsterInstance in _sim.instances.values():
			if inst.species.species_name == "史莱姆" and inst.is_alive and inst.generation > 0:
				has_child = true
				break
		if has_child:
			print("  PASS  史莱姆被击杀后裂出子代（表现层收到生成事件）")
		else:
			_fail("史莱姆击杀后未见分裂子代")


func _advance() -> void:
	_queue_index += 1
	_species_tries = 0


func _finish() -> void:
	set_process(false)
	print("\n=== 战斗验证汇总（%.0fs） ===" % _elapsed)
	_check(_kills.size() >= 6, "六物种全部被击杀（%s）" % str(_kills.keys()))
	_check(GameState.stats.xp > 0 or GameState.gold > 0, "击杀奖励已入账（xp=%d gold=%d）" % [GameState.stats.xp, GameState.gold])
	_check(_min_hp_ratio < 0.999, "玩家确实承伤（最低血量比例 %.2f）" % _min_hp_ratio)
	_check(_dash_fails == 0, "冲刺技能行为正确")
	_check(_heavy_fails == 0, "重击技能行为正确")
	_check(_bolt_fails == 0, "法弹技能行为正确")
	_check(_heal_fails == 0, "治疗技能行为正确")
	_check(_combo_fails == 0, "三段连击与朝向吸附行为正确")
	_check(_saw_bounty, "赏金任务已生成")
	_check(_saw_projectile, "雪蝎弹幕出现过")
	_check(_saw_custom_states.has("野猪"), "野猪进入过冲锋前摇/冲锋状态")
	_check(_saw_custom_states.has("岩甲龟"), "岩甲龟进入过蓄力重击状态")
	if _fails == 0:
		print("=== 战斗验证全部通过 ===")
		get_tree().quit(0)
	else:
		print("=== %d 项失败 ===" % _fails)
		get_tree().quit(1)


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  PASS  %s" % msg)
	else:
		_fails += 1
		print("  FAIL  %s" % msg)


func _fail(msg: String) -> void:
	_fails += 1
	print("  FAIL  %s" % msg)
