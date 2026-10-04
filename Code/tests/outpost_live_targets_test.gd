## 真实既有MonsterInstance与MonsterBase的前哨实名选择边界；活跃AI全路线另测。
extends "res://tests/camp_pilot_contract_test.gd"

const ChapterData := preload("res://scripts/main/outpost_quest_data.gd")
const ChapterTargets := preload("res://scripts/main/outpost_quest_targets.gd")
var _selector: OutpostQuestTargets
var _bodies: Dictionary = {}
var _anchors: Dictionary = {}

## 只固定异步竞争窗口；等待之后仍执行原来的真实有界A*，不伪造可达结论。
class YieldingTargets extends OutpostQuestTargets:
	func _route_exists(from: Vector2, to: Vector2) -> bool:
		await get_tree().process_frame
		if not is_inside_tree(): return false
		return await super._route_exists(from, to)

func _scheduled_selector(outpost: OutpostQuest) -> void:
	outpost._targets.get_parent().remove_child(outpost._targets)
	outpost._targets.queue_free()
	outpost._targets = YieldingTargets.new()
	outpost.add_child(outpost._targets)
	outpost._targets.set_process(false)

func _chapter(target: Dictionary) -> Dictionary:
	var q := ChapterData.create(GameState.camp_quest)
	for key: String in ["patrol_read", "entrance_read", "wounded_found", "supply_read", "aid_taken", "tools_taken", "rescued", "site_surveyed"]:
		q["evidence"][key] = true
	q["target"] = ChapterData.target_data(target)
	q["surveys"] = [target["key"]]
	q["choice"] = "hunt"
	ChapterData.refresh_stage(q)
	return q

