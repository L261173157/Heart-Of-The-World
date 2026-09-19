## Main 场景根：世界装配 + 生态模拟桥接。
## 负责：从 WorldConfig/BiomeMap 装配噪声群系区域 → 启动 EcologySim（经 WorldSim
## 定时驱动）→ 把模拟信号翻译成节点生成/死亡/迁徙/消散；区域铭牌、玩家跨群系
## 检测、飘血数字。表现层只消费模拟事件，不改写模拟数据。
extends Node2D

## 物种 → 表现场景（新增种族在此登记）；Boss 复用同形物种场景（体型×2.2 表达差异）
## 六 AI 原型场景（行为脚本绑定在场景上；视觉由 SpeciesData.frames_override 换 NA 帧）
## 美术 v5：22 物种与 NA 22 张怪表一一对应
const MONSTER_SCENES := {
	"妖鬼": preload("res://scenes/monsters/goblin.tscn"),
	"红史莱姆": preload("res://scenes/monsters/slime.tscn"),
	"野猪": preload("res://scenes/monsters/boar.tscn"),
	"沼泽蟹": preload("res://scenes/monsters/spider.tscn"),
	"甲虫": preload("res://scenes/monsters/ant.tscn"),
	"石像鬼": preload("res://scenes/monsters/guardian.tscn"),
	"锹形虫王": preload("res://scenes/monsters/ant.tscn"),
	"龟王": preload("res://scenes/monsters/guardian.tscn"),
	"冰史莱姆": preload("res://scenes/monsters/slime.tscn"),
	"萌芽怪": preload("res://scenes/monsters/ant.tscn"),
	"绿蛙": preload("res://scenes/monsters/goblin.tscn"),
	"曼德拉草": preload("res://scenes/monsters/spider.tscn"),
	"蘑菇怪": preload("res://scenes/monsters/spider.tscn"),
	"红章鱼": preload("res://scenes/monsters/spider.tscn"),
	"企鹅": preload("res://scenes/monsters/boar.tscn"),
	"幽灵": preload("res://scenes/monsters/goblin.tscn"),
	"松鼠": preload("res://scenes/monsters/boar.tscn"),
	"蝙蝠": preload("res://scenes/monsters/goblin.tscn"),
	"仙人掌怪": preload("res://scenes/monsters/spider.tscn"),
	"火鸟": preload("res://scenes/monsters/spider.tscn"),
	"绿龟": preload("res://scenes/monsters/boar.tscn"),
	"树人": preload("res://scenes/monsters/boar.tscn"),
	# 物种扩容（美术 v5 完整包）：4 战斗怪 + 3 被动动物
	"雪熊": preload("res://scenes/monsters/boar.tscn"),
	"独眼巨人": preload("res://scenes/monsters/ant.tscn"),
	"眼魔": preload("res://scenes/monsters/spider.tscn"),
	"火龙": preload("res://scenes/monsters/spider.tscn"),
	"浣熊": preload("res://scenes/monsters/goblin.tscn"),
	"鸡": preload("res://scenes/monsters/goblin.tscn"),
	"鹦鹉": preload("res://scenes/monsters/goblin.tscn"),
}

## M0 初始种群与六区域布局的唯一数据源已抽至 WorldConfig（纯数据类，
## 与 sim_test 生态单测同源——测试图/真实图双源漂移自此杜绝）
## 区域进入检测（世界 v5 原生化）：斑块边界多边形 Area2D（BiomeMap.patch_polygons
## 与 region_of_point 同源栅格派生——相邻多边形无缝无重叠），body_entered/exited
## 信号驱动；滞回从"0.3s×2 次轮询确认"改为"停留 REGION_CONFIRM_SECONDS 确认"
## （贴边界抖动时 exited 即取消候选，语义等价的去抖）
const REGION_CONFIRM_SECONDS := 0.6
## 区域多边形栅格步长：边界阶梯误差 ≤ 此值，远小于 8 万 px 斑块尺度；
## 同一份栅格也用来生成小地图底图（一次采样两用）
const REGION_RASTER := 1000.0
## Boss 血条轮询：玩家附近 700px 内最近存活 Boss 顶到 HUD（4Hz 足够顺滑）
const BOSS_TRACK_INTERVAL := 0.25
const BOSS_TRACK_RANGE := 700.0
## 表现层流式生成（v4 大世界，据点式）：模拟层数据全局常驻，怪物扎根地图
## 营地（EcologySim.camp_pos 确定性据点，繁衍从营地外扩），节点只生成在
## 玩家附近——全图 ~880 实例的 Node 常驻（物理/AI/动画）在 iOS 上不可行。
## 进出只看「实例位置 vs 玩家距离」：走近据点生成、走远回收，位置不随
## 玩家漂移（MMO 语义：怪属于世界，走远再回来还在原据点）
const STREAM_RADIUS := 2400.0
const STREAM_DESPAWN := 2800.0
## 流式维护轮询间隔（待生成实例扫描 + 出界节点回收 + 巢穴进出）
const STREAM_INTERVAL := 0.5
## 近旁扫描节流（地标标记/营地回血/城塞进出，真机性能优化 2026-09-19）：
## 这些判定对 0.25s 粒度无感（回血本身 1s 一跳、城塞内腔 6 格宽），不必每帧跑
const SCAN_INTERVAL := 0.25
var _scan_accum := 0.0
## 顿帧期间的全局时间尺度（真实时间不受影响，恢复定时器忽略 time_scale）
const HIT_STOP_SCALE := 0.05
# --- 世界 v5 探索层 ---
## 迷雾揭示节奏与半径（3×3 格 = 12000px 带，与流式视距同量级）
const FOG_REVEAL_INTERVAL := 0.5
const FOG_REVEAL_RADIUS := 1
## 地标视觉标记的进出半径（发现 Area 常驻，视觉节点按需生成）
const LANDMARK_VIS_RADIUS := 1400.0

@onready var monsters: Node2D = $Monsters

## 模拟实例 id → 表现节点
var _nodes: Dictionary = {}
## 尚未生成节点的存活实例（玩家不在其斑块附近；流式进出生成）
var _pending_stream: Dictionary = {}
## 巢穴 key → NestNode（只在玩家附近的巢穴有实体）
var _nest_nodes: Dictionary = {}
## 活跃巢穴 key 集（模拟层状态镜像，流式进出的依据）
var _active_nest_keys: Dictionary = {}
var _stream_accum := 0.0
## 测试钩子：全量生成节点（旧行为）——combat 等全图搜目标的测试用
## HOTW_TEST_STREAM_ALL=1
var stream_all := false
var _sim: EcologySim
var _current_region_id := ""
## 区域候选滞回（信号驱动版）：候选区域需停留 REGION_CONFIRM_SECONDS 才提交
var _region_candidate_id := ""
var _region_candidate_time := 0.0
## 世界总览后台线程（区域多边形 + 小地图底图栅格化，~1s）
var _overview_thread: Thread = null
var _boss_accum := 0.0
## Boss 血条追踪状态（id = -1 表示未追踪；换目标/丢失才发 boss_tracked）
var _boss_tracked_id := -1
## 高危警告每区域每会话只发一次（重复进入同一高星区不再刷红光）
var _warned_regions := {}
## 读档续玩时跳过首个区域播报（"进入 平原"对刚离开这个世界的玩家是噪音；
## BGM 仍需接回区域曲，见 _process 首次提交分支）
var _skip_first_region_announce := false
## 精英诞生播报节流（真实秒）
var _last_elite_broadcast := -9999.0
## 顿帧开关（测试可关：节奏测试的 4× 加速会被顿帧恢复重置回 1.0）
var hit_stop_enabled := true
## 当前顿帧的恢复定时器：用对象身份判定哪个定时器有权恢复，
## 避免拿毫秒时钟与浮点到期时刻比较（粒度/舍入会让守卫永不成立，time_scale 卡死在低压值）
var _hit_stop_timer: SceneTreeTimer
## 飘字样式（三色）：LabelSettings 复用，避免 AoE 瞬时大量分配
var _dmg_style_normal: LabelSettings
var _dmg_style_player: LabelSettings
var _dmg_style_effective: LabelSettings
## 飘血数字对象池：Label 用完隐藏回池复用（0.7s 生命周期，密集战斗下
## 每次 new/queue_free 的分配压力可观）；池按历史峰值增长，不收缩；
## 游标轮询取用（O(1)，全忙时顶掉最早排队的一条——与旧线性扫描语义一致）
var _dmg_label_pool: Array[Label] = []
var _dmg_pool_cursor := 0
## 探索层：迷雾揭示状态 + 地标标记（id → LandmarkMarker）+ NPC（id → LandmarkNPC）
var _fog_accum := 0.0
var _fog_last_cell := Vector2i(-1, -1)
var _landmark_markers := {}
var _npc_nodes := {}
var _landmark_root: Node2D
## NPC 交互注入（QuestManager.try_accept(landmark_id, quest_kind, giver)）
var _npc_interact_fn: Callable


