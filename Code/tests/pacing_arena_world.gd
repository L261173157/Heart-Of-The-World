## 节奏基准专用平地：只固定遭遇供给，战斗仍走正式玩家、怪物、碰撞与奖励。
## 调用方先设置玩家属性，再实例化本世界；本夹具不补血蓝、不清存活演员或弹幕。
extends Node2D

signal arena_ready

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const HUD_SCENE := preload("res://scenes/ui/hud.tscn")
const WORLD := preload("res://scripts/main/game_world.gd")
const REGION_ID := "pacing_arena"
const MAX_CARDS := 10
const ARENA_HALF_SIZE := 800.0
## 每张卡固定为出生平原的 3:3:1:1:1 阵容；资源和场景始终取正式真源。
const ROSTER: Array[String] = [
	"火把哥布林", "火把哥布林", "火把哥布林",
	"地精矿工", "地精矿工", "地精矿工", "突袭蛇", "青甲龟", "山猪",
]
## 九个互不重叠的固定落点，约 160px 半径；不按存活者/击杀数重新选位。
const SPAWN_OFFSETS: Array[Vector2] = [
	Vector2(0, -160), Vector2(103, -123), Vector2(158, -28),
	Vector2(139, 80), Vector2(55, 150), Vector2(-55, 150),
	Vector2(-139, 80), Vector2(-158, -28), Vector2(-103, -123),
]

var _sim: EcologySim
var _nodes: Dictionary = {}
## 下标即卡号，空数组表示尚未生成；一经生成永不清空，重复提交直接拒绝。
var card_ids: Array[Array] = []
var arena_is_ready := false
var _player: Player
var _monsters: Node2D
var _navigation: NavigationRegion2D
var _world_sim_was_processing := true


func _enter_tree() -> void:
	# 正式 Player 的 ready 会读取出生点/障碍，必须先装配相同世界种子。
	BiomeMap.configure(GameState.world_seed)
	ObstacleField.restore_destroyed(GameState.destroyed_cells)


func _ready() -> void:
	TouchInput.reset()
	for card in MAX_CARDS:
		card_ids.append([])
	var region := SimRegion.new()
	region.id = REGION_ID
	region.display_name = "节奏基准平原"
	region.center = WorldConfig.spawn_pos()
	region.size = Vector2.ONE * ARENA_HALF_SIZE * 2.0
	region.terrain = "plains"
	region.threat = 1.0
	region.capacity = MAX_CARDS * ROSTER.size()
	_sim = EcologySim.new()
	_sim.setup([region], SpeciesCatalog.build_all(), {})
	_sim.instance_died.connect(_on_instance_died)
	# 保留正式击杀的 WorldSim.sim 桥，但不让生态自动老化/捕食/繁殖这批演员。
	# 昼夜与独立自然生态参照由控制器按其真实游戏秒数推进。
	_world_sim_was_processing = WorldSim.is_processing()
	WorldSim.start(_sim)
	WorldSim.set_process(false)
	_build_navigation(region.center)
	_monsters = Node2D.new()
	_monsters.name = "Monsters"
	add_child(_monsters)
	_player = PLAYER_SCENE.instantiate() as Player
	_player.name = "Player"
	add_child(_player)
	var hud := HUD_SCENE.instantiate()
	hud.name = "HUD"
	add_child(hud)
	EventBus.player_entered_region.emit(region.id, region.display_name)
	# NavigationServer 可能先发布空图，再异步加入区域；真实路径可用才允许发卡。
	var navigation_map := get_world_2d().navigation_map
	while NavigationServer2D.map_get_iteration_id(navigation_map) == 0 \
			or NavigationServer2D.map_get_path(navigation_map, region.center,
				region.center + SPAWN_OFFSETS[0], true).size() < 2:
		await get_tree().physics_frame
		await get_tree().process_frame
	arena_is_ready = true
	arena_ready.emit()


func _build_navigation(center: Vector2) -> void:
	_navigation = NavigationRegion2D.new()
	_navigation.name = "NavigationRegion2D"
	_navigation.position = center
	var polygon := NavigationPolygon.new()
	polygon.vertices = PackedVector2Array([
		Vector2(-ARENA_HALF_SIZE, -ARENA_HALF_SIZE),
		Vector2(ARENA_HALF_SIZE, -ARENA_HALF_SIZE),
		Vector2(ARENA_HALF_SIZE, ARENA_HALF_SIZE),
		Vector2(-ARENA_HALF_SIZE, ARENA_HALF_SIZE),
	])
	polygon.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	_navigation.navigation_polygon = polygon
	add_child(_navigation)


func wait_until_ready() -> void:
	if not arena_is_ready:
		await arena_ready


func spawn_card(card_index: int) -> bool:
	if not arena_is_ready or card_index < 0 or card_index >= MAX_CARDS \
			or not card_ids[card_index].is_empty():
		return false
	# 先核整张卡的资源，配置缺失时不生成半张卡或用其它物种补位。
	var species_rows: Array[SpeciesData] = []
	for species_name: String in ROSTER:
		var species := _sim.find_species(species_name)
		if species == null or species.is_boss or not WORLD.MONSTER_SCENES.has(species_name):
			push_error("节奏遭遇卡缺少普通物种/正式场景：%s" % species_name)
			return false
		species_rows.append(species)
	for slot in ROSTER.size():
		var species: SpeciesData = species_rows[slot]
		var spawn_pos := WorldConfig.spawn_pos() + SPAWN_OFFSETS[slot]
		var inst := _sim.spawn_instance(species, REGION_ID,
			species.maturity_age + CombatBandMath.REF_AGE_OFFSET, 0, 1.0, false, spawn_pos)
		var body: MonsterBase = WORLD.MONSTER_SCENES[species.species_name].instantiate()
		_monsters.add_child(body)
		body.setup(inst)
		# 正式 setup 自带随机出生偏移；仅初次编排回固定槽，不移动既有演员。
		body.global_position = spawn_pos
		_nodes[inst.id] = body
		card_ids[card_index].append(inst.id)
	return true


func _on_instance_died(inst: MonsterInstance, _cause: String) -> void:
	var body: MonsterBase = _nodes.get(inst.id)
	if is_instance_valid(body):
		body.on_sim_death()


func get_player() -> Player:
	return _player


## 与控制器的安全传送流程兼容；固定场地不流式回收演员或弹幕。
func _stream_pass() -> void:
	pass


func _exit_tree() -> void:
	if WorldSim.sim == _sim:
		WorldSim.stop()
		WorldSim.set_process(_world_sim_was_processing)
	Projectile.clear_pool()