func _finish() -> void:
	print("=== OUTPOST LIVE TARGETS %s (%d checks, %d failures) ===" % ["PASS" if _fails == 0 else "FAIL", _checks, _fails])
	get_tree().quit(0 if _fails == 0 else 1)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if "--cold-read" in args or "--compact-cold-read" in args:
		var saved := GameState.outpost_quest.duplicate(true)
		var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GameState.SAVE_PATH + ".targets_expected"))
		_check(_same(saved["target"]["target_ids"], expected["target_ids"]), "独立冷进程保留真实实名ID，不经旧消毒器丢失")
		_check(_same(saved["kills"], expected["kills"]) and _same(saved["surveys"], expected["surveys"]), "独立冷进程保留实际贡献与原到场证据")
		await _mount(false)
		for _i in 600:
			if not _qm._outpost._searching: break
			await _frames(1)
		var ids: Array = _qm._outpost._targets.current_stock_ids(GameState.outpost_quest["target"])
		_check(not ids.is_empty(), "冷启逐个复核存活位置与路径后恢复有效实名目标")
		if "--compact-cold-read" in args:
			_check(_same(saved.get("compact_sites", {}), expected["compact_sites"]), "冷启旧合同凭据仍绑定原真实巢址，不能移给另一目标")
			_check(_same(saved.get("compact_kills", []), expected["compact_kills"]) and not WorldSim.sim.instances.has(int(expected["compact_kills"][0])), "冷启保留真实巢边击杀凭据，第一尸体已按生态规则清理")
			if not ids.is_empty():
				var actor: MonsterBase = _world._nodes.get(ids[0])
				_check(actor != null, "冷启当前巢边实名目标装配为真实演员")
				if actor != null:
					actor.take_damage(99999.0, actor.global_position + Vector2(20, 0))
					_check(GameState.outpost_quest["outcome"] == "hunt" and CampQuestData.has_result(GameState.camp_quest), "第二次真实巢边击杀与已清理尸体的保存凭据共同完成原合同")
		for id: int in ids:
			_check(WorldSim.sim.instances.has(id) , "冷启实名身份对应真实实例：%d" % id)
		await _unmount()
		_finish()
		return
	if "--compact-cold-write" in args:
		await _compact_proof(true)
		_finish()
		return
	await _mount(true)
	_world.set_process(false)
	_selector = ChapterTargets.new()
	_world.add_child(_selector)
	var original := await _selector.select_target()
	_check(not original.is_empty() and original["target_ids"].size() >= 3, "真实默认世界有可达存活族群，不补怪")
	if original.is_empty():
		await _unmount(); _finish(); return
	var site := Vector2(original["pos"][0], original["pos"][1])
	var population := WorldSim.sim.instances.size()
	for inst: MonsterInstance in WorldSim.sim.instances.values():
		if inst.is_alive and inst.region_id == original["region_id"] and inst.species.species_name == original["species"]:
			var body: MonsterBase = _world._nodes.get(inst.id)
			if body == null:
				body = World.MONSTER_SCENES[inst.species.species_name].instantiate()
				_world.add_child(body)
				body.setup(inst)
			body.set_physics_process(false)
			body._nav.avoidance_enabled = false
			_anchors[inst.id] = inst.spawn_pos
			# 专门的位移夹具：只移动真实演员，不篡改实例、生态归属或巢址。
			body.global_position = WorldConfig.spawn_pos() + Vector2(100 + _bodies.size() * 38, 90)
			_bodies[inst.id] = body
	await _frames(2)
	var displaced := await _selector.verify_target(original)
	_check(displaced["target_ids"].size() >= 3 and _selector.current_stock_ids(displaced).size() >= 3, "离巢超过1400px的同地区实名活体通过真实路径核查")
	var compact := CampQuestTargets.new()
	_world.add_child(compact)
	_check(compact.current_stock_ids(displaced).is_empty(), "旧紧凑1400px成员规则保持不变")
	_check(WorldSim.sim.instances.size() == population, "查询不增加任何世界个体或密度")
	for id: int in _anchors:
		_check(WorldSim.sim.instances[id].spawn_pos == _anchors[id] and _bodies[id].global_position.distance_to(site) > 1400.0,
			"真实离巢演员保留原生态锚点：%d" % id)
	var chosen: int = displaced["target_ids"][0]
	var inst: MonsterInstance = WorldSim.sim.instances[chosen]
	var body: MonsterBase = _bodies[chosen]
	var region := inst.region_id
	inst.region_id = "foreign_region"
	_check(not chosen in _selector.current_stock_ids(displaced), "迁出任务地区的相同ID立即失效")
	inst.region_id = region
	var species := inst.species
	inst.species = WorldSim.sim.species_list[0] if WorldSim.sim.species_list[0] != species else WorldSim.sim.species_list[1]
	_check(not chosen in _selector.current_stock_ids(displaced), "同ID不同物种不能混入目标簿")
	inst.species = species
	var position := body.global_position
	body.global_position = WorldConfig.spawn_pos() + Vector2(10050, 0)
	_check(not chosen in _selector.current_stock_ids(displaced), "真实演员跨10k边界立即失效，出生锚点不能代替当前位置")
	body.global_position = position
	var target_without_ids := ChapterData.target_data(original)
	target_without_ids["target_ids"] = []
	_check(_selector.current_stock_ids(target_without_ids).is_empty(), "空ID名册不退回全世界同种匹配")
	var blocked := OutpostLayout.center() + Vector2(96, 0)
	_check(ObstacleField.nav_blocked_at(blocked), "路径负例使用真实前哨墙体")
	body.global_position = blocked
	var blocked_result := await _selector.verify_target(displaced)
	_check(not chosen in blocked_result["target_ids"], "路径被真实墙体阻挡的演员不能重新入簿")
	body.global_position = position
	var one := displaced.duplicate(true)
	one["target_ids"] = [chosen]
	one = await _selector.verify_target(one, false)
	_check(one["target_ids"] == [chosen], "核查指定ID不会暗中加入同种替代个体")
	var outpost: OutpostQuest = _qm._outpost
	outpost.remove_child(outpost._targets)
	outpost._targets.queue_free()
	_selector.reparent(outpost)
	outpost._targets = _selector
	one = await _selector.verify_target(one, false)
	GameState.outpost_quest = _chapter(one)
	var options: Array = outpost.choice_payload()["options"]
	_check(not options[0]["enabled"] and options[1]["enabled"], "一只存活实名个体允许捣真实巢穴，但不足两杀并保留幸存者")
	var unlisted: int = displaced["target_ids"][1]
	var unlisted_body: MonsterBase = _bodies[unlisted]
	unlisted_body.take_damage(99999.0, unlisted_body.global_position + Vector2(20, 0))
	_check(GameState.outpost_quest["kills"].is_empty(), "真实玩家击杀未入簿同种ID也不能获任务信用")
	var full := await _selector.verify_target(one, true)
	_check(full["target_ids"].size() >= 2 and not unlisted in full["target_ids"], "明确重核可逐个新增替代ID，已死ID不再入簿")
	GameState.outpost_quest["target"] = ChapterData.target_data(full)
	var natural_id: int = full["target_ids"][-1]
	var natural: MonsterInstance = WorldSim.sim.instances[natural_id]
	natural.lifespan = natural.age + 1
	WorldSim.sim.tick()
	EventBus.monster_killed_at.emit(natural.id, natural.species.species_name, natural.region_id, natural.spawn_pos)
	_check(not natural.is_alive and GameState.outpost_quest["kills"].is_empty(), "真实自然死亡及补发位置事件均不能伪造玩家贡献")
	await _unmount()
	_bodies.clear()
	_anchors.clear()
	await _mount(true)
	_world.set_process(false)
	outpost = _qm._outpost
	_selector = outpost._targets
	full = await _selector.select_target()
	for id: int in full["target_ids"]:
		var member: MonsterInstance = WorldSim.sim.instances[id]
		var actor: MonsterBase = _world._nodes.get(id)
		if actor == null:
			actor = World.MONSTER_SCENES[member.species.species_name].instantiate()
			_world.add_child(actor)
			actor.setup(member)
		actor.set_physics_process(false)
		actor._nav.avoidance_enabled = false
		actor.global_position = WorldConfig.spawn_pos() + Vector2(100 + _bodies.size() * 38, 90)
		_bodies[id] = actor
	full = await _selector.verify_target(full)
	GameState.camp_quest = CampQuestData.sanitize({"id": CampQuestData.ID, "active": false, "stage": "act", "investigated": true,
		"choice": "hunt", "target": full, "surveys": [full["key"]]})
	var old_contract := GameState.camp_quest.duplicate(true)
	GameState.outpost_quest = _chapter(full)
	var eligible := _selector.current_stock_ids(full)
	_check(eligible.size() >= 3, "新的真实三人族群供独立击杀正例，不补怪或改变种群密度")
	if eligible.size() >= 3:
		var first: MonsterBase = _bodies[eligible[0]]
		first.take_damage(99999.0, first.global_position + Vector2(20, 0))
		_check(GameState.outpost_quest["kills"] == [eligible[0]], "离巢真实MonsterBase击杀事件记录实名贡献")
		_check(GameState.outpost_quest["compact_kills"].is_empty(), "离巢超1400px的真实击杀没有旧合同许可")
		EventBus.monster_killed_at.emit(eligible[0], full["species"], full["region_id"], first.global_position)
		_check(GameState.outpost_quest["kills"].size() == 1, "同一真实死亡重播不能重复信用")
		if not "--cold-write" in args:
			var second: MonsterBase = _bodies[eligible[1]]
			second.take_damage(99999.0, second.global_position + Vector2(20, 0))
			_check(GameState.outpost_quest["outcome"] == "hunt" and GameState.outpost_quest["kills"].size() == 2,
				"离巢两次真实击杀且巢与实名幸存者保留才完成猎杀")
			_check(GameState.camp_quest == old_contract and not CampQuestData.has_result(GameState.camp_quest), "章节离巢完成不改原目标、原贡献或原巢边领奖资格")
	var roundtrip := ChapterData.sanitize(JSON.parse_string(JSON.stringify(GameState.outpost_quest)))
	_check(roundtrip["target"]["target_ids"] == GameState.outpost_quest["target"]["target_ids"], "JSON消毒保留正整实名ID集合")
	var bad := full.duplicate(true)
	bad["target_ids"] = [chosen, chosen, -1, 1.5, "9", NAN, 0]
	_check(ChapterData.target_data(bad)["target_ids"] == [chosen], "损坏/重复ID不会变成新许可")
	if "--cold-write" in args:
		# 第一只实际击杀后直接保存；下一独立进程复核身份/贡献/路径。
		var file := FileAccess.open(GameState.SAVE_PATH + ".targets_expected", FileAccess.WRITE)
		file.store_string(JSON.stringify({"target_ids": GameState.outpost_quest["target"]["target_ids"], "kills": GameState.outpost_quest["kills"], "surveys": GameState.outpost_quest["surveys"]}))
		file.close()
		_check(_save(), "真实生态快照与实名章节账本共同写盘")
	await _unmount()
	if not "--cold-write" in args:
		await _compact_proof(false)
		await _test_async_lifecycle()
		await _test_finish_during_refresh()
		await _test_canonical_site()
		await _test_legacy_site_integrity()
	_finish()

