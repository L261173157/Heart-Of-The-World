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
## 强化三按钮引用在 reparent 进页签前缓存：% 唯一名查找在 reparent 到
## 代码构建容器后不可靠（金币行能刷新而按钮行静默失败的根因）
@onready var shop_upgrade_btns: Array = [%BtnWeapon, %BtnStaff, %BtnVigor]
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
## 记录每次施放的实际冷却总长，包含被动/装备减冷却；圆环不能拿裸常量做分母。
var _cd_durations := [0.0, 0.0, 0.0, 0.0, 0.0]
## 最近已知蓝量（技能槽"蓝不足"置灰用）
var _mp_now := 0.0
var _mp_max_cache := 1.0
var _hp_known := false
var _mp_known := false
## 是否满血（治疗槽"满血无效"置灰用）
var _hp_full := false
## 三选一点击去重：下一帧才接受下一张，避免同帧重复按钮事件连领。
var _passive_pick_locked := false
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
# --- 物品系统（玩法 v7 P0） ---
## 商店页签容器（强化/补给/收购）与两页数据驱动按钮
var _supply_btns: Dictionary = {}
var _sell_btns: Dictionary = {}
## 物品栏弹层（阅读型：打开暂停世界，照图鉴口径）
var _inv_layer: Control
var _inv_grid: GridContainer
var _inv_hint: Label
var _equipment_labels: Dictionary = {}
var _equipment_lock_buttons: Dictionary = {}
## 单件候选只在背包比较，不在战斗中弹层；按钮绑定本次 offer，旧回调不能处理新件。
var _equipment_offer: VBoxContainer
var _equipment_badge: Label
var _equipment_pick_locked := false
var _task_layer: Control
var _task_rows: VBoxContainer
var _task_snapshot: Array = []
var _tracked_quest_id := ""
var _stat_layer: Control
var _stat_preview: Label
var _stat_owned: Label
var _stat_confirm: Button
var _stat_attribute := ""
var _passive_owned: Label
## 同类优先使用高恢复品；满生命时跳过食物改用缺少的精力补给。
const QUICK_PRIORITY := ["life-pot", "medipack", "sushi", "onigiri", "water-pot"]
var _quick_btn: Button
var _quick_icon: TextureRect
var _quick_badge: Label
var _quick_id := ""
## 帧率显示（真机性能优化 2026-09-19 附赠）：settings.show_fps 控制，
## 4Hz 刷新（Engine.get_frames_per_second 本身是均值，快刷无意义）
var _fps_label: Label
var _fps_accum := 0.0
var _hud_plate: Panel
var _hp_value: Label
var _mp_value: Label

# --- 触控按钮图标（美术 v6 · TS 烘焙/合成图标，bake_structures 产线） ---
const ICON_ATTACK := preload("res://assets/ts/icons/attack.png")
const ICON_DASH := preload("res://assets/ts/icons/dash.png")
const ICON_HEAVY := preload("res://assets/ts/icons/heavy.png")
const ICON_BOLT := preload("res://assets/ts/icons/bolt.png")
const ICON_HEAL := preload("res://assets/ts/icons/heal_pot_red.png")
const ICON_EMPOWER := preload("res://assets/ts/icons/empower.png")
const ICON_ECO := preload("res://assets/ts/icons/eco.png")
const ICON_SHOP := preload("res://assets/ts/icons/shop.png")
const ICON_CODEX := preload("res://assets/ts/icons/cdr.png")
const ICON_COIN := preload("res://assets/ts/icons/coin.png")
const ICON_HEART := preload("res://assets/ts/icons/heart.png")
## 武器图标对位（TS Tools 件）：katana=武器磨刀（刀）、fork=法杖赋能
## （三叉法器）、sai=蛮力被动（叉手）
const ICON_KATANA := preload("res://assets/ts/icons/katana.png")
const ICON_FORK := preload("res://assets/ts/icons/fork.png")
const ICON_SAI := preload("res://assets/ts/icons/sai.png")
## 物品栏按钮（v7）：TS 皮袋 = 收纳意象
const ICON_BAG := preload("res://assets/ts/icons/bag.png")
## 升级三选一：被动 id → 图标（缺省用空卷轴）
const PASSIVE_ICONS := {
	"lifesteal": ICON_HEART, "atk_speed": ICON_DASH, "move": ICON_BOLT,
	"cdr": preload("res://assets/ts/icons/cdr.png"),
	"hp": preload("res://assets/ts/icons/hp_pot_blue.png"),
	"mp_regen": preload("res://assets/ts/icons/mp_pot_green.png"),
		"phys": ICON_SAI, "magic": ICON_BOLT, "gold": ICON_COIN,
	"xp": preload("res://assets/ts/icons/star_gold.png"),
	"heal_power": ICON_HEAL,
	"knock": preload("res://assets/ts/icons/knock_axe.png"),
}
const PASSIVE_ICON_DEFAULT := preload("res://assets/ts/icons/cdr.png")


func _ready() -> void:
	EventBus.player_hp_changed.connect(_on_hp_changed)
	EventBus.player_mp_changed.connect(_on_mp_changed)
	EventBus.player_progress_changed.connect(_on_progress_changed)
	EventBus.gold_changed.connect(_on_gold_changed)
	EventBus.monster_killed_by_player.connect(_on_kill)
	EventBus.player_entered_region.connect(_on_region_entered)
	EventBus.sim_tick_completed.connect(_on_sim_tick)
	EventBus.hint_requested.connect(func(text: String) -> void: _toast(text))
	_setup_fps_label()

	%BtnStrength.pressed.connect(_open_stat_preview.bind("strength"))
	%BtnAgility.pressed.connect(_open_stat_preview.bind("agility"))
	%BtnIntellect.pressed.connect(_open_stat_preview.bind("intellect"))

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
	%BtnBag.pressed.connect(_toggle_inventory)
	# v7 物品：拾取播报 + 背包变化刷新快捷槽/物品栏（lambda 无捕获，安全）
	EventBus.item_gained.connect(_on_item_gained)
	EventBus.equipment_offer_changed.connect(_on_equipment_offer_changed)
	EventBus.inventory_changed.connect(func() -> void:
		_refresh_quick_slot()
		if _inv_layer != null and _inv_layer.visible:
			_refresh_inventory())
	EventBus.world_event.connect(func(text: String) -> void: _toast(text))
	EventBus.bounty_updated.connect(func(text: String) -> void: bounty_label.text = text)
	# 任务行（世界 v5 地标 NPC 委托）：空串隐藏（无任务时不占行高）
	EventBus.quest_updated.connect(_on_quest_updated)
	# 任务行只打开小列表，跟踪与放弃为两个明确动作。
	EventBus.quest_list_changed.connect(_on_quest_list_changed)
	quest_label.mouse_filter = Control.MOUSE_FILTER_STOP
	quest_label.gui_input.connect(_on_quest_label_input)
	EventBus.bounty_completed.connect(func(text: String) -> void: _toast(text))
	EventBus.player_skills_changed.connect(_on_skills_changed)
	EventBus.achievement_unlocked.connect(func(title: String) -> void: _toast("🏆 成就解锁：%s" % title))
	EventBus.region_threat_warning.connect(_on_threat_warning)
	EventBus.day_phase_changed.connect(_on_day_phase)
	EventBus.player_died.connect(_on_player_died)
	GameState.stats.leveled_up.connect(_on_leveled_up)

	%PauseBtn.pressed.connect(func() -> void:
		SfxManager.play("menu")
		_toggle_pause())
	%ResumeBtn.pressed.connect(_resume_game)
	%SaveBtn.pressed.connect(_save_progress)
	%PauseSettingsBtn.pressed.connect(_open_pause_settings)
	%PauseSettingsClose.pressed.connect(_close_pause_settings)
	%MenuBtn.pressed.connect(_back_to_menu)
	%BtnCodex.pressed.connect(_toggle_codex)
	# 关闭按钮必须与 C/ESC 走同一路径：图鉴打开时世界处于暂停态，
	# 只隐藏弹层会留下“画面恢复但整个世界永久停住”的触屏死锁。
	%CodexClose.pressed.connect(_close_codex)
	for i in 3:
		passive_cards[i].pressed.connect(_pick_passive.bind(i))
	GameState.stats.leveled_up.connect(func(new_level: int, _levels: int) -> void:
		_toast("升级！Lv.%d   属性点 +1" % new_level)
	)

	# 面板底 TS 化（美术 v6 §8 收口）：木桌=交易/收纳（游商/物品栏），
	# SpecialPaper=阅读/系统（暂停/图鉴/生态）——阅读类浅字在深纸上保对比
	HotwTheme.paper_panel(get_node("Root/PauseLayer/PausePanel"), HotwTheme.PAPER_SPECIAL)
	HotwTheme.paper_panel(shop_panel, HotwTheme.WOOD_TILE, 40)
	HotwTheme.paper_panel(get_node("Root/CodexLayer/CodexPanel"), HotwTheme.PAPER_SPECIAL)
	HotwTheme.paper_panel(ecology_panel, HotwTheme.PAPER_SPECIAL)
	# 升级三选一赐福卡：WoodTable_Slots 木瓦底
	for card: Button in passive_cards:
		HotwTheme.style_wood_card(card)
	# 面板标题换 TS 丝带签（原 Label 隐藏保留，场景结构/路径引用不动）
	_swap_title_ribbon("Root/PauseLayer/PausePanel/Margin/VB/Title", 4)
	_swap_title_ribbon("Root/ShopPanel/Margin/VB/Title", 2)
	_swap_title_ribbon("Root/CodexLayer/CodexPanel/Margin/VB/Title", 0)
	_swap_title_ribbon("Root/PassiveLayer/PassiveVB/PassiveTitle", 3, 360.0)

	toast_label.modulate.a = 0.0
	_setup_combat_toast()
	_setup_hp_ghost_bar()
	_setup_boss_bar()
	_setup_dialogue_bubble()
	_setup_shop_tabs()
	_setup_inventory_layer()
	_setup_choice_layers()
	_setup_quick_slot()
	_apply_theme()
	_setup_icon_buttons()
	_setup_stats_row()
	_setup_hud_hierarchy()
	_equipment_badge = HotwTheme.add_badge(%BtnBag, "")
	_on_equipment_offer_changed()
	_apply_vignette()
	# 初值用真源实值：读档进世界（如 Lv.7 带 3 待分配点）时 HUD 不再闪显 Lv.1 空经验条
	_on_progress_changed(GameState.stats.level, GameState.stats.xp,
			GameState.stats.xp_to_next(), GameState.stats.pending_points)
	_on_gold_changed(GameState.gold)
	# 读档/菜单往返不再等待下一次升级信号；立即续接角色尚未领取的赐福。
	if GameState.stats.pending_passive_picks > 0:
		_open_passive_pick()


