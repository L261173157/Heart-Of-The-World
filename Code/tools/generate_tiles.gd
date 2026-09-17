## 程序化卡通瓦片图集生成器（自建美术 M3 环境层）
## 产出 assets/creatures/sheets/cartoon_tileset.png（448×640，与 na_tileset 同网格布局），
## 三类消费方的精确坐标全兼容（零代码改动即可换源）：
##   1) terrain_painter 36 格地表瓦（16px）：草12 + 花草细节6 + 泥10 + 水4 + 冰2 + 冰花2
##   2) world_deco.PROP_SRC 9 个 32×32 道具矩形（树/松/岩/草丛/蘑菇/原木/灌木/宝石/香蒲）
##   3) generate_obstacle_tileset.DERIVE 的 tree/pine/rock 源矩形（deadtree/ice/crystal/bones
##      为其 HSV 派生，无需独立绘制）
## 基础色相落在 terrain_painter._build_atlas 的 HSV 色桶区间（grass 0.16-0.52 /
## water 0.52-0.78 / dirt <0.16 / ice s<0.14 且 v>0.78），运行时群系烘焙原样复用。
## 道具为贴纸描边风（darkened 0.62 外扩带）——与 generate_creatures 的怪物同风格规范。
## 用法：godot --headless --path Code -s tools/generate_tiles.gd
extends SceneTree

const OUT := "res://assets/creatures/sheets/cartoon_tileset.png"
const TS := 16
const W := 448
const H := 640

## ---- 基础色（色相落桶）----
const GRASS := Color("6db34a")       # h≈0.29 草桶
const DIRT := Color("c08a52")        # h≈0.07 泥桶
const WATER := Color("4a90d8")       # h≈0.59 水桶
const ICE := Color("eef4f6")         # s≈0.05 v≈0.96 冰桶
const GRASS_DARK := Color("57993b")
const GRASS_LIGHT := Color("8ccb64")
const DIRT_DARK := Color("a06f42")
const WATER_LIGHT := Color("7ab8e8")
const ICE_STREAK := Color("d2e4ee")  # s≈0.13 仍落冰桶

const GRASS_FILL := [Vector2i(22, 31), Vector2i(22, 32), Vector2i(22, 33), Vector2i(23, 31),
	Vector2i(23, 32), Vector2i(23, 33), Vector2i(24, 33), Vector2i(24, 34),
	Vector2i(24, 35), Vector2i(25, 31), Vector2i(25, 32), Vector2i(25, 33)]
const GRASS_DETAIL := [Vector2i(23, 37), Vector2i(24, 37), Vector2i(25, 37),
	Vector2i(25, 38), Vector2i(27, 37), Vector2i(27, 38)]
const DIRT_FILL := [Vector2i(9, 32), Vector2i(9, 33), Vector2i(9, 37), Vector2i(9, 38),
	Vector2i(10, 33), Vector2i(10, 34), Vector2i(10, 35), Vector2i(11, 31),
	Vector2i(11, 32), Vector2i(11, 33)]
const WATER_FILL := [Vector2i(18, 18), Vector2i(19, 19), Vector2i(18, 19), Vector2i(19, 18)]
const ICE_FILL := [Vector2i(14, 18), Vector2i(16, 18)]
const ICE_DETAIL := [Vector2i(13, 18), Vector2i(15, 18)]

const PROP_RECTS := {
	"tree": Rect2(0, 160, 32, 32), "pine": Rect2(64, 160, 32, 32),
	"rock": Rect2(160, 160, 32, 32), "grass": Rect2(192, 160, 32, 32),
	"mushroom": Rect2(224, 160, 32, 32), "log": Rect2(256, 160, 32, 32),
	"bush": Rect2(32, 160, 32, 32), "gems": Rect2(80, 192, 32, 32),
	"cattail": Rect2(144, 240, 32, 32),
}


