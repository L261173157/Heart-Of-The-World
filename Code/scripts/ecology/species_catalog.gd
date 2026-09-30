## 物种目录（数据驱动加载器，RefCounted 静态方法）。
## 种族配置的唯一数据源是 data/species/*.tres（由 tools/export_species.gd
## 从旧代码配置一次性迁移而来；数值调整直接改 .tres，不再回到代码）。
## 新增种族三步：① 复制任一 .tres 改参数（species_name/战斗/生态/栖息地）
##   ② game_world.MONSTER_SCENES 登记表现场景（按 ai_archetype 选行为脚本）
##   ③ WorldConfig.INITIAL_POPULATION 撒初始种群 + balance_test 区域物种表
## 每个种族在「战斗机制 × 生态策略」两个维度差异化，速查见各 .tres 注释与 AGENTS.md。
class_name SpeciesCatalog
extends RefCounted

const SPECIES_DIR := "res://data/species"

## 物种更名表：旧档按此把历史物种名迁到现行名录（单跳，链条须一指到底）。
## 2026-09-30 Enemy Pack 定稿更名（美术 v6.1）：v5 NA 名 → EP 直译名全量迁移，
## v5 时代的历史名（骷髅兵/獾王等）同步 re-point 到新终点。同形变体
## （青史莱姆/小魔鬼）并入同表现役物种；已删物种（雪怪）不在表内，
## 其旧实例在恢复时自然跳过。图鉴计数/生态快照（实例·巢穴·Boss 计时·
## 灭杀名单）/任务物种字段共用本表——存读档迁移的单一真源。
const SPECIES_RENAME_MAP := {
	# 美术 v6.1（Enemy Pack 直译，2026-09-30）
	"妖鬼": "火把哥布林",
	"萌芽怪": "地精矿工",
	"野猪": "突袭蛇",
	"绿龟": "青甲龟",
	"鸡": "山猪",
	"红史莱姆": "赤炎小魔",
	"绿蛙": "蜥蜴刀客",
	"曼德拉草": "弹弓地精",
	"蘑菇怪": "巫毒萨满",
	"浣熊": "山羊",
	"树人": "巨魔王",
	"企鹅": "雪原窃贼",
	"幽灵": "白骨兵",
	"冰史莱姆": "冰霜小魔",
	"雪熊": "雪原巨熊",
	"蝙蝠": "巨蝠",
	"沼泽蟹": "沼泽蛛",
	"红章鱼": "炸弹鱼",
	"眼魔": "鱼叉鲨",
	"鹦鹉": "野鸭",
	"甲虫": "长矛哥布林",
	"松鼠": "山蜂",
	"仙人掌怪": "投骨豺狼人",
	"独眼巨人": "山岳熊猫",
	"锹形虫王": "牛头王",
	"火鸟": "火蜂",
	"石像鬼": "黑曜牛卫",
	"火龙": "熔岩萨满",
	"龟王": "熔岩龟王",
	# 美术 v5 历史名（终点随 v6.1 再指向，保持单跳可达）
	"骷髅兵": "长矛哥布林",
	"獾王": "牛头王",
	"窟魔王": "熔岩龟王",
	"古木魔像": "巨魔王",
	"石魔像": "黑曜牛卫",
	"火魔鸦": "火蜂",
	"冰晶史莱姆": "冰霜小魔",
	"青史莱姆": "冰霜小魔",
	"小魔鬼": "火把哥布林",
	"野兔": "山蜂",
	"石仔怪": "投骨豺狼人",
}


## 旧物种名 → 现行名录（未收录的名字原样返回）
static func migrate_name(old_name: String) -> String:
	return SPECIES_RENAME_MAP.get(old_name, old_name)


