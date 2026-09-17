## 生态模拟器（纯逻辑核心，RefCounted）。
## 闭环：老化死亡 → 尸体消散 → 繁衍补员 → 过量扩张；多物种共享区域承载（种间竞争），
## 栖息地约束迁徙方向，红史莱姆型种族被击杀时分裂子代（越杀越多）。
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
## 巢穴状态变化（active=true 建立/重建，false 移除）——表现层据此增删巢体；
## p_ransacked=true 表示"被玩家捣毁"（激怒播报），false 表示种群灭绝后的自然荒废
signal nest_changed(region_id: String, species_name: String, active: bool, p_ransacked: bool)

const DEATH_AGING := "aging"
const DEATH_KILLED := "killed"
## 捕食死亡（生态链内耗，不触发分裂——只有"被打碎"才裂）
const DEATH_PREDATED := "predated"
## 每 tick 每个成年捕食者的猎杀掷骰概率。实际捕食压力 = 此概率 × 饱食限流
## （PREDATOR_SATIETY_TICKS）+ 濒危豁免——2026-09-03 探针实证（tools/eco_probe.gd）：
## 无结构约束时 6 个猎物物种 95% 以上时间处于灭绝态（灭绝→重引入脉冲循环）
const PREDATION_CHANCE := 0.08
## 捕食者饱食间隔：一次成功猎杀后 N tick 内不再猎杀。
## 捕食压力总量上限 = 捕食者数量 × (1/N)，与猎物基数解耦——
## 替代"给猎物繁衍率打补丁"的旧调法（史莱姆系 0.003→0.005 那类）
const PREDATOR_SATIETY_TICKS := 10

## 繁衍变异出精英的概率与体型放大系数（纯逻辑常量，表现层与奖励自动跟随 size_scale）
const ELITE_CHANCE := 0.04
const ELITE_SIZE_MULT := 1.45

## 物种营地（MMO 据点式落点）：怪物属于地图，不属于玩家。每斑块每物种
## 一个确定性营地心（斑块中心 + 固定方向 × 环距，按斑块内物种序错开三档），
## 初始个体在营地 ±CAMP_SPREAD 扎根；繁衍子代在亲代附近出生 → 种群从
## 据点自然外扩。表现层只按「实例位置 vs 玩家距离」流式进出节点，
## 走远再回来怪还在原据点（spawn_pos 随存档持久化）。
## 环距实证调参（2026-09-17，tools/route 探针）：旧值 [0.05,0.16,0.27]（4000/
## 12800/21600px）下直线跑图遇怪率仅 ~1%（向西南 78km 全程零遇怪）——自由
## 跑图永远擦不到营地。压缩到聚簇斑块心 8000px 内 + 散布摊开到 500px，
## 跑图遇怪从"几十公里一遇"回到"每斑块可见"
const CAMP_RINGS := [0.03, 0.06, 0.10]
## 营地内个体散布半径（8~10 只的营地直径 ~1km：紧凑但不至于点簇化，
## 群体接敌的同时覆盖玩家动线）
const CAMP_SPREAD := 500.0
## 繁衍子代出生散布（亲代附近）：每代外扩半径，几代后据点摊成怪区
const BREED_SPREAD := 400.0

## 生态韧性（rescue effect）：玩家猎杀压力可能摧毁核心卖点本身。
## 濒危物种（全球 <ENDANGERED_THRESHOLD 只）繁衍加速且豁免被捕食；
## 灭绝物种罕见重引入（"从世界边缘迁徙回来"），灭绝事件仍戏剧化但可逆——
## 重引入后世界事件会播报"物种复苏"。
## 阈值探针结论（2026-09-03）：6 为最优——8 会让更多物种常态处于救援繁衍，
## ×3 加速抢占出生空位反而加剧区域饱和挤占（每遍 4~6 物种下潜 vs 阈值 6 的 0~4）
var reintroduction_enabled := true
## 捕食开关（测试隔离用；默认开）
var predation_enabled := true
## 玩家灭杀致绝的物种名单（世界线记忆）：最后一只非 Boss 个体被玩家杀死 →
## 永久灭绝，重引入对其失效（"从世界边缘迁徙回来"只属于自然兴衰）。
## 猎杀自此有了不可逆的重量；自然灭绝（衰老/竞争/捕食）仍可恢复——
## 探针实证自然归零偶发不可避免，若一并永久化世界会随时间单调失血
var player_extinct: Dictionary = {}
const ENDANGERED_THRESHOLD := 6
const RESCUE_BREED_MULT := 3.0
const REINTRODUCE_CHANCE := 0.05
const REINTRODUCE_COUNT := 2

var regions: Dictionary = {}
var instances: Dictionary = {}
var species_list: Array[SpeciesData] = []
var next_id: int = 1
var tick_count: int = 0
## 本局区域是否来自 BiomeMap 噪声群系（setup/restore 时检测一次）：
## true 时 region_of_point 走 O(1) 噪声采样（斑块形状犬牙交错，矩形判定失效），
## false 时（测试合成矩形区域）保留旧线性扫描
var _biome_world := false
## Boss 重生倒计时 { species_name: ticks_left }
var boss_respawn_timers: Dictionary = {}
## 捕食者饱食剩余 tick（实例 id → 计数；不随存档持久化——恢复后重新开始进食无碍）
var _satiety: Dictionary = {}

