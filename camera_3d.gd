extends Camera3D

@export var sensitivity: float = 0.08
@export var limit_y: float = 100.0  # Horizontal (Left/Right)
@export var limit_x: float = 75.0  # Vertical (Up/Down)

var yaw: float = 0.0
var pitch: float = 0.0
var start_y: float = 0.0
var start_x: float = 0.0
var is_locked: bool = false
enum PlayerState {SEATED, STANDING, TRANSITIONING}
var current_state: PlayerState = PlayerState.SEATED
var is_game_over: bool = false
var seated_position: Vector3
var seated_body_position: Vector3
var seated_rotation: Vector3
var walk_speed: float = 2.0
var head_bob_frequency: float = 12.0
var head_bob_amplitude: float = 0.05
var head_bob_time: float = 0.0
var interact_label: Label = null

var ray_length: float = 10.0

# Shake Params
var shake_intensity: float = 0.0
var shake_duration: float = 0.0
var shake_offset: Vector3 = Vector3.ZERO

var held_piece: Node3D = null
var held_piece_scene: String = ""
var last_highlighted_cell: GridHucre = null

func _ready():
	# Capture mouse (HIDE)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if OS.get_name() == "Linux":
		Input.mouse_mode = Input.MOUSE_MODE_CONFINED
	
	# Find table and center view
	var grid = get_tree().root.find_child("GridManager", true, false)
	if grid:
		look_at(grid.global_position)
		start_y = rotation_degrees.y
		start_x = rotation_degrees.x
		yaw = start_y
		pitch = start_x
	else:
		yaw = rotation_degrees.y
		pitch = rotation_degrees.x
		start_y = yaw
		start_x = pitch
	
	seated_position = position
	seated_body_position = get_parent().global_position
	seated_rotation = rotation_degrees
	setup_chair_interaction()
	
	# Reset state if reloaded
	Engine.time_scale = 1.0
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func setup_chair_interaction():
	var chair = get_tree().root.find_child("chair", true, false)
	if chair:
		var sb = StaticBody3D.new()
		sb.set_meta("is_chair", true)
		var cs = CollisionShape3D.new()
		var box = BoxShape3D.new()
		# Chair is scaled 0.08, so a (5,10,5) local box is roughly (0.4, 0.8, 0.4) world size
		box.size = Vector3(5, 10, 5)
		cs.shape = box
		sb.add_child(cs)
		chair.add_child(sb)
		
	# Create interaction label
	var control = get_tree().root.find_child("Control", true, false)
	if control:
		interact_label = Label.new()
		interact_label.name = "InteractLabel"
		interact_label.text = "Sit Down (E)"
		interact_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		interact_label.set_anchors_preset(Control.PRESET_CENTER)
		interact_label.position.y += 100
		interact_label.visible = false
		control.add_child(interact_label)

func stand_up():
	if current_state != PlayerState.SEATED: return
	
	current_state = PlayerState.TRANSITIONING
	is_locked = true
	
	var tw = create_tween().set_parallel(true)
	# Camera goes up slightly
	var target_pos = Vector3(position.x, position.y + 0.3, position.z)
	tw.tween_property(self, "position", target_pos, 1.0).set_trans(Tween.TRANS_SINE)
	
	tw.set_parallel(false)
	tw.tween_callback(func():
		current_state = PlayerState.STANDING
		is_locked = false
		print("PLAYER STANDING")
	)

func sit_down():
	if current_state != PlayerState.STANDING: return
	
	if interact_label: interact_label.visible = false
	current_state = PlayerState.TRANSITIONING
	is_locked = true
	
	var tw = create_tween().set_parallel(true)
	tw.tween_property(self, "position", seated_position, 1.0).set_trans(Tween.TRANS_SINE)
	tw.tween_property(self, "rotation_degrees", seated_rotation, 1.0).set_trans(Tween.TRANS_SINE)
	tw.tween_property(get_parent(), "global_position", seated_body_position, 1.0).set_trans(Tween.TRANS_SINE)
	
	tw.set_parallel(false)
	tw.tween_callback(func():
		current_state = PlayerState.SEATED
		is_locked = false
		# Reset rotation params to current rotation
		yaw = rotation_degrees.y
		pitch = rotation_degrees.x
		print("PLAYER SEATED")
	)

