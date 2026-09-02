## Main 场景根：世界装配 + 生态模拟桥接。
## 负责：从场景 Marker 读取六区域配置 → 启动 EcologySim（经 WorldSim 定时驱动）→
## 把模拟信号翻译成节点生成/死亡/迁徙/消散；区域铭牌、玩家跨区域检测、飘血数字。
## 表现层只消费模拟事件，不改写模拟数据。
extends Node2D

## 物种 → 表现场景（新增种族在此登记）；Boss 复用同形物种场景（体型×2.2 表达差异）
const MONSTER_SCENES := {
	"哥布林": preload("res://scenes/monsters/goblin.tscn"),
	"史莱姆": preload("res://scenes/monsters/slime.tscn"),
	"野猪": preload("res://scenes/monsters/boar.tscn"),
	"雪蝎": preload("res://scenes/monsters/spider.tscn"),
	"兵蚁": preload("res://scenes/monsters/ant.tscn"),
	"岩甲龟": preload("res://scenes/monsters/guardian.tscn"),
	"蚁后": preload("res://scenes/monsters/ant.tscn"),
	"龟王": preload("res://scenes/monsters/guardian.tscn"),
}

## M0 初始种群（六区域相连，物种按栖息地分布；数值后续放 .tres 数据文件）
const INITIAL_POPULATION := {
	"west": {"哥布林": 6},
	"center": {"哥布林": 3, "史莱姆": 4},
	"snow": {"野猪": 3, "雪蝎": 3},
	"swamp": {"史莱姆": 4, "雪蝎": 2},
	"east": {"兵蚁": 5, "野猪": 2, "蚁后": 1},
	"lava": {"兵蚁": 3, "岩甲龟": 2, "龟王": 1},
}

const REGION_CHECK_INTERVAL := 0.3
## 顿帧期间的全局时间尺度（真实时间不受影响，恢复定时器忽略 time_scale）
const HIT_STOP_SCALE := 0.05

@onready var monsters: Node2D = $Monsters
@onready var regions_node: Node2D = $Regions

## 模拟实例 id → 表现节点
var _nodes: Dictionary = {}
## 巢穴 key → NestNode
var _nest_nodes: Dictionary = {}
var _sim: EcologySim
var _region_accum := 0.0
var _current_region_id := ""
## 精英诞生播报节流（真实秒）
var _last_elite_broadcast := -9999.0
## 顿帧开关（测试可关：节奏测试的 4× 加速会被顿帧恢复重置回 1.0）
var hit_stop_enabled := true
## 当前顿帧的恢复定时器：用对象身份判定哪个定时器有权恢复，
## 避免拿毫秒时钟与浮点到期时刻比较（粒度/舍入会让守卫永不成立，time_scale 卡死在低压值）
var _hit_stop_timer: SceneTreeTimer
## 飘字样式（三色）：LabelSettings 复用，避免 AoE 瞬时大量分配
var _dmg_style_normal: LabelSettings
var _dmg_style_player: LabelSettings
var _dmg_style_effective: LabelSettings


func _ready() -> void:
	_sim = EcologySim.new()
	_sim.instance_spawned.connect(_on_instance_spawned)
	_sim.instance_died.connect(_on_instance_died)
	_sim.instance_migrated.connect(_on_instance_migrated)
	_sim.corpse_expired.connect(_on_corpse_expired)
	_sim.nest_changed.connect(_on_nest_changed)
	EventBus.damage_number.connect(_on_damage_number)
	EventBus.hit_stop_requested.connect(_on_hit_stop)
	# "本局击杀"按进入世界清零（ autoload 计数不跨局累计）
	GameState.session_kills = 0
	_dmg_style_normal = _make_dmg_style(20, Color(1, 0.95, 0.7))
	_dmg_style_player = _make_dmg_style(26, Color(1, 0.35, 0.3))
	_dmg_style_effective = _make_dmg_style(26, Color(1, 0.6, 0.15))
	# 先 start（挂到 WorldSim）再 setup：初始种群的节点生成会读 WorldSim.sim
	WorldSim.start(_sim)
	_sim.setup(_build_regions(), SpeciesCatalog.build_all(), INITIAL_POPULATION)
	_spawn_region_labels()
	# 新手引导/生态事件播报（纯观察者，挂载点在 sim 就绪之后）
	add_child(Tutorial.new())
	# 赏金任务（短期目标循环，纯订阅击杀信号）
	add_child(BountyManager.new())
	# 世界事件监视（灭绝/入侵潮/饱和 → world_event 播报）
	add_child(WorldEventWatcher.new())
	# 成就判定（纯订阅 + GameState 持久化）
	add_child(AchievementManager.new())
	# 环境表现层（地物装饰/区域氛围/环境粒子，纯视觉）
	add_child(WorldDeco.new())


