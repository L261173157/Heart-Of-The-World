## 通用设置面板（主菜单与暂停菜单共用实例）。
## 写入 GameState.settings 即时生效并随存档持久化。
extends PanelContainer

## 骑士外观沿用旧存档键：蓝→黑→白→蓝
const SKIN_ORDER := ["blue", "dark", "white"]
const SKIN_LABELS := {"blue": "蓝骑士", "dark": "黑骑士", "white": "白骑士"}


func _ready() -> void:
	# TS 纸面底 + 蓝青丝带标题签（v6 §8）：深纸保浅字对比，主菜单/暂停共用
	HotwTheme.paper_panel(self, HotwTheme.PAPER_SPECIAL)
	var title := get_node("Margin/VB/Title") as Label
	if title != null:
		var tag := HotwTheme.ribbon_tag(title.text, 0, 200.0)
		tag.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		title.get_parent().add_child(tag)
		title.get_parent().move_child(tag, title.get_index())
		title.visible = false
	%VolumeSlider.value = float(GameState.settings.get("volume", 0.8))
	%MusicSlider.value = float(GameState.settings.get("music_volume", 1.0))
	%SfxSlider.value = float(GameState.settings.get("sfx_volume", 1.0))
	%ShakeCheck.button_pressed = bool(GameState.settings.get("screen_shake", true))
	%DmgNumCheck.button_pressed = bool(GameState.settings.get("damage_numbers", true))
	%AutoAimCheck.button_pressed = bool(GameState.settings.get("auto_aim", false))
	%LanternCheck.button_pressed = bool(GameState.settings.get("lantern_shadows", true))
	%FpsCheck.button_pressed = bool(GameState.settings.get("show_fps", false))
	_build_sections()
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
	%LanternCheck.toggled.connect(
		func(on: bool) -> void: GameState.set_setting("lantern_shadows", on))
	%FpsCheck.toggled.connect(
		func(on: bool) -> void: GameState.set_setting("show_fps", on))
	%SkinBtn.pressed.connect(_cycle_skin)


func _refresh_skin_btn() -> void:
	var skin: String = str(GameState.settings.get("hero_skin", "blue"))
	%SkinBtn.text = SKIN_LABELS.get(skin, "蓝骑士")


func _cycle_skin() -> void:
	var skin: String = str(GameState.settings.get("hero_skin", "blue"))
	var idx: int = SKIN_ORDER.find(skin)
	if idx < 0:
		idx = 0
	GameState.set_setting("hero_skin", SKIN_ORDER[(idx + 1) % SKIN_ORDER.size()])
	_refresh_skin_btn()


## 横屏设置分成声音与冒险两组，避免单列近700px顶到底挤压关闭按钮。
func _build_sections() -> void:
	custom_minimum_size.x = 744
	var vb := get_node("Margin/VB") as VBoxContainer
	var columns := HBoxContainer.new()
	columns.name = "SettingColumns"
	columns.add_theme_constant_override("separation", 32)
	vb.add_child(columns)
	for group: Array in [["声音", "VolumeRow", "MusicRow", "SfxRow"],
			["冒险", "ShakeRow", "DmgRow", "AimRow", "LanternRow", "FpsRow", "SkinRow"]]:
		var section := VBoxContainer.new()
		section.custom_minimum_size.x = 324
		section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		section.add_theme_constant_override("separation", 8)
		columns.add_child(section)
		var heading := Label.new()
		heading.text = group[0]
		heading.add_theme_font_size_override("font_size", 20)
		heading.add_theme_color_override("font_color", HotwTheme.GOLD)
		section.add_child(heading)
		for row_name: String in group.slice(1):
			var row := vb.get_node(row_name) as HBoxContainer
			row.reparent(section)
			row.custom_minimum_size.y = 48
			var label := row.get_node("Label") as Label
			label.custom_minimum_size.x = 104
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			if row.get_child(1) is CheckButton:
				var check := row.get_child(1) as CheckButton
				check.custom_minimum_size = Vector2(84, 48)
				check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				check.text = "开启" if check.button_pressed else "关闭"
				check.toggled.connect(func(enabled: bool) -> void:
					check.text = "开启" if enabled else "关闭")
			elif row.get_child(1) is HSlider:
				var slider := row.get_child(1) as HSlider
				slider.custom_minimum_size.y = 64
				var value := Label.new()
				value.custom_minimum_size.x = 40
				value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
				value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
				value.text = "%d" % roundi(slider.value * 100.0)
				value.add_theme_font_size_override("font_size", 16)
				value.add_theme_color_override("font_color", HotwTheme.MUTED)
				row.add_child(value)
				slider.value_changed.connect(func(amount: float) -> void:
					value.text = "%d" % roundi(amount * 100.0))
