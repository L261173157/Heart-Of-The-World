## HUD：血/蓝/经验条、等级金币区域、属性点分配按钮、击杀提示、
## 小地图、生态监测面板。纯订阅 EventBus，不主动查询玩法系统。
extends CanvasLayer

const TOAST_DURATION := 2.0
const TOAST_FADE := 0.5
## toast 短窗合并：显示后 0.4s 内到达的新播报拼行而非覆盖——
## 跨区域的同一帧常连发 [进入提示/引导词/高危警告]，单通道后到者会吞掉前者
const TOAST_MERGE_WINDOW := 0.4
## toast 拼行上限（同帧三连发是设计内的最多情形；不封顶时持续事件流会
## 链式拼行无限增高，溢出覆盖下方 UI）
const TOAST_MAX_LINES := 3
const COMBAT_TOAST_DURATION := 1.2
const COMBAT_TOAST_FADE := 0.3
## 平滑血条：事件目标值（0.25s 节流推送）指数逼近，消除阶梯跳变；
## 白色残影条在掉血后按住片刻再缓慢追回——受击损耗量一眼可读（ACT 标配）
const BAR_SMOOTH := 14.0
const GHOST_HOLD := 0.35
const GHOST_DRAIN_FRAC := 0.55
## 昼夜 toast 只播前 2 个游戏日（4 次）：之后画面压暗/夜幕层自明，
## 固定播报在长局里是噪音源；"夜行者"成就走结构化信号不受影响
const DAY_TOAST_MAX := 4

@onready var hp_bar: ProgressBar = %HPBar
@onready var mp_bar: ProgressBar = %MPBar
@onready var xp_bar: ProgressBar = %XPBar
@onready var stats_label: Label = %StatsLabel
@onready var stat_buttons: Control = %StatButtons
@onready var toast_label: Label = %ToastLabel
@onready var ecology_label: Label = %EcologyContent
@onready var ecology_panel: Control = %EcologyPanel
@onready var bounty_label: Label = %BountyLabel
@onready var quest_label: Label = %QuestLabel
@onready var shop_panel: Control = %ShopPanel
@onready var shop_gold_label: Label = %GoldLabel
@onready var skill_cds: Array = [
	{"panel": %SlotDash, "label": %SlotDash/VB/Cd, "button": %DashBtn,
			"name": "冲刺", "mp": CharacterStats.DASH_COST},
	{"panel": %SlotHeavy, "label": %SlotHeavy/VB/Cd, "button": %HeavyBtn,
			"name": "重击", "mp": CharacterStats.HEAVY_COST},
	{"panel": %SlotBolt, "label": %SlotBolt/VB/Cd, "button": %BoltBtn,
			"name": "法弹", "mp": CharacterStats.BOLT_COST},
	# 治疗满血也置灰（按了不消耗，但玩家需要知道为什么没反应）
	{"panel": %SlotHeal, "label": %SlotHeal/VB/Cd, "button": %HealBtn,
			"name": "治疗", "mp": CharacterStats.HEAL_COST, "needs_hp": true},
	{"panel": %SlotEmpower, "label": %SlotEmpower/VB/Cd, "button": %EmpowerBtn,
			"name": "强化", "mp": CharacterStats.EMPOWER_COST},
]
@onready var threat_rect: ColorRect = %ThreatRect
@onready var death_label: Label = %DeathLabel
@onready var pause_layer: Control = %PauseLayer
@onready var pause_settings_layer: Control = %PauseSettingsLayer
@onready var codex_layer: Control = %CodexLayer
@onready var codex_content: Label = %CodexContent
@onready var ach_content: Label = %AchContent
@onready var passive_layer: Control = %PassiveLayer
@onready var passive_cards: Array = [%PassiveCard0, %PassiveCard1, %PassiveCard2]

var _toast_timer := 0.0
## 战斗播报位（击杀/商店反馈专用通道）
var _combat_toast: Label = Label.new()
var _combat_toast_timer := 0.0
var _region_name := ""
## 生态面板趋势：上一次 tick 的各区域总数与物种构成（对比出 ↑↓＋✕）
var _last_totals := {}
var _last_species := {}
## 技能冷却显示：最近一次推送的剩余值 + 本地流逝（订阅后本地衰减，不轮询玩法系统）
var _cd_values := [0.0, 0.0, 0.0, 0.0, 0.0]
var _cd_elapsed := 0.0
## 最近已知蓝量（技能槽"蓝不足"置灰用）
var _mp_now := 0.0
## 是否满血（治疗槽"满血无效"置灰用）
var _hp_full := false
## 三选一被动：待选择次数（连升排队）
var _pending_passive_picks := 0
var _death_tween: Tween
var _day_toast_count := 0
## 平滑条目标值（事件写入，_process 逼近）
var _hp_target := 0.0
var _mp_target := 0.0
var _xp_target := 0.0
## 血条白色残影（受击前血量的慢速追随显示）
var _hp_ghost := 0.0
var _hp_ghost_hold := 0.0
var _hp_max_cache := 1.0
var _hp_ghost_bar: ProgressBar
## Boss 顶部血条（代码构建，避免 .tscn 手术）
var _boss_layer: VBoxContainer
var _boss_name_label: Label
var _boss_bar: ProgressBar

