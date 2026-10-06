## 旧档装备兑换档位只恢复真实地图记忆：六地形、种子隔离、损坏字段与幂等保存。
extends Node

const SEED := 20260908
const LEVELS := {"plains": 1, "forest": 3, "snow": 5, "swamp": 5, "hill": 7, "lava": 10}
var _checks := 0
var _fails := 0
var _case := 0


func _ready() -> void:
	GameState.save_enabled = false
	WorldSim.stop()
	GameState.reset_all()
	_run.call_deferred()


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("  %s %s" % ["PASS" if ok else "FAIL", label])


func _base() -> Dictionary:
	return {"version": 17, "world_seed": SEED, "level": 1, "gold": 0, "checkpoints": []}


func _load_fixture(data: Dictionary) -> void:
	_case += 1
	GameState.SAVE_PATH = "user://equipment-exploration-%d.json" % _case
	var file := FileAccess.open(GameState.SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	GameState._load()


func _cell_for(terrain: String, resolution: float) -> Vector2i:
	BiomeMap.configure(SEED)
	for patch: Dictionary in BiomeMap.patches_of_terrain(terrain):
		var center := Vector2i(Vector2(patch["center"]) / resolution)
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var cell := center + Vector2i(dx, dy)
				var pos := (Vector2(cell) + Vector2.ONE * 0.5) * resolution
				if Rect2(Vector2.ZERO, BiomeMap.WORLD_SIZE).has_point(pos) and BiomeMap.terrain_at(pos) == terrain:
					return cell
	_check(false, "fixture can locate actual terrain " + terrain)
	return Vector2i.ZERO


func _put_fine(fog: ExplorationFog, cell: Vector2i) -> void:
	var key := Vector2i(cell.x >> 5, cell.y >> 5)
	var bytes: PackedByteArray = fog.chunks.get(key, PackedByteArray())
	if bytes.size() != ExplorationFog.CHUNK_BYTES:
		bytes.resize(ExplorationFog.CHUNK_BYTES)
	var index := (cell.y & 31) * 32 + (cell.x & 31)
	bytes[index >> 3] |= 1 << (index & 7)
	fog.chunks[key] = bytes


func _run() -> void:
	_test_six_terrains()
	_test_seed_isolation()
	_test_sparse_edges()
	_test_fail_closed()
	_test_no_inference()
	_test_idempotence()
	GameState.save_enabled = false
	print("=== EQUIPMENT EXPLORATION MIGRATION %s (%d checks) ===" % ["PASS" if _fails == 0 else "FAIL", _checks])
	get_tree().quit(0 if _fails == 0 else 1)


func _test_six_terrains() -> void:
	for terrain: String in LEVELS:
		var coarse := ExplorationFog.new(SEED)
		coarse.remember_legacy_cell(_cell_for(terrain, 4000.0))
		var old := _base()
		old["explored"] = Marshalls.raw_to_base64(coarse.legacy)
		_load_fixture(old)
		_check(GameState.equipment_explored_ilvl == LEVELS[terrain] and GameState.exploration.chunks.is_empty(), "old coarse known terrain migrates " + terrain)
		var fine := ExplorationFog.new(SEED)
		_put_fine(fine, _cell_for(terrain, ExplorationFog.CELL))
		var newer := _base()
		newer["exploration_v2"] = fine.to_dict()
		_load_fixture(newer)
		_check(GameState.equipment_explored_ilvl == LEVELS[terrain] and GameState.exploration.legacy.is_empty(), "sparse fine known terrain migrates " + terrain)


func _test_seed_isolation() -> void:
	BiomeMap.configure(SEED)
	var candidates: Array[Dictionary] = []
	for y in 20:
		for x in 20:
			var cell := Vector2i(x * 10, y * 10)
			var pos := (Vector2(cell) + Vector2.ONE * 0.5) * 4000.0
			candidates.append({"cell": cell, "level": LEVELS[BiomeMap.terrain_at(pos)]})
	BiomeMap.configure(SEED + 97)
	var chosen: Dictionary = {}
	for candidate: Dictionary in candidates:
		var pos := (Vector2(candidate["cell"]) + Vector2.ONE * 0.5) * 4000.0
		if candidate["level"] != LEVELS[BiomeMap.terrain_at(pos)]:
			chosen = candidate
			break
	_check(not chosen.is_empty(), "fixture distinguishes saved and previous world terrain")
	if chosen.is_empty():
		return
	var fog := ExplorationFog.new(SEED)
	fog.remember_legacy_cell(chosen["cell"])
	var old := _base()
	old["explored"] = Marshalls.raw_to_base64(fog.legacy)
	_load_fixture(old)
	_check(GameState.equipment_explored_ilvl == chosen["level"] and BiomeMap.current_seed() == SEED,
		"migration uses save seed even when checkpoint list is empty")


func _test_sparse_edges() -> void:
	var fog := ExplorationFog.new(SEED)
	_put_fine(fog, _cell_for("plains", 128.0))
	var high_cell := _cell_for("lava", 128.0)
	var zero := PackedByteArray()
	zero.resize(128)
	fog.chunks[Vector2i(high_cell.x >> 5, high_cell.y >> 5)] = zero
	var data := _base()
	data["exploration_v2"] = fog.to_dict()
	var start := Time.get_ticks_msec()
	_load_fixture(data)
	_check(GameState.equipment_explored_ilvl == 1, "unset high terrain in an allocated chunk never unlocks grade")
	_check(Time.get_ticks_msec() - start < 1500, "sparse migration does not construct whole-world raster")
	var invalid_edge := ExplorationFog.new(SEED)
	_put_fine(invalid_edge, Vector2i(6271, 6271))
	data = _base()
	data["exploration_v2"] = invalid_edge.to_dict()
	_load_fixture(data)
	_check(GameState.equipment_explored_ilvl == 1, "edge chunk bits beyond GRID6250 are ignored rather than clamped")
	var valid_edge := ExplorationFog.new(SEED)
	_put_fine(valid_edge, Vector2i(6249, 6249))
	data = _base()
	data["exploration_v2"] = valid_edge.to_dict()
	BiomeMap.configure(SEED)
	var expected: int = LEVELS[BiomeMap.terrain_at((Vector2(6249, 6249) + Vector2.ONE * 0.5) * 128.0)]
	_load_fixture(data)
	_check(GameState.equipment_explored_ilvl == expected, "last valid fine cell remains eligible at world edge")
	var mixed := ExplorationFog.new(SEED)
	mixed.remember_legacy_cell(_cell_for("forest", 4000.0))
	_put_fine(mixed, _cell_for("hill", 128.0))
	data = _base()
	data["exploration_v2"] = mixed.to_dict()
	_load_fixture(data)
	_check(GameState.equipment_explored_ilvl == 7, "coarse and fine remembered terrain use their maximum")


func _test_fail_closed() -> void:
	var high := ExplorationFog.new(SEED)
	high.remember_legacy_cell(_cell_for("lava", 4000.0))
	var mismatched := high.to_dict()
	mismatched["seed"] = SEED + 1
	var future := high.to_dict()
	future["version"] = 999
	var malformed := high.to_dict()
	malformed["legacy"] = "!".repeat(6668)
	malformed["chunks"] = {"0,0": "!".repeat(172)}
	for invalid: Variant in [null, {}, mismatched, future, malformed]:
		var data := _base()
		data["explored"] = Marshalls.raw_to_base64(high.legacy)
		data["exploration_v2"] = invalid
		_load_fixture(data)
		_check(GameState.equipment_explored_ilvl == 1 and GameState.exploration.legacy.is_empty(),
			"invalid explicit fine schema never falls back to tempting high old bitmap")
	var bad_old := _base()
	bad_old["explored"] = "!".repeat(6668)
	_load_fixture(bad_old)
	_check(GameState.equipment_explored_ilvl == 1, "invalid old base64 safely leaves starting grade")


func _test_no_inference() -> void:
	var data := _base()
	data["level"] = 90
	data["equips"] = {"weapon": {"name": "旧装", "rarity": 3, "slot": "weapon", "item_level": 10, "affixes": {"atk": 0.5}}}
	var lava := (Vector2(_cell_for("lava", 128.0)) + Vector2.ONE * 0.5) * 128.0
	data["player"] = {"x": lava.x, "y": lava.y, "hp": 100, "mp": 100}
	_load_fixture(data)
	_check(GameState.equipment_explored_ilvl == 1, "level old equipment and saved position never fabricate explored grade")
	data = _base()
	data["equipment_explored_ilvl"] = 7
	_load_fixture(data)
	_check(GameState.equipment_explored_ilvl == 7, "existing persisted grade is authoritative without scanning fog")
	var high := ExplorationFog.new(SEED)
	_put_fine(high, _cell_for("lava", 128.0))
	data["exploration_v2"] = high.to_dict()
	_load_fixture(data)
	_check(GameState.equipment_explored_ilvl == 7, "existing grade is not raised from merely visible extra terrain")


func _test_idempotence() -> void:
	var fog := ExplorationFog.new(SEED)
	_put_fine(fog, _cell_for("hill", 128.0))
	var data := _base()
	data["exploration_v2"] = fog.to_dict()
	_load_fixture(data)
	GameState.save_enabled = true
	_check(GameState.save_now(), "migrated grade persists through actual save boundary")
	GameState.save_enabled = false
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GameState.SAVE_PATH))
	_check(saved.get("equipment_explored_ilvl") == 7 and int(saved.get("version", 0)) == GameState.SAVE_VERSION,
		"saved current schema carries recovered highest known grade")
	GameState._load()
	_check(GameState.equipment_explored_ilvl == 7 and GameState.exploration.chunks.size() == 1,
		"repeated loading is idempotent and keeps sparse fog")
