## 六槽背包：视图只消费 GameState 服务，所有写入携带物品 ID 与修订号。
## 列表按页创建控件；长详情独立滚动，操作条永远留在面板底部。
extends Control

signal close_requested
signal controls_rebuilt
signal input_barrier_requested
signal feedback(message: String)

const Catalog = preload("res://scripts/equipment/equipment_catalog.gd")
const SLOTS := ["weapon", "offhand", "helmet", "armor", "boots", "charm"]
const SLOT_NAMES := {"weapon": "武器", "offhand": "副手", "helmet": "头盔", "armor": "护甲", "boots": "鞋靴", "charm": "饰品"}
const RARITIES := ["白 · 普通", "绿 · 精良", "蓝 · 稀有", "紫 · 史诗", "橙 · 传奇"]
const RARITY_COLORS := [Color("d5dedc"), Color("93cb9d"), Color("91c8f0"), Color("d2aaf1"), Color("ffc16d")]
const PAGE_SIZE := 24
const STAT_NAMES := {"max_hp": "最大生命", "max_mp": "最大精力", "physical": "物理攻击", "magic": "魔法攻击", "hp_regen": "生命恢复 / 秒", "mp_regen": "精力恢复 / 秒", "heal": "治疗回复", "move": "移动速度", "attack_interval": "平均普攻间隔 / 秒", "heavy_cooldown": "重击冷却 / 秒", "lifesteal": "每次命中吸血", "gold": "金币倍率", "xp": "经验倍率", "guard": "格挡强度", "guard_hit_cost": "挡击耗能（20伤害）", "guard_drain": "持续举盾耗能 / 秒", "guard_counter": "满蓄反击倍率", "combo_heal": "第三击生命回复", "heavy_damage": "重击原始伤害", "bolt_damage": "法弹原始伤害", "focus_refund": "法弹命中返能", "bolt_damage_mult": "法弹伤害倍率", "sword_damage_mult": "普攻伤害倍率"}


var input_allowed: Callable
var _snapshot: Dictionary = {}
var _revision := -1
var _serial := 0
var _busy := false
var _tab := "loadout"
var _gear_page := "bag"
var _page := 0
var _pages := 1
var _selected_id := ""
var _selected_slot := "weapon"
var _selected_preset := -1
var _selected_receipt := ""
var _selected_choice := -1
var _filters := {"slot": "", "rarity": -1, "affix": "", "sort": "newest"}
var _tag := "all"
var _batch_mode := false
var _narrow_filters := false
var _batch_ids: Array[String] = []
var _offer_kind := "craft"
var _selected_base := ""
var _offer: Dictionary = {}
var _confirmation: Dictionary = {}
var _status_text := "掉落收入背包；穿脱装备需连续脱战 5 秒"
var _panel: PanelContainer
var _header: Label
var _tabs: HBoxContainer
var _filters_row: HBoxContainer
var _columns: BoxContainer
var _left: VBoxContainer
var _list_scroll: ScrollContainer
var _rows: VBoxContainer
var _detail_scroll: ScrollContainer
var _detail: VBoxContainer
var _pager: HBoxContainer
var _actions: HBoxContainer
var _status: Label
var _confirm_layer: Control
var _confirm_panel: PanelContainer
var _confirm_label: Label
var _confirm_buttons: HBoxContainer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = HotwTheme.glass_theme()
	_build()
	resized.connect(_layout)
	visibility_changed.connect(_visibility_changed)
	_layout()

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.015, 0.025, 0.04, 0.86)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_panel = PanelContainer.new()
	_panel.name = "BagPanel"
	_panel.minimum_size_changed.connect(_relayout_deferred)
	add_child(_panel)
	var style := HotwTheme.panel_style()
	style.bg_color = Color("17232c")
	style.border_color = HotwTheme.GOLD
	style.set_content_margin_all(18)
	_panel.add_theme_stylebox_override("panel", style)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	_panel.add_child(body)
	var top := HBoxContainer.new()
	body.add_child(top)
	var title := _label("行囊与装配", 24, HotwTheme.GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	_header = _label("", 16, HotwTheme.MUTED)
	_header.custom_minimum_size.x = 330
	_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(_header)
	_tabs = HBoxContainer.new()
	_tabs.name = "BagTabs"
	body.add_child(_tabs)
	for spec: Array in [["loadout", "装配"], ["gear", "装备"], ["supplies", "补给 / 材料"], ["pending", "待领取"]]:
		var button := _button("BagTab_" + spec[0], spec[1], _select_tab.bind(spec[0]), 44)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_tabs.add_child(button)
	_filters_row = HBoxContainer.new()
	_filters_row.name = "BagFilters"
	body.add_child(_filters_row)
	_columns = BoxContainer.new()
	_columns.name = "BagColumns"
	_columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_columns.add_theme_constant_override("separation", 16)
	body.add_child(_columns)
	_left = VBoxContainer.new()
	_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_left.size_flags_stretch_ratio = 0.85
	_columns.add_child(_left)
	_list_scroll = _scroll("BagListScroll")
	_list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_left.add_child(_list_scroll)
	_rows = VBoxContainer.new()
	_rows.name = "BagRows"
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_scroll.add_child(_rows)
	_pager = HBoxContainer.new()
	_pager.name = "BagPager"
	_left.add_child(_pager)
	_detail_scroll = _scroll("BagDetailScroll")
	_detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_scroll.size_flags_stretch_ratio = 1.15
	_columns.add_child(_detail_scroll)
	_detail = VBoxContainer.new()
	_detail.name = "BagDetail"
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.add_theme_constant_override("separation", 10)
	_detail_scroll.add_child(_detail)
	body.add_child(HSeparator.new())
	_status = _label("", 15, HotwTheme.MUTED)
	_status.name = "BagStatus"
	_status.max_lines_visible = 2
	body.add_child(_status)
	var footer := HBoxContainer.new()
	footer.name = "BagActionBar"
	body.add_child(footer)
	_actions = HBoxContainer.new()
	_actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_actions)
	var close := _button("InventoryClose", "返回（O）", _request_close, 52)
	close.custom_minimum_size.x = 120
	footer.add_child(close)
	_build_confirmation()

func _build_confirmation() -> void:
	_confirm_layer = Control.new()
	_confirm_layer.name = "BagConfirmation"
	_confirm_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_confirm_layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_confirm_layer.add_child(dim)
	_confirm_panel = PanelContainer.new()
	_confirm_layer.add_child(_confirm_panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 20)
	_confirm_panel.add_child(body)
	_confirm_label = _label("", 20)
	_confirm_label.name = "BagConfirmText"
	body.add_child(_confirm_label)
	_confirm_buttons = HBoxContainer.new()
	body.add_child(_confirm_buttons)
	_confirm_layer.hide()

