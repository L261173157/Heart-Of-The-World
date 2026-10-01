## 共享 UI 主题工具（美术 v6 · Tiny Swords 全套）：TS 方钮/圆钮两态、
## Paper 纸面九宫、丝带标题签。HUD 与主菜单共用。
## 圆形图标按钮（MOBA 风格）也在这一站式构造：样式盒 + 图标层 +
## 冷却遮罩层 + 冷却数字，调用方只管订阅刷新。
## 纯静态方法、不持状态——可被任意 Control 场景零成本引用。
class_name HotwTheme

const GOLD := Color("e7c785")
const INK := Color("17232c")
const TEXT := Color("f4ecd8")
const MUTED := Color("b4c3c5")
static var _texture_cache: Dictionary = {}


## 先裁掉源图透明留白再做九宫；边角必须小于目标尺寸的一半。
## 旧版 128px 整图 + 36px 上下边距，在 56px 按钮里会把可见面压成细线。
## 缓存为独立纹理，保证切片坐标一致且不在每帧复制图片。
static func cropped_texture(path: String, rect: Rect2i = Rect2i()) -> Texture2D:
	var key := path + str(rect)
	if _texture_cache.has(key):
		return _texture_cache[key]
	var source: Texture2D = load(path)
	if source == null:
		return null
	var img := source.get_image()
	if img == null or img.is_empty():
		return source
	if img.is_compressed():
		img.decompress()
	var region := rect if rect.has_area() else img.get_used_rect()
	var tex := ImageTexture.create_from_image(img.get_region(region))
	_texture_cache[key] = tex
	return tex


static func panel_style() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color("17232cf5")
	box.border_color = Color("788575")
	box.set_border_width_all(2)
	box.set_corner_radius_all(3)
	box.set_content_margin_all(12)
	box.shadow_color = Color(0.02, 0.025, 0.035, 0.4)
	box.shadow_size = 8
	box.shadow_offset = Vector2(0, 4)
	return box

## TS UI 元素真源目录（免 preload：多数面板只加载一次，惰性 load 即可）
const TS_UI := "res://assets/ts/UI Elements/UI Elements"
const PAPER_REGULAR := TS_UI + "/Papers/RegularPaper.png"
const PAPER_SPECIAL := TS_UI + "/Papers/SpecialPaper.png"
const WOOD_TABLE := TS_UI + "/Wood Table/WoodTable.png"
const WOOD_TILE := TS_UI + "/Wood Table/WoodTable_Slots.png"
const RIBBONS := TS_UI + "/Ribbons/SmallRibbons.png"
## 丝带色序（SmallRibbons 320×640 十行 ×64px，每色长短尾两条，这里取长尾）：
## 0=蓝青 1=砖红 2=芥末黄 3=紫 4=蓝灰
const RIBBON_ROW := {0: 0, 1: 2, 2: 4, 3: 6, 4: 8}


## 全局主题：PanelContainer 保留深色底（各面板单独叠 TS 纸面/木桌九宫），
## Button 统一 TS 蓝方钮两态（美术 v6 §8「StyleBox/Theme 统一」收口），
## CheckButton 统一「暗槽 ↔ TS 蓝瓦」开关两态。
static func glass_theme() -> Theme:
	var theme := Theme.new()
	var panel := panel_style()
	theme.set_stylebox("panel", "PanelContainer", panel)

	# TS 方钮裁掉透明边，12px 角框保形；最小48px控件仍有完整可见面
	var btn := _texture_box(_sq_btn("Blue", "Regular"), 12.0, 12.0)
	var btn_hover := _texture_box(_sq_btn("Blue", "Regular"), 12.0, 12.0)
	btn_hover.modulate_color = Color(1.15, 1.15, 1.15)
	var btn_pressed := _texture_box(_sq_btn("Blue", "Pressed"), 12.0, 12.0)
	var btn_disabled := _texture_box(_sq_btn("Blue", "Regular"), 12.0, 12.0)
	btn_disabled.modulate_color = Color(0.55, 0.60, 0.63, 0.85)
	theme.set_stylebox("normal", "Button", btn)
	theme.set_stylebox("hover", "Button", btn_hover)
	theme.set_stylebox("pressed", "Button", btn_pressed)
	theme.set_stylebox("disabled", "Button", btn_disabled)

	# CheckButton（设置面板开关行）：关=暗槽、开=TS 蓝瓦（Tiny 方钮件）
	var ck_off := StyleBoxFlat.new()
	ck_off.bg_color = Color(0.14, 0.12, 0.1, 0.9)
	ck_off.border_color = Color(0.42, 0.33, 0.24, 0.9)
	ck_off.set_border_width_all(2)
	ck_off.set_corner_radius_all(4)
	ck_off.set_content_margin_all(10)
	var ck_on := _texture_box(TS_UI + "/Buttons/TinySquareBlueButton.png", 20.0, 10.0)
	theme.set_stylebox("normal", "CheckButton", ck_off)
	theme.set_stylebox("hover", "CheckButton", ck_off)
	theme.set_stylebox("pressed", "CheckButton", ck_on)
	theme.set_stylebox("hover_pressed", "CheckButton", ck_on)
	theme.set_stylebox("disabled", "CheckButton", ck_off)

	theme.set_color("font_color", "Button", Color(1.0, 0.96, 0.86))
	theme.set_color("font_hover_color", "Button", Color(1.0, 1.0, 0.95))
	theme.set_color("font_pressed_color", "Button", Color(0.95, 0.92, 0.8))
	theme.set_color("font_disabled_color", "Button", Color(0.55, 0.55, 0.55))
	theme.set_color("font_color", "CheckButton", Color(0.94, 0.94, 0.9))
	theme.set_color("font_pressed_color", "CheckButton", Color(1.0, 0.95, 0.8))
	theme.set_color("font_color", "Label", TEXT)
	theme.set_color("font_outline_color", "Button", Color("20363d"))
	theme.set_constant("outline_size", "Button", 2)
	theme.set_constant("h_separation", "Button", 12)
	theme.set_constant("icon_max_width", "Button", 34)
	theme.set_font_size("font_size", "Button", 18)
	theme.set_font_size("font_size", "Label", 18)
	theme.set_constant("separation", "VBoxContainer", 10)
	theme.set_constant("separation", "HBoxContainer", 10)
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color.TRANSPARENT
	focus.border_color = GOLD
	focus.set_border_width_all(2)
	focus.set_corner_radius_all(3)
	focus.set_expand_margin_all(3)
	theme.set_stylebox("focus", "Button", focus)
	var rail := StyleBoxFlat.new()
	rail.bg_color = Color("0c161f")
	rail.border_color = Color("617780")
	rail.set_border_width_all(1)
	rail.content_margin_top = 5
	rail.content_margin_bottom = 5
	theme.set_stylebox("slider", "HSlider", rail)
	var progress := rail.duplicate() as StyleBoxFlat
	progress.bg_color = Color("78afae")
	theme.set_stylebox("grabber_area", "HSlider", progress)
	theme.set_stylebox("grabber_area_highlight", "HSlider", progress)
	return theme


