## 地表分块绘制器（运行时，静态工具类 + 静态缓存）。
## v4 世界大地图重构：每区域一张静态 PNG（1100×700×6）不可覆盖 80 万像素世界，
## 改为按世界坐标分块（512px/块 = 32×32 瓦）确定性绘制——同坐标永远同画面，
## 走过再回来看到的还是同一片地。绘制核心（value noise 材质图 / 变体哈希 /
## HSV 色桶烘焙）与旧 tools/generate_terrain.gd 同源，视觉风格一脉相承。
## 群系交界：BiomeMap 双最近斑块的权重差在 BLEND_PX 内线性混合两套烘焙瓦
## （次群系瓦按 alpha 阶梯叠绘）——犬牙交错的"交融"而非硬接缝。
## 注意：_ensure_atlases() 涉及 load()，必须在主线程首次调用（ChunkStreamer._ready），
## 之后工作线程只读静态缓存（初始化后不再写，线程安全）。
class_name TerrainPainter
extends RefCounted

## 图集源（美术 v6 TS）：Tilemap 同版式 5 套配色取 3 套 + 水底纹。
## 源瓦 64px → ÷4 缩到 16px 世界网格（保持全部网格数学不变）。
const SOURCES := {
	"main": "res://assets/ts/Terrain/Tileset/Tilemap_color1.png",
	"earth": "res://assets/ts/Terrain/Tileset/Tilemap_color4.png",
	"cold": "res://assets/ts/Terrain/Tileset/Tilemap_color5.png",
	"water": "res://assets/ts/Terrain/Tileset/Water Background color.png",
}
const TS := 16
## 群系过渡带宽度（世界像素）：双斑块距离差在此宽度内线性混瓦
const BLEND_PX := 72.0
## 过渡叠绘 alpha 阶梯（两档；权重 < 0.15 不叠）
const OVERLAY_ALPHAS := [0.38, 0.68]
const ATLAS_COLS := 12

## 地表只取平面内部格（零起点 (1,1)/(6,1)）：r0/r2 是上下轮廓，
## c3/c8 是窄岛边缘，r4/r5 是竖直悬崖，随机铺地会形成无碰撞的假裂缝/假墙。
## 土斑改取现有 color4 橄榄色平面，保留材质分区；不新增美术或更改地形逻辑。
## 保留既有槽位数量/哈希索引；源图无独立花簇格，detail 槽同样只能选内部。
const GRASS_FILL := [["main", Vector2i(1, 1)], ["main", Vector2i(6, 1)],
	["main", Vector2i(1, 1)], ["main", Vector2i(6, 1)],
	["main", Vector2i(1, 1)], ["main", Vector2i(6, 1)]]
const GRASS_DETAIL := [["main", Vector2i(1, 1)], ["main", Vector2i(6, 1)],
	["main", Vector2i(1, 1)], ["main", Vector2i(6, 1)],
	["main", Vector2i(1, 1)], ["main", Vector2i(6, 1)]]
const DIRT_FILL := [["earth", Vector2i(1, 1)], ["earth", Vector2i(6, 1)],
	["earth", Vector2i(1, 1)], ["earth", Vector2i(6, 1)],
	["earth", Vector2i(1, 1)], ["earth", Vector2i(6, 1)], ["earth", Vector2i(1, 1)]]
const WATER_FILL := [["water", Vector2i(0, 0)]]
const ICE_FILL := [["cold", Vector2i(1, 1)], ["cold", Vector2i(6, 1)],
	["cold", Vector2i(1, 1)], ["cold", Vector2i(6, 1)]]
const ICE_DETAIL := [["cold", Vector2i(1, 1)], ["cold", Vector2i(6, 1)],
	["cold", Vector2i(1, 1)]]

## 素材种类 id（材质图 0=base 1=patch 2=water 按规则映射）
const KIND_GRASS := 0
const KIND_DIRT := 1
const KIND_WATER := 2
const KIND_ICE := 3
## 每种类在迷你图集中的起始格与数量（图集布局 = 上面六组按序拼接）
const KIND_RANGES := {
	KIND_GRASS: [0, 6],
	KIND_DIRT: [12, 7],
	KIND_WATER: [19, 1],
	KIND_ICE: [20, 4],
}
## 低概率换细节瓦（花簇/裂纹）打破重复：种类 → 细节格区间 [start, count]
const KIND_DETAILS := {
	KIND_GRASS: [6, 6],
	KIND_ICE: [24, 3],
}

