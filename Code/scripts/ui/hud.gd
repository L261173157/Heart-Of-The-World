## HUD：血/蓝/经验条、等级金币区域、属性点分配按钮、击杀提示、
## 小地图、生态监测面板。纯订阅 EventBus，不主动查询玩法系统。
extends CanvasLayer

const TOAST_DURATION := 2.0
const TOAST_FADE := 0.5
## 战斗播报：更短生命周期（高频滚动，不给屏面留积压）
const COMBAT_TOAST_DURATION := 1.2
const COMBAT_TOAST_FADE := 0.3

@onready var hp_bar: ProgressBar = %HPBar
@onready var mp_bar: ProgressBar = %MPBar
@onready var xp_bar: ProgressBar = %XPBar
@onready var stats_label: Label = %StatsLabel
@onready var stat_buttons: Control = %StatButtons
@onready var toast_label: Label = %ToastLabel
@onready var ecology_label: Label = %EcologyContent
@onready var ecology_panel: Control = %EcologyPanel
@onready var bounty_label: Label = %BountyLabel
@onready var shop_panel: Control = %ShopPanel
@onready var shop_gold_label: Label = %GoldLabel
@onready var skill_cds: Array = [
	{"panel": %SlotDash, "label": %SlotDash/VB/Cd, "mp": 12.0},
	{"panel": %SlotHeavy, "label": %SlotHeavy/VB/Cd, "mp": 22.0},
	{"panel": %SlotBolt, "label": %SlotBolt/VB/Cd, "mp": 8.0},
	{"panel": %SlotHeal, "label": %SlotHeal/VB/Cd, "mp": 25.0},
]
@onready var night_rect: ColorRect = %NightRect
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
var _cd_values := [0.0, 0.0, 0.0, 0.0]
var _cd_elapsed := 0.0
## 最近已知蓝量（技能槽"蓝不足"置灰用）
var _mp_now := 0.0
## 三选一被动：待选择次数（连升排队）
var _pending_passive_picks := 0
var _night_tween: Tween


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
	%BtnEco.pressed.connect(func() -> void: ecology_panel.visible = not ecology_panel.visible)
	%BtnShop.pressed.connect(_toggle_shop)
	%BtnShopClose.pressed.connect(func() -> void: shop_panel.visible = false)
	%BtnWeapon.pressed.connect(func() -> void: _try_buy("weapon"))
	%BtnStaff.pressed.connect(func() -> void: _try_buy("staff"))
	%BtnVigor.pressed.connect(func() -> void: _try_buy("vigor"))
	EventBus.world_event.connect(func(text: String) -> void: _toast(text))
	EventBus.bounty_updated.connect(func(text: String) -> void: bounty_label.text = text)
	EventBus.bounty_completed.connect(func(text: String) -> void: _toast(text))
	EventBus.player_skills_changed.connect(_on_skills_changed)
	EventBus.achievement_unlocked.connect(func(title: String) -> void: _toast("🏆 成就解锁：%s" % title))
	EventBus.region_threat_warning.connect(_on_threat_warning)
	EventBus.day_phase_changed.connect(_on_day_phase)
	EventBus.player_died.connect(_on_player_died)
	GameState.stats.leveled_up.connect(_on_leveled_up)

	%PauseBtn.pressed.connect(_toggle_pause)
	%ResumeBtn.pressed.connect(_toggle_pause)
	%PauseSettingsBtn.pressed.connect(
		func() -> void: pause_settings_layer.visible = true)
	%PauseSettingsClose.pressed.connect(
		func() -> void: pause_settings_layer.visible = false)
	%MenuBtn.pressed.connect(_back_to_menu)
	%BtnCodex.pressed.connect(_toggle_codex)
	%CodexClose.pressed.connect(func() -> void: codex_layer.visible = false)
	for i in 3:
		passive_cards[i].pressed.connect(_pick_passive.bind(i))
	GameState.stats.leveled_up.connect(func(new_level: int) -> void:
		_toast("升级！Lv.%d   属性点 +1" % new_level)
	)

	toast_label.modulate.a = 0.0
	_setup_combat_toast()
	_apply_theme()
	_apply_safe_area()
	_apply_vignette()
	_on_progress_changed(1, 0, GameState.stats.xp_to_next(), 0)
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


