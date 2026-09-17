## 音效与音乐管理（autoload 单例）。
## 音效：NA（Ninja Adventure，CC0）为主 + Kenney Impact Sounds（CC0）补位——
## 命中/受击/击杀/升级/死亡/换图/冲刺/技能施放；纯订阅 EventBus 播放；
## 非空间化（俯视全场可听），随机 ±8% 音调防止重复感；4 通道轮询不互相截断。
## 音乐：NA musics 区域 BGM（六区域一区一曲 + 主菜单），player_entered_region 驱动
## 换曲（切区 0.4s 淡出淡入，同曲不重启）；总线分离：音效走 SFX、音乐走 Music，
## 音量各自由设置面板的三条滑条控制（Master 总音量兜底）。
extends Node

const VOLUME_DB := -6.0
const MUSIC_DB := -10.0
const PITCH_SPREAD := 0.08
const CHANNEL_COUNT := 4
const CROSSFADE := 0.4
## 命中/受击音节流：重击 AOE 同帧命中十只也会发十条 damage_number，
## 不节流会抢光 4 个轮询通道糊成一片（顿帧侧早有同款 0.2s 节流，音频侧对齐）
const HIT_SFX_THROTTLE := 0.1

## 事件音（美术 v5 M-C 全量：NA 具名音效优先对口；hurt/dash/heavy/region
## NA 无对口沿用 Kenney；menu/gold2/gold3/secret/alert/voice 系为全量新增）
const SFX := {
	"hit": [
		preload("res://assets/na/audio/sounds/sword.ogg"),
		preload("res://assets/sfx/hit_a.ogg"),
	],
	"hurt": [preload("res://assets/sfx/hurt.ogg")],
	"kill": [preload("res://assets/na/audio/sounds/kill.ogg")],
	"dash": [preload("res://assets/sfx/dash.ogg")],
	"heavy": [preload("res://assets/sfx/kill.ogg")],
	"bolt": [preload("res://assets/na/audio/sounds/magic-1.ogg")],
	"heal": [preload("res://assets/na/audio/sounds/succes.ogg")],
	"levelup": [preload("res://assets/na/audio/sounds/power-up.ogg")],
	"died": [preload("res://assets/na/audio/sounds/game-over.ogg")],
	"region": [preload("res://assets/sfx/region.ogg")],
	"gold": [preload("res://assets/na/audio/sounds/gold-1.ogg")],
	"gold2": [preload("res://assets/na/audio/sounds/gold-2.ogg")],
	"gold3": [preload("res://assets/na/audio/sounds/gold-3.ogg")],
	"menu": [preload("res://assets/na/audio/sounds/menu-1.ogg")],
	"quest": [preload("res://assets/na/audio/sounds/succes-2.ogg")],
	"discover": [preload("res://assets/na/audio/sounds/succes-3.ogg")],
	"passive": [preload("res://assets/na/audio/sounds/power-up-2.ogg")],
	"secret": [preload("res://assets/na/audio/sounds/secret-1.wav")],
	"alert": [preload("res://assets/na/audio/sounds/alert.ogg")],
	"voice1": [preload("res://assets/na/audio/sounds/voice-1.ogg")],
	"voice2": [preload("res://assets/na/audio/sounds/voice-2.ogg")],
	"voice3": [preload("res://assets/na/audio/sounds/voice-3.ogg")],
	"voice4": [preload("res://assets/na/audio/sounds/voice-4.ogg")],
}

## 群系 BGM（NA musics，六地形一系一曲 + 菜单）——换群系即换情绪。
## v4 起按地形键控（同地形多斑块共享一曲，曲随地貌不随行政区划）
const TERRAIN_THEMES := {
	"plains": preload("res://assets/na/audio/musics/theme-4.ogg"),
	"forest": preload("res://assets/na/audio/musics/theme-2.ogg"),
	"snow": preload("res://assets/na/audio/musics/theme-9.ogg"),
	"swamp": preload("res://assets/na/audio/musics/theme-12.ogg"),
	"hill": preload("res://assets/na/audio/musics/theme-5.ogg"),
	"lava": preload("res://assets/na/audio/musics/theme-13.ogg"),
	"menu": preload("res://assets/na/audio/musics/theme-10.ogg"),
	## 城塞内腔（美术 v5 M-B）：进出城塞切曲，出腔回当前群系曲
	"dungeon": preload("res://assets/na/audio/musics/theme-7.ogg"),
	## Boss 临场（美术 v5 M-C 全量）：活体 Boss 进入追踪圈切战斗曲
	"boss": preload("res://assets/na/audio/musics/theme-16.ogg"),
	## 出生营地（美术 v5 M-C）：安全区休整曲
	"camp": preload("res://assets/na/audio/musics/theme-8.ogg"),
}

