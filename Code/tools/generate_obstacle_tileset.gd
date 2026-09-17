## 障碍瓦片集生成（世界 v5）：
## "$GODOT" --headless --path Code -s tools/generate_obstacle_tileset.gd
## 产出两个 TileSet（确定性，可重跑；贴图为内存构建的 ImageTexture 内嵌 .tres，
## 不产生需 import 的中间 PNG）：
##   data/obstacle_tileset.tres —— 可见障碍层用：图集（3×3 障碍格，源 na_tileset
##     已验证矩形 + 放大/调色派生，零新素材）+ 物理层（墙 layer 1，按
##     ObstacleField.KIND_INFO 半径的八边形）+ 遮挡层（Light2D 阴影）+
##     y_sort_origin（树冠遮挡排序基线）+ kind 自定义数据
##   data/nav_tileset.tres —— 导航专用层用：透明可走瓦片 + 整格导航多边形
## 与 ObstacleField.KIND_INFO/RECIPES 的 kind 键一一对应；改障碍种类两边同步。
extends SceneTree

const SRC := "res://assets/creatures/sheets/na_tileset.png"
const TILESET_TRES := "res://data/obstacle_tileset.tres"
const NAV_TRES := "res://data/nav_tileset.tres"

const CELL := 32
## kind 顺序 = 图集格序（col=i%3, row=i/3）；water 为透明深水阻挡瓦（第 4 行，
## 地面已画水只补碰撞，不留遮挡不留贴图）；castle 为城塞墙（美术 v5 Boss 地牢）
const KINDS := ["tree", "big_tree", "pine", "deadtree", "rock", "boulder",
	"ice", "crystal", "bones", "water", "castle"]
## 派生规则：src = na_tileset 已验证矩形；zoom>1 时裁底居中；HSV 调色
## （deadtree=松树灰化、ice/crystal/bones=岩石染色——与 world_deco 的
## 枯树灰化/多边形冰晶手法同源，素材无对口验证矩形故派生）
## castle：城堡石砖区（行 5-8 左区，对照板视觉验收的灰石砖+垛口带）
const DERIVE := {
	"tree": {"src": Rect2(0, 160, 32, 32)},
	"big_tree": {"src": Rect2(0, 160, 32, 32), "zoom": 1.35},
	"pine": {"src": Rect2(64, 160, 32, 32)},
	"deadtree": {"src": Rect2(64, 160, 32, 32), "sat": 0.22, "val": 0.85},
	"rock": {"src": Rect2(160, 160, 32, 32)},
	"boulder": {"src": Rect2(160, 160, 32, 32), "zoom": 1.35},
	"ice": {"src": Rect2(160, 160, 32, 32), "hue": 0.55, "sat": 0.35, "val": 1.25},
	"crystal": {"src": Rect2(160, 160, 32, 32), "hue": 0.83, "sat": 0.55, "val": 1.1},
	"bones": {"src": Rect2(160, 160, 32, 32), "sat": 0.25, "val": 1.2},
	"water": {"transparent": true},
	"castle": {"src": Rect2(32, 88, 32, 32)},
}
## 高大障碍的排序基线（y_sort_origin，格底部附近）——走到树后会被树冠遮挡
const TALL_SORT_ORIGIN := 14
const FLAT_SORT_ORIGIN := 10
## 深水阻挡瓦的排序基线（不参与 y-sort 前后关系，纯地面层）
const WATER_SORT_ORIGIN := 0


func _init() -> void:
	var atlas := _build_atlas_image()
	var ts := _build_obstacle_tileset(atlas)
	var err := ResourceSaver.save(ts, TILESET_TRES)
	if err != OK:
		push_error("障碍 TileSet 保存失败：%d" % err)
	var nav := _build_nav_tileset()
	err = ResourceSaver.save(nav, NAV_TRES)
	if err != OK:
		push_error("导航 TileSet 保存失败：%d" % err)
	print("已生成：%s / %s" % [TILESET_TRES, NAV_TRES])
	quit(0)


## 障碍图集：逐 kind 从 na_tileset 取源矩形 → 调色/放大 → 拼入 3×3 图集
func _build_atlas_image() -> Image:
	var src_tex: Image = load(SRC).get_image()
	var atlas := Image.create(CELL * 3, CELL * 4, false, Image.FORMAT_RGBA8)
	for i in KINDS.size():
		var kind: String = KINDS[i]
		var spec: Dictionary = DERIVE[kind]
		if bool(spec.get("transparent", false)):
			continue  # 透明瓦（深水）：只占图集位不画内容
		var rect: Rect2 = spec["src"]
		var cell_img: Image = src_tex.get_region(Rect2i(Vector2i(rect.position), Vector2i(rect.size)))
		cell_img = _recolor(cell_img, spec)
		var zoom: float = float(spec.get("zoom", 1.0))
		if zoom > 1.001:
			var big := cell_img
			big.resize(int(CELL * zoom), int(CELL * zoom), Image.INTERPOLATE_NEAREST)
			# 裁底居中：保底部（树干/岩基）牺牲顶部
			cell_img = big.get_region(Rect2i(
				Vector2i(int((big.get_width() - CELL) * 0.5), big.get_height() - CELL),
				Vector2i(CELL, CELL)))
		atlas.blit_rect(cell_img, Rect2i(Vector2i.ZERO, Vector2i(CELL, CELL)),
				Vector2i((i % 3) * CELL, (i / 3) * CELL))
	return atlas


