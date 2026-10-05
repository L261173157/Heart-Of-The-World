## 核心边界回归；真实演员/触屏闭环另由 camp_pilot_contract/UI 契约覆盖。
extends Node2D

const Data := preload("res://scripts/main/camp_quest_data.gd")
const Inventory := preload("res://scripts/main/camp_quest_inventory.gd")
var _checks := 0
var _fails := 0
var _qm: QuestManager
var _player: Node2D
var _npc: Node2D

class TestNPC extends Node2D:
	var landmark_id := "camp_ecology"

func _ready() -> void:
	GameState.save_enabled = false
	GameState.SAVE_PATH = "user://camp_quest_core_%d.json" % OS.get_process_id()
	GameState.reset_all()
	WorldSim.stop()
	WorldSim.sim = null
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("  %s %s" % ["PASS" if ok else "FAIL", label])

func _legacy(id: String, kind: String = "collect") -> Dictionary:
	return {"id": id, "landmark_id": id, "giver": "委托人", "title": "容量回归",
		"kind": kind, "item": "tea-leaf", "need": 3, "progress": 3,
		"gold": 25, "xp": 20, "claim_at_npc": true}

func _run() -> void:
	_player = Node2D.new()
	_player.add_to_group("player")
	add_child(_player)
	_npc = TestNPC.new()
	_npc.add_to_group("npcs")
	add_child(_npc)
	_qm = QuestManager.new()
	add_child(_qm)
	await get_tree().process_frame
	await get_tree().process_frame
	_test_sanitize()
	_test_inventory()
	_test_legacy()
	_test_camp_ledger()
	_test_known_facts_and_choices()
	await _test_loaded_target_positions()
	print("=== CAMP QUEST CORE %s (%d checks, %d failures) ===" % ["PASS" if _fails == 0 else "FAIL", _checks, _fails])
	get_tree().quit(0 if _fails == 0 else 1)

func _test_sanitize() -> void:
	for bad: Variant in [null, [], 4, "camp", {"id": "other"}]:
		_check(Data.sanitize(bad).is_empty(), "错误顶层/链ID拒绝")
	var q := Data.sanitize({"id": Data.ID, "stage": "garbage", "target": {"pos": [{}, 0]}, "gold": NAN})
	_check(q["stage"] == "investigate" and q["target"].is_empty() and q["gold"] == 39, "坏阶段/坐标/NaN奖励独立恢复")
	q = Data.sanitize({"id": Data.ID, "stage": "return", "active": true, "investigated": false})
	_check(q["stage"] == "investigate", "未实际调查的返回阶段不能冷加载领奖")
	q = Data.sanitize({"id": Data.ID, "stage": "return", "active": true, "investigated": true,
		"outcome": "hunt", "target": {"pos": [INF, 1], "region_id": "test", "species": "地精矿工"}})
	_check(q["stage"] == "investigate" and not Data.has_result(q), "非法目标加布尔调查标志不能造出领奖凭据")
	q = Data.sanitize({"id": Data.ID, "stage": "return", "active": true, "investigated": true,
		"outcome": "hunt", "surveys": ["test|地精矿工"], "kills": [NAN, 4.5],
		"target": {"pos": [1, 1], "region_id": "test", "species": "地精矿工", "need": 1}})
	_check(q["stage"] != "return" and q["kills"].is_empty() and q["target"]["need"] == 2, "无真实行动的返回状态和坏击杀ID隔离")
	q = Data.sanitize({"id": Data.ID, "paid": true, "active": true, "stage": "return", "kills": [4, 4, -1, "x"],
		"target": {"pos": [5, 6], "species": "地精矿工", "region_id": "test", "need": {}, "kill_start": []}})
	_check(q["stage"] == "completed" and not q["active"] and q["paid"], "已支付凭证优先，禁止恢复为可领奖")
	_check(q["kills"] == [4] and q["target"]["need"] == 2 and q["target"]["kill_start"] == 0, "坏数值类型隔离与击杀ID去重")

	var receipt := {"id": Data.ID, "active": false, "paid": true, "last_summary": true, "investigated": true,
		"stage": "completed", "choice": "hunt", "outcome": "hunt", "kills": [10, 11],
		"target": {"pos": [3000, 3000], "region_id": "test", "species": "地精矿工"},
		"surveys": ["test|地精矿工"], "history": ["已到场调查", "已返回营地交付，奖励已领取"],
		"paid_gold": 39, "paid_xp": 44}
	for flag: String in ["active", "paid", "last_summary", "investigated"]:
		for bad: Variant in ["true", 1, {}]:
			var damaged := receipt.duplicate(true)
			damaged[flag] = bad
			q = Data.sanitize(damaged)
			_check(not q.is_empty() and q["paid"] and q["stage"] == "completed" and not q["active"]
				and q["kills"] == [10, 11] and q["surveys"] == ["test|地精矿工"]
				and q["paid_gold"] == 39 and q["paid_xp"] == 44,
				"单个坏布尔不丢有效账本/已付收据：%s/%s" % [flag, type_string(typeof(bad))])
	var unpaid := receipt.duplicate(true)
	unpaid["stage"] = "act"
	unpaid["paid"] = "true"
	unpaid["paid_gold"] = 0
	unpaid["paid_xp"] = 0
	q = Data.sanitize(unpaid)
	_check(not q["paid"] and q["stage"] == "act", "未支付阶段不把字符串true解释成支付许可")

