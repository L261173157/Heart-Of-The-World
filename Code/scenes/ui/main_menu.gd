## 主菜单：标题 + 进入世界 / 设置 / 重置世界（清档确认）。
## 作为游戏主场景（project.godot run/main_scene）。
extends Control


func _ready() -> void:
	%StartBtn.pressed.connect(_start)
	%SettingsBtn.pressed.connect(_toggle_settings)
	%ResetBtn.pressed.connect(_confirm_reset)
	%ResetConfirmBtn.pressed.connect(_do_reset)
	%ResetCancel.pressed.connect(
		func() -> void: %ResetConfirm.visible = false)
	%QuitBtn.pressed.connect(func() -> void: get_tree().quit())
	# iOS 应用不应自行退出（App Store 审核常见拒因）；仅桌面保留退出键
	if OS.has_feature("ios"):
		%QuitBtn.visible = false
	%SettingsClose.pressed.connect(_toggle_settings)
	# 有进度时按钮文案带提示
	if _has_progress():
		%StartBtn.text = "继续冒险"
	%ResetConfirm.visible = false


func _has_progress() -> bool:
	return GameState.stats.level > 1 or GameState.gold > 0 or not GameState.codex.is_empty()


func _start() -> void:
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")


func _toggle_settings() -> void:
	%SettingsLayer.visible = not %SettingsLayer.visible


func _confirm_reset() -> void:
	%ResetConfirm.visible = true


func _do_reset() -> void:
	GameState.reset_all()
	%ResetConfirm.visible = false
	%StartBtn.text = "开始冒险"
	_toast("世界已重置")


func _toast(text: String) -> void:
	%MenuToast.text = text
	%MenuToast.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(1.6)
	tween.tween_property(%MenuToast, "modulate:a", 0.0, 0.6)