func _recolor(img: Image, spec: Dictionary) -> Image:
	if not spec.has("hue") and not spec.has("sat") and not spec.has("val"):
		return img
	var out: Image = img.duplicate()
	for y in out.get_height():
		for x in out.get_width():
			var c: Color = out.get_pixel(x, y)
			if c.a < 0.05:
				continue
			var h: float = c.h
			var s: float = c.s * float(spec.get("sat", 1.0))
			var v: float = c.v * float(spec.get("val", 1.0))
			if spec.has("hue"):
				h = lerpf(c.h, float(spec["hue"]), 0.7)
			out.set_pixel(x, y, Color.from_hsv(h, clampf(s, 0.0, 1.0), clampf(v, 0.0, 1.0), c.a))
	return out


## 可见障碍层 TileSet：物理（墙）+ 遮挡（阴影）+ y 排序 + kind 数据。
## 碰撞为八边形近似圆（TileData 物理只收多边形），半径与 KIND_INFO 一致
func _build_obstacle_tileset(atlas: Image) -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(CELL, CELL)
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, 1)  # 墙层：玩家/怪/弹幕现有约定
	ts.set_physics_layer_collision_mask(0, 0)
	ts.add_occlusion_layer()
	ts.add_custom_data_layer()
	ts.set_custom_data_layer_name(0, "kind")
	ts.set_custom_data_layer_type(0, TYPE_STRING)
	var src := TileSetAtlasSource.new()
	src.texture = ImageTexture.create_from_image(atlas)
	src.texture_region_size = Vector2i(CELL, CELL)
	# 先挂 source 再写 TileData：未挂载的 source 取到的 TileData 无 tile_set 引用，
	# 物理层/遮挡层写入会因越界静默失败
	ts.add_source(src, 0)
	for i in KINDS.size():
		var kind: String = KINDS[i]
		var coord := Vector2i(i % 3, i / 3)
		src.create_tile(coord)
		var td := src.get_tile_data(coord, 0)
		td.set_custom_data("kind", kind)
		var info: Dictionary = ObstacleField.KIND_INFO[kind]
		var r: float = float(info["r"])
		td.set_collision_polygons_count(0, 1)
		td.set_collision_polygon_points(0, 0, _octagon(r))
		if kind == "water":
			# 深水：透明地面层——不参与 y-sort、不投影（水面不挡光）
			td.y_sort_origin = WATER_SORT_ORIGIN
			continue
		td.y_sort_origin = TALL_SORT_ORIGIN if bool(info["tall"]) else FLAT_SORT_ORIGIN
		# 遮挡多边形：碰撞体的方化近似（阴影投射用，比碰撞略小留缝隙透气）
		var occ := OccluderPolygon2D.new()
		var os := r * 0.85
		occ.polygon = PackedVector2Array([
			Vector2(-os, -os), Vector2(os, -os), Vector2(os, os), Vector2(-os, os)])
		td.set_occluder(0, occ)
	return ts


## 导航专用 TileSet：一张透明可走瓦片带整格导航多边形。
## 相邻可走格的导航多边形共享边缘顶点（-16/16 网格线）→ 层内导航图连通
func _build_nav_tileset() -> TileSet:
	var walk := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	walk.fill(Color(1, 1, 1, 0))
	var ts := TileSet.new()
	ts.tile_size = Vector2i(CELL, CELL)
	ts.add_navigation_layer()
	var src := TileSetAtlasSource.new()
	src.texture = ImageTexture.create_from_image(walk)
	src.texture_region_size = Vector2i(4, 4)
	ts.add_source(src, 0)  # 先挂载再写 TileData（同上）
	src.create_tile(Vector2i.ZERO)
	var td := src.get_tile_data(Vector2i.ZERO, 0)
	var nav := NavigationPolygon.new()
	nav.vertices = PackedVector2Array([
		Vector2(-16, -16), Vector2(16, -16), Vector2(16, 16), Vector2(-16, 16)])
	nav.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	td.set_navigation_polygon(0, nav)
	return ts


func _octagon(r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var k := r * 0.4142  # tan(22.5°)：八边形边点到轴向点
	for v in [Vector2(0, -r), Vector2(k, -k), Vector2(r, 0), Vector2(k, k),
			Vector2(0, r), Vector2(-k, k), Vector2(-r, 0), Vector2(-k, -k)]:
		pts.append(v)
	return pts
