## 世界群系图（纯逻辑，RefCounted，无 Node/场景树——架构铁律合规）。
## 2026-09-08 世界大地图重构：方形 3×2 六区 → 抖动网格 Voronoi + 域扭曲 fBm 的
## 犬牙交错群系斑块。80 万像素见方（端到端基础跑速约 78 分钟），出生角为家园
## 平原、威胁沿对角线分带递增，尽头是熔岩/雪原高危群系。
## 本类是"世界结构"的唯一真源：生态区域（SimRegion 装配）、地形分块绘制
## （terrain_painter）、小地图总览（generate_world_map）三方共同消费同一份
## 采样函数——边界形状/地形归属在任何消费方眼里严格一致。
## 未来联机化时随 ecology/ 整体搬服务端，坐标采样天然权威。
class_name BiomeMap
extends RefCounted

## 斑块网格数（10×10 = 100 个群系斑块，斑块间距 8 万像素 ≈ 直线跑 7.6 分钟）
const GRID_X := 10
const GRID_Y := 10
## 世界边长（像素）。基础跑速 175px/s 直线横穿 ≈ 76 分钟，对角线 ≈ 108 分钟
const WORLD_SIZE := Vector2(800000.0, 800000.0)
## 结构随机种子默认值（世界 v5，2026-09-08 种子参数化）：旧档迁移 / 离线工具 /
## 截图取证用固定种子；「新的冒险」经 configure() 掷新种子——每个存档一个全新世界
const DEFAULT_SEED := 20260908
## 当前世界种子（主线程世界装配前 configure 一次，此后只读——工作线程
## 分块绘制与主线程采样同今天一样安全）。改动 = 世界换形状，派生缓存全重置
static var _seed := DEFAULT_SEED
## 斑块种子抖动幅度（占格距比例，<0.5 保证种子留在本格内）
const JITTER := 0.36
## 域扭曲振幅（世界像素）：边界大尺度犬牙的深度；频率 WARP_FREQ 约 3 个周期
const WARP_AMP := 24000.0
const WARP_FREQ := 3.0

## 地形信息表：显示名 / 威胁系数 / 承载。threat 与 CombatBandMath.TERRAIN_BANDS
## 一致（balance_test 有一致性断言防漂移）；capacity 沿用 v3 六区实测值
const TERRAIN_INFO := {
	"plains": {"name": "平原", "threat": 1.0, "capacity": 10},
	"forest": {"name": "林地", "threat": 1.3, "capacity": 13},
	"swamp": {"name": "沼泽", "threat": 1.7, "capacity": 10},
	"snow": {"name": "雪原", "threat": 1.7, "capacity": 11},
	"hill": {"name": "丘陵", "threat": 2.2, "capacity": 12},
	"lava": {"name": "熔岩地带", "threat": 3.0, "capacity": 10},
}

## 地形材质噪声种子（与旧 generate_terrain.gd 的 BIOMES.seedv 一脉相承，
## terrain_painter 按此取每地形的材质/烘焙规则）
const TERRAIN_NOISE_SEED := {
	"plains": 11, "forest": 22, "snow": 33, "swamp": 44, "hill": 55, "lava": 66,
}

## 地形总览色（小地图底图与 world_map 生成工具共用；纯数据，Color 是核心数学类型）
## 2026-09-10 对齐自建卡通 PALETTE：取值=各群系卡通地表基础色（generate_tiles/
## generate_creatures 的 GRASS/ICE/DIRT 及群系烘焙色族），三档绿按明度拉开区分
const TERRAIN_COLORS := {
	"plains": Color(0.427, 0.702, 0.290),   # 卡通草 6db34a（亮黄绿）
	"forest": Color(0.247, 0.490, 0.200),   # 森林深绿 3f7d33
	"snow": Color(0.910, 0.949, 0.965),     # 卡通冰 e8f2f6
	"swamp": Color(0.443, 0.471, 0.298),    # 沼泽橄榄绿 71784c
	"hill": Color(0.710, 0.529, 0.310),     # 卡通泥 b5874f
	"lava": Color(0.478, 0.196, 0.149),     # 熔岩暗红 7a3226
}

