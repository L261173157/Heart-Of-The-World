## 节奏浸泡测试：驱动一个"中度数值玩家"机器人持续作战 10 游戏分钟，
## 采集升级曲线 / 金币获取 / 死亡压力 / 击杀供给 / 生态健康，输出节奏报告。
## 运行："$GODOT" --headless --path Code res://tests/pacing_test.tscn --quit-after 100000
## 加速：Engine.time_scale = 4（时间均匀缩放，战斗结果与真实速度等价，按游戏秒计）。
## 好玩节奏闸门（不达标 = fail，用于数值调优的回归闸门）：
##   首升 ≤120s；Lv3 ≤420s；10 分钟金币可支撑 ≥2 次商店强化；击杀 ≥25；最低血线 <70%
##   （v4 大世界按出生带标定，2026-09-08；旧小世界口径为 <50%）；
##   生态未崩盘（近 60 tick 存活均值 >10，2026-09-03 加固抗瞬时波动）。
##   （死亡数为观察项不入闸：机器人从不闪避/撤退，10 分钟死 6~19 次，人类玩家用冲刺无敌帧会低得多）
## 升级三选一会暂停世界，机器人每帧代选第一张赐福后继续。
extends Node2D

const MAIN_SCENE := preload("res://scenes/main/main.tscn")
const GAME_SECONDS := 600.0
## 拟人化操作间隔：真人 ACT 每秒 2~4 个决策（移动/攻击/技能/走位并行），0.15s 太机器、0.6s 太迟钝
const STEP_INTERVAL := 0.25
## 拟人化失误率：每步 8% 概率发呆（吃弹幕/被围攻的来源——真人会失误）
const IDLE_CHANCE := 0.08
const TIME_SCALE := 4.0
## 拟人化参数：索敌半径与死亡挫败停顿。v4 据点式：怪物扎根地图营地
## （不在玩家身边凭空刷出），索敌半径 700 匹配营地散布；跨据点仍要真实
## 走图时间（机器人瞬移只发生在已索敌的目标旁）
const TARGET_RADIUS := 700.0
const DEATH_IDLE := 8.0

## 商店 weapon 线累计花费阈值（50 / +90 / +130 / +170 / +210）
const GOLD_THRESHOLDS := [50, 140, 270, 440, 650]

var _player: Player
var _world: Node2D
var _fails := 0
var _game_time := 0.0
var _timer := 0.0
var _kills := 0
var _deaths := 0
var _level_marks := {}          # level -> 首次到达的游戏秒
var _gold_marks := {}           # 阈值 -> 首次跨越的游戏秒
var _threshold_index := 0
var _last_level := 1
var _dead_until := -1.0         # 死亡挫败停顿（拟人化：真人死后会缓一缓）
var _min_hp_ratio := 1.0        # 承压度量（贴脸机器人不会死，血线才是真实压力）
## 生态存活滚动窗（最近 60 tick ≈ 1 游戏分钟）：瞬时值在高猎杀局会被
## 捕食/围剿打到个位数又快速回补，均值才反映"是否真崩盘"（2026-09-03 数值统一设计加固）
var _alive_window: Array[int] = []
## 无目标时巡游的区域锚点（拟人探索：真人清完一片自然会走出去）
## 游猎目标（最近有种群斑块中心；Vector2.INF = 无目标）与重选时刻
var _patrol_target := Vector2.INF
var _patrol_retarget := 0.0


func _ready() -> void:
	# 升级三选一会暂停世界，机器人必须 ALWAYS 才能代选赐福并推进流程
	process_mode = Node.PROCESS_MODE_ALWAYS
	Engine.time_scale = TIME_SCALE
	# 沙盒隔离：从 Lv1 干净进度出发（autoload 启动时加载的是开发者真实档，
	# 金币/等级阈值会被污染），且全程不落盘、不碰真实 user://save.json
	GameState.SAVE_PATH = "user://pacing_test.json"
	GameState.save_enabled = false
	GameState.reset_all()
	var world := MAIN_SCENE.instantiate()
	_world = world
	add_child(world)
	# 机器人普攻会触发顿帧，其恢复逻辑会把 time_scale 重置回 1.0，
	# 打掉测试的 4× 加速——节奏测试关闭顿帧
	world.hit_stop_enabled = false
	await get_tree().process_frame
	await get_tree().process_frame
	_player = get_tree().get_first_node_in_group("player")
	# 中度数值玩家（不堆数值，模拟真实成长起点）
	_player.stats.strength = 12
	_player.stats.agility = 6
	_player.stats.intellect = 6
	# v4 大世界游猎：不再固定锚点列表——打光脚下据点后朝最近的仍有种群的
	# 营地走（移动本身制造遭遇：怪物扎根营地，走到就撞上）；
	# 拟人探索行为，节奏模型与真实大世界玩家一致
	_patrol_retarget = 0.0
	GameState.stats.leveled_up.connect(_on_level_up)
	EventBus.monster_killed_by_player.connect(_on_kill)
	EventBus.player_died.connect(func() -> void: _deaths += 1)
	EventBus.sim_tick_completed.connect(func(summary: Dictionary) -> void:
		_alive_window.append(int(summary.get("total_alive", 0)))
		if _alive_window.size() > 60:
			_alive_window.remove_at(0))


