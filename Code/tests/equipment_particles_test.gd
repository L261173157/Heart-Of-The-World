## 真粒子预算/清场回归；每项检查运行真实CPUParticles2D，不以绘制圆点代替。
extends Node2D

const LAYER := preload("res://scripts/combat/equipment_particle_layer.gd")
var _checks := 0
var _fails := 0
var _layer: EquipmentParticleLayer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.save_enabled = false
	WorldSim.stop()
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])

func _run() -> void:
	GameState.settings["equipment_particles_reduced"] = false
	_layer = LAYER.new()
	_layer.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_layer)
	_check(_layer.get_child_count() == 12, "固定12个真实CPU粒子节点预热，无无限增长")
	for emitter in _layer.get_children():
		_check(emitter is CPUParticles2D and emitter.one_shot
			and emitter.texture.get_size() == Vector2(2, 2)
			and emitter.scale_amount_min == 1.0 and emitter.scale_amount_max == 2.0
			and emitter.material.blend_mode == CanvasItemMaterial.BLEND_MODE_MIX,
			"%s真实2–4px、单次、普通混合，无灯光" % emitter.name)
	for kind: String in LAYER.BURSTS:
		_layer.clear_all()
		_check(_layer.emit_burst(kind, Vector2(300, 200)), "%s成功准入" % kind)
		var entry: Dictionary = _layer._entries[0]
		_check(entry.emitter.amount == int(LAYER.BURSTS[kind].amount)
			and is_equal_approx(entry.emitter.lifetime, float(LAYER.BURSTS[kind].life)),
			"%s数量和实际引擎寿命同源" % kind)
	_layer.clear_all()
	seed(51391)
	var expected_random := randi()
	seed(51391)
	_layer.emit_burst("hit", Vector2.ZERO)
	_layer.clear_all()
	_check(randi() == expected_random, "粒子发射和强制清场不消费全局战斗随机数")
	for i in 1000:
		_layer.emit_burst(["hit", "block", "orange"][i % 3], Vector2(300, 200))
		if i % 100 == 0:
			_check(_layer.active_emitter_count() <= 12 and _layer.live_particle_count() <= 128,
				"标准模式并发预算第%d次" % i)
	_check(_layer.suppressed_bursts > 0 and _layer.get_child_count() == 12,
		"过载反馈被限流，池规模不增长")
	_layer.clear_all()
	for i in 12:
		_layer.emit_burst("hit", Vector2(i, 0))
	_check(_layer.emit_burst("orange", Vector2.ZERO) and _layer.active_emitter_count() == 12,
		"满发射器池优先让出低级命中给橙装，不增加发射器")
	var epoch := _layer._epoch
	get_tree().paused = true
	_check(_layer.active_emitter_count() == 0 and _layer.live_particle_count() == 0
		and _layer._epoch > epoch, "暂停当帧清池并推进epoch")
	_check(not _layer.emit_burst("orange", Vector2.ZERO), "暂停期间拒绝迟到发射")
	await get_tree().create_timer(0.08, true).timeout
	get_tree().paused = false
	_check(_layer.active_emitter_count() == 0, "恢复没有延迟补发")
	GameState.settings["equipment_particles_reduced"] = true
	for i in 100:
		_layer.emit_burst(["hit", "block", "orange"][i % 3], Vector2(300, 200))
	_check(_layer.active_emitter_count() <= 4 and _layer.live_particle_count() <= 32,
		"减弱模式4发射器/32粒子上限")
	_layer.clear_all()
	for kind: String in LAYER.BURSTS:
		_layer.clear_all()
		_layer.emit_burst(kind, Vector2.ZERO)
		_check(_layer.live_particle_count() == int(LAYER.BURSTS[kind].amount) / 2,
			"减弱模式%s单批减半" % kind)
	EventBus.player_died.emit()
	_check(_layer.active_emitter_count() == 0 and not _layer.emit_burst("hit", Vector2.ZERO),
		"死亡清场且后续飞弹命中不能在尸体期间补发")
	EventBus.player_respawned.emit()
	_check(_layer.emit_burst("hit", Vector2.ZERO), "复活后新事件可重新发射")
	await get_tree().create_timer(0.25).timeout
	_check(_layer.active_emitter_count() == 0 and _layer.live_particle_count() == 0,
		"寿命结束回池，计数归零")
	var old: WeakRef = weakref(_layer)
	_layer.queue_free()
	await get_tree().process_frame
	EventBus.equipment_particles_requested.emit("orange", Vector2.ZERO, Vector2.RIGHT)
	_check(old.get_ref() == null and get_tree().get_nodes_in_group("equipment_particles").is_empty(),
		"场景释放断开信号，无跨场景幽灵池")
	print("=== EQUIPMENT PARTICLES %s (%d checks) ===" % ["PASS" if _fails == 0 else "FAIL", _checks])
	get_tree().quit(0 if _fails == 0 else 1)
