## 任务系统 v2（世界 v5 地标 NPC 化 + 玩法 v7 P1）：四种任务——狩猎（击杀 N 只
## 某物种）、捣巢（捣毁 N 个巢穴）、探索（发现 N 个地标）、收集（向 NPC 交付
## N 个材料，悬赏按市价双倍溢价）。任务由地标 NPC 发放（石环=营地猎人/
## 荒废遗迹=遗迹学者/精灵泉=泉水守望者/了望石塔=瞭望者/古树=草药师），
## 靠近按攻击键接取；达成自动结算（金币+经验+物品奖励，公式与赏金同源）。
## 数据真源在 GameState.quests（存档 v5 持久化），本节点只做逻辑与信号——
## 进度全部订阅 EventBus，只读世界状态不改写。接取内容按（地标 id × 该 NPC
## 已完成数）确定性生成：读档后同一 NPC 的下一单不漂移。
class_name QuestManager
extends Node

const MAX_ACTIVE := 3

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
	_reconcile_hunts()
	_reconcile_collect()
	_push_hud()


func _on_dialogue_confirmed(quest: Dictionary) -> void:
	var text: String = accept(quest)
	EventBus.hint_requested.emit("📋 " + quest.get("giver", "") + "：" + text)


## NPC 交互入口（美术 v5 对话化）：返回「结构化委托单」由 HUD 对话气泡展示，
## 玩家按 是/否 决定接取；非委托状态（进行中/栏满/无单）返回纯文本直接播报。
## 返回 {"kind":"quest","quest":{...},"text":...} 或 {"kind":"info","text":...}
func offer(landmark_id: String, quest_kind: String, giver: String) -> Dictionary:
	var data: Dictionary = GameState.quests
	for q: Dictionary in data["active"]:
		if q.get("landmark_id", "") == landmark_id:
			return {"kind": "info",
				"text": "任务进行中——%s（%d/%d）" % [q["title"], q["progress"], q["need"]]}
	if data["active"].size() >= MAX_ACTIVE:
		return {"kind": "info", "text": "任务栏已满（最多 %d 个），先完成几单吧" % MAX_ACTIVE}
	var quest := _gen_quest(landmark_id, quest_kind, giver)
	if quest.is_empty():
		return {"kind": "info", "text": "眼下没有合适的委托…"}
	return {"kind": "quest", "quest": quest,
		"text": "有一单委托——%s（+%d 金币 +%d 经验），接下吗？" % [
			quest["title"], quest["gold"], quest["xp"]]}


## 确认接取（对话按"是"后调用）：offer 与 accept 分离保证生成确定性不漂移
func accept(quest: Dictionary) -> String:
	var data: Dictionary = GameState.quests
	for q: Dictionary in data["active"]:
		if q["id"] == quest.get("id", ""):
			return "%s：任务进行中——%s" % [quest.get("giver", ""), q["title"]]
	# 气泡展示期间种群也会死亡/迁徙；确认时复核而不是把陈旧的 7 只写进任务栏。
	if quest.get("kind", "") == "hunt":
		_refresh_hunt(quest)
	data["active"].append(quest)
	# collect 边界：offer 生成到玩家确认隔最长 12s 气泡窗口，期间可能把材料
	# 卖到低于 need——接单时按当前持有重算进度，旧快照虚标达标会误触结算
	if quest.get("kind", "") == "collect":
		quest["progress"] = mini(GameState.count_item(str(quest.get("item", ""))),
				int(quest.get("need", 1)))
	# 存量达标 → 立即结算（悬赏是收购要约，货够即成）
	if int(quest.get("progress", 0)) >= int(quest.get("need", 1)):
		_complete(quest)
	else:
		GameState._queue_save()
	_push_hud()
	return "接取委托——%s" % quest["title"]