func _init() -> void:
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var vi := 0
	for cell: Vector2i in GRASS_FILL:
		_paint_grass(img, cell, vi, false)
		vi += 1
	for cell: Vector2i in GRASS_DETAIL:
		_paint_grass(img, cell, vi, true)
		vi += 1
	for cell: Vector2i in DIRT_FILL:
		_paint_dirt(img, cell, vi)
		vi += 1
	for cell: Vector2i in WATER_FILL:
		_paint_water(img, cell, vi)
		vi += 1
	for cell: Vector2i in ICE_FILL:
		_paint_ice(img, cell, vi, false)
		vi += 1
	for cell: Vector2i in ICE_DETAIL:
		_paint_ice(img, cell, vi, true)
		vi += 1
	for kind: String in PROP_RECTS:
		_paint_prop(img, kind, PROP_RECTS[kind])
	img.save_png(OUT)
	# 落盘自检：统计非空瓦格数
	var painted := 0
	for cell: Vector2i in GRASS_FILL + GRASS_DETAIL + DIRT_FILL + WATER_FILL + ICE_FILL + ICE_DETAIL:
		if img.get_pixel(cell.x * TS + 8, cell.y * TS + 8).a > 0.9:
			painted += 1
	var props := 0
	for kind: String in PROP_RECTS:
		var r: Rect2 = PROP_RECTS[kind]
		if img.get_pixel(int(r.position.x + 16), int(r.position.y + 16)).a > 0.0:
			props += 1
	print("cartoon_tileset 完成：地形 %d/36 格 + 道具 %d/9 格 → %s" % [painted, props, OUT])
	quit(0)


static func _hash2(x: int, y: int, s: int) -> float:
	var h := (x * 374761393 + y * 668265263 + s * 1442695041) % 1000003
	return float(h) / 1000003.0


func _dot(img: Image, px: int, py: int, col: Color) -> void:
	if px >= 0 and py >= 0 and px < W and py < H:
		img.set_pixel(px, py, col)


func _paint_grass(img: Image, cell: Vector2i, vi: int, flowers: bool) -> void:
	var ox := cell.x * TS
	var oy := cell.y * TS
	for y in TS:
		for x in TS:
			img.set_pixel(ox + x, oy + y, GRASS)
	# 确定性草叶（2-3 簇短竖线，明暗各一）
	for k in 3:
		var bx := int(_hash2(cell.x, cell.y + k, 11 + vi) * 12.0) + 2
		var by := int(_hash2(cell.x + k, cell.y, 23 + vi) * 10.0) + 3
		var col := GRASS_DARK if k % 2 == 0 else GRASS_LIGHT
		for d in 2:
			_dot(img, ox + bx, oy + by + d, col)
	if flowers:
		for k in 2:
			var fx := int(_hash2(cell.x + k, cell.y, 31 + vi) * 12.0) + 2
			var fy := int(_hash2(cell.x, cell.y + k, 37 + vi) * 10.0) + 3
			_dot(img, ox + fx, oy + fy, Color.WHITE)
			_dot(img, ox + fx + 1, oy + fy, Color("ffd94d"))
			_dot(img, ox + fx, oy + fy + 1, Color("ffd94d"))


func _paint_dirt(img: Image, cell: Vector2i, vi: int) -> void:
	var ox := cell.x * TS
	var oy := cell.y * TS
	for y in TS:
		for x in TS:
			img.set_pixel(ox + x, oy + y, DIRT)
	for k in 3:
		var bx := int(_hash2(cell.x + k, cell.y, 41 + vi) * 13.0) + 1
		var by := int(_hash2(cell.x, cell.y + k, 43 + vi) * 12.0) + 2
		_dot(img, ox + bx, oy + by, DIRT_DARK)
		_dot(img, ox + bx + 1, oy + by, DIRT_DARK)


func _paint_water(img: Image, cell: Vector2i, vi: int) -> void:
	var ox := cell.x * TS
	var oy := cell.y * TS
	for y in TS:
		for x in TS:
			img.set_pixel(ox + x, oy + y, WATER)
	# 1-2 条浅色波线（水平 3px）
	for k in 2:
		var bx := int(_hash2(cell.x + k, cell.y, 53 + vi) * 11.0) + 1
		var by := int(_hash2(cell.x, cell.y + k, 59 + vi) * 12.0) + 2
		for d in 3:
			_dot(img, ox + bx + d, oy + by, WATER_LIGHT)


func _paint_ice(img: Image, cell: Vector2i, vi: int, sparkle: bool) -> void:
	var ox := cell.x * TS
	var oy := cell.y * TS
	for y in TS:
		for x in TS:
			img.set_pixel(ox + x, oy + y, ICE)
	# 斜向淡蓝冰纹
	var bx := int(_hash2(cell.x, cell.y, 61 + vi) * 10.0) + 2
	for d in 4:
		_dot(img, ox + bx + d, oy + 3 + d, ICE_STREAK)
	if sparkle:
		for k in 2:
			var sx := int(_hash2(cell.x + k, cell.y, 67 + vi) * 11.0) + 2
			var sy := int(_hash2(cell.x, cell.y + k, 71 + vi) * 11.0) + 2
			_dot(img, ox + sx, oy + sy, Color.WHITE)


# ---------- 道具（32×32，SDF 贴纸风）----------

