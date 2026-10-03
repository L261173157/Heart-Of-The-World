## 巡猎资格回归：真实玩家/怪物场景持续跑物理帧，不重建节点、不手动调用资格函数。
## 合成区域仅固定归属边界；实例仍由 EcologySim 产生，六种 AI 使用实际物种参数。
extends Node2D

const PLAYER := preload("res://scenes/player/player.tscn")
const GOBLIN := preload("res://scenes/monsters/goblin.tscn")
const ORIGIN := Vector2(120000, 120000)
const RECHECK_WAIT := MonsterBase.HUNT_RECHECK_INTERVAL + 0.15
var _player: Player
var _checks := 0
var _fails := 0
var _species: Array[SpeciesData] = []


func _ready() -> void:
	GameState.save_enabled = false
	GameState.reset_all()
	WorldSim.stop()
	BiomeMap.configure(BiomeMap.DEFAULT_SEED)
	ObstacleField.restore_destroyed([])
	_species = SpeciesCatalog.build_all()
	_run.call_deferred()


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])


func _region(id: String, center: Vector2, size: Vector2) -> SimRegion:
	var region := SimRegion.new()
	region.id = id
	region.center = center
	region.size = size
	region.capacity = 1000
	return region


func _set_regions(regions: Array) -> void:
	WorldSim.sim = EcologySim.new()
	WorldSim.sim.setup(regions, _species, {})


func _wide_region() -> void:
	_set_regions([_region("outdoors", Vector2(400000, 400000), Vector2(1000000, 1000000))])


func _monster(species_id: String, scene: PackedScene, pos: Vector2,
		region_id := "outdoors") -> MonsterBase:
	var species: SpeciesData = load("res://data/species/%s.tres" % species_id)
	var inst := WorldSim.sim.spawn_instance(species, region_id, species.maturity_age,
		0, 1.0, false, pos)
	var monster: MonsterBase = scene.instantiate()
	add_child(monster)
	monster.setup(inst)
	monster.position = pos
	# 无导航网格的独立场景关闭避让；保留真实物理移动、LOD、状态分派与子类。
	monster._nav.avoidance_enabled = false
	return monster


func _wait(seconds := RECHECK_WAIT) -> void:
	await get_tree().create_timer(seconds, true, true).timeout
	await get_tree().process_frame


func _remove(monster: MonsterBase) -> void:
	monster.queue_free()
	await get_tree().process_frame


func _run() -> void:
	seed(20261003)
	_player = PLAYER.instantiate()
	add_child(_player)
	_player.set_physics_process(false)
	_player.set_process(false)
	_player.get_node("Camera2D").enabled = false
	_player.current_hp = _player.stats.max_hp()
	await get_tree().physics_frame
	await _preloaded_region_entry()
	await _distance_and_combat_handoff()
	await _safe_places_and_lifecycle()
	await _prototype_guards()
	_player.queue_free()
	await get_tree().process_frame
	WorldSim.stop()
	print("=== HUNT ELIGIBILITY %s (%d checks) ===" % ["PASS" if _fails == 0 else "FAIL", _checks])
	get_tree().quit(0 if _fails == 0 else 1)


func _preloaded_region_entry() -> void:
	_set_regions([
		_region("west", ORIGIN - Vector2(3000, 0), Vector2(6000, 6000)),
		_region("east", ORIGIN + Vector2(3000, 0), Vector2(6000, 6000)),
	])
	_player.position = ORIGIN - Vector2(500, 0)
	var monster := _monster("goblin", GOBLIN, ORIGIN + Vector2(1200, 0), "east")
	var node_id := monster.get_instance_id()
	var instance := monster.inst
	var spawn := instance.spawn_pos
	var anchor := monster.anchor
	_check(not monster._hunt_mode, "相邻区域预载时不巡猎")
	await _wait()
	_check(not monster._hunt_mode, "玩家未进区时重复检查仍不跨区巡猎")
	_player.position = ORIGIN + Vector2(500, 0)
	var before := monster.global_position.distance_to(_player.global_position)
	await _wait()
	_check(monster._hunt_mode and monster.state == MonsterBase.S_PATROL,
		"近档已有节点在玩家跨区后自动取得巡猎资格")
	_check(monster.global_position.distance_to(_player.global_position) < before - 3.0,
		"取得资格后真实身体向玩家逼近")
	_check(monster.get_instance_id() == node_id and monster.inst == instance
		and instance.spawn_pos == spawn and monster.anchor == anchor,
		"进区不重建节点、不挪动模拟出生点或据点锚点")
	_player.position = ORIGIN - Vector2(500, 0)
	await _wait()
	_check(not monster._hunt_mode and monster.state == MonsterBase.S_PATROL,
		"玩家退回邻区后取消已有巡猎")
	_player.position = ORIGIN + Vector2(500, 0)
	await _wait()
	_check(monster._hunt_mode, "同一节点再次进区可重新巡猎")
	_player.position = ORIGIN + Vector2(0, 6000)
	await _wait()
	_check(not monster._hunt_mode, "玩家离开所有有效模拟区域后不残留巡猎")
	await _remove(monster)


