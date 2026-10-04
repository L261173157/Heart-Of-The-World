## 章节账本纯逻辑/交易边界；真实路径、UI与演员事件另由章节契约覆盖。
extends Node2D

const Data := preload("res://scripts/main/outpost_quest_data.gd")
const Legacy := preload("res://scripts/main/camp_quest_data.gd")
const Quest := preload("res://scripts/main/outpost_quest.gd")
var _checks := 0
var _fails := 0
var _quest: OutpostQuest

func _ready() -> void:
	GameState.save_enabled = false
	GameState.reset_all()
	WorldSim.stop()
	WorldSim.sim = null
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok: _fails += 1
	print("  %s %s" % ["PASS" if ok else "FAIL", label])

func _old() -> Dictionary:
	return Legacy.sanitize({"id": Legacy.ID, "active": false, "stage": "act", "investigated": true, "choice": "hunt", "kills": [71],
		"target": {"pos": [1000.0, 2000.0], "region_id": "test", "species": "地精矿工"},
		"surveys": ["test|地精矿工"], "gold": 39, "xp": 44, "bonus": "onigiri"})

func _ready_chapter() -> Dictionary:
	var q := Data.create(GameState.camp_quest)
	for key: String in Data.EVIDENCE: q["evidence"][key] = true
	q["outcome"] = "survey"
	q["survey_confirmed"] = true
	Data.refresh_stage(q)
	return q

