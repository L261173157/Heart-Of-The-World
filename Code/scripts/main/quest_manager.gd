## 任务系统 v2（世界 v5 地标 NPC 化 + 玩法 v7 P1）：四种任务——狩猎（击杀 N 只
## 某物种）、捣巢（捣毁 N 个巢穴）、探索（发现 N 个地标）、收集（向 NPC 交付
## N 个材料，悬赏按市价双倍溢价）。任务由地标 NPC 发放（石环=营地猎人/
## 荒废遗迹=遗迹学者/精灵泉=泉水守望者/了望石塔=瞭望者/古树=草药师），
## 靠近按攻击键接取；猎杀/捣巢/探索自动结算，新的收集单需返回 NPC 明确交付。
## 数据真源在 GameState.quests（存档 v5 持久化），本节点只做逻辑与信号——
## 进度全部订阅 EventBus，只读世界状态不改写。接取内容按（地标 id × 该 NPC
## 已完成数）确定性生成：读档后同一 NPC 的下一单不漂移。
class_name QuestManager
extends Node

const MAX_ACTIVE := 3
const Presentation := preload("res://scripts/ui/quest_presentation.gd")
const CLAIM_DISTANCE := 220.0
const Camp := preload("res://scripts/main/camp_quest.gd")
const Outpost := preload("res://scripts/main/outpost_quest.gd")
const Inventory := preload("res://scripts/main/camp_quest_inventory.gd")
var _camp: CampQuest
var _outpost: OutpostQuest
var _campaign: CampaignQuest
var _retrying_rewards := false

## 库存信号同步发出，交付会再次触发本管理器；守卫避免重复扣料/重复奖励。
var _reconciling_collect := false
var _collect_recheck := false
var _completing: Dictionary = {}

## game_world 的表现场景登记表（狩猎目标过滤白骨兵物种用）
const _GameWorld := preload("res://scripts/main/game_world.gd")


func _ready() -> void:
	# 保留 NPC/既有测试的组查询；HUD 的追踪与放弃仅经 EventBus 请求
	add_to_group("quest_manager")
	EventBus.monster_killed_by_player.connect(_on_kill)
	EventBus.nest_ransacked.connect(_on_ransack)
	EventBus.landmark_discovered.connect(_on_discover)
	# collect（P1）：进度 = 当前持有数（接单前的存量同样计入）
	EventBus.inventory_changed.connect(_reconcile_collect)
	EventBus.sim_tick_completed.connect(_on_sim_tick)
	# 对话气泡按"是"接单（HUD 发出，气泡自己关闭）。方法引用连接：lambda 捕获
	# self 不受"对象释放自动断连"保护，二周目世界的确认信号会悬空调用已释放的本节点
	EventBus.dialogue_confirmed.connect(_on_dialogue_confirmed)
	EventBus.quest_track_requested.connect(_on_track_requested)
	EventBus.quest_abandon_requested.connect(_on_abandon_requested)
	EventBus.quest_claim_requested.connect(_on_claim_requested)
	_camp = Camp.new()
	_camp.changed.connect(_push_hud)
	add_child(_camp)
	_outpost = Outpost.new()
	_outpost.changed.connect(_push_hud)
	add_child(_outpost)
	_camp.changed.connect(_outpost.sync_legacy_contract)
	_campaign = preload("res://scripts/main/campaign_quest.gd").new()
	_campaign.changed.connect(_push_hud)
	add_child(_campaign)
	EventBus.inventory_changed.connect(_retry_pending_rewards)
	_reconcile_hunts()
	_reconcile_collect()
	_retry_pending_rewards()
	_push_hud()


func _on_dialogue_confirmed(quest: Dictionary) -> void:
	var text: String = accept(quest)
	EventBus.hint_requested.emit("📋 " + quest.get("giver", "") + "：" + text)


