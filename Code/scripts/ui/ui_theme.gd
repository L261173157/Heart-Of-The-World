## 共享 UI 主题工具：深色玻璃拟态 + 金色强调（HUD 与主菜单共用）。
## 圆形图标按钮（MOBA 风格）也在这一站式构造：样式盒 + 图标层 +
## 冷却遮罩层 + 冷却数字，调用方只管订阅刷新。
## 纯静态方法、不持状态——可被任意 Control 场景零成本引用。
class_name HotwTheme

const GOLD := Color(1.0, 0.85, 0.45)


## 深色玻璃主题：PanelContainer 深底金边、Button 三态 + 字色。
## 与 HUD 原 _apply_theme 生成的完全同款，抽出来给主菜单复用。
## 美术 v5 借鉴①：面板底色调向 NA 官方九宫格 np_6 的暗蓝灰（纹理九宫格在
## 4.7 的 StyleBoxTexture 边距 API 缺失，改用同色系 StyleBoxFlat；对话气泡
## 则直接用九宫格件——见 hud._setup_dialogue_bubble）
static func glass_theme() -> Theme:
	var theme := Theme.new()
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.09, 0.11, 0.16, 0.92)
	panel.border_color = Color(0.32, 0.36, 0.45, 0.9)
	panel.set_border_width_all(2)
	panel.set_corner_radius_all(4)
	panel.set_content_margin_all(8)
	theme.set_stylebox("panel", "PanelContainer", panel)

	var btn := StyleBoxFlat.new()
	btn.bg_color = Color(0.13, 0.16, 0.2, 0.92)
	btn.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.5)
	btn.set_border_width_all(1)
	btn.set_corner_radius_all(6)
	btn.set_content_margin_all(6)
	theme.set_stylebox("normal", "Button", btn)

	var btn_hover := btn.duplicate()
	btn_hover.bg_color = Color(0.2, 0.24, 0.3, 0.95)
	btn_hover.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.9)
	theme.set_stylebox("hover", "Button", btn_hover)

	var btn_disabled := btn.duplicate()
	btn_disabled.bg_color = Color(0.09, 0.1, 0.12, 0.7)
	btn_disabled.border_color = Color(0.5, 0.5, 0.5, 0.3)
	theme.set_stylebox("disabled", "Button", btn_disabled)

	theme.set_color("font_color", "Button", Color(1.0, 0.94, 0.8))
	theme.set_color("font_disabled_color", "Button", Color(0.55, 0.55, 0.55))
	theme.set_color("font_color", "Label", Color(0.94, 0.94, 0.9))
	return theme


## 把按钮改造成圆形（MOBA 触控钮）：按当前尺寸取圆角半径，
## 覆盖 normal/hover/pressed/disabled 四态样式盒。要求按钮是正方形。
static func style_circle_button(btn: Button) -> void:
	var radius: float = minf(btn.size.x, btn.size.y) / 2.0
	if radius <= 0.0:
		radius = minf(btn.custom_minimum_size.x, btn.custom_minimum_size.y) / 2.0
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.corner_radius_top_left = int(radius)
		sb.corner_radius_top_right = int(radius)
		sb.corner_radius_bottom_left = int(radius)
		sb.corner_radius_bottom_right = int(radius)
		sb.border_width_left = 2
		sb.border_width_top = 2
		sb.border_width_right = 2
		sb.border_width_bottom = 2
		match state:
			"normal":
				sb.bg_color = Color(0.13, 0.16, 0.2, 0.92)
				sb.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.55)
			"hover":
				sb.bg_color = Color(0.22, 0.26, 0.32, 0.95)
				sb.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.95)
			"pressed":
				sb.bg_color = Color(0.28, 0.24, 0.16, 0.95)
				sb.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 1.0)
			"disabled":
				sb.bg_color = Color(0.09, 0.1, 0.12, 0.75)
				sb.border_color = Color(0.5, 0.5, 0.5, 0.3)
		btn.add_theme_stylebox_override(state, sb)


## 圆形按钮内铺图标：等比居中、内缩 margin、不挡点击。
## 返回图标节点（调用方按需做置灰 modulate）。
static func add_icon(btn: Control, texture: Texture2D, margin := 16.0) -> TextureRect:
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.texture = texture
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = margin
	icon.offset_top = margin
	icon.offset_right = -margin
	icon.offset_bottom = -margin
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(icon)
	return icon


## 冷却遮罩 + 数字（画在图标之上、点击穿透）：
## 返回 {"overlay": ColorRect, "cd": Label}，调用方控制 visible / text。
static func add_cd_overlay(btn: Control) -> Dictionary:
	var overlay := ColorRect.new()
	overlay.name = "CdOverlay"
	overlay.color = Color(0, 0, 0, 0.55)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
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


## NA 官方九宫格件作面板底（玩法 v7 P2）：4.7 无 StyleBoxTexture 边距 API，
## 用 NinePatchRect 铺满面板覆盖原 stylebox（调用方 add_child 后 move_child(0)
## 压到内容之下）。纹理 64×64 NEAREST 放大保像素、边距带 20（与对话气泡同款）
static func nine_patch_bg(path: String) -> NinePatchRect:
	var tex: Texture2D = load(path)
	if tex == null:
		return null
	var img: Image = tex.get_image()
	img.resize(64, 64, Image.INTERPOLATE_NEAREST)
	var np := NinePatchRect.new()
	np.texture = ImageTexture.create_from_image(img)
	np.patch_margin_left = 20
	np.patch_margin_top = 20
	np.patch_margin_right = 20
	np.patch_margin_bottom = 20
	np.set_anchors_preset(Control.PRESET_FULL_RECT)
	np.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return np


## TS Paper 纸面九宫（美术 v6）：320 原生纹理、边饰带宽约 1/5.7≈56；
## 不缩放（Paper 细节在原尺寸最干净），用法同 nine_patch_bg
static func nine_patch_paper(path: String) -> NinePatchRect:
	var tex: Texture2D = load(path)
	if tex == null:
		return null
	var np := NinePatchRect.new()
	np.texture = tex
	np.patch_margin_left = 56
	np.patch_margin_top = 56
	np.patch_margin_right = 56
	np.patch_margin_bottom = 56
	np.set_anchors_preset(Control.PRESET_FULL_RECT)
	np.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return np