# --- 触控按钮图标（NA CC0 像素素材，与怪物/道具同风格源） ---
const ICON_ATTACK := preload("res://assets/icons_cartoon/sword.png")
const ICON_DASH := preload("res://assets/icons_cartoon/shuriken.png")
const ICON_HEAVY := preload("res://assets/icons_cartoon/hammer.png")
const ICON_BOLT := preload("res://assets/icons_cartoon/fireball.png")
const ICON_HEAL := preload("res://assets/icons_cartoon/life-pot.png")
const ICON_EMPOWER := preload("res://assets/icons_cartoon/scroll-thunder.png")
const ICON_ECO := preload("res://assets/icons_cartoon/scroll-plant.png")
const ICON_SHOP := preload("res://assets/icons_cartoon/coin-2.png")
const ICON_CODEX := preload("res://assets/icons_cartoon/scroll-ice.png")
const ICON_COIN := preload("res://assets/icons_cartoon/gold-coin.png")
const ICON_HEART := preload("res://assets/icons_cartoon/heart.png")
## 升级三选一：被动 id → 图标（缺省用空卷轴）
const PASSIVE_ICONS := {
	"lifesteal": ICON_HEART, "atk_speed": ICON_DASH, "move": ICON_BOLT,
	"cdr": preload("res://assets/icons_cartoon/scroll-empty.png"),
	"hp": preload("res://assets/icons_cartoon/medipack.png"),
	"mp_regen": preload("res://assets/icons_cartoon/water-pot.png"),
	"phys": ICON_HEAVY, "magic": ICON_BOLT, "gold": ICON_COIN,
	"xp": preload("res://assets/icons_cartoon/fortune-cookie.png"),
	"heal_power": ICON_HEAL,
	"knock": preload("res://assets/icons_cartoon/axe.png"),
}
const PASSIVE_ICON_DEFAULT := preload("res://assets/icons_cartoon/scroll-empty.png")


func _ready() -> void:
	EventBus.player_hp_changed.connect(_on_hp_changed)
	EventBus.player_mp_changed.connect(_on_mp_changed)
	EventBus.player_progress_changed.connect(_on_progress_changed)
	EventBus.gold_changed.connect(_on_gold_changed)
	EventBus.monster_killed_by_player.connect(_on_kill)
	EventBus.player_entered_region.connect(_on_region_entered)
	EventBus.sim_tick_completed.connect(_on_sim_tick)
	EventBus.hint_requested.connect(func(text: String) -> void: _toast(text))

	%BtnStrength.pressed.connect(func(): GameState.allocate("strength"))
	%BtnAgility.pressed.connect(func(): GameState.allocate("agility"))
	%BtnIntellect.pressed.connect(func(): GameState.allocate("intellect"))

	%AttackBtn.button_down.connect(TouchInput.queue_attack)
	%DashBtn.button_down.connect(TouchInput.queue_dash)
	%HeavyBtn.button_down.connect(TouchInput.queue_heavy)
	%BoltBtn.button_down.connect(TouchInput.queue_bolt)
	%HealBtn.button_down.connect(TouchInput.queue_heal)
	%EmpowerBtn.button_down.connect(TouchInput.queue_empower)
	%BtnEco.pressed.connect(func() -> void: ecology_panel.visible = not ecology_panel.visible)
	%BtnShop.pressed.connect(_toggle_shop)
	%BtnShopClose.pressed.connect(func() -> void: shop_panel.visible = false)
	%BtnWeapon.pressed.connect(func() -> void: _try_buy("weapon"))
	%BtnStaff.pressed.connect(func() -> void: _try_buy("staff"))
	%BtnVigor.pressed.connect(func() -> void: _try_buy("vigor"))
	EventBus.world_event.connect(func(text: String) -> void: _toast(text))
	EventBus.bounty_updated.connect(func(text: String) -> void: bounty_label.text = text)
	# 任务行（世界 v5 地标 NPC 委托）：空串隐藏（无任务时不占行高）
	EventBus.quest_updated.connect(_on_quest_updated)
	EventBus.bounty_completed.connect(func(text: String) -> void: _toast(text))
	EventBus.player_skills_changed.connect(_on_skills_changed)
	EventBus.achievement_unlocked.connect(func(title: String) -> void: _toast("🏆 成就解锁：%s" % title))
	EventBus.region_threat_warning.connect(_on_threat_warning)
	EventBus.day_phase_changed.connect(_on_day_phase)
	EventBus.player_died.connect(_on_player_died)
	GameState.stats.leveled_up.connect(_on_leveled_up)

	%PauseBtn.pressed.connect(_toggle_pause)
	%ResumeBtn.pressed.connect(_toggle_pause)
	%SaveBtn.pressed.connect(_save_progress)
	%PauseSettingsBtn.pressed.connect(
		func() -> void: pause_settings_layer.visible = true)
	%PauseSettingsClose.pressed.connect(
		func() -> void: pause_settings_layer.visible = false)
	%MenuBtn.pressed.connect(_back_to_menu)
	%BtnCodex.pressed.connect(_toggle_codex)
	# 关闭按钮必须与 C/ESC 走同一路径：图鉴打开时世界处于暂停态，
	# 只隐藏弹层会留下“画面恢复但整个世界永久停住”的触屏死锁。
	%CodexClose.pressed.connect(_toggle_codex)
	for i in 3:
		passive_cards[i].pressed.connect(_pick_passive.bind(i))
	GameState.stats.leveled_up.connect(func(new_level: int, _levels: int) -> void:
		_toast("升级！Lv.%d   属性点 +1" % new_level)
	)

	toast_label.modulate.a = 0.0
	_setup_combat_toast()
	_setup_hp_ghost_bar()
	_setup_boss_bar()
	_apply_theme()
	_setup_icon_buttons()
	_setup_stats_row()
	_apply_safe_area()
	_apply_vignette()
	# 初值用真源实值：读档进世界（如 Lv.7 带 3 待分配点）时 HUD 不再闪显 Lv.1 空经验条
	_on_progress_changed(GameState.stats.level, GameState.stats.xp,
			GameState.stats.xp_to_next(), GameState.stats.pending_points)
	_on_gold_changed(GameState.gold)


