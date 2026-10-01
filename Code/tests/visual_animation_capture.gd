## 专用动画取证舞台（不改游戏场景）：固定相机、关闭 AI/碰撞/生态/存档。
## 真正的 AnimatedSprite2D 播放，不手动摆帧；截图标明动作名/帧号/倍速。
## HOTW_ANIMATION_CAPTURE_DIR=/tmp/... godot --path Code res://tests/visual_animation_capture.tscn
extends Node2D

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
var _attack: Player
var _hurt: Player
var _troll: MonsterBase
var _status: Array[Label] = []
var _time_label: Label
var _started := false
var _elapsed := 0.0

func _label(text: String, pos: Vector2, size: int, color := Color.WHITE) -> Label:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	add_child(label)
	return label

func _ready() -> void:
	GameState.save_enabled = false
	GameState.ecology_snapshot = null
	GameState.reset_all()
	WorldSim.stop()
	RenderingServer.set_default_clear_color(Color("202832"))
	_label("TINY SWORDS / LIVE ANIMATION CHECK", Vector2(52, 36), 30)
	_label("Staged evidence · actual game actors and .res frames · AI, collision and saving disabled", Vector2(52, 88), 18, Color("b3c3cf"))
	var names := ["HERO / SWORD", "HERO / GUARD", "TROLL / DEATH"]
	for i in 3:
		var panel := ColorRect.new()
		panel.color = Color("2e3b43")
		panel.position = Vector2(42 + i * 408, 160)
		panel.size = Vector2(380, 462)
		add_child(panel)
		_label(names[i], Vector2(64 + i * 408, 186), 23, Color("ecce91"))
		_status.append(_label("idle", Vector2(64 + i * 408, 538), 17, Color("d0d8dc")))
	_time_label = _label("", Vector2(52, 650), 20, Color("b3c3cf"))
	_attack = _player(Vector2(232, 388))
	_hurt = _player(Vector2(640, 388))
	_troll = MonsterBase.new()
	var visual := AnimatedSprite2D.new()
	visual.name = "Visual"
	visual.sprite_frames = load("res://assets/creatures/frames/treant/treant_frames.res")
	visual.scale = Vector2(2, 2)
	_troll.add_child(visual)
	add_child(_troll)
	_troll.set_physics_process(false)
	_troll.inst = MonsterInstance.new()
	_troll.inst.species = load("res://data/species/treant.tres")
	_troll.sprite_base_scale = Vector2(6, 6)
	_troll.position = Vector2(1048, 388)
	_troll.collision_layer = 0
	_troll.collision_mask = 0
	MonsterBase._species_registry[_troll.inst.species.species_name] = [_troll]
	_troll.visual.play("idle")
	_capture()

func _player(pos: Vector2) -> Player:
	var actor: Player = PLAYER_SCENE.instantiate()
	add_child(actor)
	actor.set_physics_process(false)
	actor.set_process(false)
	actor.get_node("Camera2D").enabled = false
	actor.position = pos
	actor.collision_layer = 0
	actor.collision_mask = 0
	actor.attack_hitbox.monitoring = false
	return actor

func _process(delta: float) -> void:
	if _started:
		_elapsed += delta
	_refresh_status()

func _refresh_status() -> void:
	if _status.size() < 3 or _troll == null:
		return
	var sprites := [_attack.visual, _hurt.visual, _troll.visual]
	for i in 3:
		var sprite: AnimatedSprite2D = sprites[i]
		_status[i].text = "%s · frame %d / %d\n%.2fx · %s" % [sprite.animation,
			sprite.frame + 1, sprite.sprite_frames.get_frame_count(sprite.animation),
			sprite.speed_scale, "playing" if sprite.is_playing() else "completed / held"]
	_time_label.text = "Playback: %.2f s  |  Sword faces left; real death remains upright and settles at the last frame" % _elapsed

func _capture() -> void:
	await get_tree().create_timer(0.3).timeout
	_attack.facing = Vector2.LEFT
	_attack._try_attack()
	_attack.attack_shape.disabled = true
	_hurt.take_damage(1.0)
	_troll.on_sim_death()
	_started = true
	var folder := OS.get_environment("HOTW_ANIMATION_CAPTURE_DIR")
	if folder.is_empty():
		folder = "/tmp/hotw-visual-evidence/animation/runtime"
	DirAccess.make_dir_recursive_absolute(folder)
	var marks := [0.0, 0.08, 0.16, 0.24, 0.32, 0.65, 1.4]
	for index in marks.size():
		if index > 0:
			await get_tree().create_timer(marks[index] - marks[index - 1]).timeout
		# 截图期间暂停舞台，磁盘编码时间不吃掉下一次观察区间的动画帧。
		get_tree().paused = true
		_refresh_status()  # 暂停后读当前帧，标签不能落后于同帧的精灵内部推进。
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(folder.path_join("animation_%02d.png" % index))
		get_tree().paused = false
	print("=== LIVE ANIMATION CAPTURE COMPLETE ===")
	get_tree().quit()
