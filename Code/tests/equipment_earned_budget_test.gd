## 新装备的正常收入验收。复用原Boss战斗/触控机器人/冷存档流程，只替换合法预算分配。
## 不发随机装备、不造掉落、不改Boss/角色当前HP、伤害、锚点、免伤或生态参数。
extends "res://tests/campaign_earned_boss_test.gd"

var _new_build_report: Dictionary = {}


func _purchase_earned_upgrades() -> void:
	_check(GameState.equipment_state.get("items", {}).is_empty()
		and GameState.equipment_drop_state.get("receipts", {}).is_empty(),
		"真实C5来源无额外装备或掉落收据")
	_check(GameState.buy_upgrade("weapon"), "实际50金币买武器强化一级")
	for _i in 2:
		_check(GameState.buy_upgrade("vigor"), "实际购买体魄强化，共两级140金币")
	_check(GameState.stats.upgrade_weapon == 1 and GameState.stats.upgrade_vigor == 2
		and GameState.gold == 101 and GameState.count_item("onigiri") == 5,
		"291实际收入减190强化，剩101金币及五份有收据饭团")


func _after_earned_travel() -> bool:
	_check(BiomeMap.terrain_at(_player.global_position) == "lava", "实际第六章旅行后身体位于熔岩地区")
	# 等真正的世界迷雾更新与五游戏秒空闲，不直接抬物等或修改战斗计时器。
	TouchInput.reset()
	_player.set_physics_process(true)
	var safe_seconds := 0.0
	while safe_seconds < CharacterStats.EQUIP_SAFE_WAIT + 0.05:
		await get_tree().physics_frame
		safe_seconds += get_physics_process_delta_time()
		_freeze_monsters()
	_player.set_physics_process(false)
	_check(GameState.equipment_explored_ilvl == 10, "真实熔岩探索将商店已探索物等提升到10")
	_check(_player.can_change_loadout(), "真实经过至少5游戏秒且无敌追击/残留动作后可装配")
	if _fails > 0: return false
	var bought: Array[Dictionary] = []
	for base_id: String in ["physical_sword", "shield"]:
		var slot := "weapon" if base_id == "physical_sword" else "offhand"
		var offer: Dictionary = GameState.equipment_offer("purchase", slot, base_id)
		_check(not offer.is_empty() and int(offer.get("price", 0)) == 50, "实际商店白装定价50：" + base_id)
		if offer.is_empty(): return false
		var item: Dictionary = offer.get("item", {})
		_check(int(item.get("item_level", 0)) == 10 and int(item.get("rarity", -1)) == 0
			and int(item.get("required_level", 0)) == 3 and item.get("affix_rolls", []).is_empty()
			and str(item.get("mechanism", "")).is_empty(), "iLv10白装只含固定词条，无随机/传奇机制：" + base_id)
		var purchased := GameState.equipment_action("purchase", {"token": str(offer.get("token", ""))}, GameState.equipment_revision())
		_check(bool(purchased.get("ok", false)), "真实钱包/物品事务购买：" + base_id)
		if not purchased.get("ok", false): return false
		var before := _player.save_snapshot()
		var equipped := GameState.equipment_action("equip", {"id": str(item.get("id", ""))}, GameState.equipment_revision())
		_check(bool(equipped.get("ok", false)), "通过真实安全换装服务装备：" + base_id)
		_check(_player.current_hp <= float(before.hp) and _player.current_mp <= float(before.mp)
			and _same(before.combat_timers, _player.save_snapshot().combat_timers),
			"实际换装不补血蓝或刷新冷却：" + base_id)
		if not equipped.get("ok", false): return false
		bought.append(item.duplicate(true))
	_check(GameState.gold == 1, "291−190强化−100两件白装=1，不借未来章节或击杀收入")
	_assert_new_equipment_stats()
	_new_build_report = _current_gear_report()
	_new_build_report["post_purchase_gold"] = GameState.gold
	_new_build_report["safe_wait_game_seconds"] = safe_seconds
	_new_build_report["purchased_items"] = bought
	print("EQUIPMENT_EARNED_PURCHASE ", JSON.stringify(_new_build_report))
	return _fails == 0