func _process(_delta: float) -> void:
	# 自动换行的最小尺寸需经过容器排版才稳定，收敛后保持面板的视口边界。
	if visible and _panel != null:
		var expected := Vector2(minf(1200, size.x - 32), minf(684, size.y - 32))
		if not _panel.size.is_equal_approx(expected): _layout()

func _relayout_deferred() -> void:
	_layout.call_deferred()

func _layout() -> void:
	if _panel == null:
		return
	var panel_size := Vector2(minf(1200, size.x - 32), minf(684, size.y - 32))
	_panel.position = (size - panel_size) * 0.5
	_panel.size = panel_size
	# 小屏上下排列，列表与详情都保留自己的真实滚动区。
	var narrow := size.x < 1100
	var changed_layout := _columns.vertical != narrow
	_columns.vertical = narrow
	if changed_layout and visible: refresh.call_deferred()
	_left.size_flags_stretch_ratio = 0.85 if not _columns.vertical else 1.0
	_detail_scroll.size_flags_stretch_ratio = 1.15 if not _columns.vertical else 1.0
	_confirm_panel.position = Vector2(maxf(24, (size.x - 640) * 0.5), maxf(24, (size.y - 290) * 0.5))
	_confirm_panel.size = Vector2(minf(640, size.x - 48), 290)

func refresh() -> void:
	if _panel == null:
		return
	var previous_revision := _revision
	_snapshot = GameState.call("equipment_snapshot") if GameState.has_method("equipment_snapshot") else {}
	_revision = int(_snapshot.get("revision", -1))
	if previous_revision != _revision and not _confirmation.is_empty():
		_cancel_confirmation()
		_status_text = "物品状态已变化，请重新查看后确认"
	_serial += 1
	_header.text = "%d 金币   零件 %d   装备 %d 件" % [int(_snapshot.get("gold", GameState.gold)), _parts(), (_snapshot.get("items", {}) as Dictionary).size()]
	for child: Button in _tabs.get_children():
		child.modulate = HotwTheme.GOLD if str(child.name) == "BagTab_" + _tab else Color.WHITE
	_clear(_filters_row)
	_clear(_rows)
	_clear(_detail)
	_clear(_pager)
	_clear(_actions)
	match _tab:
		"loadout": _render_loadout()
		"gear": _render_gear()
		"supplies": _render_supplies()
		"pending": _render_pending()
	_status.text = _status_text
	if not str(_snapshot.get("migration_notice", "")).is_empty():
		_status.text += " · " + str(_snapshot["migration_notice"])
	controls_rebuilt.emit()
	_layout()

func _parts() -> int:
	var materials: Variant = _snapshot.get("materials", {})
	return int(materials.get("equipment-parts", 0)) if materials is Dictionary else int(materials)

func _render_loadout() -> void:
	var help := _label("六个部位 · 穿脱不补生命、精力，不重置冷却", 16, HotwTheme.MUTED)
	help.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_filters_row.add_child(help)
	_filters_row.add_child(_button("BagParticleSetting", "粒子：精简" if bool(GameState.settings.get("equipment_particles_reduced", false)) else "粒子：完整", _toggle_particles.bind(_revision, _serial), 44))
	var equipped: Dictionary = _snapshot.get("equipped", {})
	for slot: String in SLOTS:
		var id := str(equipped.get(slot, ""))
		var item := _item(id)
		var text := "%s   %s" % [SLOT_NAMES[slot], str(item.get("name", "空槽"))]
		if not item.is_empty():
			text += "\n" + _short_item(item)
		var button := _button("BagSlot_" + slot, text, _select_slot.bind(slot, _serial), 68)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.modulate = HotwTheme.GOLD if _selected_preset < 0 and slot == _selected_slot else Color.WHITE
		_rows.add_child(button)
	_rows.add_child(_label("装配方案 · 三套独立保存", 17, HotwTheme.GOLD))
	for index in 3:
		var preset := _preset(index)
		_rows.add_child(_button("BagPreset_%d" % index, "%d  %s" % [index + 1, str(preset.get("name", "方案 %d" % (index + 1)))], _select_preset.bind(index, _serial), 52))
	if _selected_preset >= 0:
		_render_preset()
		return
	_selected_id = str(equipped.get(_selected_slot, ""))
	if _selected_id.is_empty():
		_detail.add_child(_label(SLOT_NAMES[_selected_slot] + " · 空槽", 23, HotwTheme.GOLD))
		_detail.add_child(_label("在装备页选中一件装备，查看实际收益后再穿戴。新掉落会留在背包。", 17))
		_add_action("BagFindGear", "查看该部位", _browse_slot.bind(_selected_slot))
	else:
		_render_item(_item(_selected_id), false)
		var can_swap := bool(_snapshot.get("can_swap", false))
		_add_action("BagUnequip", "卸下", _perform.bind("unequip", {"slot": _selected_slot}, _revision, _serial), not can_swap, _swap_reason())
		_item_protection_actions(_item(_selected_id))
	if not bool(_snapshot.get("can_swap", false)):
		_detail.add_child(_label(_swap_reason(), 16, Color("ffc16d")))