## 战斗播报位：与顶部世界事件/引导提示分离的第二条 toast 通道。
## 击杀与商店反馈高频而轻量（密集战斗时每秒数条），原单通道会被它们
## 反复覆盖，生态事件/引导词一闪即逝——拆开后各走各位互不打架。
func _setup_combat_toast() -> void:
	_combat_toast.anchor_left = toast_label.anchor_left
	_combat_toast.anchor_right = toast_label.anchor_right
	_combat_toast.offset_left = toast_label.offset_left
	_combat_toast.offset_right = toast_label.offset_right
	_combat_toast.offset_top = toast_label.offset_top + 52.0
	_combat_toast.offset_bottom = toast_label.offset_bottom + 52.0
	_combat_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_combat_toast.add_theme_font_size_override("font_size", 20)
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


## 标题 Label 换 TS 丝带签：同容器同位插入、横向收缩居中（全屏面板不拉通整幅）；
## 原 Label 仅隐藏不删——场景树结构与其余代码的路径引用全部保持
func _swap_title_ribbon(node_path: String, color_idx: int, min_width := 240.0) -> void:
	var title := get_node_or_null(node_path) as Label
	if title == null:
		return
	var tag := HotwTheme.ribbon_tag(title.text, color_idx, min_width)
	tag.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var parent: Control = title.get_parent()
	parent.add_child(tag)
	parent.move_child(tag, title.get_index())
	title.visible = false


# ==================== NPC 对话气泡（美术 v6，TS RegularPaper 纸面） ====================
## RegularPaper 九宫格底 + 合成金边头像框 + TS 方钮 yes/no + 丝带名牌。
## 攻击键=确认 / 冲刺键=关闭（player 侧经 dialogue_action 路由，触屏同通道）；
## 确认接单经 dialogue_confirmed 信号回到 QuestManager 结算
var _dialogue_panel: Control
var _dialogue_tag: Control
var _dialogue_text: Label
var _dialogue_name: Label
var _dialogue_faceset: TextureRect
var _dialogue_yes: TextureButton
var _dialogue_no: TextureButton
var _dialogue_quest: Dictionary = {}
var _dialogue_kind := ""
var _dialogue_timer := 0.0
## 对话发起 NPC 的世界位置（走开自动关气泡用；INF = 载荷未带位置不判距）
var _dialogue_origin := Vector2.INF
## 心形五帧条带（TS 色板合成件 heart_strip）：条带 80×16，帧 0-4 = 空→满
const HEART_STRIP := preload("res://assets/ts/icons/heart_strip.png")
var _heart_icon: TextureRect
var _heart_cache: Array[AtlasTexture] = []


func _heart_frame(idx: int) -> AtlasTexture:
	if _heart_cache.is_empty():
		for i in 5:
			var at := AtlasTexture.new()
			at.atlas = HEART_STRIP
			at.region = Rect2(i * 16.0, 0.0, 16.0, 16.0)
			_heart_cache.append(at)
	return _heart_cache[clampi(idx, 0, 4)]
const DIALOGUE_INFO_SECONDS := 3.5
const DIALOGUE_OFFER_SECONDS := 12.0
## 离开发起 NPC 超过此距离自动收气泡：对话期间攻击键=确认/冲刺=关闭，
## 玩家已走远时旧委托还挂屏会误接单（NPC 交互半径 96px，180px 留走位余量）
const DIALOGUE_WALKAWAY_RADIUS := 180.0


func _setup_dialogue_bubble() -> void:
	EventBus.npc_dialogue.connect(_open_dialogue)
	EventBus.dialogue_action.connect(_on_dialogue_action)
	var root := get_node("Root") as Control
	_dialogue_panel = Control.new()
	_dialogue_panel.name = "DialogueBubble"
	_dialogue_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_dialogue_panel.position = Vector2(-330, -216)
	_dialogue_panel.size = Vector2(660, 176)
	_dialogue_panel.visible = false
	_dialogue_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_dialogue_panel)
	_place_below_modal_layers(_dialogue_panel)

	var bubble := NinePatchRect.new()
	# 美术 v6：TS RegularPaper 纸面九宫（320 原生，边饰带宽约 56）
	bubble.texture = load("res://assets/ts/UI Elements/UI Elements/Papers/RegularPaper.png")
	bubble.patch_margin_left = 56
	bubble.patch_margin_top = 56
	bubble.patch_margin_right = 56
	bubble.patch_margin_bottom = 56
	bubble.set_anchors_preset(Control.PRESET_FULL_RECT)
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialogue_panel.add_child(bubble)

	var box := TextureRect.new()
	# v6：TS 无现成头像框 → 金边深底合成件（icon_frame）
	box.texture = preload("res://assets/ts/icons/icon_frame.png")
	box.position = Vector2(20, 40)
	box.size = Vector2(96, 96)
	box.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	box.stretch_mode = TextureRect.STRETCH_SCALE
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialogue_panel.add_child(box)
	_dialogue_faceset = TextureRect.new()
	_dialogue_faceset.position = Vector2(32, 52)
	_dialogue_faceset.size = Vector2(72, 72)
	_dialogue_faceset.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_dialogue_faceset.stretch_mode = TextureRect.STRETCH_SCALE
	_dialogue_faceset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialogue_panel.add_child(_dialogue_faceset)

	# 名牌（v6 TS 丝带）：蓝青签横在气泡上缘，RibbonLabel 即名牌文本位；
	# 宽度随名字长度撑开（九宫 128 边距下带宽 = 宽 - 256）
	var name_tag := HotwTheme.ribbon_tag("", 0, 340.0)
	name_tag.position = Vector2(126, 4)
	name_tag.size = Vector2(340, 44)
	_dialogue_panel.add_child(name_tag)
	_dialogue_tag = name_tag
	_dialogue_name = name_tag.get_node("RibbonLabel")
	_dialogue_name.add_theme_font_size_override("font_size", 19)

	_dialogue_text = Label.new()
	_dialogue_text.position = Vector2(130, 52)
	_dialogue_text.size = Vector2(396, 84)
	_dialogue_text.add_theme_font_size_override("font_size", 18)
	_dialogue_text.add_theme_color_override("font_color", Color(0.16, 0.11, 0.06))
	# 浅羊皮纸面上深墨字（v6 收口：白字对比不足改墨色，禁改回浅色）
	_dialogue_text.add_theme_color_override("font_outline_color", Color(1.0, 0.97, 0.9, 0.35))
	_dialogue_text.add_theme_constant_override("outline_size", 3)
	_dialogue_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dialogue_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_dialogue_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialogue_panel.add_child(_dialogue_text)

	_dialogue_yes = TextureButton.new()
	# v6：TS 方钮两态（蓝=确认；128px 源 ×0.55 ≈ 70px 命中区，满足 ≥44pt 触控）
	_dialogue_yes.texture_normal = preload("res://assets/ts/UI Elements/UI Elements/Buttons/SmallBlueSquareButton_Regular.png")
	_dialogue_yes.texture_pressed = preload("res://assets/ts/UI Elements/UI Elements/Buttons/SmallBlueSquareButton_Pressed.png")
	_dialogue_yes.scale = Vector2(0.55, 0.55)
	_dialogue_yes.position = Vector2(452, 104)
	_dialogue_yes.pressed.connect(_on_dialogue_action.bind("confirm"))
	_dialogue_panel.add_child(_dialogue_yes)
	_dialogue_no = TextureButton.new()
	_dialogue_no.texture_normal = preload("res://assets/ts/UI Elements/UI Elements/Buttons/SmallRedSquareButton_Regular.png")
	_dialogue_no.texture_pressed = preload("res://assets/ts/UI Elements/UI Elements/Buttons/SmallRedSquareButton_Pressed.png")
	_dialogue_no.scale = Vector2(0.55, 0.55)
	_dialogue_no.position = Vector2(542, 104)
	_dialogue_no.pressed.connect(_on_dialogue_action.bind("decline"))
	_dialogue_panel.add_child(_dialogue_no)
	var yes_label := Label.new()
	yes_label.text = "是[攻击]"
	yes_label.position = Vector2(452, 160)
	yes_label.size = Vector2(84, 18)
	yes_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	yes_label.add_theme_font_size_override("font_size", 14)
	yes_label.add_theme_color_override("font_color", Color(0.16, 0.11, 0.06))
	yes_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialogue_panel.add_child(yes_label)
	var no_label := Label.new()
	no_label.text = "否[冲刺]"
	no_label.position = Vector2(542, 160)
	no_label.size = Vector2(84, 18)
	no_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	no_label.add_theme_font_size_override("font_size", 14)
	no_label.add_theme_color_override("font_color", Color(0.16, 0.11, 0.06))
	no_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialogue_panel.add_child(no_label)


