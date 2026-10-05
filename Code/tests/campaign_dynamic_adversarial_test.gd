## Independent negative controls. Pure signal fixtures do not claim scene/gameplay completion.
extends "res://tests/campaign_world_facts_test.gd"
func _run() -> void:
	_test_migration_preview_identity()
	_test_decline_origin_disappears(false)
	_test_decline_origin_disappears(true)
	_test_random_rock_crossing_geometry()
	print("CAMPAIGN_DYNAMIC_ADVERSARIAL_TEST %s checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)
func _test_migration_preview_identity() -> void:
	var sim := _sim(20, true)
	var facts := _facts(sim)
	facts.obtain_clue("a", "fixture:read_migration_record")
	sim.tick()
	var engine := Encounters.new()
	engine.configure(sim, 734, {}, facts)
	var preview := engine.candidate("random_migration", _context())
	_check(not preview.is_empty(), "real migration with an earned clue provides a preview")
	if preview.is_empty(): facts.free(); return
	var first: Dictionary = preview.proof.migration.duplicate(true)
	sim.tick()
	var fresh := engine.candidate("random_migration", _context())
	_check(not fresh.is_empty() and first != fresh.proof.migration, "later real expansion changes the migration witness while the old dialogue is open")
	var accepted := engine.accept(preview, _context())
	_check(not accepted or engine.active().proof.migration == first, "stale migration dialogue cannot silently substitute another instance/tick witness")
	facts.free()
func _test_random_rock_crossing_geometry() -> void:
	BiomeMap.configure(734)
	ObstacleField.restore_destroyed([])
	for ordinal in 3:
		var id := "random_rocks:734:%d" % ordinal
		var from := CampaignLayout.object_position(id + ":target")
		var to := CampaignLayout.object_position(id + ":return")
		var cells := CampaignLayout.barrier_cells(id + ":barrier")
		_check(cells.size() > 0, "rock instance %d has actual authored breakable cells" % ordinal)
		var crosses := false
		for cell: Vector2i in cells:
			var point := (Vector2(cell) + Vector2(0.5, 0.5)) * 32.0
			if Geometry2D.get_closest_point_to_segment(point, from, to).distance_to(point) < 32.0: crosses = true
		_check(crosses and not _clear_segment(from, to), "rock instance %d's claimed new crossing actually intersects its unbroken barrier" % ordinal)
		print("ROCK_ROUTE ordinal=%d from=%s to=%s barrier=%s clear_before_break=%s" % [ordinal, from, to, cells, _clear_segment(from, to)])

func _clear_segment(from: Vector2, to: Vector2) -> bool:
	var count := maxi(1, ceili(from.distance_to(to) / 16.0))
	for index in count + 1:
		if ObstacleField.nav_blocked_at(from.lerp(to, float(index) / count)): return false
	return true

func _test_decline_origin_disappears(cold: bool) -> void:
	var sim := _sim(4, true)
	var facts := _facts(sim)
	sim.tick()
	sim.find_species("fixture").migrate_count = 0
	var first_region := str(facts.snapshot().decline_runs.get("fixture", {}).get("region_id", ""))
	_check(not first_region.is_empty() and sim.alive_count_in(first_region) == 1, "genuine first low-population tick records the one-survivor origin")
	for inst: MonsterInstance in sim.instances.values():
		if inst.is_alive and inst.region_id == first_region: sim._die(inst, EcologySim.DEATH_AGING)
	sim.tick()
	if cold:
		var saved: Dictionary = JSON.parse_string(JSON.stringify(facts.snapshot()))
		facts.free()
		facts = _facts(sim, saved)
	sim.tick()
	var trigger := facts.decline_trigger()
	_check(not trigger.is_empty() and sim.alive_count_of_species("fixture") == 3, "continuous real low population still correctly triggers after original local witness dies")
	_check(trigger.get("position", []).size() == 2, "pinned decline trigger retains a genuine usable historical source even when its original region becomes empty")
	print("DECLINE_EMPTY_ORIGIN cold=%s " % cold + JSON.stringify(trigger))
	facts.free()
