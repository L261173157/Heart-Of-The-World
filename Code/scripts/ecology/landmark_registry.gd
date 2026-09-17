## 世界地标注册表（纯逻辑，RefCounted，无 Node/场景树——架构铁律合规）。
## 世界 v5 探索层：每斑块 1~2 个确定性地标，id（lm_{patch}_{k}）随种子稳定、
## 可直接入存档。任务系统（待定池）未来的"到达/发现/清理"类目标在此挂锚点。
## 落点 = 斑块环带（0.18~0.42 格）hash 方位 + 通行性校验（避开障碍与抑制区
## 之外的硬卡点），向心折半重试与营地同构。种子派生自 BiomeMap.current_seed
## （configure 懒重建），表现层只消费本表不改写。
class_name LandmarkRegistry
extends RefCounted

## 每群系的地标类型（索引由 hash 决定）；微光色供发现播报/小地图图标用
const KINDS := {
	"plains": ["古树", "石环"],
	"forest": ["精灵泉", "古树"],
	"snow": ["冰封祭坛", "冰晶柱林"],
	"swamp": ["沉睡图腾", "枯木灵龛"],
	"hill": ["荒废遗迹", "了望石塔"],
	"lava": ["黑曜碑", "余烬圣所"],
}
const KIND_COLORS := {
	"古树": Color(0.4, 0.85, 0.45), "石环": Color(0.75, 0.7, 0.55),
	"精灵泉": Color(0.45, 0.8, 0.95), "冰封祭坛": Color(0.7, 0.85, 1.0),
	"冰晶柱林": Color(0.6, 0.9, 0.95), "沉睡图腾": Color(0.75, 0.6, 0.35),
	"枯木灵龛": Color(0.6, 0.5, 0.4), "荒废遗迹": Color(0.85, 0.8, 0.6),
	"了望石塔": Color(0.8, 0.75, 0.65), "黑曜碑": Color(0.65, 0.4, 0.9),
	"余烬圣所": Color(1.0, 0.55, 0.3),
}
## 发现半径（表现层 Area2D 圆；走近即"发现"）
const DISCOVER_RADIUS := 400.0
## 地标 NPC（世界 v5）：特定类型地标常驻 NPC 发任务——靠近按攻击键交互。
## quest 类型：hunt=狩猎 / ransack=捣巢 / explore=探索
const NPC_BY_KIND := {
	"石环": {"name": "营地猎人", "quest": "hunt"},
	"荒废遗迹": {"name": "遗迹学者", "quest": "ransack"},
	"精灵泉": {"name": "泉水守望者", "quest": "explore"},
}

static var _cache: Array = []
static var _seed_cached := -2147483648


## 全部地标：[{id, patch_id, kind, pos}]（同种子确定性缓存）
static func landmarks() -> Array:
	if _seed_cached == BiomeMap.current_seed() and not _cache.is_empty():
		return _cache
	_seed_cached = BiomeMap.current_seed()
	_cache = []
	for def: Dictionary in BiomeMap.patches():
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("lm|%s" % def["id"]) & 0x7FFFFFFF
		var kinds: Array = KINDS.get(def["terrain"], ["古树"])
		var count := 1 + (1 if rng.randf() < 0.45 else 0)
		var center: Vector2 = def["center"]
		for k in count:
			var angle := rng.randf() * TAU
			var ring := rng.randf_range(0.18, 0.42) * float(def["size"].x)
			var kinds_rng := RandomNumberGenerator.new()
			kinds_rng.seed = hash("lmk|%s|%d" % [def["id"], k]) & 0x7FFFFFFF
			var kind: String = kinds[kinds_rng.randi() % kinds.size()]
			_cache.append({
				"id": "lm_%s_%d" % [def["id"].substr(2), k],
				"patch_id": def["id"],
				"kind": kind,
				"pos": _valid_pos(center, Vector2(cos(angle), sin(angle)) * ring),
			})
	return _cache


## 指定斑块的地标（game_world 就近查地表/建发现 Area 用）
static func landmarks_of_patch(patch_id: String) -> Array:
	var out: Array = []
	for lm: Dictionary in landmarks():
		if lm["patch_id"] == patch_id:
			out.append(lm)
	return out


static func landmark(id: String) -> Dictionary:
	for lm: Dictionary in landmarks():
		if lm["id"] == id:
			return lm
	return {}


## 地标颜色（播报/小地图图标）
static func kind_color(kind: String) -> Color:
	return KIND_COLORS.get(kind, Color.WHITE)


## 落点通行化：硬卡点（障碍内）向心折半重试，仍卡用 8 方向 nudge
static func _valid_pos(center: Vector2, offset: Vector2) -> Vector2:
	var pos := center + offset
	for i in 4:
		if not ObstacleField.blocks(pos, 16.0):
			return pos
		pos = pos.lerp(center, 0.5)
	return ObstacleField.nudge_free(pos, 16.0)