func _process(delta: float) -> void:
	_region_accum += delta
	if _region_accum < REGION_CHECK_INTERVAL:
		return
	_region_accum = 0.0
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null or not player.visible:
		return
	var region := _sim.region_of_point(player.global_position)
	if region != null and region.id != _current_region_id:
		_current_region_id = region.id
		EventBus.player_entered_region.emit(region.id, region.display_name)
		if region.threat >= 2.2:
			EventBus.region_threat_warning.emit(region.threat)


## 从场景里的 Marker2D（name/position/meta）读区域配置：
## terrain 地形 / threat 威胁系数 / capacity 承载 / neighbors 邻接
func _build_regions() -> Array:
	var result: Array = []
	for marker in regions_node.get_children():
		var region := SimRegion.new()
		region.id = str(marker.name)
		region.display_name = str(marker.get_meta("display_name", marker.name))
		region.terrain = str(marker.get_meta("terrain", "plains"))
		region.threat = float(marker.get_meta("threat", 1.0))
		region.center = marker.global_position
		region.size = marker.get_meta("cell_size", Vector2(1100, 700))
		region.capacity = int(marker.get_meta("capacity", 8))
		for neighbor in marker.get_meta("neighbors", []):
			region.neighbor_ids.append(str(neighbor))
		result.append(region)
	return result


## 区域铭牌：地图中央大字 + 危险度星级，玩家一眼识别所在地图与深度
func _spawn_region_labels() -> void:
	for region: SimRegion in _sim.regions.values():
		var label := Label.new()
		var stars := "★".repeat(clampi(int(round(region.threat)), 1, 3))
		label.text = "%s %s" % [region.display_name, stars]
		var style := LabelSettings.new()
		style.font_size = 46
		style.font_color = Color(1, 1, 1, 0.22)
		label.label_settings = style
		label.z_index = -1
		label.position = region.center + Vector2(-250, -320)
		label.size = Vector2(500, 60)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(label)


func _on_instance_spawned(inst: MonsterInstance) -> void:
	# 击杀（Area2D 回调内）触发的分裂生成会处于物理刷新期，
	# 此时 add_child 物理体会报错，统一延迟到帧末创建
	_spawn_monster_node.call_deferred(inst)


func _spawn_monster_node(inst: MonsterInstance) -> void:
	var scene: PackedScene = MONSTER_SCENES.get(inst.species.species_name)
	if scene == null:
		push_warning("种族 %s 没有配置表现场景" % inst.species.species_name)
		return
	var node := scene.instantiate()
	monsters.add_child(node)
	node.setup(inst)
	_nodes[inst.id] = node
	# 精英诞生播报（60s 节流，避免繁衍高峰刷屏）；Boss 降临/重生无节流全服播报
	if inst.species.is_boss:
		var boss_region: SimRegion = _sim.get_region(inst.region_id)
		var boss_region_name: String = boss_region.display_name if boss_region != null else inst.region_id
		EventBus.world_event.emit("⚔ %s 盘踞%s——它是这片生态的顶点" % [
			inst.species.species_name, boss_region_name])
	elif inst.is_elite:
		var now: float = Time.get_ticks_msec() / 1000.0
		if now - _last_elite_broadcast >= 60.0:
			_last_elite_broadcast = now
			var region_name: String = _sim.get_region(inst.region_id).display_name \
					if _sim.get_region(inst.region_id) != null else inst.region_id
			EventBus.world_event.emit("金色闪光！精英 %s 降临%s" % [inst.species.species_name, region_name])
	# 延迟创建期间可能已被模拟层判死（极端时序），补一次死亡表现
	if not inst.is_alive:
		node.on_sim_death()