## 按「区域 → 物种名 → 存活实例数组」的查找索引（懒重建缓存）：
## 捕食猎物查找/区域计数/扩张收集体原先都是全实例扫描，捕食侧 O(捕食者×全体)。
## 桶只是加速结构不是状态真源——候选取用前仍现场过滤 is_alive，
## 语义与全量扫描严格一致；任何影响 存活/归属 的变更置脏，下次访问重建
var _index: Dictionary = {}
var _index_dirty := true


func _buckets() -> Dictionary:
	if _index_dirty:
		_index = {}
		for inst: MonsterInstance in instances.values():
			if not inst.is_alive:
				continue
			var by_species: Dictionary = _index.get(inst.region_id, {})
			if by_species.is_empty():
				_index[inst.region_id] = by_species
			var bucket: Array = by_species.get(inst.species.species_name, [])
			if bucket.is_empty():
				by_species[inst.species.species_name] = bucket
			bucket.append(inst)
		_index_dirty = false
	return _index

## 巢穴：{ "region_id|species": {"active": bool, "rebuild": int} }。
## 物种在区域首次立足自动建巢；捣毁 → 该区域该物种繁衍停止 + 全族激怒（表现层），
## rebuild 倒计时归零后重建（物种重新立足）。玩家"管理生态"的主动工具。
var nests: Dictionary = {}
const NEST_REBUILD_TICKS := 120


## p_regions: Array[SimRegion]；p_species_list: Array[SpeciesData]；
## initial: { region_id: { species_name: 初始数量 } }，用随机年龄初始化种群。
## 全量清空旧状态：restore 半途失败回退"新世界"时复用的是同一实例，
## 残留的实例/巢/Boss 计时/灭绝名单会让新世界带着旧世界线开局
func setup(p_regions: Array, p_species_list: Array[SpeciesData], initial: Dictionary) -> void:
	_register_regions(p_regions)
	species_list = p_species_list
	instances.clear()
	nests.clear()
	boss_respawn_timers.clear()
	player_extinct.clear()
	_satiety.clear()
	next_id = 1
	tick_count = 0
	_index_dirty = true
	_invalidate_summary_cache()
	for region_id: String in initial:
		if regions.get(region_id) == null:
			push_warning("初始种群引用了不存在的区域：%s" % region_id)
			continue
		var region: SimRegion = regions.get(region_id)
		for species_name: String in initial[region_id]:
			var species := find_species(species_name)
			if species == null:
				push_warning("初始种群引用了不存在的种族：%s" % species_name)
				continue
			var count: int = initial[region_id][species_name]
			for i in count:
				if species.is_boss:
					# Boss 以成年巨体入场（与重生逻辑一致），盘踞斑块中心
					spawn_instance(species, region_id, species.maturity_age, 0,
							species.boss_size_scale, false, region.center)
				else:
					spawn_instance(species, region_id, randi_range(5, 60),
							0, 1.0, false, _camp_member_pos(region, species))


func find_species(species_name: String) -> SpeciesData:
	for species in species_list:
		if species.species_name == species_name:
			return species
	return null


## 栖息地匹配：空 habitats = 任意地形可生存（SpeciesData 的契约注释）。
## 此前三处判断都写 `not terrain in habitats`，空数组等于匹配不到任何地形——
## 空 habitats 物种永不繁衍、连重引入都被跳过，与契约相反
func habitat_match(species: SpeciesData, region: SimRegion) -> bool:
	return species.habitats.is_empty() or region.terrain in species.habitats


## 物种营地环距档位：按斑块可栖息物种名排序取序（确定性，与种群兴衰无关
## ——营地位置不随在场个体漂移）。每斑块必有档 0：最近营地距斑块中心
## 0.03 格 ≈ 2400px，恰在流式半径（2400px）边缘——玩家走到斑块心附近
## 必见怪，出生点（=出生斑块中心）走数百 px 即达首个据点
func _camp_ring_index(region: SimRegion, species: SpeciesData) -> int:
	var names: Array = []
	for s: SpeciesData in species_list:
		if habitat_match(s, region):
			names.append(s.species_name)
	names.sort()
	var idx := names.find(species.species_name)
	return (idx if idx >= 0 else 0) % CAMP_RINGS.size()


## 斑块内某物种的营地心（确定性：同世界同落点）。表现层巢穴落点共用本
## 算法——巢与种群据点同址，捣巢即端老窝。噪声斑块（Voronoi 犬牙交错）
## 营地心越界时向中心收缩，仍越界用斑块中心；测试合成矩形区域不校验
func camp_pos(region: SimRegion, species: SpeciesData) -> Vector2:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s|%s" % [region.id, species.species_name]) & 0x7FFFFFFF
	var angle := rng.randf() * TAU
	var ring: float = CAMP_RINGS[_camp_ring_index(region, species)]
	var pos := region.center + Vector2(cos(angle), sin(angle)) * ring * region.size.x
	var half := region.size * 0.45
	pos.x = clampf(pos.x, region.center.x - half.x, region.center.x + half.x)
	pos.y = clampf(pos.y, region.center.y - half.y, region.center.y + half.y)
	if _biome_world and BiomeMap.region_id_at(pos) != region.id:
		pos = (pos + region.center) * 0.5
		if BiomeMap.region_id_at(pos) != region.id:
			pos = region.center
	# 世界 v5：营地心避开障碍（整群据点扎进岩缝会让怪全卡障碍里）——向心
	# 折半重试，仍撞用 8 方向 nudge 机械兜底（斑块中心 600px 抑制区保底可达）
	if _biome_world and ObstacleField.blocks(pos, 14.0):
		for i in 4:
			pos = pos.lerp(region.center, 0.5)
			if not ObstacleField.blocks(pos, 14.0) and BiomeMap.region_id_at(pos) == region.id:
				break
		if ObstacleField.blocks(pos, 14.0):
			pos = ObstacleField.nudge_free(pos, 14.0)
	return pos


