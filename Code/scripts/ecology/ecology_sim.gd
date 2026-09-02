## 生态模拟器（纯逻辑核心，RefCounted）。
## 闭环：老化死亡 → 尸体消散 → 繁衍补员 → 过量扩张；多物种共享区域承载（种间竞争），
## 栖息地约束迁徙方向，史莱姆型种族被击杀时分裂子代（越杀越多）。
## 架构铁律：本类及 scripts/ecology/ 下所有依赖禁止引用 Node / 场景树；
## 未来联机化时整体搬到服务端做权威模拟，客户端只消费信号与快照。
## 所有状态变更只能通过 tick() 或 report_killed() 进入，保证模拟单点权威。
class_name EcologySim
extends RefCounted

signal instance_spawned(inst: MonsterInstance)
signal instance_died(inst: MonsterInstance, cause: String)
signal instance_migrated(inst: MonsterInstance, to_region_id: String)
signal corpse_expired(inst: MonsterInstance)
signal tick_completed(summary: Dictionary)
## 巢穴状态变化（active=true 建立/重建，false 被捣毁）——表现层据此增删巢体
signal nest_changed(region_id: String, species_name: String, active: bool)

const DEATH_AGING := "aging"
const DEATH_KILLED := "killed"
## 捕食死亡（生态链内耗，不触发分裂——只有"被打碎"才裂）
const DEATH_PREDATED := "predated"
## 每 tick 每个捕食者的捕食概率（温和值：压制但不清洗）
const PREDATION_CHANCE := 0.08

## 繁衍变异出精英的概率与体型放大系数（纯逻辑常量，表现层与奖励自动跟随 size_scale）
const ELITE_CHANCE := 0.04
const ELITE_SIZE_MULT := 1.45

## 生态韧性（rescue effect）：玩家猎杀压力可能摧毁核心卖点本身。
## 濒危物种（全球 <ENDANGERED_THRESHOLD 只）繁衍加速；灭绝物种罕见重引入
## （"从世界边缘迁徙回来"），灭绝事件仍戏剧化但可逆——重引入后世界事件会播报"物种复苏"。
var reintroduction_enabled := true
## 捕食开关（测试隔离用；默认开）
var predation_enabled := true
const ENDANGERED_THRESHOLD := 6
const RESCUE_BREED_MULT := 3.0
const REINTRODUCE_CHANCE := 0.05
const REINTRODUCE_COUNT := 2

var regions: Dictionary = {}
var instances: Dictionary = {}
var species_list: Array[SpeciesData] = []
var next_id: int = 1
var tick_count: int = 0
## Boss 重生倒计时 { species_name: ticks_left }
var boss_respawn_timers: Dictionary = {}

## 巢穴：{ "region_id|species": {"active": bool, "rebuild": int} }。
## 物种在区域首次立足自动建巢；捣毁 → 该区域该物种繁衍停止 + 全族激怒（表现层），
## rebuild 倒计时归零后重建（物种重新立足）。玩家"管理生态"的主动工具。
var nests: Dictionary = {}
const NEST_REBUILD_TICKS := 120


## p_regions: Array[SimRegion]；p_species_list: Array[SpeciesData]；
## initial: { region_id: { species_name: 初始数量 } }，用随机年龄初始化种群
func setup(p_regions: Array, p_species_list: Array[SpeciesData], initial: Dictionary) -> void:
	for region in p_regions:
		regions[region.id] = region
	species_list = p_species_list
	for region_id: String in initial:
		if regions.get(region_id) == null:
			push_warning("初始种群引用了不存在的区域：%s" % region_id)
			continue
		for species_name: String in initial[region_id]:
			var species := find_species(species_name)
			if species == null:
				push_warning("初始种群引用了不存在的种族：%s" % species_name)
				continue
			var count: int = initial[region_id][species_name]
			for i in count:
				if species.is_boss:
					# Boss 以成年巨体入场（与重生逻辑一致）
					spawn_instance(species, region_id, species.maturity_age, 0, 2.2, false)
				else:
					spawn_instance(species, region_id, randi_range(5, 60))


func find_species(species_name: String) -> SpeciesData:
	for species in species_list:
		if species.species_name == species_name:
			return species
	return null


func spawn_instance(species: SpeciesData, region_id: String, age := 0,
		generation := 0, size_scale := 1.0, p_elite := false) -> MonsterInstance:
	var inst := MonsterInstance.new()
	inst.id = next_id
	next_id += 1
	inst.species = species
	inst.region_id = region_id
	inst.age = age
	inst.lifespan = randi_range(species.lifespan_min, species.lifespan_max)
	inst.generation = generation
	inst.size_scale = size_scale * ELITE_SIZE_MULT if p_elite else size_scale
	inst.is_elite = p_elite
	var region: SimRegion = regions.get(region_id)
	inst.threat_scale = region.threat if region else 1.0
	instances[inst.id] = inst
	_ensure_nest(region_id, species.species_name)
	instance_spawned.emit(inst)
	return inst


