## Earned-budget original turtle combat. Production code is deliberately unchanged.
## Preparation starts from a genuine C5 main ledger. The capacity-fixture inventory
## is discarded; only five paid chapter bonus onigiri are reconstructed. Gold is
## reduced to the sum of actual paid receipts. No optional reward is invented.
## World ecology and unrelated actors are frozen to isolate the original Boss;
## its ID, age, anchor, stats, HP, collision and live AI remain untouched.
extends "res://tests/campaign_story_acceptance_test.gd"

var _budget := {}
var _mobile := false
var _combat_active := false
var _combat_seconds := 0.0
var _ui_costs: Array = []
var _retreat_direction := Vector2.ZERO
var _retreat_active := false
var _close_probe := false

func _physics_process(delta: float) -> void:
	if _combat_active: _combat_seconds += delta

func _run() -> void:
	get_tree().root.size = Vector2i(1280,720)
	get_tree().root.content_scale_size = Vector2i(1280,720)
	get_tree().root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	get_tree().root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	Engine.time_scale = 4.0
	Engine.physics_ticks_per_second = 240
	var args := OS.get_cmdline_user_args()
	if OS.get_environment("HOTW_TEST_SAVE").is_empty() or args.is_empty():
		_check(false,"isolated cold-save path and phase required")
		_finish()
		return
	_mobile = args[0].begins_with("mobile")
	_close_probe = args[0] == "mobile_close_probe"
	seed(20261005 + (int(args[1]) if args.size()>1 else 0))
	await _mount(false)
	if args[0] == "prepare":
		await _prepare_earned()
	elif _close_probe:
		await _configure_mobile()
	elif args[0] == "age":
		await _age_ecology()
	elif args[0] == "read_complete":
		_read_defeat()
		_check(_campaign_data.ready(_cq(),C6+":s4"),"cold ordinary-build campaign retains all six chapters complete")
		_verify_ending_world()
	elif args[0] == "finish":
		await _finish_story()
	else:
		await _fight_earned(args[0] == "reckless")
	if _fails == 0:
		_check(_save(),"earned combat state atomically persisted")
	await _unmount()
	_finish()

func _receipt_budget() -> Dictionary:
	var result := {"gold":0,"xp":0,"onigiri":0,"receipt_ids":[]}
	for id: String in _q().get("receipts",{}):
		var receipt: Dictionary = _q()["receipts"][id]
		if not receipt.get("paid",false): continue
		result.gold += int(receipt.gold)
		result.xp += int(receipt.xp)
		if receipt.get("bonus","") == "onigiri": result.onigiri += 1
		result.receipt_ids.append("lost_outpost_v1:"+id)
	for id: String in _cq().get("quests",{}):
		var receipt: Dictionary = _cq()["quests"][id].get("receipt",{})
		if not receipt.get("paid",false): continue
		result.gold += int(receipt.gold)
		result.xp += int(receipt.xp)
		if receipt.get("bonus","") == "onigiri": result.onigiri += 1
		result.receipt_ids.append(id)
	return result

func _original_boss() -> MonsterInstance:
	for inst: MonsterInstance in WorldSim.sim.instances.values():
		if inst.species.species_name == "熔岩龟王": return inst
	return null