func _test_inventory() -> void:
	GameState.inventory = {"onigiri": 99, "gold-key": 99, "tea-leaf": 3}
	var keys_before := _pending_total("gold-key")
	var rice_before := _pending_total("onigiri")
	_check(Inventory.apply({"tea-leaf": 3}, {"gold-key": 1}), "奖励满99仍原子完成交易")
	_check(GameState.count_item("tea-leaf") == 0 and GameState.count_item("gold-key") == 99
		and _pending_total("gold-key") == keys_before + 1, "成本一次扣除，溢出钥匙完整留在持久收据")
	_check(Inventory.apply({}, {"onigiri": 1, "water-pot": 1}), "混合可装和溢出奖励同一事务到账")
	_check(GameState.count_item("water-pot") == 1 and _pending_total("onigiri") == rice_before + 1, "可装奖励和待领取余量总数守恒")
	_check(_pending_sources_unique(), "每个溢出收据具有唯一非空来源和正数余量")
	var pending_before := GameState.pending_items.duplicate(true)
	_check(Inventory.apply({"gold-key": 1}, {"gold-key": 1}), "同物品先扣后奖正常提交")
	_check(GameState.count_item("gold-key") == 99 and GameState.pending_items == pending_before, "同物品净额精确且不凭空创建溢出")
	var before := GameState.inventory.duplicate(true)
	_check(not Inventory.apply({"tea-leaf": 4}, {"water-pot": 1}), "成本不足仍拒绝整个交易")
	_check(before == GameState.inventory and pending_before == GameState.pending_items, "缺料失败既不改库存也不产生待领取")