func _distance_and_combat_handoff() -> void:
	_wide_region()
	_player.position = ORIGIN - Vector2(MonsterBase.HUNT_MAX_DIST + 400.0, 0)
	var monster := _monster("goblin", GOBLIN, ORIGIN)
	var node_id := monster.get_instance_id()
	_check(not monster._hunt_mode, "同区超出巡猎上限时不启动")
	_player.position = ORIGIN - Vector2(MonsterBase.HUNT_MAX_DIST - 400.0, 0)
	var before := monster.position.x
	await _wait()
	_check(monster._hunt_mode and monster.position.x < before - 3.0,
		"远档原有节点在玩家走入巡猎距离后真实移动")
	_check(monster.get_instance_id() == node_id and monster.anchor == ORIGIN
		and monster.inst.spawn_pos == ORIGIN, "远档走近不靠重新生成或移动据点")
	_player.position = ORIGIN - Vector2(MonsterBase.HUNT_MAX_DIST + 400.0, 0)
	await _wait()
	_check(not monster._hunt_mode, "玩家重新超出巡猎上限即取消，不跨世界追赶")
	# 放回同一个身体，在起步阈值外开始，之后仅通过真实物理帧接敌。
	monster.position = ORIGIN
	_player.position = ORIGIN - Vector2(monster.inst.species.detect_radius * 1.5 + 40.0, 0)
	var saw_inside_start_band := false
	var reached_combat := false
	for frame in 360:
		await get_tree().physics_frame
		await get_tree().process_frame
		var dist := monster.global_position.distance_to(_player.global_position)
		saw_inside_start_band = saw_inside_start_band or (monster._hunt_mode
			and dist < monster.inst.species.detect_radius * 1.5)
		if monster.state == MonsterBase.S_CHASE or monster.state == MonsterBase.S_ATTACK:
			reached_combat = true
			break
	_check(saw_inside_start_band, "重算保留已启动巡猎，不在1.5倍侦测圈外反复停走")
	_check(reached_combat and not monster._hunt_mode, "巡猎自然交接到原有近身战斗状态")
	# 既有短时仇恨锁保留；之后按原侦测脱战，并受当前区域约束阻止再巡猎。
	monster._aggro_lock = 1.5
	_player.position = monster.position - Vector2(600, 0)
	await _wait()
	_check(monster.state == MonsterBase.S_CHASE and monster._aggro_lock > 0.0,
		"资格重算不清空已有战斗仇恨锁")
	_player.position = ORIGIN - Vector2(MonsterBase.HUNT_MAX_DIST + 400.0, 0)
	await _wait(1.7)
	_check(monster.state == MonsterBase.S_PATROL and not monster._hunt_mode,
		"原仇恨锁到期后仍正常脱战，不因资格刷新无限追击")
	await _remove(monster)