func _prepare_earned() -> void:
	_budget = _receipt_budget()
	_check(_budget.xp == 364 and _budget.gold == 291 and _budget.onigiri == 5,"C1–C5 actual paid receipts are 364XP/291gold/5bonus onigiri")
	_check(GameState.stats.level == 3 and GameState.stats.strength == 5 and GameState.stats.pending_points == 2
		and GameState.stats.passives.is_empty() and GameState.stats.equips.is_empty(),"genuine unallocated Lv3 save, no invented attributes/passives/equipment")
	# Counterfactual inventory cleanup is explicit, bounded by verified receipts.
	GameState.inventory.clear()
	GameState.gold = mini(GameState.gold,int(_budget.gold))
	GameState.add_item("onigiri",int(_budget.onigiri))
	while GameState.stats.pending_points > 0: GameState.allocate("strength")
	_purchase_earned_upgrades()
	_player.set_process(true)
	# Actual natural regeneration at the already completed, safe snow beacon.
	var rest_frames := 0
	while (_player.current_hp < _player.stats.max_hp()-0.01 or _player.current_mp < _player.stats.max_mp()-0.01) and rest_frames < 9000:
		await get_tree().physics_frame
		rest_frames += 1
	print("EARNED_REST ",JSON.stringify({"seconds":rest_frames/60.0,"hp":_player.current_hp,"mp":_player.current_mp}))
	if not await _travel_story("lava","c5:beacon",false): return
	if not await _after_earned_travel(): return
	if not await _normal_stage(C6,1): return
	var actions := _stage_actions(C6,2)
	if not await _do_action(actions[0]): return
	if not await _cw(actions[1]["object"]): return
	var boss := _original_boss()
	_check(boss != null and boss.is_alive,"original live turtle present")
	if boss == null: return
	_world._stream_pass()
	await _frames(4)
	var body: MonsterBase = _world._nodes.get(boss.id)
	_check(body != null,"original turtle collision body streamed")
	if body == null: return
	var query := _walk_query()
	var candidates: Array[Vector2] = []
	for radius: float in [72.0,88.0]:
		for direction: Vector2 in [Vector2.DOWN,Vector2.LEFT,Vector2.RIGHT,Vector2.UP]:
			var at := body.global_position + direction*radius
			var grid_center := (at/32.0).floor()*32.0+Vector2(16,16)
			if not _walk_blocked(at,query) and not _walk_blocked(grid_center,query): candidates.append(at)
	candidates.sort_custom(func(a: Vector2,b: Vector2) -> bool: return _player.global_position.distance_squared_to(a)<_player.global_position.distance_squared_to(b))
	_check(not candidates.is_empty(),"physical melee approach exists")
	if candidates.is_empty() or not await _walk_to(candidates[0],"walk actual original fortress into combat position",8.0): return
	_budget = _receipt_budget()
	_check(GameState.stats.level == 3 and GameState.stats.strength == 7 and GameState.stats.agility == 5 and GameState.stats.intellect == 5,"only two earned points allocated")
	_check(_player._protect_timer <= 0 and _player._hurt_iframes <= 0,"no protection/invulnerability at cold save")
	print("EARNED_PREFIGHT ",JSON.stringify({"receipts":_budget,"gold":GameState.gold,"inventory":GameState.inventory,"level":GameState.stats.level,"xp":GameState.stats.xp,
		"strength":GameState.stats.strength,"hp":_player.current_hp,"max_hp":GameState.stats.max_hp(),"mp":_player.current_mp,"attack":GameState.stats.physical_attack(),
		"weapon":GameState.stats.upgrade_weapon,"vigor":GameState.stats.upgrade_vigor,"boss_id":boss.id,"boss_age":boss.age,"boss_anchor":[boss.spawn_pos.x,boss.spawn_pos.y],"boss_hp":body.current_hp,"boss_max_hp":boss.max_hp(),
		"equipment_build":_earned_equipment_report(),"player_position":[_player.global_position.x,_player.global_position.y],"setup":"genuine C5 ledger; discard capacity fixture stock; retain only paid chapter bonuses; shop methods; natural rest; real campaign travel and walking; freeze ecology/unrelated actors"}))