func _open_dialogue(payload: Dictionary) -> void:
	GameState.dialogue_open = true
	# NA 语音短音（美术 v5 音频全量）：NPC 开口随机一条，说话感
	SfxManager.play("voice%d" % (1 + randi() % 4))
	_dialogue_kind = str(payload.get("kind", ""))
	var origin: Variant = payload.get("origin", Vector2.INF)
	_dialogue_origin = origin if origin is Vector2 else Vector2.INF
	_dialogue_quest = payload.get("quest", {}) if _dialogue_kind == "quest" else {}
	var giver := str(payload.get("giver", ""))
	if _dialogue_tag != null:
		_dialogue_tag.size = Vector2(maxf(340.0, 244.0 + giver.length() * 24.0), 44.0)
	_dialogue_name.text = giver
	_dialogue_text.text = str(payload.get("text", ""))
	var face_path := str(payload.get("faceset", ""))
	_dialogue_faceset.texture = load(face_path) \
			if not face_path.is_empty() and ResourceLoader.exists(face_path) else null
	var has_offer: bool = not _dialogue_quest.is_empty() or _dialogue_kind == "shop"
	_dialogue_yes.visible = has_offer
	_dialogue_no.visible = has_offer
	_dialogue_timer = DIALOGUE_OFFER_SECONDS if has_offer else DIALOGUE_INFO_SECONDS
	_dialogue_panel.visible = true


func _on_dialogue_action(action: String) -> void:
	if not _dialogue_panel.visible:
		return
	if action == "confirm":
		SfxManager.play("menu")
		if not _dialogue_quest.is_empty():
			EventBus.dialogue_confirmed.emit(_dialogue_quest)
		elif _dialogue_kind == "shop":
			shop_panel.visible = true
	_close_dialogue()


func _close_dialogue() -> void:
	_dialogue_panel.visible = false
	_dialogue_quest = {}
	_dialogue_kind = ""
	_dialogue_origin = Vector2.INF
	GameState.dialogue_open = false


func _exit_tree() -> void:
	# 回菜单/退场景兜底：对话开关残留 true 会永久吞掉攻击键路由
	GameState.dialogue_open = false


func _process_dialogue(delta: float) -> void:
	if not _dialogue_panel.visible:
		return
	# 中途走开自动关闭（距离见 DIALOGUE_WALKAWAY_RADIUS 注释）
	if _dialogue_origin != Vector2.INF:
		var player := get_tree().get_first_node_in_group("player") as Node2D
		if player == null or player.global_position.distance_to(_dialogue_origin) \
				> DIALOGUE_WALKAWAY_RADIUS:
			_close_dialogue()
			return
	_dialogue_timer -= delta
	if _dialogue_timer <= 0.0:
		_close_dialogue()


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


## Boss 顶部血条：砖红丝带名牌 + TS BigBar 宽条，顶部居中（战斗播报位下方，
## y=132 与其 90~122 错开——此前两通道几何重叠，Boss 战中击杀播报直接盖住 Boss 名字）；
## 满血也显示——遭遇即有血量锚点（通用头顶条满血不显示）
func _setup_boss_bar() -> void:
	# 名牌走丝带签：RibbonLabel 即文本位（_on_boss_tracked 只写 text 不换节点）
	var name_tag := HotwTheme.ribbon_tag("", 1, 360.0)
	_boss_name_label = name_tag.get_node("RibbonLabel")
	_boss_name_label.add_theme_font_size_override("font_size", 19)
	_boss_layer = VBoxContainer.new()
	_boss_layer.add_child(name_tag)
	_boss_bar = ProgressBar.new()
	# 高 24 + 上下边距 8：BigBar_Fill 不透明带仅占纹理中部 ~20px，上下边距
	# ×2 ≥ 条高时中心拉伸区变负、填充整条消失（隔离探针实证 m14/h22=0 红像素）
	_boss_bar.custom_minimum_size = Vector2(520, 24)
	_boss_bar.show_percentage = false
	# TS BigBar：框=BigBar_Base 九宫（端帽 48 保形），填充=BigBar_Fill 原红横向平铺
	var fill := StyleBoxTexture.new()
	fill.texture = HotwTheme.cropped_texture(HotwTheme.TS_UI + "/Bars/BigBar_Fill.png")
	fill.texture_margin_left = 14.0
	fill.texture_margin_top = 4.0
	fill.texture_margin_right = 14.0
	fill.texture_margin_bottom = 4.0
	fill.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	_boss_bar.add_theme_stylebox_override("fill", fill)
	var boss_bg := StyleBoxTexture.new()
	boss_bg.texture = HotwTheme.cropped_texture(HotwTheme.TS_UI + "/Bars/BigBar_Base.png")
	boss_bg.texture_margin_left = 16.0
	boss_bg.texture_margin_top = 4.0
	boss_bg.texture_margin_right = 16.0
	boss_bg.texture_margin_bottom = 4.0
	_boss_bar.add_theme_stylebox_override("background", boss_bg)
	_boss_layer.add_child(_boss_bar)
	_boss_layer.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_boss_layer.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_boss_layer.position = Vector2(-260, 96)
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


## iOS 刘海/Home 指示条的安全区内收已统一由 Root 上的 SafeAreaRoot
## 组件承担（hud.tscn），主菜单同一套——hud 不再自带 _apply_safe_area。


# --- 视觉主题（深色玻璃拟态 + 金色强调，代码生成免维护 .tres） ---

func _apply_theme() -> void:
	(get_node("Root") as Control).theme = HotwTheme.glass_theme()

	# 进度条三色（血/蓝/经验）：TS BigBar_Fill 烘色平铺纹理（v6）
	hp_bar.add_theme_stylebox_override("fill", _ts_bar_fill("bar_fill_red"))
	mp_bar.add_theme_stylebox_override("fill", _ts_bar_fill("bar_fill_blue"))
	xp_bar.add_theme_stylebox_override("fill", _ts_bar_fill("bar_fill_gold"))
	for bar: ProgressBar in [mp_bar, xp_bar]:
		bar.add_theme_stylebox_override("background", _ts_bar_base())
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


## TS 条填充纹理（BigBar_Fill 烘色件，横向平铺）
func _ts_bar_fill(tex_name: String) -> StyleBoxFlat:
	# 原烘色条含绿色底半帧，缩小时会混成黄白；语义色直接绘制，保留硬边像素轮廓。
	var colors := {"bar_fill_red": Color("d96a62"), "bar_fill_blue": Color("659cc9"),
		"bar_fill_gold": Color("d6b66e")}
	var sb := StyleBoxFlat.new()
	sb.bg_color = colors.get(tex_name, HotwTheme.GOLD)
	sb.border_color = sb.bg_color.lightened(0.28)
	sb.border_width_top = 2
	sb.set_corner_radius_all(2)
	return sb


## TS 条框（SmallBar_Base 九宫：端帽保留、上下窄边）
func _ts_bar_base() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("0c1721")
	sb.border_color = Color("64797e")
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	return sb


## 触控按钮图形化（MOBA 布局）：攻击大圆钮 + 五技能圆钮 + 冷却遮罩/数字/
## 蓝耗角标，右上功能钮改小圆图标钮。节点名与 button_down 触发全保留，
## 只换视觉层——图标/遮罩子节点全部鼠标穿透，不挡按钮命中。
## 底座 v6 起为 TS 圆钮两态（攻击=红、技能/功能=蓝），替代玻璃拟态圆。
func _setup_icon_buttons() -> void:
	HotwTheme.style_ts_round_button(%AttackBtn, true)
	HotwTheme.add_icon(%AttackBtn, ICON_ATTACK, 28.0)
	_add_button_caption(%AttackBtn, "攻击")
	var skill_btns: Array = [%DashBtn, %HeavyBtn, %BoltBtn, %HealBtn, %EmpowerBtn]
	var skill_icons: Array = [ICON_DASH, ICON_HEAVY, ICON_BOLT, ICON_HEAL, ICON_EMPOWER]
	for i in skill_btns.size():
		var btn: Button = skill_btns[i]
		HotwTheme.style_ts_round_button(btn)
		var icon := HotwTheme.add_icon(btn, skill_icons[i], 22.0)
		_add_button_caption(btn, str(skill_cds[i]["name"]))
		var cd_parts := HotwTheme.add_cd_overlay(btn)
		HotwTheme.add_badge(btn, str(int(skill_cds[i]["mp"])))
		skill_cds[i]["icon"] = icon
		skill_cds[i]["overlay"] = cd_parts["overlay"]
		skill_cds[i]["cd_label"] = cd_parts["cd"]
	# 右上功能钮行（小地图正下方）：圆形小图标钮（生态/图鉴/商店/物品），暂停保留 ‖ 字形
	for pair: Array in [[%BtnEco, ICON_ECO], [%BtnCodex, ICON_CODEX], [%BtnShop, ICON_SHOP],
			[%BtnBag, ICON_BAG]]:
		var btn: Button = pair[0]
		HotwTheme.style_ts_round_button(btn)
		btn.text = ""
		HotwTheme.add_icon(btn, pair[1], 18.0)
	HotwTheme.style_ts_round_button(%PauseBtn)
	# 暂停面板/商店/三选一的图标走 Button.icon（文字说明保留，图标辅助扫读）
	%ResumeBtn.icon = preload("res://assets/ts/icons/play.png")
	%SaveBtn.icon = preload("res://assets/ts/icons/save.png")
	%PauseSettingsBtn.icon = preload("res://assets/ts/icons/star_gold.png")
	%MenuBtn.icon = preload("res://assets/ts/UI Elements/UI Elements/Swords/Swords.png")
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
	# 血条前的心形：TopLeft 左移让位，图标绝对定位贴条头；
	# TS 合成心形五帧条带（80×16）按血量比例换帧（0=空心 … 4=满心）
	parent.offset_left += 30.0
	var heart := TextureRect.new()
	heart.texture = _heart_frame(4)
	heart.position = Vector2(11, 12)
	heart.custom_minimum_size = Vector2(26, 26)
	heart.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	heart.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	heart.size = Vector2(26, 26)
	heart.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.get_parent().add_child(heart)
	_place_below_modal_layers(heart)
	_heart_icon = heart
	# MP 条头标记（v6 TS 蓝药图标）：贴条左侧作蓝量标识
	var kunai := TextureRect.new()
	kunai.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	kunai.texture = preload("res://assets/ts/icons/mp_pot_green.png")
	kunai.position = Vector2(-28, -1)
	kunai.custom_minimum_size = Vector2(20, 20)
	kunai.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	kunai.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	kunai.size = Vector2(20, 20)
	kunai.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mp_bar.add_child(kunai)


