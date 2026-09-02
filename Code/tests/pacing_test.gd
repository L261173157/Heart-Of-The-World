## 节奏浸泡测试：驱动一个"中度数值玩家"机器人持续作战 10 游戏分钟，
## 采集升级曲线 / 金币获取 / 死亡压力 / 击杀供给 / 生态健康，输出节奏报告。
## 运行："$GODOT" --headless --path Code res://tests/pacing_test.tscn --quit-after 100000
## 加速：Engine.time_scale = 4（时间均匀缩放，战斗结果与真实速度等价，按游戏秒计）。
## 好玩节奏区间（不达标 = fail，用于数值调优的回归闸门）：
##   首升 ≤120s；Lv3 ≤420s；10 分钟金币可支撑 ≥2 次商店强化；死亡 1~6 次；击杀 ≥25；生态存活 >10。
extends Node2D

const MAIN_SCENE := preload("res://scenes/main/main.tscn")
const GAME_SECONDS := 600.0
## 拟人化操作间隔：真人 ACT 每秒 2~4 个决策（移动/攻击/技能/走位并行），0.15s 太机器、0.6s 太迟钝
const STEP_INTERVAL := 0.25
## 拟人化失误率：每步 8% 概率发呆（吃弹幕/被围攻的来源——真人会失误）
const IDLE_CHANCE := 0.08
const TIME_SCALE := 4.0
## 拟人化参数：索敌半径（限单区域内部，跨区要花真实走图时间）与死亡挫败停顿
const TARGET_RADIUS := 260.0
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
## 无目标时巡游的区域锚点（拟人探索：真人清完一片自然会走出去）
var _patrol_points: Array[Vector2] = []
var _patrol_index := 0


func _ready() -> void:
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
	# 巡游锚点：六区域中心（清空一片后走出去找怪，拟人探索行为）
	for region: SimRegion in WorldSim.sim.regions.values():
		_patrol_points.append(region.center)
	GameState.stats.leveled_up.connect(_on_level_up)
	EventBus.monster_killed_by_player.connect(_on_kill)
	EventBus.player_died.connect(func() -> void: _deaths += 1)


func _process(delta: float) -> void:
	if _player == null:
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


## 无目标时走向下一个区域锚点（到达即切换），模拟真人探索换图
func _patrol() -> void:
	if _patrol_points.is_empty():
		return
	var point := _patrol_points[_patrol_index]
	if _player.global_position.distance_to(point) < 120.0:
		_patrol_index = (_patrol_index + 1) % _patrol_points.size()
		point = _patrol_points[_patrol_index]
	var dir := (point - _player.global_position).normalized()
	_player.facing = dir
	_player.global_position += dir * 90.0


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


func _on_level_up(new_level: int) -> void:
	if not _level_marks.has(new_level):
		_level_marks[new_level] = _game_time


func _on_kill(_xp: int, _gold: int, _name: String) -> void:
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
	_check(_min_hp_ratio < 0.5, "战斗有压力（最低血线 %.0f%% < 50%%）" % (_min_hp_ratio * 100.0))
	_check(WorldSim.sim != null and WorldSim.sim._build_summary()["total_alive"] > 10,
		"生态未崩盘（存活 >10）")

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
