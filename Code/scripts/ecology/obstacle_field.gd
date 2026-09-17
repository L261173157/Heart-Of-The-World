## 世界障碍场（纯逻辑，RefCounted，无 Node/场景树——架构铁律合规）。
## 世界 v5（2026-09-08）："哪里有障碍"的唯一真相——障碍瓦片层（视觉/物理/
## 导航/遮挡四件套）、生态选点校验（营地/复活/子代出生）、寻路连通性测试
## 三方共同消费同一份采样，表现层不允许自造障碍数据。
## 生成：FastNoiseLite 确定性噪声（团块 clump / 岩脊 ridged / 选型 pick 三通道，
## 域扭曲原生），按群系差异化配方——平原稀疏保风筝、森林树墙走廊、丘陵岩脊
## 峡谷、雪原冰刺、沼泽枯树、熔岩棘刺。种子派生自 BiomeMap.current_seed()
## （configure 懒重建），同种子逐位确定。
## 抑制区：斑块中心 PATCH_CLEAR 600px / 出生点 SPAWN_CLEAR 1200px 恒空——
## 复活点与出生落点的结构性保证（生态选点另有 blocks() 校验兜底）。
class_name ObstacleField
extends RefCounted

## 障碍格边长（px）：与障碍瓦片层的瓦片尺寸一致（na_tileset 16px 素材 ×2）
const CELL := 32.0
## 512px 地形块 = 16×16 障碍格
const CHUNK_CELLS := 16
## 斑块中心净空半径（复活点所在）
const PATCH_CLEAR := 600.0
## 出生点净空半径（新手安全区的视觉保底）
const SPAWN_CLEAR := 1200.0

## 障碍类型表：碰撞半径（px）/ 是否高大（y-sort 树冠遮挡 + 阴影投射）
## 半径 < CELL：格间留缝，自由格 2 格宽（64px）必然可过 20px 直径的怪/玩家
const KIND_INFO := {
	## 半径约束：导航洞 = 1 格（32px），怪 NavigationAgent 半径 ~12 ——
	## r ≤ 10 时两侧余隙 12+10 < 32 不卡边（曾实测 r14 的岩石让追击怪
	## 贴着导航路径边缘物理卡死在 202px 处；水例外走 2 格洞见 nav_tile_layer）
	"tree": {"r": 9.0, "tall": true},
	"big_tree": {"r": 10.0, "tall": true},
	"pine": {"r": 9.0, "tall": true},
	"deadtree": {"r": 8.0, "tall": true},
	"rock": {"r": 10.0, "tall": false},
	"boulder": {"r": 11.0, "tall": false},
	"ice": {"r": 10.0, "tall": false},
	"crystal": {"r": 9.0, "tall": false},
	"bones": {"r": 8.0, "tall": false},
	## 深水阻挡（世界 v5 液体场）：贴图透明——地面本来就画着水，只补碰撞
	"water": {"r": 14.0, "tall": false},
	## 城塞墙（美术 v5 M-B Boss 地牢）：整格实心墙（r15 填满 32px 格），
	## 不可破坏——永久地形骨架，与树/巨岩同等待遇
	"castle": {"r": 15.0, "tall": false},
}

## kind → 障碍图集格坐标（tools/generate_obstacle_tileset.gd 的图集布局同源，
## sim_test 有键集一致性断言防两边漂移）
const KIND_ATLAS := {
	"tree": Vector2i(0, 0), "big_tree": Vector2i(1, 0), "pine": Vector2i(2, 0),
	"deadtree": Vector2i(0, 1), "rock": Vector2i(1, 1), "boulder": Vector2i(2, 1),
	"ice": Vector2i(0, 2), "crystal": Vector2i(1, 2), "bones": Vector2i(2, 2),
	"water": Vector2i(0, 3),
	"castle": Vector2i(1, 3),
}

# --- Boss 城塞 / 地牢（美术 v5 M-B）---
## 高威胁地貌距出生角最远斑块中心 = 城堡围合竞技场（Boss 盘踞处）：
## 外墙 castle 格一圈 + 南侧 2 格门洞，内腔恒空（落在斑块 600px 抑制区内，
## 墙格在抑制判定之前返回）。结构与种子确定性同源
const DUNGEON_TERRAINS := ["hill", "lava"]
const DUNGEON_KIND := "castle"
## 半宽/半高（障碍格）：外墙 13×9 格 ≈ 416×288px 竞技场
const DUNGEON_HALF := Vector2i(6, 4)
## 南墙（+y）门洞半宽：门洞 2 格宽，玩家与怪物均可通行
const DUNGEON_DOOR_HALF := 1
## 城塞注册表（种子派生缓存）：patch_id → {center, terrain, boss}
static var _dungeons := {}

