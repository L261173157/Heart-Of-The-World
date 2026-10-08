## 小地图地形缓存：只采样局部已探索窗口，每帧最多24个64px格、约1.5ms软时间预算。
## 群系/液体/障碍均读取原真源；不生成世界纹理，不加载地表图集或导航块。
class_name MinimapTerrain
extends RefCounted

const CELL := 64.0
const BASE_CELL := 512.0
const SAMPLE_BUDGET := 24
const SAMPLE_USEC := 1500
const MAX_CELLS := 8192
const MAX_BASE_CELLS := 361
## 与实际地表共用色板常量；读取常量不会调用ensure_atlases或加载贴图。
var cells: Dictionary = {}
## 先用最多约120个局部粗地被色填满已知轮廓，慢帧下不会长时间显示空心地图。
var base_cells: Dictionary = {}
var _base_pending: Array[Vector2i] = []
var _base_positions: Dictionary = {}
var _base_cursor := 0
var pending: Array[Vector2i] = []
var cursor := 0
var total_samples := 0
var last_step_samples := 0
var _seed := -1
var _window := Rect2i()
var _revision := -1
var _known_cache: Dictionary = {}
static var _rings: Array = []


func clear() -> void:
	cells.clear()
	base_cells.clear()
	_base_pending.clear()
	_base_positions.clear()
	_base_cursor = 0
	pending.clear()
	cursor = 0
	_window = Rect2i()
	_revision = -1
	_known_cache.clear()


func prepare(world_rect: Rect2, world_seed: int, revision: int, known: Callable,
		known_cell_size: float = CELL) -> void:
	var start := Vector2i((world_rect.position / CELL).floor())
	var end := Vector2i((world_rect.end / CELL).ceil())
	var window := Rect2i(start, Vector2i(mini(end.x - start.x, 128), mini(end.y - start.y, 128)))
	if _seed != world_seed:
		clear()
		_seed = world_seed
	if window == _window and revision == _revision:
		return
	if revision != _revision:
		_known_cache.clear()
	_window = window
	_revision = revision
	# 正常探索只增不减；换档/新世界由调用方clear。移动仅裁掉离窗数据。
	for key: Vector2i in cells.keys():
		if not window.has_point(key):
			cells.erase(key)
	var bounded_world := Rect2(Vector2(window.position) * CELL, Vector2(window.size) * CELL)
	for key: Vector2i in base_cells.keys():
		if not bounded_world.grow(BASE_CELL).has_point((Vector2(key) + Vector2.ONE * 0.5) * BASE_CELL):
			base_cells.erase(key)
	for key: Vector2i in _known_cache.keys():
		if not bounded_world.grow(known_cell_size).has_point(Vector2(key) * known_cell_size):
			_known_cache.erase(key)
	_base_pending.clear()
	_base_positions.clear()
	_base_cursor = 0
	# 不重新查询、排序已有任务；相邻窗口移动保留尚未完成的局部队列。
	var retained: Array[Vector2i] = []
	var queued := {}
	for i in range(cursor, pending.size()):
		var key := pending[i]
		if window.has_point(key) and not cells.has(key):
			retained.append(key)
			queued[key] = true
	pending = retained
	cursor = 0
	_ensure_rings()
	var center := window.get_center()
	var reach := mini(64, maxi(window.size.x, window.size.y) / 2 + 1)
	for radius in range(reach + 1):
		for offset: Vector2i in _rings[radius]:
			var key := center + offset
			if not window.has_point(key):
				continue
			var pos := (Vector2(key) + Vector2.ONE * 0.5) * CELL
			if not cells.has(key) and not queued.has(key):
				var fog_key := Vector2i((pos / known_cell_size).floor())
				if not _known_cache.has(fog_key):
					_known_cache[fog_key] = known.call(pos)
				if not _known_cache[fog_key] or cells.size() + pending.size() >= MAX_CELLS:
					continue
				pending.append(key)
				queued[key] = true
			var base := Vector2i((pos / BASE_CELL).floor())
			if base_cells.size() + _base_pending.size() < MAX_BASE_CELLS \
					and not base_cells.has(base) and not _base_positions.has(base):
				_base_pending.append(base)
				_base_positions[base] = pos


## Chebyshev环仅创建一次，既先补玩家脚边也避免每次移动的O(n log n)排序。
static func _ensure_rings() -> void:
	if not _rings.is_empty():
		return
	_rings.append([Vector2i.ZERO])
	for radius in range(1, 66):
		var ring: Array[Vector2i] = []
		for x in range(-radius, radius + 1):
			ring.append(Vector2i(x, -radius))
			ring.append(Vector2i(x, radius))
		for y in range(-radius + 1, radius):
			ring.append(Vector2i(-radius, y))
			ring.append(Vector2i(radius, y))
		_rings.append(ring)


func has_pending() -> bool:
	return _base_cursor < _base_pending.size() or cursor < pending.size()


func step(budget: int = SAMPLE_BUDGET) -> int:
	last_step_samples = 0
	if not has_pending():
		return 0
	var started := Time.get_ticks_usec()
	while _base_cursor < _base_pending.size() and last_step_samples < mini(budget, SAMPLE_BUDGET):
		var key := _base_pending[_base_cursor]
		_base_cursor += 1
		var terrain := BiomeMap.terrain_at(_base_positions[key])
		base_cells[key] = surface_color(terrain, 0)
		last_step_samples += 1
		if Time.get_ticks_usec() - started >= SAMPLE_USEC:
			break
	while cursor < pending.size() and last_step_samples < mini(budget, SAMPLE_BUDGET) \
			and Time.get_ticks_usec() - started < SAMPLE_USEC:
		var key := pending[cursor]
		cursor += 1
		cells[key] = sample(key)
		last_step_samples += 1
		if Time.get_ticks_usec() - started >= SAMPLE_USEC:
			break
	total_samples += last_step_samples
	return last_step_samples


func invalidate_obstacle(cell: Vector2i) -> void:
	var key := Vector2i(floori(float(cell.x) / 2.0), floori(float(cell.y) / 2.0))
	if cells.erase(key):
		_revision = -1


static func sample(cell: Vector2i) -> Dictionary:
	var pos := (Vector2(cell) + Vector2.ONE * 0.5) * CELL
	var patch := BiomeMap.region_id_at(pos)
	var terrain := BiomeMap.terrain_of_patch(patch)
	var liquid := ObstacleField.liquid_kind_in(terrain, pos, patch)
	var material := 2 if not liquid.is_empty() else 0
	if terrain == "plains" and liquid.is_empty() and TerrainPainter.is_camp_path(pos):
		material = 1 # 仅地图的地表色，不参与可走判定。
	var color := surface_color(terrain, material)
	var blocked := 0
	var castle := false
	for dy in 2:
		for dx in 2:
			var obstacle := ObstacleField.sample_cell(cell * 2 + Vector2i(dx, dy))
			if not obstacle.is_empty() and obstacle["kind"] != "water":
				blocked += 1
				castle = castle or obstacle["kind"] == "castle"
	if castle:
		color = Color("d5b689")
	elif blocked > 0:
		color = color.darkened(0.14 + float(blocked) * 0.08)
	return {"color": color, "terrain": terrain, "liquid": liquid, "blocked": blocked, "castle": castle}


static func surface_color(terrain: String, material: int) -> Color:
	var palette: Array = TerrainPainter.SURFACE_PALETTES[terrain][material]
	return Color(palette[0]).lerp(Color(palette[1]), 0.60)
