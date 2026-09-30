# 美术方案 v6 · Tiny Swords 全面主题化（分支 TinySwordsStyle）

> 真源文档。2026-09-20 立项。取代 v5（NA）成为本分支的视觉唯一标准；main 分支仍为 NA 主题，NA 素材与切帧表**全保留**可随时回滚（slicer 的 STYLE 开关）。

## 0. 背景与决策（用户拍板）

- 素材包：Pixel Frog《Tiny Swords》免费包（CC0），已入库 `Code/assets/ts/`（428 文件：410 PNG + 18 aseprite 源），来源与许可见 `Code/assets/ts/LICENSE.md`
- 三项口径：
  1. **怪物 = Free Pack 五色军团先行**（5 阵营×5 兵种人形单位）；itch 同页 `Tiny Swords (Enemy Pack).zip`（22+ 敌人）**后补**——到货后只改 slicer 帧源表，不动任何结构
  2. **音频一并换新**（Free Pack 零音频；见 §9）
  3. **UI 连全套一起 TS 化**（见 §8）
- 主题叙事：怪物生态 = 「五色军团割据大陆」——蓝（玩家/友军）、红/黄/紫/黑（四方敌对军团），Boss 为军团领主（大体型精英）

## 1. 素材包规格（实测）

| 类别 | 内容 | 规格 |
|---|---|---|
| Units | Blue/Red/Black/Yellow/Purple × Warrior/Archer/Lancer/Monk/Pawn | 逐动画单行横条；帧 192×192（=32 逻辑像素 ×6 预放大）；Lancer 例外 64×320（长枪竖画布，五向攻击） |
| 动画清单 | Warrior: Idle/Run/Attack1/Attack2/Guard；Archer: Idle/Run/Shoot+Arrow；Lancer: Idle/Run + 5 向×Attack/Defence；Monk: Idle/Run/Heal/Heal_Effect（**无攻击动画**）；Pawn: 裸版 Idle/Run + 工具版(Axe/Hammer/Knife/Pickaxe 各 Idle/Run/Interact) + 背货版(Gold/Meat/Wood 各 Idle/Run) | 单向（默认朝右），运行时 flip_h |
| Terrain/Tileset | Tilemap_color1~5（5 套配色同版式）+ Water Foam（岸边浪花条）+ Water Background + Shadow | 瓦片 64×64，图 576×384（9×6 格） |
| Buildings | 5 色 × Castle/House1-3/Tower/Barracks/Archery/Monastery | 单张静态图 |
| Resources/Decor | 树 Tree1-4 + 树桩 4 + 木堆/金矿/金块 6+羊(Idle/Move/Grass)/肉/工具 4 + 灌木 4/岩 4/水岩 4/云 8/橡皮鸭 | 混合尺寸（树单帧 256 宽） |
| Particle FX | Dust_01/02、Explosion_01/02、Fire_01~03、Water Splash | 64 或 192 帧横条 |
| UI | 按钮(蓝红×大小方圆×两态+Tiny)、BigBar/SmallBar(Base/Fill)、RegularPaper/SpecialPaper、丝带/横幅(Banner+Slots)、光标 4、Icons_01~12、头像表 Avatars_01~25、Swords、WoodTable+Slots | 头像表 256×256（4×4×64） |

**包内无**：怪物单位、King、音频、挥砍类特效、宝箱、室内件。

## 2. 尺寸校准原则