func _input(event):
	if is_game_over: return
	
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if held_piece:
			place_held_piece()
		else:
			interact_with_crosshair()
	
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_G: # 'G' tuşu ile kutuyu açalım (Test için)
			var manager = get_tree().get_first_node_in_group("oyun_yoneticisi")
			if manager: 
				manager.start_chest_sequence()
			else:
				print("OyunYoneticisi bulunamadı!")

	if is_locked: return
	if event is InputEventMouseMotion:
		# Only rotate if the mouse is captured
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			return
			
		# Convert mouse motion to rotation
		yaw -= event.relative.x * sensitivity
		pitch -= event.relative.y * sensitivity
		
		# Limits (RELATIVE TO START ANGLES)
		if current_state == PlayerState.SEATED:
			yaw = clamp(yaw, start_y - limit_y, start_y + limit_y)
			pitch = clamp(pitch, start_x - limit_x, start_x + limit_x)
		else:
			# Standing: Full 360 yaw, but still limit pitch to avoid flipping over
			pitch = clamp(pitch, -85, 85)

	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_E:
			if current_state == PlayerState.STANDING and interact_label.visible:
				sit_down()

func _process(_delta):
	if is_locked: return
	
	# Shake logic
	if shake_duration > 0:
		shake_duration -= _delta
		# Linear decay
		var current_intensity = shake_intensity * (shake_duration / 0.5) 
		shake_offset = Vector3(
			randf_range(-1, 1) * current_intensity,
			randf_range(-1, 1) * current_intensity,
			randf_range(-1, 1) * current_intensity * 2.0
		)
	else:
		shake_offset = shake_offset.lerp(Vector3.ZERO, _delta * 10.0)

	# Breathing effect
	var t = Time.get_ticks_msec() * 0.001
	var breath_yaw = sin(t * 1.1) * 0.12
	var breath_pitch = cos(t * 0.8) * 0.15
	var breath_roll = sin(t * 0.5) * 0.08
	
	rotation_degrees.y = yaw + breath_yaw + (shake_offset.x * 2.0)
	rotation_degrees.x = pitch + breath_pitch + (shake_offset.y * 2.0)
	rotation_degrees.z = breath_roll + (shake_offset.z * 5.0)
	
	if current_state == PlayerState.STANDING:
		_process_chair_interaction()
	
	if held_piece:
		_process_placement_preview()

func _physics_process(_delta):
	if current_state == PlayerState.STANDING:
		_process_movement(_delta)

func _process_movement(_delta):
	var body = get_parent() as CharacterBody3D
	if not body: return
	
	var input_dir = Vector2.ZERO
	if Input.is_key_pressed(KEY_W): input_dir.y -= 1
	if Input.is_key_pressed(KEY_S): input_dir.y += 1
	if Input.is_key_pressed(KEY_A): input_dir.x -= 1
	if Input.is_key_pressed(KEY_D): input_dir.x += 1
	input_dir = input_dir.normalized()
	
	# Move relative to camera looking direction! (Zero out Y to stay on ground)
	var forward = -global_transform.basis.z
	var right = global_transform.basis.x
	forward.y = 0
	right.y = 0
	forward = forward.normalized()
	right = right.normalized()
	
	var move_dir = (forward * -input_dir.y + right * input_dir.x).normalized()
	
	if move_dir:
		body.velocity = move_dir * walk_speed
		# Head Bobbing
		head_bob_time += _delta * head_bob_frequency
		var bob = sin(head_bob_time) * head_bob_amplitude
		position.y = lerp(position.y, seated_position.y + 0.3 + bob, _delta * 10.0)
	else:
		body.velocity = body.velocity.lerp(Vector3.ZERO, _delta * 10.0)
		# Smooth bob reset
		position.y = lerp(position.y, seated_position.y + 0.3, _delta * 5.0)
	
	body.move_and_slide()

func _process_chair_interaction():
	if not interact_label: return
	
	var space_state = get_world_3d().direct_space_state
	var v_size = get_viewport().get_visible_rect().size
	var center = v_size / 2.0
	var origin = project_ray_origin(center)
	var end = origin + project_ray_normal(center) * 2.0 # Close range interaction
	var query = PhysicsRayQueryParameters3D.create(origin, end)
	var result = space_state.intersect_ray(query)
	
	if result and result.collider.has_meta("is_chair"):
		interact_label.visible = true
	else:
		interact_label.visible = false

