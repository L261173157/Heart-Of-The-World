## 高清素材切帧工具 v2（两阶段，配合编辑器 import）：
##   1) godot --headless --path Code -s tools/slice_spritesheets_v2.gd slice
##      消费 ~/hotw-assets/（仓库外，清单见其 INVENTORY.md）的 LuizMelo/Admurin
##      高清动画：布局切格（条带/网格）+ HSV 烘焙 → 逐帧 PNG 落盘
##      assets/creatures/frames/<name>/tex/<anim>_f<i>.png（PNG 无损压缩，
##      相比内嵌原始字节体积缩 10 倍以上）
##   2) godot --headless --path Code --import   （导入 PNG 生成纹理）
##   3) godot --headless --path Code -s tools/slice_spritesheets_v2.gd pack
##      组装 SpriteFrames（引用已导入的外部纹理，不再内嵌），输出
##      assets/creatures/frames/<name>/<name>_frames.tres
##   两阶段均可追加可选物种名只处理单个条目（如 `-- slice medieval_warrior_v2`），
##   省得全量重切在 iCloud 路径上重写上千张 PNG
## 动画名统一到 MonsterBase._update_anim 的状态映射：idle/walk/attack/die
## （玩家额外 attack2/attack3 连击段）。源素材许可证：LuizMelo/FireWorm=CC0；
## Admurin=免商用禁转售（原始图不入仓库，产物为改色裁切后的游戏资源，
## 来源记录见 Code/LICENSE）。
extends SceneTree

const OUT_DIR := "res://assets/creatures/frames/"
## 源资产根目录（仓库外）；可用环境变量 HOTW_ASSETS 覆盖
static var ASSETS_ROOT: String = OS.get_environment("HOTW_ASSETS") \
		if OS.get_environment("HOTW_ASSETS") != "" \
		else OS.get_environment("HOME") + "/hotw-assets/"