func _fight_earned(reckless: bool) -> void:
	var boss := _original_boss()
	_check(boss != null and boss.is_alive,"cold original turtle remains alive")
	if boss == null: return
	_world._stream_pass()
	await _frames(4)
	var body: Guardian = _world._nodes.get(boss.id)
	_check(body != null,"cold original turtle body")
	if body == null: return
	_check_earned_build()
	_check(GameState.count_item("onigiri") == 5 and GameState.count_item("life-pot") == 0 and GameState.count_item("water-pot") == 0,"cold finite stock is five paid bonus onigiri")
	_check(_player._protect_timer <= 0 and _player._hurt_iframes <= 0,"cold save has no protected opening")
	if _mobile:
		await _configure_mobile()
		if _fails > 0: return
	var initial_hp := _player.current_hp
	var initial_boss_hp := body.current_hp
	var initial_anchor := boss.spawn_pos
	var age := boss.age
	var start_gold := GameState.gold
	var min_hp := initial_hp
	var min_mp := _player.current_mp
	var windups := 0
	var smashes := 0
	var hits := 0
	var guard_inputs := 0
	var dash_inputs := 0
	var attack_inputs := 0
	var heavy_inputs := 0
	var empower_inputs := 0
	var heals := 0
	var old_state := body.state
	var previous_hp := initial_hp
	var distance_travelled := 0.0
	var previous_position := body.global_position
	var food_start := GameState.count_item("onigiri")
	var actual_dashes := 0
	var guard_frames := 0
	var old_dash_cd := 0.0
	var frame := 0
	var guard_demo_done := false
	var open_hit_done := false
	_world.set_process(false)
	body.set_physics_process(true)
	_player.set_physics_process(true)
	_player.set_process(true)
	_combat_active = true
	# One neutral physical frame releases the modal fresh-press gate naturally.
	await get_tree().physics_frame
	while frame < 60*300 and boss.is_alive and not _player._is_dead:
		var distance := _player.global_position.distance_to(body.global_position)
		var toward := _player.global_position.direction_to(body.global_position)
		TouchInput.joystick_active = true
		TouchInput.move_vector = Vector2.ZERO
		if _player._dash_timer <= 0.0: _player.facing = toward
		if reckless:
			TouchInput.move_vector = toward if distance > 60.0 else Vector2.ZERO
			TouchInput.queue_attack()
			attack_inputs += 1
		elif not open_hit_done:
			# One real opening smash proves the Boss can damage this normal build.
			if _mobile:
				if guard_inputs == 0: _control_touch("ShieldBtn",true,8)
			else: TouchInput.begin_guard()
			guard_inputs += 1
			if _player.current_hp < initial_hp-40.0:
				open_hit_done = true
				if _mobile: _control_touch("ShieldBtn",false,8)
				else: TouchInput.release_guard()
				guard_demo_done = true
		else:
			if _player.current_hp < _player.stats.max_hp()*0.64 and GameState.count_item("onigiri") > 0:
				if _mobile:
					var food_before := GameState.count_item("onigiri")
					await _mobile_tap(_hud.get_node("Root/QuickSlotBtn"))
					_check(GameState.count_item("onigiri") == food_before-1,"configured mobile recovery consumes exactly one onigiri")
				else: EventBus.item_use_requested.emit("onigiri")
			if body.state == Guardian.S_WINDUP:
				if not _retreat_active:
					_retreat_direction = _choose_retreat(body)
					_retreat_active = true
				TouchInput.move_vector = _retreat_direction if distance < 148.0 else Vector2.ZERO
				if (body._state_timer < 0.12 or dash_inputs == 0) and distance < 126.0 and _player._dash_cd <= 0 and _player.current_mp >= CharacterStats.DASH_COST:
					if _mobile: _press_control("DashBtn")
					else: TouchInput.queue_dash()
					dash_inputs += 1
			else:
				_retreat_active = false
				TouchInput.move_vector = toward if distance > 59.0 else Vector2.ZERO
				if distance < 90.0:
					if _mobile: _press_control("AttackBtn")
					else: TouchInput.queue_attack()
					attack_inputs += 1
					if _player._empower_cd <= 0 and _player.current_mp >= 55 and body._attack_cd > 2.0:
						if _mobile: await _more_skill("EmpowerBtn","empower",CharacterStats.EMPOWER_COST)
						else: TouchInput.queue_empower()
						empower_inputs += 1
					if _player._heavy_cd <= 0 and _player.current_mp >= 40 and body.state != Guardian.S_WINDUP and body._attack_cd > 1.0:
						if _mobile:
							var mp_before := _player.current_mp
							await _mobile_tap(_hud.get_node("Root/ShortcutBtn"))
							_ui_costs.append({"skill":"heavy","mp_before":mp_before,"mp_after":_player.current_mp,"cooldown":_player._heavy_cd})
							_check(_player._heavy_cd > 0 and _player.current_mp < mp_before-18.0,"touch preset heavy uses22MP and real4s cooldown")
						else: TouchInput.queue_heavy()
						heavy_inputs += 1
				if _player.current_hp < 55 and _player.current_mp >= 40 and _player._heal_cd <= 0:
					if _mobile: await _more_skill("HealBtn","heal",CharacterStats.HEAL_COST)
					else: TouchInput.queue_heal()
					heals += 1
		await get_tree().physics_frame
		frame += 1
		if _player.guard_state in ["raising","guarding"]: guard_frames += 1
		if _player._dash_cd > old_dash_cd+0.1: actual_dashes += 1
		old_dash_cd = _player._dash_cd
		if body.state == Guardian.S_WINDUP and old_state != Guardian.S_WINDUP: windups += 1
		if body.state != Guardian.S_WINDUP and old_state == Guardian.S_WINDUP: smashes += 1
		old_state = body.state
		if _player.current_hp < previous_hp-1.0: hits += 1
		previous_hp = _player.current_hp
		min_hp = minf(min_hp,_player.current_hp)
		min_mp = minf(min_mp,_player.current_mp)
		distance_travelled += previous_position.distance_to(body.global_position)
		previous_position = body.global_position
		if frame%600 == 0: print("EARNED_COMBAT_PROGRESS ",JSON.stringify({"seconds":frame/60.0,"hp":_player.current_hp,"boss_hp":body.current_hp,"mp":_player.current_mp,"distance":distance,"windups":windups,"food":GameState.count_item("onigiri")}))
	_combat_active = false
	TouchInput.reset()
	_player.set_physics_process(false)
	_player.set_process(false)
	body.set_physics_process(false)
	var report := {"scenario":"reckless" if reckless else ("mobile_expert_main_only" if _mobile else "expert_main_only"),"seconds":_combat_seconds,"loop_seconds":frame/60.0,"ui_costs":_ui_costs,"won":not boss.is_alive,"died":_player._is_dead,"hp_start":initial_hp,"hp_end":_player.current_hp,"hp_min":min_hp,"mp_min":min_mp,
		"boss_hp_start":initial_boss_hp,"boss_hp_end":body.current_hp,"boss_id":boss.id,"boss_age":boss.age,"boss_anchor_unchanged":boss.spawn_pos==initial_anchor,"windups":windups,"smashes":smashes,"damage_events":hits,"boss_walked_px":distance_travelled,
		"guard_active_frames":guard_frames,"actual_dashes":actual_dashes,"food_used":food_start-GameState.count_item("onigiri"),"attack_inputs":attack_inputs,"dash_inputs":dash_inputs,"shield_inputs":guard_inputs,"heavy_inputs":heavy_inputs,"empower_inputs":empower_inputs,"heals":heals,"gold_before_kill":start_gold,
		"equipment_build":_earned_equipment_report(),"limitations":"expert frame-aware AI-state bot; frozen ecology/unrelated actors; no damage/stat/HP/anchor/invulnerability edits; genuine C1-C5 ledger, bounded cleaned stock; normal natural regen; 1/60 game-second physics"}
	print("EARNED_COMBAT_RESULT ",JSON.stringify(report))
	_check(boss.age == age and boss.spawn_pos == initial_anchor,"original Boss age and anchor not modified")
	_check(windups > 0 and smashes > 0 and hits > 0,"original AI attacked and truly damaged normal player")
	if reckless:
		_check(_player._is_dead and boss.is_alive,"reckless ordinary build dies to live original turtle")
	else:
		_check(not _player._is_dead and not boss.is_alive,"expert ordinary earned build defeats original live turtle")
		_check(guard_frames > 0 and actual_dashes > 0,"real input raises shield and spends actual dash cooldown")
		_check(distance_travelled>1.0 and guard_demo_done,"Boss genuinely moves; shield was used against unblockable opening")
		if not boss.is_alive:
			var kill: Dictionary = _cq().get("main_kills",{}).get("熔岩龟王",{})
			_check(int(kill.get("instance_id",-1)) == boss.id and kill.get("player_kill",false),"real Boss death yields exact original-ID personal contribution")
			var actions := _stage_actions(C6,2)
			if not await _do_action(actions[1],"defeated"): return
			await _do_action(actions[2])

