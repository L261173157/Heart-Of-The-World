## 本地存档读写验证（作为普通场景运行，autoload 可用）。
## 运行："$GODOT" --headless --path Code res://tests/save_test.tscn --quit-after 5000
## 流程：清档 → 构造进度 → 保存 → 篡改内存 → 重载 → 断言恢复；再测坏档防御。
extends Node2D

var _fails := 0


func _ready() -> void:
	# 沙盒存档路径：测试全程不读写真实 user://save.json
	GameState.SAVE_PATH = "user://save_test.json"
	GameState.save_enabled = true
	_test_roundtrip()
	_test_shop()
	_test_progress_meta()
	_test_lifespan()
	_test_ecology_snapshot()
	_test_world_v5()
	_test_corrupted_file()
	# 收尾清档，不把测试数据留给真实游戏
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.SAVE_PATH))
	if _fails == 0:
		print("=== 存档验证全部通过 ===")
		get_tree().quit(0)
	else:
		print("=== %d 项失败 ===" % _fails)
		get_tree().quit(1)


func _test_roundtrip() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.SAVE_PATH))
	GameState.stats.level = 7
	GameState.stats.xp = 55
	GameState.stats.pending_points = 3
	GameState.stats.strength = 9
	GameState.stats.agility = 6
	GameState.stats.intellect = 4
	GameState.gold = 321
	GameState.player_snapshot = {"position": [2710.0, 340.0], "hp": 87.0, "mp": 23.0}
	GameState.seen_intro_cg = true
	GameState.save_now()
	_check(FileAccess.file_exists(GameState.SAVE_PATH), "存档文件已写入 user://save.json")
	var save_unix: float = GameState.last_save_unix
	_check(save_unix > 0.0, "落盘时记录最后保存时间（%.0f）" % save_unix)

	# 篡改内存后重载
	GameState.stats.level = 1
	GameState.stats.xp = 0
	GameState.stats.pending_points = 0
	GameState.stats.strength = 5
	GameState.stats.agility = 5
	GameState.stats.intellect = 5
	GameState.gold = 0
	GameState.player_snapshot = null
	GameState.seen_intro_cg = false
	GameState.last_save_unix = 0.0
	GameState._load()
	_check(GameState.last_save_unix > 0.0, "读档恢复最后保存时间（%.0f）" % GameState.last_save_unix)
	_check(GameState.seen_intro_cg, "读档恢复开场 CG 已播标记")
	_check(GameState.stats.level == 7, "读档恢复等级（%d == 7）" % GameState.stats.level)
	_check(GameState.stats.xp == 55, "读档恢复经验（%d == 55）" % GameState.stats.xp)
	_check(GameState.stats.pending_points == 3, "读档恢复属性点（%d == 3）" % GameState.stats.pending_points)
	_check(GameState.stats.strength == 9 and GameState.stats.agility == 6
			and GameState.stats.intellect == 4, "读档恢复三维属性")
	_check(GameState.gold == 321, "读档恢复金币（%d == 321）" % GameState.gold)
	_check(typeof(GameState.player_snapshot) == TYPE_DICTIONARY \
			and GameState.player_snapshot["position"] == [2710.0, 340.0] \
			and GameState.player_snapshot["hp"] == 87.0 and GameState.player_snapshot["mp"] == 23.0,
			"读档恢复角色位置/生命/魔法")