## 每条目：
##   src: 相对 ASSETS_ROOT 的目录；cell: 帧格尺寸；grid: true=R×C 网格 false=单行条带
##   anim: {统一名: [文件名, 帧数上限]}；bake: HSV（hue 平移/sat、val 乘子）；
##   fps: 该生物帧率覆盖（默认 10）；fps_anim: 按动画名覆盖帧率（如短攻击窗下 attack 提速）；
##   noloop: 额外的非循环动画名列表（die 默认即非循环）；
##   durations: 按动画名逐帧时长（帧单位，1.0=1/fps 秒；不足帧数尾部补 1.0）——
##     手感重排用（HeroMotion v2：攻击"预备→爆发→收招"非均匀节奏）
const CREATURES := {
	# --- LuizMelo MCF1+2（CC0，lg-rpg 镜像）---
	"slime_v2": {
		"src": "lg-rpg/lg_rpg_server/public/assets/enemies/slime", "cell": [156, 156],
		"grid": false, "bake": {"hue": -0.42},
		"anim": {"idle": ["idle.png", 14], "walk": ["walk.png", 10], "attack": ["attack.png", 10], "die": ["death.png", 10]},
	},
	"slime_ice_v2": {
		"src": "lg-rpg/lg_rpg_server/public/assets/enemies/slime", "cell": [156, 156],
		"grid": false, "bake": {"hue": 0.12, "sat": 0.9, "val": 1.05},
		"anim": {"idle": ["idle.png", 14], "walk": ["walk.png", 10], "attack": ["attack.png", 10], "die": ["death.png", 10]},
	},
	"slime_swamp_v2": {
		"src": "lg-rpg/lg_rpg_server/public/assets/enemies/slime", "cell": [156, 156],
		"grid": false, "bake": {"hue": -0.12, "sat": 1.2, "val": 0.8},
		"anim": {"idle": ["idle.png", 14], "walk": ["walk.png", 10], "attack": ["attack.png", 10], "die": ["death.png", 10]},
	},
	"goblin_v2": {
		"src": "lg-rpg/lg_rpg_server/public/assets/enemies/goblin", "cell": [150, 150],
		"grid": false,
		"anim": {"idle": ["idle.png", 8], "walk": ["run.png", 8], "attack": ["attack_1.png", 8], "die": ["death.png", 8]},
	},
	"imp_v2": {
		"src": "lg-rpg/lg_rpg_server/public/assets/enemies/goblin", "cell": [150, 150],
		"grid": false, "bake": {"hue": -0.46, "sat": 1.25, "val": 0.85},
		"anim": {"idle": ["idle.png", 8], "walk": ["run.png", 8], "attack": ["attack_1.png", 8], "die": ["death.png", 8]},
	},
	"bat_v2": {
		"src": "lg-rpg/lg_rpg_server/public/assets/enemies/bat", "cell": [87, 87],
		"grid": false,
		"anim": {"idle": ["fly.png", 6], "walk": ["fly.png", 6], "attack": ["attack.png", 6], "die": ["death.png", 6]},
	},
	"skeleton_v2": {
		"src": "lg-rpg/lg_rpg_server/public/assets/enemies/skeleton", "cell": [150, 150],
		"grid": false,
		"anim": {"idle": ["idle.png", 10], "walk": ["walk.png", 8], "attack": ["attack_1.png", 8], "die": ["death.png", 8]},
	},
	"mushroom_v2": {
		"src": "lg-rpg/lg_rpg_server/public/assets/enemies/mushroom", "cell": [150, 150],
		"grid": false,
		"anim": {"idle": ["idle.png", 8], "walk": ["run.png", 8], "attack": ["attack_1.png", 8], "die": ["death.png", 8]},
	},
	"sprout_v2": {
		"src": "lg-rpg/lg_rpg_server/public/assets/enemies/mushroom", "cell": [150, 150],
		"grid": false, "bake": {"hue": 0.16, "sat": 1.1, "val": 1.05},
		"anim": {"idle": ["idle.png", 8], "walk": ["run.png", 8], "attack": ["attack_1.png", 8], "die": ["death.png", 8]},
	},
	"ghost_v2": {
		"src": "lg-rpg/lg_rpg_server/public/assets/enemies/flying_eye", "cell": [150, 150],
		"grid": false, "bake": {"sat": 0.25, "val": 1.1},
		"anim": {"idle": ["flight.png", 8], "walk": ["flight.png", 8], "attack": ["attack_1.png", 8], "die": ["death.png", 6]},
	},
	"phoenix_v2": {
		"src": "lg-rpg/lg_rpg_server/public/assets/enemies/flying_eye", "cell": [150, 150],
		"grid": false, "bake": {"hue": 0.02, "sat": 1.5, "val": 1.05},
		"anim": {"idle": ["flight.png", 8], "walk": ["flight.png", 8], "attack": ["attack_1.png", 8], "die": ["death.png", 6]},
	},
	# --- Admurin（免商用）---
	"golem_v2": {
		"src": "unzipped/Enemy_Galore_I/Golem/No Armor", "cell": [64, 64],
		"grid": false, "fps": 8.0,
		"anim": {"idle": ["Golem_IdleA.png", 4], "walk": ["Golem_Run.png", 4], "attack": ["Golem_AttackA.png", 6], "die": ["Golem_DeathA.png", 8]},
	},
	"golem_armored_v2": {
		"src": "unzipped/Enemy_Galore_I/Golem/Armored", "cell": [64, 64],
		"grid": false, "fps": 8.0,
		"anim": {"idle": ["Golem_Armor_Idle.png", 4], "walk": ["Golem_Armor_Run.png", 4], "attack": ["Golem_Armor_AttackA.png", 6], "die": ["Golem_Armor_ArmorBreak.png", 8]},
	},
	"treant_v2": {
		"src": "unzipped/Bosses_Dino_Rex/Dino Rex", "cell": [128, 128],
		"grid": false, "fps": 8.0, "bake": {"hue": 0.30, "sat": 1.25, "val": 0.75},
		"anim": {"idle": ["dino_rex_idle.png", 5], "walk": ["dino_rex_move.png", 10], "attack": ["dino_rex_attack_A.png", 21], "die": ["dino_rex_hurt.png", 4]},
	},
	"pebble_v2": {
		"src": "unzipped/Enemy_Galore_I/Pebble", "cell": [128, 128], "grid": false,
		"anim": {"idle": ["Pebble_Idle.png", 4], "walk": ["Pebble_Run.png", 6], "die": ["Pebble_Death.png", 8]},
	},
	"crab_v2": {
		"src": "unzipped/Enemy_Galore_I/Crab", "cell": [128, 128], "grid": false,
		"bake": {"hue": -0.45, "sat": 1.2},
		"anim": {"idle": ["Crab_Idle.png", 4], "walk": ["Crab_Run.png", 6], "attack": ["Crab_AttackA.png", 6], "die": ["Crab_Death.png", 8]},
	},
	# --- Admurin 网格包（128px 格）---
	"boar_v2": {
		"src": "unzipped/Monster_Pack_21/Monster Pack 21 (Bovine)/Spritesheets/Updated Boar",
		"cell": [128, 128], "grid": true,
		"anim": {"idle": ["Boar_Idle.png", 16], "walk": ["Boar_Move.png", 24], "attack": ["Boar_Attack.png", 24]},
	},
	"rabbit_v2": {
		"src": "unzipped/Monster_Pack_Free/Monster Pack (Free)/Spritesheets/Updated Rabbit",
		"cell": [128, 128], "grid": true,
		"anim": {"idle": ["Rabbit_Brown_Idle.png", 16], "walk": ["Rabbit_Brown_Move.png", 24]},
	},
	"snowman_v2": {
		"src": "unzipped/Monster_Pack_82/Monster Pack 82 (Event)/Snowmen",
		"cell": [128, 128], "grid": true, "fps": 8.0,
		"anim": {"idle": ["Christmas_Snowman_A_Idle.png", 16], "walk": ["Christmas_Snowman_A_Move.png", 24]},
	},
	# --- Admurin Boss（128px 长条带；无 death 者以 hurt 代）---
	"frog_v2": {
		"src": "unzipped/Bosses_Frogger/Frogger", "cell": [128, 128], "grid": false, "fps": 10.0,
		"anim": {"idle": ["frogger_idle.png", 5], "walk": ["frogger_move.png", 8], "attack": ["frogger_spit.png", 10], "die": ["frogger_hurt.png", 4]},
	},
	"penguin_v2": {
		"src": "unzipped/Bosses_Pengu/Pengu", "cell": [128, 128], "grid": false, "fps": 10.0,
		"anim": {"idle": ["pengu_idle.png", 5], "walk": ["pengu_move.png", 8], "attack": ["pengu_attack_peck.png", 8], "die": ["pengu_hurt.png", 4]},
	},
	"badger_v2": {
		"src": "unzipped/Bosses_Badger/Badger", "cell": [128, 128], "grid": false, "fps": 10.0,
		"anim": {"idle": ["badger_idle.png", 5], "walk": ["badger_move.png", 12], "attack": ["badger_attack_A.png", 18], "die": ["badger_hurt.png", 4]},
	},
	"golem_king_v2": {
		"src": "unzipped/Bosses_Gollux/Gollux", "cell": [128, 128], "grid": false, "fps": 10.0,
		"anim": {"idle": ["gollux_idle.png", 5], "walk": ["gollux_move.png", 12], "attack": ["gollux_attack_A.png", 17], "die": ["gollux_hit.png", 4]},
	},
	"dino_v2": {
		"src": "unzipped/Bosses_Dino_Rex/Dino Rex", "cell": [128, 128], "grid": false, "fps": 10.0,
		"anim": {"idle": ["dino_rex_idle.png", 5], "walk": ["dino_rex_move.png", 10], "attack": ["dino_rex_attack_A.png", 21], "die": ["dino_rex_hurt.png", 4]},
	},
	# --- 玩家（LuizMelo Martial Hero，CC0）---
	"martial_hero": {
		"src": "small-adventure-game/UnJuegoDeAventuras/Assets/Martial Hero/Sprites",
		"cell": [200, 200], "grid": false, "fps": 12.0,
		"anim": {"idle": ["Idle.png", 8], "walk": ["Run.png", 8], "attack": ["Attack1.png", 6], "attack1": ["Attack1.png", 6], "attack2": ["Attack2.png", 6], "hurt": ["Take Hit.png", 4], "die": ["Death.png", 6]},
	},
	"medieval_warrior_v2": {
		"src": "small-adventure-game/UnJuegoDeAventuras/Assets/Medieval Warrior Pack 2/Sprites",
		"cell": [150, 150], "grid": false, "fps": 12.0,
		"noloop": ["attack1", "attack2", "attack3", "attack4", "hurt"],
		"anim": {"idle": ["Idle.png", 8], "walk": ["Run.png", 8], "attack1": ["Attack1.png", 4], "attack2": ["Attack2.png", 4], "attack3": ["Attack3.png", 4], "attack4": ["Attack4.png", 4], "hurt": ["Take Hit.png", 4], "die": ["Death.png", 6]},
	},
	# --- 美术 v4 试点（AI 生成条带；方案真源 Documents/美术方案-v4.md）---
	## 素材经 tools/build_ai_strips.gd 产出（契约见其文件头）：条带单行横向、等宽格；
	## cell 随工具产出的格尺寸改（当前=256）
	"slime_pilot": {
		"src": "pilot/current/slime", "cell": [256, 256], "grid": false,
		"anim": {"idle": ["idle.png", 16], "walk": ["walk.png", 16], "attack": ["attack.png", 16], "die": ["die.png", 16]},
	},
	"slime_ice_pilot": {
		"src": "pilot/current/slime_ice", "cell": [256, 256], "grid": false,
		"anim": {"idle": ["idle.png", 16], "walk": ["walk.png", 16], "attack": ["attack.png", 16], "die": ["die.png", 16]},
	},
	"slime_swamp_pilot": {
		"src": "pilot/current/slime_swamp", "cell": [256, 256], "grid": false,
		"anim": {"idle": ["idle.png", 16], "walk": ["walk.png", 16], "attack": ["attack.png", 16], "die": ["die.png", 16]},
	},
	# --- 美术 v4 Phase C（ComfyUI 全本地生成，21 物种批量条目，配置同 pilot）---
	"goblin_pilot": { "src": "pilot/current/goblin", "cell": [256, 256], "grid": false,
		"anim": {"idle": ["idle.png", 16], "walk": ["walk.png", 16], "attack": ["attack.png", 16], "die": ["die.png", 16]} },
	"imp_pilot": { "src": "pilot/current/imp", "cell": [256, 256], "grid": false,
		"anim": {"idle": ["idle.png", 16], "walk": ["walk.png", 16], "attack": ["attack.png", 16], "die": ["die.png", 16]} },
	"bat_pilot": { "src": "pilot/current/bat", "cell": [256, 256], "grid": false,
		"anim": {"idle": ["idle.png", 16], "walk": ["walk.png", 16], "attack": ["attack.png", 16], "die": ["die.png", 16]} },
	"boar_pilot": { "src": "pilot/current/boar", "cell": [256, 256], "grid": false,
		"anim": {"idle": ["idle.png", 16], "walk": ["walk.png", 16], "attack": ["attack.png", 16], "die": ["die.png", 16]} },
	"frog_pilot": { "src": "pilot/current/frog", "cell": [256, 256], "grid": false,
		"anim": {"idle": ["idle.png", 16], "walk": ["walk.png", 16], "attack": ["attack.png", 16], "die": ["die.png", 16]} },
	"ghost_pilot": { "src": "pilot/current/ghost", "cell": [256, 256], "grid": false,
		"anim": {"idle": ["idle.png", 16], "walk": ["walk.png", 16], "attack": ["attack.png", 16], "die": ["die.png", 16]} },
	"skeleton_pilot": { "src": "pilot/current/skeleton", "cell": [256, 256], "grid": false,
		"anim": {"idle": ["idle.png", 16], "walk": ["walk.png", 16], "attack": ["attack.png", 16], "die": ["die.png", 16]} },
	"sprout_pilot": { "src": "pilot/current/sprout", "cell": [256, 256], "grid": false,
		"anim": {"idle": ["idle.png", 16], "walk": ["walk.png", 16], "attack": ["attack.png", 16], "die": ["die.png", 16]} },
	"mandrake_pilot": { "src": "pilot/current/mandrake", "cell": [256, 256], "grid": false,
		"anim": {"idle": ["idle.png", 16], "walk": ["walk.png", 16], "attack": ["attack.png", 16], "die": ["die.png", 16]} },
	"phoenix_pilot": { "src": "pilot/current/phoenix", "cell": [256, 256], "grid": false,
		"anim": {"idle": ["idle.png", 16], "walk": ["walk.png", 16], "attack": ["attack.png", 16], "die": ["die.png", 16]} },
	"crab_pilot": { "src": "pilot/current/crab", "cell": [256, 256], "grid": false,
		"anim": {"idle": ["idle.png", 16], "walk": ["walk.png", 16], "attack": ["attack.png", 16], "die": ["die.png", 16]} },
	"pebble_pilot": { "src": "pilot/current/pebble", "cell": [256, 256], "grid": false,
		"anim": {"idle": ["idle.png", 16], "walk": ["walk.png", 16], "attack": ["attack.png", 16], "die": ["die.png", 16]} },
	"golem_pilot": { "src": "pilot/current/golem", "cell": [256, 256], "grid": false,
		"anim": {"idle": ["idle.png", 16], "walk": ["walk.png", 16], "attack": ["attack.png", 16], "die": ["die.png", 16]} },
	"yeti_pilot": { "src": "pilot/current/yeti", "cell": [256, 256], "grid": false,
		"anim": {"idle": ["idle.png", 16], "walk": ["walk.png", 16], "attack": ["attack.png", 16], "die": ["die.png", 16]} },
	"penguin_pilot": { "src": "pilot/current/penguin", "cell": [256, 256], "grid": false,
		"anim": {"idle": ["idle.png", 16], "walk": ["walk.png", 16], "attack": ["attack.png", 16], "die": ["die.png", 16]} },
	"rabbit_pilot": { "src": "pilot/current/rabbit", "cell": [256, 256], "grid": false,
		"anim": {"idle": ["idle.png", 16], "walk": ["walk.png", 16], "attack": ["attack.png", 16], "die": ["die.png", 16]} },
	"badger_pilot": { "src": "pilot/current/badger", "cell": [256, 256], "grid": false,
		"anim": {"idle": ["idle.png", 16], "walk": ["walk.png", 16], "attack": ["attack.png", 16], "die": ["die.png", 16]} },
	"treant_pilot": { "src": "pilot/current/treant", "cell": [256, 256], "grid": false,
		"anim": {"idle": ["idle.png", 16], "walk": ["walk.png", 16], "attack": ["attack.png", 16], "die": ["die.png", 16]} },
	"golem_king_pilot": { "src": "pilot/current/golem_king", "cell": [256, 256], "grid": false,
		"anim": {"idle": ["idle.png", 16], "walk": ["walk.png", 16], "attack": ["attack.png", 16], "die": ["die.png", 16]} },
	"hero_pilot": { "src": "pilot/current/hero", "cell": [256, 256], "grid": false, "fps": 12.0,
		## 2026-09-13 晚以 base 为参考 img2img 重生成全套关键帧（walk_a/b、attack1-3、
		## hurt、melt、puddle，同一人设），真迈步双帧+三段独立招式+受击段上线；
		## 旧四套人设混装源图仍隔离于 ~/hotw-assets/quarantine_hero_designs/。
		## 同日修正 FLIP_SPECIES 误翻转（v3 base 本朝右，此前条带被翻成朝左，
		## 玩家背朝移动方向——"走路不对"根因之一）
		## 2026-09-16 HeroMotion v2 手感重排：攻击帧像素实证 f2=蓄力顶点、f3=全力
		## 斩击、f4≡f5=收招死帧（程序补间尾巴重复），均匀 22fps 无弧线=出刀"生硬"
		## 根因之一。逐帧时长改"预备缓-爆发快-收招沉"：斩击帧（f3）压在判定窗
		## （0.18s）前段与挥砍特效同步，收招段沉住等连击重触发/linger 收尾；
		## 第三段（跃起下劈）预备更长读出"轻轻重"的段位差
		"fps_anim": {"attack": 22.0, "attack2": 22.0, "attack3": 22.0},
		"durations": {
			"attack": [0.9, 0.8, 1.0, 0.45, 1.15, 1.15],
			"attack2": [0.9, 0.8, 1.0, 0.45, 1.15, 1.15],
			"attack3": [1.2, 1.0, 1.4, 0.4, 1.15, 1.2],
		},
		"noloop": ["attack", "attack2", "attack3", "hurt"],
		"anim": {"idle": ["idle.png", 16], "walk": ["walk.png", 16], "attack": ["attack.png", 16],
			"attack2": ["attack2.png", 16], "attack3": ["attack3.png", 16], "hurt": ["hurt.png", 16],
			"die": ["die.png", 16]} },
}


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	# 可选第二参数：只处理该物种（slice/pack 通用过滤）
	var only: String = args[1] if args.size() > 1 else ""
	if args.size() > 0 and args[0] == "pack":
		_pack_phase(only)
	else:
		_slice_phase(only)
	quit(0)


