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
	"c2:herbalist": {"terrain":"forest", "title":"林地药师白榆", "kind":"npc", "portrait":"herbalist", "offset":Vector2(-96,448), "interaction_label":"交谈"},
	"c2:old_pact": {"terrain":"forest", "title":"旧约抄本", "kind":"record", "offset":Vector2(-256,288), "interaction_label":"阅读旧约"},
	"c2:route_marks": {"terrain":"forest", "title":"巡线员的方位刻记", "kind":"record", "offset":Vector2(128,224), "interaction_label":"辨认刻记"},
	"c2:rune_north": {"terrain":"forest", "title":"北方信号石", "kind":"rune", "offset":Vector2(160,-448), "interaction_label":"触碰北印"},
	"c2:rune_east": {"terrain":"forest", "title":"东方信号石", "kind":"rune", "offset":Vector2(512,32), "interaction_label":"触碰东印"},
	"c2:rune_west": {"terrain":"forest", "title":"西方信号石", "kind":"rune", "offset":Vector2(-512,128), "interaction_label":"触碰西印"},
	"c2:forest_gate": {"terrain":"forest", "title":"旧约档案石门", "kind":"gate", "offset":Vector2(-352,-32), "interaction_label":"检查石门"},
	"c2:torn_record": {"terrain":"forest", "title":"门后的残页", "kind":"record", "offset":Vector2(-352,-320), "interaction_label":"收取残页"},
	"c2:liaison": {"terrain":"forest", "title":"联络员阿苇", "kind":"injured", "portrait":"watchman", "offset":Vector2(352,-224), "interaction_label":"查看伤势"},
	"c2:aid_cache": {"terrain":"forest", "title":"林间急救匣", "kind":"aid", "offset":Vector2(480,352), "interaction_label":"取出急救物资"},
	"c2:signal_parts": {"terrain":"forest", "title":"信标备件箱", "kind":"parts", "offset":Vector2(-512,448), "interaction_label":"领取信标备件"},
	"c2:beacon": {"terrain":"forest", "title":"失火的林间信标", "kind":"beacon", "offset":Vector2(0,-32), "interaction_label":"检查信标"},
	"c3:totem_record": {"terrain":"swamp", "title":"沉睡图腾的刻文", "kind":"record", "offset":Vector2(-256,416), "interaction_label":"调查记录"},
	"c3:shrine_record": {"terrain":"swamp", "title":"枯木灵龛的布条", "kind":"record", "offset":Vector2(256,416), "interaction_label":"调查记录"},
	"c3:satchel": {"terrain":"swamp", "title":"漂来的远征行囊", "kind":"cargo", "offset":Vector2(448,192), "interaction_label":"检查物资"},
	"c3:old_route": {"terrain":"swamp", "title":"受潮的旧路书", "kind":"record", "offset":Vector2(-384,224), "interaction_label":"调查记录"},
	"c3:route_near": {"terrain":"swamp", "title":"近路勘察桩", "kind":"survey", "offset":Vector2(0,128), "interaction_label":"勘察现场"},
	"c3:route_outer": {"terrain":"swamp", "title":"外环勘察桩", "kind":"survey", "offset":Vector2(-576,-128), "interaction_label":"勘察现场"},
	"c3:route_choice": {"terrain":"swamp", "title":"接应路线图", "kind":"record", "offset":Vector2(0,384), "interaction_label":"调查记录"},
	"c3:survivor": {"terrain":"swamp", "title":"渡工沈渡", "kind":"injured", "portrait":"watchman", "offset":Vector2(0,-416), "interaction_label":"查看伤势"},
	"c3:aid_cache": {"terrain":"swamp", "title":"接应急救匣", "kind":"aid", "offset":Vector2(448,-320), "interaction_label":"领取急救物资"},
	"c3:reply_record": {"terrain":"swamp", "title":"未完成的回信", "kind":"record", "offset":Vector2(-224,-384), "interaction_label":"调查记录"},
	"c3:beacon": {"terrain":"swamp", "title":"沼泽联络灯", "kind":"beacon", "offset":Vector2(224,-416), "interaction_label":"检查信标"},
	"c4:scholar": {"terrain":"hill", "title":"遗迹学者闻川", "kind":"npc", "portrait":"scholar", "offset":Vector2(-192,448), "interaction_label":"交谈"},
	"c4:roster": {"terrain":"hill", "title":"旧驻守名册", "kind":"record", "offset":Vector2(-416,224), "interaction_label":"调查记录"},
	"c4:winch_parts": {"terrain":"hill", "title":"绞盘零件", "kind":"parts", "offset":Vector2(480,320), "interaction_label":"领取零件"},
	"c4:winch": {"terrain":"hill", "title":"断开的绞盘", "kind":"valve", "offset":Vector2(-160,-416), "interaction_label":"操作机关"},
	"c4:archive_gate": {"terrain":"hill", "title":"档案附室入口", "kind":"gate", "anchor":"boss", "offset":Vector2(512,288), "interaction_label":"检查门锁"},
	"c4:fortress_record": {"terrain":"hill", "title":"城塞南门观测点", "kind":"survey", "anchor":"boss", "offset":Vector2(0,288), "interaction_label":"勘察现场"},
	"c4:bypass_control": {"terrain":"hill", "title":"西侧绕行绞盘", "kind":"valve", "anchor":"boss", "offset":Vector2(-416,-64), "interaction_label":"操作机关"},
	"c4:archive": {"terrain":"hill", "title":"封关档案", "kind":"record", "anchor":"boss", "offset":Vector2(512,-320), "interaction_label":"调查记录"},
	"c4:map_keeper": {"terrain":"hill", "title":"地图保管员罗墨", "kind":"injured", "portrait":"scholar", "offset":Vector2(384,-256), "interaction_label":"查看伤势"},
	"c4:snow_coordinates": {"terrain":"hill", "title":"第二次分队的坐标", "kind":"record", "offset":Vector2(-384,-352), "interaction_label":"调查记录"},
	"c4:beacon": {"terrain":"hill", "title":"丘陵接应信标", "kind":"beacon", "offset":Vector2(0,128), "interaction_label":"检查信标"},
	"c5:altar_record": {"terrain":"snow", "title":"冰封祭坛刻文", "kind":"record", "offset":Vector2(-384,128), "interaction_label":"调查记录"},
	"c5:ice_barrier": {"terrain":"snow", "title":"封住祭坛的冰障", "kind":"survey", "offset":Vector2(-352,-32), "interaction_label":"勘察现场"},
	"c5:tablet": {"terrain":"snow", "title":"祭坛内的石版", "kind":"record", "offset":Vector2(-352,-320), "interaction_label":"调查记录"},
	"c5:leader": {"terrain":"snow", "title":"远征队长韩铎", "kind":"injured", "portrait":"watchman", "offset":Vector2(352,-288), "interaction_label":"查看伤势"},
	"c5:aid_cache": {"terrain":"snow", "title":"雪地急救匣", "kind":"aid", "offset":Vector2(-512,448), "interaction_label":"领取急救物资"},
	"c5:withdrawal_log": {"terrain":"snow", "title":"撤守日志", "kind":"record", "offset":Vector2(-160,224), "interaction_label":"调查记录"},
	"c5:route_log": {"terrain":"snow", "title":"分队路书", "kind":"record", "offset":Vector2(480,320), "interaction_label":"调查记录"},
	"c5:evidence_board": {"terrain":"snow", "title":"失联经过核对板", "kind":"record", "offset":Vector2(0,-96), "interaction_label":"调查记录"},
	"c5:lava_coordinates": {"terrain":"snow", "title":"最后的坐标", "kind":"record", "offset":Vector2(160,-448), "interaction_label":"调查记录"},
	"c5:beacon": {"terrain":"snow", "title":"雪原联络灯", "kind":"beacon", "offset":Vector2(0,448), "interaction_label":"检查信标"},
	"c6:hazard_record": {"terrain":"lava", "title":"熔河边界警示", "kind":"record", "offset":Vector2(-192,448), "interaction_label":"调查记录"},
	"c6:route_approach": {"terrain":"lava", "title":"避灼通路标记", "kind":"survey", "offset":Vector2(256,-384), "interaction_label":"勘察现场"},
	"c6:fortress_record": {"terrain":"lava", "title":"龟王城塞观测点", "kind":"survey", "anchor":"boss", "offset":Vector2(0,288), "interaction_label":"勘察现场"},
	"c6:bypass_control": {"terrain":"lava", "title":"中枢安全锁", "kind":"valve", "anchor":"boss", "offset":Vector2(-416,-64), "interaction_label":"操作机关"},
	"c6:core_record": {"terrain":"lava", "title":"中枢留存记录", "kind":"record", "anchor":"boss", "offset":Vector2(512,-352), "interaction_label":"调查记录"},
	"c6:core_west": {"terrain":"lava", "title":"中枢西侧回路", "kind":"rune", "anchor":"boss", "offset":Vector2(352,-224), "interaction_label":"操作回路"},
	"c6:core_east": {"terrain":"lava", "title":"中枢东侧回路", "kind":"rune", "anchor":"boss", "offset":Vector2(672,-224), "interaction_label":"操作回路"},
	"c6:core_center": {"terrain":"lava", "title":"中枢中央回路", "kind":"rune", "anchor":"boss", "offset":Vector2(512,-64), "interaction_label":"操作回路"},
	"c6:heart": {"terrain":"lava", "title":"世界之心", "kind":"beacon", "anchor":"boss", "offset":Vector2(512,96), "interaction_label":"检查信标"},
	"c6:ending_council": {"terrain":"lava", "title":"归途的团聚名册", "kind":"record", "offset":Vector2(-352,224), "interaction_label":"调查记录"},
	"c6:beacon": {"terrain":"lava", "title":"熔岩接应信标", "kind":"beacon", "offset":Vector2(0,128), "interaction_label":"检查信标"},
}