## 战斗播报位：与顶部世界事件/引导提示分离的第二条 toast 通道。
## 击杀与商店反馈高频而轻量（密集战斗时每秒数条），原单通道会被它们
## 反复覆盖，生态事件/引导词一闪即逝——拆开后各走各位互不打架。
func _setup_combat_toast() -> void:
	_combat_toast.anchor_left = toast_label.anchor_left
	_combat_toast.anchor_right = toast_label.anchor_right
	_combat_toast.offset_left = toast_label.offset_left
	_combat_toast.offset_right = toast_label.offset_right
	_combat_toast.offset_top = toast_label.offset_top + 34.0
	_combat_toast.offset_bottom = toast_label.offset_bottom + 34.0
	_combat_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_combat_toast.add_theme_font_size_override("font_size", 16)
	_combat_toast.add_theme_color_override("font_color", Color(1, 0.95, 0.8, 0.9))
	_combat_toast.modulate.a = 0.0
	toast_label.get_parent().add_child(_combat_toast)
	_place_below_modal_layers(_combat_toast)


## 追加生成的常驻浮层（战斗播报/Boss 血条）压到模态弹层（暂停/设置/图鉴/
## 三选一）之下：add_child 默认排到 Root 末尾，会画在弹层上面——升级选卡
## 瞬间顶部悬着一条冻结的 Boss 血条很出戏
func _place_below_modal_layers(node: Control) -> void:
	var root := get_node("Root") as Control
	var modal_idx: int = root.get_node("PauseLayer").get_index()
	root.move_child(node, modal_idx)


func _toast_combat(message: String) -> void:
	_combat_toast.text = message
	_combat_toast.modulate.a = 1.0
	_combat_toast_timer = COMBAT_TOAST_DURATION


## 血条白色残影层：残影条占血条原有的 VBox 槽位（自带最小尺寸），
## 血条本体改挂到残影条内部、满锚随动——红填充画在白填充之上，只露出
## "刚掉的那截"白色；底色由残影条的 background 提供（血条本体背景透明，
## 见 _apply_theme）。两个兄弟槽在 VBox 里是上下堆叠不重叠的，白条会整条
## 露在红条上方——此前残影无最小尺寸（槽位高度 0）+ 被血条不透明背景盖住，
## 功能完全不可见；嵌套方案让两层真正同几何
func _setup_hp_ghost_bar() -> void:
	_hp_ghost_bar = ProgressBar.new()
	_hp_ghost_bar.name = "HPGhostBar"
	_hp_ghost_bar.custom_minimum_size = hp_bar.custom_minimum_size
	_hp_ghost_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_ghost_bar.show_percentage = false
	_hp_ghost_bar.add_theme_stylebox_override("fill", _bar_fill(Color(1.0, 0.92, 0.85, 0.9)))
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.06, 0.08, 0.85)
	bg.set_corner_radius_all(4)
	_hp_ghost_bar.add_theme_stylebox_override("background", bg)
	var parent: Control = hp_bar.get_parent()
	parent.add_child(_hp_ghost_bar)
	parent.move_child(_hp_ghost_bar, hp_bar.get_index())
	# 血条本体入住残影条（reparent 不改 owner，%HPBar 引用不受影响）
	hp_bar.reparent(_hp_ghost_bar)
	hp_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hp_bar.custom_minimum_size = Vector2.ZERO
	hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE


## Boss 顶部血条：名字 + 宽红条，顶部居中（战斗播报位下方，y=132 与其
## 90~122 错开——此前两通道几何重叠，Boss 战中击杀播报直接盖住 Boss 名字）；
## 满血也显示——遭遇即有血量锚点（通用头顶条满血不显示）
func _setup_boss_bar() -> void:
	_boss_name_label = Label.new()
	_boss_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_name_label.add_theme_font_size_override("font_size", 18)
	_boss_name_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.6))
	_boss_bar = ProgressBar.new()
	_boss_bar.custom_minimum_size = Vector2(420, 14)
	_boss_bar.show_percentage = false
	_boss_bar.add_theme_stylebox_override("fill", _bar_fill(Color(0.85, 0.2, 0.15)))
	var boss_bg := StyleBoxFlat.new()
	boss_bg.bg_color = Color(0.05, 0.06, 0.08, 0.85)
	boss_bg.set_corner_radius_all(4)
	_boss_bar.add_theme_stylebox_override("background", boss_bg)
	_boss_layer = VBoxContainer.new()
	_boss_layer.add_child(_boss_name_label)
	_boss_layer.add_child(_boss_bar)
	_boss_layer.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_boss_layer.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_boss_layer.position = Vector2(-210, 132)
	_boss_layer.visible = false
	_boss_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(get_node("Root") as Control).add_child(_boss_layer)
	_place_below_modal_layers(_boss_layer)
	EventBus.boss_tracked.connect(_on_boss_tracked)
	EventBus.boss_hp_changed.connect(_on_boss_hp)


func _on_boss_tracked(active: bool, boss_name: String) -> void:
	_boss_layer.visible = active
	if active:
		_boss_name_label.text = "⚔ %s" % boss_name


func _on_boss_hp(current: float, maximum: float) -> void:
	_boss_bar.max_value = maximum
	_boss_bar.value = current


