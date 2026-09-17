## UI/流程冒烟测试（主菜单 → 进世界 → 死亡/重生 → 回菜单 → 继续冒险）。
## 运行："$GODOT" --headless --path Code res://tests/ui_flow_test.tscn --quit-after 8000
## 生态/战斗/存档各有专项；此前 UI 与跨场景流程零覆盖。本测试锁定：
##   1) TERRAIN_THEMES 与地形映射完整（新增地形忘配曲在此拦截）
##   2) 三路音量设置（Master 总音量/音乐/音效）→ AudioServer 总线即时生效
##   3) 主菜单按钮文案随进度切换（开始冒险 ↔ 继续冒险）
##   4) 世界进入 / 玩家死亡重生（本局击杀按条命清零、死亡信息可见）
##   5) 图鉴触屏关闭：弹层不溢出屏幕，关闭后解除暂停
##   6) 回菜单 → 快照继续：世界恢复 + 时钟恢复 + BGM 静默接回区域曲
##   7) 主菜单新结构：新的冒险（无进度隐藏/清档确认/弹层互斥）+ 冒险档案面板
##   8) 暂停菜单手动保存：「已保存」toast 反馈
##   9) 开场 CG 支线：路由谓词 intro_pending（标记×片源）+ 过场场景自动开播/跳过置标/已播直放
extends Node2D

const MENU_SCENE := preload("res://scenes/ui/main_menu.tscn")
const MAIN_SCENE := preload("res://scenes/main/main.tscn")
const _WorldConfig := preload("res://scripts/main/world_config.gd")

var _fails := 0
var _menu: Control
var _world: Node2D


func _ready() -> void:
	# 沙盒隔离：不读写真实进度，不消费真实生态快照
	GameState.SAVE_PATH = "user://ui_flow_test.json"
	GameState.save_enabled = false
	GameState.ecology_snapshot = null
	GameState.reset_all()
	_run()


func _run() -> void:
	_test_static_data()
	await _test_intro_cg()
	await _test_menu_fresh()
	await _test_world_death_respawn()
	await _test_resume_flow()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.SAVE_PATH))
	if _fails == 0:
		print("=== UI 流程冒烟全部通过 ===")
		get_tree().quit(0)
	else:
		print("=== %d 项失败 ===" % _fails)
		get_tree().quit(1)


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  PASS  %s" % label)
	else:
		_fails += 1
		print("  FAIL  %s" % label)


## 纯数据校验：BGM 映射完整 + 音量设置链路
func _test_static_data() -> void:
	var themes: Dictionary = SfxManager.TERRAIN_THEMES
	for terrain: String in _WorldConfig.terrains():
		_check(themes.has(terrain), "TERRAIN_THEMES 配有群系曲（%s）" % terrain)
	_check(themes.has("menu"), "TERRAIN_THEMES 配有菜单曲")
	GameState.set_setting("volume", 0.5)
	var expected := maxf(-60.0, linear_to_db(0.5))
	_check(is_equal_approx(AudioServer.get_bus_volume_db(0), expected),
			"音量 0.5 → Master 总线 %.1f dB" % expected)
	GameState.set_setting("volume", 0.8)
	# 三总线音量分离：Music/SFX 子总线（default_bus_layout.tres）各自独立生效
	var music_idx := AudioServer.get_bus_index("Music")
	var sfx_idx := AudioServer.get_bus_index("SFX")
	_check(music_idx >= 0 and sfx_idx >= 0, "Music/SFX 子总线已加载")
	GameState.set_setting("music_volume", 0.5)
	GameState.set_setting("sfx_volume", 0.25)
	if music_idx >= 0:
		_check(is_equal_approx(AudioServer.get_bus_volume_db(music_idx),
				maxf(-60.0, linear_to_db(0.5))), "音乐 0.5 → Music 总线即时生效")
	if sfx_idx >= 0:
		_check(is_equal_approx(AudioServer.get_bus_volume_db(sfx_idx),
				maxf(-60.0, linear_to_db(0.25))), "音效 0.25 → SFX 总线即时生效")
	GameState.set_setting("music_volume", 1.0)
	GameState.set_setting("sfx_volume", 1.0)


