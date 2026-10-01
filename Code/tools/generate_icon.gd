## App 图标生成（确定性，无外部依赖）——v6.2 起主角入镜
## 主体 = ts 素材「蓝骑士」（Tiny Swords Warrior，游戏默认皮肤 hero_skin=blue）
## Attack1 第 2 帧（剑完全展开的动态剪影，ACT 品类经典图标构图），
## 背景 = 沿用 v6.1 的夜空渐变 + 星点 + 四角暗角，与游戏昼夜/提灯氛围同源。
## 1024×1024、无透明通道（App Store 营销图强制不透明）。
## 尺寸派生：Godot 4.7 iOS 导出走单一图标模式（export_presets 的 icons/icon_1024x1024），
## 各档位（40/58/…/180/1024 及 iOS18 dark/tinted）自动缩放，无需逐个配图。
## 用法：godot --headless --path Code -s tools/generate_icon.gd
## 改完参数重跑本文件即可，输出覆盖 assets/icon/appicon_1024.png（随仓库提交）。
## 性能：渐变走 fill_rect、英雄走引擎级 blend_rect（C++），GDScript 逐像素仅限
## 星点/落影/暗角环带。注意：-s 脚本断言失败/报错不会自动退出进程，会挂起——
## 排查时别只看"跑不完"，先看有没有 SCRIPT ERROR。
## 历史：v6.1 及之前为程序化六群系像素心（git 历史可回溯）。
extends SceneTree

const OUT := "res://assets/icon/appicon_1024.png"
const OUT_SIZE := 1024

# ---- 主体素材（真源 = assets/ts/Units/Blue Units/Warrior/Warrior_Attack1.png）----
const HERO_SHEET := "res://assets/ts/Units/Blue Units/Warrior/Warrior_Attack1.png"
const HERO_FRAME := 2          # 四帧中剑完全展开的一帧（内容 bbox 实测最宽 120px）
const HERO_CELL := 192         # TS 条带单帧画布
const HERO_SCALE := 6          # 整数倍最近邻，保持像素画颗粒感；内容 120×104 → 720×624

# ---- 背景色板（沿用六群系心图标的夜空系）----
const BG_TOP := Color8(26, 26, 51)       # 夜空顶
const BG_BOTTOM := Color8(16, 14, 28)    # 夜空底
const STAR_DIM := Color8(143, 143, 208)
const STAR_BRIGHT := Color8(197, 197, 239)
const STAR_LATTICE := 16                # 星点抽样格距（1024/16=64×64 格）
const STAR_DENS := 0.045                # 格子命中概率 → 约 180 颗
const SHADOW := Color8(10, 8, 20)        # 脚下落影
const VIGNETTE := 0.16                   # 四角最大压暗量


func _init() -> void:
	var hero := _load_hero_content()
	var hw := hero.get_width()   # _load_hero_content 已按 HERO_SCALE 放大，勿再乘
	var hh := hero.get_height()
	assert(hw <= OUT_SIZE - 128 and hh <= OUT_SIZE - 128, "主体缩放后超出安全边距")

	# 全程 RGBA8 合成，底色不透明；出口 convert RGB8 去通道
	var img := Image.create_empty(OUT_SIZE, OUT_SIZE, false, Image.FORMAT_RGBA8)
	_draw_background(img)
	var pos := Vector2i((OUT_SIZE - hw) / 2, (OUT_SIZE - hh) / 2)
	_draw_shadow(img, pos, hw, hh)
	img.blend_rect(hero, Rect2i(Vector2i.ZERO, Vector2i(hw, hh)), pos)
	_draw_vignette(img)
	img.convert(Image.FORMAT_RGB8)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/icon"))
	var path := ProjectSettings.globalize_path(OUT)
	var err := img.save_png(path)
	print("生成 %s（%dx%d，主体内容 %dx%d 落位 %s）%s" % [path, OUT_SIZE, OUT_SIZE,
		hw, hh, pos, "OK" if err == OK else "失败:%d" % err])
	quit(0 if err == OK else 1)


