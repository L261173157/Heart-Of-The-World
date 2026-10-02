## 世界环境表现层（纯视觉，无碰撞无逻辑影响）v4 分块版：
## ① 程序地被装饰——地表块流式生成时按块撒草/灌丛/蘑菇（hash(块坐标)
##    固定种子可复现：走过再回来，装饰还在原地），每件道具按落点自身地形取样
## ② 环境粒子——单例跟随玩家、按当前地形切换（雪原飘雪/熔岩升火星/沼泽浮雾）
## v4 起不再做区域氛围叠色：群系交界由地表贴图 alpha 混合自然过渡，
## 矩形叠色反而是"方形区域"的视觉残留。
## 挂载于 game_world（ChunkStreamer 之后）；只读 BiomeMap，不触碰模拟状态。
class_name WorldDeco
extends Node2D

## 每地形装饰配方：类型 → 数量（密度按"簇状撒布"成团出现，避免均匀稀疏的空旷感）
## 每地形 3-5 种道具拉开层次：骨架树/岩 + 中件灌丛 + 细节宝石/香蒲
## 只有柔软地被留在无碰撞装饰层。硬树/岩一律由 ObstacleField 生成，
## 避免外观相同却一棵可穿、一棵挡路；装饰尺寸不再制造迷你树。
const RECIPES := {
	"plains": {"grass": 20, "bush": 12, "mushroom": 4},
	"forest": {"mushroom": 12, "grass": 8, "bush": 16},
	"snow": {"snowpile": 14, "bush": 6},
	"swamp": {"cattail": 10, "mushroom": 10, "puddle": 10, "bush": 8},
	"hill": {"bush": 10, "gems": 6, "grass": 8},
	"lava": {"gems": 5, "skullspike": 6},
}

## 每块（512²）道具件数：与旧"每区域配方"密度同口径
## （旧图 1100×700≈77 万 px²，块 26.2 万 px²，约 1/3 密度取整）
const CHUNK_PROPS := 13
## 撒布簇心数（70% 道具围绕簇心成团）
const CHUNK_CLUSTERS := 3
## 环境粒子跟随/切换的轮询间隔
const AMBIENT_POLL := 0.5

const DECO_Z := -1     # 地物在怪物之下
const PARTICLE_Z := 5

## 装饰精灵真源 = assets/deco/<kind>.png（tools/bake_structures 烘焙：TS Resources
## 树/松/岩/灌丛 + EP 骨堆/骷髅桩/真枯树 + 色板合成蘑菇/香蒲等。v6 起 NA 图集通道
## 已退役：缺图=该件跳过并告警，不再回退 NA 像素）。
## 走精灵绘制的装饰种类（big_tree/boulder = 放大复用；冰锥/雪堆/水洼/水晶/
## 骨堆/骷髅桩等走多边形兜底或 EP 精灵）
const TEXTURE_KINDS := ["tree", "big_tree", "grass", "pine", "deadtree", "rock", "boulder",
	"mushroom", "log", "bush", "gems", "cattail"]
## 细软小道具：落影同步收窄（草/蘑菇/灌木/香蒲/宝石下面不该拖大黑影）
const SMALL_SHADOW_KINDS := ["grass", "mushroom", "bush", "gems", "cattail"]

## 装饰精灵（assets/deco/<kind>.png）：有图走精灵；缺图该类告警一次并跳过
var _sprite_cache := {}


func _deco_sprite(kind: String) -> Texture2D:
	if _sprite_cache.has(kind):
		return _sprite_cache[kind]
	var tex: Texture2D = null
	var path := "res://assets/deco/%s.png" % kind
	if ResourceLoader.exists(path):
		tex = load(path)
	if tex == null:
		push_warning("world_deco 缺装饰精灵 assets/deco/%s.png，该类装饰跳过" % kind)
	_sprite_cache[kind] = tex
	return tex

## 块 key → {layer: DecoLayer, baked: Polygon2D}
var _by_chunk := {}
## 环境粒子（单例跟随玩家，按地形切换）
var _ambient: CPUParticles2D
var _ambient_terrain := ""
var _ambient_accum := 0.0


