## 程序化矢量卡通生物生成器（自建美术管线 M1 试点）
## 渲染：SDF 距离场逐像素着色——平滑抗锯齿 + 贴纸式深色描边 + 平涂渐变，
## 全确定性（无时间/随机种子依赖），换机重跑结果一致。
## 风格规范（自建卡通真源）：
##   描边 = 本体色 darkened(0.62) 外扩带 3px@128 画布；受光 = 顶部 lightened(0.10) 渐到底部 darkened(0.20)
##   眼睛 = 眼白后绘 + 瞳孔 + 高光点；die = X 眼；attack = 怒眉 + 张口
##   调色板 = PALETTE（按群系），物种/未来瓦片/UI 全部从中取色
## 画布：普通怪 128px（设计坐标 [-64,64]，地面 y=+52）；动画 idle4/walk6/attack6/die4 @10fps
## 产物契约（与 slice_spritesheets_v2 同构）：assets/creatures/frames/<name>/tex/<anim>_f<i>.png
## 用法：
##   godot --headless --path Code -s tools/generate_creatures.gd            # 生成 CARTOONS 全部
##   godot --headless --path Code -s tools/generate_creatures.gd -- slime_cartoon  # 指定物种（可多个）
##   godot --headless --path Code --import                                  # 导入 PNG
##   godot --headless --path Code -s tools/generate_creatures.gd -- pack    # 组装 SpriteFrames
##   godot --headless --path Code -s tools/generate_creatures.gd -- sheet   # 风格样张 /tmp/hotw_cartoon_sheet.png
extends SceneTree

const OUT_DIR := "res://assets/creatures/frames/"
const CANVAS := 128
const HALF := 64.0
const GROUND := 52.0  # 设计坐标脚底基线（y 向下为正）

## ---- 全局调色板（自建卡通风格真源；M2 物种铺开 / M3 环境层同源取色）----
## 每群系基础 8 色 + 扩展角色（stone 石/brown 棕/steel 钢铁）；个别物种特殊色走 cfg.pal_over
const PALETTE := {
	"plains": {
		"red": Color("ff5f4d"), "green": Color("7cbf4a"), "blue": Color("5aa8e8"),
		"neutral": Color("d9b380"), "soft": Color("ffe3d1"), "deep": Color("7a2a20"),
		"accent": Color("ffcf4d"), "brown": Color("9a6a48"), "stone": Color("908878"),
	},
	"snow": {
		"red": Color("ff8f7d"), "green": Color("a4d8e8"), "blue": Color("7fd0f7"),
		"neutral": Color("cfe4f0"), "soft": Color("eef9ff"), "deep": Color("1d4e6b"),
		"accent": Color("bfe8ff"), "stone": Color("9aa8b0"),
	},
	"swamp": {
		"red": Color("c96f52"), "green": Color("7cae3f"), "blue": Color("5f9e8f"),
		"neutral": Color("9a8f6a"), "soft": Color("dce8b8"), "deep": Color("2f4a14"),
		"accent": Color("c0d860"), "orange": Color("d88a3c"), "stone": Color("7a7468"),
		"brown": Color("8a6a4a"),
	},
	"forest": {
		"red": Color("e06a50"), "green": Color("5da648"), "blue": Color("6a9bd8"),
		"neutral": Color("8f7f5a"), "soft": Color("d8ecc4"), "deep": Color("33471e"),
		"accent": Color("e8d860"), "stone": Color("8a8a7a"), "brown": Color("7d5a3c"),
	},
	"hill": {
		"red": Color("d8705c"), "green": Color("9aa86a"), "blue": Color("8098c0"),
		"neutral": Color("b0a488"), "soft": Color("e4dcc8"), "deep": Color("4a4032"),
		"accent": Color("e0c060"), "stone": Color("8f8a80"), "brown": Color("8a6a4a"),
		"steel": Color("b8c4cc"),
	},
	"lava": {
		"red": Color("ff7040"), "green": Color("a07850"), "blue": Color("806090"),
		"neutral": Color("6a5850"), "soft": Color("ffb090"), "deep": Color("3a1a10"),
		"accent": Color("ffd040"), "stone": Color("6f6258"), "brown": Color("7a584a"),
	},
}

## 物种调色板：群系色 + cfg.pal_over 覆盖（个别物种特殊主色）
func _pal(cfg: Dictionary) -> Dictionary:
	var p: Dictionary = PALETTE[cfg["biome"]].duplicate()
	var over: Dictionary = cfg.get("pal_over", {})
	for k: String in over:
		p[k] = over[k]
	return p

## 动画帧数规格（统一治"帧数参差"）
const ANIMS := {"idle": 4, "walk": 6, "attack": 6, "die": 4}

## 物种表：archetype 骨架 → 骨架函数消费 PALETTE[biome] 的角色色
##   body_role: 主色角色名；crown: 头顶配件（drip 呆滴/crystal 冰晶/leaf 叶芽）
##   canvas: 输出画布（设计坐标恒为 [-64,64]，画布>128 即放大重采样，边缘更细腻）
const CARTOONS := {
	"slime_cartoon": {"archetype": "blob", "biome": "plains", "body_role": "red", "crown": "drip", "canvas": 156},
	"slime_ice_cartoon": {"archetype": "blob", "biome": "snow", "body_role": "blue", "crown": "crystal", "glint": 0.5, "canvas": 156},
	"slime_swamp_cartoon": {"archetype": "blob", "biome": "swamp", "body_role": "green", "crown": "leaf", "wide": 0.12, "canvas": 156},
	"goblin_cartoon": {"archetype": "biped", "biome": "plains", "canvas": 150},
	# --- M2 第一批：biped 家族 ---
	"imp_cartoon": {"archetype": "biped", "biome": "lava", "canvas": 150,
		"skin_role": "red", "horns": "curve", "tail": true, "cloth_role": "deep", "bulk": 0.92},
	"badger_cartoon": {"archetype": "biped", "biome": "hill", "canvas": 128,
		"skin_role": "neutral", "horns": "none", "ear_round": true, "mask": true,
		"claws": true, "tail_bush": true, "cloth_role": "deep", "bulk": 1.18},
	# --- M2 第二批：骷髅兵（biped+武器）+ 沼泽蟹（crawler）---
	"skeleton_cartoon": {"archetype": "biped", "biome": "hill", "canvas": 150,
		"skin_role": "soft", "horns": "none", "eye_style": "hollow", "weapon": "sword",
		"cloth_role": "neutral", "bulk": 0.95},
	"crab_cartoon": {"archetype": "crawler", "biome": "swamp", "canvas": 128, "body_role": "orange"},
	# --- M2 第三批：quadruped（野猪/绿蛙/企鹅/野兔）---
	"boar_cartoon": {"archetype": "quadruped", "biome": "plains", "canvas": 128,
		"body_role": "brown", "ears": "point", "tail": "curl", "tusks": true, "bulk": 1.05},
	"frog_cartoon": {"archetype": "quadruped", "biome": "swamp", "canvas": 128,
		"body_role": "green", "eyes_top": true, "squat": 1.15, "leg_len": 7.0,
		"bulk": 0.92, "mouth_big": 1.5},
	"penguin_cartoon": {"archetype": "quadruped", "biome": "snow", "canvas": 128,
		"body_role": "blue", "pal_over": {"blue": Color("46586e"), "accent": Color("f0a03c")},
		"beak": true, "belly_big": true, "leg_len": 5.0},
	"rabbit_cartoon": {"archetype": "quadruped", "biome": "plains", "canvas": 128,
		"body_role": "neutral", "pal_over": {"neutral": Color("c9ccd6")},
		"ears": "long", "tail": "puff", "leg_len": 8.0},
	# --- M2 第四批：floater（蝙蝠/幽灵/火魔鸦）---
	"bat_cartoon": {"archetype": "floater", "biome": "forest", "canvas": 90,
		"flyer": "bat", "pal_over": {"body": Color("6b5a78")}},
	"ghost_cartoon": {"archetype": "floater", "biome": "snow", "canvas": 150, "flyer": "ghost"},
	"phoenix_cartoon": {"archetype": "floater", "biome": "lava", "canvas": 150, "flyer": "phoenix"},
	# --- M2 第五批：plant（曼德拉草/萌芽怪/古木魔像 Boss）---
	"mandrake_cartoon": {"archetype": "plant", "biome": "plains", "canvas": 150,
		"plant_kind": "mushroom", "body_role": "red"},
	"sprout_cartoon": {"archetype": "plant", "biome": "forest", "canvas": 150, "plant_kind": "sprout"},
	"treant_cartoon": {"archetype": "plant", "biome": "forest", "canvas": 128, "plant_kind": "treant"},
	# --- M2 第六批：golem（石魔像/窟魔王/雪怪/石仔怪）---
	"golem_cartoon": {"archetype": "golem", "biome": "hill", "canvas": 64, "golem_kind": "guardian"},
	"golem_king_cartoon": {"archetype": "golem", "biome": "lava", "canvas": 128, "golem_kind": "king"},
	"yeti_cartoon": {"archetype": "golem", "biome": "snow", "canvas": 128, "golem_kind": "yeti"},
	"pebble_cartoon": {"archetype": "golem", "biome": "hill", "canvas": 128, "golem_kind": "pebble"},
	# --- M2-7：FX 三件（动画名 play 非循环，VfxPool 消费）+ 玩家英雄 ---
	"fx_slash": {"archetype": "fx", "biome": "plains", "fx_kind": "slash", "canvas": 32,
		"anims": {"play": 5}, "fps": 14.0,
		"pal_over": {"trail": Color("9fdcff"), "core": Color("eaf6ff")}},
	"fx_slash_gold": {"archetype": "fx", "biome": "plains", "fx_kind": "slash", "canvas": 32,
		"anims": {"play": 5}, "fps": 14.0,
		"pal_over": {"trail": Color("ffcf4d"), "core": Color("fff3c8")}},
	"fx_burst": {"archetype": "fx", "biome": "plains", "fx_kind": "burst", "canvas": 36,
		"anims": {"play": 6}, "fps": 12.0,
		"pal_over": {"trail": Color("ff8a3c"), "core": Color("ffd890")}},
	"hero_cartoon": {"archetype": "biped", "biome": "plains", "canvas": 200, "fps": 12.0,
		"anims": {"idle": 6, "walk": 6, "attack": 6, "die": 4},
		"skin_role": "peach", "pal_over": {"peach": Color("f2c9a0")},
		"horns": "none", "ears": "none", "hair": true, "headband": true,
		"weapon": "sword", "blade_len": 30.0, "cloth_role": "blue"},
}


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and args[0] == "pack":
		_pack_phase()
		quit(0)
		return
	if args.size() > 0 and args[0] == "sheet":
		_sheet_phase()
		quit(0)
		return
	if args.size() > 0 and args[0] == "icons":
		_icons_phase()
		quit(0)
		return
	var only: Array = [] if args.is_empty() else args
	_generate_phase(only)
	quit(0)


# ============================ 生成阶段 ============================

func _generate_phase(only: Array) -> void:
	var total := 0
	for name: String in CARTOONS:
		if not only.is_empty() and not only.has(name):
			continue
		var cfg: Dictionary = CARTOONS[name]
		var canvas: int = cfg.get("canvas", 128)
		var dir_path := ProjectSettings.globalize_path(OUT_DIR + name + "/tex")
		DirAccess.make_dir_recursive_absolute(dir_path)
		var count := 0
		var anims: Dictionary = cfg.get("anims", ANIMS)
		for anim_name: String in anims:
			var n: int = anims[anim_name]
			for i in n:
				var pose: Dictionary = _pose_for(cfg["archetype"], anim_name, i, n)
				var parts: Array = _build_parts(cfg, pose)
				var img := _render_frame(parts, canvas)
				img.save_png(OUT_DIR + name + "/tex/" + anim_name + "_f" + str(i) + ".png")
				count += 1
		total += count
		print("%-22s %d 帧（含 idle/walk/attack/die）" % [name, count])
	# 落盘自检：每物种每动画首帧非空
	var bad := 0
	for name: String in CARTOONS:
		if not only.is_empty() and not only.has(name):
			continue
		var anims: Dictionary = CARTOONS[name].get("anims", ANIMS)
		for anim_name: String in anims:
			var path := OUT_DIR + name + "/tex/" + anim_name + "_f0.png"
			var canvas: int = CARTOONS[name].get("canvas", 128)
			# 空图阈值随画布缩放（FX 32px 真内容约 150 像素，生物 128px 数千）
			var min_px: int = maxi(40, int(float(canvas * canvas) * 0.003))
			if not FileAccess.file_exists(path) or _opaque_pixels(Image.load_from_file(ProjectSettings.globalize_path(path))) < min_px:
				printerr("自检失败：%s %s 帧内容为空" % [name, anim_name])
				bad += 1
	print("生成完成：%d 帧，自检 %s。下一步：--import 后跑 pack" % [total, "通过" if bad == 0 else "失败 %d 项" % bad])


