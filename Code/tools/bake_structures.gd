## 建筑/结构烘焙（美术 v6 TS）：assets/ts/Buildings 整图裁内容 bbox →
## 就近邻缩放到目标世界高 → PNG 到 assets/ts/structures_baked/。
## 包内无宝箱/箭矢：chest 以 TS 色板程序合成、arrow 为 Archer 弹道 ÷4 缩图。
## 用法：-s tools/bake_structures.gd（重跑幂等覆盖）
extends SceneTree

const TS := "res://assets/ts/"
const OUT := "res://assets/ts/structures_baked/"

## 目标高（世界像素）：房屋对齐原 NA 烘焙件 ~128 档；城堡放大成地标气势
const STAMPS := {
	"ts_house1": {"src": "Buildings/Blue Buildings/House1.png", "h": 132},
	"ts_house2": {"src": "Buildings/Blue Buildings/House2.png", "h": 120},
	"ts_house3": {"src": "Buildings/Blue Buildings/House3.png", "h": 126},
	"ts_tower": {"src": "Buildings/Blue Buildings/Tower.png", "h": 156},
	"ts_barracks": {"src": "Buildings/Blue Buildings/Barracks.png", "h": 120},
	"ts_castle_black": {"src": "Buildings/Black Buildings/Castle.png", "h": 224},
	"ts_castle_red": {"src": "Buildings/Red Buildings/Castle.png", "h": 224},
}


func _bbox(img: Image) -> Rect2i:
	var min_x := 1 << 30
	var min_y := 1 << 30
	var max_x := -(1 << 30)
	var max_y := -(1 << 30)
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.08:
				min_x = mini(min_x, x)
				max_x = maxi(max_x, x)
				min_y = mini(min_y, y)
				max_y = maxi(max_y, y)
	if max_x < min_x:
		return Rect2i()
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for key: String in STAMPS:
		var cfg: Dictionary = STAMPS[key]
		var img := Image.load_from_file(ProjectSettings.globalize_path(TS + cfg["src"]))
		if img == null:
			push_warning("烘焙源缺失：" + cfg["src"])
			continue
		var b := _bbox(img)
		var crop := img.get_region(b)
		var th: int = cfg["h"]
		var tw := maxi(1, int(round(float(b.size.x) * float(th) / float(b.size.y))))
		crop.resize(tw, th, Image.INTERPOLATE_NEAREST)
		crop.save_png(ProjectSettings.globalize_path(OUT + key + ".png"))
		print("%-16s -> %s%s.png (%dx%d)" % [key, OUT, key, tw, th])
	# 弹道箭（Archer 附带件 ÷4 → 16px）
	var arrow := Image.load_from_file(ProjectSettings.globalize_path(
		TS + "Units/Blue Units/Archer/Arrow.png"))
	if arrow != null:
		arrow.resize(16, 16, Image.INTERPOLATE_NEAREST)
		arrow.save_png(ProjectSettings.globalize_path(OUT + "arrow.png"))
		print("%-16s -> %sarrow.png (16x16)" % ["arrow", OUT])
	_chest()
	quit(0)


## TS 色板宝箱（22×16 逻辑 ×2）：木体 + 深描边 + 盖沿 + 双金带 + 锁扣
func _chest() -> void:
	var w := 22
	var h := 16
	var wood := Color(0.74, 0.52, 0.30)
	var dark := Color(0.33, 0.21, 0.12)
	var band := Color(0.56, 0.37, 0.20)
	var gold := Color(1.0, 0.82, 0.34)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var c := wood
			if x == 0 or x == w - 1 or y == 0 or y == h - 1:
				c = dark
			elif y == 4:
				c = band  # 盖沿分界
			elif x == 5 or x == 6 or x == 15 or x == 16:
				c = gold if y >= 4 else band  # 竖金带（盖以上随盖色）
			if (x == 9 or x == 12) and y >= 5 and y <= 9:
				c = dark  # 锁扣外框
			if x >= 10 and x <= 11 and y >= 6 and y <= 8:
				c = gold  # 锁芯
			img.set_pixel(x, y, c)
	img.resize(w * 2, h * 2, Image.INTERPOLATE_NEAREST)
	img.save_png(ProjectSettings.globalize_path(OUT + "chest.png"))
	print("%-16s -> %schest.png (%dx%d)" % ["chest", OUT, w * 2, h * 2])