## 世界 v5：world_seed / 迷雾位图 / 地标发现 的存档往返 + v3 旧档迁移（无键 →
## DEFAULT_SEED，旧世界与旧 ecology 快照严丝合缝）
func _test_world_v5() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.SAVE_PATH))
	GameState.world_seed = 777777
	GameState.explored = PackedByteArray()
	GameState.fog_reveal_cell(0, 0)
	GameState.fog_reveal_cell(GameState.FOG_GRID - 1, GameState.FOG_GRID - 1)
	GameState.fog_reveal_cell(100, 50)
	GameState.discovered_landmarks = ["lm_p_3_4_0"]
	GameState.save_now()
	GameState.world_seed = 1
	GameState.explored = PackedByteArray()
	GameState.discovered_landmarks = []
	GameState._load()
	_check(GameState.world_seed == 777777, "读档恢复世界种子（%d == 777777）" % GameState.world_seed)
	_check(GameState.fog_is_explored(0, 0) and GameState.fog_is_explored(
			GameState.FOG_GRID - 1, GameState.FOG_GRID - 1)
			and GameState.fog_is_explored(100, 50) and not GameState.fog_is_explored(5, 5),
			"读档恢复迷雾位图（已揭示/未揭示格一致）")
	_check(GameState.discovered_landmarks == ["lm_p_3_4_0"], "读档恢复已发现地标")
	# 摧毁格走真实流：运行期覆盖层（damage_cell 灌入）→ save_now 序列化
	ObstacleField.restore_destroyed(["100,200", "-5,7"])
	GameState.save_now()
	GameState.destroyed_cells = []
	ObstacleField.restore_destroyed([])
	GameState._load()
	_check(GameState.destroyed_cells == ["100,200", "-5,7"],
			"读档恢复已摧毁障碍格（%d 条）" % GameState.destroyed_cells.size())
	# ObstacleField 覆盖层灌回（game_world 装配路径的纯逻辑部分）
	ObstacleField.restore_destroyed(GameState.destroyed_cells)
	_check(ObstacleField.sample_cell(Vector2i(100, 200)).is_empty()
			and ObstacleField.sample_cell(Vector2i(-5, 7)).is_empty(), "摧毁格灌回后采样为空")
	# v3 旧档迁移：手工构造无 world_seed/explored/landmarks 键的档
	var legacy := {
		"version": 3, "level": 5, "xp": 0, "gold": 10,
	}
	var file := FileAccess.open(GameState.SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy))
	file.close()
	GameState.world_seed = 123
	GameState.explored = PackedByteArray()
	GameState.explored.resize(GameState.FOG_GRID * 25)
	GameState.explored.fill(255)
	GameState.discovered_landmarks = ["lm_p_0_0_0"]
	GameState._load()
	_check(GameState.world_seed == BiomeMap.DEFAULT_SEED,
			"v3 旧档无种子键迁移到默认种子（%d）" % GameState.world_seed)
	_check(GameState.explored.is_empty(), "v3 旧档探索进度归零（全图未探索）")
	_check(GameState.discovered_landmarks.is_empty(), "v3 旧档无地标发现")
	_check(GameState.seen_intro_cg == false, "v3 旧档开场 CG 标记默认未播")
	_check(GameState.stats.level == 5, "v3 旧档角色进度照常读取")


## 游商营地：购买扣费/拒绝路径 + 强化等级随存档往返 + 数值公式生效
func _test_shop() -> void:
	GameState.stats.upgrade_weapon = 0
	GameState.stats.upgrade_staff = 0
	GameState.stats.upgrade_vigor = 0
	GameState.gold = 100
	_check(GameState.upgrade_cost("weapon") == 50, "0 级强化定价 50（实际 %d）" % GameState.upgrade_cost("weapon"))
	_check(GameState.buy_upgrade("weapon"), "金币足够时购买成功")
	_check(GameState.gold == 50, "购买扣费（100 - 50 = %d）" % GameState.gold)
	_check(GameState.upgrade_level("weapon") == 1, "强化等级 +1")
	_check(GameState.upgrade_cost("weapon") == 90, "1 级递增定价 90（实际 %d）" % GameState.upgrade_cost("weapon"))
	_check(not GameState.buy_upgrade("weapon"), "金币不足时购买被拒绝")
	_check(GameState.gold == 50 and GameState.upgrade_level("weapon") == 1, "拒绝路径不改状态")
	_check(not GameState.buy_upgrade("不存在的种类"), "非法种类被拒绝")
	GameState.stats.upgrade_weapon = 0
	var base_attack: float = GameState.stats.physical_attack()
	GameState.stats.upgrade_weapon = 2
	_check(GameState.stats.physical_attack() > base_attack * 1.25, "武器强化提升物理攻击公式")
	GameState.stats.upgrade_weapon = 1
	# 持久化往返
	GameState.save_now()
	GameState.stats.upgrade_weapon = 0
	GameState.gold = 0
	GameState._load()
	_check(GameState.upgrade_level("weapon") == 1, "读档恢复强化等级（%d == 1）" % GameState.upgrade_level("weapon"))