## 营地成员落点：营地心 ±CAMP_SPREAD，归属校验重试（越界收缩），兜底营地心
func _camp_member_pos(region: SimRegion, species: SpeciesData) -> Vector2:
	var camp := camp_pos(region, species)
	for i in 4:
		var p := camp + Vector2(randf_range(-CAMP_SPREAD, CAMP_SPREAD), randf_range(-CAMP_SPREAD, CAMP_SPREAD))
		if (not _biome_world or BiomeMap.region_id_at(p) == region.id) \
				and not ObstacleField.blocks(p, 10.0):
			return p
	return camp


## 区域内随机挑一只可繁衍成年（繁衍掷骰的亲代；理论必有——adults>0 才进循环，
## 竞争 pass 中途击杀等极端时序下兜底 null，由 _offspring_pos 回退营地）
func _pick_adult_in(region: SimRegion, species: SpeciesData) -> MonsterInstance:
	var bucket: Array = _buckets().get(region.id, {}).get(species.species_name, [])
	var adults: Array[MonsterInstance] = []
	for cand: MonsterInstance in bucket:
		if cand.is_alive and cand.is_adult() and not cand.is_split_sterile():
			adults.append(cand)
	return adults[randi() % adults.size()] if not adults.is_empty() else null


## 子代落点：亲代 ±BREED_SPREAD（归属校验重试）；亲代缺失/老档无位置 → 营地
func _offspring_pos(parent: MonsterInstance, region: SimRegion, species: SpeciesData) -> Vector2:
	if parent == null or parent.spawn_pos == Vector2.INF:
		return _camp_member_pos(region, species)
	for i in 4:
		var p := parent.spawn_pos + Vector2(randf_range(-BREED_SPREAD, BREED_SPREAD), randf_range(-BREED_SPREAD, BREED_SPREAD))
		if (not _biome_world or BiomeMap.region_id_at(p) == region.id) \
				and not ObstacleField.blocks(p, 10.0):
			return p
	return parent.spawn_pos


func spawn_instance(species: SpeciesData, region_id: String, age := 0,
		generation := 0, size_scale := 1.0, p_elite := false,
		p_pos := Vector2.INF) -> MonsterInstance:
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
	inst.spawn_pos = p_pos
	var region: SimRegion = regions.get(region_id)
	inst.threat_scale = region.threat if region else 1.0
	instances[inst.id] = inst
	_index_dirty = true
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
	nest_changed.emit(region_id, species_name, true, false)


## 捣毁巢穴（表现层入口）：该区域该物种繁衍停止 + 全族激怒，rebuild 后重建
func destroy_nest(region_id: String, species_name: String) -> bool:
	var key := "%s|%s" % [region_id, species_name]
	var nest: Dictionary = nests.get(key, {})
	if nest.is_empty() or not nest["active"]:
		return false
	nest["active"] = false
	nest["rebuild"] = NEST_REBUILD_TICKS
	nests[key] = nest
	nest_changed.emit(region_id, species_name, false, true)
	return true


func _process_nests() -> void:
	for key in nests:
		var nest: Dictionary = nests[key]
		if nest["active"]:
			continue
		nest["rebuild"] = int(nest["rebuild"]) - 1
		if int(nest["rebuild"]) <= 0:
			nest["active"] = true
			nest_changed.emit(key.get_slice("|", 0), key.get_slice("|", 1), true, false)
		nests[key] = nest


func get_region(region_id: String) -> SimRegion:
	return regions.get(region_id)


func get_region_center(region_id: String) -> Vector2:
	var region: SimRegion = regions.get(region_id)
	return region.center if region else Vector2.ZERO


## 玩家所在区域：噪声群系世界按 BiomeMap 采样（斑块归属 O(1)，边界犬牙交错
## 无法用矩形判定）；合成区域世界（测试）保留旧的矩形线性扫描
func region_of_point(point: Vector2) -> SimRegion:
	if _biome_world:
		return regions.get(BiomeMap.region_id_at(point))
	for region: SimRegion in regions.values():
		if region.contains_point(point):
			return region
	return null


## 注册区域集并检测来源（BiomeMap 斑块 or 测试合成矩形）——setup/restore 共用
func _register_regions(p_regions: Array) -> void:
	regions.clear()
	_biome_world = false
	for region in p_regions:
		regions[region.id] = region
		if BiomeMap.has_patch(region.id):
			_biome_world = true


func alive_count_in(region_id: String, species: SpeciesData = null) -> int:
	# 走区域索引（懒重建），不再全实例扫描；桶成员取用前现场过滤 is_alive
	var by_species: Dictionary = _buckets().get(region_id, {})
	var count := 0
	if species != null:
		for inst: MonsterInstance in by_species.get(species.species_name, []):
			if inst.is_alive:
				count += 1
		return count
	for bucket: Array in by_species.values():
		for inst: MonsterInstance in bucket:
			if inst.is_alive:
				count += 1
	return count


