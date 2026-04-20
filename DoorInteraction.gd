extends Node

var is_open: bool = false
var original_rotation: Vector3
var target_rotation: Vector3

var is_escape_ready: bool = false

func _ready():
	# Use target_node meta if provided, otherwise fallback to parent
	var target = get_meta("target_node") if has_meta("target_node") else get_parent()
	if target:
		original_rotation = target.rotation_degrees
		target_rotation = original_rotation + Vector3(0, 85, 0)
	
	# print("[DoorLogic] Door initialized at: ", get_parent().get_path())

func enable_escape():
	is_escape_ready = true
	print("[DoorLogic] Escape route is now ready!")

func interact():
	if not is_escape_ready:
		return
		
	if is_open: return # Already opened escape
	
	is_open = true
	var target = target_rotation
	
	# Play opening sound
	var sfx = get_tree().root.find_child("SesYoneticisi", true, false)
	if sfx and sfx.has_method("play_place_block"): # Or a door sound if exists
		sfx.play_place_block()
	
	# Rotate Target Node
	var node_to_rotate = get_meta("target_node") if has_meta("target_node") else get_parent()
	if node_to_rotate:
		var tw = get_tree().create_tween()
		tw.tween_property(node_to_rotate, "rotation_degrees:y", target.y, 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	
	# Screen Fade Out
	_trigger_screen_fade()

func _trigger_screen_fade():
	var fade_scene = load("res://PixelFade.tscn")
	if not fade_scene: return
	
	var fade = fade_scene.instantiate()
	get_tree().root.add_child(fade)
	
	var rect = fade.get_node("ColorRect")
	var mat = rect.material as ShaderMaterial
	
	# Shader logic: progress=1.0 is visible, progress=0.0 is black
	mat.set_shader_parameter("progress", 1.0)
	
	var tw = get_tree().create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS) # Ensure it runs even if game pauses
	tw.tween_property(mat, "shader_parameter/progress", 0.0, 1.5)
	
	# After fade, maybe show a "To be continued" or just end
	await tw.finished
	print("Game Ends - Demo Finished")

func toggle_door():
	# Legacy method if needed, but we use interact() now
	is_open = !is_open
	var target = target_rotation if is_open else original_rotation
	var tw = get_tree().create_tween()
	tw.tween_property(get_parent(), "rotation_degrees:y", target.y, 1.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
