## 英雄原画动作回归：真实输入、实际帧播放及中断生命周期，禁止 Guard 替身。
## 运行：godot --headless --path Code res://tests/hero_slash_motion_test.tscn
extends Node2D

const PLAYER := preload("res://scenes/player/player.tscn")
const GOBLIN := preload("res://scenes/monsters/goblin.tscn")
const SOURCE_KEYS := {"blue": "ninja", "dark": "ninja_dark", "white": "ninja_white"}
const DIRS := [Vector2.RIGHT, Vector2(1, 1), Vector2.DOWN, Vector2(-1, 1),
	Vector2.LEFT, Vector2(-1, -1), Vector2.UP, Vector2(1, -1)]
const STEP := 1.0 / 60.0
var _checks := 0
var _fails := 0
var _player: Player
var _targets: Array[MonsterBase] = []
var _origin := Vector2.ZERO
var _authored_anchor := Vector2.ZERO
var _watch := {}
var _texture_hashes := {}


func _ready() -> void:
	GameState.save_enabled = false
	GameState.ecology_snapshot = null
	GameState.reset_all()
	GameState.settings.auto_aim = false
	GameState.settings.screen_shake = false
	WorldSim.stop()
	WorldSim.sim = EcologySim.new()
	BiomeMap.configure(BiomeMap.DEFAULT_SEED)
	ObstacleField.restore_destroyed([])
	TouchInput.reset()
	_origin = WorldConfig.spawn_pos() + Vector2(0.25, 0.375)
	_run.call_deferred()


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])


func _step(count := 1) -> void:
	for _i in count:
		await get_tree().physics_frame
		await get_tree().process_frame
		_observe()


func _run() -> void:
	_resource_contract()
	await _skin_combo_direction_matrix()
	await _hit_phase_contract()
	await _blade_wall_clearance_contract()
	await _maximum_rate_contract()
	await _pause_contract()
	await _dash_and_pool_contract()
	await _teleport_and_death_contract()
	TouchInput.reset()
	await _clear_targets()
	_player.queue_free()
	await _step(2)
	WorldSim.stop()
	print("=== HERO SLASH MOTION %s (%d checks) ===" % ["PASS" if _fails == 0 else "FAIL", _checks])
	get_tree().quit(0 if _fails == 0 else 1)


func _hash(texture: Texture2D) -> int:
	var id := texture.get_instance_id()
	if not _texture_hashes.has(id):
		_texture_hashes[id] = hash(texture.get_image().get_data())
	return _texture_hashes[id]


func _resource_contract() -> void:
	_check(Player.HERO_SKINS.size() == 3, "三皮肤均纳入原画出招契约")
	_check(is_equal_approx(Player.ATTACK_REACH, 66.0)
		and is_equal_approx(Player.ATTACK_WINDUP, 0.16)
		and is_equal_approx(Player.ATTACK_WINDOW, 0.26)
		and is_equal_approx(Player.ATTACK_ANIM_LINGER, 0.06), "动作替换保留66px与0.16/0.26/0.32秒战斗边界")
	for skin: String in Player.HERO_SKINS:
		var frames: SpriteFrames = Player.HERO_SKINS[skin]
		var key: String = SOURCE_KEYS[skin]
		var source: SpriteFrames = load("res://assets/creatures/frames/%s/%s_frames.res" % [key, key])
		for anim: StringName in [&"idle", &"walk", &"hurt"]:
			var unchanged := frames.get_frame_count(anim) == source.get_frame_count(anim) \
				and frames.get_animation_loop(anim) == source.get_animation_loop(anim) \
				and is_equal_approx(frames.get_animation_speed(anim), source.get_animation_speed(anim))
			for index in mini(frames.get_frame_count(anim), source.get_frame_count(anim)):
				unchanged = unchanged and _hash(frames.get_frame_texture(anim, index)) == _hash(source.get_frame_texture(anim, index)) \
					and is_equal_approx(frames.get_frame_duration(anim, index), source.get_frame_duration(anim, index))
			_check(unchanged, "%s %s保留原始帧与节拍" % [skin, anim])
		var guards := {}
		for index in source.get_frame_count(&"hurt"):
			guards[_hash(source.get_frame_texture(&"hurt", index))] = true
		var grips: Dictionary = frames.get_meta("attack_grips", {})
		_check(str(frames.get_meta("hero_skin", "")) == skin, "%s 新帧表携带对应皮肤身份" % skin)
		for combo in range(1, 4):
			var anim := StringName("attack%d" % combo)
			var exists := frames.has_animation(anim)
			_check(exists and frames.get_frame_count(anim) == 4, "%s %s包含四段原画身体动作" % [skin, anim])
			if not exists:
				continue
			var distinct := {}
			var body_only := true
			for index in frames.get_frame_count(anim):
				var fingerprint := _hash(frames.get_frame_texture(anim, index))
				distinct[fingerprint] = true
				body_only = body_only and not guards.has(fingerprint)
				if source.has_animation(anim) and index < source.get_frame_count(anim):
					body_only = body_only and fingerprint != _hash(source.get_frame_texture(anim, index))
			_check(distinct.size() == 4 and body_only, "%s %s四帧均有身体变化且不复用Guard或带剑整帧" % [skin, anim])
			var points: Array = grips.get(anim, [])
			var valid_grips := points.size() == frames.get_frame_count(anim)
			for point in points:
				valid_grips = valid_grips and point is Vector2 and point.is_finite()
			_check(valid_grips, "%s %s每帧具有有限的原画握点" % [skin, anim])


