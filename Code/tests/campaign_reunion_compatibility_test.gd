## 历史实走存档冷加载；合成的部分选择输入由驱动器明确标注，不冒充实玩所得。
## 只继承场景装配/实走/界面工具，不运行其他测试的剧情阶段。
extends "res://tests/campaign_story_acceptance_test.gd"

const Data := preload("res://scripts/main/campaign_quest_data.gd")
const FINAL_STAGE := "watch_c6_lava:s4"
const FINAL_ACTION := FINAL_STAGE + ":ending"
const SETTLE_ACTION := FINAL_STAGE + ":settle"
var _archive_payload: Dictionary = {}

func _prior_progress(q: Dictionary) -> Dictionary:
	var result := q.duplicate(true)
	result.quests.erase(FINAL_STAGE)
	# 以下均是最后一次落实合法产生的派生状态。
	for key: String in ["ending", "flags", "services", "history", "travel", "dynamic_runtime", "world_facts"]: result.erase(key)
	return result

func _historical_integrity(expected: Dictionary) -> void:
	var saved: Dictionary = expected.campaign
	for key: String in ["service_receipts", "main_kills", "chapter1_proof", "chapters", "quests", "random_used", "history", "paused_chains"]:
		_check(_same(_cq().get(key), saved.get(key)), "历史冷加载精确保留独立账本字段 " + key)
	_check(_same(GameState.camp_quest, expected.get("legacy_camp", {})), "历史冷加载保留最初营地合同")
	_check(_same(GameState.quests, expected.get("ordinary", {"active":[],"completed":{},"receipts":{},"last_receipt":""})), "历史冷加载保留普通委托")
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GameState.SAVE_PATH))
	for key: String in ["item_source_receipts", "equipment_state", "equipment_drop_state", "pending_equipment", "pending_items", "first_boss_choices", "equipment_fixed_offers"]:
		_check(_same(GameState.get(key), raw.get(key, [] if key == "first_boss_choices" else {})), "历史冷加载保留非剧情资源 " + key)

func _capture_archive(payload: Dictionary) -> void:
	_archive_payload = payload.duplicate(true)

func _reread_history() -> void:
	var before := _cq().duplicate(true)
	var wallet := _wallet()
	var pending := GameState.pending_items.duplicate(true)
	EventBus.npc_dialogue.connect(_capture_archive)
	_campaign.action("campaign|history_menu")
	_check(_archive_payload.get("kind", "") == "camp_choice" and _archive_payload.get("options", []).size() == 5, "真实处理器发出已取得的五章记录菜单")
	_hud._close_dialogue()
	for chapter: Dictionary in Catalog.main_chapters():
		_campaign.action("campaign|history_chapter|" + str(chapter.id))
		var actions: Array[String] = []
		for option: Dictionary in _archive_payload.get("options", []): actions.append(str(option.action))
		for stage: Dictionary in chapter.steps:
			for action: Dictionary in stage.actions:
				var earned: bool = _cq().quests[stage.id].evidence.has(action.id)
				_check(actions.has("campaign|history_action|" + str(action.id)) == earned, "回读菜单只收录实际已得证据 " + str(action.id))
				if not earned:
					_archive_payload.clear()
					_campaign.action("campaign|history_action|" + str(action.id))
					_check(_archive_payload.is_empty(), "未得历史行动的陈旧回调不能泄露文本 " + str(action.id))
		_hud._close_dialogue()
	_campaign.action("campaign|history_action|watch_c5_snow:s4:plans")
	_check(_archive_payload.get("kind", "") == "info" and not str(_archive_payload.get("text", "")).is_empty(), "旧完成档通过真实处理器重读新名册记录")
	_check(not _archive_payload.get("questions", []).is_empty() and (JSON.stringify(_archive_payload).contains("低负载") or JSON.stringify(_archive_payload).contains("低负荷")), "旧完成档回读也提供新增追问和低负载转发说明")
	_hud._close_dialogue()
	if Data.effective_ending(_cq()) == "reunion":
		_campaign.action("campaign|history_action|" + FINAL_ACTION)
		_check(str(_archive_payload.get("text", "")).contains("团聚"), "历史旧结局重读明确当前团聚结果")
		if _cq().quests[FINAL_STAGE].choice == "distributed":
			_check(str(_archive_payload.get("text", "")).contains("旧名册") and str(_archive_payload.get("text", "")).contains("后来"), "旧分散安排如实保留，后续轮值团聚说明清楚")
		_hud._close_dialogue()
	EventBus.npc_dialogue.disconnect(_capture_archive)
	_check(_same(before, _cq()) and wallet == _wallet() and pending == GameState.pending_items, "完整历史菜单/正文/追问回读不改变原证据、奖励或物品")

