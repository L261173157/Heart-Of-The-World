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
	# Enemy Pack 弹体首帧（条带取第 0 帧 ÷4；法弹 128 帧 → 32px）
	var EP := "res://assets/ts_enemy/"
	const EP_BOLTS := {
		"acorn": ["Slingshot Gnome/Acorn_Projectile.png", 64, 16],
		"bone": ["Gnoll/Gnoll_Bone.png", 64, 16],
		"harpoon": ["Harpoon Shark/Harpoon.png", 64, 16],
		"spell": ["Hex Shaman/Hex Shaman_Projectile.png", 128, 32],
		"bomb": ["Bomb Fish/Bomb_Idle.png", 128, 16],
	}
	for key: String in EP_BOLTS:
		var cfg: Array = EP_BOLTS[key]
		var src := Image.load_from_file(ProjectSettings.globalize_path(EP + cfg[0]))
		if src == null:
			push_warning("EP 弹体源缺失：" + cfg[0])
			continue
		var cell: int = cfg[1]
		var frame := src.get_region(Rect2i(0, 0, cell, cell))
		var sz: int = cfg[2]
		frame.resize(sz, sz, Image.INTERPOLATE_NEAREST)
		frame.save_png(ProjectSettings.globalize_path(OUT + key + ".png"))
		print("%-16s -> %s%s.png (%dx%d)" % [key, OUT, key, sz, sz])
	# EP 场景装饰件（真骨堆升级/骷髅桩/枯树 → assets/deco/，world_deco 消费）。
	# 放在 _bake_props 之后跑：bones.png 由本段最终覆盖（旧 Stump 派生源已失散）
	const EPX := "res://assets/ts_enemy_extra/"
	const EP_PROPS := {
		"bones": ["Skull decorations/Bones_01.png", 32],
		"skullspike": ["Skull decorations/Skull Spike_01.png", 32],
		"deadtree": ["Dead Tree/Dead Tree.png", 64],
	}
	_chest()
	_bake_props()
	for key: String in EP_PROPS:
		var cfg: Array = EP_PROPS[key]
		var src := Image.load_from_file(ProjectSettings.globalize_path(EPX + cfg[0]))
		if src == null:
			push_warning("EP 装饰源缺失：" + cfg[0])
			continue
		var b := _bbox(src)
		var crop := src.get_region(b)
		var th: int = cfg[1]
		var tw := maxi(1, int(round(float(b.size.x) * float(th) / float(b.size.y))))
		crop.resize(tw, th, Image.INTERPOLATE_NEAREST)
		crop.save_png(ProjectSettings.globalize_path(DECO_DIR + key + ".png"))
		print("%-16s -> %s%s.png (%dx%d)" % [key, DECO_DIR, key, tw, th])
	_bake_ui_icons()
	quit(0)


## ============================ UI 图标产线（美术 v6 P4） ============================
## 产出 assets/ts/icons/<name>.png：TS Icons/Tools 对位直拷、HSV 变体、
## TS 色板合成（包内无对口）。消费方：hud.gd 图标常量、item_catalog、对话框。
const ICONS_DIR := "res://assets/ts/icons/"
const UI_SRC := "res://assets/ts/UI Elements/UI Elements/"

## [源绝对 res 路径, bake 可空]（合成件在 _synth_ui 里单独画）
const UI_ICONS := {
	"attack": [UI_SRC + "Icons/Icon_05.png", {}],
	"heavy": [UI_SRC + "Icons/Icon_01.png", {}],
	"empower": [UI_SRC + "Icons/Icon_11.png", {}],
	"eco": [UI_SRC + "Icons/Icon_07.png", {}],
	"shop": [UI_SRC + "Icons/Icon_03.png", {}],
	"coin": [UI_SRC + "Icons/Icon_03.png", {}],
	"codex": [UI_SRC + "Icons/Icon_12.png", {}],
	"cdr": [UI_SRC + "Icons/Icon_09.png", {}],
	"settings": [UI_SRC + "Icons/Icon_12.png", {}],
	"hp_pot_blue": [UI_SRC + "Icons/Icon_08.png", {}],
	"heal_pot_red": [UI_SRC + "Icons/Icon_08.png", {"hue": -0.05, "sat": 1.3, "val": 1.0}],
	"mp_pot_green": [UI_SRC + "Icons/Icon_08.png", {"hue": 0.28, "sat": 1.0, "val": 1.0}],
	"beaf": [UI_SRC + "Icons/Icon_04.png", {}],
	"octopus": [UI_SRC + "Icons/Icon_04.png", {"hue": 0.72, "sat": 0.8}],
	"tea_leaf": [UI_SRC + "Icons/Icon_02.png", {"hue": 0.13, "sat": 1.1}],
	"scroll_fire": [UI_SRC + "Icons/Icon_12.png", {"hue": -0.06, "sat": 1.35}],
	"scroll_rock": [UI_SRC + "Icons/Icon_12.png", {"sat": 0.25, "val": 1.05}],
	"katana": ["res://assets/ts/Terrain/Resources/Tools/Tool_03.png", {}],
	"fork": ["res://assets/ts/Terrain/Resources/Tools/Tool_01.png", {}],
	"sai": ["res://assets/ts/Terrain/Resources/Tools/Tool_04.png", {}],
	"knock_axe": ["res://assets/ts/Terrain/Resources/Tools/Tool_01.png", {}],
	"bolt": ["res://assets/ts/fx_generated/orb_core.png", {}],
	"save": [OUT + "chest.png", {}],
}


