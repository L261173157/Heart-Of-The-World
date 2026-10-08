## 真正运行 60Hz 物理与 120/90/144Hz 渲染，不用辅助函数手工喂伪造快照。
extends Node2D

const PLAYER := preload("res://scenes/player/player.tscn")
var _fails := 0
var _checks := 0
var _player: Player
var _hint: Node2D

func _ready() -> void:
	process_priority = 300
	GameState.save_enabled = false
	GameState.reset_all()
	WorldSim.stop()
	Engine.physics_ticks_per_second = 60
	Engine.max_fps = 120
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])

func _run() -> void:
	_player = PLAYER.instantiate()
	add_child(_player)
	_player.global_position = Vector2(21888.25, 60301.375)
	_player.get_node("Camera2D").snap_to_player()
	_hint = preload("res://scripts/monsters/monster_guard_hint.gd").new()
	_player.add_child(_hint)
	_hint.show_attack(_player.stats, 1.0, true, Vector2(0.0, -50.0))
	TouchInput.joystick_active = true
	TouchInput.move_vector = Vector2(1.0, 0.37).normalized()
	await _sample_motion(120)
	await _sample_motion(90)
	await _sample_motion(144)
	await _sample_motion(120, true)
	var sync := _player.get_node("RenderSync")
	var camera: Camera2D = _player.get_node("Camera2D")
	var before: Vector2 = _player.global_position
	# 真实冲刺输入；相机/渲染不能反写碰撞身体。
	TouchInput.queue_dash()
	for i in 30:
		await get_tree().process_frame
	_check(_player.global_position.distance_to(before) > 85.0, "高刷新下真实冲刺位移保留")
	TouchInput.move_vector = Vector2.ZERO
	for i in 30:
		await get_tree().process_frame
	# 远距离传送即刻重置；随后两物理帧均不从旧地点插值。
	_player.global_position = Vector2(753707.25, 738957.375)
	camera.snap_to_player()
	_check(sync.get_render_position().distance_to(_player.global_position) < 0.01,
		"传送同步清空旧快照")
	for i in 8:
		await get_tree().process_frame
	_check(sync.get_render_position().distance_to(_player.global_position) < 0.1,
		"传送后没有跨地图拖影")
	var before_hurt := _player.global_position
	_player.take_damage(1.0, before_hurt + Vector2(30.0, 0.0), "render test")
	for i in 45:
		await get_tree().process_frame
	_check(_player.global_position.x < before_hurt.x - 8.0, "真实击退不被渲染回写抵消")
	TouchInput.move_vector = Vector2.RIGHT
	for i in 24:
		await get_tree().process_frame
		await sampled
	var frozen: Vector2 = _player.global_position
	var frozen_render: Vector2 = sync.get_render_position()
	get_tree().paused = true
	await get_tree().create_timer(0.08, true).timeout
	_check(_player.global_position == frozen and sync.get_render_position() == frozen_render, "暂停期间身体保持原位")
	get_tree().paused = false
	await get_tree().process_frame
	await sampled
	_check(sync.get_render_position().distance_to(frozen_render) < 6.0, "运动中继续没有插值跳回旧位置")
	TouchInput.reset()
	_player.queue_free()
	await get_tree().process_frame
	Engine.max_fps = 0
	print("=== RENDER MOTION %s (%d checks) ===" % ["PASS" if _fails == 0 else "FAIL", _checks])
	get_tree().quit(0 if _fails == 0 else 1)

func _sample_motion(fps: int, variable := false) -> void:
	Engine.max_fps = fps
	if variable:
		print("  变帧率采样：72/144/96/120Hz 逐帧交替")
	var sync := _player.get_node("RenderSync")
	var camera: Camera2D = _player.get_node("Camera2D")
	var last_body: Vector2 = _player.global_position
	var last_render: Vector2 = sync.get_render_position()
	var reused_body := 0
	var moving_render := 0
	var max_error := 0.0
	var max_excess := 0.0
	var max_grid := 0.0
	var max_camera_grid := 0.0
	var max_hint_error := 0.0
	for i in fps:
		if variable:
			Engine.max_fps = [72, 144, 96, 120][i % 4]
		await get_tree().process_frame
		# process_frame 在节点回调之前触发，延迟到本帧的统一提交完成后采样。
		await sampled
		var body := _player.global_position
		var drawn: Vector2 = sync.get_render_position()
		if body == last_body:
			reused_body += 1
			if drawn.distance_to(last_render) > 0.1:
				moving_render += 1
		max_error = maxf(max_error, body.distance_to(drawn))
		max_excess = maxf(max_excess, body.distance_to(drawn) - sync._previous.distance_to(sync._current))
		var sprite: Vector2 = _player.visual.global_position + sync.render_shift
		max_grid = maxf(max_grid, sprite.distance_to(sprite.round()))
		var origin: Vector2 = get_viewport().get_canvas_transform().origin
		max_camera_grid = maxf(max_camera_grid, origin.distance_to(origin.round()))
		max_hint_error = maxf(max_hint_error, _hint.global_position.distance_to(
			(drawn + Vector2(0.0, -50.0)).round()))
		last_body = body
		last_render = drawn
	_check(reused_body > fps / 8 and moving_render > reused_body * 0.75,
		"%dHz 无物理步的渲染帧仍连续运动（%d/%d）" % [fps, moving_render, reused_body])
	_check(max_excess < 0.1, "%dHz 插值落后不超过一物理步（%.3fpx）" % [fps, max_error])
	_check(max_grid < 0.08, "%dHz 精灵绘制保持整数网格（%.3f）" % [fps, max_grid])
	_check(max_camera_grid < 0.08, "%dHz 相机画布原点整数对齐（%.3f）" % [fps, max_camera_grid])
	_check(max_hint_error < 0.08, "%dHz 独立盾形预警与插值身体同步" % fps)
	_check(camera.top_level, "%dHz 相机不继承身体阶梯变换" % fps)

signal sampled
func _process(_delta: float) -> void:
	sampled.emit()