static func _opaque_pixels(img: Image) -> int:
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			# 阈值 0.15：FX 淡出帧 alpha≈0.15 仍算有效内容（0.5 会误报空图）
			if img.get_pixel(x, y).a > 0.15:
				n += 1
	return n


# ============================ 姿态（动画参数化） ============================
## pose 字典：squash(+压扁)/stretch(+前伸)/lift(抬升)/lean(前倾弧度)/hmul(高度乘子)
##   eyes: open/blink/x/angry；mouth: smile/flat/open/sad；alpha 全局透明；fwd 前移

func _pose_for(archetype: String, anim: String, i: int, n: int) -> Dictionary:
	var t := float(i) / float(n)
	var p := {"squash": 0.0, "stretch": 0.0, "lift": 0.0, "lean": 0.0, "hmul": 1.0,
		"eyes": "open", "mouth": "smile", "alpha": 1.0, "fwd": 0.0}
	if archetype == "blob":
		match anim:
			"idle":
				p["squash"] = 0.09 * sin(TAU * t)
				if i == n - 1:
					p["eyes"] = "blink"
			"walk":
				if t < 0.25:  # 蓄力压扁
					p["squash"] = lerpf(0.0, 0.32, t / 0.25)
				elif t < 0.55:  # 弹起拉伸
					var k := (t - 0.25) / 0.30
					p["squash"] = lerpf(0.32, -0.28, k)
					p["lift"] = 20.0 * sin(PI * k)
				elif t < 0.75:  # 落地大压扁
					var k := (t - 0.55) / 0.20
					p["squash"] = lerpf(-0.28, 0.42, k)
					p["mouth"] = "flat"
				else:  # 回弹
					var k := (t - 0.75) / 0.25
					p["squash"] = lerpf(0.42, 0.0, k)
			"attack":
				if t < 0.4:  # 后仰蓄力
					var k := t / 0.4
					p["lean"] = lerpf(0.0, -0.22, k)
					p["squash"] = 0.26 * k
					p["eyes"] = "angry"
					p["mouth"] = "flat"
				elif t < 0.65:  # 前扑
					var k := (t - 0.4) / 0.25
					p["lean"] = lerpf(-0.22, 0.26, k)
					p["stretch"] = 0.5 * k
					p["fwd"] = 10.0 * k
					p["eyes"] = "angry"
					p["mouth"] = "open"
				else:  # 收招
					var k := (t - 0.65) / 0.35
					p["lean"] = lerpf(0.26, 0.0, k)
					p["stretch"] = lerpf(0.5, 0.0, k)
					p["fwd"] = lerpf(10.0, 0.0, k)
					p["eyes"] = "angry"
			"die":
				var hs := [1.0, 0.72, 0.5, 0.34]
				p["hmul"] = hs[i]
				p["squash"] = 0.15 + 0.25 * i
				p["eyes"] = "open" if i == 0 else "x"
				p["mouth"] = "sad" if i < 2 else "flat"
				p["alpha"] = [1.0, 1.0, 0.9, 0.55][i]
	elif archetype == "biped":
		match anim:
			"idle":
				p["lift"] = 1.5 * sin(TAU * t)
				if i == n - 1:
					p["eyes"] = "blink"
				p["eyes"] = "angry"  # 妖鬼常驻怒眉
			"walk":
				p["leg_swing"] = sin(TAU * t)
				p["bob"] = 2.5 * absf(sin(TAU * t))
			"attack":
				if t < 0.4:
					var k := t / 0.4
					p["lean"] = lerpf(0.0, -0.12, k)
					p["punch"] = -0.5 * k
				elif t < 0.6:
					var k := (t - 0.4) / 0.2
					p["lean"] = lerpf(-0.12, 0.15, k)
					p["punch"] = lerpf(-0.5, 1.0, k)
					p["mouth"] = "open"
				else:
					var k := (t - 0.6) / 0.4
					p["lean"] = lerpf(0.15, 0.0, k)
					p["punch"] = lerpf(1.0, 0.0, k)
				p["eyes"] = "angry"
			"die":
				p["hmul"] = [1.0, 0.8, 0.55, 0.4][i]
				p["lean"] = 0.5 * i
				p["eyes"] = "open" if i == 0 else "x"
				p["mouth"] = "sad"
				p["alpha"] = [1.0, 1.0, 0.9, 0.55][i]
	elif archetype == "crawler":
		match anim:
			"idle":
				p["bob"] = 1.5 * sin(TAU * t)
				p["claw"] = 0.08 * sin(TAU * t)
				if i == n - 1:
					p["eyes"] = "blink"
			"walk":
				p["leg_swing"] = sin(TAU * t)
				p["bob"] = 1.2 * absf(sin(TAU * t))
				p["lean"] = 0.04 * sin(TAU * t)
			"attack":
				if t < 0.4:
					var k := t / 0.4
					p["claw"] = lerpf(0.0, -0.5, k)
					p["lean"] = lerpf(0.0, -0.08, k)
				elif t < 0.65:
					var k := (t - 0.4) / 0.25
					p["claw"] = lerpf(-0.5, 1.0, k)
					p["lean"] = lerpf(-0.08, 0.12, k)
					p["fwd"] = 6.0 * k
				else:
					var k := (t - 0.65) / 0.35
					p["claw"] = lerpf(1.0, 0.0, k)
					p["lean"] = lerpf(0.12, 0.0, k)
					p["fwd"] = lerpf(6.0, 0.0, k)
				p["eyes"] = "angry"
			"die":
				p["hmul"] = [1.0, 0.78, 0.6, 0.45][i]
				p["eyes"] = "open" if i == 0 else "x"
				p["leg_up"] = 0.35 * i
				p["alpha"] = [1.0, 1.0, 0.9, 0.55][i]
	elif archetype == "quadruped":
		match anim:
			"idle":
				p["bob"] = 1.0 * sin(TAU * t)
				if i == n - 1:
					p["eyes"] = "blink"
			"walk":
				p["leg_swing"] = sin(TAU * t)
				p["bob"] = 2.2 * absf(sin(TAU * t))
				p["wag"] = sin(TAU * t)
			"attack":
				if t < 0.4:
					var k := t / 0.4
					p["lean"] = lerpf(0.0, -0.22, k)
				elif t < 0.65:
					var k := (t - 0.4) / 0.25
					p["lean"] = lerpf(-0.22, 0.16, k)
					p["fwd"] = 7.0 * k
					p["mouth"] = "open"
				else:
					var k := (t - 0.65) / 0.35
					p["lean"] = lerpf(0.16, 0.0, k)
					p["fwd"] = lerpf(7.0, 0.0, k)
				p["eyes"] = "angry"
			"die":
				p["lean"] = [0.0, 0.3, 0.6, 0.95][i]
				p["hmul"] = [1.0, 0.9, 0.8, 0.7][i]
				p["eyes"] = "open" if i == 0 else "x"
				p["alpha"] = [1.0, 1.0, 0.9, 0.55][i]
	elif archetype == "floater":
		match anim:
			"idle":
				p["hover"] = 4.0 * sin(TAU * t)
				p["flap"] = sin(TAU * t)
				if i == n - 1:
					p["eyes"] = "blink"
			"walk":
				p["hover"] = 5.0 * sin(TAU * t)
				p["flap"] = sin(2.0 * TAU * t)
				p["sway_x"] = 3.0 * sin(TAU * t)
			"attack":
				if t < 0.4:
					var k := t / 0.4
					p["hover"] = lerpf(0.0, 10.0, k)
					p["flap"] = lerpf(0.0, -0.6, k)
				elif t < 0.65:
					var k := (t - 0.4) / 0.25
					p["hover"] = lerpf(10.0, -8.0, k)
					p["lean"] = 0.3 * k
					p["mouth"] = "open"
				else:
					var k := (t - 0.65) / 0.35
					p["hover"] = lerpf(-8.0, 0.0, k)
					p["lean"] = lerpf(0.3, 0.0, k)
				p["eyes"] = "angry"
			"die":
				p["hover"] = [3.0, 0.0, -6.0, -13.0][i]
				p["flap"] = 0.2 - 0.2 * i
				p["eyes"] = "open" if i == 0 else "x"
				p["alpha"] = [1.0, 1.0, 0.85, 0.5][i]
	elif archetype == "plant":
		match anim:
			"idle":
				p["lean"] = 0.06 * sin(TAU * t)
				p["squash"] = 0.04 * sin(TAU * t)
				if i == n - 1:
					p["eyes"] = "blink"
			"walk":
				if t < 0.25:
					p["squash"] = lerpf(0.0, 0.32, t / 0.25)
				elif t < 0.55:
					var k := (t - 0.25) / 0.30
					p["squash"] = lerpf(0.32, -0.28, k)
					p["lift"] = 18.0 * sin(PI * k)
				elif t < 0.75:
					var k := (t - 0.55) / 0.20
					p["squash"] = lerpf(-0.28, 0.42, k)
				else:
					var k := (t - 0.75) / 0.25
					p["squash"] = lerpf(0.42, 0.0, k)
			"attack":
				if t < 0.4:
					var k := t / 0.4
					p["lean"] = lerpf(0.0, -0.2, k)
					p["mouth"] = "flat"
				elif t < 0.65:
					var k := (t - 0.4) / 0.25
					p["lean"] = lerpf(-0.2, 0.22, k)
					p["fwd"] = 8.0 * k
					p["mouth"] = "open"
				else:
					var k := (t - 0.65) / 0.35
					p["lean"] = lerpf(0.22, 0.0, k)
					p["fwd"] = lerpf(8.0, 0.0, k)
				p["eyes"] = "angry"
			"die":
				p["lean"] = [0.0, -0.08, 0.28, 0.5][i]
				p["hmul"] = [1.0, 0.85, 0.7, 0.55][i]
				p["eyes"] = "open" if i == 0 else "x"
				p["alpha"] = [1.0, 1.0, 0.9, 0.55][i]
	elif archetype == "golem":
		match anim:
			"idle":
				p["bob"] = 0.8 * sin(TAU * t)
				p["core"] = 0.5 + 0.5 * sin(TAU * t)
				if i == n - 1:
					p["eyes"] = "blink"
			"walk":
				p["lean"] = 0.05 * sin(TAU * t)
				p["leg_swing"] = 0.7 * sin(TAU * t)
				p["bob"] = 2.0 * absf(sin(TAU * t))
			"attack":
				if t < 0.45:
					var k := t / 0.45
					p["arm"] = lerpf(0.0, -1.1, k)
					p["lean"] = lerpf(0.0, -0.1, k)
				elif t < 0.7:
					var k := (t - 0.45) / 0.25
					p["arm"] = lerpf(-1.1, 0.55, k)
					p["lean"] = lerpf(-0.1, 0.15, k)
					p["fwd"] = 5.0 * k
				else:
					var k := (t - 0.7) / 0.3
					p["arm"] = lerpf(0.55, 0.0, k)
					p["lean"] = lerpf(0.15, 0.0, k)
					p["fwd"] = lerpf(5.0, 0.0, k)
				p["eyes"] = "angry"
			"die":
				p["hmul"] = [1.0, 0.82, 0.62, 0.45][i]
				p["arm"] = [0.0, 0.2, 0.4, 0.6][i]
				p["eyes"] = "open" if i == 0 else "x"
				p["alpha"] = [1.0, 1.0, 0.9, 0.55][i]
	elif archetype == "fx":
		# play 全帧：t 驱动 扩张/淡出/扫掠进度
		var ft := float(i) / maxf(float(n - 1), 1.0)
		p["grow"] = ft
		p["alpha"] = 1.0 - 0.85 * ft
		p["sweep"] = lerpf(0.35, 1.0, ft)
	return p