func _safe_places_and_lifecycle() -> void:
	_wide_region()
	var home := WorldConfig.spawn_pos()
	var town_edge := WorldConfig.HOME_CAMP_RADIUS
	var town_world: Script = load("res://scripts/main/game_world.gd")
	_check(is_equal_approx(town_edge, town_world.CAMP_HEAL_RADIUS),
		"巡猎与真实营地回血/音乐共用边界，不消费障碍净空半径")
	_player.position = home + Vector2(2000, 0)
	var monster := _monster("goblin", GOBLIN, home + Vector2(3500, 0))
	_check(monster._hunt_mode, "户外近营地怪物可正常开始巡猎")
	_player.position = home + Vector2(town_edge, 0)
	await _wait()
	_check(not monster._hunt_mode, "玩家返回城镇实际安全圈边界后取消巡猎")
	_player.position = home + Vector2(town_edge + 64.0, 0)
	await _wait()
	_check(monster._hunt_mode and _player.position.distance_to(home) < ObstacleField.SPAWN_CLEAR,
		"离开实际城镇后原节点立即可重获巡猎资格，不等待走出1200px障碍净空")
	await _remove(monster)
	_player.position = home + Vector2(town_edge * 0.5, 0)
	monster = _monster("goblin", GOBLIN, home + Vector2(3500, 0))
	_check(not monster._hunt_mode, "玩家仍在城镇内时预载怪物保持安静")
	_player.position = home + Vector2(town_edge + 64.0, 0)
	await _wait()
	_check(monster._hunt_mode, "镇内预载的同一怪物在刚出城后取得资格，保留早期遭遇")
	await _remove(monster)
	for index in ObstacleField.INTERIOR_POCKETS.size():
		var room := ObstacleField.interior_pocket(index)
		_player.position = room + Vector2(500, 0)
		monster = _monster("goblin", GOBLIN, room + Vector2(1400, 0))
		_check(monster._hunt_mode, "室内口袋外的正常户外不误判为进屋 %d" % index)
		_player.position = room
		await _wait()
		_check(not monster._hunt_mode, "同区且距离有效时进入实际室内仍取消巡猎 %d" % index)
		_player.position = room + Vector2(500, 0)
		await _wait()
		_check(monster._hunt_mode, "从室内返回户外可重新巡猎 %d" % index)
		await _remove(monster)
	_player.position = ORIGIN
	monster = _monster("goblin", GOBLIN, ORIGIN + Vector2(1400, 0))
	_player.visible = false
	await _wait()
	_check(not monster._hunt_mode, "不可见玩家不被巡猎")
	_player.visible = true
	await _wait()
	_check(monster._hunt_mode, "玩家重新可见后重新检查资格")
	# 真实致死伤害：趁死亡淡出尚可见，在下一物理帧走到定期检查时机。
	monster._hunt_recheck_remaining = 0.0
	_player._protect_timer = 0.0
	_player._hurt_iframes = 0.0
	_player.take_damage(100000.0)
	await get_tree().physics_frame
	await get_tree().process_frame
	_check(_player._is_dead and _player.visible and not monster._hunt_mode,
		"真实死亡淡出前仍可见时也必须取消巡猎")
	await _wait()
	_check(not monster._hunt_mode, "死亡后持续检查不重新拉起巡猎")
	_player._respawn()
	_player.position = ORIGIN
	await _wait()
	_check(monster._hunt_mode, "真实复活回到户外后原怪物重新巡猎")
	monster.on_migrate("outdoors", monster.position + Vector2(3000, 0))
	await _wait()
	_check(monster.state == MonsterBase.S_MIGRATING and not monster._hunt_mode,
		"生态迁徙优先且不被周期巡猎重算抢占")
	monster.on_sim_death()
	await _wait()
	_check(monster.state == MonsterBase.S_CORPSE and not monster._hunt_mode
		and monster.velocity == Vector2.ZERO, "死亡怪物不再取得巡猎资格")
	await _remove(monster)


func _prototype_guards() -> void:
	_wide_region()
	_player.position = ORIGIN
	var cases := [
		["goblin", "goblin"], ["slime", "slime"], ["boar", "boar"],
		["spider", "spider"], ["beetle", "ant"], ["guardian", "guardian"],
		["chicken", "goblin"], ["stag_beetle_king", "ant"],
	]
	var monsters: Array[MonsterBase] = []
	for index in cases.size():
		var entry: Array = cases[index]
		var scene: PackedScene = load("res://scenes/monsters/%s.tscn" % entry[1])
		var monster := _monster(entry[0], scene, ORIGIN + Vector2(1600, index * 160))
		monsters.append(monster)
		_check(monster._hunt_mode == (index < 6), "初始资格遵守原型/Boss/被动约束：" + entry[0])
	await _wait()
	for index in monsters.size():
		var monster := monsters[index]
		_check(monster._hunt_mode == (index < 6), "持续资格遵守原型/Boss/被动约束：" + cases[index][0])
		monster.queue_free()
	await get_tree().process_frame