func _choose_retreat(body: MonsterBase) -> Vector2:
	var outward := body.global_position.direction_to(_player.global_position)
	var query := _walk_query()
	var best := outward
	var best_score := -INF
	for step in 16:
		var direction := outward.rotated(step*TAU/16.0)
		var reachable := 0.0
		for distance: float in [16.0,32.0,48.0,64.0,80.0,96.0,112.0,128.0,144.0]:
			var at := _player.global_position+direction*distance
			if _walk_blocked(at,query) or ObstacleField.liquid_kind_at(at) == "lava": break
			reachable = distance
		var endpoint := _player.global_position+direction*reachable
		var score := body.global_position.distance_to(endpoint)+reachable*0.2
		if score > best_score:
			best_score = score
			best = direction
	return best

func _control_touch(id: String, pressed: bool, index := 7) -> void:
	var control: Control = _hud.get_node("Root/"+id)
	_step_touch(index,pressed,control.get_global_rect().get_center())

func _press_control(id: String) -> void:
	_control_touch(id,true)
	_control_touch(id,false)

func _mobile_tap(control: Control) -> void:
	# Raw injected touches do not synthesize the OS mouse-emulation events used
	# by standard Godot tabs. Send the same pair as a physical touch device.
	# Custom multi-touch actions explicitly reject the emulated mouse press.
	print("MOBILE_TAP ",control.name," rect=",control.get_global_rect()," viewport=",get_viewport().get_visible_rect()," page=",_hud._more_page," presets=",GameState.settings.mobile_shortcut,",",GameState.settings.mobile_recovery)
	var at := get_viewport().get_screen_transform()*control.get_global_rect().get_center()
	for pressed: bool in [true,false]:
		var touch := InputEventScreenTouch.new()
		touch.index = 7
		touch.position = at
		touch.pressed = pressed
		Input.parse_input_event(touch)
		var mouse := InputEventMouseButton.new()
		mouse.device = InputEvent.DEVICE_ID_EMULATION
		mouse.position = at
		mouse.button_index = MOUSE_BUTTON_LEFT
		mouse.pressed = pressed
		Input.parse_input_event(mouse)
		await _frames(2)