# ============================ 物种部件组装 ============================

func _build_parts(cfg: Dictionary, pose: Dictionary) -> Array:
	match cfg["archetype"]:
		"blob":
			return _blob_parts(cfg, pose)
		"biped":
			return _goblin_parts(cfg, pose)
		"crawler":
			return _crawler_parts(cfg, pose)
		"quadruped":
			return _quadrup_parts(cfg, pose)
		"floater":
			return _floater_parts(cfg, pose)
		"plant":
			return _plant_parts(cfg, pose)
		"golem":
			return _golem_parts(cfg, pose)
		"fx":
			return _fx_parts(cfg, pose)
	return []


## 部件字典字段：shape(ellipse/blob/capsule) p(设计坐标) rx/ry|r/a3/a5|a/b rot sc
##   col edge(描边宽,0=无) flat(无渐变) alpha(叠加透明) ink(自定描边色)
## 返回按 z 升序（先画后层）
func _blob_parts(cfg: Dictionary, pose: Dictionary) -> Array:
	var pal: Dictionary = _pal(cfg)
	var body: Color = pal[cfg["body_role"]]
	var glint_a: float = cfg.get("glint", 0.32)
	var wide: float = cfg.get("wide", 0.0)
	var r := 30.0
	var sx: float = (1.0 + pose.get("squash", 0.0) * 0.55 - pose.get("stretch", 0.0) * 0.35) * (1.0 + wide)
	var sy: float = (1.0 - pose.get("squash", 0.0) * 0.50 + pose.get("stretch", 0.0) * 0.30) * pose.get("hmul", 1.0)
	var lean: float = pose.get("lean", 0.0)
	var center: Vector2 = Vector2(pose.get("fwd", 0.0), GROUND - r * sy - pose.get("lift", 0.0))
	var a: float = pose.get("alpha", 1.0)
	var parts: Array = []

	# 身体（傅里叶扰动圆 → 有机轮廓），底部坐地
	parts.append(_pt("blob", center, {"r": r, "a3": 0.05, "a5": 0.03, "sc": Vector2(sx, sy),
		"rot": lean, "col": body, "edge": 3.0}))
	# 肚皮浅色区
	parts.append(_pt("ellipse", center + Vector2(4, r * 0.45 * sy).rotated(lean), {
		"rx": r * 0.52 * sx, "ry": r * 0.34 * sy, "rot": lean, "col": pal["soft"], "alpha": 0.85 * a}))
	# 头顶配件（呆滴/冰晶/叶芽）——物种签名
	var crown_off := Vector2(2.0 * wide, -r * sy - 2.0).rotated(lean)
	match cfg.get("crown", "drip"):
		"drip":
			parts.append(_pt("blob", center + crown_off, {"r": 6.5, "a3": 0.1,
				"sc": Vector2(0.8, 1.25), "col": body, "edge": 2.5, "alpha": a}))
		"crystal":
			for k in 2:
				var off := crown_off + Vector2(-5.0 + 10.0 * k, 2.0 * k).rotated(lean)
				parts.append(_pt("capsule", center + off, {
					"a": Vector2(0, 3.0), "b": Vector2(0, -9.0 + 2.0 * k), "r": 3.2,
					"col": pal["accent"], "edge": 2.0, "alpha": a}))
		"leaf":
			parts.append(_pt("capsule", center + crown_off + Vector2(3, -1).rotated(lean), {
				"a": Vector2(0, 2.0), "b": Vector2(9.0, -6.0), "r": 4.2,
				"col": pal["accent"], "edge": 2.0, "alpha": a}))
	# 眼睛（脸朝右 3/4 视角）
	var eye_base := center + Vector2(6.0, -6.0).rotated(lean)
	_append_eyes(parts, eye_base, Vector2(9.5, 0.0), pose.get("eyes", "open"),
		6.0, 8.0, pal["deep"], a, lean)
	# 嘴
	var mouth_pos := center + Vector2(16.0, 7.0).rotated(lean)
	_append_mouth(parts, mouth_pos, pose.get("mouth", "smile"), pal["deep"],
		pal.get("mouth_in", Color("40100c")), a, 1.0)
	# 高光（最后绘，最上层）
	parts.append(_pt("ellipse", center + Vector2(-12.0, -14.0).rotated(lean), {
		"rx": 9.0 * sx, "ry": 5.5 * sy, "rot": -0.45 + lean, "col": Color.WHITE,
		"flat": true, "alpha": glint_a * a}))
	return parts


## biped 家族通用骨架（妖鬼/小魔鬼/獾王…）。
## cfg 参数：skin_role 皮肤调色板角色；bulk 体型乘子；horns pair/curve/none；
##   tail 细尾；tail_bush 蓬尾；mask 獾面罩（白纹+眼罩）；ear_round 圆耳；claws 前拳利爪；cloth_role 兜裆布色
func _goblin_parts(cfg: Dictionary, pose: Dictionary) -> Array:
	var pal: Dictionary = _pal(cfg)
	var skin: Color = pal[cfg.get("skin_role", "green")]
	var a: float = pose.get("alpha", 1.0)
	var h: float = pose.get("hmul", 1.0)
	var lean: float = pose.get("lean", 0.0)
	var bob: float = pose.get("bob", 0.0)
	var swing: float = pose.get("leg_swing", 0.0)
	var punch: float = pose.get("punch", 0.0)
	var bulk: float = cfg.get("bulk", 1.0)
	var parts: Array = []
	var gy := GROUND

	# 腿（行走摆动；bulk 加粗）
	for k in 2:
		var dx := (-6.0 + 12.0 * k) * bulk
		var hip := Vector2(dx, gy - 13.0 * h * bulk)
		var foot := Vector2(dx + 6.0 * swing * (1.0 if k == 1 else -1.0), gy - 1.0)
		parts.append(_pt("capsule", hip, {
			"a": Vector2(0, 0), "b": foot - hip, "r": 5.0 * bulk,
			"col": skin.darkened(0.18), "edge": 2.5, "alpha": a}))
	# 蓬尾（獾王，躯干后）
	if cfg.get("tail_bush", false):
		parts.append(_pt("ellipse", Vector2(-17.0 * bulk, gy - 18.0 * h), {
			"rx": 10.0 * bulk, "ry": 6.5 * bulk, "rot": 0.5,
			"col": skin.darkened(0.3), "edge": 2.5, "alpha": a}))
	# 后臂（躯干后）
	var shoulder := Vector2(-10.0 * bulk, gy - 30.0 * h)
	parts.append(_pt("capsule", shoulder, {
		"a": Vector2(0, 0), "b": Vector2(-9.0 * bulk, 12.0 * bulk), "r": 4.2 * bulk,
		"col": skin.darkened(0.25), "edge": 2.5, "alpha": a}))
	# 细尾（小魔鬼，两段弯尾）
	if cfg.get("tail", false):
		var t1 := Vector2(-12.0 * bulk, gy - 18.0 * h)
		parts.append(_pt("capsule", t1, {"a": Vector2(0, 0), "b": Vector2(-9.0, -4.0), "r": 2.2,
			"col": skin.darkened(0.1), "edge": 1.8, "alpha": a}))
		parts.append(_pt("capsule", t1 + Vector2(-9.0, -4.0), {"a": Vector2(0, 0), "b": Vector2(-6.0, -5.0), "r": 1.8,
			"col": skin.darkened(0.1), "edge": 1.8, "alpha": a}))
	# 躯干
	parts.append(_pt("ellipse", Vector2(0, gy - 26.0 * h) + Vector2(0, -bob), {
		"rx": 14.0 * bulk, "ry": 15.0 * h * bulk, "rot": lean, "col": skin, "edge": 3.0, "alpha": a}))
	# 兜裆布
	parts.append(_pt("ellipse", Vector2(0, gy - 15.0 * h) + Vector2(0, -bob), {
		"rx": 11.0 * bulk, "ry": 5.5, "col": pal[cfg.get("cloth_role", "red")].darkened(0.1),
		"edge": 2.0, "alpha": a}))
	# 头（大而圆）
	var head: Vector2 = Vector2(2.0, gy - 48.0 * h) + Vector2(0, -bob)
	parts.append(_pt("blob", head, {"r": 15.0 * bulk, "a3": 0.04, "rot": lean * 0.4,
		"col": skin, "edge": 3.0, "alpha": a}))
	# 耳朵（尖耳/圆耳/无——人类英雄无兽耳）
	var ear_style: String = "none" if cfg.get("ears", "") == "none" \
			else ("round" if cfg.get("ear_round", false) else "point")
	if ear_style != "none":
		for k in 2:
			var sgn := -1.0 if k == 0 else 1.0
			if ear_style == "round":
				parts.append(_pt("ellipse", head + Vector2(sgn * 14.0 * bulk, -1.0), {
					"rx": 4.5, "ry": 5.0, "col": skin, "edge": 2.2, "alpha": a}))
			else:
				parts.append(_pt("capsule", head + Vector2(sgn * 13.0 * bulk, -3.0), {
					"a": Vector2(0, 0), "b": Vector2(sgn * 11.0, -4.0), "r": 3.4,
					"col": skin, "edge": 2.5, "alpha": a}))
	# 头发（英雄：深棕三撮刺发）+ 头带（红 band + 飘带）
	if cfg.get("hair", false):
		for k in 3:
			parts.append(_pt("capsule", head + Vector2(-6.0 + 6.0 * k, -13.0 * bulk), {
				"a": Vector2(0, 0), "b": Vector2(-4.0 + 4.0 * k, -8.0), "r": 3.2,
				"col": Color("4a3226"), "edge": 2.0, "alpha": a}))
	if cfg.get("headband", false):
		parts.append(_pt("capsule", head + Vector2(0, -8.0), {
			"a": Vector2(-11.0, 0.5), "b": Vector2(11.0, -0.5), "r": 2.2,
			"col": Color("d8402a"), "edge": 1.2, "alpha": a}))
		parts.append(_pt("capsule", head + Vector2(-11.0, -7.0), {
			"a": Vector2(0, 0), "b": Vector2(-8.0, 6.0), "r": 1.6,
			"col": Color("d8402a"), "edge": 1.0, "alpha": a}))
	# 双角（直角/弯角/无）
	if cfg.get("horns", "pair") != "none":
		for k in 2:
			var sgn := -1.0 if k == 0 else 1.0
			var tip := Vector2(sgn * 3.0, -8.0) if cfg.get("horns") == "pair" else Vector2(sgn * 9.0, -5.0)
			parts.append(_pt("capsule", head + Vector2(sgn * 7.0 * bulk, -12.0 * bulk), {
				"a": Vector2(0, 0), "b": tip, "r": 2.8, "col": pal["soft"], "edge": 2.0, "alpha": a}))
	# 獾面罩：白色纵纹 + 双眼黑罩（眼睛前绘）
	if cfg.get("mask", false):
		parts.append(_pt("capsule", head, {"a": Vector2(0, -14.0 * bulk), "b": Vector2(0, 12.0 * bulk),
			"r": 5.0 * bulk, "col": pal["soft"], "alpha": a}))
		for k in 2:
			var sgn := -1.0 if k == 0 else 1.0
			parts.append(_pt("ellipse", head + Vector2(3.0 + sgn * 8.0, -2.0), {
				"rx": 6.0, "ry": 5.0, "col": pal["deep"], "alpha": a}))
	# 眼 + 嘴（eye_style=hollow：黑洞眼窝 + 灼热白点，骷髅/幽灵用）
	_append_eyes(parts, head + Vector2(3.0, -2.0), Vector2(8.0, 0.0),
		pose.get("eyes", "open"), 4.6, 6.2, Color("1c2410"), a, 0.0, cfg.get("eye_style", "normal"))
	_append_mouth(parts, head + Vector2(8.0, 7.0), pose.get("mouth", "flat"),
		Color("1c2410"), Color("5a1610"), a, 0.8 * bulk)
	# 前臂 + 拳（攻击前冲；利爪挂拳上）
	var arm_a := Vector2(9.0 * bulk, gy - 32.0 * h) + Vector2(0, -bob)
	var arm_b := arm_a + Vector2(10.0 + 14.0 * punch, 2.0 - 4.0 * punch) * bulk
	parts.append(_pt("capsule", arm_a, {"a": Vector2(0, 0), "b": arm_b - arm_a, "r": 4.4 * bulk,
		"col": skin, "edge": 2.5, "alpha": a}))
	parts.append(_pt("ellipse", arm_b, {"rx": 5.5 * bulk, "ry": 5.0 * bulk,
		"col": pal["accent"], "edge": 2.0, "alpha": a}))
	if cfg.get("claws", false):
		for k in 3:
			parts.append(_pt("capsule", arm_b + Vector2(4.0, -3.0 + 3.0 * k), {
				"a": Vector2(0, 0), "b": Vector2(6.5, -1.0 + 1.0 * k), "r": 1.2,
				"col": pal["soft"], "edge": 0.8, "alpha": a}))
	# 武器：长剑（骷髅兵）——角度随出拳相位：后仰蓄力上举 → 前劈下压
	if cfg.get("weapon", "") == "sword":
		var blade_ang := -1.0 + 1.3 * clampf(punch, -0.5, 1.0)
		var blade_dir := Vector2(cos(blade_ang), sin(blade_ang))
		var blade_len: float = cfg.get("blade_len", 27.0)
		var tip := arm_b + blade_dir * blade_len
		parts.append(_pt("capsule", arm_b + blade_dir * 3.0, {
			"a": Vector2(0, 0), "b": tip - arm_b, "r": 2.6,
			"col": pal.get("steel", Color("b8c4cc")), "edge": 1.8, "alpha": a}))
		var perp := Vector2(-blade_dir.y, blade_dir.x)
		parts.append(_pt("capsule", arm_b + blade_dir * 4.0, {
			"a": -perp * 4.5, "b": perp * 4.5, "r": 1.8, "col": pal["accent"], "edge": 1.0, "alpha": a}))
	return parts