## 常驻信息只占两个角：深色阅读底与细色条给角色/战场留出视觉中心。
func _setup_hud_hierarchy() -> void:
	var root := get_node("Root") as Control
	var top := get_node("Root/TopLeft") as VBoxContainer
	top.position = Vector2(52, 26)
	top.size = Vector2(286, 150)
	top.add_theme_constant_override("separation", 7)
	_hud_plate = Panel.new()
	_hud_plate.name = "StatusPlate"
	_hud_plate.position = Vector2(14, 14)
	_hud_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := HotwTheme.panel_style()
	style.bg_color = Color(0.065, 0.105, 0.14, 0.91)
	style.border_color = Color("607b80")
	_hud_plate.add_theme_stylebox_override("panel", style)
	root.add_child(_hud_plate)
	root.move_child(_hud_plate, top.get_index())
	top.resized.connect(_resize_status_plate)
	var eco_vb := ecology_panel.get_node("EcoMargin/EcoVB") as VBoxContainer
	var eco_scroll := ScrollContainer.new()
	eco_scroll.name = "EcoScroll"
	eco_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	eco_scroll.custom_minimum_size = Vector2(364, 168)
	eco_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	eco_vb.add_child(eco_scroll)
	ecology_label.reparent(eco_scroll)
	ecology_label.custom_minimum_size.x = 352
	ecology_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	(ecology_panel.get_node("EcoMargin/EcoVB/EcologyTitle") as Label).add_theme_font_size_override("font_size", 16)
	_resize_status_plate()
	_heart_icon.position = Vector2(22, 27)
	_heart_icon.size = Vector2(22, 22)
	_hp_ghost_bar.custom_minimum_size = Vector2(286, 24)
	mp_bar.custom_minimum_size = Vector2(286, 18)
	xp_bar.custom_minimum_size = Vector2(286, 6)
	_hp_value = _bar_value_label(hp_bar)
	_mp_value = _bar_value_label(mp_bar)
	stats_label.add_theme_font_size_override("font_size", 18)
	stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stats_label.custom_minimum_size.x = 252
	for label: Label in [bounty_label, quest_label]:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = 286
		label.add_theme_font_size_override("font_size", 16)
		label.add_theme_color_override("font_outline_color", Color("16242d"))
		label.add_theme_constant_override("outline_size", 2)
	toast_label.add_theme_font_size_override("font_size", 20)
	toast_label.add_theme_color_override("font_outline_color", Color("16242d"))
	toast_label.add_theme_constant_override("outline_size", 5)
	toast_label.offset_left = -246
	toast_label.offset_right = 246
	toast_label.offset_top = 24
	toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_combat_toast.add_theme_color_override("font_outline_color", Color("16242d"))
	_combat_toast.add_theme_constant_override("outline_size", 4)
	%BtnEco.position = Vector2(362, 18)
	%BtnEco.size = Vector2(80, 80)
	_add_button_caption(%BtnEco, "生态")
	for pair: Array in [[%BtnBag, "背包"], [%BtnCodex, "图鉴"], [%BtnShop, "商店"], [%PauseBtn, "暂停"]]:
		_add_button_caption(pair[0], pair[1])
	%Minimap.offset_top = 24
	%Minimap.offset_bottom = 144
	for i in 4:
		var button: Button = [%BtnBag, %BtnCodex, %BtnShop, %PauseBtn][i]
		button.offset_left = -352 + i * 84
		button.offset_right = button.offset_left + 80
		button.offset_top = 156
		button.offset_bottom = 236
	stat_buttons.offset_top = 248
	stat_buttons.offset_bottom = 302
	# 无补给时保留可识别的空槽，而不是只剩一块无义图标。
	_add_button_caption(_quick_btn, "补给")
	# 战斗控件有独立键位；不进入Tab链，避免暂停后键盘焦点绕到遮罩背后。
	for name: String in ["AttackBtn", "DashBtn", "HeavyBtn", "BoltBtn", "HealBtn", "EmpowerBtn", "QuickSlotBtn", "BtnEco", "BtnBag", "BtnCodex", "BtnShop", "PauseBtn"]:
		(root.get_node(name) as Button).focus_mode = Control.FOCUS_NONE
	for button: Button in stat_buttons.get_children():
		button.focus_mode = Control.FOCUS_NONE
	death_label.add_theme_color_override("font_outline_color", Color("16242d"))
	death_label.add_theme_constant_override("outline_size", 6)


func _resize_status_plate() -> void:
	if _hud_plate != null:
		var top := get_node("Root/TopLeft") as Control
		_hud_plate.size = Vector2(338, top.size.y + 24)
		# 任务行出现/换行会改变信息块高度，生态面板必须跟随，不能压住任务文字。
		ecology_panel.position = Vector2(14, top.position.y + top.size.y + 22)
		ecology_panel.size = Vector2(400, 234)


func _bar_value_label(bar: ProgressBar) -> Label:
	var label := Label.new()
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color("fcf4e0"))
	label.add_theme_color_override("font_outline_color", Color("17232c"))
	label.add_theme_constant_override("outline_size", 3)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(label)
	return label


func _add_button_caption(button: Button, caption: String) -> void:
	var label := Label.new()
	label.name = "Caption"
	label.text = caption
	label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	label.offset_top = -19
	label.offset_bottom = 1
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", HotwTheme.TEXT)
	label.add_theme_color_override("font_outline_color", Color("17232c"))
	label.add_theme_constant_override("outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(label)


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
	_process_dialogue(delta)
	_update_smooth_bars(delta)
	# 帧率显示（4Hz）：FPS + 每帧绘制调用数（定位 GPU/CPU 侧用——真机卡顿
	# 时 DC 高而 FPS 低指向 GPU，DC 低而 FPS 低指向 CPU）
	_fps_accum += delta
	if _fps_accum >= 0.25:
		_fps_accum = 0.0
		var want_visible := bool(GameState.settings.get("show_fps", false))
		if _fps_label.visible != want_visible:
			_fps_label.visible = want_visible
		if want_visible:
			_fps_label.text = "%d FPS · DC %d" % [Engine.get_frames_per_second(),
				Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)]


## 底部居中帧率小字（默认隐藏；joystick 在左下、技能钮在右下，中间空）
func _setup_fps_label() -> void:
	_fps_label = Label.new()
	_fps_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_fps_label.offset_left = -46.0
	_fps_label.offset_right = 46.0
	_fps_label.offset_top = -34.0
	_fps_label.offset_bottom = -12.0
	_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fps_label.add_theme_font_size_override("font_size", 16)
	_fps_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.7, 0.85))
	_fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fps_label.visible = false
	add_child(_fps_label)


## 三条平滑逼近 + 血条白色残影的慢速追随。
## 收敛阈值 0.1%：lerp 尾部每帧都在微量变值，会让 ProgressBar 永久每帧
## 重绘不止；收敛后吸附到目标值即停（真机性能优化 2026-09-19）
func _update_smooth_bars(delta: float) -> void:
	var t := 1.0 - exp(-BAR_SMOOTH * delta)
	_snap_lerp(hp_bar, _hp_target, t)
	_snap_lerp(mp_bar, _mp_target, t)
	_snap_lerp(xp_bar, _xp_target, t)
	if _hp_ghost > _hp_target:
		_hp_ghost_hold = maxf(0.0, _hp_ghost_hold - delta)
		if _hp_ghost_hold <= 0.0:
			_hp_ghost = maxf(_hp_target, _hp_ghost - _hp_max_cache * GHOST_DRAIN_FRAC * delta)
	if _hp_ghost_bar != null:
		if not is_equal_approx(_hp_ghost_bar.max_value, _hp_max_cache):
			_hp_ghost_bar.max_value = _hp_max_cache
		if not is_equal_approx(_hp_ghost_bar.value, _hp_ghost):
			_hp_ghost_bar.value = _hp_ghost


## 平滑逼近一个 ProgressBar，近目标吸附、值未变不赋（赋值触发重绘）
func _snap_lerp(bar: ProgressBar, target: float, t: float) -> void:
	var v := lerpf(bar.value, target, t)
	if absf(v - target) <= maxf(1.0, bar.max_value) * 0.001:
		v = target
	if not is_equal_approx(v, bar.value):
		bar.value = v


## 键盘开关生态面板（Tab）/ 图鉴（C）/ 商店（B）/ 背包（O）/ 暂停（ESC）；触屏走按钮
func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if event.is_action_pressed("toggle_ecology"):
		ecology_panel.visible = not ecology_panel.visible
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_codex"):
		_toggle_codex()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_shop"):
		_toggle_shop()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_inventory"):
		_toggle_inventory()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause"):
		_close_top_layer_or_toggle_pause()
		get_viewport().set_input_as_handled()


## ESC 先关最上层弹层（设置→图鉴→物品栏→商店），全关后才切暂停——
## 否则世界解除暂停恢复战斗，设置层却还悬浮在画面上挡操作
func _close_top_layer_or_toggle_pause() -> void:
	if passive_layer.visible:
		return
	if _choice_layer_visible():
		_close_choice_layer()
	elif pause_settings_layer.visible:
		_close_pause_settings()
	elif codex_layer.visible:
		_close_codex()
	elif _inv_layer != null and _inv_layer.visible:
		_close_inventory()
	elif shop_panel.visible:
		shop_panel.visible = false
	else:
		_toggle_pause()


# --- 技能冷却条 ---

