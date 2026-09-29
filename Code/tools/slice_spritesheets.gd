## 精灵表切帧工具（无头运行：godot --headless --path Code -s tools/slice_spritesheets.gd）。
## 双风格开关（美术 v6，2026-09-20）：
##   STYLE="ts" → Tiny Swords 免费包（assets/ts/，逐动画单行条带，帧 192×192=2× 预放大；
##     裁全体 union bbox → 按目标内容高重采样 → 按需 HSV 烘焙。Lancer 64×320 竖画布
##     Lancer 实为 320×320 真帧（idle 12 帧/run 6 帧正面竖枪，方向通用；攻击/防御取 *_Right_* 朝右侧面））
##   STYLE="na" → Ninja Adventure 16px 表（v5 回滚线，表保留原样）
## 帧纹理直接内嵌进压缩二进制 .res（FLAG_BUNDLE_RESOURCES|FLAG_COMPRESS，不产生散碎帧文件）。
## 输出：assets/creatures/frames/<name>/<name>_frames.tres，场景 Visual（AnimatedSprite2D）引用之。
## NA 布局约定（与作者 Godot 演示 sprite_character.gd 一致）：列 = 朝向（0下/1上/2左/3右），行 = 帧
## （怪物 0-3 行走；角色另含 4攻击/5跳跃/6死亡）。素材取"朝右"列，运行时用 flip_h 翻转。
## TS 条目格式（键含 "anims" 者走 TS 管线）：
##   {"anims": {"idle": "相对路径", "walk": {"path":…, "from": 24, "count": 12, "step": 2}, …},
##    "cell": Vector2i(192,192),   # 帧画布，缺省 192×192
##    "k": 1,                      # 众数抽取档：缺省 1 = ÷p 还原原生后直出（不抽取）；
##                                 #   "h": N 旧目标内容高键仅 fx/deco 沿用（k=round(原生高/h)）
##    "bake"/"fps"/"loop"/"noloop": [动画名…]}——fps 可为 float 或 {动画名: fps} 字典
extends SceneTree

## ★ 风格开关：改回 "na" 并重跑 = 整体回滚到 NA 帧（美术 v6 回退线）
const STYLE := "ts"
const TS_DIR := "res://assets/ts/"

const SHEETS_DIR := "res://assets/creatures/sheets/"
const OUT_DIR := "res://assets/creatures/frames/"
const CELL := 16
## 行走帧率：Ninja Adventure 作者演示的 IMAGE_SPEED
const FPS := 6.0