func _test_legacy() -> void:
	GameState.quests = {"active": [], "completed": {}, "receipts": {}, "last_receipt": ""}
	GameState.inventory = {"gold-key": 99, "tea-leaf": 3}
	var q := _legacy("capacity_collect")
	GameState.quests["active"].append(q)
	var gold := GameState.gold
	var xp := GameState.stats.xp
	var pending_before := _pending_total("gold-key")
	_check(_qm._complete(q), "旧手动收集满包仍完整结算")
	_check(not GameState.quests["active"].has(q) and GameState.count_item("tea-leaf") == 0, "完成一次后移除任务并扣足成本")
	_check(GameState.gold == gold + 25 and GameState.stats.xp == xp + 20
		and GameState.quests["completed"]["capacity_collect"] == 1, "金币经验完成数在同次原子提交精确支付")
	_check(GameState.count_item("gold-key") == 99 and _pending_total("gold-key") == pending_before + 1, "整单奖励未截断，满额钥匙保存待领取")
	var receipts := GameState.pending_items.duplicate(true)
	_check(not _qm._complete(q) and GameState.gold == gold + 25 and GameState.pending_items == receipts, "重复结算不重付金币也不重复创建收据")
	GameState.remove_item("gold-key", 1)
	_check(_pending_total("gold-key") == pending_before + 1 and GameState.count_item("gold-key") == 98, "腾出空间不暗中领取已保存余量")
	_check(_claim_one_pending("gold-key") and GameState.count_item("gold-key") == 99
		and _pending_total("gold-key") == pending_before, "明确领取恢复一格且待领取总量准确减少一件")
	var id := ""
	for i in 100:
		var candidate := "retry_bonus_%d" % i
		if hash("quest-bonus|%s" % candidate) % 10 < 3:
			id = candidate
			break
	q = _legacy(id, "explore")
	q.erase("claim_at_npc")
	var bonus: String = _qm._bonus_item(q)
	GameState.inventory[bonus] = 99
	GameState.quests["active"].append(q)
	gold = GameState.gold
	pending_before = _pending_total(bonus)
	_check(_qm._complete(q), "旧自动探索满包仍在原触发点支付")
	_check(not GameState.quests["active"].has(q) and GameState.gold == gold + 25
		and _pending_total(bonus) == pending_before + 1, "自动模式不增加现场动作要求且保存完整奖品")
	receipts = GameState.pending_items.duplicate(true)
	GameState.remove_item(bonus, 1)
	_check(GameState.gold == gold + 25 and GameState.pending_items == receipts, "库存变化信号不重试已付任务或复制收据")
	_check(GameState.count_item(bonus) == 98 and GameState.quests["completed"][id] == 1, "任务报酬恰好一次；待领取保持显式")
	q = _legacy("same_item")
	q["item"] = "gold-key"
	q["need"] = 1
	q["progress"] = 1
	GameState.inventory["gold-key"] = 99
	GameState.quests["active"].append(q)
	pending_before = _pending_total("gold-key")
	_check(_qm._complete(q) and GameState.count_item("gold-key") == 99
		and _pending_total("gold-key") == pending_before, "实际委托同物品先扣再奖不会虚增溢出")

func _test_camp_ledger() -> void:
	_check(_qm.offer(Data.LANDMARK, "camp_ecology", "营地巡守")["kind"] == "info", "无真实世界目标不可在桌面生成有奖空单")
	_check(GameState.camp_quest.is_empty(), "仅打开NPC不创建调查证据")
	var raw := {"id": Data.ID, "active": true, "stage": "act", "investigated": true, "choice": "hunt",
		"target": {"region_id": "test", "species": "地精矿工", "pos": [3000, 3000]}, "kills": [10], "surveys": ["test|地精矿工"], "history": ["真实调查记录"]}
	GameState.camp_quest = Data.sanitize(raw)
	var before := GameState.camp_quest.duplicate(true)
	_check(_qm.camp_investigate().contains("抵达"), "异地不能登记现场调查")
	_check(GameState.camp_quest == before, "失败调查不篡改历史")
	_qm.abandon(Data.ID)
	_check(not GameState.camp_quest["active"] and GameState.camp_quest["kills"] == [10], "放弃仅暂停链，保留真实贡献")
	_qm.accept({"id": Data.ID})
	_check(GameState.camp_quest["active"] and GameState.camp_quest["stage"] == "act" and GameState.camp_quest["kills"] == [10], "重新接取复用同阶段历史")
	_qm._on_track_requested("")
	_qm._push_hud()
	_check(GameState.tracked_quest_id == "__untracked__" and GameState.camp_quest["active"], "取消追踪不会自动回选或放弃")
	GameState.camp_quest["stage"] = "return"
	GameState.camp_quest["outcome"] = "survey"
	GameState.inventory["onigiri"] = 99
	var gold := GameState.gold
	var pending_before := _pending_total("onigiri")
	_check(_qm.claim(Data.ID).contains("交付成功"), "返回真实营地NPC旁满包也可手动完整交付")
	_check(GameState.camp_quest["paid"] and GameState.gold > gold
		and _pending_total("onigiri") == pending_before + 1, "金币与已付收据同时提交，奖品溢出不截断")
	_check(_pending_sources_unique(), "营地奖励同样具有唯一持久来源")
	_check(GameState.camp_quest["paid"] and not GameState.camp_quest["active"], "成功账本写稳定已付标记")
	gold = GameState.gold
	GameState.remove_item("onigiri", 1)
	var inventory_after_paid := GameState.inventory.duplicate(true)
	_qm.claim(Data.ID)
	_qm.accept({"id": Data.ID})
	_check(GameState.gold == gold and GameState.inventory == inventory_after_paid and GameState.camp_quest["paid"], "已腾出奖励空间后重复领取/重接仍不重付")
	var loaded: Dictionary = Data.sanitize(JSON.parse_string(JSON.stringify(GameState.camp_quest)))
	_check(loaded["paid"] and loaded["stage"] == "completed" and loaded["kills"] == [10], "JSON往返保持阶段/历史/支付幂等")
	loaded["paid"] = "false"
	GameState.camp_quest = Data.sanitize(loaded)
	_qm.accept({"id": Data.ID})
	_qm.claim(Data.ID)
	_check(GameState.camp_quest["paid"] and not GameState.camp_quest["active"] and GameState.gold == gold and GameState.inventory == inventory_after_paid,
		"已完成收据的paid字段损坏不能通过重接/交付重复支付")


