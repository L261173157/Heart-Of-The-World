## 触屏输入中转站（autoload 单例）。
## 虚拟摇杆 / 攻击、冲刺按钮把结果写到这里，玩家控制器从这里读。
## 架构铁律：所有输入必须抽象成 Input Map 动作或经由本类，
## 键盘（开发期）与触屏（iOS）双通道在任何玩法代码里都不区分。
extends Node

## 摇杆当前向量（长度 0~1），joystick_active 为 false 时玩家应使用键盘输入
var move_vector: Vector2 = Vector2.ZERO
var joystick_active: bool = false

var _attack_queued: bool = false
var _dash_queued: bool = false
var _heavy_queued: bool = false
var _bolt_queued: bool = false
var _heal_queued: bool = false


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


## 玩家死亡/游戏暂停时清空排队：消费方不可用期间的点击不应在恢复后一次性兑现
func clear_queues() -> void:
	_attack_queued = false
	_dash_queued = false
	_heavy_queued = false
	_bolt_queued = false
	_heal_queued = false
