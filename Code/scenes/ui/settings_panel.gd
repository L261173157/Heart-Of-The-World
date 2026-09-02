## 通用设置面板（主菜单与暂停菜单共用实例）。
## 写入 GameState.settings 即时生效并随存档持久化。
extends PanelContainer


func _ready() -> void:
	%VolumeSlider.value = float(GameState.settings.get("volume", 0.8))
	%ShakeCheck.button_pressed = bool(GameState.settings.get("screen_shake", true))
	%DmgNumCheck.button_pressed = bool(GameState.settings.get("damage_numbers", true))
	%AutoAimCheck.button_pressed = bool(GameState.settings.get("auto_aim", false))
	%VolumeSlider.value_changed.connect(
		func(v: float) -> void: GameState.set_setting("volume", v))
	%ShakeCheck.toggled.connect(
		func(on: bool) -> void: GameState.set_setting("screen_shake", on))
	%DmgNumCheck.toggled.connect(
		func(on: bool) -> void: GameState.set_setting("damage_numbers", on))
	%AutoAimCheck.toggled.connect(
		func(on: bool) -> void: GameState.set_setting("auto_aim", on))
