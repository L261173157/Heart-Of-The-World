## 物种目录（纯数据工厂，RefCounted 静态方法）。
## v0 六种族内建配置；M1 改为 .tres 资源文件数据驱动。
## 每个种族在「战斗机制 × 生态策略」两个维度差异化：
##   哥布林：群体围攻（一呼百应）    r 策略繁殖，中等扩张 —— 新手区主力
##   史莱姆：接触伤害，被击杀分裂    繁殖全靠分裂（越杀越多）—— 刷怪博弈
##   野猪：蓄力冲锋 + 残血狂暴不逃  繁殖慢寿命长 —— 雪原/丘陵硬茬
##   雪蝎：远程吐息风筝走位          繁殖中等 —— 教玩家走位
##   兵蚁：协同近战（蚁群增伤）      快繁快死 + 低阈值强扩张 —— 入侵性物种
##   岩甲龟：重击守卫（前摇大伤害高）独居不迁徙 + 极慢繁殖 —— 深区首领
class_name SpeciesCatalog
extends RefCounted


static func build_all() -> Array[SpeciesData]:
	var list: Array[SpeciesData] = []
	list.append(_goblin())
	list.append(_slime())
	list.append(_boar())
	list.append(_spider())
	list.append(_ant())
	list.append(_guardian())
	list.append(_ant_queen())
	list.append(_turtle_king())
	return list


static func _goblin() -> SpeciesData:
	var s := SpeciesData.new()
	s.species_name = "哥布林"
	s.tint = Color(0.35, 0.7, 0.25)
	s.ai_archetype = "melee_swarm"
	s.habitats = ["plains", "forest"]
	s.base_strength = 2.0
	s.base_agility = 4.0
	s.strength_growth = 0.05
	s.agility_growth = 0.02
	s.lifespan_min = 240
	s.lifespan_max = 480
	s.maturity_age = 30
	s.breeding_rate = 0.02
	s.expansion_threshold = 8
	s.migrate_count = 2
	s.xp_base = 10
	s.xp_per_age = 0.1
	s.detect_radius = 170.0
	s.attack_range = 32.0
	s.attack_cooldown = 1.2
	s.flee_hp_ratio = 0.25
	s.poise = 0.05
	return s


static func _slime() -> SpeciesData:
	var s := SpeciesData.new()
	s.species_name = "史莱姆"
	s.tint = Color(0.62, 0.4, 0.85)
	s.ai_archetype = "splitter"
	s.habitats = ["forest", "swamp"]
	s.base_strength = 4.0
	s.base_agility = 2.0
	s.strength_growth = 0.02
	s.lifespan_min = 300
	s.lifespan_max = 600
	s.maturity_age = 60
	# 自然繁殖几乎停滞（仅保底防灭绝），种群增长主要靠"被击杀分裂"
	s.breeding_rate = 0.003
	s.expansion_threshold = 8
	s.migrate_count = 2
	s.corpse_duration = 20
	s.xp_base = 9
	s.xp_per_age = 0.06
	s.detect_radius = 110.0
	s.attack_range = 26.0
	s.attack_cooldown = 1.0
	s.flee_hp_ratio = 0.0
	s.defense_reduction = 0.15
	s.knockback_resist = 0.2
	s.poise = 0.1
	s.splits_on_death = true
	s.split_count = 2
	s.split_size_scale = 0.6
	s.max_generation = 1
	return s


static func _boar() -> SpeciesData:
	var s := SpeciesData.new()
	s.species_name = "野猪"
	s.tint = Color(0.72, 0.45, 0.2)
	s.ai_archetype = "charger"
	s.habitats = ["snow", "hill"]
	s.base_strength = 6.0
	s.base_agility = 6.0
	s.strength_growth = 0.08
	s.lifespan_min = 400
	s.lifespan_max = 700
	s.maturity_age = 60
	s.breeding_rate = 0.008
	s.expansion_threshold = 6
	s.migrate_count = 1
	s.xp_base = 16
	s.xp_per_age = 0.15
	s.detect_radius = 220.0
	s.attack_range = 40.0
	s.attack_cooldown = 2.0
	s.flee_hp_ratio = 0.0  # 永不逃跑：残血转狂暴
	s.knockback_resist = 0.5
	s.poise = 0.5
	s.element = "ice"
	s.prey = ["史莱姆"]  # 杂食：拱食史莱姆
	return s


static func _spider() -> SpeciesData:
	var s := SpeciesData.new()
	s.species_name = "雪蝎"
	s.tint = Color(0.75, 0.85, 0.95)
	s.ai_archetype = "ranged"
	s.habitats = ["snow", "swamp"]
	s.base_strength = 3.0
	s.base_agility = 5.0
	s.base_intellect = 3.0
	s.intellect_growth = 0.03
	s.lifespan_min = 260
	s.lifespan_max = 520
	s.maturity_age = 45
	s.breeding_rate = 0.012
	s.expansion_threshold = 7
	s.migrate_count = 2
	s.xp_base = 12
	s.xp_per_age = 0.1
	s.detect_radius = 260.0
	s.attack_range = 230.0
	s.attack_cooldown = 2.2
	s.flee_hp_ratio = 0.4
	s.defense_reduction = 0.0
	s.poise = 0.1
	s.element = "ice"
	s.prey = ["史莱姆"]  # 雪蝎以史莱姆为主食
	return s


