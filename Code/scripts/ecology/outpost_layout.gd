## 首章前哨的静态位置与通路目录。只依赖种子地貌，不引用场景或活体目标。
## 所有硬障碍由 ObstacleField 消费；本类不写生态，也不绕过摧毁覆盖层。
class_name OutpostLayout
extends RefCounted

const CELL := 32.0
const CHECKPOINT_ID := "outpost:lost_watch"
const HALF_CELLS := Vector2i(19, 16)
const OFFSET := Vector2(3456, -1536)
const INTERACT_DISTANCE := 94.0
const OBJECTS := {
	"patrol_record": {"title": "遗落的巡逻札记", "kind": "record", "interaction_label": "调查札记"},
	"entrance_record": {"title": "门前的拖行痕迹", "kind": "record", "offset": Vector2(-128, 544), "interaction_label": "调查入口"},
	"wounded_patrol": {"title": "受伤的前哨巡守", "kind": "patrol", "offset": Vector2(-352, -192), "interaction_label": "交谈"},
	"supply_record": {"title": "补给区清单", "kind": "record", "offset": Vector2(256, 96), "interaction_label": "查看清单"},
	"aid_bag": {"title": "巡守急救包", "kind": "aid", "offset": Vector2(448, -320), "interaction_label": "拾取急救包"},
	"repair_tools": {"title": "前哨维修工具", "kind": "tools", "offset": Vector2(448, 320), "interaction_label": "拾取工具"},
	"signpost": {"title": "损坏的前哨路标", "kind": "signpost", "offset": Vector2(96, 576), "interaction_label": "检查路标"},
	"survey_marker": {"title": "前哨观测点", "kind": "survey", "offset": Vector2(0, 160), "interaction_label": "观察周边"},
}

static var _seed := -2147483648
static var _center := Vector2.ZERO
static var _cell := Vector2i.ZERO
static var _geometry: Dictionary = {}
static var _trail := PackedVector2Array()
static var _bounds := Rect2()
static var _trail_bounds := Rect2()
static var _reserved_bounds := Rect2()


static func _ensure() -> void:
	if _seed == BiomeMap.current_seed():
		return
	_seed = BiomeMap.current_seed()
	var candidate := BiomeMap.spawn_pos() + OFFSET
	_cell = Vector2i(floori(candidate.x / CELL), floori(candidate.y / CELL))
	_center = (Vector2(_cell) + Vector2(0.5, 0.5)) * CELL
	_bounds = Rect2(_center + Vector2(-736, -640), Vector2(1472, 1536))
	_geometry = {}
	# 低石围墙：南门96px，西侧160px缺口，两条进路的物理尺寸均可通行。
	for y in range(-HALF_CELLS.y, HALF_CELLS.y + 1):
		for x in range(-HALF_CELLS.x, HALF_CELLS.x + 1):
			if absi(x) != HALF_CELLS.x and absi(y) != HALF_CELLS.y:
				continue
			if y == HALF_CELLS.y and absi(x) <= 1:
				_geometry[_cell + Vector2i(x, y)] = "rock"
			elif x == -HALF_CELLS.x and y >= -7 and y <= -3:
				continue
			else:
				_geometry[_cell + Vector2i(x, y)] = "castle"
	# 旧值守区与补给区之间的隔墙；两端均可绕行，不生成无出口房间。
	for y in range(-13, 12):
		_geometry[_cell + Vector2i(3, y)] = "castle"
	# 物资架把北侧医药和南侧工具分开，两端各留至少三格通路。
	for x in range(7, 17):
		_geometry[_cell + Vector2i(x, 0)] = "castle"
	# 小屋/瞭望塔的实心底座也进入同一真源，绝不另挂表现层假碰撞。
	for anchor: Vector2i in [Vector2i(-11, -10), Vector2i(-11, 8)]:
		for y in range(-1, 1):
			for x in range(-1, 2):
				_geometry[_cell + anchor + Vector2i(x, y)] = "castle"
	var start := BiomeMap.spawn_pos() + Vector2(0, 768)
	var end := _center + Vector2(0, 704)
	_trail = PackedVector2Array([start, start.lerp(end, 0.5), end])
	_trail_bounds = Rect2(start, Vector2.ZERO).expand(end).grow(64)
	_reserved_bounds = _bounds.merge(_trail_bounds)


static func center() -> Vector2:
	_ensure()
	return _center


static func center_cell() -> Vector2i:
	_ensure()
	return _cell


static func footprint() -> Rect2:
	_ensure()
	return _bounds


static func object_position(id: String) -> Vector2:
	_ensure()
	if id == "patrol_record":
		return _trail[1]
	if not OBJECTS.has(id):
		return Vector2.INF
	return _center + OBJECTS[id]["offset"]


static func objects() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in OBJECTS:
		var item: Dictionary = OBJECTS[id].duplicate()
		item["id"] = id
		item["position"] = object_position(id)
		out.append(item)
	return out


static func entrances() -> Dictionary:
	return {"front": center() + Vector2(0, 512), "side": center() + Vector2(-608, -160)}


static func checkpoint_position() -> Vector2:
	return center() + Vector2(-352, -96)


static func path_to_front() -> PackedVector2Array:
	_ensure()
	return _trail.duplicate()


static func front_barricade_cells() -> Array[Vector2i]:
	var c := center_cell()
	return [c + Vector2i(-1, 16), c + Vector2i(0, 16), c + Vector2i(1, 16)]


static func obstacle_kind(cell: Vector2i) -> String:
	_ensure()
	return _geometry.get(cell, "")


static func obstacle_cells() -> Dictionary:
	_ensure()
	return _geometry.duplicate()


## 仅此作者地块及128px宽来路保留干燥通道，不改变外围噪声配方或原有摧毁记录。
static func reserved_ground(pos: Vector2) -> bool:
	_ensure()
	if not _reserved_bounds.has_point(pos):
		return false
	if _bounds.has_point(pos):
		return true
	if not _trail_bounds.has_point(pos):
		return false
	return Geometry2D.get_closest_point_to_segment(pos, _trail[0], _trail[2]).distance_squared_to(pos) <= 64.0 * 64.0


static func structures() -> Array[Dictionary]:
	return [
		{"id": "watch_shelter", "asset": "ts_house1", "position": center() + Vector2(-352, -304)},
		{"id": "watch_tower", "asset": "ts_tower", "position": center() + Vector2(-352, 272)},
	]