## 每地形绘制规则（与 generate_terrain.BIOMES 同源，键改地形名）：
## base/patch=材质，thr=斑块噪声阈值；water/water_thr=独立水池层；
## bake=色桶 HSV 重映射（群系氛围由 bake 定义，瓦片纹理与明度层次保留）
const RULES := {
	"plains": {"seedv": 11, "base": "grass", "patch": "dirt", "patch_thr": 0.60,
		"water": false, "water_thr": 0.90},
	"forest": {"seedv": 22, "base": "grass", "patch": "dirt", "patch_thr": 0.52,
		"water": false, "water_thr": 0.90,
		"bake": {"grass": {"hue": -0.02, "sat": 1.10, "val": 0.78}}},
	"snow": {"seedv": 33, "base": "ice", "patch": "dirt", "patch_thr": 0.66,
		"water": true, "water_thr": 0.78,
		"bake": {"grass": {"hue": 0.42, "sat": 0.25, "val": 1.12},
			"dirt": {"sat": 0.40, "val": 1.02}, "water": {"sat": 0.20, "val": 1.15}}},
	"swamp": {"seedv": 44, "base": "grass", "patch": "water", "patch_thr": 0.62,
		"water": false, "water_thr": 0.90,
		"bake": {"grass": {"hue": 0.06, "sat": 0.70, "val": 0.70},
			"water": {"hue": -0.23, "sat": 0.80, "val": 0.68}}},
	"hill": {"seedv": 55, "base": "dirt", "patch": "grass", "patch_thr": 0.55,
		"water": true, "water_thr": 0.86},
	"lava": {"seedv": 66, "base": "ice", "patch": "grass", "patch_thr": 0.58,
		"water": true, "water_thr": 0.72,
		"bake": {"ice": {"val": 0.38}, "water": {"hue": 0.55, "sat": 1.40, "val": 0.95},
			"grass": {"sat": 0.30, "val": 0.50}}},
}

static var _sources := {}
## terrain → 烘焙迷你图集（alpha=1，基础瓦）
static var _atlases := {}
## terrain → Array[Image]（OVERLAY_ALPHAS 对应的叠绘变体）
static var _overlays := {}
## 水岸内侧 2px 暗带（横/竖细条，黑色半透明）
static var _strip_h: Image
static var _strip_v: Image
static var _ready := false


## 主线程初始化（load 图集 + 烘焙）。幂等。源 64px 瓦 ÷4 缩到 16px 世界格。
static func ensure_atlases() -> void:
	if _ready:
		return
	_ready = true
	for key: String in SOURCES:
		var img := (load(SOURCES[key]) as Texture2D).get_image()
		img.resize(img.get_width() / 4, img.get_height() / 4, Image.INTERPOLATE_NEAREST)
		_sources[key] = img
	var cells := _atlas_cells()
	var rows := (cells.size() + ATLAS_COLS - 1) / ATLAS_COLS
	for terrain: String in RULES:
		var atlas := _build_atlas(cells, rows, RULES[terrain].get("bake", {}))
		_atlases[terrain] = atlas
		var steps: Array = []
		for f: float in OVERLAY_ALPHAS:
			steps.append(_with_alpha(atlas, f))
		_overlays[terrain] = steps
	_strip_h = _black_strip(Vector2i(TS, 4))
	_strip_v = _black_strip(Vector2i(4, TS))