## 液体规则（世界 v5，真源在此——terrain_painter 的水材质层消费同一函数，
## 可见水与可行区不再两张皮）：snow/hill 深水阻挡、lava 熔岩池灼烧（可通行，
## 玩家站立掉血见 player 的环境伤）；plains/forest/swamp 无液体层（沼泽死水是
## patch 材质浅水，视觉可踩）。噪声与 painter 旧实现逐行同源（BiomeMap._fbm
## 家族），阈值一致保证存量世界的水位不变
const LIQUID_RULES := {
	"snow": {"water_thr": 0.78},
	"hill": {"water_thr": 0.86},
	"lava": {"water_thr": 0.72},
}
## 深水阻挡比可见水更保守：可见水的边缘 ~4% 噪声带宽是可趟的浅水滩，只有
## 核心深水不可通行——按可见水全覆盖阻挡会把雪原切成湖群岛
const WATER_BLOCK_MARGIN := 0.04
## 可破坏障碍类型（玩家普攻/法弹摧毁开路；树/巨岩是永久地形骨架不可破坏）
const DESTRUCTIBLE := ["rock", "bones", "crystal", "ice"]
## 可破坏障碍耐久（普攻/法弹次数）
const OBSTACLE_HP := 2
## 破坏掉落：概率与金币区间（碎石里摸到零钱的小惊喜）
const DESTROY_GOLD_CHANCE := 0.3
const DESTROY_GOLD_RANGE := [2, 6]

## 群系配方：mode = clump（团块阈值）或 ridge（岩脊波峰）；
## thr = 归一化 (n+1)/2 的障碍判定阈（覆盖率主旋钮，sim_test 分带守闸）；
## kinds = 类型池（pick 噪声按格选型）。走廊保证：团块频率与阈值使自由通道
## ≥2 格宽（64px），叠加单格死点填充（is_nav_blocked）杜绝 1 格缝
const RECIPES := {
	"plains": {"mode": "clump", "thr": 0.800, "kinds": ["rock", "tree"]},
	"forest": {"mode": "clump", "thr": 0.630, "kinds": ["tree", "big_tree"]},
	"snow": {"mode": "clump", "thr": 0.720, "kinds": ["pine", "ice"]},
	"swamp": {"mode": "clump", "thr": 0.700, "kinds": ["deadtree", "rock"]},
	"hill": {"mode": "ridge", "thr": 0.66, "gate": 0.38, "kinds": ["boulder", "rock"]},
	"lava": {"mode": "clump", "thr": 0.720, "kinds": ["crystal", "bones"]},
}

static var _seed_cached := -2147483648
static var _clump := FastNoiseLite.new()
static var _ridge := FastNoiseLite.new()
static var _pick := FastNoiseLite.new()
## 斑块中心缓存（抑制区查询 O(1)；patch(id) 是线性扫，格级采样吃不消）
static var _center_by_id := {}
## 分块结果缓存（格级采样的 region/噪声查询在 GDScript 侧是大头，512px 块
## 一次算好 18×18 边距格，铺格层/导航层/测试共享；种子切换时随 _ensure 重置）
static var _cells_chunk_cache := {}
static var _nav_chunk_cache := {}
## 摧毁覆盖层（玩家破坏的障碍格，运行期真相；存档经 GameState 往返）与
## 本局耐久（重开存档恢复满耐久）
static var _destroyed := {}
static var _obstacle_hp := {}