## 图鉴 / 被动 / 设置 的存档往返
func _test_progress_meta() -> void:
	GameState.codex = {"妖鬼": 5, "獾王": 1}
	GameState.stats.passives = {"hp": 2, "cdr": 1}
	GameState.settings = {"volume": 0.5, "screen_shake": false, "damage_numbers": true}
	GameState.save_now()
	GameState.codex = {}
	GameState.stats.passives = {}
	GameState.settings = {"volume": 0.8, "screen_shake": true, "damage_numbers": true}
	GameState._load()
	_check(int(GameState.codex.get("妖鬼", 0)) == 5 and int(GameState.codex.get("獾王", 0)) == 1,
		"读档恢复图鉴（%s）" % str(GameState.codex))
	_check(GameState.stats.passive_level("hp") == 2 and GameState.stats.passive_level("cdr") == 1,
		"读档恢复被动等级")
	_check(absf(float(GameState.settings["volume"]) - 0.5) < 0.001 and not bool(GameState.settings["screen_shake"]),
		"读档恢复设置（%s）" % str(GameState.settings))
	var hp_before: float = GameState.stats.max_hp()
	GameState.stats.add_passive("hp")
	_check(GameState.stats.max_hp() > hp_before, "被动等级即时影响衍生属性")
	# 装备：四槽位生成/评分替换/词条求和/鞋子保底移速/存档往返/旧档迁移
	GameState.stats.equips = {}
	var weak := {"slot": "weapon", "name": "旧刀", "rarity": 0, "affixes": {"atk": 0.05}}
	var strong := {"slot": "weapon", "name": "新刃", "rarity": 3,
		"affixes": {"atk": 0.20, "hp": 0.10}, "element": "fire"}
	var boots := {"slot": "boots", "name": "快靴", "rarity": 1, "affixes": {"move": 0.10}}
	_check(GameState.try_equip(weak), "空位装备任何掉落")
	_check(GameState.stats.equips["weapon"]["name"] == "旧刀", "装备写入武器槽")
	var gold_before_replace := GameState.gold
	_check(GameState.try_equip(strong), "同槽更高评分替换")
	_check(GameState.gold - gold_before_replace == EconomyMath.sell_price(0),
		"换下的旧装备按稀有度折金（+%d，旧实现直接蒸发）" % (GameState.gold - gold_before_replace))
	_check(GameState.stats.equip_element() == "fire", "武器元素读取")
	_check(GameState.try_equip(boots), "异槽掉落不与武器槽比较（鞋子独立入槽）")
	_check(GameState.stats.equip_affix("atk") > 0.19 and GameState.stats.equip_affix("move") > 0.09,
		"多槽词条求和生效（atk=%.2f move=%.2f）" % [GameState.stats.equip_affix("atk"), GameState.stats.equip_affix("move")])
	var atk_before: float = GameState.stats.physical_attack()
	GameState.stats.equips["weapon"] = {"slot": "weapon", "name": "测试", "rarity": 1, "affixes": {"atk": 0.30}}
	_check(GameState.stats.physical_attack() > atk_before, "装备攻击词条生效")
	GameState.save_now()
	GameState.stats.equips = {}
	GameState._load()
	_check(GameState.stats.equips.get("weapon", {}).get("name", "") == "测试"
			and GameState.stats.equips.get("boots", {}).get("name", "") == "快靴", "读档恢复四槽装备")
	for slot in ["weapon", "helmet", "armor", "boots"]:
		var rolled: Dictionary = GameState.roll_equipment(2, slot)
		var has_move: bool = rolled["affixes"].has("move")
		var ok: bool = rolled.has("name") and rolled["affixes"].size() == 2 and int(rolled["rarity"]) == 2
		if slot == "boots":
			ok = ok and has_move  # 鞋子保底移速词条
		if slot != "weapon":
			ok = ok and not rolled.has("element")  # 元素附魔只在武器槽
		_check(ok, "按部位生成装备（%s）：%s" % [slot, str(rolled)])
	# 旧档迁移：单件时代的 "equip" 键应落到武器槽
	GameState.stats.equips = {}
	var legacy := FileAccess.open(GameState.SAVE_PATH, FileAccess.READ)
	var data: Dictionary = JSON.parse_string(legacy.get_as_text())
	legacy.close()
	data.erase("equips")
	data["equip"] = {"name": "古剑", "rarity": 2, "affixes": {"atk": 0.15}}
	var rewrite := FileAccess.open(GameState.SAVE_PATH, FileAccess.WRITE)
	rewrite.store_string(JSON.stringify(data))
	rewrite.close()
	GameState._load()
	_check(GameState.stats.equips.get("weapon", {}).get("name", "") == "古剑", "旧档单件装备迁移到武器槽")
	# 旧档迁移的消毒：legacy "equip" 内层字段写坏（affixes 为数组）时不得绕过消毒
	# 直接入槽——否则 equip_affix 每次 max_hp() 求值即崩，读档坏档循环
	GameState.stats.equips = {}
	data.erase("equip")
	data["equip"] = {"name": "锈剑", "rarity": 1, "affixes": [1, 2, 3]}
	rewrite = FileAccess.open(GameState.SAVE_PATH, FileAccess.WRITE)
	rewrite.store_string(JSON.stringify(data))
	rewrite.close()
	GameState._load()
	var legacy_affixes: Variant = GameState.stats.equips.get("weapon", {}).get("affixes", null)
	_check(typeof(legacy_affixes) == TYPE_DICTIONARY, "legacy 数组 affixes 被消毒为字典")
	_check(GameState.stats.max_hp() > 0.0, "消毒后的 legacy 装备不炸衍生属性求值")
	# 词条数值硬钳：手改档 atk 9.9 → 0.5（正常掉落理论最大 0.20，钳 2.5 倍余量）
	GameState.stats.equips = {}
	data.erase("equip")
	data["equips"] = {"weapon": {"name": "神装", "rarity": 3, "affixes": {"atk": 9.9}}}
	rewrite = FileAccess.open(GameState.SAVE_PATH, FileAccess.WRITE)
	rewrite.store_string(JSON.stringify(data))
	rewrite.close()
	GameState._load()
	_check(absf(GameState.stats.equip_affix("atk") - GameState.AFFIX_HARD_CAP) < 0.0001,
		"手改档超模词条被钳到硬上限（实际 %.2f）" % GameState.stats.equip_affix("atk"))


