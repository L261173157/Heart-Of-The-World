## 精灵表切帧工具（无头运行：godot --headless --path Code -s tools/slice_spritesheets.gd）。
## 从 assets/creatures/sheets/ 的 Ninja Adventure 16px 精灵表生成 SpriteFrames 资源：
##   按需色相/饱和/明度烘焙（红史莱姆红→绿、猪→野猪棕）
##   + 镜像（猪表默认朝左）→ 帧纹理直接内嵌进 .tres（FLAG_BUNDLE_RESOURCES，
##   不产生散碎帧文件、不依赖编辑器导入步骤）。
## 美术 v5（NA 回归）：22 物种与 NA 22 张怪物表一一对应，无烘焙变体凑数；
##   三忍（蓝/黑/白）同布局切帧。
## 输出：assets/creatures/frames/<name>/<name>_frames.tres，场景 Visual（AnimatedSprite2D）引用之。
## 布局约定（与作者 Godot 演示 sprite_character.gd 一致）：列 = 朝向（0下/1上/2左/3右），行 = 帧
## （怪物 0-3 行走；角色另含 4攻击/5跳跃/6死亡）。素材取"朝右"列，运行时用 flip_h 翻转。
extends SceneTree

const SHEETS_DIR := "res://assets/creatures/sheets/"
const OUT_DIR := "res://assets/creatures/frames/"
const CELL := 16
## 行走帧率：Ninja Adventure 作者演示的 IMAGE_SPEED
const FPS := 6.0

## bake: hue 平移（色相环 0-1，可为负）/sat、val 乘子（灰与描边 s≈0 不受色相影响，自然保留）
## 可选键：sheet 以 res:// 开头则用绝对路径（fx 等非 sheets 目录素材）；
##   strip=true 时 anim 的帧号是单行条带的 x 格号（fx 特效表布局）；
##   fps / loop 覆盖全局默认（特效用 15fps 非循环）
const CREATURES := {
	"ninja": {
		"sheet": "na_ninja.png", "col": 3, "flop": false,
		"anim": {"idle": [0], "walk": [0, 1, 2, 3], "attack": [4], "die": [6]},
	},
	## 三忍皮肤（美术 v5）：黑忍/白忍与蓝忍同布局（4列×7行，col3=朝右）
	"ninja_dark": {
		"sheet": "na_ninja_dark.png", "col": 3, "flop": false,
		"anim": {"idle": [0], "walk": [0, 1, 2, 3], "attack": [4], "die": [6]},
	},
	"ninja_white": {
		"sheet": "na_ninja_white.png", "col": 3, "flop": false,
		"anim": {"idle": [0], "walk": [0, 1, 2, 3], "attack": [4], "die": [6]},
	},
	# --- 地标 NPC（美术 v5 M-B）：NA characters 表，与英雄同布局（64×112，col3=朝右） ---
	"npc_hunter": {
		"sheet": "res://assets/na/characters/8.png", "col": 3, "flop": false,
		"anim": {"idle": [0], "walk": [0, 1, 2, 3]},
	},
	"npc_scholar": {
		"sheet": "res://assets/na/characters/4.png", "col": 3, "flop": false,
		"anim": {"idle": [0], "walk": [0, 1, 2, 3]},
	},
	"npc_keeper": {
		"sheet": "res://assets/na/characters/7.png", "col": 3, "flop": false,
		"anim": {"idle": [0], "walk": [0, 1, 2, 3]},
	},
	## 营地行商（出生营地商店 NPC）
	"npc_merchant": {
		"sheet": "res://assets/na/characters/6.png", "col": 3, "flop": false,
		"anim": {"idle": [0], "walk": [0, 1, 2, 3]},
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
}


func _init() -> void:
	for creature: String in CREATURES:
		var cfg: Dictionary = CREATURES[creature]
		var img := _load_baked(cfg)
		var frames := SpriteFrames.new()
		frames.remove_animation("default")
		var anim_fps: float = cfg.get("fps", FPS)
		var anim_loop: bool = cfg.get("loop", true)
		var strip: bool = cfg.get("strip", false)
		for anim_name: String in cfg["anim"]:
			frames.add_animation(anim_name)
			frames.set_animation_speed(anim_name, anim_fps)
			frames.set_animation_loop(anim_name, anim_loop)
			for row: int in cfg["anim"][anim_name]:
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