## iOS 刘海/Home 指示条：把 HUD 根收进安全区（无刘海设备安全区=全屏，零影响）。
## Root 的子节点全部相对 Root 定位，缩 Root 即整体内收。
## 安全区是窗口坐标（iOS 上为 points），Root 偏移是拉伸后的画布单位——
## canvas_items 拉伸下二者差一个缩放系数（iPhone 横屏画布 720 高对 390pt ≈0.54），
## 不换算只内缩一半左右，血条仍会伸进刘海/Dynamic Island 15~25pt
func _apply_safe_area() -> void:
	var root := get_node("Root") as Control
	var win := get_window()
	var win_rect := Rect2i(win.position, win.size)
	var safe := DisplayServer.get_display_safe_area().intersection(win_rect)
	if not safe.has_area():
		return
	var xf := win.get_final_transform()
	root.offset_left = (safe.position.x - win_rect.position.x) / xf.get_scale().x
	root.offset_top = (safe.position.y - win_rect.position.y) / xf.get_scale().y
	root.offset_right = (safe.end.x - win_rect.end.x) / xf.get_scale().x
	root.offset_bottom = (safe.end.y - win_rect.end.y) / xf.get_scale().y


## 分屏/外接屏/旋转导致的窗口尺寸变化时安全区重算（_ready 只算一次会过期）
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_SIZE_CHANGED:
		_apply_safe_area()


# --- 视觉主题（深色玻璃拟态 + 金色强调，代码生成免维护 .tres） ---

func _apply_theme() -> void:
	(get_node("Root") as Control).theme = HotwTheme.glass_theme()

	# 进度条三色（血/蓝/经验），stylebox 覆盖默认灰条
	var fill_hp := _bar_fill(Color(0.78, 0.22, 0.2))
	var fill_mp := _bar_fill(Color(0.24, 0.5, 0.85))
	var fill_xp := _bar_fill(Color(0.9, 0.75, 0.25))
	hp_bar.add_theme_stylebox_override("fill", fill_hp)
	mp_bar.add_theme_stylebox_override("fill", fill_mp)
	xp_bar.add_theme_stylebox_override("fill", fill_xp)
	for bar: ProgressBar in [mp_bar, xp_bar]:
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0.05, 0.06, 0.08, 0.85)
		bg.set_corner_radius_all(4)
		bar.add_theme_stylebox_override("background", bg)
	# 血条本体背景透明：底色由其后绘制的白色残影条携带（_setup_hp_ghost_bar），
	# 不透明背景会把残影整条盖住——"刚掉的白截"永远不可见
	var hp_bg := StyleBoxFlat.new()
	hp_bg.bg_color = Color(0, 0, 0, 0)
	hp_bg.set_corner_radius_all(4)
	hp_bar.add_theme_stylebox_override("background", hp_bg)


func _bar_fill(c: Color) -> StyleBoxFlat:
	var fill := StyleBoxFlat.new()
	fill.bg_color = c
	fill.set_corner_radius_all(4)
	return fill


## 触控按钮图形化（MOBA 布局）：攻击大圆钮 + 五技能圆钮 + 冷却遮罩/数字/
## 蓝耗角标，右上功能钮改小圆图标钮。节点名与 button_down 触发全保留，
## 只换视觉层——图标/遮罩子节点全部鼠标穿透，不挡按钮命中。
func _setup_icon_buttons() -> void:
	HotwTheme.style_circle_button(%AttackBtn)
	HotwTheme.add_icon(%AttackBtn, ICON_ATTACK, 30.0)
	var skill_btns: Array = [%DashBtn, %HeavyBtn, %BoltBtn, %HealBtn, %EmpowerBtn]
	var skill_icons: Array = [ICON_DASH, ICON_HEAVY, ICON_BOLT, ICON_HEAL, ICON_EMPOWER]
	for i in skill_btns.size():
		var btn: Button = skill_btns[i]
		HotwTheme.style_circle_button(btn)
		var icon := HotwTheme.add_icon(btn, skill_icons[i], 18.0)
		var cd_parts := HotwTheme.add_cd_overlay(btn)
		HotwTheme.add_badge(btn, str(int(skill_cds[i]["mp"])))
		skill_cds[i]["icon"] = icon
		skill_cds[i]["overlay"] = cd_parts["overlay"]
		skill_cds[i]["cd_label"] = cd_parts["cd"]
	# 右上功能钮：圆形小图标钮（生态/图鉴/商店），暂停保留 ‖ 字形
	for pair: Array in [[%BtnEco, ICON_ECO], [%BtnCodex, ICON_CODEX], [%BtnShop, ICON_SHOP]]:
		var btn: Button = pair[0]
		HotwTheme.style_circle_button(btn)
		btn.text = ""
		HotwTheme.add_icon(btn, pair[1], 9.0)
	HotwTheme.style_circle_button(%PauseBtn)
	# 暂停面板/商店/三选一的图标走 Button.icon（文字说明保留，图标辅助扫读）
	%ResumeBtn.icon = preload("res://assets/icons_cartoon/arrow.png")
	%SaveBtn.icon = preload("res://assets/icons_cartoon/little-treasure-chest.png")
	%PauseSettingsBtn.icon = preload("res://assets/icons_cartoon/scroll-empty.png")
	%MenuBtn.icon = preload("res://assets/icons_cartoon/dialogue-bubble.png")
	%ResumeBtn.expand_icon = true
	%SaveBtn.expand_icon = true
	%PauseSettingsBtn.expand_icon = true
	%MenuBtn.expand_icon = true


## 顶部资源行图形化：金币行加金币图标（等级/区域文字保留），血条左侧挂心形。
func _setup_stats_row() -> void:
	# 金币行：StatsLabel 移入 HBox，前置金币图标（reparent 不改 owner，%引用不受影响）
	var row := HBoxContainer.new()
	row.name = "StatsRow"
	row.add_theme_constant_override("separation", 6)
	var coin := TextureRect.new()
	coin.texture = ICON_COIN
	coin.custom_minimum_size = Vector2(16, 16)
	coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(coin)
	var parent: Control = stats_label.get_parent()
	parent.add_child(row)
	parent.move_child(row, stats_label.get_index())
	stats_label.reparent(row)
	# 血条前的心形：TopLeft 左移让位，图标绝对定位贴条头
	parent.offset_left += 24.0
	var heart := TextureRect.new()
	heart.texture = ICON_HEART
	heart.position = Vector2(10, 13)
	heart.custom_minimum_size = Vector2(22, 22)
	heart.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	heart.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	heart.size = Vector2(22, 22)
	heart.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.get_parent().add_child(heart)
	_place_below_modal_layers(heart)