- TS 素材实测为 2× 预放大（192 画布=96 原生）。切帧=union bbox 定尺寸 + **画布以格心对称**（2026-09-20 错位根治：旧法贴 bbox 左上裁剪，宽画幅攻击帧把画布拉向一侧，身体轴偏离逻辑原点=阴影/攻击判定错位，实测 Lancer 偏 23~47 原生 px；TS 全家角色锚在格心，对称扩边后轴=画布中心=原点）+ ÷2 还原原生后**直出（k=1）**——帧尺寸见 frames_test EXPECTED_SIZES 白名单；fx/deco 沿用 bbox 锚定（VFX 帧内容逐帧游走，格心非其锚点）。
- 密度政策（2026-09-20「糊」根治定稿）：**角色像素密度与建筑同档**（建筑按最终显示分辨率烘焙、scale=1 被认可 ⇒ 角色也走原生）；显示端整数 scale 表达体型（小型 ×1、标准/大型 ×2、Boss ×2/3/7），素材像素 2×2 屏幕 px。
- 世界像素对齐：**瓦片 64→16（÷4）**，地形分块 512px/TS=16、障碍 CELL=32（源 64→÷2 或 256→÷8）、导航格全部不动——网格数学零改动。
- 体型/占地分离：`.tres visual_scale` 只管像素密度（凑整数渲染缩放），新增 `body_scale` 承接旧 visual_scale 的碰撞/血条占地语义（手感零变化）；史莱姆系特例 k=2（分裂子代需要 ×1 档位空间）。
- 英雄从四向动画降级为**侧向翻转型**（TS 单视角），HeroMotion 的 bob/前倾/步频同步保留。

## 3. 物种映射表（29；**显示名迁移缓办**——名字被 prey 捕食链/TERRAIN_BOSSES/种群表/任务按字符串引用，静默断链风险大于装饰收益；待 Enemy Pack 到货（怪物形象再大变）时统一迁移。物种 id/存档键完全不动）

蓝=友军（玩家/营地为蓝系），敌对军团按群系分布：plains=红、forest=黑/紫、snow=蓝黑、swamp=紫、hill=黄、lava=红黑。

| id | 旧名 | 新名（拟） | TS 源 | bake | AI 原型 | 群系 |
|---|---|---|---|---|---|---|
| goblin | 妖鬼 | 红袍小鬼 | Red Pawn 裸 | — | melee_swarm | plains |
| sprout | 萌芽怪 | 持刀芽兵 | Yellow Pawn Knife | — | soldier | plains |
| boar | 野猪 | 红枪骑兵 | Red Lancer | — | charger | plains |
| turtle | 绿龟 | 蓝盾卫 | Blue Warrior | — | charger | plains |
| chicken | 鸡 | 绵羊 | Sheep（Idle/Move） | — | ambient | plains |
| slime | 红史莱姆 | 猩红教徒 | Red Pawn 裸 | 深红饱和 | splitter | forest |
| frog | 绿蛙 | 黄衣散兵 | Yellow Pawn 裸 | — | melee_swarm | forest |
| mandrake | 曼德拉草 | 紫杉弓手 | Purple Archer | — | ranged | forest |
| mushroom | 蘑菇怪 | 暗夜弓手 | Black Archer | — | ranged | forest |
| raccoon | 浣熊 | 山羊 | Sheep | 棕灰 | ambient | forest |
| treant | 树人（Boss） | 黑铁骑士王 | Black Warrior | — | charger | forest Boss |
| ice_slime | 冰史莱姆 | 霜白教徒 | Pawn 裸 | 冰蓝白 | splitter | snow/swamp |
| penguin | 企鹅 | 雪原矿工 | Blue Pawn Pickaxe | — | charger | snow |
| ghost | 幽灵 | 灰烬游魂 | Pawn 裸 | 灰白降饱和 | melee_swarm | snow |
| bear | 雪熊 | 黑甲武士 | Black Warrior | — | charger | snow |
| bat | 蝙蝠 | 紫夜刺客 | Purple Pawn 裸 | — | melee_swarm | swamp |
| spider | 沼泽蟹 | 毒沼猎手 | Archer | 青绿 | ranged | swamp |
| octopus | 红章鱼 | 绛紫弓手 | Archer | 紫红 | ranged | swamp |
| eye | 眼魔 | 苍黄射手 | Yellow Archer | — | ranged | swamp |
| parrot | 鹦鹉 | 野鸭 | Rubber Duck | — | ambient | swamp |
| beetle | 甲虫 | 黄甲武士 | Yellow Warrior | — | soldier | hill |
| squirrel | 松鼠 | 橙尾山贼 | Pawn 裸 | 橙 | charger | hill |
| cactus | 仙人掌怪 | 荆棘枪兵 | Lancer | 草绿 | ranged | hill |
| cyclope | 独眼巨人 | 紫岩重兵 | Purple Warrior | — | soldier | hill |
| stag_beetle_king | 锹形虫王（Boss） | 黑枪领主 | Black Lancer | — | soldier | hill Boss |
| phoenix | 火鸟 | 焰羽射手 | Yellow Archer | 橙红 | ranged | lava |
| guardian | 石像鬼 | 黑曜守卫 | Black Warrior（Guard 帧并入） | — | guardian | lava |
| dragon_yellow | 火龙 | 熔岩枪骑 | Red Lancer | 暗红 | ranged | lava |
| turtle_king | 龟王（Boss） | 熔岩领主 | Red Warrior | — | guardian | lava Boss |

