## 导航专用瓦片层：不渲染、无碰撞，只向 NavigationServer2D 提供可走格。
## 窗口仍为半径6块（3072px），覆盖怪物流式回收半径2800px。
## 准备、铺格和出窗清理共用真实微秒预算；每帧最多各提交256格，避免
## NavigationServer 同步成本随单帧变更格数暴涨。物理/AI安全判定不变。
class_name NavTileLayer
extends TileMapLayer

const NAV_TILESET := preload("res://data/nav_tileset.tres")
const WINDOW_CHUNKS := 6
const CHUNK_PX := 512
const WORK_BUDGET_USEC := 2000
const CELL_SUBMIT_LIMIT := ObstacleField.CHUNK_CELLS * ObstacleField.CHUNK_CELLS

## 完整铺好的块、所有有格子的块（含部分铺入/部分清理）。
var _filled := {}
var _resident := {}
var _pending: Array[Vector2i] = []
var _clearing: Array[Vector2i] = []
var _clear_offsets := {}
var _fill_job: ObstacleField.NavChunkJob
var _fill_cursor := 0
var _center_chunk := Vector2i(1073741823, 1073741823)


func _init() -> void:
	# 进树前赋值，保留 Godot 4.7 的导航构建时序。
	tile_set = NAV_TILESET
	collision_enabled = false
	navigation_enabled = true


func _ready() -> void:
	EventBus.obstacle_destroyed.connect(_on_obstacle_destroyed)
	EventBus.campaign_geometry_changed.connect(_on_campaign_geometry_changed)


func _on_obstacle_destroyed(cell: Vector2i, _pos: Vector2, _kind: String) -> void:
	# 正在铺入的块也必须同步修改，不能在门关闭后留下旧的可走格。
	# 在途准备会根据 ObstacleField 的代号重新取样，不会把旧数据覆盖回来。
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var nearby := cell + Vector2i(dx, dy)
			var chunk := Vector2i(nearby.x >> 4, nearby.y >> 4)
			if not _resident.has(chunk):
				continue
			if _clearing.has(chunk):
				# 不往已清过的前缀补格；回窗后按新真源完整重铺。
				_filled.erase(chunk)
				continue
			_write_nav_cell(nearby, ObstacleField.nav_blocked_cell(nearby))