func _toast_combat(message: String) -> void:
	_combat_toast.text = message
	_combat_toast.modulate.a = 1.0
	_combat_toast_timer = COMBAT_TOAST_DURATION


## iOS 刘海/Home 指示条：把 HUD 根收进安全区（无刘海设备安全区=全屏，零影响）。
## Root 的子节点全部相对 Root 定位，缩 Root 即整体内收
func _apply_safe_area() -> void:
	var root := get_node("Root") as Control
	var win := get_window()
	var win_rect := Rect2i(win.position, win.size)
	var safe := DisplayServer.get_display_safe_area().intersection(win_rect)
	if not safe.has_area():
		return
	root.offset_left = safe.position.x - win_rect.position.x
	root.offset_top = safe.position.y - win_rect.position.y
	root.offset_right = safe.end.x - win_rect.end.x
	root.offset_bottom = safe.end.y - win_rect.end.y


# --- 视觉主题（深色玻璃拟态 + 金色强调，代码生成免维护 .tres） ---

func _apply_theme() -> void:
	var theme := Theme.new()
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.07, 0.09, 0.11, 0.88)
	panel.border_color = Color(1.0, 0.85, 0.45, 0.35)
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(8)
	panel.set_content_margin_all(6)
	theme.set_stylebox("panel", "PanelContainer", panel)

	var btn := StyleBoxFlat.new()
	btn.bg_color = Color(0.13, 0.16, 0.2, 0.92)
	btn.border_color = Color(1.0, 0.85, 0.45, 0.5)
	btn.set_border_width_all(1)
	btn.set_corner_radius_all(6)
	btn.set_content_margin_all(6)
	theme.set_stylebox("normal", "Button", btn)

	var btn_hover := btn.duplicate()
	btn_hover.bg_color = Color(0.2, 0.24, 0.3, 0.95)
	btn_hover.border_color = Color(1.0, 0.85, 0.45, 0.9)
	theme.set_stylebox("hover", "Button", btn_hover)

	var btn_disabled := btn.duplicate()
	btn_disabled.bg_color = Color(0.09, 0.1, 0.12, 0.7)
	btn_disabled.border_color = Color(0.5, 0.5, 0.5, 0.3)
	theme.set_stylebox("disabled", "Button", btn_disabled)

	theme.set_color("font_color", "Button", Color(1.0, 0.94, 0.8))
	theme.set_color("font_disabled_color", "Button", Color(0.55, 0.55, 0.55))
	theme.set_color("font_color", "Label", Color(0.94, 0.94, 0.9))
	(get_node("Root") as Control).theme = theme

	# 进度条三色（血/蓝/经验），stylebox 覆盖默认灰条
	var fill_hp := _bar_fill(Color(0.78, 0.22, 0.2))
	var fill_mp := _bar_fill(Color(0.24, 0.5, 0.85))
	var fill_xp := _bar_fill(Color(0.9, 0.75, 0.25))
	hp_bar.add_theme_stylebox_override("fill", fill_hp)
	mp_bar.add_theme_stylebox_override("fill", fill_mp)
	xp_bar.add_theme_stylebox_override("fill", fill_xp)
	for bar: ProgressBar in [hp_bar, mp_bar, xp_bar]:
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0.05, 0.06, 0.08, 0.85)
		bg.set_corner_radius_all(4)
		bar.add_theme_stylebox_override("background", bg)


func _bar_fill(c: Color) -> StyleBoxFlat:
	var fill := StyleBoxFlat.new()
	fill.bg_color = c
	fill.set_corner_radius_all(4)
	return fill


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
	if _toast_timer > 0.0:
		_toast_timer -= delta
		toast_label.modulate.a = clampf(_toast_timer / TOAST_FADE, 0.0, 1.0)
	if _combat_toast_timer > 0.0:
		_combat_toast_timer -= delta
		_combat_toast.modulate.a = clampf(_combat_toast_timer / COMBAT_TOAST_FADE, 0.0, 1.0)
	_cd_elapsed += delta
	_refresh_skill_bar()