func interact_with_crosshair():
	var space_state = get_world_3d().direct_space_state
	var v_size = get_viewport().get_visible_rect().size
	var center = v_size / 2.0
	var origin = project_ray_origin(center)
	var end = origin + project_ray_normal(center) * ray_length
	var query = PhysicsRayQueryParameters3D.create(origin, end)
	var result = space_state.intersect_ray(query)
	
	if result:
		var collider = result.collider
		if collider.has_meta("is_chair"):
			sit_down()
		elif is_node_part_of_box(collider):
			print("Kutu tıklandı: ", collider.name)
			var manager = get_tree().get_first_node_in_group("oyun_yoneticisi")
			if manager: 
				manager.start_chest_sequence()
			else:
				print("OyunYoneticisi bulunamadı!")
		else:
			print("Tıklanan obje: ", collider.name)
		
		if collider.has_meta("is_grid_cell"):
			var hucre = collider.get_meta("grid_cell_node")
			if hucre.mevcut_tas:
				print("Taş seçildi: %s (%s, %d, %d)" % [hucre.mevcut_tas.name, "Beyaz" if hucre.mevcut_tas.get("renk") == 0 else "Siyah", hucre.sutun, hucre.satir])
			else:
				print("Boş hücre: (%d, %d)" % [hucre.sutun, hucre.satir])

func pick_up_piece(piece: Node3D, scene_path: String):
	held_piece = piece
	held_piece_scene = scene_path
	# Taşı kameraya "bağlayalım" (görsel olarak)
	held_piece.reparent(self)
	held_piece.position = Vector3(0.5, -0.4, -1.0) # Sağ alt köşe
	held_piece.rotation = Vector3.ZERO

func _process_placement_preview():
	var space_state = get_world_3d().direct_space_state
	var v_size = get_viewport().get_visible_rect().size
	var center = v_size / 2.0
	var origin = project_ray_origin(center)
	var end = origin + project_ray_normal(center) * ray_length
	var query = PhysicsRayQueryParameters3D.create(origin, end)
	var result = space_state.intersect_ray(query)
	
	if last_highlighted_cell:
		last_highlighted_cell.set_highlight(false)
		last_highlighted_cell.set_preview_piece("")
		last_highlighted_cell = null
		
	if result:
		var collider = result.collider
		if collider.has_meta("is_grid_cell"):
			var hucre = collider.get_meta("grid_cell_node")
			if not hucre.mevcut_tas:
				hucre.set_highlight(true, Color(0, 1, 0, 0.4)) # Yeşil önizleme
				hucre.set_preview_piece(held_piece_scene)
				last_highlighted_cell = hucre

func is_node_part_of_box(node: Node) -> bool:
	var current = node
	while current and current != get_tree().root:
		if "box" in current.name.to_lower():
			return true
		current = current.get_parent()
	return false

func place_held_piece():
	if not last_highlighted_cell: return
	
	var target_hucre = last_highlighted_cell
	var target_pos = target_hucre.global_position
	
	# Taşı grid'e taşıyalım
	held_piece.reparent(get_tree().root)
	
	var tween = create_tween()
	tween.tween_property(held_piece, "global_position", target_pos, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(held_piece, "scale", Vector3(1, 1, 1), 0.5)
	
	target_hucre.mevcut_tas = held_piece
	held_piece = null
	held_piece_scene = ""
	
	# Hücredeki önizlemeyi temizle
	target_hucre.set_preview_piece("")
	target_hucre.set_highlight(false)
	last_highlighted_cell = null
	
	print("Taş yerleştirildi.")

func apply_shake(intensity: float, duration: float):
	shake_intensity = intensity
	shake_duration = duration

func reset_rotation():
	yaw = start_y
	pitch = start_x
	rotation_degrees.y = yaw
	rotation_degrees.x = pitch
	# Warp mouse to center to sync with reset yaw/pitch
	Input.warp_mouse(get_viewport().get_visible_rect().size / 2.0)
	is_locked = false