static var _seed := -2147483648
static var _sites: Dictionary = {}
static var _geometry: Dictionary = {}
static var _gate_cells: Dictionary = {}
static var _sealed_rooms: Dictionary = {}
static var _open_gates: Array[String] = []
static var _barrier_cells: Dictionary = {}
static var _extra_reserved: Array[Rect2] = []
static var _extra_objects: Dictionary = {}
static var _lava_pocket := Rect2()
static var _reserved_rects_by_chunk: Dictionary = {}
static var _reserved_paths_by_chunk: Dictionary = {}
static var _troll_entry := Vector2.ZERO
static var _troll_entries: Array[Vector2] = []
static var _region_routes: Dictionary = {}
static var _bounds: Dictionary = {}
static var _paths: Dictionary = {}


static func _ensure() -> void:
	if _seed == BiomeMap.current_seed():
		return
	_seed = BiomeMap.current_seed()
	_sites = {}
	_geometry = {}
	_gate_cells = {}
	_sealed_rooms = {}
	_barrier_cells = {}
	_extra_reserved = []
	_extra_objects = {}
	_region_routes = {}
	_troll_entries.clear()
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
	_build_swamp_routes()
	_build_snow_ruin()
	for terrain: String in ["hill","lava"]:
		_build_fortress_annex(terrain)
	_lava_pocket = Rect2(site_center("lava")+Vector2(288,-176),Vector2(192,288))
	_build_optional_objects()
	_build_world_objects()
	_build_ending_shelter()
	_build_encounter_objects()
	_build_reservation_index()


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
	var walls: Array[Vector2i] = []
	# 完整档案围合，南面三格（96px）门洞。只解谜开门，不能打碎城墙绕过。
	for y in range(-14,-2):
		for x in range(-19,-2):
			if x != -19 and x != -3 and y != -14 and y != -3:
				continue
			var cell := _cell(center) + Vector2i(x,y)
			walls.append(cell)
			if y == -3 and x >= -12 and x <= -10:
				gate.append(cell)
			else:
				_geometry[cell] = "castle"
	_gate_cells["c2:forest_gate"] = gate
	_register_sealed_room("c2:forest_gate", walls)
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
	if _extra_objects.has(id):
		return _extra_objects[id]["position"]
	if not OBJECTS.has(id):
		return Vector2.INF
	var item: Dictionary = OBJECTS[id]
	var base := site_center(str(item["terrain"]))
	if item.get("anchor","") == "boss":
		base = _snap(_sites[item["terrain"]]["boss_anchor"])
	return base + (item["offset"] as Vector2)


