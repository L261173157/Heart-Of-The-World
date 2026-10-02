## 受击短白闪 + 接触火花。每只怪按需创建一个复用节点，无粒子/贴图读回。
## 只处理表现，不改位置/伤害/AI/出招窗；暂停/死亡会清除材质，避免白尸体。
extends Node2D

const FLASH_TIME := 0.10
const BURST_TIME := 0.17
const RETRIGGER_GAP := 0.08
static var _shader: Shader
var active := false
var _sprite: AnimatedSprite2D
var _material: ShaderMaterial
var _previous_material: Material
var _started_usec := -1000000
var _progress := 1.0
var _heavy := false
var _effective := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 8
	set_process(false)


func configure(sprite: AnimatedSprite2D) -> void:
	_sprite = sprite
	if _shader == null:
		_shader = Shader.new()
		_shader.code = "shader_type canvas_item; uniform float flash = 0.0; varying vec4 tint; void vertex() { tint = COLOR; } void fragment() { vec4 c = texture(TEXTURE, UV) * tint; c.rgb = mix(c.rgb, vec3(1.0, 0.98, 0.88), flash); COLOR = c; }"
	_material = ShaderMaterial.new()
	_material.shader = _shader


func trigger(contact: Vector2, direction: Vector2, heavy: bool, effective: bool) -> void:
	var now := Time.get_ticks_usec()
	if now - _started_usec < int(RETRIGGER_GAP * 1000000.0):
		return
	if not active:
		_previous_material = _sprite.material
	_sprite.material = _material
	_material.set_shader_parameter("flash", 0.88)
	position = contact.round()
	rotation = direction.angle()
	_heavy = heavy
	_effective = effective
	_started_usec = now
	_progress = 0.0
	active = true
	visible = true
	set_process(true)
	queue_redraw()


func _process(_delta: float) -> void:
	if get_tree().paused or not is_instance_valid(_sprite):
		clear()
		return
	var elapsed := (Time.get_ticks_usec() - _started_usec) / 1000000.0
	if elapsed >= BURST_TIME:
		clear()
		return
	_progress = elapsed / BURST_TIME
	_material.set_shader_parameter("flash", 0.88 * maxf(0.0, 1.0 - elapsed / FLASH_TIME))
	queue_redraw()


func clear() -> void:
	if is_instance_valid(_sprite) and _sprite.material == _material:
		_sprite.material = _previous_material
	active = false
	visible = false
	set_process(false)
	queue_redraw()


func _draw() -> void:
	if not active:
		return
	var radius := (20.0 if _heavy else 14.0) * (0.65 + 0.6 * _progress)
	var color := Color(1.0, 0.81, 0.28, 1.0 - _progress)
	if _effective:
		color = Color(0.62, 0.88, 1.0, 1.0 - _progress)
	# 四枚尖角使用整像素几何；中心留空，不以大光球遮住武器和敌人轮廓。
	for i in 4:
		var ray := Vector2.RIGHT.rotated(i * PI / 2.0 + 0.22)
		var side := ray.orthogonal() * (2.0 if _heavy else 1.5)
		var start := ray * radius * 0.22
		var middle := ray * radius * 0.5
		draw_colored_polygon(PackedVector2Array([start.round(),
			(middle + side).round(), (ray * radius).round(), (middle - side).round()]), color)
	if _progress < 0.45:
		draw_rect(Rect2(-2, -2, 4, 4), Color(1.0, 0.98, 0.84, 1.0 - _progress))
