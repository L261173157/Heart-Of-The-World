## 任务系统 v1（世界 v5 地标 NPC 化）：三种任务——狩猎（击杀 N 只某物种）、
## 捣巢（捣毁 N 个巢穴）、探索（发现 N 个地标）。任务由地标 NPC 发放
## （石环=营地猎人/荒废遗迹=遗迹学者/精灵泉=泉水守望者），靠近按攻击键接取；
## 达成自动结算（金币+经验，公式与赏金同源 EconomyMath）。
## 数据真源在 GameState.quests（存档 v5 持久化），本节点只做逻辑与信号——
## 进度全部订阅 EventBus，只读世界状态不改写。接取内容按（地标 id × 该 NPC
## 已完成数）确定性生成：读档后同一 NPC 的下一单不漂移。
class_name QuestManager
extends Node

const MAX_ACTIVE := 3

## game_world 的表现场景登记表（狩猎目标过滤幽灵物种用）
const _GameWorld := preload("res://scripts/main/game_world.gd")


func _ready() -> void:
	EventBus.monster_killed_by_player.connect(_on_kill)
	EventBus.nest_ransacked.connect(_on_ransack)
	EventBus.landmark_discovered.connect(_on_discover)
	# 对话气泡按"是"接单（HUD 发出，气泡自己关闭）
	EventBus.dialogue_confirmed.connect(func(quest: Dictionary) -> void:
		var text: String = accept(quest)
		EventBus.hint_requested.emit("📋 " + quest.get("giver", "") + "：" + text))
	_push_hud()


## NPC 交互入口（美术 v5 对话化）：返回「结构化委托单」由 HUD 对话气泡展示，
## 玩家按 是/否 决定接取；非委托状态（进行中/栏满/无单）返回纯文本直接播报。
## 返回 {"kind":"quest","quest":{...},"text":...} 或 {"kind":"info","text":...}
func offer(landmark_id: String, quest_kind: String, giver: String) -> Dictionary:
	var data: Dictionary = GameState.quests
	for q: Dictionary in data["active"]:
		if q["landmark_id"] == landmark_id:
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
	data["active"].append(quest)
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
		var species := _pick_hunt_species(rng)
		if species == "":
			return {}
		quest["species"] = species
		quest["need"] = 4 + rng.randi() % 4
		quest["title"] = "狩猎：击杀 %s ×%d" % [species, quest["need"]]
	elif quest_kind == "ransack":
		quest["need"] = 1 + rng.randi() % 2
		quest["title"] = "捣毁巢穴 ×%d" % quest["need"]
	else:
		quest["need"] = 2 + rng.randi() % 2
		quest["title"] = "探索：发现新地标 ×%d" % quest["need"]
	quest["gold"] = EconomyMath.bounty_gold(quest["need"] + 2, GameState.stats.level)
	quest["xp"] = EconomyMath.bounty_xp(quest["need"] + 2)
	return quest


func _pick_hunt_species(rng: RandomNumberGenerator) -> String:
	if WorldSim.sim == null:
		return ""
	var counts := {}
	for inst: MonsterInstance in WorldSim.sim.instances.values():
		if inst.is_alive and not inst.species.is_boss \
				and _GameWorld.MONSTER_SCENES.has(inst.species.species_name):
			counts[inst.species.species_name] = int(counts.get(inst.species.species_name, 0)) + 1
	var candidates: Array = []
	for n: String in counts:
		if int(counts[n]) >= 3:
			candidates.append(n)
	if candidates.is_empty():
		return ""
	candidates.sort()
	return candidates[rng.randi() % candidates.size()]


func _on_kill(_xp: int, _gold: int, _monster_name: String, species_name: String) -> void:
	_progress_match(func(q: Dictionary) -> bool:
		return q["kind"] == "hunt" and q["species"] == species_name)


func _on_ransack(_species_name: String) -> void:
	_progress_match(func(q: Dictionary) -> bool: return q["kind"] == "ransack")


func _on_discover(_id: String, _patch: String, _kind: String, _pos: Vector2) -> void:
	_progress_match(func(q: Dictionary) -> bool: return q["kind"] == "explore")


func _progress_match(predicate: Callable) -> void:
	var data: Dictionary = GameState.quests
	var changed := false
	for q: Dictionary in data["active"].duplicate():
		if not predicate.call(q):
			continue
		q["progress"] = int(q["progress"]) + 1
		changed = true
		if int(q["progress"]) >= int(q["need"]):
			_complete(q)
	_push_hud()
	if changed:
		GameState._queue_save()


func _complete(quest: Dictionary) -> void:
	var data: Dictionary = GameState.quests
	data["active"].erase(quest)
	data["completed"][quest["landmark_id"]] = \
			int(data["completed"].get(quest["landmark_id"], 0)) + 1
	GameState.add_gold(quest["gold"])
	GameState.add_xp(quest["xp"])
	# 结算金闪（美术 v5 fx 全量）：在玩家位置炸开
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player != null:
		EventBus.fx_requested.emit("flash_yellow", player.global_position, 1.3)
	SfxManager.play("quest")
	SfxManager.play("gold3")
	EventBus.quest_completed.emit("✅ %s 完成（+%d 金币 +%d 经验）" % [
		quest["title"], quest["gold"], quest["xp"]])


## HUD 任务行：首个进行中的任务（多任务时显示计数）
func _push_hud() -> void:
	var data: Dictionary = GameState.quests
	var n: int = data["active"].size()
	if n == 0:
		EventBus.quest_updated.emit("")
		return
	if n == 1:
		var q: Dictionary = data["active"][0]
		EventBus.quest_updated.emit("📜 %s（%d/%d）" % [q["title"], q["progress"], q["need"]])
	else:
		var q0: Dictionary = data["active"][0]
		EventBus.quest_updated.emit("📜 %s（%d/%d）+另 %d 项" % [
			q0["title"], q0["progress"], q0["need"], n - 1])