func _render_preset() -> void:
	var preset := _preset(_selected_preset)
	_detail.add_child(_label("方案 %d · %s" % [_selected_preset + 1, str(preset.get("name", "未命名"))], 23, HotwTheme.GOLD))
	var entries: Dictionary = preset.get("slots", preset.get("equipped", {}))
	for slot: String in SLOTS:
		var id := str(entries.get(slot, ""))
		_detail.add_child(_label("%s：%s" % [SLOT_NAMES[slot], "空槽" if id.is_empty() else str(_item(id).get("name", "缺失装备 · 无法应用"))], 17))
	_detail.add_child(_label("应用前会一次检查整套装备及等级条件；缺件时保持当前整套装配。保存方案不会修改战斗快捷键或恢复预设。", 16, HotwTheme.MUTED))
	var loadout: Dictionary = {}
	var missing := false
	for slot: String in entries:
		var item := _item(str(entries[slot]))
		if item.is_empty(): missing = true
		else: loadout[slot] = item
	if not missing:
		var preview: Dictionary = GameState.stats.preview_loadout(loadout)
		_detail.add_child(_label("整套实际属性  当前 → 应用后", 19, HotwTheme.GOLD))
		for key: String in ["max_hp", "max_mp", "physical", "magic", "move", "heavy_damage", "bolt_damage", "guard"]:
			if preview["before"].has(key) and preview["after"].has(key):
				_detail.add_child(_label("%s  %.2f → %.2f" % [STAT_NAMES[key], float(preview["before"][key]), float(preview["after"][key])], 16))
		var caps: Dictionary = preview.get("cap_details", {})
		if not caps.is_empty(): _detail.add_child(_label(_cap_text(caps), 16, Color("ffc16d")))

	var rename := LineEdit.new()
	rename.name = "BagPresetName"
	rename.placeholder_text = "方案名称（最多 16 字）"
	rename.max_length = 16
	rename.text = str(preset.get("name", "方案 %d" % (_selected_preset + 1)))
	rename.custom_minimum_size.y = 44
	_detail.add_child(rename)
	_add_action("BagPresetSave", "保存当前装配", _ask_preset_save.bind(rename, _selected_preset, _revision, _serial))
	_add_action("BagPresetApply", "应用整套", _perform.bind("preset_apply", {"index": _selected_preset}, _revision, _serial), not bool(_snapshot.get("can_swap", false)), _swap_reason())
	_add_action("BagPresetRename", "重命名", _rename_preset.bind(rename, _selected_preset, _revision, _serial))
	_add_action("BagPresetClear", "清空方案", _ask.bind("preset_clear", {"index": _selected_preset}, "清空这套装配方案？\n只移除方案中的引用，装备仍保留在背包。", "确认清空方案", _revision, _serial))

func _render_gear() -> void:
	for spec: Array in [["bag", "背包装备"], ["buyback", "原价回购"], ["craft", "制作 / 白装"]]:
		var button := _button("BagGear_" + spec[0], spec[1], _select_gear_page.bind(spec[0]), 44)
		button.custom_minimum_size.x = 144
		button.modulate = HotwTheme.GOLD if _gear_page == spec[0] else Color.WHITE
		_filters_row.add_child(button)
	if _gear_page == "bag":
		_filters_row.add_child(_button("BagBatchMode", "退出批量" if _batch_mode else "批量整理", _toggle_batch, 44))
	if _gear_page == "craft":
		_render_craft()
		return
	if size.x < 1100:
		_filters_row.add_child(_button("BagCompactFilters", "收起筛选" if _narrow_filters else "筛选 / 排序", _toggle_narrow_filters, 44))
	if size.x >= 1100 or _narrow_filters:
		var filter_line := HBoxContainer.new()
		filter_line.add_theme_constant_override("separation", 6)
		_rows.add_child(filter_line)
		var slot_choices: Array = [["", "全部部位"]]
		for slot: String in SLOTS:
			slot_choices.append([slot, SLOT_NAMES[slot]])
		filter_line.add_child(_option("BagSlotFilter", slot_choices, _filters.get("slot", ""), _filter_changed.bind("slot")))
		var rarity_choices: Array = [[-1, "全部品质"]]
		for index in RARITIES.size():
			rarity_choices.append([index, RARITIES[index]])
		filter_line.add_child(_option("BagRarityFilter", rarity_choices, _filters.get("rarity", -1), _filter_changed.bind("rarity")))
		var affix_choices: Array = [["", "全部属性"]]
		for key: String in Catalog.CAPS:
			affix_choices.append([key, Catalog.AFFIX_NAMES.get(key, key)])
		filter_line.add_child(_option("BagAffixFilter", affix_choices, _filters.get("affix", ""), _filter_changed.bind("affix")))
		var sort_line := HBoxContainer.new()
		_rows.add_child(sort_line)
		sort_line.add_child(_option("BagSort", [["newest", "最新获得"], ["rarity", "品质优先"], ["level", "等级优先"], ["name", "名称排序"]], _filters.get("sort", "newest"), _filter_changed.bind("sort")))
		sort_line.add_child(_option("BagTagFilter", [["all", "全部标记"], ["favorite", "已收藏"], ["locked", "已锁定"]], _tag, _tag_changed))
	var query_filters := _filters.duplicate()
	query_filters["source"] = _gear_page
	if _tag != "all":
		query_filters[_tag] = true
	var result: Dictionary = GameState.call("equipment_query", query_filters, _page, PAGE_SIZE) if GameState.has_method("equipment_query") else {}
	var items: Array = result.get("items", [])
	_page = int(result.get("page", 0))
	_pages = maxi(1, int(result.get("pages", 1)))
	_render_pager(int(result.get("total", 0)))
	var selected: Dictionary = {}
	for item: Dictionary in items:
		var record_item: Dictionary = item.get("item", item)
		var id := str(record_item.get("id", item.get("id", "")))
		if _selected_id.is_empty():
			_selected_id = id
		if id == _selected_id:
			selected = record_item
		var prefix := ("[选] " if id in _batch_ids else "[  ] ") if _batch_mode and _gear_page == "bag" else ""
		var button := _button("BagItem_" + id, prefix + str(record_item.get("name", "装备")) + "\n" + _short_item(record_item), _select_item.bind(id, _serial), 70)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.modulate = RARITY_COLORS[clampi(int(record_item.get("rarity", 0)), 0, 4)]
		_rows.add_child(button)
	if selected.is_empty() and not items.is_empty():
		var first: Dictionary = items[0]
		selected = first.get("item", first)
		_selected_id = str(selected.get("id", ""))
	if selected.is_empty():
		_detail.add_child(_label("这里还没有装备", 23, HotwTheme.GOLD))
		_detail.add_child(_label("调整筛选条件，或继续探索。装备没有背包格数上限。", 17))
		return
	_render_item(selected, true)
	if _gear_page == "bag" and _batch_mode:
		_render_batch_actions(items)
		return
	if _gear_page == "buyback":
		var price := _buyback_price(_selected_id)
		_detail.add_child(_label("回购价格：%d 金币\n按当时实收原价购回同一件装备；记录不会过期或自动清空。" % price, 17, HotwTheme.GOLD))
		_add_action("BagBuyback", "原价回购 %d金" % price, _perform.bind("buyback", {"id": _selected_id}, _revision, _serial), not _can_trade() or int(_snapshot.get("gold", 0)) < price)
		_add_action("BagBuybackClear", "清空回购记录", _ask.bind("buyback_clear", {}, "永久清空全部 %d 条回购记录？\n清空后无法再购回这些装备，金币不会变化。" % (_snapshot.get("buyback", []) as Array).size(), "确认永久清空", _revision, _serial), not _can_trade())
		return
	var can_swap := bool(_snapshot.get("can_swap", false))
	_add_action("BagEquip", "穿戴", _perform.bind("equip", {"id": _selected_id}, _revision, _serial), not can_swap, _swap_reason())
	_item_protection_actions(selected)
	var refs := _references(_selected_id)
	var protected := bool(selected.get("favorite", false)) or bool(selected.get("locked", false))
	if not refs.is_empty():
		_add_action("BagClearReferences", "移除方案引用", _ask.bind("presets_clear_reference", {"id": _selected_id}, "从%s中移除「%s」的引用？\n装备仍保留。移除后才可另行出售或分解。" % [", ".join(refs), selected.get("name", "装备")], "确认移除引用", _revision, _serial))
	else:
		var price := int(selected.get("sale_price", Catalog.sale_value(selected)))
		var parts := int(selected.get("decompose_parts", Catalog.decompose_value(selected)))
		_add_action("BagSell", "出售 %d金" % price, _ask.bind("sell", {"ids": [_selected_id]}, "出售「%s」获得 %d 金币？\n装备会进入永久回购列表，可按这笔实收原价购回。" % [selected.get("name", "装备"), price], "确认出售", _revision, _serial), protected or not _can_trade())
		_add_action("BagDecompose", "分解 %d零件" % parts, _ask.bind("decompose", {"ids": [_selected_id]}, "永久分解「%s」获得 %d 装备零件？\n分解不可撤销，不会进入回购列表。" % [selected.get("name", "装备"), parts], "确认永久分解", _revision, _serial), protected or not _can_trade())
	if protected:
		_detail.add_child(_label("收藏 / 锁定保护中：请先明确取消标记，才能出售或分解。", 16, Color("ffc16d")))
	if not can_swap:
		_detail.add_child(_label(_swap_reason(), 16, Color("ffc16d")))

