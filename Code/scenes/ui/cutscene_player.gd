## 开场 CG 过场播放器：全屏视频 + 点击/按键跳过，播完或跳过后进入目标场景。
## 片源缺失（未随包/未导入）时直接放行——任何构建下入口都安全不卡死。
## 用法：main_menu._start() 在 intro_pending() 为真时切到本场景；
## 播完经 GameState.mark_intro_cg_seen() 落盘，之后不再打扰。
class_name CutscenePlayer
extends Control

## 播完/跳过后要去的目标场景（默认主世界）
@export var next_scene := "res://scenes/main/main.tscn"
## CG 片源（Theora .ogv——Godot 4 唯一原生视频格式）
const VIDEO_PATH := "res://assets/cg/intro.ogv"

var _done := false

@onready var _video: VideoStreamPlayer = %Video


## 「未看过且片源可用」才需要过场（main_menu._start 的路由谓词，测试可直接断言）
static func intro_pending() -> bool:
	return not GameState.seen_intro_cg and ResourceLoader.exists(VIDEO_PATH)


func _ready() -> void:
	var stream: VideoStream = load(VIDEO_PATH) if intro_pending() else null
	if stream == null:
		# 片源缺失或已播过：直接放行（防御路径——入口谓词拦截，正常不会到这）
		_finish()
		return
	# CG 自带音轨（压制时混入 BGM）走音乐总线，音量设置与之联动
	if AudioServer.get_bus_index("Music") >= 0:
		_video.bus = "Music"
	_video.stream = stream
	_video.finished.connect(_finish)
	_video.play()


func _input(event: InputEvent) -> void:
	# 任意点击/触摸/确认或取消键都视为跳过（开场 CG 不强迫看完）
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		_finish()
	elif event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		_finish()
	elif event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
		_finish()


## 幂等收尾：置已播标记 → 切目标场景（视频结束与手动跳过可能同帧竞发）。
## next_scene 置空串 = 只做标记不切场景（测试挂钩，避免顶掉测试场景）
func _finish() -> void:
	if _done:
		return
	_done = true
	GameState.mark_intro_cg_seen()
	if next_scene != "":
		get_tree().change_scene_to_file(next_scene)