## 物种全球存活数（玩家灭杀致绝判定用；只在击杀路径调用，频率有界）
func alive_count_of_species(species_name: String) -> int:
	var count := 0
	for inst: MonsterInstance in instances.values():
		if inst.is_alive and inst.species.species_name == species_name:
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


## 表现层血量回写入口（受击/成长同步）：血量是表现态、镜像进实例只为存档往返
## （与 report_killed 同为"表现层向模拟层报告"的单点通道）。
## 只记录不判定——归零死亡仍由表现层触发 report_killed
func report_hp(id: int, hp: float) -> void:
	var inst: MonsterInstance = instances.get(id)
	if inst != null and inst.is_alive:
		inst.hp_mirror = hp


func tick() -> void:
	tick_count += 1
	# 全量扫描合并：整个 tick 只有两遍 O(n)（老化+尸体合一、种群统计一次共享）——
	# 此前是 7 次（老化/尸体/繁衍统计/扩张统计/捕食总数/重引入总数/Boss 逐物种扫描），
	# 后续各 pass 的出生/猎杀就地增减共享计数，读到的新鲜度与"每步重扫"一致
	_process_aging_and_corpses()
	var stats := _count_population()
	_process_breeding(stats)
	_process_expansion(stats)
	_process_predation(stats["global_totals"])
	_process_reintroduction(stats["global_totals"])
	_process_boss_respawn(stats["global_totals"])
	_process_nests()
	tick_completed.emit(_build_summary())


## 老化与尸体消散合一的单遍扫描：存活者涨龄判老死，死者倒计时尸解。
## 老死者在死亡后补扣一次尸解倒计时——与合并前"老化 pass 先死、尸体 pass
## 紧接扣 1"的节奏严格一致（尸体可见时长不变）；两类死亡仍按 老死信号 →
## 尸解信号 的固定先后播报
func _process_aging_and_corpses() -> void:
	var aged_out: Array[MonsterInstance] = []
	var expired: Array[MonsterInstance] = []
	for inst: MonsterInstance in instances.values():
		if inst.is_alive:
			inst.age += 1
			# 老死判定走角色/怪物统一的 LifespanMath（寿命语义单点维护）
			if LifespanMath.is_expired(inst.age, inst.lifespan):
				aged_out.append(inst)
		elif inst.corpse_ticks >= 0:
			inst.corpse_ticks -= 1
			if inst.corpse_ticks <= 0:
				expired.append(inst)
	for inst in aged_out:
		_die(inst, DEATH_AGING)
		if inst.corpse_ticks >= 0:
			inst.corpse_ticks -= 1
			if inst.corpse_ticks <= 0:
				expired.append(inst)
	for inst in expired:
		instances.erase(inst.id)
		corpse_expired.emit(inst)
	_index_dirty = true


## 单次遍历统计各「区域|种族」存活/成年数、区域总数与物种全球存活数，
## 返回 { "cells": { "region|species": {alive, adults} },
##        "region_totals": { region: int }, "global_totals": { species: int } }
## tick 内只统计这一次，繁衍/扩张/捕食等 pass 共享并就地增减
## （出生 +1 / 猎杀 -1 / 迁徙改归属），等价于每步重新全量扫描
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
		# 可繁衍成年数排除分裂子代（不育）——原生代才是种群核心
		if inst.is_adult() and not inst.is_split_sterile():
			cells[key]["adults"] += 1
		region_totals[inst.region_id] = region_totals.get(inst.region_id, 0) + 1
		global_totals[inst.species.species_name] = \
				global_totals.get(inst.species.species_name, 0) + 1
	return {"cells": cells, "region_totals": region_totals, "global_totals": global_totals}


func _process_breeding(stats: Dictionary) -> void:
	var cells: Dictionary = stats["cells"]
	var region_totals: Dictionary = stats["region_totals"]
	var global_totals: Dictionary = stats["global_totals"]
	for region: SimRegion in regions.values():
		var alive_total: int = region_totals.get(region.id, 0)
		if alive_total >= region.capacity:
			continue
		for species in species_list:
			if species.breeding_rate <= 0.0 or not habitat_match(species, region):
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
					# 新生儿有概率变异成精英（种群演化的可见个体差异）；
					# 落点在亲代附近——繁衍即据点外扩，几代后摊成怪区
					var parent := _pick_adult_in(region, species)
					spawn_instance(species, region.id, 0, 0, 1.0,
							randf() < ELITE_CHANCE, _offspring_pos(parent, region, species))
					alive_total += 1
					# 出生就地累加共享统计：后续扩张/捕食/重引入 pass 读到的是
					# "含本 tick 新生儿"的总数（新生儿非成年，不影响本 pass 掷骰数）
					var cell: Dictionary = cells.get(key, {})
					if cell.is_empty():
						cell = {"alive": 0, "adults": 0}
						cells[key] = cell
					cell["alive"] = int(cell["alive"]) + 1
					region_totals[region.id] = alive_total
					global_totals[species.species_name] = global_total + 1
					global_total += 1