func _render_craft() -> void:
	_rows.add_child(_label("先选部位，再检查完整成品", 18, HotwTheme.GOLD))
	for slot: String in SLOTS:
		var button := _button("BagCraftSlot_" + slot, SLOT_NAMES[slot], _select_craft_slot.bind(slot), 48)
		button.modulate = HotwTheme.GOLD if slot == _selected_slot else Color.WHITE
		_rows.add_child(button)
	var kinds := HBoxContainer.new()
	_rows.add_child(kinds)
	kinds.add_child(_button("BagCraftBlue", "蓝装制作", _select_offer_kind.bind("craft"), 48))
	kinds.add_child(_button("BagPurchaseWhite", "基础白装", _select_offer_kind.bind("purchase"), 48))
	if _offer_kind == "purchase":
		var bases: Array = []
		for base_id: String in Catalog.SLOT_BASES.get(_selected_slot, []):
			bases.append([base_id, Catalog.BASES[base_id]["name"]])
		if _selected_base.is_empty() and not bases.is_empty(): _selected_base = str(bases[0][0])
		_rows.add_child(_option("BagBaseChoice", bases, _selected_base, _select_base))
	_offer = GameState.call("equipment_offer", _offer_kind, _selected_slot, _selected_base if _offer_kind == "purchase" else "") if GameState.has_method("equipment_offer") else {}
	# 新报价会持久化并推进修订号；按钮必须绑定报价后的快照。
	_snapshot = GameState.call("equipment_snapshot")
	_revision = int(_snapshot.get("revision", _revision))
	var item: Dictionary = _offer.get("item", {})
	if item.is_empty():
		_detail.add_child(_label(str(_offer.get("error", "暂无可用配方")), 18))
		return
	_render_item(item, true)
	var gold := int(_offer.get("gold", _offer.get("price", 0)))
	var parts := int(_offer.get("parts", 6 if _offer_kind == "craft" else 0))
	_detail.add_child(_label("完整成品已固定；关闭、取消或重开不会重抽。\n物品等级依据已探索的最高地形，当前最高 iLv.%d。" % int(_snapshot.get("max_ilvl", 1)), 16, HotwTheme.MUTED))
	_detail.add_child(_label("成本：%d 金币%s" % [gold, " + %d 装备零件" % parts if parts > 0 else ""], 19, HotwTheme.GOLD))
	var payload := {"token": _offer.get("token", ""), "slot": _selected_slot}
	_add_action("BagCraftCommit", "制作 %d金 + %d零件" % [gold, parts] if _offer_kind == "craft" else "购买白装 %d金" % gold, _perform.bind(_offer_kind, payload, _revision, _serial), not _can_trade() or int(_snapshot.get("gold", 0)) < gold or _parts() < parts)
	_add_action("BagPreferredSlot", "设为掉落偏好", _perform.bind("preferred_slot", {"slot": _selected_slot}, _revision, _serial))
	_detail.add_child(_label("部位偏好影响后续装备奖励的部位倾向，不保证每次掉落。橙装首批只有物理剑、盾牌和法器，其余部位最高为紫装。", 16, HotwTheme.MUTED))