static var _patches_cache: Array = []
static var _terrain_by_id := {}
## 斑块种子点缓存（field_at 每次采样要查 9 个邻格种子，地形绘制器每瓦一次——
## 不缓存的话 hash 重算是分块绘制的最大热点）
static var _seed_cache := PackedVector2Array()
## 区域归属栅格缓存（patch_polygons 提取用）：int(resolution) -> Dictionary
static var _raster_cache := {}
## 斑块边界多边形缓存："int(resolution)" -> {id -> Array[PackedVector2Array]}
## 全斑块单遍提取一次性缓存（patch_polygons 从中取单 id，见 _patch_loops_all）
static var _loops_all_cache := {}


## 种子切换入口（世界装配前主线程调用）：重置全部派生缓存，此后同种子确定性。
## 返回切换后的种子便于链式断言
static func configure(seed: int) -> int:
	_seed = seed
	_patches_cache = []
	_terrain_by_id = {}
	_seed_cache = PackedVector2Array()
	_raster_cache = {}
	_loops_all_cache = {}
	return _seed


## 当前世界种子（存档 world_seed 的来源）
static func current_seed() -> int:
	return _seed


static func cell_size() -> Vector2:
	return Vector2(WORLD_SIZE.x / float(GRID_X), WORLD_SIZE.y / float(GRID_Y))


## 斑块种子点（格心 + 确定性抖动；抖动 <0.5 格，种子恒在本格内）。
## 结果进静态缓存（首次填充整表，此后 O(1) 数组读）
static func seed_point(i: int, j: int) -> Vector2:
	if _seed_cache.is_empty():
		_seed_cache.resize(GRID_X * GRID_Y)
		var cs := cell_size()
		for jj in GRID_Y:
			for ii in GRID_X:
				var dx := (_hash2(ii, jj, _seed + 11) - 0.5) * 2.0 * JITTER * cs.x
				var dy := (_hash2(ii, jj, _seed + 12) - 0.5) * 2.0 * JITTER * cs.y
				_seed_cache[jj * GRID_X + ii] = Vector2(
					(float(ii) + 0.5) * cs.x + dx, (float(jj) + 0.5) * cs.y + dy)
	return _seed_cache[j * GRID_X + i]


## 域扭曲：低频 fBm 双通道偏移采样点——Voronoi 直边被揉成犬牙交错的有机边界。
## 邻域搜索半径约束：JITTER + WARP_AMP/格距 必须 < 1.0（见 field_at 注释），
## 调参时两者同改需重新核对此不等式
static func _warped(p: Vector2) -> Vector2:
	var nx := p.x / WORLD_SIZE.x * WARP_FREQ
	var ny := p.y / WORLD_SIZE.y * WARP_FREQ
	var wx := _fbm(nx, ny, _seed + 21, 2) - 0.5
	var wy := _fbm(nx + 7.31, ny + 3.17, _seed + 22, 2) - 0.5
	return Vector2(p.x + wx * 2.0 * WARP_AMP, p.y + wy * 2.0 * WARP_AMP)


## 采样点所属斑块：最近种子（域扭曲坐标下）。
## 搜索窗 3×3 已足够：抖动 0.36 格 + 扭曲 ≤ 约 0.3 格 < 1 格，
## 最近种子不可能落在采样格的 ±1 格之外（WARP_AMP/2 若超过 0.64 格距需扩窗）
static func region_id_at(p: Vector2) -> String:
	return field_at(p)["id1"]


## 采样点的双最近斑块与距离平方（地形过渡混合、生态归属共用）：
## {"id1": 主斑块, "d1": 主距离², "id2": 次斑块, "d2": 次距离²}
static func field_at(p: Vector2) -> Dictionary:
	var q := _warped(p)
	var cs := cell_size()
	var ci := clampi(int(q.x / cs.x), 0, GRID_X - 1)
	var cj := clampi(int(q.y / cs.y), 0, GRID_Y - 1)
	var id1 := ""
	var d1 := INF
	var id2 := ""
	var d2 := INF
	for dj in 3:
		for di in 3:
			var i := ci + di - 1
			var j := cj + dj - 1
			if i < 0 or j < 0 or i >= GRID_X or j >= GRID_Y:
				continue
			var s := seed_point(i, j)
			var dx := q.x - s.x
			var dy := q.y - s.y
			var d := dx * dx + dy * dy
			if d < d1:
				d2 = d1
				id2 = id1
				d1 = d
				id1 = patch_id(i, j)
			elif d < d2:
				d2 = d
				id2 = patch_id(i, j)
	return {"id1": id1, "d1": d1, "id2": id2, "d2": d2}