## 键盘开关生态面板（Tab）/ 暂停（ESC）；触屏走按钮
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_ecology"):
		ecology_panel.visible = not ecology_panel.visible
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_shop"):
		_toggle_shop()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause"):
		_toggle_pause()
		get_viewport().set_input_as_handled()


# --- 技能冷却条 ---

func _on_skills_changed(dash_cd: float, heavy_cd: float, bolt_cd: float, heal_cd: float,
		mp: float, _max_mp: float) -> void:
	_cd_values = [dash_cd, heavy_cd, bolt_cd, heal_cd]
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
			# 文本差分：%.1f 粒度下约 0.1s 才变一次，避免每帧字符串格式化
			var text := "%.1f" % left
			if label.text != text:
				label.text = text
			label.modulate = Color(1, 0.6, 0.5)
		elif label.text != "就绪":
			label.text = "就绪"
			label.modulate = Color(0.7, 0.95, 0.7)
		# 蓝不足置灰整格：技能按了没反应时玩家需要知道原因
		var panel: Control = slot["panel"]
		if panel != null and is_instance_valid(panel):
			panel.modulate = Color(0.5, 0.5, 0.55) if _mp_now < float(slot["mp"]) else Color.WHITE


# --- 暂停 / 主菜单 ---

func _toggle_pause() -> void:
	var world := get_tree().current_scene
	if world == null or not world is Node2D:
		return
	if passive_layer.visible:
		return  # 三选一未选时不允许暂停卡死流程
	var paused := not get_tree().paused
	get_tree().paused = paused
	if paused:
		# 暂停期间触屏按钮的排队不应在恢复后一次性兑现
		TouchInput.clear_queues()
	pause_layer.visible = paused
	pause_settings_layer.visible = false


func _back_to_menu() -> void:
	get_tree().paused = false
	GameState._save_now()
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


# --- 死亡信息 ---

func _on_player_died() -> void:
	var player := get_tree().get_first_node_in_group("player") as Player
	var killer: String = player.last_killed_by if player != null and player.last_killed_by != "" else "荒野"
	death_label.text = "被 %s 终结\n本局击杀 %d ｜ 损失两成金币\n正在重生…" % [killer, GameState.session_kills]
	death_label.modulate.a = 1.0
	var tween := death_label.create_tween()
	tween.tween_interval(2.2)
	tween.tween_property(death_label, "modulate:a", 0.0, 0.5)


# --- 图鉴与成就 ---

func _toggle_codex() -> void:
	codex_layer.visible = not codex_layer.visible
	if codex_layer.visible:
		_refresh_codex()


func _refresh_codex() -> void:
	var lines: Array[String] = []
	for species_name in ["哥布林", "史莱姆", "野猪", "雪蝎", "兵蚁", "岩甲龟", "蚁后", "龟王"]:
		var kills: int = int(GameState.codex.get(species_name, 0))
		if kills > 0:
			lines.append("✓ %s  累计猎杀 %d" % [species_name, kills])
		else:
			lines.append("？ 未曾猎杀")
	if GameState.stats.equip.is_empty():
		lines.append("— 未装备（猎杀精英/Boss 有几率掉落）")
	else:
		lines.append("— 当前装备：%s" % GameState.equip_description(GameState.stats.equip))
	codex_content.text = "\n".join(lines)
	var ach_lines: Array[String] = []
	for id in AchievementManager.ACHIEVEMENTS:
		var info: Dictionary = AchievementManager.ACHIEVEMENTS[id]
		var mark := "★" if GameState.achievements.has(id) else "☆"
		ach_lines.append("%s %s — %s" % [mark, info["title"], info["desc"]])
	ach_content.text = "\n".join(ach_lines)


# --- 三选一被动（升级赐福） ---

func _on_leveled_up(_new_level: int) -> void:
	_pending_passive_picks += 1
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