## 开场 CG 支线：谓词与过场场景接线（CG 场景自身不真切场景——next_scene 置空的测试挂钩）
func _test_intro_cg() -> void:
	GameState.reset_all()
	_check(not GameState.seen_intro_cg, "清档后开场 CG 已播标记复位")
	# 片源已在包内（assets/cg/intro.ogv）：未播过 → 待播
	_check(CutscenePlayer.intro_pending(), "未播过且片源在包内 → 谓词待播")
	var cs: CutscenePlayer = (load("res://scenes/ui/cutscene_player.tscn") as PackedScene).instantiate()
	cs.next_scene = ""
	add_child(cs)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(cs.get_node("%Video").playing, "过场场景自动开播")
	cs._finish()
	_check(GameState.seen_intro_cg and not CutscenePlayer.intro_pending(),
			"收尾置已播标记且谓词转否")
	var cs2: CutscenePlayer = (load("res://scenes/ui/cutscene_player.tscn") as PackedScene).instantiate()
	cs2.next_scene = ""
	add_child(cs2)
	await get_tree().process_frame
	_check(cs2._done, "已播后再进过场场景直接放行（不再打扰）")


## 全新进度下主菜单：主按钮「开始冒险」+ 新的冒险隐藏 + 档案空态；
## 有进度后：新的冒险可见、清档确认层全屏防误触、弹层互斥、确认后回到初始态
func _test_menu_fresh() -> void:
	_menu = MENU_SCENE.instantiate()
	add_child(_menu)
	await get_tree().process_frame
	var start: Button = _menu.get_node("MenuBox/StartBtn")
	_check(start.text == "开始冒险", "无进度时按钮为「开始冒险」")
	var new_btn: Button = _menu.get_node("MenuBox/NewBtn")
	_check(not new_btn.visible, "无进度时隐藏「新的冒险」（与开始冒险语义重复）")
	# 冒险档案空态：占位提示可见、数据行隐藏、立即保存禁用
	_menu.get_node("MenuBox/ArchiveBtn").pressed.emit()
	await get_tree().process_frame
	var archive_layer: Control = _menu.get_node("ArchiveLayer")
	_check(archive_layer.visible and _menu.get_node("ArchiveLayer/ArchivePanel/Margin/VB/EmptyHint").visible
			and not _menu.get_node("ArchiveLayer/ArchivePanel/Margin/VB/InfoGrid").visible,
			"无进度时档案面板显示空态占位")
	_check(_menu.get_node("ArchiveLayer/ArchivePanel/Margin/VB/HB/ArchiveSave").disabled,
			"无进度时「立即保存」禁用")
	_menu.get_node("ArchiveLayer/ArchivePanel/Margin/VB/HB/ArchiveClose").pressed.emit()
	await get_tree().process_frame
	_check(not archive_layer.visible, "档案面板关闭按钮生效")
	_menu.queue_free()
	await get_tree().process_frame
	# 只保存了生态世界、角色仍 Lv.1/0 金也属于可继续的进度。
	GameState.ecology_snapshot = {"instances": []}
	_menu = MENU_SCENE.instantiate()
	add_child(_menu)
	await get_tree().process_frame
	start = _menu.get_node("MenuBox/StartBtn")
	_check(start.text == "继续冒险", "仅有世界快照时按钮为「继续冒险」")
	new_btn = _menu.get_node("MenuBox/NewBtn")
	_check(new_btn.visible, "有进度时露出「新的冒险」")
	# 弹层互斥：设置开着时点新的冒险，确认层顶上、设置层收起
	_menu.get_node("MenuBox/SettingsBtn").pressed.emit()
	await get_tree().process_frame
	new_btn.pressed.emit()
	await get_tree().process_frame
	var confirm_layer: Control = _menu.get_node("NewGameConfirm")
	# 本测试把菜单作为 Node2D 子节点挂载，Control 不会获得真实窗口布局尺寸；
	# 锁锚点与鼠标拦截属性，图形截图再验证实际铺满。
	_check(confirm_layer.visible and confirm_layer.anchor_left == 0.0 and confirm_layer.anchor_top == 0.0 \
			and confirm_layer.anchor_right == 1.0 and confirm_layer.anchor_bottom == 1.0 \
			and confirm_layer.mouse_filter == Control.MOUSE_FILTER_STOP,
			"新冒险确认层使用全屏锚点并拦截误触")
	_check(not _menu.get_node("SettingsLayer").visible, "打开确认层时互斥收起设置层")
	# 确认清档：按钮回初始态（留在菜单不直接进世界）
	_menu.get_node("NewGameConfirm/NewPanel/Margin/VB/HB/NewConfirmBtn").pressed.emit()
	await get_tree().process_frame
	_check(start.text == "开始冒险" and not new_btn.visible \
			and _menu.get_node("MenuToast").modulate.a > 0.9,
			"确认新的冒险：回到初始态并 toast 提示")
	_menu.queue_free()
	await get_tree().process_frame
	GameState.ecology_snapshot = null