## 种子懒重建：BiomeMap.configure 之后首次采样自动生效（主线程调用；
## 表现层/生态选点/测试均为单线程消费）
static func _ensure() -> void:
	var s := BiomeMap.current_seed()
	if _seed_cached == s:
		return
	_seed_cached = s
	_clump = FastNoiseLite.new()
	_clump.seed = hash("obstacle|%d|clump" % s)
	_clump.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_clump.frequency = 1.0 / 2400.0  # 团块尺度 ~2400px（走廊与之同尺度）
	_clump.fractal_octaves = 3
	_clump.domain_warp_enabled = true
	_clump.domain_warp_amplitude = 120.0
	_ridge = FastNoiseLite.new()
	_ridge.seed = hash("obstacle|%d|ridge" % s)
	_ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ridge.fractal_octaves = 2
	_ridge.frequency = 1.0 / 5600.0  # 岩脊走向的大尺度
	_pick = FastNoiseLite.new()
	_pick.seed = hash("obstacle|%d|pick" % s)
	_pick.noise_type = FastNoiseLite.TYPE_CELLULAR
	_pick.frequency = 1.0 / 480.0  # 选型斑块 ~480px（同类成小片，不逐格花斑）
	_center_by_id = {}
	for def: Dictionary in BiomeMap.patches():
		_center_by_id[def["id"]] = def["center"]
	_dungeons = {}
	for terrain: String in DUNGEON_TERRAINS:
		var far: Dictionary = BiomeMap.farthest_patch(terrain)
		if far.is_empty():
			continue
		_dungeons[far["id"]] = {"center": far["center"], "terrain": terrain}
	_cells_chunk_cache = {}
	_nav_chunk_cache = {}
	_destroyed = {}
	_obstacle_hp = {}


## 全部城塞（表现层宝箱/播报消费；boss 名由表现层经 WorldConfig.TERRAIN_BOSSES
## 就地配对——ecology 不反向依赖 main）：[{center, terrain, patch_id}]
static func dungeons() -> Array:
	_ensure()
	var out: Array = []
	for patch_id: String in _dungeons:
		var d: Dictionary = _dungeons[patch_id].duplicate()
		d["patch_id"] = patch_id
		out.append(d)
	return out


## 城塞内采样（wall / inner / ""）：cell 为障碍格坐标
static func dungeon_sample(cell: Vector2i) -> String:
	if _dungeons.is_empty():
		_ensure()
	for patch_id: String in _dungeons:
		var center: Vector2 = _dungeons[patch_id]["center"]
		var cc := Vector2i(floori(center.x / CELL), floori(center.y / CELL))
		var dx: int = absi(cell.x - cc.x)
		var dy: int = absi(cell.y - cc.y)
		if dx > DUNGEON_HALF.x or dy > DUNGEON_HALF.y:
			continue
		var on_wall: bool = dx == DUNGEON_HALF.x or dy == DUNGEON_HALF.y
		if not on_wall:
			return "inner"
		# 南墙门洞（+y 侧）：2 格宽居中
		if cell.y - cc.y == DUNGEON_HALF.y and dx <= DUNGEON_DOOR_HALF:
			return ""
		return "wall"
	return ""


## 障碍格采样：{kind, r, tall} 或空字典（可通行）。坐标为障碍格坐标
## （cell = floor(pos / CELL)），逐格确定性
static func sample_cell(cell: Vector2i) -> Dictionary:
	_ensure()
	if _destroyed.has(cell):
		return {}  # 玩家已摧毁（真相覆盖层优先于一切配方）
	# Boss 城塞（先于抑制区——墙落在斑块 600px 净空内但必须存在；内腔恒空）
	match dungeon_sample(cell):
		"wall":
			var wall: Dictionary = KIND_INFO[DUNGEON_KIND]
			return {"kind": DUNGEON_KIND, "r": wall["r"], "tall": wall["tall"]}
		"inner":
			return {}
	var center := (Vector2(cell) + Vector2(0.5, 0.5)) * CELL
	# 抑制区：出生点 / 斑块中心净空（先于一切配方——保底优先）
	if center.distance_squared_to(BiomeMap.spawn_pos()) < SPAWN_CLEAR * SPAWN_CLEAR:
		return {}
	var patch_id := BiomeMap.region_id_at(center)
	var patch_center: Variant = _center_by_id.get(patch_id, null)
	if patch_center != null \
			and center.distance_squared_to(patch_center) < PATCH_CLEAR * PATCH_CLEAR:
		return {}
	var terrain := BiomeMap.terrain_of_patch(patch_id)
	# 深水阻挡（液体真源；熔岩池不阻挡——灼烧走玩家的环境伤通道）
	if liquid_kind_in(terrain, center, patch_id, true) == "water":
		return {"kind": "water", "r": KIND_INFO["water"]["r"], "tall": false}
	var recipe: Dictionary = RECIPES.get(terrain, {})
	if recipe.is_empty():
		return {}
	var v := 0.0
	if recipe["mode"] == "ridge":
		v = (_ridge.get_noise_2d(center.x, center.y) + 1.0) * 0.5
		if v < float(recipe["thr"]):
			return {}
		# 分段岩脊：clump 门控在山脊上开出缺口（峡谷通道）。不加门控的话
		# FRACTAL_RIDGED 的连续波峰会横贯斑块，自由区被切成互不相通的孤岛
		# （连通性守闸：sim_test _largest_free_component 曾实测 55% 捂住此问题）
		if (_clump.get_noise_2d(center.x, center.y) + 1.0) * 0.5 < float(recipe["gate"]):
			return {}
	else:
		v = (_clump.get_noise_2d(center.x, center.y) + 1.0) * 0.5
	if v < float(recipe["thr"]):
		return {}
	# 类型选取：cellular 噪声哈希到类型池下标（同类成片）
	var kinds: Array = recipe["kinds"]
	var pick := (_pick.get_noise_2d(center.x, center.y) + 1.0) * 0.5
	var kind: String = kinds[clampi(int(pick * kinds.size()), 0, kinds.size() - 1)]
	var info: Dictionary = KIND_INFO[kind]
	return {"kind": kind, "r": info["r"], "tall": info["tall"]}


