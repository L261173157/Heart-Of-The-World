## 怪物表现基类：MonsterInstance（纯数据）的"身体"。
## 公共状态机：巡逻 → 追击 → 攻击 / 逃跑 / 长途迁徙 / 尸体；
## 各物种子类通过重写虚函数注入专属机制（冲锋/分裂/远程/协同/重击）。
## 属性全部从 inst 实时计算；死亡/老化由 EcologySim 单点权威决定
## （report_killed → instance_died 信号回到这里）。
## 战斗参数（侦测/射程/冷却/逃跑比/护甲/击退抗性）全部读 SpeciesData。
class_name MonsterBase
extends CharacterBody2D

const S_PATROL := 0
const S_CHASE := 1
const S_ATTACK := 2
const S_FLEE := 3
const S_MIGRATING := 4
const S_CORPSE := 5

const PATROL_RADIUS := 60.0
const PATROL_SPEED := 40.0
const MIGRATE_ARRIVE_DIST := 24.0
const KNOCKBACK_DECAY := 900.0

## 物种节点注册表（static）：受击求援按物种定向派发，
## 只遍历本物种列表——替代原先 EventBus 全体哥布林+兵蚁广播（群体战 O(全怪) 开销）
static var _species_registry: Dictionary = {}

var inst: MonsterInstance
var anchor := Vector2.ZERO
var current_hp := 0.0
var state: int = S_PATROL

## 场景里 Visual 精灵的基础缩放（体型表现在此基础上乘 size_scale）
var sprite_base_scale := Vector2.ONE
## 常态底色（精英为金色；受击闪红后回到它而不是纯白）
var _base_modulate := Color.WHITE

var _attack_cd := 0.0
## 仇恨锁：群体响应期间不因脱离侦测圈而放弃追击
var _aggro_lock := 0.0
## 巢穴被捣毁的全族激怒：侦测提升 + 不再逃跑
var _enrage_timer := 0.0
const ENRAGE_TIME := 60.0
const ENRAGE_DETECT_MULT := 1.8
var _knockback := Vector2.ZERO
var _patrol_target := Vector2.ZERO
var _patrol_wait := 0.0
var _patrol_target_valid := false
## 受击闪红 tween（写入新的闪红/技能色前先杀旧的，避免旧 tween 把颜色拉回去）
var _flash_tween: Tween
## 玩家引用缓存：替代每物理帧的组查询（失效置空重查）
var _player_ref: Node2D
## 头顶血条（事件驱动重绘的宿主）
var _hp_bar: MonsterHpBar

@onready var visual: Sprite2D = $Visual


func setup(p_inst: MonsterInstance) -> void:
	inst = p_inst
	# 落点与巡逻锚点：区域内部随机扎根（±45% 半幅），
	# 避免全员挤在区域中心一团、四周大片空旷；分裂子代在母体死亡处扎根
	var region: SimRegion = WorldSim.sim.get_region(inst.region_id)
	if inst.spawn_pos != Vector2.INF:
		anchor = inst.spawn_pos
		global_position = inst.spawn_pos + Vector2(randf_range(-26.0, 26.0), randf_range(-26.0, 26.0))
	elif region != null:
		var half := region.size * 0.45
		anchor = region.center + Vector2(randf_range(-half.x, half.x), randf_range(-half.y, half.y))
		global_position = anchor
	else:
		anchor = WorldSim.sim.get_region_center(inst.region_id)
		global_position = anchor
	current_hp = inst.max_hp()
	sprite_base_scale = visual.scale
	if inst.is_elite:
		_base_modulate = Color(1.0, 0.78, 0.30)
		modulate = _base_modulate
	elif inst.species.is_boss:
		# Boss：暗金底色 + 恒定脉动光晕（顶点掠食者的威压感）
		_base_modulate = Color(1.0, 0.72, 0.35)
		modulate = _base_modulate
	_apply_size_visual()
	_species_registry.get_or_add(inst.species.species_name, []).append(self)


func _exit_tree() -> void:
	# 节点销毁/场景卸载时从注册表摘除，防悬挂引用与跨场景泄漏
	if inst == null:
		return
	var list: Array = _species_registry.get(inst.species.species_name)
	if list != null:
		list.erase(self)
		if list.is_empty():
			_species_registry.erase(inst.species.species_name)


func _ready() -> void:
	add_to_group("monsters")
	_hp_bar = MonsterHpBar.new()
	add_child(_hp_bar)
	EventBus.nest_ransacked.connect(_on_nest_ransacked)