## NPC 交互入口：接取/查询该 NPC 的任务。返回给玩家的反馈文本
func try_accept(landmark_id: String, quest_kind: String, giver: String) -> String:
	var offered: Dictionary = offer(landmark_id, quest_kind, giver)
	if offered["kind"] == "info":
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
			if int(q["progress"]) >= int(q["need"]):
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
	for quest: Dictionary in GameState.quests["active"]:
		if str(quest["id"]) == quest_id:
			GameState.tracked_quest_id = quest_id
			GameState._queue_save()
			_push_hud()
			return


func _on_abandon_requested(quest_id: String) -> void:
	var message := abandon(quest_id)
	if not message.is_empty():
		EventBus.hint_requested.emit(message)


func abandon(quest_id: String) -> String:
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


func _complete(quest: Dictionary) -> void:
	var data: Dictionary = GameState.quests
	if not data["active"].has(quest) or _completing.has(quest["id"]):
		return
	_completing[quest["id"]] = true
	# collect 先扣材料再销单：库存意外不足（接单后卖掉等边角）时不销单不计数，
	# 进度回落到当前持有等再攒——先销单后扣料的旧顺序在扣料失败时任务已没了、
	# 完成数已加、奖励没发（与"不结算不销单"的注释语义相反）
	if quest["kind"] == "collect" and not GameState.remove_item(quest["item"], int(quest["need"])):
		quest["progress"] = mini(GameState.count_item(str(quest["item"])), int(quest["need"]))
		_completing.erase(quest["id"])
		return
	data["active"].erase(quest)
	GameState._invalidate_world_save_cache()
	_completing.erase(quest["id"])
	var landmark_id := str(quest.get("landmark_id", quest["id"]))
	data["completed"][landmark_id] = int(data["completed"].get(landmark_id, 0)) + 1
	# 老档消毒允许缺失奖励字段；恢复时自动结算同样必须安全回落。
	var gold := maxi(0, int(quest.get("gold", 0)))
	var xp := maxi(0, int(quest.get("xp", 0)))
	GameState.add_gold(gold)
	GameState.add_xp(xp)
	# 物品奖励（P1）：collect 固定附金钥匙（lava 城塞的钥匙闭环）；其余任务
	# 按 hash(单号) 确定性 30% 附一件随机补给（无 RNG——同单任何端结果一致）
	var bonus := ""
	if quest["kind"] == "collect":
		bonus = EconomyMath.KEY_GOLD
	elif not quest.get("hunt_adjusted", false) and hash("quest-bonus|%s" % quest["id"]) % 10 < 3:
		var pool: Array = EconomyMath.BOSS_BONUS_POOL
		bonus = pool[hash("quest-bonus2|%s" % quest["id"]) % pool.size()]
	var bonus_text := ""
	if bonus != "":
		GameState.add_item(bonus, 1)
		bonus_text = " +%s" % ItemCatalog.name_of(bonus)
	# 结算金闪（美术 v5 fx 全量）：在玩家位置炸开
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player != null:
		EventBus.fx_requested.emit("flash_yellow", player.global_position, 1.3)
	SfxManager.play("quest")
	SfxManager.play("gold3")
	EventBus.quest_completed.emit("✅ %s 完成（+%d 金币 +%d 经验%s）" % [
		quest["title"], gold, xp, bonus_text])


## 追踪对象失效时仅回退到第一张剩余委托，不改变其进度或奖励。
func _push_hud() -> void:
	var active: Array = GameState.quests["active"]
	var selected: Dictionary = {}
	for quest: Dictionary in active:
		if str(quest["id"]) == GameState.tracked_quest_id:
			selected = quest
			break
	if selected.is_empty() and not active.is_empty():
		selected = active[0]
	var selected_id := str(selected.get("id", ""))
	if selected_id != GameState.tracked_quest_id:
		GameState.tracked_quest_id = selected_id
		GameState._queue_save()
	EventBus.quest_list_changed.emit(active.duplicate(true), selected_id)
	if selected.is_empty():
		EventBus.quest_updated.emit("")
		return
	var others := " +另 %d 项" % (active.size() - 1) if active.size() > 1 else ""
	EventBus.quest_updated.emit("📜 %s（%d/%d）%s" % [selected["title"], selected["progress"], selected["need"], others])
