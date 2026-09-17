## 一次性探针：打印当前种子下全部 Boss 城塞坐标（截图取证/调试用）
extends SceneTree


func _init() -> void:
	BiomeMap.configure(BiomeMap.DEFAULT_SEED)
	for dg: Dictionary in ObstacleField.dungeons():
		var boss: String = WorldConfig.TERRAIN_BOSSES.get(dg["terrain"], "?")
		print("%s %s %d,%d" % [dg["terrain"], boss,
			int(dg["center"].x), int(dg["center"].y)])
	quit(0)