static func objects() -> Array[Dictionary]:
	_ensure()
	var out: Array[Dictionary] = []
	for id: String in OBJECTS:
		var item: Dictionary = OBJECTS[id].duplicate(true)
		item["id"] = id
		item["role"] = id.get_slice(":",id.get_slice_count(":")-1)
		item["site"] = SITE_IDS[item["terrain"]]
		item["position"] = object_position(id)
		item["region_id"] = BiomeMap.region_id_at(item["position"])
		out.append(item)
	for item: Dictionary in _extra_objects.values():
		var copy := item.duplicate(true)
		copy["region_id"] = BiomeMap.region_id_at(copy["position"])
		out.append(copy)
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


## 围合范围由刚生成的真实墙格派生；只记录有不可破坏任务门且没有其它出口的房间。
static func _register_sealed_room(id: String, walls: Array[Vector2i]) -> void:
	var bounds := Rect2(Vector2(walls[0]) * CELL, Vector2.ONE * CELL)
	for cell: Vector2i in walls:
		bounds = bounds.expand(Vector2(cell) * CELL).expand((Vector2(cell) + Vector2.ONE) * CELL)
	var gate: Array = _gate_cells[id]
	var door := (Vector2(gate[gate.size() / 2]) + Vector2.ONE * 0.5) * CELL
	_sealed_rooms[id] = {"bounds": bounds, "exit": door + Vector2(0, CELL * 2.0)}


## 锁门时房内外是不同连通分量，不能让寻路器反复查询一个已知不可达目标。
static func separated_by_closed_gate(from: Vector2, to: Vector2) -> bool:
	_ensure()
	for id: String in _sealed_rooms:
		if id in _open_gates:
			continue
		# 导航按墙中心围线分区；外缘格角有小体型可走的空隙，不能误当室内。
		var bounds: Rect2 = (_sealed_rooms[id]["bounds"] as Rect2).grow(-CELL * 0.5)
		if bounds.has_point(from) != bounds.has_point(to):
			return true
	return false


## 新增围墙可能包住旧档原本可走的位置。仅锁门室内的恢复点移到同门外，
## 不解锁机关、不推进任务；普通位置和已开门房间逐位保持，资源由玩家原路径恢复。
static func recover_saved_position(pos: Vector2) -> Vector2:
	_ensure()
	for id: String in _sealed_rooms:
		if id not in _open_gates and (_sealed_rooms[id]["bounds"] as Rect2).has_point(pos):
			return _sealed_rooms[id]["exit"]
	return pos


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
	if _lava_pocket.has_point(pos):
		return false
	var chunk := Vector2i(floori(pos.x/512),floori(pos.y/512))
	for rect: Rect2 in _reserved_rects_by_chunk.get(chunk,[]):
		if rect.has_point(pos):
			return true
	for path: PackedVector2Array in _reserved_paths_by_chunk.get(chunk,[]):
		if Geometry2D.get_closest_point_to_segment(pos,path[0],path[1]).distance_squared_to(pos)<=64.0*64.0:
			return true
	return false


static func _build_reservation_index() -> void:
	_reserved_rects_by_chunk = {}
	_reserved_paths_by_chunk = {}
	var rects: Array = _bounds.values()
	rects.append_array(_extra_reserved)
	for rect: Rect2 in rects:
		for chunk: Vector2i in _rect_chunks(rect):
			if not _reserved_rects_by_chunk.has(chunk):
				_reserved_rects_by_chunk[chunk] = []
			_reserved_rects_by_chunk[chunk].append(rect)
	for terrain: String in _paths:
		for path: PackedVector2Array in _paths[terrain]:
			for i in range(path.size()-1):
				var segment := PackedVector2Array([path[i],path[i+1]])
				var rect := Rect2(path[i],Vector2.ZERO).expand(path[i+1]).grow(64)
				for chunk: Vector2i in _rect_chunks(rect):
					if not _reserved_paths_by_chunk.has(chunk):
						_reserved_paths_by_chunk[chunk] = []
					_reserved_paths_by_chunk[chunk].append(segment)