func _process_expansion(stats: Dictionary) -> void:
	var cells: Dictionary = stats["cells"]
	var region_totals: Dictionary = stats["region_totals"]
	for species in species_list:
		# 空 habitats = 任意地形（habitat_match 契约），同样参与扩张——
		# 旧写法直接 continue 会让这类物种"任意区域可繁衍却永不迁徙"
		if species.migrate_count <= 0:
			continue
		for region: SimRegion in regions.values():
			if not habitat_match(species, region):
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
				if neighbor == null or not habitat_match(species, neighbor):
					continue
				# 已满载的邻居不是扩张目标（否则选中后移动循环整体落空，
				# 入侵玩法被静默锁死到邻居减员为止——lava 初始即 8/8 满载）
				if region_totals.get(neighbor.id, 0) >= neighbor.capacity:
					continue
				var nkey := "%s|%s" % [neighbor.id, species.species_name]
				var neighbor_alive: int = cells[nkey]["alive"] if cells.has(nkey) else 0
				if neighbor_alive < target_alive:
					target = neighbor
					target_alive = neighbor_alive
			if target == null:
				continue
			# 随机挑存活个体迁移（数量不超过迁入区「全物种」剩余承载）——
			# 候选直接取区域索引桶（桶成员现场过滤 is_alive，语义与全量扫描一致）
			var movable: Array[MonsterInstance] = []
			for cand: MonsterInstance in _buckets().get(region.id, {}).get(species.species_name, []):
				if cand.is_alive:
					movable.append(cand)
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
				# 迁徙 = 换据点：落点重分配到目标斑块的本物种营地
				inst.spawn_pos = _camp_member_pos(target, species)
				# 威胁系数定格出生地：个体强度/奖励不因迁徙突变——
				# 表现层 current_hp 只在出生时快照，中途改 threat_scale 会让
				# 迁入高威胁区的满血怪瞬间显示"已掉血"，数值与视觉互相矛盾
				moved += 1
				instance_migrated.emit(inst, target.id)
			if moved > 0:
				cells[key]["alive"] = alive - moved
				if not cells.has(target_key):
					cells[target_key] = {"alive": 0, "adults": 0}
				cells[target_key]["alive"] += moved
				region_totals[target.id] = target_total + moved
				region_totals[region.id] = region_totals.get(region.id, 0) - moved
				# 归属变更，索引置脏（本 pass 内后续读取沿用旧桶 + 现场过滤，语义不变）
				_index_dirty = true
				# 迁入即立足：新区域同样建巢，捣巢才能遏制入侵物种繁衍
				_ensure_nest(target.id, species.species_name)


## 灭绝物种的罕见重引入：在其栖息地匹配且未满的区域生成成年对。
## 叙事口径"从世界边缘迁徙回来"；表现层经 world_event 的"物种复苏"播报
func _process_reintroduction(global_totals: Dictionary) -> void:
	if not reintroduction_enabled:
		return
	# 物种全球灭绝 → 其巢穴随之荒废（灭绝物种留下的巢是"打了没反应的假巢"，
	# 徒增误导）；重引入重新立足时 _ensure_nest 会再立新巢。
	# ransacked=false：种群消亡是自然结果而非玩家捣毁，不触发全族激怒播报
	for key: Variant in nests.keys():
		var nest_species := String(key).get_slice("|", 1)
		if int(global_totals.get(nest_species, 0)) == 0:
			nests.erase(key)
			nest_changed.emit(String(key).get_slice("|", 0), nest_species, false, false)
	for species in species_list:
		# Boss 有独立的重生倒计时（boss_respawn_ticks），不走灭绝重引入——
		# 否则倒计时未到就被"从世界边缘迁徙回来"刷出复数 Boss，破坏顶点节奏
		if species.is_boss:
			continue
		# 玩家灭杀致绝 = 一条世界线里的永久灭绝，重引入不再兜底
		if player_extinct.has(species.species_name):
			continue
		if int(global_totals.get(species.species_name, 0)) > 0 or randf() >= REINTRODUCE_CHANCE:
			continue
		# 候选区域在匹配集内随机——固定取迭代序第一个会让所有复苏永远落在
		# 同一张图（区域字典按 WorldConfig 常量序，snow 在前 east/lava 几乎
		# 见不到复苏），复苏的地理戏剧性被锁死
		var region_candidates: Array = []
		for region: SimRegion in regions.values():
			if habitat_match(species, region) \
					and region.capacity - alive_count_in(region.id) > 0:
				region_candidates.append(region)
		if region_candidates.is_empty():
			continue
		var picked: SimRegion = region_candidates[randi() % region_candidates.size()]
		for i in mini(REINTRODUCE_COUNT, picked.capacity - alive_count_in(picked.id)):
			spawn_instance(species, picked.id, species.maturity_age + randi_range(0, 10),
					0, 1.0, false, _camp_member_pos(picked, species))
			# 共享统计不变式：任何出生都就地累加（后续 Boss pass 只读 Boss 名，
			# 此行纯为"字典 == 真实全球总数"在 pass 间始终成立）
			global_totals[species.species_name] = \
					int(global_totals.get(species.species_name, 0)) + 1


