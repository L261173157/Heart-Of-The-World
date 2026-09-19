## 地表分块流式加载器（Node2D，挂 game_world）。
## 世界 80 万像素见方不可整图常驻——以玩家为中心维护 512px 块窗口：
## 工作线程绘制（TerrainPainter 确定性生成）→ 主线程建纹理挂 Sprite2D，
## 出窗即回收（LRU 上限兜底）。chunk_ready/chunk_freed 信号供 world_deco
## 同步分块撒放装饰。表现层组件：只读 BiomeMap，不改任何模拟状态。
class_name ChunkStreamer
extends Node2D

## 块边长（世界像素，32×32 瓦）
const CHUNK := 512
## 玩家所在块周围保持的块半径（5×5 窗口，覆盖视野+冲刺余量）
const KEEP_RADIUS := 2
## 出窗缓冲：超过 KEEP_RADIUS+1 才回收（防贴边反复建/删）
const EVICT_RADIUS := 3
## 同时存在的块数上限（LRU 兜底；窗口满额 25 + 换块过渡冗余）
const MAX_CHUNKS := 36
## 每帧上屏的块数（纹理创建在主线程，限流防掉帧）。
## 2→1（真机性能优化 2026-09-19）：每块 512²RGBA8 = 1MB 纹理上传，跨界帧
## 连上 2 块（2MB GPU 上传）+ 障碍/装饰连锁是移动尖峰；1 块/帧下 5 块窗口
## 5 帧铺满，步行跨界间隔 ~3.2s 完全无感
const APPLY_PER_FRAME := 1

signal chunk_ready(origin: Vector2i)
signal chunk_freed(origin: Vector2i)

var _chunks := {}          # "cx,cy" -> {"sprite": Sprite2D}
var _pending := {}         # "cx,cy" -> true（已入队未上屏）
var _last_center := Vector2i(1 << 30, 1 << 30)

var _thread: Thread
var _mutex := Mutex.new()
var _queue: Array[Vector2i] = []   # 工作线程待绘制（近者先出）
var _results: Array = []           # 工作线程产出 {origin, image}，主线程取用
var _stopping := false


func _ready() -> void:
	z_index = -2
	# 静态缓存全部在主线程预热后再开工作线程（paint_chunk 内只读）
	BiomeMap.patches()
	TerrainPainter.ensure_atlases()
	_refresh_window()
	_thread = Thread.new()
	_thread.start(_worker)


## 脚下块同步预热（game_world 在装饰层挂好 chunk 信号后调用）：
## 进世界第一帧脚下就有地（单块 ~60ms，多块同步在移动端首帧卡顿不可接受），
## 周边窗口块交给工作线程渐进填充
func warmup() -> void:
	var center := _player_center()
	if center == Vector2i(1 << 30, 1 << 30):
		return
	_spawn_sync(_origin_in_world(center))


func _exit_tree() -> void:
	_stopping = true
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()


func _process(_delta: float) -> void:
	_refresh_window()
	_apply_results()


# --- 窗口维护 ---

func _player_center() -> Vector2i:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return Vector2i(1 << 30, 1 << 30)
	return Vector2i(
		clampi(player.global_position.x, 0, int(WorldConfig.WORLD_SIZE.x) - 1) / CHUNK,
		clampi(player.global_position.y, 0, int(WorldConfig.WORLD_SIZE.y) - 1) / CHUNK)


