## 固定战斗/经济基准：10张一分钟卡，每卡正式平原3:3:1:1:1阵容，共90普通演员。
## 官方AI/碰撞/攻击/死亡/入包持续运行600游戏秒；夹具没有自然出生/捕食/老死。
## 自然生态另跑600tick参考，不能冒充玩家猎杀下的开放世界生态或旅行经济验证。
## -- --free-roam 保留真实开放世界诊断，不对任意游猎宣称70件上限。
extends Node2D

const MAIN_SCENE := preload("res://scenes/main/main.tscn")
const ARENA_WORLD := preload("res://tests/pacing_arena_world.gd")
const WORLD_SCRIPT := preload("res://scripts/main/game_world.gd")
const GAME_SECONDS := 600.0
const PACING_SEED := 20260908
const ENCOUNTER_ROSTER: Array[String] = [
	"火把哥布林", "火把哥布林", "火把哥布林",
	"地精矿工", "地精矿工", "地精矿工", "突袭蛇", "青甲龟", "山猪",
]
const ENCOUNTER_CARDS := 10
const CARD_SECONDS := 60.0
const MIN_COMPLETE_ROSTERS := 3
const STEP_INTERVAL := 0.25
const IDLE_CHANCE := 0.08
const TIME_SCALE := 4.0
const TARGET_RADIUS := 700.0
const DEATH_IDLE := 8.0
const GOLD_THRESHOLDS := [50, 140, 270, 440, 650]

var _player: Player
var _world: Node2D
var _reference_sim: EcologySim
var _fails := 0
var _game_time := 0.0
var _timer := 0.0
var _kills := 0
var _deaths := 0
var _level_marks := {}
var _gold_marks := {}
var _threshold_index := 0
var _dead_until := -1.0
var _min_hp_ratio := 1.0
var _starting_hp_ratio := 0.0
var _starting_mp_ratio := 0.0
var _hurt_events := 0
var _alive_window: Array[int] = []
var _patrol_target := Vector2.INF
var _patrol_retarget := 0.0
var _reward_ids := {}
var _reward_species := {}
var _expected_materials := {}
var _gained_items := {}
var _elite_kills := 0
var _boss_kills := 0
var _duplicate_rewards := 0
var _robot_rng := RandomNumberGenerator.new()
var _roster_kills := 0
var _incidental_kills := 0
var _free_roam := false
var _cards_started := 0
var _fixture_card_by_id := {}
var _reported_rosters := 0
var _encounter_target_id := -1
var _encounter_admissions := 0
var _encounter_unavailable := false
var _stage_ready_physics_frame := 0
var _transport_integrity := true
var _transports := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_free_roam = "--free-roam" in OS.get_cmdline_user_args()
	Engine.time_scale = TIME_SCALE
	GameState.SAVE_PATH = "user://pacing_test.json"
	GameState.save_enabled = false
	seed(PACING_SEED)
	_robot_rng.seed = PACING_SEED
	GameState.reset_all()
	GameState.world_seed = PACING_SEED
	BiomeMap.configure(PACING_SEED)
	GameState.exploration = ExplorationFog.new(PACING_SEED)
	# 在创建真实玩家之前设置属性；旧顺序会把160HP/244上限误当成战斗压力。
	_prepare_starting_stats()
	var roster_counts := {}
	for species: String in ENCOUNTER_ROSTER:
		roster_counts[species] = int(roster_counts.get(species, 0)) + 1
	_check(roster_counts == WorldConfig.TERRAIN_POPULATION["plains"], "声明阵容精确覆盖出生平原3:3:1:1:1")
	EventBus.item_gained.connect(_on_item_gained)
	EventBus.damage_number.connect(func(_pos: Vector2, amount: int, hurt: bool, _effective: bool) -> void:
		if hurt and amount > 0: _hurt_events += 1)
	if _free_roam:
		_world = MAIN_SCENE.instantiate()
		add_child(_world)
		_world.hit_stop_enabled = false
		EventBus.sim_tick_completed.connect(_on_summary)
		await get_tree().process_frame
		await get_tree().process_frame
	else:
		_reference_sim = EcologySim.new()
		var builder := WORLD_SCRIPT.new()
		_reference_sim.setup(builder._build_regions(), SpeciesCatalog.build_all(), WorldConfig.initial_population(), WorldConfig.boss_anchors())
		builder.free()
		_reference_sim.tick_completed.connect(_on_summary)
		_world = ARENA_WORLD.new()
		add_child(_world)
		await _world.wait_until_ready()
	_player = get_tree().get_first_node_in_group("player") as Player
	_capture_starting_resources()
	WorldSim.sim.instance_died.connect(_on_sim_death)
	GameState.stats.leveled_up.connect(_on_level_up)
	EventBus.monster_killed_by_player.connect(_on_kill)
	EventBus.player_died.connect(func() -> void: _deaths += 1)
	print("PACING_SCENARIO ", "free_roam_diagnostic" if _free_roam else "finite_plains_cards", " seed=", PACING_SEED)