static func _rect_chunks(rect: Rect2) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(floori(rect.position.y/512),floori(rect.end.y/512)+1):
		for x in range(floori(rect.position.x/512),floori(rect.end.x/512)+1):
			out.append(Vector2i(x,y))
	return out


## 两条实路：近路经过可击碎石障，外环须走到隔墙西端；没有覆盖整区水规则。
static func _build_swamp_routes() -> void:
	var center := site_center("swamp")
	var barrier: Array[Vector2i] = []
	for x in range(-14,15):
		var cell := _cell(center) + Vector2i(x,0)
		_geometry[cell] = "rock" if absi(x) <= 1 else "castle"
		if absi(x) <= 1:
			barrier.append(cell)
	_barrier_cells["c3:near_barrier"] = barrier
	_paths.swamp = [PackedVector2Array([center+Vector2(0,640),center+Vector2(0,128)]),
		PackedVector2Array([center+Vector2(0,128),center+Vector2(0,-416)]),
		PackedVector2Array([center+Vector2(-384,224),center+Vector2(-576,224),center+Vector2(-576,-288),center+Vector2(0,-288)])]


static func _build_snow_ruin() -> void:
	var center := site_center("snow")
	var barrier: Array[Vector2i] = []
	for y in range(-14,-2):
		for x in range(-19,-2):
			if x != -19 and x != -3 and y != -14 and y != -3:
				continue
			var cell := _cell(center) + Vector2i(x,y)
			var icy := y == -3 and x >= -12 and x <= -10
			_geometry[cell] = "ice" if icy else "castle"
			if icy:
				barrier.append(cell)
	_barrier_cells["c5:ice_barrier"] = barrier
	_paths.snow.append(PackedVector2Array([center+Vector2(-352,128),center+Vector2(-352,-320)]))


## 新档案附室与原城塞并置；原城塞的全部墙、敞开的南门和 Boss 坐标均不改。
static func _build_fortress_annex(terrain: String) -> void:
	var anchor := _snap(_sites[terrain]["boss_anchor"])
	var gate: Array[Vector2i] = []
	var walls: Array[Vector2i] = []
	for y in range(-14,7):
		for x in range(8,25):
			if x != 8 and x != 24 and y != -14 and y != 6:
				continue
			var cell := _cell(anchor) + Vector2i(x,y)
			walls.append(cell)
			if y == 6 and x >= 15 and x <= 17:
				gate.append(cell)
			else:
				_geometry[cell] = "castle"
	var gate_id := "c4:archive_gate" if terrain == "hill" else "c6:core_gate"
	_gate_cells[gate_id] = gate
	_register_sealed_room(gate_id, walls)
	_extra_reserved.append(Rect2(anchor+Vector2(208,-496),Vector2(608,880)))
	# 安全绕行只压出128px的小路，左翼控制点真实在堡墙另一侧。
	_paths[terrain].append(PackedVector2Array([anchor+Vector2(0,480),anchor+Vector2(-416,480),anchor+Vector2(-416,-64)]))
	_paths[terrain].append(PackedVector2Array([anchor+Vector2(0,320),anchor+Vector2(512,320),anchor+Vector2(512,96)]))


static func barrier_cells(id: String) -> Array[Vector2i]:
	_ensure()
	var out: Array[Vector2i] = []
	for cell: Vector2i in _barrier_cells.get(id,[]):
		out.append(cell)
	return out


## 此局部熔河与地表绘制、站立灼伤共用一份几何，不给修复站点假免疫。
static func liquid_kind(pos: Vector2) -> String:
	_ensure()
	return "lava" if _lava_pocket.has_point(pos) else ""


static func hazard_footprint() -> Rect2:
	_ensure()
	return _lava_pocket


static func _register_object(id: String,terrain: String,title: String,kind: String,at: Vector2,extra: Dictionary = {}) -> void:
	var item := {"id":id,"terrain":terrain,"site":SITE_IDS[terrain],"title":title,"kind":kind,
		"position":at,"role":id.get_slice(":",id.get_slice_count(":")-1),"interaction_label":"交谈" if kind in ["npc","injured"] else "调查"}
	item.merge(extra,true)
	_extra_objects[id] = item


static func _reserve_wing(terrain: String,at: Vector2,half := Vector2(416,416)) -> void:
	_extra_reserved.append(Rect2(at-half,half*2))
	var center := site_center(terrain)
	if terrain == "plains":
		# 接旧前哨西侧通口，不把新通路切进已有围墙。
		_paths[terrain] = _paths.get(terrain,[])
		_paths[terrain].append(PackedVector2Array([center+Vector2(-720,-160),at+Vector2(0,256),at]))
	else:
		_paths[terrain].append(PackedVector2Array([center+Vector2(0,576),Vector2(at.x,center.y+576),at]))