func _on_instance_died(inst: MonsterInstance, _cause: String) -> void:
	var node: Node = _nodes.get(inst.id)
	if node != null:
		node.on_sim_death()


func _on_instance_migrated(inst: MonsterInstance, to_region_id: String) -> void:
	var node: Node = _nodes.get(inst.id)
	if node != null:
		node.on_migrate(to_region_id)


func _on_corpse_expired(inst: MonsterInstance) -> void:
	var node: Node = _nodes.get(inst.id)
	if node != null:
		node.queue_free()
	_nodes.erase(inst.id)


## 巢穴表现：建立/重建 → 在区域随机点生成可攻击巢体；捣毁 → 移除并广播激怒
func _on_nest_changed(region_id: String, species_name: String, active: bool) -> void:
	var key := "%s|%s" % [region_id, species_name]
	if not active:
		var old: Node = _nest_nodes.get(key)
		if old != null:
			old.queue_free()
		_nest_nodes.erase(key)
		EventBus.nest_ransacked.emit(species_name)
		return
	if _nest_nodes.has(key):
		return
	var species := _sim.find_species(species_name)
	var region: SimRegion = _sim.get_region(region_id)
	if species == null or region == null:
		return
	var nest := NestNode.new()
	add_child(nest)
	var half := region.size / 2.0
	nest.setup(region_id, species_name, species.tint,
			region.center + Vector2(randf_range(-half.x * 0.6, half.x * 0.6),
					randf_range(-half.y * 0.6, half.y * 0.6)))
	_nest_nodes[key] = nest


## 顿帧执行器：压低全局时间尺度，用忽略 time_scale 的定时器恢复。
## 重叠请求取更长者；被取代的旧定时器回调直接让位
func _on_hit_stop(duration: float) -> void:
	if not hit_stop_enabled:
		return
	if _hit_stop_timer != null and _hit_stop_timer.time_left >= duration:
		return  # 已有等长/更长的顿帧在计时
	Engine.time_scale = HIT_STOP_SCALE
	_hit_stop_timer = get_tree().create_timer(duration, true, false, true)
	_hit_stop_timer.timeout.connect(_restore_time_scale.bind(_hit_stop_timer))


func _restore_time_scale(which: SceneTreeTimer) -> void:
	if which != _hit_stop_timer:
		return  # 已被更长的顿帧取代，让位
	Engine.time_scale = 1.0


## 场景退出兜底：顿帧定时器若还在挂起状态，time_scale 不能残留压低值；
## 同时停掉模拟驱动（回主菜单后旧世界不再后台空转 tick）
func _exit_tree() -> void:
	Engine.time_scale = 1.0
	_hit_stop_timer = null
	WorldSim.stop()


## 飘血数字：受击点冒数字上飘淡出（玩家受伤红色更大、怪物受伤米黄、元素克制橙色加大）；设置可关
func _on_damage_number(pos: Vector2, amount: int, is_player_hurt: bool, is_effective := false) -> void:
	if not bool(GameState.settings.get("damage_numbers", true)):
		return
	_spawn_damage_number.call_deferred(pos, amount, is_player_hurt, is_effective)


func _spawn_damage_number(pos: Vector2, amount: int, is_player_hurt: bool, is_effective := false) -> void:
	var label := Label.new()
	label.text = str(amount)
	if is_player_hurt:
		label.label_settings = _dmg_style_player
	elif is_effective:
		label.label_settings = _dmg_style_effective
	else:
		label.label_settings = _dmg_style_normal
	label.z_index = 50
	add_child(label)
	label.global_position = pos + Vector2(randf_range(-14.0, 14.0), randf_range(-30.0, -14.0))
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 42.0, 0.7)
	tween.tween_property(label, "modulate:a", 0.0, 0.7).set_delay(0.2)
	tween.chain().tween_callback(label.queue_free)


func _make_dmg_style(font_size: int, color: Color) -> LabelSettings:
	var style := LabelSettings.new()
	style.font_size = font_size
	style.font_color = color
	style.outline_size = 4
	style.outline_color = Color(0, 0, 0, 0.6)
	return style