func _render_item(item: Dictionary, compare: bool) -> void:
	var rarity := clampi(int(item.get("rarity", 0)), 0, 4)
	_detail.add_child(_label(str(item.get("name", "装备")), 24, RARITY_COLORS[rarity]))
	_detail.add_child(_label(_short_item(item), 16, HotwTheme.MUTED))
	var id := str(item.get("id", ""))
	var refs := _references(id)
	if not refs.is_empty():
		_detail.add_child(_label("方案引用：" + ", ".join(refs), 16, HotwTheme.GOLD))
	var fixed_raw: Variant = item.get("fixed_affixes", {})
	var fixed: Dictionary = fixed_raw if fixed_raw is Dictionary else {}
	var fixed_lines := _affix_lines(fixed)
	if not fixed_lines.is_empty():
		_detail.add_child(_label("固定主属性\n" + "\n".join(fixed_lines), 17))
	var lines: Array[String] = []
	if bool(item.get("legacy", false)):
		var legacy: Variant = item.get("affixes", {})
		lines = _affix_lines(legacy if legacy is Dictionary else {})
		_detail.add_child(_label("旧制词条（保留原值）\n" + ("无额外词条" if lines.is_empty() else "\n".join(lines)), 17))
	else:
		# affixes 已是固定主属性与随机词条之和；随机区只能读取实际 roll 明细。
		var rolls: Variant = item.get("affix_rolls", [])
		if rolls is Array:
			for roll: Variant in rolls:
				if roll is Dictionary:
					lines.append_array(_affix_lines({str(roll.get("id", "")): roll.get("value", 0)}))
		_detail.add_child(_label("随机词条（名义值）\n" + ("无随机词条" if lines.is_empty() else "\n".join(lines)), 17))
	var mechanism: Variant = item.get("mechanism", "")
	if not str(mechanism).is_empty():
		_detail.add_child(_label("传奇机制 / 代价\n" + _mechanism_text(item), 17, Color("ffc16d")))
	var preview: Dictionary = {}
	if compare and not id.is_empty() and GameState.has_method("equipment_preview"):
		preview = GameState.call("equipment_preview", id)
	if preview.is_empty() or not preview.has("before"):
		preview = GameState.stats.preview_equipment(item) if compare else {"before": GameState.stats.benefit_snapshot(), "after": GameState.stats.benefit_snapshot()}
	var before: Dictionary = preview.get("before", {})
	var after: Dictionary = preview.get("after", {})
	_detail.add_child(HSeparator.new())
	_detail.add_child(_label("实际属性  当前 → 穿戴后" if compare else "当前实际属性", 19, HotwTheme.GOLD))
	for key: String in STAT_NAMES:
		if not before.has(key) or not after.has(key):
			continue
		var old := float(before[key])
		var value := float(after[key])
		if not compare and key not in ["max_hp", "max_mp", "physical", "magic", "move", "attack_interval", "heavy_cooldown", "lifesteal"]:
			continue
		var changed := not is_equal_approx(old, value)
		var text := "%s  %.2f → %.2f  (%+.2f)" % [STAT_NAMES[key], old, value, value - old] if compare else "%s  %.2f" % [STAT_NAMES[key], value]
		var lower_is_better := key in ["attack_interval", "heavy_cooldown", "guard_hit_cost", "guard_drain"]
		var beneficial := (value < old) if lower_is_better else (value > old)
		_detail.add_child(_label(text, 16, (Color("a6d5ac") if beneficial else Color("f1a196")) if changed else HotwTheme.MUTED))
	if str(item.get("slot", "")) == "weapon":
		var element_names := {"": "无", "fire": "火焰", "ice": "寒冰"}
		var current: Dictionary = GameState.stats.equips.get("weapon", {})
		_detail.add_child(_label("武器元素  %s → %s" % [element_names.get(str(current.get("element", "")), "无"), element_names.get(str(item.get("element", "")), "无")], 16))
	var caps: Variant = preview.get("caps", preview.get("cap_details", {}))
	if not compare:
		caps = {}
		for key: String in Catalog.CAPS:
			var value: Dictionary = GameState.stats.equipment_affix_breakdown(key)
			if float(value.get("suppressed", 0)) > 0:
				caps[key] = {"before": value, "after": value}

	if not str(caps).is_empty() and str(caps) != "{}" and str(caps) != "[]":
		_detail.add_child(_label("上限 / 实际生效\n" + _cap_text(caps), 16, Color("ffc16d")))
	_detail.add_child(_label("实际收益来自角色计算公式；词条达到上限时，名义增加不等于实际增加。伤害尚未计入目标抗性与元素克制。", 15, HotwTheme.MUTED))

func _affix_lines(values: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	for key: Variant in values:
		var value: Variant = values[key]
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)): continue
		lines.append("%s  %+0.2f%%" % [Catalog.AFFIX_NAMES.get(str(key), str(key)), float(value) * 100])
	return lines

func _mechanism_text(item: Dictionary) -> String:
	return Catalog.mechanism_description(item)

func _cap_text(caps: Variant) -> String:
	var lines: Array[String] = []
	if caps is Dictionary:
		for key in caps:
			var value: Variant = caps[key]
			if value is Dictionary and value.has("before") and value.has("after"):
				var before: Dictionary = value["before"]
				var after: Dictionary = value["after"]
				lines.append("%s：名义 %.2f%% → %.2f%%\n实际生效 %.2f%% → %.2f%% · 新制上限 %.0f%%\n穿戴后溢出 %.2f%%（不生效）" % [Catalog.AFFIX_NAMES.get(str(key), key), float(before.get("nominal", 0)) * 100, float(after.get("nominal", 0)) * 100, float(before.get("effective", 0)) * 100, float(after.get("effective", 0)) * 100, float(after.get("cap", 0)) * 100, float(after.get("suppressed", 0)) * 100])
				if float(after.get("legacy", 0)) != 0:
					lines.append("其中旧制保留原值 %.2f%%，与新制上限分开计算" % (float(after["legacy"]) * 100))
			elif value is Dictionary:
				lines.append("%s：名义 %s · 生效 %s · 上限 %s" % [Catalog.AFFIX_NAMES.get(str(key), key), value.get("nominal", value.get("raw", "?")), value.get("effective", value.get("actual", "?")), value.get("cap", "?")])
			else:
				lines.append("%s：%s" % [key, value])
	elif caps is Array:
		for value in caps:
			lines.append(str(value))
	return "\n".join(lines)

func _render_supplies() -> void:
	_filters_row.add_child(_label("补给 / 材料每叠最多 99；溢出留在待领取", 16, HotwTheme.MUTED))
	var ids: Array[String] = []
	for kind: String in ["consumable", "material", "key"]:
		for id: String in ItemCatalog.ids_of_kind(kind):
			if GameState.count_item(id) > 0:
				ids.append(id)
	if GameState.count_item("equipment-parts") > 0 and not ids.has("equipment-parts"):
		ids.append("equipment-parts")
	_pages = maxi(1, ceili(float(ids.size()) / PAGE_SIZE))
	_page = clampi(_page, 0, _pages - 1)
	_render_pager(ids.size())
	for id: String in ids.slice(_page * PAGE_SIZE, (_page + 1) * PAGE_SIZE):
		_rows.add_child(_button("BagSupply_" + id, "%s   ×%d" % [_supply_name(id), GameState.count_item(id)], _select_item.bind(id, _serial), 58))
	if not ids.has(_selected_id):
		_selected_id = ids[0] if not ids.is_empty() else ""
	if _selected_id.is_empty():
		_detail.add_child(_label("暂无补给与材料", 22, HotwTheme.GOLD))
		return
	_detail.add_child(_label(_supply_name(_selected_id), 24, HotwTheme.GOLD))
	_detail.add_child(_label("持有 %d / 99" % GameState.count_item(_selected_id), 19))
	_detail.add_child(_label("用于指定部位蓝装制作；每件消耗 6 零件。" if _selected_id == "equipment-parts" else ItemCatalog.desc_of(_selected_id), 17))
	if ItemCatalog.is_consumable(_selected_id):
		_add_action("BagUseSupply", "使用一份", _use_supply.bind(_selected_id, _revision, _serial))
		_detail.add_child(_label("只使用选中的这一份，不修改战斗恢复预设。满生命 / 满精力时不会浪费补给。", 16, HotwTheme.MUTED))
	else:
		_detail.add_child(_label("材料和凭证不会因打开详情而消耗。", 16, HotwTheme.MUTED))