func _bake_ui_icons() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ICONS_DIR))
	for icon_name: String in UI_ICONS:
		var spec: Array = UI_ICONS[icon_name]
		var img := Image.load_from_file(ProjectSettings.globalize_path(spec[0]))
		if img == null:
			push_warning("UI 图标源缺失：" + spec[0])
			continue
		var bake: Dictionary = spec[1]
		if not bake.is_empty():
			_recolor(img, bake)
		img.save_png(ProjectSettings.globalize_path(ICONS_DIR + icon_name + ".png"))
	# 血条贴图：BigBar_Fill 烘三色（平铺填充），SmallBar_Base 直拷（九宫框）
	var fill := Image.load_from_file(ProjectSettings.globalize_path(
		UI_SRC + "Bars/BigBar_Fill.png"))
	if fill != null:
		for pair: Array in [["bar_fill_red", {"hue": -0.02, "sat": 1.25}],
				["bar_fill_blue", {"hue": 0.58, "sat": 1.0}],
				["bar_fill_gold", {"hue": 0.11, "sat": 1.1, "val": 1.05}]]:
			var img: Image = fill.duplicate()
			_recolor(img, pair[1])
			img.save_png(ProjectSettings.globalize_path(ICONS_DIR + pair[0] + ".png"))
	var base := Image.load_from_file(ProjectSettings.globalize_path(
		UI_SRC + "Bars/SmallBar_Base.png"))
	if base != null:
		base.save_png(ProjectSettings.globalize_path(ICONS_DIR + "bar_base.png"))
	_synth_ui()
	print("UI 图标产线完成 -> ", ICONS_DIR)


