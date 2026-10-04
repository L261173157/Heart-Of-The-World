## A newly opened reading surface never inherits the gesture that opened it.
## This observer is added after the controls so it sees raw input first.
extends Node

var held: Dictionary = {}
var armed := true
var _ready_for_new_press := false

func _input(event: InputEvent) -> void:
	var key := ""
	var down := false
	if event is InputEventScreenTouch:
		key = "touch:%d" % event.index
		down = event.pressed and not event.canceled
	elif event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
		key = "mouse:%d" % event.button_index
		down = event.pressed
	elif event is InputEventKey and not event.echo:
		key = "key:%d" % event.physical_keycode
		down = event.pressed
	if key.is_empty():
		return
	if down:
		# Only a new press after every opening touch/key has lifted can arm.
		# This avoids both release-frame acceptance and an arbitrary frame delay.
		if not armed and _ready_for_new_press and held.is_empty():
			armed = true
			_ready_for_new_press = false
		held[key] = true
	else:
		held.erase(key)
		if not armed and held.is_empty():
			_ready_for_new_press = true

func require_release() -> void:
	armed = false
	_ready_for_new_press = held.is_empty()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		held.clear()
		require_release()
