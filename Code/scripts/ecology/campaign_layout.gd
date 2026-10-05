## 《断开的守望》作者场景的纯逻辑坐标目录。
## 不依赖 ObstacleField、Node、任务账本或活体。墙、液体净空、导航共用同一几何。
class_name CampaignLayout
extends RefCounted

const CELL := 32.0
const INTERACT_DISTANCE := 94.0
const TERRAINS := ["plains", "forest", "swamp", "hill", "snow", "lava"]
const SITE_IDS := {"plains":"watch_c1_outpost", "forest":"watch_c2_forest", "swamp":"watch_c3_swamp", "hill":"watch_c4_hill", "snow":"watch_c5_snow", "lava":"watch_c6_lava"}
const SITE_TITLES := {"plains":"失联的前哨", "forest":"林间旧约站", "swamp":"沉没的账册", "hill":"城塞外接应营", "snow":"风雪中继站", "lava":"最后的守望"}
const SITE_HALF := Vector2(704, 704)
const OBJECTS := {
	"c2:herbalist": {"terrain":"forest", "title":"草药师", "kind":"npc", "portrait":"herbalist", "offset":Vector2(-96,448), "interaction_label":"交谈"},
	"c2:old_pact": {"terrain":"forest", "title":"旧约抄本", "kind":"record", "offset":Vector2(-256,288), "interaction_label":"阅读旧约"},
	"c2:route_marks": {"terrain":"forest", "title":"巡线员的方位刻记", "kind":"record", "offset":Vector2(128,224), "interaction_label":"辨认刻记"},
	"c2:rune_north": {"terrain":"forest", "title":"北方信号石", "kind":"rune", "offset":Vector2(160,-448), "interaction_label":"触碰北印"},
	"c2:rune_east": {"terrain":"forest", "title":"东方信号石", "kind":"rune", "offset":Vector2(512,32), "interaction_label":"触碰东印"},
	"c2:rune_west": {"terrain":"forest", "title":"西方信号石", "kind":"rune", "offset":Vector2(-512,128), "interaction_label":"触碰西印"},
	"c2:forest_gate": {"terrain":"forest", "title":"旧约档案石门", "kind":"gate", "offset":Vector2(-352,-32), "interaction_label":"检查石门"},
	"c2:torn_record": {"terrain":"forest", "title":"门后的残页", "kind":"record", "offset":Vector2(-352,-320), "interaction_label":"收取残页"},
	"c2:liaison": {"terrain":"forest", "title":"受伤的远征队联络员", "kind":"injured", "portrait":"watchman", "offset":Vector2(352,-224), "interaction_label":"查看伤势"},
	"c2:aid_cache": {"terrain":"forest", "title":"林间急救匣", "kind":"aid", "offset":Vector2(480,352), "interaction_label":"取出急救物资"},
	"c2:signal_parts": {"terrain":"forest", "title":"信标备件箱", "kind":"parts", "offset":Vector2(-512,448), "interaction_label":"领取信标备件"},
	"c2:beacon": {"terrain":"forest", "title":"失火的林间信标", "kind":"beacon", "offset":Vector2(0,-32), "interaction_label":"检查信标"},
}

static var _seed := -2147483648
static var _sites: Dictionary = {}
static var _geometry: Dictionary = {}
static var _gate_cells: Dictionary = {}
static var _open_gates: Array[String] = []
static var _bounds: Dictionary = {}
static var _paths: Dictionary = {}


static func _ensure() -> void:
	if _seed == BiomeMap.current_seed():
		return
	_seed = BiomeMap.current_seed()
	_sites = {}
	_geometry = {}
	_gate_cells = {}
	_open_gates.clear()
	_bounds = {}
	_paths = {}
	_sites["plains"] = {"id":SITE_IDS.plains, "terrain":"plains", "title":SITE_TITLES.plains,
		"center":OutpostLayout.center(), "entry":OutpostLayout.center() + Vector2(-720,-160),
		"region_id":BiomeMap.region_id_at(OutpostLayout.center())}
	for terrain: String in TERRAINS:
		if terrain == "plains":
			continue
		var patch := _choose_patch(terrain)
		if patch.is_empty():
			continue
		var anchor: Vector2 = patch["center"]
		# 站点在区域中央的局部作者场地，不挪动巢穴或 Boss。
		var center := _snap(anchor + Vector2(0,1664))
		var site := {"id":SITE_IDS[terrain], "terrain":terrain, "title":SITE_TITLES[terrain],
			"center":center, "entry":center + Vector2(0,640), "region_id":str(patch["id"])}
		if terrain in ["hill","lava"]:
			site["boss_anchor"] = anchor
		_sites[terrain] = site
		_bounds[terrain] = Rect2(center - SITE_HALF, SITE_HALF * 2.0)
		_paths[terrain] = [PackedVector2Array([center + Vector2(0,640),center + Vector2(0,448),center + Vector2(0,128),center + Vector2(0,-544)])]
		if terrain in ["hill","lava"]:
			# 接应营到原城塞的正南门；止于墙外，不覆盖任何原城塞格。
			_paths[terrain].append(PackedVector2Array([center + Vector2(0,-544),_snap(anchor) + Vector2(0,192)]))
		_add_dressing_geometry(terrain,center)
	_build_forest_gate()


