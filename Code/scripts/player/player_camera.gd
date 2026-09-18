## 玩家相机：平滑跟随 + 震屏 + 像素对齐。
## 不用引擎 position_smoothing：平滑后的视图中心是引擎内部状态，往 offset
## 上做的亚像素校准会被平滑器吞掉（实证：残差不收敛、校准量单向漂移）。
## 改为脚本侧平滑 + 取整——跟随点按指数插值逼近玩家后，把相机中心吸附到
## 1/zoom 网格，渲染时世界纹素稳定落在整数屏幕像素上，Nearest 采样不随
## 镜头移动逐帧闪抖（"像素缩放抖动"）。视口半幅非整数（expand 拉伸的设备
## 分辨率）同样成立——对齐目标是画布变换 origin 取整，不是相机坐标取整。
## 震屏叠加在 offset 上（对齐之外的瞬时随机抖动，强度指数衰减）。
extends Camera2D

## 与原 position_smoothing_speed 同值，接管后手感不漂移
const SMOOTH_SPEED := 6.0
const SHAKE_DECAY := 9.0

var _strength := 0.0
## 平滑跟随点（世界坐标）；INF = 首帧待初始化（直接对齐玩家，不从原点飘来）
var _follow := Vector2.INF


func _ready() -> void:
	# 跟随平滑由本脚本接管（见类注），关掉引擎侧平滑避免双重低通
	position_smoothing_enabled = false
	EventBus.camera_shake_requested.connect(
		func(strength: float) -> void:
			if bool(GameState.settings.get("screen_shake", true)):
				_strength = maxf(_strength, strength)
	)


## 传送后吸附（美术 v5 借鉴③：进屋/出屋瞬移）——跟随点直接对齐玩家，
## 避免 50 万 px 级跨距被平滑器拉成长镜头
func snap_to_player() -> void:
	var player := get_parent() as Node2D
	if player != null:
		_follow = player.global_position


func _process(delta: float) -> void:
	var player := get_parent() as Node2D
	if player == null:
		return
	if _follow == Vector2.INF:
		_follow = player.global_position
	_follow = _follow.lerp(player.global_position, 1.0 - exp(-SMOOTH_SPEED * delta))
	# 像素对齐：origin = 视口半幅 - center×zoom 需为整数屏幕像素，
	# 反解满足条件的 center（等价于把相机吸附到 1/zoom 网格）
	var vp_size := get_viewport().get_visible_rect().size
	var desired_origin := vp_size * 0.5 - _follow * zoom
	global_position = (vp_size * 0.5 - desired_origin.round()) / zoom
	if _strength > 0.0:
		offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _strength
		_strength = maxf(0.0, _strength - SHAKE_DECAY * _strength * delta - 2.0 * delta)
		if _strength <= 0.0:
			offset = Vector2.ZERO
	else:
		offset = Vector2.ZERO
