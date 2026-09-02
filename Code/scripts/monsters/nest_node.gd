## 巢穴表现体（StaticBody2D，可被玩家攻击）：物种在区域立足的可视化锚点。
## 捣毁效果走 EcologySim.destroy_nest（单点权威）：该区域该物种繁衍停止 + 全族激怒。
## 程序绘制：物种 tint 色土丘 + 深色洞口。
class_name NestNode
extends StaticBody2D

const NEST_HP := 4

var region_id := ""
var species_name := ""
var nest_key := ""

var _hp := NEST_HP
var _visual: Polygon2D
var _hole: Polygon2D


func setup(p_region_id: String, p_species_name: String, tint: Color, at_position: Vector2) -> void:
	region_id = p_region_id
	species_name = p_species_name
	nest_key = "%s|%s" % [p_region_id, p_species_name]
	global_position = at_position
	_visual = _mound(tint.darkened(0.15), 34.0)
	add_child(_visual)
	_hole = _mound(Color(0.08, 0.07, 0.06), 14.0)
	_hole.position = Vector2(0, -6)
	add_child(_hole)
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 26.0
	shape.shape = circle
	add_child(shape)
	z_index = -1


func _ready() -> void:
	collision_layer = 2
	collision_mask = 0
	add_to_group("nests")


func _mound(color: Color, radius: float) -> Polygon2D:
	var poly := Polygon2D.new()
	var points := PackedVector2Array()
	for i in 10:
		var ang := PI + PI * i / 9.0  # 上半圆土丘
		points.append(Vector2.RIGHT.rotated(ang) * Vector2(radius, radius * 0.62))
	poly.polygon = points
	poly.color = color
	return poly


func take_damage(_amount: float, _from_position := Vector2.INF, _heavy := false,
		_knock := 1.0, _effective := false) -> void:
	_hp -= 1
	var flash := create_tween()
	_visual.modulate = Color(1.0, 0.5, 0.5)
	flash.tween_property(_visual, "modulate", Color.WHITE, 0.15)
	if _hp > 0:
		return
	# 捣毁：模拟层单点权威 + 播报 + 碎裂
	WorldSim.sim.destroy_nest(region_id, species_name)
	EventBus.world_event.emit("💥 %s 的巢穴在%s被捣毁！%s群情激愤——繁衍已被遏制" % [
		species_name, _region_display(), species_name])
	EventBus.camera_shake_requested.emit(4.0)
	_burst()
	queue_free()


func _region_display() -> String:
	var region: SimRegion = WorldSim.sim.get_region(region_id) if WorldSim.sim != null else null
	return region.display_name if region != null else region_id


func _burst() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(nest_key)
	for i in 8:
		var shard := Polygon2D.new()
		shard.polygon = PackedVector2Array([
			Vector2(-3, -3), Vector2(3, -3), Vector2(3, 3), Vector2(-3, 3),
		])
		shard.color = _visual.color.darkened(rng.randf_range(0.0, 0.3))
		shard.z_index = 20
		get_parent().add_child(shard)
		shard.global_position = global_position
		var dir := Vector2.RIGHT.rotated(rng.randf() * TAU)
		var tween := shard.create_tween()
		tween.set_parallel(true)
		tween.tween_property(shard, "global_position",
			global_position + dir * rng.randf_range(20.0, 50.0), 0.4).set_ease(Tween.EASE_OUT)
		tween.tween_property(shard, "modulate:a", 0.0, 0.4).set_delay(0.1)
		tween.chain().tween_callback(shard.queue_free)