## 捕食：同区域内，每个成年捕食者每 tick 以 PREDATION_CHANCE 猎杀一只猎物。
## 这是生态级联的引擎——玩家清剿捕食者会让猎物种群爆发。
## 幼体不捕食：刚出生 1 tick 的个体就有 8% 掷骰猎杀成年猎物，
## 与"成年后才获得生态角色"的成长模型矛盾。
## 结构约束（缺一都会把猎物压进灭绝脉冲循环，见 tools/eco_probe.gd）：
## ① 饱食限流——猎杀成功后 PREDATOR_SATIETY_TICKS 内不再猎杀；
## ② 濒危豁免——全球存活 < ENDANGERED_THRESHOLD 的猎物不被捕食
##   （"稀少到难以找到"，与繁衍加速 rescue 组成双向韧性）；
## ③ 猎物在全部同区候选中均匀随机（不按 prey 列表顺序偏食）
func _process_predation(global_totals: Dictionary) -> void:
	if not predation_enabled:
		return
	var buckets := _buckets()  # 整个 pass 用同一份快照：中途击杀靠 is_alive 现场过滤
	for predator: MonsterInstance in instances.values():
		if not predator.is_alive or predator.species.prey.is_empty() or not predator.is_adult():
			continue
		var sat: int = _satiety.get(predator.id, 0)
		if sat > 0:
			_satiety[predator.id] = sat - 1
			continue
		if randf() >= PREDATION_CHANCE:
			continue
		var candidates: Array = []
		for prey_name: String in predator.species.prey:
			if int(global_totals.get(prey_name, 0)) < ENDANGERED_THRESHOLD:
				continue  # 濒危豁免：捕食压力转向其他猎物
			for cand: MonsterInstance in buckets.get(predator.region_id, {}).get(prey_name, []):
				if cand.is_alive and not cand.species.is_boss:
					candidates.append(cand)
		if candidates.is_empty():
			continue  # 没找到可猎目标不消耗饱食（饥饿仍在）
		var victim: MonsterInstance = candidates[randi() % candidates.size()]
		_satiety[predator.id] = PREDATOR_SATIETY_TICKS
		victim.death_pos = Vector2.INF
		_die(victim, DEATH_PREDATED)
		# 猎杀就地减共享总数（重引入/Boss pass 随后读到"本 pass 之后"的总量）。
		# 濒危豁免因此从"开局快照"变为实时：某猎物被吃到 <6 只时，同 pass 内
		# 后续捕食者立即转向其他猎物——豁免语义（"稀少到难以找到"）更准确
		global_totals[victim.species.species_name] = \
				int(global_totals.get(victim.species.species_name, 1)) - 1


## Boss 重生：is_boss 物种全球全灭后，倒计时归零时在其栖息地（承载未满）重生一只。
## 世界永远有值得挑战的顶点
func _process_boss_respawn(global_totals: Dictionary) -> void:
	for species in species_list:
		if not species.is_boss:
			continue
		if int(global_totals.get(species.species_name, 0)) > 0:
			boss_respawn_timers[species.species_name] = species.boss_respawn_ticks
			continue
		var left: int = boss_respawn_timers.get(species.species_name, species.boss_respawn_ticks) - 1
		if left > 0:
			boss_respawn_timers[species.species_name] = left
			continue
		# 倒计时归零：在栖息地承载未满处重生一只；找不到落点保持 0 下 tick 重试——
		# 此前先重置回满倒计时再扫描，满载期实际重生间隔会远超策划值
		boss_respawn_timers[species.species_name] = 0
		for region: SimRegion in regions.values():
			if not habitat_match(species, region) or alive_count_in(region.id) >= region.capacity:
				continue
			spawn_instance(species, region.id, species.maturity_age, 0,
					species.boss_size_scale, false, region.center)
			boss_respawn_timers[species.species_name] = species.boss_respawn_ticks
			break


## 全量序列化（生态存档）：个体逐条枚举 + 巢穴状态 + Boss 重生倒计时 + 计数器。
## 物种按名引用，恢复时 find_species 缺失即警告跳过；纯字典输出，无 Node 依赖，
## 满足"生态模拟整体搬迁服务端"时同一套序列化可直接复用
func to_dict() -> Dictionary:
	var inst_list: Array = []
	for inst: MonsterInstance in instances.values():
		var entry := {
			"id": inst.id,
			"species": inst.species.species_name,
			"region": inst.region_id,
			"age": inst.age,
			"lifespan": inst.lifespan,
			"generation": inst.generation,
			"size": inst.size_scale,
			"elite": inst.is_elite,
			"threat": inst.threat_scale,
			"alive": inst.is_alive,
			"corpse": inst.corpse_ticks,
			"spawn_pos": [inst.spawn_pos.x, inst.spawn_pos.y] if inst.spawn_pos != Vector2.INF else [],
		}
		# 血量镜像：只记"活着的带伤个体"（>0）；未受伤/尸体不占键，
		# 旧档无 hp 键 = 满血恢复（与拆分前的行为兼容）
		if inst.is_alive and inst.hp_mirror > 0.0:
			entry["hp"] = inst.hp_mirror
		inst_list.append(entry)
	return {
		"next_id": next_id,
		"tick": tick_count,
		"instances": inst_list,
		"nests": nests.duplicate(true),
		"boss_timers": boss_respawn_timers.duplicate(true),
		"player_extinct": player_extinct.duplicate(),
	}


