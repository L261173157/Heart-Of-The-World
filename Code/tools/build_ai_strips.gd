## AI 素材接入工具（美术 v4 主力管线第一步，2026-09-10 P0 验证通过后固化）。
## 输入契约：~/hotw-assets/ai/<物种>/ 下按文件名约定放 AI 关键帧（建议 1024² 浅底 PNG）：
##   base.png   必备——定妆图（idle/walk 的母帧与 attack/die 的首帧）
##   attack.png 可选——扑咬极帧（单一 take，勿混多 roll，防脸跳变）
##   hurt.png   可选——受击下瘪帧（die 第二帧）
##   melt.png   可选——融化帧（X 眼，die 倒数第二帧）
##   puddle.png 可选——彻底成滩帧（die 末帧）
##   walk_a/b、attack2/attack3 可选——真迈步双帧 / 连击二三段（英雄用）
## 处理：边缘泛洪抽底（按局部色距传播，跟随浅色渐变背景，非纯白亦可）→
##   256 格归一化（姿势帧统一身高锚定 + 底边贴 GROUND_Y；朝左物种镜像归一）→
##   「单一关键帧 + 程序化挤压/拉伸/抬升补间」拼动画（attack 关键帧前置，适配短攻击窗）。
## 输出：~/hotw-assets/pilot/current/<物种>/{idle,walk,attack,die}.png 横向条带。
## 之后接：slice_spritesheets_v2.gd slice → --import → -- pack（条目按物种加 CREATURES 配置）。
## 用法：
##   godot --headless --path Code -s tools/build_ai_strips.gd            # 处理 ai/ 下全部物种
##   godot --headless --path Code -s tools/build_ai_strips.gd -- slime   # 只处理单物种
## 自检：每帧不透明像素 ≥ MIN_OPAQUE，不足即 FAIL 退出非 0（-s 脚本运行时错误不中断，靠此闸门）。
##   另有抽底闸门：背景删除占比 < MIN_BG_ERASE 即 FAIL——2026-09-11 事故教训
##   （英雄源图淡蓝灰底未被"绝对白"判定抽掉，整画布底板静默进格，角色仅占 10%）。
extends SceneTree

static var AI_ROOT: String = OS.get_environment("HOME") + "/hotw-assets/ai/"
static var OUT_ROOT: String = OS.get_environment("HOME") + "/hotw-assets/pilot/current/"

const CELL := 256
const GROUND_Y := 226
const BOX_W := 200
const BOX_H := 195
const MIN_OPAQUE := 1500
## 抽底：局部色距容差（0-1 欧氏距离）。相邻像素与已接受背景像素色距 ≤ 容差即背景，
## 局部传播可跟随浅色渐变（英雄 ComfyUI 产出为淡蓝灰渐变底，纯白判定会整板漏抽）。
## 实测定档 0.05：渐变相邻差 <0.5 级/px 足以跟随；≥0.08 会经浅色部件渗入角色内部吃主体
const BG_TOL := 0.05
## 抽底闸门：背景删除占比低于此值视为抽底失败（底板会静默进格），FAIL 终止
const MIN_BG_ERASE := 0.25
## 源图朝左需镜像为"条带朝右"基准的物种（本地 ComfyUI 模型产出惯例朝左；
## player.gd/monster 侧 flip_h 均按朝右基准写）。
## hero 曾在此列（v2 base 朝左）；2026-09-11 换 v3 定妆后 base 已朝右，继续翻
## 会把条带翻成朝左 → 玩家背朝移动方向跑/砍（像素实证：base 剑质心在人物质心右侧）。
## 若未来重生成出朝左姿势帧，单独翻转该帧文件，不要整体恢复 FLIP。
const FLIP_SPECIES: Array[String] = []

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var species_list: Array[String] = []
	if args.size() > 0:
		for a: String in args:
			species_list.append(a)
	else:
		var da := DirAccess.open(AI_ROOT)
		if da == null:
			print("FAIL: 目录不存在 " + AI_ROOT)
			quit(1)
			return
		da.list_dir_begin()
		var entry := da.get_next()
		while entry != "":
			if da.current_is_dir() and not entry.begins_with("."):
				species_list.append(entry)
			entry = da.get_next()
		da.list_dir_end()
	if species_list.is_empty():
		print("ai/ 下无物种目录（契约见文件头注释）")
		quit(0)
		return
	var ok_count := 0
	for species: String in species_list:
		if _process_species(species):
			ok_count += 1
	print("完成：%d/%d 物种" % [ok_count, species_list.size()])
	quit(0 if ok_count == species_list.size() else 1)

