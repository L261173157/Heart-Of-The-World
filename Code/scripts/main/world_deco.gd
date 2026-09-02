## 世界环境表现层（纯视觉，无碰撞无逻辑影响）：
## ① 程序地物装饰——按地形在每区域撒树/岩/晶石/雪松等 Polygon2D 组合（固定 seed 可复现）
## ② 区域氛围色调——低透明度叠色（雪偏冷/熔岩偏暖/沼泽偏绿雾），压住区域间的割裂感
## ③ 环境粒子——雪原飘雪、熔岩升火星、沼泽浮雾（CPUParticles2D 局部量少省电）
## 挂载于 game_world；只读模拟区域配置，不触碰模拟状态。
class_name WorldDeco
extends Node2D

## 每地形装饰配方：类型 → 数量（密度按"簇状撒布"成团出现，避免均匀稀疏的空旷感）
const RECIPES := {
	"plains": {"tree": 18, "rock": 12, "grass": 22},
	"forest": {"big_tree": 34, "mushroom": 12, "log": 8},
	"snow": {"pine": 26, "ice": 12, "snowpile": 14},
	"swamp": {"deadtree": 22, "mushroom": 10, "puddle": 10},
	"hill": {"boulder": 26, "rock": 16},
	"lava": {"crystal": 22, "bones": 10},
}

## 区域氛围色（低透明叠色）
const TINTS := {
	"snow": Color(0.55, 0.7, 0.95, 0.07),
	"lava": Color(1.0, 0.45, 0.15, 0.08),
	"swamp": Color(0.5, 0.75, 0.4, 0.06),
	"forest": Color(0.6, 0.85, 0.5, 0.04),
}

const DECO_Z := -1     # 地物在怪物之下
const TINT_Z := 4      # 氛围色在角色之上（盖住整个区域的空气感）
const PARTICLE_Z := 5


func _ready() -> void:
	# 等 game_world setup 完成后再构建（由 add_child 时机保证：sim 已就绪）
	var world := get_parent()
	for region: SimRegion in world._sim.regions.values():
		_seed_deco(region)
		_seed_tint(region)
		_seed_particles(region)


## 地物装饰：簇状撒布——先定簇心，装饰围绕簇心聚团（70%），三成均匀散布；
## 避开区域中心锚点 70px（怪物出生区不被遮挡）。
## 整个区域的装饰烘焙进单个 Polygon2D（顶点池 + 子多边形索引 + 顶点色）：
## 原先每件 2~4 个节点、全图 700+ 件 ≈ 2000+ 节点，合并后每区域 1 个节点，
## 形状定义不变、视觉等价，消掉场景树与绘制提交的节点开销。
func _seed_deco(region: SimRegion) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(region.id) & 0x7FFFFFFF
	var recipe: Dictionary = RECIPES.get(region.terrain, {})
	var half := region.size / 2.0
	var clusters: Array[Vector2] = []
	for i in 6:
		clusters.append(region.center + Vector2(
			rng.randf_range(-half.x + 120.0, half.x - 120.0),
			rng.randf_range(-half.y + 100.0, half.y - 100.0)))
	var points := PackedVector2Array()
	var colors := PackedColorArray()
	var polys: Array = []
	for kind: String in recipe:
		for i in int(recipe[kind]):
			var pos: Vector2
			if rng.randf() < 0.7 and not clusters.is_empty():
				pos = clusters[rng.randi() % clusters.size()] + Vector2(
					rng.randf_range(-110.0, 110.0), rng.randf_range(-90.0, 90.0))
			else:
				pos = region.center + Vector2(
					rng.randf_range(-half.x + 50.0, half.x - 50.0),
					rng.randf_range(-half.y + 50.0, half.y - 50.0))
			# 收回越界点，避开中心锚点
			pos.x = clampf(pos.x, region.center.x - half.x + 40.0, region.center.x + half.x - 40.0)
			pos.y = clampf(pos.y, region.center.y - half.y + 40.0, region.center.y + half.y - 40.0)
			if pos.distance_to(region.center) < 70.0:
				continue
			_bake_deco(kind, rng, pos, points, colors, polys)
	if polys.is_empty():
		return
	var baked := Polygon2D.new()
	baked.polygon = points
	baked.vertex_colors = colors
	baked.polygons = polys
	baked.z_index = DECO_Z
	add_child(baked)


func _seed_tint(region: SimRegion) -> void:
	var tint: Color = TINTS.get(region.terrain, Color.TRANSPARENT)
	if tint.a <= 0.0:
		return
	var poly := Polygon2D.new()
	var half := region.size / 2.0
	poly.polygon = PackedVector2Array([
		-half, Vector2(half.x, -half.y), half, Vector2(-half.x, half.y),
	])
	poly.color = tint
	poly.position = region.center
	poly.z_index = TINT_Z
	add_child(poly)


