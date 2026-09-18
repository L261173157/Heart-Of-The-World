## 视野光影（世界 v5）：昼夜 CanvasModulate 压暗 + 玩家提灯 PointLight2D
## 阴影投射——夜里树影岩影真实投影，被障碍挡住的地方真的看不见（障碍瓦片
## 自带遮挡多边形，零额外节点）。取代旧的 HUD 全屏 NightRect 压暗（压暗改在
## 世界画布内做，提灯才能在黑暗里"挖出"光池）。
## 曲线与既有昼夜语义联动：WorldSim.night_intensity() 入夜前 20% 天渐入、
## 0.75~0.95 渐出（怪物侦测增益同区间收回——视觉与规则同一口径）。
## 性能：白天提灯 energy=0 且 disabled（阴影栅格化零成本）；群系底色调制
## 每 0.5s 轮询一次地形，插值过渡不跳变。挂载于 game_world。
class_name VisionLighting
extends Node2D

## 夜色（乘性偏蓝）：月光蓝基调。旧值 (0.44,0.48,0.66) 按"≈0.45 黑"标定，
## 但那是全屏均匀压暗的口径——提灯收到视口内后，夜色主要由光池外的屏幕
## 边缘承担，需要更深才读得出"夜"（2026-09-13 调参实证）
const NIGHT_TINT := Color(0.33, 0.37, 0.56)
## 群系环境底色（乘性微调；平原/丘陵中性不调）
const BIOME_TINT := {
	"lava": Color(1.06, 0.9, 0.82),
	"snow": Color(0.9, 0.95, 1.05),
	"swamp": Color(0.93, 1.0, 0.9),
	"forest": Color(0.95, 1.02, 0.95),
}
const TERRAIN_POLL := 0.5
## 提灯尺度：256px 渐变纹理 × 3.6 = 直径 921px 光池。曾经 ×5 盖满整个 zoom6
## 视口——加法光把夜色压暗完全抵消，夜里亮如白天（2026-09-13 体检实证）；
## 按「光池半径 = 可见对角半径的 ~54%」等比迁移（zoom1 对角 860×0.54≈461）：
## 中心暖亮，屏幕角落可见夜色与障碍树影。zoom 调整时按此比例换算
const LANTERN_SCALE := 3.6

var _modulate := CanvasModulate.new()
var _light: PointLight2D
var _terrain := ""
var _terrain_accum := 0.0
var _tint_current := Color.WHITE


func _ready() -> void:
	_light = PointLight2D.new()
	_light.texture = _make_lantern_texture()
	_light.texture_scale = LANTERN_SCALE
	_light.blend_mode = Light2D.BLEND_MODE_ADD
	_light.color = Color(1.0, 0.9, 0.72)  # 暖光（Light2D 的颜色属性是 color，light_color 是 3D 灯的）
	_light.shadow_enabled = true  # 障碍瓦片遮挡层投射树影/岩影（性能闸不过则降级）
	_light.shadow_filter = Light2D.SHADOW_FILTER_NONE  # 像素风硬边影最便宜
	_light.energy = 0.0
	_light.enabled = false
	add_child(_light)
	add_child(_modulate)


func _process(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null or not player.visible:
		return
	_light.global_position = player.global_position
	_terrain_accum += delta
	if _terrain_accum >= TERRAIN_POLL:
		_terrain_accum = 0.0
		_terrain = BiomeMap.terrain_at(player.global_position)
	# 夜色（连续曲线，逐帧驱动免信号时序问题）+ 群系底色插值
	var target: Color = BIOME_TINT.get(_terrain, Color.WHITE)
	_tint_current = _tint_current.lerp(target, minf(delta * 2.0, 1.0))
	var night := WorldSim.night_intensity()
	_modulate.color = Color.WHITE.lerp(NIGHT_TINT, night) * _tint_current
	# 提灯只属于黑夜；白天彻底关闭（阴影栅格化零成本）。
	# 能量 1.35：夜色加深后中心仍暖亮可读，边缘留给夜色
	_light.energy = night * 1.35
	_light.enabled = night > 0.02


## 提灯纹理：256×256 径向渐变（alpha 中心 1 → 边缘 0，幂次收边）
func _make_lantern_texture() -> ImageTexture:
	var size := 256
	var half := 128.0
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var d := Vector2(float(x) - half + 0.5, float(y) - half + 0.5).length() / half
			var a := pow(clampf(1.0 - d, 0.0, 1.0), 1.6)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	return ImageTexture.create_from_image(img)