func _ready() -> void:
	# 世界 v5：先按存档种子配置 BiomeMap（每档全新世界）——必须先于一切
	# BiomeMap 派生（区域装配/地形绘制/总览任务），此后会话内种子不变。
	# 已摧毁障碍格随后灌回（configure 已重置 ObstacleField 运行态）
	BiomeMap.configure(GameState.world_seed)
	ObstacleField.restore_destroyed(GameState.destroyed_cells)
	# 复位触屏输入残留（按住摇杆退出/死亡瞬间的场景切换会丢失 release 事件）
	TouchInput.reset()
	stream_all = OS.get_environment("HOTW_TEST_STREAM_ALL") == "1"
	_sim = EcologySim.new()
	_sim.instance_spawned.connect(_on_instance_spawned)
	_sim.instance_died.connect(_on_instance_died)
	_sim.instance_migrated.connect(_on_instance_migrated)
	_sim.corpse_expired.connect(_on_corpse_expired)
	_sim.nest_changed.connect(_on_nest_changed)
	EventBus.damage_number.connect(_on_damage_number)
	EventBus.hit_stop_requested.connect(_on_hit_stop)
	# "本局击杀"按进入世界清零（ autoload 计数不跨局累计）
	GameState.session_kills = 0
	_dmg_style_normal = _make_dmg_style(26, Color(1, 0.95, 0.7))
	_dmg_style_player = _make_dmg_style(32, Color(1, 0.35, 0.3))
	_dmg_style_effective = _make_dmg_style(32, Color(1, 0.6, 0.15))
	# 先 start（挂到 WorldSim）再 setup：初始种群的节点生成会读 WorldSim.sim
	WorldSim.start(_sim)
	var regions := _build_regions()
	var species_list := SpeciesCatalog.build_all()
	# 生态世界跨会话恢复（存档 v2+）：有快照则重建上次的世界（种群年龄/世代/
	# 精英谱系/巢穴/Boss 重生倒计时全部连续），否则撒初始种群开新世界
	var snapshot: Variant = GameState.ecology_snapshot
	GameState.ecology_snapshot = null  # 一次性引导数据，消费即清
	var resumed := false
	if snapshot != null and typeof(snapshot) == TYPE_DICTIONARY:
		resumed = _sim.restore_from_dict(regions, species_list, snapshot)
	if not resumed:
		# 恢复失败回退新世界：restore 重放信号已生成的节点/待生成池/巢穴实体
		# 属于旧世界线（实例已不在新 sim 里，留着会变成打不死的残桩），一并清场；
		# setup 随后重建模拟状态并重放信号，表现层从零接新世界
		_discard_streamed_world()
		_sim.setup(regions, species_list, WorldConfig.initial_population())
	else:
		# 读档续玩：首个区域提交只静默切 BGM 不播报（见 _process 提交分支）
		_skip_first_region_announce = true
		# 世界时钟随快照接回（相位/天数/夜幕层与存档时一致；
		# 旧版快照无 day_time 键则维持清晨起点，与新世界同口径）
		var day_time: Variant = (snapshot as Dictionary).get("day_time", -1.0)
		if typeof(day_time) in [TYPE_FLOAT, TYPE_INT] and float(day_time) >= 0.0:
			WorldSim.resume_clock(float(day_time),
					int((snapshot as Dictionary).get("game_day", 0)))
	# 装配哨兵：世界为空从此显性——「碰不到任何怪物」类问题先看这里有没有报错。
	# 物种目录为空（资源链断裂）或撒放/恢复失败（0 活体）都在这一条里现形
	var alive_after_assembly := 0
	for inst: MonsterInstance in _sim.instances.values():
		if inst.is_alive:
			alive_after_assembly += 1
	if alive_after_assembly == 0:
		push_error("生态世界装配后 0 活体：species=%d regions=%d resumed=%s——检查种族数据目录（SpeciesCatalog）与初始种群表" % [
			species_list.size(), regions.size(), resumed])
	# 配置自检：数据错误显性化（捕食死链/寿命倒挂/habitats 拼写/迁徙窗口关闭）；
	# 幽灵物种（模拟层有、表现层无）会占区域承载却看不见打不着，赏金悬赏到它将永远无法完成
	SpeciesCatalog.validate(_sim.species_list, _sim.regions.values())
	for species: SpeciesData in _sim.species_list:
		if not MONSTER_SCENES.has(species.species_name):
			push_error("种族 %s 未在 MONSTER_SCENES 登记表现场景——它将占用承载且赏金无法完成，请补齐三步清单" % species.species_name)
	# 读档归一：xp 超阈值时读档不连升（while 在 add_xp 内，被动触发才走）——
	# 延迟到帧末（HUD/订阅者均已 ready）补跑零增量升级，赐福/属性点/寿命按真实路径补发
	if GameState.stats.xp >= GameState.stats.xp_to_next():
		_normalize_xp.call_deferred()
	_setup_world_shell()
	_spawn_region_labels()
	_setup_landmarks()
	_setup_camp()
	# 首个区域即时提交（点查询，不等总览任务/Area 建立）：读档静默接回区域曲
	# 与新开图播报的旧时序保持——Area 建立后同区域的 enter 事件被
	# "region_id == _current_region_id" 分支吸收，不会重复播报
	var player0 := get_tree().get_first_node_in_group("player") as Node2D
	if player0 != null:
		var region0: SimRegion = _sim.region_of_point(player0.global_position)
		if region0 != null:
			_commit_region(region0.id)
	# 区域 Area + 小地图底图：栅格化 ~1s 后台线程（上方 _build_regions 已把
	# BiomeMap 斑块/种子缓存填满，后台线程只读安全）；结果回主线程建物理体/纹理
	_start_overview_job()
	# 新手引导/生态事件播报（纯观察者，挂载点在 sim 就绪之后）
	add_child(Tutorial.new())
	# 赏金任务（短期目标循环，纯订阅击杀信号）
	add_child(BountyManager.new())
	# 任务系统 v1（地标 NPC 委托：狩猎/捣巢/探索；数据真源 GameState.quests）
	var quest_manager := QuestManager.new()
	add_child(quest_manager)
	_npc_interact_fn = quest_manager.offer
	# NA fx 全量通道（美术 v5 M-C）：事件侧只发 fx_requested，本层统一播条带
	var fx_layer := FxLayer.new()
	fx_layer.name = "FxLayer"
	add_child(fx_layer)
	# 世界事件监视（灭绝/入侵潮/饱和 → world_event 播报）
	add_child(WorldEventWatcher.new())
	# 成就判定（纯订阅 + GameState 持久化）
	add_child(AchievementManager.new())
	# 地表分块流式生成 + 环境装饰（装饰层先挂 chunk 信号，再同步预热脚下 3×3，
	# 保证进世界第一帧的地与装饰一起出现）
	var streamer := ChunkStreamer.new()
	streamer.name = "ChunkStreamer"
	add_child(streamer)
	add_child(WorldDeco.new())
	# 世界 v5 障碍：可见瓦片层（贴图/物理/遮挡一图三吃）+ 导航专用层。
	# y-sort 总开关：高大障碍（树冠）与怪物/玩家按 y 排序——走到树后被树冠
	# 遮挡；z≠0 的层（地表 -2/装饰 -1/飘字 50）不受影响仍在各自 z 层
	y_sort_enabled = true
	monsters.y_sort_enabled = true
	# 世界表现层延迟到树进入完成后挂载：TileMapLayer 实例在根节点 _ready 阶段
	# （树进入级联中）创建的话物理体静默不构建（视觉格照画）——combat 层内
	# 自检探针实证：早期实例永久零碰撞体，运行期新建的同脚本类层正常。
	# warmup 一并延迟：障碍层须先挂上 chunk_ready 订阅再预热首块
	_mount_stream_layers.call_deferred(streamer)
	# 立即跑一轮流式生成（读档/新开的脚下怪与巢穴不用等首个 0.5s 轮询）
	_stream_pass.call_deferred()


func _mount_stream_layers(streamer: ChunkStreamer) -> void:
	add_child(ObstacleTileLayer.new())
	add_child(NavTileLayer.new())
	# 视野光影：昼夜压暗 + 玩家提灯阴影投射（取代 HUD 全屏夜幕矩形）
	add_child(VisionLighting.new())
	streamer.warmup()
	_layer_physics_selfcheck.call_deferred()


## 延迟挂载自检：2s 后对障碍层已铺格做点查询（物理修复的回归哨兵，常态保留）。
## 子 Timer 而非 create_timer+await：SceneTree 定时器随树存活，2s 窗口内回主
## 菜单会在已释放的本节点上恢复协程（freed instance 报错）；子节点定时器随
## 世界一起释放，方法引用连接自动断开
func _layer_physics_selfcheck() -> void:
	var timer := Timer.new()
	timer.wait_time = 2.0
	timer.one_shot = true
	timer.timeout.connect(_layer_selfcheck_tick)
	add_child(timer)
	timer.start()


func _layer_selfcheck_tick() -> void:
	var layer: TileMapLayer = null
	for c in get_children():
		if c is ObstacleTileLayer:
			layer = c
			break
	if layer == null:
		return
	var cells := layer.get_used_cells()
	if cells.is_empty():
		return
	var q := PhysicsPointQueryParameters2D.new()
	q.collision_mask = 1
	q.position = (Vector2(cells[cells.size() / 2]) + Vector2(0.5, 0.5)) * 32.0
	var n := get_world_2d().direct_space_state.intersect_point(q, 4).size()
	print("MOUNTCHECK physics=", n, " cells=", cells.size())  # 障碍物理回归哨兵


## 世界外壳：深色底板（z=-3，分块未及处兜底）+ 四面边界墙。
## v4 起世界尺寸是运行期数据（WorldConfig.WORLD_SIZE），不再写死在场景里
func _setup_world_shell() -> void:
	var w := WorldConfig.WORLD_SIZE
	var base := Polygon2D.new()
	base.z_index = -3
	base.color = Color(0.08, 0.09, 0.08)
	base.polygon = PackedVector2Array([
		Vector2.ZERO, Vector2(w.x, 0), w, Vector2(0, w.y)])
	add_child(base)
	var wall_defs := [
		{"pos": Vector2(w.x / 2.0, -10.0), "size": Vector2(w.x + 40.0, 20.0)},
		{"pos": Vector2(w.x / 2.0, w.y + 10.0), "size": Vector2(w.x + 40.0, 20.0)},
		{"pos": Vector2(-10.0, w.y / 2.0), "size": Vector2(20.0, w.y + 40.0)},
		{"pos": Vector2(w.x + 10.0, w.y / 2.0), "size": Vector2(20.0, w.y + 40.0)},
	]
	for def: Dictionary in wall_defs:
		var wall := StaticBody2D.new()
		wall.position = def["pos"]
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = def["size"]
		shape.shape = rect
		wall.add_child(shape)
		add_child(wall)


