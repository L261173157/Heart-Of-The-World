## 可选真实节奏探针：三个完整小节，普通新档属性，TouchInput行走/攻击，活跃AI/生态。
## --branch=hunt|ransack --entrance=front|side --world=fresh|depleted|aged
## --revision=<已提交HEAD> --measurement=exploratory|final；正式结论须从干净HEAD运行。
## 对话确认/分支选择采用独立新触点，只略过人工阅读；不传送、不加资源、不伪造击杀/任务事件。
extends Node2D

const MAIN := preload("res://scenes/main/main.tscn")
const Layout := preload("res://scripts/ecology/outpost_layout.gd")
const Data := preload("res://scripts/main/outpost_quest_data.gd")
const RNG_SEED := 20261004
const DECISION_INTERVAL := 0.25
var _world: Node2D
var _player: Player
var _qm: Node
var _hud: CanvasLayer
var _branch := "hunt"
var _entrance := "front"
var _world_kind := "fresh"
var _revision := "unrecorded"
var _measurement := "exploratory"
var _world_seed := BiomeMap.DEFAULT_SEED
var _game := 0.0
var _wall := 0
var _step_left := 0.0
var _trace_at := 0.0
var _phase := "accept"
var _phase_seconds := {}
var _episode := "investigation"
var _episode_results := {}
var _episode_start := {}
var _evidence_seen := {}
var _receipt_seen := {}
var _deaths := 0
var _kills := 0
var _damage_received := 0
var _encounters := {}
var _nearby_encounters := {}
var _distance := 0.0
var _previous := Vector2.INF
var _min_hp := INF
var _min_mp := INF
var _next_action := 0.0
var _next_attack := 0.0
var _next_bolt := 0.0
var _next_interaction := 0.0
var _actions := {"attack": 0, "bolt": 0, "heal": 0, "dash": 0, "interact": 0, "dialogue_confirm": 0, "dialogue_choice": 0}
var _target_key := ""
var _target_roster: Array = []
var _target_pos := Vector2.INF
var _path := PackedVector2Array()
var _path_goal := Vector2.INF
var _path_index := 0
var _planner := AStarGrid2D.new()
var _progress_pos := Vector2.INF
var _progress_time := 0.0
var _replans := 0
var _route_compute_usec := 0
var _victim_id := -1
var _start_wallet := {}
var _finished := false
var _paused_wall := 0
var _decision_pause := 0.0
var _dialogue_frame := 0
var _dialogue_token := ""
var _entry_step := 0
var _entry_complete := false
var _broken_cells := []
var _nest_events := []
var _alternate := false
var _outcome_seen := ""
var _ticks_start := 0
var _fixture := {}
var _touch_down := false
var _touch_frames := 0
var _touch_position := Vector2.ZERO
var _ui_next_wall := 0
var _diagnose_routes := false
var _diagnosing := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--diagnose-routes": _diagnose_routes = true
		if arg.begins_with("--branch="): _branch = arg.get_slice("=", 1)
		if arg.begins_with("--entrance="): _entrance = arg.get_slice("=", 1)
		if arg.begins_with("--world="): _world_kind = arg.get_slice("=", 1)
		if arg.begins_with("--seed="): _world_seed = int(arg.get_slice("=", 1))
		if arg.begins_with("--revision="): _revision = arg.get_slice("=", 1)
		if arg.begins_with("--measurement="): _measurement = arg.get_slice("=", 1)
	if _branch not in ["hunt", "ransack"] or _entrance not in ["front", "side"] or _world_kind not in ["fresh", "depleted", "aged"] or _measurement not in ["exploratory", "final"] or (_measurement == "final" and (_revision == "unrecorded" or _diagnose_routes)):
		get_tree().quit(2)
		return
	GameState.save_enabled = false
	GameState.SAVE_PATH = "user://outpost_chapter_pacing_%d.json" % OS.get_process_id()
	GameState.reset_all()
	GameState.world_seed = _world_seed
	BiomeMap.configure(_world_seed)
	seed(RNG_SEED)
	if _world_kind in ["depleted", "aged"] and not _prepare_world_fixture():
		get_tree().quit(2)
		return
	Engine.time_scale = 1.0
	_world = MAIN.instantiate()
	add_child(_world)
	_player = _world.get_node("Player")
	_hud = _world.get_node("HUD")
	_qm = get_tree().get_first_node_in_group("quest_manager")
	_start_wallet = _resources()
	_previous = _player.global_position
	_progress_pos = _previous
	_ticks_start = WorldSim.sim.tick_count
	_wall = Time.get_ticks_msec()
	_episode_start = _sample()
	EventBus.player_died.connect(_on_death)
	EventBus.player_respawned.connect(func() -> void:
		_previous = _player.global_position
		_path_goal = Vector2.INF
		_log("respawn", {"pos": _pos(_player.global_position)}))
	EventBus.monster_killed_by_player.connect(func(_xp: int, _gold: int, _name: String, species: String) -> void:
		_kills += 1
		_log("kill", {"species": species, "chapter_kills": _q().get("kills", []).size()}))
	EventBus.monster_killed_at.connect(func(id: int, species: String, region: String, position: Vector2) -> void:
		_log("real_kill_at", {"instance_id": id, "species": species, "region_id": region, "position": _pos(position),
			"chapter_kill_ids": _q().get("kills", []).duplicate(), "player_position": _pos(_player.global_position),
			"distance_from_nest": position.distance_to(_target_pos) if _target_pos.is_finite() else -1.0}))
	EventBus.damage_number.connect(func(_position: Vector2, amount: int, player_hurt: bool, _effective: bool) -> void:
		if player_hurt: _damage_received += amount)
	EventBus.obstacle_destroyed.connect(func(cell: Vector2i, _position: Vector2, kind: String) -> void:
		var front := cell in Layout.front_barricade_cells()
		_broken_cells.append({"cell": [cell.x, cell.y], "front_barricade": front})
		_log("obstacle_destroyed", {"cell": [cell.x, cell.y], "kind": kind, "front_barricade": front}))
	EventBus.nest_ransacked_at.connect(func(species: String, region: String, position: Vector2) -> void:
		_nest_events.append({"species": species, "region": region, "pos": _pos(position)})
		_log("real_nest_ransack", _nest_events.back().duplicate()))
	WorldSim.sim.instance_died.connect(func(inst: MonsterInstance, cause: String) -> void:
		if inst.region_id + "|" + inst.species.species_name == _target_key:
			_log("target_death", {"id": inst.id, "cause": cause, "species": inst.species.species_name}))
	_log("start", {"seed": _world_seed, "rng_seed": RNG_SEED, "branch": _branch, "entrance": _entrance,
		"world": _world_kind, "fixture": _fixture, "revision": _revision, "measurement": _measurement,
		"engine": Engine.get_version_info()["string"], "platform": OS.get_name(),
		"physics_hz": Engine.physics_ticks_per_second, "time_scale": Engine.time_scale, "hit_stop": _world.hit_stop_enabled,
		"stream_all": _world.stream_all, "ecology_reintroduction_enabled": WorldSim.sim.reintroduction_enabled,
		"ecology_predation_enabled": WorldSim.sim.predation_enabled,
		"stats": {"strength": _player.stats.strength, "agility": _player.stats.agility, "intellect": _player.stats.intellect,
		"move_speed": _player.stats.move_speed()}, "resources": _start_wallet, "initial_position": _pos(_previous)})

