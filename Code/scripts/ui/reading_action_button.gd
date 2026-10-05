## Reading controls use the same independent/cancelable touch capture as combat,
## but remain usable while the world is paused. No canceled touch can commit.
extends "res://scripts/ui/mobile_action_button.gd"

func _allowed() -> bool:
	return not disabled and is_visible_in_tree() \
		and (not input_allowed.is_valid() or input_allowed.call())

## 不可选的长方案也可作为滚动起点，但门禁未释放时仍不得捕获。
func _touch_allowed() -> bool:
	return _allowed() or (disabled and is_visible_in_tree() and _scroll_container() != null \
		and (not input_allowed.is_valid() or input_allowed.call()))

func _input(event: InputEvent) -> void:
	# A disabled fresh-gesture gate must also block BaseButton's native mouse
	# emulation path; otherwise an ignored touch can turn into a GUI click.
	if is_visible_in_tree() and not _touch_allowed():
		var blocked_pointer := (event is InputEventScreenTouch or event is InputEventMouseButton) \
			and _hit_test(event.position)
		var blocked_key := event is InputEventKey and has_focus() and event.is_action("ui_accept")
		if blocked_pointer or blocked_key:
			cancel_touch()
			get_viewport().set_input_as_handled()
			return
	super._input(event)