func _refresh_window() -> void:
	var center := _player_center()
	if center == _last_center:
		return
	_last_center = center
	for dy in range(-KEEP_RADIUS, KEEP_RADIUS + 1):
		for dx in range(-KEEP_RADIUS, KEEP_RADIUS + 1):
			var origin := _origin_in_world(center + Vector2i(dx, dy))
			if origin == Vector2i(-1, -1):
				continue
			var key := _key(origin)
			if not _chunks.has(key) and not _pending.has(key):
				_pending[key] = true
				_mutex.lock()
				_queue.append(origin)
				_mutex.unlock()
	# 请求按距玩家近者优先（工作线程同序出队，脚下的地先出现）
	_mutex.lock()
	_queue.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _dist2_to_center(a) < _dist2_to_center(b))
	_mutex.unlock()
	# 出窗回收（含 LRU 上限兜底：极端快速移动时窗口外的滞留块）
	for key: String in _chunks.keys():
		var origin := _origin_of(key)
		if _dist2_to_center(origin) > EVICT_RADIUS * EVICT_RADIUS:
			_free_chunk(key)
	if _chunks.size() > MAX_CHUNKS:
		var excess: Array = _chunks.keys()
		excess.sort_custom(func(a: String, b: String) -> bool:
			return _dist2_to_center(_origin_of(a)) > _dist2_to_center(_origin_of(b)))
		while _chunks.size() > MAX_CHUNKS and not excess.is_empty():
			_free_chunk(excess.pop_front())


func _origin_in_world(cell: Vector2i) -> Vector2i:
	if cell.x < 0 or cell.y < 0 \
			or cell.x * CHUNK >= int(WorldConfig.WORLD_SIZE.x) \
			or cell.y * CHUNK >= int(WorldConfig.WORLD_SIZE.y):
		return Vector2i(-1, -1)
	return Vector2i(cell.x * CHUNK, cell.y * CHUNK)


func _dist2_to_center(origin: Vector2i) -> int:
	var dx: int = origin.x / CHUNK - _last_center.x
	var dy: int = origin.y / CHUNK - _last_center.y
	return dx * dx + dy * dy


func _spawn_sync(origin: Vector2i) -> void:
	if origin == Vector2i(-1, -1) or _chunks.has(_key(origin)):
		return
	var img := TerrainPainter.paint_chunk(origin, CHUNK / TerrainPainter.TS)
	_add_sprite(origin, img)


# --- 工作线程：出队 → 绘制 → 回传 ---

func _worker() -> void:
	while not _stopping:
		var origin := Vector2i.ZERO
		_mutex.lock()
		if _queue.is_empty():
			_mutex.unlock()
			OS.delay_msec(8)
			continue
		origin = _queue.pop_front()
		_mutex.unlock()
		var img := TerrainPainter.paint_chunk(origin, CHUNK / TerrainPainter.TS)
		_mutex.lock()
		_results.append({"origin": origin, "image": img})
		_mutex.unlock()


# --- 主线程：上屏 / 回收 ---

func _apply_results() -> void:
	for i in APPLY_PER_FRAME:
		_mutex.lock()
		if _results.is_empty():
			_mutex.unlock()
			return
		var result: Dictionary = _results.pop_front()
		_mutex.unlock()
		var origin: Vector2i = result["origin"]
		var key := _key(origin)
		_pending.erase(key)
		# 等待期间玩家可能已走远（出窗），直接丢弃免得白占纹理
		if _dist2_to_center(origin) > EVICT_RADIUS * EVICT_RADIUS:
			continue
		if not _chunks.has(key):
			_add_sprite(origin, result["image"])


func _add_sprite(origin: Vector2i, img: Image) -> void:
	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.position = Vector2(origin)
	sprite.texture = ImageTexture.create_from_image(img)
	add_child(sprite)
	_chunks[_key(origin)] = {"sprite": sprite}
	chunk_ready.emit(origin)


func _free_chunk(key: String) -> void:
	var entry: Dictionary = _chunks.get(key, {})
	if entry.is_empty():
		return
	(entry["sprite"] as Sprite2D).queue_free()
	_chunks.erase(key)
	chunk_freed.emit(_origin_of(key))


func _key(origin: Vector2i) -> String:
	return "%d,%d" % [origin.x, origin.y]


func _origin_of(key: String) -> Vector2i:
	var parts := key.split(",")
	return Vector2i(int(parts[0]), int(parts[1]))
