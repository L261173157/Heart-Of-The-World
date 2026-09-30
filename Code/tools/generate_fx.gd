## TS 风格特效合成器（美术 v6 P2）：Tiny Swords 包无挥砍/闪光/光柱类特效，
## 以 TS 色板（白核+彩色边+硬边量阶）程序化合成，产出到 assets/ts/fx_generated/
## 单行条带 PNG（×2 预放大保持块感），由 slice_spritesheets.gd 的 TS 表切帧消费。
## 用法：godot --headless --path Code -s tools/generate_fx.gd（重跑幂等覆盖）
extends SceneTree

const OUT_DIR := "res://assets/ts/fx_generated/"
## 逻辑画布 48×48 → ×2 输出 96×96 帧（与 TS 素材同款块感）
const LOGIC := 48
const UP := 2

const CORE := Color(1.0, 1.0, 1.0, 1.0)


func _c(r: int, g: int, b: int) -> Color:
	return Color(r / 255.0, g / 255.0, b / 255.0, 1.0)


## alpha 三级量阶（像素艺术硬边感）
func _quant(a: float) -> float:
	if a > 0.85:
		return 1.0
	if a > 0.45:
		return 0.66
	if a > 0.15:
		return 0.33
	return 0.0


func _mix(core: Color, edge: Color, k: float) -> Color:
	var c := core.lerp(edge, clampf(k, 0.0, 1.0))
	c.a = _quant(c.a)
	return c


func _new_frame() -> Image:
	return Image.create(LOGIC, LOGIC, false, Image.FORMAT_RGBA8)


func _save_strip(name: String, frames: Array) -> void:
	var fw: int = frames[0].get_width()
	var fh: int = frames[0].get_height()
	var strip := Image.create(fw * UP * frames.size(), fh * UP, false, Image.FORMAT_RGBA8)
	for k: int in frames.size():
		var im: Image = frames[k]
		im.resize(fw * UP, fh * UP, Image.INTERPOLATE_NEAREST)
		strip.blit_rect(im, Rect2i(Vector2i.ZERO, im.get_size()), Vector2i(k * fw * UP, 0))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	strip.save_png(ProjectSettings.globalize_path(OUT_DIR + name + ".png"))
	print("%-12s -> %s%s.png (%d 帧)" % [name, OUT_DIR, name, frames.size()])


func _init() -> void:
	# --- 挥砍弧光（白刃/金刃各 4 帧：扫掠+收势） ---
	_save_strip("slash", _sweep_frames(_c(170, 205, 255)))
	_save_strip("slash_gold", _sweep_frames(_c(255, 196, 60)))
	# --- 闪光（白/金/蓝/黄 各 3 帧：涨-满-收） ---
	_save_strip("flash", _flash_frames(_c(208, 208, 220)))
	_save_strip("flash_gold", _flash_frames(_c(255, 190, 40)))
	_save_strip("flash_blue", _flash_frames(_c(92, 140, 255)))
	_save_strip("flash_yellow", _flash_frames(_c(255, 230, 80)))
	# --- 细光束（命中贯穿，3 帧） ---
	_save_strip("beam", _beam_frames(_c(255, 220, 120)))
	# --- 光柱（开箱/升级，4 帧竖条） ---
	_save_strip("pillar", _pillar_frames(_c(255, 200, 80)))
	# --- 多重光束（Boss 重生，3 帧散射） ---
	_save_strip("beams", _beams_frames(_c(255, 240, 160)))
	# --- 法弹核心（player_bolt 紫球，单帧 24×24 逻辑） ---
	var orb := Image.create(24, 24, false, Image.FORMAT_RGBA8)
	for y in 24:
		for x in 24:
			var d := Vector2(x - 11.5, y - 11.5).length() / 9.5
			if d < 1.0:
				var col := _mix(CORE, _c(150, 70, 220), d)
				col.a = _quant((1.0 - d) * 1.2)
				orb.set_pixel(x, y, col)
	orb.resize(24 * UP, 24 * UP, Image.INTERPOLATE_NEAREST)
	orb.save_png(ProjectSettings.globalize_path(OUT_DIR + "orb_core.png"))
	print("%-12s -> %sorb_core.png" % ["orb_core", OUT_DIR])
	quit(0)


## 挥砍：θ 从 -75° 扫到 +75°（朝 +x 弧面），半径 17、亮核 2.5px + 外晕 5px
const SWEEP := 56  # 弧光画布（比通用 48 大：半径 22 需要余地）