func _render_pending() -> void:
	_filters_row.add_child(_label("持久收据 · 关闭 / 读档不丢失，不重复发奖", 16, HotwTheme.MUTED))
	var receipts: Array = _pending_rows()
	_pages = maxi(1, ceili(float(receipts.size()) / PAGE_SIZE))
	_page = clampi(_page, 0, _pages - 1)
	_render_pager(receipts.size())
	var selected: Dictionary = {}
	for receipt: Dictionary in receipts.slice(_page * PAGE_SIZE, (_page + 1) * PAGE_SIZE):
		var id := str(receipt.get("id", ""))
		if _selected_receipt.is_empty():
			_selected_receipt = id
		_rows.add_child(_button("BagReceipt_" + id, str(receipt.get("title", receipt.get("name", "%s ×%d" % [_supply_name(str(receipt.get("item_id", ""))), int(receipt.get("count", 0))]))), _select_receipt.bind(id, _serial), 64))
		if id == _selected_receipt:
			selected = receipt
	if selected.is_empty() and not receipts.is_empty():
		selected = receipts[0]
		_selected_receipt = str(selected.get("id", ""))
	if selected.is_empty():
		_detail.add_child(_label("奖励都已收好", 23, HotwTheme.GOLD))
		_detail.add_child(_label("材料溢出与首领奖励会留在这里，战斗中只显示提醒。", 17))
		return
	_detail.add_child(_label(str(selected.get("title", "待领取奖励")), 23, HotwTheme.GOLD))
	var choices: Array = selected.get("choices", selected.get("items", []))
	if bool(selected.get("first_boss", false)) or not choices.is_empty():
		_detail.add_child(_label("世界线首领奖励 · 三选一橙装\n选择前可比较；确定后其余两件放弃。", 17))
		for index in choices.size():
			var item: Dictionary = choices[index]
			var button := _button("BagBossChoice_%d" % index, str(item.get("name", "候选装备")), _select_choice.bind(index, _serial), 48)
			button.modulate = HotwTheme.GOLD if _selected_choice == index else Color.WHITE
			_detail.add_child(button)
		if _selected_choice >= 0 and _selected_choice < choices.size():
			var item: Dictionary = choices[_selected_choice]
			_render_item(item, true)
			_add_action("BagBossClaim", "选择并领取", _ask.bind("first_boss_choose", {"id": str(item.get("id", "")), "index": _selected_choice}, "选择「%s」？\n它将进入背包，此收据中的其余两件不会领取。" % item.get("name", "橙装"), "确认选择并领取", _revision, _serial))
		return
	var item_id := str(selected.get("item_id", selected.get("item", "")))
	_detail.add_child(_label("%s ×%d" % [_supply_name(item_id), int(selected.get("count", selected.get("remaining", 0)))], 20))
	_detail.add_child(_label("按当前空余叠数领取，余量继续留在这张收据。无需一次领完。", 17, HotwTheme.MUTED))
	_add_action("BagClaimPending", "领取可装部分", _perform.bind("claim_pending", {"id": _selected_receipt}, _revision, _serial))

func _pending_rows() -> Array:
	var rows: Array = []
	var pending: Variant = _snapshot.get("pending", [])
	if pending is Array:
		for receipt: Variant in pending:
			if receipt is Dictionary:
				rows.append(receipt)
	var boss: Variant = _snapshot.get("first_boss_choices", [])
	if boss is Array and not boss.is_empty():
		rows.push_front({"id": "first_boss", "title": "首领橙装 · 三选一", "choices": boss, "first_boss": true})
	elif boss is Dictionary and not boss.is_empty():
		var row: Dictionary = boss.duplicate(true)
		row["first_boss"] = true
		row["id"] = row.get("id", "first_boss")
		row["title"] = "首领橙装 · 三选一"
		rows.push_front(row)
	return rows

func _render_pager(total: int) -> void:
	var previous := _button("BagPreviousPage", "上一页", _change_page.bind(-1), 44)
	previous.disabled = _page <= 0
	_pager.add_child(previous)
	var label := _label("%d / %d · %d 件" % [_page + 1, _pages, total], 15, HotwTheme.MUTED)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pager.add_child(label)
	var next := _button("BagNextPage", "下一页", _change_page.bind(1), 44)
	next.disabled = _page + 1 >= _pages
	_pager.add_child(next)

func _item_protection_actions(item: Dictionary) -> void:
	var id := str(item.get("id", ""))
	var favorite := bool(item.get("favorite", false))
	var locked := bool(item.get("locked", false))
	_add_action("BagFavorite", "取消收藏" if favorite else "收藏", _perform.bind("favorite", {"id": id, "value": not favorite}, _revision, _serial))
	_add_action("BagLock", "解除锁定" if locked else "锁定", _perform.bind("lock", {"id": id, "value": not locked}, _revision, _serial))

func _add_action(node_name: String, text: String, action: Callable, disabled := false, reason := "") -> void:
	var button := _button(node_name, text, action, 52)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.disabled = disabled
	button.tooltip_text = reason
	_actions.add_child(button)

func _perform(action: String, payload: Dictionary, revision: int, serial: int) -> void:
	if not _valid(serial, revision) or not GameState.has_method("equipment_action"):
		return
	_busy = true
	_cancel_confirmation()
	var result: Dictionary = GameState.call("equipment_action", action, payload, revision)
	_status_text = str(result.get("message", "操作完成")) if bool(result.get("ok", false)) else _error_text(str(result.get("error", "操作未完成")))
	feedback.emit(_status_text)
	refresh()
	input_barrier_requested.emit()
	_unlock.call_deferred()

func _unlock() -> void:
	_busy = false

