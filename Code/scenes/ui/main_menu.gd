## 主菜单：标题 + 开始/继续冒险 / 新的冒险（清档确认）/ 冒险档案 / 设置。
## 作为游戏主场景（project.godot run/main_scene）。
extends Control

const ICON_START := preload("res://assets/ts/icons/attack.png")
## 语义对位：play=开始新的冒险 / save=档案箱 / star=设置偏好。
## 注意 TS 包的 codex.png 与 settings.png 贴图内容同为音符（挑图时错位），勿用
const ICON_NEW := preload("res://assets/ts/icons/play.png")
const ICON_ARCHIVE := preload("res://assets/ts/icons/save.png")
const ICON_SETTINGS := preload("res://assets/ts/icons/star_gold.png")
## 底部群系地平线装饰条（六群系地表图，与游戏内同源素材）
const REGION_TERRAINS: Array[String] = [
	"res://assets/terrain/region_center.png",
	"res://assets/terrain/region_east.png",
	"res://assets/terrain/region_lava.png",
	"res://assets/terrain/region_snow.png",
	"res://assets/terrain/region_swamp.png",
	"res://assets/terrain/region_west.png",
]

## 物种总数（档案面板"图鉴 X/总数"）：懒加载缓存，目录扫描只做一次
var _species_total := -1


func _ready() -> void:
	_apply_style()
	# 面板底 TS 化（v6 §8 收口）：档案=WoodTable 木桌（浅字在木色上保对比；
	# 原 RegularPaper 太浅、金字对比不足），新冒险确认=SpecialPaper 深纸
	HotwTheme.paper_panel(get_node("ArchiveLayer/ArchivePanel"), HotwTheme.WOOD_TILE, 40)
	HotwTheme.paper_panel(get_node("NewGameConfirm/NewPanel"), HotwTheme.PAPER_SPECIAL)
	# 危险动作红色方钮：清档确认（退出钮 iOS 隐藏，桌面端见 _apply_style）
	HotwTheme.style_ts_square_button(%NewConfirmBtn, true)
	# iOS 刘海/圆角：菜单根整体收进安全区。Bg 随之缩进后，边带露出的是
	# project.godot 的 default_clear_color（已设为同色），视觉无缝
	SafeAreaRoot.apply_to(self)
	# 方法引用连接：菜单释放时自动断连（lambda 悬连会在视口尺寸变化时
	# 对已释放菜单悬空调用）
	get_viewport().size_changed.connect(_on_viewport_resized)
	# 主菜单 BGM（进世界后由区域检测换成区域曲）
	SfxManager.play_music("menu")
	# 复位触屏输入残留：按住摇杆时退出世界（节点释放收不到 release 事件），
	# 摇杆向量会永久残留——再进世界角色自顾自朝旧方向漂移
	TouchInput.reset()
	%StartBtn.pressed.connect(_start)
	%NewBtn.pressed.connect(func() -> void: _open_layer(%NewGameConfirm))
	%NewConfirmBtn.pressed.connect(_do_new_game)
	%NewCancel.pressed.connect(func() -> void: %NewGameConfirm.visible = false)
	%ArchiveBtn.pressed.connect(_toggle_archive)
	%ArchiveClose.pressed.connect(_toggle_archive)
	%ArchiveSave.pressed.connect(_manual_save)
	%SettingsBtn.pressed.connect(_toggle_settings)
	%SettingsClose.pressed.connect(_toggle_settings)
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


func _on_viewport_resized() -> void:
	SafeAreaRoot.apply_to(self)


