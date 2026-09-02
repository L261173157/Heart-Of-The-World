## 玩家全局进度状态（autoload 单例）。
## 持有角色养成数据（等级/经验/属性点/金币）与本地存档（M1 起启用）。
## 数值变更后通过 EventBus 广播，HUD 等表现层只订阅不轮询；
## 进度变化防抖自动落盘 user://save.json，退后台/退出时立即保存。
extends Node

## 存档路径：var 而非 const，测试场景可指向沙盒路径避免覆盖真实进度
var SAVE_PATH := "user://save.json"
const SAVE_DEBOUNCE := 2.0

## stats 对象被重建（reset_all）时通知常驻订阅者（如 SfxManager）重连信号
signal stats_rebuilt

var stats: CharacterStats
var gold: int = 0
## 测试场景可关闭存档，避免污染真实进度
var save_enabled: bool = true
## 新手引导完成标志（tutorial.gd 写入，随存档持久化）
var tutorial_flags: Dictionary = {}
## 图鉴：物种 → 累计击杀数（monster_killed_by_player 时自动记录）
var codex: Dictionary = {}
## 已解锁成就 id → true
var achievements: Dictionary = {}
## 设置（主菜单/暂停菜单写入）：音量 0~1、震屏、伤害数字
var settings: Dictionary = {"volume": 0.8, "screen_shake": true, "damage_numbers": true}
## 本局击杀数（死亡信息/统计用）
var session_kills: int = 0

var _save_timer := 0.0
## 寿命警告已触发过的阈值（避免重复播报；读档按剩余寿命重建）
var _lifespan_warned: Array = []

## 游商营地：永久强化（金币消费出口），每类上限 5 级
const UPGRADE_MAX_LEVEL := 5
const UPGRADE_KINDS := ["weapon", "staff", "vigor"]
const UPGRADE_NAMES := {
	"weapon": "武器磨刀", "staff": "法杖赋能", "vigor": "体质淬炼",
}


func _ready() -> void:
	stats = CharacterStats.new()
	stats.changed.connect(_on_stats_changed)
	_load()
	# 无档首启也要应用默认设置（否则音量保持系统 100% 直到手动动滑条）
	_apply_settings()
	# 图鉴/击杀统计：订阅击杀信号自动记录
	EventBus.monster_killed_by_player.connect(_on_kill_record)
	# 寿命：游戏日推进 + 倒下缩短（策划：死亡缩短寿命）
	EventBus.game_day_advanced.connect(_on_game_day)
	EventBus.player_died.connect(_on_player_died_lifespan)


## 新游戏日：角色寿命 -1 天，剩余不多时一次性预警
func _on_game_day(_day: int) -> void:
	stats.age_days += 1.0
	var left: float = stats.lifespan_remaining()
	for threshold in [10.0, 5.0, 1.0]:
		if left <= threshold and not _lifespan_warned.has(threshold):
			_lifespan_warned.append(threshold)
			EventBus.hint_requested.emit("⏳ 岁月不饶人：剩余寿命 %d 天（升级可延长）" % int(ceil(maxf(left, 0.0))))
	_queue_save()


## 倒下缩短寿命（与掉金币同为死亡代价；寿命归零后进入风烛残年而非删除）
func _on_player_died_lifespan() -> void:
	stats.lifespan_days = maxf(0.0, stats.lifespan_days - CharacterStats.DEATH_LIFESPAN_LOSS)
	stats.changed.emit()
	_queue_save()


func _on_kill_record(_xp: int, _gold: int, monster_name: String) -> void:
	session_kills += 1
	var species_name := monster_name.get_slice("#", 0)
	if species_name.begins_with("精英·"):
		species_name = species_name.trim_prefix("精英·")
	codex[species_name] = codex.get(species_name, 0) + 1
	_queue_save()


func _process(delta: float) -> void:
	if _save_timer > 0.0:
		_save_timer -= delta
		if _save_timer <= 0.0:
			_save_now()