## 全屏暗角：程序生成径向渐变纹理，弱化边缘聚焦画面中心。
## 128² 生成后拉伸铺屏——暗角本就是模糊渐变，低分辨率无可感差异，
## 避免 512² 双重循环 26 万次 set_pixel 的移动端启动卡顿
func _apply_vignette() -> void:
	var size := 128
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size, size) / 2.0
	for y in size:
		for x in size:
			var d: float = Vector2(x, y).distance_to(center) / (size * 0.72)
			var a: float = clampf((d - 0.55) / 0.45, 0.0, 1.0) * 0.38
			img.set_pixel(x, y, Color(0, 0, 0, a))
	var tex := ImageTexture.create_from_image(img)
	var sprite := TextureRect.new()
	sprite.texture = tex
	sprite.stretch_mode = TextureRect.STRETCH_SCALE
	sprite.anchor_right = 1.0
	sprite.anchor_bottom = 1.0
	sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sprite)
	move_child(sprite, 0)


func _process(delta: float) -> void:
	# 暂停/选卡期间 toast 计时同步冻结（HUD 是 ALWAYS，_process 仍在走）——
	# 否则暂停前 1 秒出现的引导词/生态播报会在菜单背后悄悄淡没，恢复后已读不到
	if not get_tree().paused:
		if _toast_timer > 0.0:
			_toast_timer -= delta
			toast_label.modulate.a = clampf(_toast_timer / TOAST_FADE, 0.0, 1.0)
		if _combat_toast_timer > 0.0:
			_combat_toast_timer -= delta
			_combat_toast.modulate.a = clampf(_combat_toast_timer / COMBAT_TOAST_FADE, 0.0, 1.0)
		# 暂停/选卡期间真实冷却随玩家节点冻结（PAUSABLE），显示侧同步冻结——
		# 否则暂停数秒后技能槽显示"就绪"而实际 CD 未到，恢复后手感错乱
		_cd_elapsed += delta
		_refresh_skill_bar()
	_update_smooth_bars(delta)


## 三条平滑逼近 + 血条白色残影的慢速追随
func _update_smooth_bars(delta: float) -> void:
	var t := 1.0 - exp(-BAR_SMOOTH * delta)
	hp_bar.value = lerpf(hp_bar.value, _hp_target, t)
	mp_bar.value = lerpf(mp_bar.value, _mp_target, t)
	xp_bar.value = lerpf(xp_bar.value, _xp_target, t)
	if _hp_ghost > _hp_target:
		_hp_ghost_hold = maxf(0.0, _hp_ghost_hold - delta)
		if _hp_ghost_hold <= 0.0:
			_hp_ghost = maxf(_hp_target, _hp_ghost - _hp_max_cache * GHOST_DRAIN_FRAC * delta)
	if _hp_ghost_bar != null:
		_hp_ghost_bar.max_value = _hp_max_cache
		_hp_ghost_bar.value = _hp_ghost


## 键盘开关生态面板（Tab）/ 图鉴（C）/ 商店（B）/ 暂停（ESC）；触屏走按钮
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_ecology"):
		ecology_panel.visible = not ecology_panel.visible
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_codex"):
		_toggle_codex()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_shop"):
		_toggle_shop()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause"):
		_close_top_layer_or_toggle_pause()
		get_viewport().set_input_as_handled()


## ESC 先关最上层弹层（设置→图鉴→商店），全关后才切暂停——
## 否则世界解除暂停恢复战斗，设置层却还悬浮在画面上挡操作
func _close_top_layer_or_toggle_pause() -> void:
	if pause_settings_layer.visible:
		pause_settings_layer.visible = false
	elif codex_layer.visible:
		codex_layer.visible = false
		# 图鉴打开期间世界是暂停的（_toggle_codex），关闭即恢复
		get_tree().paused = false
	elif shop_panel.visible:
		shop_panel.visible = false
	else:
		_toggle_pause()


# --- 技能冷却条 ---

func _on_skills_changed(dash_cd: float, heavy_cd: float, bolt_cd: float, heal_cd: float,
		empower_cd: float, mp: float, _max_mp: float) -> void:
	_cd_values = [dash_cd, heavy_cd, bolt_cd, heal_cd, empower_cd]
	_cd_elapsed = 0.0
	_mp_now = mp
	_refresh_skill_bar()


