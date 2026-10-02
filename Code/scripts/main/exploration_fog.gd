## 局部探索真源：128px 格、32×32 位稀疏块，只为到访范围分配内存。
## 旧200×200地图只作为已知地形记忆；不会变成实时视野或展开成全世界细图。
class_name ExplorationFog
extends RefCounted

const CELL := 128.0
const CHUNK_SIDE := 32
const CHUNK_BYTES := 128
const GRID := 6250 # 800000 / 128；世界边界外不钳到边缘已知格
const LEGACY_GRID := 200
const LEGACY_BYTES := 5000
const REVEAL_RADIUS := 1600.0
const SCHEMA := 1
var seed: int
var chunks: Dictionary = {}
var legacy := PackedByteArray()


func _init(world_seed: int = 0) -> void:
	seed = world_seed


static func cell_of(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / CELL), floori(pos.y / CELL))


static func valid_cell(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < GRID and cell.y < GRID


func is_explored(pos: Vector2) -> bool:
	if not pos.is_finite() or not Rect2(Vector2.ZERO, BiomeMap.WORLD_SIZE).has_point(pos):
		return false
	var cell := cell_of(pos)
	if not valid_cell(cell):
		return false
	var key := Vector2i(cell.x >> 5, cell.y >> 5)
	var index := (cell.y & 31) * CHUNK_SIDE + (cell.x & 31)
	if chunks.has(key) and chunks[key][index >> 3] & (1 << (index & 7)) != 0:
		return true
	var old := Vector2i(pos / 4000.0)
	return legacy.size() == LEGACY_BYTES and legacy[old.y * 25 + (old.x >> 3)] & (1 << (old.x & 7)) != 0


func remember_legacy_cell(cell: Vector2i) -> void:
	if cell.x < 0 or cell.y < 0 or cell.x >= LEGACY_GRID or cell.y >= LEGACY_GRID:
		return
	if legacy.is_empty():
		legacy.resize(LEGACY_BYTES)
	var index := cell.y * 25 + (cell.x >> 3)
	legacy[index] |= 1 << (cell.x & 7)


## 返回本次新格，调用方可同步旧粗图供既有任务线索消费；固定最多27×27次。
func reveal(pos: Vector2) -> Array[Vector2i]:
	var added: Array[Vector2i] = []
	if not pos.is_finite() or not Rect2(Vector2.ZERO, BiomeMap.WORLD_SIZE).has_point(pos):
		return added
	var center := cell_of(pos)
	var reach := ceili(REVEAL_RADIUS / CELL)
	for y in range(center.y - reach, center.y + reach + 1):
		for x in range(center.x - reach, center.x + reach + 1):
			var cell := Vector2i(x, y)
			if not valid_cell(cell) or ((Vector2(cell) + Vector2(0.5, 0.5)) * CELL).distance_squared_to(pos) > REVEAL_RADIUS * REVEAL_RADIUS:
				continue
			var key := Vector2i(x >> 5, y >> 5)
			if not chunks.has(key):
				var bytes := PackedByteArray()
				bytes.resize(CHUNK_BYTES)
				chunks[key] = bytes
			var index := (y & 31) * CHUNK_SIDE + (x & 31)
			var bytes: PackedByteArray = chunks[key]
			var mask := 1 << (index & 7)
			if bytes[index >> 3] & mask == 0:
				bytes[index >> 3] |= mask
				chunks[key] = bytes
				added.append(cell)
	return added


func to_dict() -> Dictionary:
	var saved := {}
	for key: Vector2i in chunks:
		saved["%d,%d" % [key.x, key.y]] = Marshalls.raw_to_base64(chunks[key])
	return {"version": SCHEMA, "seed": seed, "chunks": saved,
		"legacy": "" if legacy.is_empty() else Marshalls.raw_to_base64(legacy)}


## 新字段存在但损坏/种子不符时 fail closed，不能回退粗图来扩大探索。
func restore(data: Variant, old_bitmap: PackedByteArray) -> void:
	chunks.clear()
	legacy = PackedByteArray()
	if data == null:
		if old_bitmap.size() == LEGACY_BYTES:
			legacy = old_bitmap.duplicate()
		return
	if not data is Dictionary or data.get("version") != SCHEMA or data.get("seed") != seed:
		return
	var saved: Variant = data.get("chunks", {})
	if saved is Dictionary:
		for key: Variant in saved:
			if not key is String or not saved[key] is String or saved[key].length() != 172:
				continue
			var parts: PackedStringArray = key.split(",")
			if parts.size() != 2 or parts[0].length() > 3 or parts[1].length() > 3 \
				or not parts[0].is_valid_int() or not parts[1].is_valid_int():
				continue
			# 必须在构造32位Vector2i之前验证64位整数，拒绝溢出别名归零。
			var x := int(parts[0])
			var y := int(parts[1])
			if x < 0 or y < 0 or x > ((GRID - 1) >> 5) or y > ((GRID - 1) >> 5):
				continue
			var cell := Vector2i(x, y)
			var decoded := decode_bitmap(saved[key], CHUNK_BYTES)
			if decoded.size() == CHUNK_BYTES:
				chunks[cell] = decoded
	var old: Variant = data.get("legacy", "")
	if old is String and old.length() == 6668:
		var decoded := decode_bitmap(old, LEGACY_BYTES)
		if decoded.size() == LEGACY_BYTES:
			legacy = decoded


## 在调用引擎解码器前拒绝坏字母/填充，坏探索字段安全归零且不制造引擎ERROR。
## 只校验本模块固定字节数的位图；不会捕获或屏蔽任何真正的运行错误。
static func decode_bitmap(encoded: Variant, byte_count: int) -> PackedByteArray:
	if not encoded is String:
		return PackedByteArray()
	var expected_length := ((byte_count + 2) / 3) * 4
	if encoded.length() != expected_length:
		return PackedByteArray()
	var padding := (3 - byte_count % 3) % 3
	var content_length := expected_length - padding
	for i in content_length:
		var ch: int = encoded.unicode_at(i)
		if not ((ch >= 65 and ch <= 90) or (ch >= 97 and ch <= 122) \
				or (ch >= 48 and ch <= 57) or ch == 43 or ch == 47):
			return PackedByteArray()
	for i in range(content_length, expected_length):
		if encoded.unicode_at(i) != 61: # '='只能出现在预期的末尾填充位。
			return PackedByteArray()
	return Marshalls.base64_to_raw(encoded)