func _on_skills_changed(dash_cd: float, heavy_cd: float, bolt_cd: float, heal_cd: float,
		empower_cd: float, mp: float, _max_mp: float) -> void:
	var incoming := [dash_cd, heavy_cd, bolt_cd, heal_cd, empower_cd]
	for i in incoming.size():
		var previous := maxf(0.0, _cd_values[i] - _cd_elapsed)
		if incoming[i] > previous + 0.05:
			_cd_durations[i] = incoming[i]
	_cd_values = incoming
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
			var overlay: Control = slot.get("overlay")
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
				# 字号覆盖只在 26↔16 档位切换时调：每次调用都会重建主题覆盖
				# 并排队重绘，每帧×5 槽是纯浪费（真机性能优化 2026-09-19）
				var size_want := 26 if left > 0.05 else 16
				if cd_label.get_theme_font_size("font_size") != size_want:
					cd_label.add_theme_font_size_override("font_size", size_want)
				cd_label.visible = want_text != ""
			if overlay != null:
				overlay.visible = left > 0.05 or hint != ""
				var duration := maxf(float(_cd_durations[i]), left)
				overlay.set("fraction", clampf(left / duration, 0.0, 1.0) if left > 0.05 else 1.0)
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
	if _choice_layer_visible():
		_close_choice_layer()
		return
	if _inv_layer != null and _inv_layer.visible:
		_toggle_inventory()
		return
	if codex_layer.visible:
		# 图鉴打开期间世界已暂停：任何暂停入口（按钮/ESC）先收起图鉴，
		# 直接翻转 paused 会造成"世界恢复运行而图鉴还开着"的坏状态
		_toggle_codex()
		return
	# 鼠标暂停入口也必须收起商店，不能把仍可键盘购买的商店留在遮罩背后。
	shop_panel.visible = false
	var paused := not get_tree().paused
	get_tree().paused = paused
	if paused:
		# 暂停期间触屏按钮的排队不应在恢复后一次性兑现
		TouchInput.clear_queues()
	pause_layer.visible = paused
	pause_settings_layer.visible = false
	_sync_modal_focus()


func _open_pause_settings() -> void:
	if not pause_layer.visible:
		return
	pause_settings_layer.visible = true
	_sync_modal_focus()


func _close_pause_settings() -> void:
	pause_settings_layer.visible = false
	_sync_modal_focus(%PauseSettingsBtn)


## 遮罩只挡鼠标，不挡键盘焦点。仅最上层可进入 Tab 链，关闭后恢复原始模式。
## 模态内动态生成的背包格子也在每次打开后登记；不改常驻战斗按钮的 FOCUS_NONE。
func _sync_modal_focus(preferred: Control = null) -> void:
	var active: Control = null
	var fallback: Control = null
	if passive_layer.visible:
		active = passive_layer
		fallback = passive_cards[0]
	elif _stat_layer != null and _stat_layer.visible:
		active = _stat_layer
		fallback = _stat_layer.find_child("ChoiceClose", true, false)
	elif _task_layer != null and _task_layer.visible:
		active = _task_layer
		fallback = _task_layer.find_child("ChoiceClose", true, false)
	elif pause_settings_layer.visible:
		active = pause_settings_layer
		fallback = %PauseSettingsClose
	elif _inv_layer != null and _inv_layer.visible:
		active = _inv_layer
		fallback = _inv_layer.find_child("InventoryClose", true, false) as Control
	elif codex_layer.visible:
		active = codex_layer
		fallback = %CodexClose
	elif pause_layer.visible:
		active = pause_layer
		fallback = %ResumeBtn
	for node: Node in get_node("Root").find_children("*", "Control", true, false):
		var control := node as Control
		if not control.has_meta("hud_focus_mode"):
			control.set_meta("hud_focus_mode", control.focus_mode)
		var eligible := active == null or control == active or active.is_ancestor_of(control)
		control.focus_mode = int(control.get_meta("hud_focus_mode")) if eligible else Control.FOCUS_NONE
	if active == null:
		return
	if preferred != null and preferred.is_visible_in_tree() \
			and active.is_ancestor_of(preferred) and preferred.focus_mode != Control.FOCUS_NONE:
		preferred.grab_focus()
		return
	var focused := get_viewport().gui_get_focus_owner()
	if focused == null or not active.is_ancestor_of(focused):
		if fallback != null:
			fallback.grab_focus()


## 关闭动作必须幂等：同帧重复点击不能把刚收起的面板重新打开。
func _resume_game() -> void:
	if not pause_layer.visible:
		return
	pause_layer.visible = false
	pause_settings_layer.visible = false
	get_tree().paused = false
	TouchInput.clear_queues()
	_sync_modal_focus()


func _close_codex() -> void:
	if not codex_layer.visible:
		return
	codex_layer.visible = false
	get_tree().paused = false
	TouchInput.clear_queues()
	_sync_modal_focus()


func _close_inventory() -> void:
	if _inv_layer == null or not _inv_layer.visible:
		return
	_inv_layer.visible = false
	get_tree().paused = false
	TouchInput.clear_queues()
	_sync_modal_focus()


## 手动保存（暂停菜单"保存进度"）：自动存档本已覆盖，按钮的价值是
## 给玩家确定感；toast 计时在暂停态冻结，"已保存"会停留到恢复游戏后淡出
func _save_progress() -> void:
	var saved := GameState.save_now()
	_toast("已保存" if saved else ("存档已禁用" if not GameState.save_enabled else "保存失败，请重试"))


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
	if _choice_layer_visible():
		return
	if _inv_layer != null and _inv_layer.visible:
		return
	# 暂停菜单/三选一已占住屏幕时不响应（键 C 穿透暂停层打开图鉴会造成
	# 双弹层叠加 + 暂停态翻转错乱）
	if not codex_layer.visible and (pause_layer.visible or pause_settings_layer.visible \
			or passive_layer.visible):
		return
	shop_panel.visible = false
	codex_layer.visible = not codex_layer.visible
	if codex_layer.visible:
		# 图鉴是 29 物种 + 成就的长列表阅读界面：读条时被围殴不是乐趣是干扰，
		# 与升级三选一同口径（暂停 + 清触屏队列）；商店维持打开不暂停（已拍板）
		get_tree().paused = true
		TouchInput.clear_queues()
		_refresh_codex()
	else:
		get_tree().paused = false
		TouchInput.clear_queues()
	_sync_modal_focus()


func _refresh_codex() -> void:
	var lines: Array[String] = []
	# 物种清单取自运行中的模拟（= data/species/*.tres 真源）：
	# 新增种族后图鉴自动收录，与成就判定同口径，不再手抄清单漂移
	var species_names: Array = []
	if WorldSim.sim != null:
		for species: SpeciesData in WorldSim.sim.species_list:
			species_names.append(species.species_name)
	for i in species_names.size():
		var kills: int = int(GameState.codex.get(species_names[i], 0))
		if kills > 0:
			var species: SpeciesData = WorldSim.sim.species_list[i]
			var status := WorldEventDetector.species_status_text(species_names[i],
					WorldSim.sim.alive_count_of_species(species_names[i]), WorldSim.sim.player_extinct,
					species.is_boss, WorldSim.sim.reintroduction_enabled)
			lines.append("✓ %s  累计猎杀 %d\n    %s" % [species_names[i], kills, status])
		else:
			# 未猎杀隐藏名字（收集悬念），但给序号让玩家能感知收集进度
			lines.append("？ #%02d 未曾猎杀" % [i + 1])
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
	lines.append(_owned_passive_text())
	codex_content.text = "\n".join(lines)
	var ach_lines: Array[String] = []
	for id in AchievementManager.ACHIEVEMENTS:
		var info: Dictionary = AchievementManager.ACHIEVEMENTS[id]
		var mark := "★" if GameState.achievements.has(id) else "☆"
		ach_lines.append("%s %s — %s" % [mark, info["title"], info["desc"]])
	ach_content.text = "\n".join(ach_lines)


# --- 三选一被动（升级赐福） ---

func _on_leveled_up(_new_level: int, _levels_gained: int) -> void:
	# 资格由 CharacterStats 在发信号前记账；HUD 只展示，重建场景不会丢失。
	if not passive_layer.visible:
		_open_passive_pick()


func _open_passive_pick() -> void:
	if GameState.stats.pending_passive_picks <= 0:
		passive_layer.visible = false
		get_tree().paused = false
		_sync_modal_focus()
		return
	var chosen: Array[String] = GameState.stats.passive_choices
	for i in 3:
		var btn: Button = passive_cards[i]
		if i < chosen.size():
			var entry: Dictionary = {}
			for candidate: Dictionary in CharacterStats.PASSIVE_POOL:
				if candidate["id"] == chosen[i]:
					entry = candidate
			var lv: int = GameState.stats.passive_level(entry["id"])
			btn.icon = PASSIVE_ICONS.get(entry["id"], PASSIVE_ICON_DEFAULT)
			btn.expand_icon = true
			btn.text = "%s  %d → %d 级\n%s" % [entry["name"], lv, lv + 1,
					_benefit_text(GameState.stats.preview_passive(entry["id"]))]
			btn.set_meta("passive_id", entry["id"])
			btn.set_meta("passive_offer_id", GameState.stats.passive_offer_id)
			btn.visible = true
		else:
			btn.visible = false
	_passive_owned.text = _owned_passive_text()
	# 升级可发生于读取/调试信号中断：先收起旧模态，再把赐福放到最上层。
	for layer: Control in [_inv_layer, _task_layer, _stat_layer, codex_layer,
			pause_layer, pause_settings_layer, shop_panel]:
		if layer != null:
			layer.visible = false
	passive_layer.get_parent().move_child(passive_layer, -1)
	# 读卡时暂停世界，领取后不会遗留隐藏模态的暂停态。
	passive_layer.visible = true
	get_tree().paused = true
	TouchInput.clear_queues()
	_sync_modal_focus()


func _pick_passive(index: int) -> void:
	if _passive_pick_locked or not passive_layer.visible or index < 0 or index >= passive_cards.size():
		return
	var btn: Button = passive_cards[index]
	var id := str(btn.get_meta("passive_id", ""))
	var offer_id := int(btn.get_meta("passive_offer_id", -1))
	_passive_pick_locked = true
	if GameState.stats.claim_passive(id, offer_id):
		SfxManager.play("passive")
		_open_passive_pick()
	await get_tree().process_frame
	_passive_pick_locked = false


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