var _channels: Array[AudioStreamPlayer] = []
var _next_channel := 0
var _music: AudioStreamPlayer
var _music_name := ""
var _fade_tween: Tween
var _last_hit_sfx := -9999.0
## 玩家受击音独立节流时间戳：与怪物命中共用一条时，围攻中密集的 hit 音
## 会把 hurt 音整个吞掉——"挨打了没声音"恰好在最需要听见的时刻发生
var _last_hurt_sfx := -9999.0


func _ready() -> void:
	# ALWAYS：升级三选一/暂停期间 BGM 不随树冻结（每次升级音乐卡断一下很扎耳）；
	# 音效由事件驱动，世界暂停时本就没有发射方，ALWAYS 不会带来额外声音
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in CHANNEL_COUNT:
		var channel := AudioStreamPlayer.new()
		channel.volume_db = VOLUME_DB
		channel.bus = &"SFX"
		add_child(channel)
		_channels.append(channel)
	_music = AudioStreamPlayer.new()
	_music.volume_db = MUSIC_DB
	_music.bus = &"Music"
	add_child(_music)

	EventBus.damage_number.connect(
		func(_pos: Vector2, _amount: int, is_player_hurt: bool, _effective: bool) -> void:
			var now := Time.get_ticks_msec() / 1000.0
			if is_player_hurt:
				if now - _last_hurt_sfx < HIT_SFX_THROTTLE:
					return
				_last_hurt_sfx = now
				play("hurt")
			else:
				if now - _last_hit_sfx < HIT_SFX_THROTTLE:
					return
				_last_hit_sfx = now
				play("hit")
	)
	EventBus.monster_killed_by_player.connect(
		func(_xp: int, _gold: int, _name: String, _species: String) -> void: play("kill")
	)
	EventBus.player_died.connect(func() -> void: play("died"))
	EventBus.player_dashed.connect(func() -> void: play("dash"))
	EventBus.bounty_completed.connect(
		func(_text: String) -> void: play("gold")
	)
	# 世界事件（灭绝/复苏/入侵潮/Boss 降临）不配音：此前复用换区 chime，
	# 三个 Boss 相继重生会连响三声同款音效、且与真实换区音无法区分语义——
	# 事件的反馈通道是 toast 播报，声音留给"真的换了张地图"
	EventBus.player_entered_region.connect(
		func(region_id: String, _name: String) -> void:
			play("region")
			# 区域 id → 地形（TERRAIN_THEMES 键控）；查不到回退平原曲不硬崩
			var region: SimRegion = WorldSim.sim.get_region(region_id) if WorldSim.sim != null else null
			play_music(region.terrain if region != null else "plains")
	)
	# leveled_up 挂在 CharacterStats 上：reset_all() 后经 stats_rebuilt 重连。
	# reset_all 现为就地重置（对象身份不变），连接前查重防叠连（否则升级音效叠播）
	GameState.stats.leveled_up.connect(_on_leveled_up)
	GameState.stats_rebuilt.connect(_reconnect_stats)


func _reconnect_stats() -> void:
	if not GameState.stats.leveled_up.is_connected(_on_leveled_up):
		GameState.stats.leveled_up.connect(_on_leveled_up)


func _on_leveled_up(_level: int, _levels_gained: int) -> void:
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


## 群系/菜单 BGM：同曲不重启；换曲走短淡出淡入（战斗间隙不被硬切惊扰）
func play_music(name: String) -> void:
	var stream: AudioStream = TERRAIN_THEMES.get(name)
	if stream == null or name == _music_name:
		return
	_music_name = name
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	if _music.playing:
		_fade_tween = create_tween()
		_fade_tween.tween_property(_music, "volume_db", -60.0, CROSSFADE * 0.5)
		_fade_tween.tween_callback(func() -> void: _switch_stream(stream))
		_fade_tween.tween_property(_music, "volume_db", MUSIC_DB, CROSSFADE * 0.5)
	else:
		_switch_stream(stream)


func _switch_stream(stream: AudioStream) -> void:
	if stream is AudioStreamOggVorbis:
		stream.loop = true
	_music.stream = stream
	_music.play()


func stop_music() -> void:
	# 先杀在途切曲 tween：其 tween_callback(_switch_stream) 会在 stop 之后
	# 重新起播，把刚停下的 BGM 又拉回来
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_music_name = ""
	_music.stop()
