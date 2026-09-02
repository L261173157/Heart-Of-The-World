## 数值平衡校验（纯公式层，不加载场景）。
## 运行："$GODOT" --headless --path Code -s tests/balance_test.gd
## 校验：每个区域按"预期玩家等级"推算强度带——
##   击杀该区怪物需要 1~8 刀；被单体打死至少要挨 4 刀，群体(3只)至少 2 刀。
## 数值改动只动 SpeciesData/SpeciesCatalog，本测试守住手感区间。
extends SceneTree

## 各区域预期玩家等级（威胁系数的玩家侧映射）
const EXPECTED_LEVEL := {"west": 1, "center": 3, "snow": 5, "swamp": 5, "east": 7, "lava": 10}
const REGION_THREAT := {"west": 1.0, "center": 1.3, "snow": 1.7, "swamp": 1.7, "east": 2.2, "lava": 3.0}
## 各区域按初始种群分布的物种（与 SpeciesCatalog 栖息地一致）
const REGION_SPECIES := {
	"west": ["哥布林"],
	"center": ["哥布林", "史莱姆"],
	"snow": ["野猪", "雪蝎", "冰晶史莱姆"],
	"swamp": ["史莱姆", "雪蝎"],
	"east": ["兵蚁", "野猪"],
	"lava": ["兵蚁", "岩甲龟"],
}
## 群体攻击物种（按 3 只同时在场估算承伤）
const PACK_SPECIES := ["哥布林", "兵蚁"]

var _failures := 0


func _init() -> void:
	randomize()
	var species_list := SpeciesCatalog.build_all()
	var by_name := {}
	for s in species_list:
		by_name[s.species_name] = s
	for region_id in REGION_SPECIES:
		var level: int = EXPECTED_LEVEL[region_id]
		for species_name in REGION_SPECIES[region_id]:
			_check_species(region_id, level, by_name[species_name])
	if _failures == 0:
		print("\n=== 平衡校验全部通过 ===")
		quit(0)
	else:
		print("\n=== %d 项超出手感区间 ===" % _failures)
		quit(1)


func _player_stats(level: int) -> Dictionary:
	# 简化假设：全部点数投力量（输出向）；等级 L 力量 = 5 + (L-1)
	var strength := 5 + (level - 1)
	return {
		"attack": 10.0 + strength * 2.5,
		"max_hp": 100.0 + strength * 12.0,
		"interval": clampf(0.9 - 5 * 0.01, 0.35, 0.9),
	}


func _check_species(region_id: String, level: int, species: SpeciesData) -> void:
	var p := _player_stats(level)
	var threat: float = REGION_THREAT[region_id]
	# 成年中期个体（age≈maturity+90）为基准怪
	var age: int = species.maturity_age + 90
	var inst := MonsterInstance.new()
	inst.species = species
	inst.age = age
	inst.threat_scale = threat
	inst.size_scale = 1.0

	var eff_hp: float = inst.max_hp() / (1.0 - clampf(species.defense_reduction, 0.0, 0.8))
	var hits_to_kill: int = ceili(eff_hp / p["attack"])
	var attackers := 3 if species.species_name in PACK_SPECIES else 1
	var hits_to_die: float = p["max_hp"] / (inst.attack_power() * attackers)

	# 岩甲龟是终区 BOSS 定位：战斗时长 10~24 刀（≈8~18 秒），重击可走位/冲刺闪避
	var is_boss: bool = species.species_name == "岩甲龟"
	var kill_ok: bool = hits_to_kill >= (10 if is_boss else 1) and hits_to_kill <= (24 if is_boss else 8)
	var die_ok: bool
	if is_boss:
		die_ok = hits_to_die >= 3.0
	else:
		die_ok = (hits_to_die >= 4.0 and attackers == 1) or (hits_to_die >= 2.0 and attackers == 3)
	var tag := "%s/%s(L%d)%s" % [region_id, species.species_name, level,
			"×3" if attackers == 3 else ""]
	if kill_ok and die_ok:
		print("  PASS  %-18s 击杀 %2d 刀，被击 %.1f 刀死亡" % [tag, hits_to_kill, hits_to_die])
	else:
		_failures += 1
		var why := ""
		if not kill_ok:
			why += "击杀刀数 %d 超出 [1,8]" % hits_to_kill
		if not die_ok:
			why += ("；" if why != "" else "") + "被击 %.1f 刀过低" % hits_to_die
		print("  FAIL  %-18s %s" % [tag, why])
