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

const VISUAL_RULES := preload("res://scripts/main/terrain/obstacle_visual_rules.gd")
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
## 分帧铺格（真机性能优化 2026-09-19）：chunk_ready 同帧铺满森林块
## ~80 格（瓦片写入 + 80 次节点创建）×跨界多块是移动尖峰主源之一。
## 格子入队按预算分帧铺入，body 等本块形状全齐才挂树进物理。
## 64→160/帧（真机性能优化二轮）：收窄"逻辑格已到、碰撞体未铺"的竞态窗
## （森林块 ~85 格一帧铺完），攻击侧另有射线落空回退查真源兜底
const LAY_BUDGET := 160
var _lay_queue: Array[Dictionary] = []  # [{origin, cell, atlas, r}]
## origin → {body, shapes, remaining}（铺设中；remaining 归零转 _bodies）
var _laying := {}

## 出窗擦格分帧（真机卡顿修复 2026-10-01）：_on_chunk_freed 曾同帧 erase
## 整块 16×16=256 格×最多 5 块=1280 次 erase_cell（对齐 nav 层 _clearing 模式）。
## 碰撞 body 仍同帧 queue_free（碰撞先消失、视觉晚 1-2 帧——不会出现
## "看不见却撞得到"；出窗块在 1536px 外玩家不可见，短暂不一致无感）。
## 块级队列带擦除游标（边界抖动回窗时整块撤销清除，保住已重铺的格）
const CLEAR_BUDGET := 96
var _clearing: Array[Dictionary] = []  # [{origin, next}]（next=块内游标 0..255）

## 圆形碰撞形状按半径共享（2026-10-01）：Shape2D 是 Resource，半径只有
## KIND_INFO 的少数几档，逐格 new CircleShape2D 是跨界物理尖峰的组成部分
## （每个 shape 构造+物理服务器上传）；共享后每格只造便宜的节点壳
var _shape_cache := {}  # radius: float -> CircleShape2D


func _shared_circle(radius: float) -> CircleShape2D:
	var shape: CircleShape2D = _shape_cache.get(radius)
	if shape == null:
		shape = CircleShape2D.new()
		shape.radius = radius
		_shape_cache[radius] = shape
	return shape


func _ready() -> void:
	y_sort_enabled = true
	var streamer := get_parent().get_node_or_null("ChunkStreamer") as ChunkStreamer
	if streamer != null:
		streamer.chunk_ready.connect(_on_chunk_ready)
		streamer.chunk_freed.connect(_on_chunk_freed)
	EventBus.obstacle_destroyed.connect(_on_obstacle_destroyed)


func _exit_tree() -> void:
	# 铺设预算尚未消费完时 body 仍在树外，父节点退场不会替我们释放它。
	# 暂停后立即回菜单/切世界也必须回收，不等下一次 _process 或出窗信号。
	for entry: Dictionary in _laying.values():
		var body: Node = entry["body"]
		if is_instance_valid(body) and body.get_parent() == null:
			body.free()
	_laying.clear()
	_lay_queue.clear()
	_clearing.clear()


func _process(_delta: float) -> void:
	var budget := LAY_BUDGET
	while budget > 0 and not _lay_queue.is_empty():
		var item: Dictionary = _lay_queue.pop_front()
		var origin: Vector2i = item["origin"]
		var entry: Dictionary = _laying.get(origin, {})
		if entry.is_empty():
			continue  # 排队期间块已出窗被释放
		set_cell(item["cell"], item["source"], item["atlas"], item["alternative"])
		var shape := CollisionShape2D.new()
		shape.shape = _shared_circle(float(item["r"]))
		shape.position = (Vector2(item["cell"]) + Vector2(0.5, 0.5)) * ObstacleField.CELL
		(entry["body"] as StaticBody2D).add_child(shape)
		(entry["shapes"] as Dictionary)[item["cell"]] = shape
		entry["remaining"] = int(entry["remaining"]) - 1
		if entry["remaining"] == 0:
			add_child(entry["body"])
			_bodies[origin] = {"body": entry["body"], "shapes": entry["shapes"]}
			_laying.erase(origin)
		budget -= 1
	var clear_budget := CLEAR_BUDGET
	while clear_budget > 0 and not _clearing.is_empty():
		var entry: Dictionary = _clearing[0]
		var base := Vector2i(entry["origin"].x >> 5, entry["origin"].y >> 5)
		var next: int = entry["next"]
		while clear_budget > 0 and next < ObstacleField.CHUNK_CELLS * ObstacleField.CHUNK_CELLS:
			erase_cell(base + Vector2i(next % ObstacleField.CHUNK_CELLS,
					next / ObstacleField.CHUNK_CELLS))
			next += 1
			clear_budget -= 1
		if next >= ObstacleField.CHUNK_CELLS * ObstacleField.CHUNK_CELLS:
			_clearing.pop_front()
		else:
			entry["next"] = next


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
	# 同步移除该格碰撞形状（body 常驻，形状按格摘除；分帧铺设期间形状在 _laying）
	for registry: Dictionary in [_bodies, _laying]:
		for entry: Dictionary in registry.values():
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


func _on_chunk_freed(origin: Vector2i) -> void:
	# 视觉格分帧擦（_clearing 带游标），碰撞 body 同帧释放防泄漏
	# （碰撞先消失、视觉晚 1-2 帧——不会出现"看不见却撞得到"）
	_clearing.append({"origin": origin, "next": 0})
	var entry: Dictionary = _bodies.get(origin, {})
	if not entry.is_empty():
		(entry["body"] as Node).queue_free()
		_bodies.erase(origin)
	# 铺设中即被回收：body 直接释放，队列残留格子消费时按 _laying 缺失跳过
	var laying: Dictionary = _laying.get(origin, {})
	if not laying.is_empty():
		(laying["body"] as Node).queue_free()
		_laying.erase(origin)


func _on_chunk_ready(origin: Vector2i) -> void:
	if _bodies.has(origin) or _laying.has(origin):
		return
	# 边界抖动回窗：撤销该块的待清（擦格游标后与重铺的格会互相打架）
	for i in _clearing.size():
		if (_clearing[i] as Dictionary)["origin"] == origin:
			_clearing.remove_at(i)
			break
	var cells: Array = ObstacleField.cells_of_chunk(origin)
	var body := _make_obstacle_body()
	if cells.is_empty():
		add_child(body)
		_bodies[origin] = {"body": body, "shapes": {}}
		return
	# 碰撞体（每块一个 body，形状按格）：见类注——不依赖瓦片物理。
	# 铺格入队分帧（LAY_BUDGET），本块形状全齐才把 body 挂树
	_laying[origin] = {"body": body, "shapes": {}, "remaining": cells.size()}
	for c: Dictionary in cells:
		var art: Dictionary = VISUAL_RULES.appearance(c["cell"], c["kind"])
		_lay_queue.append({"origin": origin, "cell": c["cell"], "source": art["source"],
			"atlas": art["atlas"], "alternative": art["alternative"], "r": c["r"]})
