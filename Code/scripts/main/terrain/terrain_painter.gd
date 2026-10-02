## 地表分块绘制器（运行时，静态工具类 + 静态缓存）。
## v4 世界大地图重构：每区域一张静态 PNG（1100×700×6）不可覆盖 80 万像素世界，
## 改为按世界坐标分块（512px/块 = 32×32 瓦）确定性绘制——同坐标永远同画面，
## 走过再回来看到的还是同一片地。沿用 Tiny Swords 平面像素纹理，
## 运行时采用六群系明确色板、世界尺度材质斑块和邻接岸线。
## 保留 16px 逻辑取样，纹理按 32px 世界尺度铺设；材质边缘消费原图草岸轮廓，
## 不把悬崖或随机外轮廓当平地。所有细节按世界坐标取样，任意分块/重载像素一致。
## 注意：_ensure_atlases() 涉及 load()，必须在主线程首次调用（ChunkStreamer._ready），
## 之后工作线程只读静态缓存（初始化后不再写，线程安全）。
class_name TerrainPainter
extends RefCounted

## 图集源（美术 v6 TS）：Tilemap 同版式 5 套配色取 3 套 + 水底纹。
## 运行时源瓦 64px → 32px 视觉纹理；16px 逻辑格从中取四个相位，网格数学不变。
const SOURCES := {
	"main": "res://assets/ts/Terrain/Tileset/Tilemap_color1.png",
	"earth": "res://assets/ts/Terrain/Tileset/Tilemap_color4.png",
	"cold": "res://assets/ts/Terrain/Tileset/Tilemap_color5.png",
	"water": "res://assets/ts/Terrain/Tileset/Water Background color.png",
}
const TS := 16
## 群系过渡带宽度（世界像素）：双斑块距离差在此宽度内线性混瓦
const BLEND_PX := 160.0
## 对称群系渐变色阶；边界两侧权重均趋近 0.5，避免换主群系时颜色跳变。
const OVERLAY_ALPHAS := [0.0625, 0.125, 0.1875, 0.25, 0.3125, 0.375, 0.4375, 0.5]

## 以下旧槽位表保留给主菜单生成器/帧资产契约；运行时 _build_surface 直接抽内部格。
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

## 材质语义与宏观斑块；水位仍只消费 ObstacleField，色板集中在下方。
const RULES := {
	"plains": {"seedv": 11, "base": "grass", "patch": "dirt", "patch_thr": 0.64},
	"forest": {"seedv": 22, "base": "grass", "patch": "dirt", "patch_thr": 0.57},
	"snow": {"seedv": 33, "base": "ice", "patch": "dirt", "patch_thr": 0.66},
	"swamp": {"seedv": 44, "base": "grass", "patch": "water", "patch_thr": 0.59},
	"hill": {"seedv": 55, "base": "dirt", "patch": "grass", "patch_thr": 0.55},
	"lava": {"seedv": 66, "base": "ice", "patch": "grass", "patch_thr": 0.58},
}

## 色板仅重映射 Tiny Swords 的原始像素纹理；不生成纯色地板或假悬崖。
## 三槽 = 地被、裸地/浅滩、真实液体；低对比纹理为角色、投射物与地物让出层次。
const SURFACE_PALETTES := {
	"plains": [["6f914e", "91ad61"], ["988961", "bba578"], ["477b91", "5b9bae"]],
	"forest": [["426d4c", "5c8555"], ["757650", "8e8a60"], ["467383", "60909c"]],
	"snow": [["cbdcde", "e4eded"], ["a3bbc4", "bed1d5"], ["48829e", "6aa5ba"]],
	"swamp": [["4e6c56", "6f805f"], ["456563", "5e8075"], ["456563", "5e8075"]],
	"hill": [["a08c6e", "b6a27f"], ["7c8855", "97a167"], ["447f98", "64a0b2"]],
	"lava": [["4e4852", "68606a"], ["716069", "89746f"], ["c94c35", "f49b47"]],
}
const TEXTURE_SIZE := 32
const EDGE_N := 1
const EDGE_E := 2
const EDGE_S := 4
const EDGE_W := 8
## 出生营地现有门前、行商与南侧开口的步道中心线。仅地表色块，无导航含义。
const CAMP_PATHS := [
	[Vector2(0, -178), Vector2(12, -80), 24.0],
	[Vector2(12, -80), Vector2(-22, 90), 26.0],
	[Vector2(-22, 90), Vector2(10, 220), 26.0],
	[Vector2(10, 220), Vector2(-24, 390), 24.0],
	[Vector2(-310, -25), Vector2(-180, 0), 24.0],
	[Vector2(-180, 0), Vector2(12, -45), 24.0],
	[Vector2(12, -45), Vector2(180, -15), 24.0],
	[Vector2(180, -15), Vector2(300, -10), 22.0],
	[Vector2(300, -10), Vector2(430, -25), 22.0],
	[Vector2(6, -150), Vector2(110, -130), 22.0],
	[Vector2(110, -130), Vector2(215, -145), 22.0],
	[Vector2(85, -28), Vector2(100, 48), 20.0],
]

