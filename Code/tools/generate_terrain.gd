## 地表纹理离线生成工具（无头运行：godot --headless --path Code -s tools/generate_terrain.gd）。
## v2（2026-09-03 内容重设计 v3 / P2）：Ninja Adventure tileset 真贴图拼接——
##   确定性噪声决定每 16px 瓦的材质（草/泥/水/冰），变体哈希防重复，细节瓦点缀；
##   群系差异 = 色桶重映射（绿/蓝水/白冰/棕橙各自 HSV 目标，纹理与明度层次保留）；
##   水岸 2px 描边 + 边缘渐暗 + 簇状散点（沿用 v1 质感层）。
## v4（2026-09-08 世界大地图重构）起游戏内地表改为运行时分块绘制
## （scripts/main/terrain/terrain_painter.gd，同源算法），本工具的 6 张
## 1100×700 PNG 仅剩主菜单底部地平线装饰条一个消费方（main_menu.gd）——
## 保留不动；小地图底图用 tools/generate_world_map.gd。
extends SceneTree

const W := 1100
const H := 700
const OUT_DIR := "res://assets/terrain/"
const TILESET := "res://assets/creatures/sheets/cartoon_tileset.png"
const TS := 16

## 瓦片坐标（列,行）——程序化像素统计验证（2026-09-03）：
##   草填充绿色度=1.00 / 泥填充橙棕度=1.00 / 水瓦蓝色度≥0.96 / 冰瓦白色度≥0.86
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

## 群系规则：base/patch=材质（grass/dirt/water/ice），thr=斑块噪声阈值；
## water/water_thr=独立水池层；bake=色桶 HSV 重映射（键：grass/water/ice/dirt）
const BIOMES := {
	"west": {
		"names": ["region_west.png"], "seedv": 11,
		"base": "grass", "patch": "dirt", "patch_thr": 0.60,
		"water": false, "water_thr": 0.90,
	},
	"center": {
		"names": ["region_center.png"], "seedv": 22,
		"base": "grass", "patch": "dirt", "patch_thr": 0.52,
		"water": false, "water_thr": 0.90,
		"bake": {"grass": {"hue": -0.02, "sat": 1.10, "val": 0.78}},
	},
	"snow": {
		"names": ["region_snow.png"], "seedv": 33,
		"base": "ice", "patch": "dirt", "patch_thr": 0.66,
		"water": true, "water_thr": 0.78,
		"bake": {"grass": {"hue": 0.42, "sat": 0.25, "val": 1.12},
			"dirt": {"sat": 0.40, "val": 1.02}, "water": {"sat": 0.20, "val": 1.15}},
	},
	"swamp": {
		"names": ["region_swamp.png"], "seedv": 44,
		"base": "grass", "patch": "water", "patch_thr": 0.62,
		"water": false, "water_thr": 0.90,
		"bake": {"grass": {"hue": 0.06, "sat": 0.70, "val": 0.70},
			"water": {"hue": -0.23, "sat": 0.80, "val": 0.68}},
	},
	"east": {
		"names": ["region_east.png"], "seedv": 55,
		"base": "dirt", "patch": "grass", "patch_thr": 0.55,
		"water": true, "water_thr": 0.86,
	},
	"lava": {
		"names": ["region_lava.png"], "seedv": 66,
		"base": "ice", "patch": "grass", "patch_thr": 0.58,
		"water": true, "water_thr": 0.72,
		"bake": {"ice": {"val": 0.38}, "water": {"hue": 0.55, "sat": 1.40, "val": 0.95},
			"grass": {"sat": 0.30, "val": 0.50}},
	},
}

const EDGE := 44.0


func _init() -> void:
	var ts := Image.load_from_file(ProjectSettings.globalize_path(TILESET))
	for key: String in BIOMES:
		var cfg: Dictionary = BIOMES[key]
		var img := _generate(cfg, ts)
		var path: String = OUT_DIR + cfg["names"][0]
		var err := img.save_png(path)
		print("生成 %s（%dx%d）%s" % [path, W, H, "OK" if err == OK else "失败:%d" % err])
	quit(0)


## 整数坐标散列 → [0,1)
func _hash2(x: int, y: int, s: int) -> float:
	var h: int = x * 374761393 + y * 668265263 + s * 2246822519
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0x7FFFFFFF) / 2147483647.0


## value noise（双线性插值 + smoothstep）
func _vnoise(x: float, y: float, s: int) -> float:
	var xi := floori(x)
	var yi := floori(y)
	var xf := x - float(xi)
	var yf := y - float(yi)
	var u := xf * xf * (3.0 - 2.0 * xf)
	var v := yf * yf * (3.0 - 2.0 * yf)
	var a := _hash2(xi, yi, s)
	var b := _hash2(xi + 1, yi, s)
	var c := _hash2(xi, yi + 1, s)
	var d := _hash2(xi + 1, yi + 1, s)
	return a * (1.0 - u) * (1.0 - v) + b * u * (1.0 - v) + c * (1.0 - u) * v + d * u * v


## 分形叠加噪声（octaves 层，频率倍增振幅减半）
func _fbm(x: float, y: float, s: int, octaves: int) -> float:
	var sum := 0.0
	var amp := 0.5
	var freq := 1.0
	var norm := 0.0
	for i in octaves:
		sum += amp * _vnoise(x * freq, y * freq, s + i * 101)
		norm += amp
		amp *= 0.5
		freq *= 2.0
	return sum / norm


