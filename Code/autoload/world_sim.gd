## 生态模拟驱动器（autoload 单例）。
## 架构铁律：EcologySim 及 scripts/ecology/ 下所有类必须是纯逻辑
## （RefCounted/Resource + 信号），禁止引用 Node / 场景树。
## 本节点是唯一的"桥"：按固定间隔驱动 tick，并把模拟信号转发给表现层，
## 未来联机化时把 EcologySim 整体搬到服务器，客户端只保留这个桥的接收端。
extends Node

const TICK_INTERVAL := 1.0

## 昼夜循环：一天 DAY_LENGTH 游戏秒（4 分钟）；夜晚（day_time ≥ 0.55）怪物侦测提升、画面压暗
const DAY_LENGTH := 240.0
const NIGHT_START := 0.55

var sim: EcologySim
## 当天进度 0~1（0 = 黎明）
var day_time: float = 0.15
var is_night: bool = false

var _accum := 0.0
var _running := false


func start(p_sim: EcologySim) -> void:
	sim = p_sim
	_running = true
	# 每局从清晨重新开始：autoload 的昼夜状态不跨局残留
	# （否则新开局可能处于"夜幕层未显示但怪物侦测已提升"的隐形夜晚）
	day_time = 0.15
	if is_night:
		is_night = false
		EventBus.day_phase_changed.emit(false)
	sim.tick_completed.connect(
		func(summary: Dictionary) -> void: EventBus.sim_tick_completed.emit(summary)
	)


## 停止驱动并释放模拟引用（回主菜单时调用，避免旧世界后台空转 tick）
func stop() -> void:
	_running = false
	sim = null


func _process(delta: float) -> void:
	if not _running:
		return
	_advance_day(delta)
	_accum += delta
	while _accum >= TICK_INTERVAL:
		_accum -= TICK_INTERVAL
		sim.tick()


func _advance_day(delta: float) -> void:
	day_time = fmod(day_time + delta / DAY_LENGTH, 1.0)
	var night := day_time >= NIGHT_START
	if night != is_night:
		is_night = night
		EventBus.day_phase_changed.emit(night)


## 夜晚怪物侦测倍率（表现层消费）
func night_vision_mult() -> float:
	return 1.4 if is_night else 1.0


## 夜色浓度 0~1（HUD 夜幕层用：入夜前 20% 天内渐入，0.75~0.95 黎明渐出）
func night_intensity() -> float:
	if day_time < NIGHT_START - 0.2:
		return 0.0
	if day_time < NIGHT_START:
		return (day_time - (NIGHT_START - 0.2)) / 0.2
	if day_time < 0.75:
		return 1.0
	return clampf((0.95 - day_time) / 0.2, 0.0, 1.0)
