## 可选真实节奏实跑：新档普通属性，活跃生态/AI，普通频率 TouchInput 和真实碰撞。
## 不传送/改资源/造怪；API 跳过阅读，阅读时间明确未测，不冒充新手试玩。
## "$GODOT" --headless --max-fps 60 --path Code res://tests/camp_pilot_pacing_test.tscn -- --branch=hunt
extends Node2D
const MAIN := preload("res://scenes/main/main.tscn")
const RNG_SEED := 20261004
var _world: Node2D
var _player: Player
var _qm: Node
var _hud: CanvasLayer
var _branch := "hunt"
var _world_seed := BiomeMap.DEFAULT_SEED
var _game := 0.0
var _wall := 0
var _step_left := 0.0
var _trace_at := 0.0
var _phase := "offer"
var _phase_seconds := {}
var _marks := {}
var _deaths := 0
var _kills := 0
var _distance := 0.0
var _previous := Vector2.INF
var _min_hp := INF
var _min_mp := INF
var _next_action := 0.0
var _next_attack := 0.0
var _next_bolt := 0.0
var _actions := {"attack": 0, "bolt": 0, "heal": 0, "dash": 0}
var _target_key := ""
var _target_pos := Vector2.INF
var _path := PackedVector2Array()
var _path_goal := Vector2.INF
var _path_index := 0
var _planner := AStarGrid2D.new()
var _progress_pos := Vector2.INF
var _progress_time := 0.0
var _replans := 0
var _victim_id := -1
var _start_wallet := {}
var _finished := false
var _paused_wall := 0
var _decision_pause := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--branch="): _branch = arg.get_slice("=", 1)
		if arg.begins_with("--seed="): _world_seed = int(arg.get_slice("=", 1))
	if _branch not in ["hunt", "ransack"]:
		get_tree().quit(2)
		return
	GameState.save_enabled = false
	GameState.SAVE_PATH = "user://camp_pilot_pacing_%d.json" % OS.get_process_id()
	GameState.reset_all()
	GameState.world_seed = _world_seed
	seed(RNG_SEED)
	Engine.time_scale = 1.0
	_wall = Time.get_ticks_msec()
	_world = MAIN.instantiate()
	add_child(_world)
	_player = _world.get_node("Player")
	_hud = _world.get_node("HUD")
	_qm = get_tree().get_first_node_in_group("quest_manager")
	_start_wallet = _resources()
	_previous = _player.global_position
	_progress_pos = _previous
	WorldSim.sim.instance_died.connect(func(inst: MonsterInstance, cause: String) -> void:
		if inst.region_id + "|" + inst.species.species_name == _target_key:
			_log("target_death", {"id": inst.id, "cause": cause, "species": inst.species.species_name}))
	EventBus.player_died.connect(_on_death)
	EventBus.player_respawned.connect(func() -> void:
		_previous = _player.global_position
		_path_goal = Vector2.INF
		_log("respawn", {"pos": _pos(_player.global_position)}))
	EventBus.monster_killed_by_player.connect(func(_xp: int, _gold: int, _name: String, species: String) -> void:
		_kills += 1
		_log("kill", {"species": species, "quest_kills": GameState.camp_quest.get("kills", []).size()}))
	_log("start", {"seed": _world_seed, "rng_seed": RNG_SEED, "branch": _branch,
		"physics_hz": Engine.physics_ticks_per_second, "time_scale": Engine.time_scale,
		"hit_stop": _world.hit_stop_enabled, "stats": {"strength": _player.stats.strength,
		"agility": _player.stats.agility, "intellect": _player.stats.intellect,
		"move_speed": _player.stats.move_speed()}, "resources": _start_wallet})