## iOS 退后台必须立即落盘（进程随时可能被系统杀死）
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_now()


func add_xp(amount: int) -> void:
	stats.add_xp(amount)


## 属性点分配：strength / agility / intellect
func allocate(stat_name: String) -> void:
	if stats.pending_points <= 0:
		return
	if not stat_name in ["strength", "agility", "intellect"]:
		return
	stats.set(stat_name, stats.get(stat_name) + 1)
	stats.pending_points -= 1
	stats.changed.emit()


func add_gold(amount: int) -> void:
	# 贪婪被动只放大获取，不放大损失（负数直通）
	if amount > 0:
		amount = int(amount * stats.gold_mult())
	gold += amount
	EventBus.gold_changed.emit(gold)
	_queue_save()


# --- 游商营地（金币 → 永久强化的消费出口） + 装备掉落 ---

## 装备：稀有度名（0~3）
const RARITY_NAMES := ["普通", "精良", "稀有", "史诗"]
## 四槽位（策划纲要：头盔/衣服/鞋子 + 武器），各自独立单件替换
const EQUIP_SLOTS := ["weapon", "helmet", "armor", "boots"]
const SLOT_NAMES := {"weapon": "武器", "helmet": "头盔", "armor": "衣服", "boots": "鞋子"}
const EQUIP_PREFIX := ["猎手", "龙鳞", "霜刃", "灰烬", "蚁噬", "龟甲", "夜枭", "荒野"]
const EQUIP_SUFFIX := {"weapon": ["之刃", "之核", "獠牙"], "helmet": ["战冠", "面甲", "兜帽"],
	"armor": ["鳞甲", "护胸", "皮衣"], "boots": ["之履", "胫甲", "便鞋"]}
## 按部位的词条池：id -> [最小值, 最大值]（比例）；稀有度线性放大。
## 武器偏输出 / 头盔偏效用 / 衣服偏生存 / 鞋子保底移速（策划：鞋子=移速+1条随机）
const EQUIP_AFFIXES := {
	"weapon": {"atk": [0.05, 0.18], "cdr": [0.03, 0.10], "lifesteal": [0.02, 0.06],
		"xp": [0.04, 0.12], "gold": [0.05, 0.15]},
	"helmet": {"hp": [0.05, 0.20], "xp": [0.04, 0.12], "gold": [0.05, 0.15],
		"cdr": [0.03, 0.10]},
	"armor": {"hp": [0.05, 0.20], "lifesteal": [0.02, 0.06], "atk": [0.03, 0.10]},
	"boots": {"move": [0.04, 0.12], "hp": [0.03, 0.10], "gold": [0.04, 0.10]},
}


## 随机生成一件指定槽位的装备（rarity 0~3）：2 条不重复词条（鞋子 = 移速 + 1 条随机）；
## 元素附魔只在武器槽且稀有度以上 35% 出
func roll_equipment(rarity: int, slot := "weapon") -> Dictionary:
	rarity = clampi(rarity, 0, 3)
	slot = slot if slot in EQUIP_SLOTS else "weapon"
	var affixes := {}
	var pool: Array = EQUIP_AFFIXES[slot].keys()
	pool.shuffle()
	if slot == "boots":
		affixes["move"] = _roll_affix(slot, "move", rarity)
		pool.erase("move")
	# 词条数：常规 2 条；鞋子为 移速 + 1 条随机（合计 2）
	var count := mini(1 if slot == "boots" else 2, pool.size())
	for i in count:
		var id: String = pool[i]
		affixes[id] = _roll_affix(slot, id, rarity)
	var suffixes: Array = EQUIP_SUFFIX[slot]
	var item := {
		"slot": slot,
		"name": "%s%s" % [EQUIP_PREFIX[randi() % EQUIP_PREFIX.size()],
			suffixes[randi() % suffixes.size()]],
		"rarity": rarity,
		"affixes": affixes,
	}
	if slot == "weapon" and rarity >= 2 and randf() < 0.35:
		item["element"] = "fire" if randf() < 0.5 else "ice"
	return item


