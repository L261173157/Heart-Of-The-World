## Tiny Swords 素材规格探针（无头：godot --headless --path Code -s tools/ts_probe.gd）。
## 量：图尺寸 / 帧网格 / 每帧内容 bbox / 水平像素块周期（判断是否整数预放大）。
## 用于 v6 切帧管线校准（防降采样陷阱：先实测再定常数）。
extends SceneTree

const TS := "res://assets/ts/"

## [路径, 帧宽, 帧高]（帧宽高 0 = 整图单帧）
const PROBES: Array = [
	["Units/Blue Units/Warrior/Warrior_Idle.png", 192, 192],
	["Units/Blue Units/Warrior/Warrior_Run.png", 192, 192],
	["Units/Blue Units/Warrior/Warrior_Attack1.png", 192, 192],
	["Units/Blue Units/Archer/Archer_Idle.png", 192, 192],
	["Units/Blue Units/Archer/Archer_Shoot.png", 192, 192],
	["Units/Blue Units/Lancer/Lancer_Idle.png", 64, 320],
	["Units/Blue Units/Lancer/Lancer_Run.png", 64, 320],
	["Units/Blue Units/Lancer/Lancer_Right_Attack.png", 64, 320],
	["Units/Blue Units/Monk/Idle.png", 192, 192],
	["Units/Blue Units/Pawn/Pawn_Idle.png", 192, 192],
	["Units/Blue Units/Pawn/Pawn_Run Gold.png", 192, 192],
	["Terrain/Resources/Meat/Sheep/Sheep_Idle.png", 0, 0],
	["Terrain/Resources/Meat/Sheep/Sheep_Move.png", 0, 0],
	["Terrain/Decorations/Rubber Duck/Rubber duck.png", 0, 0],
	["Terrain/Resources/Wood/Trees/Tree1.png", 0, 0],
	["Terrain/Decorations/Rocks/Rock1.png", 0, 0],
	["Terrain/Tileset/Tilemap_color1.png", 64, 64],
	["Particle FX/Explosion_01.png", 192, 192],
	["Particle FX/Fire_01.png", 64, 64],
	["Particle FX/Dust_01.png", 64, 64],
	["Particle FX/Water Splash.png", 192, 192],
	["Buildings/Blue Buildings/House1.png", 0, 0],
	["Buildings/Blue Buildings/Castle.png", 0, 0],
	["Buildings/Blue Buildings/Tower.png", 0, 0],
]

## NA 对照组（现役 16px 表，取 col3 朝右帧的 bbox 做世界尺寸基准）
const NA_PROBES: Array = [
	["assets/creatures/sheets/na_ninja.png", 16, "col3"],
	["assets/creatures/sheets/na_oni.png", 16, "col3"],
	["assets/creatures/sheets/na_sprout.png", 16, "col3"],
]


func _bbox(img: Image, r: Rect2i) -> Rect2i:
	var min_x := 1 << 30
	var min_y := 1 << 30
	var max_x := -(1 << 30)
	var max_y := -(1 << 30)
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if img.get_pixel(x, y).a > 0.08:
				min_x = mini(min_x, x); max_x = maxi(max_x, x)
				min_y = mini(min_y, y); max_y = maxi(max_y, y)
	if max_x < min_x:
		return Rect2i()
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)


## 水平同色游程的最小公倍重复周期（近似像素块宽度：6=预放大 6 倍）
func _block_period(img: Image) -> int:
	var runs: Dictionary = {}
	for y in range(0, img.get_height(), 7):
		var run := 1
		var prev: Color = img.get_pixel(0, y)
		for x in range(1, img.get_width()):
			var c := img.get_pixel(x, y)
			if c == prev:
				run += 1
			else:
				if run > 1 and prev.a > 0.0:
					runs[run] = runs.get(run, 0) + 1
				run = 1
				prev = c
	var best := 1
	var best_n := 0
	for k: int in runs:
		if k <= 32 and runs[k] > best_n:
			best = k; best_n = runs[k]
	return best


func _init() -> void:
	print("===== Tiny Swords 素材实测 =====")
	for p: Array in PROBES:
		var img := Image.load_from_file(ProjectSettings.globalize_path(TS + p[0]))
		if img == null:
			print("!! 读取失败: ", p[0]); continue
		var fw: int = p[1] if p[1] > 0 else img.get_width()
		var fh: int = p[2] if p[2] > 0 else img.get_height()
		var n := int(img.get_width() / fw)
		var b0 := _bbox(img, Rect2i(0, 0, fw, fh)) if fw <= img.get_width() else Rect2i()
		var tall := ""
		if fh > fw:  # 竖画布（Lancer）：对帧 0 全画布取 bbox
			tall = " 竖画布bbox=%s" % [b0]
			b0 = Rect2i()
		var h_max := 0
		var w_max := 0
		for k in n:
			var b := _bbox(img, Rect2i(k * fw, 0, fw, fh))
			if b.get_area() > 0:
				h_max = maxi(h_max, b.size.y); w_max = maxi(w_max, b.size.x)
		print("%-58s %4dx%-4d 帧=%dx%d 最大内容bbox=%dx%d 块周期=%d%s",
			[p[0], img.get_width(), img.get_height(), n, fh, w_max, h_max,
			_block_period(img), tall])
	print("===== NA 对照（16px 表 col3 内容 bbox） =====")
	for p: Array in NA_PROBES:
		var img := Image.load_from_file(ProjectSettings.globalize_path("res://" + p[0]))
		if img == null:
			print("!! 读取失败: ", p[0]); continue
		var cell: int = p[1]
		var col: int = 3
		var h_max := 0
		var w_max := 0
		for row in 4:
			var b := _bbox(img, Rect2i(col * cell, row * cell, cell, cell))
			if b.get_area() > 0:
				h_max = maxi(h_max, b.size.y); w_max = maxi(w_max, b.size.x)
		print("%-46s 内容bbox=%dx%d", [p[0], w_max, h_max])
	quit(0)
