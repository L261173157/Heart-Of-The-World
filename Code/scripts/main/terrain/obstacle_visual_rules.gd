## 障碍视觉分层：密林每个32px实心格仍有可见木质根床，成熟树冠稀疏分布。
## 只决定画哪一张图；采样/碰撞/导航真源仍是 ObstacleField，不制造隐形墙。
class_name ObstacleVisualRules
extends RefCounted


static func appearance(cell: Vector2i, kind: String) -> Dictionary:
	var hash_value := _cell_hash(cell)
	if kind not in ["tree", "big_tree", "pine"]:
		return {"source": 0, "atlas": ObstacleField.KIND_ATLAS[kind], "alternative": 0}
	# 2×2局部竞争：孤立树完整保留；浓密格中只有一个成熟树冠，不依赖加载块边缘。
	var block := Vector2i(floori(float(cell.x) / 2.0), floori(float(cell.y) / 2.0)) * 2
	var winner := cell
	var score := hash_value
	for dy in 2:
		for dx in 2:
			var other := block + Vector2i(dx, dy)
			if other == cell:
				continue
			var sample := ObstacleField.sample_cell(other)
			if sample.get("kind", "") not in ["tree", "big_tree", "pine"]:
				continue
			var candidate := _cell_hash(other)
			if candidate < score:
				score = candidate
				winner = other
	if winner != cell:
		return {"source": 1, "atlas": Vector2i(hash_value % 3, 0), "alternative": 0}
	# 同一大噪声斑不再重复同款树：针叶/阔叶与明暗按格稳定变化。
	var kinds := ["tree", "big_tree", "pine"]
	var visual_kind: String = kinds[(hash_value / 7) % 3] if kind != "pine" else "pine"
	return {"source": 0, "atlas": ObstacleField.KIND_ATLAS[visual_kind],
		"alternative": 1 if hash_value % 2 == 0 else 0}


static func _cell_hash(cell: Vector2i) -> int:
	# 最后混洗打散相邻格的高位相关性，避免每个2×2块都选同一个角形成新对角网。
	var value := (cell.x * 73856093 ^ cell.y * 19349663) & 0x7fffffff
	value = ((value ^ (value >> 13)) * 1274126177) & 0x7fffffff
	return value ^ (value >> 16)