func _physics_process(delta: float) -> void:
	if _player == null or _finished: return
	if get_tree().paused:
		if _paused_wall == 0: _paused_wall = Time.get_ticks_msec()
		if _hud._dialogue_panel.visible:
			_hud._close_dialogue()
		if _hud.passive_layer.visible:
			_hud._pick_passive(0)
			_log("automatic_blessing", {"selected_index": 0})
		return
	if _paused_wall > 0:
		_decision_pause += float(Time.get_ticks_msec() - _paused_wall) / 1000.0
		_paused_wall = 0
	_game += delta
	_phase_seconds[_phase] = float(_phase_seconds.get(_phase, 0.0)) + delta
	var moved := _previous.distance_to(_player.global_position)
	if moved < 80.0: _distance += moved
	_previous = _player.global_position
	_min_hp = minf(_min_hp, _player.current_hp)
	_min_mp = minf(_min_mp, _player.current_mp)
	if _game >= 900.0:
		_finish("timeout_900_game_seconds")
		return
	if _game >= _trace_at:
		_trace_at = _game + 10.0
		_log("trace", {"phase": _phase, "pos": _pos(_player.global_position),
			"resources": _resources(), "distance_px": _distance,
			"stage": GameState.camp_quest.get("stage", ""), "target": _target_key,
			"target_distance": _player.global_position.distance_to(_target_pos) if _target_pos.is_finite() else -1.0})
	if _player._is_dead:
		TouchInput.move_vector = Vector2.ZERO
		return
	_step_left -= delta
	if _step_left > 0.0: return
	_step_left += 0.25
	_step()

func _step() -> void:
	if _phase == "offer":
		var offer: Dictionary = _qm.offer("camp_ecology", "camp_ecology", "营地巡守")
		if offer.get("kind", "") == "quest":
			_qm.accept(offer["quest"])
			_set_phase("outbound")
			_log("accepted", {"ledger": GameState.camp_quest})
		elif _game > 30.0: _finish("no_offer_within_30_seconds")
		return
	var q := GameState.camp_quest
	var target: Dictionary = q.get("target", {})
	if target.is_empty():
		_move(Vector2.ZERO)
		return
	var key := str(target.get("key", ""))
	if key != _target_key:
		_target_key = key
		_target_pos = Vector2(float(target["pos"][0]), float(target["pos"][1]))
		_path_goal = Vector2.INF
		_log("target", {"target": target, "distance_from_camp": WorldConfig.spawn_pos().distance_to(_target_pos)})
	var stage := str(q.get("stage", ""))
	if stage == "return":
		if _phase != "return":
			_set_phase("return")
			_log("action_complete", {"ledger": q, "facts": _qm._camp.facts()})
		var home := WorldConfig.spawn_pos()
		if _player.global_position.distance_to(home) < 110.0:
			_move(Vector2.ZERO)
			_qm.claim("camp_ecology_v1")
			if GameState.camp_quest.get("paid", false): _finish("completed")
		else:
			_walk(home)
			_escape()
		return
	if stage == "investigate":
		if _phase != "outbound": _set_phase("outbound")
		if bool(_qm.camp_context().get("can_investigate", false)):
			_move(Vector2.ZERO)
			_log("investigate", {"result": _qm.camp_investigate(), "facts": _qm._camp.facts()})
		else:
			_walk(_target_pos)
			_escape()
		return
	if stage == "choose":
		if not bool(_qm.camp_context().get("on_site", false)):
			_walk(_target_pos)
			_escape()
			return
		_move(Vector2.ZERO)
		_log("choose", {"result": _qm.camp_choose(_branch), "branch": _branch})
		if str(GameState.camp_quest.get("stage", "")) == "act": _set_phase("combat")
		else: _finish("requested_branch_unavailable_at_arrival")
		return
	if stage == "act":
		if _phase != "combat": _set_phase("combat")
		if _branch == "hunt": _hunt()
		else: _ransack()

