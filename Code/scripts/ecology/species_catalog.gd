## 物种目录（数据驱动加载器，RefCounted 静态方法）。
## 种族配置的唯一数据源是 data/species/*.tres（由 tools/export_species.gd
## 从旧代码配置一次性迁移而来；数值调整直接改 .tres，不再回到代码）。
## 新增种族三步：① 复制任一 .tres 改参数（species_name/战斗/生态/栖息地）
##   ② game_world.MONSTER_SCENES 登记表现场景（按 ai_archetype 选行为脚本）
##   ③ game_world.INITIAL_POPULATION 撒初始种群 + balance_test 区域物种表
## 每个种族在「战斗机制 × 生态策略」两个维度差异化，速查见各 .tres 注释与 AGENTS.md。
class_name SpeciesCatalog
extends RefCounted

const SPECIES_DIR := "res://data/species"


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
		if file_name.ends_with(".tres"):
			files.append(file_name)
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
