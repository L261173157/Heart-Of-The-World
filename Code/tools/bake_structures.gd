## 建筑/结构烘焙（美术 v6 TS）：assets/ts/Buildings 整图裁内容 bbox →
## 就近邻缩放到目标世界高 → PNG 到 assets/ts/structures_baked/。
## 包内无宝箱/箭矢：chest 以 TS 色板程序合成、arrow 为 Archer 弹道 ÷4 缩图。
## 用法：-s tools/bake_structures.gd（重跑幂等覆盖）
extends SceneTree

const TS := "res://assets/ts/"
const OUT := "res://assets/ts/structures_baked/"

## 目标高（世界像素）：房屋对齐原 NA 烘焙件 ~128 档；城堡放大成地标气势
const STAMPS := {
	"ts_house1": {"src": "Buildings/Blue Buildings/House1.png", "h": 132},
	"ts_house2": {"src": "Buildings/Blue Buildings/House2.png", "h": 120},
	"ts_house3": {"src": "Buildings/Blue Buildings/House3.png", "h": 126},
	"ts_tower": {"src": "Buildings/Blue Buildings/Tower.png", "h": 156},
	"ts_barracks": {"src": "Buildings/Blue Buildings/Barracks.png", "h": 120},
	"ts_castle_black": {"src": "Buildings/Black Buildings/Castle.png", "h": 224},
	"ts_castle_red": {"src": "Buildings/Red Buildings/Castle.png", "h": 224},
}


func _bbox(img: Image) -> Rect2i:
	var min_x := 1 << 30
	var min_y := 1 << 30
	var max_x := -(1 << 30)
	var max_y := -(1 << 30)
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.08:
				min_x = mini(min_x, x)
				max_x = maxi(max_x, x)
				min_y = mini(min_y, y)
				max_y = maxi(max_y, y)
	if max_x < min_x:
		return Rect2i()
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for key: String in STAMPS:
		var cfg: Dictionary = STAMPS[key]
		var img := Image.load_from_file(ProjectSettings.globalize_path(TS + cfg["src"]))
		if img == null:
			push_warning("烘焙源缺失：" + cfg["src"])
			continue
		var b := _bbox(img)
		var crop := img.get_region(b)
		var th: int = cfg["h"]
		var tw := maxi(1, int(round(float(b.size.x) * float(th) / float(b.size.y))))
		crop.resize(tw, th, Image.INTERPOLATE_NEAREST)
		crop.save_png(ProjectSettings.globalize_path(OUT + key + ".png"))
		print("%-16s -> %s%s.png (%dx%d)" % [key, OUT, key, tw, th])
	# 弹道箭（Archer 附带件 ÷4 → 16px）
	var arrow := Image.load_from_file(ProjectSettings.globalize_path(
		TS + "Units/Blue Units/Archer/Arrow.png"))
	if arrow != null:
		arrow.resize(16, 16, Image.INTERPOLATE_NEAREST)
		arrow.save_png(ProjectSettings.globalize_path(OUT + "arrow.png"))
		print("%-16s -> %sarrow.png (16x16)" % ["arrow", OUT])
	_chest()
	_bake_props()
	quit(0)


## 世界装饰精灵（world_deco 的 assets/deco/<kind>.png 优先通道，v6 全面接管）：
## TS 树/岩/灌木/金块裁内容 bbox → 目标高（岩类较扁）→ 画布统一高 32（上留白）。
## 包内无蘑菇/香蒲/水洼：TS 色板合成。
const DECO_DIR := "res://assets/deco/"

## [源相对路径, 目标内容高, bake 可空, strip 帧宽可空（取帧 0）]
const PROPS := {
	"tree": ["Terrain/Resources/Wood/Trees/Tree1.png", 32, {}, 256],
	"pine": ["Terrain/Resources/Wood/Trees/Tree3.png", 32, {}, 256],
	"rock": ["Terrain/Decorations/Rocks/Rock1.png", 22, {}, 0],
	"grass": ["Terrain/Decorations/Bushes/Bushe1.png", 14, {}, 64],
	"bush": ["Terrain/Decorations/Bushes/Bushe3.png", 20, {}, 64],
	"log": ["Terrain/Resources/Wood/Trees/Stump 2.png", 16, {}, 0],
	"gems": ["Terrain/Resources/Gold/Gold Stones/Gold Stone 3.png", 14, {}, 0],
	"ice": ["Terrain/Decorations/Rocks/Rock1.png", 22, {"hue": 0.55, "sat": 0.35, "val": 1.25}, 0],
	"snowpile": ["Terrain/Decorations/Rocks/Rock2.png", 16, {"sat": 0.12, "val": 1.1}, 0],
	"crystal": ["Terrain/Decorations/Rocks/Rock4.png", 26, {"hue": 0.83, "sat": 0.55, "val": 1.1}, 0],
	"bones": ["Terrain/Decorations/Rocks/Rock3.png", 20, {"sat": 0.22, "val": 1.15}, 0],
}