## NPC 交互入口（美术 v5 对话化）：返回「结构化委托单」由 HUD 对话气泡展示，
## 玩家按 是/否 决定接取；非委托状态（进行中/栏满/无单）返回纯文本直接播报。
## 返回 {"kind":"quest","quest":{...},"text":...} 或 {"kind":"info","text":...}
func offer(landmark_id: String, quest_kind: String, giver: String) -> Dictionary:
	if quest_kind == "outpost":
		if _campaign != null and _campaign.has_first_clue():
			return _campaign.departure_payload("home:patrol", giver)
		return _outpost.offer(giver)
	if landmark_id == Camp.Data.LANDMARK:
		return _camp.offer(giver)
	var data: Dictionary = GameState.quests
	for q: Dictionary in data["active"]:
		if q.get("landmark_id", "") != landmark_id:
			continue
		var view := Presentation.snapshot(q)
		if view["ui_state"] == "claimable":
			return {"kind": "claim", "state": "claimable", "quest": view,
				"confirm_text": "交付材料", "text": "正是我等的这些。愿意把%s×%d交给我吗？报酬给你备好了。\n报酬：%s" % [
					ItemCatalog.name_of(str(q.get("item", ""))), q["need"], view["ui_reward"]]}
		return {"kind": "info", "state": "in_progress", "text": _npc_progress(q, view), "questions": _npc_questions(q), "rules": _npc_rules(q)}
	if data["active"].size() >= MAX_ACTIVE:
		return {"kind": "info", "state": "unavailable", "text": "你已经应下%d件事了。先把手头的忙完，我这边不催。" % MAX_ACTIVE}
	var quest := _gen_quest(landmark_id, quest_kind, giver)
	if quest.is_empty():
		return {"kind": "info", "state": "unavailable", "text": "眼下没什么适合托付的事。路上多留心，别为我白跑。"}
	var receipt: Dictionary = data.get("receipts", {}).get(landmark_id, {})
	var previous := "上回多亏你了，报酬你已领过。\n" if not receipt.is_empty() else ""
	return {"kind": "quest", "state": "completed" if not receipt.is_empty() else "available",
		"quest": quest, "confirm_text": "我来帮忙",
		"text": previous + _npc_request(quest), "questions": _npc_questions(quest), "rules": _npc_rules(quest)}


## 日常委托仍消费原有目标与数值；居民只说自己托付的事，领取规则另列。
func _npc_request(quest: Dictionary) -> String:
	var need := int(quest.get("need", 0))
	var giver := str(quest.get("giver", ""))
	var text := ""
	match str(quest.get("kind", "")):
		"hunt":
			text = "这附近的%s还得留心。我想请你处理%d只，够了就收手，别追着把整片猎场清空。" % [quest.get("species", ""), need]
		"ransack":
			text = "巢区挤着来路，我想请你捣毁%d处巢穴，给调查遗迹留一点空隙。它们往后还可能重建，经过时仍要小心。" % need
		"collect":
			text = "手边还缺%s×%d。你若找到了，先收好，再带回来交给我；这份材料的报酬我会备着。" % [ItemCatalog.name_of(str(quest.get("item", ""))), need]
		_:
			text = "我望得见近处，却看不清更远的路。替我找%d处还没发现过的地标，让这张图少留些空白。" % need if "瞭望" in giver or "了望" in giver else "泉边总有人问前面的路。你若能找到%d处还没发现过的地标，往后来的人也能多认一点方向。" % need
	return text


func _npc_progress(quest: Dictionary, _view: Dictionary) -> String:
	if quest.get("settlement_blocked", false): return "答应的事你已经做完了。报酬暂时还没能交到你手上，先替你留着。"
	var progress := int(quest.get("progress", 0))
	var need := int(quest.get("need", 1))
	var text := ""
	match str(quest.get("kind", "")):
		"hunt": text = "已经处理%d只，还差%d只。若附近踪迹变了，先看清再动手。" % [progress, maxi(0, need - progress)]
		"ransack": text = "已经捣毁%d处，还剩%d处。留心巢区，别被围住了。" % [progress, maxi(0, need - progress)]
		"collect": text = "目前凑到%d份，还差%d份。先放在你那里，齐了再交给我。" % [progress, maxi(0, need - progress)]
		_: text = "已经添上%d处，还盼着另外%d处的消息。慢慢找，记住回来时的路。" % [progress, maxi(0, need - progress)]
	return text


func _npc_questions(quest: Dictionary) -> Array:
	if quest.get("kind", "") != "hunt": return []
	return [{"label": "去哪里找？", "answer": "先去%s看看。那是我能指给你的搜寻范围，到了再找%s的踪迹。" % [Presentation.hunt_area(quest), quest.get("species", "目标")]}]


func _npc_rules(quest: Dictionary) -> String:
	var policy := "收齐后回到委托人身旁，确认交付才扣除材料并领取报酬。" if Presentation.requires_claim(quest) else "达成后自动领取报酬，无需返回委托人。"
	return "报酬：" + Presentation.reward(quest) + "\n" + policy + "\n" + Presentation.objective(quest)