func _new_player(skin: String) -> void:
	_watch = {}
	if is_instance_valid(_player):
		_player.queue_free()
		await _step(2)
	GameState.settings.hero_skin = skin
	_player = PLAYER.instantiate()
	_authored_anchor = _player.get_node("Visual").position
	add_child(_player)
	_player.get_node("Camera2D").enabled = false
	_player.stats.agility = 100
	_player.current_mp = 10000.0
	_player.visual.frame_changed.connect(_record_frame)
	_player.teleport_to(_origin)
	await _step(2)
	_check(_player.visual.sprite_frames == Player.HERO_SKINS[skin], "%s真实实例使用该皮肤的完整动作帧表" % skin)


func _face(direction: Vector2) -> void:
	_watch = {}
	_player.teleport_to(_origin)
	TouchInput.joystick_active = true
	TouchInput.move_vector = direction.normalized()
	await _step(3)
	TouchInput.move_vector = Vector2.ZERO
	await _step(8)
	for _i in 60:
		if _player._attack_cooldown <= 0.0:
			break
		await _step()


func _begin_watch(combo: int) -> void:
	_watch = {"anim": StringName("attack%d" % combo), "seen": {}, "samples": 0,
		"material_ok": true, "animation_ok": true, "anchor_error": 0.0,
		"grip_error": 0.0, "grip_samples": 0, "feet_ok": true}


## frame_changed 也会在 stop→play 的同步过渡内发出，只记录姿态；
## 动画、材质与握点不应在尚未完成的重启动作中作渲染断言。
func _record_frame() -> void:
	if _watch.is_empty() or not is_instance_valid(_player):
		return
	if _player._attack_anim_linger > 0.0 and _player.visual.animation == _watch.anim:
		_watch.seen[_player.visual.frame] = true


func _observe() -> void:
	if _watch.is_empty() or not is_instance_valid(_player):
		return
	if _player._attack_anim_linger <= 0.0:
		return
	var visual := _player.visual
	_watch.samples += 1
	_watch.material_ok = _watch.material_ok and visual.material == null
	_watch.animation_ok = _watch.animation_ok and visual.animation == _watch.anim
	_watch.anchor_error = maxf(_watch.anchor_error,
		visual.global_position.distance_to(_player.to_global(_authored_anchor)))
	_watch.feet_ok = _watch.feet_ok and is_equal_approx(_player._shadow.position.y, _player._feet_y)
	if visual.animation == _watch.anim:
		_record_frame()
		var grips: Dictionary = visual.sprite_frames.get_meta("attack_grips", {})
		var points: Array = grips.get(visual.animation, [])
		if visual.frame < points.size() and _player._weapon_visual.active:
			var point: Vector2 = points[visual.frame]
			if visual.flip_h:
				point.x = -point.x
			var expected := visual.to_global(point + visual.offset)
			var actual := _player._weapon_visual.to_global(_player._weapon_visual.grip)
			_watch.grip_error = maxf(_watch.grip_error, expected.distance_to(actual))
			_watch.grip_samples += 1


func _finish_watch(label: String, require_grip := true) -> void:
	_check(_watch.samples > 0 and _watch.animation_ok and _watch.seen.size() == 4,
		"%s真实播放观察到全部四帧，不以Guard代替出招（%s）" % [label, str(_watch.seen.keys())])
	_check(_watch.material_ok, "%s整个动作均无运行时裁切材质" % label)
	_check(_watch.anchor_error <= 0.71 and _watch.feet_ok,
		"%s身体与阴影维持固定脚点（偏差%.3fpx）" % [label, _watch.anchor_error])
	if require_grip:
		_check(_watch.grip_samples > 0 and _watch.grip_error <= 0.08,
			"%s独立剑握柄逐帧跟随原画手部（偏差%.3fpx）" % [label, _watch.grip_error])
	_watch = {}


