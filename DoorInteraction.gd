extends Node

var is_open: bool = false
var original_rotation: Vector3
var target_rotation: Vector3

func _ready():
	# Store initial rotation
	original_rotation = get_parent().rotation_degrees
	# Open door by rotating it inwards/outwards
	target_rotation = original_rotation + Vector3(0, 85, 0)
	
	print("[DoorLogic] Door initialized at: ", get_parent().get_path())

func toggle_door():
	is_open = !is_open
	var target = target_rotation if is_open else original_rotation
	
	print("[DoorLogic] Toggling door. Open: ", is_open)
	
	var tw = get_tree().create_tween()
	tw.tween_property(get_parent(), "rotation_degrees:y", target.y, 1.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	
	# Play a simple sound if manager available
	var sfx = get_tree().root.find_child("SesYoneticisi", true, false)
	if sfx and sfx.has_method("play_place_block"):
		sfx.play_place_block()
