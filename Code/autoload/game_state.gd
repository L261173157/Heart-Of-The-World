## 玩家全局进度状态（autoload 单例）。
## 持有角色养成数据（等级/经验/属性点/金币）与本地存档（M1 起启用）。
## 数值变更后通过 EventBus 广播，HUD 等表现层只订阅不轮询；
## 进度变化防抖自动落盘 user://save.json，退后台/退出时立即保存。
extends Node

## 存档路径：var 而非 const，测试场景可指向沙盒路径避免覆盖真实进度
var SAVE_PATH := "user://save.json"
const SAVE_DEBOUNCE := 2.0
## 存档版本：v1 角色侧；v2 增加生态世界；v3 增加角色位置/当前生命与魔法；
## v4（世界 v5）增加 world_seed（每档全新世界）+ 探索进度（explored/discovered）；
## v5 增加 destroyed（已摧毁障碍格）+ quests（任务进度）；
## v6（玩法 v7）增加 inventory（物品栏：消耗品/材料）；
## v7 增加未领取赐福/当前选卡与城塞宝箱领取状态；
## v8 增加装备槽锁定与已发现检查点；
## v9 增加单件待比较装备、自动赏金与所追踪委托（旧字段原样兼容）
## v10 增加委托领奖收据；新收集委托显式交付，旧单仍自动交付。
## v11 保留战斗计时剩余值；菜单/暂停/离线冻结，不恢复半招或架盾手势。
## v12 新营地生态链独立账本；旧委托字段和结算方式不迁改。
## v13 失联前哨独立章节证据与分段支付；v12营地委托保持原账本。
const SAVE_VERSION := 13

## 世界种子（世界 v5）：「新的冒险」重掷，游戏内 BiomeMap.configure 消费；
## v3 旧档无此键 → DEFAULT_SEED（旧世界与旧 ecology 存档严丝合缝）
var world_seed: int = BiomeMap.DEFAULT_SEED
## 战争迷雾位图（200×200 位，每格 4000px ≈ 据点尺度；行内按 bit 打包，
## 25 bytes/行 × 200 行 = 5KB）。空数组 = 全图未探索（懒分配）
const FOG_GRID := 200
var explored := PackedByteArray()
## 细探索独立稀疏保存；粗图继续服务旧任务线索与旧档兼容。
var exploration := ExplorationFog.new(BiomeMap.DEFAULT_SEED)
## 迷雾改动计数（小地图纹理增量重建的脏标记；_test 也可复位）
var fog_version := 0
## 旧粗图新揭示格（最多4万格）；观察者只读，不能清空其他模块的探索通知。
## 新局部地图依赖fog_version与稀疏细图，不再构建全世界纹理。
var fog_dirty: Array[Vector2i] = []
## 已发现地标 id 列表（lm_{patch}_{k}，确定性 id 随种子稳定）
var discovered_landmarks: Array[String] = []
## 已亲自发现的检查点；合法定义来自 WorldConfig，旧档由世界装配迁移已发现地标。
var discovered_checkpoints: Array[String] = []
## 已摧毁障碍格（"x,y" 字符串列表；game_world 装配时灌回 ObstacleField）
var destroyed_cells: Array[String] = []
## 城塞宝箱已领取：patch_id -> true，Boss 实际重生后才清除对应条目。
var chest_claims: Dictionary = {}
## 任务系统数据真源（存档 v5）：active=进行中任务数组，completed=各 NPC 已完成数
var quests := {"active": [], "completed": {}, "receipts": {}, "last_receipt": ""}
## 一次性生态链：放弃只停追踪，已核实行动和已付凭证永久保留。
var camp_quest: Dictionary = {}
var outpost_quest: Dictionary = {}
## 物品栏（玩法 v7，存档 v6）：id -> 数量（钳 ITEM_MAX）。合法 id 真源是
## EconomyMath 的价格表（纯逻辑层，随迁服务端）；表现元数据在 ItemCatalog
var inventory: Dictionary = {}
## 已占用槽位默认锁定；false 是玩家明确选择的按总词条自动换装。
var equipment_locks: Dictionary = {}
## 单个待比较位：首件保留到明确选择，满位后新掉落折金，不覆盖未查看的候选。
var pending_equipment: Dictionary = {}
## 每次新候选递增；按钮保存此凭证，重复/延迟输入不能处理后来的装备。
var equipment_offer_id: int = 0
## 自动赏金跨场景/进程持久化；{} 表示交接期。
var bounty: Dictionary = {}
## 当前追踪的已接 NPC 委托；无效 ID 由任务管理器回退。
var tracked_quest_id := ""
const ITEM_MAX := 99

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
## 生态世界快照（读档时暂存，game_world 启动时消费一次后置空）；
## 运行中的快照在 save_now 时直接向 WorldSim.sim 取——生态跨会话连续是核心卖点
var ecology_snapshot: Variant = null
## 角色运行态快照（位置/当前 HP/MP）：与生态世界一起恢复，避免“继续冒险”
## 实际把角色免费传回出生点并回满状态。死亡时快照由 Player 归一为出生点满状态。
var player_snapshot: Variant = null
## 设置（主菜单/暂停菜单写入）：三条音量滑条（Master 总音量 / Music 音乐 / SFX 音效，
## 后两者默认 1.0——旧档无键走默认，响度与单总线时代完全一致）、震屏、伤害数字、
## 自动瞄准、三忍外观（blue/dark/white，美术 v5）、提灯阴影（默认开；夜间阴影
## pass 是移动端 GPU 大项，真机卡顿可关——开发计划预案内降级路径）、帧率显示
## （默认关，真机性能定位用）
var settings: Dictionary = {"volume": 0.8, "music_volume": 1.0, "sfx_volume": 1.0,
	"screen_shake": true, "damage_numbers": true, "auto_aim": false,
	"hero_skin": "blue", "lantern_shadows": true, "show_fps": false,
	"mobile_shortcut": "bolt", "mobile_recovery": "heal"}
## 本局击杀数（死亡信息/统计用）
var session_kills: int = 0
## 主动阅读对话开合标记（运行态，不存档）；攻击与交互始终独立。
var dialogue_open := false
## 最近一次成功落盘的时刻（Unix 秒）：冒险档案面板显示"最后保存 HH:MM"。
## 0 = 尚未保存过（首启无档 / 测试关闭写盘）
var last_save_unix: float = 0.0

var _save_timer := 0.0
## 生态大快照降频（真机性能优化 2026-09-19）：自动防抖档每 2s 一次
## to_dict(~880 实例深拷贝)是战斗期主线程尖峰；序列化按 6s 节流，跳过时
## 复用上次快照缓存——存档文件任何时刻都带 ecology 键（丢键=静默重置世界）。
## 手动保存/退后台/测试与首次保存恒走全量（参数 include_ecology）
const ECOLOGY_SAVE_INTERVAL := 6.0
var _ecology_saved_at := 0.0
var _ecology_cache: Variant = null
## 击杀奖励及生态死亡在同一同步事务完成；信号订阅者要求立即保存时延至末尾。
var _world_reward_depth := 0
var _world_reward_save_requested := false
var _world_reward_save_full := false
## 寿命警告已触发过的阈值（避免重复播报；读档按剩余寿命重建）
var _lifespan_warned: Array = []

