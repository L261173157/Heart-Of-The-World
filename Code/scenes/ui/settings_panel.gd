## 通用设置面板（主菜单与暂停菜单共用实例）。
## 写入 GameState.settings 即时生效并随存档持久化。
extends PanelContainer

## 三忍外观循环序（美术 v5）：蓝→黑→白→蓝
const SKIN_ORDER := ["blue", "dark", "white"]
const SKIN_LABELS := {"blue": "蓝忍", "dark": "黑忍", "white": "白忍"}


func _ready() -> void:
	%VolumeSlider.value = float(GameState.settings.get("volume", 0.8))
	%MusicSlider.value = float(GameState.settings.get("music_volume", 1.0))
	%SfxSlider.value = float(GameState.settings.get("sfx_volume", 1.0))
	%ShakeCheck.button_pressed = bool(GameState.settings.get("screen_shake", true))
	%DmgNumCheck.button_pressed = bool(GameState.settings.get("damage_numbers", true))
	%AutoAimCheck.button_pressed = bool(GameState.settings.get("auto_aim", false))
	_refresh_skin_btn()
	%VolumeSlider.value_changed.connect(
		func(v: float) -> void: GameState.set_setting("volume", v))
	%MusicSlider.value_changed.connect(
		func(v: float) -> void: GameState.set_setting("music_volume", v))
	%SfxSlider.value_changed.connect(
		func(v: float) -> void: GameState.set_setting("sfx_volume", v))
	%ShakeCheck.toggled.connect(
		func(on: bool) -> void: GameState.set_setting("screen_shake", on))
	%DmgNumCheck.toggled.connect(
		func(on: bool) -> void: GameState.set_setting("damage_numbers", on))
	%AutoAimCheck.toggled.connect(
		func(on: bool) -> void: GameState.set_setting("auto_aim", on))
	%SkinBtn.pressed.connect(_cycle_skin)


func _refresh_skin_btn() -> void:
	var skin: String = str(GameState.settings.get("hero_skin", "blue"))
	%SkinBtn.text = SKIN_LABELS.get(skin, "蓝忍")


func _cycle_skin() -> void:
	var skin: String = str(GameState.settings.get("hero_skin", "blue"))
	var idx: int = SKIN_ORDER.find(skin)
	if idx < 0:
		idx = 0
	GameState.set_setting("hero_skin", SKIN_ORDER[(idx + 1) % SKIN_ORDER.size()])
	_refresh_skin_btn()