## 确认接取（对话按"是"后调用）：offer 与 accept 分离保证生成确定性不漂移
func accept(quest: Dictionary) -> String:
	if quest.get("kind", "") == "campaign":
		return _campaign.accept_chapter(str(quest.get("chapter", "")))
	if quest.get("id", "") == Outpost.Data.ID:
		return _outpost.accept()
	if quest.get("id", "") == Camp.Data.ID:
		if not GameState.outpost_quest.is_empty() and not Outpost.Data.valid_legacy(GameState.camp_quest):
			return "新前哨章节已包含一次生态奖励，不能另开重复的营地调查"
		return _camp.accept()
	var data: Dictionary = GameState.quests
	if str(quest.get("id", "")).is_empty() or int(quest.get("need", 0)) <= 0:
		return "委托已失效，请重新交谈"
	var landmark_id := str(quest.get("landmark_id", ""))
	var receipt: Dictionary = data.get("receipts", {}).get(landmark_id, {})
	if receipt.get("id", "") == quest["id"] or (quest.has("offer_index")
			and int(quest["offer_index"]) != int(data["completed"].get(landmark_id, 0))):
		return "此委托已领奖，请重新交谈查看下一单"
	for q: Dictionary in data["active"]:
		if q["id"] == quest["id"] or (landmark_id != "" and q.get("landmark_id", "") == landmark_id):
			return "委托已接取：%s（%d/%d）" % [q["title"], q["progress"], q["need"]]
	if data["active"].size() >= MAX_ACTIVE:
		return "任务栏已满（最多 %d 个）" % MAX_ACTIVE
	# 气泡展示期间种群也会死亡/迁徙；确认时复核而不是把陈旧的 7 只写进任务栏。
	if quest.get("kind", "") == "hunt":
		_refresh_hunt(quest)
	data["active"].append(quest)
	# collect 边界：offer 生成到玩家确认隔最长 12s 气泡窗口，期间可能把材料
	# 卖到低于 need——接单时按当前持有重算进度，旧快照虚标达标会误触结算
	if quest.get("kind", "") == "collect":
		quest["progress"] = mini(GameState.count_item(str(quest.get("item", ""))),
				int(quest.get("need", 1)))
	# 旧收集单保持自动交付；新单材料先保留，返回 NPC 明确确认后扣除。
	if int(quest.get("progress", 0)) >= int(quest.get("need", 1)) and not Presentation.requires_claim(quest):
		_complete(quest)
	else:
		GameState._queue_save()
	_push_hud()
	return "已接取：%s · %s" % [quest["title"], Presentation.objective(quest)]


## NPC 交互入口：接取/查询该 NPC 的任务。返回给玩家的反馈文本
func try_accept(landmark_id: String, quest_kind: String, giver: String) -> String:
	var offered: Dictionary = offer(landmark_id, quest_kind, giver)
	if offered["kind"] in ["info", "claim"]:
		return "%s：%s" % [giver, offered["text"]]
	return accept(offered["quest"])