func _canonical_world() -> void:
	_check(Data.effective_ending(_cq()) == "reunion", "当前有效结局唯一为团聚")
	var canonical := CampaignLayout.ending_positions("reunion")
	for old: String in ["distributed", "centralized", "", "unknown"]:
		_check(CampaignLayout.ending_positions(old) == canonical, "兼容布局参数统一驻地 " + old)
	for id: String in canonical:
		var npc := _cp(id)
		_check(npc != null and npc.global_position == canonical[id], "真实旧档人物迁回统一团聚驻地 " + id)
		_check(npc != null and str(npc.get("service")).contains("补给"), "真实旧档团聚居民仍有补给服务 " + id)
		_check(BiomeMap.terrain_at(canonical[id]) == "plains", "真实旧档四人均在平原 " + id)
	var shelter := _cp("ending:shelter")
	_check(shelter != null and shelter.is_visible_in_tree(), "旧档加载也显现真实团聚避难所")
	var summary := CampaignQuest.completed_summary(_cq(), true)
	_check(summary.contains("团聚") and not summary.contains("分散") and not summary.contains("集中"), "完成摘要只有当前团聚目标")
	var epilogue: String = _campaign.epilogue()
	for name: String in ["阿苇", "沈渡", "罗墨", "韩铎"]:
		_check(epilogue.contains(name), "后记记得实际归来的人 " + name)
	_check(epilogue.contains("自动转发") and epilogue.contains("轮流"), "后记交代归来后远方信标的运行方式")

func _no_duplicate_awards() -> void:
	var before := _cq().duplicate(true)
	var wallet := _wallet()
	var pending := GameState.pending_items.duplicate(true)
	var sources := GameState.item_source_receipts.duplicate(true)
	_campaign._settle_ready()
	_campaign._settle_ready()
	_campaign.claim(FINAL_STAGE)
	_campaign.perform_action(FINAL_ACTION, "distributed")
	_campaign.perform_action(FINAL_ACTION, "centralized")
	_check(_same(before, _cq()), "已完成旧档重复结算/陈旧回调不改任何剧情账本")
	_check(wallet == _wallet() and pending == GameState.pending_items and sources == GameState.item_source_receipts, "已完成旧档不重复增加余额、库存、待领取或物品收据")

## 纯账本畸形输入隔离，与真实冷读及实际末段完成测试分开。
func _adversarial_ledger() -> void:
	var original := _cq().duplicate(true)
	var receipt: Dictionary = original.quests[FINAL_STAGE].receipt.duplicate(true)
	for invalid: Variant in ["", "reunion", "unknown", {}, [], 9, true, null]:
		var bad := original.duplicate(true)
		bad.quests[FINAL_STAGE].evidence[FINAL_ACTION].kind = "choice"
		bad.quests[FINAL_STAGE].evidence[FINAL_ACTION].choice = invalid
		var clean := Data.sanitize(bad, int(bad.seed))
		_check(not clean.quests[FINAL_STAGE].evidence.has(FINAL_ACTION) and not Data.ready(clean, FINAL_STAGE), "畸形历史选择被隔离 " + str(invalid))
		_check(clean.quests[FINAL_STAGE].choice == "" and Data.effective_ending(clean) == "", "无效选择不能制造当前团聚")
		_check(_same(clean.quests[FINAL_STAGE].receipt, receipt) and Data.paid(clean, FINAL_STAGE), "坏证据仍保留支付墓碑，不能重领奖励")
	var forged := original.duplicate(true)
	for sid: String in [FINAL_STAGE, "watch_c5_snow:s4"]:
		forged.quests[sid].evidence.clear()
	forged.ending = "reunion"
	_check(Data.effective_ending(Data.sanitize(forged, int(forged.seed))) == "", "伪造顶层结局不跳过终章或前章")
	# 同一兼容口不得放宽另一行动的 kind。
	var sibling := original.duplicate(true)
	sibling.quests[FINAL_STAGE].evidence[SETTLE_ACTION].kind = "choice"
	sibling.quests[FINAL_STAGE].evidence[SETTLE_ACTION].choice = "distributed"
	var sibling_clean := Data.sanitize(sibling, int(sibling.seed))
	_check(not sibling_clean.quests[FINAL_STAGE].evidence.has(SETTLE_ACTION), "历史choice例外不泄漏到最后落实或其他行动")

func _finish_partial() -> void:
	var stage: Dictionary = _cq().quests[FINAL_STAGE]
	var proof: Dictionary = stage.evidence.get(FINAL_ACTION, {}).duplicate(true)
	var selected := str(stage.choice)
	_check(selected in ["distributed", "centralized"] and proof.get("kind", "") == "choice", "合成兼容边界输入保留原版已选证据")
	_check(not Data.ready(_cq(), FINAL_STAGE) and not Data.paid(_cq(), FINAL_STAGE) and Data.effective_ending(_cq()) == "", "历史只选未落实的输入不提前通关或支付")
	var prior := _prior_progress(_cq())
	var wallet := _wallet()
	var promised := Data.reward(_cq(), FINAL_STAGE)
	if not await _do_action(Catalog.action(FINAL_STAGE, SETTLE_ACTION)): return
	_check(_same(proof, _cq().quests[FINAL_STAGE].evidence[FINAL_ACTION]) and _cq().quests[FINAL_STAGE].choice == selected, "实际落实不会把旧choice证据重写成conclude或改选项")
	_check(_same(prior, _prior_progress(_cq())), "实际旧档末段落实保留其他任务与合同")
	_check(Data.paid(_cq(), FINAL_STAGE), "历史未付末段经实际现场落实获得一次收据")
	_check(GameState.gold - int(wallet.gold) == int(_cq().quests[FINAL_STAGE].receipt.gold), "历史末段仅按冻结收据增加金币")
	_check(_wallet_xp(_wallet()) - _wallet_xp(wallet) == int(_cq().quests[FINAL_STAGE].receipt.xp), "历史末段仅按冻结收据增加经验")
	_check(GameState.count_item("onigiri") == int(wallet.inventory.get("onigiri", 0)) + 1 and _same(promised, Data.reward(_cq(), FINAL_STAGE)), "旧末段仅补发一份承诺物品且预算不变")

