## 导航专用瓦片层（世界 v5）：不渲染（瓦片全透明）、无碰撞，只向
## NavigationServer2D 提供可走格导航多边形——整层合并为单导航区域，天然没有
## 分块 Region 的边界缝合问题；相邻可走格共享边缘顶点，层内导航图连通。
## 窗口半径 WINDOW_CHUNKS = 7 块（3584px，扣除半块余量仍 ≥ 怪物流式回收半径
## 2800px）——所有活跃怪物脚下恒有导航网格。格子同源 ObstacleField 派生
## （含单格死点填充，见 nav_blocked_chunk），与可见障碍层无双源漂移。
## 铺格按帧预算节流（跨界一次最多补 15 块，全铺会顶帧；导航晚到无害——
## 覆盖前的怪走直线，进窗后自动走导航）。
class_name NavTileLayer
extends TileMapLayer

const NAV_TILESET := preload("res://data/nav_tileset.tres")
const WINDOW_CHUNKS := 7
## 每帧最多补铺的地形块数（跨界瞬间欠 15 块，~5 帧铺满）
const FILL_BUDGET := 3
const CHUNK_PX := 512

## 已铺块集合（chunk 坐标 → true）
var _filled := {}
## 待铺队列（近者先）
var _pending: Array[Vector2i] = []
var _center_chunk := Vector2i(1073741823, 1073741823)


func _init() -> void:
	# tile_set 进树前赋值（与 obstacle_tile_layer 同因——_ready 内赋值在
	# Godot 4.7 有内部构建时序坑；导航当前可用，统一时序防同类问题）
	tile_set = NAV_TILESET
	collision_enabled = false
	navigation_enabled = true


func _ready() -> void:
	# 障碍被摧毁：立即补可走格（导航网格更新后怪物的旧路径会在下次重铺时修正）
	EventBus.obstacle_destroyed.connect(_on_obstacle_destroyed)


func _on_obstacle_destroyed(cell: Vector2i, _pos: Vector2, _kind: String) -> void:
	if _filled.has(Vector2i(cell.x >> 4, cell.y >> 4)):
		set_cell(cell, 0, Vector2i.ZERO, 0)


func _process(_delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null or not player.visible:
		return
	var cc := Vector2i(floori(player.global_position.x / float(CHUNK_PX)),
			floori(player.global_position.y / float(CHUNK_PX)))
	if cc != _center_chunk:
		_center_chunk = cc
		_replan_window(cc)
	var budget := FILL_BUDGET
	while budget > 0 and not _pending.is_empty():
		var chunk: Vector2i = _pending.pop_front()
		_fill_chunk(chunk)
		budget -= 1


## 重建窗口：进窗缺口入队（按距玩家排序），出窗块整块清除
func _replan_window(center: Vector2i) -> void:
	_pending.clear()
	var r := WINDOW_CHUNKS
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var chunk := center + Vector2i(dx, dy)
			if not _filled.has(chunk):
				_pending.append(chunk)
	_pending.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _chunk_dist2(a, center) < _chunk_dist2(b, center))
	for chunk: Vector2i in _filled.keys():
		if absi(chunk.x - center.x) > r or absi(chunk.y - center.y) > r:
			_clear_chunk(chunk)
			_filled.erase(chunk)


func _fill_chunk(chunk: Vector2i) -> void:
	if _filled.has(chunk):
		return
	var origin := chunk * CHUNK_PX
	var blocked := ObstacleField.nav_blocked_chunk(origin)
	var base := Vector2i(origin.x >> 5, origin.y >> 5)
	for dy in ObstacleField.CHUNK_CELLS:
		for dx in ObstacleField.CHUNK_CELLS:
			if blocked[dy * ObstacleField.CHUNK_CELLS + dx] == 0:
				set_cell(base + Vector2i(dx, dy), 0, Vector2i.ZERO, 0)
	_filled[chunk] = true


func _clear_chunk(chunk: Vector2i) -> void:
	var base := Vector2i(chunk.x * CHUNK_PX >> 5, chunk.y * CHUNK_PX >> 5)
	for dy in ObstacleField.CHUNK_CELLS:
		for dx in ObstacleField.CHUNK_CELLS:
			erase_cell(base + Vector2i(dx, dy))


func _chunk_dist2(a: Vector2i, b: Vector2i) -> int:
	var dx := a.x - b.x
	var dy := a.y - b.y
	return dx * dx + dy * dy
