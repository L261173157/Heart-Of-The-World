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
## 迷雾纹理：常驻 Image + 增量更新（揭示只增不减；fog_version 变化时只把
## GameState.fog_dirty 的新揭示格写透明并 update 纹理。曾经每版本全量
## 40000 像素 set_pixel 重建，跑图期间 ~2 次/s 是移动尖峰——真机性能优化
## 2026-09-19。首次（读档后）按 explored 全量建一次）
const FOG_BLACK := Color(0.02, 0.03, 0.04, 1.0)
const FOG_CLEAR := Color(0, 0, 0, 0)
var _fog_image: Image = null
var _fog_texture: ImageTexture = null
var _fog_version_drawn := -1

var _accum := 0.0
## 营地聚合点缓存：gkey("region|species") → {pos, tint}。营地位置确定性派生
## （EcologySim.camp_pos，与巢穴/种群据点同址），换世界（sim 身份变化）时清空
var _camp_cache_sim: EcologySim = null
var _camp_cache: Dictionary = {}
## 聚合结果缓存（真机性能优化二轮）：880 实例分组统计从 4Hz 降到 1Hz——
## 战略地图层不需要更快，玩家/怪物实时点仍 4Hz
var _camp_groups_cache: Dictionary = {}
var _camp_groups_sim: EcologySim = null
var _camp_groups_ms := 0


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
	# 战争迷雾：未探索格盖黑（200×200 位图 → 一像素一格；按版本增量更新）
	_sync_fog_texture()
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
	# 未探索区域不显示保住开荒未知感；营地被清剿/物种灭绝时聚合数为 0 自然熄灭。
	# 分组统计 880 实例按 1s 缓存（重绘仍 4Hz，实时玩家/怪物点不缓存）
	if _camp_cache_sim != WorldSim.sim:
		_camp_cache_sim = WorldSim.sim
		_camp_cache.clear()
		_camp_groups_sim = null
	if _camp_groups_sim != WorldSim.sim:
		_camp_groups_sim = WorldSim.sim
		_camp_groups_cache = {}
	if Time.get_ticks_msec() - _camp_groups_ms >= 1000 or _camp_groups_cache.is_empty():
		_camp_groups_ms = Time.get_ticks_msec()
		var fresh: Dictionary = {}
		for inst: MonsterInstance in WorldSim.sim.instances.values():
			if not inst.is_alive:
				continue
			var gkey := "%s|%s" % [inst.region_id, inst.species.species_name]
			fresh[gkey] = int(fresh.get(gkey, 0)) + 1
		_camp_groups_cache = fresh
	for gkey: String in _camp_groups_cache:
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


## 迷雾纹理增量维护：首次按 explored 全量建图（读档/换世界后也走这里），
## 之后版本变化只把脏格写透明并整图 update 上传（160KB，远小于全量重建）
func _sync_fog_texture() -> void:
	if _fog_texture == null:
		_fog_image = Image.create(GameState.FOG_GRID, GameState.FOG_GRID,
				false, Image.FORMAT_RGBA8)
		for y in GameState.FOG_GRID:
			for x in GameState.FOG_GRID:
				_fog_image.set_pixel(x, y,
						FOG_BLACK if not GameState.fog_is_explored(x, y) else FOG_CLEAR)
		_fog_texture = ImageTexture.create_from_image(_fog_image)
		GameState.fog_dirty.clear()
		_fog_version_drawn = GameState.fog_version
		return
	if GameState.fog_version == _fog_version_drawn:
		return
	_fog_version_drawn = GameState.fog_version
	if GameState.fog_dirty.is_empty():
		return
	for cell: Vector2i in GameState.fog_dirty:
		_fog_image.set_pixel(cell.x, cell.y, FOG_CLEAR)
	GameState.fog_dirty.clear()
	_fog_texture.update(_fog_image)