## 游商营地：永久强化（金币消费出口），每类上限 5 级
const UPGRADE_MAX_LEVEL := 5
const UPGRADE_KINDS := ["weapon", "staff", "vigor"]
const UPGRADE_NAMES := {
	"weapon": "武器磨刀", "staff": "法杖赋能", "vigor": "体质淬炼",
}


func _ready() -> void:
	# 暂停期间存档计时继续走：暂停菜单里改设置（音量/震屏）后 2s 内即落盘，
	# 不依赖"恢复游戏后"才补写——玩家改完设置直接杀进程是真实路径
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 测试密闭通道（2026-09-20）：行为类测试（combat/pacing）读真实档会让世界种子
	# 随玩家进度漂移——机器人路线/NPC 距离变化引发种子敏感偶发。launch 时设
	# HOTW_TEST_SAVE=res://tests/fixtures/test_save.json 即与真实档完全隔离
	var test_save := OS.get_environment("HOTW_TEST_SAVE")
	if not test_save.is_empty():
		SAVE_PATH = test_save
	# 强制横屏重申：引擎方向掩码在场景锚定时若单例未就绪会短暂放行全方向，
	# 挂起恢复/设备旋转后可能跟随设备竖屏——竖屏下 expand 拉伸会把可视世界
	# 纵向撑大约 4 倍，人物缩到屏高 ~1.5%（2026-09-09 模拟器实证）。
	# 引擎此调用仅移动端有方向几何意义，桌面 display server 不支持会打警告——显式跳过
	if OS.get_name() == "iOS" or OS.get_name() == "Android":
		DisplayServer.screen_set_orientation(DisplayServer.SCREEN_LANDSCAPE)
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


func _on_kill_record(_xp: int, _gold: int, _monster_name: String, species_name: String) -> void:
	session_kills += 1
	codex[species_name] = codex.get(species_name, 0) + 1
	_queue_save()


func _process(delta: float) -> void:
	if _save_timer > 0.0:
		_save_timer -= delta
		if _save_timer <= 0.0:
			save_now(false)  # 自动防抖档：生态序列化按 ECOLOGY_SAVE_INTERVAL 降频


## iOS 退后台必须立即落盘（进程随时可能被系统杀死）
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_now()
	# 挂起恢复时重申横屏：见 _ready 内注释（iOS 方向锁竞态防御第二道）
	if what == NOTIFICATION_APPLICATION_RESUMED:
		DisplayServer.screen_set_orientation(DisplayServer.SCREEN_LANDSCAPE)


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
	# 贪婪被动只放大获取，不放大损失（负数直通）；
	# roundi 与 EconomyMath 全线口径一致（int() 截断会长期微量少发）
	if amount > 0:
		amount = roundi(amount * stats.gold_mult())
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


## 锁定是保留构筑的默认值：旧档缺字段、新装备入空槽都不会被下一件静默换掉。
## 空槽无需锁；只有玩家在背包明确解锁后，才启用旧有的总词条自动比较。
func is_equipment_locked(slot: String) -> bool:
	return slot in EQUIP_SLOTS and not stats.equips.get(slot, {}).is_empty() \
			and bool(equipment_locks.get(slot, true))


func set_equipment_locked(slot: String, locked: bool) -> bool:
	if not slot in EQUIP_SLOTS or stats.equips.get(slot, {}).is_empty():
		return false
	if is_equipment_locked(slot) == locked:
		return false
	equipment_locks[slot] = locked
	_queue_save()
	return true


## 掉落入口返回实际处置，避免表现层把“待比较”误报为“已出售”。
## 空槽自动穿戴，明确解锁仍按旧有评分自动换装；默认锁定槽保留一个候选。
## 同时只保留一件：待比较期间的后续掉落折金且明确播报，不覆盖首件或无声丢失。
func receive_equipment(item: Dictionary) -> String:
	if item.is_empty():
		return "invalid"
	var slot := str(item.get("slot", "weapon"))
	if not slot in EQUIP_SLOTS:
		return "invalid"
	var clean := _sanitize_equip_item(slot, item)
	var current: Dictionary = stats.equips.get(slot, {})
	if current.is_empty() or (not is_equipment_locked(slot) \
			and stats.equip_score(clean) > stats.equip_score(current)):
		stats.equips[slot] = clean
		if current.is_empty():
			equipment_locks[slot] = true
		stats.changed.emit()
		if not current.is_empty():
			add_gold(EconomyMath.sell_price(int(current.get("rarity", 0))))
		_invalidate_world_save_cache()
		return "equipped"
	if is_equipment_locked(slot) and pending_equipment.is_empty():
		equipment_offer_id += 1
		pending_equipment = clean
		_invalidate_world_save_cache()
		EventBus.equipment_offer_changed.emit()
		return "pending"
	add_gold(EconomyMath.sell_price(int(clean.get("rarity", 0))))
	_invalidate_world_save_cache()
	return "sold"


## 旧调用点的兼容布尔接口：仅已经穿上才返回 true。
func try_equip(item: Dictionary) -> bool:
	return receive_equipment(item) == "equipped"


## 先撤销候选凭证，再变更属性/金币并广播；重复点按与信号重入最多结算一次。
func resolve_pending_equipment(equip_new: bool, expected_offer_id: int) -> bool:
	if pending_equipment.is_empty() or expected_offer_id != equipment_offer_id:
		return false
	var item := pending_equipment.duplicate(true)
	pending_equipment.clear()
	var sold: Dictionary = item
	if equip_new:
		var slot: String = item["slot"]
		sold = stats.equips.get(slot, {}).duplicate(true)
		stats.equips[slot] = item
		# 玩家明确选中的构筑继续受保护，不沿用途中切换的自动模式。
		equipment_locks[slot] = true
		stats.changed.emit()
	if not sold.is_empty():
		add_gold(EconomyMath.sell_price(int(sold.get("rarity", 0))))
	_invalidate_world_save_cache()
	EventBus.equipment_offer_changed.emit()
	return true


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
	return EconomyMath.upgrade_cost(upgrade_level(kind))


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


# --- 物品栏（玩法 v7 P0）：库存单点；掉落/购买/售出统一入口 ---

## 获得物品（monster 掉落 / 商店购买 / P1 任务奖励都走这）。
## 未知 id 忽略；总量钳 ITEM_MAX（满 99 静默丢溢出——单机游戏不惩罚囤积）
func add_item(id: String, count: int = 1) -> void:
	if not EconomyMath.knows_item(id) or count <= 0:
		return
	var total := mini(int(inventory.get(id, 0)) + count, ITEM_MAX)
	inventory[id] = total
	EventBus.item_gained.emit(id, count, total)
	EventBus.inventory_changed.emit()
	_queue_save()