## 从存档恢复（替代 setup 撒初始种群）：重建区域/物种注册与完整实例集，
## 并向表现层重放 instance_spawned / nest_changed 信号驱动节点生成。
## 数据结构非法或一个实例都恢复不了时返回 false，调用方回退 INITIAL_POPULATION
func restore_from_dict(p_regions: Array, p_species_list: Array[SpeciesData], data: Dictionary) -> bool:
	var inst_entries: Variant = data.get("instances", null)
	if typeof(inst_entries) != TYPE_ARRAY:
		return false
	_register_regions(p_regions)
	species_list = p_species_list
	_invalidate_summary_cache()
	instances.clear()
	nests.clear()
	boss_respawn_timers.clear()
	player_extinct.clear()
	_satiety.clear()
	_index_dirty = true
	next_id = maxi(1, _safe_int_field(data.get("next_id", 1), 1))
	tick_count = maxi(0, _safe_int_field(data.get("tick", 0), 0))
	for entry: Variant in inst_entries:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = entry
		# 物种名经美术 v5 更名迁移（旧档骷髅兵→甲虫等；已删物种查无即跳过）
		var species := find_species(SpeciesCatalog.migrate_name(str(d.get("species", ""))))
		var region: SimRegion = regions.get(str(d.get("region", "")))
		if species == null or region == null:
			push_warning("存档实例无法恢复（物种或区域缺失）：%s@%s" % [
				str(d.get("species", "?")), str(d.get("region", "?"))])
			continue
		var inst := MonsterInstance.new()
		inst.id = _safe_int_field(d.get("id", 0), 0)
		inst.species = species
		inst.region_id = region.id
		inst.age = maxi(0, _safe_int_field(d.get("age", 0), 0))
		inst.lifespan = maxi(1, _safe_int_field(d.get("lifespan", species.lifespan_min), species.lifespan_min))
		inst.generation = maxi(0, _safe_int_field(d.get("generation", 0), 0))
		inst.size_scale = maxf(0.1, float(d.get("size", 1.0)) if typeof(d.get("size", 1.0)) in [TYPE_FLOAT, TYPE_INT] else 1.0)
		inst.is_elite = _safe_bool(d.get("elite", false), false)
		inst.threat_scale = maxf(0.1, float(d.get("threat", 1.0)) if typeof(d.get("threat", 1.0)) in [TYPE_FLOAT, TYPE_INT] else 1.0)
		# 严格布尔：非 bool 值（手改档的字符串 "false" 等）按活体回落——与缺键
		# 默认 true 同口径（判死会拉低活体数、全死时触发回退 setup 丢整条世界线，
		# 代价远大于多恢复一只怪）；GDScript 里 "false" == true 是运行时错误
		# 而非 false，必须先判类型
		inst.is_alive = _safe_bool(d.get("alive", true), true)
		inst.corpse_ticks = _safe_int_field(d.get("corpse", -1), -1)
		# 血量镜像（v2 存档补键）：>0 才可信，超界交给表现层钳制
		var hp_v: Variant = d.get("hp", null)
		if typeof(hp_v) in [TYPE_FLOAT, TYPE_INT] and float(hp_v) > 0.0:
			inst.hp_mirror = float(hp_v)
		var pos: Variant = d.get("spawn_pos", [])
		if typeof(pos) == TYPE_ARRAY and (pos as Array).size() == 2 \
				and typeof(pos[0]) in [TYPE_FLOAT, TYPE_INT] \
				and typeof(pos[1]) in [TYPE_FLOAT, TYPE_INT]:
			inst.spawn_pos = Vector2(float(pos[0]), float(pos[1]))
		if inst.id <= 0 or instances.has(inst.id):
			inst.id = next_id
		instances[inst.id] = inst
		next_id = maxi(next_id, inst.id + 1)
		instance_spawned.emit(inst)
	# 老档兼容：玩家锚点流式时代的存活实例可能从未落位（spawn_pos=INF）——
	# 按所在斑块营地补据点，维持「存活实例必有位置」不变量（表现层流式
	# 进出与存档往返都依赖它；信号重放时按 INF 判定进了待生成池，此处
	# 补完后下一轮流询即在据点生成）
	for inst: MonsterInstance in instances.values():
		if inst.is_alive and inst.spawn_pos == Vector2.INF:
			var region: SimRegion = regions.get(inst.region_id)
			if region != null:
				inst.spawn_pos = _camp_member_pos(region, inst.species)
	# 巢穴状态（保留捣毁中的 rebuild 倒计时）；active 巢重放信号让表现层建节点。
	# 键级消毒：巢字典缺 active/rebuild 时直接下标访问会在 _process_nests /
	# _process_breeding 处每 tick 报 Invalid access（手改档防御，与实例侧同口径）
	var saved_nests: Variant = data.get("nests", {})
	if typeof(saved_nests) == TYPE_DICTIONARY:
		for key: Variant in saved_nests:
			var nest: Variant = saved_nests[key]
			if typeof(key) == TYPE_STRING and typeof(nest) == TYPE_DICTIONARY:
				var nd: Dictionary = nest
				# 巢键 "区域|物种"：物种段经更名迁移后须仍存在（已删物种的巢一并丢弃）
				var nest_region: String = key.get_slice("|", 0)
				var nest_species: SpeciesData = find_species(SpeciesCatalog.migrate_name(key.get_slice("|", 1)))
				if nest_species == null:
					continue
				var active := _safe_bool(nd.get("active", true), true)
				nests["%s|%s" % [nest_region, nest_species.species_name]] = {
					"active": active,
					"rebuild": maxi(0, _safe_int_field(nd.get("rebuild", 0), 0)),
				}
				if active:
					nest_changed.emit(nest_region, nest_species.species_name, true, false)
	var saved_timers: Variant = data.get("boss_timers", {})
	if typeof(saved_timers) == TYPE_DICTIONARY:
		for key: Variant in saved_timers:
			if typeof(key) == TYPE_STRING:
				var boss_name: String = SpeciesCatalog.migrate_name(key)
				if find_species(boss_name) != null:
					boss_respawn_timers[boss_name] = _safe_int_field(saved_timers[key], 1)
	# 玩家灭杀致绝名单（世界线记忆；旧档无键 = 空名单，行为等同此前）；
	# 物种名同样走更名迁移，已删物种的键不再保留
	var saved_extinct: Variant = data.get("player_extinct", {})
	if typeof(saved_extinct) == TYPE_DICTIONARY:
		for key: Variant in saved_extinct:
			if typeof(key) == TYPE_STRING:
				var extinct_name: String = SpeciesCatalog.migrate_name(key)
				if find_species(extinct_name) != null:
					player_extinct[extinct_name] = true
	# 成败判定看活体而不是字典非空：死实例也占 instances——一个"全死快照"
	# （手改档/异常写坏）按旧口径会恢复"成功"，0 活体世界再写回存档永久固化；
	# 返回 false 让调用方回退 setup 重新撒放（世界自愈，尸体无保存价值）
	for inst: MonsterInstance in instances.values():
		if inst.is_alive:
			return true
	return false