func _sweep_frames(edge: Color) -> Array:
	var frames: Array = []
	var thetas := [-42.0, 0.0, 42.0, 8.0]
	var wins := [52.0, 74.0, 52.0, 30.0]
	for k in 4:
		var img := Image.create(SWEEP, SWEEP, false, Image.FORMAT_RGBA8)
		var tc := deg_to_rad(thetas[k])
		var hw := deg_to_rad(wins[k] * 0.5)
		var fade := 1.0 - 0.18 * k
		for y in SWEEP:
			for x in SWEEP:
				var v := Vector2(x - 28.0, y - 28.0)
				var r := v.length()
				if r > 26.0:
					continue
				var th := atan2(v.y, v.x)
				var dth := absf(fposmod(th - tc + PI, TAU) - PI)
				if dth > hw:
					continue
				var along := 1.0 - pow(dth / hw, 1.6)  # 弧向端点更利落的渐隐
				var dr := absf(r - 22.0)
				if dr <= 3.0:
					var col := _mix(CORE, edge, 0.3 * dr)
					col.a = _quant(along * fade)
					img.set_pixel(x, y, col)
				elif dr <= 6.5:
					var col := edge
					col.a = _quant(along * (1.0 - (dr - 3.0) / 3.5) * 0.55 * fade)
					img.set_pixel(x, y, col)
		frames.append(img)
	return frames


## 闪光：径向圆盘 涨-满-收（r: 9/15/19，透明度 0.8/1.0/0.5）
func _flash_frames(edge: Color) -> Array:
	var frames: Array = []
	var radii := [9.0, 15.0, 19.0]
	var peak := [0.85, 1.2, 0.55]
	for k in 3:
		var img := _new_frame()
		for y in LOGIC:
			for x in LOGIC:
				var d: float = Vector2(x - 23.5, y - 23.5).length() / radii[k]
				if d < 1.0:
					var col := _mix(CORE, edge, d)
					col.a = _quant((1.0 - d) * peak[k])
					img.set_pixel(x, y, col)
		frames.append(img)
	return frames


## 细光束：水平纺锤（长涨后淡出）
func _beam_frames(edge: Color) -> Array:
	var frames: Array = []
	var lens := [15.0, 23.0, 20.0]
	var hmax := [4.0, 6.5, 8.0]
	var peak := [0.9, 1.2, 0.5]
	for k in 3:
		var img := _new_frame()
		for y in LOGIC:
			for x in LOGIC:
				var hx: float = absf(x - 23.5) / lens[k]
				if hx >= 1.0:
					continue
				var hh: float = hmax[k] * (1.0 - hx * hx)
				var dy := absf(y - 23.5)
				if dy <= hh:
					var col := _mix(CORE, edge, dy / maxf(hh, 0.001))
					col.a = _quant((1.0 - hx) * peak[k])
					img.set_pixel(x, y, col)
		frames.append(img)
	return frames


## 光柱：竖条底宽顶收 + 中心亮线（涨-满-闪-收）
func _pillar_frames(edge: Color) -> Array:
	var frames: Array = []
	var widths := [5.0, 8.0, 11.0, 6.0]
	var peak := [0.8, 1.2, 1.0, 0.45]
	for k in 4:
		var img := _new_frame()
		for y in LOGIC:
			# 顶部 30% 收窄成尖
			var taper := 1.0
			if y < 14.0:
				taper = 0.25 + 0.75 * (y / 14.0)
			var w: float = widths[k] * taper
			for x in LOGIC:
				var dx := absf(x - 23.5)
				if dx <= w:
					var core_line := 1.0 if dx <= 1.0 else 0.0
					var col := _mix(CORE, edge, 0.3 + 0.7 * (dx / maxf(w, 0.001)))
					if core_line > 0.0:
						col = CORE
					col.a = _quant(peak[k] * (0.55 + 0.45 * (1.0 - y / 48.0)))
					img.set_pixel(x, y, col)
		frames.append(img)
	return frames


## 多重光束：自底心的三束扇形散射
func _beams_frames(edge: Color) -> Array:
	var frames: Array = []
	var lens := [16.0, 30.0, 22.0]
	var peak := [0.8, 1.2, 0.5]
	var angles := [deg_to_rad(-28.0), 0.0, deg_to_rad(28.0)]  # 相对竖直向上
	for k in 3:
		var img := _new_frame()
		for a: float in angles:
			var dir := Vector2(sin(a), -cos(a))
			for step in int(lens[k]):
				var c := Vector2(23.5, 44.0) + dir * (step + 2.0)
				for oy in [-1, 0, 1]:
					for ox in [-1, 0, 1]:
						var p := c + Vector2(ox, oy)
						if p.x < 0 or p.y < 0 or p.x >= LOGIC or p.y >= LOGIC:
							continue
						var dist := Vector2(ox, oy).length()
						var col := _mix(CORE, edge, 0.4)
						col.a = _quant(peak[k] * (1.0 - step / lens[k]) * (1.0 - 0.18 * dist))
						img.set_pixel(int(p.x), int(p.y), col)
		frames.append(img)
	return frames