## 扣减物品（不足返回 false 不改状态）；归零即 erase（存档不留 0 键）
func remove_item(id: String, count: int = 1) -> bool:
	var have := int(inventory.get(id, 0))
	if have < count or count <= 0:
		return false
	have -= count
	if have <= 0:
		inventory.erase(id)
	else:
		inventory[id] = have
	EventBus.inventory_changed.emit()
	_queue_save()
	return true


func count_item(id: String) -> int:
	return int(inventory.get(id, 0))


## 使用消耗品：只管库存校验与扣减（必须是可购买的消耗品 id）。
## 效果应用与满血满蓝拦截在 player 侧（生命/精力的权威持有者），
## player 先验拦截再调本方法——库存与效果两层各司其职
func try_use_consumable(id: String) -> bool:
	if not EconomyMath.ITEM_BUY.has(id):
		return false
	return remove_item(id, 1)


## 商店购买消耗品：钱不够 / 已满 ITEM_MAX 返回 false
func buy_item(id: String) -> bool:
	var price := EconomyMath.item_price(id)
	if price <= 0 or gold < price or count_item(id) >= ITEM_MAX:
		return false
	gold -= price
	EventBus.gold_changed.emit(gold)
	add_item(id, 1)
	return true


## 商店出售材料（一次性全卖该 id）：返回卖出件数（0 = 不可售或没货）。
## 收入走 add_gold（贪婪被动与装备折金同口径放大）
func sell_material(id: String) -> int:
	var price := EconomyMath.item_sell_price(id)
	var n := count_item(id)
	if price <= 0 or n <= 0:
		return 0
	inventory.erase(id)
	EventBus.inventory_changed.emit()
	add_gold(price * n)
	return n


func set_tutorial_flag(key: String) -> void:
	if tutorial_flags.has(key):
		return
	tutorial_flags[key] = true
	_queue_save()


# --- 战争迷雾（世界 v5）：200×200 位图，行内 bit 打包（25 bytes/行） ---

func fog_is_explored(gx: int, gy: int) -> bool:
	gx = clampi(gx, 0, FOG_GRID - 1)
	gy = clampi(gy, 0, FOG_GRID - 1)
	var row := gy * 25 + (gx >> 3)
	if row >= explored.size():
		return false
	return (explored[row] >> (gx & 7)) & 1 == 1


func fog_reveal_cell(gx: int, gy: int) -> void:
	# 显式旧API表示整粗格已经知道；世界移动必须走fog_reveal_position。
	_ensure_exploration()
	exploration.remember_legacy_cell(Vector2i(gx, gy))
	_fog_mark_coarse(gx, gy)
	fog_version += 1


func _fog_mark_coarse(gx: int, gy: int) -> void:
	gx = clampi(gx, 0, FOG_GRID - 1)
	gy = clampi(gy, 0, FOG_GRID - 1)
	if explored.is_empty():
		explored.resize(FOG_GRID * 25)
	var row := gy * 25 + (gx >> 3)
	var bit := 1 << (gx & 7)
	if explored[row] & bit == 0:
		explored[row] = explored[row] | bit
		fog_dirty.append(Vector2i(gx, gy))


func _ensure_exploration() -> void:
	if exploration.seed != world_seed:
		exploration = ExplorationFog.new(world_seed)


func fog_knows_position(pos: Vector2) -> bool:
	if exploration.seed != world_seed or not pos.is_finite():
		return false
	return exploration.is_explored(pos)


func fog_reveal_position(pos: Vector2) -> bool:
	_ensure_exploration()
	var added := exploration.reveal(pos)
	for cell: Vector2i in added:
		var coarse := fog_cell_of((Vector2(cell) + Vector2.ONE * 0.5) * ExplorationFog.CELL)
		_fog_mark_coarse(coarse.x, coarse.y)
	if added.is_empty():
		return false
	fog_version += 1
	_queue_save()
	return true


## 世界坐标 → 迷雾格坐标
func fog_cell_of(world_pos: Vector2) -> Vector2i:
	var step := BiomeMap.WORLD_SIZE.x / float(FOG_GRID)
	return Vector2i(clampi(int(world_pos.x / step), 0, FOG_GRID - 1),
			clampi(int(world_pos.y / step), 0, FOG_GRID - 1))


## 标记发现地标（幂等；返回 true = 本次新发现）
func discover_landmark(id: String) -> bool:
	if discovered_landmarks.has(id):
		return false
	discovered_landmarks.append(id)
	_queue_save()
	return true


## 只有定义内的检查点可被发现；重复触发 Area2D 不重复写档。
func discover_checkpoint(id: String) -> bool:
	if id == "outpost:lost_watch" and not outpost_quest.get("evidence", {}).get("signpost_repaired", false):
		return false
	if discovered_checkpoints.has(id) or not WorldConfig.checkpoints().has(id):
		return false
	discovered_checkpoints.append(id)
	_queue_save()
	return true


## 设置应用（音量即时生效）与写入
func set_setting(key: String, value) -> void:
	settings[key] = value
	_apply_settings()
	_queue_save()


## 重置世界：清空全部进度（主菜单"新的冒险"确认）。
## stats 就地重置而非重建对象——Player/HUD/AchievementManager 等订阅者
## 持有的是旧对象引用，换血会静默失联（属性不生效/升级不弹窗）
func reset_all() -> void:
	stats.reset()
	gold = 0
	tutorial_flags = {}
	codex = {}
	achievements = {}
	session_kills = 0
	ecology_snapshot = null
	player_snapshot = null
	_ecology_cache = null
	_ecology_saved_at = 0.0
	_lifespan_warned.clear()
	# 世界 v5：新的冒险 = 全新世界——重掷种子并同步 BiomeMap（此后的菜单预览/
	# 世界装配读到的都是新世界），探索进度归零
	world_seed = randi()
	BiomeMap.configure(world_seed)
	ObstacleField.restore_destroyed([])
	explored = PackedByteArray()
	exploration = ExplorationFog.new(world_seed)
	fog_version += 1
	fog_dirty.clear()
	discovered_landmarks = []
	discovered_checkpoints = []
	destroyed_cells = []
	chest_claims = {}
	quests = {"active": [], "completed": {}, "receipts": {}, "last_receipt": ""}
	camp_quest = {}
	outpost_quest = {}
	inventory = {}
	equipment_locks = {}
	pending_equipment = {}
	equipment_offer_id += 1
	bounty = {}
	tracked_quest_id = ""
	save_now()
	stats_rebuilt.emit()
	EventBus.player_progress_changed.emit(stats.level, stats.xp, stats.xp_to_next(), stats.pending_points)
	EventBus.gold_changed.emit(gold)


