# AGENTS.md — Heart Of The World（Hotw / 《心之世界》）

iOS 优先的 2D 动作游戏：ACT 无锁定战斗 + 角色养成 + **怪物生态自演化**（种族繁衍/扩张/死亡，是本作核心卖点）。当前路线：**先单机，后加联机**（M2 才引入服务器）。项目由个人开发者业余时间维护，范围控制是第一原则。

## 必读文档（改动前）

- `Documents/开发计划.md` — **当前生效**的范围/里程碑/决策，与代码冲突时以其为准
- `Documents/策划纲要.md` — 长期愿景（完整 MMO 设计），实现时取其子集，不要按它扩张范围

## 技术栈与硬性约束

- **Godot 4.7 + 纯 GDScript**（Steam 标准版，GDScript 内置、无 .NET）。禁止引入 C#/.NET（iOS 导出为实验性支持，且增加导出链复杂度）。重计算需求未来用 GDExtension，不用 C#。
- 渲染器：Mobile（iOS 设备）；2D 游戏，不使用 3D 资产
- 真正的 Godot 工程根在 `Code/`（不是仓库根）；打开 `Code/project.godot`
- iOS 导出：预设已配（`Code/export_presets.cfg`），Team ID / 签名留空待用户填写；`build/` 已忽略

## 无头快速验证（改完代码先跑这个，别开编辑器）