func _stamp(img: Image, parts: Array, rect: Rect2) -> void:
	var cx := rect.position.x + rect.size.x * 0.5
	var cy := rect.position.y + rect.size.y * 0.5
	var half := rect.size.x * 0.5
	for py in int(rect.size.y):
		for px in int(rect.size.x):
			var d := Vector2(rect.position.x + float(px) + 0.5 - cx,
				rect.position.y + float(py) + 0.5 - cy)
			var c := Color(0, 0, 0, 0)
			for part in parts:
				c = _stamp_part(c, part, d)
			if c.a > 0.003:
				img.set_pixel(int(rect.position.x) + px, int(rect.position.y) + py, c)


func _stamp_part(dst: Color, d: Dictionary, world: Vector2) -> Color:
	var q: Vector2 = (world - d["p"]).rotated(-d.get("rot", 0.0)) / d.get("sc", Vector2.ONE)
	var sd := _part_sd(d, q) * minf(d.get("sc", Vector2.ONE).x, d.get("sc", Vector2.ONE).y)
	var base: Color = d["col"]
	if d.get("edge", 0.0) > 0.0:
		var e_cov := clampf(0.5 - (sd + float(d["edge"])), 0.0, 1.0)
		if e_cov > 0.0:
			var ink: Color = base.darkened(0.62)
			dst = _over(dst, Color(ink.r, ink.g, ink.b, e_cov))
	var f_cov := clampf(0.5 - sd, 0.0, 1.0)
	if f_cov > 0.0:
		dst = _over(dst, Color(base.r, base.g, base.b, f_cov))
	return dst


func _part_sd(d: Dictionary, p: Vector2) -> float:
	match d["shape"]:
		"ellipse":
			return _sd_ellipse(p, d["rx"], d["ry"])
		"blob":
			return _sd_blob(p, d["r"], d.get("a3", 0.0), d.get("a5", 0.0))
		"capsule":
			return _sd_capsule(p, d["a"], d["b"], d["r"])
	return 1e9


static func _sd_ellipse(q: Vector2, rx: float, ry: float) -> float:
	rx = maxf(rx, 0.5); ry = maxf(ry, 0.5)
	var k0 := Vector2(q.x / rx, q.y / ry).length()
	var k1 := Vector2(q.x / (rx * rx), q.y / (ry * ry)).length()
	return k0 * (k0 - 1.0) / maxf(k1, 1e-5)


static func _sd_blob(q: Vector2, r: float, a3: float, a5: float) -> float:
	var ang := atan2(q.y, q.x)
	var target := r * (1.0 + a3 * sin(3.0 * ang) + a5 * sin(5.0 * ang + 1.7))
	return q.length() - target


static func _sd_capsule(q: Vector2, a: Vector2, b: Vector2, r: float) -> float:
	var pa := q - a
	var ba := b - a
	var h := clampf(pa.dot(ba) / maxf(ba.dot(ba), 1e-9), 0.0, 1.0)
	return (pa - ba * h).length() - r


static func _over(dst: Color, src: Color) -> Color:
	if dst.a <= 0.003:
		return src
	var da := dst.a + src.a - dst.a * src.a
	if da <= 0.0:
		return Color(0, 0, 0, 0)
	var out := (dst * dst.a * (1.0 - src.a) + src * src.a) / da
	out.a = da
	return out


func _p(shape: String, p: Vector2, props: Dictionary) -> Dictionary:
	var d := {"shape": shape, "p": p, "col": Color.WHITE}
	for k in props:
		d[k] = props[k]
	return d


