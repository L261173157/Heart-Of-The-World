## 主菜单：标题 + 开始/继续冒险 / 新的冒险（清档确认）/ 冒险档案 / 设置。
## 作为游戏主场景（project.godot run/main_scene）。
extends Control

const ICON_START := preload("res://assets/ts/icons/attack.png")
## 语义对位：play=开始新的冒险 / save=档案箱 / star=设置偏好。
## 注意 TS 包的 codex.png 与 settings.png 贴图内容同为音符（挑图时错位），勿用
const ICON_NEW := preload("res://assets/ts/icons/play.png")
const ICON_ARCHIVE := preload("res://assets/ts/icons/save.png")
const ICON_SETTINGS := preload("res://assets/ts/icons/star_gold.png")
const MENU_VIGNETTE := preload("res://scenes/ui/menu_vignette.gd")
var _vignette: Control
var _menu_caption: Label
var _wordmark: Label
var _menu_rule: ColorRect
var _toast_tween: Tween
var _return_focus: Control
var _starting := false

## 物种总数（档案面板"图鉴 X/总数"）：懒加载缓存，目录扫描只做一次
var _species_total := -1


func _ready() -> void:
	_apply_style()
	# 面板底 TS 化（v6 §8 收口）：档案=WoodTable 木桌（浅字在木色上保对比；
	# 原 RegularPaper 太浅、金字对比不足），新冒险确认=SpecialPaper 深纸
	HotwTheme.paper_panel(get_node("ArchiveLayer/ArchivePanel"), HotwTheme.WOOD_TILE, 24)
	HotwTheme.paper_panel(get_node("NewGameConfirm/NewPanel"), HotwTheme.PAPER_SPECIAL)
	# 危险动作红色方钮只用于清档确认；退出入口保留低权重。
	HotwTheme.style_ts_square_button(%NewConfirmBtn, true)
	# iOS 刘海/圆角：操作、标题与插画均收进安全区，边带保留深色背景。
	SafeAreaRoot.apply_to(self)
	# 方法引用连接：菜单释放时自动断连（lambda 悬连会在视口尺寸变化时
	# 对已释放菜单悬空调用）
	get_viewport().size_changed.connect(_on_viewport_resized)
	resized.connect(_layout_menu)
	# 主菜单 BGM（进世界后由区域检测换成区域曲）
	SfxManager.play_music("menu")
	# 复位触屏输入残留：按住摇杆时退出世界（节点释放收不到 release 事件），
	# 摇杆向量会永久残留——再进世界角色自顾自朝旧方向漂移
	TouchInput.reset()
	%StartBtn.pressed.connect(_start)
	%NewBtn.pressed.connect(func() -> void: _open_layer(%NewGameConfirm))
	%NewConfirmBtn.pressed.connect(_do_new_game)
	%NewCancel.pressed.connect(_close_layers)
	%ArchiveBtn.pressed.connect(_toggle_archive)
	%ArchiveClose.pressed.connect(_close_layers)
	%ArchiveSave.pressed.connect(_manual_save)
	%SettingsBtn.pressed.connect(_toggle_settings)
	%SettingsClose.pressed.connect(_close_layers)
	%QuitBtn.pressed.connect(func() -> void: get_tree().quit())
	# iOS 应用不应自行退出（App Store 审核常见拒因）；仅桌面保留退出键
	if OS.has_feature("ios"):
		%QuitBtn.visible = false
	# 有进度时：主按钮变"继续冒险"，并露出"新的冒险"（清档入口）
	var has_progress := _has_progress()
	if has_progress:
		%StartBtn.text = "继续冒险"
	%NewBtn.visible = has_progress
	%NewGameConfirm.visible = false
	%ArchiveLayer.visible = false
	_layout_menu()
	call_deferred("_layout_menu")


func _on_viewport_resized() -> void:
	SafeAreaRoot.apply_to(self)
	_layout_menu()


## 左侧品牌与骑士场景、右侧操作区；安全区变化后重排，宽屏不拉伸素材。
func _layout_menu() -> void:
	if not is_instance_valid(_vignette):
		return
	var canvas := size
	if canvas.x < 1.0 or canvas.y < 1.0:
		canvas = get_viewport_rect().size
	var content_width := minf(canvas.x - 80.0, 1120.0)
	var origin := Vector2((canvas.x - content_width) * 0.5, (canvas.y - 580.0) * 0.5)
	var menu_width := 328.0
	var menu_x := origin.x + content_width - menu_width
	var art_width := minf(620.0, content_width - menu_width - 48.0)
	_set_rect($Title, Rect2(origin + Vector2(24, 62), Vector2(art_width, 78)))
	_set_rect(_wordmark, Rect2(origin + Vector2(28, 143), Vector2(art_width, 24)))
	_set_rect($Subtitle, Rect2(origin + Vector2(28, 188), Vector2(art_width, 32)))
	_set_rect(_vignette, Rect2(origin + Vector2(-8, 248), Vector2(art_width + 36, 320)))
	_set_rect(_menu_caption, Rect2(menu_x + 8, origin.y + 118, menu_width - 16, 32))
	_set_rect(_menu_rule, Rect2(menu_x + 8, origin.y + 158, menu_width - 16, 2))
	_set_rect($MenuBox, Rect2(menu_x, origin.y + 182, menu_width, 0))
	_set_rect(%MenuToast, Rect2(24, canvas.y - 66, canvas.x - 48, 36))
	# 弹层最小尺寸变化（空档/有档）及安全区变化时始终重新居中。
	for panel: Control in [$ArchiveLayer/ArchivePanel, $NewGameConfirm/NewPanel,
			$SettingsLayer/SettingsBox]:
		panel.reset_size()
		panel.position = (canvas - panel.size) * 0.5


