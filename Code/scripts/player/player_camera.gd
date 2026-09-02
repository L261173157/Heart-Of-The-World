## 玩家相机：跟随（场景配置）+ 震屏（订阅 EventBus.camera_shake_requested）。
## 用 offset 抖动而非 position，避免与 position_smoothing 打架；强度指数衰减。
extends Camera2D

const SHAKE_DECAY := 9.0

var _strength := 0.0


func _ready() -> void:
	EventBus.camera_shake_requested.connect(
		func(strength: float) -> void:
			if bool(GameState.settings.get("screen_shake", true)):
				_strength = maxf(_strength, strength)
	)


func _process(delta: float) -> void:
	if _strength <= 0.0:
		offset = Vector2.ZERO
		return
	offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _strength
	_strength = maxf(0.0, _strength - SHAKE_DECAY * _strength * delta - 2.0 * delta)
	if _strength <= 0.0:
		offset = Vector2.ZERO
