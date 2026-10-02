## 障碍瓦片集生成（世界 v5）：
## "$GODOT" --headless --path Code -s tools/generate_obstacle_tileset.gd
## 产出两个 TileSet（确定性，可重跑；贴图为内存构建的 PortableCompressedTexture2D 无损内嵌 .tres，
## 不产生需 import 的中间 PNG）：
##   data/obstacle_tileset.tres —— 可见障碍层用：图集（3×3 障碍格，源 TS deco 精灵
##     底边对齐/放大/调色派生）+ 物理层（墙 layer 1，按
##     ObstacleField.KIND_INFO 半径的八边形）+ 遮挡层（Light2D 阴影）+
##     y_sort_origin（树冠遮挡排序基线）+ kind 自定义数据
##   data/nav_tileset.tres —— 导航专用层用：透明可走瓦片 + 整格导航多边形
## 与 ObstacleField.KIND_INFO/RECIPES 的 kind 键一一对应；改障碍种类两边同步。
extends SceneTree

const TILESET_TRES := "res://data/obstacle_tileset.tres"
const NAV_TRES := "res://data/nav_tileset.tres"

const CELL := 32
## 图集画布与逻辑格解耦：大树不再被裁成一格，脚点仍是逻辑格中心。
const ART_CELL := 160
## kind 顺序 = 图集格序（col=i%3, row=i/3）；water 为透明深水阻挡瓦（第 4 行，
## 地面已画水只补碰撞，不留遮挡不留贴图）；castle 为城塞墙（美术 v6 Boss 地牢）
const KINDS := ["tree", "big_tree", "pine", "deadtree", "rock", "boulder",
	"ice", "crystal", "bones", "water", "castle"]
## 派生规则（美术 v6 TS）：img = assets/deco 精灵（tools/bake_structures.gd 产出，
## 树使用正确的 192px 单帧原图，去透明边后按内容高度缩放；
## 图集大画布保留完整树冠，逻辑格/碰撞/导航仍是32px。
const DERIVE := {
	"tree": {"img": "res://assets/ts/Terrain/Resources/Wood/Trees/Tree1.png", "frame": Vector2i(192, 256), "height": 96},
	"big_tree": {"img": "res://assets/ts/Terrain/Resources/Wood/Trees/Tree2.png", "frame": Vector2i(192, 256), "height": 124},
	"pine": {"img": "res://assets/ts/Terrain/Resources/Wood/Trees/Tree3.png", "frame": Vector2i(192, 192), "height": 104},
	"deadtree": {"img": "res://assets/deco/deadtree.png", "height": 96},
	"rock": {"img": "res://assets/deco/rock.png", "height": 32},
	"boulder": {"img": "res://assets/deco/rock.png", "height": 44},
	"ice": {"img": "res://assets/deco/ice.png", "height": 36},
	"crystal": {"img": "res://assets/deco/crystal.png", "height": 44},
	"bones": {"img": "res://assets/deco/bones.png", "height": 32},
	"water": {"transparent": true},
	"castle": {"src": Rect2(100, 168, 40, 40),
		"src_img": "res://assets/ts/structures_baked/ts_castle_black.png"},
}


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


## 障碍图集：逐 kind 取源（deco 精灵底边对齐 / castle 矩形）→ 调色/放大 → 拼入 3×3
func _build_atlas_image() -> Image:
	var atlas := Image.create(ART_CELL * 3, ART_CELL * 4, false, Image.FORMAT_RGBA8)
	for i in KINDS.size():
		var kind: String = KINDS[i]
		var spec: Dictionary = DERIVE[kind]
		if bool(spec.get("transparent", false)):
			continue
		var prop: Image
		if spec.has("img"):
			prop = Image.load_from_file(ProjectSettings.globalize_path(String(spec["img"])))
			if spec.has("frame"):
				prop = prop.get_region(Rect2i(Vector2i.ZERO, spec["frame"]))
			# 先去透明边，再缩放完整单帧；树干中心与碰撞中心同 x，不混入下一帧枝叶。
			prop = prop.get_region(prop.get_used_rect())
			prop = _recolor(prop, spec)
			var h: int = spec["height"]
			prop.resize(maxi(1, roundi(float(prop.get_width()) * h / prop.get_height())), h,
					Image.INTERPOLATE_NEAREST)
		else:
			var source := Image.load_from_file(ProjectSettings.globalize_path(String(spec["src_img"])))
			prop = source.get_region(Rect2i(spec["src"]))
			prop.resize(CELL, CELL, Image.INTERPOLATE_NEAREST)
		var base := Vector2i((i % 3) * ART_CELL, (i / 3) * ART_CELL)
		atlas.blit_rect(prop, Rect2i(Vector2i.ZERO, prop.get_size()),
				base + Vector2i((ART_CELL - prop.get_width()) / 2, ART_CELL - prop.get_height()))
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
	src.texture = _portable_texture(atlas)
	src.texture_region_size = Vector2i(ART_CELL, ART_CELL)
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
			td.y_sort_origin = 0
			continue
		# 纹理底边落在碰撞中心以下半径处，树冠向上长；排序始终在真实脚点。
		td.texture_origin = Vector2i(0, ART_CELL / 2 - roundi(r * 0.6))
		td.y_sort_origin = 0
		# 遮挡多边形：碰撞体的方化近似（阴影投射用，比碰撞略小留缝隙透气）
		var occ := OccluderPolygon2D.new()
		var os := r * 0.85
		occ.polygon = PackedVector2Array([
			Vector2(-os, -os), Vector2(os, -os), Vector2(os, os), Vector2(-os, os)])
		td.set_occluder(0, occ)
		if kind in ["tree", "big_tree", "pine"]:
			src.create_alternative_tile(coord, 1)
			var alternate := src.get_tile_data(coord, 1)
			alternate.texture_origin = td.texture_origin
			alternate.y_sort_origin = 0
			alternate.flip_h = true
			alternate.modulate = Color(0.86, 0.94, 0.91)
			alternate.set_custom_data("kind", kind)
			alternate.set_occluder(0, occ)
	_add_rootbeds(ts)
	return ts