## 视觉：与游戏内 HUD 同款 TS 主题；标题区垫 TS 布幡、菜单按钮图形化（图标+文字），
## 底部铺六群系地平线装饰条点题"心之世界"的多群系荒野。
func _apply_style() -> void:
	theme = HotwTheme.glass_theme()
	# 标题横幅（TS SmallRibbons 芥末黄丝带九宫拉伸；store 页 Banner 为
	# 大透明区形状件不能整幅垫底），标题深棕字浮于丝带上
	var banner := HotwTheme.ribbon_banner(720.0, 88.0, 2)
	banner.name = "TitleBanner"
	banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner.position = Vector2(-360, 96)
	add_child(banner)
	move_child(banner, get_node("Title").get_index())
	var title := get_node("Title") as Label
	title.add_theme_color_override("font_color", Color(0.33, 0.21, 0.09))
	title.add_theme_color_override("font_outline_color", Color(1.0, 0.96, 0.88, 0.85))
	title.add_theme_constant_override("outline_size", 6)
	for pair: Array in [[%StartBtn, ICON_START], [%NewBtn, ICON_NEW],
			[%ArchiveBtn, ICON_ARCHIVE], [%SettingsBtn, ICON_SETTINGS]]:
		var btn: Button = pair[0]
		btn.icon = pair[1]
		btn.expand_icon = true
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		# 图标与文字之间留出呼吸位（展开图标默认贴文字）
		btn.add_theme_constant_override("h_separation", 14)
	# 退出钮（仅桌面）：红色方钮警示，配 Swords 交叉剑图标
	HotwTheme.style_ts_square_button(%QuitBtn, true)
	%QuitBtn.icon = preload("res://assets/ts/UI Elements/UI Elements/Swords/Swords.png")
	%QuitBtn.expand_icon = true
	%QuitBtn.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	%QuitBtn.add_theme_constant_override("h_separation", 14)
	%StartBtn.add_theme_font_size_override("font_size", 22)
	# 档案面板网格标签（真源在 tscn 无字号覆写）：iOS 上默认 16 号≈8.7pt 不可读
	for grid_label: Label in %InfoGrid.get_children():
		grid_label.add_theme_font_size_override("font_size", 18)
	var strip := HBoxContainer.new()
	strip.name = "TerrainStrip"
	# 底部全宽 + 高 140：anchors+offsets 一步到位（分开设 preset 与 offset
	# 会触发引擎 "non-equal opposite anchors" 布局提示警告）
	strip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	strip.offset_top = -140.0
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for path: String in REGION_TERRAINS:
		var tex := TextureRect.new()
		tex.texture = load(path)
		tex.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_SCALE
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		strip.add_child(tex)
	# 装饰条压暗并向背景退层：位于 Bg 之上、Title/MenuBox 之下
	strip.modulate = Color(0.6, 0.62, 0.65, 0.5)
	add_child(strip)
	move_child(strip, get_node("Bg").get_index() + 1)


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
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")


# --- 弹层互斥：设置 / 新冒险确认 / 冒险档案同一时刻只开一个 ---

## 打开一个弹层并收起其余（按钮可点的前提是其余弹层没压在它上面）
func _open_layer(layer: Control) -> void:
	for other: Control in [%SettingsLayer, %NewGameConfirm, %ArchiveLayer]:
		other.visible = other == layer


func _toggle_settings() -> void:
	if %SettingsLayer.visible:
		%SettingsLayer.visible = false
	else:
		_open_layer(%SettingsLayer)


func _toggle_archive() -> void:
	if %ArchiveLayer.visible:
		%ArchiveLayer.visible = false
	else:
		_refresh_archive()
		_open_layer(%ArchiveLayer)


## 新的冒险 = 清档回到初始状态：确认后留在菜单（按钮回到"开始冒险"），
## 不直接进世界——玩家可能想先看看设置或换个时间再出发
func _do_new_game() -> void:
	GameState.reset_all()
	%NewGameConfirm.visible = false
	%StartBtn.text = "开始冒险"
	%NewBtn.visible = false
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
	GameState.save_now()
	%SaveTimeValue.text = _format_save_time()
	_toast("已保存")


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
	var tween := create_tween()
	tween.tween_interval(1.6)
	tween.tween_property(%MenuToast, "modulate:a", 0.0, 0.6)
