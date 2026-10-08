## 真实玩家输入和怪物迁徙运动；观察引擎帧进度，不手动推进动画。
extends Node2D

const PLAYER := preload("res://scenes/player/player.tscn")
const GOBLIN := preload("res://scenes/monsters/goblin.tscn")
const Playback := preload("res://scripts/animation/sprite_playback.gd")
var _checks := 0
var _fails := 0

func _ready() -> void:
	GameState.save_enabled = false
	GameState.ecology_snapshot = null
	GameState.reset_all()
	WorldSim.stop()
	WorldSim.sim = EcologySim.new()
	BiomeMap.configure(BiomeMap.DEFAULT_SEED)
	TouchInput.reset()
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])

func _sample(player: Player, monster: MonsterBase, cap: int, input_scale: float) -> float:
	Engine.max_fps = cap if cap > 0 else 120
	TouchInput.move_vector = Vector2.RIGHT * input_scale
	for frame in 12:
		await get_tree().physics_frame
	var visual := player.visual
	var start := player.position
	var monster_start := monster.position
	var before := float(visual.frame) + visual.frame_progress
	var monster_before := float(monster.visual.frame) + monster.visual.frame_progress
	var monster_advanced := 0.0
	var wall_start := Time.get_ticks_usec()
	var shortest := INF
	var longest := 0.0
	var elapsed := 0.0
	var advanced := 0.0
	var switches := 0
	var samples := 0
	var expected := 0.0
	while elapsed < 0.85:
		if cap == 0:
			Engine.max_fps = [45, 120, 75, 60][samples % 4]
		await get_tree().process_frame
		var delta := get_process_delta_time()
		elapsed += delta
		shortest = minf(shortest, delta)
		longest = maxf(longest, delta)
		var monster_now := float(monster.visual.frame) + monster.visual.frame_progress
		monster_advanced += fposmod(monster_now - monster_before, float(monster.visual.sprite_frames.get_frame_count("walk")))
		monster_before = monster_now
		var now := float(visual.frame) + visual.frame_progress
		var count := visual.sprite_frames.get_frame_count(visual.animation)
		var step := fposmod(now - before, float(count))
		advanced += step
		if int(now) != int(before):
			switches += 1
		before = now
		expected += visual.sprite_frames.get_animation_speed(visual.animation) * visual.speed_scale * delta
		samples += 1
	var fps := advanced / elapsed
	var label := "%dHz / 输入%.2f" % [cap, input_scale]
	_check(player.position.distance_to(start) > 20.0 and monster.position.distance_to(monster_start) > 10.0,
		label + " 玩家真实输入／怪物真实迁徙产生位移")
	_check(visual.animation == "walk" and switches >= 5, label + " 引擎真实步行换帧")
	_check(absf(advanced - expected) < 1.2, label + " 帧进度按实际时间而非渲染帧计数")
	_check(fps >= 5.0 and fps <= 24.5, label + " 六姿势步频有界 %.2ffps" % fps)
	var monster_fps := monster_advanced / elapsed
	var wall_elapsed := float(Time.get_ticks_usec() - wall_start) / 1000000.0
	print("    采样 %d帧 / 游戏%.3fs / 实时%.3fs / 间隔%.4f–%.4fs" % [samples, elapsed, wall_elapsed, shortest, longest])
	if cap > 0:
		_check(float(samples) / elapsed > float(cap) * 0.65 and float(samples) / elapsed < float(cap) * 1.3, label + " 实际渲染采样频率吻合")
	else:
		_check(longest > shortest * 1.5, label + " 实际采样间隔随渲染变帧")
	_check(monster.visual.animation == "walk" and monster_fps >= 10.0 and monster_fps <= 24.0,
		label + " 怪物移动不再锁于5.2fps（%.2f）" % monster_fps)
	return fps

func _run() -> void:
	var player: Player = PLAYER.instantiate()
	add_child(player)
	player.position = Vector2(21888, 60301)
	player.get_node("Camera2D").enabled = false
	var monster: MonsterBase = GOBLIN.instantiate()
	add_child(monster)
	var inst := MonsterInstance.new()
	inst.id = 9001
	inst.species = load("res://data/species/goblin.tres")
	inst.spawn_pos = player.position + Vector2(0, 250)
	monster.setup(inst)
	monster._player_ref = player
	monster._nav.avoidance_enabled = false
	monster.on_migrate("", monster.position + Vector2(6000, 0))
	TouchInput.joystick_active = true
	var slow := await _sample(player, monster, 60, 0.4)
	var normal60 := await _sample(player, monster, 60, 1.0)
	var normal120 := await _sample(player, monster, 120, 1.0)
	var variable := await _sample(player, monster, 0, 1.0)
	_check(normal60 > slow * 2.2 and normal60 < slow * 2.8, "真实慢走与满速步频按位移比例变化，保持步幅")
	_check(absf(normal60 - normal120) < 1.5 and absf(normal60 - variable) < 1.5,
		"60／120／变帧渲染不改变步频")
	# 同名续播与反向转身均不得重置步相。
	player.set_physics_process(false)
	player.visual.set_frame_and_progress(3, 0.4)
	player.facing = Vector2.LEFT
	player._update_anim()
	_check(player.visual.frame == 3 and is_equal_approx(player.visual.frame_progress, 0.4), "反向转身保留帧内进度")

	player.velocity = Vector2.RIGHT * 620.0
	player._dash_timer = 0.1
	player._update_anim()
	_check(player.visual.frame == 3 and is_equal_approx(player.visual.frame_progress, 0.4)
		and is_equal_approx(player.visual.speed_scale * player.visual.sprite_frames.get_animation_speed("walk"), 24.0),
		"冲刺转换保留步相且六姿势最多24fps")
	player._dash_timer = 0.0
	player.velocity = Vector2.ZERO
	player._update_anim()
	player.visual.set_frame_and_progress(2, 0.8)
	player.velocity = Vector2.RIGHT * 160.0
	player._update_anim()
	_check(player.visual.frame == 0 and is_zero_approx(player.visual.frame_progress), "站定后起步使用首个落脚姿势，不沿用呼吸相位")
	# 非等长帧循环切换也按时间相位转换，不按帧下标硬拷贝。
	var frames := SpriteFrames.new()
	frames.rename_animation("default", "walk")
	var tex := player.visual.sprite_frames.get_frame_texture("walk", 0)
	frames.add_frame("walk", tex, 1.0)
	frames.add_frame("walk", tex, 3.0)
	frames.add_animation("walk_up")
	frames.add_frame("walk_up", tex, 2.0)
	frames.add_frame("walk_up", tex, 2.0)
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = frames
	add_child(sprite)
	sprite.play("walk")
	sprite.set_frame_and_progress(1, 0.5)
	Playback.transition_loop(sprite, "walk_up")
	_check(sprite.frame == 1 and is_equal_approx(sprite.frame_progress, 0.25), "循环换向保留非等长帧时间相位")
	TouchInput.reset()
	Engine.max_fps = 0
	player.queue_free()
	monster.queue_free()
	sprite.queue_free()
	await get_tree().process_frame
	print("=== LOCOMOTION CADENCE %s (%d checks) ===" % ["PASS" if _fails == 0 else "FAIL", _checks])
	get_tree().quit(0 if _fails == 0 else 1)