func _configure_mobile() -> void:
	await _mobile_tap(_hud.get_node("Root/MoreBtn"))
	_check(_hud._more_panel.visible and not get_tree().paused,"touch More opens without pausing live world")
	await _mobile_tap(_hud._more_panel.find_child("MoreTab_shortcut",true,false))
	await _mobile_tap(_hud._more_panel.find_child("ShortcutPreset_heavy",true,false))
	await _mobile_tap(_hud._more_panel.find_child("MoreTab_recovery",true,false))
	await _mobile_tap(_hud._more_panel.find_child("RecoveryPreset_onigiri",true,false))
	await _mobile_tap(_hud._more_panel.find_child("MoreClose",true,false) if _close_probe else _hud.get_node("Root/MoreBtn"))
	print("MOBILE_PRESETS_FINAL ",GameState.settings.mobile_shortcut,",",GameState.settings.mobile_recovery," panel_visible=",_hud._more_panel.visible)
	_check(GameState.settings.mobile_shortcut == "heavy" and GameState.settings.mobile_recovery == "item:onigiri","real touch menu selects heavy and onigiri presets")

func _more_skill(id: String, kind: String, cost: float) -> void:
	var before := _player.current_mp
	await _mobile_tap(_hud.get_node("Root/MoreBtn"))
	_check(_hud._more_panel.visible and not get_tree().paused,"live combat More remains unpaused")
	var control: Control = _hud._more_panel.find_child(id,true,false)
	_check(control.is_visible_in_tree(),"requested skill physically visible in More: "+id)
	await _mobile_tap(control)
	await _mobile_tap(_hud.get_node("Root/MoreBtn"))
	var cooldown: float = _player.get("_"+kind+"_cd")
	_ui_costs.append({"skill":kind,"mp_before":before,"mp_after":_player.current_mp,"cooldown":cooldown,"expected_cost":cost})
	_check(cooldown > 0 and _player.current_mp < before-cost+5.0,"real More touch consumes skill MP and starts cooldown: "+kind)

