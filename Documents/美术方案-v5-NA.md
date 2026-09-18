# 美术方案 v5 · Ninja Adventure 全面主题化（NA 回归）

> 2026-09-17 立项并当日全量落地。用户拍板：精简纯 NA 阵容 / 三忍皮肤切换 /
> AI 素材全删（含 CG 开场）/ NA 包全类别（英雄、NPC、怪物、Boss、森林、地牢、
> 建筑、道具、VFX、UI、音效、音乐）全部投入使用。
> **本文取代 美术方案-v4.md 成为现行真源**（v4 保留作历史档案）。

## 1. 素材源与库存

- **主源**：Ninja Adventure（pixel-boy，CC0）。GitHub sparklinlabs/superpowers-asset-packs
  通道已全量入库（itch 新版包沙箱不可达；用户后续手动下载后可再增量，未阻塞）。
- **仓库布局**：
  - `assets/creatures/sheets/na_*.png`：22 怪表 + 3 忍 + na_tileset（448×640，16px 网格）
  - `assets/na/characters/{1-25,dog}.png + faceset/`：角色表与立绘
  - `assets/na/fx/1-20.{png,gif}`：特效条带；`assets/na/bg/`：背景动画 gif+条带
  - `assets/na/items|weapons|hud/`：图标源；`assets/na/structures/`：建筑烘焙件
  - `assets/na/audio/{musics×19, sounds×45}`
- **切帧真源**：`tools/slice_spritesheets.gd`（47 条目：22 怪 + 三忍 + 4 NPC +
  18 fx；tres 内嵌纹理免 import）。改表重跑即可。
- **建筑烘焙**：`tools/bake_structures.gd`（na_tileset 已验收矩形 → ×2 PNG）。

## 2. 阵容（22 物种 = NA 22 张怪表 1:1）

妖鬼(oni)/萌芽怪(sprout)/野猪(pig)/绿龟(turtle)/红史莱姆(slime)/绿蛙(frog)/
曼德拉草(mandrake)/蘑菇怪(mushroom)/树人Boss(treant)/冰史莱姆(teal)/蝙蝠(bat)/
沼泽蟹(crab)/红章鱼(octopus)/企鹅/幽灵/甲虫(beetle)/松鼠(squirrel)/仙人掌怪(cactus)/
锹形虫王Boss(stag_beetle)/火鸟(phoenix)/石像鬼(gargoyle)/龟王Boss(sea_turtle)。
- 删除：小魔鬼/青史莱姆（烘焙变体凑数）、雪怪（形象归 Boss）。
- **旧档迁移**：`SpeciesCatalog.SPECIES_RENAME_MAP`（11 项，青史莱姆/小魔鬼并入
  同形物种）——图鉴计数/生态快照（实例·巢穴·Boss 计时·灭杀名单）/任务字段统一走它。
- 种群/捕食链：见 `world_config.gd` TERRAIN_POPULATION（六地形 9/11/9/9/10/6）与
  各 .tres prey 字段；balance/sim/pacing 三测守闸。

## 3. 英雄与皮肤

- 蓝忍为默认（player.tscn 接 frames/ninja）；**三忍切换**：设置面板「忍者外观」
  循环行 → `GameState.settings.hero_skin`（blue/dark/white，白名单消毒）→
  player._ready 换帧（动画名同构零逻辑差异）。16px 帧 × scale 4.8 ≈ 77px 屏幕高。

## 4. 环境与结构

- 地表/障碍/装饰/主菜单 KeyArt 四消费方同坐标契约指向 **na_tileset.png**（与旧
  cartoon_tileset 同网格，零代码换源）。
- **出生营地**：房屋×2+鸟居（structures 烘焙件，StaticBody 挡身位）+行商 NPC
  （characters/6，对话确认开商店）+420px 安全区每秒 3% 缓回血。
- **Boss 城塞（地牢）**：hill/lava 最远斑块中心确定性生成——castle 墙格环形
  （13×9 格，南门 3 格洞，`ObstacleField.DUNGEON_*`）+ 内腔恒空 + Boss 盘踞 +
  宝箱（Boss 被讨伐期间可开：金币 EconomyMath 同源 + 光柱/金闪/secret 音效；
  Boss 重生即重置可再开）。`tools/dungeon_check.gd` 为结构回归探针；
  截图取证 `HOTW_SHOT_DUNGEON={0,1}[in]`（运行时按种子自取城塞坐标，永不过期）。

## 5. NPC 与对话