## 物种在区域首次立足时建巢（已存在则不动——捣毁状态由 rebuild 倒计时恢复）。
## Boss 物种不建巢：繁衍率恒为 0，捣毁"Boss 巢"没有任何生态效果，
## 立一个可攻击却无意义的巢只会误导玩家
func _ensure_nest(region_id: String, species_name: String) -> void:
	var species := find_species(species_name)
	if species != null and species.is_boss:
		return
	var key := "%s|%s" % [region_id, species_name]
	if nests.has(key):
		return
	nests[key] = {"active": true, "rebuild": 0}
	nest_changed.emit(region_id, species_name, true)


## 捣毁巢穴（表现层入口）：该区域该物种繁衍停止 + 全族激怒，rebuild 后重建
func destroy_nest(region_id: String, species_name: String) -> bool:
	var key := "%s|%s" % [region_id, species_name]
	var nest: Dictionary = nests.get(key, {})
	if nest.is_empty() or not nest["active"]:
		return false
	nest["active"] = false
	nest["rebuild"] = NEST_REBUILD_TICKS
	nests[key] = nest
	nest_changed.emit(region_id, species_name, false)
	return true


func _process_nests() -> void:
	for key in nests:
		var nest: Dictionary = nests[key]
		if nest["active"]:
			continue
		nest["rebuild"] = int(nest["rebuild"]) - 1
		if int(nest["rebuild"]) <= 0:
			nest["active"] = true
			nest_changed.emit(key.get_slice("|", 0), key.get_slice("|", 1), true)
		nests[key] = nest


func get_region(region_id: String) -> SimRegion:
	return regions.get(region_id)


func get_region_center(region_id: String) -> Vector2:
	var region: SimRegion = regions.get(region_id)
	return region.center if region else Vector2.ZERO


## 玩家所在区域（表现层可据contains_point判定；此处提供中心回退）
func region_of_point(point: Vector2) -> SimRegion:
	for region: SimRegion in regions.values():
		if region.contains_point(point):
			return region
	return null


func alive_count_in(region_id: String, species: SpeciesData = null) -> int:
	var count := 0
	for inst: MonsterInstance in instances.values():
		if inst.is_alive and inst.region_id == region_id and (species == null or inst.species == species):
			count += 1
	return count


## 玩家击杀入口（表现层调用，at_position 回填死亡位置供分裂子代继承）；
## 自然老化死亡走 tick 内部
func report_killed(id: int, at_position := Vector2.INF) -> void:
	var inst: MonsterInstance = instances.get(id)
	if inst == null or not inst.is_alive:
		return
	inst.death_pos = at_position
	_die(inst, DEATH_KILLED)


func tick() -> void:
	tick_count += 1
	_process_aging()
	_process_corpses()
	_process_breeding()
	_process_expansion()
	_process_predation()
	_process_reintroduction()
	_process_boss_respawn()
	_process_nests()
	tick_completed.emit(_build_summary())


func _process_aging() -> void:
	var aged_out: Array[MonsterInstance] = []
	for inst: MonsterInstance in instances.values():
		if not inst.is_alive:
			continue
		inst.age += 1
		if inst.age >= inst.lifespan:
			aged_out.append(inst)
	for inst in aged_out:
		_die(inst, DEATH_AGING)


func _process_corpses() -> void:
	var expired: Array[MonsterInstance] = []
	for inst: MonsterInstance in instances.values():
		if inst.is_alive or inst.corpse_ticks < 0:
			continue
		inst.corpse_ticks -= 1
		if inst.corpse_ticks <= 0:
			expired.append(inst)
	for inst in expired:
		instances.erase(inst.id)
		corpse_expired.emit(inst)


## 单次遍历统计各「区域|种族」存活/成年数、区域总数与物种全球存活数，
## 返回 { "cells": { "region|species": {alive, adults} },
##        "region_totals": { region: int }, "global_totals": { species: int } }
func _count_population() -> Dictionary:
	var cells := {}
	var region_totals := {}
	var global_totals := {}
	for inst: MonsterInstance in instances.values():
		if not inst.is_alive:
			continue
		var key := "%s|%s" % [inst.region_id, inst.species.species_name]
		if not cells.has(key):
			cells[key] = {"alive": 0, "adults": 0}
		cells[key]["alive"] += 1
		if inst.is_adult():
			cells[key]["adults"] += 1
		region_totals[inst.region_id] = region_totals.get(inst.region_id, 0) + 1
		global_totals[inst.species.species_name] = \
				global_totals.get(inst.species.species_name, 0) + 1
	return {"cells": cells, "region_totals": region_totals, "global_totals": global_totals}