func _set_rect(control: Control, rect: Rect2) -> void:
	control.set_anchors_preset(Control.PRESET_TOP_LEFT)
	control.position = rect.position
	control.size = rect.size


func _apply_style() -> void:
	theme = HotwTheme.glass_theme()
	$Bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$Title.add_theme_color_override("font_color", Color("f3dfac"))
	$Title.add_theme_color_override("font_outline_color", Color("111e27"))
	$Title.add_theme_constant_override("outline_size", 5)
	$Title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	$Subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	$Subtitle.text = "会呼吸、会演化的荒野"
	$Subtitle.add_theme_color_override("font_color", Color("a7b9af"))
	_wordmark = Label.new()
	_wordmark.text = "H E A R T   O F   T H E   W O R L D"
	_wordmark.add_theme_font_size_override("font_size", 15)
	_wordmark.add_theme_color_override("font_color", Color("b7a57b"))
	_wordmark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_wordmark)
	_vignette = Control.new()
	_vignette.set_script(MENU_VIGNETTE)
	_vignette.name = "AdventureVignette"
	add_child(_vignette)
	move_child(_vignette, $Bg.get_index() + 1)
	_menu_caption = Label.new()
	_menu_caption.text = "YOUR ADVENTURE"
	_menu_caption.add_theme_font_size_override("font_size", 16)
	_menu_caption.add_theme_color_override("font_color", Color("b7a57b"))
	_menu_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_menu_caption)
	_menu_rule = ColorRect.new()
	_menu_rule.color = Color(0.65, 0.55, 0.35, 0.28)
	_menu_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_menu_rule)
	# 标题与装饰全部位于弹层下方，避免挡住模态操作。
	for decoration: Control in [_wordmark, _menu_caption, _menu_rule]:
		move_child(decoration, $NewGameConfirm.get_index())
	for pair: Array in [[%StartBtn, ICON_START], [%NewBtn, ICON_NEW],
			[%ArchiveBtn, ICON_ARCHIVE], [%SettingsBtn, ICON_SETTINGS]]:
		var btn: Button = pair[0]
		btn.icon = pair[1]
		btn.expand_icon = true
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_constant_override("icon_max_width", 30 if btn == %StartBtn else 24)
		btn.add_theme_constant_override("h_separation", 16)
		if btn != %StartBtn:
			HotwTheme.style_wood_card(btn)
	%StartBtn.add_theme_font_size_override("font_size", 24)
	# 退出不是清档危险动作，降为低权重文字按钮；触控范围仍保留 48px。
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		var exit_style := StyleBoxFlat.new()
		exit_style.bg_color = Color(0.22, 0.30, 0.32, 0.28) if state == "hover" else Color.TRANSPARENT
		exit_style.set_content_margin_all(10)
		%QuitBtn.add_theme_stylebox_override(state, exit_style)
	%QuitBtn.add_theme_color_override("font_color", Color("839995"))
	for grid_label: Label in %InfoGrid.get_children():
		grid_label.add_theme_font_size_override("font_size", 19)
		if grid_label.name.ends_with("Value"):
			grid_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			grid_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid_label.add_theme_color_override("font_color", Color("fff0c9"))
		else:
			grid_label.add_theme_color_override("font_color", Color("c9c1ab"))
	# 保存提示必须显示在档案模态层之上；重置后也继续复用同一个 toast。
	%MenuToast.z_index = 10
	%MenuToast.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _has_progress() -> bool:
	# 口径与 reset_all 清理的字段对齐：有装备/强化/引导进度也算（不只等级金币图鉴）
	# 仅进入世界后立刻返回也已经产生生态快照；若漏掉它，按钮会误写“开始冒险”，
	# 实际点击却恢复旧世界，让玩家误以为刚才的世界没有保存。
	var has_world := typeof(GameState.ecology_snapshot) == TYPE_DICTIONARY \
			and not (GameState.ecology_snapshot as Dictionary).is_empty()
	return has_world or GameState.stats.level > 1 or GameState.gold > 0 or not GameState.codex.is_empty() \
		or not GameState.stats.equips.is_empty() or not GameState.stats.passives.is_empty() \
		or GameState.upgrade_level("weapon") > 0 or GameState.upgrade_level("staff") > 0 \
		or GameState.upgrade_level("vigor") > 0 or not GameState.tutorial_flags.is_empty()