- Boss 无专属大图：用大 visual_scale（约 2.0~2.4）军团精英呈现；表现层挤压缩放/血条机制照旧。
- 物种 id（.tres 文件名、存档键）**一律不变**，只改显示名（迁移走 species_catalog.gd 的 SPECIES_RENAME_MAP，v5 已验证的通道）。
- ambient 注意：Sheep/Rubber Duck 为侧视条带；橡皮鸭若为单帧则 idle 静态+位移。

## 4. 英雄与皮肤

- 帧源：`Units/Blue|Black|Yellow Units/Warrior/`（Idle/Run/Attack1/Attack2/Guard）
- 皮肤键沿用（免存档迁移）：blue→Warrior 蓝（缺省）、dark→Warrior 黑、white→Warrior 黄（亮色近似）
- Attack1/Attack2 → 三段连击交替（现 combo 计数逻辑复用）；Guard 帧可用于受击/格挡演出（可选）
- 设置面板文案「忍者外观」→「骑士外观」；SKIN_ORDER 不动
- die 帧：TS 无 → 沿用白闪+烟+挤压演出（现有逻辑）

## 5. 地标 NPC（6 槽，全部蓝系友军）

| kind | 角色 | TS 源 | 头像 |
|---|---|---|---|
| 石环 | 营地猎人 | Blue Archer | Avatars 切片 |
| 荒废遗迹 | 遗迹学者（考古） | Blue Pawn Pickaxe | 同上 |
| 精灵泉 | 泉水守望者（治疗） | Blue Monk（Heal 动画天然对口） | 同上 |
| merchant | 行商 | Blue Pawn Gold（背金袋） | 同上 |
| 了望石塔 | 瞭望者 | Blue Warrior | 同上 |
| 古树 | 草药师 | Blue Pawn Knife | 同上 |

- 头像：`Avatars_01~25`（各 4×4×64px）切出后按 NPC 挑 6 张，路径改 `assets/ts/` 切片产物；hud.gd faceset 加载点同步。
- 对话气泡底板/头像框换 TS Paper 系（§8）。

## 6. fx 映射（18 组，零 NA 依赖）

| kind | 源 | 处理 |
|---|---|---|
| fx_slash | **合成** | 白色弧光 3 帧（新工具 generate_fx.gd，TS 色板/像素密度） |
| fx_slash_gold | **合成** | 金色弧光 |
| fx_flame | Fire_01 | 直用 |
| fx_frost | Fire_01 | bake 冰蓝 |
| fx_magic | Explosion_01 | bake 紫 |
| fx_charge | Fire_02 | bake 白金 |
| fx_burst | Explosion_02 | 直用 |
| fx_boom | Explosion_01 | 直用 |
| fx_smoke | Dust_01 | bake 灰 |
| fx_darksmoke | Dust_02 | bake 暗紫 |
| fx_orb | Fire_03 | bake 紫红 |
| fx_beam | **合成** | 白金细束 |
| fx_pillar | **合成** | 开箱光柱 |
| fx_flash | **合成** | 白闪 |
| fx_flash_gold | **合成** | 金闪 |
| fx_flash_blue | **合成** | 蓝闪 |
| fx_flash_yellow | **合成** | 黄闪 |
| fx_beams | **合成** | Boss 重生多重光束 |