func _write_cold_expected() -> void:
	var q := GameState.outpost_quest
	var file := FileAccess.open(GameState.SAVE_PATH + ".targets_expected", FileAccess.WRITE)
	file.store_string(JSON.stringify({"target_ids": q["target"]["target_ids"], "kills": q["kills"], "surveys": q["surveys"], "compact_kills": q["compact_kills"], "compact_sites": q["compact_sites"]}))
	file.close()

func _compact_proof(write_cold: bool) -> void:
	await _mount(true)
	_world.set_process(false)
	var outpost: OutpostQuest = _qm._outpost
	_selector = outpost._targets
	var t := await _selector.select_target()
	_check(not t.is_empty(), "旧紧凑正例也从真实既有生态选取")
	if t.is_empty(): await _unmount(); return
	var site := Vector2(t["pos"][0], t["pos"][1])
	_player.teleport_to(site + Vector2(0, 100))
	_world._stream_pass()
	await _frames(3)
	_freeze_monsters()
	t = await _selector.verify_target(t)
	GameState.camp_quest = CampQuestData.sanitize({"id": CampQuestData.ID, "active": false, "stage": "act", "investigated": true,
		"choice": "hunt", "target": t, "surveys": [t["key"]]})
	GameState.outpost_quest = _chapter(t)
	var first_id: int = t["target_ids"][0]
	var first: MonsterBase = _world._nodes.get(first_id)
	_check(first != null and first.global_position.distance_to(site) <= 1400.0, "旧合同正例使用原巢边真实加载演员")
	if first == null: await _unmount(); return
	var duration: int = first.inst.species.corpse_duration
	# 只隔离尸体期限：捕食另有真实自然死亡负例，完整路径探针始终开启生态/AI。
	WorldSim.sim.predation_enabled = false
	first.take_damage(99999.0, first.global_position + Vector2(20, 0))
	_check(GameState.outpost_quest["compact_kills"] == [first_id], "仅真实原巢边击杀生成窄范围旧合同凭据")
	var original_chapter := GameState.outpost_quest.duplicate(true)
	GameState.outpost_quest["compact_sites"][str(first_id)]["key"] = "wrong_region|" + t["species"]
	outpost._carry_result_to_legacy()
	_check(GameState.camp_quest["kills"].is_empty(), "真实击杀ID也不能把不同巢址的凭据转给原合同")
	GameState.outpost_quest = original_chapter.duplicate(true)
	GameState.outpost_quest["compact_sites"][str(first_id)]["pos"] = [WorldConfig.spawn_pos().x, WorldConfig.spawn_pos().y]
	outpost._carry_result_to_legacy()
	_check(GameState.camp_quest["kills"].is_empty(), "同巢键的错误坐标凭据也不能转给原合同")
	GameState.outpost_quest = original_chapter
	for _i in duration + 1: WorldSim.sim.tick()
	_check(not WorldSim.sim.instances.has(first_id) and GameState.outpost_quest["compact_kills"] == [first_id], "真实尸体到期清理不抹去已验证巢边贡献")
	if write_cold:
		_write_cold_expected()
		GameState._invalidate_world_save_cache()
		_check(_save(), "尸体清理后的巢边贡献与完整世界真实写盘")
	else:
		var ids := _selector.current_stock_ids(t)
		_check(ids.size() >= 2, "生态正常前进后仍有第二目标及幸存者")
		if ids.size() >= 2:
			var second: MonsterBase = _world._nodes.get(ids[0])
			_check(second != null, "第二实名目标仍为真实MonsterBase")
			if second != null:
				second.take_damage(99999.0, second.global_position + Vector2(20, 0))
				_check(GameState.outpost_quest["outcome"] == "hunt" and CampQuestData.has_result(GameState.camp_quest), "实际两次巢边击杀包括已清理尸体的凭据，按原规则保留旧领奖资格")
				_check(GameState.camp_quest["gold"] == 39 and GameState.camp_quest["xp"] == 44 and not GameState.camp_quest["paid"], "旧合同承诺金额不变且仍需亲自交付")
	await _unmount()