Steam 版 Godot 二进制：
```
GODOT="$HOME/Library/Application Support/Steam/steamapps/common/Godot Engine/Godot.app/Contents/MacOS/Godot"
"$GODOT" --headless --path Code --import   # 首次/改资源后导入并暴露脚本解析错误
"$GODOT" --headless --path Code --quit     # 单帧加载主场景的冒烟测试
"$GODOT" --headless --path Code -s tests/sim_test.gd          # 生态不变量单测（纯逻辑，123 项断言）
"$GODOT" --headless --path Code -s tests/balance_test.gd      # 数值平衡校验（6 地形×物种手感区间，v4 起按地形去重展开）
"$GODOT" --headless --path Code res://tests/combat_test.tscn --quit-after 100000   # 战斗闭环+五技能/连击/赏金验证（据点式流式下测试自动传送至目标据点，~15s 自行退出）
"$GODOT" --headless --path Code res://tests/save_test.tscn --quit-after 5000       # 存档读写/坏档防御/商店购买
"$GODOT" --headless --path Code res://tests/ui_flow_test.tscn --quit-after 8000    # UI/流程冒烟：菜单→世界→死亡重生→回菜单→继续（TERRAIN_THEMES 映射/三路音量总线/快照恢复 26 项）
"$GODOT" --headless --path Code res://tests/pacing_test.tscn --quit-after 100000   # 节奏浸泡：拟人机器人 10 游戏分钟（首升/Lv3/金币/压力/生态六项区间，约 2.5 分钟真实时间）
"$GODOT" --headless --path Code -s tools/generate_terrain.gd                      # 生成 6 张群系地表 PNG（v4 起仅主菜单装饰条消费；游戏内地表为运行时分块绘制）
"$GODOT" --headless --path Code -s tools/generate_world_map.gd                    # 生成小地图总览 PNG（世界 v5 起小地图运行时按种子自采样，此图仅留档参考，可不重跑）
"$GODOT" --headless --path Code -s tools/generate_obstacle_tileset.gd             # 障碍瓦片集 data/{obstacle,nav}_tileset.tres（改 ObstacleField 的 KIND_INFO/类型表后必须重跑；贴图内嵌 tres 不产 PNG）
"$GODOT" --headless --path Code -s tools/obstacle_probe.gd                        # 障碍覆盖率探针（调 RECIPES 阈值后看各群系实测%；sim_test 分带守闸）
"$GODOT" --headless --path Code -s tools/slice_spritesheets.gd                    # 从 sheets/ 精灵表重切帧动画 SpriteFrames（含色相烘焙，见文件头注）
"$GODOT" --headless --path Code -s tools/slice_spritesheets_v2.gd -- slice        # 高清素材（~/hotw-assets/，LuizMelo/Admurin）切帧+烘焙 → 逐帧 PNG（2026-09-08 美术升级；**现为回退位**，线上美术已换自建卡通，见下两行）
"$GODOT" --headless --path Code -s tools/generate_creatures.gd                    # ★ 自建卡通生物帧生成（SDF 矢量卡通：22 物种+FX 三件+玩家英雄+图标；改风格/调色板/骨架后重跑，再 --import）
"$GODOT" --headless --path Code -s tools/generate_creatures.gd -- pack           # 组装引用式 SpriteFrames（die/play 非循环；接线=data/species/*.tres 一行 frames_override，场景 scale 与 v2 姐妹共档）
"$GODOT" --headless --path Code -s tools/generate_creatures.gd -- sheet          # 风格样张 /tmp/hotw_cartoon_sheet.png（contact sheet，风格验收用）
"$GODOT" --headless --path Code -s tools/generate_tiles.gd                       # 卡通瓦片图集 cartoon_tileset.png（36 地形格+9 道具，与 na_tileset 同网格同坐标；重跑后 generate_obstacle_tileset/generate_terrain 须跟着重跑）
"$GODOT" --headless --path Code --import                                           # 导入上一步产出的帧 PNG（v2 切帧后必跑，再进 pack）
"$GODOT" --headless --path Code -s tools/slice_spritesheets_v2.gd -- pack         # 组装引用式 SpriteFrames（idle/walk/attack/die 统一动画名）
"$GODOT" --headless --path Code -s tools/build_ai_strips.gd                        # ★ 美术 v4 AI 素材接入（P0 已验证）：~/hotw-assets/ai/<物种>/{base,attack,hurt,melt,puddle}.png 抽白底+程序补间 → pilot/current/<物种>/ 四动画条带；之后 slice v2 → import → pack → .tres frames_override（方案真源 Documents/美术方案-v4.md）
"$GODOT" --headless --path Code -s tools/numbers_audit.gd                        # 数值全盘量化审计（构筑/对刀/经济/生态/寿命基线表）
"$GODOT" --headless --path Code -s tools/eco_probe.gd                            # 生态长程探针（2000 tick 逐物种存活占比/灭绝次数/死因——捕食结构调参的实证工具）
python3 Code/tools/subset_font.py    # 重新生成内嵌中文字体 assets/fonts/（iOS 26 系统字体回退失效须自带 CJK 字体；游戏文案缺字变豆腐块时重跑，桌面端缺字静默回退看不出来）
"$GODOT" --headless --path Code -s tools/generate_icon.gd                         # 重新生成 App 图标 1024（六群系像素心；导出走单一图标模式自动派生全 iOS 尺寸，改参数重跑本工具即可）
"$GODOT" --path Code --resolution 1280x720 res://tests/screenshot.tscn            # 视觉截图（3s+3.35s 双帧到 /tmp/hotw_shot{,_b}.png，帧差验证动画；HOTW_SHOT_POS="x,y" 指定世界坐标，v4 大世界采样点：出生平原 21888,60301 / 雪原 753707,738957 / 熔岩 774085,696114 / 平原|沼泽交界 83882,99810；HOTW_SHOT_UI="menu" 截主菜单+冒险档案面板，"codex" 截图鉴；HOTW_SHOT_NIGHT=1 强制满夜取证提灯+障碍阴影投射）
```
主场景为 scenes/ui/main_menu.tscn（开始/继续冒险、新的冒险、冒险档案、设置、退出；暂停菜单含保存进度）；测试直接加载 main.tscn/combat_test.tscn 不受影响。
无输出且退出码 0 = 通过。改生态层必跑 sim_test；改战斗/AI/场景必跑 combat_test；改 GameState 必跑 save_test；改数值必跑 balance_test；改 HUD/菜单/流程必跑 ui_flow_test。测试场景会自动关闭自动存档（GameState.save_enabled），不污染真实进度。
iOS 一键导出装机（前置：Xcode 已登录账号 + 设备已连接）：仓库根 `./ios-run.sh`（输出在 build-output/，勿放回 Code/build/ 防资源自污染）。
iOS TestFlight/App Store 上传通道（前置：Xcode 已登录团队账号 + ASC 已建 App 记录「心之世界」6808568562）：仓库根 `./ios-upload.sh`——Release 导出→自动签名 Archive→app-store 重签出 ipa→校验→**经 Xcode 会话免密码上传**（xcodebuild destination=upload，2026-09-04 实证；内部测试组自动分发）；build 号自动递增。
**安全约束（上传通道）**：上传属对外发布操作，Agent 不得自动执行，每次须用户当次明确确认。

## 目录结构（Code/）

