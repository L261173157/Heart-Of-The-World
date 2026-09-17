## App 图标生成（确定性，无外部依赖）
## 概念「心之世界」：像素心形内嵌六群系地层（雪原→中央林地→沼泽→东部丘陵→熔岩核心），
## 深色星空背景 + 左上高光。1024×1024、无透明通道（App Store 营销图强制不透明）。
## 尺寸派生：Godot 4.7 iOS 导出走单一图标模式（export_presets 的 icons/icon_1024x1024），
## 各档位（40/58/…/180/1024 及 iOS18 dark/tinted）自动缩放，无需逐个配图。
## 用法：godot --headless --path Code -s tools/generate_icon.gd
## 改完参数重跑本文件即可，输出覆盖 assets/icon/appicon_1024.png（随仓库提交）。
extends SceneTree

const OUT := "res://assets/icon/appicon_1024.png"
const GRID := 64          # 逻辑像素网格，×16 最近邻放大到 1024（像素画颗粒感）
const OUT_SIZE := 1024

# 心形隐式曲线参数：f(u,v)=(u²+v²−1)³−u²v³≤0 为内部；S 控制整体大小，CX/CY 为网格中心
const CX := 32.0
const CY := 30.0
const S := 21.0

const OUTLINE := Color8(43, 23, 51)      # 深紫描边
const BG_TOP := Color8(26, 26, 51)       # 夜空顶
const BG_BOTTOM := Color8(16, 14, 28)    # 夜空底
const STAR_DIM := Color8(143, 143, 208)
const STAR_BRIGHT := Color8(197, 197, 239)
const HIGHLIGHT := Color8(255, 255, 255)

# 六群系意象色板：行分带（自心顶向下），base=基色 / speck=点缀像素 / dens=点缀密度
# 对应世界六区域：snow → center(林地) → swamp → east(丘陵) → lava（占底部核心，最深最厚）
const LAYERS := [
	{"y1": 14, "base": Color8(184, 212, 232), "speck": Color8(234, 246, 252), "dens": 0.10},  # 雪原
	{"y1": 22, "base": Color8(78, 154, 72), "speck": Color8(106, 184, 92), "dens": 0.12},     # 中央林地
	{"y1": 30, "base": Color8(62, 143, 116), "speck": Color8(88, 171, 136), "dens": 0.12},    # 沼泽
	{"y1": 37, "base": Color8(176, 138, 70), "speck": Color8(204, 164, 86), "dens": 0.10},    # 东部丘陵
	{"y1": 99, "base": Color8(197, 64, 30), "speck": Color8(239, 122, 42), "dens": 0.16},     # 熔岩
]
const LAVA_DEEP := Color8(142, 36, 20)   # 熔岩层向下渐深的底色


func _init() -> void:
	var img := Image.create_empty(GRID, GRID, false, Image.FORMAT_RGB8)
	for y in GRID:
		for x in GRID:
			img.set_pixel(x, y, _background(x, y))
	for y in GRID:
		for x in GRID:
			if not _inside(x, y):
				continue
			if _is_edge(x, y):
				img.set_pixel(x, y, OUTLINE)
			else:
				img.set_pixel(x, y, _jitter(_layer_color(x, y), x, y))
	# 左心房像素高光：3×2 主块 + 1 像素拖尾（经典像素画反光）
	for hy in [13, 14]:
		for hx in [16, 17, 18]:
			if _inside(hx, hy):
				img.set_pixel(hx, hy, HIGHLIGHT)
	if _inside(19, 13):
		img.set_pixel(19, 13, HIGHLIGHT)

	img.resize(OUT_SIZE, OUT_SIZE, Image.INTERPOLATE_NEAREST)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/icon"))
	var path := ProjectSettings.globalize_path(OUT)
	var err := img.save_png(path)
	print("生成 %s（%dx%d，格式 %s）%s" % [path, OUT_SIZE, OUT_SIZE, Image.FORMAT_RGB8,
		"OK" if err == OK else "失败:%d" % err])
	quit(0 if err == OK else 1)


func _background(x: int, y: int) -> Color:
	# 星点只在心形外可见（心形稍后覆盖），两档亮度、密度稀疏
	if _hash2(x, y, 777) < 0.010:
		return STAR_BRIGHT if _hash2(x, y, 779) < 0.35 else STAR_DIM
	var t := float(y) / float(GRID - 1)
	return BG_TOP.lerp(BG_BOTTOM, t)


func _heart_f(ix: int, iy: int) -> float:
	# 像素中心采样（+0.5 对齐格子中心），v 轴向上
	var u := (float(ix) + 0.5 - CX) / S
	var v := (CY - float(iy) - 0.5) / S
	var a := u * u + v * v - 1.0
	return a * a * a - u * u * v * v * v


func _inside(x: int, y: int) -> bool:
	return _heart_f(x, y) <= 0.0


func _is_edge(x: int, y: int) -> bool:
	return not _inside(x - 1, y) or not _inside(x + 1, y) \
		or not _inside(x, y - 1) or not _inside(x, y + 1)


func _layer_color(x: int, y: int) -> Color:
	var col: Color = LAYERS.back()["base"]
	for i in LAYERS.size():
		if y <= int(LAYERS[i]["y1"]):
			col = LAYERS[i]["base"]
			if _hash2(x, y, 500 + i) < float(LAYERS[i]["dens"]):
				return LAYERS[i]["speck"]
			break
	# 熔岩层自 50 行起向底尖渐深，营造"核心"纵深
	if y > 37:
		col = col.lerp(LAVA_DEEP, clampf((float(y) - 50.0) / 8.0, 0.0, 0.8))
	return col


func _jitter(c: Color, x: int, y: int) -> Color:
	# 每像素明度 ±4% 微扰，压平"纯色块"的塑料感
	var j := 1.0 + (_hash2(x, y, 42) - 0.5) * 0.08
	return Color(clampf(c.r * j, 0.0, 1.0), clampf(c.g * j, 0.0, 1.0), clampf(c.b * j, 0.0, 1.0))


## 整数坐标散列 → [0,1)，与 generate_terrain.gd 同款（确定性，换机重跑结果一致）
func _hash2(x: int, y: int, s: int) -> float:
	var h: int = x * 374761393 + y * 668265263 + s * 2246822519
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0x7FFFFFFF) / 2147483647.0