func _skin_combo_direction_matrix() -> void:
	for skin: String in Player.HERO_SKINS:
		await _new_player(skin)
		for index in DIRS.size():
			var direction: Vector2 = DIRS[index].normalized()
			await _face(direction)
			for combo in range(1, 4):
				_begin_watch(combo)
				# 两个正式输入通道交替，既不直接调出招函数，也不手动设动画帧。
				if (index + combo) % 2 == 0:
					TouchInput.queue_attack()
				else:
					Input.action_press("attack")
				await _step()
				Input.action_release("attack")
				var label := "%s 第%d段 方向%d " % [skin, combo, index]
				_check(_player._combo == combo and _player._weapon_visual.active
					and _player._weapon_visual.aim.dot(direction) > 0.999
					and _player.visual.frame == 0, label + "真实输入同步起手与刀锋方向")
				await _step(24)
				_finish_watch(label)
				_check(not _player._weapon_visual.active and _player.attack_shape.disabled
					and _player.visual.material == null, label + "收招清理武器与伤害形状")


func _monster(offset: Vector2) -> MonsterBase:
	var monster: MonsterBase = GOBLIN.instantiate()
	add_child(monster)
	monster.set_physics_process(false)
	var species: SpeciesData = preload("res://data/species/goblin.tres").duplicate()
	var pos := _player.global_position + offset
	var inst := WorldSim.sim.spawn_instance(species, "slash_motion", 200, 0, 1.0, false, pos)
	monster.setup(inst)
	monster.global_position = pos
	monster.current_hp = 10000.0
	monster.collision_mask = 0
	_targets.append(monster)
	return monster


func _clear_targets() -> void:
	for target in _targets:
		if is_instance_valid(target):
			target.queue_free()
	_targets.clear()
	await _step(2)


func _hit_phase_contract() -> void:
	await _face(Vector2.RIGHT)
	for combo in range(1, 4):
		var near := _monster(Vector2(62, 0))
		var late := _monster(Vector2(180, 0))
		var far := _monster(Vector2(88, 0))
		var back := _monster(Vector2(-62, 0))
		await _step(2)
		TouchInput.queue_attack()
		var first_hit := -1.0
		var early_ok := true
		var late_moved := false
		for frame in 26:
			await _step()
			if _player._attack_elapsed < Player.ATTACK_WINDUP:
				early_ok = early_ok and near.current_hp == 10000.0 and _player.attack_shape.disabled
			if near.current_hp < 10000.0 and first_hit < 0.0:
				first_hit = _player._attack_elapsed
			# 全判定窗已结束后，另一个未命中的真实碰撞体才进入刀锋路径。
			if not late_moved and _player._attack_elapsed > Player.ATTACK_WINDOW:
				late.global_position = _player.global_position + Vector2(50, 0)
				late_moved = true
		_check(_player._combo == combo and early_ok and first_hit >= 0.16
			and first_hit <= 0.26 + STEP, "第%d段只在既定挥击物理步命中（%.3fs）" % [combo, first_hit])
		_check(late_moved and late.current_hp == 10000.0 and far.current_hp == 10000.0
			and back.current_hp == 10000.0 and _player._hit_this_swing.size() == 1,
			"第%d段无收招补刀、刀尖外误伤、背后误伤或重复结算" % combo)
		await _clear_targets()