static func _ant() -> SpeciesData:
	var s := SpeciesData.new()
	s.species_name = "兵蚁"
	s.tint = Color(0.78, 0.22, 0.18)
	s.ai_archetype = "soldier"
	s.habitats = ["hill", "lava"]
	s.base_strength = 3.5
	s.base_agility = 7.0
	s.strength_growth = 0.06
	s.lifespan_min = 200
	s.lifespan_max = 400
	s.maturity_age = 25
	# r 策略极端：快繁、快死、低阈值强扩张，会持续入侵毗邻栖息地
	s.breeding_rate = 0.03
	s.expansion_threshold = 6
	s.migrate_count = 3
	s.corpse_duration = 20
	s.xp_base = 11
	s.xp_per_age = 0.08
	s.detect_radius = 180.0
	s.attack_range = 30.0
	s.attack_cooldown = 0.6
	s.flee_hp_ratio = 0.15
	s.defense_reduction = 0.25
	s.poise = 0.15
	s.element = "fire"
	s.prey = ["哥布林", "史莱姆"]  # 蚁群掠食：压制两类基础种
	return s


static func _guardian() -> SpeciesData:
	var s := SpeciesData.new()
	s.species_name = "岩甲龟"
	s.tint = Color(0.5, 0.5, 0.55)
	s.ai_archetype = "guardian"
	s.habitats = ["lava"]
	s.base_strength = 10.0
	s.base_agility = 1.5
	s.strength_growth = 0.1
	s.lifespan_min = 800
	s.lifespan_max = 1200
	s.maturity_age = 120
	# K 策略极端：独居、极慢繁殖、永不迁徙，是熔岩洞窟的定海神针
	s.breeding_rate = 0.002
	s.expansion_threshold = 4
	s.migrate_count = 0
	s.corpse_duration = 60
	s.xp_base = 45
	s.xp_per_age = 0.2
	s.detect_radius = 260.0
	s.attack_range = 60.0
	s.attack_cooldown = 2.4
	s.flee_hp_ratio = 0.0
	s.defense_reduction = 0.4
	s.knockback_resist = 0.85
	s.poise = 1.0  # 完全霸体
	s.element = "fire"
	s.prey = ["兵蚁"]  # 压制兵蚁种群
	return s


## 蚁后：东部丘陵的生态位 Boss——兵蚁之母，击杀后兵蚁失去统御暂时溃散（繁衍骤降）
static func _ant_queen() -> SpeciesData:
	var s := SpeciesData.new()
	s.species_name = "蚁后"
	s.tint = Color(0.95, 0.35, 0.15)
	s.ai_archetype = "soldier"
	s.habitats = ["hill"]
	s.is_boss = true
	s.boss_respawn_ticks = 360
	s.base_strength = 10.0
	s.base_agility = 3.0
	s.strength_growth = 0.05
	s.lifespan_min = 2000
	s.lifespan_max = 3000
	s.maturity_age = 200
	s.breeding_rate = 0.0
	s.expansion_threshold = 99
	s.migrate_count = 0
	s.corpse_duration = 90
	s.xp_base = 260
	s.xp_per_age = 0.0
	s.detect_radius = 300.0
	s.attack_range = 46.0
	s.attack_cooldown = 1.6
	s.flee_hp_ratio = 0.0
	s.defense_reduction = 0.3
	s.knockback_resist = 0.9
	s.poise = 0.9
	s.element = "fire"
	s.prey = ["哥布林", "史莱姆"]
	return s


## 龟王：熔岩洞窟的生态位 Boss——洞窟真正的主人
static func _turtle_king() -> SpeciesData:
	var s := SpeciesData.new()
	s.species_name = "龟王"
	s.tint = Color(0.75, 0.55, 0.25)
	s.ai_archetype = "guardian"
	s.habitats = ["lava"]
	s.is_boss = true
	s.boss_respawn_ticks = 480
	s.base_strength = 12.0
	s.base_agility = 1.0
	s.strength_growth = 0.05
	s.lifespan_min = 2400
	s.lifespan_max = 3600
	s.maturity_age = 200
	s.breeding_rate = 0.0
	s.expansion_threshold = 99
	s.migrate_count = 0
	s.corpse_duration = 120
	s.xp_base = 380
	s.xp_per_age = 0.0
	s.detect_radius = 320.0
	s.attack_range = 70.0
	s.attack_cooldown = 2.6
	s.flee_hp_ratio = 0.0
	s.defense_reduction = 0.5
	s.knockback_resist = 0.95
	s.poise = 1.0
	s.element = "fire"
	s.prey = ["兵蚁", "岩甲龟"]
	return s