func _on_nest_ransacked(species_name: String) -> void:
	if inst != null and inst.species.species_name == species_name and not inst.species.is_boss:
		_enrage_timer = ENRAGE_TIME
		_pulse_red()


## 技能预警/情绪色写入点：先杀掉进行中的闪红，避免旧 tween 结束时把颜色拉回底色
func set_tint(color: Color) -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	modulate = color


## 闪红结束时应恢复的颜色；子类重写以返回当前预警色（岩甲龟蓄力橙/野猪前摇色）
func _restore_tint() -> Color:
	return _base_modulate


## 受击/激怒闪红：渐回"当前应有颜色"——预警色期间被攻击不吞掉预警
func _pulse_red() -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	modulate = Color(1.0, 0.45, 0.45)
	_flash_tween = create_tween()
	_flash_tween.tween_property(self, "modulate", _restore_tint(), 0.15)


func _get_player() -> Node2D:
	if _player_ref == null or not is_instance_valid(_player_ref):
		_player_ref = get_tree().get_first_node_in_group("player") as Node2D
	return _player_ref


## 体型表现（分裂子代缩小）；子类可扩展（如史莱姆的果冻脉动在此基础上叠加）
func _apply_size_visual() -> void:
	visual.scale = sprite_base_scale * maxf(0.45, inst.size_scale)


func _physics_process(delta: float) -> void:
	if state == S_CORPSE:
		velocity = Vector2.ZERO
		return

	_attack_cd = maxf(0.0, _attack_cd - delta)
	_aggro_lock = maxf(0.0, _aggro_lock - delta)
	_enrage_timer = maxf(0.0, _enrage_timer - delta)
	var player := _get_player()

	if _enrage_timer <= 0.0 and _wants_flee(player) \
			and (state == S_PATROL or state == S_CHASE or state == S_ATTACK):
		state = S_FLEE

	match state:
		S_PATROL:
			_patrol(delta, player)
		S_CHASE:
			_chase_tick(delta, player)
		S_ATTACK:
			_attack_tick(delta, player)
		S_FLEE:
			_flee_tick(player)
		S_MIGRATING:
			_migrate_tick()
		_:
			_extra_state_tick(delta, player)

	velocity += _knockback
	_knockback = _knockback.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * delta)
	move_and_slide()
	# 素材默认朝右，横向移动时翻转（纵向移动保持上一朝向）
	if absf(velocity.x) > 5.0:
		visual.flip_h = velocity.x < 0.0


func take_damage(amount: float, from_position := Vector2.INF, p_heavy := false,
		p_knock_mult := 1.0, p_effective := false) -> void:
	if state == S_CORPSE:
		return
	var armor: float = clampf(inst.species.defense_reduction, 0.0, 0.8)
	var dealt: float = maxf(1.0, amount * (1.0 - armor))
	current_hp -= dealt
	if _hp_bar != null:
		_hp_bar.notify_change()
	EventBus.damage_number.emit(global_position, int(round(dealt)), false, p_effective)
	_pulse_red()
	# 被玩家攻击会中断迁徙反击：迁徙中挨打毫无反应（不还手不停步）像坏掉了
	if state == S_MIGRATING and from_position != Vector2.INF:
		state = S_CHASE
		_aggro_lock = 3.0
	if from_position != Vector2.INF:
		# 击退受双抗性叠乘：knockback_resist（物种）× poise（削韧/霸体）；
		# 重击（连击第三段）击退翻倍 + 玩家重锤被动乘子——霸体怪（岩甲龟/龟王）纹丝不动
		var resist: float = clampf(inst.species.knockback_resist
				+ inst.species.poise * (1.0 - inst.species.knockback_resist), 0.0, 1.0)
		var dir := (global_position - from_position).normalized()
		if dir == Vector2.ZERO:
			dir = Vector2.UP
		_knockback += dir * 150.0 * (1.0 - resist) * (2.0 if p_heavy else 1.0) * p_knock_mult
	_on_taken_damage(dealt, from_position)
	# 仇恨连锁：同物种邻近个体会来支援（哥布林/兵蚁实现支援半径）
	notify_allies_hit(inst.species.species_name, global_position)
	if current_hp <= 0.0:
		_die_by_player()


## 生态迁移：锚点换到新区域内部随机点，走过去（EcologySim.instance_migrated → game_world 调用）
func on_migrate(to_region_id: String) -> void:
	if state == S_CORPSE:
		return
	var region: SimRegion = WorldSim.sim.get_region(to_region_id)
	if region != null:
		var half := region.size * 0.45
		anchor = region.center + Vector2(randf_range(-half.x, half.x), randf_range(-half.y, half.y))
	else:
		anchor = WorldSim.sim.get_region_center(to_region_id)
	state = S_MIGRATING