## 对独立刀的实际握点→刀尖复核，不复用生产端裁切函数或角色原点射线。
## 前墙面距角色27px，复现右向握点约(20,-6)时蓄势刀锋越墙的问题。
func _blade_wall_clearance_contract() -> void:
	var clearance := CircleShape2D.new()
	clearance.radius = 8.0
	var total_drawable := 0
	var total_clipped := 0
	for index in DIRS.size():
		var direction: Vector2 = DIRS[index].normalized()
		await _face(direction)
		var wall := StaticBody2D.new()
		wall.collision_layer = 1
		wall.collision_mask = 0
		var shape := CollisionShape2D.new()
		var rectangle := RectangleShape2D.new()
		rectangle.size = Vector2(10.0, 180.0)
		shape.shape = rectangle
		wall.add_child(shape)
		add_child(wall)
		wall.global_position = _player.global_position + direction * 32.0
		wall.rotation = direction.angle()
		var target := _monster(direction * 62.0)
		await _step(2)
		for combo in range(1, 4):
			TouchInput.queue_attack()
			var phases := {}
			var drawable := 0
			var clear_start := true
			var clear_sweep := true
			for frame in 25:
				await _step()
				var weapon: Node2D = _player._weapon_visual
				if not weapon.active:
					continue
				var phase := "windup" if _player._attack_elapsed < Player.ATTACK_WINDUP \
					else ("strike" if _player._attack_elapsed < Player.ATTACK_WINDOW else "recovery")
				phases[phase] = true
				var hand: Vector2 = weapon.grip
				var tip: Vector2 = weapon.blade_tip
				# 独立重建未裁切端点，确保该夹具真的触发裁切而非只挥空。
				var uncut := Vector2.from_angle(weapon.blade_angle) * minf(weapon.blade_reach, 50.0)
				if weapon.windup:
					uncut = hand + Vector2.from_angle(weapon.blade_angle) * 30.0
					if uncut.length() > weapon.blade_reach:
						uncut = uncut.normalized() * weapon.blade_reach
				if tip.distance_to(uncut) > 0.1:
					total_clipped += 1
				# 与实际绘制的存在条件一致；被墙压到不足14px的刀不提交几何。
				if weapon.blade_reach <= maxf(10.0, hand.length() + 8.0) or hand.distance_to(tip) < 14.0:
					continue
				drawable += 1
				var query := PhysicsShapeQueryParameters2D.new()
				query.shape = clearance
				query.transform = Transform2D(0.0, weapon.to_global(hand))
				query.collision_mask = 1
				query.exclude = [_player.get_rid()]
				var space := get_world_2d().direct_space_state
				clear_start = clear_start and space.intersect_shape(query, 1).is_empty()
				query.motion = weapon.to_global(tip) - query.transform.origin
				var fractions := space.cast_motion(query)
				clear_sweep = clear_sweep and fractions[0] >= 0.999999
			total_drawable += drawable
			var label := "近墙方向%d第%d段 " % [index, combo]
			_check(_player._combo == combo and phases.size() == 3,
				label + "真实输入观察到蓄势、挥击、收招三阶段")
			_check(clear_start and clear_sweep,
				label + "实际握点到刀尖的8px包络全程不入墙（%d个可绘帧）" % drawable)
			_check(target.current_hp == 10000.0, label + "墙后真实怪物始终不受伤")
		wall.queue_free()
		await _clear_targets()
	_check(total_drawable > 0 and total_clipped > 0,
		"近墙回归确实覆盖%d个可绘刀帧与%d个实际裁切帧" % [total_drawable, total_clipped])


func _maximum_rate_contract() -> void:
	await _face(Vector2.RIGHT)
	var seen_by_swing: Array[Dictionary] = []
	var combos: Array[int] = []
	var previous_elapsed := 100.0
	var intervals: Array[int] = []
	var last_start := -1
	for frame in 125:
		if frame % 2 == 0:
			TouchInput.queue_attack()
		await _step()
		if _player._attack_elapsed < previous_elapsed:
			seen_by_swing.append({})
			combos.append(_player._combo)
			if last_start >= 0:
				intervals.append(frame - last_start)
			last_start = frame
		if not seen_by_swing.is_empty() and _player.visual.animation.begins_with("attack"):
			seen_by_swing[-1][_player.visual.frame] = true
		previous_elapsed = _player._attack_elapsed
	TouchInput.clear_queues()
	await _step(25)
	var complete := true
	# 最后一刀可能刚起手就退出循环；此前各刀都必须实际走过四个身体姿态。
	for index in maxi(0, seen_by_swing.size() - 1):
		complete = complete and seen_by_swing[index].size() == 4 \
			and combos[index] == index % 3 + 1
	var cadence_ok := not intervals.is_empty()
	for interval in intervals:
		cadence_ok = cadence_ok and interval >= 16 and interval <= 18
	_check(seen_by_swing.size() >= 7 and complete, "最高攻速预输入仍完整播放每刀四姿态并循环1→2→3")
	_check(cadence_ok, "最高攻速仍在16至18个物理步重触发，没有因视觉恢复拉长冷却")
	_check(not _player._weapon_visual.active and _player.attack_shape.disabled
		and _player.visual.material == null, "连续出招停止后无武器或材质残留")


