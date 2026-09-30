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

## 帧尺寸界（粗闸：防横带级超宽帧——事故时帧宽 219/236px；格心对称锚定后最大
## = Lancer 系 147×113（含对称留边），160 留余量。精确守卫见 EXPECTED_SIZES 白名单）
const MAX_FRAME_DIM := 160
const MIN_FRAME_DIM := 3
## 帧内容最少不透明像素数（防裁到条带空白段/全透明帧）
const MIN_OPAQUE_PIXELS := 8

## 逐条目期望尺寸白名单（真源=切帧器打印；2026-09-28 动作补齐后同步：
## 裸兵种换工具版/加 Interact 攻击帧扩了 9 目录画布）：
## p 误检（÷p 步长错）/ k 回归 / 横带事故/ 锚定回退四类都会在这里现形——
## 切帧表或素材改动时按切帧器输出同步更新本表
const EXPECTED_SIZES := {
	"ninja": Vector2i(67, 60), "ninja_dark": Vector2i(67, 60), "ninja_white": Vector2i(67, 60),
	"npc_hunter": Vector2i(40, 50), "npc_scholar": Vector2i(43, 39), "npc_keeper": Vector2i(42, 38),
	"npc_merchant": Vector2i(37, 39), "npc_watchman": Vector2i(50, 51), "npc_herbalist": Vector2i(46, 39),
	"oni": Vector2i(58, 39), "sprout": Vector2i(46, 45), "boar": Vector2i(67, 60),
	"turtle": Vector2i(67, 60), "chicken": Vector2i(52, 55), "slime": Vector2i(23, 23),
	"frog": Vector2i(46, 45), "mandrake": Vector2i(44, 50), "mushroom": Vector2i(44, 50),
	"raccoon": Vector2i(52, 55), "treant": Vector2i(67, 60), "slime_teal": Vector2i(23, 23),
	"penguin": Vector2i(57, 39), "ghost": Vector2i(46, 45), "bear": Vector2i(67, 60),
	"bat": Vector2i(46, 45), "crab": Vector2i(44, 50), "octopus": Vector2i(44, 50),
	"eye": Vector2i(44, 50), "parrot": Vector2i(32, 24), "beetle": Vector2i(67, 60),
	"squirrel": Vector2i(46, 45), "cactus": Vector2i(147, 113), "cyclope": Vector2i(67, 60),
	"boss_samurai": Vector2i(147, 113), "phoenix": Vector2i(44, 50), "gargoyle": Vector2i(63, 56),
	"dragon": Vector2i(147, 113), "boss_flam": Vector2i(63, 56),
	"fx_flame": Vector2i(11, 12), "fx_frost": Vector2i(11, 12), "fx_magic": Vector2i(16, 16),
	"fx_charge": Vector2i(9, 11), "fx_burst": Vector2i(14, 18), "fx_boom": Vector2i(16, 16),
	"fx_smoke": Vector2i(18, 17), "fx_darksmoke": Vector2i(13, 12), "fx_orb": Vector2i(10, 10),
	"fx_slash": Vector2i(6, 15), "fx_slash_gold": Vector2i(6, 15), "fx_flash": Vector2i(14, 14),
	"fx_flash_gold": Vector2i(14, 14), "fx_flash_blue": Vector2i(14, 14),
	"fx_flash_yellow": Vector2i(14, 14), "fx_beam": Vector2i(40, 16),
	"fx_pillar": Vector2i(8, 16), "fx_beams": Vector2i(14, 13), "deco_foam": Vector2i(15, 16),
}

