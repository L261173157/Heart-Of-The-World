## 音效管理（autoload 单例）。
## 占位音效来自 Kenney Impact Sounds / RPG Audio（CC0，许可证随附 assets/sfx/）。
## 纯订阅 EventBus 播放：命中/受击/击杀/升级/死亡/换图/冲刺；
## 非空间化（俯视全场可听），随机 ±8% 音调防止重复感。
## 4 通道轮询：密集战斗时击杀音不再截断命中音。
extends Node

const VOLUME_DB := -6.0
const PITCH_SPREAD := 0.08
const CHANNEL_COUNT := 4

const SFX := {
	"hit": [
		preload("res://assets/sfx/hit_a.ogg"),
		preload("res://assets/sfx/hit_b.ogg"),
	],
	"hurt": [preload("res://assets/sfx/hurt.ogg")],
	"kill": [preload("res://assets/sfx/kill.ogg")],
	"dash": [preload("res://assets/sfx/dash.ogg")],
	"heavy": [preload("res://assets/sfx/kill.ogg")],
	"bolt": [preload("res://assets/sfx/dash.ogg")],
	"heal": [preload("res://assets/sfx/levelup.ogg")],
	"levelup": [preload("res://assets/sfx/levelup.ogg")],
	"died": [preload("res://assets/sfx/died.ogg")],
	"region": [preload("res://assets/sfx/region.ogg")],
}

var _channels: Array[AudioStreamPlayer] = []
var _next_channel := 0


func _ready() -> void:
	for i in CHANNEL_COUNT:
		var channel := AudioStreamPlayer.new()
		channel.volume_db = VOLUME_DB
		add_child(channel)
		_channels.append(channel)

	EventBus.damage_number.connect(
		func(_pos: Vector2, _amount: int, is_player_hurt: bool, _effective: bool) -> void:
			play("hurt" if is_player_hurt else "hit")
	)
	EventBus.monster_killed_by_player.connect(
		func(_xp: int, _gold: int, _name: String) -> void: play("kill")
	)
	EventBus.player_died.connect(func() -> void: play("died"))
	EventBus.player_dashed.connect(func() -> void: play("dash"))
	EventBus.bounty_completed.connect(func(_text: String) -> void: play("levelup"))
	EventBus.world_event.connect(func(_text: String) -> void: play("region"))
	EventBus.player_entered_region.connect(
		func(_id: String, _name: String) -> void: play("region")
	)
	# leveled_up 挂在 CharacterStats 上，而 reset_all() 会整体换对象——
	# 订阅 stats_rebuilt 重连，否则"重置世界"后升级音效永久失效
	GameState.stats.leveled_up.connect(_on_leveled_up)
	GameState.stats_rebuilt.connect(_reconnect_stats)


func _reconnect_stats() -> void:
	GameState.stats.leveled_up.connect(_on_leveled_up)


func _on_leveled_up(_level: int) -> void:
	play("levelup")


func play(sound_name: String) -> void:
	var streams: Array = SFX.get(sound_name, [])
	if streams.is_empty():
		return
	# 轮询取一个空闲通道（全忙时取下一个，顶掉最旧的排队感最弱）
	var channel := _channels[_next_channel]
	_next_channel = (_next_channel + 1) % _channels.size()
	channel.stream = streams[randi() % streams.size()]
	channel.pitch_scale = randf_range(1.0 - PITCH_SPREAD, 1.0 + PITCH_SPREAD)
	channel.play()
