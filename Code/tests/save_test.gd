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
	GameState._save_now()
	_check(FileAccess.file_exists(GameState.SAVE_PATH), "存档文件已写入 user://save.json")

	# 篡改内存后重载
	GameState.stats.level = 1
	GameState.stats.xp = 0
	GameState.stats.pending_points = 0
	GameState.stats.strength = 5
	GameState.stats.agility = 5
	GameState.stats.intellect = 5
	GameState.gold = 0
	GameState._load()
	_check(GameState.stats.level == 7, "读档恢复等级（%d == 7）" % GameState.stats.level)
	_check(GameState.stats.xp == 55, "读档恢复经验（%d == 55）" % GameState.stats.xp)
	_check(GameState.stats.pending_points == 3, "读档恢复属性点（%d == 3）" % GameState.stats.pending_points)
	_check(GameState.stats.strength == 9 and GameState.stats.agility == 6
			and GameState.stats.intellect == 4, "读档恢复三维属性")
	_check(GameState.gold == 321, "读档恢复金币（%d == 321）" % GameState.gold)


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
	GameState._save_now()
	GameState.stats.upgrade_weapon = 0
	GameState.gold = 0
	GameState._load()
	_check(GameState.upgrade_level("weapon") == 1, "读档恢复强化等级（%d == 1）" % GameState.upgrade_level("weapon"))


## 图鉴 / 被动 / 设置 的存档往返
func _test_progress_meta() -> void:
	GameState.codex = {"哥布林": 5, "蚁后": 1}
	GameState.stats.passives = {"hp": 2, "cdr": 1}
	GameState.settings = {"volume": 0.5, "screen_shake": false, "damage_numbers": true}
	GameState._save_now()
	GameState.codex = {}
	GameState.stats.passives = {}
	GameState.settings = {"volume": 0.8, "screen_shake": true, "damage_numbers": true}
	GameState._load()
	_check(int(GameState.codex.get("哥布林", 0)) == 5 and int(GameState.codex.get("蚁后", 0)) == 1,
		"读档恢复图鉴（%s）" % str(GameState.codex))
	_check(GameState.stats.passive_level("hp") == 2 and GameState.stats.passive_level("cdr") == 1,
		"读档恢复被动等级")
	_check(absf(float(GameState.settings["volume"]) - 0.5) < 0.001 and not bool(GameState.settings["screen_shake"]),
		"读档恢复设置（%s）" % str(GameState.settings))
	var hp_before: float = GameState.stats.max_hp()
	GameState.stats.add_passive("hp")
	_check(GameState.stats.max_hp() > hp_before, "被动等级即时影响衍生属性")
	# 装备：生成/评分替换/词条生效/存档往返
	GameState.stats.equip = {}
	var weak := {"name": "旧刀", "rarity": 0, "affixes": {"atk": 0.05}}
	var strong := {"name": "新刃", "rarity": 3, "affixes": {"atk": 0.20, "hp": 0.10}, "element": "fire"}
	_check(GameState.try_equip(weak), "空位装备任何掉落")
	_check(GameState.stats.equip["name"] == "旧刀", "装备写入")
	_check(GameState.try_equip(strong), "更高评分装备替换")
	_check(GameState.stats.equip_element() == "fire", "装备元素读取")
	var atk_before: float = GameState.stats.physical_attack()
	GameState.stats.equip = {"name": "测试", "rarity": 1, "affixes": {"atk": 0.30}}
	_check(GameState.stats.physical_attack() > atk_before, "装备攻击词条生效")
	GameState._save_now()
	GameState.stats.equip = {}
	GameState._load()
	_check(GameState.stats.equip.get("name", "") == "测试", "读档恢复装备")
	var rolled := GameState.roll_equipment(2)
	_check(rolled.has("name") and rolled["affixes"].size() == 2
			and int(rolled["rarity"]) == 2, "装备生成（稀有度/2 词条）：%s" % str(rolled))


func _test_corrupted_file() -> void:
	var file := FileAccess.open(GameState.SAVE_PATH, FileAccess.WRITE)
	file.store_string("{这不是合法JSON！！")
	file.close()
	GameState.stats.level = 3
	GameState._load()
	_check(GameState.stats.level == 3, "坏档被安全忽略，内存状态不受影响")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.SAVE_PATH))


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  PASS  %s" % msg)
	else:
		_fails += 1
		print("  FAIL  %s" % msg)