```
autoload/    EventBus(全局信号) GameState(养成进度+存档) TouchInput(触屏中转) WorldSim(生态tick驱动桥) SfxManager(音效+群系BGM)
scripts/
  ecology/     ★ 生态模拟纯逻辑层（EcologySim/SimRegion/MonsterInstance/SpeciesData/SpeciesCatalog/CombatBandMath 目标带/EconomyMath 经济/BiomeMap 世界群系结构（种子参数化）/ObstacleField 障碍场/LandmarkRegistry 地标——22 物种）
  character/   角色养成数据（CharacterStats）
  combat/      战斗公式（CombatMath 静态方法）
  player/      玩家控制器（普攻+冲刺无敌帧；HeroMotion v2 动作系统：起停加减速/步频同步/锁相bob/冲刺前倾）
  monsters/    MonsterBase 状态机基类（含 _update_anim 状态→帧动画映射/ShadowBlob 落影/挤压回弹）+ 六 AI 原型子类(melee_swarm/splitter/charger/ranged/soldier/guardian) + shadow_blob + projectile + 血条
  ui/          HUD、虚拟摇杆、小地图（世界总览纹理 + 实时彩点）
  main/        game_world：世界装配 + 模拟桥接 + 区域/地标 Area2D 检测 + 迷雾揭示 + 表现层流式生成（怪物/巢穴按玩家距离进出）+ 飘血；tutorial：引导/生态事件播报；world_deco：按地表块撒放装饰；vision_lighting：昼夜压暗+提灯阴影；quest_manager：地标 NPC 委托（狩猎/捣巢/探索，真源 GameState.quests）；terrain/：terrain_painter 分块绘制 + chunk_streamer 流式加载 + obstacle_tile_layer 障碍瓦片（视觉+StaticBody2D 碰撞） + nav_tile_layer 导航瓦片
data/species/  种族配置 .tres（数据驱动，唯一数据源；新增种族改这里不改代码）
scenes/      main / player / monsters / ui（.tscn）
tests/       sim_test.gd（生态单测）、combat_test.tscn（战斗自动化）、save_test.tscn（存档）、ui_flow_test.tscn（UI/流程冒烟）、pacing_test.tscn（节奏浸泡）、screenshot.tscn（视觉截图）
assets/      creatures/sheets/（cartoon_tileset.png=现行瓦片图集（generate_tiles.gd 产物，与 na_tileset 同网格同坐标）；na_tileset.png=旧源回退位）、creatures/frames/（SpriteFrames .tres：**现行=美术 v4 全家（2026-09-11 全量上线）：22 套 `<物种>_pilot` + hero_pilot（成熟版剑客，三段连击独立招式）+ fx_slash/fx_slash_gold/fx_burst，全部 ComfyUI 本地生成（方案真源 Documents/美术方案-v4.md；生成管线 ~/comfyui-workspace/ + ~/hotw-assets/ai/；怪物回退=v3/v2 .tres 一行切，英雄回退=player.tscn 一行改 hero_cartoon）**）、icons_cartoon/（**AI 生成 19 枚 64px**，hud.gd/main_menu.gd 零改动换源）、landmarks/（**AI 地标精灵 11 种**，LandmarkMarker 消费，缺图回退圆环）、terrain/（region_*.png=**AI 厚涂 KeyArt 6 张**主菜单地平线 + 运行时地表种子图集源 + world_map.png 留档）、sfx/（Kenney CC0 音效补位）、na/audio/（NA CC0 音效 7 个 + 群系 BGM 7 曲，取用清单见 LICENSE 文件）
```

## 世界与物种速查