## 物种帧目录 → 必需动作集（2026-09-28 动作补齐口径）：战斗怪必有 attack
## （Pawn 工具版 Interact / Warrior Attack / Archer Shoot / Lancer Right_Attack），
## Warrior/Lancer 系另有 hurt（Guard/Right_Defence 演出）；羊/鸭被动系仅
## idle/walk（永不参战，无动作素材）。与运行时请求面（_perform_attack 播
## attack、take_damage 播 hurt）一致——该切没切/切了没接线在此现形
const SPECIES_REQUIRED := {
	"oni": ["idle", "walk", "attack"], "sprout": ["idle", "walk", "attack"],
	"frog": ["idle", "walk", "attack"], "ghost": ["idle", "walk", "attack"],
	"bat": ["idle", "walk", "attack"], "squirrel": ["idle", "walk", "attack"],
	"slime": ["idle", "walk", "attack"], "slime_teal": ["idle", "walk", "attack"],
	"penguin": ["idle", "walk", "attack"],
	"mandrake": ["idle", "walk", "attack"], "mushroom": ["idle", "walk", "attack"],
	"crab": ["idle", "walk", "attack"], "octopus": ["idle", "walk", "attack"],
	"eye": ["idle", "walk", "attack"], "phoenix": ["idle", "walk", "attack"],
	"boar": ["idle", "walk", "attack", "hurt"], "turtle": ["idle", "walk", "attack", "hurt"],
	"bear": ["idle", "walk", "attack", "hurt"], "beetle": ["idle", "walk", "attack", "hurt"],
	"cyclope": ["idle", "walk", "attack", "hurt"], "treant": ["idle", "walk", "attack", "hurt"],
	"gargoyle": ["idle", "walk", "attack", "hurt"], "boss_flam": ["idle", "walk", "attack", "hurt"],
	"boss_samurai": ["idle", "walk", "attack", "hurt"], "cactus": ["idle", "walk", "attack", "hurt"],
	"dragon": ["idle", "walk", "attack", "hurt"],
	"chicken": ["idle", "walk"], "raccoon": ["idle", "walk"], "parrot": ["idle", "walk"],
}

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
		_test_frames_dir(hero, ["idle", "walk", "attack", "attack1", "attack2",
			"attack3", "hurt"], "英雄皮肤")
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
	re_path.compile("path=\"(res://assets/creatures/frames/[^\"]+\\.res)\"")
	var re_scale := RegEx.new()
	re_scale.compile("visual_scale = ([0-9.]+)")
	for f in files:
		var text := FileAccess.get_file_as_string("res://data/species/" + f)
		var m := re_path.search(text)
		if m == null:
			_check(false, "%s 含 frames_override 路径" % f)
			continue
		# 帧目录名（frames_override 路径首段）→ 按物种动作期望验收
		var frame_dir: String = m.get_string(1).replace(
			"res://assets/creatures/frames/", "").split("/")[0]
		var required: Array = SPECIES_REQUIRED.get(frame_dir, ["idle", "walk"])
		_test_frames_file(m.get_string(1), required, "物种 " + f)
		var ms := re_scale.search(text)
		if ms != null:
			var scale := float(ms.get_string(1))
			_check(scale > 0.05 and scale <= 3.0,
				"%s visual_scale %.2f ∈ (0.05, 3]" % [f, scale])


func _test_frames_dir(frame_dir: String, required: Array, label: String) -> void:
	_test_frames_file("res://assets/creatures/frames/%s/%s_frames.res" % [frame_dir, frame_dir],
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
	# 尺寸界 + 内容非空（横带守卫：超宽帧直接 FAIL）+ 白名单精确尺寸
	var dir_name := path.replace("res://assets/creatures/frames/", "").split("/")[0]
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
			if EXPECTED_SIZES.has(dir_name) and Vector2i(w, h) != EXPECTED_SIZES[dir_name]:
				bad_dim = "%s.%s 帧%d 尺寸 %dx%d ≠ 白名单 %s" % [label, anim, k, w, h,
					str(EXPECTED_SIZES[dir_name])]
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
						# 含 % 的动态拼接路径不算：正则字符类不含 %，匹配串总是断在
						# %s 前的目录前缀（如探图 res://assets/landmarks/），故看匹配
						# 后余文是否以 % 起头，而非匹配串本身
						if line.substr(m.get_end()).lstrip(" ").begins_with("%"):
							continue
						out[p] = true
		fn = dir.get_next()
	dir.list_dir_end()
