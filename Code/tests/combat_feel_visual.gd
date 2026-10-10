## 战斗表现取证：正式世界、角色、HUD与特效，固定遭遇但真实推进动作和命中。
## 原生SubViewport尺寸；只读回引擎渲染像素，不缩放/拼装截图，不接触玩家存档。
## 无头模式只验证取证路径和相位，绝不能当作图形验收。
extends Node

const MAIN := preload("res://scenes/main/main.tscn")
const FIXED_ACTIONS := ["AttackBtn", "ShieldBtn", "DashBtn", "ShortcutBtn", "QuickSlotBtn", "MoreBtn"]
var _world: Node2D
var _player: Player
var _hud: CanvasLayer
var _viewport: SubViewport
var _size := Vector2i(1280, 720)
var _origin := Vector2.ZERO
var _output := ""
var _headless := false
var _failures := 0
var _checks := 0
var _target: MonsterBase
var _records: Array[Dictionary] = []

func _ready() -> void:
	_headless = OS.get_environment("HOTW_COMBAT_VISUAL_HEADLESS") == "1"
	_output = OS.get_environment("HOTW_COMBAT_VISUAL_DIR")
	if _output.is_empty():
		_output = "/tmp/hotw-combat-feel-visual"
	DirAccess.make_dir_recursive_absolute(_output)
	var parts := OS.get_environment("HOTW_COMBAT_VISUAL_SIZE").split("x")
	if parts.size() == 2:
		_size = Vector2i(int(parts[0]), int(parts[1]))
	GameState.save_enabled = false
	GameState.reset_all()
	GameState.world_seed = 20260908
	GameState.ecology_snapshot = null
	GameState.settings.auto_aim = false
	GameState.settings.screen_shake = false
	TouchInput.reset()
	seed(20261009)
	_viewport = SubViewport.new()
	_viewport.name = "NativeLandscapeCapture"
	_viewport.size = _size
	_viewport.world_2d = World2D.new()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	_world = MAIN.instantiate()
	_viewport.add_child(_world)
	_player = _world.get_node("Player") as Player
	_hud = _world.get_node("HUD")
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])

func _frames(count := 1) -> void:
	for _i in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func _until(predicate: Callable, label: String, limit := 1200) -> bool:
	for _i in limit:
		if predicate.call():
			return true
		await _frames()
	_check(false, "取证相位超时：" + label)
	return false

