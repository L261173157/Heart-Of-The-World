## 世界配置（纯数据，无 Node/autoload/场景依赖）。
## v4（2026-09-08 世界大地图重构）：六块 3×2 方形区域 → BiomeMap 噪声群系
## （10×10≈100 个犬牙交错斑块，80 万像素见方，端到端跑图 1 小时以上）。
## 世界结构（形状/地形/邻接/威胁）的真源是 scripts/ecology/biome_map.gd；
## 本类负责把它装配成区域定义与初始种群——game_world 装配世界、
## sim_test 生态单测都从这里读，单一事实源杜绝测试图/真实图漂移。
## 改动世界形状/带位改 BiomeMap；改种群分布改下面的地形物种表。
class_name WorldConfig
extends RefCounted

## 世界边长与斑块名义格距（BiomeMap 是结构真源，此处仅别名转发；
## CELL_SIZE 需函数计算，const 不允许调用函数，故为 static func）
const WORLD_SIZE := BiomeMap.WORLD_SIZE


static func cell_size() -> Vector2:
	return BiomeMap.cell_size()

## 玩家出生点：家园角斑块（(0,0) 格，地形恒为平原）中心
static func spawn_pos() -> Vector2:
	return BiomeMap.spawn_pos()


## 指定地形距出生角最远的斑块中心（Boss 盘踞地；测试用作“深入该地形”代表坐标）
static func farthest_terrain_center(terrain: String) -> Vector2:
	var far: Dictionary = BiomeMap.farthest_patch(terrain)
	return far["center"] if not far.is_empty() else BiomeMap.spawn_pos()


## Boss 初生、复生与城塞共同使用种子派生的家园锚点；纯数据注入模拟层。
static func boss_anchors() -> Dictionary:
	var out := {}
	# 有城塞的地形直接消费建筑目录；未来城塞选址变化也不会产生两套锚点。
	for dungeon: Dictionary in ObstacleField.dungeons():
		var name: String = TERRAIN_BOSSES.get(dungeon["terrain"], "")
		if name != "":
			out[name] = {"region_id": dungeon["patch_id"], "position": dungeon["center"]}
	for terrain: String in TERRAIN_BOSSES:
		if out.has(TERRAIN_BOSSES[terrain]):
			continue
		var patch := BiomeMap.farthest_patch(terrain)
		if not patch.is_empty():
			out[TERRAIN_BOSSES[terrain]] = {"region_id": patch["id"], "position": patch["center"]}
	return out


static var _checkpoints_seed := -2147483648
static var _checkpoints: Dictionary = {}


## 可发现复活点目录：家园、有人驻守的地标营地和城塞南门外。
## 这里只列目录；是否走到过由 GameState 持久化，绝不按死亡位置解锁未知区。
static func checkpoints() -> Dictionary:
	if _checkpoints_seed == BiomeMap.current_seed() and not _checkpoints.is_empty():
		return _checkpoints
	_checkpoints_seed = BiomeMap.current_seed()
	_checkpoints = {"home": {"name": "家园营地", "position": spawn_pos(), "kind": "camp"}}
	for lm: Dictionary in LandmarkRegistry.landmarks():
		if LandmarkRegistry.NPC_BY_KIND.has(lm["kind"]):
			_checkpoints["landmark:" + lm["id"]] = {"name": lm["kind"] + "营地",
				"position": _safe_checkpoint_position(lm["pos"]), "kind": "camp"}
	for dg: Dictionary in ObstacleField.dungeons():
		# 480px 在中心净空圈内且在南门外，约三秒能返回挑战；不会站进城墙/岩浆。
		_checkpoints["fortress:" + dg["patch_id"]] = {"name": "城塞南门",
			"position": _safe_checkpoint_position(dg["center"] + Vector2(0, 480)),
			"kind": "fortress"}
	return _checkpoints


static func _safe_checkpoint_position(pos: Vector2) -> Vector2:
	# 营地可能不在中心净空内：排除墙与灼烧液体，再逐圈找最近可站立地面。
	for ring in 17:
		for direction in (1 if ring == 0 else 16):
			var angle := float(direction) * TAU / 16.0
			var p := pos + Vector2(cos(angle), sin(angle)) * float(ring) * 32.0
			if not ObstacleField.blocks(p, 12.0) and ObstacleField.liquid_kind_at(p) == "":
				return p
	# 极端种子兜底仍安全；不会把未发现地点加入解锁列表。
	return spawn_pos()