## crawler 骨架（沼泽蟹）：宽扁体 + 眼柄 + 双螯 + 两侧三腿
func _crawler_parts(cfg: Dictionary, pose: Dictionary) -> Array:
	var pal: Dictionary = _pal(cfg)
	var body: Color = pal[cfg.get("body_role", "orange")]
	var a: float = pose.get("alpha", 1.0)
	var h: float = pose.get("hmul", 1.0)
	var lean: float = pose.get("lean", 0.0)
	var bob: float = pose.get("bob", 0.0)
	var swing: float = pose.get("leg_swing", 0.0)
	var claw: float = pose.get("claw", 0.0)
	var leg_up: float = pose.get("leg_up", 0.0)
	var parts: Array = []
	var bc := Vector2(pose.get("fwd", 0.0), GROUND - 15.0 * h) + Vector2(0, -bob)
	# 腿（每侧 3 条交替相位；die 时上翻）
	for s in 2:
		var sgn := -1.0 if s == 0 else 1.0
		for k in 3:
			var ph := 1.0 if (k % 2 == s) else -1.0
			var hip := bc + Vector2(-14.0 + 13.0 * k, 8.0)
			var foot := hip + Vector2(sgn * 9.0 + 5.0 * ph * swing, 6.0 - leg_up * 11.0)
			parts.append(_pt("capsule", hip, {"a": Vector2(0, 0), "b": foot - hip, "r": 2.6,
				"col": body.darkened(0.28), "edge": 1.8, "alpha": a}))
	# 体 + 壳瘤
	parts.append(_pt("ellipse", bc, {"rx": 27.0, "ry": 14.0 * h, "rot": lean,
		"col": body, "edge": 3.0, "alpha": a}))
	parts.append(_pt("blob", bc + Vector2(-8.0, -10.0 * h), {"r": 4.5, "col": body.darkened(0.12),
		"edge": 2.0, "alpha": a}))
	parts.append(_pt("blob", bc + Vector2(7.0, -12.0 * h), {"r": 5.0, "col": body.darkened(0.12),
		"edge": 2.0, "alpha": a}))
	# 眼柄
	var stalk := bc + Vector2(9.0, -10.0 * h)
	for s in 2:
		var off := Vector2(4.0 * s, 0.0)
		parts.append(_pt("capsule", stalk + off, {"a": Vector2(0, 0), "b": Vector2(2.0, -10.0), "r": 1.8,
			"col": body.darkened(0.2), "edge": 1.5, "alpha": a}))
	_append_eyes(parts, stalk + Vector2(4.0, -13.0), Vector2(6.0, 0.0),
		pose.get("eyes", "open"), 4.0, 5.0, pal["deep"], a, 0.0)
	# 双螯（attack 抬起→夹合前伸）
	for s in 2:
		var lift := -0.4 * claw
		var arm_a := bc + Vector2(20.0, 2.0 + (-3.0 if s == 0 else 5.0))
		var arm_b := arm_a + Vector2(8.0 + 6.0 * claw, -6.0 - 8.0 * claw).rotated(lift)
		parts.append(_pt("capsule", arm_a, {"a": Vector2(0, 0), "b": arm_b - arm_a, "r": 3.5,
			"col": body.darkened(0.15), "edge": 2.0, "alpha": a}))
		var open := 0.55 - 0.5 * clampf(claw, 0.0, 1.0)
		parts.append(_pt("capsule", arm_b, {"a": Vector2(0, 0),
			"b": Vector2(9.0, -7.0 * open - 2.0).rotated(lift), "r": 3.2, "col": body, "edge": 2.0, "alpha": a}))
		parts.append(_pt("capsule", arm_b, {"a": Vector2(0, 0),
			"b": Vector2(10.0, 5.0 * open + 2.0).rotated(lift), "r": 3.2, "col": body, "edge": 2.0, "alpha": a}))
	return parts


## quadruped 骨架（野猪/绿蛙/企鹅/野兔）：水平体 + 前头 + 四腿交替
func _quadrup_parts(cfg: Dictionary, pose: Dictionary) -> Array:
	var pal: Dictionary = _pal(cfg)
	var body: Color = pal[cfg.get("body_role", "brown")]
	var a: float = pose.get("alpha", 1.0)
	var h: float = pose.get("hmul", 1.0)
	var lean: float = pose.get("lean", 0.0)
	var bob: float = pose.get("bob", 0.0)
	var swing: float = pose.get("leg_swing", 0.0)
	var parts: Array = []
	var bulk: float = cfg.get("bulk", 1.0)
	var bc := Vector2(pose.get("fwd", 0.0), GROUND - 13.0 * h) + Vector2(0, -bob)
	# 尾（先绘于体后）
	match cfg.get("tail", "none"):
		"puff":
			parts.append(_pt("ellipse", bc + Vector2(-24.0, -2.0), {"rx": 5.0, "ry": 5.0,
				"col": pal["soft"], "edge": 2.0, "alpha": a}))
		"curl":
			parts.append(_pt("capsule", bc + Vector2(-22.0, -4.0), {"a": Vector2(0, 0),
				"b": Vector2(-7.0, -8.0), "r": 2.5, "col": body.darkened(0.1), "edge": 1.8, "alpha": a}))
	# 四腿（远侧两条先绘深色）
	var leg_len: float = cfg.get("leg_len", 9.0)
	for i in 4:
		var xn: float = [-14.0, -5.0, 10.0, 17.0][i]
		var far: bool = i % 2 == 0
		var ph: float = 1.0 if i % 2 == 0 else -1.0
		var hip := Vector2(bc.x + xn, bc.y + 8.0)
		var foot := hip + Vector2(4.0 * ph * swing, leg_len)
		var leg_col: Color = pal["accent"] if (cfg.get("beak", false) and not far) else body.darkened(0.3 if far else 0.15)
		parts.append(_pt("capsule", hip, {"a": Vector2(0, 0), "b": foot - hip, "r": 3.0,
			"col": leg_col, "edge": 1.8, "alpha": a}))
	# 体 + 腹
	var squat: float = cfg.get("squat", 1.0)
	parts.append(_pt("ellipse", bc, {"rx": 23.0 * bulk, "ry": 13.0 * h * squat * bulk, "rot": lean,
		"col": body, "edge": 3.0, "alpha": a}))
	var belly_rx := 16.0 if cfg.get("belly_big", false) else 14.0
	parts.append(_pt("ellipse", bc + Vector2(3.0, 5.0 * h), {"rx": belly_rx, "ry": 6.5,
		"col": pal["soft"], "alpha": 0.9 * a}))
	# 头（前方）+ 耳
	var head := bc + Vector2(23.0, -7.0 * h).rotated(lean * 0.3)
	parts.append(_pt("blob", head, {"r": 11.0 * bulk, "a3": 0.04, "rot": lean,
		"col": body, "edge": 3.0, "alpha": a}))
	match cfg.get("ears", "none"):
		"point":
			for k in 2:
				var sgn := -1.0 if k == 0 else 1.0
				parts.append(_pt("capsule", head + Vector2(sgn * 6.0, -8.0), {
					"a": Vector2(0, 0), "b": Vector2(sgn * 2.0, -7.0), "r": 2.5,
					"col": body, "edge": 1.8, "alpha": a}))
		"long":
			for k in 2:
				var sgn := -1.0 if k == 0 else 1.0
				parts.append(_pt("capsule", head + Vector2(sgn * 3.0 - 2.0, -9.0), {
					"a": Vector2(0, 0), "b": Vector2(sgn * 4.0 - 2.0, -17.0), "r": 3.2,
					"col": body, "edge": 2.2, "alpha": a}))
	# 吻部 / 喙 / 獠牙
	if cfg.get("beak", false):
		parts.append(_pt("capsule", head + Vector2(9.0, 1.0), {"a": Vector2(0, 0),
			"b": Vector2(8.0, -1.0), "r": 2.8, "col": pal["accent"], "edge": 1.8, "alpha": a}))
	else:
		parts.append(_pt("ellipse", head + Vector2(8.0, 3.0), {"rx": 5.5, "ry": 4.0,
			"col": pal["soft"], "edge": 1.5, "alpha": a}))
		if cfg.get("tusks", false):
			for k in 2:
				parts.append(_pt("capsule", head + Vector2(9.0 + 3.0 * k, 5.0), {
					"a": Vector2(0, 0), "b": Vector2(4.0 + 3.0 * k, 6.0), "r": 1.5,
					"col": pal["soft"], "edge": 1.0, "alpha": a}))
	# 眼（青蛙顶眼突出 / 其余侧脸双眼）
	if cfg.get("eyes_top", false):
		for k in 2:
			var sgn := -1.0 if k == 0 else 1.0
			var pos := head + Vector2(-2.0 + 5.0 * k, -11.0)
			parts.append(_pt("ellipse", pos, {"rx": 4.2, "ry": 5.0, "col": Color.WHITE,
				"edge": 1.5, "ink": pal["deep"].darkened(0.1), "flat": true, "alpha": a}))
			parts.append(_pt("ellipse", pos + Vector2(1.2, 0.6), {"rx": 1.8, "ry": 2.2,
				"col": pal["deep"], "flat": true, "alpha": a}))
	else:
		_append_eyes(parts, head + Vector2(4.0, -3.0), Vector2(2.5, 0.0),
			pose.get("eyes", "open"), 3.6, 4.6, pal["deep"], a, 0.0)
	_append_mouth(parts, head + Vector2(7.0, 7.0), pose.get("mouth", "smile"),
		pal["deep"], Color("5a1610"), a, 0.7 * cfg.get("mouth_big", 1.0))
	return parts