## 受击求援定向派发：只遍历该物种注册的节点，无支援行为的物种零成本跳过
static func notify_allies_hit(species_name: String, hit_position: Vector2) -> void:
	var list: Array = _species_registry.get(species_name)
	if list == null:
		return
	for node: MonsterBase in list:
		if node == null or node.state == S_CORPSE:
			continue
		var radius := node.ally_assist_radius()
		if radius > 0.0 and node.global_position.distance_to(hit_position) <= radius:
			node._on_ally_hit()


## 同物种同伴受击时的支援半径；0 = 该物种没有仇恨连锁（基类默认）
func ally_assist_radius() -> float:
	return 0.0


## 被同伴的受击求援唤起：脱离巡逻/迁徙进入追击，并锁仇恨数秒
func _on_ally_hit() -> void:
	if state == S_PATROL or state == S_MIGRATING:
		state = S_CHASE
	_aggro_lock = 3.0


## 模拟层判定的死亡（老化/击杀都走这里），幂等
func on_sim_death() -> void:
	if state == S_CORPSE:
		return
	state = S_CORPSE
	velocity = Vector2.ZERO
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	rotation = PI / 2.0
	modulate = Color(0.45, 0.45, 0.45, 0.7)
	if _hp_bar != null:
		_hp_bar.notify_change()


# --- 子类可重写的机制钩子 ---

## 追击速度倍率（野猪狂暴时重写）
func _speed_mult() -> float:
	return 1.0


## 残血逃跑判定（<=0 的物种永不逃跑，如狂暴/守卫型）
func _wants_flee(player: Node2D) -> bool:
	var ratio: float = inst.species.flee_hp_ratio
	if ratio <= 0.0 or player == null or not player.visible:
		return false
	if current_hp > inst.max_hp() * ratio:
		return false
	return global_position.distance_to(player.global_position) < inst.species.detect_radius * 1.5


func _chase_tick(_delta: float, player: Node2D) -> void:
	if player == null or not player.visible:
		state = S_PATROL
		return
	var dist := global_position.distance_to(player.global_position)
	if dist > inst.species.detect_radius * 1.3 and _aggro_lock <= 0.0:
		state = S_PATROL
		return
	if dist <= inst.species.attack_range:
		state = S_ATTACK
		return
	velocity = (player.global_position - global_position).normalized() * inst.move_speed() * _speed_mult()


func _attack_tick(_delta: float, player: Node2D) -> void:
	if player == null or not player.visible:
		state = S_PATROL
		return
	var dist := global_position.distance_to(player.global_position)
	if dist > inst.species.attack_range * 1.2:
		state = S_CHASE
		return
	velocity = Vector2.ZERO
	if _attack_cd <= 0.0:
		_attack_cd = inst.species.attack_cooldown
		_perform_attack(player)


## 普攻执行（子类重写可加协同加成等）；source 名传给玩家做死亡信息
func _perform_attack(player: Node2D) -> void:
	if player.has_method("take_damage"):
		player.take_damage(CombatMath.physical_damage(inst.attack_power()), global_position, inst.display_name())


## 受击后钩子（狂暴触发等）；from_position 为 Vector2.INF 表示无来源
func _on_taken_damage(_amount: float, _from_position: Vector2) -> void:
	pass


## 自定义状态（>=10）的处理入口
func _extra_state_tick(_delta: float, _player: Node2D) -> void:
	pass


# --- 公共状态实现 ---

func _patrol(delta: float, player: Node2D) -> void:
	var detect: float = inst.species.detect_radius * (WorldSim.night_vision_mult() if WorldSim != null else 1.0)
	if _enrage_timer > 0.0:
		detect *= ENRAGE_DETECT_MULT
	if player != null and player.visible \
			and global_position.distance_to(player.global_position) < detect:
		state = S_CHASE
		return
	if _patrol_wait > 0.0:
		_patrol_wait -= delta
		velocity = Vector2.ZERO
		return
	if not _patrol_target_valid or global_position.distance_to(_patrol_target) < 6.0:
		_patrol_target = anchor + Vector2(randf_range(-PATROL_RADIUS, PATROL_RADIUS), randf_range(-PATROL_RADIUS, PATROL_RADIUS))
		_patrol_target_valid = true
		_patrol_wait = randf_range(0.8, 2.5)
		# 到达即站桩选新点，不朝新路点抽动一帧
		velocity = Vector2.ZERO
		return
	velocity = (_patrol_target - global_position).normalized() * PATROL_SPEED