func _paint_prop(img: Image, kind: String, r: Rect2) -> void:
	## 道具设计坐标 [-16,16]，底边 y≈+14（与 world_deco 底边中心对齐约定一致）
	var leaf := Color("5da648")
	var leaf_dark := Color("478238")
	var wood := Color("8a6a4a")
	var parts: Array = []
	match kind:
		"tree":
			parts.append(_p("capsule", Vector2(0, 11), {"a": Vector2(0, 0), "b": Vector2(0, 6),
				"r": 3.0, "col": wood, "edge": 1.6}))
			parts.append(_p("blob", Vector2(0, -3), {"r": 9.5, "a3": 0.09, "a5": 0.04,
				"col": leaf, "edge": 1.8}))
			parts.append(_p("blob", Vector2(-5, -8), {"r": 5.0, "a3": 0.1,
				"col": leaf.darkened(0.1), "edge": 1.5}))
			parts.append(_p("ellipse", Vector2(-3, -8), {"rx": 3.0, "ry": 2.0,
				"col": leaf.lightened(0.3)}))
		"pine":
			parts.append(_p("capsule", Vector2(0, 12), {"a": Vector2(0, 0), "b": Vector2(0, 4),
				"r": 2.6, "col": wood, "edge": 1.4}))
			parts.append(_p("capsule", Vector2(0, 2), {"a": Vector2(-5.5, 0), "b": Vector2(5.5, 0),
				"r": 4.2, "col": leaf_dark, "edge": 1.6}))
			parts.append(_p("capsule", Vector2(0, -4), {"a": Vector2(-4.2, 0), "b": Vector2(4.2, 0),
				"r": 3.8, "col": leaf_dark, "edge": 1.6}))
			parts.append(_p("capsule", Vector2(0, -10), {"a": Vector2(-2.8, 0), "b": Vector2(2.8, 0),
				"r": 3.4, "col": leaf_dark, "edge": 1.6}))
		"rock":
			parts.append(_p("blob", Vector2(0, 4), {"r": 8.5, "a3": 0.1, "a5": 0.05,
				"col": Color("908878"), "edge": 1.8}))
			parts.append(_p("ellipse", Vector2(-2, 1), {"rx": 3.0, "ry": 2.0,
				"col": Color("a8a090")}))
			parts.append(_p("ellipse", Vector2(3, -3), {"rx": 2.2, "ry": 1.4,
				"col": Color("6db34a"), "alpha": 0.85}))
		"grass":
			for k in 3:
				var lean := -3.0 + 3.0 * k
				parts.append(_p("capsule", Vector2(-4.0 + 4.0 * k, 8), {"a": Vector2(0, 0),
					"b": Vector2(lean, -9.0 - 2.0 * (k % 2)), "r": 1.6, "col": GRASS, "edge": 1.0}))
		"mushroom":
			parts.append(_p("capsule", Vector2(0, 9), {"a": Vector2(0, 0), "b": Vector2(0, -3),
				"r": 2.8, "col": Color("e8dcc0"), "edge": 1.4}))
			parts.append(_p("ellipse", Vector2(0, -4), {"rx": 7.5, "ry": 5.0,
				"col": Color("d8543c"), "edge": 1.6}))
			parts.append(_p("ellipse", Vector2(-3, -5), {"rx": 1.4, "ry": 1.2, "col": Color.WHITE}))
			parts.append(_p("ellipse", Vector2(3, -3), {"rx": 1.2, "ry": 1.0, "col": Color.WHITE}))
		"log":
			parts.append(_p("capsule", Vector2(0, 6), {"a": Vector2(-8, 0), "b": Vector2(8, 0),
				"r": 4.5, "col": wood, "edge": 1.6}))
			parts.append(_p("ellipse", Vector2(8, 6), {"rx": 2.2, "ry": 4.0,
				"col": Color("c9a877"), "edge": 1.2}))
			parts.append(_p("ellipse", Vector2(8, 6), {"rx": 1.0, "ry": 2.0, "col": wood.darkened(0.2)}))
		"bush":
			parts.append(_p("blob", Vector2(-4, 6), {"r": 5.0, "a3": 0.1, "col": leaf, "edge": 1.4}))
			parts.append(_p("blob", Vector2(4, 6), {"r": 5.0, "a3": 0.1, "col": leaf, "edge": 1.4}))
			parts.append(_p("blob", Vector2(0, 3), {"r": 5.5, "a3": 0.08, "col": leaf.lightened(0.08),
				"edge": 1.4}))
		"gems":
			var gem_cols := [Color("5aa8e8"), Color("9a6ae8"), Color("6ad8c8")]
			for k in 3:
				var gx := -5.0 + 5.0 * k
				var gy := 8.0 - 4.0 * absf(k - 1)
				parts.append(_p("capsule", Vector2(gx, gy), {"a": Vector2(-2.2, -2.2),
					"b": Vector2(2.2, 2.2), "r": 2.2, "col": gem_cols[k], "edge": 1.2}))
			parts.append(_p("ellipse", Vector2(-5, 5), {"rx": 0.9, "ry": 0.9, "col": Color.WHITE}))
		"cattail":
			for k in 2:
				var cx := -3.0 + 6.0 * k
				parts.append(_p("capsule", Vector2(cx, 8), {"a": Vector2(0, 0), "b": Vector2(1.0, -12.0),
					"r": 1.2, "col": GRASS_DARK, "edge": 0.8}))
				parts.append(_p("capsule", Vector2(cx + 1, -5), {"a": Vector2(0, 0), "b": Vector2(0.5, -5.0),
					"r": 2.2, "col": Color("9a6a3c"), "edge": 1.0}))
	_stamp(img, parts, r)