func _physics_process(delta: float) -> void:
	if _player == null or _finished: return
	_release_ui_touch()
	if get_tree().paused:
		if _paused_wall == 0: _paused_wall = Time.get_ticks_msec()
		_automate_dialogue()
		if _hud.passive_layer.visible:
			_hud._pick_passive(0)
			_log("automatic_blessing", {"selected_index": 0})
		return
	if _paused_wall > 0:
		_decision_pause += float(Time.get_ticks_msec() - _paused_wall) / 1000.0
		_paused_wall = 0
		_dialogue_frame = 0
		_dialogue_token = ""
	_game += delta
	_phase_seconds[_phase] = float(_phase_seconds.get(_phase, 0.0)) + delta
	if _previous.is_finite():
		var moved := _previous.distance_to(_player.global_position)
		if moved < 80.0: _distance += moved
		elif not _player._is_dead: _log("unmeasured_position_jump", {"distance": moved, "pos": _pos(_player.global_position)})
	_previous = _player.global_position
	_min_hp = minf(_min_hp, _player.current_hp)
	_min_mp = minf(_min_mp, _player.current_mp)
	_observe_progress()
	if _game >= 900.0:
		_finish("timeout_900_game_seconds")
		return
	if _game >= _trace_at:
		_trace_at = _game + 10.0
		_log("trace", {"episode": _episode, "phase": _phase, "pos": _pos(_player.global_position),
			"resources": _resources(), "distance_px": _distance, "stage": _q().get("stage", ""),
			"evidence": _q().get("evidence", {}), "target": _target_key, "ecology_ticks": WorldSim.sim.tick_count - _ticks_start})
	if _player._is_dead:
		_move(Vector2.ZERO)
		return
	_step_left -= delta
	if _step_left > 0.0: return
	_step_left += DECISION_INTERVAL
	_observe_encounters()
	if not _diagnosing: _step()

