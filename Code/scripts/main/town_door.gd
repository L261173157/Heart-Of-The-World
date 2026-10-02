## 明确交互的门：可见门框 + 前方入口区；只踩上绝不自动传送。
## 门与 NPC 共用攻击键/触屏交互通道，前后边界由真实 Area2D 判断。
class_name TownDoor
extends Node2D

var title := "旅舍"
var is_exit := false
var destination := Vector2.ZERO
var travel: Callable
var _players: Array[Node2D] = []
var _prompt: Label
var _entry: Area2D


func _ready() -> void:
	add_to_group("npcs")
	add_to_group("town_doors")
	_entry = Area2D.new()
	_entry.name = "EntryArea"
	_entry.collision_layer = 0
	_entry.collision_mask = 1
	_entry.monitorable = false
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(84, 68)
	shape.shape = rect
	shape.position = Vector2(0, -24 if is_exit else 24)
	_entry.add_child(shape)
	_entry.body_entered.connect(func(body: Node2D) -> void:
		if body.is_in_group("player") and not _players.has(body):
			_players.append(body)
			_refresh_prompt())
	_entry.body_exited.connect(func(body: Node2D) -> void:
		_players.erase(body)
		_refresh_prompt())
	add_child(_entry)
	_prompt = Label.new()
	_prompt.name = "DoorPrompt"
	_prompt.position = Vector2(-100, -64 if is_exit else -166)
	_prompt.size = Vector2(200, 28)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 20)
	_prompt.add_theme_color_override("font_color", Color("ffe0a0"))
	_prompt.add_theme_color_override("font_outline_color", Color("241d1b"))
	_prompt.add_theme_constant_override("outline_size", 5)
	_prompt.z_index = 8
	add_child(_prompt)
	_refresh_prompt()


func can_interact() -> bool:
	for player in _players:
		if is_instance_valid(player) and player.visible and player.global_position.distance_to(global_position) <= 86.0:
			return true
	return false


func interact() -> void:
	if not can_interact() or not travel.is_valid():
		return
	for player in _players:
		if is_instance_valid(player) and player.is_in_group("player"):
			travel.call(player, destination)
			return


func _refresh_prompt() -> void:
	if _prompt == null:
		return
	_prompt.text = ("出门 · 攻击键" if is_exit else "进入%s · 攻击键" % title) if can_interact() else ("出口" if is_exit else title)
	queue_redraw()


func _draw() -> void:
	# 屋外沿用 Tiny Swords 房屋自己的弧形蓝门，不再外挂黑色矩形门扇。
	# 短石阶紧贴原图底边；室内用同色木框/竖板门，明确落在南墙上。
	if is_exit:
		draw_rect(Rect2(-21, -33, 42, 35), Color("493d39"))
		draw_rect(Rect2(-17, -31, 34, 31), Color("9b7350"))
		for x in [-13, -5, 3, 11]:
			draw_rect(Rect2(x, -29, 6, 28), Color("73503e"))
		draw_rect(Rect2(-20, -35, 40, 5), Color("c49b67"))
		draw_rect(Rect2(-15, -11, 30, 3), Color("4d4843"))
		draw_rect(Rect2(9, -17, 3, 3), Color("e7c789"))
	var y := -7.0 if is_exit else -12.0
	draw_rect(Rect2(-24, y, 48, 9), Color("655c50"))
	draw_rect(Rect2(-21, y, 42, 6), Color("b3a080"))
	draw_line(Vector2(-4, y), Vector2(-4, y + 6), Color("756a59"), 2.0)
	if can_interact():
		draw_arc(Vector2(0, y + 8), 29, 0.0, PI, 16, Color(1.0, 0.85, 0.5, 0.9), 2.0)
