## 弹幕池生命周期回归：真实多物体同帧碰撞、重复回收、复用、超时与场景退出。
## 运行：Godot --headless --path Code res://tests/projectile_pool_test.tscn
extends Node2D

class TestWorld extends Node2D:
	func _exit_tree() -> void:
		Projectile.clear_pool()

class DamageTarget extends CharacterBody2D:
	var hits := 0
	func take_damage(_amount: float, _position: Vector2, _source: String) -> void:
		hits += 1

var _fails := 0

func _ready() -> void:
	GameState.save_enabled = false
	Projectile.clear_pool()
	await _test_physics_collision_and_exit()
	await _test_release_and_reuse()
	await _test_capacity_and_pending_exit()
	if _fails == 0:
		print("=== 弹幕池生命周期验证全部通过 ===")
	else:
		print("=== 弹幕池生命周期 %d 项失败 ===" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)


func _check(ok: bool, label: String) -> void:
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_fails += 1


func _wait_frames() -> void:
	for i in 4:
		await get_tree().physics_frame
	await get_tree().process_frame


func _test_physics_collision_and_exit() -> void:
	var world := TestWorld.new()
	add_child(world)
	# 真实物理回调而非直接调 _release：一发弹幕同帧触发两堵重叠墙。
	for i in 2:
		var wall := StaticBody2D.new()
		var collider := CollisionShape2D.new()
		var shape := CircleShape2D.new()
		shape.radius = 30.0
		collider.shape = shape
		wall.add_child(collider)
		world.add_child(wall)
	var p := Projectile.spawn(world, Vector2.ZERO, Vector2.RIGHT, 5.0, 0.0)
	await _wait_frames()
	_check(Projectile._pool.size() == 1 and not p.is_inside_tree(),
			"同帧撞两物体只归还一次，且在安全阶段摘树")
	# 旧实现这里重复 free 引起 SIGSEGV；使用与 game_world 相同的 _exit_tree 清池。
	world.queue_free()
	await get_tree().process_frame
	_check(Projectile._pool.is_empty() and not is_instance_valid(p),
			"场景退出清池无重复释放")


func _test_release_and_reuse() -> void:
	var world := TestWorld.new()
	add_child(world)
	var target := DamageTarget.new()
	world.add_child(target)
	target.add_to_group("player")
	var p := Projectile.spawn(world, Vector2(500, 500), Vector2.RIGHT, 5.0, 0.0)
	p._on_body_entered(target)
	p._on_body_entered(target)
	p._release()
	_check(target.hits == 1, "重复回调不重复造成伤害")
	_check(Projectile._pool.is_empty() and p.get_parent() == world,
			"延迟摘树前仍由旧父节点持有，不能提前借出")
	var other := Projectile.spawn(world, Vector2(600, 500), Vector2.RIGHT, 5.0, 0.0)
	_check(other != p, "同帧新发射不会取得仍待摘树的弹幕")
	await _wait_frames()
	var reused := Projectile.spawn(world, Vector2(700, 500), Vector2.UP, 9.0, 0.0,
			"新射手", "bone")
	_check(reused == p and reused.is_inside_tree() and reused.is_physics_processing()
			and reused.visible and reused.monitoring and not reused._retiring,
			"复用恢复处理、可见与碰撞状态")
	_check(reused.source_name == "新射手" and reused.damage == 9.0
			and reused.direction == Vector2.UP and reused.bolt_tex == "bone",
			"复用更新伤害、方向、归因与贴图")
	reused._life = 0.0
	await _wait_frames()
	_check(Projectile._pool.size() == 1 and not reused.is_inside_tree(),
			"超时出口安全归还一次")
	world.queue_free()
	await get_tree().process_frame


func _test_capacity_and_pending_exit() -> void:
	var world := TestWorld.new()
	add_child(world)
	for i in Projectile.POOL_MAX + 3:
		var p := Projectile.spawn(world, Vector2(i * 40, 2000), Vector2.RIGHT, 5.0, 0.0)
		p._release()
	await _wait_frames()
	_check(Projectile._pool.size() == Projectile.POOL_MAX,
			"同帧批量归还在完成摘树时执行池上限")
	world.queue_free()
	await get_tree().process_frame
	_check(Projectile._pool.is_empty(), "满池世界退出后无静态残留")

	world = TestWorld.new()
	add_child(world)
	var pending := Projectile.spawn(world, Vector2(500, 2000), Vector2.RIGHT, 5.0, 0.0)
	var old_active := Projectile.spawn(world, Vector2(800, 2000), Vector2.RIGHT, 5.0, 0.0)
	pending._release()
	Projectile.clear_pool()
	old_active._release()
	var fresh := Projectile.spawn(world, Vector2(600, 2000), Vector2.RIGHT, 5.0, 0.0)
	await _wait_frames()
	_check(Projectile._pool.is_empty() and not is_instance_valid(pending)
			and not is_instance_valid(old_active)
			and is_instance_valid(fresh) and fresh.is_inside_tree(),
			"清池使旧延迟回收失效，不污染新世界或释放新弹幕")
	fresh._release()
	world.queue_free()
	await _wait_frames()
	_check(Projectile._pool.is_empty() and not is_instance_valid(fresh),
			"父场景已排队删除时不把待回收节点转入静态池")