## 阶段一：切格 + 烘焙 → 逐帧 PNG 落盘
func _slice_phase(only := "") -> void:
	var total := 0
	for creature: String in CREATURES:
		if only != "" and creature != only:
			continue
		var cfg: Dictionary = CREATURES[creature]
		var cell_imgs: Dictionary = _load_baked_cells(cfg)
		if cell_imgs.is_empty():
			print("%-22s 失败：无可用源文件" % creature)
			continue
		var dir_path := ProjectSettings.globalize_path(OUT_DIR + creature + "/tex")
		DirAccess.make_dir_recursive_absolute(dir_path)
		var count := 0
		for anim_name: String in cfg["anim"]:
			var file_name: String = cfg["anim"][anim_name][0]
			var frame_count: int = cfg["anim"][anim_name][1]
			if not cell_imgs.has(file_name):
				print("%-22s 警告：缺 %s，跳过动画 %s" % [creature, file_name, anim_name])
				continue
			var cells: Array = cell_imgs[file_name]
			if frame_count > cells.size():
				frame_count = cells.size()
			for i in frame_count:
				var img: Image = cells[i]
				img.save_png(OUT_DIR + creature + "/tex/" + anim_name + "_f" + str(i) + ".png")
				count += 1
		total += count
		print("%-22s %d 帧 PNG" % [creature, count])
	print("切片完成：%d 帧。下一步：--import 后跑 pack 阶段" % total)