static func is_obstacle_cell(cell: Vector2i) -> bool:
	return not sample_cell(cell).is_empty()


## 寻路/导航格是否可走：障碍格或单格死点（自由格 4 邻 ≥3 阻塞）。
## 死点填充防止导航走 1 格缝而物理半径过不去的卡位，也消掉对角穿缝
static func is_nav_blocked(cell: Vector2i) -> bool:
	if is_obstacle_cell(cell):
		return true
	var blocked := 0
	blocked += int(is_obstacle_cell(cell + Vector2i(1, 0)))
	blocked += int(is_obstacle_cell(cell + Vector2i(-1, 0)))
	blocked += int(is_obstacle_cell(cell + Vector2i(0, 1)))
	blocked += int(is_obstacle_cell(cell + Vector2i(0, -1)))
	return blocked >= 3


## 点位通行性（生态选点校验用）：pos 附近 r 半径内无障碍碰撞体。
## 扫 pos 所在格及邻格（半径 + 格碰撞半径跨到的格），确定性
static func blocks(pos: Vector2, r: float = 0.0) -> bool:
	_ensure()
	var c0 := Vector2i(floori((pos.x - r - CELL) / CELL), floori((pos.y - r - CELL) / CELL))
	var c1 := Vector2i(floori((pos.x + r + CELL) / CELL), floori((pos.y + r + CELL) / CELL))
	for cy in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var cell := Vector2i(cx, cy)
			var s := sample_cell(cell)
			if s.is_empty():
				continue
			var center := (Vector2(cell) + Vector2(0.5, 0.5)) * CELL
			if center.distance_to(pos) < r + float(s["r"]) + 2.0:
				return true
	return false


## 把点位推到最近可通行处（老档 spawn_pos/玩家位置落进新障碍时的 nudge）：
## 8 方向 × 递增距离尝试，全败返回原位（由物理 depenetration 兜底）
static func nudge_free(pos: Vector2, r: float = 12.0) -> Vector2:
	if not blocks(pos, r):
		return pos
	for dist: float in [40.0, 80.0, 160.0, 320.0, 640.0]:
		for k in 8:
			var ang := TAU * float(k) / 8.0
			var cand := pos + Vector2(cos(ang), sin(ang)) * dist
			if not blocks(cand, r):
				return cand
	return pos


## 地形块（512px）的障碍格清单：[{cell, kind, r, tall}]。
## 障碍瓦片层铺格的唯一数据入口（含碰撞/贴图/遮挡所需元数据），分块缓存
static func cells_of_chunk(chunk_origin_px: Vector2i) -> Array:
	var key := Vector2i(chunk_origin_px.x >> 9, chunk_origin_px.y >> 9)
	if _cells_chunk_cache.has(key):
		return _cells_chunk_cache[key]
	var base := Vector2i(chunk_origin_px.x >> 5, chunk_origin_px.y >> 5)
	var out: Array = []
	for dy in CHUNK_CELLS:
		for dx in CHUNK_CELLS:
			var cell := base + Vector2i(dx, dy)
			var s := sample_cell(cell)
			if s.is_empty():
				continue
			out.append({"cell": cell, "kind": s["kind"], "r": s["r"], "tall": s["tall"]})
	_cells_chunk_cache[key] = out
	return out


