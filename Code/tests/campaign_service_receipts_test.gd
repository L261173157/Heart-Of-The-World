## 服务可用性与不可逆领取收据分离的纯账本回归；不替代真实库存/保存事务测试。
extends SceneTree
const Data := preload("res://scripts/main/campaign_quest_data.gd")
const SERVICE := "patrol_station"
const STAGE := "side_patrol:s2"
const ACTION := "side_patrol:s2:settle"
var checks := 0
var failures := 0
func _initialize() -> void:
	var q := _completed_patrol()
	_check(q["services"].get(SERVICE, {}).get("enabled", false), "真实驻地证据开放服务")
	_check(not Data.service_claimed(q, SERVICE), "未领取无付款墓碑")
	_check(Data.mark_service_claimed(q, SERVICE), "首次领取登记独立收据")
	_check(not Data.mark_service_claimed(q, SERVICE), "活跃站点重复领取拒绝")
	_check(q["service_receipts"].get(SERVICE, {}).get("claimed", false), "收据独立于可用服务")
	for mode: String in ["independent", "legacy_claimed", "legacy_status", "bool_receipt", "mixed_damage"]:
		var damaged := q.duplicate(true)
		damaged["quests"][STAGE]["evidence"].erase(ACTION)
		match mode:
			"independent": damaged["services"].clear()
			"legacy_claimed":
				damaged.erase("service_receipts")
				damaged["services"][SERVICE].erase("status")
			"legacy_status":
				damaged.erase("service_receipts")
				damaged["services"][SERVICE]["claimed"] = "damaged"
			"bool_receipt":
				damaged["service_receipts"][SERVICE] = true
				damaged["services"].clear()
			"mixed_damage": damaged["service_receipts"][SERVICE] = {"claimed": false, "status": "available"}
		var clean := _cold(damaged)
		_check(not clean["services"].has(SERVICE), mode + "损坏动作不由支付记录免费解锁服务")
		_check(clean["service_receipts"].get(SERVICE, {}).get("claimed", false), mode + "保留不可逆领取收据")
		_check(Data.service_claimed(clean, SERVICE), mode + "付款历史独立可查")
		_check(not Data.mark_service_claimed(clean, SERVICE), mode + "失效服务不可再次领物")
		clean = _cold(clean)
		_check(clean["service_receipts"].get(SERVICE, {}).get("claimed", false), mode + "再次读档仍保留失效站点收据")
		_check(Data.record(clean, STAGE, ACTION, {"position": [120, 180], "tick": 5, "destination": "side_patrol:station_camp"}), mode + "重新修复动作允许恢复站点")
		_check(clean["services"].get(SERVICE, {}).get("enabled", false), mode + "重新修复后服务实际可用")
		_check(clean["services"][SERVICE]["claimed"], mode + "重新修复继承已付状态")
		_check(not Data.mark_service_claimed(clean, SERVICE), mode + "重新修复不能重复领饭团")
		clean = _cold(clean)
		_check(clean["services"][SERVICE]["claimed"], mode + "修复后冷启动保持一次性")
	var fake := Data.create(8899)
	fake["service_receipts"] = {"unknown_service": true, SERVICE: {"claimed": true, "status": "claimed"}}
	fake["services"] = {"other_unknown": {"claimed": true, "enabled": true}}
	fake = _cold(fake)
	_check(not fake["service_receipts"].has("unknown_service") and not fake["service_receipts"].has("other_unknown"), "未知服务ID不能注入收据")
	_check(fake["services"].is_empty(), "已知收据本身也不能创造服务")
	_check(fake["service_receipts"].get(SERVICE, {}).get("claimed", false), "已知孤立付款证明保留但不解锁")
	fake["services"]["unknown_service"] = {"enabled": true}
	_check(not Data.mark_service_claimed(fake, "unknown_service"), "未知活动字段不能授权新服务")
	var source := _completed_patrol()
	var snapshot := source.duplicate(true)
	_check(Data.mark_service_claimed(source, SERVICE), "测试事务暂存领取")
	source = snapshot
	_check(not Data.service_claimed(source, SERVICE), "整账本回滚同时还原物资收据状态")
	print("CAMPAIGN_SERVICE_RECEIPTS_TEST ", "PASS " if failures == 0 else "FAIL ", checks)
	quit(0 if failures == 0 else 1)
func _completed_patrol() -> Dictionary:
	var q := Data.create(8899)
	var e: Dictionary = {}
	for key: String in Data.Outpost.EVIDENCE: e[key] = true
	Data.authorize_chapter1(q, {"id": "lost_outpost_v1", "evidence": e, "outcome": "survey", "survey_confirmed": true})
	Data.accept(q, "side_patrol:s1", 3)
	for action: String in ["request", "record", "badge"]:
		_check(Data.record(q, "side_patrol:s1", "side_patrol:s1:" + action, {"position": [100, 200], "tick": 1}), "前置巡守故事 " + action)
	_check(Data.accept(q, STAGE, 3), "接取真实驻地安排")
	_check(Data.record(q, STAGE, "side_patrol:s2:station", {"position": [100, 200], "tick": 2, "choice": "camp"}), "选择营地驻地")
	_check(Data.record(q, STAGE, ACTION, {"position": [120, 180], "tick": 3, "destination": "side_patrol:station_camp"}), "亲手落实驻地证据")
	return q
func _cold(q: Dictionary) -> Dictionary:
	return Data.sanitize(JSON.parse_string(JSON.stringify(q)), 8899)
func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
