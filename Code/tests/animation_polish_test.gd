## 动作表现回归：直接消费当前 .res 帧，验证状态转换、动作完整性及重复出招。
## 运行：godot --headless --path Code res://tests/animation_polish_test.tscn
extends Node2D

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
var _fails := 0
var _checks := 0

func _ready() -> void:
	GameState.save_enabled = false
	GameState.ecology_snapshot = null
	GameState.reset_all()
	WorldSim.stop()
	_run()

func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])

func _frames(key: String) -> SpriteFrames:
	return load("res://assets/creatures/frames/%s/%s_frames.res" % [key, key]) as SpriteFrames

func _length(frames: SpriteFrames, anim: StringName) -> float:
	var total := 0.0
	for i in frames.get_frame_count(anim):
		total += frames.get_frame_duration(anim, i)
	return total / frames.get_animation_speed(anim)

func _monster(key: String) -> MonsterBase:
	var monster := MonsterBase.new()
	var sprite := AnimatedSprite2D.new()
	sprite.name = "Visual"
	sprite.sprite_frames = _frames(key)
	monster.add_child(sprite)
	add_child(monster)
	monster.set_physics_process(false)
	monster.inst = MonsterInstance.new()
	monster.inst.species = load("res://data/species/goblin.tres")
	monster.current_hp = monster.inst.max_hp()
	MonsterBase._species_registry[monster.inst.species.species_name] = [monster]
	monster.visual.play("idle")
	return monster

