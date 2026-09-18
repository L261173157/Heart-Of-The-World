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
signal player_skills_changed(dash_cd: float, heavy_cd: float, bolt_cd: float, heal_cd: float, empower_cd: float, mp: float, max_mp: float)
## 玩家跨区域（game_world 区域 Area2D 信号 + 滞回确认后发出）
signal player_entered_region(region_id: String, display_name: String)
## 高危区域预警（threat ≥ 2.2 时随进入区域发出，HUD 做红光脉冲）
signal region_threat_warning(threat: float)
## 成就解锁（achievement_manager 发出，HUD toast + 持久化由 GameState 完成）
signal achievement_unlocked(title: String)
## 昼夜切换（WorldSim 发出，night=true 入夜）
signal day_phase_changed(night: bool)
## 新的游戏日开始（WorldSim 发出，day 从 1 计数；角色寿命按天推进）
signal game_day_advanced(day: int)
## 引导/剧情播报请求（tutorial → HUD toast 呈现）
signal hint_requested(text: String)

# --- 战斗 ---
## 击杀者造成的击杀（经验/掉落在击杀方处理）；monster_name 为带精英前缀/编号的
## 展示名（飘字用），species_name 为裸物种名（赏金/图鉴/成就的结构化判定用，
## 不再由消费方解析字符串——物种名含 # 或精英条件扩展时曾三处静默断链）
signal monster_killed_by_player(xp_reward: int, gold_reward: int, monster_name: String, species_name: String)
## 飘血数字（受击位置、数值、是否玩家受伤、是否元素克制——克制时橙色加大）
signal damage_number(position: Vector2, amount: int, is_player_hurt: bool, is_effective: bool)

# --- 表现反馈（打击感） ---
## 相机震动请求（强度 ≈ 抖动像素幅度），玩家相机订阅
signal camera_shake_requested(strength: float)
## 顿帧请求（真实秒数）：game_world 压低 time_scale 后用忽略时间尺度的定时器恢复
signal hit_stop_requested(duration: float)
## Boss 顶部血条：game_world 轮询玩家附近的存活 Boss（0.25s 节流），
## HUD 据此呈现/隐藏——Boss 满血也显示，遭遇即有血量锚点（头顶小条满血不显示）
signal boss_tracked(active: bool, boss_name: String)
signal boss_hp_changed(current: float, maximum: float)

# --- 赏金任务（bounty_manager 发出，HUD 呈现） ---
signal bounty_updated(bounty_text: String)
signal bounty_completed(bounty_text: String)

# --- 世界事件（world_event_watcher 检测生态快照的戏剧性变化，HUD 播报） ---
signal world_event(text: String)
## 结构化生态事件（与 world_event 文本同源）：灭绝/复苏的成就判定用，文案改动不断链
signal species_extinct(species_name: String)
signal species_recovered(species_name: String)
## 巢穴被捣毁（激怒信号）：同物种全体侦测提升且不再逃跑，持续一段时间
signal nest_ransacked(species_name: String)

# --- 生态模拟（由 WorldSim 转发） ---
signal sim_tick_completed(summary: Dictionary)

# --- 世界 v5：探索与总览 ---
## 世界总览就绪（game_world 加载期后台栅格化完成）：ImageTexture 为按当前
## 种子生成的小地图底图，Minimap 订阅替换占位（每档世界一张，不预载 PNG）
signal world_overview_ready(texture: ImageTexture)
## 发现地标（game_world 地标 Area2D 触发，首次进入 400px 圈发出）：
## 地标 id 形如 lm_{patch}_{k}，随种子确定性稳定，可作任务锚点
signal landmark_discovered(landmark_id: String, patch_id: String, kind: String, world_pos: Vector2)
## 障碍被玩家摧毁（ObstacleField 真源发出）：瓦片层擦格 / 导航层补可走格 /
## 碎屑特效 各自订阅；cell 为 32px 障碍格坐标，pos 为格中心世界坐标
signal obstacle_destroyed(cell: Vector2i, pos: Vector2, kind: String)
## 任务进度行（QuestManager 发出，HUD 任务栏呈现；空串 = 清空）
signal quest_updated(text: String)
## 任务完成结算播报
signal quest_completed(text: String)
## NPC 对话（美术 v5）：NPC 交互键触发，HUD 对话气泡呈现。payload 含
## giver（名字）/ faceset（立绘编号）/ kind（quest|info）/ text / quest（可接单）
signal npc_dialogue(payload: Dictionary)
## 对话按键路由（player 侧转发）：action = "confirm" | "decline"，HUD 消费
signal dialogue_action(action: String)
## 对话确认接单（HUD 是按钮/确认键发出）→ QuestManager.accept 结算
signal dialogue_confirmed(quest: Dictionary)
## 全局特效请求（美术 v5 fx 全量接线）：kind 见 game_world.FxLayer.TABLE，
## pos 世界坐标，scale 视觉倍率（1.0 ≈ 32px 实际尺寸）
signal fx_requested(kind: String, pos: Vector2, scale: float)

# --- 物品系统（玩法 v7）：掉落/购买/使用 ---
## 获得物品（GameState.add_item 统一发出：击杀掉落/商店购买/任务奖励）；
## count = 本次增量，total = 持有总量（HUD 战斗播报 "兽肉 ×2（共 5）" 用）
signal item_gained(item_id: String, count: int, total: int)
## 背包内容任何变化（获得/使用/售出后都发；HUD 物品栏/快捷槽的刷新源）
signal inventory_changed
## 使用消耗品请求（HUD 快捷槽/物品栏发出）→ player 订阅：满血拦截与恢复
## 应用在 player（生命/精力的权威持有者），库存扣减在 GameState
signal item_use_requested(item_id: String)
