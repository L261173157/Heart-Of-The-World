## 种族配置导出工具（一次性迁移 + 日后再导出校验用）。
## 把 SpeciesCatalog.build_all() 的全部种族保存为 data/species/*.tres——
## 此后种族配置以 .tres 为唯一数据源（SpeciesCatalog 只负责加载）。
## 新种族直接复制任一 .tres 修改即可，无需回到代码。
## 运行："$GODOT" --headless --path Code -s tools/export_species.gd
extends SceneTree

const OUT_DIR := "res://data/species"

## 物种名 → 文件名（按拼音；加载顺序按文件名排序，与导出顺序无关）
const FILE_KEYS := {
	"哥布林": "goblin",
	"史莱姆": "slime",
	"野猪": "boar",
	"雪蝎": "spider",
	"兵蚁": "ant",
	"岩甲龟": "guardian",
	"蚁后": "ant_queen",
	"龟王": "turtle_king",
	"冰晶史莱姆": "ice_slime",
}


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var count := 0
	for species: SpeciesData in SpeciesCatalog.build_all():
		var key: String = FILE_KEYS.get(species.species_name, "")
		if key == "":
			push_error("未登记文件名，跳过：%s" % species.species_name)
			continue
		var path := "%s/%s.tres" % [OUT_DIR, key]
		var err := ResourceSaver.save(species, path)
		if err != OK:
			push_error("保存失败 %s：%s" % [path, err])
		else:
			count += 1
			print("已导出 %s → %s" % [species.species_name, path])
	print("共导出 %d 个种族配置" % count)
	quit(0 if count == FILE_KEYS.size() else 1)