- 三地标 NPC（石环=营地猎人/8、荒废遗迹=遗迹学者/4、精灵泉=泉水守望者/7）+
  营地行商（6）：NA 角色精灵（idle/walk 待机踱步）+ 头顶名牌。
- **对话气泡**（HUD）：NA dialogue-bubble 九宫格 + faceset-box + 同号立绘 +
  yes/no 按钮。流程：攻击键开泡（offer）→ 攻击=确认接单 / 冲刺=关闭（触屏同
  通道；GameState.dialogue_open 路由，防对话期挥刀）。QuestManager.offer/accept
  分离保证生成确定性。

## 6. VFX（19/20 事件化）

通道：`EventBus.fx_requested(kind,pos,scale)` → game_world.FxLayer（TABLE 15 条 +
player 本地 slash 系 3 条 + 宝箱 pillar 等）。映射：普攻/强化挥砍(2/1)、重击爆裂(9)、
守卫砸击火爆(10)、死亡烟(11/12)、Boss重生光束组(20)、开箱光柱(15)、法弹魔光(6)、
元素克制焰/霜(5/8)、怪命中邪光(13)、治疗蓝闪(18)、聚气(7)、升级白闪(16)、
任务金闪(19)、金币闪光系(17)。**预留**：fx/14 光束、fx/3、fx/4（未验证身份）。

## 7. UI 与音频

- HUD 图标 19 槽全 NA 源（items/weapons/hud）；**heart 五帧条带**按血量换帧
  （0 空→4 满）；MP 条头苦无。设置面板加「忍者外观」行。
- **音乐 19 曲映射 10 槽**：六群系(4/2/9/12/5/13)+菜单(10)+城塞(7)+Boss临场(16)
  +营地(8)；优先级调度：活Boss临场>城塞内>营地>群系（game_world._refresh_music
  4Hz，同曲不重启）。**预留池**：theme-1/3/6/6s/11/14/15/17/18（情绪未验证，
  按需补位勿硬塞）。
- **音效（2026-09-17 完整包增量后）**：Kenney 全退役——hurt/dash/heavy/region 换 NA 分类件（na_hit2/na_whoosh/na_impact/na_bonus2），levelup/died 换 Jingles（LevelUp1/GameOver）。老包编号音效 1-19 与 magic.wav 未验证身份，留库。

## 8. 已删除（git e9af73a 快照可溯）

AI 素材全家（22×_pilot/hero_pilot/medieval/martial/_cartoon/_v2 帧、icons_cartoon、
landmarks AI、deco AI、cartoon tilesets、world_map.png）、CG 链（intro.ogv +
cutscene_player + seen_intro_cg 全链）、过期工具五件（generate_tiles/
generate_creatures/slice_spritesheets_v2/build_ai_strips/generate_world_map）。

## 9. 验收记录（2026-09-17）

六项无头测试全绿（sim 123 断言/balance/combat 41/save 含迁移用例/ui_flow 含
音乐优先级断言/pacing 六带）；结构探针 dungeon_check 通过（37 墙+3 门洞+内腔净空）；
运行时实证：城塞宝箱/Boss 节点在场。取证图：/tmp/v5_*.png（营地/城塞/菜单/
夜晚/战斗 fx）。**遗留**：iOS 包体核对（音频全量后，超预算则 ogg 降码率）。

## 10. Godot 4 官方示例包评估（2026-09-17，~/hotw-assets/na-full-dl/na-demo/）

37 脚本/21 场景的关卡制小框架——**约定确认 + 局部借鉴，不搬架构**（我们是流式
大世界+生态模拟，整体不兼容）。逐项结论：
- **约定验证（零改动）**：精灵表 布局（列=朝向 0下/1上/2左/3右，行=帧 0-3走/4攻/5跳/6死）与
  IMAGE_SPEED=6 同我们的 col3+flip 切帧、6fps 完全一致；受击白闪+震屏+粒子与我们同构。
- **借鉴①（高价值）**：`theme/nine_path_*.png` 官方九宫格 UI 件 12 张+像素字体——
  对话气泡/菜单/图鉴面板可换官方九宫格铺底，比单张 dialogue-bubble 耐铺。
- **借鉴②**：`sprite_character.gd` 四方向渲染（frame_coords.x=方向列）——完整包
  903 角色均为四向表，NPC/角色升级时做真四向（上下移动不再侧身 flip）。
- **借鉴③**：`transition.gd`（41 行淡入淡出）+ `teleporter.gd`（Area2D 成对传送）——
  未来「进房屋室内」（Interior tileset）的现成参考件。