## 采样点主导地形（小地图总览 / 环境粒子切换用）
static func terrain_at(p: Vector2) -> String:
	return terrain_of_patch(region_id_at(p))


## 斑块 id → 地形（O(1) 查表；地形绘制器每瓦采样高频调用，线性扫斑块不可接受）
static func terrain_of_patch(id: String) -> String:
	if _terrain_by_id.is_empty():
		for def: Dictionary in patches():
			_terrain_by_id[def["id"]] = def["terrain"]
	return _terrain_by_id.get(id, "plains")


static func patch_id(i: int, j: int) -> String:
	return "p_%d_%d" % [i, j]


static func has_patch(id: String) -> bool:
	return not patch(id).is_empty()


## 单斑块定义（空字典 = id 不存在）
static func patch(id: String) -> Dictionary:
	for def: Dictionary in patches():
		if def["id"] == id:
			return def
	return {}


## 出生角斑块（(0,0) 格，地形强制平原——新手安全区）
static func spawn_patch() -> Dictionary:
	return patches()[0]


static func spawn_pos() -> Vector2:
	return spawn_patch()["center"]


## 全部斑块定义（WorldConfig.region_defs() 的真源）。确定性：同种子同结果。
## 字段与旧 REGIONS 完全同构：id/name/terrain/threat/capacity/center/neighbors，
## 额外带 i/j（网格位）与 size（名义覆盖范围，锚点撒布/名义包围盒用）
static func patches() -> Array:
	if not _patches_cache.is_empty():
		return _patches_cache
	var cs := cell_size()
	var terrains: Array = []
	for j in GRID_Y:
		for i in GRID_X:
			terrains.append(_terrain_for_cell(i, j))
	# 兜底：带噪声分带在极端 seed 下可能让某地形零斑块（该地形物种将无处生存），
	# 从中带借格子补齐——确定性 seed 下只是保险丝，正常参数不会触发
	for terrain: String in TERRAIN_INFO:
		if not terrains.has(terrain):
			for idx in terrains.size():
				var i := idx % GRID_X
				var j := idx / GRID_X
				if terrains[idx] == "swamp" or terrains[idx] == "hill":
					terrains[idx] = terrain
					break
	var list: Array = []
	for j in GRID_Y:
		for i in GRID_X:
			var terrain: String = terrains[j * GRID_X + i]
			var info: Dictionary = TERRAIN_INFO[terrain]
			var neighbors: Array[String] = []
			for dj in 3:
				for di in 3:
					if di == 1 and dj == 1:
						continue
					var ni := i + di - 1
					var nj := j + dj - 1
					if ni >= 0 and nj >= 0 and ni < GRID_X and nj < GRID_Y:
						neighbors.append(patch_id(ni, nj))
			list.append({
				"id": patch_id(i, j),
				"i": i,
				"j": j,
				"name": info["name"],
				"terrain": terrain,
				"threat": info["threat"],
				"capacity": info["capacity"],
				"center": seed_point(i, j),
				"size": cs,
				"neighbors": neighbors,
			})
	_patches_cache = list
	return list