func _ask(action: String, payload: Dictionary, question: String, confirm_text: String, revision: int, serial: int) -> void:
	if not _valid(serial, revision):
		return
	_confirmation = {"action": action, "payload": payload.duplicate(true), "revision": revision, "serial": serial}
	_confirm_label.text = question
	_clear(_confirm_buttons)
	var cancel := _button("BagConfirmCancel", "取消 / 返回", _cancel_confirmation, 56)
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_confirm_buttons.add_child(cancel)
	var confirm := _button("BagConfirmAccept", confirm_text, _confirm_action.bind(serial, revision), 56)
	confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_confirm_buttons.add_child(confirm)
	_confirm_layer.show()
	controls_rebuilt.emit()
	input_barrier_requested.emit()
	cancel.grab_focus()

func _confirm_action(serial: int, revision: int) -> void:
	if _confirmation.is_empty() or not _valid(serial, revision):
		return
	var action := str(_confirmation.get("action", ""))
	var payload: Dictionary = _confirmation.get("payload", {}).duplicate(true)
	payload["confirmed"] = true
	_perform(action, payload, revision, serial)

func _cancel_confirmation() -> void:
	_confirmation = {}
	if _confirm_layer != null:
		_confirm_layer.hide()
	controls_rebuilt.emit()

func cancel_confirmation() -> bool:
	if _confirmation.is_empty():
		return false
	_cancel_confirmation()
	input_barrier_requested.emit()
	return true

func confirmation_active() -> bool:
	return not _confirmation.is_empty()

func _valid(serial: int, revision: int) -> bool:
	return is_visible_in_tree() and not _busy and serial == _serial and revision == _revision and _allowed()

func _allowed() -> bool:
	return is_visible_in_tree() and (not input_allowed.is_valid() or bool(input_allowed.call()))

func _select_tab(tab: String) -> void:
	if not _allowed(): return
	_tab = tab
	_reset_selection()
	refresh()
	input_barrier_requested.emit()

func _select_gear_page(page: String) -> void:
	if not _allowed(): return
	_gear_page = page
	_reset_selection()
	refresh()
	input_barrier_requested.emit()

func _select_slot(slot: String, serial: int) -> void:
	if not _valid(serial, _revision): return
	_selected_slot = slot
	_selected_preset = -1
	_detail_scroll.scroll_vertical = 0
	refresh()

func _select_preset(index: int, serial: int) -> void:
	if not _valid(serial, _revision): return
	_selected_preset = index
	_detail_scroll.scroll_vertical = 0
	refresh()

func _select_item(id: String, serial: int) -> void:
	if not _valid(serial, _revision): return
	_selected_id = id
	if _batch_mode and _tab == "gear" and _gear_page == "bag":
		if _batch_ids.has(id):
			_batch_ids.erase(id)
		elif _can_batch_item(_item(id)):
			_batch_ids.append(id)
		else:
			_status_text = "已排除收藏、锁定或方案引用的装备"
	_detail_scroll.scroll_vertical = 0
	refresh()

func _select_receipt(id: String, serial: int) -> void:
	if not _valid(serial, _revision): return
	_selected_receipt = id
	_selected_choice = -1
	refresh()

func _select_choice(index: int, serial: int) -> void:
	if not _valid(serial, _revision): return
	_selected_choice = index
	refresh()

func _select_craft_slot(slot: String) -> void:
	if not _allowed(): return
	_selected_slot = slot
	_selected_base = ""
	refresh()

func _select_base(value: Variant) -> void:
	_selected_base = str(value)
	refresh()

func _select_offer_kind(kind: String) -> void:
	if not _allowed(): return
	_offer_kind = kind
	refresh()

func _browse_slot(slot: String) -> void:
	_tab = "gear"
	_gear_page = "bag"
	_filters["slot"] = slot
	_reset_selection()
	refresh()

func _toggle_narrow_filters() -> void:
	_narrow_filters = not _narrow_filters
	refresh()

func _filter_changed(value: Variant, key: String) -> void:
	_filters[key] = value
	_narrow_filters = false
	_reset_selection()
	refresh()

func _tag_changed(value: Variant) -> void:
	_tag = str(value)
	_narrow_filters = false
	_reset_selection()
	refresh()

func _change_page(direction: int) -> void:
	if not _allowed(): return
	_page = clampi(_page + direction, 0, _pages - 1)
	_selected_id = ""
	_selected_receipt = ""
	_list_scroll.scroll_vertical = 0
	_cancel_confirmation()
	refresh()
	input_barrier_requested.emit()

func _ask_preset_save(field: LineEdit, index: int, revision: int, serial: int) -> void:
	if not is_instance_valid(field): return
	_ask("preset_save", {"index": index, "name": field.text}, "将当前六槽装配保存到方案 %d？\n这会覆盖该方案原有的装备引用。" % (index + 1), "确认保存装配", revision, serial)

func _rename_preset(field: LineEdit, index: int, revision: int, serial: int) -> void:
	if not is_instance_valid(field): return
	_perform("preset_rename", {"index": index, "name": field.text}, revision, serial)

func _toggle_particles(revision: int, serial: int) -> void:
	if not _valid(serial, revision): return
	GameState.set_setting("equipment_particles_reduced", not bool(GameState.settings.get("equipment_particles_reduced", false)))
	refresh()

func _toggle_batch() -> void:
	if not _allowed(): return
	_batch_mode = not _batch_mode
	_batch_ids.clear()
	refresh()

func _can_batch_item(item: Dictionary) -> bool:
	return not item.is_empty() and not bool(item.get("favorite", false)) and not bool(item.get("locked", false)) and not bool(item.get("quarantined", false)) and str(item.get("id", "")) not in (_snapshot.get("equipped", {}) as Dictionary).values() and _references(str(item.get("id", ""))).is_empty()

func _render_batch_actions(items: Array) -> void:
	var page_ids: Array[String] = []
	for item: Dictionary in items:
		if _can_batch_item(item): page_ids.append(str(item.get("id", "")))
	_filters_row.add_child(_button("BagSelectPage", "选本页可处理项", _select_batch_page.bind(page_ids, _serial), 44))
	var valid_ids: Array[String] = []
	var gold := 0
	var parts := 0
	for id: String in _batch_ids:
		var item := _item(id)
		if _can_batch_item(item):
			valid_ids.append(id)
			gold += Catalog.sale_value(item)
			parts += Catalog.decompose_value(item)
	_batch_ids = valid_ids
	_detail.add_child(_label("批量选择 %d 件；收藏、锁定与方案引用自动排除。\n出售和分解分别确认，绝不混在同一动作。" % valid_ids.size(), 17, HotwTheme.GOLD))
	var disabled := valid_ids.is_empty() or not _can_trade()
	_add_action("BagBatchSell", "出售 %d件 / %d金" % [valid_ids.size(), gold], _ask.bind("sell", {"ids": valid_ids.duplicate()}, "出售所选 %d 件装备，获得 %d 金币？\n全部进入永久原价回购列表。" % [valid_ids.size(), gold], "确认批量出售", _revision, _serial), disabled)
	_add_action("BagBatchDecompose", "分解 %d件 / %d零件" % [valid_ids.size(), parts], _ask.bind("decompose", {"ids": valid_ids.duplicate()}, "永久分解所选 %d 件装备，获得 %d 零件？\n不可撤销，不进入回购列表；溢出的零件保留在待领取。" % [valid_ids.size(), parts], "确认永久分解", _revision, _serial), disabled)