func _prepare_starting_stats() -> void:
	GameState.stats.strength = 12
	GameState.stats.agility = 6
	GameState.stats.intellect = 6


func _capture_starting_resources() -> void:
	_starting_hp_ratio = _player.current_hp / _player.stats.max_hp()
	_starting_mp_ratio = _player.current_mp / _player.stats.max_mp()
	_check(is_equal_approx(_starting_hp_ratio, 1.0) and is_equal_approx(_starting_mp_ratio, 1.0),
		"属性设定后真实玩家满血满蓝开始，不用低初始血线冒充压力")


func _on_summary(summary: Dictionary) -> void:
	_alive_window.append(int(summary.get("total_alive", 0)))
	if _alive_window.size() > 60: _alive_window.remove_at(0)


func _advance_reference(delta: float) -> void:
	WorldSim._advance_day(delta)
	var target_ticks := int(floor(_game_time + 0.000001))
	while _reference_sim.tick_count < target_ticks:
		_reference_sim.tick()


func _process(delta: float) -> void:
	if _player == null: return
	if get_tree().paused:
		var hud := _world.get_node_or_null("HUD")
		if hud != null and hud.passive_layer.visible: hud._pick_passive(0)
		return
	var step := minf(delta, GAME_SECONDS - _game_time)
	_game_time += step
	if not _free_roam: _advance_reference(step)
	if _game_time >= GAME_SECONDS:
		_finish()
		return
	if not _free_roam: _spawn_due_cards()
	_track_gold()
	_min_hp_ratio = minf(_min_hp_ratio, _player.current_hp / _player.stats.max_hp())
	if _game_time < _dead_until: return
	if _player._is_dead:
		_dead_until = _game_time + DEATH_IDLE
		return
	_timer -= step
	if _timer <= 0.0:
		_timer = STEP_INTERVAL
		_robot_step()


func _available_encounter_slots() -> int:
	return mini(ENCOUNTER_CARDS, int(_game_time / CARD_SECONDS) + 1) * ENCOUNTER_ROSTER.size()


func _spawn_due_cards() -> void:
	if _game_time >= GAME_SECONDS or _encounter_unavailable: return
	var due := _available_encounter_slots() / ENCOUNTER_ROSTER.size()
	while _cards_started < due:
		var card := _cards_started
		if not _world.spawn_card(card):
			_fail_encounter("有限卡片生成失败，不能替换或补演员")
			return
		var ids: Array = _world.card_ids[card]
		if ids.size() != ENCOUNTER_ROSTER.size():
			_fail_encounter("卡片必须完整包含预声明九个演员")
			return
		for slot in ids.size():
			var id := int(ids[slot])
			var inst: MonsterInstance = WorldSim.sim.instances.get(id)
			if _fixture_card_by_id.has(id) or inst == null or inst.species.species_name != ENCOUNTER_ROSTER[slot] or inst.is_elite:
				_fail_encounter("卡片ID/普通物种与声明不一致")
				return
			_fixture_card_by_id[id] = card
		_encounter_admissions += ids.size()
		_cards_started += 1
		print("PACING_CARD card=", _cards_started, " actor_total=", _encounter_admissions, " time=", _game_time)


func _completed_rosters() -> int:
	if _world == null or _free_roam: return 0
	var count := 0
	for card in _cards_started:
		var ids: Array = _world.card_ids[card]
		var complete := ids.size() == ENCOUNTER_ROSTER.size()
		for id in ids: complete = complete and _reward_ids.has(int(id))
		if complete: count += 1
	return count


func _choose_encounter_instance() -> MonsterInstance:
	if _world == null or WorldSim.sim == null: return null
	for card in _cards_started:
		for value in _world.card_ids[card]:
			var id := int(value)
			if _reward_ids.has(id): continue
			var inst: MonsterInstance = WorldSim.sim.instances.get(id)
			if inst == null or not inst.is_alive:
				_fail_encounter("声明演员未经玩家击杀便丢失，不补位")
				return null
			return inst
	return null