## 阶段二：load 已导入的帧纹理 → 组装引用式 SpriteFrames
func _pack_phase(only := "") -> void:
	var ok_count := 0
	var matched := 0
	for creature: String in CREATURES:
		if only != "" and creature != only:
			continue
		matched += 1
		var cfg: Dictionary = CREATURES[creature]
		var tex_dir := OUT_DIR + creature + "/tex/"
		var frames := SpriteFrames.new()
		frames.remove_animation("default")
		var base_fps: float = cfg.get("fps", 10.0)
		var fps_anim: Dictionary = cfg.get("fps_anim", {})
		var noloop: Array = cfg.get("noloop", [])
		var durations_cfg: Dictionary = cfg.get("durations", {})
		var anim_count := 0
		for anim_name: String in cfg["anim"]:
			var i := 0
			var any := false
			var dur_list: Array = durations_cfg.get(anim_name, [])
			while FileAccess.file_exists(tex_dir + anim_name + "_f" + str(i) + ".png"):
				var tex: Texture2D = load(tex_dir + anim_name + "_f" + str(i) + ".png")
				if tex == null:
					break
				if not any:
					frames.add_animation(anim_name)
					frames.set_animation_speed(anim_name, float(fps_anim.get(anim_name, base_fps)))
					frames.set_animation_loop(anim_name, anim_name != "die" and not noloop.has(anim_name))
					any = true
				## 逐帧时长（帧单位）：列表不足的帧补 1.0（与 pack 其余行为一致，可局部重排）
				var dur: float = float(dur_list[i]) if i < dur_list.size() else 1.0
				frames.add_frame(anim_name, tex, dur)
				i += 1
			if any:
				anim_count += 1
		var path := OUT_DIR + creature + "/" + creature + "_frames.tres"
		var err := ResourceSaver.save(frames, path)
		if err == OK:
			ok_count += 1
		print("%-22s %d 组动画 %s" % [creature, anim_count, "OK" if err == OK else "失败:%d" % err])
	print("组装完成：%d/%d" % [ok_count, matched if only != "" else CREATURES.size()])