## 块贴图装饰层：一个节点 _draw 全部道具（保持"每块个位数节点"的性能模型）。
## 每件 = 精灵 + 落点 + 缩放 + 水平翻转 + 着色（枯树走 EP 精灵，56 高树档）
class DecoLayer extends Node2D:
	var items: Array = []

	func _draw() -> void:
		for item: Dictionary in items:
			var sp: Texture2D = item.get("sprite")
			if sp == null:
				continue
			var s: float = item["s"]
			draw_set_transform(item["pos"], 0.0,
				Vector2(-s if item["flip"] else s, s))
			# 精灵：底边贴落点，高 32px 基准档（保持占地/落影一致）；
			# 高件（枯树等）经 item["h"] 指定目标高
			var h := float(item.get("h", 32.0))
			var w := h * float(sp.get_width()) / float(sp.get_height())
			draw_texture_rect(sp, Rect2(-w / 2.0, -h, w, h), false, item["mod"])


func _ready() -> void:
	# 订阅地表流式生成器的块信号（挂载顺序由 game_world 保证：本节点在流式器之后）
	var streamer := get_parent().get_node_or_null("ChunkStreamer") as ChunkStreamer
	if streamer != null:
		streamer.chunk_ready.connect(_on_chunk_ready)
		streamer.chunk_freed.connect(_on_chunk_freed)
	_ambient = CPUParticles2D.new()
	_ambient.z_index = PARTICLE_Z
	_ambient.emitting = false
	add_child(_ambient)


func _process(delta: float) -> void:
	# 粒子跟随玩家（视野尺度的局部天气，而非全区域常驻量）
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player != null:
		_ambient.position = player.global_position
	_ambient_accum += delta
	if _ambient_accum >= AMBIENT_POLL:
		_ambient_accum = 0.0
		var terrain := BiomeMap.terrain_at(player.global_position) if player != null else ""
		if player != null and ObstacleField.interior_index_at(player.global_position) >= 0:
			terrain = ""  # 房间不继承口袋下方的雨雪/浮雾/火星
		if terrain != _ambient_terrain:
			_ambient_terrain = terrain
			_configure_ambient(terrain)


# --- 分块装饰 ---

func _on_chunk_ready(origin: Vector2i) -> void:
	if _by_chunk.has(_key(origin)):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = (absi(origin.x) * 73856093) ^ (absi(origin.y) * 19349663) ^ 0x5DEC0
	var rect := Rect2(Vector2(origin), Vector2.ONE * 512.0)
	var clusters: Array[Vector2] = []
	for i in CHUNK_CLUSTERS:
		clusters.append(rect.position + Vector2(
			rng.randf_range(60.0, 452.0), rng.randf_range(60.0, 452.0)))
	var layer := DecoLayer.new()
	layer.z_index = DECO_Z
	var points := PackedVector2Array()
	var colors := PackedColorArray()
	var polys: Array = []
	for i in CHUNK_PROPS:
		var pos: Vector2
		if rng.randf() < 0.7 and not clusters.is_empty():
			pos = clusters[rng.randi() % clusters.size()] + Vector2(
				rng.randf_range(-110.0, 110.0), rng.randf_range(-90.0, 90.0))
		else:
			pos = rect.position + Vector2(rng.randf_range(20.0, 492.0), rng.randf_range(20.0, 492.0))
		if ObstacleField.blocks(pos, 18.0) or ObstacleField._in_interior_pocket(pos):
			continue
		var camp_delta := pos - WorldConfig.spawn_pos()
		if absf(camp_delta.x) < 130.0 and absf(camp_delta.y) < 340.0:
			continue
		# 落点按自身地形取样（交界块自然出现两群系道具混居）
		var terrain := BiomeMap.terrain_at(pos)
		var recipe: Dictionary = RECIPES.get(terrain, {})
		if recipe.is_empty():
			continue
		var kind := _pick_kind(recipe, rng)
		var s := rng.randf_range(0.8, 1.25)
		# 统一落影：脚下半透明椭圆，让地物"站"在地上（立体感的关键一招）；细软小道具收窄
		var sw := (6.0 if kind in SMALL_SHADOW_KINDS else 10.0) * s
		_bake_poly([Vector2(-sw, 0), Vector2(-sw * 0.5, -3), Vector2(sw * 0.5, -3), Vector2(sw, 0),
				Vector2(sw * 0.5, 3), Vector2(-sw * 0.5, 3)], Color(0, 0, 0, 0.28), pos, 0.0, s, points, colors, polys)
		if kind in TEXTURE_KINDS:
			var item := _texture_item(kind, rng, pos, s)
			if not item.is_empty():
				layer.items.append(item)
		else:
			# 多边形兜底类优先换烘焙精灵，无精灵再走多边形
			var poly_sp := _deco_sprite(kind)
			if poly_sp != null:
				layer.items.append({"pos": pos, "s": s,
					"flip": rng.randf() < 0.5, "mod": Color.WHITE, "sprite": poly_sp})
			else:
				_bake_deco(kind, rng, pos, points, colors, polys)
	var entry := {"layer": null, "baked": null}
	if not layer.items.is_empty():
		add_child(layer)
		entry["layer"] = layer
	if not polys.is_empty():
		var baked := Polygon2D.new()
		baked.polygon = points
		baked.vertex_colors = colors
		baked.polygons = polys
		baked.z_index = DECO_Z
		add_child(baked)
		entry["baked"] = baked
	_by_chunk[_key(origin)] = entry