func _process(delta: float) -> void:
	_boss_accum += delta
	if _boss_accum >= BOSS_TRACK_INTERVAL:
		_boss_accum = 0.0
		_update_boss_track()
	_stream_accum += delta
	if _stream_accum >= STREAM_INTERVAL:
		_stream_accum = 0.0
		_stream_primed = true
		_stream_pass()
		_update_dungeons()
	_scan_accum += delta
	if _scan_accum >= SCAN_INTERVAL:
		# 近旁扫描统一 4Hz：地标全表(~145 个)/营地/城塞每帧轮询是真机
		# 常驻负载，0.25s 粒度对这些判定无感（回血 1s 一跳、标记进出 1400px）
		var scan_delta := _scan_accum
		_scan_accum = 0.0
		_update_landmark_markers()
		_process_camp(scan_delta)
	_fog_accum += delta
	if _fog_accum >= FOG_REVEAL_INTERVAL:
		_fog_accum = 0.0
		_reveal_fog()
	# 区域候选滞回：跨区信号确认后停留 REGION_CONFIRM_SECONDS 才提交
	# （贴边界抖动时 exited 会取消候选；首次进图在 entered 里即时提交）
	if _region_candidate_id != "":
		_region_candidate_time -= delta
		if _region_candidate_time <= 0.0:
			var rid := _region_candidate_id
			_region_candidate_id = ""
			_commit_region(rid)


# --- 出生营地（美术 v5 M-B）：NA 建筑群 + 行商 + 安全区缓回血 ---
## 营地落点 = 出生斑块中心（障碍抑制区内恒空地，建筑纯装饰 + 底座碰撞体）
const CAMP_HEAL_RADIUS := 420.0
## 安全区缓回血：每秒 3% 最大生命（脱战自然恢复档，不走无敌帧不触发受击演出）
const CAMP_HEAL_FRAC_PER_SEC := 0.03
var _camp_heal_accum := 0.0
var _in_camp := false
## 进屋过场（借鉴③）：遮罩层与传送防重入标记
var _transition_layer: CanvasLayer
var _veil: ColorRect
var _teleporting := false


func _setup_camp() -> void:
	var spawn: Vector2 = WorldConfig.spawn_pos()
	# 建筑三件（视觉盘点验收过的 na_tileset 房屋/鸟居烘焙件）：
	# 底部 StaticBody2D 矩形挡身位（独立于 ObstacleField 瓦片物理，营地恒不被流式回收）
	_add_structure("house_red", spawn + Vector2(-310, -60), Vector2(140, 44))
	_add_structure("house_brown", spawn + Vector2(215, -185), Vector2(140, 44))
	_add_structure("torii", spawn + Vector2(-4, -235), Vector2(120, 36), true)
	# P2 闲置件补位：灰屋（营地东侧民居）+ 道场招牌（鸟居旁，练武去处的暗示）
	_add_structure("house_grey", spawn + Vector2(430, -70), Vector2(140, 44))
	_add_structure("sign_dojo", spawn + Vector2(-118, -212), Vector2(40, 12), true)
	# 行商：对话气泡确认后开商店（HUD 侧 kind=="shop" 分支）
	var merchant := LandmarkNPC.new()
	merchant.position = spawn + Vector2(96, 24)
	merchant.kind = "merchant"
	merchant.giver = "行商"
	merchant.landmark_id = "camp_merchant"
	merchant.quest_kind = "shop"
	merchant.color = Color(0.95, 0.8, 0.45)
	merchant.interact_fn = func(_id: String, _kind: String, _giver: String) -> Dictionary:
		return {"kind": "shop", "text": "风尘仆仆的猎人——看看营地补给吗？"}
	_landmark_root.add_child(merchant)
	# 营地动画件（完整包 Animated）：水车 + 旋转桨叶 + 旗帜
	_add_animated_prop("res://assets/creatures/frames/camp_watermill/camp_watermill_frames.tres",
			spawn + Vector2(-150, -230), 2.6)
	_add_animated_prop("res://assets/creatures/frames/camp_propeller/camp_propeller_frames.tres",
			spawn + Vector2(-150, -262), 2.6)
	_add_animated_prop("res://assets/creatures/frames/camp_flag/camp_flag_frames.tres",
			spawn + Vector2(-4, -262), 2.6)
	# 借鉴③：房屋可进——门前 Area2D 传送门 + 淡入淡出过场 → 世界内嵌室内口袋
	_add_house_door(spawn + Vector2(-310, -8), 0)
	_add_house_door(spawn + Vector2(215, -137), 1)
	_build_interior(0)
	_build_interior(1)
	# 过场遮罩（Transition 借鉴：ColorRect 淡入淡出；CanvasLayer 顶层盖 HUD 之下）
	_transition_layer = CanvasLayer.new()
	_transition_layer.layer = 90
	var veil := ColorRect.new()
	veil.color = Color(0, 0, 0, 0)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_transition_layer.add_child(veil)
	add_child(_transition_layer)
	_veil = veil


## 门前传送门（Zelda 式踩上即进；淡入期间防重触发）
func _add_house_door(pos: Vector2, pocket_idx: int) -> void:
	var area := Area2D.new()
	area.position = pos
	area.collision_layer = 0
	area.collision_mask = 1
	area.monitorable = false
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 42.0
	shape.shape = circle
	area.add_child(shape)
	area.body_entered.connect(func(body: Node2D) -> void:
		if body.is_in_group("player"):
			_fade_teleport(body, ObstacleField.interior_pocket(pocket_idx) + Vector2(0, -50)))
	add_child(area)


## 淡入淡出传送（官方示例包 Transition 的同构实现：遮罩→移人→吸附相机→揭幕）
func _fade_teleport(player: Node2D, target: Vector2) -> void:
	if _teleporting:
		return
	_teleporting = true
	var tween := create_tween()
	tween.tween_property(_veil, "color:a", 1.0, 0.22)
	tween.tween_callback(func() -> void:
		player.global_position = target
		var cam := player.get_node_or_null("Camera2D")
		if cam != null and cam.has_method("snap_to_player"):
			cam.call("snap_to_player"))
	tween.tween_interval(0.08)
	tween.tween_property(_veil, "color:a", 0.0, 0.3)
	tween.tween_callback(func() -> void: _teleporting = false)


## 室内口袋房间（借鉴③）：地板块平铺 + 墙环（StaticBody+视觉）+ 床 + 出口门
const INTERIOR_ROOM := Vector2(320, 256)

func _build_interior(idx: int) -> void:
	var center: Vector2 = ObstacleField.interior_pocket(idx)
	var room := Node2D.new()
	room.position = center
	# 地板：32px 地板块 region 平铺（texture_repeat）
	var floor_sp := Sprite2D.new()
	floor_sp.texture = load("res://assets/na/structures/interior_floor.png")
	floor_sp.centered = false
	floor_sp.position = -INTERIOR_ROOM / 2.0
	floor_sp.region_enabled = true
	floor_sp.region_rect = Rect2(Vector2.ZERO, INTERIOR_ROOM)
	floor_sp.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	floor_sp.z_index = -2
	room.add_child(floor_sp)
	# 墙环：StaticBody 四边 + 暗色九宫格视觉条
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var t := INTERIOR_ROOM / 2.0
	for side: Array in [
			[Vector2(0, -t.y), Vector2(INTERIOR_ROOM.x, 32)],
			[Vector2(0, t.y), Vector2(INTERIOR_ROOM.x, 32)],
			[Vector2(-t.x, 0), Vector2(32, INTERIOR_ROOM.y)],
			[Vector2(t.x, 0), Vector2(32, INTERIOR_ROOM.y)]]:
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = side[1]
		shape.shape = rect
		shape.position = side[0]
		body.add_child(shape)
		var wall := Sprite2D.new()
		wall.texture = load("res://assets/na/ui/np_dark.png")
		wall.position = side[0]
		wall.centered = false
		wall.region_enabled = true
		wall.region_rect = Rect2(Vector2.ZERO, Vector2(side[1]) / 2.0)
		wall.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		wall.scale = Vector2(2, 2)
		wall.z_index = -1
		wall.position -= Vector2(side[1]) / 2.0
		room.add_child(wall)
	room.add_child(body)
	# 家具：床（左上角）
	var bed := Sprite2D.new()
	bed.texture = load("res://assets/na/structures/bed.png")
	bed.position = Vector2(-t.x + 76, -t.y + 64)
	room.add_child(bed)
	# 出口门（南墙缺口）：传送回营地该房屋门前
	var door := Area2D.new()
	door.position = Vector2(0, t.y - 40)
	door.collision_layer = 0
	door.collision_mask = 1
	door.monitorable = false
	var dshape := CollisionShape2D.new()
	var dcircle := CircleShape2D.new()
	dcircle.radius = 34.0
	dshape.shape = dcircle
	door.add_child(dshape)
	var camp := WorldConfig.spawn_pos()
	var back: Vector2 = camp + (Vector2(-310, -8) if idx == 0 else Vector2(215, -137)) + Vector2(0, 90)
	door.body_entered.connect(func(b: Node2D) -> void:
		if b.is_in_group("player"):
			_fade_teleport(b, back))
	room.add_child(door)
	add_child(room)


## 营地动画件（完整包 Animated 背景）：AnimatedSprite2D 循环播放，底部对齐落点
func _add_animated_prop(frames_path: String, pos: Vector2, scale := 2.0) -> void:
	var node := Node2D.new()
	node.position = pos
	var sp := AnimatedSprite2D.new()
	sp.sprite_frames = load(frames_path)
	sp.scale = Vector2(scale, scale)
	var frames: SpriteFrames = sp.sprite_frames
	if frames != null and frames.get_animation_names().size() > 0:
		sp.play(frames.get_animation_names()[0])
	node.add_child(sp)
	add_child(node)


