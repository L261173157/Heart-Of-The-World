## 性能探针（图形模式运行，非 headless）：
##   "$GODOT" --path Code --resolution 1280x720 res://tests/perf_probe.tscn
##   "$GODOT" --path Code --resolution 2556x1179 res://tests/perf_probe.tscn   # iPhone 15 物理分辨率
## 完整世界 + 移动 + 战斗负载下每 0.5s 采样：FPS / CPU process 耗时 / 物理步耗时 /
## 绘制调用数 / 画布对象数 / 活跃怪物数。第 8/14/20 秒各传送 +700px 触发跨块流式尖峰。
## 结束打印汇总（均值/最大值），据此区分 GPU 填充 / CPU 常驻 / 流式尖峰三类瓶颈。
## HOTW_PROBE_NIGHT=1 强制满夜（提灯+阴影开销取证）。
extends Node2D

const MAIN_SCENE := preload("res://scenes/main/main.tscn")
## 总时长：前 4s 世界预热（流式稳定），4~24s 为采样窗口
const DURATION := 24.0
const SAMPLE_INTERVAL := 0.5
## 传送时刻：触发地形/障碍/导航跨块重建的尖峰采样
const TELEPORT_AT := [8.0, 14.0, 20.0]
## 采样即落盘（绕开 stdout 块缓冲；进程被杀数据不丢）
const OUT_CSV := "/tmp/hotw_perf_samples.csv"
## 二分开关（均在 t=6s 生效，之后采样即"关停后"数字）：
##   HOTW_PROBE_KILL_MONSTERS=1  怪物组全部 PROCESS_MODE_DISABLED（停 AI/物理回调）
##   HOTW_PROBE_KILL_NAV=1        NavigationServer2D.set_active(false)（停寻路/RVO/地图同步）
##   HOTW_PROBE_KILL_FX=1         FxLayer 节点隐藏（停动画帧推进）
const KILL_AT := 6.0

var _elapsed := 0.0
var _sample_accum := 0.0
var _attack_pulse := 0.0
var _teleport_i := 0
var _kill_applied := false
## 采样行：[t, fps, proc_ms, phys_ms, draws, objects, monsters]
var _rows: Array = []


