## 装备反馈层：真正的 CPU 粒子，有界复用，低亮度且永远在敌方预警之下。
## 数量预算只覆盖新增装备层；不宣称包含既有全游戏 VFX，更不是设备性能验收。
class_name EquipmentParticleLayer
extends Node2D

const MAX_EMITTERS := 12
const MAX_PARTICLES := 128
const REDUCED_EMITTERS := 4
const REDUCED_PARTICLES := 32
const BURSTS := {
	"hit": {"amount": 6, "life": 0.18, "priority": 0, "color": Color(0.72, 0.72, 0.62, 0.72)},
	"block": {"amount": 8, "life": 0.22, "priority": 1, "color": Color(0.56, 0.70, 0.76, 0.76)},
	"orange": {"amount": 12, "life": 0.35, "priority": 2, "color": Color(0.85, 0.51, 0.22, 0.78)},
}
var _entries: Array[Dictionary] = []
var _texture: ImageTexture
var _epoch := 0
var _reduced := false
var _disabled_until_respawn := false
var emitted_bursts := 0
var suppressed_bursts := 0
var peak_emitters := 0
var peak_particles := 0


func _ready() -> void:
	add_to_group("equipment_particles")
	z_index = 4 # 盾形敌预警 z30；绝不盖住危险提示。
	var pixels := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	pixels.fill(Color.WHITE)
	_texture = ImageTexture.create_from_image(pixels)
	_reduced = bool(GameState.settings.get("equipment_particles_reduced", false))
	for i in MAX_EMITTERS:
		var emitter := CPUParticles2D.new()
		emitter.name = "EquipmentBurst%d" % i
		emitter.emitting = false
		emitter.one_shot = true
		emitter.explosiveness = 1.0
		emitter.randomness = 0.0
		emitter.local_coords = false
		emitter.texture = _texture
		emitter.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		emitter.gravity = Vector2(0, 20)
		emitter.spread = 110.0
		emitter.initial_velocity_min = 28.0
		emitter.initial_velocity_max = 60.0
		emitter.scale_amount_min = 1.0
		emitter.scale_amount_max = 2.0 # 2×2纹理，最终始终2–4世界像素。
		emitter.fixed_fps = 60
		emitter.fract_delta = false
		emitter.use_fixed_seed = true
		emitter.seed = i + 1
		var material := CanvasItemMaterial.new()
		material.blend_mode = CanvasItemMaterial.BLEND_MODE_MIX
		emitter.material = material
		var fade := Gradient.new()
		fade.set_color(0, Color.WHITE)
		fade.set_color(1, Color(1, 1, 1, 0))
		emitter.color_ramp = fade
		add_child(emitter)
		emitter.hide()
		_entries.append({"emitter": emitter, "remaining": 0.0, "amount": 0, "priority": -1})
	EventBus.equipment_particles_requested.connect(emit_burst)
	EventBus.player_died.connect(_on_player_died)
	EventBus.player_respawned.connect(_on_player_respawned)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED or what == NOTIFICATION_EXIT_TREE \
			or what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		clear_all()


func _on_player_died() -> void:
	_disabled_until_respawn = true
	clear_all()


func _on_player_respawned() -> void:
	_disabled_until_respawn = false


func set_reduced(value: bool) -> void:
	if _reduced == value:
		return
	_reduced = value
	clear_all() # 当帧降档就满足4/32，不等待旧粒子自然过期。


func _process(delta: float) -> void:
	set_reduced(bool(GameState.settings.get("equipment_particles_reduced", false)))
	for entry in _entries:
		if float(entry.remaining) <= 0.0:
			continue
		entry.remaining = maxf(0.0, float(entry.remaining) - delta)
		if float(entry.remaining) <= 0.0:
			_retire(entry)


## 同步准入，没有 deferred/Timer。旧场景无排队发射，暂停时立即清除可见状态。
func emit_burst(kind: String, pos: Vector2, direction := Vector2.RIGHT) -> bool:
	if not is_inside_tree() or is_queued_for_deletion() or get_parent() == null \
			or get_parent().is_queued_for_deletion() or get_tree().paused \
			or _disabled_until_respawn or not BURSTS.has(kind):
		return false
	set_reduced(bool(GameState.settings.get("equipment_particles_reduced", false)))
	var spec: Dictionary = BURSTS[kind]
	var amount := int(spec.amount) / (2 if _reduced else 1)
	var emitter_limit := REDUCED_EMITTERS if _reduced else MAX_EMITTERS
	var particle_limit := REDUCED_PARTICLES if _reduced else MAX_PARTICLES
	var priority := int(spec.priority)
	var slot: Dictionary = {}
	# 满池时只替换更低优先级的旧反馈；普通命中绝不挤掉格挡或橙装。
	if active_emitter_count() >= emitter_limit or live_particle_count() + amount > particle_limit:
		for entry in _entries:
			if float(entry.remaining) > 0.0 and int(entry.priority) < priority:
				if slot.is_empty() or int(entry.priority) < int(slot.priority) \
						or (int(entry.priority) == int(slot.priority) and float(entry.remaining) < float(slot.remaining)):
					slot = entry
		if not slot.is_empty():
			_retire(slot)
	if active_emitter_count() >= emitter_limit or live_particle_count() + amount > particle_limit:
		suppressed_bursts += 1
		return false
	if slot.is_empty():
		for entry in _entries:
			if float(entry.remaining) <= 0.0:
				slot = entry
				break
	if slot.is_empty():
		suppressed_bursts += 1
		return false
	var emitter := slot.emitter as CPUParticles2D
	emitter.amount = amount
	emitter.lifetime = float(spec.life)
	emitter.direction = direction.normalized() if not direction.is_zero_approx() else Vector2.RIGHT
	emitter.color = spec.color
	emitter.global_position = pos.round()
	emitter.show()
	emitter.seed = emitted_bursts + 1
	emitter.restart(true)
	emitter.emitting = true
	# 多保留一物理帧预算，避免CPU粒子末帧与新一批重叠超限。
	slot.remaining = float(spec.life) + 1.0 / 60.0
	slot.amount = amount
	slot.priority = priority
	emitted_bursts += 1
	peak_emitters = maxi(peak_emitters, active_emitter_count())
	peak_particles = maxi(peak_particles, live_particle_count())
	return true


func _retire(entry: Dictionary) -> void:
	var emitter := entry.emitter as CPUParticles2D
	if is_instance_valid(emitter):
		# Godot4.7 restart同步清所有active位；随后关发射，不只把旧粒子藏起来。
		# 保留seed使表现层不会消费战斗/掉落使用的全局随机数流。
		emitter.restart(true)
		emitter.emitting = false
		emitter.hide()
	entry.remaining = 0.0
	entry.amount = 0
	entry.priority = -1


func clear_all() -> void:
	_epoch += 1
	for entry in _entries:
		_retire(entry)


func active_emitter_count() -> int:
	var count := 0
	for entry in _entries:
		if float(entry.remaining) > 0.0:
			count += 1
	return count


## 保守占用计数：整批寿命结束前都算活跃，实际绘制粒子不会高于这个数。
func live_particle_count() -> int:
	var count := 0
	for entry in _entries:
		count += int(entry.amount)
	return count


func budget_snapshot() -> Dictionary:
	return {"emitters": active_emitter_count(), "particles": live_particle_count(),
		"reduced": _reduced, "epoch": _epoch, "peak_emitters": peak_emitters,
		"peak_particles": peak_particles, "pool_size": _entries.size()}