func _flee_tick(player: Node2D) -> void:
	# 远离玩家直到脱离侦测圈，然后回到锚点巡逻
	if player == null or not player.visible \
			or global_position.distance_to(player.global_position) > inst.species.detect_radius * 1.6:
		state = S_PATROL
		return
	velocity = (global_position - player.global_position).normalized() * inst.move_speed() * _speed_mult()


func _migrate_tick() -> void:
	if global_position.distance_to(anchor) < MIGRATE_ARRIVE_DIST:
		state = S_PATROL
		_patrol_target_valid = false
		return
	velocity = (anchor - global_position).normalized() * inst.move_speed() * _speed_mult()


func _die_by_player() -> void:
	# 击杀奖励：经验/金币随年龄与区域威胁增长（策划：尸体拾取，M0 简化为自动）；
	# 精英个体金币 ×4（遭遇感 → 战利品回报）
	var xp := inst.xp_reward()
	var gold := int(randi_range(3, 8) * inst.threat_scale)
	if inst.species.is_boss:
		gold *= 8
	elif inst.is_elite:
		gold *= 4
	GameState.add_xp(xp)
	GameState.add_gold(gold)
	EventBus.monster_killed_by_player.emit(xp, gold, inst.display_name())
	# 装备掉落：Boss 必掉史诗，精英 40% 稀有，普通 8% 精良；评分更高自动替换，否则折金
	var drop_rarity := -1
	if inst.species.is_boss:
		drop_rarity = 3
	elif inst.is_elite and randf() < 0.4:
		drop_rarity = 2
	elif randf() < 0.08:
		drop_rarity = 1
	if drop_rarity >= 0:
		var item := GameState.roll_equipment(drop_rarity)
		if GameState.try_equip(item):
			EventBus.hint_requested.emit("✨ 装备 %s" % GameState.equip_description(item))
		else:
			EventBus.hint_requested.emit("获得 %s（不如当前，折算 30 金币）" % GameState.equip_description(item))
	# 打击感：击杀轻震，精英击杀重震 + 短顿帧（大怪倒下的"重量"）；Boss 战绩播报
	if inst.species.is_boss:
		EventBus.camera_shake_requested.emit(9.0)
		EventBus.hit_stop_requested.emit(0.12)
		EventBus.world_event.emit("🏆 顶点掠食者 %s 被讨伐！生态链将为之震荡…" % inst.species.species_name)
	elif inst.is_elite:
		EventBus.camera_shake_requested.emit(7.0)
		EventBus.hit_stop_requested.emit(0.09)
	else:
		EventBus.camera_shake_requested.emit(2.5)
	_spawn_death_burst()
	WorldSim.sim.report_killed(inst.id, global_position)  # 同步触发 on_sim_death()（史莱姆在此裂出子代)


## 击杀爆裂：碎片小方块四散旋转淡出（颜色跟怪物 tint，精英金色）
func _spawn_death_burst() -> void:
	var color := Color(1.0, 0.78, 0.30) if inst.is_elite else Color(0.85, 0.3, 0.3)
	var count := 10 if inst.is_elite else 6
	var rng := RandomNumberGenerator.new()
	rng.seed = inst.id
	for i in count:
		var shard := Polygon2D.new()
		var sc := clampf(inst.size_scale, 0.6, 1.4)
		shard.polygon = PackedVector2Array([
			Vector2(-3, -3) * sc, Vector2(3, -3) * sc,
			Vector2(3, 3) * sc, Vector2(-3, 3) * sc,
		])
		shard.color = color.darkened(rng.randf_range(0.0, 0.25))
		shard.z_index = 20
		get_parent().add_child(shard)
		shard.global_position = global_position
		var dir := Vector2.RIGHT.rotated(rng.randf() * TAU)
		var dist := rng.randf_range(24.0, 60.0) * clampf(inst.size_scale, 0.7, 1.4)
		var tween := shard.create_tween()
		tween.set_parallel(true)
		tween.tween_property(shard, "global_position",
			global_position + dir * dist, 0.45).set_ease(Tween.EASE_OUT)
		tween.tween_property(shard, "rotation", rng.randf_range(-6.0, 6.0), 0.45)
		tween.tween_property(shard, "modulate:a", 0.0, 0.45).set_delay(0.1)
		tween.chain().tween_callback(shard.queue_free)
