extends SceneTree
## 双模式探针（默认=凸分解守闸，sample=截图采样点）：
##  1) 凸分解守闸：区域 Area2D 的 CollisionPolygon2D 用 patch_polygons 栅格边界环，
##     鞍点续链偶发产出引擎无法凸分解的环（失败环不生成碰撞形状 → 进区播报/BGM/
##     威胁警告静默失灵，约 1~2% 随机种子命中，实证坏种子 1999437034）。
##     对指定种子全量验证 BiomeMap.collision_safe_loop：修复后每个环必须可凸分解。
##  2) sample：输出各群系斑块中心 + 一处群系交界 + 前几个地标坐标（截图取证用；
##     世界种子每档不同，旧文档坐标会过期）。
## 用法：headless -s tools/convex_probe.gd -- [种子]        # 守闸模式
##       headless -s tools/convex_probe.gd -- sample [种子]  # 采样点模式

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var seed_arg := 3805551120  # 无 randomize 时代 randi() 的确定值（历史档种子）
	if not args.is_empty() and args[0] == "sample":
		if args.size() > 1:
			seed_arg = int(args[1])
		_sample_points(seed_arg)
		return
	if args.size() > 0:
		seed_arg = int(args[0])
	_convex_gate(seed_arg)


func _convex_gate(seed_arg: int) -> void:
	BiomeMap.configure(seed_arg)
	var total := 0
	var raw_fail := 0
	var safe_fail := 0
	var simplified := 0
	for p: Dictionary in BiomeMap.patches():
		for loop: PackedVector2Array in BiomeMap.patch_polygons(p["id"], 1000.0):
			total += 1
			var safe: PackedVector2Array = BiomeMap.collision_safe_loop(loop)
			if safe != loop:
				simplified += 1
			if Geometry2D.decompose_polygon_in_convex(safe).is_empty():
				safe_fail += 1
				print("  仍失败：", p["id"], " ", safe.size(), " 点")
			if Geometry2D.decompose_polygon_in_convex(loop).is_empty():
				raw_fail += 1
	print("种子=%d 总环=%d 原始失败=%d 简化=%d 修复后失败=%d" % [
			seed_arg, total, raw_fail, simplified, safe_fail])
	quit(1 if safe_fail > 0 else 0)


func _sample_points(seed_arg: int) -> void:
	BiomeMap.configure(seed_arg)
	var seen := {}
	for p: Dictionary in BiomeMap.patches():
		var t: String = p["terrain"]
		if seen.has(t):
			continue
		seen[t] = true
		var c: Vector2 = p["center"]
		print("%s 中心 %d,%d" % [t, int(c.x), int(c.y)])
	var plains: Dictionary = BiomeMap.patches_of_terrain("plains")[0]
	var swamp: Dictionary = BiomeMap.patches_of_terrain("swamp")[0]
	var a: Vector2 = plains["center"]
	var b: Vector2 = swamp["center"]
	var prev_t := ""
	for i in range(1, 200):
		var pt := a.lerp(b, float(i) / 200.0)
		var t := BiomeMap.terrain_at(pt)
		if prev_t != "" and t != prev_t:
			print("交界 %s|%s  %d,%d" % [prev_t, t, int(pt.x), int(pt.y)])
			break
		prev_t = t
	for lm: Dictionary in LandmarkRegistry.landmarks().slice(0, 4):
		print("地标 ", lm["kind"], " ", lm["pos"])
	quit(0)