## floater 骨架（蝙蝠/幽灵/火魔鸦）：无腿悬浮，翼/摆尾随 flap 摆动
func _floater_parts(cfg: Dictionary, pose: Dictionary) -> Array:
	var pal: Dictionary = _pal(cfg)
	var a: float = pose.get("alpha", 1.0)
	var lean: float = pose.get("lean", 0.0)
	var hover: float = pose.get("hover", 0.0)
	var flap: float = pose.get("flap", 0.0)
	var parts: Array = []
	var base := Vector2(pose.get("sway_x", 0.0), -10.0 - hover)
	match cfg.get("flyer", "bat"):
		"bat":
			var body: Color = pal["body"]
			# 翼（每侧三羽扇形，flap 摆动）
			for s in 2:
				var sgn := -1.0 if s == 0 else 1.0
				for k in 3:
					var ang := sgn * (0.30 + 0.28 * k) + sgn * flap * 0.38
					var len := 15.0 + 3.0 * k
					var sh := base + Vector2(sgn * 6.0, -1.0)
					parts.append(_pt("capsule", sh, {"a": Vector2(0, 0),
						"b": Vector2(cos(ang), sin(ang) * 0.6) * len, "r": 3.4 - 0.5 * k,
						"col": body.darkened(0.08 + 0.05 * k), "edge": 1.8, "alpha": a}))
			# 体 + 耳 + 脸
			parts.append(_pt("blob", base, {"r": 10.0, "a3": 0.05, "rot": lean,
				"col": body, "edge": 2.6, "alpha": a}))
			for k in 2:
				var sgn := -1.0 if k == 0 else 1.0
				parts.append(_pt("capsule", base + Vector2(sgn * 4.0, -8.0), {
					"a": Vector2(0, 0), "b": Vector2(sgn * 3.0, -8.0), "r": 2.2,
					"col": body, "edge": 1.6, "alpha": a}))
			_append_eyes(parts, base + Vector2(2.0, -2.0), Vector2(4.0, 0.0),
				pose.get("eyes", "open"), 3.4, 4.2, Color("ffe9a8"), a, 0.0)
			_append_mouth(parts, base + Vector2(5.0, 5.0), pose.get("mouth", "flat"),
				Color("ffe9a8"), Color("5a1610"), a, 0.6)
			# 小尖牙
			if pose.get("mouth", "flat") == "open":
				for k in 2:
					parts.append(_pt("capsule", base + Vector2(3.0 + 3.0 * k, 7.0), {
						"a": Vector2(0, 0), "b": Vector2(0, 3.0), "r": 1.0,
						"col": Color.WHITE, "flat": true, "alpha": a}))
		"ghost":
			var soft: Color = pal["soft"]
			var ga := 0.88 * a
			# 下摆波瓣（随 flap 相位摆动）
			for k in 4:
				var x0 := -13.5 + 9.0 * k
				var lob_len := 9.0 + (4.0 if k % 2 == 0 else 0.0)
				var sway := 2.5 * flap * (1.0 if k % 2 == 0 else -1.0)
				parts.append(_pt("capsule", base + Vector2(x0, 12.0), {"a": Vector2(0, 0),
					"b": Vector2(sway, lob_len), "r": 4.5, "col": soft, "edge": 0.0, "alpha": ga}))
			parts.append(_pt("blob", base, {"r": 19.0, "a3": 0.04, "rot": lean,
				"col": soft, "edge": 2.6, "alpha": ga}))
			_append_eyes(parts, base + Vector2(3.0, -3.0), Vector2(7.0, 0.0),
				pose.get("eyes", "open"), 4.4, 5.6, pal["deep"], a, 0.0, "hollow")
			_append_mouth(parts, base + Vector2(7.0, 7.0), pose.get("mouth", "flat"),
				pal["deep"], pal["deep"], a, 0.8)
		"phoenix":
			var body: Color = pal["red"]
			# 翼（红→金渐层三羽）
			for s in 2:
				var sgn := -1.0 if s == 0 else 1.0
				for k in 3:
					var ang := sgn * (0.30 + 0.26 * k) + sgn * flap * 0.4
					var len := 16.0 + 4.0 * k
					var sh := base + Vector2(sgn * 7.0, -2.0)
					parts.append(_pt("capsule", sh, {"a": Vector2(0, 0),
						"b": Vector2(cos(ang), sin(ang) * 0.6) * len, "r": 3.6 - 0.5 * k,
						"col": body.lerp(pal["accent"], 0.35 * k), "edge": 1.8, "alpha": a}))
			# 尾焰三缕
			for k in 3:
				parts.append(_pt("capsule", base + Vector2(-10.0, 2.0 + 4.0 * k), {
					"a": Vector2(0, 0), "b": Vector2(-15.0, -4.0 + 6.0 * k + 3.0 * flap), "r": 2.8,
					"col": pal["accent"] if k == 1 else body, "edge": 1.6, "alpha": a}))
			# 体 + 冠焰 + 喙
			parts.append(_pt("blob", base, {"r": 12.0, "a3": 0.04, "rot": lean,
				"col": body, "edge": 2.6, "alpha": a}))
			for k in 2:
				parts.append(_pt("capsule", base + Vector2(-1.0 + 4.0 * k, -11.0), {
					"a": Vector2(0, 0), "b": Vector2(-5.0 + 6.0 * k, -9.0), "r": 2.8,
					"col": pal["accent"], "edge": 1.6, "alpha": a}))
			parts.append(_pt("capsule", base + Vector2(11.0, 0.0), {"a": Vector2(0, 0),
				"b": Vector2(8.0, 1.0), "r": 2.4, "col": pal["accent"].darkened(0.25),
				"edge": 1.5, "alpha": a}))
			_append_eyes(parts, base + Vector2(3.0, -3.0), Vector2(3.5, 0.0),
				pose.get("eyes", "open"), 3.0, 3.8, Color("3a1a10"), a, 0.0)
	return parts


## plant 骨架（曼德拉草/萌芽怪/古木魔像）
func _plant_parts(cfg: Dictionary, pose: Dictionary) -> Array:
	var pal: Dictionary = _pal(cfg)
	var a: float = pose.get("alpha", 1.0)
	var h: float = pose.get("hmul", 1.0)
	var lean: float = pose.get("lean", 0.0)
	var parts: Array = []
	var gy := GROUND
	var fx: float = pose.get("fwd", 0.0)
	match cfg.get("plant_kind", "mushroom"):
		"mushroom":
			var cap: Color = pal[cfg.get("body_role", "red")]
			var sy: float = 1.0 - pose.get("squash", 0.0) * 0.5
			# 菌柄（奶白）
			parts.append(_pt("capsule", Vector2(fx, gy - 3.0 * h * sy), {"a": Vector2(0, 0),
				"b": Vector2(0, -27.0 * h * sy), "r": 8.0, "col": pal["soft"], "edge": 3.0, "alpha": a}))
			# 根脚
			for k in 2:
				var sgn := -1.0 if k == 0 else 1.0
				parts.append(_pt("capsule", Vector2(fx + sgn * 4.0, gy - 2.0), {
					"a": Vector2(0, 0), "b": Vector2(sgn * 5.0, 2.0), "r": 2.2,
					"col": pal["soft"].darkened(0.15), "edge": 1.5, "alpha": a}))
			# 菌盖 + 斑点
			var cap_c := Vector2(fx, gy - 36.0 * h * sy).rotated(lean * 0.4) + Vector2(0, 0)
			parts.append(_pt("ellipse", cap_c, {"rx": 20.0, "ry": 12.0, "rot": lean,
				"col": cap, "edge": 3.0, "alpha": a}))
			for k in 3:
				parts.append(_pt("ellipse", cap_c + Vector2(-10.0 + 9.0 * k, -4.0 + 2.0 * (k % 2)), {
					"rx": 2.4, "ry": 2.0, "col": pal["soft"], "flat": true, "alpha": a}))
			# 脸在菌柄上
			_append_eyes(parts, Vector2(fx + 2.0, gy - 18.0 * h * sy), Vector2(4.5, 0.0),
				pose.get("eyes", "open"), 3.4, 4.4, pal["deep"], a, 0.0)
			_append_mouth(parts, Vector2(fx + 5.0, gy - 11.0 * h * sy), pose.get("mouth", "flat"),
				pal["deep"], pal["deep"], a, 0.7)
		"sprout":
			var body: Color = pal["green"]
			var sy: float = 1.0 - pose.get("squash", 0.0) * 0.5
			var bc := Vector2(fx, gy - 11.0 * h * sy - pose.get("lift", 0.0))
			# 双子叶
			for k in 2:
				var sgn := -1.0 if k == 0 else 1.0
				parts.append(_pt("capsule", bc + Vector2(0, -9.0 * sy), {
					"a": Vector2(0, 0), "b": Vector2(sgn * 9.0, -8.0), "r": 3.6,
					"col": body.lightened(0.25), "edge": 2.0, "alpha": a}))
			parts.append(_pt("blob", bc, {"r": 11.0, "a3": 0.05,
				"col": body, "edge": 2.8, "alpha": a}))
			_append_eyes(parts, bc + Vector2(2.0, -2.0), Vector2(4.0, 0.0),
				pose.get("eyes", "open"), 3.4, 4.4, pal["deep"], a, 0.0)
			_append_mouth(parts, bc + Vector2(5.0, 4.0), pose.get("mouth", "smile"),
				pal["deep"], pal["deep"], a, 0.7)
		"treant":
			var bark: Color = pal["brown"]
			var leaf: Color = pal["green"]
			var arm: float = pose.get("arm", 0.0)
			# 后臂（枝）
			var sh_back := Vector2(fx - 10.0, gy - 30.0 * h)
			parts.append(_pt("capsule", sh_back, {"a": Vector2(0, 0),
				"b": Vector2(-8.0, -12.0), "r": 3.5, "col": bark.darkened(0.15), "edge": 2.2, "alpha": a}))
			parts.append(_pt("blob", sh_back + Vector2(-8.0, -12.0), {"r": 5.0,
				"col": leaf, "edge": 2.0, "alpha": a}))
			# 树冠（先绘，躯干盖根）
			for k in 3:
				parts.append(_pt("blob", Vector2(fx - 8.0 + 8.0 * k, gy - 50.0 * h), {
					"r": 8.0 - float(k == 1) * -2.0, "a3": 0.06, "col": leaf, "edge": 2.4, "alpha": a}))
			# 主干 + 根
			parts.append(_pt("capsule", Vector2(fx, gy - 2.0), {"a": Vector2(0, 0),
				"b": Vector2(0, -44.0 * h), "r": 12.0, "col": bark, "edge": 3.5, "alpha": a}))
			for k in 2:
				var sgn := -1.0 if k == 0 else 1.0
				parts.append(_pt("capsule", Vector2(fx + sgn * 8.0, gy - 2.0), {
					"a": Vector2(0, 0), "b": Vector2(sgn * 8.0, 2.0), "r": 4.0,
					"col": bark.darkened(0.1), "edge": 2.5, "alpha": a}))
			# 树皮裂纹
			for k in 2:
				parts.append(_pt("capsule", Vector2(fx - 3.0 + 6.0 * k, gy - 26.0 * h), {
					"a": Vector2(0, 0), "b": Vector2(1.0, -10.0), "r": 1.0,
					"col": pal["deep"], "flat": true, "alpha": 0.5 * a}))
			# 脸（灼目）+ 前臂枝拳
			_append_eyes(parts, Vector2(fx + 4.0, gy - 36.0 * h), Vector2(5.0, 0.0),
				pose.get("eyes", "open"), 3.8, 4.6, pal["deep"], a, 0.0, "hollow")
			_append_mouth(parts, Vector2(fx + 7.0, gy - 28.0 * h), pose.get("mouth", "flat"),
				pal["deep"], pal["deep"], a, 1.1)
			var sh := Vector2(fx + 10.0, gy - 30.0 * h)
			var dir := Vector2(1.0, -0.4).rotated(arm)
			parts.append(_pt("capsule", sh, {"a": Vector2(0, 0), "b": dir * 15.0, "r": 4.0,
				"col": bark, "edge": 2.2, "alpha": a}))
			parts.append(_pt("blob", sh + dir * 16.0, {"r": 6.0, "a3": 0.05,
				"col": leaf, "edge": 2.0, "alpha": a}))
	return parts


