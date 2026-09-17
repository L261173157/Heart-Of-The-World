## 视觉截图工具（图形模式运行，非 headless）：
##   "$GODOT" --path Code res://tests/screenshot.tscn
## 加载主场景跑 3 秒（怪物生成、粒子出现）后截全屏存 /tmp/hotw_shot.png；
## 0.35s 后再截一张 /tmp/hotw_shot_b.png（帧差对比可验证行走动画确实在播）。
## HOTW_SHOT_UI="codex" 可在同一视口截取图鉴弹层，验证长内容滚动与安全区。
## HOTW_SHOT_UI="menu" 截主菜单：首帧完整菜单，次帧打开冒险档案面板。
extends Node2D

const MAIN_SCENE := preload("res://scenes/main/main.tscn")
const MENU_SCENE := preload("res://scenes/ui/main_menu.tscn")
const OUT_PATH := "/tmp/hotw_shot.png"
const OUT_PATH_B := "/tmp/hotw_shot_b.png"
const DELAY := 3.0
const SECOND_DELAY := 0.35

var _elapsed := 0.0
var _shot_a := false
var _shot_b := false
var _ui_opened := false
var _menu_mode := false
var _menu: Control
## HOTW_SHOT_FIGHT=1：2.2s 起贴近最近怪（优先远程兵种）连续脉冲普攻——
## 逼出怪物血条与弹幕反击，供配色/瞬态特效取证
var _fight := false
var _fight_started := false
var _fight_pulse := 0.0
var _fight_target: Node2D = null
## HOTW_SHOT_PROBE=1：程序件配色取证——确定性在玩家脚边摆出
## 巢穴(NestNode)+怪物血条(压到60%)+慢速弹幕(projectile)三件套
var _probe := false
var _probe_done := false
var _probe_proj: Node2D = null
var _dbg_accum := 0.0
## HOTW_SHOT_UI="overlays"：世界内 HUD 弹层逐态取证（常规模式拍不到的状态）——
## 属性点按钮+任务行+Boss 顶条 → 商店 → 暂停菜单 → 暂停内设置 → 生态面板收起 →
## 死亡信息 → 升级三选一，输出 /tmp/hotw_ov_1..7.png，拍完自动退出
var _overlays := false
var _ov_step := 0
var _ov_pending := ""
var _ov_wait := 0.0
## HOTW_SHOT_UI="menu_layers"：主菜单弹层取证——设置面板 / 清档确认层，
## 输出 /tmp/hotw_ml_1..2.png（与 menu 模式同构的伪造进度，确保新冒险钮可见）
var _menu_layers := false