## bake: hue 平移（色相环 0-1，可为负）/sat、val 乘子（灰与描边 s≈0 不受色相影响，自然保留）
## 可选键：sheet 以 res:// 开头则用绝对路径（fx 等非 sheets 目录素材）；
##   strip=true 时 anim 的帧号是单行条带的 x 格号（fx 特效表布局）；
##   fps / loop 覆盖全局默认（特效用 15fps 非循环）
const CREATURES_NA := {
	"ninja": {
		"sheet": "na_ninja.png", "col": 3, "flop": false, "dirs": true,
		"anim": {"idle": [0], "walk": [0, 1, 2, 3], "attack": [4], "die": [6]},
	},
	## 三忍皮肤（美术 v5）：黑忍/白忍与蓝忍同布局（4列×7行，col3=朝右）
	"ninja_dark": {
		"sheet": "na_ninja_dark.png", "col": 3, "flop": false, "dirs": true,
		"anim": {"idle": [0], "walk": [0, 1, 2, 3], "attack": [4], "die": [6]},
	},
	"ninja_white": {
		"sheet": "na_ninja_white.png", "col": 3, "flop": false, "dirs": true,
		"anim": {"idle": [0], "walk": [0, 1, 2, 3], "attack": [4], "die": [6]},
	},
	# --- 地标/营地 NPC（美术 v5 完整包：命名角色，与英雄同布局 64×112） ---
	"npc_hunter": {
		"sheet": "na_ch_hunter.png", "col": 3, "flop": false, "dirs": true,
		"anim": {"idle": [0], "walk": [0, 1, 2, 3]},
	},
	"npc_scholar": {
		"sheet": "na_ch_inspector.png", "col": 3, "flop": false, "dirs": true,
		"anim": {"idle": [0], "walk": [0, 1, 2, 3]},
	},
	"npc_keeper": {
		"sheet": "na_ch_sorcerer.png", "col": 3, "flop": false, "dirs": true,
		"anim": {"idle": [0], "walk": [0, 1, 2, 3]},
	},
	## 营地行商（出生营地商店 NPC，完整包 Villager）
	"npc_merchant": {
		"sheet": "na_ch_villager.png", "col": 3, "flop": false, "dirs": true,
		"anim": {"idle": [0], "walk": [0, 1, 2, 3]},
	},
	# --- 玩法 v7 P1：新地标 NPC（GitHub 包 characters 表，了望石塔/古树） ---
	## 瞭望者 = characters/13（深蓝兜帽，哨兵气质；faceset 同号 13）
	"npc_watchman": {
		"sheet": "na_ch_watchman.png", "col": 3, "flop": false, "dirs": true,
		"anim": {"idle": [0], "walk": [0, 1, 2, 3]},
	},
	## 草药师 = characters/9（橙红和服，温和医者；faceset 同号 9）
	"npc_herbalist": {
		"sheet": "na_ch_herbalist.png", "col": 3, "flop": false, "dirs": true,
		"anim": {"idle": [0], "walk": [0, 1, 2, 3]},
	},
	# --- 玩法 v7 P2：群系动画装饰（NA Animated bg 条带） ---
	## 瀑布三段（start 5 帧 / middle 5 帧 / end 3 帧，16px 格）
	"deco_waterfall_start": {"sheet": "res://assets/na/bg/frames/waterfall-start.png", "strip": true, "fps": 6.0, "anim": {"play": "auto"}},
	"deco_waterfall_middle": {"sheet": "res://assets/na/bg/frames/waterfall-middle.png", "strip": true, "fps": 6.0, "anim": {"play": "auto"}},
	"deco_waterfall_end": {"sheet": "res://assets/na/bg/frames/waterfall-end.png", "strip": true, "fps": 6.0, "anim": {"play": "auto"}},
	## 草叶摇摆（64×16 = 4 帧；flower 20×8 不合 16 网格弃用）
	"deco_plant": {"sheet": "res://assets/na/bg/frames/plant.png", "strip": true, "fps": 4.0, "anim": {"play": "auto"}},
	# --- Boss 专属形象（美术 v5 完整包 48-50px 横条带；按动画独立源 + cell 格宽） ---
	## 锹形虫王 → 大武士（GiantBlueSamurai，48px×12 帧）
	"boss_samurai": {
		"cell": 48,
		"anim": {
			"idle": {"sheet": "res://assets/creatures/sheets/boss_samurai_idle.png"},
			"walk": {"sheet": "res://assets/creatures/sheets/boss_samurai_walk.png"},
			"hurt": {"sheet": "res://assets/creatures/sheets/boss_samurai_hit.png"},
		},
	},
	# --- 营地动画件（完整包 Animated）：水车 3 帧/桨叶 2 帧/旗帜 4 帧 ---
	"camp_watermill": {"cell": 34, "anim": {"idle": {"sheet": "res://assets/na/bg/frames_watermill_a.png"}}},
	"camp_propeller": {"cell": 64, "anim": {"idle": {"sheet": "res://assets/creatures/sheets/na_mill_propeller.png"}}},
	"camp_flag": {"sheet": "res://assets/na/bg/frames/flag.png", "strip": true, "fps": 4.0, "anim": {"play": [0, 1, 2, 3]}},
	## 龟王 → 火焰魔王（GiantFlam，50px 条带；无走路帧=idle 兼任）
	"boss_flam": {
		"cell": 50,
		"anim": {
			"idle": {"sheet": "res://assets/creatures/sheets/boss_flam_idle.png"},
			"hurt": {"sheet": "res://assets/creatures/sheets/boss_flam_hit.png"},
		},
	},
	## 打击特效（Ninja Adventure fx 表：16px 单行条带）
	"fx_slash": {
		"sheet": "res://assets/na/fx/2.png", "strip": true,
		"fps": 15.0, "loop": false,
		"anim": {"play": [0, 1, 2, 3, 4, 5]},
	},
	"fx_slash_gold": {
		"sheet": "res://assets/na/fx/1.png", "strip": true,
		"fps": 15.0, "loop": false,
		"anim": {"play": [0, 1, 2, 3, 4, 5]},
	},
	"fx_burst": {
		"sheet": "res://assets/na/fx/9.png", "strip": true,
		"fps": 12.0, "loop": false,
		"anim": {"play": [0, 1, 2, 3, 4]},
	},
	# --- fx 全量接线（美术 v5 M-C）：帧号 "auto" = 条带宽/16 全帧 ---
	"fx_flame": {"sheet": "res://assets/na/fx/5.png", "strip": true, "fps": 14.0, "loop": false, "anim": {"play": "auto"}},
	"fx_magic": {"sheet": "res://assets/na/fx/6.png", "strip": true, "fps": 14.0, "loop": false, "anim": {"play": "auto"}},
	"fx_charge": {"sheet": "res://assets/na/fx/7.png", "strip": true, "fps": 12.0, "loop": false, "anim": {"play": "auto"}},
	"fx_frost": {"sheet": "res://assets/na/fx/8.png", "strip": true, "fps": 14.0, "loop": false, "anim": {"play": "auto"}},
	"fx_boom": {"sheet": "res://assets/na/fx/10.png", "strip": true, "fps": 12.0, "loop": false, "anim": {"play": "auto"}},
	"fx_smoke": {"sheet": "res://assets/na/fx/11.png", "strip": true, "fps": 10.0, "loop": false, "anim": {"play": "auto"}},
	"fx_darksmoke": {"sheet": "res://assets/na/fx/12.png", "strip": true, "fps": 10.0, "loop": false, "anim": {"play": "auto"}},
	"fx_orb": {"sheet": "res://assets/na/fx/13.png", "strip": true, "fps": 14.0, "loop": false, "anim": {"play": "auto"}},
	"fx_beam": {"sheet": "res://assets/na/fx/14.png", "strip": true, "fps": 14.0, "loop": false, "anim": {"play": "auto"}},
	"fx_pillar": {"sheet": "res://assets/na/fx/15.png", "strip": true, "fps": 14.0, "loop": false, "anim": {"play": "auto"}},
	"fx_flash": {"sheet": "res://assets/na/fx/16.png", "strip": true, "fps": 12.0, "loop": false, "anim": {"play": "auto"}},
	"fx_flash_gold": {"sheet": "res://assets/na/fx/17.png", "strip": true, "fps": 12.0, "loop": false, "anim": {"play": "auto"}},
	"fx_flash_blue": {"sheet": "res://assets/na/fx/18.png", "strip": true, "fps": 12.0, "loop": false, "anim": {"play": "auto"}},
	"fx_flash_yellow": {"sheet": "res://assets/na/fx/19.png", "strip": true, "fps": 12.0, "loop": false, "anim": {"play": "auto"}},
	"fx_beams": {"sheet": "res://assets/na/fx/20.png", "strip": true, "fps": 14.0, "loop": false, "anim": {"play": "auto"}},
	"oni": {
		"sheet": "na_oni.png", "col": 3, "flop": false,
		"anim": {"idle": [0], "walk": [0, 1, 2, 3]},
	},
	"slime": {
		"sheet": "na_slime.png", "col": 3, "flop": false,
		"bake": {"hue": 0.33},
		"anim": {"idle": [0], "walk": [0, 1, 2, 3]},
	},
	## 甲虫（美术 v5 纯 NA 阵容）：无烘焙素版（原 ant 暗化变体已退役）
	"beetle": {
		"sheet": "na_beetle.png", "col": 3, "flop": false,
		"anim": {"idle": [0], "walk": [0, 1, 2, 3]},
	},
	"boar": {
		"sheet": "na_pig64.png", "col": 3, "flop": false,
		"bake": {"hue": 0.09, "sat": 0.75, "val": 0.72},
		"anim": {"idle": [0], "walk": [0, 1, 2, 3]},
	},
	# --- P4 阵容大扩：NA 64x64 四向表（col3=朝右），直接取用或差异化烘焙 ---
	"sprout": {
		"sheet": "na_sprout.png", "col": 3, "flop": false,
		"anim": {"idle": [0], "walk": [0, 1, 2, 3]},
	},
	"frog": {
		"sheet": "na_frog.png", "col": 3, "flop": false,
		"anim": {"idle": [0], "walk": [0, 1, 2, 3]},
	},
	"mandrake": {
		"sheet": "na_mandrake.png", "col": 3, "flop": false,
		"anim": {"idle": [0], "walk": [0, 1, 2, 3]},
	},
	"penguin": {
		"sheet": "na_penguin.png", "col": 3, "flop": false,
		"anim": {"idle": [0], "walk": [0, 1, 2, 3]},
	},
	"ghost": {
		"sheet": "na_ghost.png", "col": 3, "flop": false,
		"anim": {"idle": [0], "walk": [0, 1, 2, 3]},
	},
	"stag_beetle": {
		"sheet": "na_stag_beetle.png", "col": 3, "flop": false,
		"anim": {"idle": [0], "walk": [0, 1, 2, 3]},
	},
	"octopus": {
		"sheet": "na_octopus.png", "col": 3, "flop": false,
		"anim": {"idle": [0], "walk": [0, 1, 2, 3]},
	},
	"bat": {
		"sheet": "na_bat.png", "col": 3, "flop": false,
		"anim": {"idle": [0], "walk": [0, 1, 2, 3]},
	},
	"squirrel": {
		"sheet": "na_squirrel.png", "col": 3, "flop": false,
		"anim": {"idle": [0], "walk": [0, 1, 2, 3]},
	},
	"cactus": {
		"sheet": "na_cactus.png", "col": 3, "flop": false,
		"anim": {"idle": [0], "walk": [0, 1, 2, 3]},
	},
	"phoenix": {
		"sheet": "na_phoenix.png", "col": 3, "flop": false,
		"anim": {"idle": [0], "walk": [0, 1, 2, 3]},
	},
	"gargoyle": {
		"sheet": "na_gargoyle.png", "col": 3, "flop": false,
		"anim": {"idle": [0], "walk": [0, 1, 2, 3]},
	},
	"treant": {
		"sheet": "na_treant.png", "col": 3, "flop": false,
		"anim": {"idle": [0], "walk": [0, 1, 2, 3]},
	},
	## 冰史莱姆：真实青蓝表（美术 v5：合并冰晶/青两变体为单一纯 NA 形象）
	"slime_teal": {
		"sheet": "na_slime_teal.png", "col": 3, "flop": false,
		"anim": {"idle": [0], "walk": [0, 1, 2, 3]},
	},
	# --- 美术 v5 纯 NA 补量：库内休眠表启用（沼泽蟹换真蟹表/蘑菇/绿龟/海龟龟王） ---
	"crab": {
		"sheet": "na_crab.png", "col": 3, "flop": false,
		"anim": {"idle": [0], "walk": [0, 1, 2, 3]},
	},
	"mushroom": {
		"sheet": "na_mushroom.png", "col": 3, "flop": false,
		"anim": {"idle": [0], "walk": [0, 1, 2, 3]},
	},
	"turtle": {
		"sheet": "na_turtle.png", "col": 3, "flop": false,
		"anim": {"idle": [0], "walk": [0, 1, 2, 3]},
	},
	"sea_turtle": {
		"sheet": "na_sea_turtle.png", "col": 3, "flop": false,
		"anim": {"idle": [0], "walk": [0, 1, 2, 3]},
	},
	# --- 物种扩容（美术 v5 完整包 Monster/Animal）---
	"bear": {"sheet": "na_bear.png", "col": 3, "flop": false, "anim": {"idle": [0], "walk": [0, 1, 2, 3]}},
	"cyclope": {"sheet": "na_cyclope.png", "col": 3, "flop": false, "anim": {"idle": [0], "walk": [0, 1, 2, 3]}},
	"eye": {"sheet": "na_eye.png", "col": 3, "flop": false, "anim": {"idle": [0], "walk": [0, 1, 2, 3]}},
	"dragon": {"sheet": "na_dragon.png", "col": 3, "flop": false, "anim": {"idle": [0], "walk": [0, 1, 2, 3]}},
	"raccoon": {"sheet": "na_raccoon.png", "col": 3, "flop": false, "anim": {"idle": [0], "walk": [0, 1, 2, 3]}},
	## 动物侧视 2 帧表（32×16）：条带模式切两格
	"chicken": {"sheet": "na_chicken.png", "strip": true, "fps": 5.0, "anim": {"idle": [0], "walk": [0, 1]}},
	"parrot": {"sheet": "na_parrot.png", "strip": true, "fps": 8.0, "anim": {"idle": [0], "walk": [0, 1]}},
}