## 对话来自真实情境交互；每次选项/确认都是独立新触点，只略过人工阅读。
func _automate_dialogue() -> void:
	if not _hud._dialogue_panel.visible or _touch_down or Time.get_ticks_msec() < _ui_next_wall: return
	_dialogue_frame += 1
	if _dialogue_frame < 3: return
	var token := str(_hud._dialogue_kind) + "|" + str(_hud._dialogue_action_name) + "|" + str(_hud._dialogue_text.text)
	if token != _dialogue_token:
		_dialogue_token = token
		_log("dialogue", {"kind": _hud._dialogue_kind, "action": _hud._dialogue_action_name, "text": _hud._dialogue_text.text})
	if _hud._dialogue_kind == "camp_choice" and _hud._dialogue_selected_option.is_empty():
		for button: Node in _hud._dialogue_option_box.get_children():
			if button is Button and str(button.name).ends_with("choose_" + _branch) and not button.disabled:
				_tap_ui(button)
				_actions["dialogue_choice"] += 1
				return
		_finish("requested_branch_unavailable_at_arrival")
		return
	if _hud._dialogue_yes.visible:
		_actions["dialogue_confirm"] += 1
		_tap_ui(_hud._dialogue_yes)
	else:
		_tap_ui(_hud._dialogue_no)

func _tap_ui(button: Control) -> void:
	_touch_position = get_viewport().get_screen_transform() * button.get_global_rect().get_center()
	var event := InputEventScreenTouch.new()
	event.index = 73
	event.position = _touch_position
	event.pressed = true
	_touch_down = true
	_touch_frames = 0
	_ui_next_wall = Time.get_ticks_msec() + 250
	Input.parse_input_event(event)

func _release_ui_touch() -> void:
	if not _touch_down: return
	_touch_frames += 1
	if _touch_frames < 3: return
	var event := InputEventScreenTouch.new()
	event.index = 73
	event.position = _touch_position
	event.pressed = false
	_touch_down = false
	Input.parse_input_event(event)

func _step() -> void:
	if _q().is_empty():
		_set_phase("accept")
		var keeper := _keeper()
		if keeper == null:
			_finish("missing_camp_keeper")
			return
		_interact_with(keeper, "camp_keeper")
		return
	var e: Dictionary = _q().get("evidence", {})
	if not e.get("patrol_read", false):
		_object("patrol_record")
	elif not e.get("entrance_read", false):
		_object("entrance_record")
	elif not _entry_complete:
		_enter_outpost()
	elif not e.get("wounded_found", false):
		_object("wounded_patrol")
	elif not e.get("supply_read", false):
		_object("supply_record")
	elif not e.get("aid_taken", false):
		_object("aid_bag")
	elif not e.get("rescued", false):
		_object("wounded_patrol")
	elif not e.get("tools_taken", false):
		_object("repair_tools")
	elif not Data.has_ecology_result(_q()):
		_ecology()
	elif not e.get("signpost_repaired", false):
		_object("signpost")
	elif str(_q().get("stage", "")) == "claim":
		_object("signpost")
	elif not e.get("next_clue_received", false):
		_object("wounded_patrol")
	else:
		_finish("completed")

func _object(id: String) -> void:
	_set_phase(id)
	var prop := _prop(id)
	if prop == null:
		_finish("missing_object_" + id)
		return
	_interact_with(prop, id)

func _interact_with(prop: Node2D, id: String) -> void:
	var goal := prop.global_position + Vector2(0, 56)
	var expected := "npc:%d" % prop.get_instance_id()
	var context := _player._current_context()
	if _player.global_position.distance_to(prop.global_position) < 82.0 and str(context.get("target_id", "")) == expected:
		_move(Vector2.ZERO)
		if _game >= _next_interaction:
			_next_interaction = _game + 0.75
			_actions["interact"] += 1
			TouchInput.queue_interact(expected)
			_log("context_input", {"object": id, "context": context, "pos": _pos(_player.global_position)})
	else:
		_walk(goal)
		_escape()