## 读目录下每个涉及的文件 → HSV 烘焙（整图）→ 按布局切格返回 {文件名: [Image...]}
func _load_baked_cells(cfg: Dictionary) -> Dictionary:
	var src_dir: String = ASSETS_ROOT + cfg["src"]
	var cell_w: int = cfg["cell"][0]
	var cell_h: int = cfg["cell"][1]
	var grid: bool = cfg.get("grid", false)
	var out: Dictionary = {}
	var needed: Array = []
	for anim_name: String in cfg["anim"]:
		var f: String = cfg["anim"][anim_name][0]
		if not needed.has(f):
			needed.append(f)
	for file_name: String in needed:
		var path := src_dir + "/" + file_name
		if not FileAccess.file_exists(path):
			continue
		var img := Image.load_from_file(path)
		if img == null:
			continue
		img = _bake_hsv(img, cfg.get("bake", {}))
		var cells: Array = []
		if grid:
			for gy in img.get_height() / cell_h:
				for gx in img.get_width() / cell_w:
					cells.append(img.get_region(Rect2i(gx * cell_w, gy * cell_h, cell_w, cell_h)))
		else:
			for gx in img.get_width() / cell_w:
				cells.append(img.get_region(Rect2i(gx * cell_w, 0, cell_w, cell_h)))
		out[file_name] = cells
	return out


func _bake_hsv(img: Image, bake: Dictionary) -> Image:
	var hue: float = bake.get("hue", 0.0)
	var sat: float = bake.get("sat", 1.0)
	var val: float = bake.get("val", 1.0)
	if hue == 0.0 and sat == 1.0 and val == 1.0:
		return img
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a > 0.0:
				img.set_pixel(x, y, Color.from_hsv(
					fposmod(c.h + hue, 1.0),
					clampf(c.s * sat, 0.0, 1.0),
					clampf(c.v * val, 0.0, 1.0),
					c.a))
	return img