static var _sources := {}
static var _surfaces := {} # terrain → 三槽 32px 原图材质
static var _patch_edges := {} # terrain → 16 邻接轮廓 × 4 世界纹理相位
static var _water_edges := {} # terrain → 水面 + 原图轮廓岸边
static var _overlays := {} # terrain → 次群系地被渐变色阶
static var _ready := false
static var _edge_depths := PackedInt32Array()


## 主线程初始化（load 图集 + 烘焙）。幂等；工作线程只读约 1.4MiB 材质缓存。
static func ensure_atlases() -> void:
	if _ready:
		return
	for key: String in SOURCES:
		var img := (load(SOURCES[key]) as Texture2D).get_image()
		# 原图 64px 瓦缩到 32px：与 TS 角色/树的像素粒度一致。
		img.resize(img.get_width() / 2, img.get_height() / 2, Image.INTERPOLATE_NEAREST)
		_sources[key] = img
	_edge_depths.resize(TEXTURE_SIZE)
	for x in TEXTURE_SIZE:
		_edge_depths[x] = 2
		for y in 6:
			if (_sources["main"] as Image).get_pixel(TEXTURE_SIZE + x, y).a > 0.5:
				_edge_depths[x] = clampi(y + 1, 1, 3)
				break
	for terrain: String in RULES:
		var surface := _build_surface(terrain)
		_surfaces[terrain] = surface
		_patch_edges[terrain] = _build_edges(terrain, surface, false)
		_water_edges[terrain] = _build_edges(terrain, surface, true)
		var steps: Array = []
		for alpha: float in OVERLAY_ALPHAS:
			steps.append(_with_alpha(surface, alpha))
		_overlays[terrain] = steps
	_ready = true


## 世界取样加一圈邻格；边界、岸线和纹理相位均不依赖块的大小与加载顺序。
static func paint_chunk(origin: Vector2i, tiles: int) -> Image:
	ensure_atlases()
	var dim := tiles + 2
	var terr1 := PackedStringArray()
	var terr2 := PackedStringArray()
	var mat1 := PackedInt32Array()
	var wet := PackedByteArray()
	var mix := PackedFloat32Array()
	terr1.resize(dim * dim)
	terr2.resize(dim * dim)
	mat1.resize(dim * dim)
	wet.resize(dim * dim)
	mix.resize(dim * dim)
	var base_gtx := floori(float(origin.x) / TS)
	var base_gty := floori(float(origin.y) / TS)
	for ty in dim:
		for tx in dim:
			var gtx := base_gtx + tx - 1
			var gty := base_gty + ty - 1
			var center := Vector2(gtx * TS + TS / 2, gty * TS + TS / 2)
			var field := BiomeMap.field_at(center)
			var idx := ty * dim + tx
			var t1 := BiomeMap.terrain_of_patch(field["id1"])
			terr1[idx] = t1
			terr2[idx] = BiomeMap.terrain_of_patch(field["id2"])
			mat1[idx] = _material(t1, gtx, gty, center, field["id1"])
			wet[idx] = int(mat1[idx] == 2 or (mat1[idx] == 1 and t1 == "swamp"))
			var dd := sqrt(float(field["d2"])) - sqrt(float(field["d1"]))
			mix[idx] = clampf(1.0 - dd / BLEND_PX, 0.0, 1.0) * 0.5
	var img := Image.create(tiles * TS, tiles * TS, false, Image.FORMAT_RGBA8)
	for ty in tiles:
		for tx in tiles:
			var idx := (ty + 1) * dim + tx + 1
			var t1 := terr1[idx]
			var phase := posmod(base_gtx + tx, 2) + posmod(base_gty + ty, 2) * 2
			var dst := Vector2i(tx * TS, ty * TS)
			var material := mat1[idx]
			if wet[idx] != 0:
				var edges := _edge_mask(wet, idx, dim, 1)
				img.blit_rect(_water_edges[t1], _edge_rect(edges, phase), dst)
			else:
				img.blit_rect(_surfaces[t1], _surface_rect(0, phase), dst)
				if material == 1:
					var edges := _edge_mask(mat1, idx, dim, 1)
					img.blend_rect(_patch_edges[t1], _edge_rect(edges, phase), dst)
			# 跨群系只交融地被色板，不把次群系的水画到主群系可行地面上。
			# 真水/熔岩岸线维持权威液体口径，不做跨岸 alpha 污染。
			var w := mix[idx]
			if w >= 0.03125 and terr2[idx] != t1 and wet[idx] == 0:
				var step := clampi(int(round(w * 16.0)) - 1, 0, OVERLAY_ALPHAS.size() - 1)
				var center := Vector2((base_gtx + tx) * TS + TS / 2,
					(base_gty + ty) * TS + TS / 2)
				var secondary := _ground_material(terr2[idx], base_gtx + tx, base_gty + ty, center)
				img.blend_rect((_overlays[terr2[idx]] as Array)[step],
					_surface_rect(secondary, phase), dst)
	return img