func _apply_settings() -> void:
	# linear_to_db(0) = -inf：部分音频后端对 inf 行为未定义，钳到 -60dB（事实静音）
	_set_bus_volume(0, settings.get("volume", 0.8), 0.8)
	# Music/SFX 子总线（default_bus_layout.tres）：按名取索引，布局缺失时静默跳过
	# （headless -s 纯逻辑测试不加载场景也可能无 AudioServer 总线，防御性容错）
	_set_bus_volume(AudioServer.get_bus_index("Music"), settings.get("music_volume", 1.0), 1.0)
	_set_bus_volume(AudioServer.get_bus_index("SFX"), settings.get("sfx_volume", 1.0), 1.0)


func _set_bus_volume(bus_idx: int, linear_value: Variant, fallback: float) -> void:
	if bus_idx < 0:
		return
	var linear := clampf(_safe_float(linear_value, fallback), 0.0, 1.0)
	AudioServer.set_bus_volume_db(bus_idx, maxf(-60.0, linear_to_db(maxf(linear, 0.0001))))


func _on_stats_changed() -> void:
	EventBus.player_progress_changed.emit(
		stats.level, stats.xp, stats.xp_to_next(), stats.pending_points
	)
	_queue_save()


# --- 本地存档（JSON，字段级类型校验，坏档安全忽略） ---

func _queue_save() -> void:
	# 首次变更后 2s 必落盘，后续变更不推迟（领先沿防抖）：旧行为每次变更都
	# 重置计时，长时间连续战斗（金币/经验持续变动）会一直不落盘，进程若被杀
	# 进度损失无上界；写入是 KB 级 JSON 原子替换，2s 节奏对 iOS 闪存无感
	if _save_timer <= 0.0:
		_save_timer = SAVE_DEBOUNCE


## 宝箱与 Boss 周期同档提交：状态改变必须使降频生态缓存失效，
## 否则可能把新领取标记与上一个 Boss 周期的快照拼成同一份档。
func mark_chest_taken(patch_id: String) -> void:
	if patch_id.is_empty() or chest_claims.has(patch_id):
		return
	chest_claims[patch_id] = true
	_invalidate_world_save_cache()


func reset_chest_claim(patch_id: String) -> void:
	chest_claims.erase(patch_id)
	# 未开过宝箱也进入了新 Boss 周期，旧的死亡快照同样不能继续复用。
	_invalidate_world_save_cache()


func clear_chest_claims() -> void:
	chest_claims.clear()
	_invalidate_world_save_cache()


func _invalidate_world_save_cache() -> void:
	_ecology_cache = null
	_ecology_saved_at = 0.0
	_queue_save()


## 只包住同步的击杀结算，不跨帧：奖励、掉落、图鉴与死亡/分裂必须同档。
func begin_world_reward() -> void:
	_world_reward_depth += 1


func end_world_reward() -> void:
	assert(_world_reward_depth > 0)
	_world_reward_depth -= 1
	if _world_reward_depth > 0:
		return
	_invalidate_world_save_cache()
	if _world_reward_save_requested:
		var include_ecology := _world_reward_save_full
		_world_reward_save_requested = false
		_world_reward_save_full = false
		save_now(include_ecology)


## 立即落盘（公开：防抖到时/退后台/回主菜单自动调用，也是
## 主菜单"冒险档案"与暂停菜单"保存进度"手动保存的入口）。
## include_ecology=false 为自动防抖档：生态快照按 ECOLOGY_SAVE_INTERVAL
## 降频序列化，跳过时复用缓存——文件仍带（可能早至 6s 的）ecology 键
## 返回 true 只表示临时档写入/flush/原子替换全部成功；测试禁用写盘也返回 false。
func save_now(include_ecology := true) -> bool:
	if _world_reward_depth > 0:
		_world_reward_save_requested = true
		_world_reward_save_full = _world_reward_save_full or include_ecology
		return false # 此时尚未落盘，不能向调用者声称已保存。
	_save_timer = 0.0
	if not save_enabled:
		return false
	# 世界运行中取角色实时状态；菜单期间沿用 game_world 退出前留下的缓存。
	var live_player := get_tree().get_first_node_in_group("player")
	if live_player != null and live_player.has_method("save_snapshot"):
		player_snapshot = live_player.save_snapshot()
	var saved_at := Time.get_unix_time_from_system()
	var data := {
		"version": SAVE_VERSION,
		"world_seed": world_seed,
		"level": stats.level,
		"xp": stats.xp,
		"pending_points": stats.pending_points,
		"pending_passive_picks": stats.pending_passive_picks,
		"passive_choices": stats.passive_choices.duplicate(),
		"passive_offer_id": stats.passive_offer_id,
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
		"equipment_locks": equipment_locks,
		"pending_equipment": pending_equipment.duplicate(true),
		"equipment_offer_id": equipment_offer_id,
		"bounty": bounty.duplicate(true),
		"tracked_quest_id": tracked_quest_id,
		"camp_quest": camp_quest.duplicate(true),
		"outpost_quest": outpost_quest.duplicate(true),
		"age_days": stats.age_days,
		"lifespan_days": stats.lifespan_days,
		"codex": codex,
		"achievements": achievements,
		"settings": settings,
		"tutorial": tutorial_flags,
		"last_save_unix": saved_at,
	}
	if typeof(player_snapshot) == TYPE_DICTIONARY:
		data["player"] = (player_snapshot as Dictionary).duplicate(true)
	# 生态世界快照：世界运行中取实时 sim；菜单期间（sim 已被 game_world 卸载）
	# 回退到最近一次快照缓存（读档暂存 / 退出世界时 game_world 存入）。
	# 若在此直接丢键，菜单里改任何设置（如音量滑条触发的防抖落盘）都会把存档
	# 原子替换为无 ecology 的版本——玩家没按"重置世界"，演化中的世界却静默丢失。
	# 自动防抖档降频：未到 ECOLOGY_SAVE_INTERVAL 时跳过 to_dict 深拷贝，
	# 复用上次序列化结果（文件仍带 ecology，内容早至 6s——生态 tick=1s，
	# 极端丢档上限 ≈5 tick 的演化，可忽略）
	var ecology: Variant = null
	if WorldSim.sim != null:
		var now := Time.get_unix_time_from_system()
		if not include_ecology and _ecology_cache != null \
				and now - _ecology_saved_at < ECOLOGY_SAVE_INTERVAL:
			ecology = _ecology_cache
		else:
			ecology = WorldSim.sim.to_dict()
			# 世界时钟随快照入档（昼夜相位/游戏天数）：生态连续而昼夜断裂的话，
			# "读档回清晨"等于时间回溯（寿命按游戏天推进，可反复读档免老化）
			(ecology as Dictionary)["day_time"] = WorldSim.day_time
			(ecology as Dictionary)["game_day"] = WorldSim.game_day
			_ecology_cache = ecology
			_ecology_saved_at = now
	elif typeof(ecology_snapshot) == TYPE_DICTIONARY:
		ecology = ecology_snapshot
	if ecology != null:
		data["ecology"] = ecology
	# 探索进度（世界 v5）：迷雾位图（base64 存 PackedByteArray）+ 已发现地标
	if not explored.is_empty():
		data["explored"] = Marshalls.raw_to_base64(explored)
	_ensure_exploration()
	data["exploration_v2"] = exploration.to_dict()
	if not discovered_landmarks.is_empty():
		data["landmarks"] = discovered_landmarks.duplicate()
	if not discovered_checkpoints.is_empty():
		data["checkpoints"] = discovered_checkpoints.duplicate()
	# 世界运行时覆盖层是真源；菜单冷启动尚未装配 ObstacleField，必须保留读档缓存。
	if WorldSim.sim != null:
		destroyed_cells.assign(ObstacleField.destroyed_list())
	if not destroyed_cells.is_empty():
		data["destroyed"] = destroyed_cells.duplicate()
	if not chest_claims.is_empty():
		data["chest_claims"] = chest_claims.duplicate()
	if not quests["active"].is_empty() or not quests["completed"].is_empty():
		data["quests"] = {"active": (quests["active"] as Array).duplicate(true),
			"completed": (quests["completed"] as Dictionary).duplicate(true),
			"receipts": (quests.get("receipts", {}) as Dictionary).duplicate(true),
			"last_receipt": str(quests.get("last_receipt", ""))}
	# 物品栏（v6+）：非空才写（照 quests 口径）
	if not inventory.is_empty():
		data["inventory"] = inventory.duplicate(true)
	# 原子写：iOS 退后台瞬间进程可能在写入中途被杀留下半截档——
	# 先写临时文件再改名（rename 是原子操作），主档任何时刻都是完整状态
	var tmp_path := "%s.tmp" % SAVE_PATH
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		return _save_failed("存档写入失败：%s" % tmp_path)
	var payload := JSON.stringify(data).to_utf8_buffer()
	var stored := file.store_buffer(payload)
	var write_error := file.get_error()
	# 缓冲写入可能直到 flush 才暴露磁盘满/IO 错误，不能直接 close 后替换好档。
	file.flush()
	var flush_error := file.get_error()
	file.close()
	if not stored or write_error != OK or flush_error != OK:
		DirAccess.remove_absolute(tmp_path)
		return _save_failed("存档写入/刷新失败（错误码 %d/%d），保留旧档" % [write_error, flush_error])
	# Godot 4.7 在 POSIX 缓冲 flush 失败时可能仍返回 get_error()==OK
	#（RLIMIT_FSIZE 短写实测）；关闭后核对完整字节，确认无截断才替换好档。
	if FileAccess.get_file_as_bytes(tmp_path) != payload:
		DirAccess.remove_absolute(tmp_path)
		return _save_failed("存档写入校验失败，保留旧档")
	var err := DirAccess.rename_absolute(tmp_path, SAVE_PATH)
	if err != OK:
		DirAccess.remove_absolute(tmp_path)
		return _save_failed("存档原子替换失败（错误码 %d），保留旧档" % err)
	last_save_unix = saved_at
	return true