## 反序列化的宽松整型读取（存档可能被手改/三方工具写坏，类型错误回落默认值）
static func _safe_int_field(value: Variant, fallback: int) -> int:
	match typeof(value):
		TYPE_INT:
			return value
		TYPE_FLOAT:
			return int(value)
		TYPE_BOOL:
			return 1 if value else 0
		_:
			return fallback


## 反序列化的严格布尔读取：只有真正的 bool 才可信（字符串/数字一律回落）——
## GDScript 的 "false" == true 是运行时错误而非 false，先判类型再取值
static func _safe_bool(value: Variant, fallback: bool) -> bool:
	return value if typeof(value) == TYPE_BOOL else fallback


func _die(inst: MonsterInstance, cause: String) -> void:
	inst.is_alive = false
	inst.corpse_ticks = inst.species.corpse_duration
	_satiety.erase(inst.id)
	_index_dirty = true
	instance_died.emit(inst, cause)
	# 分裂繁殖：只有被击杀（被打碎）才会裂出子代，自然老死不分裂——
	# 玩家刷怪会助推种群扩张，"越杀越多"的取舍是本作的生态博弈点
	if cause == DEATH_KILLED and inst.can_split():
		_spawn_splits(inst)
	# 玩家灭杀致绝：最后一只非 Boss 个体死因是"被打碎"→ 记入世界线永久灭绝。
	# 必须在分裂子代生成之后再判定——否则杀掉最后一只原生代时计数瞬间为 0，
	# 物种明明裂出了活体却被记入永久灭绝（不育子代自然老死后重引入被永久
	# 封锁，比设计意图更严苛且玩家不可见）；连子代一并杀光才真正灭种
	if cause == DEATH_KILLED and not inst.species.is_boss \
			and alive_count_of_species(inst.species.species_name) == 0:
		player_extinct[inst.species.species_name] = true


func _spawn_splits(parent: MonsterInstance) -> void:
	# 子代归属按死亡位置实际所在区域回退：迁徙个体的 region_id 在出发瞬间已指向
	# 新区、节点却还在慢慢走过去——途中被截杀时若沿用模拟归属，子代会
	# "记在新区、生在旧位置"：新区容量被虚占、生态面板数字与眼前生物对不上
	var region: SimRegion = regions.get(parent.region_id)
	if parent.death_pos != Vector2.INF:
		var pos_region: SimRegion = region_of_point(parent.death_pos)
		if pos_region != null:
			region = pos_region
	if region == null:
		return
	var room: int = region.capacity - alive_count_in(region.id)
	var count := mini(parent.species.split_count, maxi(0, room))
	for i in count:
		# 子代在母体死亡处裂开（未记录位置则回退亲代据点附近）
		var pos := parent.death_pos if parent.death_pos != Vector2.INF \
				else _offspring_pos(parent, region, parent.species)
		var child := spawn_instance(parent.species, region.id, 0,
				parent.generation + 1, parent.size_scale * parent.species.split_size_scale,
				false, pos)


## tick 快照的结构复用缓存：region 桶字典（summary/alive/species）跨 tick 就地覆写——
## 消费方（HUD 生态面板 / WorldEventDetector）均为同步读取且不持有引用
## （detector 对 species dict 做 duplicate，HUD 同样复制基线），复用无副作用。
## setup/restore 改变区域集时置空重建
var _summary_regions: Array = []
## regions 字段直接复用各桶的 summary 子字典数组（消费方读的是 region 级字段）
var _summary_list: Array = []
var _summary_root: Dictionary = {}


func _invalidate_summary_cache() -> void:
	_summary_regions = []
	_summary_list = []
	_summary_root = {}


func _build_summary() -> Dictionary:
	# 单趟遍历累加（原为每区域各扫一遍全体实例，O(区域×个体)）
	if _summary_regions.is_empty():
		for region: SimRegion in regions.values():
			var bucket := {
				"id": region.id,
				"summary": region.to_dict(),
				"alive": 0,
				"species": {},
			}
			_summary_regions.append(bucket)
			_summary_list.append(bucket["summary"])
		_summary_root = {"tick": 0, "regions": _summary_list, "total_alive": 0}
	var by_region := {}
	for bucket: Dictionary in _summary_regions:
		bucket["alive"] = 0
		(bucket["species"] as Dictionary).clear()
		by_region[bucket["id"]] = bucket
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
	for bucket: Dictionary in _summary_regions:
		var summary: Dictionary = bucket["summary"]
		summary["alive"] = bucket["alive"]
		summary["species"] = bucket["species"]
	_summary_root["tick"] = tick_count
	_summary_root["total_alive"] = total_alive
	return _summary_root