func _pause_contract() -> void:
	await _face(Vector2.LEFT)
	var target := _monster(Vector2(-62, 0))
	await _step(2)
	TouchInput.queue_attack()
	await _step(4)
	var elapsed := _player._attack_elapsed
	var frame := _player.visual.frame
	var progress := _player.visual.frame_progress
	var angle: float = _player._weapon_visual.blade_angle
	var grip: Vector2 = _player._weapon_visual.grip
	var position_before := _player.visual.global_position
	get_tree().paused = true
	await get_tree().create_timer(0.12, true).timeout
	_check(_player._attack_elapsed == elapsed and _player.visual.frame == frame
		and _player.visual.frame_progress == progress and _player._weapon_visual.blade_angle == angle
		and _player._weapon_visual.grip == grip and _player.visual.global_position == position_before
		and target.current_hp == 10000.0, "暂停同时冻结身体帧、握点、刀锋时相与伤害")
	get_tree().paused = false
	await _step(25)
	_check(target.current_hp < 10000.0 and not _player._weapon_visual.active
		and _player.visual.material == null, "恢复后按剩余出招时相命中并正常收招")
	await _clear_targets()


func _dash_and_pool_contract() -> void:
	await _face(Vector2.DOWN)
	await _step(25) # 旧残影归池后，专门播种一个带旧材质的复用节点。
	var ghost := Sprite2D.new()
	add_child(ghost)
	ghost.texture = load("res://assets/creatures/frames/ninja/ninja_frames.res").get_frame_texture(&"attack1", 2)
	ghost.material = CanvasItemMaterial.new()
	VfxPool.release(ghost, "afterimage")
	var target := _monster(Vector2(0, 136))
	await _step(2)
	_begin_watch(1)
	TouchInput.queue_attack()
	await _step(3)
	TouchInput.queue_dash()
	await _step(2)
	_check(_player._dash_timer > 0.0 and _player._attack_anim_linger > 0.0
		and _player.visual.animation.begins_with("attack") and _player._weapon_visual.active,
		"攻击后冲刺保留原画身体和既有短窗dash-strike")
	var body_textures := {}
	for combo in range(1, 4):
		var anim := StringName("attack%d" % combo)
		for index in _player.visual.sprite_frames.get_frame_count(anim):
			body_textures[_hash(_player.visual.sprite_frames.get_frame_texture(anim, index))] = true
	_check(ghost.visible and ghost.material == null and body_textures.has(_hash(ghost.texture)),
		"实际冲刺复用的残影只有当前身体纹理，清除旧裁切材质与烘焙剑")
	await _step(30)
	_finish_watch("冲刺挥砍 ")
	_check(target.current_hp < 10000.0, "冲刺进入刀锋范围的真实目标仍可受到dash-strike伤害")
	_check(not ghost.visible and not _player._weapon_visual.active and _player.attack_shape.disabled,
		"冲刺结束后残影归池且伤害与独立剑结束")
	await _clear_targets()


func _teleport_and_death_contract() -> void:
	await _face(Vector2.UP)
	var old_target := _monster(Vector2(0, -62))
	await _step(2)
	TouchInput.queue_attack()
	await _step(4)
	_player.teleport_to(_origin + Vector2(180, 0))
	await _step(25)
	_check(old_target.current_hp == 10000.0 and not _player._weapon_visual.active
		and _player.visual.animation == &"idle" and _player.visual.material == null
		and _player.attack_shape.disabled, "传送清理未完成出招，旧地点无迟到命中")
	await _clear_targets()
	await _face(Vector2.RIGHT)
	TouchInput.queue_attack()
	await _step(4)
	_player._protect_timer = 0.0
	_player._hurt_iframes = 0.0
	_player.take_damage(_player.stats.max_hp() + 1.0, Vector2.INF, "slash lifecycle test")
	await _step()
	_check(_player._is_dead and not _player._weapon_visual.active and _player.attack_shape.disabled
		and _player.visual.material == null and not _player.visual.is_playing(),
		"真实致死伤害立即停止身体出招、刀锋与伤害形状")
	TouchInput.queue_attack()
	TouchInput.queue_dash()
	await _step(140)
	_check(not _player._is_dead and _player.visible and _player.visual.animation == &"idle"
		and _player.visual.is_playing() and _player.visual.material == null
		and not _player._weapon_visual.active and _player.attack_shape.disabled,
		"自然重生恢复完整站姿，死亡期间积压输入不补刀")
	await _step(35)
	_check(_player.visible and is_equal_approx(_player.visual.modulate.a, 1.0),
		"重生不会再被过期死亡淡出回调隐藏")