func _save_failed(message: String) -> bool:
	push_warning(message)
	# 失败不是已保存：保留内存进度，恢复可写后自动重试，暂停菜单期间也继续计时。
	_queue_save()
	return false


## 反序列化的宽松数值读取：存档可能被手改/三方工具写坏，
## 类型错误回落默认值而不是中断 _load 留下"半加载"状态
func _safe_int(value: Variant, fallback: int) -> int:
	match typeof(value):
		TYPE_INT:
			return value
		TYPE_FLOAT:
			return int(value) if is_finite(value) else fallback
		_:
			return fallback


func _safe_float(value: Variant, fallback: float) -> float:
	match typeof(value):
		TYPE_FLOAT:
			return value
		TYPE_INT:
			return float(value)
		_:
			return fallback


## 玩家运行态字段级消毒：位置必须是两个有限数，HP/MP 也只接收有限数值。
## 缺 hp/mp 键不注入哨兵（曾以 -1 占位 → 恢复侧 clamp 成 1 血开局）：
## 交给 player._restore_saved_state 的满血蓝默认；键存在但坏值仍整段丢弃。
func _sanitize_player_snapshot(value: Variant) -> Variant:
	if typeof(value) != TYPE_DICTIONARY:
		return null
	var raw: Dictionary = value
	var pos: Variant = raw.get("position", null)
	if typeof(pos) != TYPE_ARRAY or pos.size() != 2:
		return null
	if not typeof(pos[0]) in [TYPE_INT, TYPE_FLOAT] or not typeof(pos[1]) in [TYPE_INT, TYPE_FLOAT]:
		return null
	var x := float(pos[0])
	var y := float(pos[1])
	if not is_finite(x) or not is_finite(y):
		return null
	var hp := stats.max_hp()
	var mp := stats.max_mp()
	if raw.has("hp"):
		hp = _safe_float(raw.get("hp", 0.0), NAN)
		if not is_finite(hp):
			return null
	if raw.has("mp"):
		mp = _safe_float(raw.get("mp", 0.0), NAN)
		if not is_finite(mp):
			return null
	var clean := {"position": [x, y], "hp": hp, "mp": mp}
	# 类型/有限数/上限的真源在 Player 恢复侧；此处仅保留独立字典，
	# 坏计时不能连带丢弃有效位置和资源，旧档缺键按原零计时恢复。
	if typeof(raw.get("combat_timers")) == TYPE_DICTIONARY:
		clean["combat_timers"] = raw["combat_timers"].duplicate(true)
	return clean


## 装备条目字段级消毒（equips 主路径与 v1 legacy 迁移共用）：
## 名称转字符串、稀有度钳 0~3、词条只收 String 键 + 数值钳 [0, 硬上限]、元素只认火/冰。
## 词条硬上限 0.5 = 词条表理论最大值（0.20）的 2.5 倍余量：正常掉落永不可达，
## 只拦手改档神装（单机自欺本无受害者，但护栏与类型消毒同口径；M2 服务器权威前先行）
const AFFIX_HARD_CAP := 0.5

func _sanitize_equip_item(slot: String, item: Dictionary) -> Dictionary:
	var clean := {
		"slot": slot,
		"name": str(item.get("name", "?")),
		"rarity": clampi(_safe_int(item.get("rarity", 0), 0), 0, 3),
		"affixes": {},
	}
	var affixes: Variant = item.get("affixes", {})
	if typeof(affixes) == TYPE_DICTIONARY:
		for key in affixes:
			if typeof(key) == TYPE_STRING:
				clean["affixes"][key] = clampf(_safe_float(affixes[key], 0.0), 0.0, AFFIX_HARD_CAP)
	var element := str(item.get("element", ""))
	if element == "fire" or element == "ice":
		clean["element"] = element
	return clean