func _process_species(species: String) -> bool:
	var src_dir := AI_ROOT + species + "/"
	var base := _load_keyed(src_dir + "base.png", species)
	if base == null:
		print("%-14s 失败：缺 base.png" % species)
		return false
	var keys := {}
	for name: String in ["attack", "attack2", "attack3", "hurt", "melt", "puddle", "walk_a", "walk_b"]:
		var img := _load_keyed(src_dir + name + ".png", species)
		if img != null:
			keys[name] = img
	# 统一锚定：roll 间"角色在画布中占比"漂移若按各图独立 fit 会变成帧间大小跳变。
	# 姿势帧（walk/attack）按 base 内容高对齐（侧面角色姿势身高稳定、宽度差异大）；
	# 塌落帧（hurt/melt/puddle）与 base 同 scale（人变滩的物理大小关系不被等高拉大）。
	var scales := {}
	scales[base] = minf(BOX_W / float(base.get_width()), BOX_H / float(base.get_height()))
	var target_h: float = base.get_height() * float(scales[base])
	for name: String in keys:
		var img: Image = keys[name]
		if name == "hurt" or name == "melt" or name == "puddle":
			scales[img] = scales[base]
		else:
			scales[img] = minf(target_h / float(img.get_height()),
				minf(BOX_W / float(img.get_width()), float(scales[base]) * 1.25))
	# (图, 横向缩放, 纵向缩放, 附加抬升px, 锚定scale)
	var anims := {
		"idle": [
			[base, 1.00, 1.00, 0, scales[base]], [base, 1.02, 0.96, 0, scales[base]],
			[base, 1.05, 0.93, 0, scales[base]], [base, 1.02, 0.96, 0, scales[base]],
			[base, 1.00, 1.00, 0, scales[base]], [base, 0.99, 1.03, 0, scales[base]],
		],
	}
	# 真迈步双帧行走：walk_a↔walk_b 直接交替（两腿前后姿势差即步幅观感），
	# 叠加轻微挤压变体防机械；不再混入 base 缩放帧（幅度过小读不出动作）
	if keys.has("walk_a") and keys.has("walk_b"):
		var wa: Image = keys["walk_a"]
		var wb: Image = keys["walk_b"]
		anims["walk"] = [
			[wa, 1.00, 1.00, 0, scales[wa]], [wb, 1.02, 0.98, 0, scales[wb]],
			[wa, 0.98, 1.02, 2, scales[wa]], [wb, 1.00, 1.00, 0, scales[wb]],
			[wa, 1.02, 0.98, 0, scales[wa]], [wb, 0.98, 1.02, 2, scales[wb]],
		]
	else:
		anims["walk"] = [
			[base, 1.10, 0.88, 0, scales[base]], [base, 0.94, 1.12, 18, scales[base]],
			[base, 1.08, 0.90, 0, scales[base]], [base, 0.95, 1.10, 14, scales[base]],
			[base, 1.08, 0.90, 0, scales[base]], [base, 1.00, 1.00, 0, scales[base]],
		]
	# 攻击关键帧前置：短攻击窗（玩家 0.18s 状态窗）下出招姿势必须在首帧就位，
	# 蓄力帧后置作收招过渡（f0 出招 → f1 前冲拉伸 → f2 回拉 → f3-f5 收招回 base）
	if keys.has("attack"):
		var atk: Image = keys["attack"]
		anims["attack"] = [
			[atk, 1.00, 1.00, 0, scales[atk]], [atk, 1.05, 1.00, 0, scales[atk]],
			[atk, 0.94, 1.02, 0, scales[atk]], [base, 1.02, 0.96, 0, scales[base]],
			[base, 1.00, 1.00, 0, scales[base]], [base, 1.00, 1.00, 0, scales[base]],
		]
		# 二段斩（连击）：同构，用 attack2 关键帧
		if keys.has("attack2"):
			var atk2: Image = keys["attack2"]
			anims["attack2"] = [
				[atk2, 1.00, 1.00, 0, scales[atk2]], [atk2, 1.06, 1.00, 0, scales[atk2]],
				[atk2, 0.94, 1.02, 2, scales[atk2]], [base, 1.02, 0.96, 0, scales[base]],
				[base, 1.00, 1.00, 0, scales[base]], [base, 1.00, 1.00, 0, scales[base]],
			]
		# 三段重击（连击收尾）：幅度更大
		if keys.has("attack3"):
			var atk3: Image = keys["attack3"]
			anims["attack3"] = [
				[atk3, 1.03, 1.03, 0, scales[atk3]], [atk3, 1.08, 1.00, 0, scales[atk3]],
				[atk3, 0.92, 1.04, 4, scales[atk3]], [base, 1.04, 0.94, 0, scales[base]],
				[base, 1.00, 1.00, 0, scales[base]], [base, 1.00, 1.00, 0, scales[base]],
			]
	else:
		anims["attack"] = [
			[base, 1.00, 1.00, 0, scales[base]], [base, 1.12, 0.84, 0, scales[base]],
			[base, 0.95, 1.12, 10, scales[base]], [base, 1.10, 0.88, 0, scales[base]],
			[base, 0.97, 1.08, 6, scales[base]], [base, 1.00, 1.00, 0, scales[base]],
		]
	# 受击独立条带（玩家消费；4 帧@12fps≈0.33s 对齐 player HURT_ANIM_TIME）。
	# 无 hurt 关键帧的物种不产出——slice 配置不切即无感
	if keys.has("hurt"):
		var ht: Image = keys["hurt"]
		anims["hurt"] = [
			[ht, 1.00, 1.00, 0, scales[ht]], [ht, 0.97, 1.03, 0, scales[ht]],
			[ht, 1.00, 0.98, 0, scales[ht]], [base, 1.00, 1.00, 0, scales[base]],
		]
	var die_frames: Array = [[base, 1.12, 0.85, 0, scales[base]]]
	for name: String in ["hurt", "melt", "puddle"]:
		if keys.has(name):
			die_frames.append([keys[name], 1.00, 1.00, 0, scales[keys[name]]])
	if die_frames.size() == 1:
		die_frames = [
			[base, 1.05, 0.88, 0, scales[base]], [base, 1.15, 0.78, 0, scales[base]],
			[base, 1.25, 0.66, 0, scales[base]], [base, 1.35, 0.55, 0, scales[base]],
		]
	anims["die"] = die_frames

	var out_dir := OUT_ROOT + species + "/"
	DirAccess.make_dir_recursive_absolute(out_dir)
	for anim: String in anims:
		var frames: Array = anims[anim]
		var strip := Image.create(CELL * frames.size(), CELL, false, Image.FORMAT_RGBA8)
		for i: int in frames.size():
			var spec: Array = frames[i]
			var frame := _compose(spec[0], spec[1], spec[2], spec[3], spec[4])
			var opaque := _opaque_count(frame)
			if opaque < MIN_OPAQUE:
				print("%-14s FAIL：%s 第 %d 帧不透明像素 %d < %d" % [species, anim, i, opaque, MIN_OPAQUE])
				return false
			strip.blit_rect(frame, Rect2i(Vector2i.ZERO, Vector2i(CELL, CELL)), Vector2i(i * CELL, 0))
		var err := strip.save_png(out_dir + anim + ".png")
		if err != OK:
			print("%-14s FAIL：%s.png 保存失败 %d" % [species, anim, err])
			return false
	var key_note := ""
	for name: String in keys:
		key_note += name + " "
	print("%-14s OK  idle6/walk6/attack%d/die%d  关键帧：base %s" % [
		species, anims["attack"].size(), anims["die"].size(), key_note])
	return true