func _on_chunk_freed(origin: Vector2i) -> void:
	var entry: Dictionary = _by_chunk.get(_key(origin), {})
	if entry.is_empty():
		return
	for node_name in ["layer", "baked"]:
		var node := entry[node_name] as Node
		if node != null:
			node.queue_free()
	_by_chunk.erase(_key(origin))


## 按配方权重随机挑种类
func _pick_kind(recipe: Dictionary, rng: RandomNumberGenerator) -> String:
	var total := 0
	for kind: String in recipe:
		total += int(recipe[kind])
	var roll := rng.randi_range(1, maxi(1, total))
	for kind: String in recipe:
		roll -= int(recipe[kind])
		if roll <= 0:
			return kind
	return recipe.keys()[0]


# --- 环境粒子（单例跟随，按地形切换） ---

func _configure_ambient(terrain: String) -> void:
	match terrain:
		"snow":
			_ambient.amount = 22
			_ambient.lifetime = 5.0
			_ambient.gravity = Vector2(6, 22)
			_ambient.initial_velocity_min = 8.0
			_ambient.initial_velocity_max = 20.0
			_ambient.scale_amount_min = 0.6
			_ambient.scale_amount_max = 1.6
			_ambient.color = Color(1, 1, 1, 0.75)
			_ambient.emitting = true
		"lava":
			_ambient.amount = 14
			_ambient.lifetime = 4.0
			_ambient.gravity = Vector2(0, -26)
			_ambient.initial_velocity_min = 4.0
			_ambient.initial_velocity_max = 14.0
			_ambient.scale_amount_min = 0.5
			_ambient.scale_amount_max = 1.4
			_ambient.color = Color(1.0, 0.55, 0.2, 0.8)
			_ambient.emitting = true
		"swamp":
			_ambient.amount = 8
			_ambient.lifetime = 6.0
			_ambient.gravity = Vector2(4, -4)
			_ambient.initial_velocity_min = 2.0
			_ambient.initial_velocity_max = 8.0
			_ambient.scale_amount_min = 2.0
			_ambient.scale_amount_max = 4.0
			_ambient.color = Color(0.7, 0.85, 0.65, 0.16)
			_ambient.emitting = true
		_:
			_ambient.emitting = false
			return
	_ambient.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_ambient.emission_rect_extents = Vector2(460, 300)


# --- 装饰物烘焙（多边形兜底类：贴图素材未覆盖的地形特色物） ---