- Water Splash 留库（未来水花/岩浆泡）。
- 弹道：Arrow.png 用于 Archer 系怪物弹（现 projectile 通道换皮）；法弹合成紫球。

## 7. 地形 / 障碍 / 建筑 / 主菜单

- **地表**：terrain_painter 的 TILESET_PATH → Tilemap_color1~5（÷4 到 16px 世界格），坐标表按 64px 版式重写；5 主题 + 现有 HSV 烘焙出 6 群系（snow=冷白、swamp=黄绿暗、lava=水烘橙红岩浆、hill=泥底等，沿用 RULES 机制）。主题↔color 编号执行时视觉判读定。
- **水面**：Water Background（底色）+ Water Foam（岸线，先静态后动画可选）。
- **障碍**（generate_obstacle_tileset.DERIVE 换源，sim_test 键集守闸不动）：tree/pine→Tree1-4 变体、big_tree→Tree 放大、boulder→Rock 放大、rock→Rock1-4、deadtree→Stump、crystal→Rock bake 蓝紫、ice→Rock bake 白、bones→Stump bake 灰白、water→Water Background 裁片、castle→Castle/Tower 墙体。
- **装饰**（world_deco.PROP_SRC）：灌木/岩/树/金块(Gold Stone)/工具掉落(Tool)替换；多边形类（冰锥/雪堆/水洼/水晶/骨堆）改 TS 色板重绘或 TS 元素；云(Clouds)留主菜单。
- **建筑**（bake_structures.STAMPS 换源）：
  - 出生营地 = Blue House1（主屋）+ House3 + Tower + Banner 旗（水车/鸟居/演武牌退役）+ Gold Resource 货堆点缀；行商 = Blue House2 铺面 + Pawn Gold
  - Boss 城塞 = Red/Black Castle + Tower 呼应（hill=Black、lava=Red，与 Boss 阵营色一致）；城墙障碍格视觉同源
  - 宝箱：TS 无 → Icons 盘点有无，无则合成木箱（缺口如实记录）
  - 室内口袋（interior_floor/bed/np 墙）：TS 无室内件 → 暂留 NA 并入缺口清单，P4 复议
- **主菜单**：generate_terrain 重产 6 张 region_*.png（TS 瓦片 + 树/岩/建筑剪影）；标题区可用 Banner.png + 云视差（P4）。

## 8. UI 全套（P4）

- 血条：玩家 HP/MP → BigBar_Base/Fill（TextureProgressBar）；怪物/Boss 血条 → SmallBar
- 按钮：Big/Small（蓝红 × 方圆 × Regular/Pressed）→ StyleBox/Theme 统一；Tiny 系做图标按钮
- 对话框：RegularPaper 九宫格底板 + SmallRibbons 标题签 + 头像框（BigRibbons/自切）
- yes/no → Tiny 系双色按钮；菜单装饰 → Swords.png / 丝带
- 图标：ItemCatalog → Icons_01~12 + Tools_01~04 + Gold Stone/Meat/Wood 切帧替换（先盘点 Icons 内容，缺口清单如实记录）
- 光标：Cursors_01~04（可选，iOS 无鼠标则仅桌面生效）
- WoodTable+Slots：背包/商店格子底板候选

## 9. 音频（P5，包内零音频）

- 需求：10 BGM 槽（6 群系+菜单+地牢+Boss+营地，须可循环）+ 23 事件音
- 事件音主体：Kenney CC0（rpg-audio / impact-sounds / interface-sounds）
- BGM：CC0 中世纪/幻想循环曲包，执行时列 2~3 候选（默认自选最贴的并汇报取舍；个别槽 CC0 覆盖不满允许暂留 NA 并记录）
- 落点：新库 `assets/audio/`（kenney 曲目与 NA sfx/ 分离），sfx_manager.gd 的 SFX/TERRAIN_THEMES 两表重映射；ui_flow_test 三路音量总线/主题映射守闸