## 行点击只打开列表，不改任务。真实触摸和鼠标经同一 GUI 输入通道。
func _on_quest_label_input(event: InputEvent) -> void:
	var clicked: bool = event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT
	var touched: bool = event is InputEventScreenTouch and event.pressed
	if clicked or touched:
		quest_label.accept_event()
		_open_task_list()


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
	if _choice_layer_visible():
		return
	if pause_layer.visible or pause_settings_layer.visible or passive_layer.visible or codex_layer.visible:
		return
	# 物品栏开着（世界暂停）时开商店会留下"商店可点而世界冻结"的怪态——先收起
	if _inv_layer != null and _inv_layer.visible:
		_close_inventory()
	shop_panel.visible = not shop_panel.visible
	if shop_panel.visible:
		_refresh_shop()


func _refresh_shop() -> void:
	shop_gold_label.text = "金币 %d" % GameState.gold
	_refresh_shop_btn(shop_upgrade_btns[0], "weapon", "武器磨刀", "物理攻击", ICON_KATANA)
	_refresh_shop_btn(shop_upgrade_btns[1], "staff", "法杖赋能", "魔法攻击", ICON_FORK)
	_refresh_shop_btn(shop_upgrade_btns[2], "vigor", "体质淬炼", "生命上限", ICON_HEART)
	_refresh_supply()
	_refresh_sellout()


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


# --- 物品系统（玩法 v7 P0）：商店三分区 + 物品栏弹层 + 战斗快捷槽 ---

## 商店页签化：强化页收编既有三按钮（reparent 不改 owner，%引用不受影响——
## 与 _setup_stats_row 的 StatsLabel 同款手法）；补给/收购两页的商品按钮
## 从 EconomyMath 价格表数据驱动生成，增删物品零 UI 改动
func _setup_shop_tabs() -> void:
	var vb: VBoxContainer = shop_panel.get_node("Margin/VB")
	var tabs := TabContainer.new()
	tabs.name = "ShopTabs"
	tabs.custom_minimum_size = Vector2(0, 336)
	tabs.add_theme_font_size_override("font_size", 18)
	# 页签木色化（配合木桌面板底）：选中亮木金边、未选暗木；内容区透明浮于木桌
	var tab_un := StyleBoxFlat.new()
	tab_un.bg_color = Color(0.24, 0.17, 0.12, 0.95)
	tab_un.border_color = Color(0.5, 0.37, 0.24, 0.9)
	tab_un.set_border_width_all(1)
	tab_un.set_corner_radius_all(4)
	tab_un.set_content_margin_all(10)
	var tab_sel := tab_un.duplicate()
	tab_sel.bg_color = Color(0.38, 0.27, 0.15, 0.98)
	tab_sel.border_color = Color(1.0, 0.82, 0.45, 0.9)
	tabs.add_theme_stylebox_override("tab_unselected", tab_un)
	tabs.add_theme_stylebox_override("tab_selected", tab_sel)
	tabs.add_theme_color_override("font_selected_color", Color(1, 0.95, 0.8))
	tabs.add_theme_color_override("font_unselected_color", Color(0.82, 0.76, 0.66))
	var tabs_panel := StyleBoxFlat.new()
	tabs_panel.bg_color = Color(0, 0, 0, 0)
	tabs.add_theme_stylebox_override("panel", tabs_panel)

	var tab_up := VBoxContainer.new()
	tab_up.name = "强化"
	tabs.add_child(tab_up)
	for btn: Button in shop_upgrade_btns:
		btn.reparent(tab_up)

	var tab_supply := VBoxContainer.new()
	tab_supply.name = "补给"
	tabs.add_child(tab_supply)
	for id: String in EconomyMath.ITEM_BUY:
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 52)
		b.icon = ItemCatalog.icon_of(id)
		b.expand_icon = true
		b.pressed.connect(_buy_item.bind(id))
		tab_supply.add_child(b)
		_supply_btns[id] = b

	var tab_sell := VBoxContainer.new()
	tab_sell.name = "收购"
	tabs.add_child(tab_sell)
	for id: String in EconomyMath.ITEM_SELL:
		# 钥匙不进收购页（凭证非商品）：金钥匙仅收集委托可得，误卖整叠会锁死
		# 城塞宝箱闭环（ITEM_SELL 表保留钥匙 id 以过 knows_item 存档消毒认证）
		if ItemCatalog.kind_of(id) == "key":
			continue
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 52)
		b.icon = ItemCatalog.icon_of(id)
		b.expand_icon = true
		b.pressed.connect(_sell_item.bind(id))
		tab_sell.add_child(b)
		_sell_btns[id] = b

	vb.add_child(tabs)
	vb.move_child(tabs, 2)  # GoldLabel 之后、关闭按钮之前


func _refresh_supply() -> void:
	for id: String in _supply_btns:
		var btn: Button = _supply_btns[id]
		var price := EconomyMath.item_price(id)
		btn.text = "%s %s ｜ %d 金币" % [ItemCatalog.name_of(id), ItemCatalog.desc_of(id), price]
		btn.disabled = GameState.gold < price or GameState.count_item(id) >= GameState.ITEM_MAX


func _refresh_sellout() -> void:
	for id: String in _sell_btns:
		var btn: Button = _sell_btns[id]
		var n := GameState.count_item(id)
		btn.text = "%s ×%d ｜ 售 %d 金/个" % [ItemCatalog.name_of(id), n,
			EconomyMath.item_sell_price(id)]
		btn.disabled = n <= 0


func _buy_item(id: String) -> void:
	if GameState.buy_item(id):
		SfxManager.play("levelup")
		_toast_combat("购入 %s" % ItemCatalog.name_of(id))
	else:
		SfxManager.play("menu")
		_toast_combat("金币不足或背包已满")
	_refresh_shop()


func _sell_item(id: String) -> void:
	var n := GameState.sell_material(id)
	if n > 0:
		SfxManager.play("levelup")
		_toast_combat("售出 %s ×%d（+%d 金）" % [ItemCatalog.name_of(id), n,
			n * EconomyMath.item_sell_price(id)])
	_refresh_shop()


## 拾取播报：主 toast 通道（与装备掉落同位——战斗播报位留给击杀行，
## 0.4s 短窗合并让连杀+连拾自然拼行）
func _on_item_gained(item_id: String, count: int, total: int) -> void:
	_toast("拾取 %s ×%d（共 %d）" % [ItemCatalog.name_of(item_id), count, total])


## 物品栏弹层（阅读型，照图鉴口径：打开暂停世界 + 清触屏队列；
## 全代码构建避免 .tscn 手术，结构同 CodexLayer：Dim → Panel → VB → Scroll → Grid）
func _setup_inventory_layer() -> void:
	var root := get_node("Root") as Control
	_inv_layer = Control.new()
	_inv_layer.name = "InventoryLayer"
	_inv_layer.visible = false
	_inv_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(_inv_layer)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP  # 挡住下层触控
	_inv_layer.add_child(dim)

	var panel := PanelContainer.new()
	# 中心锚定 + 四向偏移（照 ShopPanel 的 tscn 模式）：PRESET_CENTER 的
	# MINSIZE 模式把控件左上角放在屏幕中心，600 高的面板底部直接出屏
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -324.0
	panel.offset_top = -290.0
	panel.offset_right = 324.0
	panel.offset_bottom = 290.0
	_inv_layer.add_child(panel)
	# 木瓦底 + 芥末黄丝带标题（与游商营地同属交易/收纳意象）
	HotwTheme.paper_panel(panel, HotwTheme.WOOD_TILE, 40)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)
	var vb := VBoxContainer.new()
	margin.add_child(vb)

	var title := HotwTheme.ribbon_tag("装备与物品", 2, 240.0)
	title.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(title)

	_inv_hint = Label.new()
	_inv_hint.add_theme_font_size_override("font_size", 16)
	_inv_hint.add_theme_color_override("font_color", Color(0.85, 0.85, 0.8, 0.9))
	_inv_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_inv_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_inv_hint)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 356)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	_inv_grid = GridContainer.new()
	_inv_grid.columns = 5
	_inv_grid.add_theme_constant_override("h_separation", 10)
	_inv_grid.add_theme_constant_override("v_separation", 10)
	_inv_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var contents := VBoxContainer.new()
	contents.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	contents.add_theme_constant_override("separation", 12)
	scroll.add_child(contents)
	var equipment_help := Label.new()
	equipment_help.text = "锁定槽保留 1 件待比较装备；选择后换下或放弃的装备折金。\n候选未处理时，后续掉落直接折金。解锁可启用总词条自动换装。"
	equipment_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	equipment_help.add_theme_font_size_override("font_size", 16)
	_equipment_offer = VBoxContainer.new()
	_equipment_offer.name = "EquipmentOffer"
	_equipment_offer.add_theme_constant_override("separation", 8)
	contents.add_child(_equipment_offer)
	contents.add_child(equipment_help)
	for slot: String in GameState.EQUIP_SLOTS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		contents.add_child(row)
		var detail := Label.new()
		detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail.add_theme_font_size_override("font_size", 16)
		row.add_child(detail)
		_equipment_labels[slot] = detail
		var lock_button := Button.new()
		lock_button.name = "EquipmentLock_" + slot
		lock_button.custom_minimum_size = Vector2(152, 72)
		lock_button.toggle_mode = true
		lock_button.toggled.connect(_on_equipment_lock_toggled.bind(slot))
		row.add_child(lock_button)
		_equipment_lock_buttons[slot] = lock_button
	contents.add_child(HSeparator.new())
	contents.add_child(_inv_grid)

	var close := Button.new()
	close.name = "InventoryClose"
	close.text = "关闭（O）"
	close.custom_minimum_size = Vector2(0, 56)
	close.pressed.connect(_close_inventory)
	vb.add_child(close)