## 寿命系统：天数推进/升级延长/倒下缩短/风烛残年衰减/存档往返
func _test_lifespan() -> void:
	GameState.stats.age_days = 3.0
	GameState.stats.lifespan_days = 30.0
	GameState.save_now()
	GameState.stats.age_days = 0.0
	GameState.stats.lifespan_days = 1.0
	GameState._load()
	_check(absf(GameState.stats.age_days - 3.0) < 0.001
			and absf(GameState.stats.lifespan_days - 30.0) < 0.001, "读档恢复寿命（%.0f/%.0f 天）"
			% [GameState.stats.age_days, GameState.stats.lifespan_days])
	# 游戏日推进：信号驱动年龄 +1
	EventBus.game_day_advanced.emit(1)
	_check(absf(GameState.stats.age_days - 4.0) < 0.001, "游戏日推进角色寿命（4 == %.0f）" % GameState.stats.age_days)
	# 升级延长寿命
	GameState.stats.level = 1
	GameState.stats.xp = 0
	var lifespan_before: float = GameState.stats.lifespan_days
	GameState.stats.add_xp(GameState.stats.xp_to_next() + 1)
	_check(GameState.stats.lifespan_days >= lifespan_before + CharacterStats.LEVELED_LIFESPAN_GAIN - 0.001,
		"升级延长寿命（%.0f → %.0f）" % [lifespan_before, GameState.stats.lifespan_days])
	# 倒下缩短寿命
	lifespan_before = GameState.stats.lifespan_days
	EventBus.player_died.emit()
	_check(absf(lifespan_before - GameState.stats.lifespan_days - CharacterStats.DEATH_LIFESPAN_LOSS) < 0.001,
		"倒下缩短寿命（%.0f → %.0f）" % [lifespan_before, GameState.stats.lifespan_days])
	# 风烛残年：寿命充裕无衰减；剩余 2.5 天（窗口一半）衰减到 ~0.8；到点后维持下限 0.6
	_check(absf(GameState.stats.aging_decay() - 1.0) < 0.001, "寿命充裕时无衰老衰减")
	var hp_prime: float = GameState.stats.max_hp()  # 当前装备/被动下的无衰减基准
	GameState.stats.age_days = GameState.stats.lifespan_days - 2.5
	_check(absf(GameState.stats.max_hp() / hp_prime - 0.8) < 0.01,
		"风烛残年渐进衰减（×%.2f）" % (GameState.stats.max_hp() / hp_prime))
	GameState.stats.age_days = GameState.stats.lifespan_days + 10.0
	_check(absf(GameState.stats.max_hp() / hp_prime - 0.6) < 0.01,
		"寿命到点衰减下限（×%.2f）" % (GameState.stats.max_hp() / hp_prime))
	GameState.stats.age_days = 0.0
	GameState.stats.lifespan_days = CharacterStats.BASE_LIFESPAN_DAYS
	GameState._lifespan_warned.clear()