func _hunt() -> void:
	var victim: MonsterBase = null
	var best := INF
	for node: Node in get_tree().get_nodes_in_group("monsters"):
		if not (node is MonsterBase): continue
		var body := node as MonsterBase
		if body.inst == null or not body.inst.is_alive or body.inst.region_id != GameState.camp_quest["target"]["region_id"] \
			or body.inst.species.species_name != GameState.camp_quest["target"]["species"]: continue
		var d := _player.global_position.distance_to(body.global_position)
		if body.inst.id == _victim_id: d -= 200.0
		if d < best:
			best = d
			victim = body
	if victim == null:
		_walk(_target_pos)
		if bool(_qm.camp_context().get("can_investigate", false)):
			_log("lost_target_review", {"result": _qm.camp_investigate()})
		return
	_victim_id = victim.inst.id
	var diff := victim.global_position - _player.global_position
	var dist := diff.length()
	# 在巢外挥砍，避免范围刀误伤巢；敌人仍照常追击。
	if _player.global_position.distance_to(_target_pos) < 135.0:
		_walk(_target_pos + (_player.global_position - _target_pos).normalized() * 230.0)
		return
	if dist > 58.0: _walk(victim.global_position)
	else: _move(diff.normalized() * 0.08)
	if _heal(): return
	if _game < _next_action: return
	if dist < 68.0 and _game >= _next_attack and _player._attack_timer <= 0.0:
		_queue("attack")
		_next_attack = _game + maxf(0.75, _player.stats.attack_interval())
	elif dist > 75.0 and dist < 260.0 and _game >= _next_bolt and _player.current_mp >= CharacterStats.BOLT_COST + 25.0 and _player._bolt_cd <= 0.0:
		_queue("bolt")
		_next_bolt = _game + 1.0

func _ransack() -> void:
	var nest: NestNode = null
	for node: Node in get_tree().get_nodes_in_group("nests"):
		if node is NestNode and node.nest_key == _target_key:
			nest = node
			break
	if nest == null:
		_walk(_target_pos)
		if bool(_qm.camp_context().get("can_investigate", false)):
			_log("lost_nest_review", {"result": _qm.camp_investigate()})
		return
	var diff := nest.global_position - _player.global_position
	if diff.length() > 48.0: _walk(nest.global_position)
	else: _move(diff.normalized() * 0.08)
	if _heal(): return
	if diff.length() < 66.0 and _game >= _next_attack and _game >= _next_action:
		_queue("attack")
		_next_attack = _game + maxf(0.75, _player.stats.attack_interval())

func _heal() -> bool:
	if _player.current_hp < _player.stats.max_hp() * 0.60 and _player._heal_cd <= 0.0 and _player.current_mp >= CharacterStats.HEAL_COST and _game >= _next_action:
		_queue("heal")
		return true
	return false

func _escape() -> void:
	if _heal(): return
	if _player.current_hp >= _player.stats.max_hp() * 0.45 or _game < _next_action: return
	if _player._dash_cd <= 0.0 and _player.current_mp >= CharacterStats.DASH_COST and TouchInput.move_vector.length() > 0.5:
		_queue("dash")

func _queue(action: String) -> void:
	_actions[action] += 1
	_next_action = _game + 0.5
	match action:
		"attack": TouchInput.queue_attack()
		"bolt": TouchInput.queue_bolt()
		"heal": TouchInput.queue_heal()
		"dash": TouchInput.queue_dash()
	_log("input", {"action": action, "hp": _player.current_hp, "mp": _player.current_mp, "pos": _pos(_player.global_position), "target_id": _victim_id})

func _walk(goal: Vector2) -> void:
	if _player.global_position.distance_to(goal) < 20.0:
		_move(Vector2.ZERO)
		return
	if _progress_pos.distance_to(_player.global_position) > 35.0:
		_progress_pos = _player.global_position
		_progress_time = _game
	if _game - _progress_time > 4.0:
		_path_goal = Vector2.INF
		_progress_time = _game
		_replans += 1
		_log("replan_stuck", {"pos": _pos(_player.global_position), "goal": _pos(goal)})
	if _clear_segment(_player.global_position, goal):
		_move((goal - _player.global_position).normalized())
		return
	if not _path_goal.is_finite() or goal.distance_to(_path_goal) > 80.0 or _path.is_empty(): _plan(goal)
	if _path.is_empty():
		_move(Vector2.ZERO)
		return
	while _path_index < _path.size() - 1 and _player.global_position.distance_to(_path[_path_index]) < 20.0:
		_path_index += 1
	for index in range(_path.size() - 1, _path_index, -1):
		if _clear_segment(_player.global_position, _path[index]):
			_path_index = index
			break
	_move((_path[_path_index] - _player.global_position).normalized())