## 绘制一个世界坐标块：origin 为块左上角世界像素（TS 的倍数），tiles 为边长瓦数。
## 返回 RGBA8 Image（调用方在主线程转 ImageTexture）。确定性：同参数同结果。
static func paint_chunk(origin: Vector2i, tiles: int) -> Image:
	ensure_atlases()
	var size_px := tiles * TS
	# 材质图带 1 瓦边距（水岸判定需要邻瓦；边距瓦只供查询不绘制）
	var dim := tiles + 2
	var terr1 := PackedStringArray()
	var terr2 := PackedStringArray()
	terr1.resize(dim * dim)
	terr2.resize(dim * dim)
	var mat1 := PackedInt32Array()
	mat1.resize(dim * dim)
	var mix := PackedFloat32Array()
	mix.resize(dim * dim)
	var base_gtx := origin.x / TS
	var base_gty := origin.y / TS
	for ty in dim:
		for tx in dim:
			var center := Vector2(
				float(origin.x + (tx - 1) * TS + TS / 2),
				float(origin.y + (ty - 1) * TS + TS / 2))
			var field := BiomeMap.field_at(center)
			var t1: String = BiomeMap.terrain_of_patch(field["id1"])
			var t2: String = BiomeMap.terrain_of_patch(field["id2"])
			var idx := ty * dim + tx
			terr1[idx] = t1
			terr2[idx] = t2
			var gtx := base_gtx + tx - 1
			var gty := base_gty + ty - 1
			mat1[idx] = _material(t1, gtx, gty, center, field["id1"])
			var dd := sqrt(float(field["d2"])) - sqrt(float(field["d1"]))
			mix[idx] = clampf(1.0 - dd / BLEND_PX, 0.0, 1.0) * 0.5
	# 铺瓦：主导群系基础瓦 + 交界处次群系叠瓦
	var img := Image.create(size_px, size_px, false, Image.FORMAT_RGBA8)
	for ty in tiles:
		for tx in tiles:
			var idx := (ty + 1) * dim + (tx + 1)
			var t1: String = terr1[idx]
			var m := mat1[idx]
			var gtx := base_gtx + tx
			var gty := base_gty + ty
			var rule: Dictionary = RULES[t1]
			var kind := _kind_of(rule, m)
			var cell := _cell_rect(_pick(kind, gtx, gty, rule["seedv"]))
			var dst := Vector2i(tx * TS, ty * TS)
			img.blit_rect(_atlases[t1], cell, dst)
			# 群系交融：次斑块瓦按权重阶梯叠绘（权重 0.15~0.5）
			var w: float = mix[idx]
			var t2: String = terr2[idx]
			if w >= 0.15 and t2 != t1:
				var rule2: Dictionary = RULES[t2]
				var kind2 := _kind_of(rule2, mat1[idx])
				var cell2 := _cell_rect(_pick(kind2, gtx, gty, rule2["seedv"]))
				var step := 0 if w < 0.34 else 1
				img.blend_rect((_overlays[t2] as Array)[step], cell2, dst)
			# 水岸：水瓦贴着非水瓦的内侧 2~4px 暗带
			if m == 2:
				if mat1[idx - 1] != 2:
					img.blend_rect(_strip_v, Rect2i(0, 0, 4, TS), dst)
				if mat1[idx + 1] != 2:
					img.blend_rect(_strip_v, Rect2i(0, 0, 4, TS), dst + Vector2i(TS - 4, 0))
				if mat1[idx - dim] != 2:
					img.blend_rect(_strip_h, Rect2i(0, 0, TS, 4), dst)
				if mat1[idx + dim] != 2:
					img.blend_rect(_strip_h, Rect2i(0, 0, TS, 4), dst + Vector2i(0, TS - 4))
	# 碎斑散点：簇状暗点成团（水面不撒），密度与旧整图口径一致（80 簇/77 万 px²）
	var rng := RandomNumberGenerator.new()
	rng.seed = (absi(origin.x) * 73856093) ^ (absi(origin.y) * 19349663)
	var clusters := maxi(2, int(round(80.0 * float(size_px * size_px) / 770000.0)))
	for c in clusters:
		var cx := rng.randi_range(10, size_px - 11)
		var cy := rng.randi_range(10, size_px - 11)
		for i in rng.randi_range(18, 46):
			var sx := clampi(cx + rng.randi_range(-7, 7), 4, size_px - 5)
			var sy := clampi(cy + rng.randi_range(-5, 5), 4, size_px - 5)
			if mat1[(sy / TS + 1) * dim + sx / TS + 1] == 2:
				continue
			if rng.randf() < 0.55:
				img.set_pixel(sx, sy, img.get_pixel(sx, sy).darkened(0.06))
	return img


## 材质图采样：0=base 1=patch 2=water（全局瓦坐标连续）。
## 液体层真源在 ObstacleField.liquid_kind_in（世界 v5 起与阻挡/灼烧判定同源，
## 抑制区同口径——可见水与可行区不再两张皮；RULES 的 water/water_thr 键废弃留档）
static func _material(terrain: String, gtx: int, gty: int, center: Vector2,
		patch_id: String) -> int:
	var rule: Dictionary = RULES[terrain]
	var seedv: int = rule["seedv"]
	var macro := _fbm(float(gtx) / 8.5, float(gty) / 8.5, seedv, 3)
	var m := 0
	if macro >= float(rule["patch_thr"]):
		m = 1
	if ObstacleField.liquid_kind_in(terrain, center, patch_id) != "":
		m = 2
	return m