func _ready() -> void:
	# 打开图鉴会暂停 SceneTree；截图驱动本身必须继续处理才能完成取证和退出。
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 沙盒隔离（世界装配前）：不消费真实存档生态快照、不落盘测试进度
	GameState.save_enabled = false
	_fight = OS.get_environment("HOTW_SHOT_FIGHT") == "1"
	_probe = OS.get_environment("HOTW_SHOT_PROBE") == "1"
	_menu_mode = OS.get_environment("HOTW_SHOT_UI") == "menu"
	_menu_layers = OS.get_environment("HOTW_SHOT_UI") == "menu_layers"
	_overlays = OS.get_environment("HOTW_SHOT_UI") == "overlays"
	if _menu_mode or _menu_layers:
		# 菜单取证：伪造进度（不落盘），让"继续冒险/新的冒险/档案数据"全部就位
		GameState.ecology_snapshot = {"game_day": 7, "instances": []}
		GameState.stats.level = 6
		GameState.gold = 233
		GameState.last_save_unix = Time.get_unix_time_from_system() - 300.0
		GameState.save_enabled = false
		_menu = MENU_SCENE.instantiate()
		add_child(_menu)
		# 本工具根是 Node2D，不给子 Control 布局（菜单锚点参考矩形为 0）——
		# 真实游戏里菜单是主场景由视口铺满；这里手动铺满复现同等布局
		_menu.position = Vector2.ZERO
		_menu.size = get_viewport_rect().size
		return
	GameState.ecology_snapshot = null
	add_child(MAIN_SCENE.instantiate())
	# 传送玩家到首只怪物旁（相机平滑跟随 0.5s 内到位），确保截图内有怪物可评审；
	# 环境变量 HOTW_SHOT_POS="x,y" 指定世界坐标（v4 大世界 80 万见方）。世界种子
	# 每档重掷，固定坐标会过期——各群系采样点用
	# `"$GODOT" --headless --path Code -s tools/convex_probe.gd -- sample [种子]` 现取
	var monsters := get_tree().get_nodes_in_group("monsters")
	var player := get_tree().get_first_node_in_group("player")
	# HOTW_SHOT_NIGHT=1：强制满夜（世界 v5 提灯+障碍阴影取证；day_time 0.68 落在
	# night_intensity 满档区间，无黎明渐出干扰）
	if OS.get_environment("HOTW_SHOT_NIGHT") == "1":
		WorldSim.resume_clock(0.68, WorldSim.game_day)
	if player != null:
		var pos_arg := OS.get_environment("HOTW_SHOT_POS")
		var dungeon_arg := OS.get_environment("HOTW_SHOT_DUNGEON")
		if dungeon_arg != "":
			# Boss 城塞取证：运行时按当前世界种子自取城塞中心（固定坐标会过期，
			# 本模式永远指向真城塞；索引 0=hill 1=lava）
			var dgs := ObstacleField.dungeons()
			if not dgs.is_empty():
				var idx := clampi(dungeon_arg.to_int(), 0, dgs.size() - 1)
				# "in" 后缀 = 落进场内中心（拍 Boss/宝箱同屏）；默认南门外上方拍全景
				if dungeon_arg.ends_with("in"):
					idx = clampi(dungeon_arg.trim_suffix("in").to_int(), 0, dgs.size() - 1)
					player.global_position = dgs[idx]["center"] + Vector2(0, 40)
				else:
					player.global_position = dgs[idx]["center"] + Vector2(0, 260)
		elif pos_arg.contains(","):
			var xy := pos_arg.split(",")
			player.global_position = Vector2(float(xy[0]), float(xy[1]))
		elif not monsters.is_empty():
			player.global_position = monsters[0].global_position + Vector2(64.0, 24.0)