## 10. Enemy Pack 后补通道（到货后）

- zip 解压到 `Code/assets/ts_enemy/`（LICENSE 补记）
- 只改 slicer 的 TS 帧源表（§3 表的「TS 源」列换成 Enemy 单位）+ 视需要调 bake；.tres/场景/UI/地形零改动
- 物种显示名若再随怪物形象调整，继续走 SPECIES_RENAME_MAP

## 11. 回滚与验证

- 回滚：slicer `STYLE = "ts" | "na"` 一键切回 NA 帧；main 分支即 NA 主线
- 每阶段验收：改帧→combat_test+save_test；改 UI→ui_flow_test；改障碍→sim_test；改数值→balance_test；P6 六测全绿 + screenshot.tscn 六点位取证（出生/雪原/熔岩/交界/menu/codex/night）

## 12. 落地定稿记录（2026-09-20，P0~P6 收束）

六个阶段提交：00b236f（入库+方案）→ dcd05b8（切帧管线）→ c466ca0（角色层）→ edb7080（地形层）→ 869dfdf（UI 全套）→ a52e2b4（音频）+ 终验提交。与初稿的差异与实证：

1. **尺寸体系**（2026-09-20 晚间「糊」根治后终稿）：TS 素材 2× 预放大；切帧=union bbox+÷2 还原原生**直出**（k=1），帧内嵌**压缩二进制 .res**（frames 目录 4.6MB 文本→1.1MB）；显示端场景基准 2.0 × visual_scale 凑整数档（小型 0.5=×1、标准/大型 1.0=×2、Boss 0.45~1.59=×2/3/7），碰撞/血条占地拆到 body_scale（=旧 visual_scale 值，手感零变化）。英雄屏高 112px（旧 95）。当日早前 9~18 行抽取档已废弃：「TS 源帧 21 行」系误读（21 行是当时切帧输出而非源；真源 idle 44 / 含攻击 union 56），h 档迫使 k=3 众数抽取、每轴丢 2/3 信息且 1px 描边在 3×3 投票中必败——即当日五轮「糊」反馈的真源；渲染层（Nearest/整数缩放/坐标吸附）自证清白。frames_test 新增逐条目尺寸白名单守闸（p 误检/k 回归/横带三类事故现形）。
2. **Lancer 分段实证**：idle=5 方向×12 帧（右向 24-35）、run=5×6（右向 12-17），攻击取 *_Right_* 独立文件；只用于 hill Boss 与 cactus/dragon 两物种（竖枪画布不适合常规怪）。
3. **英雄侧向翻转零代码**：player._update_anim 原生降级链（缺 _up/_down 自动侧向+flip_h、缺 attack1-3 回退 attack、缺 die/hurt 跳过）直接吃 TS 单视角帧表。
4. **特效**：TS 源 9 组（Fire/Explosion/Dust 烘焙变色）+ generate_fx 合成 9 组（slash 弧光两轮几何调优：56 画布半径 22±45°）+ orb_core 法弹球；FxLayer TABLE 路径不变零代码接入。
5. **装饰双通道**：障碍/装饰统一走 assets/deco 精灵通道（world_deco 原生 AI 精灵优先机制复用），bake_structures 一站产出 14 件。
6. **UI**：39 件图标产线（对位/变色/合成）；对话框=RegularPaper 九宫+TS 方钮+合成金边头像框；血条=BigBar_Fill 烘三色平铺+SmallBar_Base 九宫（StyleBoxTexture texture_margin API 实测：属性名 texture_margin_*、值为 float）；室内口袋合成件（地板/墙/床）关闭 NA 残留。
7. **音频**：FreePD 2025 关站改道 OpenGameArt CC0 合集（10 槽）+ Kenney 四包（24 事件音）；WAV 两曲 ffmpeg libmp3lame 转 mp3；mp3/ogg 运行时 loop。jingles 族编号未试听、mp3 循环间隙为已知观察项。
8. **显示名迁移缓办**：物种名被 prey 链/WorldConfig/TERRAIN_BOSSES/任务按字符串引用，改名静默断链风险大于收益；待 Enemy Pack 到货（怪物形象再变）统一走 SPECIES_RENAME_MAP。
9. **验收**：六测全绿（sim 123 项/balance/combat 62 项/save/ui_flow 26 项/pacing）+ 七点位截图像素实证（出生/交界/主菜单/HUD/雪原/熔岩/夜间/图鉴），零 NA 视觉残留、零渲染异常。存档完全兼容（id/路径键全未动）。
10. **回滚通道**：slice_spritesheets.gd `STYLE="na"` 重跑即整体回退 NA 帧；main 分支=NA 主线。
11. **动作补齐（2026-09-28，实玩反馈「动作基本没有尤其战斗动作」）**：TS 现成动作素材全量消费——裸兵种整体换工具版（武器常驻不闪现），9 Pawn 系补 attack=同色 Pawn_Interact（妖鬼红斧/sprout 黄刀/penguin 蓝镐/slime 系红蓝刀/frog·ghost·bat·squirrel 各色刀，k=2 与 bake 沿用）；5 Warrior 系（boar/turtle/bear/beetle/cyclope）+ 2 Lancer 系（cactus/dragon）补 hurt=同色 Guard/Right_Defence（hurt 覆盖 11 物种，含原有 4 Boss/守卫）。运行时改「出招相位定点播放」：monster_base 新增 _play_action_anim 非循环动作通道，_perform_attack 出招瞬间播 attack（帧与伤害同相位）、take_damage 空闲时播 hurt（0.45s 最小间隔、不打断进行中动作）、spider._spit 播 Archer_Shoot（远程 8 物种攻击帧首次有播放路径）、boar S_TELL/guardian S_WINDUP 前摇=挥击预备帧；S_ATTACK 常驻循环挥刀的旧映射废除（冷却逼近回归速度驱动）。英雄 attack1-3 ×1.3 / hurt ×2.5 纯视觉提速收进判定窗。羊/鸭被动系（鸡/浣熊/鹦鹉，ambient 永不参战）素材本无动作条带，不补。frames_test 物种断言升级为按物种期望表（26 含 attack/11 含 hurt）+ 尺寸白名单同步 9 目录（加攻击帧只扩 union 画布透明区，本体像素不变、无体型漂移），444→525 项。
12. **UI 全量收口（2026-09-30，「ui更换为ts相关元素」）**：§8 计划中仍为纯色/程序绘制的表面全部 TS 化——glass_theme 的 Button 三态=SmallBlueSquareButton Regular/Pressed 纹理（全局统一，主菜单/HUD/商店/物品栏按钮一次到位）、CheckButton=暗槽↔TinySquareBlueButton；触控钮=TS 圆钮两态（攻击红/技能功能蓝）；商店与物品栏=WoodTable_Slots 木瓦九宫面板+木色页签；图鉴/生态/暂停/设置/清档确认=SpecialPaper 深纸；三选一赐福卡=WoodTable_Slots 木瓦；面板标题（暂停/游商/图鉴/物品栏/赐福/设置/Boss 名/NPC 名牌）=SmallRibbons 丝带签（5 色×长短尾十行图集，AtlasTexture 行裁切）；主菜单标题=芥末黄丝带横幅 720×88（store 页 Banner 弃用）；Boss 条=BigBar_Base/Fill（高 24 边距 8）；怪物头顶条=TS 色板合成 monster_bar.png 64×12 木框（bake 产线 +1 件，icons 41 件）。对话气泡浅纸面文字改深墨色+浅描边（白字对比不足）。**三条实证教训**：①WoodTable/store Banner 是带大透明区的「形状件」（覆盖 ~27%），整幅垫底碎成补丁——面板底只能用实心的 WoodTable_Slots（内部 100% 覆盖）；②SmallRibbons 单元=燕尾 19-63/横带 128-191/两侧 64px 透明缺口，九宫边距必须 128（只拉横带），取 96 会把缺口拉宽出「空洞带」；③BigBar_Fill 不透明带仅占纹理 y24-44，StyleBoxTexture 上下边距×2 ≥ 条高时中心区变负、填充整条消失（隔离探针 m14/h22=0 红像素、m6/m8 正常）。验收：六测全绿 + overlays/探针/菜单九点位像素与视觉双取证。附：screenshot.gd 的 overlays 模式此前 _process_overlays 无调用点空转（本次补上调度，七帧弹层取证恢复）。

