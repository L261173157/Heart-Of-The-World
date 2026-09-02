## 全局事件总线（autoload 单例）。
## 所有跨模块通信统一走这里的信号，模块之间不允许互相直接持有引用。
## 约定：信号参数用基础类型或数据类，避免传递 Node（世界坐标 Vector2 除外）。
extends Node

# --- 玩家状态 ---
signal player_hp_changed(current: float, maximum: float)
signal player_mp_changed(current: float, maximum: float)
## 等级、当前经验、升级所需经验、可分配属性点
signal player_progress_changed(level: int, xp: int, xp_needed: int, pending_points: int)
signal gold_changed(amount: int)
signal player_died
signal player_respawned
signal player_dashed
## 技能冷却状态（冲刺/重击/法弹/治疗 的剩余冷却 + 当前蓝量），HUD 技能条订阅
signal player_skills_changed(dash_cd: float, heavy_cd: float, bolt_cd: float, heal_cd: float, mp: float, max_mp: float)
## 玩家跨区域（game_world 轮询所在区域后发出）
signal player_entered_region(region_id: String, display_name: String)
## 高危区域预警（threat ≥ 2.2 时随进入区域发出，HUD 做红光脉冲）
signal region_threat_warning(threat: float)
## 成就解锁（achievement_manager 发出，HUD toast + 持久化由 GameState 完成）
signal achievement_unlocked(title: String)
## 昼夜切换（WorldSim 发出，night=true 入夜）
signal day_phase_changed(night: bool)
## 引导/剧情播报请求（tutorial → HUD toast 呈现）
signal hint_requested(text: String)

# --- 战斗 ---
## 击杀者造成的击杀（经验/掉落在击杀方处理），monster_name 用于飘字等表现
signal monster_killed_by_player(xp_reward: int, gold_reward: int, monster_name: String)
## 飘血数字（受击位置、数值、是否玩家受伤、是否元素克制——克制时橙色加大）
signal damage_number(position: Vector2, amount: int, is_player_hurt: bool, is_effective: bool)

# --- 表现反馈（打击感） ---
## 相机震动请求（强度 ≈ 抖动像素幅度），玩家相机订阅
signal camera_shake_requested(strength: float)
## 顿帧请求（真实秒数）：game_world 压低 time_scale 后用忽略时间尺度的定时器恢复
signal hit_stop_requested(duration: float)

# --- 赏金任务（bounty_manager 发出，HUD 呈现） ---
signal bounty_updated(bounty_text: String)
signal bounty_completed(bounty_text: String)

# --- 世界事件（world_event_watcher 检测生态快照的戏剧性变化，HUD 播报） ---
signal world_event(text: String)
## 巢穴被捣毁（激怒信号）：同物种全体侦测提升且不再逃跑，持续一段时间
signal nest_ransacked(species_name: String)

# --- 生态模拟（由 WorldSim 转发） ---
signal sim_tick_completed(summary: Dictionary)
