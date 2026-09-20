## 帧资产契约验收（第七测；无头：godot --headless --path Code -s tests/frames_test.gd）。
## 背景（2026-09-20 横带事故）：切帧器 union bbox 用了条带绝对坐标，每帧被裁成
## 「多角色并排横带」——六测全绿但玩家实玩才暴露。本测试守住资产契约层：
##   A. 帧资源契约：可加载 / 必需动画齐全 / 帧数≥1 / 帧尺寸在单角色界内
##      （横带=超宽帧，直接 FAIL）/ 帧内容非空（防裁到空白段）
##      覆盖：29 物种 frames_override、英雄三皮肤、6 NPC、18 组 fx
##   B. 字面资产路径存在性：扫描 scripts/scenes/autoload/tools 里的 res:// 字面
##      路径（跳过注释行），逐一验证存在——烘焙产物缺失/忘跑 --import 都会现形
## 约定：切帧器/烘焙工具改表重跑后必跑本测试；退出码非 0 = 失败。
extends SceneTree

## 帧尺寸界（单角色档：横带事故时帧宽 219/236px；正常最大 = boss_flam 50、
## fx 最大 ~40。96 留一倍余量，未来加宽素材再调）
const MAX_FRAME_DIM := 96
const MIN_FRAME_DIM := 3
## 帧内容最少不透明像素数（防裁到条带空白段/全透明帧）
const MIN_OPAQUE_PIXELS := 8

## 英雄三皮肤（键名沿用 ninja* 免存档迁移）
const HERO_FRAME_DIRS := ["ninja", "ninja_dark", "ninja_white"]
## 地标/营地 NPC 六槽（与 game_world.LandmarkNPC.FRAMES 同步）
const NPC_FRAME_DIRS := ["npc_hunter", "npc_scholar", "npc_keeper",
	"npc_merchant", "npc_watchman", "npc_herbalist"]
## 18 组特效（与 FxLayer.TABLE + player 本地 3 组同步；新增 kind 两边同改）
const FX_FRAME_DIRS := ["fx_slash", "fx_slash_gold", "fx_flame", "fx_magic",
	"fx_charge", "fx_frost", "fx_burst", "fx_boom", "fx_smoke", "fx_darksmoke",
	"fx_orb", "fx_beam", "fx_pillar", "fx_flash", "fx_flash_gold",
	"fx_flash_blue", "fx_flash_yellow", "fx_beams"]

var _pass := 0
var _fail := 0


func _check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("  FAIL  ", msg)


func _init() -> void:
	print("=== A. 帧契约 ===")
	_test_species_frames()
	for hero: String in HERO_FRAME_DIRS:
		_test_frames_dir(hero, ["idle", "walk", "attack"], "英雄皮肤")
	for npc: String in NPC_FRAME_DIRS:
		_test_frames_dir(npc, ["idle", "walk"], "NPC")
	for fx: String in FX_FRAME_DIRS:
		_test_frames_dir(fx, ["play"], "特效")
	print("=== B. 字面资产路径存在性 ===")
	_test_literal_paths()
	print("=== 帧资产验收：%d 项断言（通过 %d / 失败 %d）===" % [_pass + _fail, _pass, _fail])
	if _fail > 0:
		print("!!! 存在失败项：先跑 tools/slice_spritesheets.gd + bake_structures.gd，")
		print("    再 godot --headless --path Code --import，最后重跑本测试")
	quit(0 if _fail == 0 else 1)


## 物种：解析 .tres 文本里的 frames_override 路径（不编译类，纯文本稳妥），
## 另校验 visual_scale 落在 sane 区间
func _test_species_frames() -> void:
	var dir := DirAccess.open("res://data/species")
	if dir == null:
		_check(false, "data/species 目录可打开")
		return
	dir.list_dir_begin()
	var files: Array[String] = []
	var fn := dir.get_next()
	while fn != "":
		var base := fn.trim_suffix(".remap")
		if base.ends_with(".tres"):
			files.append(base)
		fn = dir.get_next()
	dir.list_dir_end()
	files.sort()
	_check(files.size() >= 29, "物种 .tres 数量 %d ≥ 29" % files.size())
	var re_path := RegEx.new()
	re_path.compile("path=\"(res://assets/creatures/frames/[^\"]+\\.tres)\"")
	var re_scale := RegEx.new()
	re_scale.compile("visual_scale = ([0-9.]+)")
	for f in files:
		var text := FileAccess.get_file_as_string("res://data/species/" + f)
		var m := re_path.search(text)
		if m == null:
			_check(false, "%s 含 frames_override 路径" % f)
			continue
		_test_frames_file(m.get_string(1), ["idle", "walk"], "物种 " + f)
		var ms := re_scale.search(text)
		if ms != null:
			var scale := float(ms.get_string(1))
			_check(scale > 0.05 and scale <= 3.0,
				"%s visual_scale %.2f ∈ (0.05, 3]" % [f, scale])