## 生态世界快照（存档 v2）：构造状态 → 存档 → 读档 → 新 sim 恢复，断言关键字段保真
func _test_ecology_snapshot() -> void:
	var regions: Array = []
	for pair in [["west", "plains", 1.0], ["center", "forest", 1.3]]:
		var r := SimRegion.new()
		r.id = pair[0]
		r.terrain = pair[1]
		r.threat = pair[2]
		r.center = Vector2(500, 350)
		r.size = Vector2(1000, 700)
		r.capacity = 10
		regions.append(r)
	var species_list := SpeciesCatalog.build_all()
	var sim := EcologySim.new()
	sim.setup(regions, species_list, {"west": {"妖鬼": 3}, "center": {"红史莱姆": 2}})
	var find := func(name: String) -> SpeciesData:
		for s in species_list:
			if s.species_name == name:
				return s
		return null
	# 丰富状态：精英个体 + 分裂子代（世代/体型）+ 捣毁中的巢穴 + Boss 重生倒计时
	var elite := sim.spawn_instance(find.call("妖鬼"), "west", 50, 0, 1.0, true)
	var child := sim.spawn_instance(find.call("红史莱姆"), "center", 8, 1, 0.6)
	_check(sim.destroy_nest("center", "红史莱姆"), "测试前置：巢穴已捣毁")
	sim.boss_respawn_timers["獾王"] = 123
	var count_before: int = sim.instances.size()
	# 完整链路：挂 WorldSim（save_now 从这里取快照）→ 存档 → 卸载 → 读档 → 新世界恢复
	WorldSim.start(sim)
	GameState.save_now()
	WorldSim.stop()
	GameState.ecology_snapshot = null  # 清直接引用，强制走存档文件链路
	GameState._load()
	_check(GameState.ecology_snapshot != null, "生态快照写入存档并读回")
	var sim2 := EcologySim.new()
	var ok: bool = sim2.restore_from_dict(regions, species_list, GameState.ecology_snapshot)
	GameState.ecology_snapshot = null
	_check(ok, "生态快照恢复成功")
	_check(sim2.instances.size() == count_before,
		"实例数跨会话保真（%d == %d）" % [sim2.instances.size(), count_before])
	var restored_elite: MonsterInstance = sim2.instances.get(elite.id)
	_check(restored_elite != null and restored_elite.is_elite and restored_elite.age == 50,
		"精英标记与年龄跨会话保留")
	var restored_child: MonsterInstance = sim2.instances.get(child.id)
	_check(restored_child != null and restored_child.generation == 1
			and absf(restored_child.size_scale - 0.6) < 0.001,
		"分裂世代与体型跨会话保留")
	_check(int(sim2.boss_respawn_timers.get("獾王", 0)) == 123, "Boss 重生倒计时跨会话保留")
	var nest: Dictionary = sim2.nests.get("center|红史莱姆", {})
	_check(not nest.is_empty() and not nest["active"], "巢穴捣毁状态跨会话保留")
	_check(sim2.next_id > maxi(elite.id, child.id), "实例 id 计数器正确恢复")
	# v1 旧档（无 ecology 键）升级路径：snapshot 为空 = 开新世界，不报错
	var file := FileAccess.open(GameState.SAVE_PATH, FileAccess.READ)
	var data: Dictionary = JSON.parse_string(file.get_as_text())
	file.close()
	data.erase("ecology")
	var rewrite := FileAccess.open(GameState.SAVE_PATH, FileAccess.WRITE)
	rewrite.store_string(JSON.stringify(data))
	rewrite.close()
	GameState._load()
	_check(GameState.ecology_snapshot == null, "v1 旧档无生态键：读档后快照为空（开新世界）")
	# 菜单往返回归：sim 已卸载（WorldSim.sim == null）但 game_world 退出时暂存了快照——
	# 此时落盘（如菜单里拖动音量滑条触发的防抖保存）必须保留 ecology 键，
	# 否则"玩一局→回菜单调个设置"就把演化中的世界静默重置了
	GameState.ecology_snapshot = sim.to_dict()
	GameState.save_now()
	var menu_file := FileAccess.open(GameState.SAVE_PATH, FileAccess.READ)
	var menu_data: Dictionary = JSON.parse_string(menu_file.get_as_text())
	menu_file.close()
	_check(typeof(menu_data.get("ecology", null)) == TYPE_DICTIONARY,
		"菜单期间落盘保留生态快照（sim==null 时回退快照缓存）")
	# 重置世界：快照缓存一并清除，落盘不再带 ecology（下次进世界 = 新世界）
	GameState.reset_all()
	var reset_file := FileAccess.open(GameState.SAVE_PATH, FileAccess.READ)
	var reset_data: Dictionary = JSON.parse_string(reset_file.get_as_text())
	reset_file.close()
	_check(not reset_data.has("ecology"), "重置世界后存档不再携带生态快照")