func _wait_roster(outpost: OutpostQuest, require_ready: bool = true) -> void:
	for _i in 600:
		if not outpost._searching and (outpost._roster_ready or not require_ready): return
		await _frames(1)

func _test_async_lifecycle() -> void:
	await _mount(true)
	_world.set_process(false)
	var outpost: OutpostQuest = _qm._outpost
	_scheduled_selector(outpost)
	_check(not outpost._targets.is_processing(), "尚未接取章节时不做逐帧实名跟踪")
	var selected := await outpost._targets.select_target()
	_check(not selected.is_empty(), "异步生命周期用真实现存族群与真实有界路径")
	if selected.is_empty(): await _unmount(); return
	GameState.outpost_quest = _chapter(selected)
	outpost._save()
	_check(outpost._targets.is_processing(), "活动生态阶段才启用正常位移跟踪")
	outpost._refresh_roster(false)
	_check(outpost._searching, "真实路线核查已经进入分帧等待")
	outpost.abandon()
	await _wait_roster(outpost, false)
	_check(not outpost._targets.is_processing() and outpost._targets._verified.is_empty(), "暂停期间完成的旧回调不能恢复运行时证明")
	outpost.accept()
	await _wait_roster(outpost)
	_check(not outpost._targets.current_stock_ids(GameState.outpost_quest["target"]).is_empty(), "暂停后继续显式重核真实存量")
	outpost._refresh_roster(false)
	_check(outpost._searching, "立即恢复负例确实发生于真实等待中")
	outpost.abandon()
	outpost.accept()
	await _wait_roster(outpost)
	_check(not outpost._targets.current_stock_ids(GameState.outpost_quest["target"]).is_empty(), "等待中暂停并立即继续不会把取消结果当空存量，自动重试有效名册")
	var original_sim := WorldSim.sim
	var replacement := EcologySim.new()
	_check(replacement.restore_from_dict(original_sim.regions.values(), original_sim.species_list, original_sim.to_dict(), WorldConfig.boss_anchors()), "世界切换负例使用真实快照恢复的新实例身份")
	outpost._refresh_roster(false)
	_check(outpost._searching, "世界切换发生于真实路线等待中")
	WorldSim.sim = replacement
	await _wait_roster(outpost)
	var valid := outpost._targets._proof_sim == replacement
	for id: int in outpost._targets._verified:
		valid = valid and outpost._targets._verified[id]["inst"] == replacement.instances.get(id)
	_check(valid and not outpost._targets.current_stock_ids(GameState.outpost_quest["target"]).is_empty(), "旧世界回调不覆盖新世界名册，只提交新实例的独立路径证明")
	outpost._refresh_roster(false)
	_check(outpost._searching, "场景移除发生于真实路线等待中")
	outpost.get_parent().remove_child(outpost)
	await _frames(8)
	_check(not outpost.is_inside_tree() and not outpost._targets.busy and outpost._targets._verified.is_empty(), "场景退出终止等待且不能重新填入旧证明")
	outpost.queue_free()
	await _unmount()