# ============================ Tiny Swords（美术 v6）============================
## 五色军团生态（映射真源 Documents/美术方案-v6-TinySwords.md §3）：
## 蓝=友军/玩家系；敌对军团按群系：plains=红、forest=黑紫、snow=蓝黑、swamp=紫、hill=黄、lava=红黑。
## 密度：角色/NPC/Boss 原生直出（k=1，2026-09-20「糊」根治；显示端整数 scale ×2 表达
## 体型档），fx/deco 沿用 h 目标档（fx_scale 消费端语义不变）。
## 动作补齐（2026-09-28）：裸兵种整体换工具版（武器常驻不闪现），attack=同色
## Pawn_Interact；Warrior 系/Lancer 系 hurt=同色 Guard/Right_Defence——TS 现成
## 动作素材全量启用（此前 12 物种战斗静默回退 idle）。羊/鸭无动作条带，不补。
## Lancer 右向段：idle from 24 / run from 12（5 方向×12/6 帧分段，2026-09-20 像素实证）。
const CREATURES_TS := {
	# --- 英雄三皮肤（Warrior；键名沿用 ninja* 免存档迁移） ---
	"ninja": {
		"anims": {
			"idle": "Units/Blue Units/Warrior/Warrior_Idle.png",
			"walk": "Units/Blue Units/Warrior/Warrior_Run.png",
			"attack": "Units/Blue Units/Warrior/Warrior_Attack1.png",
			"attack1": "Units/Blue Units/Warrior/Warrior_Attack1.png",
			"attack2": "Units/Blue Units/Warrior/Warrior_Attack2.png",
			"attack3": "Units/Blue Units/Warrior/Warrior_Attack2.png",
			"hurt": "Units/Blue Units/Warrior/Warrior_Guard.png",
		},
		"fps": {"idle": 6.0, "walk": 12.0, "attack": 10.0, "attack1": 10.0,
			"attack2": 10.0, "attack3": 10.0, "hurt": 8.0},
		"noloop": ["attack", "attack1", "attack2", "attack3", "hurt"],
	},
	"ninja_dark": {
		"anims": {
			"idle": "Units/Black Units/Warrior/Warrior_Idle.png",
			"walk": "Units/Black Units/Warrior/Warrior_Run.png",
			"attack": "Units/Black Units/Warrior/Warrior_Attack1.png",
			"attack1": "Units/Black Units/Warrior/Warrior_Attack1.png",
			"attack2": "Units/Black Units/Warrior/Warrior_Attack2.png",
			"attack3": "Units/Black Units/Warrior/Warrior_Attack2.png",
			"hurt": "Units/Black Units/Warrior/Warrior_Guard.png",
		},
		"fps": {"idle": 6.0, "walk": 12.0, "attack": 10.0, "attack1": 10.0,
			"attack2": 10.0, "attack3": 10.0, "hurt": 8.0},
		"noloop": ["attack", "attack1", "attack2", "attack3", "hurt"],
	},
	"ninja_white": {
		"anims": {
			"idle": "Units/Yellow Units/Warrior/Warrior_Idle.png",
			"walk": "Units/Yellow Units/Warrior/Warrior_Run.png",
			"attack": "Units/Yellow Units/Warrior/Warrior_Attack1.png",
			"attack1": "Units/Yellow Units/Warrior/Warrior_Attack1.png",
			"attack2": "Units/Yellow Units/Warrior/Warrior_Attack2.png",
			"attack3": "Units/Yellow Units/Warrior/Warrior_Attack2.png",
			"hurt": "Units/Yellow Units/Warrior/Warrior_Guard.png",
		},
		"fps": {"idle": 6.0, "walk": 12.0, "attack": 10.0, "attack1": 10.0,
			"attack2": 10.0, "attack3": 10.0, "hurt": 8.0},
		"noloop": ["attack", "attack1", "attack2", "attack3", "hurt"],
	},
	# --- 地标/营地 NPC（全部蓝系友军） ---
	"npc_hunter": {
		"anims": {"idle": "Units/Blue Units/Archer/Archer_Idle.png", "walk": "Units/Blue Units/Archer/Archer_Run.png"},
		"fps": {"idle": 6.0, "walk": 8.0},
	},
	"npc_scholar": {
		"anims": {"idle": "Units/Blue Units/Pawn/Pawn_Idle Pickaxe.png", "walk": "Units/Blue Units/Pawn/Pawn_Run Pickaxe.png"},
		"fps": {"idle": 6.0, "walk": 8.0},
	},
	"npc_keeper": {
		"anims": {"idle": "Units/Blue Units/Monk/Idle.png", "walk": "Units/Blue Units/Monk/Run.png"},
		"fps": {"idle": 6.0, "walk": 8.0},
	},
	"npc_merchant": {
		"anims": {"idle": "Units/Blue Units/Pawn/Pawn_Idle Gold.png", "walk": "Units/Blue Units/Pawn/Pawn_Run Gold.png"},
		"fps": {"idle": 6.0, "walk": 8.0},
	},
	"npc_watchman": {
		"anims": {"idle": "Units/Blue Units/Warrior/Warrior_Idle.png", "walk": "Units/Blue Units/Warrior/Warrior_Run.png"},
		"fps": {"idle": 6.0, "walk": 8.0},
	},
	"npc_herbalist": {
		"anims": {"idle": "Units/Blue Units/Pawn/Pawn_Idle Knife.png", "walk": "Units/Blue Units/Pawn/Pawn_Run Knife.png"},
		"fps": {"idle": 6.0, "walk": 8.0},
	},
	# --- 29 物种（id/存档键不变；显示名迁移见 v6 方案 §3） ---
	"oni": {
		"anims": {"idle": "Units/Red Units/Pawn/Pawn_Idle Axe.png", "walk": "Units/Red Units/Pawn/Pawn_Run Axe.png",
			"attack": "Units/Red Units/Pawn/Pawn_Interact Axe.png"},
		"fps": {"idle": 6.0, "walk": 8.0, "attack": 10.0}, "noloop": ["attack"],
	},
	"sprout": {
		"anims": {"idle": "Units/Yellow Units/Pawn/Pawn_Idle Knife.png", "walk": "Units/Yellow Units/Pawn/Pawn_Run Knife.png",
			"attack": "Units/Yellow Units/Pawn/Pawn_Interact Knife.png"},
		"fps": {"idle": 6.0, "walk": 8.0, "attack": 10.0}, "noloop": ["attack"],
	},
	"boar": {
		"anims": {"idle": "Units/Red Units/Warrior/Warrior_Idle.png", "walk": "Units/Red Units/Warrior/Warrior_Run.png",
			"attack": "Units/Red Units/Warrior/Warrior_Attack1.png", "hurt": "Units/Red Units/Warrior/Warrior_Guard.png"},
		"fps": {"idle": 6.0, "walk": 8.0, "attack": 10.0, "hurt": 8.0}, "noloop": ["attack", "hurt"],
	},
	"turtle": {
		"anims": {"idle": "Units/Blue Units/Warrior/Warrior_Idle.png", "walk": "Units/Blue Units/Warrior/Warrior_Run.png",
			"attack": "Units/Blue Units/Warrior/Warrior_Attack1.png", "hurt": "Units/Blue Units/Warrior/Warrior_Guard.png"},
		"fps": {"idle": 6.0, "walk": 8.0, "attack": 10.0, "hurt": 8.0}, "noloop": ["attack", "hurt"],
	},
	"chicken": {
		"cell": Vector2i(128, 128),
		"anims": {"idle": "Terrain/Resources/Meat/Sheep/Sheep_Idle.png", "walk": "Terrain/Resources/Meat/Sheep/Sheep_Move.png"},
		"fps": {"idle": 4.0, "walk": 6.0},
	},
	"slime": {
		"anims": {"idle": "Units/Red Units/Pawn/Pawn_Idle Knife.png", "walk": "Units/Red Units/Pawn/Pawn_Run Knife.png",
			"attack": "Units/Red Units/Pawn/Pawn_Interact Knife.png"},
		## 史莱姆特例 k=2：小体型档最终整数缩放为 1，分裂子代（0.6×）将无处可小；
		## 折半帧让本体落 2 档、子代落 1 档（果冻无细节损失顾虑）
		"bake": {"sat": 1.35, "val": 0.92}, "k": 2, "fps": {"idle": 6.0, "walk": 8.0, "attack": 10.0},
		"noloop": ["attack"],
	},
	"frog": {
		"anims": {"idle": "Units/Yellow Units/Pawn/Pawn_Idle Knife.png", "walk": "Units/Yellow Units/Pawn/Pawn_Run Knife.png",
			"attack": "Units/Yellow Units/Pawn/Pawn_Interact Knife.png"},
		"fps": {"idle": 6.0, "walk": 8.0, "attack": 10.0}, "noloop": ["attack"],
	},
	"mandrake": {
		"anims": {"idle": "Units/Purple Units/Archer/Archer_Idle.png", "walk": "Units/Purple Units/Archer/Archer_Run.png",
			"attack": "Units/Purple Units/Archer/Archer_Shoot.png"},
		"fps": {"idle": 6.0, "walk": 8.0, "attack": 10.0}, "noloop": ["attack"],
	},
	"mushroom": {
		"anims": {"idle": "Units/Black Units/Archer/Archer_Idle.png", "walk": "Units/Black Units/Archer/Archer_Run.png",
			"attack": "Units/Black Units/Archer/Archer_Shoot.png"},
		"fps": {"idle": 6.0, "walk": 8.0, "attack": 10.0}, "noloop": ["attack"],
	},
	"raccoon": {
		"cell": Vector2i(128, 128),
		"anims": {"idle": "Terrain/Resources/Meat/Sheep/Sheep_Idle.png", "walk": "Terrain/Resources/Meat/Sheep/Sheep_Move.png"},
		"bake": {"sat": 0.45, "val": 0.78}, "fps": {"idle": 4.0, "walk": 6.0},
	},
	"treant": {
		"anims": {"idle": "Units/Black Units/Warrior/Warrior_Idle.png", "walk": "Units/Black Units/Warrior/Warrior_Run.png",
			"attack": "Units/Black Units/Warrior/Warrior_Attack1.png", "hurt": "Units/Black Units/Warrior/Warrior_Guard.png"},
		"fps": {"idle": 6.0, "walk": 8.0, "attack": 9.0, "hurt": 8.0}, "noloop": ["attack", "hurt"],
	},
	"slime_teal": {
		"anims": {"idle": "Units/Blue Units/Pawn/Pawn_Idle Knife.png", "walk": "Units/Blue Units/Pawn/Pawn_Run Knife.png",
			"attack": "Units/Blue Units/Pawn/Pawn_Interact Knife.png"},
		"bake": {"hue": 0.52, "sat": 0.55, "val": 1.05}, "k": 2, "fps": {"idle": 6.0, "walk": 8.0, "attack": 10.0},
		"noloop": ["attack"],
	},
	"penguin": {
		"anims": {"idle": "Units/Blue Units/Pawn/Pawn_Idle Pickaxe.png", "walk": "Units/Blue Units/Pawn/Pawn_Run Pickaxe.png",
			"attack": "Units/Blue Units/Pawn/Pawn_Interact Pickaxe.png"},
		"fps": {"idle": 6.0, "walk": 8.0, "attack": 10.0}, "noloop": ["attack"],
	},
	"ghost": {
		"anims": {"idle": "Units/Blue Units/Pawn/Pawn_Idle Knife.png", "walk": "Units/Blue Units/Pawn/Pawn_Run Knife.png",
			"attack": "Units/Blue Units/Pawn/Pawn_Interact Knife.png"},
		"bake": {"sat": 0.12, "val": 1.1}, "fps": {"idle": 6.0, "walk": 8.0, "attack": 10.0},
		"noloop": ["attack"],
	},
	"bear": {
		"anims": {"idle": "Units/Black Units/Warrior/Warrior_Idle.png", "walk": "Units/Black Units/Warrior/Warrior_Run.png",
			"attack": "Units/Black Units/Warrior/Warrior_Attack1.png", "hurt": "Units/Black Units/Warrior/Warrior_Guard.png"},
		"fps": {"idle": 6.0, "walk": 8.0, "attack": 10.0, "hurt": 8.0}, "noloop": ["attack", "hurt"],
	},
	"bat": {
		"anims": {"idle": "Units/Purple Units/Pawn/Pawn_Idle Knife.png", "walk": "Units/Purple Units/Pawn/Pawn_Run Knife.png",
			"attack": "Units/Purple Units/Pawn/Pawn_Interact Knife.png"},
		"fps": {"idle": 6.0, "walk": 8.0, "attack": 10.0}, "noloop": ["attack"],
	},
	"crab": {
		"anims": {"idle": "Units/Blue Units/Archer/Archer_Idle.png", "walk": "Units/Blue Units/Archer/Archer_Run.png",
			"attack": "Units/Blue Units/Archer/Archer_Shoot.png"},
		"bake": {"hue": 0.45, "sat": 0.95}, "fps": {"idle": 6.0, "walk": 8.0, "attack": 10.0},
		"noloop": ["attack"],
	},
	"octopus": {
		"anims": {"idle": "Units/Red Units/Archer/Archer_Idle.png", "walk": "Units/Red Units/Archer/Archer_Run.png",
			"attack": "Units/Red Units/Archer/Archer_Shoot.png"},
		"bake": {"hue": 0.78}, "fps": {"idle": 6.0, "walk": 8.0, "attack": 10.0},
		"noloop": ["attack"],
	},
	"eye": {
		"anims": {"idle": "Units/Yellow Units/Archer/Archer_Idle.png", "walk": "Units/Yellow Units/Archer/Archer_Run.png",
			"attack": "Units/Yellow Units/Archer/Archer_Shoot.png"},
		"fps": {"idle": 6.0, "walk": 8.0, "attack": 10.0}, "noloop": ["attack"],
	},
	"parrot": {
		"cell": Vector2i(32, 32),
		"anims": {"idle": {"path": "Terrain/Decorations/Rubber Duck/Rubber duck.png", "count": 1},
			"walk": "Terrain/Decorations/Rubber Duck/Rubber duck.png"},
		"fps": {"idle": 2.0, "walk": 5.0},
	},
	"beetle": {
		"anims": {"idle": "Units/Yellow Units/Warrior/Warrior_Idle.png", "walk": "Units/Yellow Units/Warrior/Warrior_Run.png",
			"attack": "Units/Yellow Units/Warrior/Warrior_Attack1.png", "hurt": "Units/Yellow Units/Warrior/Warrior_Guard.png"},
		"fps": {"idle": 6.0, "walk": 8.0, "attack": 10.0, "hurt": 8.0}, "noloop": ["attack", "hurt"],
	},
	"squirrel": {
		"anims": {"idle": "Units/Yellow Units/Pawn/Pawn_Idle Knife.png", "walk": "Units/Yellow Units/Pawn/Pawn_Run Knife.png",
			"attack": "Units/Yellow Units/Pawn/Pawn_Interact Knife.png"},
		"bake": {"hue": -0.04, "sat": 1.2, "val": 0.95}, "fps": {"idle": 6.0, "walk": 8.0, "attack": 10.0},
		"noloop": ["attack"],
	},
	"cactus": {
		"cell": Vector2i(320, 320),
		"anims": {
			"idle": "Units/Yellow Units/Lancer/Lancer_Idle.png",
			"walk": "Units/Yellow Units/Lancer/Lancer_Run.png",
			"attack": "Units/Yellow Units/Lancer/Lancer_Right_Attack.png",
			"hurt": "Units/Yellow Units/Lancer/Lancer_Right_Defence.png",
		},
		"bake": {"hue": 0.2, "sat": 0.9, "val": 0.95},
		"fps": {"idle": 6.0, "walk": 8.0, "attack": 10.0, "hurt": 8.0}, "noloop": ["attack", "hurt"],
	},
	"cyclope": {
		"anims": {"idle": "Units/Purple Units/Warrior/Warrior_Idle.png", "walk": "Units/Purple Units/Warrior/Warrior_Run.png",
			"attack": "Units/Purple Units/Warrior/Warrior_Attack1.png", "hurt": "Units/Purple Units/Warrior/Warrior_Guard.png"},
		"fps": {"idle": 6.0, "walk": 8.0, "attack": 10.0, "hurt": 8.0}, "noloop": ["attack", "hurt"],
	},
	"boss_samurai": {
		"cell": Vector2i(320, 320),
		"anims": {
			"idle": {"path": "Units/Black Units/Lancer/Lancer_Idle.png", "step": 2},
			"walk": "Units/Black Units/Lancer/Lancer_Run.png",
			"attack": "Units/Black Units/Lancer/Lancer_Right_Attack.png",
			"hurt": "Units/Black Units/Lancer/Lancer_Right_Defence.png",
		},
		"fps": {"idle": 6.0, "walk": 8.0, "attack": 9.0, "hurt": 8.0},
		"noloop": ["attack", "hurt"],
	},
	"phoenix": {
		"anims": {"idle": "Units/Yellow Units/Archer/Archer_Idle.png", "walk": "Units/Yellow Units/Archer/Archer_Run.png",
			"attack": "Units/Yellow Units/Archer/Archer_Shoot.png"},
		"bake": {"hue": -0.07, "sat": 1.3, "val": 1.05},
		"fps": {"idle": 6.0, "walk": 8.0, "attack": 10.0}, "noloop": ["attack"],
	},
	"gargoyle": {
		"anims": {"idle": "Units/Black Units/Warrior/Warrior_Idle.png", "walk": "Units/Black Units/Warrior/Warrior_Run.png",
			"attack": "Units/Black Units/Warrior/Warrior_Attack2.png", "hurt": "Units/Black Units/Warrior/Warrior_Guard.png"},
		"fps": {"idle": 6.0, "walk": 8.0, "attack": 10.0, "hurt": 8.0},
		"noloop": ["attack", "hurt"],
	},
	"dragon": {
		"cell": Vector2i(320, 320),
		"anims": {
			"idle": "Units/Red Units/Lancer/Lancer_Idle.png",
			"walk": "Units/Red Units/Lancer/Lancer_Run.png",
			"attack": "Units/Red Units/Lancer/Lancer_Right_Attack.png",
			"hurt": "Units/Red Units/Lancer/Lancer_Right_Defence.png",
		},
		"bake": {"sat": 1.1, "val": 0.9},
		"fps": {"idle": 6.0, "walk": 8.0, "attack": 10.0, "hurt": 8.0}, "noloop": ["attack", "hurt"],
	},
	"boss_flam": {
		"anims": {"idle": "Units/Red Units/Warrior/Warrior_Idle.png", "walk": "Units/Red Units/Warrior/Warrior_Run.png",
			"attack": "Units/Red Units/Warrior/Warrior_Attack2.png", "hurt": "Units/Red Units/Warrior/Warrior_Guard.png"},
		"fps": {"idle": 6.0, "walk": 8.0, "attack": 9.0, "hurt": 8.0},
		"noloop": ["attack", "hurt"],
	},
	# --- fx（TS 源条带 + 烘焙变色；合成类 slash/flash/beam 见 tools/generate_fx.gd，P2 接线） ---
	"fx_flame": {"cell": Vector2i(64, 64), "anims": {"play": "Particle FX/Fire_01.png"}, "h": 14, "fps": 14.0, "loop": false},
	"fx_frost": {"cell": Vector2i(64, 64), "anims": {"play": "Particle FX/Fire_01.png"}, "bake": {"hue": 0.5, "sat": 0.8}, "h": 14, "fps": 14.0, "loop": false},
	"fx_magic": {"cell": Vector2i(192, 192), "anims": {"play": "Particle FX/Explosion_01.png"}, "bake": {"hue": 0.75, "sat": 0.6}, "h": 16, "fps": 12.0, "loop": false},
	"fx_charge": {"cell": Vector2i(64, 64), "anims": {"play": "Particle FX/Fire_02.png"}, "bake": {"sat": 0.2, "val": 1.1}, "h": 12, "fps": 12.0, "loop": false},
	"fx_burst": {"cell": Vector2i(192, 192), "anims": {"play": "Particle FX/Explosion_02.png"}, "h": 16, "fps": 12.0, "loop": false},
	"fx_boom": {"cell": Vector2i(192, 192), "anims": {"play": "Particle FX/Explosion_01.png"}, "h": 16, "fps": 12.0, "loop": false},
	"fx_smoke": {"cell": Vector2i(64, 64), "anims": {"play": "Particle FX/Dust_01.png"}, "bake": {"sat": 0.15}, "h": 12, "fps": 10.0, "loop": false},
	"fx_darksmoke": {"cell": Vector2i(64, 64), "anims": {"play": "Particle FX/Dust_02.png"}, "bake": {"sat": 0.3, "val": 0.6}, "h": 12, "fps": 10.0, "loop": false},
	"fx_orb": {"cell": Vector2i(64, 64), "anims": {"play": "Particle FX/Fire_03.png"}, "bake": {"hue": 0.8, "sat": 0.7}, "h": 10, "fps": 14.0, "loop": false},
	# --- 合成特效（tools/generate_fx.gd 产出，TS 色板程序化） ---
	"fx_slash": {"cell": Vector2i(112, 112), "anims": {"play": "fx_generated/slash.png"}, "h": 14, "fps": 15.0, "loop": false},
	"fx_slash_gold": {"cell": Vector2i(112, 112), "anims": {"play": "fx_generated/slash_gold.png"}, "h": 14, "fps": 15.0, "loop": false},
	"fx_flash": {"cell": Vector2i(96, 96), "anims": {"play": "fx_generated/flash.png"}, "h": 12, "fps": 12.0, "loop": false},
	"fx_flash_gold": {"cell": Vector2i(96, 96), "anims": {"play": "fx_generated/flash_gold.png"}, "h": 12, "fps": 12.0, "loop": false},
	"fx_flash_blue": {"cell": Vector2i(96, 96), "anims": {"play": "fx_generated/flash_blue.png"}, "h": 12, "fps": 12.0, "loop": false},
	"fx_flash_yellow": {"cell": Vector2i(96, 96), "anims": {"play": "fx_generated/flash_yellow.png"}, "h": 12, "fps": 12.0, "loop": false},
	"fx_beam": {"cell": Vector2i(96, 96), "anims": {"play": "fx_generated/beam.png"}, "h": 12, "fps": 14.0, "loop": false},
	"fx_pillar": {"cell": Vector2i(96, 96), "anims": {"play": "fx_generated/pillar.png"}, "h": 16, "fps": 10.0, "loop": false},
	"fx_beams": {"cell": Vector2i(96, 96), "anims": {"play": "fx_generated/beams.png"}, "h": 16, "fps": 12.0, "loop": false},
	# --- 地标动画装饰（精灵泉水花，TS Water Foam 条带） ---
	"deco_foam": {"cell": Vector2i(192, 192), "anims": {"play": "Terrain/Tileset/Water Foam.png"}, "h": 16, "fps": 8.0, "loop": true},
}