## 该格是否为深水（阻挡型液体；导航洞加宽判定用，独立纯函数无跨块边距问题）
static func _water_at_cell(cell: Vector2i) -> bool:
	var pos := (Vector2(cell) + Vector2(0.5, 0.5)) * CELL
	return liquid_kind_in(BiomeMap.terrain_at(pos), pos,
			BiomeMap.region_id_at(pos), true) == "water"


## 地形块的导航阻挡表：PackedByteArray 256 字节（16×16，行主序，1=不可走）。
## 死点填充需 1 格边距——内部多采一圈（18×18）障碍样本，仅缓存本块 16×16 结果
static func nav_blocked_chunk(chunk_origin_px: Vector2i) -> PackedByteArray:
	var key := Vector2i(chunk_origin_px.x >> 9, chunk_origin_px.y >> 9)
	if _nav_chunk_cache.has(key):
		return _nav_chunk_cache[key]
	var base := Vector2i(chunk_origin_px.x >> 5, chunk_origin_px.y >> 5)
	var obstacle := PackedByteArray()
	obstacle.resize((CHUNK_CELLS + 2) * (CHUNK_CELLS + 2))
	for dy in CHUNK_CELLS + 2:
		for dx in CHUNK_CELLS + 2:
			obstacle[dy * (CHUNK_CELLS + 2) + dx] = \
					int(is_obstacle_cell(base + Vector2i(dx - 1, dy - 1)))
	var out := PackedByteArray()
	out.resize(CHUNK_CELLS * CHUNK_CELLS)
	for dy in CHUNK_CELLS:
		for dx in CHUNK_CELLS:
			var idx := (dy + 1) * (CHUNK_CELLS + 2) + dx + 1
			var blocked := obstacle[idx] == 1
			if not blocked:
				var walls := 0
				walls += obstacle[(dy + 1) * (CHUNK_CELLS + 2) + dx + 2]
				walls += obstacle[(dy + 1) * (CHUNK_CELLS + 2) + dx]
				walls += obstacle[(dy + 2) * (CHUNK_CELLS + 2) + dx + 1]
				walls += obstacle[dy * (CHUNK_CELLS + 2) + dx + 1]
				blocked = walls >= 3  # 单格死点填充
			if not blocked:
				# 深水导航缓冲：4 邻有水则本格也留洞——水碰撞 r14 + 怪 12 超过
				# 单格洞余隙，贴边路径会物理卡死；湖边一圈不可走代价可接受
				# （_water_at_cell 是独立纯函数，跨块边距无需展开）
				var near_water: bool = _water_at_cell(base + Vector2i(dx + 1, dy)) \
						or _water_at_cell(base + Vector2i(dx - 1, dy)) \
						or _water_at_cell(base + Vector2i(dx, dy + 1)) \
						or _water_at_cell(base + Vector2i(dx, dy - 1))
				if near_water:
					blocked = true
			out[dy * CHUNK_CELLS + dx] = int(blocked)
	_nav_chunk_cache[key] = out
	return out


## 点级导航可走判定（测试布阵/选点校验用）：取点所在格查所在块的导航阻挡表
static func nav_blocked_at(pos: Vector2) -> bool:
	var cell := Vector2i(floori(pos.x / CELL), floori(pos.y / CELL))
	var chunk := Vector2i(cell.x >> 4, cell.y >> 4)
	var local := cell - (chunk * 16)
	return nav_blocked_chunk(chunk * 512)[local.y * CHUNK_CELLS + local.x] == 1


## 覆盖率统计（测试/调参探针用）：在 rect 世界区域内采样障碍格占比
static func coverage_in(rect: Rect2) -> float:
	var c0 := Vector2i(floori(rect.position.x / CELL), floori(rect.position.y / CELL))
	var c1 := Vector2i(floori(rect.end.x / CELL), floori(rect.end.y / CELL))
	var total := 0
	var hit := 0
	for cy in range(c0.y, c1.y):
		for cx in range(c0.x, c1.x):
			total += 1
			if is_obstacle_cell(Vector2i(cx, cy)):
				hit += 1
	return float(hit) / float(maxi(total, 1))