static func _sq_btn(kind: String, state: String) -> String:
	return "%s/Buttons/Small%sSquareButton_%s.png" % [TS_UI, kind, state]


## 纹理样式盒：四向边距保角框、内容边距定文字内缩（TS 按钮通用底座）
static func _texture_box(path: String, tex_margin: float, content_margin: float) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = cropped_texture(path)
	sb.texture_margin_left = tex_margin
	sb.texture_margin_top = tex_margin
	sb.texture_margin_right = tex_margin
	sb.texture_margin_bottom = tex_margin
	sb.set_content_margin_all(content_margin)
	return sb


## 触控圆钮 TS 化（MOBA 布局）：Small 圆钮两态逐钮覆盖样式盒。
## 替代 v5 深色玻璃 style_circle_button——节点/信号/图标层结构全不变，只换底。
static func style_ts_round_button(btn: Button, red := false) -> void:
	var kind := "Red" if red else "Blue"
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		var file := "Pressed" if state == "pressed" else "Regular"
		var sb := _texture_box("%s/Buttons/Small%sRoundButton_%s.png" % [TS_UI, kind, file], 0.0, 10.0)
		match state:
			"hover":
				sb.modulate_color = Color(1.14, 1.14, 1.14)
			"disabled":
				sb.modulate_color = Color(0.5, 0.5, 0.55, 0.85)
		btn.add_theme_stylebox_override(state, sb)


## 方钮逐钮换色（危险动作=红）：全局主题是蓝方钮，退出/清档确认等用红
static func style_ts_square_button(btn: Button, red := false) -> void:
	var kind := "Red" if red else "Blue"
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		var file := "Pressed" if state == "pressed" else "Regular"
		var sb := _texture_box(_sq_btn(kind, file), 12.0, 12.0)
		match state:
			"hover":
				sb.modulate_color = Color(1.15, 1.15, 1.15)
			"disabled":
				sb.modulate_color = Color(0.55, 0.60, 0.63, 0.85)
		btn.add_theme_stylebox_override(state, sb)


## 木瓦卡片底（三选一赐福卡）：WoodTable_Slots 单瓦拉伸，木色中棕配浅字
static func style_wood_card(btn: Button) -> void:
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		var sb := _texture_box(WOOD_TILE, 16.0, 16.0)
		match state:
			"hover":
				sb.modulate_color = Color(1.18, 1.18, 1.18)
			"pressed":
				sb.modulate_color = Color(0.82, 0.82, 0.88)
		btn.add_theme_stylebox_override(state, sb)