func _test_frames_dir(frame_dir: String, required: Array, label: String) -> void:
	_test_frames_file("res://assets/creatures/frames/%s/%s_frames.tres" % [frame_dir, frame_dir],
		required, "%s %s" % [label, frame_dir])


## 单个 SpriteFrames 的完整契约
func _test_frames_file(path: String, required: Array, label: String) -> void:
	var res: Resource = load(path)
	if res == null or not (res is SpriteFrames):
		_check(false, "%s 帧资源可加载（%s）" % [label, path])
		return
	_check(true, "%s 帧资源可加载" % label)
	var frames := res as SpriteFrames
	for anim: String in required:
		if not frames.has_animation(anim):
			_check(false, "%s 含动画 %s" % [label, anim])
			continue
		var n := frames.get_frame_count(anim)
		_check(n >= 1, "%s.%s 帧数 %d ≥ 1" % [label, anim, n])
	# 尺寸界 + 内容非空（横带守卫：超宽帧直接 FAIL）
	for anim in frames.get_animation_names():
		var bad_dim := ""
		for k in frames.get_frame_count(anim):
			var t := frames.get_frame_texture(anim, k)
			var w := t.get_width()
			var h := t.get_height()
			if w < MIN_FRAME_DIM or h < MIN_FRAME_DIM or w > MAX_FRAME_DIM or h > MAX_FRAME_DIM:
				bad_dim = "%s.%s 帧%d 尺寸 %dx%d 越界 [%d,%d]" % [label, anim, k, w, h,
					MIN_FRAME_DIM, MAX_FRAME_DIM]
				break
		_check(bad_dim.is_empty(), "%s.%s 全帧尺寸在界内%s" % [label, anim,
			"" if bad_dim.is_empty() else "（" + bad_dim + "）"])
		# 帧内容非空（前 6 帧取最大：火焰/光束类特效首帧淡起是动画语义，
		# 但整段动画全空 = 裁到空白段，如 Lancer 64 帧误分段事故）
		if frames.get_frame_count(anim) > 0:
			var best := 0
			for k in mini(frames.get_frame_count(anim), 6):
				var img := frames.get_frame_texture(anim, k).get_image()
				var opaque := 0
				for y in img.get_height():
					for x in img.get_width():
						if img.get_pixel(x, y).a > 0.5:
							opaque += 1
							if opaque >= MIN_OPAQUE_PIXELS:
								break
					if opaque >= MIN_OPAQUE_PIXELS:
						break
				best = maxi(best, opaque)
				if best >= MIN_OPAQUE_PIXELS:
					break
			_check(best >= MIN_OPAQUE_PIXELS, "%s.%s 前6帧含内容（最多 %d 不透明像素）" % [
				label, anim, best])


## B. 字面 res:// 资产路径存在性（跳过注释行；含 % 的动态拼接路径不算）
func _test_literal_paths() -> void:
	var re := RegEx.new()
	re.compile("res://assets/[A-Za-z0-9_\\-./ ]+")
	var paths := {}
	for root: String in ["res://scripts", "res://scenes", "res://autoload", "res://tools"]:
		_collect(root, re, paths)
	var missing: Array[String] = []
	for p_raw: String in paths:
		var p := p_raw.strip_edges().rstrip("/")
		if ResourceLoader.exists(p) or FileAccess.file_exists(p) \
				or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(p)):
			continue
		missing.append(p)
	_check(missing.is_empty(), "字面资产路径 %d 条全部存在%s" % [paths.size(),
		"" if missing.is_empty() else "（缺失：" + "、".join(missing) + "）"])


func _collect(dir_path: String, re: RegEx, out: Dictionary) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var fn := dir.get_next()
	while fn != "":
		var full := dir_path + "/" + fn
		if dir.current_is_dir():
			if not fn.begins_with("."):
				_collect(full, re, out)
		elif fn.ends_with(".gd") or fn.ends_with(".tscn"):
			var f := FileAccess.open(full, FileAccess.READ)
			if f != null:
				while not f.eof_reached():
					var line := f.get_line().strip_edges()
					if line.begins_with("#"):
						continue  # 注释行里的历史路径不算引用
					for m: RegExMatch in re.search_all(line):
						var p := m.get_string(0)
						if not p.contains("%"):
							out[p] = true
		fn = dir.get_next()
	dir.list_dir_end()