## golem 骨架（石魔像/窟魔王/雪怪/石仔怪）：块状体重臂 + 蓄力抡砸
func _golem_parts(cfg: Dictionary, pose: Dictionary) -> Array:
	var pal: Dictionary = _pal(cfg)
	var a: float = pose.get("alpha", 1.0)
	var h: float = pose.get("hmul", 1.0)
	var lean: float = pose.get("lean", 0.0)
	var bob: float = pose.get("bob", 0.0)
	var arm: float = pose.get("arm", 0.0)
	var parts: Array = []
	var gy := GROUND
	var fx: float = pose.get("fwd", 0.0)
	match cfg.get("golem_kind", "guardian"):
		"guardian":
			var stone: Color = pal["stone"]
			# 短腿
			for k in 2:
				var sgn := -1.0 if k == 0 else 1.0
				parts.append(_pt("capsule", Vector2(fx + sgn * 6.0, gy - 6.0 * h), {
					"a": Vector2(0, 0), "b": Vector2(sgn * 1.0, 5.0), "r": 4.0,
					"col": stone.darkened(0.2), "edge": 2.0, "alpha": a}))
			var bc := Vector2(fx, gy - 17.0 * h) + Vector2(0, -bob)
			# 肩岩 + 双臂（前臂抡砸）
			for s in 2:
				var sgn := -1.0 if s == 0 else 1.0
				var sh := bc + Vector2(sgn * 12.0, -7.0 * h)
				parts.append(_pt("blob", sh, {"r": 5.0, "a3": 0.07,
					"col": stone.darkened(0.08), "edge": 2.2, "alpha": a}))
				var dir := Vector2(sgn * 0.7, 0.7).rotated(arm if s == 1 else 0.0)
				parts.append(_pt("capsule", sh, {"a": Vector2(0, 0), "b": dir * 15.0, "r": 4.2,
					"col": stone.darkened(0.15), "edge": 2.2, "alpha": a}))
				parts.append(_pt("blob", sh + dir * 17.0, {"r": 5.0, "a3": 0.06,
					"col": stone, "edge": 2.2, "alpha": a}))
			# 体 + 核心脉冲
			parts.append(_pt("blob", bc, {"r": 15.0, "a3": 0.06, "rot": lean,
				"col": stone, "edge": 3.0, "alpha": a}))
			var core_a: float = 0.55 + 0.45 * pose.get("core", 0.5)
			parts.append(_pt("ellipse", bc + Vector2(2.0, -1.0), {"rx": 3.4, "ry": 3.4,
				"col": pal["accent"], "flat": true, "alpha": core_a * a}))
			_append_eyes(parts, bc + Vector2(4.0, -5.0 * h), Vector2(4.5, 0.0),
				pose.get("eyes", "open"), 3.0, 3.6, pal["deep"], a, 0.0)
			_append_mouth(parts, bc + Vector2(6.0, 3.0), pose.get("mouth", "flat"),
				pal["deep"], pal["deep"], a, 0.6)
		"king":
			var stone: Color = pal["stone"]
			# 粗腿
			for k in 2:
				var sgn := -1.0 if k == 0 else 1.0
				parts.append(_pt("capsule", Vector2(fx + sgn * 9.0, gy - 8.0 * h), {
					"a": Vector2(0, 0), "b": Vector2(sgn * 2.0, 7.0), "r": 5.0,
					"col": stone.darkened(0.2), "edge": 2.2, "alpha": a}))
			var bc := Vector2(fx - 2.0, gy - 20.0 * h) + Vector2(0, -bob)
			# 后臂
			var sh_b := bc + Vector2(-16.0, 0.0)
			parts.append(_pt("capsule", sh_b, {"a": Vector2(0, 0), "b": Vector2(-6.0, 12.0), "r": 5.0,
				"col": stone.darkened(0.2), "edge": 2.4, "alpha": a}))
			# 甲壳 + 壳刺 + 腹板
			parts.append(_pt("ellipse", bc, {"rx": 22.0, "ry": 17.0 * h, "rot": lean,
				"col": stone, "edge": 3.5, "alpha": a}))
			for k in 3:
				parts.append(_pt("capsule", bc + Vector2(-12.0 + 11.0 * k, -15.0 * h), {
					"a": Vector2(0, 0), "b": Vector2(0, -7.0), "r": 2.6,
					"col": stone.darkened(0.15), "edge": 1.8, "alpha": a}))
			parts.append(_pt("ellipse", bc + Vector2(6.0, 8.0 * h), {"rx": 13.0, "ry": 7.0,
				"col": pal["soft"], "alpha": 0.75 * a}))
			# 头（前伸，怒目灼光）
			var head := bc + Vector2(21.0, -2.0 * h)
			parts.append(_pt("blob", head, {"r": 9.0, "a3": 0.05,
				"col": stone.darkened(0.08), "edge": 2.8, "alpha": a}))
			_append_eyes(parts, head + Vector2(2.0, -2.0), Vector2(4.0, 0.0),
				pose.get("eyes", "open"), 3.0, 3.6, pal["deep"], a, 0.0, "hollow")
			_append_mouth(parts, head + Vector2(5.0, 4.0), pose.get("mouth", "flat"),
				pal["deep"], pal["accent"], a, 0.8)
			# 前巨臂（抡砸）
			var sh := bc + Vector2(14.0, 2.0)
			var dir := Vector2(0.8, 0.6).rotated(arm)
			parts.append(_pt("capsule", sh, {"a": Vector2(0, 0), "b": dir * 16.0, "r": 5.5,
				"col": stone.darkened(0.12), "edge": 2.4, "alpha": a}))
			parts.append(_pt("blob", sh + dir * 18.0, {"r": 6.5, "a3": 0.05,
				"col": stone, "edge": 2.4, "alpha": a}))
		"yeti":
			var fur: Color = pal["soft"]
			var bc := Vector2(fx, gy - 20.0 * h) + Vector2(0, -bob)
			# 长臂（毛）
			for s in 2:
				var sgn := -1.0 if s == 0 else 1.0
				var sh := bc + Vector2(sgn * 17.0, -6.0)
				var dir := Vector2(sgn * 0.5, 0.9).rotated(arm if s == 1 else 0.0)
				parts.append(_pt("capsule", sh, {"a": Vector2(0, 0), "b": dir * 16.0, "r": 4.5,
					"col": fur.darkened(0.08), "edge": 2.4, "alpha": a}))
			# 蓬毛大体（高扰动=毛茸）
			parts.append(_pt("blob", bc, {"r": 21.0, "a3": 0.09, "a5": 0.04, "rot": lean,
				"col": fur, "edge": 3.0, "alpha": a}))
			# 脸斑 + 眼嘴
			parts.append(_pt("ellipse", bc + Vector2(6.0, -4.0), {"rx": 11.0, "ry": 9.0,
				"col": pal["deep"], "alpha": 0.9 * a}))
			_append_eyes(parts, bc + Vector2(6.0, -6.0), Vector2(5.0, 0.0),
				pose.get("eyes", "open"), 3.6, 4.4, Color.WHITE, a, 0.0)
			_append_mouth(parts, bc + Vector2(9.0, 1.0), pose.get("mouth", "flat"),
				Color.WHITE, Color.WHITE, a, 0.7)
			# 冰锥冠
			for k in 2:
				parts.append(_pt("capsule", bc + Vector2(0.0, -20.0) + Vector2(-4.0 + 8.0 * k, 0.0), {
					"a": Vector2(0, 0), "b": Vector2(0, -7.0), "r": 2.4,
					"col": pal["accent"], "edge": 1.6, "alpha": a}))
		"pebble":
			var stone: Color = pal["stone"]
			var bc := Vector2(fx, gy - 10.0 * h) + Vector2(0, -bob)
			# 脚点
			for k in 2:
				var sgn := -1.0 if k == 0 else 1.0
				parts.append(_pt("ellipse", bc + Vector2(sgn * 5.0, 9.0 * h), {"rx": 2.6, "ry": 2.2,
					"col": stone.darkened(0.2), "edge": 1.5, "alpha": a}))
			parts.append(_pt("blob", bc, {"r": 12.0, "a3": 0.07, "rot": lean,
				"col": stone, "edge": 2.8, "alpha": a}))
			# 苔帽 + 头顶晶簇
			parts.append(_pt("ellipse", bc + Vector2(-2.0, -6.0 * h), {"rx": 9.0, "ry": 5.0,
				"col": PALETTE["swamp"]["green"], "alpha": 0.9 * a}))
			parts.append(_pt("capsule", bc + Vector2(3.0, -10.0 * h), {"a": Vector2(0, 0),
				"b": Vector2(3.0, -8.0), "r": 2.4, "col": pal["accent"], "edge": 1.6, "alpha": a}))
			_append_eyes(parts, bc + Vector2(3.0, 0.0), Vector2(5.0, 0.0),
				pose.get("eyes", "open"), 3.8, 4.8, pal["deep"], a, 0.0)
			_append_mouth(parts, bc + Vector2(6.0, 6.0), pose.get("mouth", "smile"),
				pal["deep"], pal["deep"], a, 0.7)
	return parts


## FX 构建器（fx_slash/fx_slash_gold/fx_burst）：无描边发光体，动画名 play 非循环
func _fx_parts(cfg: Dictionary, pose: Dictionary) -> Array:
	var pal: Dictionary = _pal(cfg)
	var a: float = pose.get("alpha", 1.0)
	var grow: float = pose.get("grow", 0.0)
	var sweep: float = pose.get("sweep", 1.0)
	var trail: Color = pal["trail"]
	var core: Color = pal["core"]
	var parts: Array = []
	match cfg.get("fx_kind", "slash"):
		"slash":
			# 弧光：沿圆弧的渐细胶囊段（中段最粗），随 sweep 张角、grow 扩张淡出
			# 设计单位按满画布取（半径≈50/64），线宽 4~9——小画布(32px)密度 0.25 下仍 ≥1 输出像素
			var radius := 50.0 + 12.0 * grow
			var center_ang := -0.9  # 前上方（画面 y 向下）
			var span := 1.9 * sweep
			var segs := 6
			var pts: Array = []
			for k in segs + 1:
				var ang := center_ang - span * 0.5 + span * float(k) / float(segs)
				pts.append(Vector2(cos(ang), sin(ang)) * radius)
			for k in segs:
				var mid_t := absf(float(k) / float(segs) - 0.5) * 2.0  # 0 中段 1 两端
				var r := lerpf(9.0, 4.0, mid_t)
				parts.append(_pt("capsule", Vector2(0, 0), {
					"a": pts[k], "b": pts[k + 1], "r": r,
					"col": core.lerp(trail, mid_t * 0.6), "flat": true, "alpha": a}))
			# 内芯亮弧（更小半径、更细）
			for k in segs:
				var mid_t := absf(float(k) / float(segs) - 0.5) * 2.0
				if mid_t < 0.6:
					var r2 := radius - 11.0
					var ang0 := center_ang - span * 0.5 + span * (float(k) + 0.5) / float(segs)
					var ang1 := center_ang - span * 0.5 + span * (float(k) + 1.5) / float(segs)
					parts.append(_pt("capsule", Vector2(0, 0), {
						"a": Vector2(cos(ang0), sin(ang0)) * r2, "b": Vector2(cos(ang1), sin(ang1)) * r2,
						"r": 4.5, "col": Color.WHITE, "flat": true, "alpha": a * 0.8}))
		"burst":
			# 爆裂：白炽核 + 8 向尖刺 + 外扩虚线环（尺寸按 36px 画布密度 0.28 放大设计单位）
			var cr := 13.0 + 15.0 * grow
			for k in 8:
				var ang := TAU * float(k) / 8.0 + 0.3
				var spike_len := 15.0 * (1.0 - grow * 0.5)
				var r0 := cr + 3.0
				var r1 := r0 + spike_len
				parts.append(_pt("capsule", Vector2(0, 0), {
					"a": Vector2(cos(ang), sin(ang)) * r0, "b": Vector2(cos(ang), sin(ang)) * r1,
					"r": 5.5 - 2.5 * grow, "col": trail, "flat": true, "alpha": a}))
			for k in 8:
				var ang := TAU * float(k) / 8.0
				var ring_r := 24.0 + 22.0 * grow
				parts.append(_pt("ellipse", Vector2(cos(ang), sin(ang)) * ring_r, {
					"rx": 4.5, "ry": 4.5, "col": trail.lerp(core, 0.5), "flat": true, "alpha": a * 0.8}))
			parts.append(_pt("ellipse", Vector2(0, 0), {"rx": cr, "ry": cr,
				"col": core, "flat": true, "alpha": a}))
	return parts