func _on_day_phase(night: bool) -> void:
	if _night_tween != null:
		_night_tween.kill()
	_night_tween = night_rect.create_tween()
	var target := 0.45 if night else 0.0
	_night_tween.tween_property(night_rect, "color:a", target, 6.0)
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
	_refresh_shop_btn(%BtnWeapon, "weapon", "武器磨刀", "物理攻击")
	_refresh_shop_btn(%BtnStaff, "staff", "法杖赋能", "魔法攻击")
	_refresh_shop_btn(%BtnVigor, "vigor", "体质淬炼", "生命上限")


func _refresh_shop_btn(btn: Button, kind: String, display: String, effect: String) -> void:
	var level: int = GameState.upgrade_level(kind)
	if level >= GameState.UPGRADE_MAX_LEVEL:
		btn.text = "%s 已满级（%s +%.0f%%）" % [display, effect, level * 15.0]
		btn.disabled = true
		return
	btn.disabled = GameState.gold < GameState.upgrade_cost(kind)
	btn.text = "%s Lv.%d → +%d%% ｜ %d 金币" % [display, level, (level + 1) * 15, GameState.upgrade_cost(kind)]


func _try_buy(kind: String) -> void:
	if GameState.buy_upgrade(kind):
		SfxManager.play("levelup")
		_toast_combat("%s 强化成功！" % GameState.UPGRADE_NAMES[kind])
	else:
		_toast_combat("金币不足（需要 %d）" % GameState.upgrade_cost(kind))
	_refresh_shop()


func _on_hp_changed(current: float, maximum: float) -> void:
	hp_bar.max_value = maximum
	hp_bar.value = current


func _on_mp_changed(current: float, maximum: float) -> void:
	_mp_now = current
	mp_bar.max_value = maximum
	mp_bar.value = current


func _on_progress_changed(level: int, xp: int, xp_needed: int, pending_points: int) -> void:
	xp_bar.max_value = xp_needed
	xp_bar.value = xp
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


## 生态监测面板：每秒刷新各区域种群构成，并对比上一 tick 标注趋势——
## ↑/↓ 总数涨跌，＋ 该区域新出现的物种（扩张/迁入），✕ 上次有而这次没了（灭绝/迁出）
func _on_sim_tick(summary: Dictionary) -> void:
	if not ecology_panel.visible:
		# 面板关闭时跳过整段字符串拼接；趋势基线保持在上次可见的时刻，
		# 重新打开后显示的恰是"这段时间里发生的变化"
		return
	var lines: Array[String] = []
	for region: Dictionary in summary["regions"]:
		var rid: String = region["id"]
		var alive: int = region["alive"]
		var last_total: int = _last_totals.get(rid, alive)
		var trend := "—"
		if alive > last_total:
			trend = "↑"
		elif alive < last_total:
			trend = "↓"
		_last_totals[rid] = alive
		var species_counts: Dictionary = region["species"]
		var last_set: Dictionary = _last_species.get(rid, {})
		var parts: Array[String] = []
		for species_name: String in species_counts:
			var mark := "＋" if not last_set.has(species_name) else ""
			parts.append("%s%s×%d" % [mark, species_name, species_counts[species_name]])
		for species_name: String in last_set:
			if not species_counts.has(species_name):
				parts.append("✕%s" % species_name)
		_last_species[rid] = species_counts.duplicate()
		var detail := " ".join(parts) if not parts.is_empty() else "—"
		lines.append("%s %s%d/%d  %s" % [region["name"], trend, alive, region["capacity"], detail])
	ecology_label.text = "\n".join(lines)


func _on_kill(xp_reward: int, gold_reward: int, monster_name: String) -> void:
	# 击杀走战斗通道：连杀高频滚动时不再挤掉生态事件/引导词
	_toast_combat("击杀 %s   +%d 经验  +%d 金币" % [monster_name, xp_reward, gold_reward])


func _toast(message: String) -> void:
	toast_label.text = message
	toast_label.modulate.a = 1.0
	_toast_timer = TOAST_DURATION