func _start() -> void:
	if _starting or %SettingsLayer.visible or %NewGameConfirm.visible or %ArchiveLayer.visible:
		return
	_starting = true
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")


# --- 弹层互斥：设置 / 新冒险确认 / 冒险档案同一时刻只开一个 ---

## 打开一个弹层并收起其余（按钮可点的前提是其余弹层没压在它上面）
func _open_layer(layer: Control) -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null and $MenuBox.is_ancestor_of(focused):
		_return_focus = focused
	for other: Control in [%SettingsLayer, %NewGameConfirm, %ArchiveLayer]:
		other.visible = other == layer
	for button: Control in $MenuBox.get_children():
		button.focus_mode = Control.FOCUS_NONE
	# 防止键盘焦点仍停在模态层背后的开始按钮，Enter 穿透切进世界。
	if layer == %NewGameConfirm:
		%NewCancel.grab_focus()
	elif layer == %ArchiveLayer:
		%ArchiveClose.grab_focus()
	else:
		%SettingsClose.grab_focus()
	_layout_menu()
	call_deferred("_layout_menu")


func _close_layers() -> void:
	for layer: Control in [%SettingsLayer, %NewGameConfirm, %ArchiveLayer]:
		layer.visible = false
	for button: Control in $MenuBox.get_children():
		button.focus_mode = Control.FOCUS_ALL
	if is_instance_valid(_return_focus) and _return_focus.is_visible_in_tree():
		_return_focus.grab_focus()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		for layer: Control in [%SettingsLayer, %NewGameConfirm, %ArchiveLayer]:
			if layer.visible:
				_close_layers()
				get_viewport().set_input_as_handled()
				return


func _toggle_settings() -> void:
	if %SettingsLayer.visible:
		_close_layers()
	else:
		_open_layer(%SettingsLayer)


func _toggle_archive() -> void:
	if %ArchiveLayer.visible:
		_close_layers()
	else:
		_refresh_archive()
		_open_layer(%ArchiveLayer)


## 新的冒险 = 清档回到初始状态：确认后留在菜单（按钮回到"开始冒险"），
## 不直接进世界——玩家可能想先看看设置或换个时间再出发
func _do_new_game() -> void:
	if not %NewGameConfirm.visible:
		return
	GameState.reset_all()
	_close_layers()
	%StartBtn.text = "开始冒险"
	%NewBtn.visible = false
	_layout_menu()
	%StartBtn.grab_focus()
	_toast("进度已清空，新的冒险从这里开始")


# --- 冒险档案（进度概览 + 手动保存） ---

## 打开时刷新：等级/金币/图鉴/成就直读 GameState；游戏天数与最后保存时间
## 在菜单期间分别存于 ecology_snapshot 与 last_save_unix（世界运行中打不开主菜单）
func _refresh_archive() -> void:
	var has_progress := _has_progress()
	%EmptyHint.visible = not has_progress
	%InfoGrid.visible = has_progress
	%AutoHint.visible = has_progress
	%ArchiveSave.disabled = not has_progress
	if not has_progress:
		return
	var day := 1
	if typeof(GameState.ecology_snapshot) == TYPE_DICTIONARY:
		day = maxi(1, int((GameState.ecology_snapshot as Dictionary).get("game_day", 1)))
	%LvValue.text = "Lv.%d" % GameState.stats.level
	%GoldValue.text = "%d" % GameState.gold
	%DayValue.text = "第 %d 天" % day
	%AgeValue.text = "%d / %d 天" % [int(GameState.stats.age_days),
		int(GameState.stats.lifespan_days)]
	%CodexValue.text = "%d / %d" % [GameState.codex.size(), _species_count()]
	%AchvValue.text = "%d / %d" % [GameState.achievements.size(),
		AchievementManager.ACHIEVEMENTS.size()]
	%SaveTimeValue.text = _format_save_time()


func _manual_save() -> void:
	var saved := GameState.save_now()
	%SaveTimeValue.text = _format_save_time()
	_toast("已保存" if saved else ("存档已禁用" if not GameState.save_enabled else "保存失败，请重试"))


func _species_count() -> int:
	if _species_total < 0:
		_species_total = SpeciesCatalog.build_all().size()
	return _species_total


## Unix 秒 → 本地 HH:MM。get_time_dict_from_unix_time 返回 UTC，
## 需加上时区偏移（bias，分钟）；0 = 从未保存过
func _format_save_time() -> String:
	if GameState.last_save_unix <= 0.0:
		return "尚未保存"
	var bias_min := int(Time.get_time_zone_from_system().get("bias", 0))
	var t := Time.get_time_dict_from_unix_time(GameState.last_save_unix + bias_min * 60)
	return "%02d:%02d" % [t.hour, t.minute]


func _toast(text: String) -> void:
	%MenuToast.text = text
	%MenuToast.modulate.a = 1.0
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(1.6)
	_toast_tween.tween_property(%MenuToast, "modulate:a", 0.0, 0.6)