func _test_finish_during_refresh() -> void:
	await _mount(true)
	_world.set_process(false)
	var outpost: OutpostQuest = _qm._outpost
	_scheduled_selector(outpost)
	var selector := outpost._targets
	var t := await selector.select_target()
	_check(t.get("target_ids", []).size() >= 3, "真实三只族群供事件验证")
	if t.get("target_ids", []).size() < 3: await _unmount(); return
	var site := Vector2(t["pos"][0], t["pos"][1])
	_player.teleport_to(site + Vector2(0, 120))
	_world._stream_pass()
	await _frames(3)
	_freeze_monsters()
	var first: MonsterBase = _world._nodes.get(t["target_ids"][0])
	var second: MonsterBase = _world._nodes.get(t["target_ids"][1])
	var survivor: MonsterBase = _world._nodes.get(t["target_ids"][2])
	_check(first != null and second != null and survivor != null, "使用真实流式演员")
	if first == null or second == null or survivor == null: await _unmount(); return
	survivor._nav.avoidance_enabled = false
	survivor.global_position = WorldConfig.spawn_pos() + Vector2(100, 100)
	t = await selector.verify_target(t)
	GameState.outpost_quest = _chapter(t)
	outpost._save()
	outpost._refresh_roster(true)
	_check(outpost._searching, "真实击杀完成恰在实名重核等待窗口中")
	first.take_damage(99999.0, first.global_position + Vector2(20, 0))
	second.take_damage(99999.0, second.global_position + Vector2(20, 0))
	var result_target: Dictionary = GameState.outpost_quest["target"].duplicate(true)
	var result_history: Array = GameState.outpost_quest["history"].duplicate(true)
	for i in 600:
		await _frames(1)
		if not outpost._searching:
			await _frames(2)
			if not outpost._searching: break
	_check(GameState.outpost_quest["outcome"] == "hunt", "处理事件已取得真实猎杀结果")
	_check(GameState.outpost_quest["target"] == result_target and GameState.outpost_quest["history"] == result_history, "完结后取消的旧重查不回写空名册或后续勘察记录")
	_check(selector._verified.is_empty() and not selector.is_processing(), "修复阶段不持有活动生态路径许可")
	await _unmount()