func _roll_affix(slot: String, id: String, rarity: int) -> float:
	var rangev: Array = EQUIP_AFFIXES[slot][id]
	var t := (0.5 + 0.5 * rarity / 3.0)  # 稀有度抬升词条区间
	return lerpf(float(rangev[0]), float(rangev[1]), t * randf())


## 掉落结算：按物品槽位比较评分，更高则替换该槽返回 true；否则按稀有度折金返回 false
func try_equip(item: Dictionary) -> bool:
	var slot := str(item.get("slot", "weapon"))
	if not slot in EQUIP_SLOTS:
		slot = "weapon"
	var current: Dictionary = stats.equips.get(slot, {})
	if stats.equip_score(item) > stats.equip_score(current):
		stats.equips[slot] = item
		stats.changed.emit()
		_queue_save()
		return true
	add_gold(20 + int(item.get("rarity", 0)) * 10)
	return false


## 装备描述文本（HUD 图鉴/掉落 toast 用）
func equip_description(item: Dictionary) -> String:
	var names := {"atk": "攻击", "hp": "生命", "cdr": "冷却", "lifesteal": "吸血",
		"move": "移速", "gold": "金币", "xp": "经验"}
	var parts: Array[String] = []
	for key in item.get("affixes", {}):
		parts.append("%s+%.0f%%" % [names.get(key, key), float(item["affixes"][key]) * 100.0])
	var element := str(item.get("element", ""))
	if element != "":
		parts.append("火焰附魔" if element == "fire" else "寒冰附魔")
	return "%s·%s [%s]" % [RARITY_NAMES[clampi(int(item.get("rarity", 0)), 0, RARITY_NAMES.size() - 1)], item.get("name", "?"), " ".join(parts)]


func upgrade_level(kind: String) -> int:
	var value: Variant = stats.get("upgrade_%s" % kind)
	return int(value) if value != null else 0


func upgrade_cost(kind: String) -> int:
	return 50 + upgrade_level(kind) * 40


## 购买一级强化：成功扣钱返回 true；种类非法/满级/钱不够返回 false 不改状态
func buy_upgrade(kind: String) -> bool:
	if not kind in UPGRADE_KINDS:
		return false
	if upgrade_level(kind) >= UPGRADE_MAX_LEVEL:
		return false
	var cost := upgrade_cost(kind)
	if gold < cost:
		return false
	gold -= cost
	stats.set("upgrade_%s" % kind, upgrade_level(kind) + 1)
	EventBus.gold_changed.emit(gold)
	stats.changed.emit()
	_queue_save()
	return true


func set_tutorial_flag(key: String) -> void:
	if tutorial_flags.has(key):
		return
	tutorial_flags[key] = true
	_queue_save()


## 设置应用（音量即时生效）与写入
func set_setting(key: String, value) -> void:
	settings[key] = value
	_apply_settings()
	_queue_save()


## 重置世界：清空全部进度（主菜单"重置世界"）
func reset_all() -> void:
	stats = CharacterStats.new()
	stats.changed.connect(_on_stats_changed)
	gold = 0
	tutorial_flags = {}
	codex = {}
	achievements = {}
	session_kills = 0
	_lifespan_warned.clear()
	_save_now()
	stats_rebuilt.emit()
	EventBus.player_progress_changed.emit(stats.level, stats.xp, stats.xp_to_next(), stats.pending_points)
	EventBus.gold_changed.emit(gold)


func _apply_settings() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(clampf(float(settings.get("volume", 0.8)), 0.0, 1.0)))


func _on_stats_changed() -> void:
	EventBus.player_progress_changed.emit(
		stats.level, stats.xp, stats.xp_to_next(), stats.pending_points
	)
	_queue_save()


# --- 本地存档（JSON，字段级类型校验，坏档安全忽略） ---

func _queue_save() -> void:
	_save_timer = SAVE_DEBOUNCE