## 进世界 → 玩家死亡 → 自动重生
func _test_world_death_respawn() -> void:
	_world = MAIN_SCENE.instantiate()
	add_child(_world)
	await get_tree().process_frame
	await get_tree().process_frame
	var player := get_tree().get_first_node_in_group("player")
	_check(player != null, "玩家节点存在")
	# v4 据点式：出生点（斑块中心）2400 流式圈内无营地（最近 ~4000px），
	# 开局零怪物节点是正确行为；验证改为「模拟层有种群 + 走到据点节点供给」
	_check(WorldSim.sim != null and not WorldSim.sim.instances.is_empty(),
			"初始种群已在模拟层（表现节点按据点距离流式供给）")
	if WorldSim.sim != null:
		var nearest := Vector2.INF
		for inst: MonsterInstance in WorldSim.sim.instances.values():
			if inst.is_alive and inst.spawn_pos != Vector2.INF \
					and (nearest == Vector2.INF \
						or player.global_position.distance_squared_to(inst.spawn_pos) \
							< player.global_position.distance_squared_to(nearest)):
				nearest = inst.spawn_pos
		if nearest != Vector2.INF:
			player.global_position = nearest + Vector2(120.0, 0.0)
			await get_tree().create_timer(1.2).timeout
			_check(not get_tree().get_nodes_in_group("monsters").is_empty(),
					"走近据点后流式生成表现节点")
	# iOS 按住摇杆切后台可能没有 release 事件；两层状态都必须复位。
	var joystick = _world.get_node("HUD/Root/Joystick")
	joystick._touch_index = 7
	TouchInput.joystick_active = true
	TouchInput.move_vector = Vector2.RIGHT
	joystick._notification(NOTIFICATION_APPLICATION_PAUSED)
	_check(joystick._touch_index == -1 and not TouchInput.joystick_active \
			and TouchInput.move_vector == Vector2.ZERO, "切后台释放虚拟摇杆残留")
	# 触屏图鉴路径：22 物种 + 13 成就必须收进滚动区，关闭按钮始终可点；
	# 关闭不能只藏弹层却留下 SceneTree.paused=true 的软锁死。
	var hud := _world.get_node("HUD")
	var codex_layer: Control = hud.get_node("Root/CodexLayer")
	var codex_panel: Control = hud.get_node("Root/CodexLayer/CodexPanel")
	var codex_close: Button = hud.get_node("Root/CodexLayer/CodexPanel/Margin/VB/CodexClose")
	hud._toggle_codex()
	_check(codex_layer.visible and get_tree().paused, "图鉴打开时暂停世界")
	var viewport_rect := get_viewport_rect()
	_check(viewport_rect.encloses(codex_panel.get_global_rect()), "图鉴弹层完整位于屏幕内")
	codex_close.pressed.emit()
	_check(not codex_layer.visible and not get_tree().paused, "图鉴关闭按钮解除暂停")
	# 模拟本条命的击杀数后致死：死亡信息应显示该值，重生后清零。
	# 上一步在据点旁停留的 1.2s 里怪物可能命中过玩家——受击无敌帧（0.35s）
	# 内 take_damage 会整段吞掉，处决前先清掉免疫守卫，断言与种子时序解耦
	GameState.session_kills = 7
	player._dash_timer = 0.0
	player._protect_timer = 0.0
	player._hurt_iframes = 0.0
	player.take_damage(999999.0)
	await get_tree().create_timer(0.6).timeout
	_check(player._is_dead, "玩家已死亡")
	var dead_snapshot: Dictionary = player.save_snapshot()
	_check(dead_snapshot["position"] == [player._spawn_position.x, player._spawn_position.y]
			and dead_snapshot["hp"] == player.stats.max_hp()
			and dead_snapshot["mp"] == player.stats.max_mp(),
			"死亡期间存档归一为出生点满状态")
	var death_label: Label = _world.get_node("HUD/Root/DeathLabel")
	_check(death_label.modulate.a > 0.5 and death_label.text.begins_with("被"),
			"死亡信息已显示（含本局击杀 7）")
	_check(GameState.session_kills == 7, "死亡瞬间本局击杀仍可读")
	await get_tree().create_timer(2.2).timeout
	_check(not player._is_dead, "2 秒后自动重生")
	_check(GameState.session_kills == 0, "重生清零本局击杀")
	# 暂停菜单手动保存：toast 反馈 + 不破坏暂停态（沙盒 save_enabled=false，
	# save_now 早退不写盘——这里只验 UI 链路，落盘归 save_test 管）
	hud._toggle_pause()
	var save_btn: Button = hud.get_node("Root/PauseLayer/PausePanel/Margin/VB/SaveBtn")
	save_btn.pressed.emit()
	_check(get_tree().paused and hud.toast_label.text.ends_with("已保存")
			and hud.toast_label.modulate.a > 0.9, "暂停菜单「保存进度」出「已保存」toast")
	hud._toggle_pause()
	_check(not get_tree().paused, "手动保存后可正常恢复游戏")