static func _build_optional_objects() -> void:
	var sides := {
		"side_patrol":["plains","新巡守","watchman",0,["station_camp","station_forest"]],
		"side_herbalist":["forest","草药师","herbalist",0,["medicine","patient","station_reserve"]],
		"side_hunter":["plains","营地猎人","hunter",1,["warning_sign"]],
		"side_scholar":["hill","拓印学者","scholar",0,["shortcut_gate"]],
		"side_merchant":["swamp","赶路的行商","merchant",0,["crate","station_near","station_outer"]],
		"side_watchman":["hill","瞭望者","watchman",1,["watch_near","watch_high"]],
		"side_letter":["snow","守信人","keeper",0,["letter_case","recipient"]],
		"side_troll":["forest","旧营地知情者","hunter",1,["room_runes","room_gate","room_record","rune_leaf","rune_stone","rune_lamp"]],
	}
	var offsets := [Vector2(-192,224),Vector2(0,32),Vector2(192,-160),Vector2(192,224),
		Vector2(-192,-192),Vector2(0,-192),Vector2(192,32),Vector2(-192,32),Vector2(0,224),Vector2(-320,-64)]
	for chain: String in sides:
		var config: Array = sides[chain]
		var terrain: String = config[0]
		var at := site_center(terrain)+Vector2(-1152,-768 if int(config[3])==1 else 256)
		if terrain == "plains":
			at = site_center(terrain)+Vector2(-1408,-640 if int(config[3])==1 else 416)
		if chain == "side_troll":
			at = _snap(BiomeMap.farthest_patch("forest")["center"])+Vector2(-1152,1024)
			_extra_reserved.append(Rect2(at-Vector2(416,416),Vector2(832,832)))
			_troll_entry = at+Vector2(-640,512)
			# 分开的作者接近垫使一个后来迁入的营地不能同时占住全部落点。
			_troll_entries.assign([_troll_entry,at+Vector2(-1568,512),at+Vector2(-640,1440),at+Vector2(288,1440)])
			for pad: Vector2 in _troll_entries:
				_extra_reserved.append(Rect2(pad-Vector2(112,112),Vector2(224,224)))
				_paths.forest.append(PackedVector2Array([pad,Vector2(pad.x,at.y+512),at+Vector2(-640,512),at+Vector2(-192,224)]))
		else:
			_reserve_wing(terrain,at)
		var suffixes: Array = ["giver","record","target","resolution"]
		suffixes.append_array(config[4])
		for index in suffixes.size():
			var suffix: String = suffixes[index]
			var kind := "record"
			var title := str(config[1])+"的记录"
			if suffix == "giver":
				kind = "npc"
				title = str(config[1])
			elif suffix == "resolution":
				kind = "record"
				title = str(config[1])+"的抉择"
			elif suffix in ["target","crate","medicine","letter_case"]:
				kind = "cargo" if suffix != "medicine" else "aid"
				title = {"target":"待回收的故事物件","crate":"落下的封存货箱","medicine":"学徒封存药包","letter_case":"冻结的信筒"}[suffix]
			elif suffix == "patient":
				kind = "injured"
				title = "等待药包的伤者"
			elif suffix == "recipient":
				kind = "npc"
				title = "等信的旧队员"
			elif suffix.ends_with("gate"):
				kind = "gate"
				title = "遗迹机关门"
			elif suffix.begins_with("rune_"):
				kind = "rune"
				title = {"rune_leaf":"树叶符记","rune_stone":"石块符记","rune_lamp":"灯火符记"}[suffix]
			elif suffix.begins_with("station_") or suffix.begins_with("watch_") or suffix == "warning_sign":
				kind = "flag"
				title = {"station_camp":"营地驻守点","station_forest":"林地驻守点","station_reserve":"站点药物储备","station_near":"近路收货台","station_outer":"外缘收货台","watch_near":"近处新旗位","watch_high":"高处新旗位","warning_sign":"旧猎场警示牌"}.get(suffix,"候选驻站")
			_register_object(chain+":"+suffix,terrain,title,kind,at+offsets[index],{"portrait":config[2],"initial_hidden":false})
		if chain == "side_patrol":
			_extra_objects[chain+":station_camp"]["position"] = BiomeMap.spawn_pos()+Vector2(160,128)
			_extra_objects[chain+":station_forest"]["position"] = site_center("forest")+Vector2(-320,576)
			_extra_objects[chain+":station_forest"]["terrain"] = "forest"
			_extra_objects[chain+":station_forest"]["site"] = SITE_IDS.forest
		if chain == "side_troll":
			_extra_objects[chain+":target"]["position"] = at+Vector2(-256,-160)
		if chain in ["side_hunter","side_watchman","side_troll"]:
			_extra_objects[chain+":target"]["kind"] = "survey"
			_extra_objects[chain+":target"]["title"] = "现场核对点"
		if chain == "side_merchant":
			_extra_objects[chain+":station_near"]["position"] = site_center("swamp")+Vector2(192,-224)
			_extra_objects[chain+":station_outer"]["position"] = site_center("swamp")+Vector2(-576,32)
		if chain == "side_watchman":
			# 旧旗确实被岩脊遮住；两处新增旗位绕开旧遮挡，各自保留真实视线。
			_register_object("side_watchman:old_flag",terrain,"岩脊后的旧旗","flag",at+Vector2(192,-288))
			for y in [32,64,96]: _geometry[_cell(at+Vector2(-64,y))]="boulder"
		if chain in ["side_scholar","side_troll"]:
			var gate_id := chain+ (":shortcut_gate" if chain=="side_scholar" else ":room_gate")
			var target_id := chain+ (":shortcut_exit" if chain=="side_scholar" else ":room_record")
			if chain == "side_scholar":
				_register_object(target_id,terrain,"碑文后的近道","survey",at)
				_extra_objects[chain+":target"]["position"] = at+Vector2(-256,-160)
			var room_center := at+Vector2(192,-160)
			_build_small_room(room_center,gate_id,target_id)
	var specific_titles := {
		"side_patrol":["旧巡逻名册","遗留的身份徽记","巡守驻地名册"],
		"side_herbalist":["学徒用途记录","学徒遗漏的药方","药包用途牌"],
		"side_hunter":["昨日猎数账","猎场足迹核对点","猎人的新决定"],
		"side_scholar":["旧道铭文","遗失的拓印","铭文处置案"],
		"side_merchant":["湿透的运单","遗落的签收牌","补给去向板"],
		"side_watchman":["值守视线草图","旧旗视线核对点","新旗位置图"],
		"side_letter":["收信登记","收信人的姓名牌","收信后的回执"],
		"side_troll":["褪色的人类旗记","巨魔盘踞处旧遗迹","遗留房间铭文"],
	}
	for chain: String in specific_titles:
		for i in 3:
			_extra_objects[chain+":"+["record","target","resolution"][i]]["title"] = specific_titles[chain][i]
	_extra_objects["side_troll:room_runes"]["title"] = "旧房间符记"
	_extra_objects["side_troll:room_record"]["title"] = "旧房间居住记录"
	_register_object("side_troll:departure","forest","旧旗远征接引员","npc",site_center("forest")+Vector2(288,576),{"portrait":"hunter","initial_hidden":true})
	for terrain: String in TERRAINS:
		var chain := "region_"+terrain
		var at := site_center(terrain)+Vector2(1152,64)
		if terrain == "plains":
			at = site_center(terrain)+Vector2(-1408,1472)
		_reserve_wing(terrain,at,Vector2(480,480))
		var entries := {
			"survey_a":["来路现场观测桩","survey",Vector2(-256,256)],
			"survey_b":["彼端现场观测桩","survey",Vector2(256,-256)],
			"choice":["路线施工图","record",Vector2(0,256)],
			"work_near":["近线施工点","valve",Vector2(-256,-64)],
			"work_outer":["外环施工点","parts",Vector2(256,64)],
			"station":["新路线接应台","beacon",Vector2(0,-320)],
		}
		for suffix: String in entries:
			var row: Array = entries[suffix]
			_register_object(chain+":"+suffix,terrain,row[0],row[1],at+row[2])
		if terrain == "forest":
			_register_object("region_forest:guide",terrain,"林缘巡线员","npc",at+Vector2(-320,352),{"portrait":"hunter"})
		if terrain in ["swamp","hill"]:
			var barrier: Array[Vector2i] = []
			for y in range(-4,5):
				var cell := _cell(at)+Vector2i(-4,y)
				_geometry[cell] = "rock" if absi(y)<=1 else "castle"
				if absi(y)<=1:
					barrier.append(cell)
			_barrier_cells[chain+":near_barrier"] = barrier
		_region_routes[terrain] = {
			"near":PackedVector2Array([at+Vector2(0,256),at+Vector2(0,-320)]),
			"outer":PackedVector2Array([at+Vector2(0,256),at+Vector2(384,256),at+Vector2(384,-384),at+Vector2(0,-320)]),
		}
		if terrain in ["swamp", "hill"]:
			# West approach, then the destroyed three-cell aperture; stay north of the separate hill gate.
			var gap := (Vector2(_cell(at)+Vector2i(-4,0))+Vector2(0.5,0.5))*CELL
			_region_routes[terrain]["near"] = PackedVector2Array([gap+Vector2(-96,-32),gap+Vector2(96,-32)])
		if terrain == "hill":
			_region_routes[terrain]["outer"] = PackedVector2Array([at+Vector2(384,256),at+Vector2(16,128),at+Vector2(16,-96),at+Vector2(0,-320)])
			var gate: Array[Vector2i] = []
			for x in range(-3,4):
				var cell := _cell(at)+Vector2i(x,0)
				if absi(x)<=1:
					gate.append(cell)
				else:
					_geometry[cell] = "castle"
			_gate_cells[chain+":shortcut_gate"] = gate
			_register_object(chain+":shortcut_gate",terrain,"岩脊旧道机关门","gate",at+Vector2(0,96))
		if terrain == "snow":
			for offset: Vector2 in [Vector2(288,192),Vector2(448,64),Vector2(288,-96),Vector2(448,-256)]:
				_geometry[_cell(at+offset)] = "ice"
		if terrain == "lava":
			var center := site_center("lava")
			_extra_objects[chain+":survey_a"]["position"] = center+Vector2(224,-32)
			_extra_objects[chain+":survey_b"]["position"] = center+Vector2(544,-32)
			_region_routes[terrain] = {
				"near":PackedVector2Array([center+Vector2(224,-32),center+Vector2(224,-256),center+Vector2(544,-256),center+Vector2(544,-32)]),
				"outer":PackedVector2Array([center+Vector2(224,-32),center+Vector2(192,288),center+Vector2(640,288),center+Vector2(640,-32)]),
			}
		for route: PackedVector2Array in _region_routes[terrain].values():
			_paths[terrain].append(route)


