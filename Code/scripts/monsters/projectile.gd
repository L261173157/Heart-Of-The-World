## 远程弹幕（沼泽蛛吐息）：直线飞行，命中玩家结算伤害，撞墙消散，超时自毁。
## 碰撞只检测玩家与地形（均 layer 1）；穿过其它怪物（虫海互相挡弹道会自杀）。
## 类级对象池（2026-10-01 真机卡顿修复）：围攻时多只远程怪高频吐息，
## 逐发 instantiate（Area2D+CollisionShape+Visual 节点构造成本）是战斗
## 掉帧的组成部分；发射方走 Projectile.spawn()，命中/撞墙/超时三出口
## 统一归还池。池上限防异常场景无限增长
class_name Projectile
extends Area2D

const LIFE_TIME := 2.2
## 池上限：同屏存活弹幕理论上限 ≈ 远程怪数×(射速×2.2s)，16 只×1.4≈22
const POOL_MAX := 32

## 空闲池（static：跨场景生命周期，怪物表现节点流式进出不回收池）
static var _pool: Array[Projectile] = []
## 世界退场时递增；尚未执行的延迟归还不能把旧世界弹幕塞回新池。
static var _pool_epoch := 0


## 发射入口（池化）：从池取或新建，挂到发射者父节点并初始化
static func spawn(parent: Node, pos: Vector2, dir: Vector2, dmg: float,
		p_speed := 270.0, p_source := "", p_bolt := "") -> Projectile:
	var p: Projectile = _pool.pop_back() if not _pool.is_empty() else null
	if p == null:
		p = preload("res://scenes/monsters/projectile.tscn").instantiate()
	parent.add_child(p)
	p.global_position = pos
	p.launch(dir, dmg, p_speed, p_source, p_bolt)
	return p


## 归还池（命中/撞墙/超时统一出口）：摘树入池；超上限直接释放
func _release() -> void:
	# 同一次物理同步可能先后派发多个 body_entered。必须在回调内同步关闸，
	# 否则同一节点会重复入池，世界退场时重复 free 甚至令引擎崩溃。
	if _retiring or is_queued_for_deletion():
		return
	_retiring = true
	set_physics_process(false)
	hide()
	# CollisionObject 不能在物理查询派发中摘树。归还前仍归父节点所有，
	# 延迟阶段完成摘树后才可被 spawn 复用，避免“仍在旧父节点就借出”的竞态。
	_finish_release.call_deferred(_spawn_epoch)


func _finish_release(epoch: int) -> void:
	var parent := get_parent()
	if is_queued_for_deletion():
		return
	if epoch != _pool_epoch or parent == null or not is_inside_tree() \
			or parent.is_queued_for_deletion() or _pool.size() >= POOL_MAX:
		queue_free()
		return
	monitoring = false
	parent.remove_child(self)
	_pool.append(self)


## 世界退场清池（game_world._exit_tree 调用）：静态池节点无树宿主，显式释放
static func clear_pool() -> void:
	_pool_epoch += 1
	for p in _pool:
		if is_instance_valid(p):
			p.free()
	_pool.clear()

var direction := Vector2.RIGHT
var damage := 5.0
var speed := 270.0
## 射手名（死亡信息归因用）
var source_name := ""
## 弹体贴图名（Enemy Pack 弹体烘焙件，空 = 默认箭矢；launch 前赋值）
var bolt_tex := ""

var _life := LIFE_TIME
var _retiring := false
var _spawn_epoch := 0


func launch(dir: Vector2, dmg: float, p_speed := 270.0, p_source := "", p_bolt := "") -> void:
	_retiring = false
	_spawn_epoch = _pool_epoch
	monitoring = true
	set_physics_process(true)
	show()
	direction = dir.normalized()
	damage = dmg
	speed = p_speed
	source_name = p_source
	bolt_tex = p_bolt
	rotation = direction.angle()
	_life = LIFE_TIME
	# v6 弹道：EP 弹体首帧烘焙件按物种取图（acorn/bone/harpoon/spell/bomb），
	# 默认 Archer 箭矢缩图；素材一律朝右，launch 已按方向设 rotation。
	# （原在 _ready：池化复用不重跑 _ready，纹理设置随 launch 每发刷新）
	var name := bolt_tex if bolt_tex != "" else "arrow"
	($Visual as Sprite2D).texture = load(
		"res://assets/ts/structures_baked/%s.png" % name)


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	position += direction * speed * delta
	_life -= delta
	if _life <= 0.0:
		_release()


func _on_body_entered(body: Node2D) -> void:
	if _retiring or is_queued_for_deletion():
		return
	if body.is_in_group("player") and body.has_method("take_damage"):
		_release()
		body.take_damage(damage, global_position, source_name)
		return
	# 撞墙消散（不再穿地形，与玩家法弹对称；巢穴在独立层 4 不被检测）。
	# 障碍瓦片（TileMapLayer）同样消散——怪物弹幕不能替玩家开路
	if body is StaticBody2D or body is TileMapLayer:
		_release()