func _run() -> void:
	for bad: Variant in [null, 4, [], "chapter", {}, {"id": "other"}]:
		_check(Data.sanitize(bad).is_empty(), "拒绝错误顶层或章节ID")
	var q := Data.sanitize({"id": Data.ID, "stage": "completed", "active": "true", "evidence": {"rescued": true, "signpost_repaired": true}, "receipts": []})
	_check(q["stage"] == "investigation" and not q["active"] and not q["evidence"]["signpost_repaired"], "终态字符串与孤立救援不能跳过调查或伪造修复")
	_check(not Data.valid_legacy({"id": Legacy.ID}) and not Data.valid_legacy({"id": "other", "paid": true}), "损坏或空壳旧单不能占用奖励合同")
	var old := _old()
	q = Data.create(old)
	_check(q["legacy_reserved"] and not q["legacy_result"] and q["stage"] == "investigation", "旧暂停部分贡献仅保留合同，不自动完成新行动")
	var paid := old.duplicate(true)
	paid["stage"] = "completed"
	paid["paid"] = "broken"
	_check(Data.valid_legacy(paid) and Data.legacy_result(paid), "旧completed独立收据优先于坏paid布尔，禁止重付")
	q = Data.create(paid)
	_check(q["legacy_result"] and not Data.has_ecology_result(q), "旧已付生态仍必须先完成新调查回收救援")
	var carried := Data.sanitize(q, {})
	_check(carried["legacy_reserved"] and carried["legacy_result"] and carried["legacy_contract"]["paid"], "章节保留旧已付独立证明，原字段缺失也不重开新奖励")
	var conflict := Data.sanitize(q, _old())
	_check(conflict["legacy_contract"]["paid"], "独立已付证明优先于矛盾的旧未付副本，不能回滚支付")
	var totals := {"gold": 0, "xp": 0, "items": 0}
	for stage: String in Data.RECEIPTS:
		var reward := Data.reward(stage, false)
		totals["gold"] += reward["gold"]; totals["xp"] += reward["xp"]
		totals["items"] += 1 if reward["bonus"] != "" else 0
		_check(Data.reward(stage, true) == {"gold": 0, "xp": 0, "bonus": ""}, "已有原合同的章节段落不重复付预算：" + stage)
	_check(totals == {"gold": 39, "xp": 44, "items": 1}, "三段总合同仅39金币44经验与一个饭团")
	GameState.camp_quest = {}
	q = _ready_chapter()
	q["kills"] = [1, 1, -1, NAN, 1.5, "2", 3]
	q["receipts"]["investigation"] = {"paid": "bad", "status": "paid", "gold": NAN, "xp": []}
	q = Data.sanitize(q)
	_check(q["kills"] == [1, 3] and q["receipts"]["investigation"]["paid"] and q["receipts"]["investigation"]["gold"] == 0, "坏数值隔离与支付状态双凭证，不清除已付记录")
	_check(Data.sanitize(JSON.parse_string(JSON.stringify(q))) == q, "标准JSON往返保持全部证据与收据")
	q["evidence"]["aid_taken"] = false
	q = Data.sanitize(q)
	_check(not q["evidence"]["rescued"] and not q["evidence"]["signpost_repaired"] and q["receipts"]["investigation"]["paid"], "动作前置损坏会关闭修复资格，但不会重开已付款")
	_quest = Quest.new()
	add_child(_quest)
	GameState.outpost_quest = _ready_chapter()
	GameState.inventory = {"onigiri": 99}
	var gold := GameState.gold
	_quest._settle_ready(true)
	_check(GameState.gold == gold + 15 and GameState.outpost_quest["receipts"]["investigation"]["paid"] and GameState.outpost_quest["receipts"]["rescue"]["paid"], "前两段提交实际支付各自合同")
	_check(GameState.outpost_quest["stage"] == "claim" and not GameState.outpost_quest["receipts"]["restoration"]["paid"] and GameState.count_item("onigiri") == 99, "饭团99阻止整个末段奖励，不撤销修复证据")
	var once := GameState.gold
	_quest._settle_ready(true)
	_check(GameState.gold == once, "容量阻塞重试不重复前两段金币")
	GameState.inventory["onigiri"] = 98
	_quest._settle_ready(true)
	_check(GameState.gold == gold + 39 and GameState.count_item("onigiri") == 99 and GameState.outpost_quest["stage"] == "completed", "空间释放后完整末段24金币24经验饭团提交")
	var done := GameState.outpost_quest.duplicate(true)
	_quest._settle_ready(true)
	_check(GameState.gold == gold + 39 and GameState.outpost_quest == done, "末段重入不重付也不改已付收据")
	GameState.camp_quest = _old()
	GameState.outpost_quest = _ready_chapter()
	GameState.outpost_quest["target"] = GameState.camp_quest["target"].duplicate(true)
	GameState.outpost_quest["surveys"] = [GameState.camp_quest["target"]["key"]]
	GameState.outpost_quest["kills"] = [71, 72]
	GameState.outpost_quest["outcome"] = "hunt"
	GameState.outpost_quest["choice"] = "hunt"
	_quest._carry_result_to_legacy()
	_check(GameState.camp_quest["kills"] == [71] and GameState.camp_quest["stage"] == "act" and not GameState.camp_quest["active"], "未提供真实巢边事件证据的72不能扩大旧合同贡献或伪造交付资格")
	_check(GameState.camp_quest["gold"] == 39 and GameState.camp_quest["xp"] == 44 and GameState.camp_quest["bonus"] == "onigiri", "兼容证据转交不改旧承诺金额或物品")
	var old_pending := GameState.camp_quest.duplicate(true)
	_quest._carry_result_to_legacy()
	_check(GameState.camp_quest == old_pending, "旧待领取合同不可被另一结果覆盖")
	GameState.camp_quest = _old()
	GameState.outpost_quest["target"] = {}
	GameState.outpost_quest["surveys"] = []
	GameState.outpost_quest["outcome"] = "survey"
	var before := GameState.camp_quest.duplicate(true)
	_quest._carry_result_to_legacy()
	_check(GameState.camp_quest["stage"] == before["stage"] and GameState.camp_quest["surveys"] == before["surveys"], "前哨勘察点不能伪造旧生态据点到场或关闭原合同")
	GameState.camp_quest = Legacy.sanitize(paid)
	before = GameState.camp_quest.duplicate(true)
	_quest._carry_result_to_legacy()
	_check(GameState.camp_quest == before, "旧已付完整账本不可变")
	GameState.camp_quest = {}
	GameState.outpost_quest = Data.create()
	var manager := QuestManager.new()
	add_child(manager)
	GameState.outpost_quest["evidence"]["patrol_read"] = true
	GameState.outpost_quest["evidence"]["entrance_read"] = true
	manager._outpost._settle_ready()
	before = GameState.outpost_quest.duplicate(true)
	manager.accept({"id": Legacy.ID})
	manager._camp.accept()
	_check(GameState.camp_quest.is_empty() and GameState.outpost_quest == before, "章节已付后旧API与陈旧旧对话均不能另开第二份合同")
	for original: Dictionary in [_old(), Legacy.sanitize(paid)]:
		GameState.outpost_quest = Data.create(original)
		GameState.camp_quest = {}
		_quest._sync_legacy()
		_check(GameState.camp_quest == original, "缺失原账本时从验证合同恢复原暂停/支付状态与全部承诺")
		GameState.outpost_quest = Data.create(original)
		GameState.camp_quest = {}
		GameState.SAVE_PATH = "user://outpost_ledger_recovery_%d.json" % OS.get_process_id()
		var file := FileAccess.open(GameState.SAVE_PATH, FileAccess.WRITE)
		file.store_string(JSON.stringify({"version": 13, "camp_quest": {}, "outpost_quest": GameState.outpost_quest}))
		file.close()
		GameState._load()
		_check(GameState.camp_quest == original and GameState.outpost_quest["legacy_reserved"], "真实读档恢复缺失的有效原合同，数值奖励仍保留在旧权威账本")
	GameState.camp_quest = _old()
	GameState.outpost_quest = Data.create(GameState.camp_quest)
	GameState.camp_quest["paid"] = true
	GameState.camp_quest["stage"] = "completed"
	GameState.camp_quest["active"] = false
	manager._camp.changed.emit()
	_check(GameState.outpost_quest["legacy_contract"]["paid"], "原委托支付变更同步刷新备份收据，不留下可重付的旧未付副本")
	print("=== OUTPOST LEDGER %s (%d checks, %d failures) ===" % ["PASS" if _fails == 0 else "FAIL", _checks, _fails])
	get_tree().quit(0 if _fails == 0 else 1)