func _toggle_inventory() -> void:
	if _choice_layer_visible():
		return
	# 暂停菜单/设置/三选一/图鉴已占屏时不响应（与 _toggle_codex 同防穿层）
	if _inv_layer == null:
		return
	if not _inv_layer.visible and (pause_layer.visible or pause_settings_layer.visible \
			or passive_layer.visible or codex_layer.visible):
		return
	if _inv_layer.visible == false and shop_panel.visible:
		shop_panel.visible = false  # 商店不暂停，与暂停态物品栏互斥
	_inv_layer.visible = not _inv_layer.visible
	if _inv_layer.visible:
		# 阅读型面板（照图鉴口径）：读背包时被围殴不是乐趣是干扰
		get_tree().paused = true
		TouchInput.clear_queues()
		_refresh_inventory()
	else:
		get_tree().paused = false
		TouchInput.clear_queues()
	_sync_modal_focus()


func _refresh_inventory() -> void:
	_refresh_equipment()
	_refresh_equipment_offer()
	# 先摘除再延迟释放：queue_free 是帧末生效，同帧连刷（拾取信号 + 使用后刷新）
	# 会把待释放格子留在树里，格数统计与布局都失真
	for child in _inv_grid.get_children().duplicate():
		_inv_grid.remove_child(child)
		child.queue_free()
	var ids: Array[String] = []
	ids.append_array(ItemCatalog.ids_of_kind("consumable"))
	ids.append_array(ItemCatalog.ids_of_kind("material"))
	# 钥匙也入列：凭证类物品必须有常驻 UI 可查持有量（此前拾取 toast 之外无处可看）
	ids.append_array(ItemCatalog.ids_of_kind("key"))
	var shown := 0
	for id: String in ids:
		var n := GameState.count_item(id)
		if n <= 0:
			continue
		shown += 1
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(104, 104)
		var icon := HotwTheme.add_icon(btn, ItemCatalog.icon_of(id), 23.0)
		icon.offset_bottom = -38
		_add_button_caption(btn, ItemCatalog.name_of(id))
		var caption := btn.get_node("Caption") as Label
		caption.offset_top = -34
		caption.offset_bottom = -12
		caption.add_theme_font_size_override("font_size", 14)
		HotwTheme.add_badge(btn, "×%d" % n).add_theme_font_size_override("font_size", 16)
		btn.pressed.connect(_on_inv_cell.bind(id))
		_inv_grid.add_child(btn)
	_inv_hint.text = "消耗品点击即使用 ｜ 材料可整叠售予营地行商" if shown > 0 \
			else "暂无材料与补给——猎杀野兽有机会拾取"


## 开关用目标布尔值而非反转：同一回调重复交付也不会翻回原状态。
func _on_equipment_lock_toggled(locked: bool, slot: String) -> void:
	if _inv_layer == null or not _inv_layer.visible:
		return
	GameState.set_equipment_locked(slot, locked)
	_refresh_equipment()


func _refresh_equipment() -> void:
	for slot: String in _equipment_labels:
		var item: Dictionary = GameState.stats.equips.get(slot, {})
		var label: Label = _equipment_labels[slot]
		var button: Button = _equipment_lock_buttons[slot]
		var locked := GameState.is_equipment_locked(slot)
		label.text = "%s：%s" % [GameState.SLOT_NAMES[slot],
				"尚未装备" if item.is_empty() else GameState.equip_description(item)]
		button.disabled = item.is_empty()
		button.set_pressed_no_signal(locked)
		button.text = "空槽" if item.is_empty() else ("已锁定\n点击解锁" if locked else "自动换装\n点击锁定")


## 物品格子点击：消耗品 → 经 item_use_requested 交 player 应用（满血拦截也在那）；
## 钥匙 → 播报用途（凭证不可用不可售）；材料 → 文案播报（面板是暂停态，_toast 计时冻结可从容读）
func _on_inv_cell(id: String) -> void:
	if ItemCatalog.is_consumable(id):
		EventBus.item_use_requested.emit(id)
		_refresh_inventory()  # player 同步扣减，立刻反映数量
	elif ItemCatalog.kind_of(id) == "key":
		_toast("%s：城塞宝箱凭证（%s）" % [ItemCatalog.name_of(id),
			"击败精英怪有几率掉落" if id == "silver-key" else "完成收集委托获得"])
	else:
		_toast("%s：%s（%d 金/个）" % [ItemCatalog.name_of(id), ItemCatalog.desc_of(id),
			EconomyMath.item_sell_price(id)])


## 战斗快捷槽：零配置绑定——按 QUICK_PRIORITY 取当前资源有缺口的恢复品，
## 显示持有数；点击经 item_use_requested 交 player（满血满蓝拦截在 player 侧）
func _setup_quick_slot() -> void:
	_quick_btn = %QuickSlotBtn
	HotwTheme.style_ts_round_button(_quick_btn)
	_quick_icon = HotwTheme.add_icon(_quick_btn, ICON_HEART, 18.0)
	_quick_badge = HotwTheme.add_badge(_quick_btn, "")
	_quick_btn.pressed.connect(_on_quick_slot)
	_refresh_quick_slot()


func _refresh_quick_slot() -> void:
	if _quick_btn == null:
		return
	var pick := ""
	for id: String in QUICK_PRIORITY:
		if GameState.count_item(id) <= 0:
			continue
		var needs_hp := _hp_known and not _hp_full and CharacterStats.ITEM_HP_FRAC.has(id)
		var needs_mp := _mp_known and _mp_now < _mp_max_cache - 0.5 and CharacterStats.ITEM_MP_FRAC.has(id)
		if needs_hp or needs_mp:
			pick = id
			break
	_quick_id = pick
	_quick_btn.disabled = pick == ""
	_quick_icon.texture = ItemCatalog.icon_of(pick) if pick != "" else ICON_BAG
	_quick_badge.text = str(GameState.count_item(pick)) if pick != "" else ""


func _on_quick_slot() -> void:
	_refresh_quick_slot()
	if _quick_id == "":
		return
	EventBus.item_use_requested.emit(_quick_id)


func _on_hp_changed(current: float, maximum: float) -> void:
	_hp_known = true
	if _hp_value != null:
		_hp_value.text = "%d / %d" % [ceili(current), ceili(maximum)]
	hp_bar.max_value = maximum
	_hp_max_cache = maximum
	_hp_full = current >= maximum - 0.5
	# 心形图标按血量换帧（TS 合成条带：0=空心 … 4=满心）
	if _heart_icon != null and maximum > 0.0:
		_heart_icon.texture = _heart_frame(int(round(
			clampf(current / maximum, 0.0, 1.0) * 4.0)))
	# 平滑条：事件只写目标，_process 逼近；掉血时白色残影先按住片刻
	if current < _hp_target:
		_hp_ghost_hold = GHOST_HOLD
	if current > _hp_ghost:
		_hp_ghost = current  # 回血：残影立即抬升
	_hp_target = current
	_refresh_quick_slot()


func _on_mp_changed(current: float, maximum: float) -> void:
	_mp_known = true
	_mp_max_cache = maximum
	_mp_now = current
	if _mp_value != null:
		_mp_value.text = "%d / %d" % [ceili(current), ceili(maximum)]
	mp_bar.max_value = maximum
	_mp_target = current
	_refresh_quick_slot()


func _on_progress_changed(level: int, xp: int, xp_needed: int, pending_points: int) -> void:
	xp_bar.max_value = xp_needed
	_xp_target = xp
	_refresh_stats_label(level, pending_points)
	if _inv_layer != null and _inv_layer.visible:
		_refresh_equipment()
		_refresh_equipment_offer()
	if _stat_layer != null and _stat_layer.visible:
		_refresh_stat_preview()


func _on_gold_changed(_amount: int) -> void:
	_refresh_stats_label(GameState.stats.level, GameState.stats.pending_points)
	if shop_panel.visible:
		_refresh_shop()


func _refresh_stats_label(level: int, pending_points: int) -> void:
	# 有待分配属性点时亮出分配按钮，分完收起
	stat_buttons.visible = pending_points > 0
	stats_label.text = "Lv.%d  金币 %d" % [level, GameState.gold]
	if _region_name != "":
		stats_label.text += "\n%s" % _region_name
	if pending_points > 0:
		stats_label.text += " · 属性点 +%d" % pending_points


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
		# 明细截断：每地形最多 3 项 +「等N种」，行宽控在面板 320px 内容宽内
		#（Label 另有 autowrap 兜底极端长名），展开面板右缘距屏幕中心英雄尚有
		# 360px+ 净空，任何状态下都不再横压画面中部
		if parts.size() > 3:
			var hidden := parts.size() - 3
			parts = parts.slice(0, 3)
			parts.append("等%d种" % hidden)
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


# --- 选择前的实际收益（CharacterStats 的只读快照，展示层不重算养成公式） ---
const BENEFIT_NAMES := {
	"max_hp": "生命上限", "hp_regen": "生命回复/秒", "max_mp": "精力上限",
	"mp_regen": "精力回复/秒", "physical": "物理攻击", "magic": "魔法攻击",
	"heal": "治疗回复", "move": "移动速度", "attack_interval": "攻击间隔",
	"heavy_cooldown": "重击冷却", "lifesteal": "普攻吸血", "gold": "金币倍率",
	"xp": "经验倍率", "knock": "击退倍率",
}


func _benefit_value(key: String, value: float) -> String:
	if key in ["gold", "xp", "knock"]:
		return "×%.2f" % value
	if key in ["attack_interval", "heavy_cooldown"]:
		return "%.2f秒" % value
	return "%.2f" % value


func _benefit_text(preview: Dictionary, include_key_stats := false) -> String:
	var lines: Array[String] = []
	var before: Dictionary = preview["before"]
	var after: Dictionary = preview["after"]
	for key: String in BENEFIT_NAMES:
		if not is_equal_approx(float(before[key]), float(after[key])) \
				or (include_key_stats and key in ["max_hp", "physical"]):
			lines.append("%s  %s → %s" % [BENEFIT_NAMES[key],
					_benefit_value(key, before[key]), _benefit_value(key, after[key])])
	return "\n".join(lines) if not lines.is_empty() else "当前数值已到上限，无额外提升"


