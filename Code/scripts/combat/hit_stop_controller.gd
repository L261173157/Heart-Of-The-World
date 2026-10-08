## 世界级短顿帧：使用真实时钟，重叠命中不延长；只恢复自己取得的时间尺度。
## 暂停、玩家死亡和场景退出均主动归还，不能把已有慢动作/测试加速改成 1。
extends Node

## 保留打击的短促重量，但普通命中不再把全世界压到近乎静止。
## 请求仍按普通/重击/终结技分级；仅压缩表现时长，不改战斗计时器或伤害。
const SCALE_RATIO := 0.35
const DURATION_RATIO := 0.6
const MAX_DURATION := 0.045
const RECOVERY_GAP := 0.20
var active := false
var _restore_scale := 1.0
var _applied_scale := 1.0
var _deadline_usec := 0
var _next_allowed_usec := 0
var _player_dead := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.player_died.connect(_on_player_died)
	EventBus.player_respawned.connect(_on_player_respawned)
	set_process(false)


func request(duration: float) -> bool:
	if not is_inside_tree() or get_tree().paused or _player_dead \
			or not is_finite(duration) or duration <= 0.0:
		return false
	var now := Time.get_ticks_usec()
	if active or now < _next_allowed_usec or Engine.time_scale <= 0.0:
		return false
	_restore_scale = Engine.time_scale
	_applied_scale = _restore_scale * SCALE_RATIO
	_deadline_usec = now + int(minf(duration * DURATION_RATIO, MAX_DURATION) * 1000000.0)
	_next_allowed_usec = _deadline_usec + int(RECOVERY_GAP * 1000000.0)
	active = true
	Engine.time_scale = _applied_scale
	set_process(true)
	return true


func _process(_delta: float) -> void:
	if get_tree().paused or Time.get_ticks_usec() >= _deadline_usec \
			or not is_equal_approx(Engine.time_scale, _applied_scale):
		cancel()


func cancel() -> void:
	if active:
		# 长帧可能延后恢复：保护窗从实际归还开始，不能刚恢复又立刻顿帧。
		_next_allowed_usec = maxi(_next_allowed_usec, Time.get_ticks_usec() + int(RECOVERY_GAP * 1000000.0))
	# 外部系统期间改变了尺度时，它是新的权威；不得用旧值反向覆盖。
	if active and is_equal_approx(Engine.time_scale, _applied_scale):
		Engine.time_scale = _restore_scale
	active = false
	set_process(false)


func _on_player_died() -> void:
	_player_dead = true
	cancel()


func _on_player_respawned() -> void:
	_player_dead = false


func _exit_tree() -> void:
	cancel()
