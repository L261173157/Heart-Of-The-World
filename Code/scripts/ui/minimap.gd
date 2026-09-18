## 小地图：世界总览纹理 + 玩家白点 + 怪物实时彩点。
## 世界 v5：底图不再预载离线 world_map.png——game_world 按当前世界种子在
## 加载期后台栅格化生成（EventBus.world_overview_ready 送达后替换占位），
## 每个存档一个全新世界，底图天然对应脚下世界。怪物彩点只显示已生成的
## 表现节点（流式生成后即玩家附近，天然局部雷达）。
## 让"犬牙交错的群系"与生态迁徙/扩张一眼可视（本作核心卖点的常驻展示位）。
class_name Minimap
extends Control

const REDRAW_INTERVAL := 0.25
## 运行时生成的总览底图（world_overview_ready 送达前为 null——画占位深色）
var _map_texture: ImageTexture = null
## 迷雾纹理与增量重建脏标记（fog_version 变化才重建 200×200 纹理）
var _fog_texture: ImageTexture = null
var _fog_version_drawn := -1

var _accum := 0.0
## 营地聚合点缓存：gkey("region|species") → {pos, tint}。营地位置确定性派生
## （EcologySim.camp_pos，与巢穴/种群据点同址），换世界（sim 身份变化）时清空
var _camp_cache_sim: EcologySim = null
var _camp_cache: Dictionary = {}


func _ready() -> void:
	# 底图下采样 10:1，最近邻会闪烁成噪点——小地图单独走线性过滤
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	EventBus.world_overview_ready.connect(_on_overview_ready)


func _on_overview_ready(texture: ImageTexture) -> void:
	_map_texture = texture
	queue_redraw()


func _process(delta: float) -> void:
	# 暂停期间世界冻结，画面内容不变——跳过周期性全量重绘（含怪物组遍历）
	if get_tree().paused:
		return
	_accum += delta
	if _accum >= REDRAW_INTERVAL:
		_accum = 0.0
		queue_redraw()


func _draw() -> void:
	if WorldSim.sim == null or WorldSim.sim.regions.is_empty():
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.35))

	var world := Rect2(Vector2.ZERO, WorldConfig.WORLD_SIZE)
	if world.size.x <= 0.0 or world.size.y <= 0.0:
		return
	var s := minf(size.x / world.size.x, size.y / world.size.y)
	var offset := (size - world.size * s) * 0.5
	if _map_texture != null:
		draw_texture_rect(_map_texture, Rect2(offset, world.size * s), false)
	# 战争迷雾：未探索格盖黑（200×200 位图 → 一像素一格；按版本增量重建）
	if GameState.fog_version != _fog_version_drawn:
		_fog_version_drawn = GameState.fog_version
		_fog_texture = _build_fog_texture()
	if _fog_texture != null:
		draw_texture_rect(_fog_texture, Rect2(offset, world.size * s), false)
	# 已发现地标图标（类型色点；未发现不显示——保住未知感）
	for id: String in GameState.discovered_landmarks:
		var lm: Dictionary = LandmarkRegistry.landmark(id)
		if lm.is_empty():
			continue
		draw_circle(offset + (lm["pos"] - world.position) * s, 2.4,
				LandmarkRegistry.kind_color(lm["kind"]))

	# 族群营地怪群点：把模拟层活体按「区域|物种」聚合到所属营地据点画色点
	# （据点制语义：怪属于地图营地，个体实时点只覆盖玩家 2400px——全图底图
	# 只画局部节点会让玩家误读为"全世界没怪"）。只画已探索迷雾格内的营地，
	# 未探索区域不显示保住开荒未知感；营地被清剿/物种灭绝时聚合数为 0 自然熄灭
	if _camp_cache_sim != WorldSim.sim:
		_camp_cache_sim = WorldSim.sim
		_camp_cache.clear()
	var camp_groups: Dictionary = {}
	for inst: MonsterInstance in WorldSim.sim.instances.values():
		if not inst.is_alive:
			continue
		var gkey := "%s|%s" % [inst.region_id, inst.species.species_name]
		camp_groups[gkey] = int(camp_groups.get(gkey, 0)) + 1
	for gkey: String in camp_groups:
		var camp: Dictionary = _camp_cache.get(gkey, {})
		if camp.is_empty():
			var camp_region: SimRegion = WorldSim.sim.regions.get(gkey.get_slice("|", 0))
			var camp_species: SpeciesData = WorldSim.sim.find_species(gkey.get_slice("|", 1))
			if camp_region == null or camp_species == null:
				continue
			camp = {"pos": WorldSim.sim.camp_pos(camp_region, camp_species),
				"tint": camp_species.tint}
			_camp_cache[gkey] = camp
		var camp_pos: Vector2 = camp["pos"]
		var cell: Vector2i = GameState.fog_cell_of(camp_pos)
		if not GameState.fog_is_explored(cell.x, cell.y):
			continue
		# 深色描边 + 物种色面：与白色玩家点（3.5px，常与出生营地重叠）可区分
		var camp_screen: Vector2 = offset + (camp_pos - world.position) * s
		draw_circle(camp_screen, 2.8, Color(0.05, 0.06, 0.08, 0.9))
		draw_circle(camp_screen, 2.0, camp["tint"] as Color)

	for body in get_tree().get_nodes_in_group("monsters"):
		var monster := body as MonsterBase
		if monster == null or monster.inst == null or monster.state == MonsterBase.S_CORPSE:
			continue
		draw_circle(offset + (monster.global_position - world.position) * s, 2.0,
				monster.inst.species.tint)

	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player != null and player.visible:
		draw_circle(offset + (player.global_position - world.position) * s, 3.5, Color.WHITE)

	# 金色细描边圈出面板轮廓：开局迷雾几乎全黑、底图未送达时，
	# 纯黑矩形贴在暗色地形上认不出"这是小地图"——描边是常驻的面板证据
	draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 0.85, 0.45, 0.4), false, 2.0)


## 迷雾纹理：200×200，未探索黑不透明 / 已探索全透明
func _build_fog_texture() -> ImageTexture:
	var img := Image.create(GameState.FOG_GRID, GameState.FOG_GRID, false, Image.FORMAT_RGBA8)
	var black := Color(0.02, 0.03, 0.04, 1.0)
	var clear := Color(0, 0, 0, 0)
	for y in GameState.FOG_GRID:
		for x in GameState.FOG_GRID:
			img.set_pixel(x, y, black if not GameState.fog_is_explored(x, y) else clear)
	return ImageTexture.create_from_image(img)