# ============================ 图标阶段（HUD/菜单 17 枚）============================

const ICON_DIR := "res://assets/icons_cartoon/"
const ICON_NAMES := ["sword", "axe", "hammer", "shuriken", "fireball", "life-pot",
	"scroll-thunder", "scroll-plant", "scroll-ice", "scroll-empty", "coin-2",
	"gold-coin", "heart", "medipack", "water-pot", "fortune-cookie", "arrow",
	"dialogue-bubble", "little-treasure-chest"]

func _icons_phase() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ICON_DIR))
	for icon_name: String in ICON_NAMES:
		var parts := _icon_parts(icon_name)
		var img := _render_frame(parts, 64)
		img.save_png(ICON_DIR + icon_name + ".png")
	print("图标 %d 枚 → %s（替换 hud.gd/main_menu.gd 引用后 --import）" % [ICON_NAMES.size(), ICON_DIR])


func _icon_parts(icon_name: String) -> Array:
	var steel := Color("b8c4cc")
	var wood := Color("8a6a4a")
	var gold := Color("ffcf4d")
	var red := Color("ff5f4d")
	var green := Color("7cbf4a")
	var blue := Color("5aa8e8")
	var beige := Color("e8dcc0")
	var parts: Array = []
	match icon_name:
		"sword":
			parts.append(_pt("capsule", Vector2(0, 0), {"a": Vector2(-14, 14), "b": Vector2(12, -12),
				"r": 4.0, "col": steel, "edge": 2.0}))
			parts.append(_pt("capsule", Vector2(0, 0), {"a": Vector2(-2, 10), "b": Vector2(-10, 2),
				"r": 2.2, "col": gold, "edge": 1.2}))
			parts.append(_pt("capsule", Vector2(0, 0), {"a": Vector2(-14, 14), "b": Vector2(-20, 20),
				"r": 3.0, "col": wood, "edge": 1.8}))
			parts.append(_pt("ellipse", Vector2(-21, 21), {"rx": 3.0, "ry": 3.0, "col": gold, "edge": 1.2}))
		"axe":
			parts.append(_pt("capsule", Vector2(0, 0), {"a": Vector2(-12, 12), "b": Vector2(12, -12),
				"r": 2.6, "col": wood, "edge": 1.8}))
			parts.append(_pt("ellipse", Vector2(10, -10), {"rx": 9.0, "ry": 6.0, "rot": 0.785,
				"col": steel, "edge": 2.0}))
			parts.append(_pt("ellipse", Vector2(13, -13), {"rx": 3.0, "ry": 5.0, "rot": 0.785,
				"col": Color.WHITE, "flat": true, "alpha": 0.6}))
		"hammer":
			parts.append(_pt("capsule", Vector2(0, 0), {"a": Vector2(-2, 14), "b": Vector2(3, -8),
				"r": 2.8, "col": wood, "edge": 1.8}))
			parts.append(_pt("ellipse", Vector2(2, -11), {"rx": 11.0, "ry": 7.0, "rot": -0.15,
				"col": steel, "edge": 2.0}))
		"shuriken":
			for k in 4:
				var ang := TAU * float(k) / 4.0 + PI / 4.0
				parts.append(_pt("capsule", Vector2(0, 0), {
					"a": Vector2(cos(ang), sin(ang)) * 3.0, "b": Vector2(cos(ang), sin(ang)) * 17.0,
					"r": 3.2, "col": steel, "edge": 1.6}))
			parts.append(_pt("ellipse", Vector2(0, 0), {"rx": 3.5, "ry": 3.5, "col": red, "edge": 1.2}))
		"fireball":
			for k in 3:
				parts.append(_pt("capsule", Vector2(0, 0), {
					"a": Vector2(-8, -4.0 + 4.0 * k), "b": Vector2(-19, -8.0 + 6.0 * k),
					"r": 2.5, "col": Color("ff8a3c"), "edge": 1.2}))
			parts.append(_pt("ellipse", Vector2(0, 0), {"rx": 10.0, "ry": 10.0,
				"col": Color("ff8a3c"), "edge": 2.0}))
			parts.append(_pt("ellipse", Vector2(-3, -4), {"rx": 2.6, "ry": 2.6, "col": Color.WHITE, "flat": true}))
		"life-pot", "water-pot":
			var potion: Color = red if icon_name == "life-pot" else blue
			parts.append(_pt("capsule", Vector2(0, 0), {"a": Vector2(0, -8), "b": Vector2(0, -13),
				"r": 3.2, "col": Color("cfe0e8"), "edge": 2.0}))
			parts.append(_pt("ellipse", Vector2(0, 5), {"rx": 8.5, "ry": 9.5,
				"col": potion, "edge": 2.0}))
			parts.append(_pt("ellipse", Vector2(-3, 1), {"rx": 2.5, "ry": 4.0,
				"col": Color.WHITE, "flat": true, "alpha": 0.5}))
			parts.append(_pt("ellipse", Vector2(0, -14), {"rx": 3.2, "ry": 2.0, "col": wood, "edge": 1.2}))
		"scroll-thunder", "scroll-plant", "scroll-ice", "scroll-empty":
			parts.append(_pt("capsule", Vector2(0, 0), {"a": Vector2(-9, 0), "b": Vector2(9, 0),
				"r": 7.5, "col": beige, "edge": 2.0}))
			parts.append(_pt("ellipse", Vector2(-10, 0), {"rx": 3.0, "ry": 8.0,
				"col": beige.darkened(0.12), "edge": 1.5}))
			parts.append(_pt("ellipse", Vector2(10, 0), {"rx": 3.0, "ry": 8.0,
				"col": beige.darkened(0.12), "edge": 1.5}))
			match icon_name:
				"scroll-thunder":
					parts.append(_pt("ellipse", Vector2(0, 0), {"rx": 3.2, "ry": 3.2, "col": gold, "edge": 1.0}))
				"scroll-plant":
					parts.append(_pt("ellipse", Vector2(0, 0), {"rx": 3.2, "ry": 3.2, "col": green, "edge": 1.0}))
				"scroll-ice":
					parts.append(_pt("ellipse", Vector2(0, 0), {"rx": 3.2, "ry": 3.2, "col": blue, "edge": 1.0}))
				"scroll-empty":
					parts.append(_pt("capsule", Vector2(0, 0), {"a": Vector2(-5, -1), "b": Vector2(5, -1),
						"r": 1.0, "col": Color("a09070"), "flat": true, "alpha": 0.7}))
					parts.append(_pt("capsule", Vector2(0, 0), {"a": Vector2(-4, 2.5), "b": Vector2(4, 2.5),
						"r": 1.0, "col": Color("a09070"), "flat": true, "alpha": 0.7}))
		"coin-2":
			parts.append(_pt("ellipse", Vector2(-4, 3), {"rx": 7.0, "ry": 7.0,
				"col": Color("c8ccd4"), "edge": 2.0}))
			parts.append(_pt("ellipse", Vector2(5, -3), {"rx": 7.0, "ry": 7.0, "col": gold, "edge": 2.0}))
			parts.append(_pt("ellipse", Vector2(3, -5), {"rx": 1.6, "ry": 1.6, "col": Color.WHITE, "flat": true}))
		"gold-coin":
			parts.append(_pt("ellipse", Vector2(0, 0), {"rx": 9.5, "ry": 9.5, "col": gold, "edge": 2.0}))
			parts.append(_pt("ellipse", Vector2(0, 0), {"rx": 6.5, "ry": 6.5,
				"col": gold.lightened(0.25), "flat": true, "alpha": 0.8}))
			parts.append(_pt("ellipse", Vector2(-3, -3), {"rx": 1.8, "ry": 1.8, "col": Color.WHITE, "flat": true}))
		"heart":
			# 同色多件联合体——若带描边会出现内部接缝，故整体无描边
			parts.append(_pt("ellipse", Vector2(-4.5, -3), {"rx": 6.0, "ry": 6.0, "col": red}))
			parts.append(_pt("ellipse", Vector2(4.5, -3), {"rx": 6.0, "ry": 6.0, "col": red}))
			parts.append(_pt("capsule", Vector2(0, 0), {"a": Vector2(-9, -1), "b": Vector2(0, 9),
				"r": 7.0, "col": red}))
			parts.append(_pt("capsule", Vector2(0, 0), {"a": Vector2(9, -1), "b": Vector2(0, 9),
				"r": 7.0, "col": red}))
			parts.append(_pt("ellipse", Vector2(-4, -5), {"rx": 1.8, "ry": 1.8, "col": Color.WHITE, "flat": true}))
		"medipack":
			parts.append(_pt("ellipse", Vector2(0, 0), {"rx": 10.5, "ry": 9.5, "col": Color.WHITE, "edge": 2.0}))
			parts.append(_pt("capsule", Vector2(0, 0), {"a": Vector2(0, -4.5), "b": Vector2(0, 4.5),
				"r": 2.6, "col": red, "flat": true}))
			parts.append(_pt("capsule", Vector2(0, 0), {"a": Vector2(-4.5, 0), "b": Vector2(4.5, 0),
				"r": 2.6, "col": red, "flat": true}))
		"fortune-cookie":
			parts.append(_pt("blob", Vector2(0, 0), {"r": 9.0, "a3": 0.08, "col": beige, "edge": 2.0}))
			parts.append(_pt("capsule", Vector2(0, 0), {"a": Vector2(-5, 2), "b": Vector2(6, -3),
				"r": 1.4, "col": Color("b09070"), "flat": true}))
		"arrow":
			parts.append(_pt("capsule", Vector2(0, 0), {"a": Vector2(-12, 8), "b": Vector2(8, -4),
				"r": 2.6, "col": wood, "edge": 1.6}))
			parts.append(_pt("capsule", Vector2(0, 0), {"a": Vector2(8, -4), "b": Vector2(17, -9),
				"r": 2.8, "col": steel, "edge": 1.6}))
			parts.append(_pt("capsule", Vector2(0, 0), {"a": Vector2(8, -4), "b": Vector2(15, 0),
				"r": 2.8, "col": steel, "edge": 1.6}))
			parts.append(_pt("capsule", Vector2(0, 0), {"a": Vector2(-12, 8), "b": Vector2(-18, 13),
				"r": 2.2, "col": red, "edge": 1.2}))
			parts.append(_pt("capsule", Vector2(0, 0), {"a": Vector2(-11, 6), "b": Vector2(-16, 10),
				"r": 2.2, "col": red, "edge": 1.2}))
		"dialogue-bubble":
			parts.append(_pt("capsule", Vector2(0, 0), {"a": Vector2(-2, 13), "b": Vector2(-9, 19),
				"r": 3.0, "col": Color.WHITE, "edge": 1.8}))
			parts.append(_pt("ellipse", Vector2(0, 0), {"rx": 12.0, "ry": 9.0,
				"col": Color.WHITE, "edge": 1.8}))
			for k in 3:
				parts.append(_pt("ellipse", Vector2(-6.0 + 6.0 * k, 0), {"rx": 1.6, "ry": 1.6,
					"col": Color("6a7480"), "flat": true}))
		"little-treasure-chest":
			parts.append(_pt("ellipse", Vector2(0, 2), {"rx": 11.0, "ry": 8.0,
				"col": wood, "edge": 2.0}))
			parts.append(_pt("capsule", Vector2(0, 0), {"a": Vector2(-10, -2), "b": Vector2(10, -2),
				"r": 2.2, "col": gold, "edge": 1.4}))
			parts.append(_pt("capsule", Vector2(0, 0), {"a": Vector2(0, -6), "b": Vector2(0, 8),
				"r": 1.8, "col": gold, "edge": 1.2}))
			parts.append(_pt("ellipse", Vector2(0, -2), {"rx": 1.8, "ry": 2.4,
				"col": Color("4a3226"), "flat": true}))
	return parts