func _init() -> void:
	var creatures: Dictionary = CREATURES_TS if STYLE == "ts" else CREATURES_NA
	print("切帧风格 = %s" % ("Tiny Swords（v6）" if STYLE == "ts" else "Ninja Adventure（v5 回滚）"))
	for creature: String in creatures:
		var cfg: Dictionary = creatures[creature]
		if cfg.has("anims"):
			_slice_ts(creature, cfg)  # TS 管线（v6）：逐动画条带
			continue
		var img: Image = _load_baked(cfg) if cfg.has("sheet") else null
		var frames := SpriteFrames.new()
		frames.remove_animation("default")
		var anim_fps: float = cfg.get("fps", FPS)
		var anim_loop: bool = cfg.get("loop", true)
		var strip: bool = cfg.get("strip", false)
		# Boss 模式（动画规格为 Dictionary）：idle 等也走独立条带分支
		var boss_mode: bool = typeof(cfg["anim"].get("idle", {})) == TYPE_DICTIONARY
		# 四方向模式（美术 v5 借鉴②，官方 sprite_character 同构）：角色表按列
		# 切 idle/walk 的 down/up/left 变体（列 0/1/2）+ 无后缀右向经典集（列 3），
		# 消费端纵向移动不再侧身 flip
		var dir_cols: Array = [[3, ""]] if not bool(cfg.get("dirs", false)) \
				else [[0, "down"], [1, "up"], [2, "left"], [3, ""]]
		for dir_cfg: Array in dir_cols:
			var dir_col := int(dir_cfg[0])
			var suffix: String = dir_cfg[1]
			if strip or boss_mode:
				break  # 条带/Boss 模式无方向概念，走下方通用循环
			for base: String in ["idle", "walk"]:
				var anim_name: String = base if suffix == "" else base + "_" + suffix
				if not cfg["anim"].has(base) or frames.has_animation(anim_name):
					continue
				frames.add_animation(anim_name)
				frames.set_animation_speed(anim_name, anim_fps)
				frames.set_animation_loop(anim_name, anim_loop)
				for row: int in cfg["anim"][base]:
					var frame_img := img.get_region(
						Rect2i(dir_col * CELL, row * CELL, CELL, CELL))
					frames.add_frame(anim_name, ImageTexture.create_from_image(frame_img))
		for anim_name: String in cfg["anim"]:
			if (anim_name == "idle" or anim_name == "walk") and not boss_mode and not strip:
				continue  # 已在方向循环处理（条带/Boss 模式在此处理）
			frames.add_animation(anim_name)
			frames.set_animation_speed(anim_name, anim_fps)
			frames.set_animation_loop(anim_name, anim_loop)
			# Boss 模式（美术 v5 完整包）：动画规格为 Dictionary 时按独立条带源
			# 切帧（cell 取条带高度，帧数=宽/高自动），不再走本表网格
			var spec: Variant = cfg["anim"][anim_name]
			if typeof(spec) == TYPE_DICTIONARY:
				var bimg := Image.load_from_file(ProjectSettings.globalize_path(spec["sheet"]))
				var bcell := int(cfg.get("cell", bimg.get_height()))
				for k in int(bimg.get_width() / bcell):
					var bf := bimg.get_region(Rect2i(k * bcell, 0, bcell, bcell))
					frames.add_frame(anim_name, ImageTexture.create_from_image(bf))
				continue
			# strip 模式 "auto"：按条带实际宽度枚举全部 16px 格
			# （Array == String 在 GDScript 是运行时错误，先 typeof 再比较）
			var rows: Variant = spec
			if typeof(rows) == TYPE_STRING and rows == "auto":
				var auto_rows: Array = []
				for k in int(img.get_width() / CELL):
					auto_rows.append(k)
				rows = auto_rows
			for row: int in rows:
				var frame_img: Image
				if strip:
					frame_img = img.get_region(Rect2i(row * CELL, 0, CELL, CELL))
				else:
					frame_img = img.get_region(
						Rect2i(int(cfg["col"]) * CELL, row * CELL, CELL, CELL))
				frames.add_frame(anim_name, ImageTexture.create_from_image(frame_img))
		var dir := ProjectSettings.globalize_path(OUT_DIR + creature)
		DirAccess.make_dir_recursive_absolute(dir)
		var path := OUT_DIR + creature + "/" + creature + "_frames.tres"
		var err := ResourceSaver.save(frames, path, ResourceSaver.FLAG_BUNDLE_RESOURCES)
		print("%-10s %d 组动画 %s" % [creature, frames.get_animation_names().size(),
			"OK" if err == OK else "失败:%d" % err])
	quit(0)