func _enter_outpost() -> void:
	_set_phase("enter_" + _entrance)
	var entrances: Dictionary = Layout.entrances()
	if _entrance == "side":
		var side: Vector2 = entrances["side"]
		var goal := side + Vector2(-96 if _entry_step == 0 else 96, 0)
		if _player.global_position.distance_to(goal) < 24.0:
			_entry_step += 1
			_path_goal = Vector2.INF
			if _entry_step == 2:
				_entry_complete = true
				_log("entry_complete", {"route": _entrance, "broken_cells": _broken_cells})
		else: _walk(goal)
	else:
		var front: Vector2 = entrances["front"]
		if _entry_step == 0:
			var approach := front + Vector2(0, 58)
			if _player.global_position.distance_to(approach) < 18.0: _entry_step = 1
			else: _walk(approach)
		elif _entry_step == 1:
			if not ObstacleField.blocks(front, 15.0):
				_entry_step = 2
				_path_goal = Vector2.INF
			else:
				_move(_player.global_position.direction_to(front) * 0.08)
				if _game >= _next_attack and _game >= _next_action:
					_queue("attack")
					_next_attack = _game + maxf(0.75, _player.stats.attack_interval())
		else:
			var inside := front + Vector2(0, -96)
			if _player.global_position.distance_to(inside) < 24.0:
				_entry_complete = true
				_log("entry_complete", {"route": _entrance, "broken_cells": _broken_cells})
			else: _walk(inside)
	_escape()

func _ecology() -> void:
	var target: Dictionary = _q().get("target", {})
	if target.is_empty():
		if _qm._outpost._searching:
			# 正常跨帧核查期间去勘察点，不反复开窗暂停核查，也不额外填充等待。
			_set_phase("ecology_search")
			_walk(Layout.object_position("survey_marker") + Vector2(0, 56))
			_escape()
			return
		# 查找由正常任务代码跨帧完成；无目标时仍需要现场确认替代，而非假完成。
		_object("survey_marker")
		return
	var key := str(target.get("key", ""))
	var roster: Array = target.get("target_ids", [])
	if key != _target_key or roster != _target_roster:
		_target_key = key
		_target_roster = roster.duplicate()
		_target_pos = Vector2(float(target["pos"][0]), float(target["pos"][1]))
		_path_goal = Vector2.INF
		_log("target", {"target": target, "verified_current_ids": _qm._outpost._targets.current_stock_ids(target)})
	var surveyed: bool = _target_key in _q().get("surveys", [])
	if not surveyed or str(_q().get("choice", "")).is_empty():
		if _qm._outpost._searching:
			_set_phase("ecology_recheck")
			_move(Vector2.ZERO)
			_escape()
			return
		_set_phase("ecology_investigate")
		var context: Dictionary = _qm.outpost_context()
		if bool(context.get("on_site", false)) and bool(context.get("can_investigate", false)):
			_move(Vector2.ZERO)
			var current := _player._current_context()
			if str(current.get("target_id", "")).begins_with("outpost:") and _game >= _next_interaction:
				TouchInput.queue_interact(str(current["target_id"]))
				_actions["interact"] += 1
				_next_interaction = _game + 0.75
				_log("context_input", {"object": "ecology_site", "context": current})
			elif not str(current.get("target_id", "")).begins_with("outpost:"):
				_walk(_target_pos + Vector2(160, 0))
		else:
			_walk(_target_pos)
			_escape()
		return
	_set_phase("combat_" + _branch)
	if _branch == "hunt": _hunt()
	else: _ransack()

func _hunt() -> void:
	# 只追新章节当前核实过路径的真实ID；10k/同地区同物种边界由生产选择器校验。
	var eligible_ids: Array = _qm._outpost._targets.current_stock_ids(_q()["target"])
	var victim: MonsterBase = null
	var best := INF
	for node: Node in get_tree().get_nodes_in_group("monsters"):
		if not node is MonsterBase: continue
		var body := node as MonsterBase
		if body.inst == null or not body.inst.is_alive or body.inst.region_id != _q()["target"]["region_id"] or body.inst.species.species_name != _q()["target"]["species"]: continue
		if body.inst.id not in eligible_ids: continue
		var d := _player.global_position.distance_to(body.global_position)
		if body.inst.id == _victim_id: d -= 200.0
		if d < best:
			best = d
			victim = body
	if victim == null:
		_review_ecology()
		return
	_victim_id = victim.inst.id
	if not _encounters.has(str(_victim_id)):
		_encounters[str(_victim_id)] = {"species": victim.inst.species.species_name, "first_game_second": _game}
	var diff := victim.global_position - _player.global_position
	var dist := diff.length()
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
		_review_ecology()
		return
	var diff := nest.global_position - _player.global_position
	if diff.length() > 48.0: _walk(nest.global_position)
	else: _move(diff.normalized() * 0.08)
	if _heal(): return
	if diff.length() < 66.0 and _game >= _next_attack and _game >= _next_action:
		_queue("attack")
		_next_attack = _game + maxf(0.75, _player.stats.attack_interval())