static func _edge_mask(values: Variant, idx: int, dim: int, match_value: int) -> int:
	return (EDGE_N if values[idx - dim] != match_value else 0) \
		| (EDGE_E if values[idx + 1] != match_value else 0) \
		| (EDGE_S if values[idx + dim] != match_value else 0) \
		| (EDGE_W if values[idx - 1] != match_value else 0)


static func _surface_rect(material: int, phase: int) -> Rect2i:
	return Rect2i(material * TEXTURE_SIZE + (phase % 2) * TS, (phase / 2) * TS, TS, TS)


static func _edge_rect(edges: int, phase: int) -> Rect2i:
	return Rect2i(edges * TS, phase * TS, TS, TS)


## 用原草地内部的明暗形状映射六群系色板；源图轮廓绝不进入平地填充。
static func _build_surface(terrain: String) -> Image:
	var out := Image.create(TEXTURE_SIZE * 3, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	var grass: Image = _sources["main"]
	var water: Image = _sources["water"]
	for material in 3:
		var palette: Array = SURFACE_PALETTES[terrain][material]
		var dark := Color(palette[0])
		var light := Color(palette[1])
		for y in TEXTURE_SIZE:
			for x in TEXTURE_SIZE:
				var pixel := grass.get_pixel(x + TEXTURE_SIZE, y + TEXTURE_SIZE)
				var tone := clampf((pixel.v - 0.50) / 0.24, 0.0, 1.0)
				if material == 2 or (terrain == "swamp" and material == 1):
					# 水底沿用 TS 原图；少量原草纹低幅叠入，避免液体成为纯色块。
					var wave := water.get_pixel(x % water.get_width(), y % water.get_height())
					tone = clampf(wave.v * 0.60 + tone * 0.18, 0.0, 1.0)
				out.set_pixel(material * TEXTURE_SIZE + x, y, dark.lerp(light, tone))
	return out


## 原图顶部叶簇轮廓提供 1~3px 不规则边，不绘制悬崖/黑方框。
static func _shore_depth(at: int) -> int:
	return _edge_depths[posmod(at, TEXTURE_SIZE)]


static func _build_edges(terrain: String, surface: Image, water: bool) -> Image:
	var out := Image.create(16 * TS, 4 * TS, false, Image.FORMAT_RGBA8)
	for phase in 4:
		for edges in 16:
			for y in TS:
				for x in TS:
					var sx := (phase % 2) * TS + x
					var sy := (phase / 2) * TS + y
					var distance := 99
					if edges & EDGE_N: distance = mini(distance, y - _shore_depth(sx))
					if edges & EDGE_E: distance = mini(distance, TS - 1 - x - _shore_depth(sy))
					if edges & EDGE_S: distance = mini(distance, TS - 1 - y - _shore_depth(sx))
					if edges & EDGE_W: distance = mini(distance, x - _shore_depth(sy))
					var color := surface.get_pixel(TEXTURE_SIZE + sx, sy)
					if water:
						color = surface.get_pixel(TEXTURE_SIZE * 2 + sx, sy)
						if distance < 0:
							color = surface.get_pixel(sx, sy)
						elif distance <= 1:
							# 陆缘厚度与像素纹理都来自真实地被，区别于旧黑色矩形条。
							color = surface.get_pixel(sx, sy).darkened(0.15)
						elif distance <= 4:
							# 浅岸是可见液体内部的一小段，不移动权威水位/碰撞线。
							if terrain == "lava":
								color = color.lerp(Color("ffca70"), 0.58 - float(distance) * 0.06)
							else:
								color = color.lerp(surface.get_pixel(sx, sy), 0.62 - float(distance) * 0.06)
						elif distance == 5:
							color = color.lightened(0.12)
					else:
						# 草/土是同一高度的可行地面，以半透明绒边过渡，不加墙边。
						color.a = clampf(float(distance + 1) / 3.0, 0.0, 1.0)
					out.set_pixel(edges * TS + x, phase * TS + y, color)
	return out


## 出生点只画现有通路；不会拓路、移动障碍或赋予任何可达性保证。
static func is_camp_path(pos: Vector2) -> bool:
	var relative := pos - BiomeMap.spawn_pos()
	if absf(relative.x) > 480.0 or relative.y < -240.0 or relative.y > 450.0:
		return false
	for line: Array in CAMP_PATHS:
		var nearest := Geometry2D.get_closest_point_to_segment(relative, line[0], line[1])
		if relative.distance_squared_to(nearest) <= float(line[2]) * float(line[2]):
			return true
	return false


## 材质图采样：0=base 1=patch 2=water（全局瓦坐标连续）。
## 液体层真源在 ObstacleField.liquid_kind_in（世界 v5 起与阻挡/灼烧判定同源，
## 抑制区同口径——可见水与可行区不再两张皮）
static func _material(terrain: String, gtx: int, gty: int, center: Vector2,
		patch_id: String) -> int:
	if ObstacleField.liquid_kind_in(terrain, center, patch_id) != "":
		return 2
	return _ground_material(terrain, gtx, gty, center)


## 次群系用自己的地被配方，禁止把主群系材质编号直接套给次群系。
static func _ground_material(terrain: String, gtx: int, gty: int, center: Vector2) -> int:
	var rule: Dictionary = RULES[terrain]
	var seedv: int = rule["seedv"]
	var macro := _fbm(float(gtx) / 22.0, float(gty) / 22.0, seedv, 3)
	var m := 0
	var threshold := float(rule["patch_thr"])
	if terrain == "plains":
		# 安全营地以草坪衬托建筑，天然裸地在外围渐回；不把小路并进巨大泥斑。
		var camp_distance := center.distance_to(BiomeMap.spawn_pos())
		threshold += 0.45 * clampf((1100.0 - camp_distance) / 500.0, 0.0, 1.0)
	if macro >= threshold:
		m = 1
	if terrain == "plains" and is_camp_path(center):
		m = 1
	return m


# --- 图集烘焙 ---

## 主菜单旧图集源格序列（帧资产契约保留；运行时不用这些旧索引）
static func _atlas_cells() -> Array:
	var cells: Array = []
	cells.append_array(GRASS_FILL)
	cells.append_array(GRASS_DETAIL)
	cells.append_array(DIRT_FILL)
	cells.append_array(WATER_FILL)
	cells.append_array(ICE_FILL)
	cells.append_array(ICE_DETAIL)
	return cells


## 图集整体乘 alpha（交界叠绘变体）
static func _with_alpha(src: Image, factor: float) -> Image:
	var out := src.duplicate()
	for y in out.get_height():
		for x in out.get_width():
			var c: Color = out.get_pixel(x, y)
			if c.a > 0.0:
				out.set_pixel(x, y, Color(c.r, c.g, c.b, c.a * factor))
	return out


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