static func _build_small_room(center: Vector2,gate_id: String,target_id: String) -> void:
	var gate: Array[Vector2i] = []
	var walls: Array[Vector2i] = []
	for y in range(-4,5):
		for x in range(-4,5):
			if absi(x)!=4 and absi(y)!=4:
				continue
			var cell := _cell(center)+Vector2i(x,y)
			# 学者机关是南北贯通的真正近道，旧旗故事的房间仍只有原南门。
			if gate_id=="side_scholar:shortcut_gate" and y==-4 and absi(x)<=1: continue
			walls.append(cell)
			if y==4 and absi(x)<=1:
				gate.append(cell)
			else:
				_geometry[cell] = "castle"
	_gate_cells[gate_id] = gate
	if gate_id=="side_troll:room_gate":
		_register_sealed_room(gate_id,walls)
	_extra_objects[gate_id]["position"] = center+Vector2(0,192)
	_extra_objects[target_id]["position"] = center+Vector2(0,-224) if gate_id=="side_scholar:shortcut_gate" else center


static func _build_world_objects() -> void:
	var definitions := {
		"world_migration":{"route_a":"forest","route_b":"swamp","observer":"forest","record_board":"plains"},
		"world_decline":{"last_site":"forest","evidence_post":"forest","warning_sign":"forest","observer":"plains"},
		"world_relief":{"need_a":"forest","need_b":"swamp","supply_a":"plains","supply_b":"plains","coordination_post":"plains"},
		"world_watchnet":{"planning_board":"plains","node_1":"forest","node_2":"swamp","node_3":"hill","record_board":"plains"},
	}
	var counts: Dictionary = {}
	for chain: String in definitions:
		for suffix: String in definitions[chain]:
			var terrain: String = definitions[chain][suffix]
			var index := int(counts.get(terrain,0))
			counts[terrain] = index+1
			var at := site_center(terrain)+Vector2(0,1024)+Vector2((index%4-2)*192,(index/4)*192)
			if terrain=="plains":
				at = site_center(terrain)+Vector2(-2176,256)+Vector2((index%3)*192,(index/3)*192)
			_extra_reserved.append(Rect2(at-Vector2(112,112),Vector2(224,224)))
			_paths[terrain] = _paths.get(terrain,[])
			_paths[terrain].append(PackedVector2Array([entry(terrain),Vector2(at.x,entry(terrain).y+192),at]))
			var kind := "npc" if suffix in ["observer","need_a","need_b"] else ("cargo" if suffix.begins_with("supply") else "record")
			_register_object(chain+":"+suffix,terrain,"守望协作 · "+{"route_a":"第一条迁徙线","route_b":"第二条迁徙线","observer":"现场观察员","record_board":"记录交接板","last_site":"最后踪迹","evidence_post":"实况记录桩","warning_sign":"族群警示牌","need_a":"林间接应员","need_b":"沼泽接应员","supply_a":"第一份专用物资","supply_b":"第二份专用物资","coordination_post":"接应协调台","planning_board":"守望网规划板","node_1":"林间灯火节点","node_2":"沼泽灯火节点","node_3":"丘陵灯火节点"}[suffix],kind,at,{"portrait":"scholar"})

	for suffix: String in ["a","b"]:
		var destination: Dictionary = _extra_objects["world_relief:need_"+suffix]
		var supply: Dictionary = _extra_objects["world_relief:supply_"+suffix]
		supply["position"] = destination.position+Vector2(128,0)
		supply["terrain"] = destination.terrain
		supply["site"] = destination.site
		_extra_reserved.append(Rect2(supply.position-Vector2(96,96),Vector2(192,192)))


