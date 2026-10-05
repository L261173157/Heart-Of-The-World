## Real dynamic rescue/payments across a blocked atomic write and a new process.
## Uses the existing explicit prerequisite fixture; never injects dynamic completion evidence.
extends "res://tests/campaign_dynamic_cold_test.gd"
var previous_bytes := PackedByteArray()
var previous_save_time := 0.0
var reward_signal_checked := false
var blocked_tmp := ""
func do_action(a: Dictionary) -> void:
	if not str(a.id).begins_with("random_wounded:") or a.kind != "rescue":
		await super.do_action(a)
		return
	await go(str(a.object))
	check(not OS.get_environment("HOTW_TEST_SAVE").is_empty(), "write failure test uses an isolated disk save")
	previous_bytes = FileAccess.get_file_as_bytes(GameState.SAVE_PATH)
	previous_save_time = GameState.last_save_unix
	blocked_tmp = ProjectSettings.globalize_path(GameState.SAVE_PATH + ".tmp")
	check(DirAccess.make_dir_absolute(blocked_tmp) == OK, "directory blocks only this isolated atomic temporary file")
	GameState.save_enabled = true
	EventBus.gold_changed.connect(_attempt_reward_signal_save)
	host.action("campaign|dynamic|act|" + str(a.id))
	EventBus.gold_changed.disconnect(_attempt_reward_signal_save)
	check(dynamic._done(a), "actual on-site rescue remains complete after storage failure")
	check(reward_signal_checked, "actual reward gold signal exercised a synchronous interrupted-save attempt")
	check(Data.paid(GameState.campaign_quest, str(a.stage)), "one-time dynamic payment receipt remains in memory")
	check(FileAccess.get_file_as_bytes(GameState.SAVE_PATH) == previous_bytes, "failed final write preserves every byte of the earlier saved state")
	check(GameState.last_save_unix == previous_save_time and GameState._save_timer > 0.0, "failure never claims a newer successful disk save and leaves retry scheduled")
func _attempt_reward_signal_save(_value: int) -> void:
	reward_signal_checked = true
	check(GameState._world_reward_depth > 0, "real dynamic payout holds the world transaction lock")
	check(not GameState.save_now(true), "synchronous save request cannot persist a partial reward")
	check(FileAccess.get_file_as_bytes(GameState.SAVE_PATH) == previous_bytes, "reward signal cannot expose partial payment on disk")
func persist_and_exit() -> void:
	if not blocked_tmp.is_empty():
		var id := "random_wounded:" + str(GameState.world_seed) + ":0"
		var paid_gold := GameState.gold
		var receipt: Dictionary = GameState.campaign_quest.quests[id].receipt.duplicate(true)
		host.action("campaign|dynamic|act|" + id + ":rescue")
		host.claim(id)
		check(GameState.gold == paid_gold and GameState.campaign_quest.quests[id].receipt == receipt, "repeated confirmation during failed storage cannot pay twice")
		check(DirAccess.remove_absolute(blocked_tmp) == OK, "recover only the deliberately blocked temporary path")
		GameState._process(GameState.SAVE_DEBOUNCE + 0.01)
		var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GameState.SAVE_PATH))
		check(int(saved.get("gold", -1)) == paid_gold and normalized(saved.get("campaign_quest", {}).get("quests", {}).get(id, {}).get("receipt", {})) == normalized(receipt), "automatic retry persists actual payout and receipt in the same snapshot")
		check(saved.get("campaign_quest", {}).get("encounters", {}).get("active", "missing").is_empty() and saved.has("ecology"), "retry preserves finite closure and complete ecology with the payment")
		print("CAMPAIGN_DYNAMIC_SAVE_FAILURE_CHECKS PASS" if failures == 0 else "CAMPAIGN_DYNAMIC_SAVE_FAILURE_CHECKS FAIL")
	super.persist_and_exit()
func verify_loaded() -> void:
	super.verify_loaded()
	if phase == "read_save_failure":
		var id := "random_wounded:" + str(GameState.world_seed) + ":0"
		check(Data.ready(GameState.campaign_quest, id) and Data.paid(GameState.campaign_quest, id), "new process loads the actual rescued state and paid receipt after retry")
		var gold := GameState.gold
		host.perform_action(id + ":rescue")
		host.claim(id)
		check(GameState.gold == gold and dynamic.encounters.total_issued() == 1, "cold duplicate action neither republishes reward nor refreshes finite quota")