## 读原始表 → 逐像素 HSV 烘焙 → 镜像。灰阶/描边（s≈0）只受 val 影响，轮廓自然保住
func _load_baked(cfg: Dictionary) -> Image:
	var sheet: String = cfg["sheet"]
	if not sheet.begins_with("res://"):
		sheet = SHEETS_DIR + sheet
	var img := Image.load_from_file(ProjectSettings.globalize_path(sheet))
	var bake: Dictionary = cfg.get("bake", {})
	var hue: float = bake.get("hue", 0.0)
	var sat: float = bake.get("sat", 1.0)
	var val: float = bake.get("val", 1.0)
	if hue != 0.0 or sat != 1.0 or val != 1.0:
		for y in img.get_height():
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				if c.a > 0.0:
					img.set_pixel(x, y, Color.from_hsv(
						fposmod(c.h + hue, 1.0),
						clampf(c.s * sat, 0.0, 1.0),
						clampf(c.v * val, 0.0, 1.0),
						c.a))
	if bool(cfg.get("flop", false)):
		img.flip_x()
	return img


# ============================ TS 管线（美术 v6） ============================

## 逐动画条带 → 全体 union bbox 裁剪（跨动画锚点一致）→ ÷p 还原原生（k=1 直出；
## 显式 k 档才众数抽取）→ HSV 烘焙 → 帧纹理内嵌压缩二进制 .res（消费路径同构）。
func _slice_ts(creature: String, cfg: Dictionary) -> void:
	var cell: Vector2i = cfg.get("cell", Vector2i(192, 192))
	var strips: Dictionary = {}
	for anim: String in cfg["anims"]:
		var spec: Variant = cfg["anims"][anim]
		var rel := ""
		var from := 0
		var count := -1
		var step := 1
		if typeof(spec) == TYPE_DICTIONARY:
			rel = spec["path"]
			from = int(spec.get("from", 0))
			count = int(spec.get("count", -1))
			step = int(spec.get("step", 1))
		else:
			rel = spec
		var img := Image.load_from_file(ProjectSettings.globalize_path(TS_DIR + rel))
		if img == null:
			push_warning("TS 素材缺失，跳过 %s: %s" % [creature, rel])
			return
		var n := int(img.get_width() / cell.x)
		var to := n if count < 0 else mini(from + count, n)
		strips[anim] = {"img": img, "from": maxi(0, from), "to": to, "step": maxi(1, step)}
	# union bbox（帧内局部坐标）
	var min_x := 1 << 30
	var min_y := 1 << 30
	var max_x := -(1 << 30)
	var max_y := -(1 << 30)
	for anim: String in strips:
		var s: Dictionary = strips[anim]
		for k in range(s["from"], s["to"], s["step"]):
			var b := _ts_bbox(s["img"], Rect2i(k * cell.x, 0, cell.x, cell.y))
			if b.get_area() <= 0:
				continue
			# bbox 返回条带绝对坐标——先平移到帧内局部坐标再并 union，
			# 否则跨帧 min/max 横向铺满整条带（每帧裁出多角色横带的回归即此）
			b.position.x -= k * cell.x
			min_x = mini(min_x, b.position.x)
			min_y = mini(min_y, b.position.y)
			max_x = maxi(max_x, b.position.x + b.size.x)
			max_y = maxi(max_y, b.position.y + b.size.y)
	if max_x < min_x:
		push_warning("TS 全空帧，跳过 %s" % creature)
		return
	var uw := max_x - min_x
	var uh := max_y - min_y
	# 密度政策（2026-09-20「糊」根治定稿，取代当日早前的 h 目标档）：角色/NPC/Boss
	#   一律 k=1 原生直出——÷p 还原作者分辨率后不再抽取。此前 h 档迫使 k=3 众数
	#   抽取：每轴丢 2/3 信息（像素剩 11%），1px 描边在 3×3 投票中必败被系统性
	#   吃掉，再 ×5 放大 = 「糊」的真源（渲染层 Nearest/整数缩放早已干净）。
	#   例外两键：'"k": N' 显式抽取档（史莱姆系 k=2 为分裂子代留 1 档位）；
	#   '"h"' 仅 fx/deco 沿用旧语义（特效消费端 fx_scale 不动，屏占保持现状）
	var p := _block_period((strips[strips.keys()[0]]["img"] as Image))
	p = maxi(p, 1)
	if cfg.has("h"):
		# fx/deco 沿旧口径：bbox 左上锚定——VFX 帧内容逐帧游走（火焰上窜/爆开），
		# 格心非其锚点，对称扩边会虚增画布、连带改变 k 档与形状（flame 事故）
		min_x -= min_x % p
		min_y -= min_y % p
		uw = maxi(p, (uw + p - 1) / p * p)
		uh = maxi(p, (uh + p - 1) / p * p)
	else:
		# 角色系画布以格心对称（2026-09-20 错位根治）：旧法贴内容包围盒左上角，
		# 宽画幅攻击帧（Lancer 横枪）会把画布拉向一侧——身体轴偏离画布中心 =
		# 可见身体偏离逻辑原点（阴影/攻击判定错位；实测 Lancer 偏 23~47 原生 px）。
		# TS 全家角色锚在格心，画布以格心居中对称扩边（尺寸 + 2×内容中心偏移），
		# 格心即跨动画不动的轴/脚线基准；内容必仍在画布内（uw+2|dx| ≤ cell 恒成立）
		var dx: int = absi((min_x + max_x) / 2 - cell.x / 2)
		var dy: int = absi((min_y + max_y) / 2 - cell.y / 2)
		uw = maxi(p, (uw + 2 * dx + p - 1) / p * p)
		uh = maxi(p, (uh + 2 * dy + p - 1) / p * p)
		min_x = (cell.x - uw) / 2
		min_y = (cell.y - uh) / 2
	var n_h: int = uh / p
	var k: int = clampi(int(cfg.get("k", 1)), 1, 8)
	if not cfg.has("k") and cfg.has("h"):
		k = clampi(round(float(n_h) / float(int(cfg["h"]))), 1, 8)
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	var base_fps: Variant = cfg.get("fps", FPS)
	var base_loop: bool = cfg.get("loop", true)
	var noloop: Array = cfg.get("noloop", [])
	var bake: Dictionary = cfg.get("bake", {})
	var idle_img: Image = null  # idle 首帧留样（帧几何 meta 计算用）
	for anim: String in strips:
		var s2: Dictionary = strips[anim]
		frames.add_animation(anim)
		var fps := 6.0
		if typeof(base_fps) == TYPE_DICTIONARY:
			fps = float(base_fps.get(anim, 6.0))
		elif typeof(base_fps) == TYPE_FLOAT:
			fps = float(base_fps)
		frames.set_animation_speed(anim, fps)
		frames.set_animation_loop(anim, base_loop and not noloop.has(anim))
		for fi in range(s2["from"], s2["to"], s2["step"]):
			var frame_img: Image = (s2["img"] as Image).get_region(
				Rect2i(fi * cell.x + min_x, min_y, uw, uh))
			if p > 1:
				frame_img.resize(uw / p, uh / p, Image.INTERPOLATE_NEAREST)
			frame_img = _align_mul(frame_img, k)
			frame_img = _mode_decimate(frame_img, k)
			if not bake.is_empty():
				_ts_bake(frame_img, bake)
			frames.add_frame(anim, ImageTexture.create_from_image(frame_img))
			if anim == "idle" and fi == s2["from"]:
				idle_img = frame_img
	# 帧几何元数据（角色系）：idle 首帧脚点/内容宽，运行时阴影锚定消费——
	# 切帧时一次算好（2026-09-20 GUI 卡死教训：运行时 get_image() 在真渲染器
	# 上走 GPU 读回/管线同步，怪物生成帧内调用会卡死 Metal 提交；无头虚拟
	# 渲染器秒回故六测全绿、实机必卡）。meta 随资源持久化，加载即纯数据
	if idle_img != null:
		var feet := 0
		var left := idle_img.get_width()
		var right := 0
		for y in idle_img.get_height():
			for x in idle_img.get_width():
				if idle_img.get_pixel(x, y).a > 0.5:
					feet = maxi(feet, y)
					left = mini(left, x)
					right = maxi(right, x)
		frames.set_meta("feet", feet)
		frames.set_meta("cw", (right - left + 1) if right >= left else 1)
	var dir := ProjectSettings.globalize_path(OUT_DIR + creature)
	DirAccess.make_dir_recursive_absolute(dir)
	# 二进制 .res + zlib 压缩（原生直出后文本 .tres 会 4× 膨胀到 40MB+ 不可接受；
	# 免 import 性质不变，load() 透明加载，导出 PCK 走 remap 与 .tres 同构）
	var path := OUT_DIR + creature + "/" + creature + "_frames.res"
	var err := ResourceSaver.save(frames, path,
			ResourceSaver.FLAG_BUNDLE_RESOURCES | ResourceSaver.FLAG_COMPRESS)
	print("%-16s native %3d×%-3d ×k%d → %3d×%-3d %2d 组动画 %s" % [creature,
		uw / p, n_h, k, (uw / p + k - 1) / k, (n_h + k - 1) / k,
		frames.get_animation_names().size(), "OK" if err == OK else "失败:%d" % err])