## 三次实例使用确定性偏移的独立小场地；只有已登记的当前实例可见。
static func _build_encounter_objects() -> void:
	var templates := ["random_wounded","random_parcel","random_sign","random_rocks","random_medicine","random_message","random_nest","random_migration","random_camp","random_runes"]
	var display := ["野外伤者","散落包裹","断裂路标","岩缝近道","紧缺药包","留守讯息","巢区临道","迁徙目击","据点余患","废墟符记"]
	for i in templates.size():
		var terrain: String = TERRAINS[i%TERRAINS.size()]
		var at := site_center(terrain)+Vector2(1280,-1024 if i<TERRAINS.size() else 1024)
		if terrain == "plains":
			at = site_center(terrain)+Vector2(-2368,-768 if i<TERRAINS.size() else 1280)
		_reserve_wing(terrain,at,Vector2(384,320))
		for ordinal in 3:
			var instance_id := "%s:%d:%d" % [templates[i],_seed,ordinal]
			var instance_at := at+Vector2(0,(ordinal-1)*256)
			if templates[i]=="random_rocks":
				# Three disjoint sites, east of the original fortress; no shared obstacle cells or overlapping rune pads.
				instance_at=site_center(terrain)+Vector2(2304+ordinal*1024,-1664)
				_extra_reserved.append(Rect2(instance_at-Vector2(448,384),Vector2(896,768)))
				_paths[terrain].append(PackedVector2Array([site_center(terrain)+Vector2(0,576),Vector2(instance_at.x-320,site_center(terrain).y+576),instance_at+Vector2(-320,224)]))
				_paths[terrain].append(PackedVector2Array([instance_at+Vector2(-192,0),instance_at+Vector2(192,0)]))
				_paths[terrain].append(PackedVector2Array([instance_at+Vector2(-192,0),instance_at+Vector2(-192,-288),instance_at+Vector2(192,-288),instance_at+Vector2(192,0)]))
			_extra_reserved.append(Rect2(instance_at-Vector2(384,320),Vector2(768,640)))
			var suffixes := ["giver","target","return","parts","record"]
			if templates[i]=="random_runes":
				suffixes.append_array(["rune_a","rune_b","rune_c"])
			for n in suffixes.size():
				var suffix: String = suffixes[n]
				var kind := "npc" if suffix in ["giver","return"] else ("record" if suffix=="record" else "cargo")
				if suffix.begins_with("rune_"):
					kind = "rune"
				elif templates[i]=="random_wounded" and suffix=="target":
					kind = "injured"
				elif templates[i]=="random_sign" and suffix=="target":
					kind = "flag"
				var offset := Vector2((n%3-1)*192,(n/3-1)*192)
				if templates[i]=="random_rocks": offset={"giver":Vector2(-320,224),"target":Vector2(-192,0),"return":Vector2(192,0),"parts":Vector2(-320,-224),"record":Vector2(320,224)}[suffix]
				if suffix == "target":
					if templates[i] == "random_medicine": kind="npc"
					elif templates[i] in ["random_rocks","random_nest","random_migration","random_camp"]: kind="survey"
					elif templates[i] == "random_runes": kind="valve"
				_register_object(instance_id+":"+suffix,terrain,display[i]+" · "+{"giver":"发起人","target":"现场目标","return":"接收人","parts":"专用物资","record":"现场线索","rune_a":"灯符记","rune_b":"路符记","rune_c":"人符记"}[suffix],kind,instance_at+offset,{"portrait":"watchman","instance_id":instance_id,"initial_hidden":true})
			if templates[i]=="random_rocks":
				var barrier: Array[Vector2i] = []
				# A real 384px ridge separates the two reachable endpoints. Its central 96px gap contains this instance's three breakable rocks.
				for y in range(-6,7):
					var cell := _cell(instance_at)+Vector2i(0,y)
					_geometry[cell] = "rock" if absi(y)<=1 else "boulder"
					if absi(y)<=1: barrier.append(cell)
				_barrier_cells[instance_id+":barrier"] = barrier