## TS 纸面/木桌九宫铺进面板：叠在原 stylebox 之上、内容之下
## （add_child 后 move_child(0)；纹理不缩放，Paper 细节原尺寸最干净）
static func paper_panel(panel: Control, path: String, margin := 56) -> void:
	if panel == null:
		return
	var tex: Texture2D = cropped_texture(path)
	if tex == null:
		return
	var np := NinePatchRect.new()
	np.texture = tex
	np.patch_margin_left = mini(margin, 24)
	np.patch_margin_top = mini(margin, 24)
	np.patch_margin_right = mini(margin, 24)
	np.patch_margin_bottom = mini(margin, 24)
	# 纹理只提供边缘触感，深底承担阅读对比，避免棕色噪点抢文字。
	np.modulate = Color(0.28, 0.34, 0.39, 0.42)
	np.set_anchors_preset(Control.PRESET_FULL_RECT)
	np.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(np)
	panel.move_child(np, 0)


## SmallRibbons 的每行是「左端64 + 空64 + 中段64 + 空64 + 右端64」，
## 不是连续横幅。先拼成192px完整带，再缩放；不能把空白当成九宫边距。
static func ribbon_texture(color_idx: int) -> Texture2D:
	var key := "ribbon_%d" % color_idx
	if _texture_cache.has(key):
		return _texture_cache[key]
	var source: Texture2D = load(RIBBONS)
	var src := source.get_image()
	if src.is_compressed():
		src.decompress()
	var strip := Image.create(192, 64, false, Image.FORMAT_RGBA8)
	var row: int = RIBBON_ROW.get(color_idx, 0) * 64
	for i in 3:
		strip.blit_rect(src, Rect2i(i * 128, row, 64, 64), Vector2i(i * 64, 0))
	var tex := ImageTexture.create_from_image(strip)
	_texture_cache[key] = tex
	return tex


static func ribbon_tag(text: String, color_idx := 0, min_width := 200.0) -> Control:
	var atlas: Texture2D = load(RIBBONS)
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if atlas != null:
		var at := ribbon_texture(color_idx)
		var np := TextureRect.new()
		np.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		np.stretch_mode = TextureRect.STRETCH_SCALE
		np.texture = at
		np.set_anchors_preset(Control.PRESET_FULL_RECT)
		np.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(np)
	var label := Label.new()
	label.name = "RibbonLabel"
	label.text = text
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(1.0, 0.98, 0.92))
	label.add_theme_color_override("font_outline_color", Color(0.13, 0.09, 0.05, 0.85))
	label.add_theme_constant_override("outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(label)
	holder.custom_minimum_size = Vector2(maxf(min_width, 96.0 + text.length() * 22.0), 44.0)
	return holder


## 丝带横幅裸底（主菜单标题等大尺度场景）：无文字，调用方自行铺 Label。
## 注意 store 页 Banner/WoodTable 是带大透明区的形状件，不能整幅垫底
static func ribbon_banner(width: float, height: float, color_idx := 0) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(width, height)
	holder.size = Vector2(width, height)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var atlas: Texture2D = load(RIBBONS)
	if atlas != null:
		var at := ribbon_texture(color_idx)
		var np := TextureRect.new()
		np.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		np.stretch_mode = TextureRect.STRETCH_SCALE
		np.texture = at
		np.set_anchors_preset(Control.PRESET_FULL_RECT)
		np.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(np)
	return holder


## 圆形按钮内铺图标：等比居中、内缩 margin、不挡点击。
## 返回图标节点（调用方按需做置灰 modulate）。
static func add_icon(btn: Control, texture: Texture2D, margin := 16.0) -> TextureRect:
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = margin
	icon.offset_top = margin
	icon.offset_right = -margin
	icon.offset_bottom = -margin
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.texture = texture
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(icon)
	return icon


## 冷却遮罩 + 数字（画在图标之上、点击穿透）：
## 返回 {"overlay": Control, "cd": Label}，调用方控制 visible / text。
static func add_cd_overlay(btn: Control) -> Dictionary:
	var overlay := Control.new()
	overlay.set_script(preload("res://scripts/ui/cooldown_mask.gd"))
	overlay.name = "CdOverlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.offset_left = 14
	overlay.offset_top = 14
	overlay.offset_right = -14
	overlay.offset_bottom = -14
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.visible = false
	btn.add_child(overlay)
	var cd := Label.new()
	cd.name = "CdLabel"
	cd.set_anchors_preset(Control.PRESET_FULL_RECT)
	cd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cd.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cd.add_theme_font_size_override("font_size", 22)
	cd.add_theme_color_override("font_color", Color(1, 0.95, 0.85))
	cd.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	cd.add_theme_constant_override("outline_size", 4)
	cd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cd.visible = false
	btn.add_child(cd)
	return {"overlay": overlay, "cd": cd}


## 右下角小角标（蓝耗数字等）：金色小字带黑描边。
static func add_badge(btn: Control, text: String) -> Label:
	var badge := Label.new()
	badge.name = "Badge"
	badge.text = text
	badge.add_theme_font_size_override("font_size", 13)
	badge.add_theme_color_override("font_color", Color(0.55, 0.75, 1.0))
	badge.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	badge.add_theme_constant_override("outline_size", 3)
	badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	badge.offset_left = -34.0
	badge.offset_top = -20.0
	badge.offset_right = -4.0
	badge.offset_bottom = -2.0
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(badge)
	return badge