static func nearest_checkpoint_respawn(pos: Vector2, discovered: Array[String]) -> Vector2:
	var all := checkpoints()
	var best: Vector2 = all["home"]["position"]
	var best_distance := pos.distance_squared_to(best)
	for id: String in discovered:
		if not all.has(id):
			continue
		var candidate: Vector2 = all[id]["position"]
		var distance := pos.distance_squared_to(candidate)
		if distance < best_distance:
			best = candidate
			best_distance = distance
	return _safe_checkpoint_position(best)


## 就近安全复活点：距 p 最近的平原/林地斑块中心（v4 大世界端到端 1 小时+，
## 固定回出生角意味着深处死亡要几十分钟回头路；平原/林地威胁 ≤1.3 是安全带）
static func nearest_safe_respawn(p: Vector2) -> Vector2:
	var best := BiomeMap.spawn_pos()
	var best_d := INF
	for def: Dictionary in region_defs():
		if def["terrain"] == "plains" or def["terrain"] == "forest":
			var d: float = (def["center"] as Vector2).distance_squared_to(p)
			if d < best_d:
				best_d = d
				best = def["center"]
	# 世界 v5 兜底：斑块中心有 600px 障碍抑制区理论恒空，此处幂等校验
	# （clear 原样返回）——复活点落障碍是玩家硬卡死的不可接受项
	return ObstacleField.nudge_free(best, 12.0)


## 区域定义（与旧 REGIONS 数组同构：id/name/terrain/threat/capacity/center/
## neighbors，另带 i/j/size）。由 BiomeMap 确定性派生——改动世界只改 BiomeMap
static func region_defs() -> Array:
	return BiomeMap.patches()


## 世界全部地形类型（balance_test/ui_flow_test 的 TERRAIN_BANDS/TERRAIN_THEMES
## 覆盖校验用）
static func terrains() -> Array:
	var out: Array = []
	for def: Dictionary in region_defs():
		if not out.has(def["terrain"]):
			out.append(def["terrain"])
	return out


## 每地形初始物种表（每斑块按此撒布，沿用 v3 六区阵容与配比）。
## 每斑块总数 ≤ 该地形承载且留 1~3 余量：满载即全区停繁衍
## （EcologySim._process_breeding），最短寿命 200 tick ≈ 3.3 分钟才有第一具
## 尸体腾格子——开局"世界是活的"（繁衍/扩张可见）是第一印象，不预留余量
## 会在头几分钟被静默锁死
const TERRAIN_POPULATION := {
	"plains": {"火把哥布林": 3, "地精矿工": 3, "突袭蛇": 1, "青甲龟": 1, "山猪": 1},
	"forest": {"赤炎小魔": 3, "蜥蜴刀客": 3, "弹弓地精": 2, "巫毒萨满": 2, "山羊": 2},
	"snow": {"雪原窃贼": 3, "白骨兵": 3, "冰霜小魔": 3, "雪原巨熊": 1},
	"swamp": {"冰霜小魔": 2, "巨蝠": 3, "沼泽蛛": 1, "炸弹鱼": 1, "鱼叉鲨": 1, "野鸭": 1},
	"hill": {"长矛哥布林": 5, "山蜂": 3, "投骨豺狼人": 2, "山岳熊猫": 1},
	"lava": {"火蜂": 3, "黑曜牛卫": 3, "熔岩萨满": 1},
}

## 每地形 Boss（各一只，盘踞该地形距出生角最远的斑块——旅程尽头的顶点）
const TERRAIN_BOSSES := {
	"forest": "巨魔王",
	"hill": "牛头王",
	"lava": "熔岩龟王",
}

## 初始种群：{ 斑块 id: { 物种: 数量 } }——按地形表铺满全部斑块 + 远端 Boss。
## 总活体约 880（100 斑块 × 7~10 只），模拟层 O(个体) 恒轻，表现层由
## game_world 按玩家距离流式生成节点
static func initial_population() -> Dictionary:
	var out := {}
	var boss_patch_ids := {}
	for terrain: String in TERRAIN_BOSSES:
		var far: Dictionary = BiomeMap.farthest_patch(terrain)
		if not far.is_empty():
			boss_patch_ids[far["id"]] = TERRAIN_BOSSES[terrain]
	for def: Dictionary in region_defs():
		var roster: Dictionary = (TERRAIN_POPULATION.get(def["terrain"], {}) as Dictionary).duplicate()
		var boss: String = boss_patch_ids.get(def["id"], "")
		if boss != "":
			roster[boss] = 1
		if not roster.is_empty():
			out[def["id"]] = roster
	return out
