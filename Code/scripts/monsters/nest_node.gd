## 巢穴表现体（StaticBody2D，可被玩家攻击）：物种在区域立足的可视化锚点。
## 捣毁效果走 EcologySim.destroy_nest（单点权威）：该区域该物种繁衍停止 + 全族激怒。
## 美术 v6.1（Enemy Pack）：按区域群系挂动画小屋帧（plains/forest=哥布林小屋、
## swamp=鱼屋、snow/hill/lava=洞穴），碎片色仍取物种 tint 保族别辨识。
class_name NestNode
extends StaticBody2D

const NEST_HP := 4

## 群系 → 巢穴动画帧资源（tools/slice_spritesheets.gd 产，frames_test 守契约）
const NEST_FRAMES := {
	"plains": "res://assets/creatures/frames/nest_hut/nest_hut_frames.res",
	"forest": "res://assets/creatures/frames/nest_hut/nest_hut_frames.res",
	"swamp": "res://assets/creatures/frames/nest_fish_hut/nest_fish_hut_frames.res",
	"snow": "res://assets/creatures/frames/nest_cave/nest_cave_frames.res",
	"hill": "res://assets/creatures/frames/nest_cave/nest_cave_frames.res",
	"lava": "res://assets/creatures/frames/nest_cave/nest_cave_frames.res",
}

var region_id := ""
var species_name := ""
var nest_key := ""
## 碎片/受击闪烁基色（物种 tint，捣毁碎屑的族别辨识）
var _tint := Color(0.35, 0.7, 0.25)

var _hp := NEST_HP
## 捣毁幂等守卫：节点在帧末才释放，同帧多来源命中（重击 AOE + 普攻判定框 +
## 法弹可同帧到达）会重复走完破坏效果（双播报/双倍碎片/双震屏）
var _destroyed := false
var _visual: AnimatedSprite2D


func setup(p_region_id: String, p_species_name: String, tint: Color, at_position: Vector2) -> void:
	region_id = p_region_id
	species_name = p_species_name
	nest_key = "%s|%s" % [p_region_id, p_species_name]
	_tint = tint
	global_position = at_position
	var terrain := ""
	var region: SimRegion = WorldSim.sim.get_region(region_id) if WorldSim.sim != null else null
	if region != null:
		terrain = region.terrain
	var frames_path: String = NEST_FRAMES.get(terrain,
		NEST_FRAMES["plains"])
	_visual = AnimatedSprite2D.new()
	_visual.sprite_frames = load(frames_path) as SpriteFrames
	_visual.scale = Vector2.ONE  # 原生直出（hut 128×113 / fish 75×83 / cave 80×77）
	if _visual.sprite_frames != null and _visual.sprite_frames.has_animation("play"):
		var h := _visual.sprite_frames.get_frame_texture("play", 0).get_height()
		_visual.position = Vector2(0, -h / 2.0)  # 底边贴巢位锚点
	add_child(_visual)
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 26.0
	shape.shape = circle
	add_child(shape)
	z_index = -1


func _ready() -> void:
	# 独立碰撞层 4（不是怪物层 2）：巢穴可被攻击（攻击判定 mask 含 4），
	# 但不再阻挡怪物与玩家的身体——怪物不顶自家巢滑动绕行、法弹不被巢吸弹
	collision_layer = 4
	collision_mask = 0
	add_to_group("nests")
	if _visual != null and _visual.sprite_frames != null:
		_visual.play(&"play")


func take_damage(_amount: float, _from_position := Vector2.INF, _heavy := false,
		_knock := 1.0, _effective := false) -> void:
	if _destroyed:
		return
	_hp -= 1
	if _visual != null:
		var flash := create_tween()
		_visual.modulate = Color(1.0, 0.5, 0.5)
		flash.tween_property(_visual, "modulate", Color.WHITE, 0.15)
	if _hp > 0:
		return
	_destroyed = true
	# 捣毁：模拟层单点权威 + 播报 + 碎裂（WorldSim 已停时的残余攻击判空防崩）
	if WorldSim.sim != null:
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
	# 巢穴碎片池化复用（巢体自身随即销毁，碎片经 VfxPool 跨巢共享；见 VfxPool 约定）
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(nest_key)
	var parent := get_parent()
	for i in 8:
		var shard := VfxPool.take("nest_shard") as Polygon2D
		if shard == null:
			shard = Polygon2D.new()
			shard.z_index = 20
			parent.add_child(shard)
		elif shard.get_parent() != parent:
			shard.get_parent().remove_child(shard)
			parent.add_child(shard)
		shard.polygon = PackedVector2Array([
			Vector2(-3, -3), Vector2(3, -3), Vector2(3, 3), Vector2(-3, 3),
		])
		shard.color = _tint.darkened(rng.randf_range(0.0, 0.3))
		shard.modulate.a = 1.0
		shard.global_position = global_position
		var dir := Vector2.RIGHT.rotated(rng.randf() * TAU)
		var tween := shard.create_tween()
		shard.set_meta("vfx_tween", tween)
		tween.set_parallel(true)
		tween.tween_property(shard, "global_position",
			global_position + dir * rng.randf_range(20.0, 50.0), 0.4).set_ease(Tween.EASE_OUT)
		tween.tween_property(shard, "modulate:a", 0.0, 0.4).set_delay(0.1)
		tween.chain().tween_callback(func() -> void: VfxPool.release(shard, "nest_shard"))