func _save_now() -> void:
	_save_timer = 0.0
	if not save_enabled:
		return
	var data := {
		"version": 1,
		"level": stats.level,
		"xp": stats.xp,
		"pending_points": stats.pending_points,
		"strength": stats.strength,
		"agility": stats.agility,
		"intellect": stats.intellect,
		"gold": gold,
		"upgrades": {
			"weapon": stats.upgrade_weapon,
			"staff": stats.upgrade_staff,
			"vigor": stats.upgrade_vigor,
		},
		"passives": stats.passives,
		"equips": stats.equips,
		"age_days": stats.age_days,
		"lifespan_days": stats.lifespan_days,
		"codex": codex,
		"achievements": achievements,
		"settings": settings,
		"tutorial": tutorial_flags,
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("存档写入失败：%s" % SAVE_PATH)
		return
	file.store_string(JSON.stringify(data))
	file.close()


func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("存档损坏，已忽略")
		return
	var data: Dictionary = parsed
	stats.level = maxi(1, int(data.get("level", 1)))
	stats.xp = maxi(0, int(data.get("xp", 0)))
	stats.pending_points = maxi(0, int(data.get("pending_points", 0)))
	stats.strength = maxi(1, int(data.get("strength", 5)))
	stats.agility = maxi(1, int(data.get("agility", 5)))
	stats.intellect = maxi(1, int(data.get("intellect", 5)))
	gold = maxi(0, int(data.get("gold", 0)))
	var saved_upgrades: Variant = data.get("upgrades", {})
	if typeof(saved_upgrades) == TYPE_DICTIONARY:
		for kind in UPGRADE_KINDS:
			stats.set("upgrade_%s" % kind,
				clampi(int(saved_upgrades.get(kind, 0)), 0, UPGRADE_MAX_LEVEL))
	var saved_flags: Variant = data.get("tutorial", {})
	if typeof(saved_flags) == TYPE_DICTIONARY:
		tutorial_flags = saved_flags
	var saved_codex: Variant = data.get("codex", {})
	if typeof(saved_codex) == TYPE_DICTIONARY:
		codex = saved_codex
	var saved_passives: Variant = data.get("passives", {})
	if typeof(saved_passives) == TYPE_DICTIONARY:
		stats.passives = saved_passives
	# 寿命：读档重建（非法值回落默认）；已越过的警告阈值静默补记防重复播报
	stats.age_days = maxf(0.0, float(data.get("age_days", 0.0)))
	stats.lifespan_days = maxf(1.0, float(data.get("lifespan_days", CharacterStats.BASE_LIFESPAN_DAYS)))
	_lifespan_warned.clear()
	for threshold in [10.0, 5.0, 1.0]:
		if stats.lifespan_remaining() <= threshold:
			_lifespan_warned.append(threshold)
	var saved_equips: Variant = data.get("equips", {})
	if typeof(saved_equips) == TYPE_DICTIONARY:
		# 只收合法槽位，旧档遗留字段不带入
		for slot in EQUIP_SLOTS:
			var item: Variant = saved_equips.get(slot, null)
			if typeof(item) == TYPE_DICTIONARY:
				stats.equips[slot] = item
	# 旧档迁移：单件装备时代（"equip" 键）整体视作武器槽
	var legacy_equip: Variant = data.get("equip", null)
	if typeof(legacy_equip) == TYPE_DICTIONARY and not legacy_equip.is_empty() \
			and not stats.equips.has("weapon"):
		stats.equips["weapon"] = legacy_equip
	var saved_achv: Variant = data.get("achievements", {})
	if typeof(saved_achv) == TYPE_DICTIONARY:
		achievements = saved_achv
	var saved_settings: Variant = data.get("settings", {})
	if typeof(saved_settings) == TYPE_DICTIONARY:
		for key in saved_settings:
			settings[key] = saved_settings[key]
	_apply_settings()
	EventBus.player_progress_changed.emit(
		stats.level, stats.xp, stats.xp_to_next(), stats.pending_points
	)
	EventBus.gold_changed.emit(gold)