func _refresh_skill_bar() -> void:
	for i in skill_cds.size():
		var slot: Dictionary = skill_cds[i]
		var left: float = maxf(0.0, _cd_values[i] - _cd_elapsed)
		var label: Label = slot["label"]
		# quit/换场景的销毁中途子节点可能已释放
		if label == null or not is_instance_valid(label):
			continue
		if left > 0.05:
			# 文本差分：%.1f 粒度下约 0.1s 才变一次，避免每帧字符串格式化；
			# modulate 同理脏检查——无条件赋值会让 10 个 UI 控件每帧强制重绘
			var text := "%.1f" % left
			if label.text != text:
				label.text = text
			if not slot.get("cd_on", false):
				slot["cd_on"] = true
				label.modulate = Color(1, 0.6, 0.5)
		else:
			if label.text != "就绪":
				label.text = "就绪"
			if slot.get("cd_on", true):
				slot["cd_on"] = false
				label.modulate = Color(0.7, 0.95, 0.7)
		# 蓝不足/满血治疗置灰整格：技能按了没反应时玩家需要知道原因
		var blocked := _mp_now < float(slot["mp"])
		if not blocked and slot.get("needs_hp", false) and _hp_full:
			blocked = true
		# 触控按钮已图形化：冷却 = 半透明遮罩 + 中央秒数；受阻 = 图标置灰 +
		# 遮罩位显示原因（"蓝不足"/"生命满"）。文字脏检查沿用（避免每帧重绘）
		var button: Button = slot["button"]
		if button != null and is_instance_valid(button):
			var overlay: ColorRect = slot.get("overlay")
			var cd_label: Label = slot.get("cd_label")
			var icon: TextureRect = slot.get("icon")
			var hint := ""
			var text := ""
			if left > 0.05:
				text = "%.1f" % left
			elif blocked:
				hint = "生命已满" if slot.get("needs_hp", false) else "蓝不足"
			if cd_label != null:
				var want_text: String = text if left > 0.05 else hint
				if cd_label.text != want_text:
					cd_label.text = want_text
				cd_label.add_theme_font_size_override("font_size",
						22 if left > 0.05 else 14)
				cd_label.visible = want_text != ""
			if overlay != null:
				overlay.visible = left > 0.05 or hint != ""
			if icon != null and blocked != slot.get("blocked", false):
				icon.modulate = Color(0.45, 0.45, 0.5) if blocked else Color.WHITE
			button.disabled = left > 0.05 or blocked
		if blocked != slot.get("blocked", false):
			slot["blocked"] = blocked
			var panel: Control = slot["panel"]
			if panel != null and is_instance_valid(panel):
				panel.modulate = Color(0.5, 0.5, 0.55) if blocked else Color.WHITE


# --- 暂停 / 主菜单 ---

func _toggle_pause() -> void:
	var world := get_tree().current_scene
	if world == null or not world is Node2D:
		return
	if passive_layer.visible:
		return  # 三选一未选时不允许暂停卡死流程
	if codex_layer.visible:
		# 图鉴打开期间世界已暂停：任何暂停入口（按钮/ESC）先收起图鉴，
		# 直接翻转 paused 会造成"世界恢复运行而图鉴还开着"的坏状态
		_toggle_codex()
		return
	var paused := not get_tree().paused
	get_tree().paused = paused
	if paused:
		# 暂停期间触屏按钮的排队不应在恢复后一次性兑现
		TouchInput.clear_queues()
	pause_layer.visible = paused
	pause_settings_layer.visible = false


## 手动保存（暂停菜单"保存进度"）：自动存档本已覆盖，按钮的价值是
## 给玩家确定感；toast 计时在暂停态冻结，"已保存"会停留到恢复游戏后淡出
func _save_progress() -> void:
	GameState.save_now()
	_toast("已保存")


func _back_to_menu() -> void:
	get_tree().paused = false
	GameState.save_now()
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


# --- 死亡信息 ---

func _on_player_died() -> void:
	var player := get_tree().get_first_node_in_group("player") as Player
	var killer: String = player.last_killed_by if player != null and player.last_killed_by != "" else "荒野"
	# 掉金详情由玩家侧 toast 单独播报（0 金时不误导），这里只报死因与战绩
	death_label.text = "被 %s 终结\n本局击杀 %d\n正在重生…" % [killer, GameState.session_kills]
	death_label.modulate.a = 1.0
	# 快速二次死亡时旧 tween（总时长 2.7s）可能仍在跑，先杀避免淡入淡出互抢 alpha
	if _death_tween != null and _death_tween.is_valid():
		_death_tween.kill()
	_death_tween = death_label.create_tween()
	_death_tween.tween_interval(2.2)
	_death_tween.tween_property(death_label, "modulate:a", 0.0, 0.5)


# --- 图鉴与成就 ---

func _toggle_codex() -> void:
	# 暂停菜单/三选一已占住屏幕时不响应（键 C 穿透暂停层打开图鉴会造成
	# 双弹层叠加 + 暂停态翻转错乱）
	if not codex_layer.visible and (pause_layer.visible or pause_settings_layer.visible \
			or passive_layer.visible):
		return
	codex_layer.visible = not codex_layer.visible
	if codex_layer.visible:
		# 图鉴是 22 物种 + 成就的长列表阅读界面：读条时被围殴不是乐趣是干扰，
		# 与升级三选一同口径（暂停 + 清触屏队列）；商店维持打开不暂停（已拍板）
		get_tree().paused = true
		TouchInput.clear_queues()
		_refresh_codex()
	else:
		get_tree().paused = false