func _requested_species() -> String:
	var inst := _choose_encounter_instance()
	return inst.species.species_name if inst != null else ""


func _nearest_monster() -> MonsterBase:
	if not _free_roam:
		var inst := _choose_encounter_instance()
		if inst == null: return null
		var body: Variant = _world._nodes.get(inst.id)
		if not is_instance_valid(body) or not body is MonsterBase:
			_fail_encounter("真实注册场景演员丢失，不用辅助函数发奖")
			return null
		_encounter_target_id = inst.id
		return body as MonsterBase
	var best: MonsterBase = null
	var best_distance := INF
	for node in get_tree().get_nodes_in_group("monsters"):
		var body := node as MonsterBase
		if body == null or body.inst == null or body.state == MonsterBase.S_CORPSE: continue
		var distance := _player.global_position.distance_to(body.global_position)
		if distance < best_distance and distance <= TARGET_RADIUS:
			best = body
			best_distance = distance
	return best


func _robot_step() -> void:
	if _robot_rng.randf() < IDLE_CHANCE or _encounter_unavailable: return
	if Engine.get_physics_frames() < _stage_ready_physics_frame: return
	var target := _nearest_monster()
	if target == null:
		if _free_roam: _patrol()
		return
	var distance := _player.global_position.distance_to(target.global_position)
	var direction := (target.global_position - _player.global_position).normalized()
	if direction == Vector2.ZERO: direction = Vector2.RIGHT
	_player.facing = direction
	if _player.current_hp < _player.stats.max_hp() * 0.6: _player._try_heal()
	if _count_nearby(120.0) >= 3: _player._try_heavy_attack()
	if not is_instance_valid(target) or not target.inst.is_alive: return
	if distance > 100.0 and distance < 300.0: _player._try_cast_bolt()
	if distance > 24.0:
		if _transport_for_encounter(target.global_position - direction * 22.0):
			_stage_ready_physics_frame = Engine.get_physics_frames() + 2
		return
	_player._try_attack()


func _on_sim_death(inst: MonsterInstance, cause: String) -> void:
	if not _free_roam and _fixture_card_by_id.has(inst.id) and cause != EcologySim.DEATH_KILLED:
		_fail_encounter("有限夹具演员被非玩家原因移除，不补位/补奖")
	if cause != EcologySim.DEATH_KILLED: return
	if _reward_ids.has(inst.id):
		_duplicate_rewards += 1
		return
	_reward_ids[inst.id] = true
	if not _free_roam and _fixture_card_by_id.has(inst.id):
		_roster_kills += 1
		var complete := _completed_rosters()
		if complete > _reported_rosters:
			_reported_rosters = complete
			print("PACING_ROSTER complete=", complete, " time=", _game_time)
	else:
		_incidental_kills += 1
	if inst.id == _encounter_target_id: _encounter_target_id = -1
	var species := inst.species.species_name
	var cohort := species + ("/Boss" if inst.species.is_boss else ("/精英" if inst.is_elite else "/普通"))
	_reward_species[cohort] = int(_reward_species.get(cohort, 0)) + 1
	if inst.species.is_boss: _boss_kills += 1
	elif inst.is_elite: _elite_kills += 1
	var material := EconomyMath.material_for(species)
	if material != "":
		var quantity := 3 if inst.species.is_boss else (2 if inst.is_elite else 1)
		_expected_materials[material] = int(_expected_materials.get(material, 0)) + quantity