## 地形分配：对角进度 dn∈[0,1]（出生角 0 → 远角 1）分带 + 每格噪声扰动。
## 带内按 hash 在候选地形里挑——带间犬牙（±0.07 dn ≈ ±1.4 格）+ 域扭曲边界
## 共同构成"交融"而非"直线分界"
static func _terrain_for_cell(i: int, j: int) -> String:
	if i + j <= 1:
		return "plains"  # 家园角 2×2 强制平原（新手安全区的结构性保证）
	var s := seed_point(i, j)
	var dn := (s.x / WORLD_SIZE.x + s.y / WORLD_SIZE.y) * 0.5
	dn += (_hash2(i, j, _seed + 771) - 0.5) * 0.10
	var pick := _hash2(i, j, _seed + 772)
	if dn < 0.16:
		return "plains" if pick < 0.62 else "forest"
	if dn < 0.34:
		if pick < 0.42:
			return "forest"
		return "plains" if pick < 0.72 else "swamp"
	if dn < 0.55:
		if pick < 0.32:
			return "swamp"
		if pick < 0.62:
			return "hill"
		return "snow" if pick < 0.84 else "forest"
	if dn < 0.75:
		if pick < 0.36:
			return "hill"
		return "snow" if pick < 0.70 else "lava"
	return "lava" if pick < 0.52 else "snow"


## 每种地形的全部斑块（种群撒布/测试取样用）
static func patches_of_terrain(terrain: String) -> Array:
	var out: Array = []
	for def: Dictionary in patches():
		if def["terrain"] == terrain:
			out.append(def)
	return out


## 指定地形中距出生角最远的斑块（Boss 盘踞地：旅程尽头的顶点）
static func farthest_patch(terrain: String) -> Dictionary:
	var best: Dictionary = {}
	var best_d := -1.0
	var spawn := spawn_pos()
	for def: Dictionary in patches_of_terrain(terrain):
		var d := (def["center"] as Vector2).distance_squared_to(spawn)
		if d > best_d:
			best_d = d
			best = def
	return best


# --- 世界 v5：区域栅格与斑块边界多边形（区域 Area2D 用，纯逻辑） ---

## 区域归属栅格（region_id_at 同源采样，格心取值）：{"cells","cols","rows","resolution"}。
## 首次调用全图采样（1000px 步长 ≈ 64 万次，加载期后台线程调用为宜，~1-2s），
## 同种子缓存。相邻斑块的边界多边形共享此栅格 → 无缝隙无重叠，Area2D 不会
## 出现"缝隙双跳"或"重叠双触发"
static func region_raster(resolution: float = 1000.0) -> Dictionary:
	var key := int(resolution)
	if _raster_cache.has(key):
		return _raster_cache[key]
	var cols := int(ceil(WORLD_SIZE.x / resolution))
	var rows := int(ceil(WORLD_SIZE.y / resolution))
	var cells := PackedInt32Array()
	cells.resize(cols * rows)
	var cs := cell_size()
	for gy in rows:
		for gx in cols:
			cells[gy * cols + gx] = _raster_idx_at(gx, gy, resolution, cs)
	var data := {"cells": cells, "cols": cols, "rows": rows, "resolution": resolution}
	_raster_cache[key] = data
	return data


## 栅格快速路径：与 field_at（经 region_id_at）同一数学——域扭曲 + 3×3 最近
## 种子、同样的比较顺序（严格小于=先到者赢平局）——但全程标量、直出斑块
## 下标，免掉 64 万格 × {Vector2、结果 Dictionary、String id、String 散列}
## 的容器开销（实测占栅格采样耗时的大头）。语义与 field_at 逐位一致。
static func _raster_idx_at(gx: int, gy: int, resolution: float, cs: Vector2) -> int:
	var px := (float(gx) + 0.5) * resolution
	var py := (float(gy) + 0.5) * resolution
	var nx := px / WORLD_SIZE.x * WARP_FREQ
	var ny := py / WORLD_SIZE.y * WARP_FREQ
	var qx := px + (_fbm(nx, ny, _seed + 21, 2) - 0.5) * 2.0 * WARP_AMP
	var qy := py + (_fbm(nx + 7.31, ny + 3.17, _seed + 22, 2) - 0.5) * 2.0 * WARP_AMP
	var ci := clampi(int(qx / cs.x), 0, GRID_X - 1)
	var cj := clampi(int(qy / cs.y), 0, GRID_Y - 1)
	var best_d := INF
	var best_i := -1
	var best_j := -1
	for dj in 3:
		for di in 3:
			var i := ci + di - 1
			var j := cj + dj - 1
			if i < 0 or j < 0 or i >= GRID_X or j >= GRID_Y:
				continue
			var s := seed_point(i, j)
			var dx := qx - s.x
			var dy := qy - s.y
			var d := dx * dx + dy * dy
			if d < best_d:
				best_d = d
				best_i = i
				best_j = j
	return best_j * GRID_X + best_i