func _refresh_codex() -> void:
	var lines: Array[String] = []
	# 物种清单取自运行中的模拟（= data/species/*.tres 真源）：
	# 新增种族后图鉴自动收录，与成就判定同口径，不再手抄清单漂移
	var species_names: Array = []
	if WorldSim.sim != null:
		for species: SpeciesData in WorldSim.sim.species_list:
			species_names.append(species.species_name)
	for species_name in species_names:
		var kills: int = int(GameState.codex.get(species_name, 0))
		if kills > 0:
			lines.append("✓ %s  累计猎杀 %d" % [species_name, kills])
		else:
			lines.append("？ 未曾猎杀")
	if GameState.stats.equips.is_empty():
		lines.append("— 未装备（猎杀精英/Boss 有几率掉落）")
	else:
		for slot in GameState.EQUIP_SLOTS:
			var item: Dictionary = GameState.stats.equips.get(slot, {})
			if item.is_empty():
				lines.append("— %s：空" % GameState.SLOT_NAMES[slot])
			else:
				lines.append("— %s：%s" % [GameState.SLOT_NAMES[slot], GameState.equip_description(item)])
	# 寿命：剩余不多时给出衰老警示（升级延长/倒下缩短）
	var left_days: float = GameState.stats.lifespan_remaining()
	var life_line := "— 寿命：剩 %d / %d 天" % [int(ceil(maxf(left_days, 0.0))), int(GameState.stats.lifespan_days)]
	if GameState.stats.aging_decay() < 1.0:
		life_line += "（风烛残年：上限 ×%.0f%%）" % (GameState.stats.aging_decay() * 100.0)
	lines.append(life_line)
	codex_content.text = "\n".join(lines)
	var ach_lines: Array[String] = []
	for id in AchievementManager.ACHIEVEMENTS:
		var info: Dictionary = AchievementManager.ACHIEVEMENTS[id]
		var mark := "★" if GameState.achievements.has(id) else "☆"
		ach_lines.append("%s %s — %s" % [mark, info["title"], info["desc"]])
	ach_content.text = "\n".join(ach_lines)


# --- 三选一被动（升级赐福） ---

func _on_leveled_up(_new_level: int, levels_gained: int) -> void:
	# 按跨级数排队：单次大额经验连升 N 级 = N 次三选一（漏发无法事后补领）
	_pending_passive_picks += levels_gained
	if not passive_layer.visible:
		_open_passive_pick()


func _open_passive_pick() -> void:
	if _pending_passive_picks <= 0:
		passive_layer.visible = false
		get_tree().paused = false
		return
	var pool: Array = []
	for entry: Dictionary in CharacterStats.PASSIVE_POOL:
		pool.append(entry)
	pool.shuffle()
	var chosen: Array = pool.slice(0, mini(3, pool.size()))
	for i in 3:
		var btn: Button = passive_cards[i]
		if i < chosen.size():
			var entry: Dictionary = chosen[i]
			var lv: int = GameState.stats.passive_level(entry["id"])
			btn.icon = PASSIVE_ICONS.get(entry["id"], PASSIVE_ICON_DEFAULT)
			btn.expand_icon = true
			btn.text = "%s\n%s\n（当前 %d 级）" % [entry["name"], entry["desc"], lv]
			btn.set_meta("passive_id", entry["id"])
			btn.visible = true
		else:
			btn.visible = false
	# 读卡时暂停世界：全屏选卡层挡操作，怪物却仍在攻击——升级应是奖励不是惩罚
	passive_layer.visible = true
	get_tree().paused = true
	TouchInput.clear_queues()


func _pick_passive(index: int) -> void:
	var btn: Button = passive_cards[index]
	var id: Variant = btn.get_meta("passive_id", "")
	if id != null and str(id) != "":
		GameState.stats.add_passive(str(id))
	_pending_passive_picks -= 1
	_open_passive_pick()


# --- 氛围 ---

func _on_threat_warning(_threat: float) -> void:
	_toast("⚠ 高危区域：怪物更强，奖励也更丰厚")
	threat_rect.color.a = 0.0
	var tween := threat_rect.create_tween()
	tween.tween_property(threat_rect, "color:a", 0.18, 0.25)
	tween.tween_property(threat_rect, "color:a", 0.0, 0.5)


func _on_quest_updated(text: String) -> void:
	quest_label.text = text
	quest_label.visible = text != ""


func _on_day_phase(night: bool) -> void:
	# 昼夜视觉（压暗/提灯）由 VisionLighting 按连续曲线驱动，这里只做播报
	# （限前 2 个游戏日，见 DAY_TOAST_MAX 注释）
	if _day_toast_count < DAY_TOAST_MAX:
		_day_toast_count += 1
		if night:
			_toast("夜幕降临——怪物的感官变得敏锐…")
		else:
			_toast("黎明到来")


# --- 游商营地 ---

func _toggle_shop() -> void:
	shop_panel.visible = not shop_panel.visible
	if shop_panel.visible:
		_refresh_shop()


func _refresh_shop() -> void:
	shop_gold_label.text = "金币 %d" % GameState.gold
	_refresh_shop_btn(%BtnWeapon, "weapon", "武器磨刀", "物理攻击", ICON_HEAVY)
	_refresh_shop_btn(%BtnStaff, "staff", "法杖赋能", "魔法攻击", ICON_BOLT)
	_refresh_shop_btn(%BtnVigor, "vigor", "体质淬炼", "生命上限", ICON_HEART)


func _refresh_shop_btn(btn: Button, kind: String, display: String, effect: String,
		icon: Texture2D) -> void:
	if btn.icon != icon:
		btn.icon = icon
		btn.expand_icon = true
	var level: int = GameState.upgrade_level(kind)
	# 每级幅度读 CharacterStats 真源（UPGRADE_BONUS=0.15），不再手抄 15 魔法数
	var pct := CharacterStats.UPGRADE_BONUS * 100.0
	if level >= GameState.UPGRADE_MAX_LEVEL:
		btn.text = "%s 已满级（%s +%.0f%%）" % [display, effect, level * pct]
		btn.disabled = true
		return
	btn.disabled = GameState.gold < GameState.upgrade_cost(kind)
	btn.text = "%s Lv.%d → +%.0f%% ｜ %d 金币" % [display, level, (level + 1) * pct, GameState.upgrade_cost(kind)]


func _try_buy(kind: String) -> void:
	if GameState.buy_upgrade(kind):
		SfxManager.play("levelup")
		_toast_combat("%s 强化成功！" % GameState.UPGRADE_NAMES[kind])
	elif GameState.upgrade_level(kind) >= GameState.UPGRADE_MAX_LEVEL:
		_toast_combat("%s 已满级" % GameState.UPGRADE_NAMES[kind])
	else:
		_toast_combat("金币不足（需要 %d）" % GameState.upgrade_cost(kind))
	_refresh_shop()