func _run() -> void:
	await _frames(90)
	WorldSim.set_process(false)
	_world.set_process(false)
	# 隔离本次遭遇；选中演员保留正式物理/AI，未选中世界怪不参与测试。
	for actor in get_tree().get_nodes_in_group("monsters"):
		actor.set_physics_process(false)
		actor.hide()
		actor.collision_layer = 0
		actor.collision_mask = 0
	_origin = ObstacleField.nudge_free(WorldConfig.spawn_pos() + Vector2(420, 150), 200.0)
	_player.teleport_to(_origin)
	_player.set_process(false)
	_player.current_hp = _player.stats.max_hp()
	_player.current_mp = _player.stats.max_mp()
	_player.facing = Vector2.RIGHT
	_player.get_node("Camera2D").snap_to_player()
	_player._push_hud()
	await _frames(8)
	# 慢放只延长观察时间；仍由正式物理delta推进，保留真实顿帧控制器。
	Engine.time_scale = 0.35
	_hud_contract()
	await _capture("hud_idle")
	await _hero_actions()
	await _stagger_actions()
	await _melee_actions()
	await _ranged_actions()
	await _charger_actions()
	await _boss_actions()
	await _remove_target()
	await _frames(120)
	var budget: Dictionary = _world.get_node("EquipmentParticles").budget_snapshot()
	_check(int(budget.pool_size) == EquipmentParticleLayer.MAX_EMITTERS,
		"装备特效保持固定池大小")
	_check(int(budget.peak_emitters) <= EquipmentParticleLayer.MAX_EMITTERS \
		and int(budget.peak_particles) <= EquipmentParticleLayer.MAX_PARTICLES,
		"本次真实遭遇不超过装备粒子预算")
	_check(_player.get_node_or_null("SkillFeedback") != null,
		"技能预备复用玩家单节点")
	_hud_contract()
	await _capture("hud_settled")
	Engine.time_scale = 1.0
	var report := {"size": [_size.x, _size.y], "headless_state_only": _headless,
		"checks": _checks, "failures": _failures, "captures": _records,
		"equipment_budget": budget, "fixture": "Generated deterministic encounter; ecology/background enemies paused; durable stationary target for hero shots; selected combat actors and effects tick through production physics",
		"scope": "Linux Godot 4.7 OpenGL compatibility; not device/Metal performance or touch feel acceptance"}
	var file := FileAccess.open(_output.path_join("states.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	var mode := "STATE" if _headless else "VISUAL"
	print("=== COMBAT FEEL %s %s (%d checks, %d captures) ===" % [mode,
		"PASS" if _failures == 0 else "FAIL", _checks, _records.size()])
	get_tree().quit(0 if _failures == 0 else 1)

func _hud_contract() -> void:
	var root: Control = _hud.get_node("Root")
	var visible_count := 0
	for id: String in FIXED_ACTIONS:
		var button: Control = root.get_node(id)
		visible_count += int(button.is_visible_in_tree())
		_check(root.get_global_rect().encloses(button.get_global_rect()), id + "横屏安全区内")
		_check(not button.get_global_rect().intersects(root.get_node("Joystick").get_global_rect()), id + "避开摇杆")
	_check(visible_count == 6, "六个常驻动作按钮")
	_check(_hud._hud_plate.get_global_rect().encloses(_hud.hp_bar.get_global_rect()) \
		and _hud._hud_plate.get_global_rect().encloses(_hud.mp_bar.get_global_rect()), "生命/精力位于紧凑底板内")

func _remove_target() -> void:
	if is_instance_valid(_target):
		_target._clear_attack_context()
		_world._nodes.erase(_target.inst.id)
		_world._boss_ids.erase(_target.inst.id)
		_target.queue_free()
		_target = null
		await _frames(2)
	Projectile.clear_pool()
	PlayerBolt.clear_pool()

func _spawn(id: String, offset: Vector2) -> MonsterBase:
	await _remove_target()
	_player.teleport_to(_origin)
	_player.current_hp = _player.stats.max_hp()
	_player.current_mp = _player.stats.max_mp()
	_player._protect_timer = 0.0
	_player._hurt_iframes = 0.0
	_player._push_hud()
	var species: SpeciesData = load("res://data/species/%s.tres" % id)
	var region: SimRegion = WorldSim.sim.region_of_point(_origin)
	var size_scale := species.boss_size_scale if species.is_boss else 1.0
	var inst := WorldSim.sim.spawn_instance(species, region.id, 200, 0, size_scale, false, _origin + offset)
	await _frames(2)
	_target = _world._nodes.get(inst.id) as MonsterBase
	if _target == null:
		_check(false, "真实世界生成" + id)
		get_tree().quit(1)
		return null
	_target.set_physics_process(false)
	_target.global_position = _origin + offset
	_target._player_ref = _player
	_target._aggro_lock = 100.0
	_target._attack_cd = 0.0
	_target._nav.avoidance_enabled = true
	_target.state = MonsterBase.S_CHASE
	_target.show()
	_world._update_boss_track()
	await _frames(2)
	return _target

func _hero_actions() -> void:
	var enemy := await _spawn("goblin", Vector2(53, 0))
	# 高生命夹具避免第二刀前奖励/死亡干扰；不改任何伤害公式。
	enemy.current_hp = 10000.0
	_player.facing = Vector2.RIGHT
	_player._attack_cooldown = 0.0
	_player._try_attack()
	await _until(func(): return _player._attack_elapsed >= 0.08, "轻击前摇")
	await _capture("hero_light_windup")
	await _until(func(): return _player._attack_elapsed >= Player.ATTACK_WINDUP + 0.015, "轻击命中")
	await _capture("hero_light_impact")
	await _until(func(): return _player._attack_elapsed >= Player.ATTACK_WINDOW + 0.005, "轻击收招")
	await _capture("hero_light_recovery")
	await _until(func(): return _player._attack_anim_linger <= 0.0, "轻击结束")
	for kind: String in ["heavy", "bolt"]:
		_player.teleport_to(_origin)
		_player.facing = Vector2.RIGHT
		enemy.global_position = _origin + Vector2(74, 0)
		_player.current_mp = _player.stats.max_mp()
		if kind == "heavy":
			_player._heavy_cd = 0.0
			_player._try_heavy_attack()
		else:
			_player._bolt_cd = 0.0
			_player._try_cast_bolt()
		await _until(func(): return _player._skill_elapsed >= _player._skill_windup() * 0.5, kind + "前摇")
		_check(not _player._skill_released, kind + "前摇尚未释放")
		await _capture("hero_%s_windup" % kind)
		await _until(func(): return _player._skill_released, kind + "释放")
		await _capture("hero_%s_impact" % kind)
		await _until(func(): return _player._skill_elapsed >= _player._skill_windup() + _player._skill_impact_time() + 0.015, kind + "收招")
		await _capture("hero_%s_recovery" % kind)
		await _until(func(): return _player._skill_action.is_empty(), kind + "结束")
		await _frames(24)

## 真实出刀击中仍在运行的敌人；取证受击打断与重整，不只摆hurt帧。
func _stagger_actions() -> void:
	for heavy: bool in [false, true]:
		var enemy := await _spawn("goblin", Vector2(47, 0))
		enemy.current_hp = 10000.0
		enemy._attack_cd = 100.0
		enemy.set_physics_process(true)
		_player.facing = Vector2.RIGHT
		_player.current_mp = _player.stats.max_mp()
		if heavy:
			_player._heavy_cd = 0.0
			_player._try_heavy_attack()
		else:
			_player._attack_cooldown = 0.0
			_player._try_attack()
		await _until(func(): return enemy._stagger_timer > 0.0, "真实命中削韧")
		await _capture("enemy_stagger_heavy" if heavy else "enemy_stagger_light")
		_check(enemy._melee_windup <= 0.0 and enemy._attack_context.is_empty(), "受击硬直撤销待发攻击")
		await _until(func(): return enemy._stagger_timer <= 0.0, "削韧恢复")
		if heavy:
			await _capture("enemy_stagger_cleared")
		enemy.set_physics_process(false)
		await _until(func(): return _player._skill_action.is_empty() and _player._attack_anim_linger <= 0.0, "出刀结束")

func _melee_actions() -> void:
	var enemy := await _spawn("goblin", Vector2(30, 0))
	enemy.state = MonsterBase.S_ATTACK
	enemy.set_physics_process(true)
	await _until(func(): return enemy._melee_windup > 0.04, "近战前摇")
	await _frames(8)
	await _capture("enemy_melee_windup")
	await _until(func(): return enemy._attack_recovery > 0.0, "近战命中")
	await _capture("enemy_melee_impact")
	await _until(func(): return enemy._attack_recovery < enemy.inst.species.melee_recovery_time * 0.55, "近战收招")
	await _capture("enemy_melee_recovery")
	enemy.set_physics_process(false)

func _ranged_actions() -> void:
	var enemy := await _spawn("spider", Vector2(175, 0)) as Spider
	enemy.set_physics_process(true)
	await _until(func(): return enemy.state == Spider.S_SPIT_WINDUP, "远程前摇")
	await _frames(10)
	await _capture("enemy_ranged_windup")
	await _until(func(): return enemy._attack_recovery > 0.0, "远程释放")
	await _capture("enemy_ranged_impact")
	await _frames(18)
	await _capture("enemy_ranged_recovery")
	enemy.set_physics_process(false)

func _charger_actions() -> void:
	var enemy := await _spawn("boar", Vector2(210, 0)) as Boar
	enemy.set_physics_process(true)
	await _until(func(): return enemy.state == Boar.S_TELL, "冲锋前摇")
	await _frames(20)
	await _capture("enemy_charge_windup")
	await _until(func(): return enemy.state == Boar.S_CHARGE, "冲锋启动")
	await _frames(12)
	await _capture("enemy_charge_active")
	await _until(func(): return enemy.state == Boar.S_TIRED, "冲锋接触硬直")
	await _capture("enemy_charge_recovery")
	enemy.set_physics_process(false)

func _boss_actions() -> void:
	var boss := await _spawn("turtle_king", Vector2(85, 0)) as Guardian
	_check(is_equal_approx(boss.inst.size_scale, boss.inst.species.boss_size_scale), "Boss取正式生态体型而非缩小替身")
	boss.set_physics_process(true)
	await _boss_move_capture(boss, Guardian.MOVE_STOMP, "stomp")
	# 只在两招间清冷却避免冗长等待；第二招由正式循环游标选择。
	await _until(func(): return boss.state == MonsterBase.S_CHASE, "Boss震地结束")
	_player.teleport_to(_origin)
	boss._attack_cd = 0.0
	await _boss_move_capture(boss, Guardian.MOVE_SWEEP, "sweep")
	await _until(func(): return boss.state == MonsterBase.S_CHASE, "Boss扇扫结束")
	_player.teleport_to(_origin)
	_player.current_hp = _player.stats.max_hp()
	# 正式承伤触发半血阶段；不是直接改阶段或摆出环形图案。
	var amount := (boss.current_hp - boss.inst.max_hp() * 0.5) / (1.0 - boss.inst.species.defense_reduction)
	boss.take_damage(amount, _player.global_position, true)
	_check(boss.state == Guardian.S_PHASE_CHANGE and boss._boss_phase == 2, "真实半血承伤触发第二阶段")
	await _frames(40)
	await _capture("boss_phase_transition")
	await _until(func(): return boss.state == MonsterBase.S_CHASE, "Boss阶段变化结束")
	await _capture("boss_phase_two_ready")
	boss._attack_cd = 0.0
	await _boss_move_capture(boss, Guardian.MOVE_ERUPTION, "eruption")
	boss.set_physics_process(false)
	# 低血条取正式承伤后的真实HUD；不绘制或替换血条像素。
	var low_damage := (boss.current_hp - boss.inst.max_hp() * 0.1) / (1.0 - boss.inst.species.defense_reduction)
	boss.take_damage(low_damage, _player.global_position)
	await _until(func(): return not is_instance_valid(boss._impact_feedback) or not boss._impact_feedback.active, "低血截图受击闪光结束")
	await _frames(45)
	_check(absf(boss.current_hp / boss.inst.max_hp() - 0.1) < 0.001, "Boss真实承伤至10%生命")
	await _capture("boss_hp_low")

func _boss_move_capture(boss: Guardian, move: int, tag: String) -> void:
	await _until(func(): return boss.state == Guardian.S_WINDUP and boss._current_move == move, "Boss " + tag + "前摇")
	await _frames(30)
	await _capture("boss_%s_windup" % tag)
	await _until(func(): return boss.state == Guardian.S_RECOVER, "Boss " + tag + "命中")
	await _capture("boss_%s_impact" % tag)
	await _until(func(): return boss.state == Guardian.S_RECOVER and not boss._ring.visible, "Boss " + tag + "收招")
	await _capture("boss_%s_recovery" % tag)

func _capture(name: String) -> void:
	_player._push_hud()
	_world._update_boss_track()
	# 不暂停SceneTree：暂停通知会清除正式粒子，造成假阴性截图。
	if not _headless:
		await RenderingServer.frame_post_draw
	_capture_phase_contract(name)
	_boss_toast_contract(name)
	var record := {"name": name, "physics_frame": Engine.get_physics_frames(),
		"player_position": [_player.global_position.x, _player.global_position.y],
		"player_animation": str(_player.visual.animation), "player_frame": _player.visual.frame,
		"attack_elapsed": _player._attack_elapsed, "skill": _player._skill_action,
		"skill_elapsed": _player._skill_elapsed, "skill_released": _player._skill_released,
		"player_hp": _player.current_hp, "player_mp": _player.current_mp,
		"hud_bounds": _hud_bounds_record()}
	if is_instance_valid(_target):
		record.merge({"enemy_species": _target.inst.species.species_name,
			"enemy_state": _target.state, "enemy_animation": str(_target.visual.animation),
			"enemy_frame": _target.visual.frame, "enemy_windup": _target._melee_windup,
			"enemy_size_scale": _target.inst.size_scale,
			"enemy_visual_scale": [_target.visual.scale.x, _target.visual.scale.y],
			"enemy_recovery": _target._attack_recovery, "enemy_hp": _target.current_hp,
			"enemy_stagger": _target._stagger_timer})
		if is_instance_valid(_target._attack_cue):
			record.merge({"enemy_cue_visible": _target._attack_cue.visible,
				"enemy_cue_reach": _target._attack_cue._reach,
				"enemy_cue_half_angle": _target._attack_cue._half_angle})
		if _target is Guardian:
			record.merge({"boss_phase": _target._boss_phase, "boss_move": _target._current_move,
				"boss_timer": _target._state_timer, "ring_visible": _target._ring.visible,
				"ring_shape": _target._ring.shape, "ring_impact": _target._ring.impact})
	var screen := _player.visual.get_global_transform_with_canvas().origin
	_check(Rect2(Vector2.ZERO, Vector2(_size)).has_point(screen), name + "玩家实际画布坐标在屏内")
	if not _headless:
		var image := _viewport.get_texture().get_image()
		if image == null or image.is_empty():
			_check(false, name + "要求真实图形渲染像素")
		else:
			_check(image.get_size() == _size, name + "原生横屏像素尺寸")
			var palette := {}
			for y in range(0, image.get_height(), maxi(1, image.get_height() / 36)):
				for x in range(0, image.get_width(), maxi(1, image.get_width() / 64)):
					palette[image.get_pixel(x, y).to_rgba32()] = true
			_check(palette.size() >= 24, name + "包含真实场景色彩而非空白帧")
			record["sampled_colors"] = palette.size()
			var path := _output.path_join(name + ".png")
			_check(image.save_png(path) == OK, name + "保存原始PNG")
			record["png"] = name + ".png"
	_records.append(record)
	print("COMBAT_FEEL_CAPTURE ", JSON.stringify(record))

## 截图名必须与读回当帧的真实相位吻合；慢图形机器也不能错标动作。
func _capture_phase_contract(name: String) -> void:
	if name.begins_with("hero_light_"):
		var elapsed := _player._attack_elapsed
		if name.ends_with("windup"):
			_check(elapsed < Player.ATTACK_WINDUP, name + "真实前摇")
		elif name.ends_with("impact"):
			_check(elapsed >= Player.ATTACK_WINDUP and elapsed < Player.ATTACK_WINDOW, name + "真实命中窗")
		else:
			_check(elapsed >= Player.ATTACK_WINDOW and _player._attack_anim_linger > 0.0, name + "真实收招")
	elif name.begins_with("hero_heavy_") or name.begins_with("hero_bolt_"):
		_check(not _player._skill_action.is_empty(), name + "动作仍活跃")
		if name.ends_with("windup"):
			_check(not _player._skill_released, name + "真实预备")
		elif name.ends_with("impact"):
			_check(_player._skill_released and _player._skill_elapsed < _player._skill_windup() + _player._skill_impact_time(), name + "真实释放窗")
		else:
			_check(_player._skill_released and _player._skill_elapsed >= _player._skill_windup() + _player._skill_impact_time(), name + "真实收招")
	elif name.begins_with("enemy_stagger_"):
		_check(_target._stagger_timer <= 0.0 if name.ends_with("cleared") else _target._stagger_timer > 0.0, name + "真实削韧状态")
	elif name.begins_with("enemy_melee_") or name.begins_with("enemy_ranged_") or name.begins_with("enemy_charge_"):
		_check(is_instance_valid(_target._attack_cue), name + "复用正式地面预警节点")
		if is_instance_valid(_target._attack_cue):
			_check(_target._attack_cue.visible == name.ends_with("windup"), name + "预警只在前摇可见")
		if name.begins_with("enemy_melee_"):
			_check(_target._melee_windup > 0.0 if name.ends_with("windup") else _target._attack_recovery > 0.0, name + "真实近战时相")
		elif name.begins_with("enemy_ranged_"):
			_check(_target.state == Spider.S_SPIT_WINDUP if name.ends_with("windup") else _target._attack_recovery > 0.0, name + "真实射击时相")
		else:
			var expected_state := Boar.S_TELL if name.ends_with("windup") else (Boar.S_CHARGE if name.ends_with("active") else Boar.S_TIRED)
			_check(_target.state == expected_state, name + "真实冲锋时相")
	elif name.begins_with("boss_") and _target is Guardian:
		if name.ends_with("windup"):
			_check(_target.state == Guardian.S_WINDUP and _target._ring.visible and not _target._ring.impact, name + "前摇几何仍可见")
		elif name.ends_with("impact"):
			_check(_target.state == Guardian.S_RECOVER and _target._ring.visible and _target._ring.impact, name + "真实结算帧")
		elif name.ends_with("recovery"):
			_check(_target.state == Guardian.S_RECOVER and not _target._ring.visible, name + "真实可反击恢复窗")
		elif name == "boss_phase_transition":
			_check(_target.state == Guardian.S_PHASE_CHANGE and _target._ring.shape == 3, name + "真实无伤过渡")

## 原图发现的Boss条/阶段提示遮挡必须成为门禁，不能只验节点visible。
func _boss_toast_contract(name: String) -> void:
	if not _hud._boss_layer.is_visible_in_tree():
		return
	var root: Control = _hud.get_node("Root")
	var boss_rect: Rect2 = _hud._boss_layer.get_global_rect()
	_check(root.get_global_rect().encloses(boss_rect), name + "Boss标题与血条位于安全区")
	var radar_rect: Rect2 = root.get_node("Minimap").get_global_rect()
	_check(not boss_rect.intersects(radar_rect), name + "Boss丝带与雷达不重叠")
	_check(radar_rect.position.x - boss_rect.end.x >= 11.5, name + "Boss丝带与雷达至少12px间隔")
	if _hud.toast_label.is_visible_in_tree() and _hud.toast_label.modulate.a > 0.05 			and not _hud.toast_label.text.is_empty():
		var toast_rect: Rect2 = _hud.toast_label.get_global_rect()
		_check(not toast_rect.intersects(boss_rect.grow(1.0)), name + "真实提示与Boss条不重叠")
		_check(root.get_global_rect().encloses(toast_rect), name + "真实提示完整位于安全区")

func _rect_values(rect: Rect2) -> Array:
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]

func _hud_bounds_record() -> Dictionary:
	return {"boss_visible": _hud._boss_layer.is_visible_in_tree(),
		"boss_rect": _rect_values(_hud._boss_layer.get_global_rect()),
		"boss_bar_rect": _rect_values(_hud._boss_bar.get_global_rect()),
		"radar_rect": _rect_values(_hud.get_node("Root/Minimap").get_global_rect()),
		"toast_rect": _rect_values(_hud.toast_label.get_global_rect()),
		"toast_alpha": _hud.toast_label.modulate.a, "toast_text": _hud.toast_label.text}