func _ready() -> void:
	GameState.save_enabled = false
	GameState.ecology_snapshot = null
	# 游戏锁 60 帧（run/max_fps），探针解除限制以测真实余量（帧率上限本身
	# 也是性能口径的一部分——锁帧前真机实测 80~120）
	Engine.max_fps = 0
	var f := FileAccess.open(OUT_CSV, FileAccess.WRITE)
	if f != null:
		f.store_line("t,fps,proc_ms,phys_ms,draws,objects,monsters")
	var fm := FileAccess.open("/tmp/hotw_perf_monsters.csv", FileAccess.WRITE)
	if fm != null:
		fm.store_line("t,near_ms,near_n,far_ms,far_n,anim_ms,anim_n,nav_ms,nav_n")
	add_child(MAIN_SCENE.instantiate())
	if OS.get_environment("HOTW_PROBE_NIGHT") == "1":
		WorldSim.resume_clock(0.68, WorldSim.game_day)
	var player := get_tree().get_first_node_in_group("player")
	if player != null:
		var monsters := get_tree().get_nodes_in_group("monsters")
		if not monsters.is_empty():
			player.global_position = (monsters[0] as Node2D).global_position + Vector2(64.0, 24.0)


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= DURATION:
		_finish()
		return
	# 二分开关在 KILL_AT 生效一次（之后的采样行即关停后负载）
	if not _kill_applied and _elapsed >= KILL_AT:
		_kill_applied = true
		if OS.get_environment("HOTW_PROBE_KILL_MONSTERS") == "1":
			for m in get_tree().get_nodes_in_group("monsters"):
				m.process_mode = Node.PROCESS_MODE_DISABLED
			print(">>> t=%.1f 已停用全部怪物处理" % _elapsed)
		if OS.get_environment("HOTW_PROBE_KILL_NAV") == "1":
			NavigationServer2D.set_active(false)
			print(">>> t=%.1f 已停用 NavigationServer" % _elapsed)
		# 逗号分隔的子系统名：按类/名匹配 Main 下子节点整层停处理+隐藏
		var disable_arg := OS.get_environment("HOTW_PROBE_DISABLE")
		if disable_arg != "":
			var main_node := get_node_or_null("Main")
			if main_node != null:
				for part in disable_arg.split(","):
					var hits: Array = []
					if part == "MAIN":
						var main_root := get_node_or_null("Main")
						if main_root != null:
							hits.append(main_root)
					elif part == "FxLayer" or part == "HUD" or part == "Monsters":
						for c in main_node.get_children():
							if c.name == part:
								hits.append(c)
					else:
						for c in main_node.get_children():
							var hit := false
							match part:
								"WorldDeco": hit = c is WorldDeco
								"ObstacleTileLayer": hit = c is ObstacleTileLayer
								"NavTileLayer": hit = c is NavTileLayer
								"VisionLighting": hit = c is VisionLighting
								"Tutorial": hit = c is Tutorial
								"ChunkStreamer": hit = c is ChunkStreamer
							if hit:
								hits.append(c)
					if hits.is_empty():
						print(">>> 未匹配到 %s" % part)
					for node in hits:
						node.process_mode = Node.PROCESS_MODE_DISABLED
						if node is CanvasItem:
							(node as CanvasItem).visible = false
						print(">>> t=%.1f 已停用 %s（%s）" % [_elapsed, part, node.name])
	# 2s 起按住右移（移动 + 相机跟随 + 跨界流式）
	if _elapsed >= 2.0 and not Input.is_action_pressed("move_right"):
		Input.action_press("move_right")
	# 6s 起 0.2s 脉冲普攻（战斗负载：命中/受击/特效/顿帧）；
	# HOTW_PROBE_NOATTACK=1 关脉冲（分离"战斗事件链"与"怪物常驻"两类负载）
	if _elapsed >= 6.0 and OS.get_environment("HOTW_PROBE_NOATTACK") != "1":
		_attack_pulse += delta
		if _attack_pulse >= 0.2:
			_attack_pulse = 0.0
			if Input.is_action_pressed("attack"):
				Input.action_release("attack")
			else:
				Input.action_press("attack")
	# 定时传送：逼出跨块重建尖峰
	if _teleport_i < TELEPORT_AT.size() and _elapsed >= TELEPORT_AT[_teleport_i]:
		_teleport_i += 1
		var player := get_tree().get_first_node_in_group("player")
		if player != null:
			player.global_position += Vector2(700.0, 120.0)
	_sample_accum += delta
	if _sample_accum >= SAMPLE_INTERVAL:
		_sample_accum = 0.0
		# 怪物剖析累计器差分（近圈/远档/动画/导航，ms 与调用数）
		var f2 := FileAccess.open("/tmp/hotw_perf_monsters.csv", FileAccess.READ_WRITE if FileAccess.file_exists("/tmp/hotw_perf_monsters.csv") else FileAccess.WRITE)
		if f2 != null:
			f2.seek_end()
			f2.store_line("%.1f,%.2f,%d,%.2f,%d,%.2f,%d,%.2f,%d" % [_elapsed,
				MonsterBase.prof_phys_ms, MonsterBase.prof_phys_n,
				MonsterBase.prof_far_ms, MonsterBase.prof_far_n,
				MonsterBase.prof_anim_ms, MonsterBase.prof_anim_n,
				MonsterBase.prof_nav_ms, MonsterBase.prof_nav_n])
		var row := [
			_elapsed,
			Engine.get_frames_per_second(),
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			get_tree().get_nodes_in_group("monsters").size(),
		]
		_rows.append(row)
		var f := FileAccess.open(OUT_CSV, FileAccess.READ_WRITE if FileAccess.file_exists(OUT_CSV) else FileAccess.WRITE)
		if f != null:
			f.seek_end()
			f.store_line(",".join(row.map(func(v): return str(v))))


func _finish() -> void:
	# 预热期（前 4s）不入统计；teleport 后 1.5s 的行单独标注为尖峰区
	print("== 采样明细（t / fps / proc_ms / phys_ms / draws / objects / monsters）==")
	for i in _rows.size():
		var r: Array = _rows[i]
		var tag := ""
		for tp in TELEPORT_AT:
			if float(r[0]) > tp and float(r[0]) <= tp + 1.5:
				tag = "  ← 跨块尖峰"
		print("t=%5.1f  fps=%3d  proc=%5.2f  phys=%5.2f  draws=%4d  obj=%4d  mon=%3d%s" % [
			r[0], r[1], r[2], r[3], r[4], r[5], r[6], tag])
	var steady: Array = _rows.filter(func(r): return float(r[0]) >= 4.0)
	if steady.is_empty():
		print("无有效采样")
		get_tree().quit(0)
		return
	var fps_min := 1e9
	var proc_max := -1.0
	var phys_max := -1.0
	var draws_max := -1.0
	var proc_sum := 0.0
	var phys_sum := 0.0
	var draws_sum := 0.0
	for r in steady:
		fps_min = min(fps_min, r[1])
		proc_max = max(proc_max, r[2])
		phys_max = max(phys_max, r[3])
		draws_max = max(draws_max, r[4])
		proc_sum += r[2]
		phys_sum += r[3]
		draws_sum += r[4]
	var n := float(steady.size())
	print("== 汇总（t≥4s 稳态窗，n=%d）==" % steady.size())
	print("fps_min=%d  proc_avg=%.2fms proc_max=%.2fms  phys_avg=%.2fms phys_max=%.2fms  draws_avg=%.0f draws_max=%.0f" % [
		int(fps_min), proc_sum / n, proc_max, phys_sum / n, phys_max, draws_sum / n, draws_max])
	print("night=%s  res=%s" % [OS.get_environment("HOTW_PROBE_NIGHT") == "1",
			str(get_viewport().get_visible_rect().size)])
	get_tree().quit(0)