func _test_canonical_site() -> void:
	await _mount(true)
	_world.set_process(false)
	var outpost: OutpostQuest = _qm._outpost
	var actual := await outpost._targets.select_target()
	_check(not actual.is_empty(), "从真实世界先取合法巢穴及实名族群")
	if actual.is_empty(): await _unmount(); return
	var real_site := Vector2(actual["pos"][0], actual["pos"][1])
	var damaged := actual.duplicate(true)
	damaged["pos"] = [_player.global_position.x, _player.global_position.y]
	var q := _chapter(damaged)
	q["evidence"]["site_surveyed"] = false
	q["surveys"] = []
	q["choice"] = ""
	GameState.outpost_quest = ChapterData.sanitize(JSON.parse_string(JSON.stringify(q)))
	outpost._roster_ready = false
	outpost.accept()
	for i in 600:
		if not outpost._searching: break
		await _frames(1)
	_check(not outpost._on_site(), "到损坏坐标不能视作真实巢穴到场")
	var response := outpost.investigate()
	_check(not actual["key"] in GameState.outpost_quest["surveys"], "损坏坐标不能生成原巢穴调查历史")
	for i in 600:
		if not outpost._searching: break
		await _frames(1)
	_check(Vector2(GameState.outpost_quest["target"]["pos"][0], GameState.outpost_quest["target"]["pos"][1]).distance_to(real_site) <= 4.0, "损坏坐标恢复为真源巢址线索，不循环继承坏坐标")
	_player.teleport_to(real_site + Vector2(0, 100))
	_world._stream_pass()
	await _frames(3)
	WorldSim.sim.destroy_nest(actual["region_id"], actual["species"])
	_check(outpost._on_site(), "真实巢穴消失后仍允许亲自到规范历史巢址调查")
	var surveys_before: Array = GameState.outpost_quest["surveys"].duplicate()
	outpost.investigate()
	_check(actual["key"] in GameState.outpost_quest["surveys"] and not actual["key"] in surveys_before, "消失巢穴的现场调查须由真址到访产生")
	await _wait_roster(outpost, false)
	await _unmount()

func _test_legacy_site_integrity() -> void:
	await _mount(true)
	_world.set_process(false)
	var outpost: OutpostQuest = _qm._outpost
	var selector := outpost._targets
	var t := await selector.select_target()
	if t.get("target_ids", []).size() < 3: _check(false, "需要真实三只族群"); await _unmount(); return
	var site := Vector2(t["pos"][0], t["pos"][1])
	var bodies: Array[MonsterBase] = []
	for id: int in t["target_ids"]:
		var inst: MonsterInstance = WorldSim.sim.instances[id]
		var actor: MonsterBase = _world._nodes.get(id)
		if actor == null:
			actor = World.MONSTER_SCENES[inst.species.species_name].instantiate()
			_world.add_child(actor)
			actor.setup(inst)
		actor.set_physics_process(false)
		actor._nav.avoidance_enabled = false
		actor.global_position = WorldConfig.spawn_pos() + Vector2(100 + 30 * bodies.size(), 100)
		bodies.append(actor)
	t = await selector.verify_target(t)
	var damaged_old := t.duplicate(true)
	damaged_old["pos"] = [WorldConfig.spawn_pos().x, WorldConfig.spawn_pos().y]
	GameState.camp_quest = CampQuestData.sanitize({"id": CampQuestData.ID, "active": false, "stage": "act", "investigated": true, "choice": "hunt", "target": damaged_old, "surveys": [damaged_old["key"]]})
	GameState.outpost_quest = _chapter(t)
	outpost._save()
	_check(bodies[0].global_position.distance_to(site) > 1400 and bodies[1].global_position.distance_to(site) > 1400, "两只真实演员都在实际巢穴1400px之外")
	bodies[0].take_damage(99999, bodies[0].global_position + Vector2(20, 0))
	bodies[1].take_damage(99999, bodies[1].global_position + Vector2(20, 0))
	_check(GameState.outpost_quest["outcome"] == "hunt", "章节真实10k巡猎仍有效")
	_check(GameState.camp_quest["kills"].is_empty() and GameState.outpost_quest["compact_kills"].is_empty(), "旧保存位置损坏不能扩大真实巢边1400px贡献")
	await _unmount()