## 载入 + RGBA8 + 抽底（局部色距泛洪）+ 朝左物种镜像 + 内容框裁切，失败返回 null
func _load_keyed(path: String, species: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var img := Image.load_from_file(path)
	if img == null:
		print("FAIL: 加载失败 " + path)
		return null
	img.convert(Image.FORMAT_RGBA8)
	if species in FLIP_SPECIES:
		img.flip_x()
	var erased := _flood_key(img)
	if erased < MIN_BG_ERASE:
		print("FAIL: %s 抽底仅删 %.0f%%（< %d%%）——底色未被识别，整画布底板会静默进格，终止" % [
			path.get_file(), erased * 100.0, int(MIN_BG_ERASE * 100)])
		quit(1)
	var rect := _content_rect(img)
	if rect.size.x <= 0 or rect.size.y <= 0:
		print("FAIL: 无内容 " + path)
		return null
	print("    %-16s 抽底 %.0f%%" % [path.get_file(), erased * 100.0])
	return img.get_region(rect)

## 抽底：边缘泛洪按局部色距传播（相邻像素与已接受背景像素的色距 ≤ BG_TOL 即背景，
## 可跟随浅色渐变），软边按色距比例衰减 alpha 去描边外灰圈。全程字节数组操作避免逐像素 FFI。
## 返回被删背景像素占比（0-1）。BFS 只删与边缘连通区域，轮廓内白色部件（围巾/高光）保留。
func _flood_key(img: Image) -> float:
	var w := img.get_width()
	var h := img.get_height()
	var data := img.get_data()
	var n := w * h
	var mask := PackedByteArray()
	mask.resize(n)  # 0=保留 1=背景
	const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var tol := BG_TOL * 255.0
	var tol_sq := tol * tol
	var stack := PackedInt32Array()
	for x: int in w:
		stack.append(x)
		stack.append((h - 1) * w + x)
	for y: int in h:
		stack.append(y * w)
		stack.append(y * w + w - 1)
	for idx: int in stack:
		mask[idx] = 1
	var erased := stack.size()
	var cursor := 0
	while cursor < stack.size():
		var idx: int = stack[cursor]
		cursor += 1
		var r := data[idx * 4]
		var g := data[idx * 4 + 1]
		var b := data[idx * 4 + 2]
		var p := Vector2i(idx % w, idx / w)
		for d: Vector2i in DIRS:
			var q := p + d
			if q.x < 0 or q.x >= w or q.y < 0 or q.y >= h:
				continue
			var nidx := q.y * w + q.x
			if mask[nidx] != 0:
				continue
			var dr := data[nidx * 4] - r
			var dg := data[nidx * 4 + 1] - g
			var db := data[nidx * 4 + 2] - b
			if dr * dr + dg * dg + db * db <= tol_sq:
				mask[nidx] = 1
				erased += 1
				stack.append(nidx)
	# 软边：与背景相邻的保留像素，色距 < 2×容差的是 AI 源图 halo 过渡带（实测 10-25 级）
	# 直接清零（半透明残留会在实机读作灰白晕圈）；2~3×容差为描边抗锯齿混色，线性过渡
	for y: int in h:
		for x: int in w:
			var idx := y * w + x
			if mask[idx] != 0:
				continue
			var best := -1.0
			for d: Vector2i in DIRS:
				var q := Vector2i(x, y) + d
				if q.x < 0 or q.x >= w or q.y < 0 or q.y >= h:
					continue
				var bidx := q.y * w + q.x
				if mask[bidx] != 1:
					continue
				var dr := data[idx * 4] - data[bidx * 4]
				var dg := data[idx * 4 + 1] - data[bidx * 4 + 1]
				var db := data[idx * 4 + 2] - data[bidx * 4 + 2]
				var dist := sqrt(float(dr * dr + dg * dg + db * db))
				if best < 0.0 or dist < best:
					best = dist
			if best >= 0.0 and best < tol * 3.0:
				data[idx * 4 + 3] = int(float(data[idx * 4 + 3]) * clampf((best - tol * 2.0) / tol, 0.0, 1.0))
	# 应用背景擦除
	for i: int in n:
		if mask[i] == 1:
			data[i * 4 + 3] = 0
	img.set_data(w, h, false, Image.FORMAT_RGBA8, data)
	return float(erased) / float(n)

func _content_rect(img: Image) -> Rect2i:
	var min_x := 1 << 30
	var min_y := 1 << 30
	var max_x := -1
	var max_y := -1
	for y: int in img.get_height():
		for x: int in img.get_width():
			if img.get_pixel(x, y).a > 0.0:
				if x < min_x: min_x = x
				if x > max_x: max_x = x
				if y < min_y: min_y = y
				if y > max_y: max_y = y
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)

## 内容图按统一锚定 scale ×(sx, sy) 补间缩放后落进 256 格：底边贴 GROUND_Y-lift，水平居中。
## scale 由调用方按"统一身高/同 scale"锚定策略预计算（见 _process_species）
func _compose(src: Image, sx: float, sy: float, lift: int, scale: float) -> Image:
	var w := maxi(1, int(src.get_width() * scale * sx))
	var h := maxi(1, int(src.get_height() * scale * sy))
	var scaled := src.duplicate()
	scaled.resize(w, h, Image.INTERPOLATE_LANCZOS)
	var frame := Image.create(CELL, CELL, false, Image.FORMAT_RGBA8)
	frame.blit_rect(scaled, Rect2i(Vector2i.ZERO, Vector2i(w, h)),
		Vector2i((CELL - w) / 2, GROUND_Y - lift - h))
	return frame

func _opaque_count(img: Image) -> int:
	var n := 0
	for y: int in img.get_height():
		for x: int in img.get_width():
			if img.get_pixel(x, y).a > 0.0:
				n += 1
	return n
