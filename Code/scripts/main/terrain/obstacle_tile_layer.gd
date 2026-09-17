## 可见障碍瓦片层（世界 v5）：把 ObstacleField 的障碍格铺成 TileMap——
## 贴图（y-sort 树冠遮挡）+ 阴影遮挡（TileSet 遮挡层供提灯 Light2D 投影）。
## 物理不依赖瓦片碰撞：Godot 4.7 的 TileMapLayer 存在"格子只注册视觉、
## 物理体静默不构建"的时序坑（早期实例/重铺均复现，运行期新建偶发正常，
## 无稳定规避路径），碰撞改由每块一个 StaticBody2D + 圆形碰撞形状承担
## （墙层 layer 1，与世界边界墙/巢穴同款被验证的方案；瓦片层专职视觉）。
## 随地表流式器的 chunk_ready/freed 进出 5×5 窗，格子由 ObstacleField
## 确定性派生，走远再回来障碍还在原地。挂载于 game_world（延迟挂载）。
class_name ObstacleTileLayer
extends TileMapLayer

const OBSTACLE_TILESET := preload("res://data/obstacle_tileset.tres")


func _init() -> void:
	# tile_set 必须在进树前赋值（_init/.new() 阶段）：在 _ready 里赋值的话
	# Godot 4.7 的 TileMapLayer 只注册视觉格子、物理体静默不构建——
	# 游戏内点查询实证 934 格零碰撞体，隔帧原生对照层正常（combat 探针定位）
	tile_set = OBSTACLE_TILESET
	# 关闭瓦片原生物理：碰撞由每块自挂 StaticBody2D 圆承担（本文件工厂）。
	# 瓦片集残留的 physics 多边形会让引擎在每次流式填块时合并+凸分解象限碰撞体，
	# 森林密集簇分解失败 → 每跑一次 combat_test 刷 30~40 条 "Convex decomposing
	# failed" 且白耗 CPU（ Godot 4.7 tile_map_layer.cpp:940 实证路径）
	collision_enabled = false


## 块坐标（px）→ {body: StaticBody2D, shapes: {cell: CollisionShape2D}}
var _bodies := {}

func _ready() -> void:
	y_sort_enabled = true
	var streamer := get_parent().get_node_or_null("ChunkStreamer") as ChunkStreamer
	if streamer != null:
		streamer.chunk_ready.connect(_on_chunk_ready)
		streamer.chunk_freed.connect(_on_chunk_freed)
	EventBus.obstacle_destroyed.connect(_on_obstacle_destroyed)


## 静态碰撞体工厂：圆形形状按类型半径（KIND_INFO.r），墙层 layer 1
static func _make_obstacle_body() -> StaticBody2D:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("obstacle", true)  # 玩家挥砍射线识别用（区别于世界边界墙）
	return body


## 障碍被玩家摧毁：擦格 + 碎屑演出（同格重铺时 destroyed 覆盖层已挡住）
func _on_obstacle_destroyed(cell: Vector2i, pos: Vector2, kind: String) -> void:
	erase_cell(cell)
	# 同步移除该格碰撞形状（body 常驻，形状按格摘除）
	for entry: Dictionary in _bodies.values():
		var shapes: Dictionary = entry["shapes"]
		if shapes.has(cell):
			var shape: Node = shapes[cell]
			shape.queue_free()
			shapes.erase(cell)
	var debris := DebrisBurst.new()
	debris.position = pos
	debris.kind = kind
	add_child(debris)


## 碎屑演出：4 片碎块外抛坠落淡出（0.5s 自动回收；按障碍类型取色）
class DebrisBurst extends Node2D:
	var kind := "rock"

	func _ready() -> void:
		z_index = 3
		var palette := {
			"rock": Color(0.55, 0.48, 0.38), "bones": Color(0.85, 0.82, 0.7),
			"crystal": Color(0.75, 0.5, 0.95), "ice": Color(0.65, 0.85, 1.0),
		}
		var color: Color = palette.get(kind, Color.GRAY)
		for i in 4:
			var chip := Polygon2D.new()
			var side := randf_range(4.0, 7.0)
			chip.polygon = PackedVector2Array([
				Vector2(-side * 0.5, -side * 0.4), Vector2(side * 0.5, -side * 0.5),
				Vector2(side * 0.4, side * 0.5), Vector2(-side * 0.4, side * 0.4)])
			chip.color = color
			chip.rotation = randf() * TAU
			add_child(chip)
			var ang := randf() * TAU
			var dest := Vector2(cos(ang), sin(ang)) * randf_range(18.0, 40.0) + Vector2(0, 14)
			var tween := chip.create_tween()
			tween.set_parallel(true)
			tween.tween_property(chip, "position", dest, 0.45)					.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
			tween.tween_property(chip, "modulate:a", 0.0, 0.45).set_delay(0.12)
		var dying := get_tree().create_timer(0.55)
		dying.timeout.connect(queue_free)


func _on_chunk_ready(origin: Vector2i) -> void:
	var cells: Array = ObstacleField.cells_of_chunk(origin)
	for c: Dictionary in cells:
		set_cell(c["cell"], 0, ObstacleField.KIND_ATLAS[c["kind"]], 0)
	# 碰撞体（每块一个 body，形状按格）：见类注——不依赖瓦片物理
	var body := _make_obstacle_body()
	var shapes := {}
	for c: Dictionary in cells:
		var cell: Vector2i = c["cell"]
		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = float(c["r"])
		shape.shape = circle
		shape.position = (Vector2(cell) + Vector2(0.5, 0.5)) * ObstacleField.CELL
		body.add_child(shape)
		shapes[cell] = shape
	add_child(body)
	_bodies[origin] = {"body": body, "shapes": shapes}


func _on_chunk_freed(origin: Vector2i) -> void:
	var base := Vector2i(origin.x >> 5, origin.y >> 5)
	for dy in ObstacleField.CHUNK_CELLS:
		for dx in ObstacleField.CHUNK_CELLS:
			erase_cell(base + Vector2i(dx, dy))
	var entry: Dictionary = _bodies.get(origin, {})
	if not entry.is_empty():
		(entry["body"] as Node).queue_free()
		_bodies.erase(origin)
