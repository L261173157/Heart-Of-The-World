## 视觉截图工具（图形模式运行，非 headless）：
##   "$GODOT" --path Code res://tests/screenshot.tscn
## 加载主场景跑 3 秒（怪物生成、粒子出现）后截全屏存 /tmp/hotw_shot.png 并退出。
extends Node2D

const MAIN_SCENE := preload("res://scenes/main/main.tscn")
const OUT_PATH := "/tmp/hotw_shot.png"
const DELAY := 3.0

var _elapsed := 0.0


func _ready() -> void:
	add_child(MAIN_SCENE.instantiate())
	GameState.save_enabled = false


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < DELAY:
		return
	var img := get_viewport().get_texture().get_image()
	img.save_png(OUT_PATH)
	print("截图已保存 %s" % OUT_PATH)
	get_tree().quit(0)