static func object_definition(id: String) -> Dictionary:
	_ensure()
	var item: Dictionary = _extra_objects.get(id,OBJECTS.get(id,{})).duplicate(true)
	if item.is_empty():
		return {}
	item["id"] = id
	item["role"] = id.get_slice(":",id.get_slice_count(":")-1)
	item["position"] = object_position(id)
	item["site"] = SITE_IDS[item["terrain"]]
	item["region_id"] = BiomeMap.region_id_at(item["position"])
	return item


static func _build_ending_shelter() -> void:
	var at := site_center("plains")+Vector2(-576,1472)
	_reserve_wing("plains",at,Vector2(480,320))
	_register_object("ending:shelter","plains","新的守望避难所","shelter",at+Vector2(0,160),{"initial_hidden":true})
	# 小屋硬底座与建筑外观同源；前方交互垫、北侧居民通道仍可行。
	for x in range(-1,2):
		for y in range(0,2):
			_geometry[_cell(at+Vector2(0,96))+Vector2i(x,y)] = "castle"


## 只给新增剧情人物安排驻地，绝不改第一章留守巡逻员或既有检查点。
static func ending_positions(_legacy_choice: String = "reunion") -> Dictionary:
	_ensure()
	var cast := ["c2:liaison","c3:survivor","c4:map_keeper","c5:leader"]
	var out := {}
	var center := site_center("plains")+Vector2(-576,1472)
	for i in cast.size():
		out[cast[i]] = center+Vector2((i-1.5)*160,-120)
	return out


static func entry_for_object(id: String) -> Vector2:
	_ensure()
	if id.begins_with("side_troll:") and id!="side_troll:departure":
		return _troll_entry
	var item := object_definition(id)
	return entry(str(item["terrain"])) if not item.is_empty() else Vector2.INF


static func region_routes(terrain: String) -> Dictionary:
	_ensure()
	return _region_routes.get(terrain,{}).duplicate(true)


## Only the selected repaired regional passage needs a separate swept-body receipt.
## Centers come from the registered cells, including their half-cell offset at every seed.
static func regional_passage(terrain: String, choice: String) -> Dictionary:
	_ensure()
	var id := "region_"+terrain
	var cells: Array[Vector2i] = []
	var direction := Vector2.RIGHT
	var kind := "barrier"
	if terrain in ["swamp", "hill"] and choice == "near":
		id += ":near_barrier"
		cells = barrier_cells(id)
	elif terrain == "hill" and choice == "outer":
		id += ":shortcut_gate"
		cells = gate_cells(id)
		direction = Vector2.UP
		kind = "gate"
	else:
		return {}
	if cells.is_empty(): return {}
	var center := Vector2.ZERO
	for cell: Vector2i in cells: center += (Vector2(cell)+Vector2(0.5,0.5))*CELL
	center /= float(cells.size())
	return {"id":id,"kind":kind,"center":center,"direction":direction,"half_width":38.0}


## C3 现场路线的真实逐段落脚点。调查/传送不能替代走过这些点。
static func route_waypoints(choice: String) -> Array[Vector2]:
	_ensure()
	var center := site_center("swamp")
	var offsets: Array[Vector2] = [Vector2(0,384)]
	if choice == "near":
		offsets.append_array([Vector2(0,128),Vector2(0,0),Vector2(0,-192),Vector2(0,-416)])
	elif choice == "outer":
		offsets.append_array([Vector2(-576,224),Vector2(-576,-288),Vector2(0,-288),Vector2(0,-416)])
	else:
		return []
	var points: Array[Vector2] = []
	for offset: Vector2 in offsets:
		points.append(center+offset)
	return points


## 候选列表本身由种子确定。运行时仍须核验当前真实敌人，不能把历史落点当安全承诺。
static func entry_candidates(terrain: String) -> Array[Vector2]:
	_ensure()
	if terrain == "shelter":
		var at := site_center("plains")+Vector2(-576,1472)
		return [at+Vector2(0,-224),at+Vector2(-352,-224),at+Vector2(352,-224),at+Vector2(352,160)]
	if terrain == "side_troll":
		return _troll_entries.duplicate()
	if terrain == "plains":
		return [entry(terrain),OutpostLayout.checkpoint_position(),OutpostLayout.center()+Vector2(-352,416)]
	if not _sites.has(terrain):
		return []
	var center := site_center(terrain)
	return [entry(terrain),center+Vector2(-640,64),center+Vector2(640,64),center+Vector2(0,-544)]
