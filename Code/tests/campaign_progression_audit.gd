## 确定性战役成长审计：纯读取现有奖励、升级、强化和Boss公式，不改游戏平衡。
## 单次运行：Godot --headless --path Code -s tests/campaign_progression_audit.gd
extends SceneTree

const Data := preload("res://scripts/main/campaign_quest_data.gd")
const Catalog := preload("res://scripts/main/campaign_catalog.gd")

func _build(stats: CharacterStats, weapon: int, vigor: int) -> CharacterStats:
	var model := CharacterStats.new()
	model.level = stats.level
	model.xp = stats.xp
	model.strength = 5 + model.level - 1
	model.upgrade_weapon = weapon
	model.upgrade_vigor = vigor
	return model

func _cost(level: int) -> int:
	var total := 0
	for i in level: total += EconomyMath.upgrade_cost(i)
	return total

func _row(label: String, stats: CharacterStats, gold: int, weapon: int, vigor: int) -> Dictionary:
	var model := _build(stats,weapon,vigor)
	var row := {"scenario":label,"level":model.level,"unspent_xp":model.xp,"allocated_strength":model.strength,
		"earned_gold":gold,"weapon_upgrade":weapon,"vigor_upgrade":vigor,"upgrade_cost":_cost(weapon)+_cost(vigor),
		"gold_left":gold-_cost(weapon)-_cost(vigor),"hp":model.max_hp(),"attack":model.physical_attack(),
		"attack_interval":model.attack_interval(),"assumptions":"no equipment/passives/random rewards; all earned points allocated to strength"}
	var boss_rows := []
	for age in [200,1400]:
		var boss := MonsterInstance.new()
		boss.species = load("res://data/species/turtle_king.tres")
		boss.age = age
		boss.size_scale = 2.2
		boss.threat_scale = 3.0
		boss_rows.append({"age":age,"boss_hp":boss.max_hp(),"boss_attack":boss.attack_power(),"max_single_hit":boss.attack_power()*1.1,
			"plain_hits_to_kill":CombatBandMath.hits_to_kill(boss,model.physical_attack()),
			"max_hits_survivable_ratio":model.max_hp()/(boss.attack_power()*1.1),"boss_kill_xp":boss.xp_reward()})
	row["boss"] = boss_rows
	return row

func _init() -> void:
	var stats := CharacterStats.new()
	var gold := 39
	var total_xp := 44
	stats.add_xp(44)
	var main := [{"chapter":"lost_outpost_v1","gold":39,"xp":44}]
	for chapter: Dictionary in Catalog.main_chapters():
		if int(chapter["number"]) == 6: break
		var budget := Data.reward_budget_v1(4+int(chapter["number"]),stats.level)
		gold += int(budget["gold"])
		stats.add_xp(int(budget["xp"]))
		total_xp += int(budget["xp"])
		main.append({"chapter":chapter["id"],"gold":budget["gold"],"xp":budget["xp"],"level_after":stats.level})
	var finale := Data.reward_budget_v1(10,stats.level)
	gold += int(float(finale["gold"])*0.15)
	stats.add_xp(int(float(finale["xp"])*0.15))
	print("CAMPAIGN_REWARD_AUDIT ", JSON.stringify({"main_through_chapter5":main,"chapter6_frozen":finale,
		"pre_boss_total_base_xp":total_xp+int(float(finale["xp"])*0.15),"full_main_total_base_xp":total_xp+int(finale["xp"]),"original_lava_expected_level":CombatBandMath.TERRAIN_BANDS.lava.expected}))
	print("CAMPAIGN_BUILD_AUDIT ", JSON.stringify(_row("main_only_pre_boss_unupgraded",stats,gold,0,0)))
	print("CAMPAIGN_BUILD_AUDIT ", JSON.stringify(_row("main_only_pre_boss_affordable_2_2",stats,gold,2,2)))
	for _stage in 34:
		var reward := Data.reward_budget_v1(3,stats.level)
		gold += int(reward["gold"])
		stats.add_xp(int(reward["xp"]))
	print("CAMPAIGN_BUILD_AUDIT ", JSON.stringify(_row("planned_batch3_main_plus_34_finite_side_regional_pre_boss",stats,gold,5,5)))
	var reference := CharacterStats.new()
	reference.level = 10
	reference.strength = 14
	reference.upgrade_weapon = 1
	reference.upgrade_vigor = 1
	reference.passives = {"hp":1,"phys":1}
	print("CAMPAIGN_EXISTING_BOSS_REFERENCE ", JSON.stringify({"level":10,"hp":reference.max_hp(),"attack":reference.physical_attack(),
		"upgrade_cost":100,"assumptions":"existing boss_age_balance_test strength reference: one HP and one physical passive, no equipment"}))
	var combat_finish := CharacterStats.new()
	combat_finish.add_xp(total_xp+int(finale["xp"])+2508)
	var empty_finish := CharacterStats.new()
	empty_finish.add_xp(total_xp+int(finale["xp"]))
	print("CAMPAIGN_COMPLETION_LEVELS ", JSON.stringify({"live_boss_path":{"level":combat_finish.level,"xp":combat_finish.xp,"total_xp":total_xp+int(finale["xp"])+2508},
		"true_empty_path":{"level":empty_finish.level,"xp":empty_finish.xp,"total_xp":total_xp+int(finale["xp"])},
		"note":"Boss kill XP is awarded after the combat gate and cannot finance pre-fight stats"}))
	print("=== CAMPAIGN PROGRESSION AUDIT COMPLETE ===")
	quit()