## 液体类型（视觉与玩法同源）："" 无 / "water" 深水 / "lava" 熔岩池。
## blocking=false 按可见水（terrain_painter 消费——画出来的就是判得到的）；
## blocking=true 深水核再加保守边距（障碍阻挡判定用，浅水滩可趟）。
## 抑制区（斑块中心/出生点）内液体降级为普通地面——复活点/营地保底，
## 且地表绘制同走本函数，不会出现"看着是水但能走"的两张皮
static func liquid_kind_in(terrain: String, pos: Vector2, patch_id: String,
		blocking := false) -> String:
	_ensure()
	var rule: Dictionary = LIQUID_RULES.get(terrain, {})
	if rule.is_empty():
		return ""
	if pos.distance_squared_to(BiomeMap.spawn_pos()) < SPAWN_CLEAR * SPAWN_CLEAR:
		return ""
	var patch_center: Variant = _center_by_id.get(patch_id, null)
	if patch_center != null \
			and pos.distance_squared_to(patch_center) < PATCH_CLEAR * PATCH_CLEAR:
		return ""
	var gtx := floori(pos.x / 16.0)
	var gty := floori(pos.y / 16.0)
	var wet: float = BiomeMap._fbm(float(gtx) / 12.0, float(gty) / 12.0,
			int(BiomeMap.TERRAIN_NOISE_SEED[terrain]) + 51, 3)
	var thr: float = float(rule["water_thr"]) + (WATER_BLOCK_MARGIN if blocking else 0.0)
	if wet < thr:
		return ""
	return "lava" if terrain == "lava" else "water"


## 点位液体（玩家灼烧判定/环境查询用；完整口径含地形归属采样）
static func liquid_kind_at(pos: Vector2) -> String:
	return liquid_kind_in(BiomeMap.terrain_at(pos), pos, BiomeMap.region_id_at(pos), false)


## 玩家攻击对障碍格结算一次伤害（普攻/法弹共用）。返回被摧毁的 kind
## （"" = 未摧毁：不可破坏/已摧毁/耐久未尽）。纯逻辑层不发信号——调用方
## （表现层）拿到 kind 后自行发 EventBus.obstacle_destroyed（瓦片层擦格/
## 导航层补可走格/碎屑特效各自订阅），分块缓存在本层同步失效
static func damage_cell(cell: Vector2i) -> String:
	if _destroyed.has(cell):
		return ""
	var s := sample_cell(cell)
	if s.is_empty() or not DESTRUCTIBLE.has(s["kind"]):
		return ""
	var hp: int = int(_obstacle_hp.get(cell, OBSTACLE_HP)) - 1
	if hp > 0:
		_obstacle_hp[cell] = hp
		return ""
	_destroyed[cell] = true
	_obstacle_hp.erase(cell)
	_cells_chunk_cache.erase(Vector2i(cell.x >> 4, cell.y >> 4))
	_nav_chunk_cache.erase(Vector2i(cell.x >> 4, cell.y >> 4))
	return str(s["kind"])


## 摧毁覆盖层的存档序列化（"x,y" 字符串列表；读档恢复，新世界清零）
static func destroyed_list() -> Array:
	var out: Array = []
	for cell: Vector2i in _destroyed:
		out.append("%d,%d" % [cell.x, cell.y])
	return out


static func restore_destroyed(list: Array) -> void:
	# 先消化种子切换的重置（configure 后本调用先于任何采样——不主动 _ensure
	# 的话，灌进来的摧毁层会被首次采样触发的种子重置静默清空）
	_ensure()
	_destroyed = {}  # 整表替换语义（空列表 = 全复原，测试与读档共用）
	for entry in list:
		if typeof(entry) != TYPE_STRING:
			continue
		var parts: PackedStringArray = entry.split(",")
		if parts.size() != 2:
			continue
		var x := parts[0].to_int()
		var y := parts[1].to_int()
		if str(x) == parts[0] and str(y) == parts[1]:
			_destroyed[Vector2i(x, y)] = true