func _on_hp_changed(current: float, maximum: float) -> void:
	hp_bar.max_value = maximum
	_hp_max_cache = maximum
	_hp_full = current >= maximum - 0.5
	# 平滑条：事件只写目标，_process 逼近；掉血时白色残影先按住片刻
	if current < _hp_target:
		_hp_ghost_hold = GHOST_HOLD
	if current > _hp_ghost:
		_hp_ghost = current  # 回血：残影立即抬升
	_hp_target = current


func _on_mp_changed(current: float, maximum: float) -> void:
	_mp_now = current
	mp_bar.max_value = maximum
	_mp_target = current


func _on_progress_changed(level: int, xp: int, xp_needed: int, pending_points: int) -> void:
	xp_bar.max_value = xp_needed
	_xp_target = xp
	_refresh_stats_label(level, pending_points)


func _on_gold_changed(_amount: int) -> void:
	_refresh_stats_label(GameState.stats.level, GameState.stats.pending_points)
	if shop_panel.visible:
		_refresh_shop()


func _refresh_stats_label(level: int, pending_points: int) -> void:
	# 有待分配属性点时亮出分配按钮，分完收起
	stat_buttons.visible = pending_points > 0
	stats_label.text = "Lv.%d  金币 %d" % [level, GameState.gold]
	if _region_name != "":
		stats_label.text += "  |  %s" % _region_name
	if pending_points > 0:
		stats_label.text += "  可分配 %d" % pending_points


func _on_region_entered(_region_id: String, display_name: String) -> void:
	_region_name = display_name
	_refresh_stats_label(GameState.stats.level, GameState.stats.pending_points)
	_toast("进入 %s" % display_name)


## 生态监测面板：每秒刷新种群构成，并对比上一 tick 标注趋势——
## ↑/↓ 总数涨跌，＋ 该地形新出现的物种（扩张/迁入），✕ 上次有而这次没了（灭绝/迁出）。
## v4 大世界按地形聚合展示（100 个斑块逐行不可读；同地形共享承载与手感带，
## "地形"才是玩家认知的生态单元），行序 = 威胁梯度（平原→熔岩）
func _on_sim_tick(summary: Dictionary) -> void:
	if not ecology_panel.visible:
		# 面板关闭时跳过整段字符串拼接；趋势基线保持在上次可见的时刻，
		# 重新打开后显示的恰是"这段时间里发生的变化"
		return
	var terrain_order: Array[String] = ["plains", "forest", "swamp", "snow", "hill", "lava"]
	var terrain_names := {
		"plains": "平原", "forest": "林地", "swamp": "沼泽",
		"snow": "雪原", "hill": "丘陵", "lava": "熔岩",
	}
	var agg := {}
	for region: Dictionary in summary["regions"]:
		var terrain: String = region["terrain"]
		var bucket: Dictionary = agg.get(terrain, {})
		if bucket.is_empty():
			bucket = {"name": region["name"], "alive": 0, "capacity": 0, "species": {}}
			agg[terrain] = bucket
		bucket["alive"] += region["alive"]
		bucket["capacity"] += region["capacity"]
		var species_counts: Dictionary = region["species"]
		for species_name: String in species_counts:
			bucket["species"][species_name] = int(bucket["species"].get(species_name, 0)) \
					+ int(species_counts[species_name])
	var lines: Array[String] = []
	for terrain: String in terrain_order:
		var bucket: Dictionary = agg.get(terrain, {})
		if bucket.is_empty():
			continue
		var alive: int = bucket["alive"]
		var last_total: int = _last_totals.get(terrain, alive)
		var trend := "—"
		if alive > last_total:
			trend = "↑"
		elif alive < last_total:
			trend = "↓"
		_last_totals[terrain] = alive
		var species_counts: Dictionary = bucket["species"]
		var last_set: Dictionary = _last_species.get(terrain, {})
		var parts: Array[String] = []
		for species_name: String in species_counts:
			var mark := "＋" if not last_set.has(species_name) else ""
			parts.append("%s%s×%d" % [mark, species_name, species_counts[species_name]])
		for species_name: String in last_set:
			if not species_counts.has(species_name):
				parts.append("✕%s" % species_name)
		_last_species[terrain] = species_counts.duplicate()
		var detail := " ".join(parts) if not parts.is_empty() else "—"
		lines.append("%s %s%d/%d  %s" % [
			terrain_names.get(terrain, bucket["name"]), trend, alive, bucket["capacity"], detail])
	ecology_label.text = "\n".join(lines)


func _on_kill(xp_reward: int, gold_reward: int, monster_name: String, _species_name: String) -> void:
	# 击杀走战斗通道：连杀高频滚动时不再挤掉生态事件/引导词
	_toast_combat("击杀 %s   +%d 经验  +%d 金币" % [monster_name, xp_reward, gold_reward])


func _toast(message: String) -> void:
	# 短窗合并：上一条刚显示不到 0.4s 时拼行，否则整条替换——
	# 保证同帧连发的多条播报（进区提示+引导+警告）都看得见；
	# 拼行封顶 TOAST_MAX_LINES，持续事件流不再无限增高
	if _toast_timer > TOAST_DURATION - TOAST_MERGE_WINDOW:
		toast_label.text += "\n" + message
		var lines := toast_label.text.split("\n")
		if lines.size() > TOAST_MAX_LINES:
			toast_label.text = "\n".join(lines.slice(lines.size() - TOAST_MAX_LINES))
	else:
		toast_label.text = message
	toast_label.modulate.a = 1.0
	_toast_timer = TOAST_DURATION