func _process(delta: float) -> void:
	_elapsed += delta
	if _menu_layers:
		_process_menu_layers()
		return
	if _dbg_accum >= 0.25:
		_dbg_accum = 0.0
		# HOTW_SHOT_DEBUG=1 时每 0.25s 打印怪物组/玩家/种子诊断（流式问题排查用）
		if OS.get_environment("HOTW_SHOT_DEBUG") == "1":
			var pl := get_tree().get_first_node_in_group("player")
			var hp := -1.0
			var vis := false
			if pl != null:
				hp = float(pl.get("current_hp"))
				vis = (pl as Node2D).visible
			print("dbg t=%.2f monsters=%d player_vis=%s hp=%.0f pos=%.0f,%.0f paused=%s seed=%d terrain=%s day=%.3f night=%.2f" % [_elapsed,
					get_tree().get_nodes_in_group("monsters").size(), vis, hp,
					(pl as Node2D).global_position.x if pl != null else -1.0,
					(pl as Node2D).global_position.y if pl != null else -1.0,
					get_tree().paused, GameState.world_seed,
					BiomeMap.terrain_at((pl as Node2D).global_position) if pl != null else "?",
					WorldSim.day_time, WorldSim.night_intensity()])
	_dbg_accum += delta
	if not _ui_opened and _elapsed >= 2.6 and OS.get_environment("HOTW_SHOT_UI") == "codex":
		var hud := get_tree().get_first_node_in_group("hud")
		if hud == null:
			# HUD 当前未登记组名，按截图场景的固定结构兜底定位。
			hud = get_node_or_null("Main/HUD")
		if hud != null:
			hud._toggle_codex()
		_ui_opened = true
	# 2s 起按住右移：截图时刻玩家处于行走循环中（验证帧动画），邻近怪会追击；
	# 战斗/探针取证模式例外（要贴身输出或站桩摆件，不能走开）
	if not _menu_mode and not _fight and not _probe and not _overlays \
			and _elapsed >= 2.0 and not Input.is_action_pressed("move_right"):
		Input.action_press("move_right")
	# 探针模式：2.2s 起轮询等流式怪物就绪（最多 2.8s）再摆出
	# 巢穴+血条+弹幕 三件套（确定性，不依赖 AI 走位）
	if _probe and not _probe_done and _elapsed >= 2.2:
		var monsters := get_tree().get_nodes_in_group("monsters")
		var player := get_tree().get_first_node_in_group("player") as Node2D
		if not monsters.is_empty() or _elapsed >= 3.8:
			_probe_done = true
			print("探针: monsters=", monsters.size(), " player=", player != null)
			if player != null and not monsters.is_empty():
				var m0 := monsters[0] as MonsterBase
				if m0 != null and m0.inst != null:
					player.global_position = m0.global_position + Vector2(70.0, 18.0)
					# 血条：压到 60% 触发显示
					m0.current_hp = m0.inst.max_hp() * 0.6
					if m0.get("_hp_bar") != null:
						(m0.get("_hp_bar") as MonsterHpBar).notify_change()
					# 巢穴：怪脚边（物种 tint 同源）
					var nest := NestNode.new()
					get_tree().current_scene.add_child(nest)
					nest.setup("probe", m0.inst.species.species_name,
							m0.inst.species.tint, m0.global_position + Vector2(-110.0, 34.0))
					print("探针: player@", player.global_position, " m0@", m0.global_position,
							" nest@", nest.global_position, " tint=", m0.inst.species.tint)
	# 弹幕延迟到开拍前 0.4s 慢速生成（早生会被障碍撞毁/被走位甩出画面）
	if _probe and _probe_done and _elapsed >= 3.6 and _probe_proj == null:
		var pl := get_tree().get_first_node_in_group("player") as Node2D
		if pl != null:
			_probe_proj = preload("res://scenes/monsters/projectile.tscn").instantiate()
			get_tree().current_scene.add_child(_probe_proj)
			_probe_proj.global_position = pl.global_position + Vector2(-70.0, -10.0)
			_probe_proj.launch(Vector2.RIGHT, 1.0, 20.0, "取证")
			print("探针: 弹幕@", _probe_proj.global_position)
	# 战斗取证：2.2s 贴近目标怪（优先远程兵种逼弹幕），0.18s 脉冲连按普攻
	if _fight and _elapsed >= 2.2 and not _fight_started:
		_fight_started = true
		var monsters := get_tree().get_nodes_in_group("monsters")
		var player := get_tree().get_first_node_in_group("player") as Node2D
		if player != null and not monsters.is_empty():
			var pick: Node2D = monsters[0]
			for m in monsters:
				var mb := m as Node2D
				if mb == null or mb == pick:
					continue
				var is_soldier: bool = str((m as Node).get("inst").species.ai_archetype) == "soldier"
				var pick_soldier: bool = str((pick as Node).get("inst").species.ai_archetype) == "soldier"
				var d_new := mb.global_position.distance_to(player.global_position)
				var d_pick := pick.global_position.distance_to(player.global_position)
				if (is_soldier and not pick_soldier) or (is_soldier == pick_soldier and d_new < d_pick):
					pick = mb
			player.global_position = pick.global_position + Vector2(46.0, 10.0)
			_fight_target = pick
	# 近战逼血条后（2.6s）拉开距离当远程靶：远程兵种进入射程即吐弹幕
	if _fight and _elapsed >= 2.6 and _fight_target != null:
		var pl := get_tree().get_first_node_in_group("player") as Node2D
		if pl != null:
			pl.global_position = _fight_target.global_position + Vector2(150.0, 24.0)
		if Input.is_action_pressed("attack"):
			Input.action_release("attack")
	if _fight and _fight_started and _elapsed < 2.6:
		_fight_pulse += delta
		if _fight_pulse >= 0.18:
			_fight_pulse = 0.0
			if Input.is_action_pressed("attack"):
				Input.action_release("attack")
			else:
				Input.action_press("attack")
	# 探针模式整体延后 1s：等流式怪物稳定入场（平原点实测 3s 前后才有节点）
	var shot_delay := DELAY + (1.0 if _probe else 0.0)
	if not _shot_a and _elapsed >= shot_delay and (_probe_done or not _probe):
		_capture(OUT_PATH)
		# 城塞取证模式：打印结构实证（墙/门/宝箱/Boss 节点在场的运行时证据）
		if OS.get_environment("HOTW_SHOT_DUNGEON") != "":
			var dgs := ObstacleField.dungeons()
			for i in dgs.size():
				var dg: Dictionary = dgs[i]
				var boss: String = WorldConfig.TERRAIN_BOSSES.get(dg["terrain"], "?")
				var alive := 0
				for m in get_tree().get_nodes_in_group("monsters"):
					var mi = m.get("inst")
					if mi != null and mi.species.species_name == boss and mi.is_alive:
						alive += 1
				var chests := get_tree().get_nodes_in_group("chests").size()
				print("城塞[%d] %s@%d,%d boss=%s 活体=%d 宝箱节点=%d" % [i, dg["terrain"],
					int(dg["center"].x), int(dg["center"].y), boss, alive, chests])
		# 菜单模式次帧取证冒险档案面板（数据行 + 立即保存）
		if _menu_mode and _menu != null:
			_menu.get_node("MenuBox/ArchiveBtn").pressed.emit()
		_shot_a = true
		_elapsed = 0.0
		return
	if _shot_a and not _shot_b and _elapsed >= SECOND_DELAY:
		_capture(OUT_PATH_B)
		_shot_b = true
		if not _fight:
			get_tree().quit(0)
			return
		# 战斗取证追加第三帧：远程弹幕冷却周期常 > 0.35s，延后捕捉飞行中的弹体
		_elapsed = 0.0
		return
	if _fight and _shot_b and _elapsed >= 0.7:
		_capture("/tmp/hotw_shot_c.png")
		get_tree().quit(0)


