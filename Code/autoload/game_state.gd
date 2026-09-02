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


# --- 游商营地（金币 → 永久强化的消费出口） ---

## 装备：稀有度名（0~3）
const RARITY_NAMES := ["普通", "精良", "稀有", "史诗"]
const EQUIP_PREFIX := ["猎手", "龙鳞", "霜刃", "灰烬", "蚁噬", "龟甲", "夜枭", "荒野"]
const EQUIP_SUFFIX := ["之刃", "之核", "鳞甲", "獠牙", "护符"]
## 词条池：id -> [最小值, 最大值]（比例）；稀有度线性放大
const EQUIP_AFFIXES := {
	"atk": [0.05, 0.18], "hp": [0.05, 0.20], "cdr": [0.03, 0.10],
	"lifesteal": [0.02, 0.06], "move": [0.04, 0.12],
	"gold": [0.05, 0.15], "xp": [0.04, 0.12],
}


## 随机生成一件装备（rarity 0~3）：2 条不重复词条 + 稀有度以上 35% 带元素
func roll_equipment(rarity: int) -> Dictionary:
	rarity = clampi(rarity, 0, 3)
	var affixes := {}
	var pool: Array = EQUIP_AFFIXES.keys()
	pool.shuffle()
	for i in mini(2, pool.size()):
		var id: String = pool[i]
		var rangev: Array = EQUIP_AFFIXES[id]
		var t := (0.5 + 0.5 * rarity / 3.0)  # 稀有度抬升词条区间
		affixes[id] = lerpf(float(rangev[0]), float(rangev[1]), t * randf())
	var item := {
		"name": "%s%s" % [EQUIP_PREFIX[randi() % EQUIP_PREFIX.size()],
			EQUIP_SUFFIX[randi() % EQUIP_SUFFIX.size()]],
		"rarity": rarity,
		"affixes": affixes,
	}
	if rarity >= 2 and randf() < 0.35:
		item["element"] = "fire" if randf() < 0.5 else "ice"
	return item


## 掉落结算：评分更高则替换当前装备返回 true；否则折 30 金返回 false
func try_equip(item: Dictionary) -> bool:
	if stats.equip_score(item) > stats.equip_score(stats.equip):
		stats.equip = item
		stats.changed.emit()
		_queue_save()
		return true
	add_gold(30)
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
		"equip": stats.equip,
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
	var saved_equip: Variant = data.get("equip", {})
	if typeof(saved_equip) == TYPE_DICTIONARY:
		stats.equip = saved_equip
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