func _owned_passive_text() -> String:
	var parts: Array[String] = []
	for entry: Dictionary in CharacterStats.PASSIVE_POOL:
		var rank := GameState.stats.passive_level(entry["id"])
		if rank > 0:
			parts.append("%s%d级" % [entry["name"], rank])
	return "已获赐福：" + ("、".join(parts) if not parts.is_empty() else "暂无")


func _readable_label(text := "", font_size := 18) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", font_size)
	return label


## 通用的小型阅读层：可滚动正文和固定关闭按钮，继承 Root 的实际安全区。
func _new_choice_layer(layer_name: String, title: String) -> Control:
	var layer := Control.new()
	layer.name = layer_name
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.visible = false
	get_node("Root").add_child(layer)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.5)
	layer.add_child(dim)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -332
	panel.offset_right = 332
	panel.offset_top = -266
	panel.offset_bottom = 266
	HotwTheme.paper_panel(panel, HotwTheme.PAPER_SPECIAL)
	layer.add_child(panel)
	var margin := MarginContainer.new()
	for edge: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 20)
	panel.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	margin.add_child(content)
	var ribbon := HotwTheme.ribbon_tag(title, 0, 260)
	ribbon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	content.add_child(ribbon)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)
	var body := VBoxContainer.new()
	body.name = "Body"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	scroll.add_child(body)
	var close := Button.new()
	close.name = "ChoiceClose"
	close.text = "关闭 / 返回"
	close.custom_minimum_size = Vector2(0, 56)
	close.pressed.connect(_close_choice_layer)
	content.add_child(close)
	return layer


func _setup_choice_layers() -> void:
	_task_layer = _new_choice_layer("TaskListLayer", "当前委托")
	_task_rows = _task_layer.find_child("Body", true, false)
	_stat_layer = _new_choice_layer("StatPreviewLayer", "属性点收益")
	var body: VBoxContainer = _stat_layer.find_child("Body", true, false)
	_stat_preview = _readable_label()
	_stat_preview.name = "StatPreview"
	body.add_child(_stat_preview)
	_stat_owned = _readable_label("", 16)
	body.add_child(_stat_owned)
	_stat_confirm = Button.new()
	_stat_confirm.name = "ConfirmAttribute"
	_stat_confirm.custom_minimum_size = Vector2(0, 60)
	_stat_confirm.pressed.connect(_confirm_stat_point)
	body.add_child(_stat_confirm)
	_passive_owned = _readable_label("", 16)
	_passive_owned.name = "OwnedPassives"
	_passive_owned.custom_minimum_size.x = 860
	_passive_owned.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	passive_layer.get_node("PassiveVB").add_child(_passive_owned)
	for card: Button in passive_cards:
		card.custom_minimum_size = Vector2(280, 192)
		card.add_theme_font_size_override("font_size", 18)


func _choice_layer_visible() -> bool:
	return (_task_layer != null and _task_layer.visible) \
			or (_stat_layer != null and _stat_layer.visible)


func _can_open_choice() -> bool:
	return not passive_layer.visible and not pause_layer.visible and not pause_settings_layer.visible \
			and not codex_layer.visible and not _choice_layer_visible() \
			and not (_inv_layer != null and _inv_layer.visible)


func _open_choice_layer(layer: Control) -> void:
	shop_panel.visible = false
	layer.visible = true
	layer.get_parent().move_child(layer, -1)
	get_tree().paused = true
	TouchInput.clear_queues()
	_sync_modal_focus()


func _close_choice_layer() -> void:
	if not _choice_layer_visible() or passive_layer.visible:
		return
	_task_layer.visible = false
	_stat_layer.visible = false
	_stat_attribute = ""
	get_tree().paused = false
	TouchInput.clear_queues()
	_sync_modal_focus()


func _open_stat_preview(attribute: String) -> void:
	if not _can_open_choice() or GameState.stats.pending_points <= 0:
		return
	_stat_attribute = attribute
	_refresh_stat_preview()
	_open_choice_layer(_stat_layer)


func _refresh_stat_preview() -> void:
	var names := {"strength": "力量", "agility": "敏捷", "intellect": "智力"}
	if not names.has(_stat_attribute):
		return
	var points := GameState.stats.pending_points
	_stat_preview.text = "%s +1（可分配 %d 点）\n\n%s" % [names[_stat_attribute], points,
			_benefit_text(GameState.stats.preview_attribute(_stat_attribute))]
	_stat_owned.text = _owned_passive_text()
	_stat_confirm.text = "确认分配 1 点%s" % names[_stat_attribute]
	_stat_confirm.disabled = points <= 0


func _confirm_stat_point() -> void:
	if _stat_layer == null or not _stat_layer.visible or passive_layer.visible \
			or GameState.stats.pending_points <= 0:
		return
	var attribute := _stat_attribute
	# 先关闭并清空目标；重复/延迟回调不能再次消费属性点。
	_close_choice_layer()
	GameState.allocate(attribute)


func _on_quest_list_changed(active_quests: Array, tracked_quest_id: String) -> void:
	_task_snapshot = active_quests.duplicate(true)
	_tracked_quest_id = tracked_quest_id
	if _task_layer != null and _task_layer.visible:
		_refresh_task_list()
		_sync_modal_focus()


func _open_task_list() -> void:
	if not _can_open_choice():
		return
	_task_snapshot = GameState.quests.get("active", []).duplicate(true)
	_tracked_quest_id = GameState.tracked_quest_id
	_refresh_task_list()
	_open_choice_layer(_task_layer)


func _refresh_task_list() -> void:
	for child: Node in _task_rows.get_children():
		_task_rows.remove_child(child)
		child.queue_free()
	if _task_snapshot.is_empty():
		_task_rows.add_child(_readable_label("暂无进行中的委托"))
		return
	for quest: Dictionary in _task_snapshot.slice(0, 3):
		var id := str(quest.get("id", ""))
		var row := VBoxContainer.new()
		_task_rows.add_child(row)
		row.add_child(_readable_label("%s  %d/%d" % [quest.get("title", "委托"),
				int(quest.get("progress", 0)), int(quest.get("need", 1))]))
		var actions := HBoxContainer.new()
		actions.add_theme_constant_override("separation", 12)
		row.add_child(actions)
		var track := Button.new()
		track.name = "Track_" + id
		track.text = "正在跟踪" if id == _tracked_quest_id else "跟踪此委托"
		track.custom_minimum_size = Vector2(188, 56)
		track.disabled = id == _tracked_quest_id
		track.pressed.connect(_request_quest_action.bind(id, false))
		actions.add_child(track)
		var abandon := Button.new()
		abandon.name = "Abandon_" + id
		abandon.text = "放弃委托"
		abandon.custom_minimum_size = Vector2(148, 56)
		abandon.pressed.connect(_request_quest_action.bind(id, true))
		actions.add_child(abandon)


func _request_quest_action(id: String, abandon: bool) -> void:
	if _task_layer == null or not _task_layer.visible or passive_layer.visible:
		return
	if abandon:
		EventBus.quest_abandon_requested.emit(id)
	else:
		EventBus.quest_track_requested.emit(id)


func _on_equipment_offer_changed() -> void:
	if _equipment_badge != null:
		_equipment_badge.text = "待比较" if not GameState.pending_equipment.is_empty() else ""
	if _inv_layer != null and _inv_layer.visible:
		_refresh_equipment_offer()
		_refresh_equipment()
		_sync_modal_focus()


func _refresh_equipment_offer() -> void:
	if _equipment_offer == null:
		return
	for child: Node in _equipment_offer.get_children():
		_equipment_offer.remove_child(child)
		child.queue_free()
	var candidate: Dictionary = GameState.pending_equipment
	_equipment_offer.visible = not candidate.is_empty()
	if candidate.is_empty():
		return
	var slot := str(candidate.get("slot", "weapon"))
	var current: Dictionary = GameState.stats.equips.get(slot, {})
	var token := GameState.equipment_offer_id
	_equipment_offer.add_child(_readable_label("待比较 · " + str(GameState.SLOT_NAMES.get(slot, slot)), 20))
	_equipment_offer.add_child(_readable_label("当前：" + (GameState.equip_description(current)
			if not current.is_empty() else "空槽") + "\n候选：" + GameState.equip_description(candidate), 16))
	var preview := GameState.stats.preview_equipment(candidate)
	var effect := _benefit_text(preview, true)
	var element_names := {"": "无", "fire": "火焰", "ice": "寒冰"}
	if slot == "weapon":
		effect += "\n武器元素  %s → %s" % [element_names.get(str(current.get("element", "")), "无"),
				element_names.get(str(candidate.get("element", "")), "无")]
	var benefit := _readable_label(effect, 16)
	benefit.name = "EquipmentBenefit"
	_equipment_offer.add_child(benefit)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	_equipment_offer.add_child(actions)
	for equip_new: bool in [true, false]:
		var button := Button.new()
		button.name = "EquipCandidate" if equip_new else "KeepEquipment"
		button.text = "装备候选 / 出售旧件" if equip_new else "保留当前 / 出售候选"
		button.custom_minimum_size = Vector2(268, 60)
		button.add_theme_font_size_override("font_size", 16)
		button.pressed.connect(_resolve_equipment_offer.bind(equip_new, token))
		actions.add_child(button)
	_equipment_offer.add_child(HSeparator.new())


func _resolve_equipment_offer(equip_new: bool, token: int) -> void:
	if _equipment_pick_locked or _inv_layer == null or not _inv_layer.visible or passive_layer.visible:
		return
	_equipment_pick_locked = true
	GameState.resolve_pending_equipment(equip_new, token)
	_refresh_inventory()
	_sync_modal_focus()
	await get_tree().process_frame
	_equipment_pick_locked = false