func _new_conclusion() -> void:
	_check(_cq().quests[FINAL_STAGE].evidence.is_empty(), "真正旧版未决定检查点没有终局证据")
	var action := Catalog.action(FINAL_STAGE, FINAL_ACTION)
	_check(action.kind == "conclude" and not action.has("choices"), "新目录只有无分支团聚确认")
	if not await _cw(str(action.object)): return
	for stale: String in ["distributed", "centralized", "reunion", "unknown"]:
		var before := _cq().duplicate(true)
		var wallet := _wallet()
		_campaign.perform_action(FINAL_ACTION, stale)
		_check(_same(before, _cq()) and wallet == _wallet(), "真实现场陈旧choice回调不能写入新conclude " + stale)
		var fixture := before.duplicate(true)
		_check(not Data.record(fixture, FINAL_STAGE, FINAL_ACTION, {"position":[1,2],"tick":1,"kind":"choice","choice":stale}), "底层live record也拒绝旧选择负载 " + stale)
	if not await _ci(str(action.object)): return
	var proof: Dictionary = _cq().quests[FINAL_STAGE].evidence.get(FINAL_ACTION, {})
	_check(proof.get("kind", "") == "conclude" and not proof.has("choice") and _cq().quests[FINAL_STAGE].choice == "", "真实界面新确认只写conclude且没有历史选项")
	_check(Data.effective_ending(_cq()) == "" and not Data.paid(_cq(), FINAL_STAGE), "新确认也须等待最后落实才能完成")
	await _do_action(Catalog.action(FINAL_STAGE, SETTLE_ACTION))

func _write_campaign_expected() -> void:
	super._write_campaign_expected()
	var expected := _expected()
	expected.legacy_camp = GameState.camp_quest.duplicate(true)
	expected.ordinary = GameState.quests.duplicate(true)
	_write_expected(expected)

func _saved_schema_and_backup(original: PackedByteArray) -> void:
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GameState.SAVE_PATH))
	_check(GameState.SAVE_VERSION == 19 and int(saved.get("version", 0)) == 19 and int(saved.get("campaign_min_reader", 0)) == 19, "conclude证据只写入v19，v18读者不能覆盖")
	_check(int(saved.get("equipment_schema", 0)) == 1, "仅升级存档读者边界，装备实例格式仍为1")
	var source: Dictionary = JSON.parse_string(original.get_string_from_utf8())
	if int(source.get("version", 0)) < GameState.SAVE_VERSION:
		var base := GameState.SAVE_PATH + ".pre-equipment-v17.bak"
		var alternate := GameState.SAVE_PATH + ".pre-equipment-" + original.hex_encode().sha256_text().substr(0, 16) + ".bak"
		var exact := FileAccess.file_exists(base) and FileAccess.get_file_as_bytes(base) == original
		exact = exact or (FileAccess.file_exists(alternate) and FileAccess.get_file_as_bytes(alternate) == original)
		_check(exact, "v18迁移前原始字节完整备份，已有不同备份也不覆盖")

func _run() -> void:
	Engine.time_scale = 4.0
	var args := OS.get_cmdline_user_args()
	if args.size() != 1 or OS.get_environment("HOTW_TEST_SAVE").is_empty():
		_check(false, "兼容测试必须提供隔离输入与单一阶段")
		_finish()
		return
	var original := FileAccess.get_file_as_bytes(GameState.SAVE_PATH)
	await _mount(false)
	_cold_campaign_expected()
	_historical_integrity(_expected())
	if _fails == 0: _reread_history()
	if _fails == 0:
		match args[0]:
			"preserve", "read":
				_canonical_world()
				_no_duplicate_awards()
				_adversarial_ledger()
			"partial":
				await _finish_partial()
				_canonical_world()
				_no_duplicate_awards()
			"new":
				await _new_conclusion()
				_canonical_world()
				_no_duplicate_awards()
			_: _check(false, "未知兼容阶段")
	if _fails == 0 and args[0] != "read":
		_check(_save(), "兼容结果通过真实原子存档写回隔离副本")
		_saved_schema_and_backup(original)
		_write_campaign_expected()
	elif _fails == 0:
		_saved_schema_and_backup(original)
	await _unmount()
	_finish()

func _finish() -> void:
	print("=== CAMPAIGN REUNION COMPATIBILITY %s (%d checks, %d failures) ===" % ["PASS" if _fails == 0 else "FAIL", _checks, _fails])
	get_tree().quit(0 if _fails == 0 else 1)