func _append_eyes(parts: Array, base: Vector2, gap: Vector2, mode: String,
		rx: float, ry: float, deep: Color, a: float, lean: float, style: String = "normal") -> void:
	# 两眼：mode 决定 睁/眨/X/怒；angry 追加怒眉；style=hollow 黑窝+白热点
	for k in 2:
		var off := gap * (-1.0 if k == 0 else 1.0)
		var pos := base + off
		if mode == "blink":
			parts.append(_pt("capsule", pos, {"a": Vector2(-rx, 0), "b": Vector2(rx, 0),
				"r": 1.6, "col": deep, "flat": true, "alpha": a}))
		elif mode == "x":
			for m in 2:
				parts.append(_pt("capsule", pos, {
					"a": Vector2(-4.5, -4.5 if m == 0 else 4.5), "b": Vector2(4.5, 4.5 if m == 0 else -4.5),
					"r": 1.7, "col": deep, "flat": true, "alpha": a}))
		elif style == "hollow":
			parts.append(_pt("ellipse", pos, {"rx": rx * 1.05, "ry": ry * 1.1,
				"col": deep, "flat": true, "alpha": a}))
			parts.append(_pt("ellipse", pos + Vector2(1.0, 0.5), {"rx": rx * 0.38, "ry": ry * 0.4,
				"col": Color.WHITE, "flat": true, "alpha": a}))
		else:
			parts.append(_pt("ellipse", pos, {"rx": rx, "ry": ry, "col": Color.WHITE,
				"flat": true, "edge": 1.6, "ink": deep.darkened(0.1), "alpha": a}))
			parts.append(_pt("ellipse", pos + Vector2(1.8, 0.8), {"rx": rx * 0.42, "ry": ry * 0.46,
				"col": deep, "flat": true, "alpha": a}))
			parts.append(_pt("ellipse", pos + Vector2(0.2, -1.4), {"rx": 1.2, "ry": 1.4,
				"col": Color.WHITE, "flat": true, "alpha": a}))
		if mode == "angry":
			var brow := pos + Vector2(0, -ry - 3.0)
			var tilt := 0.45 if k == 1 else -0.45  # 内低外高 → 凶相
			parts.append(_pt("capsule", brow, {
				"a": Vector2(-rx, 0).rotated(tilt), "b": Vector2(rx, 0).rotated(tilt),
				"r": 1.8, "col": deep, "flat": true, "alpha": a}))


func _append_mouth(parts: Array, pos: Vector2, mode: String, deep: Color,
		inner: Color, a: float, scale: float) -> void:
	match mode:
		"smile":
			parts.append(_pt("capsule", pos, {"a": Vector2(-4 * scale, 1), "b": Vector2(4 * scale, -1),
				"r": 1.4, "col": deep, "flat": true, "alpha": a}))
		"flat":
			parts.append(_pt("capsule", pos, {"a": Vector2(-3.5 * scale, 0), "b": Vector2(3.5 * scale, 0),
				"r": 1.2, "col": deep, "flat": true, "alpha": a}))
		"sad":
			parts.append(_pt("capsule", pos, {"a": Vector2(-4 * scale, -1), "b": Vector2(4 * scale, 1),
				"r": 1.4, "col": deep, "flat": true, "alpha": a}))
		"open":
			parts.append(_pt("ellipse", pos, {"rx": 4.5 * scale, "ry": 3.6 * scale,
				"col": inner, "edge": 1.6, "ink": deep, "alpha": a}))


func _pt(shape: String, p: Vector2, props: Dictionary) -> Dictionary:
	var d := {"shape": shape, "p": p, "rot": 0.0, "sc": Vector2.ONE, "col": Color.WHITE,
		"edge": 0.0, "flat": false, "alpha": 1.0}
	for k in props:
		d[k] = props[k]
	return d


# ============================ SDF 渲染核心 ============================

## size = 画布边长；设计坐标恒 [-64,64]，>128 时按 density=size/128 重采样（部件等比放大）
func _render_frame(parts: Array, size: int = CANVAS) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var half := float(size) * 0.5
	var density := float(size) / 128.0
	# 每部件包围盒（设计坐标 ± 半径 + 描边余量），像素循环内快速剔除
	var boxes: Array = []
	for d in parts:
		boxes.append(_part_bbox(d))
	for py in size:
		var dy := (float(py) + 0.5 - half) / density
		for px in size:
			var dx := (float(px) + 0.5 - half) / density
			var c := Color(0, 0, 0, 0)
			for i in parts.size():
				var b: Rect2 = boxes[i]
				if dx < b.position.x or dx > b.end.x or dy < b.position.y or dy > b.end.y:
					continue
				c = _stamp_part(c, parts[i], Vector2(dx, dy))
			if c.a > 0.003:
				img.set_pixel(px, py, c)
	return img


func _stamp_part(dst: Color, d: Dictionary, world: Vector2) -> Color:
	var q: Vector2 = (world - d["p"]).rotated(-d["rot"]) / d["sc"]
	var sd := _part_sd(d, q) * minf(d["sc"].x, d["sc"].y)
	var base: Color = d["col"]
	var a: float = d["alpha"]
	# 描边带（本体色深度变体，贴纸感）
	if d["edge"] > 0.0:
		var e_cov := clampf(0.5 - (sd + float(d["edge"])), 0.0, 1.0) * a
		if e_cov > 0.0:
			var ink: Color = d.get("ink", base.darkened(0.62))
			dst = _over(dst, Color(ink.r, ink.g, ink.b, e_cov))
	var f_cov := clampf(0.5 - sd, 0.0, 1.0) * a
	if f_cov > 0.0:
		var fill := base
		if not d["flat"]:
			var h := _part_height(d)
			if h > 6.0:
				var t := smoothstep(0.0, 1.0, clampf((q.y + h * 0.5) / h, 0.0, 1.0))
				fill = base.darkened(0.20).lerp(base.lightened(0.10), 1.0 - t)
		dst = _over(dst, Color(fill.r, fill.g, fill.b, f_cov))
	return dst


static func _over(dst: Color, src: Color) -> Color:
	if dst.a <= 0.003:
		return src
	var sa := src.a
	var da := dst.a + sa - dst.a * sa
	if da <= 0.0:
		return Color(0, 0, 0, 0)
	var out := (dst * dst.a * (1.0 - sa) + src * sa) / da
	out.a = da
	return out


func _part_sd(d: Dictionary, p: Vector2) -> float:
	match d["shape"]:
		"ellipse":
			return _sd_ellipse(p, d["rx"], d["ry"])
		"blob":
			return _sd_blob(p, d["r"], d.get("a3", 0.0), d.get("a5", 0.0))
		"capsule":
			return _sd_capsule(p, d["a"], d["b"], d["r"])
	return 1e9


static func _sd_ellipse(q: Vector2, rx: float, ry: float) -> float:
	# IQ 近似（够卡通用；rx/ry 下限防除零）
	rx = maxf(rx, 0.5); ry = maxf(ry, 0.5)
	var k0 := Vector2(q.x / rx, q.y / ry).length()
	var k1 := Vector2(q.x / (rx * rx), q.y / (ry * ry)).length()
	return k0 * (k0 - 1.0) / maxf(k1, 1e-5)


static func _sd_blob(q: Vector2, r: float, a3: float, a5: float) -> float:
	var ang := atan2(q.y, q.x)
	var target := r * (1.0 + a3 * sin(3.0 * ang) + a5 * sin(5.0 * ang + 1.7))
	return q.length() - target


static func _sd_capsule(q: Vector2, a: Vector2, b: Vector2, r: float) -> float:
	var pa := q - a
	var ba := b - a
	var h := clampf(pa.dot(ba) / maxf(ba.dot(ba), 1e-9), 0.0, 1.0)
	return (pa - ba * h).length() - r


func _part_height(d: Dictionary) -> float:
	match d["shape"]:
		"ellipse":
			return d["ry"] * 2.0 * d["sc"].y
		"blob":
			return d["r"] * 2.0 * d["sc"].y
		"capsule":
			return absf(d["b"].y - d["a"].y) + d["r"] * 2.0
	return 0.0


func _part_bbox(d: Dictionary) -> Rect2:
	var rad := 0.0
	match d["shape"]:
		"ellipse":
			rad = maxf(d["rx"], d["ry"])
		"blob":
			rad = d["r"]
		"capsule":
			rad = maxf(absf(d["b"].x - d["a"].x), absf(d["b"].y - d["a"].y)) * 0.5 + d["r"]
			rad = maxf(Vector2(d["a"]).length(), Vector2(d["b"]).length())
	rad *= maxf(d["sc"].x, d["sc"].y)
	rad += float(d["edge"]) + 1.5
	return Rect2(d["p"] - Vector2(rad, rad), Vector2(rad * 2.0, rad * 2.0))


# ============================ pack 阶段（照搬 slice_v2 逻辑）============================

func _pack_phase() -> void:
	var ok := 0
	for name: String in CARTOONS:
		var tex_dir := OUT_DIR + name + "/tex/"
		var frames := SpriteFrames.new()
		frames.remove_animation("default")
		var base_fps: float = CARTOONS[name].get("fps", 10.0)
		var anims: Dictionary = CARTOONS[name].get("anims", ANIMS)
		var anim_count := 0
		for anim_name: String in anims:
			var i := 0
			var any := false
			while FileAccess.file_exists(tex_dir + anim_name + "_f" + str(i) + ".png"):
				var tex: Texture2D = load(tex_dir + anim_name + "_f" + str(i) + ".png")
				if tex == null:
					break
				if not any:
					frames.add_animation(anim_name)
					frames.set_animation_speed(anim_name, base_fps)
					# die 与一次性特效（play）非循环
					frames.set_animation_loop(anim_name, anim_name != "die" and anim_name != "play")
					any = true
				frames.add_frame(anim_name, tex)
				i += 1
			if any:
				anim_count += 1
		var path := OUT_DIR + name + "/" + name + "_frames.tres"
		var err := ResourceSaver.save(frames, path)
		if err == OK:
			ok += 1
		print("%-22s %d 组动画 %s" % [name, anim_count, "OK" if err == OK else "失败:%d" % err])
	print("组装完成：%d/%d" % [ok, CARTOONS.size()])


# ============================ 样张阶段 ============================

## contact sheet：每物种 idle 全帧 + walk/attack/die 代表帧，末行附现有 v2 同类首帧对比
func _sheet_phase() -> void:
	var names := CARTOONS.keys()
	names.sort()
	var cell := CANVAS
	var pad := 6
	## 每格代表帧（含形变中后段）：idle 全帧 + walk 弹跳三态 + attack 蓄/扑 + die 渐瘪
	var picks: Array = [
		["idle", 0], ["idle", 1], ["idle", 2], ["idle", 3],
		["walk", 1], ["walk", 3], ["walk", 5],
		["attack", 2], ["attack", 4],
		["die", 1], ["die", 2], ["die", 3],
	]
	var rows := names.size() + 1  # +1 行 v2 对比
	var w := picks.size() * (cell + pad) + pad
	var h := rows * (cell + pad) + pad
	var sheet := Image.create(w, h, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("2b2f3a"))
	for r in names.size():
		var name: String = names[r]
		for c in picks.size():
			var anim_name: String = picks[c][0]
			var fidx: int = picks[c][1]
			var path: String = OUT_DIR + name + "/tex/%s_f%d.png" % [anim_name, fidx]
			if FileAccess.file_exists(path):
				var img := Image.load_from_file(ProjectSettings.globalize_path(path))
				if img.get_width() != cell:
					img.resize(cell, cell, Image.INTERPOLATE_NEAREST)
				sheet.blit_rect(img, Rect2i(0, 0, cell, cell),
					Vector2i(pad + c * (cell + pad), pad + r * (cell + pad)))
	# v2 对比行：现有 LuizMelo slime / goblin 的 idle_f0（缩到 128 同格）
	var v2_refs: Array[String] = ["slime_ice_v2", "goblin_v2", "boar_v2"]
	for c in v2_refs.size():
		var path: String = OUT_DIR + v2_refs[c] + "/tex/idle_f0.png"
		if FileAccess.file_exists(path):
			var img := Image.load_from_file(ProjectSettings.globalize_path(path))
			img.resize(cell, cell, Image.INTERPOLATE_NEAREST)
			sheet.blit_rect(img, Rect2i(0, 0, cell, cell),
				Vector2i(pad + c * (cell + pad), pad + (rows - 1) * (cell + pad)))
	var out := "/tmp/hotw_cartoon_sheet.png"
	sheet.save_png(out)
	print("样张已保存 " + out + "（%d×%d）" % [w, h])