## 13. Enemy Pack 定稿（2026-09-30，v6.1——§0/§10 预定通道兑现）

素材入库：`Documents/Tiny Swords (Enemy Pack) 20260916.zip`（itch 付费/捐助渠道，144 PNG+43 .aseprite，每怪附 256 Avatar 留作未来图鉴头像）→ `Code/assets/ts_enemy/`（22 物种）+ `Code/assets/ts_enemy_extra/`（22 附件目录），授权注记见 `assets/ts/LICENSE.md` 第二节。**22 怪 21 只直接启用**（Paddle Shark 留库备水内容），5 组 bake 异色复用（Imp/蜂/HexShaman/Turtle/Minotaur ×2，沿用 v6 同源异色惯例），被动猎物=Extra Pig；羊/鸭留免费包（EP 无被动动物）。

### 物种映射定稿（29；id/存档键/AI 原型/生态数值零改动，显示名同步迁移）

| 群系 | 物种 id（存档键） | EP 源 | 新显示名 | 原型 |
|---|---|---|---|---|
| plains | goblin | Torch Goblin | 火把哥布林 | melee_swarm |
| plains | sprout | Gnome | 地精矿工 | soldier |
| plains | boar | Snake | 突袭蛇 | charger |
| plains | turtle | Turtle（320 画布） | 青甲龟 | charger |
| plains | chicken | Extra: Pig | 山猪 | ambient |
| forest | slime | Imp（三段攻击取 Start） | 赤炎小魔 | splitter |
| forest | frog | Lizard（hurt=Lizard_Hit） | 蜥蜴刀客 | melee_swarm |
| forest | mandrake | Slingshot Gnome | 弹弓地精 | ranged |
| forest | mushroom | Hex Shaman | 巫毒萨满 | ranged |
| forest | raccoon | Sheep bake（免费包，不变） | 山羊 | ambient |
| forest★ | treant | **Troll**（Windup/Attack/Recovery/Dead 全套） | 巨魔王 | charger Boss |
| snow | penguin | Thief | 雪原窃贼 | charger |
| snow | ghost | Skull（hurt=Skull_Guard） | 白骨兵 | melee_swarm |
| snow | ice_slime | Imp bake 冰蓝 | 冰霜小魔 | splitter |
| snow | bear | Bear（256 画布） | 雪原巨熊 | charger |
| swamp | bat | Giant Bat | 巨蝠 | melee_swarm |
| swamp | spider | Spider | 沼泽蛛 | ranged |
| swamp | octopus | Bomb Fish（attack=Shoot） | 炸弹鱼 | ranged |
| swamp | eye | Harpoon Shark（attack=Throw） | 鱼叉鲨 | ranged |
| swamp | parrot | Rubber Duck（免费包，不变） | 野鸭 | ambient |
| hill | beetle | Spear Goblin（256，attack=Attack Fast） | 长矛哥布林 | soldier |
| hill | squirrel | Bumblebee | 山蜂 | charger |
| hill | cactus | Gnoll（hurt=Gnoll_Hit） | 投骨豺狼人 | ranged |
| hill | cyclope | Panda（256） | 山岳熊猫 | soldier |
| hill★ | stag_beetle_king | Minotaur（hurt=Minotaur_Guard） | 牛头王 | soldier Boss |
| lava | phoenix | Bumblebee bake 焰红 | 火蜂 | ranged |
| lava | gargoyle | Minotaur bake 黑曜（sat .28/val .60） | 黑曜牛卫 | guardian |
| lava | dragon_yellow | Hex Shaman bake 熔岩红 | 熔岩萨满 | ranged |
| lava★ | turtle_king | Turtle bake 暗红（hurt=Guard_In） | 熔岩龟王 | guardian Boss |