- **不借鉴**：fog（shader alpha 位图方案弱于我们的迷雾系统）、camera_grid（复古
  分格相机与连续相机路线不同）、behavior/damage/destroyable（我们对应系统更完整）。

## 11. 三借鉴件落地（2026-09-17 第二批）

- **①九宫格 UI**：theme 件入库 `assets/na/ui/`（np_dialogue/np_panel/np_archive/np_dark+字体）。
  消费：对话气泡底板= np_panel 暗蓝灰（16px×4 放大、边距带 20，NinePatchRect）；
  glass_theme 面板调色向 np_6 同系（StyleBoxTexture 九宫格边距 API 在 4.7 缺失，
  弃用改同色系平样式——暗底保白字对比度）。np_dark 用作室内墙视觉。
- **②四方向渲染**：slicer 增 `dirs` 模式（idle/walk 的 down/up/left 变体，官方
  sprite_character 同构），三忍+4 NPC 已切；玩家纵向移动/站定用 up/down 帧，
  横向保持右向+flip 老路径；NPC 玩家靠近时转向玩家。
- **③房屋可进**：门前 Area2D 传送门（Zelda 式踩上即进）→ 淡入淡出过场
  （CanvasLayer 90 黑幕 0.22s/0.3s，相机 snap_to_player 防长镜头滑移）→ 世界内嵌
  室内口袋（ObstacleField.INTERIOR_POCKETS 出生点正南 52 万 px ×2 间，障碍/液体
  双抑制）＝木地板平铺+墙环 StaticBody+床+南门回程传送。截图 HOTW_SHOT_INTERIOR=N。

## 12. 完整包全量增量（2026-09-17 第三批，b9283b6）

- **NPC 命名角色**：营地猎人→Hunter、遗迹学者→Inspector、泉水守望者→SorcererOrange、
  行商→Villager（64×112 同布局直接换装+专属 Faceset 101-104，四方向+踱步保留）。
- **Boss 专属形象**：锹形虫王→GiantBlueSamurai 大武士（48px×12帧 Idle/Walk/Hit）、
  龟王→GiantFlam 火焰魔王（50px 条带）；slicer 新增「按动画独立条带源+cell 格宽」
  Boss 模式；SpeciesData.visual_scale（0.33/0.32）对齐 16px 基准体型。
- **物种扩容 22→29**：战斗怪 雪熊(snow charger)/独眼巨人(hill soldier)/眼魔(swamp
  ranged)/火龙(lava ranged)；**被动动物** 鸡(plains)/浣熊(forest)/鹦鹉(swamp+forest)
  ——SpeciesData.ambient（永不主动攻击+玩家近身即逃+balance 承伤带豁免），侧视
  32×16 双帧表走 strip 模式。种群表六地形重排（余量守恒），妖鬼捕食链+鸡。
- **城塞瓦片**：castle kind 换完整包 TilesetDungeon 专用墙砖（DERIVE.src_img 独立
  源机制），障碍图集重生成。
- **营地动画件**：水车(3帧)+旋转桨叶(2帧)+旗帜(4帧)，_add_animated_prop 通用挂件。
- **音乐升级**：城塞→"21 Dungeon"、Boss→"17 Fight"、营地→"33 Calm Village"
  （完整包具名曲目）。留库：其余 36 曲（Quicksand/WaterRipples 动画与沙漠/废弃
  村庄瓦片待后续地貌扩展）。

## 13. 玩法 v7 P0 物品系统取用（2026-09-18）

- **新增消费 items 图标 13 张**（此前 0 引用→接入）：消耗品 onigiri 饭团/sushi
  寿司/medipack 医疗包/life-pot 生命药剂/water-pot 竹水壶；材料 beaf 兽肉/fish
  鲜鱼/shrimp 鲜虾/octopus 章鱼足/tea-leaf 茶叶/scroll-fire 火之卷轴/scroll-rock
  岩之卷轴；物品栏按钮 jar 罐子。消费方：ItemCatalog（真源表）→ HUD 商店
  补给/收购页、物品栏格子、战斗快捷槽。
- **items 余量 15 张待 P1/P2**：big/little-treasure-chest（P1 钥匙宝箱）、
  gold/silver-key（P1）、gold-cup/silver-cup、arrow/ice-spike/kunai/shuriken
  （投射物图标候选）、calamari/empty-pot/milk-pot/noodle/sushi-2/tea-leaf 之外
  的食物变体（yakitori/honey/fish 已用或候补）——按"宁缺毋滥"口径不强行上。
- **HUD 侧零新增素材**：快捷槽/物品栏钮全部复用 HotwTheme 样式 + 已有图标。