func _bake_props() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DECO_DIR))
	for kind: String in PROPS:
		var spec: Array = PROPS[kind]
		var img := Image.load_from_file(ProjectSettings.globalize_path(TS + spec[0]))
		if img == null:
			push_warning("装饰源缺失：" + spec[0])
			continue
		if int(spec[3]) > 0:  # 树条带取帧 0
			img = img.get_region(Rect2i(0, 0, int(spec[3]), int(spec[3])))
		var b := _bbox(img)
		var crop := img.get_region(b)
		var bake: Dictionary = spec[2]
		if not bake.is_empty():
			_recolor(crop, bake)
		var th: int = spec[1]
		var tw := maxi(1, int(round(float(b.size.x) * float(th) / float(b.size.y))))
		crop.resize(tw, th, Image.INTERPOLATE_NEAREST)
		# 画布统一高 32（上留白），底边对齐——消费端按画布高定档
		var canvas := Image.create(tw, 32, false, Image.FORMAT_RGBA8)
		canvas.blit_rect(crop, Rect2i(Vector2i.ZERO, crop.get_size()), Vector2i(0, 32 - th))
		canvas.save_png(ProjectSettings.globalize_path(DECO_DIR + kind + ".png"))
		print("%-10s -> %s%s.png (%dx32)" % [kind, DECO_DIR, kind, tw])
	_synthesize_props()


func _recolor(img: Image, bake: Dictionary) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a < 0.05:
				continue
			var h: float = lerpf(c.h, float(bake.get("hue", c.h)), 0.7)
			img.set_pixel(x, y, Color.from_hsv(h,
				clampf(c.s * float(bake.get("sat", 1.0)), 0.0, 1.0),
				clampf(c.v * float(bake.get("val", 1.0)), 0.0, 1.0), c.a))


## TS 色板合成装饰（包内无对口）：蘑菇 / 香蒲 / 水洼
func _synthesize_props() -> void:
	# 蘑菇：红帽白点 + 白茎（10×10 逻辑 ×2）
	var m := Image.create(20, 20, false, Image.FORMAT_RGBA8)
	for y in 20:
		for x in 20:
			var d := Vector2(x - 9.5, y - 9.5) / Vector2(9.0, 6.0)
			if y <= 11 and d.length() <= 1.0:
				m.set_pixel(x, y, Color(0.82, 0.25, 0.22))
			if y >= 12 and absf(x - 9.5) <= 2.5 and y <= 18:
				m.set_pixel(x, y, Color(0.9, 0.86, 0.78))
	for pt: Vector2i in [Vector2i(7, 5), Vector2i(12, 6), Vector2i(9, 9)]:
		m.set_pixel(pt.x, pt.y, Color(0.95, 0.93, 0.88))
	m.save_png(ProjectSettings.globalize_path(DECO_DIR + "mushroom.png"))
	# 香蒲：绿茎 + 棕穗（12×22 逻辑 ×2）
	var ct := Image.create(24, 44, false, Image.FORMAT_RGBA8)
	for y in range(8, 44):
		ct.set_pixel(11, y, Color(0.3, 0.55, 0.28))
		ct.set_pixel(12, y, Color(0.25, 0.45, 0.24))
	for y in range(0, 18):
		for x in range(6, 19):
			var dd := Vector2(x - 11.5, y - 8.5) / Vector2(5.5, 8.5)
			if dd.length() <= 1.0:
				ct.set_pixel(x, y, Color(0.48, 0.35, 0.2))
	ct.save_png(ProjectSettings.globalize_path(DECO_DIR + "cattail.png"))
	# 水洼：water 色椭圆（半透明）
	var pd := Image.create(28, 10, false, Image.FORMAT_RGBA8)
	for y in 10:
		for x in 28:
			var dd := Vector2(x - 13.5, y - 4.5) / Vector2(13.0, 4.0)
			if dd.length() <= 1.0:
				pd.set_pixel(x, y, Color(0.28, 0.67, 0.66, 0.55))
	pd.save_png(ProjectSettings.globalize_path(DECO_DIR + "puddle.png"))
	print("mushroom/cattail/puddle -> 合成完成")


## TS 色板宝箱（22×16 逻辑 ×2）：木体 + 深描边 + 盖沿 + 双金带 + 锁扣
func _chest() -> void:
	var w := 22
	var h := 16
	var wood := Color(0.74, 0.52, 0.30)
	var dark := Color(0.33, 0.21, 0.12)
	var band := Color(0.56, 0.37, 0.20)
	var gold := Color(1.0, 0.82, 0.34)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var c := wood
			if x == 0 or x == w - 1 or y == 0 or y == h - 1:
				c = dark
			elif y == 4:
				c = band  # 盖沿分界
			elif x == 5 or x == 6 or x == 15 or x == 16:
				c = gold if y >= 4 else band  # 竖金带（盖以上随盖色）
			if (x == 9 or x == 12) and y >= 5 and y <= 9:
				c = dark  # 锁扣外框
			if x >= 10 and x <= 11 and y >= 6 and y <= 8:
				c = gold  # 锁芯
			img.set_pixel(x, y, c)
	img.resize(w * 2, h * 2, Image.INTERPOLATE_NEAREST)
	img.save_png(ProjectSettings.globalize_path(OUT + "chest.png"))
	print("%-16s -> %schest.png (%dx%d)" % ["chest", OUT, w * 2, h * 2])