### 行为-画面接线（超出 §10 最小通道的部分）

- **投射物弹体按物种**：SpeciesData 新增 `projectile_tex`；弹弓地精=橡果、投骨豺狼人=骨头、鱼叉鲨=鱼叉、巫毒萨满/沼泽蛛/熔岩萨满=法球、炸弹鱼=炸弹（bake_structures 首帧烘焙 ÷4，projectile.gd 缺省回退箭矢）
- **巢穴按群系换装**：nest_node 程序土丘→动画小屋（plains/forest=Goblin Hut、swamp=Fish Hut、snow/hill/lava=Cave；slicer 新增 nest_hut/nest_fish_hut/nest_cave 三条目，捣毁碎片色仍取物种 tint）
- **Troll Boss 连招**：treant 获 windup（boar.gd 冲锋前摇优先播，回退 attack）/hurt=Recovery/die=Dead——全 29 物种唯一真死亡动画
- **EP 无通用 hurt/death**（仅 Gnoll/Lizard Hit、Troll Dead、Guard 系）：缺 hurt 物种照旧静默跳过（受击挤压回弹兜底），frames_test 按新实情收敛期望
- **装饰升级**：bones=EP 真骨堆（旧 Stump 派生源已失散，一并修复）、skullspike 新 kind（lava/hill 低权重）、deadtree=EP 真枯树（world_deco 56 高档 + 障碍瓦片 DERIVE 改指 + 重生成）