func _test_corrupted_file() -> void:
	var file := FileAccess.open(GameState.SAVE_PATH, FileAccess.WRITE)
	file.store_string("{这不是合法JSON！！")
	file.close()
	GameState.stats.level = 3
	GameState._load()
	_check(GameState.stats.level == 3, "坏档被安全忽略，内存状态不受影响")
	# 类型错误字段（手改档/三方工具写坏）：不中断 _load 留"半加载"态，逐字段回落默认
	var file2 := FileAccess.open(GameState.SAVE_PATH, FileAccess.WRITE)
	file2.store_string(JSON.stringify({
		"version": 2, "level": [1, 2], "gold": "321", "xp": {"a": 1},
		"strength": true, "codex": {"妖鬼": "很多"}, "age_days": [9],
		"last_save_unix": "昨天",
		"player": {"position": ["墙外", 10.0], "hp": "满血", "mp": null},
	}))
	file2.close()
	GameState.gold = 77
	GameState._load()
	_check(GameState.stats.level == 1 and GameState.gold == 0,
		"类型错误字段安全回落默认（level=%d gold=%d）" % [GameState.stats.level, GameState.gold])
	_check(GameState.stats.strength == 5 and GameState.stats.age_days == 0.0,
		"bool/数组字段回落默认（strength=%d age=%.1f）" % [GameState.stats.strength, GameState.stats.age_days])
	_check(GameState.codex.is_empty(), "图鉴值类型错误被过滤（%s）" % str(GameState.codex))
	_check(GameState.player_snapshot == null, "角色运行态坏字段被整段丢弃")
	_check(GameState.last_save_unix == 0.0, "最后保存时间类型错误回落 0（档案面板显示\"尚未保存\"）")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.SAVE_PATH))


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  PASS  %s" % msg)
	else:
		_fails += 1
		print("  FAIL  %s" % msg)