func _clear_segment(a: Vector2, b: Vector2) -> bool:
	var steps := maxi(1, ceili(a.distance_to(b) / 12.0))
	for index in range(1, steps + 1):
		if ObstacleField.blocks(a.lerp(b, float(index) / steps), 15.0): return false
	var ray := PhysicsRayQueryParameters2D.create(a, b, 1)
	ray.exclude = [_player.get_rid()]
	return _player.get_world_2d().direct_space_state.intersect_ray(ray).is_empty()

func _plan(goal: Vector2) -> void:
	var start := Vector2i((_player.global_position / 32.0).floor())
	var end := Vector2i((goal / 32.0).floor())
	_planner.region = Rect2i(start.min(end) - Vector2i(20, 20), (start - end).abs() + Vector2i(41, 41))
	_planner.cell_size = Vector2(32, 32)
	_planner.offset = Vector2(16, 16)
	_planner.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_planner.update()
	for y in range(_planner.region.position.y, _planner.region.end.y):
		for x in range(_planner.region.position.x, _planner.region.end.x):
			var cell := Vector2i(x, y)
			_planner.set_point_solid(cell, ObstacleField.blocks(Vector2(cell) * 32.0 + Vector2(16, 16), 15.0))
	_planner.set_point_solid(start, false)
	_planner.set_point_solid(end, false)
	_path = _planner.get_point_path(start, end, true)
	_path_goal = goal
	_path_index = mini(1, _path.size() - 1)
	_log("plan", {"points": _path.size(), "goal": _pos(goal), "partial_allowed": true})

func _move(direction: Vector2) -> void:
	TouchInput.joystick_active = true
	TouchInput.move_vector = direction

func _on_death() -> void:
	_deaths += 1
	_previous = Vector2.INF
	_path_goal = Vector2.INF
	_log("death", {"cause": _player.last_killed_by, "pos": _pos(_player.global_position), "resources": _resources()})

func _set_phase(value: String) -> void:
	_phase = value
	if not _marks.has(value): _marks[value] = _game
	_path_goal = Vector2.INF

func _resources() -> Dictionary:
	return {"hp": _player.current_hp, "mp": _player.current_mp, "max_hp": _player.stats.max_hp(), "max_mp": _player.stats.max_mp(),
		"gold": GameState.gold, "xp": GameState.stats.xp, "level": GameState.stats.level, "inventory": GameState.inventory.duplicate(true)}

func _pos(v: Vector2) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01)]

func _log(event: String, details: Dictionary) -> void:
	details["event"] = event
	details["game_seconds"] = snappedf(_game, 0.001)
	details["wall_seconds"] = snappedf(float(Time.get_ticks_msec() - _wall) / 1000.0, 0.001)
	print("CAMP_PACING ", JSON.stringify(details))

func _finish(reason: String) -> void:
	if _finished: return
	_finished = true
	TouchInput.reset()
	var ledger := GameState.camp_quest.duplicate(true)
	_log("result", {"reason": reason, "branch": _branch, "seed": _world_seed, "rng_seed": RNG_SEED,
		"success": reason == "completed" and ledger.get("outcome", "") == _branch, "distance_px": snappedf(_distance, 0.1),
		"deaths": _deaths, "total_player_kills": _kills, "minimum_hp": _min_hp, "minimum_mp": _min_mp,
		"resources_start": _start_wallet, "resources_end": _resources(), "ledger": ledger, "phase_seconds": _phase_seconds,
		"marks": _marks, "queued_inputs": _actions, "stuck_replans": _replans, "automated_selection_pause_wall_seconds": _decision_pause,
		"human_reading_seconds": "not_measured", "limitations": "Expert automated strategy, obstacle planner, 0.25s decisions; task APIs skip reading/UI search. No human/phone timing, teleports, stat/resource boosts, target edits, or AI/ecology suspension"})
	var requested_done: bool = reason == "completed" and ledger.get("outcome", "") == _branch
	print("=== CAMP PILOT PACING %s ===" % ("COMPLETE" if requested_done else "INCOMPLETE"))
	get_tree().quit(0 if requested_done else 1)