## 色桶重映射：像素按色相/饱和度分桶（草/水/冰白/泥橙/灰描边），
## 桶各自应用 HSV 增量——群系氛围由 bake 定义，瓦片纹理与明度层次保留
func _bake_tileset(ts: Image, rules: Dictionary) -> Image:
	if rules.is_empty():
		return ts
	var out := ts.duplicate()
	for y in out.get_height():
		for x in out.get_width():
			var c: Color = out.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			var bucket := ""
			if c.s < 0.14:
				bucket = "ice" if c.v > 0.78 else ""
			elif 0.52 <= c.h and c.h < 0.78:
				bucket = "water"
			elif 0.16 <= c.h and c.h < 0.52:
				bucket = "grass"
			else:
				bucket = "dirt"
			var rule: Dictionary = rules.get(bucket, {})
			if rule.is_empty():
				continue
			out.set_pixel(x, y, Color.from_hsv(
				fposmod(c.h + rule.get("hue", 0.0), 1.0),
				clampf(c.s * rule.get("sat", 1.0), 0.0, 1.0),
				clampf(c.v * rule.get("val", 1.0), 0.0, 1.0),
				c.a))
	return out


func _generate(cfg: Dictionary, ts: Image) -> Image:
	var baked := _bake_tileset(ts, cfg.get("bake", {}))
	var seedv: int = cfg["seedv"]
	var cols := (W + TS - 1) / TS
	var rows := (H + TS - 1) / TS
	## 材质图：0=base 1=patch 2=water
	var mat := PackedInt32Array()
	mat.resize(cols * rows)
	for ty in rows:
		for tx in cols:
			var macro := _fbm(float(tx) / 8.5, float(ty) / 8.5, seedv, 3)
			var wet := _fbm(float(tx) / 12.0, float(ty) / 12.0, seedv + 51, 3)
			var m := 0
			if macro >= float(cfg["patch_thr"]):
				m = 1
			if bool(cfg.get("water", false)) and wet >= float(cfg["water_thr"]):
				m = 2
			mat[ty * cols + tx] = m
	## 铺瓦（含边缘溢出的 1 瓦画布，最终逐像素拷贝时裁掉）
	var canvas := Image.create(cols * TS, rows * TS, false, Image.FORMAT_RGBA8)
	var fills := {
		"grass": GRASS_FILL, "dirt": DIRT_FILL, "water": WATER_FILL, "ice": ICE_FILL,
	}
	var details := {"grass": GRASS_DETAIL, "ice": ICE_DETAIL}
	for ty in rows:
		for tx in cols:
			var m := mat[ty * cols + tx]
			var kind: String = cfg["base"] if m == 0 else (cfg["patch"] if m == 1 else "water")
			var src := _tile_rect(_pick_tile(kind, tx, ty, seedv, fills, details))
			canvas.blit_rect(baked, src, Vector2i(tx * TS, ty * TS))
	## 最终逐像素：水岸 2px 描边 + 边缘渐暗 → RGB8 输出
	var img := Image.create(W, H, false, Image.FORMAT_RGB8)
	for y in H:
		for x in W:
			var tx := x / TS
			var ty := y / TS
			var c: Color = canvas.get_pixel(x, y)
			if mat[ty * cols + tx] == 2 and _near_water_edge(mat, cols, rows, tx, ty, x, y):
				c = c.darkened(0.35)
			var d := minf(minf(float(x), float(W - 1 - x)), minf(float(y), float(H - 1 - y)))
			if d < EDGE:
				c = c.darkened(0.35 * (1.0 - d / EDGE))
			img.set_pixel(x, y, c)
	## 簇状散点（v1 保留：碎斑点成团，水面不撒）
	var rng := RandomNumberGenerator.new()
	rng.seed = seedv * 7919
	for cluster in 80:
		var cx := rng.randi_range(10, W - 11)
		var cy := rng.randi_range(10, H - 11)
		var cluster_size := rng.randi_range(18, 46)
		for i in cluster_size:
			var sx := clampi(cx + rng.randi_range(-7, 7), 4, W - 5)
			var sy := clampi(cy + rng.randi_range(-5, 5), 4, H - 5)
			if mat[(sy / TS) * cols + sx / TS] == 2:
				continue
			if rng.randf() < 0.55:
				img.set_pixel(sx, sy, img.get_pixel(sx, sy).darkened(0.06))
	return img


## 按材质选瓦：哈希挑填充变体；低概率换细节瓦（花簇/裂纹）打破重复
func _pick_tile(kind: String, tx: int, ty: int, seedv: int,
		fills: Dictionary, details: Dictionary) -> Vector2i:
	var v := _hash2(tx, ty, seedv + 3)
	if v > 0.93 and details.has(kind):
		var det: Array = details[kind]
		return det[int(_hash2(tx, ty, seedv + 4) * det.size())]
	var list: Array = fills[kind]
	return list[int(_hash2(tx, ty, seedv + 5) * list.size())]


func _tile_rect(cell: Vector2i) -> Rect2i:
	return Rect2i(cell.x * TS, cell.y * TS, TS, TS)


## 水瓦内侧 2px 岸线（该像素贴着非水瓦才描）
func _near_water_edge(mat: PackedInt32Array, cols: int, rows: int,
		tx: int, ty: int, x: int, y: int) -> bool:
	var lx := x % TS
	var ly := y % TS
	if lx <= 1 and tx > 0 and mat[ty * cols + tx - 1] != 2:
		return true
	if lx >= TS - 2 and tx + 1 < cols and mat[ty * cols + tx + 1] != 2:
		return true
	if ly <= 1 and ty > 0 and mat[(ty - 1) * cols + tx] != 2:
		return true
	if ly >= TS - 2 and ty + 1 < rows and mat[(ty + 1) * cols + tx] != 2:
		return true
	return false
