## 石魔像：重击守卫——察觉半径大、护甲厚、伤害极高；重击有明显前摇（蓄力变橙），
## 命中判定取攻击瞬间的距离，前摇期间走出范围即可规避。
## 永不逃跑、生态上永不迁徙、繁殖极慢——熔岩洞窟的定海神针，
## 被玩家猎杀殆尽就是一条世界线里的永久灭绝（2026-09-04 起该承诺成真：
## 玩家灭杀归零的物种不再重引入；自然兴衰归零仍可"从世界边缘迁徙回来"）。
## 前摇/砸击半径读 SpeciesData（石魔像与窟魔王 Boss 共用本脚本，可按物种调参）
class_name Guardian
extends MonsterBase

const S_WINDUP := 10

var _state_timer := 0.0
## 蓄力范围圈（石魔像与窟魔王共用本脚本，一并生效）
var _ring: RangeRing
## 蓄力圈分档重绘：72 段弧的全量重绘按进度粗化为 12 档——
## 0.8s 蓄力 ≈ 48 物理帧 → 最多 12 次重绘，观感无差别
var _ring_step := -1


## 蓄力范围圈：画出重击实际判定半径，圈越亮越粗 = 越接近砸下；
## 新玩家不需要背数据，前摇期间看着圈外撤即可安全规避
class RangeRing extends Node2D:
	var radius := 0.0
	var progress := 0.0  # 0→1 蓄力进度

	func _draw() -> void:
		if radius <= 0.0:
			return
		draw_circle(Vector2.ZERO, radius, Color(1.0, 0.3, 0.12, 0.04 + 0.08 * progress))
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 72,
			Color(1.0, 0.5, 0.2, 0.5 + 0.5 * progress), 2.0 + 2.5 * progress)


func setup(p_inst: MonsterInstance) -> void:
	super(p_inst)
	_ring = RangeRing.new()
	_ring.radius = inst.species.attack_range * inst.species.guard_smash_range_mult
	_ring.z_index = -1  # 圈画在龟身之下
	add_child(_ring)
	_ring.visible = false


func on_sim_death() -> void:
	super()
	if _ring != null:
		_ring.visible = false


func _attack_tick(_delta: float, player: Node2D) -> void:
	if player == null or not player.visible:
		state = S_PATROL
		return
	var dist := global_position.distance_to(player.global_position)
	if dist > inst.species.attack_range * 1.3:
		state = S_CHASE
		return
	# 冷却恢复期不再原地罚站：缓慢逼近（0.4 倍速）保持守卫的压迫感；
	# 玩家仍可靠 0.8s 蓄力前摇 + 射程圈预警在砸下之前撤出判定半径
	if _attack_cd > 0.0:
		if dist > inst.species.attack_range:
			velocity = (player.global_position - global_position).normalized() * inst.move_speed() * 0.4
		else:
			velocity = Vector2.ZERO
		return
	velocity = Vector2.ZERO
	state = S_WINDUP
	_state_timer = inst.species.guard_windup_time
	# 蓄力=抡起：攻击条带 0.4s 播完停在蓄力帧，蓄满砸下与收招 squash/boom 同拍
	_play_action_anim("attack", inst.species.guard_windup_time)
	set_tint(Color(1.0, 0.7, 0.3))  # 蓄力预警
	_squash(Vector2(1.14, 0.86), 0.7)  # 蓄力下沉（与 0.8s 前摇同拍）
	if _ring != null:
		_ring.visible = true
		_ring.progress = 0.0
		_ring_step = -1
		_ring.queue_redraw()


## 闪红恢复到蓄力橙（受击不吞预警色）
func _restore_tint() -> Color:
	return Color(1.0, 0.7, 0.3) if state == S_WINDUP else _base_modulate


func _extra_state_tick(delta: float, player: Node2D) -> void:
	if state != S_WINDUP:
		return
	velocity = Vector2.ZERO
	_state_timer -= delta
	if _ring != null:
		_ring.progress = clampf(1.0 - _state_timer / inst.species.guard_windup_time, 0.0, 1.0)
		var step := int(_ring.progress * 12.0)
		if step != _ring_step:
			_ring_step = step
			_ring.queue_redraw()
	if _state_timer > 0.0:
		return
	set_tint(_base_modulate)
	_squash(Vector2(0.88, 1.12), 0.2)  # 砸下过冲
	if _ring != null:
		_ring.visible = false
	_attack_cd = inst.species.attack_cooldown
	# 砸击落点爆焰（美术 v5 fx 全量；Boss ×1.8 加重份量）
	EventBus.fx_requested.emit("boom", global_position,
		1.8 if inst.species.is_boss else 1.2)
	if player != null and player.visible \
			and global_position.distance_to(player.global_position) <= inst.species.attack_range * inst.species.guard_smash_range_mult:
		if player.has_method("take_damage"):
			player.take_damage(CombatMath.physical_damage(inst.attack_power()), global_position, inst.display_name())
	state = S_CHASE