func _process(_delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null or not player.visible:
		return
	var cc := Vector2i(floori(player.global_position.x / float(CHUNK_PX)),
			floori(player.global_position.y / float(CHUNK_PX)))
	if cc != _center_chunk:
		_replan_window(cc)
	_advance_work()


## 清理预留四分之一预算，避免持续移动时旧块一直堆积；总预算不翻倍。
## 即使缓存命中，提交与清理仍逐格检查时钟和提交数上限。
func _advance_work(budget_usec: int = WORK_BUDGET_USEC) -> void:
	var started := Time.get_ticks_usec()
	var deadline := started + maxi(0, budget_usec)
	_advance_clearing(started + maxi(0, budget_usec / 4))
	var submitted := 0
	while Time.get_ticks_usec() < deadline and submitted < CELL_SUBMIT_LIMIT:
		if _fill_job == null:
			if _pending.is_empty():
				break
			var chunk: Vector2i = _pending.pop_front()
			if _filled.has(chunk) or not _in_window(chunk):
				continue
			_fill_job = ObstacleField.begin_nav_chunk(chunk * CHUNK_PX)
			_fill_cursor = 0
		elif _fill_job.revision != ObstacleField.nav_revision():
			# 破坏、机关或读档可能发生在准备或提交中途；从头校正已有格。
			_fill_job = ObstacleField.begin_nav_chunk(_fill_job.chunk * CHUNK_PX)
			_fill_cursor = 0
		if not ObstacleField.advance_nav_chunk(_fill_job, deadline):
			break
		while _fill_cursor < CELL_SUBMIT_LIMIT and submitted < CELL_SUBMIT_LIMIT:
			if Time.get_ticks_usec() >= deadline:
				return
			var cell := _fill_job.base + Vector2i(_fill_cursor % ObstacleField.CHUNK_CELLS,
				_fill_cursor / ObstacleField.CHUNK_CELLS)
			_resident[_fill_job.chunk] = true
			_write_nav_cell(cell, _fill_job.blocked[_fill_cursor] != 0)
			_fill_cursor += 1
			submitted += 1
		if _fill_cursor == CELL_SUBMIT_LIMIT:
			_filled[_fill_job.chunk] = true
			_fill_job = null


func _advance_clearing(deadline: int) -> void:
	var submitted := 0
	while not _clearing.is_empty() and submitted < CELL_SUBMIT_LIMIT:
		if Time.get_ticks_usec() >= deadline:
			return
		var chunk := _clearing[0]
		var cursor: int = _clear_offsets.get(chunk, 0)
		_filled.erase(chunk)
		var base := chunk * ObstacleField.CHUNK_CELLS
		erase_cell(base + Vector2i(cursor % ObstacleField.CHUNK_CELLS,
			cursor / ObstacleField.CHUNK_CELLS))
		cursor += 1
		submitted += 1
		if cursor == CELL_SUBMIT_LIMIT:
			_resident.erase(chunk)
			_clear_offsets.erase(chunk)
			_clearing.pop_front()
		else:
			_clear_offsets[chunk] = cursor


func _in_window(chunk: Vector2i) -> bool:
	return absi(chunk.x - _center_chunk.x) <= WINDOW_CHUNKS \
		and absi(chunk.y - _center_chunk.y) <= WINDOW_CHUNKS


## 回头时先撤销所有进窗块的旧清理任务，再重建近者优先队列。
## 已清过一部分的块不再标为完整，会重新铺齐；未清过的整块直接复用。
func _replan_window(center: Vector2i) -> void:
	_center_chunk = center
	for chunk: Vector2i in _clearing.duplicate():
		if _in_window(chunk):
			_clearing.erase(chunk)
			_clear_offsets.erase(chunk)
	if _fill_job != null and not _in_window(_fill_job.chunk):
		_fill_job = null
		_fill_cursor = 0
	for chunk: Vector2i in _resident:
		if not _in_window(chunk) and not _clearing.has(chunk):
			_clearing.append(chunk)
	_pending.clear()
	for dy in range(-WINDOW_CHUNKS, WINDOW_CHUNKS + 1):
		for dx in range(-WINDOW_CHUNKS, WINDOW_CHUNKS + 1):
			var chunk := center + Vector2i(dx, dy)
			if not _filled.has(chunk) and (_fill_job == null or _fill_job.chunk != chunk):
				_pending.append(chunk)
	_pending.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _chunk_dist2(a, center) < _chunk_dist2(b, center))


## 同步入口仅供固定场景布阵；正式 _process 不调用整块准备/提交。
func _fill_chunk(chunk: Vector2i) -> void:
	if _filled.has(chunk):
		_clearing.erase(chunk)
		_clear_offsets.erase(chunk)
		return
	_clearing.erase(chunk)
	_clear_offsets.erase(chunk)
	_pending.erase(chunk)
	if _fill_job != null and _fill_job.chunk == chunk:
		_fill_job = null
		_fill_cursor = 0
	var blocked := ObstacleField.nav_blocked_chunk(chunk * CHUNK_PX)
	var base := chunk * ObstacleField.CHUNK_CELLS
	for index in CELL_SUBMIT_LIMIT:
		_write_nav_cell(base + Vector2i(index % ObstacleField.CHUNK_CELLS,
			index / ObstacleField.CHUNK_CELLS), blocked[index] != 0)
	_resident[chunk] = true
	_filled[chunk] = true


func _write_nav_cell(cell: Vector2i, blocked: bool) -> void:
	if blocked:
		erase_cell(cell)
	else:
		set_cell(cell, 0, Vector2i.ZERO, 0)


func _clear_chunk(chunk: Vector2i) -> void:
	var base := chunk * ObstacleField.CHUNK_CELLS
	for index in CELL_SUBMIT_LIMIT:
		erase_cell(base + Vector2i(index % ObstacleField.CHUNK_CELLS,
			index / ObstacleField.CHUNK_CELLS))
	_filled.erase(chunk)
	_resident.erase(chunk)
	_clearing.erase(chunk)
	_clear_offsets.erase(chunk)


func _chunk_dist2(a: Vector2i, b: Vector2i) -> int:
	var dx := a.x - b.x
	var dy := a.y - b.y
	return dx * dx + dy * dy


func _on_campaign_geometry_changed(cells: Array) -> void:
	for cell: Vector2i in cells:
		_on_obstacle_destroyed(cell, Vector2.ZERO, "")
