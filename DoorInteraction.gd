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
	
	# Hide mouse cursor for cinematic
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	
	# Rotate Target Node
	var node_to_rotate = get_meta("target_node") if has_meta("target_node") else get_parent()
	if node_to_rotate:
		var tw = get_tree().create_tween()
		tw.tween_property(node_to_rotate, "rotation_degrees:y", target.y, 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	
	# Hide instruction label
	var manager = get_tree().get_first_node_in_group("oyun_yoneticisi")
	if manager and manager.has_method("_show_escape_instruction"):
		# We can call with empty string or just hide the label if we know its path
		var label = get_tree().root.find_child("EscapeInstruction", true, false)
		if label: label.visible = false
		
		# Also hide interaction prompt (Open the door E)
		var int_label = get_tree().root.find_child("InteractLabel", true, false)
		if int_label: int_label.visible = false
	
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
	
	# After fade, wait 2 seconds then start final sequence
	await tw.finished
	_start_demo_end_sequence()

func _start_demo_end_sequence():
	# 1. Wait 2 seconds in total darkness
	await get_tree().create_timer(2.0).timeout
	
	# 2. Setup final elements
	var poster = get_tree().root.find_child("poster8", true, false)
	if poster: 
		poster.visible = true
		# Ensure poster is drawn on top of EVERYTHING (including pieces/king)
		var manager = get_tree().get_first_node_in_group("oyun_yoneticisi")
		if manager and manager.has_method("set_piece_render_priority"):
			manager.set_piece_render_priority(poster, 127, true)
	
	var final_cam = get_tree().root.find_child("DemoSonuCam", true, false)
	if final_cam:
		final_cam.rotation_degrees = Vector3(0, -116, 0)
		final_cam.current = true
	
	# 3. Remove the old fade overlay to show the new camera view
	var old_fade = get_tree().root.find_child("PixelFade", true, false)
	if old_fade:
		old_fade.queue_free()
	
	# 4. Start Camera Animation
	if final_cam:
		# Rotation sequence (Slower: 2.5s each)
		var rot_tw = get_tree().create_tween()
		rot_tw.tween_property(final_cam, "rotation_degrees", Vector3(-63, -170, 0), 2.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		rot_tw.tween_property(final_cam, "rotation_degrees", Vector3(-35.7, -180, 0), 2.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		
		await rot_tw.finished
		
		# Parallel 2: FOV zoom (slowly after rotation is done)
		var fov_tw = get_tree().create_tween()
		fov_tw.tween_property(final_cam, "fov", 25.0, 5.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		
		await fov_tw.finished
		
		# 5. Wait 4 more seconds then Cut to Black
		await get_tree().create_timer(4.0).timeout
		_instant_black_cut()

func _instant_black_cut():
	# Create a simple black overlay instantly
	var canvas = CanvasLayer.new()
	canvas.layer = 100
	get_tree().root.add_child(canvas)
	
	var rect = ColorRect.new()
	rect.color = Color.BLACK
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(rect)
	
	print("DEMO END - FINAL CUT")

func toggle_door():
	# Legacy method if needed, but we use interact() now
	is_open = !is_open
	var target = target_rotation if is_open else original_rotation
	var tw = get_tree().create_tween()
	tw.tween_property(get_parent(), "rotation_degrees:y", target.y, 1.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
