## Reading controls use the same independent/cancelable touch capture as combat,
## but remain usable while the world is paused. No canceled touch can commit.
extends "res://scripts/ui/mobile_action_button.gd"

func _allowed() -> bool:
	return not disabled and is_visible_in_tree() \
		and (not input_allowed.is_valid() or input_allowed.call())

func _input(event: InputEvent) -> void:
	# A disabled fresh-gesture gate must also block BaseButton's native mouse
	# emulation path; otherwise an ignored touch can turn into a GUI click.
	if is_visible_in_tree() and not _allowed():
		var blocked_pointer := (event is InputEventScreenTouch or event is InputEventMouseButton) \
			and get_global_rect().has_point(event.position)
		var blocked_key := event is InputEventKey and has_focus() and event.is_action("ui_accept")
		if blocked_pointer or blocked_key:
			cancel_touch()
			get_viewport().set_input_as_handled()
			return
	super._input(event)
