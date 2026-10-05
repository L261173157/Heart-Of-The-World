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
	"c3:totem_record": {"terrain":"swamp", "title":"沉睡图腾的刻文", "kind":"record", "offset":Vector2(-256,416), "interaction_label":"调查记录"},
	"c3:shrine_record": {"terrain":"swamp", "title":"枯木灵龛的布条", "kind":"record", "offset":Vector2(256,416), "interaction_label":"调查记录"},
	"c3:satchel": {"terrain":"swamp", "title":"漂来的远征行囊", "kind":"cargo", "offset":Vector2(448,192), "interaction_label":"检查物资"},
	"c3:old_route": {"terrain":"swamp", "title":"受潮的旧路书", "kind":"record", "offset":Vector2(-384,224), "interaction_label":"调查记录"},
	"c3:route_near": {"terrain":"swamp", "title":"近路勘察桩", "kind":"survey", "offset":Vector2(0,128), "interaction_label":"勘察现场"},
	"c3:route_outer": {"terrain":"swamp", "title":"外环勘察桩", "kind":"survey", "offset":Vector2(-576,-128), "interaction_label":"勘察现场"},
	"c3:route_choice": {"terrain":"swamp", "title":"接应路线图", "kind":"record", "offset":Vector2(0,384), "interaction_label":"调查记录"},
	"c3:survivor": {"terrain":"swamp", "title":"沼泽幸存者", "kind":"injured", "portrait":"watchman", "offset":Vector2(0,-416), "interaction_label":"查看伤势"},
	"c3:aid_cache": {"terrain":"swamp", "title":"接应急救匣", "kind":"aid", "offset":Vector2(448,-320), "interaction_label":"领取急救物资"},
	"c3:reply_record": {"terrain":"swamp", "title":"未完成的回信", "kind":"record", "offset":Vector2(-224,-384), "interaction_label":"调查记录"},
	"c3:beacon": {"terrain":"swamp", "title":"沼泽联络灯", "kind":"beacon", "offset":Vector2(224,-416), "interaction_label":"检查信标"},
	"c4:scholar": {"terrain":"hill", "title":"遗迹学者", "kind":"npc", "portrait":"scholar", "offset":Vector2(-192,448), "interaction_label":"交谈"},
	"c4:roster": {"terrain":"hill", "title":"旧驻守名册", "kind":"record", "offset":Vector2(-416,224), "interaction_label":"调查记录"},
	"c4:winch_parts": {"terrain":"hill", "title":"绞盘零件", "kind":"parts", "offset":Vector2(480,320), "interaction_label":"领取零件"},
	"c4:winch": {"terrain":"hill", "title":"断开的绞盘", "kind":"valve", "offset":Vector2(-160,-416), "interaction_label":"操作机关"},
	"c4:archive_gate": {"terrain":"hill", "title":"档案附室入口", "kind":"gate", "anchor":"boss", "offset":Vector2(512,288), "interaction_label":"检查门锁"},
	"c4:fortress_record": {"terrain":"hill", "title":"城塞南门观测点", "kind":"survey", "anchor":"boss", "offset":Vector2(0,288), "interaction_label":"勘察现场"},
	"c4:bypass_control": {"terrain":"hill", "title":"西侧绕行绞盘", "kind":"valve", "anchor":"boss", "offset":Vector2(-416,-64), "interaction_label":"操作机关"},
	"c4:archive": {"terrain":"hill", "title":"封关档案", "kind":"record", "anchor":"boss", "offset":Vector2(512,-320), "interaction_label":"调查记录"},
	"c4:map_keeper": {"terrain":"hill", "title":"负伤的地图保管员", "kind":"injured", "portrait":"scholar", "offset":Vector2(384,-256), "interaction_label":"查看伤势"},
	"c4:snow_coordinates": {"terrain":"hill", "title":"第二次分队的坐标", "kind":"record", "offset":Vector2(-384,-352), "interaction_label":"调查记录"},
	"c4:beacon": {"terrain":"hill", "title":"丘陵接应信标", "kind":"beacon", "offset":Vector2(0,128), "interaction_label":"检查信标"},
	"c5:altar_record": {"terrain":"snow", "title":"冰封祭坛刻文", "kind":"record", "offset":Vector2(-384,128), "interaction_label":"调查记录"},
	"c5:ice_barrier": {"terrain":"snow", "title":"封住祭坛的冰障", "kind":"survey", "offset":Vector2(-352,-32), "interaction_label":"勘察现场"},
	"c5:tablet": {"terrain":"snow", "title":"祭坛内的石版", "kind":"record", "offset":Vector2(-352,-320), "interaction_label":"调查记录"},
	"c5:leader": {"terrain":"snow", "title":"受伤的远征队长", "kind":"injured", "portrait":"watchman", "offset":Vector2(352,-288), "interaction_label":"查看伤势"},
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
	"c6:ending_council": {"terrain":"lava", "title":"此后道路的议事桌", "kind":"record", "offset":Vector2(-352,224), "interaction_label":"调查记录"},
	"c6:beacon": {"terrain":"lava", "title":"熔岩接应信标", "kind":"beacon", "offset":Vector2(0,128), "interaction_label":"检查信标"},
}

static var _seed := -2147483648
static var _sites: Dictionary = {}
static var _geometry: Dictionary = {}
static var _gate_cells: Dictionary = {}
static var _open_gates: Array[String] = []
static var _barrier_cells: Dictionary = {}
static var _extra_reserved: Array[Rect2] = []
static var _extra_objects: Dictionary = {}
static var _lava_pocket := Rect2()
static var _reserved_rects_by_chunk: Dictionary = {}
static var _reserved_paths_by_chunk: Dictionary = {}
static var _troll_entry := Vector2.ZERO
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
	_barrier_cells = {}
	_extra_reserved = []
	_extra_objects = {}
	_region_routes = {}
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
	_build_ending_shelter()
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
	for y in range(-14,7):
		for x in range(8,25):
			if x != 8 and x != 24 and y != -14 and y != 6:
				continue
			var cell := _cell(anchor) + Vector2i(x,y)
			if y == 6 and x >= 15 and x <= 17:
				gate.append(cell)
			else:
				_geometry[cell] = "castle"
	_gate_cells["c4:archive_gate" if terrain == "hill" else "c6:core_gate"] = gate
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
static func ending_positions(choice: String) -> Dictionary:
	_ensure()
	var cast := ["c2:liaison","c3:survivor","c4:map_keeper","c5:leader"]
	var out := {}
	var center := site_center("plains")+Vector2(-576,1472)
	for i in cast.size():
		out[cast[i]] = center+Vector2((i-1.5)*160,-120) if choice=="centralized" else object_position(cast[i])
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
		return [_troll_entry,_troll_entry+Vector2(-96,0),_troll_entry+Vector2(0,96),_troll_entry+Vector2(96,0)]
	if terrain == "plains":
		return [entry(terrain),OutpostLayout.checkpoint_position(),OutpostLayout.center()+Vector2(-352,416)]
	if not _sites.has(terrain):
		return []
	var center := site_center(terrain)
	return [entry(terrain),center+Vector2(-640,64),center+Vector2(640,64),center+Vector2(0,-544)]