static func build_all() -> Array[SpeciesData]:
	var list: Array[SpeciesData] = []
	var dir := DirAccess.open(SPECIES_DIR)
	if dir == null:
		push_error("种族数据目录不存在：%s（运行 tools/export_species.gd 重新导出）" % SPECIES_DIR)
		return list
	var files: Array[String] = []
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		# 导出包（iOS PCK 等）内所有资源统一带 .remap 指针文件（桌面文件系统无）：
		# DirAccess 列举拿到的是 "ant.tres.remap"，只有 load() 会透明解析 remap，
		# 目录列举不会。此前真机上列出 0 个 ".tres" → 种族目录空 → 初始撒放/
		# 繁衍/重引入全空转（全世界无怪且永不自愈），桌面却完全复现不了
		var base_name := file_name.trim_suffix(".remap")
		if base_name.ends_with(".tres"):
			files.append(base_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	files.sort()  # 文件名排序保证加载顺序稳定可复现
	for file in files:
		var res: Resource = load("%s/%s" % [SPECIES_DIR, file])
		var species := res as SpeciesData
		if species == null or species.species_name.is_empty():
			push_warning("种族资源无效，已跳过：%s" % file)
			continue
		list.append(species)
	if list.is_empty():
		push_error("种族数据目录为空：%s" % SPECIES_DIR)
	return list


## 数据合法性校验（防 .tres 手误造成"静默死区"——数据错误时生态只是悄悄不动）。
## 数值关系 + prey 引用存在性 + 捕食可达性（habitats 共享地形，否则捕食边永不触发）；
## 传入 regions（Array[SimRegion]）时追加校验：habitats 拼写、扩张窗口 vs 区域容量。
## 校验只告警不阻断——配置错误应显性可见，但不应让整个世界起不来
static func validate(list: Array[SpeciesData], regions: Array = []) -> void:
	var names := {}
	for species in list:
		names[species.species_name] = species
	for species in list:
		var n: String = species.species_name
		if species.lifespan_min > species.lifespan_max:
			push_warning("种族 %s：lifespan_min %d > lifespan_max %d" % [
				n, species.lifespan_min, species.lifespan_max])
		if species.maturity_age >= species.lifespan_min:
			push_warning("种族 %s：maturity_age %d ≥ lifespan_min %d（幼体未成熟即老死，出生即灭绝）" % [
				n, species.maturity_age, species.lifespan_min])
		for prey_name: String in species.prey:
			var prey: SpeciesData = names.get(prey_name)
			if prey == null:
				push_warning("种族 %s：prey 引用了不存在的物种「%s」" % [n, prey_name])
				continue
			if prey.is_boss:
				push_warning("种族 %s：prey「%s」是 Boss（Boss 个体永不被捕食，此边无效）" % [n, prey_name])
			var shared := false
			for habitat: String in species.habitats:
				if habitat in prey.habitats:
					shared = true
					break
			if not shared and not species.habitats.is_empty() and not prey.habitats.is_empty():
				push_warning("种族 %s 捕食 %s：双方 habitats 无共享地形（[%s] vs [%s]），这条捕食关系永远不会触发" % [
					n, prey_name, "、".join(species.habitats), "、".join(prey.habitats)])
		if species.is_boss and species.habitats.is_empty():
			push_warning("种族 %s：Boss 的 habitats 为空 = 任意地形，重生可能落在任意区域" % n)
		if regions.is_empty():
			continue
		var terrains := {}
		for region: SimRegion in regions:
			terrains[region.terrain] = region.id
		var any_valid := false
		for habitat: String in species.habitats:
			if not terrains.has(habitat):
				push_warning("种族 %s：habitats 含不存在的地形「%s」（世界现有：%s）——该地形永不匹配" % [
					n, habitat, "、".join(PackedStringArray(terrains.keys()))])
			else:
				any_valid = true
		if not species.habitats.is_empty() and not any_valid:
			push_warning("种族 %s：habitats 全部无效，该物种在当前世界永不繁衍/迁徙" % n)
		if species.migrate_count > 0:
			for region: SimRegion in regions:
				if region.terrain in species.habitats \
						and species.expansion_threshold >= region.capacity - 1:
					push_warning("种族 %s 在 %s：expansion_threshold %d ≥ 容量-1（%d），迁徙窗口窄到接近关闭" % [
						n, region.id, species.expansion_threshold, region.capacity])