func _check_earned_build() -> void:
	_check(GameState.stats.level == 3 and GameState.stats.strength == 7 and GameState.stats.agility == 5
		and GameState.stats.intellect == 5 and GameState.stats.pending_points == 0
		and GameState.stats.upgrade_weapon == 1 and GameState.stats.upgrade_vigor == 2,
		"冷启动合法新装备构筑：Lv3/两点力量/武器强化1/体魄强化2")
	_check(GameState.gold == 13, "开战前钱包仅1余额加实际C6:s1支付12=13金币")
	_check(GameState.stats.passives.is_empty(), "没有选择额外赐福或伪造被动")
	_assert_new_equipment_stats()
	var equipped: Dictionary = GameState.equipment_state.get("equipped", {})
	_check(equipped.size() == 2 and equipped.has("weapon") and equipped.has("offhand"), "两件购买装备经过冷启动仍在对应槽")
	for slot: String in ["weapon", "offhand"]:
		var id := str(equipped.get(slot, ""))
		var item: Dictionary = GameState.equipment_state.get("items", {}).get(id, {})
		_check(id.begins_with("offer:") and int(item.get("item_level", 0)) == 10
			and int(item.get("rarity", -1)) == 0 and not bool(item.get("legacy", true))
			and item.get("affix_rolls", []).is_empty() and str(item.get("mechanism", "")).is_empty(),
			"冷存档保留真正购买的白装ID和固定词条：" + slot)
		_check(str(item.get("base_id", "")) == ("physical_sword" if slot == "weapon" else "shield"),
			"冷存档没有换成其他基底：" + slot)
	_new_build_report = _current_gear_report()


func _assert_new_equipment_stats() -> void:
	_check(is_equal_approx(GameState.stats.max_hp(), 239.2), "正常体魄两级生命上限239.2，未用HP注入")
	_check(is_equal_approx(GameState.stats.physical_attack(), 37.3175), "新白剑实际物攻37.3175，对照旧预算35.75")
	_check(is_equal_approx(GameState.stats.guard_strength(), 44.444), "新白盾实际格挡44.444，对照旧预算41")
	_check(is_equal_approx(GameState.stats.equip_affix("phys"), 0.18)
		and is_equal_approx(GameState.stats.equip_affix("guard"), 0.084), "新装备固定效果恰为物攻18%/格挡8.4%")


func _current_gear_report() -> Dictionary:
	return {"name": "earned_white_sword_shield", "source_gold": 291, "source_xp": 364,
		"upgrade_spend": 190, "white_equipment_spend": 100, "gold": GameState.gold,
		"strength": GameState.stats.strength, "weapon_upgrade": GameState.stats.upgrade_weapon,
		"vigor_upgrade": GameState.stats.upgrade_vigor, "max_hp": GameState.stats.max_hp(),
		"physical_attack": GameState.stats.physical_attack(), "guard_strength": GameState.stats.guard_strength(),
		"equipped": GameState.equipment_state.get("equipped", {}).duplicate(true),
		"items": GameState.equipment_state.get("items", {}).duplicate(true),
		"baseline_attack": 35.75, "baseline_guard": 41.0,
		"assumptions": "genuine main receipts only; two earned STR points; upgrade weapon1/vigor2; purchase ilvl10 fixed white sword+shield after real lava travel/exploration; five paid bonus foods; no random gear/perks"}


func _earned_equipment_report() -> Dictionary:
	return _new_build_report.duplicate(true)


func _finish() -> void:
	print("=== EQUIPMENT EARNED BOSS %s (%d checks, %d failures) ===" % ["PASS" if _fails == 0 else "FAIL", _checks, _fails])
	get_tree().quit(0 if _fails == 0 else 1)