## 载入条带帧并裁到内容紧致框、整数倍放大（去透明边，令构图居中的是角色本身而非画布）
func _load_hero_content() -> Image:
	var sheet := Image.load_from_file(ProjectSettings.globalize_path(HERO_SHEET))
	assert(sheet != null, "读不到素材：" + HERO_SHEET)
	sheet.convert(Image.FORMAT_RGBA8)
	var frame := sheet.get_region(Rect2i(HERO_FRAME * HERO_CELL, 0, HERO_CELL, HERO_CELL))
	var bb := _alpha_bbox(frame)
	frame = frame.get_region(Rect2i(bb.position, bb.size))
	frame.resize(bb.size.x * HERO_SCALE, bb.size.y * HERO_SCALE, Image.INTERPOLATE_NEAREST)
	return frame


func _alpha_bbox(img: Image) -> Rect2i:
	var x0 := img.get_width()
	var y0 := img.get_height()
	var x1 := -1
	var y1 := -1
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.0:
				x0 = mini(x0, x)
				y0 = mini(y0, y)
				x1 = maxi(x1, x)
				y1 = maxi(y1, y)
	assert(x1 >= x0, "素材帧无可见内容")
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)


func _draw_background(img: Image) -> void:
	# 垂直渐变：按行 fill_rect（引擎批量路径）
	for y in OUT_SIZE:
		var row := BG_TOP.lerp(BG_BOTTOM, float(y) / float(OUT_SIZE - 1))
		row.a = 1.0
		img.fill_rect(Rect2i(0, y, OUT_SIZE, 1), row)
	# 星点：格心命中（确定性散列），亮星 4×4 / 暗星 3×3
	for cy in OUT_SIZE / STAR_LATTICE:
		for cx in OUT_SIZE / STAR_LATTICE:
			if _hash2(cx, cy, 777) >= STAR_DENS:
				continue
			var bright := _hash2(cx, cy, 779) < 0.35
			var col := STAR_BRIGHT if bright else STAR_DIM
			var sz := 4 if bright else 3
			var ox := cx * STAR_LATTICE + int(float(STAR_LATTICE - sz) * _hash2(cx, cy, 781))
			var oy := cy * STAR_LATTICE + int(float(STAR_LATTICE - sz) * _hash2(cx, cy, 783))
			for sy in sz:
				for sx in sz:
					img.set_pixel(ox + sx, oy + sy, col)


## 脚下椭圆落影（游戏内 ShadowBlob 的图标化）：小区域逐像素半透明合成
func _draw_shadow(img: Image, pos: Vector2i, w: int, h: int) -> void:
	var c := Vector2(float(pos.x + w / 2.0), float(pos.y + h) + 18.0)
	var rx := float(w) * 0.42
	var ry := 26.0
	for y in range(int(c.y - ry) - 1, int(c.y + ry) + 3):
		if y < 0 or y >= OUT_SIZE:
			continue
		for x in range(int(c.x - rx) - 1, int(c.x + rx) + 3):
			if x < 0 or x >= OUT_SIZE:
				continue
			var e := sqrt(pow(absf(float(x) - c.x) / rx, 2.0) + pow(absf(float(y) - c.y) / ry, 2.0))
			if e < 1.0:
				var a := 0.45 * (1.0 - e) * (1.0 - e)
				var p := img.get_pixel(x, y)
				p = p.lerp(Color(SHADOW.r, SHADOW.g, SHADOW.b), a)
				img.set_pixel(x, y, p)


## 四角径向压暗：只遍历 dist > 0.9R 的角落环带（约 4 万像素），跳过中央大面积
func _draw_vignette(img: Image) -> void:
	var c := float(OUT_SIZE) * 0.5
	var inner := c * 0.9
	var dy := 0.0
	var dx := 0.0
	var d := 0.0
	var k := 0.0
	for y in OUT_SIZE:
		dy = absf(float(y) - c)
		for x in OUT_SIZE:
			dx = absf(float(x) - c)
			d = sqrt(dx * dx + dy * dy)
			if d <= inner:
				continue
			k = clampf((d - inner) / (c * 0.55), 0.0, 1.0) * VIGNETTE
			if k > 0.0:
				var p := img.get_pixel(x, y)
				p = p.darkened(k)
				img.set_pixel(x, y, p)


## 整数坐标散列 → [0,1)，与 generate_terrain.gd 同款（确定性，换机重跑结果一致）
func _hash2(x: int, y: int, s: int) -> float:
	var h: int = x * 374761393 + y * 668265263 + s * 2246822519
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0x7FFFFFFF) / 2147483647.0
