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
"$GODOT" --headless --path Code -s tests/sim_test.gd          # 生态不变量单测（纯逻辑，20 项）
"$GODOT" --headless --path Code -s tests/balance_test.gd      # 数值平衡校验（12 区域×物种手感区间）
"$GODOT" --headless --path Code res://tests/combat_test.tscn --quit-after 100000   # 战斗闭环+冲刺/重击/法弹/赏金验证（约 10s 自行退出）
"$GODOT" --headless --path Code res://tests/save_test.tscn --quit-after 5000       # 存档读写/坏档防御/商店购买
"$GODOT" --headless --path Code res://tests/pacing_test.tscn --quit-after 100000   # 节奏浸泡：拟人机器人 10 游戏分钟（首升/Lv3/金币/压力/生态六项区间，约 2.5 分钟真实时间）
"$GODOT" --headless --path Code -s tools/generate_terrain.gd                      # 重新生成 6 张群系地表 PNG（确定性 seed，约 30s）
"$GODOT" --path Code --resolution 1280x720 res://tests/screenshot.tscn            # 视觉截图（图形模式 3s 截屏到 /tmp/hotw_shot.png）
```
主场景已切换为 scenes/ui/main_menu.tscn（开始/设置/重置世界）；测试直接加载 main.tscn/combat_test.tscn 不受影响。
无输出且退出码 0 = 通过。改生态层必跑 sim_test；改战斗/AI/场景必跑 combat_test；改 GameState 必跑 save_test；改数值必跑 balance_test。测试场景会自动关闭自动存档（GameState.save_enabled），不污染真实进度。
iOS 一键导出装机（前置：Xcode 已登录账号 + 设备已连接）：仓库根 `./ios-run.sh`（输出在 build-output/，勿放回 Code/build/ 防资源自污染）。

## 目录结构（Code/）

```
autoload/    EventBus(全局信号) GameState(养成进度+存档) TouchInput(触屏中转) WorldSim(生态tick驱动桥) SfxManager(占位音效)
scripts/
  ecology/     ★ 生态模拟纯逻辑层（EcologySim/SimRegion/MonsterInstance/SpeciesData/SpeciesCatalog 六物种）
  character/   角色养成数据（CharacterStats）
  combat/      战斗公式（CombatMath 静态方法）
  player/      玩家控制器（普攻+冲刺无敌帧）
  monsters/    MonsterBase 状态机基类 + 六物种子类(goblin/slime/boar/spider/ant/guardian) + projectile + 血条
  ui/          HUD、虚拟摇杆、小地图
  main/        game_world：世界装配 + 模拟桥接 + 区域检测 + 飘血；tutorial：引导/生态事件播报
scenes/      main / player / monsters / ui（.tscn）
tests/       sim_test.gd（生态单测）、combat_test.tscn（战斗自动化）、save_test.tscn（存档）
assets/      creatures/（CC0 像素精灵）、terrain/（程序合成群系地表）、sfx/（Kenney CC0 音效），许可证随附
```

## 世界与物种速查

- 六张相连地图由 `scenes/main/main.tscn` 的 Marker2D 数据驱动：terrain（地形，决定物种栖息地）/ threat（威胁系数，强度与奖励倍率）/ capacity（区域总承载，种间竞争）/ neighbors（扩张邻接）
- 六物种战斗×生态差异见 `scripts/ecology/species_catalog.gd` 头部注释；新增种族 = SpeciesCatalog 加配置 + MONSTER_SCENES 登记场景

## 架构铁律（违反=返工）

1. **`scripts/ecology/` 只允许纯逻辑类**（RefCounted/Resource + 信号，`Vector2` 世界坐标可作数据），**禁止引用 Node/场景树/get_tree**。它是未来服务端权威模拟的整体搬迁单元。
2. 模拟状态只能经 `EcologySim.tick()` / `report_killed()` 变更（单点权威）；表现层（Node）只消费信号与快照，不改写模拟数据。
3. 跨模块通信一律走 `EventBus` 信号；模块间不互相持有引用。
4. 输入必须双通道同源：键盘走 Input Map 动作（move_left/right/up/down、attack），触屏走 `TouchInput`；玩法代码禁止判断平台。
5. 数值公式集中在 `CharacterStats`（玩家衍生属性）与 `SpeciesData`/`MonsterInstance`（怪物衍生属性）的方法里，全部视为 v0 占位，改动只动公式不动调用方。

## 约定与注意事项

- 注释与文档用中文；Godot 4 GDScript 语法（`@onready`/`@export`/typed signals）
- 仓库位于 iCloud Drive 路径（含空格与中文）：shell 命令中的路径必须加引号；`.godot/` 缓存受同步干扰导致异常时先清理再重试
- `.godot/`、`build/`、`*.csproj`、`*.sln` 均被忽略；`.uid` 文件由编辑器生成，随代码提交
- 行尾 LF；远程 github.com/L261173157/Heart-Of-The-World，主分支 `main`
- 新想法一律写入 `Documents/开发计划.md` 的"待定池"，不得直接进当前里程碑代码