func _seed_particles(region: SimRegion) -> void:
	# 只有三种地形有环境粒子；其余直接跳过，不为一次释放白建节点
	if not (region.terrain in ["snow", "lava", "swamp"]):
		return
	var p := CPUParticles2D.new()
	match region.terrain:
		"snow":
			p.amount = 22
			p.lifetime = 5.0
			p.gravity = Vector2(6, 22)
			p.initial_velocity_min = 8.0
			p.initial_velocity_max = 20.0
			p.scale_amount_min = 0.6
			p.scale_amount_max = 1.6
			p.color = Color(1, 1, 1, 0.75)
		"lava":
			p.amount = 14
			p.lifetime = 4.0
			p.gravity = Vector2(0, -26)
			p.initial_velocity_min = 4.0
			p.initial_velocity_max = 14.0
			p.scale_amount_min = 0.5
			p.scale_amount_max = 1.4
			p.color = Color(1.0, 0.55, 0.2, 0.8)
		"swamp":
			p.amount = 8
			p.lifetime = 6.0
			p.gravity = Vector2(4, -4)
			p.initial_velocity_min = 2.0
			p.initial_velocity_max = 8.0
			p.scale_amount_min = 2.0
			p.scale_amount_max = 4.0
			p.color = Color(0.7, 0.85, 0.65, 0.16)
		_:
			p.queue_free()
			return
	p.position = region.center
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = region.size / 2.0
	p.z_index = PARTICLE_Z
	add_child(p)


# --- 装饰物烘焙（形状定义不变，占位几何；素材期可整体替换为精灵） ---

## 单件装饰：套用落影/缩放/旋转/落点后，把各部件多边形追加进区域顶点池
func _bake_deco(kind: String, rng: RandomNumberGenerator, pos: Vector2,
		points: PackedVector2Array, colors: PackedColorArray, polys: Array) -> void:
	var s := rng.randf_range(0.8, 1.25)
	var rot := rng.randf_range(-0.12, 0.12)
	# 统一落影：脚下半透明椭圆，让地物"站"在地上（立体感的关键一招）
	var sw := 10.0 * s
	_bake_poly([Vector2(-sw, 0), Vector2(-sw * 0.5, -3), Vector2(sw * 0.5, -3), Vector2(sw, 0),
			Vector2(sw * 0.5, 3), Vector2(-sw * 0.5, 3)], Color(0, 0, 0, 0.28), pos, rot, s, points, colors, polys)
	match kind:
		"tree":
			_bake_poly([-3, 0, 3, 0, 3, -10, -3, -10], Color("#6b4a33"), pos, rot, s, points, colors, polys)  # 干
			_bake_poly([-12, -8, 12, -8, 0, -30], Color("#4d7038"), pos, rot, s, points, colors, polys)  # 冠
		"big_tree":
			_bake_poly([-4, 0, 4, 0, 4, -12, -4, -12], Color("#5d4030"), pos, rot, s, points, colors, polys)
			_bake_poly([-16, -10, 16, -10, 0, -36], Color("#3f5e30"), pos, rot, s, points, colors, polys)
			_bake_poly([-11, -20, 11, -20, 0, -40], Color("#4d7038"), pos, rot, s, points, colors, polys)
		"grass":
			for blade in 3:
				var bx := (blade - 1) * 4.0
				_bake_poly([Vector2(bx - 1, 0), Vector2(bx + 1, 0),
						Vector2(bx + rng.randf_range(0.5, 1.5), -7)],
						Color("#7fa055").darkened(rng.randf_range(0.0, 0.2)), pos, rot, s, points, colors, polys)
		"pine":
			_bake_poly([-3, 0, 3, 0, 3, -8, -3, -8], Color("#5a4634"), pos, rot, s, points, colors, polys)
			_bake_poly([-11, -6, 11, -6, 0, -26], Color("#37503c"), pos, rot, s, points, colors, polys)
			_bake_poly([-8, -16, 8, -16, 0, -32], Color("#e6ecf0"), pos, rot, s, points, colors, polys)  # 积雪
		"deadtree":
			_bake_poly([-3, 0, 3, 0, 2, -24, -2, -24], Color("#4a4238"), pos, rot, s, points, colors, polys)
			_bake_poly([0, -12, 12, -20, 13, -17, 1, -9], Color("#4a4238"), pos, rot, s, points, colors, polys)  # 枝
		"rock", "boulder":
			var scale_mult := 1.0 if kind == "rock" else 1.8
			var pts: Array = []
			for pt in [Vector2(-7, 0), Vector2(-5, -5), Vector2(0, -7), Vector2(5, -5), Vector2(7, 0)]:
				pts.append(pt * scale_mult)
			_bake_poly(pts, Color("#7d7669").darkened(rng.randf_range(0.0, 0.15)), pos, rot, s, points, colors, polys)
		"ice":
			_bake_poly([-4, 0, 0, -16, 4, 0], Color("#bcd8ea", 0.9), pos, rot, s, points, colors, polys)
			_bake_poly([0, -4, 6, -14, 8, -2], Color("#d8e8f2", 0.8), pos, rot, s, points, colors, polys)
		"snowpile":
			_bake_poly([-10, 0, -6, -4, 0, -6, 6, -4, 10, 0], Color("#e8eef4", 0.95), pos, rot, s, points, colors, polys)
		"mushroom":
			_bake_poly([-2, 0, 2, 0, 2, -4, -2, -4], Color("#d8cfc0"), pos, rot, s, points, colors, polys)
			_bake_poly([-5, -4, 5, -4, 3, -8, -3, -8], Color("#a05a4a"), pos, rot, s, points, colors, polys)
		"log":
			_bake_poly([-14, -3, 14, -3, 14, 3, -14, 3], Color("#5d4a38"), pos, rot, s, points, colors, polys)
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