## TS 色板合成件（包内无对口）：疾风符/红心条带/金星/皮袋/钥匙/鱼/虾/饭团/寿司/
## 播放三角/头像框
func _synth_ui() -> void:
	var c_wood := Color(0.74, 0.52, 0.30)
	var c_dark := Color(0.33, 0.21, 0.12)
	var c_gold := Color(1.0, 0.82, 0.34)
	var c_white := Color(1.0, 0.98, 0.94)
	var c_red := Color(0.85, 0.25, 0.22)
	# 疾风符（dash）：三条白速度线 + 青点
	var dash := Image.create(48, 28, false, Image.FORMAT_RGBA8)
	for k in 3:
		var y := 4 + k * 8
		var line_len := 30 - k * 4
		for x in line_len:
			dash.set_pixel(x + k * 6, y, c_white)
			dash.set_pixel(x + k * 6, y + 1, Color(0.7, 0.88, 1.0, 0.8))
	for dy in 3:
		for dx in 3:
			dash.set_pixel(40 + dx, 12 + dy, Color(0.5, 0.85, 1.0))
	dash.save_png(ProjectSettings.globalize_path(ICONS_DIR + "dash.png"))
	# 红心条带（5 帧 ×16px：满→空，帧内=红行数递减）
	var strip := Image.create(80, 16, false, Image.FORMAT_RGBA8)
	for f in 5:
		var fill_rows := 4 - f
		for y in 16:
			for x in 16:
				var p := Vector2(x - 7.5, y - 8.5)
				var in_heart: bool = (p.y > -1.0 and p.y < 5.0 and absf(p.x) < 7.0 - maxf(0.0, p.y - 3.0)) \
						or (p.y <= -1.0 and Vector2(absf(p.x) - 3.0, p.y + 1.0).length() < 3.6)
				if not in_heart:
					continue
				var red_row: bool = p.y < 4.0 - float(fill_rows)
				strip.set_pixel(f * 16 + x, y, c_red if red_row else c_white)
	strip.save_png(ProjectSettings.globalize_path(ICONS_DIR + "heart_strip.png"))
	strip.get_region(Rect2i(0, 0, 16, 16)).save_png(
		ProjectSettings.globalize_path(ICONS_DIR + "heart.png"))
	# 金星（xp）
	var star := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var v := Vector2(x - 15.5, y - 15.5)
			var a := absf(atan2(v.y, v.x))
			var star_r := 6.0 + 9.0 * (1.0 - absf(fmod(a, TAU / 5.0) / (TAU / 5.0) * 2.0 - 1.0))
			if v.length() < star_r:
				star.set_pixel(x, y, c_gold if v.length() > star_r - 4.0 else c_white)
	star.save_png(ProjectSettings.globalize_path(ICONS_DIR + "star_gold.png"))
	# 皮袋（bag）
	var bag := Image.create(40, 36, false, Image.FORMAT_RGBA8)
	for y in 36:
		for x in 40:
			var p := Vector2(x - 19.5, y - 18.0) / Vector2(13.0, 14.0)
			if p.length() <= 1.0 and y > 8:
				bag.set_pixel(x, y, c_wood)
			if absf(p.x) < 0.42 and y >= 6 and y <= 11:
				bag.set_pixel(x, y, c_dark)
	for x in range(13, 27):
		bag.set_pixel(x, 7, c_dark)
		bag.set_pixel(x, 8, c_gold)
	bag.save_png(ProjectSettings.globalize_path(ICONS_DIR + "bag.png"))
	# 钥匙（银/金）
	for pair: Array in [["key_silver", Color(0.78, 0.8, 0.85)], ["key_gold", c_gold]]:
		var key := Image.create(40, 24, false, Image.FORMAT_RGBA8)
		for y in range(4, 20):
			for x in range(2, 16):
				var d := Vector2(x - 8.5, y - 11.5) / Vector2(6.0, 7.0)
				if d.length() <= 1.0 and d.length() > 0.55:
					key.set_pixel(x, y, pair[1])
		for x in range(16, 38):
			key.set_pixel(x, 11, pair[1])
			key.set_pixel(x, 12, Color(pair[1].r * 0.6, pair[1].g * 0.6, pair[1].b * 0.6))
		for y in range(12, 19):
			key.set_pixel(31, y, pair[1])
			key.set_pixel(36, y, pair[1])
		key.save_png(ProjectSettings.globalize_path(ICONS_DIR + pair[0] + ".png"))
	# 鱼
	var fish := Image.create(40, 20, false, Image.FORMAT_RGBA8)
	for y in 20:
		for x in 40:
			var d := Vector2(x - 17.0, y - 9.5) / Vector2(13.0, 6.0)
			if d.length() <= 1.0:
				fish.set_pixel(x, y, Color(0.55, 0.62, 0.72))
			elif x >= 30 and x <= 38 and absf(y - 9.5) < (x - 29.0) * 1.1:
				fish.set_pixel(x, y, Color(0.42, 0.5, 0.6))
	fish.set_pixel(10, 8, c_dark)
	fish.save_png(ProjectSettings.globalize_path(ICONS_DIR + "fish.png"))
	# 虾：粉红弯钩 + 尾扇
	var shrimp := Image.create(36, 24, false, Image.FORMAT_RGBA8)
	for t in 60:
		var ang := -0.5 + t / 60.0 * 2.6
		var cx := 18.0 + cos(ang) * 10.0
		var cy := 13.0 + sin(ang) * 7.0
		for k in 5:
			var px := int(cx + cos(ang + 1.57) * (k - 2.0))
			var py := int(cy + sin(ang + 1.57) * (k - 2.0))
			if px >= 0 and px < 36 and py >= 0 and py < 24:
				shrimp.set_pixel(px, py, Color(0.95, 0.55, 0.45))
	for dy in 5:
		for dx in 3:
			shrimp.set_pixel(27 + dx, 4 + dy + dx, Color(0.9, 0.42, 0.35))
	shrimp.save_png(ProjectSettings.globalize_path(ICONS_DIR + "shrimp.png"))
	# 饭团：白三角 + 海苔带
	var oni := Image.create(32, 28, false, Image.FORMAT_RGBA8)
	for y in 28:
		for x in 32:
			var p := Vector2(x - 15.5, y - 13.0)
			if p.y > -2.0 and absf(p.x) < (p.y + 3.0) * 1.35 and absf(p.x) < 14.0 and p.y < 13.0:
				oni.set_pixel(x, y, c_white)
			if p.y >= 8.0 and p.y <= 16.0 and absf(p.x) < (p.y - 6.0) * 1.3:
				oni.set_pixel(x, y, Color(0.2, 0.35, 0.22))
	oni.save_png(ProjectSettings.globalize_path(ICONS_DIR + "onigiri.png"))
	# 寿司：白饭底 + 橙 salmon + 海苔带
	var susi := Image.create(36, 24, false, Image.FORMAT_RGBA8)
	for y in range(12, 24):
		for x in range(3, 33):
			var d := Vector2(x - 17.5, y - 17.5) / Vector2(14.5, 6.0)
			if d.length() <= 1.0:
				susi.set_pixel(x, y, c_white)
	for y in range(5, 13):
		for x in range(4, 32):
			var d := Vector2(x - 17.5, y - 8.5) / Vector2(13.5, 4.0)
			if d.length() <= 1.0:
				susi.set_pixel(x, y, Color(0.95, 0.48, 0.25))
	for y in range(4, 22):
		susi.set_pixel(16, y, Color(0.2, 0.35, 0.22))
		susi.set_pixel(17, y, Color(0.2, 0.35, 0.22))
	susi.save_png(ProjectSettings.globalize_path(ICONS_DIR + "sushi.png"))
	# 播放三角（ResumeBtn）
	var play := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for x in 24:
		var h := 4 + x
		for y in range(16 - h, 16 + h):
			if y >= 0 and y < 32:
				play.set_pixel(x + 4, y, Color(0.45, 0.8, 0.4) if x < 20 else Color(0.35, 0.68, 0.32))
	play.save_png(ProjectSettings.globalize_path(ICONS_DIR + "play.png"))
	# 头像框（对话立绘框）：深底 + 双线金边
	var frame := Image.create(96, 96, false, Image.FORMAT_RGBA8)
	for y in 96:
		for x in 96:
			var edge := minf(minf(float(x), 95.0 - x), minf(float(y), 95.0 - y))
			if edge < 2.0 or (edge >= 5.0 and edge < 7.0):
				frame.set_pixel(x, y, c_gold)
			elif edge >= 7.0:
				frame.set_pixel(x, y, Color(0.12, 0.13, 0.18, 0.92))
	frame.save_png(ProjectSettings.globalize_path(ICONS_DIR + "icon_frame.png"))
	# 怪物头顶条框（monster_bar）：TS 色板合成 64×12 木框暗槽——
	# SmallBar_Base 320×64 直缩到 64 宽会糊成线，按目标尺寸逐像素画保脆；
	# 消费方 scripts/monsters/monster_hp_bar.gd 按原生 64×12 绘制
	var mbar := Image.create(64, 12, false, Image.FORMAT_RGBA8)
	var mb_wood := Color(0.46, 0.41, 0.36)
	var mb_wood_dark := Color(0.3, 0.26, 0.22)
	var mb_slot := Color(0.13, 0.1, 0.08, 0.85)
	for y in 12:
		for x in 64:
			if x < 3 or x > 60 or y == 0 or y == 11:
				mbar.set_pixel(x, y, mb_wood)
			elif y == 1 or y == 10:
				mbar.set_pixel(x, y, mb_wood_dark)
			else:
				mbar.set_pixel(x, y, mb_slot)
	mbar.save_png(ProjectSettings.globalize_path(ICONS_DIR + "monster_bar.png"))
	# 室内口袋三件（TS 无室内件，木色合成）：地板/深墙/床
	var floor_img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var plank := int(y / 8.0)
			var off := (plank % 2) * 16
			var grain := (x + off) % 32 < 1 or (x + off) % 7 == 3
			floor_img.set_pixel(x, y, Color(0.62, 0.44, 0.27) if not grain else Color(0.55, 0.38, 0.22))
			if y % 8 == 0:
				floor_img.set_pixel(x, y, Color(0.42, 0.28, 0.16))
	floor_img.save_png(ProjectSettings.globalize_path(OUT + "interior_floor.png"))
	var wall := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var brick_y := int(y / 8.0)
			var off := (brick_y % 2) * 16
			var mortar := y % 8 == 0 or (x + off) % 16 == 0
			wall.set_pixel(x, y, Color(0.3, 0.26, 0.32) if not mortar else Color(0.2, 0.17, 0.22))
	wall.save_png(ProjectSettings.globalize_path(OUT + "interior_wall.png"))
	var bed := Image.create(40, 28, false, Image.FORMAT_RGBA8)
	for y in 28:
		for x in 40:
			var frame_edge := x < 4 or x > 35 or y < 3 or y > 24
			if frame_edge:
				bed.set_pixel(x, y, c_wood)
			elif y < 6:
				bed.set_pixel(x, y, Color(0.9, 0.88, 0.82))  # 枕
			else:
				bed.set_pixel(x, y, Color(0.82, 0.3, 0.28))  # 红毯
	bed.save_png(ProjectSettings.globalize_path(OUT + "bed.png"))


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