## 右/下扩透明边到 k 的倍数（众数抽取要求整除；新增的是透明无视觉影响）
func _align_mul(img: Image, k: int) -> Image:
	if k <= 1:
		return img
	var w := maxi(1, (img.get_width() + k - 1) / k * k)
	var h := maxi(1, (img.get_height() + k - 1) / k * k)
	if w == img.get_width() and h == img.get_height():
		return img
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	out.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i.ZERO)
	return out


## 众数滤波抽取：每输出像素 = k×k 块内出现最多的不透明色（平局取先到）；
## 全透明块输出透明。描边/主色留存率远高于点采样（英雄「糊」的根治）
func _mode_decimate(img: Image, k: int) -> Image:
	if k <= 1:
		return img
	var w := maxi(1, img.get_width() / k)
	var h := maxi(1, img.get_height() / k)
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var tally := {}
			for by in k:
				for bx in k:
					var c := img.get_pixel(x * k + bx, y * k + by)
					if c.a < 0.05:
						continue
					var key: int = c.to_rgba32()
					var e: Array = tally.get(key, [0, c])
					e[0] = e[0] + 1
					tally[key] = e
			var best := Color(0, 0, 0, 0)
			var best_n := 0
			for key: int in tally:
				var e: Array = tally[key]
				if e[0] > best_n:
					best_n = e[0]
					best = e[1]
			out.set_pixel(x, y, best)
	return out