## 斑块边界多边形（世界坐标顶点环，已合并共线点；通常 1 环，犬牙极端时多环
## ——对 Area2D 等价）。阶梯轮廓与 region_of_point 的偏差 ≤ resolution，
## 远小于斑块尺度（8 万 px）。marching-squares 提取：对栅格中"本斑块 vs 其他"
## 的边界边定向（内域恒在行进方向左侧，y 向下坐标系），再首尾链成环——
## 定向一致保证每个顶点入度=出度，链环必然闭合。
## 全斑块单遍提取（_patch_loops_all）：一次栅格扫描同时收集 100 个斑块的边界边，
## 逐斑块 640k 格重扫的历史实现实测 1.3s/百次——曾是区域 Area 装配 ~6s 预热的
## 次要大头。
static func patch_polygons(id: String, resolution: float = 1000.0) -> Array:
	return _patch_loops_all(resolution).get(id, [])


## 单遍多斑块边界提取：一次行主序栅格扫描，对每格按上/下/左/右的固定顺序把
## 与异斑块相邻的有向边压入所属斑块的边表——与历史逐斑块实现的插入顺序逐位
## 一致，链环结果逐位相同（_chain_loops 依赖插入顺序的确定性）。
static func _patch_loops_all(resolution: float) -> Dictionary:
	var key := int(resolution)
	if _loops_all_cache.has(key):
		return _loops_all_cache[key]
	var raster := region_raster(resolution)
	var cells: PackedInt32Array = raster["cells"]
	var cols: int = raster["cols"]
	var rows: int = raster["rows"]
	var edges := {}  # 斑块下标 -> 边表（Vector2i 起点 -> [终点,...]）
	for gy in rows:
		for gx in cols:
			var v := cells[gy * cols + gx]
			if v < 0:
				continue
			var ed: Dictionary = edges.get_or_add(v, {})
			if gy == 0 or cells[(gy - 1) * cols + gx] != v:
				_push_edge(ed, Vector2i(gx + 1, gy), Vector2i(gx, gy))
			if gy == rows - 1 or cells[(gy + 1) * cols + gx] != v:
				_push_edge(ed, Vector2i(gx, gy + 1), Vector2i(gx + 1, gy + 1))
			if gx == 0 or cells[gy * cols + gx - 1] != v:
				_push_edge(ed, Vector2i(gx, gy), Vector2i(gx, gy + 1))
			if gx == cols - 1 or cells[gy * cols + gx + 1] != v:
				_push_edge(ed, Vector2i(gx + 1, gy + 1), Vector2i(gx + 1, gy))
	var patches_list := patches()
	var out := {}
	for idx: int in edges:
		out[patches_list[idx]["id"]] = _chain_loops(edges[idx], resolution)
	_loops_all_cache[key] = out
	return out


static func _push_edge(edges: Dictionary, from: Vector2i, to: Vector2i) -> void:
	if edges.has(from):
		edges[from].append(to)
	else:
		edges[from] = [to]


static func _chain_loops(edges: Dictionary, resolution: float) -> Array:
	var loops: Array = []
	while not edges.is_empty():
		var start: Vector2i = edges.keys()[0]
		var pts := PackedVector2Array()
		var cur := start
		while true:
			pts.append(Vector2(cur) * resolution)
			var outs: Array = edges[cur]
			var nxt: Vector2i = outs.pop_back()
			if outs.is_empty():
				edges.erase(cur)
			cur = nxt
			if cur == start:
				break
		var simplified := _simplify_loop(pts)
		if simplified.size() >= 3:
			loops.append(simplified)
	return loops