func _finish() -> void:
	set_process(false)
	Engine.time_scale = 1.0
	var level_now := GameState.stats.level
	var purchases := _gold_marks.size()
	_check(GameState.world_seed == PACING_SEED and BiomeMap.current_seed() == PACING_SEED and GameState.exploration.seed == PACING_SEED,
		"规范种子贯穿世界、地图与探索")
	_check(is_equal_approx(_game_time, GAME_SECONDS), "真实场景完整推进600游戏秒")
	print("\n=== 节奏报告（%.0f游戏秒） ===" % _game_time)
	print("  击杀 %d / 指定夹具 %d / 顺带 %d / 死亡 %d / Lv.%d / 金币 %d / 最低血线 %.0f%%" % [
		_kills, _roster_kills, _incidental_kills, _deaths, level_now, GameState.gold, _min_hp_ratio * 100.0])
	print("  升级时刻：", _level_marks, " 商店阈值：", _gold_marks)
	if not _free_roam:
		_check(not _encounter_unavailable and _cards_started == ENCOUNTER_CARDS and _fixture_card_by_id.size() == 90 and _encounter_admissions == 90,
			"仅十张有限卡、90个唯一普通演员，无自然供给或补位")
		_check(WorldSim.sim.tick_count == 0 and _reference_sim.tick_count == 600,
			"夹具不自然出生/捕食/老死；独立正常生态参考确实推进600tick")
		_check(_completed_rosters() >= MIN_COMPLETE_ROSTERS, "完整九人卡≥3张（%d）" % _completed_rosters())
	_check(_transport_integrity, "全部安全接近保持HP/MP/六项冷却，不携带未完成挥刀")
	_check(_kills >= 25, "击杀供给≥25（%d）" % _kills)
	_check(_level_marks.has(2) and _level_marks[2] <= 120.0, "首升≤120s（%s）" % str(_level_marks.get(2, "未升级")))
	_check(level_now >= 3 and _level_marks.get(3, 1e9) <= 420.0, "Lv3≤420s（%s）" % str(_level_marks.get(3, "未达到")))
	_check(purchases >= 2, "金币支撑≥2次商店强化（%d）" % purchases)
	_check(_hurt_events > 0 and _min_hp_ratio < 0.70, "真实战斗有压力（伤害事件%d，最低血线%.0f%%<70%%）" % [_hurt_events, _min_hp_ratio * 100.0])
	var alive_avg := 0.0
	for value in _alive_window: alive_avg += value
	if not _alive_window.is_empty(): alive_avg /= _alive_window.size()
	_check(alive_avg > 10.0, "%s近60tick存活均值%.1f>10" % ["自由游猎生态" if _free_roam else "独立自然生态参考（非猎杀压力）", alive_avg])
	var material_count := 0
	for id: String in ItemCatalog.ids_of_kind("material"): material_count += GameState.count_item(id)
	if _free_roam:
		print("  OBS  自由游猎材料%d件，不适用固定卡片[5,70]预算" % material_count)
	else:
		_check(material_count >= 5 and material_count <= 70, "固定600秒材料∈[5,70]（%d件）" % material_count)
	_check_material_conservation()
	print("=== 自由游猎诊断完成 ===" if _free_roam and _fails == 0 else ("=== 节奏验证全部通过 ===" if _fails == 0 else "=== %d项未达节奏区间 ===" % _fails))
	get_tree().quit(0 if _fails == 0 else 1)


func _patrol() -> void:
	if not is_finite(_patrol_target.x) or _game_time - _patrol_retarget > 8.0 \
			or _player.global_position.distance_to(_patrol_target) < 120.0:
		_patrol_retarget = _game_time
		_patrol_target = _nearest_populated_center()
		if not is_finite(_patrol_target.x):
			return
	var dir := (_patrol_target - _player.global_position).normalized()
	_player.facing = dir
	# 空地赶路提速（300px/步 = 1200px/s 游戏速）：大世界斑块间距 8 万像素，
	# 按战斗步速 90px 走要 3.7 分钟/跳——600 秒预算全花在赶路上（实测 34 杀）。
	# 提速模拟真实玩家冲刺穿行空地（冲刺连发 ~620px/s + 空旷无战），遭遇时
	# 机器人回到 22px 贴身节奏，战斗压力口径不变
	_player.global_position += dir * 300.0


## 最近的有存活个体的据点（打光的地方不再回头，模拟"往前探索"；
## 全世界无活体时返回 Vector2.INF）。v4 据点式：怪物扎根地图营地（camp），
## 游猎目标取最近存活实例的位置而非斑块中心——营地与斑块中心可相距
## 上万像素，按中心走会扑空
func _nearest_populated_center() -> Vector2:
	var sim: EcologySim = WorldSim.sim
	if sim == null:
		return Vector2.INF
	var me := _player.global_position
	var best := Vector2.INF
	var best_d := INF
	for inst: MonsterInstance in sim.instances.values():
		if not inst.is_alive or inst.spawn_pos == Vector2.INF:
			continue
		var d: float = me.distance_squared_to(inst.spawn_pos)
		if d < best_d:
			best_d = d
			best = inst.spawn_pos
	return best

func _count_nearby(radius: float) -> int:
	var count := 0
	for body in get_tree().get_nodes_in_group("monsters"):
		var monster := body as MonsterBase
		if monster == null or monster.inst == null or monster.state == MonsterBase.S_CORPSE:
			continue
		if _player.global_position.distance_to(monster.global_position) <= radius:
			count += 1
	return count