func _process_breeding() -> void:
	var stats := _count_population()
	var cells: Dictionary = stats["cells"]
	var region_totals: Dictionary = stats["region_totals"]
	var global_totals: Dictionary = stats["global_totals"]
	for region: SimRegion in regions.values():
		var alive_total: int = region_totals.get(region.id, 0)
		if alive_total >= region.capacity:
			continue
		for species in species_list:
			if species.breeding_rate <= 0.0 or not region.terrain in species.habitats:
				continue
			# 巢穴被捣毁则该区域该物种繁衍停止（生态管理的主动杠杆）
			var nest: Dictionary = nests.get("%s|%s" % [region.id, species.species_name], {})
			if not nest.is_empty() and not nest["active"]:
				continue
			var key := "%s|%s" % [region.id, species.species_name]
			var adults: int = cells[key]["adults"] if cells.has(key) else 0
			# 每个成年个体每 tick 独立掷骰，总量不超过区域承载（全物种共享，形成种间竞争）；
			# 全球濒危（< ENDANGERED_THRESHOLD 只）时繁衍加速——rescue effect，防止猎杀压力摧毁种群
			var rate: float = species.breeding_rate
			var global_total: int = global_totals.get(species.species_name, 0)
			if global_total > 0 and global_total < ENDANGERED_THRESHOLD:
				rate = minf(1.0, rate * RESCUE_BREED_MULT)
			# 每个成年个体每 tick 独立掷骰
			for i in adults:
				if alive_total >= region.capacity:
					break
				if randf() < rate:
					# 新生儿有概率变异成精英（种群演化的可见个体差异）
					spawn_instance(species, region.id, 0, 0, 1.0, randf() < ELITE_CHANCE)
					alive_total += 1


func _process_expansion() -> void:
	var stats := _count_population()
	var cells: Dictionary = stats["cells"]
	var region_totals: Dictionary = stats["region_totals"]
	for species in species_list:
		if species.migrate_count <= 0 or species.habitats.is_empty():
			continue
		for region: SimRegion in regions.values():
			if not region.terrain in species.habitats:
				continue
			var key := "%s|%s" % [region.id, species.species_name]
			var alive: int = cells[key]["alive"] if cells.has(key) else 0
			if alive <= species.expansion_threshold:
				continue
			# 选同种族存活数最少、且是自己栖息地的相邻区域迁入
			var target: SimRegion = null
			var target_alive := INF
			for neighbor_id in region.neighbor_ids:
				var neighbor: SimRegion = regions.get(neighbor_id)
				if neighbor == null or not neighbor.terrain in species.habitats:
					continue
				var nkey := "%s|%s" % [neighbor.id, species.species_name]
				var neighbor_alive: int = cells[nkey]["alive"] if cells.has(nkey) else 0
				if neighbor_alive < target_alive:
					target = neighbor
					target_alive = neighbor_alive
			if target == null:
				continue
			# 随机挑存活个体迁移（数量不超过迁入区「全物种」剩余承载）
			var movable: Array[MonsterInstance] = []
			for inst: MonsterInstance in instances.values():
				if inst.is_alive and inst.region_id == region.id and inst.species == species:
					movable.append(inst)
			movable.shuffle()
			var target_key := "%s|%s" % [target.id, species.species_name]
			var target_total: int = region_totals.get(target.id, 0)
			var moved := 0
			for inst in movable:
				if moved >= species.migrate_count:
					break
				if target_total + moved >= target.capacity:
					break
				inst.region_id = target.id
				inst.threat_scale = target.threat
				moved += 1
				instance_migrated.emit(inst, target.id)
			if moved > 0:
				cells[key]["alive"] = alive - moved
				if not cells.has(target_key):
					cells[target_key] = {"alive": 0, "adults": 0}
				cells[target_key]["alive"] += moved
				region_totals[target.id] = target_total + moved
				region_totals[region.id] = region_totals.get(region.id, 0) - moved
				# 迁入即立足：新区域同样建巢，捣巢才能遏制入侵物种繁衍
				_ensure_nest(target.id, species.species_name)