static func _choose_patch(terrain: String) -> Dictionary:
	if terrain in ["hill","lava"]:
		return BiomeMap.farthest_patch(terrain)
	var best: Dictionary = {}
	var distance := INF
	for patch: Dictionary in BiomeMap.patches_of_terrain(terrain):
		var center: Vector2 = patch["center"]
		var value := center.distance_squared_to(BiomeMap.spawn_pos())
		if value < distance:
			distance = value
			best = patch
	return best


static func _snap(pos: Vector2) -> Vector2:
	return (Vector2(Vector2i(floori(pos.x/CELL),floori(pos.y/CELL))) + Vector2.ONE * 0.5) * CELL


static func _cell(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x/CELL),floori(pos.y/CELL))


static func _add_dressing_geometry(terrain: String, center: Vector2) -> void:
	# 稀疏边缘实物，每一个都有同源的可见障碍和物理体；中央路永不摆假建筑。
	var kind := "pine" if terrain == "snow" else ("deadtree" if terrain == "swamp" else "rock")
	if terrain == "forest":
		kind = "tree"
	for offset: Vector2 in [Vector2(-640,-544),Vector2(640,-544),Vector2(-640,544),Vector2(640,544)]:
		_geometry[_cell(center + offset)] = kind


static func _build_forest_gate() -> void:
	if not _sites.has("forest"):
		return
	var center: Vector2 = _sites.forest.center
	var gate: Array[Vector2i] = []
	# 完整档案围合，南面三格（96px）门洞。只解谜开门，不能打碎城墙绕过。
	for y in range(-14,-2):
		for x in range(-19,-2):
			if x != -19 and x != -3 and y != -14 and y != -3:
				continue
			var cell := _cell(center) + Vector2i(x,y)
			if y == -3 and x >= -12 and x <= -10:
				gate.append(cell)
			else:
				_geometry[cell] = "castle"
	_gate_cells["c2:forest_gate"] = gate
	_paths.forest.append(PackedVector2Array([center + Vector2(-352,128),center + Vector2(-352,-320)]))


static func sites() -> Dictionary:
	_ensure()
	return _sites.duplicate(true)


static func entry(terrain: String) -> Vector2:
	_ensure()
	return _sites.get(terrain,{}).get("entry",Vector2.INF)


static func site_center(terrain: String) -> Vector2:
	_ensure()
	return _sites.get(terrain,{}).get("center",Vector2.INF)


static func object_position(id: String) -> Vector2:
	_ensure()
	if not OBJECTS.has(id):
		return Vector2.INF
	var item: Dictionary = OBJECTS[id]
	return site_center(str(item["terrain"])) + (item["offset"] as Vector2)


static func objects() -> Array[Dictionary]:
	_ensure()
	var out: Array[Dictionary] = []
	for id: String in OBJECTS:
		var item: Dictionary = OBJECTS[id].duplicate(true)
		item["id"] = id
		item["site"] = SITE_IDS[item["terrain"]]
		item["position"] = object_position(id)
		out.append(item)
	return out


static func footprint(terrain: String) -> Rect2:
	_ensure()
	return _bounds.get(terrain,Rect2())


static func paths(terrain: String) -> Array:
	_ensure()
	return _paths.get(terrain,[]).duplicate(true)


static func gate_cells(id: String) -> Array[Vector2i]:
	_ensure()
	var out: Array[Vector2i] = []
	for cell: Vector2i in _gate_cells.get(id,[]):
		out.append(cell)
	return out


## 账本向纯几何注入已经解开的机关。返回实际变化格，供碰撞/导航增量刷新。
static func set_open_gates(ids: Array) -> Array[Vector2i]:
	_ensure()
	var changed: Array[Vector2i] = []
	for id: String in _gate_cells:
		if (id in ids) != (id in _open_gates):
			changed.append_array(gate_cells(id))
	_open_gates.clear()
	for id: Variant in ids:
		if id is String and _gate_cells.has(id):
			_open_gates.append(id)
	return changed


static func obstacle_kind(cell: Vector2i) -> String:
	_ensure()
	if _geometry.has(cell):
		return str(_geometry[cell])
	for id: String in _gate_cells:
		if id not in _open_gates and cell in _gate_cells[id]:
			return "castle"
	return ""


static func obstacle_cells() -> Dictionary:
	_ensure()
	var out := _geometry.duplicate()
	for id: String in _gate_cells:
		if id not in _open_gates:
			for cell: Vector2i in _gate_cells[id]:
				out[cell] = "castle"
	return out


static func reserved_ground(pos: Vector2) -> bool:
	_ensure()
	for terrain: String in _bounds:
		if (_bounds[terrain] as Rect2).has_point(pos):
			return true
		if terrain not in ["hill","lava"]:
			continue
		for path: PackedVector2Array in _paths[terrain]:
			if not Rect2(path[0],Vector2.ZERO).expand(path[-1]).grow(64).has_point(pos):
				continue
			for i in range(path.size()-1):
				if Geometry2D.get_closest_point_to_segment(pos,path[i],path[i+1]).distance_squared_to(pos) <= 64.0 * 64.0:
					return true
	return false


## 候选列表由种子确定；实际出发还必须核验当前真实敌人，历史坐标不保证安全。
static func entry_candidates(terrain: String) -> Array[Vector2]:
	_ensure()
	if terrain == "plains":
		return [entry(terrain),OutpostLayout.checkpoint_position(),OutpostLayout.center()+Vector2(-352,416)]
	if not _sites.has(terrain):
		return []
	var center := site_center(terrain)
	return [entry(terrain),center+Vector2(-640,64),center+Vector2(640,64),center+Vector2(0,-544)]