## 去除共线顶点（阶梯轮廓 4 方向直角，合并后点数约降 4 倍）
static func _simplify_loop(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := pts.size()
	if n < 3:
		return out
	for i in n:
		var prev := pts[(i - 1 + n) % n]
		var next := pts[(i + 1) % n]
		var d1 := pts[i] - prev
		var d2 := next - pts[i]
		if absf(d1.x * d2.y - d1.y * d2.x) > 0.5:  # 叉积非零 = 转角，保留
			out.append(pts[i])
	return out


## --- 凸分解安全环（区域 Area2D 触发体用；tools/convex_probe.gd 守闸）---

## 栅格边界环偶发凸分解失败（鞍点续链可产出引擎无法分convex的环，约 1~2% 随机
## 种子命中，实证坏种子 1999437034）——失败即不生成碰撞形状，该区域触发体静默
## 缺失：无进区播报/不换 BGM/无威胁警告。只对失败环做 RDP 逐级简化（最后兜底
## 凸包），可分解的原样返回，不改 patch_polygons 真源几何。纯逻辑静态可测。
static func collision_safe_loop(loop: PackedVector2Array) -> PackedVector2Array:
	if not Geometry2D.decompose_polygon_in_convex(loop).is_empty():
		return loop
	for epsilon in [400.0, 800.0, 1600.0]:
		var simplified := _rdp_closed(loop, epsilon)
		if simplified.size() >= 3 and not Geometry2D.decompose_polygon_in_convex(simplified).is_empty():
			push_warning("区域边界环凸分解失败，已简化 %d→%d 点（epsilon=%.0f）" % [
					loop.size(), simplified.size(), epsilon])
			return simplified
	push_warning("区域边界环简化后仍无法凸分解（%d 点），该区域改用凸包近似" % loop.size())
	return Geometry2D.convex_hull(loop)


## 闭环 RDP：取与首点最远的点拆两条链各自简化后拼接（隐式闭合，端点必保留）
static func _rdp_closed(loop: PackedVector2Array, epsilon: float) -> PackedVector2Array:
	var n := loop.size()
	if n < 5:
		return loop
	var b := 0
	var best := -1.0
	for i in n:
		var d := loop[i].distance_squared_to(loop[0])
		if d > best:
			best = d
			b = i
	var first := _rdp_chain(loop.slice(0, b + 1), epsilon)
	var second := _rdp_chain(loop.slice(b, n) + PackedVector2Array([loop[0]]), epsilon)
	var out := PackedVector2Array(first)
	out.append_array(second.slice(1, second.size() - 1))
	return out


## 开链 RDP（Ramer–Douglas–Peucker，首尾点保留）
static func _rdp_chain(pts: PackedVector2Array, epsilon: float) -> PackedVector2Array:
	var n := pts.size()
	if n < 3:
		return pts
	var anchor := pts[0]
	var end_pt := pts[n - 1]
	var seg := end_pt - anchor
	var seg_len2 := maxf(seg.length_squared(), 0.0001)
	var worst_d := -1.0
	var worst_i := -1
	for i in range(1, n - 1):
		var t := clampf((pts[i] - anchor).dot(seg) / seg_len2, 0.0, 1.0)
		var d := anchor + seg * t - pts[i]
		if d.length_squared() > worst_d:
			worst_d = d.length_squared()
			worst_i = i
	if worst_d <= epsilon * epsilon:
		return PackedVector2Array([anchor, end_pt])
	var left := _rdp_chain(pts.slice(0, worst_i + 1), epsilon)
	var right := _rdp_chain(pts.slice(worst_i, n), epsilon)
	var out := PackedVector2Array(left)
	out.append_array(right.slice(1))
	return out


# --- 确定性噪声（与 tools/generate_terrain.gd 同源，行为一致便于材质层复用） ---

## 整数坐标散列 → [0,1)
static func _hash2(x: int, y: int, s: int) -> float:
	var h: int = x * 374761393 + y * 668265263 + s * 2246822519
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0x7FFFFFFF) / 2147483647.0


## value noise（双线性插值 + smoothstep）
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


## 分形叠加噪声（octaves 层，频率倍增振幅减半）
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