## 密林低层仍画可碰撞的树桩/盘根灌木，不以透明瓦掩藏硬格。
func _add_rootbeds(ts: TileSet) -> void:
	const ROOT_CELL := 64
	var atlas := Image.create(ROOT_CELL * 3, ROOT_CELL, false, Image.FORMAT_RGBA8)
	for i in 3:
		var source_path := "res://assets/ts/Terrain/Resources/Wood/Trees/Stump 1.png" if i != 1 else "res://assets/deco/deadtree.png"
		var prop := Image.load_from_file(ProjectSettings.globalize_path(source_path))
		prop = prop.get_region(prop.get_used_rect())
		var h := 28 if i == 0 else 40
		prop.resize(roundi(float(prop.get_width()) * h / prop.get_height()), h, Image.INTERPOLATE_NEAREST)
		var root := Vector2i(i * ROOT_CELL, 0)
		if i == 2:
			var leaves := Image.load_from_file(ProjectSettings.globalize_path("res://assets/ts/Terrain/Decorations/Bushes/Bushe3.png"))
			leaves = leaves.get_region(Rect2i(0, 0, 128, 128))
			leaves = leaves.get_region(leaves.get_used_rect())
			leaves.resize(44, 32, Image.INTERPOLATE_NEAREST)
			atlas.blit_rect(leaves, Rect2i(Vector2i.ZERO, leaves.get_size()), root + Vector2i(10, 16))
			prop.resize(32, 26, Image.INTERPOLATE_NEAREST)
		atlas.blend_rect(prop, Rect2i(Vector2i.ZERO, prop.get_size()),
				root + Vector2i((ROOT_CELL - prop.get_width()) / 2, ROOT_CELL - prop.get_height()))
	var src := TileSetAtlasSource.new()
	src.texture = _portable_texture(atlas)
	src.texture_region_size = Vector2i(ROOT_CELL, ROOT_CELL)
	ts.add_source(src, 1)
	for i in 3:
		var coord := Vector2i(i, 0)
		src.create_tile(coord)
		var td := src.get_tile_data(coord, 0)
		td.texture_origin = Vector2i(0, ROOT_CELL / 2 - 6)
		td.y_sort_origin = 0
		td.set_custom_data("kind", "wood_roots")
		var occ := OccluderPolygon2D.new()
		occ.polygon = PackedVector2Array([Vector2(-8,-8),Vector2(8,-8),Vector2(8,8),Vector2(-8,8)])
		td.set_occluder(0, occ)


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


## 内嵌无损压缩，保留原.tres路径且免生成PNG/import依赖；4.7 ClassDB API实测。
## 原RGBA数字数组约4MB，无损压缩buffer仅几十KB，运行仍是同一像素图。
func _portable_texture(img: Image) -> PortableCompressedTexture2D:
	var tex := PortableCompressedTexture2D.new()
	tex.keep_compressed_buffer = true
	tex.create_from_image(img, PortableCompressedTexture2D.COMPRESSION_MODE_LOSSLESS)
	assert(tex.get_image().get_data() == img.get_data(), "内嵌压缩必须逐像素无损")
	return tex


func _octagon(r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var k := r * 0.4142  # tan(22.5°)：八边形边点到轴向点
	for v in [Vector2(0, -r), Vector2(k, -k), Vector2(r, 0), Vector2(k, k),
			Vector2(0, r), Vector2(-k, k), Vector2(-r, 0), Vector2(-k, -k)]:
		pts.append(v)
	return pts
