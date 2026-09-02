## 小地图：六区域地形色块 + 玩家白点 + 怪物实时彩点。
## 让"相连的多张地图"与生态迁徙/扩张一眼可视（本作核心卖点的常驻展示位）。
class_name Minimap
extends Control

const REDRAW_INTERVAL := 0.25
const TERRAIN_COLORS := {
	"plains": Color(0.55, 0.52, 0.32),
	"forest": Color(0.18, 0.33, 0.16),
	"snow": Color(0.8, 0.86, 0.9),
	"swamp": Color(0.22, 0.28, 0.2),
	"hill": Color(0.47, 0.37, 0.25),
	"lava": Color(0.36, 0.16, 0.12),
}

var _accum := 0.0


func _process(delta: float) -> void:
	_accum += delta
	if _accum >= REDRAW_INTERVAL:
		_accum = 0.0
		queue_redraw()


func _draw() -> void:
	var sim: EcologySim = WorldSim.sim
	if sim == null or sim.regions.is_empty():
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.35))

	var world := _world_rect(sim)
	if world.size.x <= 0.0 or world.size.y <= 0.0:
		return
	var s := minf(size.x / world.size.x, size.y / world.size.y)
	var offset := (size - world.size * s) * 0.5

	for region: SimRegion in sim.regions.values():
		var rect := Rect2(
			offset + (region.center - region.size * 0.5 - world.position) * s,
			region.size * s)
		draw_rect(rect, TERRAIN_COLORS.get(region.terrain, Color.GRAY))
		draw_rect(rect, Color(0, 0, 0, 0.55), false, 1.0)

	for body in get_tree().get_nodes_in_group("monsters"):
		var monster := body as MonsterBase
		if monster == null or monster.inst == null or monster.state == MonsterBase.S_CORPSE:
			continue
		draw_circle(offset + (monster.global_position - world.position) * s, 2.0,
				monster.inst.species.tint)

	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player != null and player.visible:
		draw_circle(offset + (player.global_position - world.position) * s, 3.5, Color.WHITE)


func _world_rect(sim: EcologySim) -> Rect2:
	var min_pos := Vector2.INF
	var max_pos := -Vector2.INF
	for region: SimRegion in sim.regions.values():
		var a := region.center - region.size * 0.5
		var b := region.center + region.size * 0.5
		min_pos = min_pos.min(a)
		max_pos = max_pos.max(b)
	return Rect2(min_pos, max_pos - min_pos)