func _process(delta: float) -> void:
	if _player == null:
		return
	# 世界因三选一赐福暂停时：代选第一张（卡池每次洗牌，首张即随机）
	if get_tree().paused:
		var hud := _world.get_node_or_null("HUD")
		if hud != null and hud.passive_layer.visible:
			hud._pick_passive(0)
		return
	_game_time += delta
	if _game_time >= GAME_SECONDS:
		_finish()
		return
	_track_gold()
	_min_hp_ratio = minf(_min_hp_ratio, _player.current_hp / _player.stats.max_hp())
	if _game_time < _dead_until:
		return
	if _player._is_dead:
		_dead_until = _game_time + DEATH_IDLE
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = STEP_INTERVAL
		_robot_step()


## 简单策略机器人：就近索敌 → 贴身普攻；残血治疗；扎堆重击；中距法弹；8% 发呆
func _robot_step() -> void:
	if randf() < IDLE_CHANCE:
		return
	var target := _nearest_monster()
	if target == null:
		_patrol()
		return
	var dist: float = _player.global_position.distance_to(target.global_position)
	var dir := (target.global_position - _player.global_position).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT

	if _player.current_hp < _player.stats.max_hp() * 0.6:
		_player._try_heal()
	if _count_nearby(120.0) >= 3:
		_player._try_heavy_attack()
	if dist > 100.0 and dist < 300.0:
		_player._try_cast_bolt()

	_player.facing = dir
	if dist > 24.0:
		_player.global_position = target.global_position - dir * 22.0
	_player._try_attack()


## 无目标时游猎：朝最近的有存活种群的据点移动（v4 大世界节奏模型——
## 移动=遭遇供给；每 8 游戏秒或到达后重选目标，拟人探索不追纯最优路径）
func _patrol() -> void:
	if not is_finite(_patrol_target.x) or _game_time - _patrol_retarget > 8.0 \
			or _player.global_position.distance_to(_patrol_target) < 120.0:
		_patrol_retarget = _game_time
		_patrol_target = _nearest_populated_center()
		if not is_finite(_patrol_target.x):
			return
	var dir := (_patrol_target - _player.global_position).normalized()
	_player.facing = dir
	# 空地赶路提速（300px/步 = 1200px/s 游戏速）：大世界斑块间距 8 万像素，
	# 按战斗步速 90px 走要 3.7 分钟/跳——600 秒预算全花在赶路上（实测 34 杀）。
	# 提速模拟真实玩家冲刺穿行空地（冲刺连发 ~620px/s + 空旷无战），遭遇时
	# 机器人回到 22px 贴身节奏，战斗压力口径不变
	_player.global_position += dir * 300.0


## 最近的有存活个体的据点（打光的地方不再回头，模拟"往前探索"；
## 全世界无活体时返回 Vector2.INF）。v4 据点式：怪物扎根地图营地（camp），
## 游猎目标取最近存活实例的位置而非斑块中心——营地与斑块中心可相距
## 上万像素，按中心走会扑空
func _nearest_populated_center() -> Vector2:
	var sim: EcologySim = WorldSim.sim
	if sim == null:
		return Vector2.INF
	var me := _player.global_position
	var best := Vector2.INF
	var best_d := INF
	for inst: MonsterInstance in sim.instances.values():
		if not inst.is_alive or inst.spawn_pos == Vector2.INF:
			continue
		var d: float = me.distance_squared_to(inst.spawn_pos)
		if d < best_d:
			best_d = d
			best = inst.spawn_pos
	return best


func _nearest_monster() -> MonsterBase:
	var best: MonsterBase = null
	var best_dist := INF
	for body in get_tree().get_nodes_in_group("monsters"):
		var monster := body as MonsterBase
		if monster == null or monster.inst == null or monster.state == MonsterBase.S_CORPSE:
			continue
		var dist: float = _player.global_position.distance_to(monster.global_position)
		if dist < best_dist and dist <= TARGET_RADIUS:
			best = monster
			best_dist = dist
	return best


