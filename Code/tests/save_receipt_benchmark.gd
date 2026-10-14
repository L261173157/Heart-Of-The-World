## 固定世界种子、正式来源生成；11次真实写入，包含flush、回读和原子替换。
extends Node

func _ready() -> void:
	GameState.save_enabled = false
	GameState.set_process(false)
	WorldSim.set_process(false)
	_run.call_deferred()

func _run() -> void:
	GameState.reset_all()
	GameState.world_seed = BiomeMap.DEFAULT_SEED
	var drops := preload("res://scripts/equipment/equipment_drops.gd")
	for n in [0, 1000, 5000, 10000]:
		GameState.equipment_drop_state = drops.empty_state()
		for i in n:
			var source: Dictionary = drops.create_source(GameState.world_seed, "ordinary", i + 1, 0, "plains")
			drops.begin_combat(GameState.equipment_drop_state, source, {}, "weapon")
			source["player_kill"] = true
			drops.settle(GameState.equipment_drop_state, source)
		GameState.save_enabled = true
		var times: Array = []
		for rep in 11:
			var begin := Time.get_ticks_usec()
			GameState.save_now(false)
			times.append((Time.get_ticks_usec() - begin) / 1000.0)
		print("PROBE_DROP_SAMPLES kills=", n, " times_ms=", times)
		times.sort()
		print("PROBE_DROP_PERF kills=", n, " bytes=", FileAccess.get_file_as_bytes(GameState.SAVE_PATH).size(), " median_ms=", times[5], " max_ms=", times[10])
	GameState.save_enabled = false
	get_tree().quit()