## 单件装饰：套用缩放/旋转后把各部件多边形追加进顶点池（落影在 _on_chunk_ready 统一处理）
func _bake_deco(kind: String, rng: RandomNumberGenerator, pos: Vector2,
		points: PackedVector2Array, colors: PackedColorArray, polys: Array) -> void:
	var s := rng.randf_range(0.8, 1.25)
	var rot := rng.randf_range(-0.12, 0.12)
	match kind:
		"ice":
			_bake_poly([-4, 0, 0, -16, 4, 0], Color("#bcd8ea", 0.9), pos, rot, s, points, colors, polys)
			_bake_poly([0, -4, 6, -14, 8, -2], Color("#d8e8f2", 0.8), pos, rot, s, points, colors, polys)
		"snowpile":
			_bake_poly([-10, 0, -6, -4, 0, -6, 6, -4, 10, 0], Color("#e8eef4", 0.95), pos, rot, s, points, colors, polys)
		"puddle":
			_bake_poly([-14, 0, -8, -4, 4, -5, 12, -1, 8, 3, -6, 4], Color("#5d7a80", 0.55), pos, rot, s, points, colors, polys)
		"crystal":
			_bake_poly([-5, 0, 0, -18, 5, 0], Color("#5a2f2c"), pos, rot, s, points, colors, polys)
			_bake_poly([-3, 0, 0, -15, 3, 0], Color("#d8622a", 0.9), pos, rot, s, points, colors, polys)
			_bake_poly([2, -2, 7, -12, 9, -1], Color("#a8452a", 0.85), pos, rot, s, points, colors, polys)
		"bones":
			_bake_poly([-8, -2, -2, -3, -2, 0, -8, 1], Color("#cfc8b8", 0.9), pos, rot, s, points, colors, polys)
			_bake_poly([2, -1, 9, -2, 9, 1, 2, 1], Color("#cfc8b8", 0.9), pos, rot, s, points, colors, polys)
			_bake_poly([-2, -4, 2, -4, 2, 2, -2, 2], Color("#bfb8a6", 0.9), pos, rot, s, points, colors, polys)


## 精灵类装饰 → 绘制条目：big_tree/boulder = 基础精灵放大复用；枯树 = EP 真枯树
## 精灵（56 高树档）；缺图返回空字典，由调用方跳过该件
func _texture_item(kind: String, rng: RandomNumberGenerator, pos: Vector2, s: float) -> Dictionary:
	var src_key := kind
	var mod := Color.WHITE
	var scale_mult := 1.0
	var h := 0.0
	match kind:
		"big_tree":
			src_key = "tree"
			scale_mult = 1.8
		"boulder":
			src_key = "rock"
			scale_mult = 1.8
		"deadtree":
			h = 56.0  # EP 枯树：树形高件，超默认 32 档
	var sp := _deco_sprite(src_key)
	if sp == null:
		return {}
	# 素材内容偏紧凑，整体再放大一档贴回占地（v6 沿用既有调参）
	var item := {
		"pos": pos, "s": s * scale_mult * 1.25,
		"flip": rng.randf() < 0.5, "mod": mod,
		"sprite": sp,
	}
	if h > 0.0:
		item["h"] = h
	return item


## 部件多边形入池：局部顶点经 缩放→旋转→平移 后追加，记录子多边形索引；
## flat 数组（奇偶配对 xy）与 Vector2 数组都接受
func _bake_poly(part_pts: Array, color: Color, pos: Vector2, rot: float, s: float,
		points: PackedVector2Array, colors: PackedColorArray, polys: Array) -> void:
	var idx := PackedInt32Array()
	if part_pts.size() > 0 and not (part_pts[0] is Vector2):
		# flat 数组（奇偶配对 xy；字面量为 int）
		for i in part_pts.size() / 2:
			idx.append(points.size())
			points.append(pos + (Vector2(part_pts[i * 2], part_pts[i * 2 + 1]) * s).rotated(rot))
			colors.append(color)
	else:
		for pt: Vector2 in part_pts:
			idx.append(points.size())
			points.append(pos + (pt * s).rotated(rot))
			colors.append(color)
	polys.append(idx)


func _key(origin: Vector2i) -> String:
	return "%d,%d" % [origin.x, origin.y]
