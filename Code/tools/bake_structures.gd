## 建筑/结构素材烘焙（美术 v5 M-B）：从 na_tileset 抠已验证矩形 → 放大 2 倍
## 存 PNG 到 assets/na/structures/。营地（房屋/鸟居/招牌）与地牢（墙/垛/塔）
## 表现层按世界 32px 障碍格消费（16px 原件 ×2 = 32px/格）。
## 坐标经对照板视觉验收（tools/extract_tile_region.gd 产物）+ 实机截图终验。
## 用法：-s tools/bake_structures.gd（重跑幂等覆盖）
extends SceneTree

## 抠取矩形（na_tileset 原生 16px 网格坐标，Rect2i(x, y, w, h)）
const STAMPS := {
	# 营地房屋三变体（行 0-2 完整房：屋顶+墙+门）
	"house_red": Rect2i(0, 0, 80, 64),
	"house_brown": Rect2i(96, 0, 80, 64),
	"house_grey": Rect2i(192, 0, 80, 64),
	# 鸟居（行 2-4 右区）
	"torii": Rect2i(352, 32, 96, 64),
	# 木招牌（DOJO 牌，行 3-4）
	"sign_dojo": Rect2i(288, 48, 64, 64),
	# 城堡石墙（行 4-7 左区，带城垛）
	"castle_wall": Rect2i(0, 80, 96, 64),
	# 城塔（行 3-6 右区）
	"castle_tower": Rect2i(288, 48, 160, 64),
	# 地牢灰砖（行 9-11 左区，墙+地面）
	"dungeon_brick": Rect2i(0, 144, 96, 48),
	# 宝箱探针（行 11 左起，32×32 双格）
	"chest": Rect2i(0, 176, 32, 32),
}
const OUT_DIR := "res://assets/na/structures/"


func _init() -> void:
	var src := Image.load_from_file(ProjectSettings.globalize_path(
		"res://assets/creatures/sheets/na_tileset.png"))
	var dir := DirAccess.open("res://assets/na")
	dir.make_dir_recursive("structures")
	for key: String in STAMPS:
		var crop := src.get_region(STAMPS[key])
		# ×2 直达 32px 障碍格尺寸（就近邻保像素锐度）
		crop.resize(crop.get_width() * 2, crop.get_height() * 2,
			Image.INTERPOLATE_NEAREST)
		var path := OUT_DIR + key + ".png"
		crop.save_png(ProjectSettings.globalize_path(path))
		print("%-14s -> %s (%dx%d)" % [key, path, crop.get_width(), crop.get_height()])
	quit(0)