func _test_known_facts_and_choices() -> void:
	var home := WorldConfig.spawn_pos()
	var region := SimRegion.new()
	region.id = "test"
	region.center = home
	region.size = Vector2(1000, 1000)
	var species: SpeciesData = load("res://data/species/goblin.tres")
	var catalog: Array[SpeciesData] = [species]
	var sim := EcologySim.new()
	sim.setup([region], catalog, {region.id: {species.species_name: 3}})
	WorldSim.sim = sim
	for inst: MonsterInstance in sim.instances.values():
		inst.age = 0
		inst.is_elite = false
		inst.spawn_pos = home
	var key := region.id + "|" + species.species_name
	GameState.camp_quest = Data.sanitize({"id": Data.ID, "active": true, "stage": "act", "investigated": true,
		"choice": "hunt", "surveys": [key], "target": {"region_id": region.id, "species": species.species_name, "pos": [home.x, home.y]}})
	_player.global_position = home + Vector2(2000, 0)
	var objective_before: String = _qm._camp.objective()
	_check(objective_before.contains("现状待到场确认"), "远端任务只显示历史目标和待核实现状")
	sim.destroy_nest(region.id, species.species_name)
	_qm._camp._on_tick({})
	_check(_qm._camp.objective() == objective_before and _qm._camp.snapshot()["ui_objective"] == objective_before,
		"远端巢穴变化经过生态tick也不会隔空泄露到任务目标")
	_player.global_position = home + Vector2(60, 0)
	_check(_qm._camp.context()["on_site"] and _qm._camp.objective().contains("现场已变化"),
		"实际可见现场才更新目标变化提示")
	sim.nests[key]["active"] = true
	(sim.instances.values()[0] as MonsterInstance).is_alive = false
	GameState.camp_quest["stage"] = "choose"
	GameState.camp_quest["choice"] = ""
	var options: Array = _qm._camp.choice_payload()["options"]
	_check(not options[0]["enabled"] and options[0]["label"].contains("不可用")
		and options[0]["disabled_reason"].contains("当前2只") and options[1]["enabled"],
		"仅剩两只时有限狩猎明确不可用，仍保留可行捣巢选项")
	_check(options.size() == 3 and options[2].get("utility", false) and options[2]["action"] == "find_hunt_clue",
		"狩猎不可用时明确提供可选择的替代线索行动")
	GameState.camp_quest["kills"] = [999]
	options = _qm._camp.choice_payload()["options"]
	_check(options[0]["enabled"] and options[0]["consequence"].contains("再猎杀1只"),
		"保留一只历史贡献后正确显示只需再猎杀一只")
	GameState.camp_quest["kills"] = []
	_qm._camp.find_hunt_clue()
	_check(GameState.camp_quest["stage"] == "return" and GameState.camp_quest["outcome"] == "survey"
		and GameState.camp_quest["surveys"].has(key) and sim.nests[key]["active"],
		"主动核对无替代后凭真实现场记录交付，不强迫捣巢且不改生态")
	WorldSim.sim = null