func _add_structure(stamp: String, pos: Vector2, body_size: Vector2, thin := false) -> void:
	var node := Node2D.new()
	node.position = pos
	var sp := Sprite2D.new()
	sp.texture = load("res://assets/na/structures/%s.png" % stamp)
	# 锚点落底边中心（y-sort 按脚点排序，建筑可被走到"后面"）
	sp.offset = Vector2(0, -sp.texture.get_height() / 2.0)
	node.add_child(sp)
	if not thin:
		var body := StaticBody2D.new()
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = body_size
		shape.shape = rect
		shape.position = Vector2(0, -body_size.y / 2.0)
		body.add_child(shape)
		body.collision_layer = 1  # 世界障碍层（与 ObstacleField 瓦片物理同层，玩家/怪都挡）
		node.add_child(body)
	add_child(node)  # game_world 根 y-sort 直接子节点


func _process_camp(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not ("current_hp" in player):
		return
	_in_camp = (player.global_position as Vector2).distance_to(
		WorldConfig.spawn_pos()) <= CAMP_HEAL_RADIUS
	if _in_camp:
		_camp_heal_accum += delta
		if _camp_heal_accum >= 1.0:
			_camp_heal_accum = 0.0
			var max_hp: float = player.stats.max_hp()
			if player.current_hp < max_hp:
				player.current_hp = minf(max_hp, player.current_hp + max_hp * CAMP_HEAL_FRAC_PER_SEC)
				EventBus.player_hp_changed.emit(player.current_hp, max_hp)
	_process_dungeon_zone(player)


# --- Boss 城塞 / 地牢（美术 v5 M-B）---
## 城塞内腔半宽高（px；与 ObstacleField.DUNGEON_HALF×CELL 同口径）
const DUNGEON_ZONE_HALF := Vector2(6.0 * 32.0 + 16.0, 4.0 * 32.0 + 16.0)
## 宝箱刷新半径（走进城塞才生成实体）
const CHEST_STREAM_RADIUS := 1400.0
var _chests := {}  # patch_id → DungeonChest
## 已开标记（patch_id → true）：Boss 死亡窗口内开过的箱，流式离场（>1400px
## 节点回收）后重进不得重置成未开——否则走远回来可反复开箱刷奖励；Boss 复活
## 时清除（下一轮可再开）。会话级状态不进存档（与节点 taken 旧语义同生命周期，
## 只是活过流式回收）
var _chest_taken := {}
var _in_dungeon := false
var _dungeon_announced := {}
## 城塞表缓存（ObstacleField.dungeons 每次调用新分配数组+逐城 duplicate；
## 表本身按种子确定性、装配后不变，缓存后零分配读取）
var _dungeons_cache: Array = []


func _dungeon_list() -> Array:
	if _dungeons_cache.is_empty():
		_dungeons_cache = ObstacleField.dungeons()
	return _dungeons_cache
## 首轮流式未完成前不播 Boss 重生（世界装配期 instance_spawned 全量重放，
## 初始 Boss 不是"重生"；0.5s 首轮 _stream_pass 后置位）
var _stream_primed := false


## 城塞维护（流式节拍里跑）：宝箱进出 + 可开状态 + 进出城塞的 BGM/播报
func _update_dungeons() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return
	for dg: Dictionary in _dungeon_list():
		var patch_id: String = dg["patch_id"]
		var center: Vector2 = dg["center"]
		var near: bool = player.global_position.distance_to(center) <= CHEST_STREAM_RADIUS
		var boss_name: String = WorldConfig.TERRAIN_BOSSES.get(dg["terrain"], "")
		if near and not _chests.has(patch_id):
			var chest := DungeonChest.new()
			chest.position = center + Vector2(0, -110)
			chest.boss_name = boss_name
			chest.key_id = EconomyMath.DUNGEON_KEYS.get(dg["terrain"], "")
			chest.notify_taken = _mark_chest_taken.bind(patch_id)
			_landmark_root.add_child(chest)
			_chests[patch_id] = chest
		elif not near and _chests.has(patch_id):
			_chests[patch_id].queue_free()
			_chests.erase(patch_id)
		if _chests.has(patch_id):
			# boss_name 查空（地形没配 Boss）视为无主宝箱直接解锁，防永久锁死
			var boss_dead: bool = boss_name == "" \
					or (_sim != null and _sim.boss_respawn_timers.get(boss_name, 0) > 0)
			var chest_node: DungeonChest = _chests[patch_id]
			chest_node.locked = not boss_dead
			if not boss_dead:
				_chest_taken.erase(patch_id)  # Boss 复活 → 宝箱重置（下一轮可再开）
			chest_node.taken = _chest_taken.has(patch_id)


func _mark_chest_taken(patch_id: String) -> void:
	_chest_taken[patch_id] = true


## 进出城塞（内腔矩形）：地牢 BGM 与首发现播报
func _process_dungeon_zone(player: Node) -> void:
	var pos: Vector2 = player.global_position
	var inside := false
	for dg: Dictionary in _dungeon_list():
		var center: Vector2 = dg["center"]
		if absf(pos.x - center.x) <= DUNGEON_ZONE_HALF.x \
				and absf(pos.y - center.y) <= DUNGEON_ZONE_HALF.y:
			inside = true
			var pid: String = dg["patch_id"]
			if not _dungeon_announced.has(pid):
				_dungeon_announced[pid] = true
				var boss_name: String = WorldConfig.TERRAIN_BOSSES.get(dg["terrain"], "")
				EventBus.world_event.emit("🏯 发现城塞——%s盘踞之地" % boss_name)
			break
	if inside == _in_dungeon:
		return
	_in_dungeon = inside
	# 切曲走统一调度（_refresh_music，Boss 追踪 4Hz 节拍里判定优先级）


## 全局特效层（美术 v5 M-C）：NA fx 全 20 组的统一播放通道。事件侧
## （怪物死亡/技能施放/元素克制/任务结算…）只发 EventBus.fx_requested，
## 本层查表播条带、播完自灭——逻辑零侵入，缺 kind 静默忽略
class FxLayer extends Node2D:
	## kind → 帧资源（slash 系仍由 player 本地播——已接线的旧路径不动）
	const TABLE := {
		"flame": preload("res://assets/creatures/frames/fx_flame/fx_flame_frames.tres"),
		"magic": preload("res://assets/creatures/frames/fx_magic/fx_magic_frames.tres"),
		"charge": preload("res://assets/creatures/frames/fx_charge/fx_charge_frames.tres"),
		"frost": preload("res://assets/creatures/frames/fx_frost/fx_frost_frames.tres"),
		"boom": preload("res://assets/creatures/frames/fx_boom/fx_boom_frames.tres"),
		"smoke": preload("res://assets/creatures/frames/fx_smoke/fx_smoke_frames.tres"),
		"darksmoke": preload("res://assets/creatures/frames/fx_darksmoke/fx_darksmoke_frames.tres"),
		"orb": preload("res://assets/creatures/frames/fx_orb/fx_orb_frames.tres"),
		"beam": preload("res://assets/creatures/frames/fx_beam/fx_beam_frames.tres"),
		"pillar": preload("res://assets/creatures/frames/fx_pillar/fx_pillar_frames.tres"),
		"flash": preload("res://assets/creatures/frames/fx_flash/fx_flash_frames.tres"),
		"flash_gold": preload("res://assets/creatures/frames/fx_flash_gold/fx_flash_gold_frames.tres"),
		"flash_blue": preload("res://assets/creatures/frames/fx_flash_blue/fx_flash_blue_frames.tres"),
		"flash_yellow": preload("res://assets/creatures/frames/fx_flash_yellow/fx_flash_yellow_frames.tres"),
		"beams": preload("res://assets/creatures/frames/fx_beams/fx_beams_frames.tres"),
	}

	func _ready() -> void:
		z_index = 50  # 顶层（血条/飘字之上不遮 HUD——HUD 是 CanvasLayer）
		EventBus.fx_requested.connect(_spawn)

	## kind → 回收桶（真机性能优化 2026-09-19）：每次事件 new AnimatedSprite2D
	## + 播完 free 在 AOE/连杀时同帧多个是战斗尖峰；改池化——播完 stop+隐藏
	## 留树回桶，复用时重定位重播（桶按需增长不收缩，与飘字池同思路）
	var _pool := {}

	func _spawn(kind: String, pos: Vector2, fx_scale: float) -> void:
		var frames: SpriteFrames = TABLE.get(kind)
		if frames == null:
			return
		if not _pool.has(kind):
			_pool[kind] = []
		var bucket: Array = _pool[kind]
		var fx: AnimatedSprite2D
		if bucket.is_empty():
			fx = AnimatedSprite2D.new()
			fx.sprite_frames = frames
			fx.animation_finished.connect(_recycle.bind(kind, fx))
			add_child(fx)  # 常驻树中，回收只隐藏不摘树
		else:
			fx = bucket.pop_back()
		fx.position = pos
		fx.scale = Vector2.ONE * clampf(fx_scale, 0.5, 3.0)
		fx.visible = true
		fx.play(&"play")

	func _recycle(kind: String, fx: AnimatedSprite2D) -> void:
		fx.stop()
		fx.visible = false
		(_pool[kind] as Array).append(fx)


## 城塞宝箱（v7 P1 钥匙模式）：Boss 被讨伐期间（重生倒计时进行中）解封，
## 还需对应钥匙——银钥匙开 hill 城塞（精英怪掉落）、金钥匙开 lava 城塞
## （collect 任务奖励）；开箱 = 金币 + 双件物品（hash 确定性抽取）。
## 加入 npcs 组复用玩家的最近交互路由（攻击键开箱）
class DungeonChest extends Node2D:
	## 大宝箱（NA items 图标 16px ×3）；箱顶悬浮所需钥匙图标提示
	const CHEST_TEX := preload("res://assets/na/items/big-treasure-chest.png")
	var boss_name := ""
	var key_id := ""
	var locked := true
	var taken := false
	## 开箱回调（game_world 绑定，记录进 _chest_taken 活过流式回收）
	var notify_taken: Callable
	var _sprite: Sprite2D
	var _key_hint: Sprite2D

	func _ready() -> void:
		add_to_group("npcs")
		add_to_group("chests")
		_sprite = Sprite2D.new()
		_sprite.texture = CHEST_TEX
		_sprite.scale = Vector2(3.0, 3.0)
		add_child(_sprite)
		if key_id != "":
			_key_hint = Sprite2D.new()
			_key_hint.texture = ItemCatalog.icon_of(key_id)
			_key_hint.scale = Vector2(2.0, 2.0)
			_key_hint.position = Vector2(0, -34)
			add_child(_key_hint)

	func _process(_delta: float) -> void:
		visible = not taken
		# 锁定时微暗提示"开不了"；解封且需钥匙时，箱顶钥匙图标随缺口闪示
		_sprite.modulate = Color(1, 1, 1, 0.75) if locked else Color(1, 1, 1, 1)
		if _key_hint != null:
			var need_key: bool = not locked and not taken \
					and GameState.count_item(key_id) <= 0
			_key_hint.visible = need_key
			_key_hint.modulate = Color(1, 0.85, 0.5, 0.7 + 0.3 * sin(Time.get_ticks_msec() * 0.004))

	func interact() -> void:
		if taken:
			return
		if locked:
			EventBus.hint_requested.emit("🔒 宝箱被城主的力量封印着——讨伐%s再说" % boss_name)
			return
		if key_id != "" and not GameState.remove_item(key_id, 1):
			EventBus.hint_requested.emit("🗝 需要%s才能打开（%s）" % [
				ItemCatalog.name_of(key_id),
				"完成收集委托获得" if key_id == EconomyMath.KEY_GOLD else "击败精英怪有几率掉落"])
			return
		taken = true
		if notify_taken.is_valid():
			notify_taken.call()
		var gold: int = EconomyMath.bounty_gold(8, GameState.stats.level)
		GameState.add_gold(gold)
		# 双件物品奖励（hash 确定性，无 RNG）：补给 1 件 + 稀有材料 1 件
		var h: int = hash("chest|%s|%d" % [key_id, GameState.stats.level])
		var supply: Array = EconomyMath.BOSS_BONUS_POOL
		var rares: Array = EconomyMath.COLLECT_POOL_RARE
		var item1: String = supply[absi(h) % supply.size()]
		var item2: String = rares[absi(h >> 8) % rares.size()]
		GameState.add_item(item1, 1)
		GameState.add_item(item2, 1)
		SfxManager.play("secret")
		SfxManager.play("gold2")
		EventBus.hint_requested.emit("📦 城塞宝箱 +%d 金币 +%s +%s" % [
			gold, ItemCatalog.name_of(item1), ItemCatalog.name_of(item2)])
		# 开箱光柱 + 爆散（美术 v5 fx 全量）
		EventBus.fx_requested.emit("pillar", position, 2.0)
		EventBus.fx_requested.emit("flash_gold", position, 1.4)


# --- 世界总览后台任务（区域多边形 + 小地图底图，世界 v5） ---

## 栅格化在后台线程（~64 万次 BiomeMap 采样 ≈ 1s），物理体/纹理创建必须主线程。
## 线程只读 BiomeMap 已填缓存（_build_regions 在其之前填充），无并发写
func _start_overview_job() -> void:
	_overview_thread = Thread.new()
	_overview_thread.start(_compute_overview)


func _compute_overview() -> void:
	var raster: Dictionary = BiomeMap.region_raster(REGION_RASTER)
	var polys := {}
	for def: Dictionary in BiomeMap.patches():
		polys[def["id"]] = BiomeMap.patch_polygons(def["id"], REGION_RASTER)
	# 小地图底图：栅格逐格上地形总览色（800×800，与旧 world_map.png 同等分辨率；
	# 每档种子一张，不再依赖离线烘焙 PNG）
	var cols: int = raster["cols"]
	var rows: int = raster["rows"]
	var cells: PackedInt32Array = raster["cells"]
	var patches_list := BiomeMap.patches()
	var palette := PackedColorArray()
	palette.resize(patches_list.size())
	for idx in patches_list.size():
		palette[idx] = BiomeMap.TERRAIN_COLORS.get(patches_list[idx]["terrain"], Color(0.1, 0.1, 0.1))
	var bytes := PackedByteArray()
	bytes.resize(cells.size() * 3)
	var fallback := Color(0.1, 0.1, 0.1)
	for idx in cells.size():
		var c := palette[cells[idx]] if cells[idx] >= 0 else fallback
		var o := idx * 3
		bytes[o] = c.r8
		bytes[o + 1] = c.g8
		bytes[o + 2] = c.b8
	var image := Image.create_from_data(cols, rows, false, Image.FORMAT_RGB8, bytes)
	_apply_overview.call_deferred({"polys": polys, "image": image})


func _apply_overview(result: Dictionary) -> void:
	if _overview_thread != null:
		_overview_thread.wait_to_finish()
		_overview_thread = null
	if not is_inside_tree():
		return
	_setup_region_areas(result["polys"])
	EventBus.world_overview_ready.emit(ImageTexture.create_from_image(result["image"]))


# --- 世界 v5 探索层 ---

## 地标发现：每地标一个 400px 圆形 Area2D（仅监测玩家），首次靠近即发现——
## 纯原生信号驱动，零轮询。发现 → 存档 + 结构化信号（任务系统锚点）+ 播报
func _setup_landmarks() -> void:
	_landmark_root = Node2D.new()
	_landmark_root.name = "Landmarks"
	add_child(_landmark_root)
	for lm: Dictionary in LandmarkRegistry.landmarks():
		var area := Area2D.new()
		area.position = lm["pos"]
		area.collision_layer = 0
		area.collision_mask = 1
		area.monitorable = false
		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = LandmarkRegistry.DISCOVER_RADIUS
		shape.shape = circle
		area.add_child(shape)
		area.body_entered.connect(_on_landmark_area_entered.bind(lm["id"]))
		_landmark_root.add_child(area)


func _on_landmark_area_entered(_body: Node2D, id: String) -> void:
	var lm: Dictionary = LandmarkRegistry.landmark(id)
	if lm.is_empty() or not GameState.discover_landmark(id):
		return
	EventBus.landmark_discovered.emit(id, lm["patch_id"], lm["kind"], lm["pos"])
	EventBus.world_event.emit("🧭 发现地标「%s」" % lm["kind"])
	SfxManager.play("discover")
	var marker: LandmarkMarker = _landmark_markers.get(id)
	if marker != null:
		marker.discovered = true
		marker.queue_redraw()


## 地标视觉标记：玩家附近才有实体（微光圈 + 图腾点；发现后高亮）
func _update_landmark_markers() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null or not player.visible:
		return
	for lm: Dictionary in LandmarkRegistry.landmarks():
		var id: String = lm["id"]
		var near: bool = player.global_position.distance_to(lm["pos"]) <= LANDMARK_VIS_RADIUS
		if near and not _landmark_markers.has(id):
			var marker := LandmarkMarker.new()
			marker.position = lm["pos"]
			marker.kind = lm["kind"]
			marker.color = LandmarkRegistry.kind_color(lm["kind"])
			marker.discovered = GameState.discovered_landmarks.has(id)
			marker.z_index = -1
			_landmark_root.add_child(marker)
			_attach_landmark_deco(marker, lm["kind"])
			_landmark_markers[id] = marker
		elif not near and _landmark_markers.has(id):
			(_landmark_markers[id] as Node).queue_free()
			_landmark_markers.erase(id)
		# 地标 NPC（世界 v5）：特定类型常驻发任务，随标记同进出
		var npc_def: Dictionary = LandmarkRegistry.NPC_BY_KIND.get(lm["kind"], {})
		if npc_def.is_empty():
			continue
		if near and not _npc_nodes.has(id):
			var npc := LandmarkNPC.new()
			npc.position = lm["pos"] + Vector2(30, 4)
			npc.landmark_id = id
			npc.giver = npc_def["name"]
			npc.quest_kind = npc_def["quest"]
			npc.kind = lm["kind"]
			npc.color = LandmarkRegistry.kind_color(lm["kind"])
			npc.interact_fn = _npc_interact_fn
			_landmark_root.add_child(npc)
			_npc_nodes[id] = npc
		elif not near and _npc_nodes.has(id):
			(_npc_nodes[id] as Node).queue_free()
			_npc_nodes.erase(id)


## 地标动画装饰（玩法 v7 P2）：随标记流式同进出——精灵泉挂瀑布三段纵排
## （NA Animated waterfall 条带，水从泉眼流出）、古树挂草叶摇摆 ×2；
## 其余地标保持原有圆环/精灵不抢戏
func _attach_landmark_deco(marker: Node2D, kind: String) -> void:
	# 偏移是相对地标的局部坐标（装饰作为 marker 子节点随其流式同进出）
	if kind == "精灵泉":
		var wf := [
			["deco_waterfall_start", Vector2(-44, -30)],
			["deco_waterfall_middle", Vector2(-44, 2)],
			["deco_waterfall_end", Vector2(-44, 34)],
		]
		for pair in wf:
			marker.add_child(_make_animated_prop(
				"res://assets/creatures/frames/%s/%s_frames.tres" % [pair[0], pair[0]],
				pair[1], 2.0))
	elif kind == "古树":
		for offset in [Vector2(-40, 6), Vector2(40, -4)]:
			marker.add_child(_make_animated_prop(
				"res://assets/creatures/frames/deco_plant/deco_plant_frames.tres",
				offset, 2.0))


## 动画挂件（地标装饰版：相对地标的局部坐标，随标记同生命周期）
func _make_animated_prop(frames_path: String, pos: Vector2, scale := 2.0) -> Node2D:
	var node := Node2D.new()
	node.position = pos
	var sp := AnimatedSprite2D.new()
	sp.sprite_frames = load(frames_path)
	sp.scale = Vector2(scale, scale)
	var frames: SpriteFrames = sp.sprite_frames
	if frames != null and frames.get_animation_names().size() > 0:
		sp.play(frames.get_animation_names()[0])
	node.add_child(sp)
	return node


## 战争迷雾揭示：玩家所在 3×3 格入档（跨格才动笔，版本号通知小地图重建）
func _reveal_fog() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null or not player.visible:
		return
	var cell := GameState.fog_cell_of(player.global_position)
	if cell == _fog_last_cell:
		return
	_fog_last_cell = cell
	var revealed := false
	for dy in range(-FOG_REVEAL_RADIUS, FOG_REVEAL_RADIUS + 1):
		for dx in range(-FOG_REVEAL_RADIUS, FOG_REVEAL_RADIUS + 1):
			if not GameState.fog_is_explored(cell.x + dx, cell.y + dy):
				GameState.fog_reveal_cell(cell.x + dx, cell.y + dy)
				revealed = true
	if revealed:
		GameState.fog_version += 1
		GameState._queue_save()


## 地标视觉标记：地标精灵探图（assets/landmarks/<种类>.png，缺图回退纯圆环；美术 v5 起默认回退圆环，NA 风格地标图到位后放回即生效）
## + 底部微光环作发现指示（发现后高亮）
class LandmarkMarker extends Node2D:
	var kind := ""
	var color := Color.WHITE
	var discovered := false

	func _ready() -> void:
		var path := "res://assets/landmarks/%s.png" % kind
		if ResourceLoader.exists(path):
			var sp := Sprite2D.new()
			sp.texture = load(path)
			sp.scale = Vector2(0.55, 0.55)
			sp.position.y = -sp.scale.y * float(sp.texture.get_height()) / 2.0
			add_child(sp)

	func _draw() -> void:
		draw_circle(Vector2.ZERO, 54.0, Color(color.r, color.g, color.b, 0.08))
		var ring_alpha := 0.85 if discovered else 0.35
		draw_arc(Vector2.ZERO, 54.0, 0.0, TAU, 40,
				Color(color.r, color.g, color.b, ring_alpha), 2.0)
		draw_circle(Vector2.ZERO, 7.0, Color(color.r, color.g, color.b, 0.9))


## 地标 NPC（美术 v5）：NA 角色精灵 + 头顶名牌 + 轻微踱步。
## 交互 = 玩家贴近按攻击键（player 侧查询 npcs 组）→ 结构化委托经
## EventBus.npc_dialogue 由 HUD 对话气泡呈现（是/否接取）
class LandmarkNPC extends Node2D:
	## 地标类型 → NA 角色帧（characters 表 8=猎人 4=老者 7=巫女 6=行商；
	## P1 扩容 13=瞭望者 9=草药师，视觉盘点定）
	const FRAMES := {
		"石环": preload("res://assets/creatures/frames/npc_hunter/npc_hunter_frames.tres"),
		"荒废遗迹": preload("res://assets/creatures/frames/npc_scholar/npc_scholar_frames.tres"),
		"精灵泉": preload("res://assets/creatures/frames/npc_keeper/npc_keeper_frames.tres"),
		"merchant": preload("res://assets/creatures/frames/npc_merchant/npc_merchant_frames.tres"),
		"了望石塔": preload("res://assets/creatures/frames/npc_watchman/npc_watchman_frames.tres"),
		"古树": preload("res://assets/creatures/frames/npc_herbalist/npc_herbalist_frames.tres"),
	}
	## 立绘编号（faceset 同源表号；0 = 无立绘兜底）
	const FACESETS := {"石环": 101, "荒废遗迹": 102, "精灵泉": 103, "merchant": 104,
		"了望石塔": 13, "古树": 9}
	var landmark_id := ""
	var giver := ""
	var quest_kind := ""
	var kind := ""
	var color := Color.WHITE
	var interact_fn: Callable
	var _visual: AnimatedSprite2D
	var _t := 0.0
	var _home := Vector2.ZERO
	var _walk_dir := 0.0
	var _pause := 2.0

	func _ready() -> void:
		add_to_group("npcs")
		_home = position
		_visual = AnimatedSprite2D.new()
		var frames: SpriteFrames = FRAMES.get(kind)
		if frames != null:
			_visual.sprite_frames = frames
		_visual.scale = Vector2(4.8, 4.8)
		_visual.position.y = -4.0
		_visual.play(&"idle")
		add_child(_visual)
		var label := Label.new()
		var style := LabelSettings.new()
		style.font_size = 24
		style.font_color = Color(1, 1, 1, 0.85)
		style.outline_size = 4
		style.outline_color = Color(0, 0, 0, 0.7)
		label.label_settings = style
		label.text = giver
		label.position = Vector2(-52, -104)
		label.size = Vector2(104, 28)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(label)

	func _process(delta: float) -> void:
		_t += delta
		# 待机踱步：走一小段→停一会儿→折返（贴地标小范围活动，不参与碰撞）
		var player := get_tree().get_first_node_in_group("player") as Node2D
		if player != null and global_position.distance_to(player.global_position) <= 220.0:
			# 玩家靠近：转向玩家（四方向帧，纵向不再侧身）
			var to_p := player.global_position - global_position
			_face_dir(to_p, false)
			return
		if _pause > 0.0:
			_pause -= delta
			if _pause <= 0.0:
				_walk_dir = 1.0 if _t * 0.37 - floor(_t * 0.37) < 0.5 else -1.0
		elif _walk_dir != 0.0:
			position.x += _walk_dir * 18.0 * delta
			_face_dir(Vector2(_walk_dir, 0), true)
			if absf(position.x - _home.x) > 14.0:
				_walk_dir = 0.0
				_pause = 2.0 + fmod(_t, 3.0)
				_face_dir(Vector2(_walk_dir, 0), false)
		# _draw 只画一枚恒定光圈（位置变化走 transform，无需重绘命令）——
		# 每帧 queue_redraw 是纯浪费，已去除（真机性能优化 2026-09-19）

	## 朝向表现：水平→右向帧+flip；纵向→up/down 帧（美术 v5 借鉴②）
	func _face_dir(dir: Vector2, walking: bool) -> void:
		var base := "walk" if walking else "idle"
		var frames: SpriteFrames = _visual.sprite_frames
		if frames == null:
			return
		if absf(dir.y) > absf(dir.x) and frames.has_animation(base + "_up"):
			_visual.flip_h = false
			_visual.play(base + ("_up" if dir.y < 0.0 else "_down"))
		else:
			_visual.flip_h = dir.x < 0.0
			_visual.play(base)

	func _draw() -> void:
		# 脚下光环保留地标微光色，与地标圆环同色系（精灵本体在上）
		draw_circle(Vector2.ZERO, 10.0, Color(color.r, color.g, color.b, 0.25))

	func interact() -> void:
		if interact_fn.is_valid():
			var offered: Dictionary = interact_fn.call(landmark_id, quest_kind, giver)
			offered["giver"] = giver
			offered["faceset"] = FACESETS.get(kind, 0)
			# 对话现场位置：HUD 据此在玩家走开时收气泡（不改道攻击/冲刺键）
			offered["origin"] = global_position
			EventBus.npc_dialogue.emit(offered)


## 区域 Area2D：100 个静态监测体（mask=玩家层，仅玩家触发）。共享栅格派生的
## 多边形无缝无重叠——跨界瞬间 exited/entered 成对触发，由滞回逻辑消化
func _setup_region_areas(polys: Dictionary) -> void:
	var root := Node2D.new()
	root.name = "RegionAreas"
	add_child(root)
	for region: SimRegion in _sim.regions.values():
		var loops: Array = polys.get(region.id, [])
		if loops.is_empty():
			continue
		var area := Area2D.new()
		area.collision_layer = 0
		area.collision_mask = 1  # 只监测玩家（layer 1）
		area.monitorable = false
		for loop: PackedVector2Array in loops:
			var poly := CollisionPolygon2D.new()
			poly.polygon = BiomeMap.collision_safe_loop(loop)
			area.add_child(poly)
		area.body_entered.connect(_on_region_area_entered.bind(region.id))
		area.body_exited.connect(_on_region_area_exited.bind(region.id))
		root.add_child(area)


func _on_region_area_entered(_body: Node2D, region_id: String) -> void:
	if _current_region_id == "":
		# 首次进图立即提交（Area 建立时玩家所在区域即刻确认）
		_commit_region(region_id)
		return
	if region_id == _current_region_id:
		# 抖动返回当前区域：取消进行中的候选
		_region_candidate_id = ""
		return
	_region_candidate_id = region_id
	_region_candidate_time = REGION_CONFIRM_SECONDS


func _on_region_area_exited(_body: Node2D, region_id: String) -> void:
	# 候选区域又被走出（贴边界抖动）：取消，等待下次 entered 重启计时
	if region_id == _region_candidate_id:
		_region_candidate_id = ""


func _commit_region(region_id: String) -> void:
	var region: SimRegion = _sim.get_region(region_id)
	if region == null:
		return
	_current_region_id = region_id
	if _skip_first_region_announce:
		# 读档续玩的首个区域提交：只静默接回区域 BGM，不播报/不放换区音/
		# 不打威胁警告（威胁警告留给之后真正的跨区再入）
		_skip_first_region_announce = false
		# 先同步一次特殊区判定再定首曲：出生点常在营地内，直接播群系曲会被
		# 0.25s 后首个 _refresh_music 纠正成营地曲——每次进世界双重淡入淡出
		var player := get_tree().get_first_node_in_group("player") as Node2D
		if player != null:
			_in_camp = player.global_position.distance_to(
					WorldConfig.spawn_pos()) <= CAMP_HEAL_RADIUS
			_process_dungeon_zone(player)
		if _in_camp:
			_music_mode = "camp"
			SfxManager.play_music("camp")
		elif _in_dungeon:
			_music_mode = "dungeon"
			SfxManager.play_music("dungeon")
		else:
			SfxManager.play_music(region.terrain)
		return
	EventBus.player_entered_region.emit(region.id, region.display_name)
	# 群系曲只在无特殊区模式时切：Boss 临场/城塞/营地中进行跨区不得抢占战斗曲，
	# 脱离特殊区时 _refresh_music 会按当前区域接回群系曲（切曲权威在本调度器）
	if _music_mode == "":
		SfxManager.play_music(region.terrain)
	if region.threat >= 2.2 and not _warned_regions.has(region.id):
		_warned_regions[region.id] = true
		EventBus.region_threat_warning.emit(region.threat)


## 零增量升级归一（add_xp(0) 只跑 while 循环：等级/属性点/寿命/赐福全按正常路径结算）
func _normalize_xp() -> void:
	if GameState.stats.xp >= GameState.stats.xp_to_next():
		GameState.stats.add_xp(0)


## Boss 顶部血条桥：玩家附近最近的存活 Boss 上屏（换目标/脱离/死亡时收起）。
## Boss 数量 ≤3，遍历模拟实例即可；HUD 只订阅不轮询玩法系统
func _update_boss_track() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	var best: MonsterBase = null
	var best_dist := BOSS_TRACK_RANGE
	if player != null and player.visible:
		for inst: MonsterInstance in _sim.instances.values():
			if not inst.is_alive or not inst.species.is_boss:
				continue
			var node: Node = _nodes.get(inst.id)
			var mb := node as MonsterBase
			if mb == null or mb.state == MonsterBase.S_CORPSE:
				continue
			var dist: float = player.global_position.distance_to(mb.global_position)
			if dist < best_dist:
				best = mb
				best_dist = dist
	if best == null:
		if _boss_tracked_id != -1:
			_boss_tracked_id = -1
			EventBus.boss_tracked.emit(false, "")
		_refresh_music()
		return
	if best.inst.id != _boss_tracked_id:
		_boss_tracked_id = best.inst.id
		EventBus.boss_tracked.emit(true, best.inst.species.species_name)
	EventBus.boss_hp_changed.emit(best.current_hp, best.inst.max_hp())
	_refresh_music()


## 音乐优先级调度（美术 v5 M-C 全量，4Hz 随 Boss 追踪节拍）：
## 活体 Boss 临场 > 城塞内 > 营地 > 群系曲；只在模式切换时切曲
## （play_music 同曲不重启），回群系由换区监听负责、此处不重播
var _music_mode := ""

func _refresh_music() -> void:
	var mode := ""
	if _boss_tracked_id != -1:
		mode = "boss"
	elif _in_dungeon:
		mode = "dungeon"
	elif _in_camp:
		mode = "camp"
	if mode == _music_mode:
		return
	_music_mode = mode
	if mode != "":
		SfxManager.play_music(mode)
	elif _current_region_id != "":
		# 退出特殊区（营地/城塞/Boss 圈）回到群系曲；换区监听已切过曲时同曲不重启
		var region: SimRegion = _sim.get_region(_current_region_id)
		SfxManager.play_music(region.terrain if region != null else "plains")


## 从 WorldConfig（纯数据唯一源，v4 由 BiomeMap 派生）构建区域配置：
## terrain 地形 / threat 威胁系数 / capacity 承载 / neighbors 邻接
func _build_regions() -> Array:
	var result: Array = []
	for def: Dictionary in WorldConfig.region_defs():
		var region := SimRegion.new()
		region.id = def["id"]
		region.display_name = def["name"]
		region.terrain = def["terrain"]
		region.threat = def["threat"]
		region.center = def["center"]
		region.size = def["size"]
		region.capacity = def["capacity"]
		for neighbor: String in def["neighbors"]:
			region.neighbor_ids.append(neighbor)
		result.append(region)
	return result


## 区域铭牌：地图中央大字 + 危险度星级，玩家一眼识别所在地图与深度
func _spawn_region_labels() -> void:
	for region: SimRegion in _sim.regions.values():
		var label := Label.new()
		var stars := "★".repeat(clampi(int(round(region.threat)), 1, 3))
		label.text = "%s %s" % [region.display_name, stars]
		var style := LabelSettings.new()
		style.font_size = 46
		style.font_color = Color(1, 1, 1, 0.22)
		label.label_settings = style
		label.z_index = -1
		label.position = region.center + Vector2(-250, -320)
		label.size = Vector2(500, 60)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(label)


func _on_instance_spawned(inst: MonsterInstance) -> void:
	# Boss 重生降临：多重光束 + 播报（美术 v5 fx 全量；只在玩家附近、且世界
	# 已装配完成后的重生才播——初始撒放的重放不是"重生"）
	if _stream_primed and inst.species.is_boss \
			and _instance_in_view(inst, Vector2.INF) and inst.spawn_pos != Vector2.INF:
		EventBus.world_event.emit("⚠️ %s 在城塞深处重生了" % inst.species.species_name)
		EventBus.fx_requested.emit("beams", inst.spawn_pos, 2.2)
		SfxManager.play("alert")
	# 击杀（Area2D 回调内）触发的分裂生成会处于物理刷新期，
	# 此时 add_child 物理体报错，统一延迟到帧末创建
	if stream_all or _instance_in_view(inst, Vector2.INF):
		_spawn_monster_node.call_deferred(inst)
	else:
		_pending_stream[inst.id] = inst


## 流式维护：待生成实例进场、出界节点回收、巢穴按距离进出。
## 模拟层状态与实例据点位置都不动——这里只是表现节点的生命周期管理
func _stream_pass() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null or not player.visible or stream_all:
		return
	var ppos := player.global_position
	# 传送兜底：Area 事件只在连续移动跨斑时触发，直接改坐标的传送（测试/
	# 复活点等）不产生 enter 事件——每轮点查玩家实际所在斑块，静默漂移就
	# 补全提交（区域播报/视图集/BGM 全链），视图集不再依赖事件是否送达
	var actual: SimRegion = _sim.region_of_point(ppos)
	if actual != null and actual.id != _current_region_id \
			and _region_candidate_id != actual.id:
		_commit_region(actual.id)
	# ① 玩家所在斑块（+邻接）内的待生成实例 → 节点
	for id: int in _pending_stream.keys():
		var inst: MonsterInstance = _pending_stream[id]
		if inst == null or not inst.is_alive:
			_pending_stream.erase(id)
			continue
		if _instance_in_view(inst, ppos):
			_pending_stream.erase(id)
			_spawn_monster_node.call_deferred(inst)
	# ② 出界节点回收：据点位置不变（走远再回来还在原地）；尸体直接回收。
	# 不写回节点当前位置——追击/游走会把据点拖离营地，MMO 语义是怪回据点。
	# 斑块级生成（v5 跑图遭遇）后，巡猎逼近中的实例即便节点走出 2800px，
	# 只要归属斑块仍在视图集内就不回收（换斑瞬间凭空消失是穿帮）
	for id: int in _nodes.keys():
		var node: Node = _nodes.get(id)
		var mb := node as MonsterBase
		var inst: MonsterInstance = _sim.instances.get(id)
		if mb == null or inst == null:
			continue
		var dist := ppos.distance_to(mb.global_position)
		if dist > STREAM_DESPAWN and not _region_in_view(inst.region_id):
			mb.queue_free()
			_nodes.erase(id)
			if inst.is_alive:
				_pending_stream[id] = inst
	# ③ 巢穴：归属斑块在视图集内 → 实体；出视图 → 回收（捣毁状态由模拟层信号处理）
	for key: String in _active_nest_keys.keys():
		var nest_visible := _nest_nodes.has(key)
		var nest_near := _region_in_view(key.get_slice("|", 0))
		if nest_near and not nest_visible:
			_create_nest_node.call_deferred(key, key.get_slice("|", 0), key.get_slice("|", 1))
		elif not nest_near and nest_visible:
			var old: Node = _nest_nodes[key]
			old.queue_free()
			_nest_nodes.erase(key)


## 实例是否在玩家的斑块视图集（所在斑块 + 邻接斑块）内。
## 斑块级生成（替代旧「spawn_pos 距玩家 2400px」点位圈）：80 万 px 世界里
## 点圈覆盖率仅 ~1%（跑图 78 万 px 期望遇怪 2 次），自由跑图永远碰不到怪；
## 按斑块生成 + 怪物巡猎逼近（monster_base）让跑图必与斑块种群相遇。
## ppos 传 Vector2.INF 表示调用方无现成玩家位置（自行点查）
func _instance_in_view(inst: MonsterInstance, ppos: Vector2) -> bool:
	if _region_in_view(inst.region_id):
		return true
	# 跨斑巡猎的既有节点：距玩家仍近则保留（换斑瞬间凭空消失是穿帮）
	if ppos == Vector2.INF:
		var player := get_tree().get_first_node_in_group("player") as Node2D
		ppos = player.global_position if player != null else Vector2.INF
		if ppos == Vector2.INF:
			return false
	var node: Node = _nodes.get(inst.id)
	return node != null and (node as Node2D).global_position.distance_to(ppos) <= STREAM_DESPAWN


## 斑块视图集判定：玩家当前提交斑块 + 其邻接。当前斑块未提交（刚进世界）
## 时按玩家位置点查兜底
func _region_in_view(region_id: String) -> bool:
	if stream_all:
		return true
	var current := _current_region_id
	if current == "":
		var player := get_tree().get_first_node_in_group("player") as Node2D
		if player == null:
			return false
		var region: SimRegion = _sim.region_of_point(player.global_position)
		if region == null:
			return false
		current = region.id
	if region_id == current:
		return true
	var region: SimRegion = _sim.get_region(current)
	return region != null and region_id in region.neighbor_ids


## 巢穴落点 = 该斑块该物种的营地心（EcologySim.camp_pos 确定性派生）：
## 巢与种群据点同址——捣巢即端老窝；同巢每次走近都在原地
func _nest_pos_of(key: String) -> Vector2:
	var region := _sim.get_region(key.get_slice("|", 0))
	var species := _sim.find_species(key.get_slice("|", 1))
	if region == null or species == null:
		return Vector2.ZERO
	return _sim.camp_pos(region, species)


func _spawn_monster_node(inst: MonsterInstance) -> void:
	var scene: PackedScene = MONSTER_SCENES.get(inst.species.species_name)
	if scene == null:
		push_warning("种族 %s 没有配置表现场景" % inst.species.species_name)
		return
	# 落点 = 模拟层分配的据点位置（营地扎根/亲代附近/巢穴同址），
	# 表现层不改写；MonsterBase.setup 对 INF 有斑块内随机兜底（纯防御）
	var node := scene.instantiate()
	monsters.add_child(node)
	node.setup(inst)
	_nodes[inst.id] = node
	# 精英诞生播报（60s 节流，避免繁衍高峰刷屏）；Boss 降临/重生无节流全服播报
	if inst.species.is_boss:
		var boss_region: SimRegion = _sim.get_region(inst.region_id)
		var boss_region_name: String = boss_region.display_name if boss_region != null else inst.region_id
		EventBus.world_event.emit("⚔ %s 盘踞%s——它是这片生态的顶点" % [
			inst.species.species_name, boss_region_name])
	elif inst.is_elite:
		var now: float = Time.get_ticks_msec() / 1000.0
		if now - _last_elite_broadcast >= 60.0:
			_last_elite_broadcast = now
			var region_name: String = _sim.get_region(inst.region_id).display_name \
					if _sim.get_region(inst.region_id) != null else inst.region_id
			EventBus.world_event.emit("金色闪光！精英 %s 降临%s" % [inst.species.species_name, region_name])
	# 延迟创建期间可能已被模拟层判死（极端时序），补一次死亡表现
	if not inst.is_alive:
		node.on_sim_death()


func _on_instance_died(inst: MonsterInstance, _cause: String) -> void:
	var node: Node = _nodes.get(inst.id)
	if node != null:
		node.on_sim_death()
	_pending_stream.erase(inst.id)


func _on_instance_migrated(inst: MonsterInstance, to_region_id: String) -> void:
	var node: Node = _nodes.get(inst.id)
	if node == null:
		return
	# v4 大世界：迁徙 = 模拟层已重分配到目标斑块营地；新据点在流式范围外 →
	# 回收节点（让节点跋涉数万像素的"长征"既看不见也不可行）。
	# 近处迁移保留"朝新据点走过去"的演出
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null or player.global_position.distance_to(inst.spawn_pos) > STREAM_DESPAWN:
		node.queue_free()
		_nodes.erase(inst.id)
		_pending_stream[inst.id] = inst
		return
	node.on_migrate(to_region_id, inst.spawn_pos)


func _on_corpse_expired(inst: MonsterInstance) -> void:
	var node: Node = _nodes.get(inst.id)
	if node != null:
		node.queue_free()
	_nodes.erase(inst.id)


## 清空全部怪物/巢穴表现态（restore 失败回退 setup 时用）：模拟层 setup 会
## 全量清空重建，表现层不同步清场的话，旧世界线的节点残留 _nodes（实例查无、
## 永不回收也打不死），待生成池里的旧实例还会被重复生成
func _discard_streamed_world() -> void:
	for id: int in _nodes.keys():
		var node: Node = _nodes.get(id)
		if node != null:
			node.queue_free()
	_nodes.clear()
	_pending_stream.clear()
	for key: String in _nest_nodes.keys():
		var nest: Node = _nest_nodes.get(key)
		if nest != null:
			nest.queue_free()
	_nest_nodes.clear()
	_active_nest_keys.clear()


## 巢穴表现：建立/重建 → 玩家走近时生成可攻击巢体；捣毁 → 移除并广播激怒；
## 灭绝荒废（ransacked=false）→ 静默移除，不触发激怒——种群消亡不是玩家的战果。
## v4 大世界：~350 个活跃巢的 Node 不可全量常驻——模拟层只记账
## （_active_nest_keys），实体由 _stream_pass 按玩家距离进出（落点确定性，
## 走远再回来巢还在原地）。创建走 call_deferred：击杀分裂链可能处于
## 物理刷新期（report_killed → _spawn_splits → _ensure_nest → nest_changed
## 同步直达），此时 add_child 物理体会报引擎错误
func _on_nest_changed(region_id: String, species_name: String, active: bool, p_ransacked: bool) -> void:
	var key := "%s|%s" % [region_id, species_name]
	if not active:
		_active_nest_keys.erase(key)
		var old: Node = _nest_nodes.get(key)
		if old != null:
			old.queue_free()
			_nest_nodes.erase(key)
		if p_ransacked:
			EventBus.nest_ransacked.emit(species_name)
		return
	_active_nest_keys[key] = true
	# 玩家恰好在附近（当面捣毁后重建等）→ 立即补上，不等下一轮轮询
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player != null \
			and player.global_position.distance_squared_to(_nest_pos_of(key)) <= STREAM_RADIUS * STREAM_RADIUS:
		_create_nest_node.call_deferred(key, region_id, species_name)


func _create_nest_node(key: String, region_id: String, species_name: String) -> void:
	if _nest_nodes.has(key) or not is_inside_tree():
		return
	var species := _sim.find_species(species_name)
	var region: SimRegion = _sim.get_region(region_id)
	if species == null or region == null:
		return
	var nest := NestNode.new()
	add_child(nest)
	nest.setup(region_id, species_name, species.tint, _nest_pos_of(key))
	_nest_nodes[key] = nest


## 顿帧执行器：压低全局时间尺度，用忽略 time_scale 的定时器恢复。
## 重叠请求取更长者；被取代的旧定时器回调直接让位
func _on_hit_stop(duration: float) -> void:
	if not hit_stop_enabled:
		return
	if _hit_stop_timer != null and _hit_stop_timer.time_left >= duration:
		return  # 已有等长/更长的顿帧在计时
	Engine.time_scale = HIT_STOP_SCALE
	_hit_stop_timer = get_tree().create_timer(duration, true, false, true)
	_hit_stop_timer.timeout.connect(_restore_time_scale.bind(_hit_stop_timer))


func _restore_time_scale(which: SceneTreeTimer) -> void:
	if which != _hit_stop_timer:
		return  # 已被更长的顿帧取代，让位
	Engine.time_scale = 1.0


## 场景退出兜底：顿帧定时器若还在挂起状态，time_scale 不能残留压低值；
## 同时停掉模拟驱动（回主菜单后旧世界不再后台空转 tick）
func _exit_tree() -> void:
	Engine.time_scale = 1.0
	_hit_stop_timer = null
	# 总览线程兜底收尾（正常路径 _apply_overview 已 join；极端时序下阻塞等待，
	# 避免 SceneManager 换场景后线程还在写已释放的缓存）
	if _overview_thread != null:
		_overview_thread.wait_to_finish()
		_overview_thread = null
	# 退出世界前把快照暂存进 GameState：① 同会话回菜单再"继续冒险"时
	# game_world._ready 能直接恢复世界（否则会撒初始种群开新世界）；
	# ② 菜单期间 WorldSim.sim 已空，save_now 靠这份缓存才能保住 ecology 键；
	# ③ 世界时钟（昼夜相位/天数）一并入快照，"继续冒险"接回真实时刻
	if _sim != null:
		var snap := _sim.to_dict()
		snap["day_time"] = WorldSim.day_time
		snap["game_day"] = WorldSim.game_day
		GameState.ecology_snapshot = snap
	# _exit_tree 的组查询可能已看不到先退出树的子节点；直接取仍挂在本根下的
	# Player，保证测试卸载/异常换场景也能留下最后位置（正常菜单路径此前已实时保存）。
	var player := get_node_or_null("Player")
	if player != null and player.has_method("save_snapshot"):
		GameState.player_snapshot = player.save_snapshot()
	WorldSim.stop()


## 飘血数字：受击点冒数字上飘淡出（玩家受伤红色更大、怪物受伤米黄、元素克制橙色加大）；设置可关
func _on_damage_number(pos: Vector2, amount: int, is_player_hurt: bool, is_effective := false) -> void:
	if not bool(GameState.settings.get("damage_numbers", true)):
		return
	_spawn_damage_number.call_deferred(pos, amount, is_player_hurt, is_effective)


func _spawn_damage_number(pos: Vector2, amount: int, is_player_hurt: bool, is_effective := false) -> void:
	# 游标锚定扫描空闲 Label（隐藏 = 动画已结束）：O(到下一空闲的距离)，密集战斗下
	# 通常 1~2 步；无空闲则增长池（不抢在途动画中的 Label——其 tween 仍持有写权）
	var label: Label = null
	var pool_size := _dmg_label_pool.size()
	for i in pool_size:
		var candidate: Label = _dmg_label_pool[(_dmg_pool_cursor + i) % pool_size]
		if not candidate.visible:
			label = candidate
			_dmg_pool_cursor = (_dmg_pool_cursor + i + 1) % pool_size
			break
	if label == null:
		label = Label.new()
		label.z_index = 50
		add_child(label)
		_dmg_label_pool.append(label)
		_dmg_pool_cursor = 0
	label.visible = true
	label.text = str(amount)
	if is_player_hurt:
		label.label_settings = _dmg_style_player
	elif is_effective:
		label.label_settings = _dmg_style_effective
	else:
		label.label_settings = _dmg_style_normal
	label.modulate.a = 1.0
	label.global_position = pos + Vector2(randf_range(-14.0, 14.0), randf_range(-30.0, -14.0))
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 64.0, 0.7)
	tween.tween_property(label, "modulate:a", 0.0, 0.7).set_delay(0.2)
	tween.chain().tween_callback(label.hide)


func _make_dmg_style(font_size: int, color: Color) -> LabelSettings:
	var style := LabelSettings.new()
	style.font_size = font_size
	style.font_color = color
	style.outline_size = 6
	style.outline_color = Color(0, 0, 0, 0.6)
	return style