func _review_ecology() -> void:
	_walk(_target_pos)
	var context: Dictionary = _qm.outpost_context()
	if bool(context.get("can_investigate", false)) and _game >= _next_interaction:
		var current := _player._current_context()
		if str(current.get("target_id", "")).begins_with("outpost:"):
			_move(Vector2.ZERO)
			TouchInput.queue_interact(str(current["target_id"]))
			_actions["interact"] += 1
			_next_interaction = _game + 1.0
			_log("review_changed_ecology", {"context": current})

func _heal() -> bool:
	if _player.current_hp < _player.stats.max_hp() * 0.60 and _player._heal_cd <= 0.0 and _player.current_mp >= CharacterStats.HEAL_COST and _game >= _next_action:
		_queue("heal")
		return true
	return false

func _escape() -> void:
	if _heal(): return
	if _player.current_hp >= _player.stats.max_hp() * 0.45 or _game < _next_action: return
	if _player._dash_cd <= 0.0 and _player.current_mp >= CharacterStats.DASH_COST and TouchInput.move_vector.length() > 0.5: _queue("dash")

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
	var started := Time.get_ticks_usec()
	_walk_impl(goal)
	_route_compute_usec += Time.get_ticks_usec() - started

func _walk_impl(goal: Vector2) -> void:
	if _player.global_position.distance_to(goal) < 18.0:
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
	var current_path := _path_goal.is_finite() and goal.distance_to(_path_goal) <= 80.0 and not _path.is_empty()
	# 已有真实可走路径时，不每0.25秒重新扫描数千像素外的终点；近段照常验碰撞。
	if (not current_path or _player.global_position.distance_to(goal) <= 1024.0) and _clear_segment(_player.global_position, goal):
		_move((goal - _player.global_position).normalized())
		return
	if not current_path: _plan(goal)
	if _path.is_empty():
		_move(Vector2.ZERO)
		return
	while _path_index < _path.size() - 1 and _player.global_position.distance_to(_path[_path_index]) < 20.0: _path_index += 1
	# 有界前视只影响机器人规划开销；逐段仍检查真实障碍/碰撞，不缩短世界路程。
	for index in range(mini(_path.size() - 1, _path_index + 16), _path_index, -1):
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
	_planner.region = Rect2i(start.min(end) - Vector2i(24, 24), (start - end).abs() + Vector2i(49, 49))
	_planner.cell_size = Vector2(32, 32)
	_planner.offset = Vector2(16, 16)
	_planner.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_planner.update()
	var shape := CircleShape2D.new()
	shape.radius = 15.0
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.collision_mask = 1
	query.exclude = [_player.get_rid()]
	for y in range(_planner.region.position.y, _planner.region.end.y):
		for x in range(_planner.region.position.x, _planner.region.end.x):
			var cell := Vector2i(x, y)
			var point := Vector2(cell) * 32.0 + Vector2(16, 16)
			var blocked := ObstacleField.blocks(point, 15.0)
			if not blocked and point.distance_to(_player.global_position) < 2000.0:
				query.transform = Transform2D(0.0, point)
				blocked = not _player.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()
			_planner.set_point_solid(cell, blocked)
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
	if _phase == value: return
	_log("phase", {"from": _phase, "to": value})
	_phase = value
	_path_goal = Vector2.INF

func _q() -> Dictionary:
	return GameState.get("outpost_quest") as Dictionary

func _prop(id: String) -> Node2D:
	for node: Node in get_tree().get_nodes_in_group("outpost_objects"):
		if node is Node2D and str(node.get("outpost_id")) == id: return node
	return null

func _keeper() -> Node2D:
	for node: Node in get_tree().get_nodes_in_group("npcs"):
		if str(node.get("landmark_id")) == "camp_ecology": return node as Node2D
	return null

func _observe_encounters() -> void:
	for node: Node in get_tree().get_nodes_in_group("monsters"):
		if not node is MonsterBase or node.inst == null or not node.inst.is_alive: continue
		if _player.global_position.distance_to(node.global_position) < 300.0:
			var id := str(node.inst.id)
			if not _nearby_encounters.has(id):
				_nearby_encounters[id] = {"species": node.inst.species.species_name, "first_game_second": _game}
				_log("encounter", {"instance_id": node.inst.id, "species": node.inst.species.species_name, "radius_px": 300})

