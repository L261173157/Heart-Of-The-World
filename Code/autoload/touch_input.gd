## 触屏输入中转站（autoload 单例）。
## 虚拟摇杆 / 攻击、冲刺按钮把结果写到这里，玩家控制器从这里读。
## 架构铁律：所有输入必须抽象成 Input Map 动作或经由本类，
## 键盘（开发期）与触屏（iOS）双通道在任何玩法代码里都不区分。
extends Node

## 取消不是松手：任何中断都清蓄力且禁止反击，键盘和触屏共用通知。
signal guard_canceled

var guard_held: bool = false
var _guard_release_queued: bool = false
## UI 权限同样约束键盘。按需读取可用性，禁用/隐藏后当帧就不能重新按 F 举盾。
## 无 HUD 的独立玩家场景默认可用；Callable 失效后也自动回到默认，不留全局死锁。
var _guard_availability_check: Callable
var guard_available: bool:
	get:
		return not _guard_availability_check.is_valid() or bool(_guard_availability_check.call())

## 摇杆当前向量（长度 0~1），joystick_active 为 false 时玩家应使用键盘输入
var move_vector: Vector2 = Vector2.ZERO
var joystick_active: bool = false

var _interaction_queued := ""
var _attack_queued: bool = false
var _dash_queued: bool = false
var _heavy_queued: bool = false
var _bolt_queued: bool = false
var _heal_queued: bool = false
var _empower_queued: bool = false


func _ready() -> void:
	# 死亡/复活均结束上一次手势；局部触点与全局向量必须一同复位。
	EventBus.player_died.connect(reset)
	EventBus.player_respawned.connect(reset)


## 独立交互通道；空参数只供键盘/测试按当前对象发起，不与攻击共用。
func queue_interact(target_id: String = "") -> void:
	_interaction_queued = target_id if not target_id.is_empty() else "__nearest__"


func consume_interact() -> String:
	var target := _interaction_queued
	_interaction_queued = ""
	return target


## 攻击按钮按下时调用
func queue_attack() -> void:
	_attack_queued = true


## 玩家每帧轮询；取走后清空，保证一次按下只触发一次攻击
func consume_attack() -> bool:
	var pressed := _attack_queued
	_attack_queued = false
	return pressed


## 冲刺按钮按下时调用 / 取走（与攻击同模式）
func queue_dash() -> void:
	_dash_queued = true


func consume_dash() -> bool:
	var pressed := _dash_queued
	_dash_queued = false
	return pressed


## 重击按钮（与攻击/冲刺同模式）
func queue_heavy() -> void:
	_heavy_queued = true


func consume_heavy() -> bool:
	var pressed := _heavy_queued
	_heavy_queued = false
	return pressed


## 法弹按钮（与攻击/冲刺同模式）
func queue_bolt() -> void:
	_bolt_queued = true


func consume_bolt() -> bool:
	var pressed := _bolt_queued
	_bolt_queued = false
	return pressed


## 治疗按钮（与攻击/冲刺同模式）
func queue_heal() -> void:
	_heal_queued = true


func consume_heal() -> bool:
	var pressed := _heal_queued
	_heal_queued = false
	return pressed


## 武装强化按钮（与攻击/冲刺同模式）
func queue_empower() -> void:
	_empower_queued = true


func consume_empower() -> bool:
	var pressed := _empower_queued
	_empower_queued = false
	return pressed


## 只由当前持盾控件登记自己的实时可用性；旧 HUD 退树不能清掉新 HUD 的入口。
func set_guard_availability_check(check: Callable) -> void:
	_guard_availability_check = check
	if not guard_available:
		cancel_guard()


func clear_guard_availability_check(check: Callable) -> void:
	if _guard_availability_check == check:
		_guard_availability_check = Callable()


## 防御是持续输入，只有由按住转为正常松手才排队一次反击。
func begin_guard() -> void:
	if not guard_available:
		cancel_guard()
		return
	guard_held = true
	_guard_release_queued = false


func release_guard() -> void:
	if guard_held:
		guard_held = false
		_guard_release_queued = true


func consume_guard_release() -> bool:
	var released := _guard_release_queued
	_guard_release_queued = false
	return released


func cancel_guard() -> void:
	guard_held = false
	_guard_release_queued = false
	# 即使只有键盘 F 按住，也必须通知玩家直到松开才允许重新举盾。
	guard_canceled.emit()


## 玩家死亡/游戏暂停时清空排队：消费方不可用期间的点击不应在恢复后一次性兑现
func clear_queues() -> void:
	cancel_guard()
	_interaction_queued = ""
	_attack_queued = false
	_dash_queued = false
	_heavy_queued = false
	_bolt_queued = false
	_heal_queued = false
	_empower_queued = false


## 场景切换时复位全部输入状态：按住摇杆时退出世界（节点释放收不到 release 事件），
## 摇杆向量会永久残留——再进世界角色自顾自朝旧方向漂移，必须由新场景入口主动清
func reset() -> void:
	move_vector = Vector2.ZERO
	joystick_active = false
	clear_queues()
	EventBus.touch_input_reset.emit()


## iOS 按住摇杆切后台时不保证补发 ScreenTouch released；恢复后若保留状态，
## 角色会自行漂移，按钮队列也可能在第一帧兑现。autoload 兜底清全局输入。
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		reset()