func _age_ecology() -> void:
	_world.set_process(false)
	_player.set_process(false)
	var boss := _original_boss()
	var original_id := boss.id
	var original_anchor := boss.spawn_pos
	var original_age := boss.age
	var original_tick := WorldSim.sim.tick_count
	var original_population := WorldSim.sim.instances.size()
	var original_player := _player.save_snapshot()
	var extra_ticks := maxi(0,1400-boss.age)
	for i in extra_ticks:
		# Production bridge advances days and authoritative simulation together.
		# No age, species, breeding, density, lifespan or combat field is assigned.
		WorldSim._process(WorldSim.TICK_INTERVAL)
		if i%20 == 0: await get_tree().process_frame
	_check(boss.id == original_id and boss.is_alive and boss.age == 1400 and boss.spawn_pos == original_anchor,
		"normal ecology ticks preserve original live turtle identity/anchor and advance age to1400")
	_check(_same(original_player,_player.save_snapshot()),"ecology aging does not refill or move player")
	print("EARNED_ECOLOGY_AGING ",JSON.stringify({"original_id":original_id,"original_age":original_age,"age":boss.age,"ticks_advanced":WorldSim.sim.tick_count-original_tick,
		"population_before":original_population,"population_after":WorldSim.sim.instances.size(),"max_hp":boss.max_hp(),"hp_mirror":boss.hp_mirror,"game_day":WorldSim.game_day,
		"method":"1199 normal WorldSim bridge ticks; no ecology parameters or Boss fields edited; not cumulative human play"}))

func _finish_story() -> void:
	_read_defeat()
	if _fails > 0: return
	var core := _stage_actions(C6,3)
	for object_id: String in core[0]["puzzle_objects"]:
		if not await _cw(object_id): return
		await _ci(object_id)
	_check(not _proof(C6+":s3",C6+":s3:core_order").is_empty(),"earned original Boss path physically unlocks core")
	if not await _do_action(core[1]): return
	await _ending()
	print("EARNED_STORY_COMPLETE ",JSON.stringify({"ending":_cq().get("ending",{}),"level_after_legitimate_boss_xp":GameState.stats.level,"gold":GameState.gold,"inventory":GameState.inventory,"boss_kill":_cq().get("main_kills",{}).get("熔岩龟王",{})}))

func _finish() -> void:
	print("=== CAMPAIGN EARNED BOSS %s (%d checks, %d failures) ===" % ["PASS" if _fails==0 else "FAIL",_checks,_fails])
	get_tree().quit(0 if _fails==0 else 1)


## 仅供派生验收夹具替换合法购买方案；默认路径和旧断言保持原样。
func _purchase_earned_upgrades() -> void:
	for kind: String in ["weapon","vigor"]:
		for _i in 2: _check(GameState.buy_upgrade(kind),"actual affordable shop upgrade "+kind)
	_check(GameState.gold == 11 and GameState.count_item("onigiri") == 5,"291gold minus280 upgrades =11; five bonus food only")


func _after_earned_travel() -> bool:
	return true


func _check_earned_build() -> void:
	_check(GameState.stats.level == 3 and GameState.stats.strength == 7 and GameState.stats.upgrade_weapon == 2 and GameState.stats.upgrade_vigor == 2,"cold build is Lv3/STR7/weapon2/vigor2")


func _earned_equipment_report() -> Dictionary:
	return {}