func _observe_progress() -> void:
	var q := _q()
	for key: String in q.get("evidence", {}):
		if q["evidence"][key] and not _evidence_seen.has(key):
			_evidence_seen[key] = _sample()
			_log("evidence", {"key": key, "position": _pos(_player.global_position)})
	for key: String in q.get("receipts", {}):
		if q["receipts"][key].get("paid", false) and not _receipt_seen.has(key):
			_receipt_seen[key] = _sample()
			_log("receipt", {"key": key, "receipt": q["receipts"][key], "resources": _resources()})
	var outcome := str(q.get("outcome", ""))
	if outcome != _outcome_seen:
		_outcome_seen = outcome
		if outcome == "survey": _alternate = true
		_log("ecology_outcome", {"outcome": outcome, "ledger": q})
	if _episode == "investigation" and Data.investigation_done(q): _end_episode("rescue")
	if _episode == "rescue" and Data.rescue_done(q):
		_end_episode("restoration")
		_log("ecology_selection_diagnostics", _ecology_diagnostics())
		if _diagnose_routes:
			_diagnosing = true
			_move(Vector2.ZERO)
			_diagnose_route_candidates.call_deferred()

## 只读探针诊断，不向玩家UI暴露全局存量，不参与任务选择/改变生产情报。
func _ecology_diagnostics() -> Dictionary:
	var groups := {}
	var sim := WorldSim.sim
	var helper: Node = _qm._outpost._targets
	for inst: MonsterInstance in sim.instances.values():
		if not inst.is_alive: continue
		var center := sim.camp_pos(sim.get_region(inst.region_id), inst.species)
		if center.distance_to(WorldConfig.spawn_pos()) > 10000.0: continue
		var key := inst.region_id + "|" + inst.species.species_name
		if not groups.has(key):
			groups[key] = {"alive": 0, "feasible": 0, "members": 0, "minimum_age": inst.age, "maximum_age": inst.age,
				"camp_distance_home": center.distance_to(WorldConfig.spawn_pos()), "nest": sim.nests.get(key, {}), "individuals": []}
		groups[key]["alive"] += 1
		if helper._feasible(inst): groups[key]["feasible"] += 1
		var target := {"region_id": inst.region_id, "species": inst.species.species_name, "pos": [center.x, center.y]}
		if helper._member_current(inst, target): groups[key]["members"] += 1
		var actor_position: Vector2 = helper.actor_position(inst)
		groups[key]["individuals"].append({"id": inst.id, "actor_position": _pos(actor_position), "spawn_position": _pos(inst.spawn_pos),
			"canonical_position": _pos(center), "distance_home": actor_position.distance_to(WorldConfig.spawn_pos()),
			"distance_camp": actor_position.distance_to(center), "nav_blocked": ObstacleField.nav_blocked_at(actor_position),
			"member": helper._member_current(inst, target)})
		groups[key]["minimum_age"] = mini(groups[key]["minimum_age"], inst.age)
		groups[key]["maximum_age"] = maxi(groups[key]["maximum_age"], inst.age)
	return {"local_groups": groups, "position": _pos(_player.global_position),
		"searching": _qm._outpost._searching, "search_complete": _qm._outpost._search_complete,
		"target": _q().get("target", {}), "read_only_test_diagnostic": true,
		"route_cells_connected": helper._route_connected.size(), "route_visits_left": helper._route_visits_left,
		"inside_town_room": helper._inside_town_room()}

## 仅 --diagnose-routes 的未完成调试运行：独立选择器做只读路线查询，结束即退出。
## 不纳入正式实跑，不让规划缓存修改任务选择器，不传送玩家。
func _diagnose_route_candidates() -> void:
	var helper := CampQuestTargets.new()
	add_child(helper)
	var groups: Dictionary = _ecology_diagnostics()["local_groups"]
	var sim := WorldSim.sim
	for key: String in groups:
		if int(groups[key]["feasible"]) < 3: continue
		var region := sim.get_region(key.get_slice("|", 0))
		var species := sim.find_species(key.get_slice("|", 1))
		var goal := sim.camp_pos(region, species)
		for origin: Vector2 in [_player.global_position, Layout.entrances()["side"] + Vector2(-96, 0), WorldConfig.spawn_pos()]:
			helper._route_connected.clear()
			helper._route_blocked.clear()
			helper._route_slice_started = Time.get_ticks_usec()
			helper._route_visits_left = 8000
			var reachable: bool = await helper._route_exists(origin, goal)
			_log("diagnostic_candidate_route", {"key": key, "from": _pos(origin), "goal": _pos(goal),
				"reachable": reachable, "visits_left": helper._route_visits_left, "connected_cells": helper._route_connected.size(),
				"goal_nav_blocked": ObstacleField.nav_blocked_at(goal), "group": groups[key]})
	_finish("diagnostic_only_after_rescue")