- **v4 世界结构（2026-09-08 大地图重构）**：80 万像素见方（端到端直线跑图 76 分钟），唯一真源是 `scripts/ecology/biome_map.gd`（BiomeMap 纯逻辑：抖动网格 Voronoi + 域扭曲 → ~100 个犬牙交错群系斑块；出生角强制平原，威胁沿对角线递增至熔岩）。`scripts/main/world_config.gd`（WorldConfig）把 BiomeMap 装配成区域定义（id/terrain/threat/capacity/center/neighbors）与按地形的初始种群表——改世界形状/带位改 BiomeMap（改后须重跑 generate_world_map），改种群分布改 WorldConfig 的 TERRAIN_POPULATION
- 地表为运行时分块绘制（terrain/），怪物/巢穴节点按玩家距离流式生成（game_world `_stream_pass`），模拟层数据始终全局
- **世界 v5 障碍与探索层（2026-09-08）**：每档全新世界（GameState.world_seed，「新的冒险」重掷；旧档迁移回 DEFAULT_SEED 零损失）。障碍唯一真源是 `ecology/obstacle_field.gd`（FastNoiseLite 确定性，群系差异化配方：平原稀疏 4%/森林树墙 26%/丘陵分段岩脊 21% 等，斑块中心 600px·出生点 1200px 抑制区，sim_test 覆盖带守闸）；表现层 `terrain/obstacle_tile_layer`（TileMap：贴图 y-sort 树冠+瓦片物理墙+LightOccluder 阴影）与 `terrain/nav_tile_layer`（仅导航不渲染，整层单 NavigationRegion，窗 7 块 > 怪物流式 2800px）。怪物 AI = NavigationAgent2D（追击/逃跑/迁徙/巡逻全导航 + RVO 同族避让 + 远程 `intersect_ray` 视线、被掩体挡视线时沿路径逼近重取——射线终点须回撤 28px 避开玩家本体碰撞）。视野 = `vision_lighting.gd`（昼夜 CanvasModulate + 提灯 PointLight2D 阴影投射；白天灯关零成本）。区域进入检测与地标发现均原生 Area2D（BiomeMap.patch_polygons 同源栅格派生多边形；`ecology/landmark_registry.gd` 每斑块 1~2 地标）；战争迷雾 GameState.explored（200×200 位图）开局全黑随移动揭示，小地图未探索盖黑+已发现地标色点。营地/子代/复活点选点经 ObstacleField 通行性校验。**液体场**（同源真源）：snow/hill 深水阻挡（可见水核 +4% 噪声保守边距，浅水滩可趟）、lava 熔岩池可通行但站立灼烧（玩家 3% 最大生命/0.5s，环境伤不走无敌帧）；terrain_painter 的水材质层消费同一 `liquid_kind_in`（可见水 == 判得到的水，抑制区同口径）。**可破坏障碍**：rock/bones/crystal/ice 两刀可碎（普攻射线/法弹破块开路，碎屑演出 + 概率掉金币），摧毁覆盖层存档 v5 往返、导航层即时补可走格；碰撞不依赖瓦片物理——Godot 4.7 TileMapLayer 有"格子只注册视觉、物理体静默不构建"的时序坑（早建/重铺均复现无稳定规避），由 obstacle_tile_layer 每块挂 StaticBody2D 圆形碰撞体承担（游戏内 MOUNTCHECK 哨兵回归守闸）。**地标 NPC + 任务 v1**：石环=营地猎人(狩猎)/荒废遗迹=遗迹学者(捣巢)/精灵泉=泉水守望者(探索)，靠近按攻击键交互接单（不消耗冷却），达成自动结算金币+经验（EconomyMath 与赏金同源）；数据真源 GameState.quests（存档 v5），接单内容按（地标×已完成数）确定性生成，HUD 任务行常驻进度
- **怪物据点制（MMO 语义，2026-09-08）**：怪物属于地图不属于玩家——每斑块每物种一个确定性营地（`EcologySim.camp_pos`，环距三档 0.05/0.16/0.27 格），初始个体扎根营地 ±180，繁衍子代在亲代 ±220 出生（据点逐代外扩），迁徙/重引入重分配新营地，Boss 盘踞斑块中心，巢穴与营地同址（捣巢=端老窝）。表现层只按「实例 spawn_pos vs 玩家距离」进出节点（2400 生成/2800 回收），位置不随玩家漂移；存活实例必有非 INF 位置（老档恢复时按营地补齐）
- 种族战斗×生态差异见 `data/species/*.tres`；新增种族 = 复制任一 .tres 改参数 + MONSTER_SCENES 登记表现场景 + WorldConfig.TERRAIN_POPULATION 撒初始种群（三步清单见 species_catalog.gd 头注）

## 架构铁律（违反=返工）

1. **`scripts/ecology/` 只允许纯逻辑类**（RefCounted/Resource + 信号，`Vector2` 世界坐标可作数据），**禁止引用 Node/场景树/get_tree**。它是未来服务端权威模拟的整体搬迁单元。
2. 模拟状态只能经 `EcologySim.tick()` / `report_killed()` 变更（单点权威）；表现层（Node）只消费信号与快照，不改写模拟数据。
3. 跨模块通信一律走 `EventBus` 信号；模块间不互相持有引用。
4. 输入必须双通道同源：键盘走 Input Map 动作（move_left/right/up/down、attack），触屏走 `TouchInput`；玩法代码禁止判断平台。
5. 数值公式集中在 `CharacterStats`（玩家衍生属性+技能常量真源）与 `SpeciesData`/`MonsterInstance`（怪物衍生属性）的方法里；手感目标带与反推在 `CombatBandMath`，经济公式在 `EconomyMath`（ecology/，纯逻辑）。改数值只动定义处，balance_test/pacing_test 自动守闸。

## 约定与注意事项

- 注释与文档用中文；Godot 4 GDScript 语法（`@onready`/`@export`/typed signals）
- 仓库位于 iCloud Drive 路径（含空格与中文）：shell 命令中的路径必须加引号；`.godot/` 缓存受同步干扰导致异常时先清理再重试
- `.godot/`、`build/`、`*.csproj`、`*.sln` 均被忽略；`.uid` 文件由编辑器生成，随代码提交
- 行尾 LF；远程 github.com/L261173157/Heart-Of-The-World，主分支 `main`
- 新想法一律写入 `Documents/开发计划.md` 的"待定池"，不得直接进当前里程碑代码