## 赏金仍由管理器按真实世界可行性复核，这里只恢复完整、有限、合法的状态。
func _sanitize_bounty(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY or value.is_empty():
		return {}
	var raw: Dictionary = value
	if typeof(raw.get("species")) != TYPE_STRING or str(raw["species"]).is_empty() \
			or typeof(raw.get("region_id")) != TYPE_STRING or str(raw["region_id"]).is_empty():
		return {}
	for key: String in ["need", "progress", "gold", "xp"]:
		if typeof(raw.get(key)) not in [TYPE_INT, TYPE_FLOAT] \
				or not is_finite(float(raw[key])):
			return {}
	var need := clampi(int(raw["need"]), 1, 7)
	var original_need := clampi(_safe_int(raw.get("original_need", need), need), need, 7)
	var clean := {
		"species": SpeciesCatalog.migrate_name(raw["species"]),
		"region_id": str(raw["region_id"]), "need": need,
		"progress": clampi(int(raw["progress"]), 0, need),
		"gold": clampi(int(raw["gold"]), 0, 100000),
		"xp": clampi(int(raw["xp"]), 0, 100000),
		"original_need": original_need,
		"original_gold": clampi(_safe_int(raw.get("original_gold", raw["gold"]), 0), 0, 100000),
		"original_xp": clampi(_safe_int(raw.get("original_xp", raw["xp"]), 0), 0, 100000),
		"adjusted": raw.get("adjusted", false) == true if typeof(raw.get("adjusted", false)) == TYPE_BOOL else false,
	}

	if raw.has("target_ids") and typeof(raw["target_ids"]) == TYPE_ARRAY:
		var ids: Array[int] = []
		for id: Variant in raw["target_ids"]:
			if typeof(id) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(id)):
				continue
			var value_id := int(id)
			if value_id > 0 and float(value_id) == float(id) and not ids.has(value_id):
				ids.append(value_id)
			if ids.size() >= 7:
				break
		clean["target_ids"] = ids
	return clean


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
	var version := _safe_int(data.get("version", 1), 1)
	if version > SAVE_VERSION:
		push_warning("存档版本 %d 高于当前支持的 %d（可能来自更新版本客户端），按兼容模式尝试读取" % [
			version, SAVE_VERSION])
	# 世界种子（v4+）：v3 旧档无键 → DEFAULT_SEED，旧世界与旧 ecology 快照严丝合缝
	world_seed = _safe_int(data.get("world_seed", BiomeMap.DEFAULT_SEED), BiomeMap.DEFAULT_SEED)
	stats.level = maxi(1, _safe_int(data.get("level", 1), 1))
	stats.xp = maxi(0, _safe_int(data.get("xp", 0), 0))
	stats.pending_points = maxi(0, _safe_int(data.get("pending_points", 0), 0))
	stats.strength = maxi(1, _safe_int(data.get("strength", 5), 5))
	stats.agility = maxi(1, _safe_int(data.get("agility", 5), 5))
	stats.intellect = maxi(1, _safe_int(data.get("intellect", 5), 5))
	gold = maxi(0, _safe_int(data.get("gold", 0), 0))
	var saved_upgrades: Variant = data.get("upgrades", {})
	if typeof(saved_upgrades) == TYPE_DICTIONARY:
		for kind in UPGRADE_KINDS:
			stats.set("upgrade_%s" % kind,
				clampi(_safe_int(saved_upgrades.get(kind, 0), 0), 0, UPGRADE_MAX_LEVEL))
	var saved_flags: Variant = data.get("tutorial", {})
	if typeof(saved_flags) == TYPE_DICTIONARY:
		tutorial_flags = {}
		for key in saved_flags:
			if typeof(key) != TYPE_STRING:
				continue
			# 标志值兼容 bool（常态）与数字（旧格式），其余类型视为未完成
			var flag: Variant = saved_flags[key]
			if flag == true or _safe_int(flag, 0) > 0:
				tutorial_flags[key] = true
	var saved_codex: Variant = data.get("codex", {})
	if typeof(saved_codex) == TYPE_DICTIONARY:
		codex = {}
		for key in saved_codex:
			if typeof(key) == TYPE_STRING:
				var kills := _safe_int(saved_codex[key], 0)
				if kills > 0:
					# 旧物种名迁到现行名录（美术 v5 更名；两个旧名并入同一新名时累加）
					var migrated: String = SpeciesCatalog.migrate_name(key)
					codex[migrated] = codex.get(migrated, 0) + kills
	var saved_passives: Variant = data.get("passives", {})
	stats.passives = {}
	if typeof(saved_passives) == TYPE_DICTIONARY:
		for key in saved_passives:
			if typeof(key) == TYPE_STRING and CharacterStats.passive_known(key):
				var lv := _safe_int(saved_passives[key], 0)
				if lv > 0:
					stats.passives[key] = mini(lv, 1) if key in CharacterStats.WEAPON_PASSIVES else lv
	# v1-v6 每级恰有一次赐福，但待领取次数仅在旧 HUD 内存中。
	# 用「已升等级 - 已持有被动等级之和」补回遗失资格；保留全部既有被动，
	# 已领取的不会再发。v7 的显式剩余次数为真源，不能每次读档重新推算。
	var claimed := 0
	for rank: int in stats.passives.values():
		claimed += rank
	var inferred_pending := maxi(0, stats.level - 1 - claimed)
	stats.pending_passive_picks = clampi(
		_safe_int(data.get("pending_passive_picks", inferred_pending), inferred_pending),
		0, stats.level - 1)
	stats.passive_offer_id = maxi(0, _safe_int(data.get("passive_offer_id", 0), 0))
	stats.passive_choices.clear()
	var saved_choices: Variant = data.get("passive_choices", [])
	if typeof(saved_choices) == TYPE_ARRAY:
		for id: Variant in saved_choices:
			if typeof(id) != TYPE_STRING or stats.passive_choices.has(id):
				continue
			for entry: Dictionary in CharacterStats.PASSIVE_POOL:
				if entry["id"] == id:
					stats.passive_choices.append(id)
		# 损坏/不完整选项重新生成一组完整卡，资格不丢；正常三张卡保持原样。
	if stats.passive_choices.size() != 3:
		stats.passive_choices.clear()
	stats.ensure_passive_choices()
	# 寿命：读档重建（非法值回落默认）；已越过的警告阈值静默补记防重复播报
	stats.age_days = maxf(0.0, _safe_float(data.get("age_days", 0.0), 0.0))
	stats.lifespan_days = maxf(1.0, _safe_float(data.get("lifespan_days", CharacterStats.BASE_LIFESPAN_DAYS), CharacterStats.BASE_LIFESPAN_DAYS))
	_lifespan_warned.clear()
	for threshold in [10.0, 5.0, 1.0]:
		if stats.lifespan_remaining() <= threshold:
			_lifespan_warned.append(threshold)
	stats.equips = {}
	var saved_equips: Variant = data.get("equips", {})
	if typeof(saved_equips) == TYPE_DICTIONARY:
		# 只收合法槽位，旧档遗留字段不带入；内层字段级消毒（存档可能被手改/工具写坏）：
		# affixes 若被改成数组，equip_affix 遍历时会按错误类型索引崩溃
		for slot in EQUIP_SLOTS:
			var item: Variant = saved_equips.get(slot, null)
			if typeof(item) != TYPE_DICTIONARY:
				continue
			stats.equips[slot] = _sanitize_equip_item(slot, item)
	# 旧档迁移：单件装备时代（"equip" 键）整体视作武器槽——走与主路径相同的消毒
	# （此前原样放入，legacy 档里 affixes 若是数组会让每次 max_hp() 求值即崩，读档坏档循环）
	var legacy_equip: Variant = data.get("equip", null)
	if typeof(legacy_equip) == TYPE_DICTIONARY and not legacy_equip.is_empty() \
			and not stats.equips.has("weapon"):
		stats.equips["weapon"] = _sanitize_equip_item("weapon", legacy_equip)
	# 缺键/坏值默认锁定，既有输出/吸血构筑升级后立即受保护；仅布尔 false 可解锁。
	equipment_locks = {}
	var saved_locks: Variant = data.get("equipment_locks", {})
	if typeof(saved_locks) == TYPE_DICTIONARY:
		for slot: String in EQUIP_SLOTS:
			if stats.equips.has(slot) and typeof(saved_locks.get(slot)) == TYPE_BOOL:
				equipment_locks[slot] = saved_locks[slot]
	# 旧档缺候选即为空；坏候选不会成为可领取的免费金币。
	pending_equipment = {}
	equipment_offer_id = maxi(0, _safe_int(data.get("equipment_offer_id", 0), 0))
	var saved_offer: Variant = data.get("pending_equipment", {})
	if typeof(saved_offer) == TYPE_DICTIONARY and not saved_offer.is_empty() \
			and typeof(saved_offer.get("slot")) == TYPE_STRING \
			and saved_offer.get("slot") in EQUIP_SLOTS \
			and typeof(saved_offer.get("name")) == TYPE_STRING \
			and typeof(saved_offer.get("affixes")) == TYPE_DICTIONARY:
		pending_equipment = _sanitize_equip_item(saved_offer["slot"], saved_offer)
		equipment_offer_id = maxi(1, equipment_offer_id)
	bounty = _sanitize_bounty(data.get("bounty", {}))
	tracked_quest_id = str(data.get("tracked_quest_id", "")) \
			if typeof(data.get("tracked_quest_id", "")) == TYPE_STRING else ""
	var saved_achv: Variant = data.get("achievements", {})
	if typeof(saved_achv) == TYPE_DICTIONARY:
		achievements = {}
		for key in saved_achv:
			# typeof 先行：GDScript 的 "true" == true 是运行时错误而非 true
			if typeof(key) == TYPE_STRING and typeof(saved_achv[key]) == TYPE_BOOL \
					and saved_achv[key]:
				achievements[key] = true
	var saved_settings: Variant = data.get("settings", {})
	if typeof(saved_settings) == TYPE_DICTIONARY:
		for key in saved_settings:
			if typeof(key) != TYPE_STRING:
				continue
			# 键白名单 + 类型消毒（与 codex/achievements 同口径）：手改档把布尔
			# 写成 "false"（truthy 字符串）直接覆写会让开关行为反直觉
			match key:
				"volume", "music_volume", "sfx_volume":
					# 回退值经 get 取：内存 settings 可能缺键（如部分赋值后读档），
					# 直接 settings[key] 索引会在键缺失时中断整个 _load
					settings[key] = clampf(_safe_float(saved_settings[key],
						float(settings.get(key, 1.0))), 0.0, 1.0)
				"screen_shake", "damage_numbers", "auto_aim", "lantern_shadows", "show_fps":
					if typeof(saved_settings[key]) == TYPE_BOOL:
						settings[key] = saved_settings[key]
				"mobile_shortcut":
					if typeof(saved_settings[key]) == TYPE_STRING and saved_settings[key] in ["bolt", "heavy", "empower"]:
						settings[key] = saved_settings[key]
				"mobile_recovery":
					if typeof(saved_settings[key]) == TYPE_STRING:
						var recovery: String = saved_settings[key]
						if recovery == "heal" or (recovery.begins_with("item:") and ItemCatalog.is_consumable(recovery.trim_prefix("item:"))):
							settings[key] = recovery
				"hero_skin":
					# 三忍外观只认三个合法值，其余一律回落蓝忍
					if str(saved_settings[key]) in ["blue", "dark", "white"]:
						settings[key] = str(saved_settings[key])
	# 生态世界快照（v2+）：由 game_world 启动时消费
	var saved_ecology: Variant = data.get("ecology", null)
	if typeof(saved_ecology) == TYPE_DICTIONARY:
		ecology_snapshot = saved_ecology
	else:
		ecology_snapshot = null
	# 换档后旧世界的降频缓存必须作废（新世界首个自动保存走全量）
	_ecology_cache = null
	_ecology_saved_at = 0.0
	player_snapshot = _sanitize_player_snapshot(data.get("player", null))
	# 探索进度（v4+）：坏值静默回退"全未探索/零发现"——迷雾只是表现，不值得坏档
	var saved_fog: Variant = data.get("explored", "")
	explored = PackedByteArray()
	exploration = ExplorationFog.new(world_seed)
	fog_version += 1
	fog_dirty.clear()
	if typeof(saved_fog) == TYPE_STRING and saved_fog != "":
		var decoded := ExplorationFog.decode_bitmap(saved_fog, FOG_GRID * 25)
		if decoded.size() == FOG_GRID * 25:
			explored = decoded
	exploration.restore(data.get("exploration_v2") if data.get("exploration_v2") != null else \
		({} if data.has("exploration_v2") else null), explored)
	discovered_landmarks = []
	discovered_checkpoints = []
	destroyed_cells = []
	chest_claims = {}
	var saved_claims: Variant = data.get("chest_claims", {})
	if typeof(saved_claims) == TYPE_DICTIONARY:
		for patch_id: Variant in saved_claims:
			if typeof(patch_id) == TYPE_STRING and not patch_id.is_empty() \
					and typeof(saved_claims[patch_id]) == TYPE_BOOL and saved_claims[patch_id]:
				chest_claims[patch_id] = true
	var saved_cells: Variant = data.get("destroyed", [])
	if typeof(saved_cells) == TYPE_ARRAY:
		for entry in saved_cells:
			if typeof(entry) == TYPE_STRING and entry.contains(","):
				destroyed_cells.append(entry)
	camp_quest = preload("res://scripts/main/camp_quest_data.gd").sanitize(data.get("camp_quest", {}))
	outpost_quest = preload("res://scripts/main/outpost_quest_data.gd").sanitize(data.get("outpost_quest", {}), camp_quest)
	# 章节携带独立原合同备份；恢复缺失合同或不可逆已付证明，保留正常最新进度。
	if preload("res://scripts/main/outpost_quest_data.gd").valid_legacy(outpost_quest.get("legacy_contract", {})) and (not preload("res://scripts/main/outpost_quest_data.gd").valid_legacy(camp_quest) \
			or (outpost_quest["legacy_contract"].get("paid", false) and not camp_quest.get("paid", false))):
		camp_quest = preload("res://scripts/main/camp_quest_data.gd").sanitize(outpost_quest["legacy_contract"])

	# 任务进度（v5+）：字段级消毒——缺键/坏类型的条目丢弃而非中断整个任务栏
	quests = {"active": [], "completed": {}, "receipts": {}, "last_receipt": ""}
	var saved_quests: Variant = data.get("quests", {})
	if typeof(saved_quests) == TYPE_DICTIONARY:
		var saved_active: Variant = saved_quests.get("active", [])
		if typeof(saved_active) == TYPE_ARRAY:
			for q: Variant in saved_active:
				if typeof(q) != TYPE_DICTIONARY:
					continue
				var qd: Dictionary = q
				# id 判型默认值须用 null：默认 "" 也是 String，缺 id 的坏条目
				# 会溜过类型门留在任务栏，HUD 读 title/kind 即崩。合法任务
				#（_gen_quest 产出）必有 id/kind/title，缺任一即丢弃
				if typeof(qd.get("id", null)) != TYPE_STRING or str(qd.get("id")) == "" \
						or typeof(qd.get("need", 0)) not in [TYPE_INT, TYPE_FLOAT] \
						or typeof(qd.get("kind", null)) != TYPE_STRING \
						or typeof(qd.get("title", null)) != TYPE_STRING:
					continue
				# 旧档任务的目标物种随美术 v5 更名一并迁移（查无的已删物种任务
				# 保留但永不达成——任务栏可手动放弃，不做读档时静默删任务）。
				# 物种键仅狩猎任务携带：捣巢/探索/收集任务无此键，get 默认须用
				# null 判型（默认 "" 也是 String，旧写法会对无键任务取 qd["species"]
				# 崩溃，中断 _load——其后的物品栏/地标/保存时间全部丢失）
				if typeof(qd.get("species", null)) == TYPE_STRING:
					qd["species"] = SpeciesCatalog.migrate_name(qd["species"])
				qd["need"] = maxi(1, int(qd["need"]))
				qd["progress"] = clampi(_safe_int(qd.get("progress", 0), 0), 0, int(qd["need"]))
				# 缺失此标志的 v9/早期存档保留自动交付，不能读档后强迫返程。
				if qd.has("claim_at_npc"):
					qd["claim_at_npc"] = qd["kind"] == "collect" and typeof(qd["claim_at_npc"]) == TYPE_BOOL and qd["claim_at_npc"]
				quests["active"].append(qd)
		var saved_completed: Variant = saved_quests.get("completed", {})
		if typeof(saved_completed) == TYPE_DICTIONARY:
			for key in saved_completed:
				if typeof(key) == TYPE_STRING and typeof(saved_completed[key]) in [TYPE_INT, TYPE_FLOAT]:
					quests["completed"][key] = maxi(0, int(saved_completed[key]))
		var saved_receipts: Variant = saved_quests.get("receipts", {})
		if typeof(saved_receipts) == TYPE_DICTIONARY:
			for key: Variant in saved_receipts:
				if typeof(key) != TYPE_STRING or typeof(saved_receipts[key]) != TYPE_DICTIONARY:
					continue
				var receipt: Dictionary = saved_receipts[key]
				if typeof(receipt.get("id")) != TYPE_STRING or str(receipt.get("id", "")).is_empty() \
						or typeof(receipt.get("title")) != TYPE_STRING:
					continue
				quests["receipts"][key] = {"id": receipt["id"], "title": receipt["title"],
					"gold": maxi(0, _safe_int(receipt.get("gold"), 0)),
					"xp": maxi(0, _safe_int(receipt.get("xp"), 0)),
					"bonus": str(receipt.get("bonus", "")) if EconomyMath.knows_item(str(receipt.get("bonus", ""))) else "",
					"giver": str(receipt.get("giver", "")), "kind": str(receipt.get("kind", ""))}
		var last: Variant = saved_quests.get("last_receipt", "")
		if typeof(last) == TYPE_STRING and quests["receipts"].has(last):
			quests["last_receipt"] = last
	var saved_marks: Variant = data.get("landmarks", [])
	if typeof(saved_marks) == TYPE_ARRAY:
		for id in saved_marks:
			if typeof(id) == TYPE_STRING and id.begins_with("lm_"):
				discovered_landmarks.append(id)
	var saved_checkpoints: Variant = data.get("checkpoints", [])
	if typeof(saved_checkpoints) == TYPE_ARRAY and not saved_checkpoints.is_empty():
		# 校验必须使用本档世界种子，不能借用上一档残留的地标定义。
		BiomeMap.configure(world_seed)
		var valid_checkpoints := WorldConfig.checkpoints()
		for id: Variant in saved_checkpoints:
			if typeof(id) == TYPE_STRING and valid_checkpoints.has(id) \
					and not discovered_checkpoints.has(id):
				discovered_checkpoints.append(id)
	# 前哨只继承亲手修复证据，不因雾、到访、旧检查点数组或终态字符串解锁。
	discovered_checkpoints.erase("outpost:lost_watch")
	if outpost_quest.get("evidence", {}).get("signpost_repaired", false):
		discovered_checkpoints.append("outpost:lost_watch")
	# 物品栏（v6+）：逐条消毒——未知 id / 非 String 键丢弃，数量只收正整数钳
	# ITEM_MAX（手改档负数/浮点/超限都按边界收敛，不中断整个背包）
	inventory = {}
	var saved_inventory: Variant = data.get("inventory", {})
	if typeof(saved_inventory) == TYPE_DICTIONARY:
		for key in saved_inventory:
			if typeof(key) != TYPE_STRING or not EconomyMath.knows_item(key):
				continue
			var n := clampi(_safe_int(saved_inventory[key], 0), 0, ITEM_MAX)
			if n > 0:
				inventory[key] = n
	last_save_unix = maxf(0.0, _safe_float(data.get("last_save_unix", 0.0), 0.0))
	_apply_settings()
	EventBus.player_progress_changed.emit(
		stats.level, stats.xp, stats.xp_to_next(), stats.pending_points
	)
	EventBus.gold_changed.emit(gold)