func _select_batch_page(ids: Array[String], serial: int) -> void:
	if not _valid(serial, _revision): return
	for id: String in ids:
		if not _batch_ids.has(id): _batch_ids.append(id)
	refresh()

func _use_supply(id: String, revision: int, serial: int) -> void:
	if not _valid(serial, revision): return
	_busy = true
	EventBus.item_use_requested.emit(id)
	refresh()
	input_barrier_requested.emit()
	_unlock.call_deferred()

func _reset_selection() -> void:
	_page = 0
	_batch_ids.clear()
	_selected_id = ""
	_selected_receipt = ""
	_selected_choice = -1
	_selected_preset = -1
	_cancel_confirmation()
	_list_scroll.scroll_vertical = 0
	_detail_scroll.scroll_vertical = 0

func _request_close() -> void:
	if cancel_confirmation(): return
	close_requested.emit()

func _visibility_changed() -> void:
	if not visible:
		_cancel_confirmation()
		_serial += 1
		_busy = false

func _item(id: String) -> Dictionary:
	return (_snapshot.get("items", {}) as Dictionary).get(id, {})

func _preset(index: int) -> Dictionary:
	var presets: Array = _snapshot.get("presets", [])
	return presets[index] if index >= 0 and index < presets.size() and presets[index] is Dictionary else {}

func _references(id: String) -> PackedStringArray:
	var refs := PackedStringArray()
	if id.is_empty(): return refs
	for index in 3:
		var preset := _preset(index)
		var slots: Dictionary = preset.get("slots", preset.get("equipped", {}))
		if id in slots.values(): refs.append(str(preset.get("name", "方案 %d" % (index + 1))))
	return refs

func _buyback_price(id: String) -> int:
	for record: Dictionary in _snapshot.get("buyback", []):
		if str(record.get("id", (record.get("item", {}) as Dictionary).get("id", ""))) == id:
			return int(record.get("price", record.get("gold", 0)))
	return 0

func _short_item(item: Dictionary) -> String:
	var text := "%s · %s · iLv.%d · 需求 Lv.%d" % [SLOT_NAMES.get(str(item.get("slot", "")), "装备"), RARITIES[clampi(int(item.get("rarity", 0)), 0, 4)].split(" · ")[0], int(item.get("item_level", 1)), int(item.get("required_level", 1))]
	if bool(item.get("favorite", false)): text += " · 收藏"
	if bool(item.get("locked", false)): text += " · 锁定"
	if not _references(str(item.get("id", ""))).is_empty(): text += " · 方案"
	return text

func _supply_name(id: String) -> String:
	return "装备零件" if id == "equipment-parts" else ItemCatalog.name_of(id)

func _swap_reason() -> String:
	return str(_snapshot.get("swap_reason", "需连续脱战 5 游戏秒，且无攻击、受击、追击或在途技能；暂停不会推进计时"))

func _can_trade() -> bool:
	return bool(_snapshot.get("can_trade", true))

func _error_text(error: String) -> String:
	return {"stale_revision": "装备状态已变化，请重新查看后操作", "combat": _swap_reason(), "in_combat": _swap_reason(), "locked": "装备已锁定，请先解除锁定", "favorite": "装备已收藏，请先取消收藏", "preset_reference": "请先明确移除方案引用", "insufficient_gold": "金币不足", "insufficient_materials": "装备零件不足", "unsafe_loadout": _swap_reason(), "requirement": "角色等级不足或装备不可穿戴", "read_only": "更新版本存档只读，无法修改", "full_stack": "物品叠数已满，请先腾出空间", "missing_preset_item": "方案中有缺失装备，整套装配保持不变", "required_level": "角色等级不足", "missing_item": "装备已不在背包，请重新选择", "equipped": "请先卸下这件装备", "confirmation_required": "请先确认该操作"}.get(error, error)

func _button(node_name: String, text: String, action: Callable, height: float) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.clip_text = true
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.custom_minimum_size = Vector2(144, height)
	button.add_theme_font_size_override("font_size", 16)
	button.set_script(preload("res://scripts/ui/reading_action_button.gd"))
	button.set("input_allowed", _button_allowed.bind(button))
	button.pressed.connect(action)
	return button

func _button_allowed(button: Button) -> bool:
	return _allowed() and not _busy and _owns_pointer_or_free(button) and (not confirmation_active() or _confirm_layer.is_ancestor_of(button))

func _option(node_name: String, choices: Array, selected: Variant, action: Callable) -> OptionButton:
	var button := OptionButton.new()
	button.name = node_name
	button.custom_minimum_size = Vector2(130, 44)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 15)
	for index in choices.size():
		button.add_item(str(choices[index][1]))
		button.set_item_metadata(index, choices[index][0])
		if choices[index][0] == selected:
			button.select(index)
	button.item_selected.connect(func(index: int) -> void: action.call(button.get_item_metadata(index)))
	return button

func _label(text: String, font_size := 17, color := HotwTheme.TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _scroll(node_name: String) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.set_script(preload("res://scripts/ui/equipment_scroll.gd"))
	scroll.set("input_allowed", _scroll_allowed.bind(scroll))
	scroll.name = node_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.scroll_deadzone = 10
	return scroll

func _scroll_allowed(scroll: ScrollContainer) -> bool:
	return _allowed() and not _busy and not confirmation_active() and _owns_pointer_or_free(scroll)

func _owns_pointer_or_free(control: Control) -> bool:
	for scroll: ScrollContainer in [_list_scroll, _detail_scroll]:
		if scroll == null: continue
		var owner_id := int(scroll.get_meta(&"mobile_action_touch_owner", 0))
		if owner_id != 0 and is_instance_id_valid(owner_id) and owner_id != control.get_instance_id(): return false
	return true

func _clear(node: Node) -> void:
	for child: Node in node.get_children():
		node.remove_child(child)
		child.queue_free()