func _sample() -> Dictionary:
	return {"game_seconds": _game, "wall_seconds": float(Time.get_ticks_msec() - _wall) / 1000.0,
		"distance_px": _distance, "deaths": _deaths, "kills": _kills, "nearby_encounters": _nearby_encounters.size(),
		"damage_received": _damage_received, "bot_route_compute_wall_seconds": float(_route_compute_usec) / 1000000.0, "actions": _actions.duplicate()}

func _end_episode(next: String) -> void:
	var end := _sample()
	var report := {}
	for key: String in end:
		if key == "actions":
			var actions := {}
			for action: String in _actions: actions[action] = end[key][action] - _episode_start[key][action]
			report[key] = actions
		else: report[key] = end[key] - _episode_start[key]
	_episode_results[_episode] = report
	_log("episode_complete", {"episode": _episode, "metrics": report})
	_episode = next
	_episode_start = end

func _resources() -> Dictionary:
	return {"hp": _player.current_hp, "mp": _player.current_mp, "max_hp": _player.stats.max_hp(), "max_mp": _player.stats.max_mp(),
		"gold": GameState.gold, "xp": GameState.stats.xp, "level": GameState.stats.level, "inventory": GameState.inventory.duplicate(true)}

func _pos(v: Vector2) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01)]

func _log(event: String, details: Dictionary) -> void:
	details["event"] = event
	details["game_seconds"] = snappedf(_game, 0.001)
	details["wall_seconds"] = snappedf(float(Time.get_ticks_msec() - _wall) / 1000.0, 0.001)
	print("OUTPOST_PACING ", JSON.stringify(details))

func _finish(reason: String) -> void:
	if _finished: return
	_finished = true
	TouchInput.reset()
	get_tree().paused = false
	_end_episode("finished")
	var ledger := _q().duplicate(true)
	var reward := {"gold": 0, "xp": 0, "bonus": ""}
	var base_reward := {"gold": 0, "xp": 0, "bonus": ""}
	var paid_count := 0
	for stage: String in ledger.get("receipts", {}):
		var receipt: Dictionary = ledger["receipts"][stage]
		if receipt.get("paid", false):
			paid_count += 1
			var base := Data.reward(stage, false)
			base_reward["gold"] += base["gold"]
			base_reward["xp"] += base["xp"]
			if base["bonus"] != "": base_reward["bonus"] = base["bonus"]
			reward["gold"] += int(receipt.get("gold", 0))
			reward["xp"] += int(receipt.get("xp", 0))
			if receipt.get("bonus", "") != "": reward["bonus"] = receipt["bonus"]
	var valid_outcome: bool = ledger.get("outcome", "") == ("survey" if _world_kind == "depleted" else _branch)
	var checkpoint := GameState.discovered_checkpoints.has(Layout.CHECKPOINT_ID)
	var front_broken := false
	for broken: Dictionary in _broken_cells:
		if broken.get("front_barricade", false): front_broken = true
	var valid_entrance := _entry_complete and (front_broken if _entrance == "front" else not front_broken)
	var success: bool = reason == "completed" and valid_outcome and checkpoint and valid_entrance and paid_count == 3 and base_reward == {"gold": 39, "xp": 44, "bonus": "onigiri"} and reward["bonus"] == "onigiri"
	_log("result", {"reason": reason, "success": success, "chapter_completed": ledger.get("stage", "") == "completed",
		"requested_outcome_achieved": valid_outcome, "branch": _branch, "entrance": _entrance,
		"world": _world_kind, "fixture": _fixture, "seed": _world_seed, "rng_seed": RNG_SEED, "revision": _revision,
		"measurement": _measurement, "distance_px": snappedf(_distance, 0.1), "deaths": _deaths,
		"total_player_kills": _kills, "nearby_encounter_count": _nearby_encounters.size(), "combat_target_count": _encounters.size(),
		"damage_received": _damage_received, "bot_route_compute_wall_seconds": float(_route_compute_usec) / 1000000.0, "minimum_hp": _min_hp, "minimum_mp": _min_mp,
		"resources_start": _start_wallet, "resources_end": _resources(), "ledger": ledger, "reward_receipt_total": reward, "base_reward_budget": base_reward,
		"checkpoint_unlocked": checkpoint, "checkpoint_position": _pos(Layout.checkpoint_position()),
		"episode_metrics": _episode_results, "phase_seconds": _phase_seconds, "evidence_marks": _evidence_seen,
		"receipt_marks": _receipt_seen, "queued_inputs": _actions, "stuck_replans": _replans, "entry_complete": _entry_complete, "entrance_evidence_valid": valid_entrance,
		"destroyed_cells": _broken_cells, "nest_events": _nest_events, "ecology_alternate": _alternate,
		"ecology_ticks": WorldSim.sim.tick_count - _ticks_start, "automated_selection_pause_wall_seconds": _decision_pause,
		"human_reading_seconds": "not_measured", "limitations": "Informed automated obstacle-aware routing; 0.25s combat/movement decisions; actual context inputs and independent fresh dialog touches skip human reading and UI search. Wall time includes separately reported bot route computation; not novice/iPhone time or device performance. No route teleports, stat/HP/resource boosts, world changes during measurement, AI/ecology freeze, or fake combat/task events. Initial fixture is disclosed separately."})
	print("=== OUTPOST CHAPTER PACING %s ===" % ("COMPLETE" if success else "INCOMPLETE"))
	get_tree().quit(0 if success else 1)