func _test_loaded_target_positions() -> void:
	GameState.reset_all()
	GameState.world_seed = BiomeMap.DEFAULT_SEED
	BiomeMap.configure(GameState.world_seed)
	ObstacleField.restore_destroyed([])
	seed(20261004)
	var regions: Array = []
	for definition: Dictionary in WorldConfig.region_defs():
		var region := SimRegion.new()
		region.id = definition["id"]
		region.display_name = definition["name"]
		region.terrain = definition["terrain"]
		region.threat = definition["threat"]
		region.center = definition["center"]
		region.size = definition["size"]
		region.capacity = definition["capacity"]
		region.neighbor_ids.assign(definition["neighbors"])
		regions.append(region)
	var sim := EcologySim.new()
	sim.setup(regions, SpeciesCatalog.build_all(), WorldConfig.initial_population(), WorldConfig.boss_anchors())
	WorldSim.sim = sim
	_player.global_position = WorldConfig.spawn_pos()
	var clue: String = _qm._camp._next_clue()
	var has_direction := false
	for direction: String in ["东", "西", "南", "北"]:
		has_direction = has_direction or clue.contains(direction)
	_check(clue.contains("营地") and has_direction and clue.contains("自由探索"),
		"下一地区线索使用真实邻区的粗方向并保留自由探索")
	var selector: CampQuestTargets = _qm._camp._targets
	var first := await selector.select_target()
	_check(not first.is_empty() and first["species"] == "地精矿工" and first.get("target_ids", []).size() >= 3,
		"真实默认生态基线选中三个已核验可达矿工ID")
	if first.is_empty():
		WorldSim.sim = null
		return
	var actors: Array[Node] = []
	var anchors := {}
	for inst: MonsterInstance in sim.instances.values():
		if inst.is_alive and inst.region_id == first["region_id"] and inst.species.species_name == first["species"]:
			var body: MonsterBase = preload("res://scripts/main/game_world.gd").MONSTER_SCENES[inst.species.species_name].instantiate()
			add_child(body)
			body.set_physics_process(false)
			body.setup(inst)
			body._nav.avoidance_enabled = false
			anchors[inst.id] = inst.spawn_pos
			body.global_position = _player.global_position + Vector2(90 + actors.size() * 30, 0)
			actors.append(body)
	_qm._camp._preview = first
	_check(not _qm._camp._preview_current(), "实际加载怪追逐离巢后出生锚点不能充当可用存量")
	var second := await selector.select_target()
	_qm._camp._preview = second
	_check(not second.is_empty() and second["key"] != first["key"] and _qm._camp._preview_current(),
		"选择器跳过离巢组并返回真实可行替代据点，不循环发失效邀约")
	var anchors_kept := true
	for id: int in anchors:
		anchors_kept = anchors_kept and sim.instances[id].spawn_pos == anchors[id]
	_check(anchors_kept, "实时位置选择不迁移或篡改生态出生锚点")
	for body: Node in actors:
		body.queue_free()
	await get_tree().process_frame
	WorldSim.sim = null


func _pending_total(item_id: String) -> int:
	var total := 0
	for receipt: Dictionary in GameState.pending_items.values():
		if receipt.get("item_id", "") == item_id: total += int(receipt.get("count", 0))
	return total


func _claim_one_pending(item_id: String) -> bool:
	for receipt: Dictionary in GameState.pending_items.values():
		if receipt.get("item_id", "") == item_id:
			return bool(GameState.equipment_action("claim_pending", {"id": receipt["id"]}, GameState.equipment_revision()).get("ok", false))
	return false


func _pending_sources_unique() -> bool:
	var sources := {}
	for key: String in GameState.pending_items:
		var receipt: Dictionary = GameState.pending_items[key]
		var source := str(receipt.get("source", ""))
		if source.is_empty() or sources.has(source) or receipt.get("id", "") != key or int(receipt.get("count", 0)) <= 0: return false
		sources[source] = true
	return true