### 显示名迁移（v6 欠账清偿）

29 旧名→新名全量落地：SPECIES_RENAME_MAP 40 条（29 新 + 11 条 v5 历史名 re-point 一跳到底，如 獾王→牛头王、青史莱姆→冰霜小魔）；53 文件按名引用同步（prey 链/INITIAL_POPULATION/TERRAIN_BOSSES/MONSTER_SCENES/掉料表/tutorial 播报/成就/六测试断言）；grep 全仓旧名归零（RENAME_MAP 除外）。**存档完全兼容**：图鉴计数/任务/生态快照经 6 个既有调用点自动迁移。

### 尺寸档（visual_scale 按「新画布原生尺寸×目标整数档≈旧屏占」重推）

bear/beetle/cyclope/eye/guardian/phoenix/turtle 1.0→0.5（EP 中大型画布落 ×1 档）；dragon_yellow 0.5→1.0（Hex Shaman 画布小，×2 回目标体感）；Boss 三只重推：treant 0.682→0.35（Troll 119 原生）、stag_beetle_king 0.4545→0.5、turtle_king 1.591→0.7（Turtle 宽画幅按宽守恒）。body_scale（手感真源）全部未动。

### 定稿实证

- 切帧器支持 res:// 绝对路径（EP 免费包外素材通道）；EP 条带画布按体型 192/256/320/384，p=2 预放大自动检测
- frames_test 525→531 项全绿（29 物种新尺寸白名单 + 3 巢穴 + treant windup/die 期望）；八测全绿（smoke/sim 123/balance/frames/combat/save/ui_flow 26/pacing）
- 目检七组截图全过：四群系怪物新装无撕裂/悬空/阴影错位、挥击/吐息/弹体飞行/血条在播、图鉴 29 行全新名零残留、三类巢穴（小屋+火把哥布林同框/鱼屋/洞穴+白骨兵）实拍确认、骷髅桩/骨堆入镜
- 教训一条：营地巢穴取证须以 camp 坐标传送拍摄（据点制下采样点距营地 4300px 超流式圈 2400px，常规定位点必空镜——非巢穴缺失）
