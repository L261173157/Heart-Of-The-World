## 地表纹理离线生成工具（无头运行：godot --headless --path Code -s tools/generate_terrain.gd）。
## 生成 6 张 1100×700 群系地表 PNG 到 assets/terrain/：
##   大尺度 fbm 明暗分区（解决"均质噪点墙"）+ 有机色斑 + 地形专属细节
##   （草簇/落叶/碎石/雪堆/水洼高光/岩层条/熔岩裂纹 ridged 噪声窄带）+ 边缘渐暗。
## 全部确定性随机（固定 seed），重跑结果一致。
extends SceneTree

const W := 1100
const H := 700
const OUT_DIR := "res://assets/terrain/"

## 每地形：base/dark/light 三档底色 + accent 强调色
const BIOMES := {
	"west": {
		"names": ["region_west.png"], "seedv": 11,
		"base": Color("#6b7d45"), "dark": Color("#55663a"), "light": Color("#82935a"),
		"accent": Color("#8a7351"), "cracks": false,
	},
	"center": {
		"names": ["region_center.png"], "seedv": 22,
		"base": Color("#4a6641"), "dark": Color("#3a5233"), "light": Color("#5c7a4f"),
		"accent": Color("#96813f"), "cracks": false,
	},
	"snow": {
		"names": ["region_snow.png"], "seedv": 33,
		"base": Color("#c3ccd9"), "dark": Color("#a8b3c4"), "light": Color("#e6ecf3"),
		"accent": Color("#9a8f7a"), "cracks": true,
		"crack_color": Color("#dfe9f2"),
	},
	"swamp": {
		"names": ["region_swamp.png"], "seedv": 44,
		"base": Color("#4f5a44"), "dark": Color("#3d4636"), "light": Color("#626e52"),
		"accent": Color("#5d7a80"), "cracks": false,
	},
	"east": {
		"names": ["region_east.png"], "seedv": 55,
		"base": Color("#7a705f"), "dark": Color("#635a4c"), "light": Color("#8f8471"),
		"accent": Color("#a09482"), "cracks": false,
	},
	"lava": {
		"names": ["region_lava.png"], "seedv": 66,
		"base": Color("#453b3a"), "dark": Color("#362e2d"), "light": Color("#544a49"),
		"accent": Color("#e0722a"), "cracks": true,
		"crack_color": Color("#f08a35"),
	},
}

const EDGE := 44.0


func _init() -> void:
	for key: String in BIOMES:
		var cfg: Dictionary = BIOMES[key]
		var img := _generate(cfg)
		var path: String = OUT_DIR + cfg["names"][0]
		var err := img.save_png(path)
		print("生成 %s（%dx%d）%s" % [path, W, H, "OK" if err == OK else "失败:%d" % err])
	quit(0)


## 整数坐标散列 → [0,1)
func _hash2(x: int, y: int, s: int) -> float:
	var h: int = x * 374761393 + y * 668265263 + s * 2246822519
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0x7FFFFFFF) / 2147483647.0


## value noise（双线性插值 + smoothstep）
func _vnoise(x: float, y: float, s: int) -> float:
	var xi := floori(x)
	var yi := floori(y)
	var xf := x - float(xi)
	var yf := y - float(yi)
	var u := xf * xf * (3.0 - 2.0 * xf)
	var v := yf * yf * (3.0 - 2.0 * yf)
	var a := _hash2(xi, yi, s)
	var b := _hash2(xi + 1, yi, s)
	var c := _hash2(xi, yi + 1, s)
	var d := _hash2(xi + 1, yi + 1, s)
	return a * (1.0 - u) * (1.0 - v) + b * u * (1.0 - v) + c * (1.0 - u) * v + d * u * v


## 分形叠加噪声（octaves 层，频率倍增振幅减半）
func _fbm(x: float, y: float, s: int, octaves: int) -> float:
	var sum := 0.0
	var amp := 0.5
	var freq := 1.0
	var norm := 0.0
	for i in octaves:
		sum += amp * _vnoise(x * freq, y * freq, s + i * 101)
		norm += amp
		amp *= 0.5
		freq *= 2.0
	return sum / norm


func _generate(cfg: Dictionary) -> Image:
	var seedv: int = cfg["seedv"]
	var base: Color = cfg["base"]
	var dark: Color = cfg["dark"]
	var light: Color = cfg["light"]
	var accent: Color = cfg["accent"]
	var img := Image.create(W, H, false, Image.FORMAT_RGB8)
	for y in H:
		for x in W:
			# 大尺度明暗分区（低频 fbm 决定 base↔light↔dark 走向；窄 smoothstep 拉强对比）
			var macro := _fbm(float(x) / 130.0, float(y) / 130.0, seedv, 3)
			var col := base.lerp(light, smoothstep(0.50, 0.68, macro))
			col = col.lerp(dark, smoothstep(0.48, 0.30, macro))
			# 中尺度有机色斑（斑块集团，非均匀噪点）
			var patch := _fbm(float(x) / 34.0, float(y) / 34.0, seedv + 7, 3)
			if patch > 0.62:
				col = col.lerp(accent, (patch - 0.62) * 1.6)
			elif patch < 0.34:
				col = col.lerp(dark, (0.34 - patch) * 1.2)
			# 细节颗粒
			var grain := _vnoise(float(x) / 3.0, float(y) / 3.0, seedv + 13)
			col = col.darkened(0.05 * (0.5 - grain))
			# 裂纹（ridged 噪声窄带：熔岩脉络 / 冰面裂纹），宽晕带让热色/冰色沿裂缝聚集
			if cfg["cracks"]:
				var ridge: float = absf(2.0 * _fbm(float(x) / 60.0, float(y) / 60.0, seedv + 29, 3) - 1.0)
				if ridge < 0.12:
					col = col.lerp(cfg["crack_color"], 0.25 * (1.0 - ridge / 0.12))
				if ridge < 0.045:
					col = col.lerp(cfg["crack_color"], 1.0 - ridge / 0.045)
			# 边缘渐暗收口（宽过渡带：区域之间形成"沟壑"式的自然分隔）
			var d := minf(minf(float(x), float(W - 1 - x)), minf(float(y), float(H - 1 - y)))
			if d < EDGE:
				col = col.darkened(0.35 * (1.0 - d / EDGE))
			img.set_pixel(x, y, col)
	# 簇状散点装饰：80 个簇心 × 高斯散布小点（草簇/碎石/雪斑成团，留白与密集对比）
	var rng := RandomNumberGenerator.new()
	rng.seed = seedv * 7919
	for cluster in 80:
		var cx := rng.randi_range(10, W - 11)
		var cy := rng.randi_range(10, H - 11)
		var c := light if rng.randf() < 0.6 else accent
		var cluster_size := rng.randi_range(18, 46)
		for i in cluster_size:
			var sx := clampi(cx + rng.randi_range(-7, 7), 4, W - 5)
			var sy := clampi(cy + rng.randi_range(-5, 5), 4, H - 5)
			if rng.randf() < 0.55:
				img.set_pixel(sx, sy, c.darkened(rng.randf_range(0.0, 0.12)))
	return img