func _on_level_up(new_level: int, _levels: int) -> void:
	if not _level_marks.has(new_level):
		_level_marks[new_level] = _game_time

func _on_kill(_xp: int, _gold: int, _name: String, _species: String) -> void:
	_kills += 1


func _on_item_gained(id: String, count: int, _total: int) -> void:
	_gained_items[id] = int(_gained_items.get(id, 0)) + count

func _check_material_conservation() -> void:
	_check(_roster_kills + _incidental_kills == _reward_ids.size() and _roster_kills <= _reward_ids.size(),
		"阵容进度与顺带击杀之和等于真实唯一死亡（%d + %d = %d）" % [_roster_kills, _incidental_kills, _reward_ids.size()])
	_check(_duplicate_rewards == 0 and _reward_ids.size() == _kills,
		"每次击杀对应唯一真实死亡（奖励 %d / 唯一个体 %d）" % [_kills, _reward_ids.size()])
	for id: String in ItemCatalog.ids_of_kind("material"):
		var expected := int(_expected_materials.get(id, 0))
		var gained := int(_gained_items.get(id, 0))
		_check(gained == expected and GameState.count_item(id) == mini(expected, GameState.ITEM_MAX),
			"材料守恒 %s：真实死亡应得 %d / 发放 %d / 库存 %d" % [id, expected, gained, GameState.count_item(id)])
	var silver := int(_gained_items.get(EconomyMath.KEY_SILVER, 0))
	_check(silver <= _elite_kills and GameState.count_item(EconomyMath.KEY_SILVER) == mini(silver, GameState.ITEM_MAX)
		and GameState.count_item(EconomyMath.KEY_GOLD) == 0,
		"钥匙单独核对：银钥 %d ≤ 精英 %d，未接任务不产金钥" % [silver, _elite_kills])
	var consumables := 0
	for id: String in ItemCatalog.ids_of_kind("consumable"):
		consumables += int(_gained_items.get(id, 0))
	_check(consumables == _boss_kills, "每只 Boss 附一件消耗品（%d / %d）" % [consumables, _boss_kills])
	print("  材料来源：", JSON.stringify({"seed": PACING_SEED, "species": _reward_species,
		"expected": _expected_materials, "gained": _gained_items, "inventory": GameState.inventory,
		"elite_kills": _elite_kills, "boss_kills": _boss_kills,
		"roster_kills": _roster_kills, "incidental_kills": _incidental_kills, "free_roam": _free_roam,
		"encounter_admissions": _encounter_admissions, "transports": _transports}))

func _track_gold() -> void:
	while _threshold_index < GOLD_THRESHOLDS.size() \
			and GameState.gold >= GOLD_THRESHOLDS[_threshold_index]:
		_gold_marks[GOLD_THRESHOLDS[_threshold_index]] = _game_time
		_threshold_index += 1

func _transport_for_encounter(destination: Vector2) -> bool:
	if not _player.can_begin_town_return():
		return false
	var hp := _player.current_hp
	var mp := _player.current_mp
	var cooldowns := {}
	for property: String in ["_attack_cooldown", "_dash_cd", "_heavy_cd", "_bolt_cd", "_heal_cd", "_empower_cd"]:
		cooldowns[property] = _player.get(property)
	_player.teleport_to(destination)
	_transport_integrity = _transport_integrity and is_equal_approx(hp, _player.current_hp) and is_equal_approx(mp, _player.current_mp)
	for property: String in cooldowns:
		_transport_integrity = _transport_integrity and is_equal_approx(float(cooldowns[property]), float(_player.get(property)))
	_transport_integrity = _transport_integrity and _player._attack_timer == 0.0 and _player._attack_anim_linger == 0.0
	_transports += 1
	# 复用正式门传送的同步预热步骤；只装配目的地，不移动怪物/清弹幕/恢复资源。
	if _world != null:
		var streamer := _world.get_node_or_null("ChunkStreamer") as ChunkStreamer
		if streamer != null:
			streamer._refresh_window()
			streamer.warmup()
		for child in _world.get_children():
			if child is NavTileLayer or child is ObstacleTileLayer:
				child._process(0.0)
		_world._stream_pass()
	return true

func _fail_encounter(reason: String) -> void:
	if not _encounter_unavailable:
		_encounter_unavailable = true
		_check(false, "固定遭遇不可用：" + reason)

func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  PASS  %s" % msg)
	else:
		_fails += 1
		print("  FAIL  %s" % msg)