func _capture(path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("截图已保存 %s" % path)


## 主菜单弹层取证：首帧设置面板（背后衬完整菜单），次帧清档确认层。
## 开层与截图必须错帧——同帧截屏拿到的是上一帧渲染结果（弹层还没画上去）
func _process_menu_layers() -> void:
	if not _ui_opened and _elapsed >= 3.0:
		_ui_opened = true
		_menu._toggle_settings()
		_elapsed = 0.0
		return
	if _ui_opened and not _shot_a and _elapsed >= 0.35:
		_shot_a = true
		_capture("/tmp/hotw_ml_1.png")
		return
	if _shot_a and not _shot_b and _elapsed >= 0.7:
		_shot_b = true
		_menu._toggle_settings()
		_menu._open_layer(_menu.get_node("%NewGameConfirm"))
		return
	if _shot_b and _elapsed >= 1.05:
		_capture("/tmp/hotw_ml_2.png")
		get_tree().quit(0)


## HUD 弹层逐态步进：每步改状态 → 等 0.4s 渲染稳定 → 截图 → 下一步开头还原，
## 步骤间互不串影；图鉴/暂停会冻结世界，驱动节点为 PROCESS_MODE_ALWAYS 不受影响
func _process_overlays(delta: float) -> void:
	if _ov_pending != "":
		_ov_wait -= delta
		if _ov_wait > 0.0:
			return
		_capture(_ov_pending)
		_ov_pending = ""
		_ov_step += 1
	var hud := _hud()
	match _ov_step:
		0:
			# HUD 三态合一：属性点按钮 + 任务行 + Boss 顶条
			GameState.stats.pending_points = 2
			hud._refresh_stats_label(GameState.stats.level, 2)
			EventBus.quest_updated.emit("委托·捣巢：摧毁荒废遗迹旁的巢穴（0/1）")
			EventBus.boss_tracked.emit(true, "龟王")
			EventBus.boss_hp_changed.emit(620.0, 1000.0)
			_ov_arm("/tmp/hotw_ov_1.png")
		1:
			EventBus.boss_tracked.emit(false, "")
			hud._toggle_shop()
			_ov_arm("/tmp/hotw_ov_2.png")
		2:
			hud._toggle_shop()
			hud._toggle_pause()
			_ov_arm("/tmp/hotw_ov_3.png")
		3:
			hud.pause_settings_layer.visible = true
			_ov_arm("/tmp/hotw_ov_4.png")
		4:
			hud.pause_settings_layer.visible = false
			hud._toggle_pause()
			hud.ecology_panel.visible = false
			_ov_arm("/tmp/hotw_ov_5.png")
		5:
			hud.ecology_panel.visible = true
			EventBus.player_died.emit()
			_ov_arm("/tmp/hotw_ov_6.png")
		6:
			GameState.stats.leveled_up.emit(GameState.stats.level + 1, 1)
			_ov_arm("/tmp/hotw_ov_7.png")
		7:
			hud._pick_passive(0)
			print("overlays 弹层取证完成（7 帧）")
			get_tree().quit(0)


func _ov_arm(path: String) -> void:
	_ov_pending = path
	_ov_wait = 0.4


func _hud() -> Node:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud == null:
		hud = get_node_or_null("Main/HUD")
	return hud
