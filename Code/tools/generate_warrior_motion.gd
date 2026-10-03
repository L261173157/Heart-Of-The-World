## Warrior 身体动作分层（离线工具）：只拷贝已授权 TS 原画像素，不在运行时读回 GPU。
## 第一下沿用 Attack1 四姿；反向斩从低手收势蓄力，再接 Attack2 的举盾出手/收势。
## Attack2 前两帧的剑遮住盾，不能简单抠掉：使用现有低手姿，不凭空补画盾。
## 几何蒙版跨蓝/黑/黄三皮肤共用，不按颜色删像素；源画与蒙版均192×192。
## 运行：godot --headless --path Code -s tools/generate_warrior_motion.gd
extends SceneTree

const OUT := "res://assets/creatures/frames/warrior_motion/"
const MASKS := "res://tools/warrior_motion_masks.json"
const SKINS := {"blue": ["Blue", "ninja"], "dark": ["Black", "ninja_dark"],
	"white": ["Yellow", "ninja_white"]}
const SEQUENCES := {
	"attack": ["a1_0", "a1_1", "a1_2", "a1_3"],
	"attack1": ["a1_0", "a1_1", "a1_2", "a1_3"],
	"attack2": ["a1_3", "a1_2", "a2_2", "a2_3"],
	"attack3": ["a1_0", "a1_1", "a2_2", "a2_3"],
}


func _init() -> void:
	var verify := "--check" in OS.get_cmdline_user_args()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MASKS))
	if not parsed is Dictionary or not parsed.has("frames"):
		push_error("缺失 Warrior 分层几何定义")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for skin: String in SKINS:
		var info: Array = SKINS[skin]
		var original: SpriteFrames = load("res://assets/creatures/frames/%s/%s_frames.res" % [info[1], info[1]])
		var result := original.duplicate(true) as SpriteFrames
		var size := original.get_frame_texture("attack1", 0).get_size()
		var sources := {}
		for source in ["Attack1", "Attack2"]:
			sources[source] = Image.load_from_file(ProjectSettings.globalize_path(
				"res://assets/ts/Units/%s Units/Warrior/Warrior_%s.png" % [info[0], source]))
		var poses := {}
		var hands := {}
		for key: String in parsed.frames:
			var spec: Dictionary = parsed.frames[key]
			var image := (sources[spec.source] as Image).get_region(Rect2i(int(spec.frame) * 192, 0, 192, 192))
			for patch: Dictionary in spec.get("patches", []):
				var rect: Array = patch.rect
				var destination: Array = patch.dest
				image.blit_rect(sources[patch.source], Rect2i(int(patch.frame) * 192 + int(rect[0]),
					int(rect[1]), int(rect[2]), int(rect[3])), Vector2i(int(destination[0]), int(destination[1])))
			var separated := Image.create(192, 192, false, Image.FORMAT_RGBA8)
			for row: Array in spec.rows:
				for x in range(int(row[1]), int(row[2]) + 1):
					separated.set_pixel(x, int(row[0]), image.get_pixel(x, int(row[0])))
			# 严格沿用全角色统一格心画布；不按新身体包围盒重新居中。
			var region := Rect2i(Vector2i((Vector2(192, 192) - size * 2.0) * 0.5), Vector2i(size * 2.0))
			var body := separated.get_region(region)
			body.resize(int(size.x), int(size.y), Image.INTERPOLATE_NEAREST)
			poses[key] = ImageTexture.create_from_image(body)
			hands[key] = (Vector2(float(spec.hand[0]), float(spec.hand[1])) - Vector2(96, 96)) * 0.5
		var grips := {}
		for animation: String in SEQUENCES:
			result.clear(animation)
			grips[animation] = []
			for key: String in SEQUENCES[animation]:
				result.add_frame(animation, poses[key], 1.0)
				grips[animation].append(hands[key])
		result.set_meta("attack_grips", grips)
		result.set_meta("hero_skin", skin)
		result.set_meta("authored_attack_body", true)
		result.set_meta("attack_source_sequences", SEQUENCES)
		if verify:
			var stored: SpriteFrames = load(OUT + skin + "_frames.res")
			if not _same_frames(result, stored):
				push_error("Warrior 动作资源过期，请重跑 generate_warrior_motion.gd: " + skin)
				quit(1)
				return
			continue
		var error := ResourceSaver.save(result, OUT + skin + "_frames.res",
			ResourceSaver.FLAG_BUNDLE_RESOURCES | ResourceSaver.FLAG_COMPRESS)
		if error != OK:
			push_error("Warrior 动作保存失败: " + str(error))
			quit(1)
			return
		print("WARRIOR MOTION ", skin, " ", size, " 原画身体/手点保存成功")
	print("=== WARRIOR MOTION ASSETS PASS ===")
	quit(0)


## CI 校验像素与数据，不比较可能携带临时 Resource UID 的二进制序列化字节。
func _same_frames(expected: SpriteFrames, actual: SpriteFrames) -> bool:
	if actual == null or expected.get_animation_names() != actual.get_animation_names():
		return false
	for key in ["attack_grips", "hero_skin", "authored_attack_body", "attack_source_sequences", "feet", "cw"]:
		if expected.get_meta(key, null) != actual.get_meta(key, null):
			return false
	for animation in expected.get_animation_names():
		if expected.get_frame_count(animation) != actual.get_frame_count(animation) \
				or expected.get_animation_speed(animation) != actual.get_animation_speed(animation) \
				or expected.get_animation_loop(animation) != actual.get_animation_loop(animation):
			return false
		for frame in expected.get_frame_count(animation):
			var a := expected.get_frame_texture(animation, frame).get_image()
			var b := actual.get_frame_texture(animation, frame).get_image()
			if a.get_size() != b.get_size() or a.get_data() != b.get_data() \
					or expected.get_frame_duration(animation, frame) != actual.get_frame_duration(animation, frame):
				return false
	return true