func _run() -> void:
	await get_tree().process_frame
	var weighted := SpriteFrames.new()
	weighted.set_animation_speed("default", 10.0)
	var tex := _frames("ninja").get_frame_texture("idle", 0)
	weighted.add_frame("default", tex, 1.0)
	weighted.add_frame("default", tex, 3.0)
	_check(is_equal_approx(Player.SpritePlayback.duration(weighted, "default"), 0.4),
		"动作时长包含非等长帧权重")
	var player: Player = PLAYER_SCENE.instantiate()
	add_child(player)
	player.set_physics_process(false)
	player.get_node("Camera2D").enabled = false
	player.position = Vector2(300, 300)
	for skin: String in Player.HERO_SKINS:
		player.visual.sprite_frames = Player.HERO_SKINS[skin]
		player._attack_cooldown = 0.0
		player._combo = 0
		player.facing = Vector2.LEFT
		player.visual.flip_h = false
		player._try_attack()
		player._update_anim()
		_check(player._attack_anim_linger >= Player.ATTACK_WINDOW + Player.ATTACK_ANIM_LINGER - 0.001,
			"%s 攻击判定与收招窗口串联" % skin)
		_check(_length(player.visual.sprite_frames, player.visual.animation) / player.visual.speed_scale
				<= player._attack_anim_linger, "%s 刀光与收招全帧可播完" % skin)
		_check(player.visual.flip_h, "%s 向左出招同步翻面" % skin)
		player.visual.set_frame_and_progress(2, 0.7)
		player._attack_cooldown = 0.0
		player._combo = 0
		player._try_attack()
		_check(player.visual.frame == 0 and is_zero_approx(player.visual.frame_progress),
			"%s 同名下一刀从首帧重播" % skin)
	# 攻击动作横向锁定，移动朝向仍可改变（不改位移/判定）。
	player.facing = Vector2.RIGHT
	player._update_anim()
	_check(player.visual.flip_h, "收招期间不被下一帧移动方向翻转")
	player._attack_timer = 0.0
	player._attack_anim_linger = 0.0
	player._update_anim()
	_check(not player.visual.flip_h, "收招结束恢复移动朝向")
	player._hurt_iframes = 0.0
	player._hurt_anim_timer = 0.0
	player._protect_timer = 0.0
	player.take_damage(1.0)
	player._update_anim()
	_check(player.visual.animation == "hurt", "受击即时启动素材 Guard")
	_check(_length(player.visual.sprite_frames, "hurt") / player.visual.speed_scale <= Player.HURT_ANIM_TIME,
		"受击全帧在表现窗内完成")
	# 循环动画应恢复正常速率，不继承 hurt 的提速。
	player._hurt_anim_timer = 0.0
	player.velocity = Vector2.ZERO
	player._update_anim()
	_check(player.visual.animation == "idle" and is_equal_approx(player.visual.speed_scale, 1.0),
		"受击结束回 idle 原速")
	# 真实引擎推进：非手动设置末帧，观察 animation_finished 以及每一帧出现。
	player._attack_cooldown = 0.0
	player._combo = 0
	player._try_attack()
	player.set_physics_process(true)
	await _verify_playback(player.visual, player._attack_animation(), 0.38, "英雄真实方向武器组合出招")
	player.set_physics_process(false)
	_check(player.attack_shape.disabled, "纯视觉收招不延长 0.18s 命中窗口")
	_check(player.visual.animation == "idle", "英雄收招结束回 idle")
	player._hurt_iframes = 0.0
	player.take_damage(1.0)
	player.set_physics_process(true)
	await _verify_playback(player.visual, "hurt", 0.35, "英雄真实受击")
	player.set_physics_process(false)
	player._hurt_anim_timer = 0.0
	player._attack_anim_linger = 0.0
	player._attack_timer = 0.0
	player.velocity = Vector2(160, 0)
	player._update_anim()
	for i in 6:
		player.visual.set_frame_and_progress(1, 0.0)
		player._update_anim(1.0 / 60.0)
	_check(absf(player.visual.offset.y) >= 1.0, "60Hz 步相插值不因取整反馈永久卡在零")
	player.velocity = Vector2.ZERO
	player._update_anim()
	player._die()
	_check(not player.visual.is_playing(), "无死亡素材的英雄不在淡出时继续走路/挥刀")
	player._respawn()
	await get_tree().create_timer(0.6).timeout
	_check(player.visible and is_equal_approx(player.visual.modulate.a, 1.0), "重生后旧淡出回调不会再隐藏英雄")
	_check(player.visual.animation == "idle" and player.visual.is_playing(), "重生立即回到 idle")

	for key in ["oni", "frog", "crab", "boss_samurai", "treant"]:
		var monster := _monster(key)
		monster.position = player.position + Vector2(60, 0)
		monster.visual.flip_h = false
		monster._play_action_anim("attack", 0.45)
		_check(_length(monster.visual.sprite_frames, "attack") / monster.visual.speed_scale <= 0.45,
			"%s EP 攻击全部帧适配既有动作窗" % key)
		_check(monster.visual.flip_h, "%s 站定出招面向目标" % key)
		monster.visual.set_frame_and_progress(2, 0.7)
		monster._play_action_anim("attack", 0.45)
		_check(monster.visual.frame == 0 and is_zero_approx(monster.visual.frame_progress),
			"%s 重复攻击从首帧重播" % key)
		monster.velocity = Vector2.RIGHT * 120.0
		monster._post_move_and_anim(0.016)
		_check(monster.visual.flip_h, "%s 出招不因击退/RVO 翻背" % key)
		monster._action_anim_timer = 0.0
		monster.velocity = Vector2.ZERO
		monster._update_anim()
		_check(monster.visual.animation == "idle" and is_equal_approx(monster.visual.speed_scale, 1.0),
			"%s 收招回 idle 清理播放速率" % key)
		monster._play_action_anim("attack", 0.45)
		await _verify_playback(monster.visual, "attack", 0.46, "%s 真实出招" % key)
		if monster.visual.sprite_frames.has_animation("hurt"):
			monster._play_action_anim("hurt", 0.4)
			await _verify_playback(monster.visual, "hurt", 0.42, "%s 真实受击" % key)
		monster._action_anim_timer = 0.0
		monster.velocity = Vector2(30, 0)
		monster._update_anim()
		var slow_rate := monster.visual.speed_scale
		monster.velocity = Vector2(200, 0)
		monster._update_anim()
		_check(monster.visual.speed_scale > slow_rate, "%s 步频随地面速度变化" % key)
		monster.visual.play("walk")
		monster._pulse_red()
		monster.on_sim_death()
		if key == "treant":
			_check(is_zero_approx(monster.rotation), "Troll 原生倒地不再额外侧转 90 度")
			_check(monster.visual.animation == "die" and is_equal_approx(monster.visual.speed_scale, 1.0),
				"Troll 死亡完整原速播放")
			await get_tree().create_timer(1.35).timeout
			var last := monster.visual.sprite_frames.get_frame_count("die") - 1
			_check(monster.visual.frame == last and not monster.visual.is_playing(), "Troll 死亡抵达并停留末帧")
			monster.on_sim_death()
			monster._update_anim()
			_check(monster.visual.frame == last and not monster.visual.is_playing(), "重复死亡/动画刷新不会复活倒地动画")
		else:
			_check(monster.visual.animation == "idle" and not monster.visual.is_playing(),
				"%s 无死亡素材尸体保持静止" % key)
		var corpse_color := monster.modulate
		await get_tree().create_timer(0.18).timeout
		_check(monster.modulate == corpse_color, "%s 死亡不被旧受击闪色复写" % key)
		var enrage_before: float = monster._enrage_timer
		EventBus.nest_ransacked.emit(monster.inst.species.species_name)
		await get_tree().create_timer(0.18).timeout
		_check(monster.modulate == corpse_color and monster._enrage_timer == enrage_before,
			"%s 尸体忽略迟到的捣巢闪色事件" % key)
		_check(not monster._play_action_anim("attack", 0.45), "%s 尸体拒绝迟到的出招事件" % key)
		monster.queue_free()
		await get_tree().process_frame
	player.queue_free()
	await get_tree().process_frame
	print("=== ANIMATION POLISH %s (%d checks) ===" % ["PASS" if _fails == 0 else "FAIL", _checks])
	get_tree().quit(0 if _fails == 0 else 1)

## 在实际 AnimatedSprite2D 时间线上观察，而不是只断言配置的帧率。
func _verify_playback(sprite: AnimatedSprite2D, anim: StringName, wait_time: float, label: String) -> void:
	var seen := {0: true}
	var finished := [false]
	var on_frame := func() -> void:
		if sprite.animation == anim:
			seen[sprite.frame] = true
	var on_finished := func() -> void:
		if sprite.animation == anim:
			finished[0] = true
	sprite.frame_changed.connect(on_frame)
	sprite.animation_finished.connect(on_finished)
	await get_tree().create_timer(wait_time, true, true).timeout
	sprite.frame_changed.disconnect(on_frame)
	sprite.animation_finished.disconnect(on_finished)
	_check(seen.size() == sprite.sprite_frames.get_frame_count(anim), label + "逐帧完整出现")
	_check(finished[0], label + "收到真实完成事件")