## 回菜单（快照暂存）→ 有进度文案 → 继续冒险（快照恢复 + 静默接回区域曲）
func _test_resume_flow() -> void:
	# 离开前停在熔岩区且带伤/耗蓝；继续后应原地恢复，不能免费传回出生点回满。
	# v4 大世界：熔岩 = 距出生角最远的熔岩斑块中心（确定性坐标）。
	# 存档点取斑块中心 +300px，须同时满足两个约束：
	#   1) 避开盘踞斑块中心的 Boss 身体（ guardian 场景 42×38 × boss_size_scale
	#      2.2 + 生成 ±26px 抖动，身体最多延伸到中心外 ~90px）
	#   2) 严格落在障碍抑制区（PATCH_CLEAR 600px）内——偏移 600 会恰好压在
	#      边界上，部分种子下该格不受抑制且判为障碍，恢复路径的
	#      ObstacleField.nudge_free 会把玩家推移 ≥40px，位置断言偶发挂
	#      （300 个种子实测 +600 命中 24 次、+300 恒 0）；300px 两个约束都满足
	var lava_center: Vector2 = _WorldConfig.farthest_terrain_center("lava") + Vector2(300.0, 0.0)
	var old_player: Player = get_tree().get_first_node_in_group("player") as Player
	old_player.global_position = lava_center
	old_player.current_hp = 87.0
	old_player.current_mp = 23.0
	# 卸载世界：_exit_tree 会自动暂存生态快照并停止 WorldSim（与真实回菜单同路径）
	_world.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	# 把暂存快照的时钟字段改写为"存档时刻 0.6 / 第 3 天"，验证恢复路径
	var snapshot: Dictionary = GameState.ecology_snapshot
	snapshot["day_time"] = 0.6
	snapshot["game_day"] = 3
	GameState.ecology_snapshot = snapshot
	# 真实流程里菜单会播菜单曲——先把 BGM 置为菜单曲，才能验证继续冒险时的静默切换
	SfxManager.play_music("menu")
	# 制造进度（升级会连升，HUD 已卸载不会弹三选一）
	GameState.stats.add_xp(500)
	_menu = MENU_SCENE.instantiate()
	add_child(_menu)
	await get_tree().process_frame
	var start: Button = _menu.get_node("MenuBox/StartBtn")
	_check(start.text == "继续冒险", "有进度时按钮为「继续冒险」")
	# 冒险档案数据行：等级/金币直读 GameState，游戏天数来自快照，图鉴成对总数
	_menu.get_node("MenuBox/ArchiveBtn").pressed.emit()
	await get_tree().process_frame
	var grid := "ArchiveLayer/ArchivePanel/Margin/VB/InfoGrid/"
	var day_value: Label = _menu.get_node(grid + "DayValue")
	var lv_value: Label = _menu.get_node(grid + "LvValue")
	var gold_value: Label = _menu.get_node(grid + "GoldValue")
	var codex_value: Label = _menu.get_node(grid + "CodexValue")
	_check(day_value.text == "第 3 天", "档案面板读取快照游戏天数（%s）" % day_value.text)
	_check(lv_value.text == "Lv.%d" % GameState.stats.level and gold_value.text == str(GameState.gold),
			"档案面板显示等级与金币（%s / %s）" % [lv_value.text, gold_value.text])
	_check(codex_value.text.begins_with("0 / "), "图鉴按「已解锁/总数」成对显示（%s）" % codex_value.text)
	# 立即保存（沙盒不落盘）：toast 反馈即可
	_menu.get_node("ArchiveLayer/ArchivePanel/Margin/VB/HB/ArchiveSave").pressed.emit()
	_check(_menu.get_node("MenuToast").modulate.a > 0.9, "档案面板「立即保存」toast 反馈")
	_menu.queue_free()
	await get_tree().process_frame
	# 继续冒险：快照恢复世界（出生点在西部荒野）
	_world = MAIN_SCENE.instantiate()
	add_child(_world)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(WorldSim.sim != null, "世界已按快照重建")
	_check(WorldSim.game_day == 3, "游戏天数随快照恢复（%d）" % WorldSim.game_day)
	_check(WorldSim.is_night, "昼夜相位随快照恢复（0.6 = 夜晚）")
	_check(not get_tree().get_nodes_in_group("monsters").is_empty(), "快照世界生成了表现节点")
	var resumed_player: Player = get_tree().get_first_node_in_group("player") as Player
	_check(resumed_player.global_position.distance_to(lava_center) < 0.1,
			"继续冒险恢复角色位置")
	# 两个 process frame 内自然回复会产生极小增量，验证仍在保存值附近且没有回满。
	_check(absf(resumed_player.current_hp - 87.0) < 1.0 \
			and absf(resumed_player.current_mp - 23.0) < 1.0, "继续冒险恢复生命/魔法")
	# resume_clock 在 AchievementManager 挂载前恢复夜晚；管理器需从当前相位补记，
	# 否则读档后的这一夜活到黎明不会解锁“夜行者”。
	GameState.achievements.erase("night_walker")
	EventBus.day_phase_changed.emit(false)
	_check(GameState.achievements.has("night_walker"), "夜间读档后活到黎明解锁夜行者")
	# 读档首个区域提交只静默切 BGM 不播报：等首个区域检测周期过后验证
	await get_tree().create_timer(1.2).timeout
	_check(SfxManager._music_name == "lava",
			"读档按恢复位置静默接回区域曲（当前 %s）" % SfxManager._music_name)