## 只在装配前构造并保存/读取极端耗尽或自然演化600刻的世界夹具。
## 耗尽夹具真实远方Boss保留；所有测量内AI/生态照常运行，不把前置演化算进玩家时间。
func _prepare_world_fixture() -> bool:
	var fixture_wall := Time.get_ticks_msec()
	var sim := EcologySim.new()
	var regions: Array = []
	for definition: Dictionary in WorldConfig.region_defs():
		var region := SimRegion.new()
		region.id = definition["id"]
		region.display_name = definition["name"]
		region.terrain = definition["terrain"]
		region.threat = definition["threat"]
		region.center = definition["center"]
		region.size = definition["size"]
		region.capacity = definition["capacity"]
		for neighbor: String in definition["neighbors"]: region.neighbor_ids.append(neighbor)
		regions.append(region)
	sim.setup(regions, SpeciesCatalog.build_all(), WorldConfig.initial_population(), WorldConfig.boss_anchors())
	if _world_kind == "aged":
		for _tick in 600: sim.tick()
	var snapshot := sim.to_dict()
	var surviving: Array = []
	var extinct := {}
	for species: SpeciesData in sim.species_list:
		if not species.is_boss: extinct[species.species_name] = true
	for entry: Dictionary in snapshot["instances"]:
		if sim.find_species(str(entry["species"])).is_boss: surviving.append(entry)
	if _world_kind == "depleted":
		snapshot["instances"] = surviving
		snapshot["player_extinct"] = extinct
		snapshot["nests"] = {}
	else:
		snapshot["day_time"] = fmod(0.15 + 600.0 / WorldSim.DAY_LENGTH, 1.0)
		snapshot["game_day"] = floori(0.15 + 600.0 / WorldSim.DAY_LENGTH)
	GameState.ecology_snapshot = snapshot
	GameState.save_enabled = true
	var saved := GameState.save_now()
	GameState.save_enabled = false
	if not saved:
		push_error("前哨节奏耗尽世界夹具未能写入隔离存档")
		return false
	GameState.ecology_snapshot = null
	GameState._load()
	_fixture = {"kind": "all_non_boss_species_predepleted_snapshot", "retained_distant_bosses": surviving.size(),
		"extinct_non_boss_species": extinct.size(), "all_local_chapter_targets_depleted": true, "saved_then_loaded_through_game_state": true,
		"limitation": "All-dead snapshots are deliberately rejected by existing restore; distant Bosses remain and run normally."}

	if _world_kind == "aged":
		_fixture = {"kind": "naturally_aged_world_saved_then_loaded", "normal_ecology_ticks_before_measurement": 600,
			"ordinary_new_adventurer_stats": true, "saved_then_loaded_through_game_state": true,
			"premeasurement_world_clock": {"day_time": snapshot["day_time"], "game_day": snapshot["game_day"]}}
	_fixture["fixture_setup_wall_seconds_excluded"] = float(Time.get_ticks_msec() - fixture_wall) / 1000.0
	return GameState.ecology_snapshot is Dictionary