## 确定性生成该 NPC 的下一单（landmark × 已完成数）；狩猎目标取当前世界
## 活体健康种群（≥3 且有表现场景），无候选返回空
func _gen_quest(landmark_id: String, quest_kind: String, giver: String) -> Dictionary:
	var data: Dictionary = GameState.quests
	var count: int = int(data["completed"].get(landmark_id, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("quest|%s|%d" % [landmark_id, count]) & 0x7FFFFFFF
	var quest := {
		"id": "q_%s_%d" % [landmark_id, count],
		"landmark_id": landmark_id,
		"giver": giver,
		"kind": quest_kind,
		"progress": 0,
		"offer_index": count,
	}
	if quest_kind == "hunt":
		quest["hunt_origin_region"] = _hunt_origin_region(quest)
		var target := _pick_hunt_target(quest, rng)
		if target.is_empty():
			return {}
		quest["species"] = target["species"]
		quest["hunt_region"] = target["region_id"]
		quest["need"] = mini(4 + rng.randi() % 4, int(target["count"]))
		_update_hunt_title(quest)
	elif quest_kind == "ransack":
		quest["need"] = 1 + rng.randi() % 2
		quest["title"] = "捣毁巢穴 ×%d" % quest["need"]
	elif quest_kind == "collect":
		quest["claim_at_npc"] = true
		# 材料池避开被动动物来源（EconomyMath.COLLECT_POOL 注释）；
		# 高价池在 NPC 已完成 ≥3 单后加入（与推进深度对齐）
		var pool: Array = EconomyMath.COLLECT_POOL.duplicate()
		if count >= 3:
			pool.append_array(EconomyMath.COLLECT_POOL_RARE)
		var item: String = pool[rng.randi() % pool.size()]
		quest["item"] = item
		quest["need"] = 3 + rng.randi() % 3
		quest["title"] = "收集：%s ×%d" % [ItemCatalog.name_of(item), quest["need"]]
		quest["progress"] = mini(GameState.count_item(item), quest["need"])
	else:
		quest["need"] = 2 + rng.randi() % 2
		quest["title"] = "探索：发现新地标 ×%d" % quest["need"]
	quest["gold"] = EconomyMath.bounty_gold(quest["need"] + 2, GameState.stats.level)
	if quest_kind == "collect":
		# 收集悬赏 = 赏金 + 材料市价双倍溢价（低于市价玩家宁可卖掉）
		quest["gold"] += roundi(EconomyMath.item_sell_price(quest["item"]) \
				* quest["need"] * EconomyMath.COLLECT_PREMIUM)
	quest["xp"] = EconomyMath.bounty_xp(quest["need"] + 2)
	if quest_kind == "hunt":
		_remember_hunt_reward(quest)
	return quest


## NPC 所在区是任务范围的固定起点，存档后不跟着玩家漂移。
func _hunt_origin_region(quest: Dictionary) -> String:
	if WorldSim.sim == null:
		return ""
	var stored := str(quest.get("hunt_origin_region", ""))
	if WorldSim.sim.get_region(stored) != null:
		return stored
	var landmark := LandmarkRegistry.landmark(str(quest.get("landmark_id", "")))
	var region_id := str(landmark.get("patch_id", ""))
	if WorldSim.sim.get_region(region_id) != null:
		return region_id
	var player := get_tree().get_first_node_in_group("player") as Node2D if is_inside_tree() else null
	if player != null:
		var region := WorldSim.sim.region_of_point(player.global_position)
		if region != null:
			return region.id
	# 无地标/玩家的合成世界兼容；真实 NPC 总能从注册表解析。
	return str(WorldSim.sim.regions.keys()[0]) if not WorldSim.sim.regions.is_empty() else ""


## 分三档：本区 → 邻区 → 已探索个体据点。未探索的遥远全局种群不发单。
func _hunt_targets(quest: Dictionary, minimum: int = 1) -> Array:
	if WorldSim.sim == null:
		return []
	var origin := WorldSim.sim.get_region(_hunt_origin_region(quest))
	var groups: Array = [{}, {}, {}]
	for inst: MonsterInstance in WorldSim.sim.instances.values():
		if not inst.is_alive or inst.species.is_boss \
				or not _GameWorld.MONSTER_SCENES.has(inst.species.species_name):
			continue
		var tier := 2
		if origin != null and inst.region_id == origin.id:
			tier = 0
		elif origin != null and inst.region_id in origin.neighbor_ids:
			tier = 1
		else:
			if not inst.spawn_pos.is_finite():
				continue
			var cell := Vector2i(inst.spawn_pos / WorldConfig.WORLD_SIZE * GameState.FOG_GRID)
			if not GameState.fog_is_explored(cell.x, cell.y):
				continue
		var key := "%s|%s" % [inst.species.species_name, inst.region_id]
		if not groups[tier].has(key):
			groups[tier][key] = {"species": inst.species.species_name,
				"region_id": inst.region_id, "count": 0, "tier": tier}
		groups[tier][key]["count"] += 1
	var targets: Array = []
	for group: Dictionary in groups:
		var keys := group.keys()
		keys.sort()
		for key: String in keys:
			if int(group[key]["count"]) >= minimum:
				targets.append(group[key])
	return targets


func _pick_hunt_target(quest: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var targets := _hunt_targets(quest, 3)
	if targets.is_empty():
		return {}
	var tier: int = targets[0]["tier"]
	var candidates := targets.filter(func(t: Dictionary) -> bool: return int(t["tier"]) == tier)
	return candidates[rng.randi() % candidates.size()]


func _remember_hunt_reward(quest: Dictionary) -> void:
	if not quest.has("hunt_original_need"):
		quest["hunt_original_need"] = maxi(1, int(quest["need"]))
		quest["hunt_original_gold"] = int(quest.get("gold", 0))
		quest["hunt_original_xp"] = int(quest.get("xp", 0))


func _update_hunt_title(quest: Dictionary) -> void:
	var region := WorldSim.sim.get_region(str(quest.get("hunt_region", ""))) if WorldSim.sim != null else null
	var where := " · " + region.display_name if region != null else ""
	var note := " · 等待本地目标" if quest.get("hunt_waiting", false) else ""
	if quest.get("hunt_adjusted", false) and note == "":
		note = " · 数量调整/按量结算"
	quest["title"] = "猎杀：击杀 %s ×%d%s%s" % [quest.get("species", ""), quest["need"], where, note]


## 留住已击杀进度；种群缩减只下调未完成部分，奖励按原单比例，不能白领整单。
## 零进度且已无本地目标时换可完成的本地目标；无候选则明确等待，不静默丢单。
func _refresh_hunt(quest: Dictionary) -> void:
	if WorldSim.sim == null:
		return
	_remember_hunt_reward(quest)
	quest["hunt_origin_region"] = _hunt_origin_region(quest)
	var available := 0
	var nearest := ""
	for target: Dictionary in _hunt_targets(quest):
		if target["species"] == quest.get("species", ""):
			available += int(target["count"])
			if nearest == "":
				nearest = target["region_id"]
	var progress := int(quest.get("progress", 0))
	quest["hunt_waiting"] = false
	if available == 0 and progress == 0:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("quest-repair|%s" % quest.get("id", "")) & 0x7FFFFFFF
		var target := _pick_hunt_target(quest, rng)
		if target.is_empty():
			quest["hunt_waiting"] = true
		else:
			quest["species"] = target["species"]
			nearest = target["region_id"]
			available = int(target["count"])
	if nearest != "":
		quest["hunt_region"] = nearest
	if not quest["hunt_waiting"] and progress + available < int(quest["need"]):
		quest["need"] = progress + available
		quest["hunt_adjusted"] = true
		var fraction := float(quest["need"]) / maxi(1, int(quest["hunt_original_need"]))
		quest["gold"] = floori(int(quest["hunt_original_gold"]) * fraction)
		quest["xp"] = floori(int(quest["hunt_original_xp"]) * fraction)
	_update_hunt_title(quest)


func _on_sim_tick(_summary: Dictionary) -> void:
	_reconcile_hunts()


func _reconcile_hunts() -> void:
	if WorldSim.sim == null:
		return
	var changed := false
	for quest: Dictionary in GameState.quests["active"].duplicate():
		if quest.get("kind", "") != "hunt":
			continue
		var before := quest.duplicate(true)
		_refresh_hunt(quest)
		changed = changed or before != quest
		if not quest.get("hunt_waiting", false) and int(quest["progress"]) >= int(quest["need"]):
			_complete(quest)
			changed = true
	if changed:
		GameState._queue_save()
		_push_hud()


func _on_kill(_xp: int, _gold: int, _monster_name: String, species_name: String) -> void:
	_progress_match(func(q: Dictionary) -> bool:
		return q["kind"] == "hunt" and q.get("species", "") == species_name)


func _on_ransack(_species_name: String) -> void:
	_progress_match(func(q: Dictionary) -> bool: return q["kind"] == "ransack")


func _on_discover(_id: String, _patch: String, _kind: String, _pos: Vector2) -> void:
	_progress_match(func(q: Dictionary) -> bool: return q["kind"] == "explore")


## collect 进度 = 当前持有数（接单前存量也计入；卖掉材料会回退进度）
func _reconcile_collect() -> void:
	if _reconciling_collect:
		_collect_recheck = true
		return
	_reconciling_collect = true
	var changed := false
	while true:
		_collect_recheck = false
		for q: Dictionary in GameState.quests["active"].duplicate():
			if q["kind"] != "collect" or _completing.has(q["id"]):
				continue
			var have := mini(GameState.count_item(str(q.get("item", ""))), int(q["need"]))
			if have != int(q["progress"]):
				q["progress"] = have
				changed = true
			if q.get("settlement_blocked", false):
				var bonus := _bonus_item(q)
				if have < int(q["need"]) or Inventory.can_apply({str(q["item"]): int(q["need"])}, {bonus: 1} if bonus != "" else {}):
					q.erase("settlement_blocked")
					q.erase("blocked_item")
					changed = true
			if int(q["progress"]) >= int(q["need"]) and not Presentation.requires_claim(q):
				_complete(q)
				changed = true
		# 后一单交付可能消耗前一单刚计入的材料，必须重访前面的单。
		# 重入只标脏不递归；每次交付都销掉一单（最多 3 单），因此有界。
		if not _collect_recheck:
			break
	_reconciling_collect = false
	_push_hud()
	if changed:
		GameState._queue_save()


## 点击任务行只追踪；销单必须经过单独的明确放弃请求。
func _on_track_requested(quest_id: String) -> void:
	if quest_id.is_empty():
		GameState.tracked_quest_id = "__untracked__"
		GameState._queue_save()
		_push_hud()
		return
	if _campaign != null and _campaign.owns(quest_id):
		GameState.tracked_quest_id = quest_id
		GameState._queue_save()
		_push_hud()
		return
	if quest_id == Outpost.Data.ID and (_outpost.is_active() or _outpost.guidance_pending()):
		GameState.tracked_quest_id = quest_id
		GameState._queue_save()
		_push_hud()
		return
	if quest_id == Camp.Data.ID and _camp.is_active():
		GameState.tracked_quest_id = quest_id
		GameState._queue_save()
		_push_hud()
		return
	for quest: Dictionary in GameState.quests["active"]:
		if str(quest["id"]) == quest_id:
			GameState.tracked_quest_id = quest_id
			GameState._queue_save()
			_push_hud()
			return


func _on_claim_requested(quest_id: String) -> void:
	var message := claim(quest_id)
	if not message.is_empty():
		EventBus.hint_requested.emit(message)


## 只从真实活动单结算，忽略气泡里的旧奖励/库存快照；重复点击不会认领下一单。
func claim(quest_id: String) -> String:
	if _campaign != null and _campaign.owns(quest_id): return _campaign.claim(quest_id)
	if quest_id == Outpost.Data.ID:
		return _outpost.claim()
	if quest_id == Camp.Data.ID:
		return _camp.claim()
	for quest: Dictionary in GameState.quests["active"]:
		if str(quest["id"]) != quest_id or not Presentation.requires_claim(quest):
			continue
		var player := get_tree().get_first_node_in_group("player") as Node2D
		var nearby := false
		if player != null:
			for node: Node in get_tree().get_nodes_in_group("npcs"):
				if node is Node2D and node.get("landmark_id") == quest.get("landmark_id", "") \
						and (node as Node2D).is_visible_in_tree() \
						and player.global_position.distance_to((node as Node2D).global_position) <= CLAIM_DISTANCE:
					nearby = true
					break
		if not nearby:
			return "请返回%s身边交付领奖" % quest.get("giver", "委托人")
		_reconcile_collect()
		if Presentation.state(quest) != "claimable":
			return "材料不足：%d/%d，尚未交付" % [quest["progress"], quest["need"]]
		if not _complete(quest):
			_push_hud()
			return "当前无法结算，请稍后重试；材料和奖励仍保留"
		_push_hud()
		GameState._queue_save()
		return "交付成功 · 奖励已到账"
	return "此委托已结算或失效"


func _on_abandon_requested(quest_id: String) -> void:
	var message := abandon(quest_id)
	if not message.is_empty():
		EventBus.hint_requested.emit(message)


func abandon(quest_id: String) -> String:
	if _campaign != null and _campaign.owns(quest_id): return _campaign.abandon(quest_id)
	if quest_id == Outpost.Data.ID:
		return _outpost.abandon()
	if quest_id == Camp.Data.ID:
		return _camp.abandon()
	for quest: Dictionary in GameState.quests["active"]:
		if str(quest["id"]) != quest_id:
			continue
		GameState.quests["active"].erase(quest)
		GameState._queue_save()
		_push_hud()
		return "已放弃：%s" % quest["title"]
	return ""


## 仅兼容旧调用者；新的 HUD 不再调用此入口。
func abandon_first() -> String:
	var active: Array = GameState.quests["active"]
	return abandon(str(active[0]["id"])) if not active.is_empty() else ""


func _progress_match(predicate: Callable) -> void:
	var data: Dictionary = GameState.quests
	var changed := false
	for q: Dictionary in data["active"].duplicate():
		if not predicate.call(q):
			continue
		q["progress"] = int(q["progress"]) + 1
		GameState._invalidate_world_save_cache()
		changed = true
		if int(q["progress"]) >= int(q["need"]):
			_complete(q)
	_push_hud()
	if changed:
		GameState._queue_save()


func _bonus_item(quest: Dictionary) -> String:
	return Presentation.bonus_item(quest)

func _complete(quest: Dictionary) -> bool:
	var data: Dictionary = GameState.quests
	if not data["active"].has(quest) or _completing.has(quest["id"]):
		return false
	var costs := {str(quest["item"]): int(quest["need"])} if quest["kind"] == "collect" else {}
	var bonus := _bonus_item(quest)
	var rewards := {bonus: 1} if bonus != "" else {}
	# 全部预检先于扣料、销单、金币/经验发放。材料本次支出释放的空间可使用。
	if not Inventory.can_apply(costs, rewards):
		if quest["kind"] == "collect" and GameState.count_item(str(quest["item"])) < int(quest["need"]):
			quest["progress"] = mini(GameState.count_item(str(quest["item"])), int(quest["need"]))
		else:
			quest["settlement_blocked"] = true
			quest["blocked_item"] = bonus
		GameState._queue_save()
		return false
	_completing[quest["id"]] = true
	GameState.begin_world_reward()
	data["active"].erase(quest)
	GameState._invalidate_world_save_cache()
	var landmark_id := str(quest.get("landmark_id", quest["id"]))
	data["completed"][landmark_id] = int(data["completed"].get(landmark_id, 0)) + 1
	var gold := maxi(0, int(quest.get("gold", 0)))
	var xp := maxi(0, int(quest.get("xp", 0)))
	var paid_gold := roundi(gold * GameState.stats.gold_mult())
	var paid_xp := int(xp * GameState.stats.passive_mult("xp", 1.1) * (1.0 + GameState.stats.equip_affix("xp")))
	Inventory.apply(costs, rewards)
	GameState.add_gold(gold)
	GameState.add_xp(xp)
	var bonus_text := " +%s" % ItemCatalog.name_of(bonus) if bonus != "" else ""
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player != null:
		EventBus.fx_requested.emit("flash_yellow", player.global_position, 1.3)
	SfxManager.play("quest")
	SfxManager.play("gold3")
	var receipt := {"id": str(quest["id"]), "title": str(quest["title"]),
		"gold": paid_gold, "xp": paid_xp,
		"bonus": bonus, "giver": str(quest.get("giver", "")), "kind": str(quest["kind"])}
	if not data.has("receipts"):
		data["receipts"] = {}
	data["receipts"][landmark_id] = receipt
	data["last_receipt"] = landmark_id
	if not GameState.camp_quest.is_empty():
		GameState.camp_quest["last_summary"] = false
	GameState._queue_save()
	GameState.end_world_reward()
	_completing.erase(quest["id"])
	EventBus.quest_completed.emit("✓ %s · %s（+%d 金币 +%d 经验%s）" % [
		quest["title"], "交付领奖成功" if Presentation.requires_claim(quest) else "已自动领奖",
		receipt["gold"], receipt["xp"], bonus_text])
	return true


## 旧自动任务保留自动模式：容量恢复后重试，不能要求玩家再杀/再发现一个。
func _retry_pending_rewards() -> void:
	if _retrying_rewards:
		return
	_retrying_rewards = true
	for quest: Dictionary in GameState.quests["active"].duplicate():
		if quest.get("settlement_blocked", false) and not Presentation.requires_claim(quest) \
				and int(quest.get("progress", 0)) >= int(quest.get("need", 1)):
			_complete(quest)
	_retrying_rewards = false
	_push_hud()


func camp_context() -> Dictionary:
	return _camp.context() if _camp != null else {}

func camp_target() -> Dictionary:
	return _camp.target() if _camp != null else {}

func camp_investigate() -> String:
	return _camp.investigate()

func camp_choose(branch: String) -> String:
	return _camp.choose(branch)

func npc_status(landmark_id: String, quest_kind: String, giver: String) -> Dictionary:
	if quest_kind == "outpost":
		return _outpost.npc_status()
	if landmark_id == Camp.Data.LANDMARK:
		return _camp.npc_status()
	for quest: Dictionary in GameState.quests["active"]:
		if quest.get("landmark_id", "") == landmark_id:
			return Presentation.npc_status(landmark_id)
	if GameState.quests["active"].size() >= MAX_ACTIVE or _gen_quest(landmark_id, quest_kind, giver).is_empty():
		return {"state": "unavailable", "marker": "· 暂无委托", "color": Presentation.PROGRESS_COLOR}
	return Presentation.npc_status(landmark_id)


## 追踪对象失效时仅回退到第一张剩余委托，不改变其进度或奖励。
func _push_hud() -> void:
	var active: Array = GameState.quests["active"].duplicate()
	if _camp != null and _camp.is_active():
		active.append(_camp.snapshot())
	if _outpost != null and (_outpost.is_active() or _outpost.guidance_pending()):
		active.append(_outpost.snapshot())
	if _campaign != null:
		active.append_array(_campaign.snapshots())
	var selected: Dictionary = {}
	for quest: Dictionary in active:
		if str(quest["id"]) == GameState.tracked_quest_id:
			selected = quest
			break
	if selected.is_empty() and not active.is_empty() and GameState.tracked_quest_id != "__untracked__":
		selected = active[0]
	var selected_id := str(selected.get("id", ""))
	if selected_id != GameState.tracked_quest_id and GameState.tracked_quest_id != "__untracked__":
		GameState.tracked_quest_id = selected_id
		GameState._queue_save()
	var views: Array = []
	for quest: Dictionary in active:
		if str(quest.get("id", "")) == selected_id:
			views.push_front(Presentation.snapshot(quest))
		else:
			views.append(Presentation.snapshot(quest))
	EventBus.quest_list_changed.emit(views, selected_id)
	if selected.is_empty():
		if not active.is_empty():
			EventBus.quest_updated.emit("委托未追踪 · 点击查看已有任务")
			return
		var campaign_summary := CampaignQuest.completed_summary(GameState.campaign_quest, true)
		if not campaign_summary.is_empty():
			EventBus.quest_updated.emit(campaign_summary)
			return
		if _outpost != null and GameState.outpost_quest.get("stage", "") == "completed" and GameState.outpost_quest.get("last_summary", false):
			EventBus.quest_updated.emit(_outpost.receipt_text())
			return
		if _camp != null and GameState.camp_quest.get("paid", false) and GameState.camp_quest.get("last_summary", false):
			EventBus.quest_updated.emit(_camp.receipt_text())
			return
		var receipt: Dictionary = GameState.quests.get("receipts", {}).get(GameState.quests.get("last_receipt", ""), {})
		EventBus.quest_updated.emit(Presentation.receipt_text(receipt) if not receipt.is_empty() else "! 委托：找带 ! 的居民接取")
		return
	var view := Presentation.snapshot(selected)
	var others := " +另 %d 项" % (active.size() - 1) if active.size() > 1 else ""
	EventBus.quest_updated.emit("%s %s（%d/%d）%s · %s" % [view["ui_status"], selected["title"],
		selected["progress"], selected["need"], others, view["ui_objective"]])


## 前哨公开接口；表现层只拿快照和提交明确动作，不直接写证据。
func outpost_object_payload(id: String) -> Dictionary:
	return _outpost.object_payload(id)

func outpost_action(id: String) -> String:
	match id.trim_prefix("outpost:"):
		"accept", "resume": return _outpost.accept()
		"investigate": return _outpost.investigate()
		"choose_hunt": return _outpost.choose("hunt")
		"choose_ransack": return _outpost.choose("ransack")
		"find_hunt_clue": return _outpost.find_hunt_clue()
		_: return _outpost.object_action(id.trim_prefix("outpost:"))

func outpost_object_state(id: String) -> Dictionary:
	return _outpost.object_state(id)

func outpost_context() -> Dictionary:
	return _outpost.context()

func outpost_target() -> Dictionary:
	return _outpost.target()

func outpost_snapshot() -> Dictionary:
	return _outpost.snapshot()

func outpost_evidence(id: String) -> bool:
	return _outpost.evidence(id)

func outpost_visual_state() -> Dictionary:
	return _outpost.visual_state()

func outpost_state() -> Dictionary:
	return _outpost.visual_state()

func legacy_camp_offer(giver: String = "营地巡守周照") -> Dictionary:
	var payload := _camp.offer(giver)
	payload["back_action"] = "outpost:menu"
	return payload


func campaign_visual_state() -> Dictionary:
	return _campaign.visual_state() if _campaign != null else {}

func campaign_action(id: String) -> String:
	return _campaign.action(id)
