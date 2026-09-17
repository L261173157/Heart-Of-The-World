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
## 夜晚结束（视觉口径）：night_intensity() 在 0.75~0.95 渐出黎明——侦测增益
## 必须在同一时刻收回，否则 0.75~1.0 区间画面已是白天、怪物却仍按 1.4×
## 夜视索敌，玩家被"看不见的黑夜规则"提前锁定，感知为不公平
const DAWN_END := 0.95

var sim: EcologySim
## 当天进度 0~1（0 = 黎明）
var day_time: float = 0.15
var is_night: bool = false
## 已流逝的游戏天数（寿命系统按天推进；每局从 0 重新计）
var game_day: int = 0
## 昼夜精确累加器：按秒累加、整日精确扣除 DAY_LENGTH——旧的
## fmod(day_time + delta/DAY_LENGTH, 1.0) 每帧除法取模、误差逐帧复合；
## 累加器方案的误差不跨日复合（每日扣除的是同一常量）
var _day_accum := 0.15 * DAY_LENGTH

var _accum := 0.0
var _running := false


func start(p_sim: EcologySim) -> void:
	sim = p_sim
	_running = true
	# 防御性清零：不依赖"上局 _exit_tree 一定先调过 stop()"这条隐性契约
	# （headless 测试直接换 sim 重启时残留欠账会立刻连跑数个补帧 tick）
	_accum = 0.0
	# 每局从清晨重新开始：autoload 的昼夜状态不跨局残留
	# （否则新开局可能处于"夜幕层未显示但怪物侦测已提升"的隐形夜晚）；
	# "继续冒险"的世界在 game_world 恢复快照后调 resume_clock 接回真实时刻
	day_time = 0.15
	_day_accum = 0.15 * DAY_LENGTH
	game_day = 0
	if is_night:
		is_night = false
		EventBus.day_phase_changed.emit(false)
	sim.tick_completed.connect(
		func(summary: Dictionary) -> void: EventBus.sim_tick_completed.emit(summary)
	)


## 继续冒险时恢复世界时钟（生态快照带 day_time/game_day 时由 game_world 调用）。
## 不恢复 = "读档回清晨"，生态连续而昼夜断裂，还可借反复读档白嫖寿命；
## is_night 同步重算并广播——否则恢复到夜晚时画面无夜幕层而怪物侦测已提升
func resume_clock(p_day_time: float, p_game_day: int) -> void:
	day_time = clampf(p_day_time, 0.0, 0.999)
	_day_accum = day_time * DAY_LENGTH
	game_day = maxi(0, p_game_day)
	var night := day_time >= NIGHT_START and day_time < DAWN_END
	if night != is_night:
		is_night = night
		EventBus.day_phase_changed.emit(night)


## 停止驱动并释放模拟引用（回主菜单时调用，避免旧世界后台空转 tick）
func stop() -> void:
	_running = false
	sim = null
	# 清掉跨局残留的亚秒相位
	_accum = 0.0


func _process(delta: float) -> void:
	if not _running:
		return
	# 挂起/切后台恢复后 delta 巨大：无上限追帧会在单帧串行连跑数百 tick
	# （每 tick 全实例遍历 + 信号驱动的节点增删），直接掉帧雪崩——最多补 3 tick 丢弃欠账；
	# 同一份钳制也约束昼夜相位（否则昼夜瞬间跳变、寿命多扣天数，防御口径与 tick 侧一致）
	delta = minf(delta, TICK_INTERVAL * 3.0)
	_advance_day(delta)
	_accum += delta
	_accum = minf(_accum, TICK_INTERVAL * 3.0)
	while _accum >= TICK_INTERVAL:
		_accum -= TICK_INTERVAL
		sim.tick()


func _advance_day(delta: float) -> void:
	_day_accum += delta
	while _day_accum >= DAY_LENGTH:
		_day_accum -= DAY_LENGTH
		# 绕回 = 新的一天（寿命/成就按天推进）
		game_day += 1
		EventBus.game_day_advanced.emit(game_day)
	day_time = _day_accum / DAY_LENGTH
	var night := day_time >= NIGHT_START and day_time < DAWN_END
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