## 横向同色游程统计 → 素材预放大周期（2× 素材的 2-游程远多于 1-游程；
## 原生素材则 1-游程占优。用于整数抽取时偏向偶数除数，保像素块均匀）
func _block_period(img: Image) -> int:
	var n1 := 0
	var n2 := 0
	for y in range(0, img.get_height(), 7):
		var run := 1
		var prev: Color = img.get_pixel(0, y)
		for x in range(1, img.get_width()):
			var c := img.get_pixel(x, y)
			if c == prev:
				run += 1
			else:
				if run == 1:
					n1 += 1
				elif run == 2:
					n2 += 1
				run = 1
				prev = c
	return 2 if n2 > n1 * 1.5 else 1


## 帧内容 bbox（alpha>0.08 视为内容）
func _ts_bbox(img: Image, r: Rect2i) -> Rect2i:
	var min_x := 1 << 30
	var min_y := 1 << 30
	var max_x := -(1 << 30)
	var max_y := -(1 << 30)
	for y in range(r.position.y, r.position.y + r.size.y):
		for x in range(r.position.x, r.position.x + r.size.x):
			if img.get_pixel(x, y).a > 0.08:
				min_x = mini(min_x, x)
				max_x = maxi(max_x, x)
				min_y = mini(min_y, y)
				max_y = maxi(max_y, y)
	if max_x < min_x:
		return Rect2i()
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)


## 逐像素 HSV 烘焙（重采样后的小帧上做，量小；灰阶/描边 s≈0 只受 val 影响）
func _ts_bake(img: Image, bake: Dictionary) -> void:
	var hue: float = bake.get("hue", 0.0)
	var sat: float = bake.get("sat", 1.0)
	var val: float = bake.get("val", 1.0)
	if hue == 0.0 and sat == 1.0 and val == 1.0:
		return
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a > 0.0:
				img.set_pixel(x, y, Color.from_hsv(
					fposmod(c.h + hue, 1.0),
					clampf(c.s * sat, 0.0, 1.0),
					clampf(c.v * val, 0.0, 1.0),
					c.a))