## 灭绝物种的罕见重引入：在其栖息地匹配且未满的区域生成成年对。
## 叙事口径"从世界边缘迁徙回来"；表现层经 world_event 的"物种复苏"播报
func _process_reintroduction() -> void:
	if not reintroduction_enabled:
		return
	var totals := {}
	for inst: MonsterInstance in instances.values():
		if inst.is_alive:
			totals[inst.species.species_name] = totals.get(inst.species.species_name, 0) + 1
	for species in species_list:
		# Boss 有独立的重生倒计时（boss_respawn_ticks），不走灭绝重引入——
		# 否则倒计时未到就被"从世界边缘迁徙回来"刷出复数 Boss，破坏顶点节奏
		if species.is_boss:
			continue
		if int(totals.get(species.species_name, 0)) > 0 or randf() >= REINTRODUCE_CHANCE:
			continue
		for region: SimRegion in regions.values():
			if not region.terrain in species.habitats:
				continue
			var room: int = region.capacity - alive_count_in(region.id)
			if room <= 0:
				continue
			for i in mini(REINTRODUCE_COUNT, room):
				spawn_instance(species, region.id, species.maturity_age + randi_range(0, 10))
			break


## 捕食：同区域内，每个捕食者每 tick 以 PREDATION_CHANCE 猎杀一只猎物。
## 这是生态级联的引擎——玩家清剿捕食者会让猎物种群爆发。
func _process_predation() -> void:
	if not predation_enabled:
		return
	for predator: MonsterInstance in instances.values():
		if not predator.is_alive or predator.species.prey.is_empty():
			continue
		if randf() >= PREDATION_CHANCE:
			continue
		for prey_name: String in predator.species.prey:
			var victim: MonsterInstance = null
			for cand: MonsterInstance in instances.values():
				if cand.is_alive and cand.region_id == predator.region_id \
						and cand.species.species_name == prey_name and not cand.species.is_boss:
					victim = cand
					break
			if victim != null:
				victim.death_pos = Vector2.INF
				_die(victim, DEATH_PREDATED)
				break


## Boss 重生：is_boss 物种全球全灭后，倒计时归零时在其栖息地（承载未满）重生一只。
## 世界永远有值得挑战的顶点
func _process_boss_respawn() -> void:
	for species in species_list:
		if not species.is_boss:
			continue
		var alive := false
		for inst: MonsterInstance in instances.values():
			if inst.species == species and inst.is_alive:
				alive = true
				break
		if alive:
			boss_respawn_timers[species.species_name] = species.boss_respawn_ticks
			continue
		var left: int = boss_respawn_timers.get(species.species_name, species.boss_respawn_ticks) - 1
		if left > 0:
			boss_respawn_timers[species.species_name] = left
			continue
		boss_respawn_timers[species.species_name] = species.boss_respawn_ticks
		for region: SimRegion in regions.values():
			if not region.terrain in species.habitats or alive_count_in(region.id) >= region.capacity:
				continue
			spawn_instance(species, region.id, species.maturity_age, 0, 2.2, false)
			break


func _die(inst: MonsterInstance, cause: String) -> void:
	inst.is_alive = false
	inst.corpse_ticks = inst.species.corpse_duration
	instance_died.emit(inst, cause)
	# 分裂繁殖：只有被击杀（被打碎）才会裂出子代，自然老死不分裂——
	# 玩家刷怪会助推种群扩张，"越杀越多"的取舍是本作的生态博弈点
	if cause == DEATH_KILLED and inst.can_split():
		_spawn_splits(inst)


func _spawn_splits(parent: MonsterInstance) -> void:
	var region: SimRegion = regions.get(parent.region_id)
	if region == null:
		return
	var room: int = region.capacity - alive_count_in(region.id)
	var count := mini(parent.species.split_count, maxi(0, room))
	for i in count:
		var child := spawn_instance(parent.species, parent.region_id, 0,
				parent.generation + 1, parent.size_scale * parent.species.split_size_scale)
		# 子代在母体死亡处裂开（未记录位置则回退区域锚点落点）
		if parent.death_pos != Vector2.INF:
			child.spawn_pos = parent.death_pos


func _build_summary() -> Dictionary:
	# 单趟遍历累加（原为每区域各扫一遍全体实例，O(区域×个体)）
	var by_region := {}
	for region: SimRegion in regions.values():
		by_region[region.id] = {"summary": region.to_dict(), "alive": 0, "species": {}}
	var total_alive := 0
	for inst: MonsterInstance in instances.values():
		if not inst.is_alive:
			continue
		var bucket: Dictionary = by_region.get(inst.region_id, {})
		if bucket.is_empty():
			continue
		bucket["alive"] += 1
		var name := inst.species.species_name
		bucket["species"][name] = bucket["species"].get(name, 0) + 1
		total_alive += 1
	var region_summaries: Array[Dictionary] = []
	for region: SimRegion in regions.values():
		var bucket: Dictionary = by_region[region.id]
		bucket["summary"]["alive"] = bucket["alive"]
		bucket["summary"]["species"] = bucket["species"]
		region_summaries.append(bucket["summary"])
	return {
		"tick": tick_count,
		"regions": region_summaries,
		"total_alive": total_alive,
	}