static func _kind_of(rule: Dictionary, m: int) -> int:
	var name: String = rule["base"] if m == 0 else (rule["patch"] if m == 1 else "water")
	match name:
		"grass":
			return KIND_GRASS
		"dirt":
			return KIND_DIRT
		"ice":
			return KIND_ICE
		_:
			return KIND_WATER


## 按材质选瓦：哈希挑填充变体；低概率换细节瓦（花簇/裂纹）打破重复
static func _pick(kind: int, gtx: int, gty: int, seedv: int) -> int:
	var v := _hash2(gtx, gty, seedv + 3)
	var detail: Array = KIND_DETAILS.get(kind, [])
	if v > 0.93 and not detail.is_empty():
		return detail[0] + int(_hash2(gtx, gty, seedv + 4) * detail[1])
	var range_: Array = KIND_RANGES[kind]
	return range_[0] + int(_hash2(gtx, gty, seedv + 5) * range_[1])


static func _cell_rect(cell: int) -> Rect2i:
	return Rect2i((cell % ATLAS_COLS) * TS, (cell / ATLAS_COLS) * TS, TS, TS)


# --- 图集烘焙 ---

## 迷你图集源格序列（六组瓦表按序拼接，索引即 KIND_RANGES 的坐标系）
static func _atlas_cells() -> Array:
	var cells: Array = []
	cells.append_array(GRASS_FILL)
	cells.append_array(GRASS_DETAIL)
	cells.append_array(DIRT_FILL)
	cells.append_array(WATER_FILL)
	cells.append_array(ICE_FILL)
	cells.append_array(ICE_DETAIL)
	return cells


## 从各源图集抽取用到的瓦组成迷你图集，再按色桶规则 HSV 烘焙（群系氛围）。
## 色桶区间按 TS 素材实测色相标定（草 0.21-0.25 / 泥 0.44 / 水 0.50 青）
static func _build_atlas(cells: Array, rows: int, bake: Dictionary) -> Image:
	var atlas := Image.create(ATLAS_COLS * TS, rows * TS, false, Image.FORMAT_RGBA8)
	for idx in cells.size():
		var spec: Array = cells[idx]
		var img: Image = _sources[spec[0]]
		var cell: Vector2i = spec[1]
		atlas.blit_rect(img, Rect2i(cell.x * TS, cell.y * TS, TS, TS),
			Vector2i((idx % ATLAS_COLS) * TS, (idx / ATLAS_COLS) * TS))
	if bake.is_empty():
		return atlas
	for y in atlas.get_height():
		for x in atlas.get_width():
			var c: Color = atlas.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			var bucket := ""
			if c.s < 0.14:
				bucket = "ice" if c.v > 0.78 else ""
			elif 0.48 <= c.h and c.h < 0.72:
				bucket = "water"
			elif 0.16 <= c.h and c.h < 0.40:
				bucket = "grass"
			else:
				bucket = "dirt"
			var rule: Dictionary = bake.get(bucket, {})
			if rule.is_empty():
				continue
			atlas.set_pixel(x, y, Color.from_hsv(
				fposmod(c.h + rule.get("hue", 0.0), 1.0),
				clampf(c.s * rule.get("sat", 1.0), 0.0, 1.0),
				clampf(c.v * rule.get("val", 1.0), 0.0, 1.0),
				c.a))
	return atlas


## 图集整体乘 alpha（交界叠绘变体）
static func _with_alpha(src: Image, factor: float) -> Image:
	var out := src.duplicate()
	for y in out.get_height():
		for x in out.get_width():
			var c: Color = out.get_pixel(x, y)
			if c.a > 0.0:
				out.set_pixel(x, y, Color(c.r, c.g, c.b, c.a * factor))
	return out


## 水岸暗带细条（黑色半透明）
static func _black_strip(sz: Vector2i) -> Image:
	var img := Image.create(sz.x, sz.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0.35))
	return img


# --- 确定性噪声（与 generate_terrain / BiomeMap 同源实现） ---

static func _hash2(x: int, y: int, s: int) -> float:
	var h: int = x * 374761393 + y * 668265263 + s * 2246822519
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0x7FFFFFFF) / 2147483647.0


static func _vnoise(x: float, y: float, s: int) -> float:
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


static func _fbm(x: float, y: float, s: int, octaves: int) -> float:
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