func _count_nearby(radius: float) -> int:
	var count := 0
	for body in get_tree().get_nodes_in_group("monsters"):
		var monster := body as MonsterBase
		if monster == null or monster.inst == null or monster.state == MonsterBase.S_CORPSE:
			continue
		if _player.global_position.distance_to(monster.global_position) <= radius:
			count += 1
	return count


func _on_level_up(new_level: int, _levels: int) -> void:
	if not _level_marks.has(new_level):
		_level_marks[new_level] = _game_time


func _on_kill(_xp: int, _gold: int, _name: String, _species: String) -> void:
	_kills += 1


func _track_gold() -> void:
	while _threshold_index < GOLD_THRESHOLDS.size() \
			and GameState.gold >= GOLD_THRESHOLDS[_threshold_index]:
		_gold_marks[GOLD_THRESHOLDS[_threshold_index]] = _game_time
		_threshold_index += 1


func _finish() -> void:
	set_process(false)
	Engine.time_scale = 1.0
	var level_now: int = GameState.stats.level
	var purchases: int = _gold_marks.size()
	print("\n=== 节奏报告（%.0f 游戏秒，time_scale=%.0f） ===" % [_game_time, TIME_SCALE])
	print("  击杀 %d 只 / 死亡 %d 次 / 终点等级 Lv.%d / 金币 %d / 最低血线 %.0f%%" % [
		_kills, _deaths, level_now, GameState.gold, _min_hp_ratio * 100.0])
	print("  升级时刻：%s" % str(_level_marks))
	print("  商店阈值跨越：%s（%d 次）" % [str(_gold_marks), purchases])

	_check(_kills >= 25, "击杀供给充足（%d ≥ 25）" % _kills)
	_check(_level_marks.has(2) and _level_marks[2] <= 120.0,
		"首升 ≤120s（%s）" % str(_level_marks.get(2, "未升级")))
	_check(level_now >= 3 and _level_marks.get(3, 1e9) <= 420.0,
		"Lv3 ≤420s（%s）" % str(_level_marks.get(3, "未达到")))
	_check(purchases >= 2, "金币支撑 ≥2 次商店强化（%d 次）" % purchases)
	# v4 大世界（2026-09-08）标定：10 游戏分钟只能采样出生带低威胁群系
	# （对角线 108 分钟才是熔岩），遭遇模型从"小区域持续绞肉"变为"簇战+赶路"；
	# 同日据点式重构后再标：怪物扎根单物种营地（2~5 只/营，繁衍逐代外扩），
	# 围攻密度低于旧九只混编簇，机器人实测血线稳定 65~66%、击杀 114~173
	# （供给大增），闸门调至 <70% 守"战斗有压力"的底线（完全无伤仍被拦截），
	# 死亡数保持观察项；真人触屏操作承压高于机器人，口径偏保守
	_check(_min_hp_ratio < 0.70, "战斗有压力（最低血线 %.0f%% < 70%%）" % (_min_hp_ratio * 100.0))
	# 生态闸门：最近 60 tick 存活均值 >10（瞬时值在 240+ 击杀局会被打到个位数
	# 又随即回补——总量出生上限 94/分 vs 猎杀 24/分，均值才能区分"波动"与"崩盘"）
	var alive_avg := 0.0
	for v in _alive_window:
		alive_avg += v
	if not _alive_window.is_empty():
		alive_avg /= _alive_window.size()
	var alive_final: int = WorldSim.sim._build_summary()["total_alive"] if WorldSim.sim != null else 0
	_check(alive_avg > 10.0,
		"生态未崩盘（近 60 tick 存活均值 %.1f >10，终点 %d）" % [alive_avg, alive_final])
	# v7 物品闸门：10 游戏分钟的猎杀应攒下可见的材料流（拾取感），
	# 但不爆仓（材料是金币补充而非替代）。上界放宽到 ITEM_MAX×物种数级别
	# 不现实，取 60 = 击杀 114~173 实测 × 掉材料物种占比 × 平均 1.x 件的包络
	var material_count := 0
	for id: String in EconomyMath.ITEM_SELL:
		material_count += GameState.count_item(id)
	_check(material_count >= 5 and material_count <= 60,
		"材料拾取节奏健康（10 分钟 %d 件 ∈ [5,60]）" % material_count)

	if _fails == 0:
		print("=== 节奏验证全部通过 ===")
		get_tree().quit(0)
	else:
		print("=== %d 项未达节奏区间 ===" % _fails)
		get_tree().quit(1)


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  PASS  %s" % msg)
	else:
		_fails += 1
		print("  FAIL  %s" % msg)
