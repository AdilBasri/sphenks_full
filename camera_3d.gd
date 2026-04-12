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
@onready var crosshair_ui: TextureRect = get_tree().root.find_child("Crosshair", true, false)
@onready var camera2: Camera3D = get_parent().get_node("Camera3D2") if get_parent().has_node("Camera3D2") else null
var piece_name_label: Label = null
var cursor_3d_pos: Vector3 = Vector3.ZERO

var is_zoomed_view: bool = false
var is_transitioning_view: bool = false

# Shake Params
var shake_intensity: float = 0.0
var shake_duration: float = 0.0
var shake_offset: Vector3 = Vector3.ZERO

var held_piece: Node3D = null
var held_piece_scene: String = ""
var last_highlighted_cell: GridHucre = null
var selected_hucre: GridHucre = null
var move_highlights: Array[GridHucre] = []
var is_placing_piece: bool = false
var is_upgrade_mode: bool = false
var upgrade_manager: Node = null
var hovered_upgrade_piece: Node3D = null
var blood_puke_scene = preload("res://BloodPuke.tscn")
var is_receiving_piece: bool = false

func _ready():
	# Capture mouse (HIDE)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if current_state == PlayerState.SEATED:
		Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN # Hide OS cursor, keep free movement
	elif OS.get_name() == "Linux":
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
	
	seated_position = Vector3(0, -0.313, 2.085)
	seated_rotation = Vector3(-17.6, 0, 0)
	seated_body_position = get_parent().global_position
	setup_chair_interaction()
	
	# Connect to InspectUI signals
	var ui = get_node_or_null("/root/InspectUI")
	if ui:
		ui.dismissed.connect(_on_inspect_dismissed)
	
	# Reset state if reloaded
	Engine.time_scale = 1.0
	# The initial mouse mode is handled above in the current_state check
	
	# Instantiate Upgrade Manager
	var upgrade_script = load("res://Scripts/PieceUpgradeManager.gd")
	if upgrade_script:
		upgrade_manager = Node.new()
		upgrade_manager.set_script(upgrade_script)
		add_child(upgrade_manager)

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
		
		# Create Piece Info Label
		piece_name_label = Label.new()
		piece_name_label.name = "PieceInfoLabel"
		var settings = LabelSettings.new()
		settings.font = load("res://Assets/fonts/Golden Horse.ttf")
		settings.font_size = 28
		settings.font_color = Color.WHITE
		settings.outline_size = 8
		settings.outline_color = Color.BLACK
		piece_name_label.label_settings = settings
		piece_name_label.visible = false
		control.add_child(piece_name_label)

func stand_up():
	if current_state != PlayerState.SEATED: return
	
	current_state = PlayerState.TRANSITIONING
	is_locked = true
	
	var tw = create_tween()
	
	# 1. Aşama: Masaya doğru hafifçe eğilme (Lean In)
	tw.set_parallel(true)
	tw.tween_property(self, "position:z", 1.8, 0.4).set_trans(Tween.TRANS_SINE)
	tw.tween_property(self, "rotation_degrees:x", -30.0, 0.4).set_trans(Tween.TRANS_SINE)
	
	tw.set_parallel(false) # Sıralı devam et
	tw.tween_interval(0.1) # Kısa bir duraksama
	
	# 2. Aşama: Doğrulma ve Geri Çekilme (Push Back & Rise)
	tw.set_parallel(true)
	# Gövdeyi geriye çekelim
	var target_body_pos = get_parent().global_position + get_parent().global_transform.basis.z * 1.0
	tw.tween_property(get_parent(), "global_position", target_body_pos, 0.8).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	# Kamerayı yukarı kaldırıp düzeltelim
	tw.tween_property(self, "position:y", seated_position.y + 0.3, 0.8).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "rotation_degrees:x", 0.0, 0.8).set_trans(Tween.TRANS_SINE)
	
	await tw.finished
	
	current_state = PlayerState.STANDING
	is_locked = false
	is_zoomed_view = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Bakış yönünü mevcut rotasyona kilitleyelim
	yaw = rotation_degrees.y
	pitch = rotation_degrees.x
	print("PLAYER STANDING")

func sit_down():
	if is_game_over:
		print("Oyun bittiği için baştan yükleniyor...")
		Engine.time_scale = 1.0
		get_tree().reload_current_scene()
		return
		
	if current_state != PlayerState.STANDING: return
	
	if interact_label: interact_label.visible = false
	current_state = PlayerState.TRANSITIONING
	is_locked = true
	
	var tw = create_tween().set_parallel(true)
	tw.tween_property(self, "position", seated_position, 1.0).set_trans(Tween.TRANS_SINE)
	tw.tween_property(self, "rotation_degrees", seated_rotation, 1.0).set_trans(Tween.TRANS_SINE)
	tw.tween_property(get_parent(), "global_position", seated_body_position, 1.0).set_trans(Tween.TRANS_SINE)
	
	await tw.finished
	
	current_state = PlayerState.SEATED
	is_locked = false
	Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN # Hide OS cursor
	# Reset rotation params to current rotation
	yaw = rotation_degrees.y
	pitch = rotation_degrees.x
	print("PLAYER SEATED")

func _input(event):
	if is_receiving_piece: return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if is_game_over and current_state == PlayerState.SEATED: return
		if event.double_click:
			_handle_double_click()
		else:
			if held_piece:
				place_held_piece()
			else:
				if is_upgrade_mode:
					_handle_upgrade_click()
				else:
					interact_with_crosshair()
	
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if is_game_over: return
		# Deselect on right click
		if held_piece:
			SesYoneticisi.play_error()
		_clear_selection()
	
	if event is InputEventKey and event.pressed:
		# Camera Switching Logic (W to Zoom, S to Back)
		if current_state == PlayerState.SEATED and not is_transitioning_view:
			if event.keycode == KEY_W and not is_zoomed_view:
				_transition_to_board_view()
			elif event.keycode == KEY_S and is_zoomed_view:
				_transition_to_seated_view()
				
		if event.keycode == KEY_C and current_state == PlayerState.SEATED and not is_transitioning_view:
			stand_up()

	if is_locked: return
	if event is InputEventMouseMotion:
		# Only rotate if the mouse is captured
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			return
			
		# Convert mouse motion to rotation
		if current_state != PlayerState.SEATED:
			yaw -= event.relative.x * sensitivity
			pitch -= event.relative.y * sensitivity
			
			# Limits (RELATIVE TO START ANGLES)
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
	
	if current_state == PlayerState.SEATED:
		if not is_transitioning_view:
			if is_zoomed_view and camera2:
				position = camera2.position
				rotation_degrees = camera2.rotation_degrees
			else:
				rotation_degrees.y = seated_rotation.y
				rotation_degrees.x = seated_rotation.x
				rotation_degrees.z = seated_rotation.z
	elif not is_upgrade_mode:
		rotation_degrees.y = yaw + breath_yaw + (shake_offset.x * 2.0)
		rotation_degrees.x = pitch + breath_pitch + (shake_offset.y * 2.0)
		rotation_degrees.z = breath_roll + (shake_offset.z * 5.0)
	
	if current_state == PlayerState.STANDING:
		_process_chair_interaction()
	
	# Update Crosshair Position
	_update_crosshair_position()
	_update_piece_hover_info()
	if is_upgrade_mode:
		_process_upgrade_interaction()

func _update_piece_hover_info():
	if not piece_name_label: return
	
	var space_state = get_world_3d().direct_space_state
	var v_size = get_viewport().get_visible_rect().size
	var crosshair_pos = get_viewport().get_mouse_position() if (current_state == PlayerState.SEATED or is_upgrade_mode) else v_size / 2.0
	var origin = project_ray_origin(crosshair_pos)
	var end = origin + project_ray_normal(crosshair_pos) * ray_length
	var query = PhysicsRayQueryParameters3D.create(origin, end)
	var result = space_state.intersect_ray(query)
	
	if result:
		var collider = result.collider
		var target_piece: Node3D = null
		
		# Check grid pieces
		if collider.has_meta("is_grid_cell"):
			var hucre = collider.get_meta("grid_cell_node")
			if hucre and hucre.mevcut_tas:
				target_piece = hucre.mevcut_tas
		# Check drafted/upgrade pieces (look at collider directly first, then parent)
		elif collider.has_meta("is_upgrade_choice"):
			target_piece = collider
		elif collider.get_parent() and collider.get_parent().has_meta("is_upgrade_choice"):
			target_piece = collider.get_parent()
			
		if target_piece:
			var path = target_piece.get_meta("scene_path") if target_piece.has_meta("scene_path") else ""
			if path != "":
				var display_name = PieceDatabase.get_piece_display_name(path)
				piece_name_label.text = display_name
				piece_name_label.global_position = crosshair_pos + Vector2(20, -20)
				piece_name_label.visible = true
				cursor_3d_pos = result.position
				return
				
	# If no piece is hit OR piece has no path, hide the label
	piece_name_label.visible = false
	
	# Update cursor_3d_pos even if not over a piece (for head tracking)
	if result:
		cursor_3d_pos = result.position
	else:
		# Fallback: Look at player's general area
		cursor_3d_pos = global_position

func _update_crosshair_position():
	if not crosshair_ui: return
	
	if current_state == PlayerState.SEATED:
		# Follow mouse
		crosshair_ui.global_position = get_viewport().get_mouse_position() - (crosshair_ui.size / 2.0)
	else:
		# Center screen
		var v_size = get_viewport().get_visible_rect().size
		crosshair_ui.global_position = (v_size / 2.0) - (crosshair_ui.size / 2.0)
	
	if held_piece:
		_process_placement_preview()

func _physics_process(_delta):
	if current_state == PlayerState.STANDING and not is_upgrade_mode:
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
	
	SesYoneticisi.set_walking(move_dir != Vector3.ZERO)
	
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
	var crosshair_pos = get_viewport().get_mouse_position() if current_state == PlayerState.SEATED else v_size / 2.0
	var origin = project_ray_origin(crosshair_pos)
	var end = origin + project_ray_normal(crosshair_pos) * 2.0 # Close range interaction
	var query = PhysicsRayQueryParameters3D.create(origin, end)
	var result = space_state.intersect_ray(query)
	
	if result:
		if result.collider.has_meta("is_chair") or result.collider.has_meta("is_door"):
			interact_label.visible = true
		else:
			interact_label.visible = false
	else:
		interact_label.visible = false

func interact_with_crosshair():
	if is_receiving_piece: return
	
	var manager = get_tree().get_first_node_in_group("oyun_yoneticisi")
	if not manager or manager.current_turn != manager.GameTurn.PLAYER:
		print("Sıra sizde değil!")
		return
		
	var space_state = get_world_3d().direct_space_state
	var v_size = get_viewport().get_visible_rect().size
	var crosshair_pos = get_viewport().get_mouse_position() if current_state == PlayerState.SEATED else v_size / 2.0
	var origin = project_ray_origin(crosshair_pos)
	var end = origin + project_ray_normal(crosshair_pos) * ray_length
	var query = PhysicsRayQueryParameters3D.create(origin, end)
	var result = space_state.intersect_ray(query)
	
	# IF STANDING AND CLICKED GRID: Sit down first, then re-calculate
	if current_state == PlayerState.STANDING and result and result.collider.has_meta("is_grid_cell"):
		is_locked = true # Lock during transit
		await sit_down()
		# RE-CALCULATE after sitting (mouse mode might have changed)
		v_size = get_viewport().get_visible_rect().size
		crosshair_pos = get_viewport().get_mouse_position() # Now seated
		origin = project_ray_origin(crosshair_pos)
		end = origin + project_ray_normal(crosshair_pos) * ray_length
		query = PhysicsRayQueryParameters3D.create(origin, end)
		result = space_state.intersect_ray(query)

	if result:
		var collider = result.collider
		
		# Door Interaction
		if collider.has_meta("is_door"):
			var door_mesh = collider.get_parent()
			if door_mesh and door_mesh.has_meta("door_logic"):
				door_mesh.get_meta("door_logic").toggle_door()
				return
		
		if collider.has_meta("is_grid_cell"):
			var hucre = collider.get_meta("grid_cell_node")
			
			# If we clicked a move highlight
			if hucre in move_highlights:
				_execute_move(selected_hucre, hucre)
				return
				
			# If we clicked a piece
			if hucre.mevcut_tas:
				var path = hucre.mevcut_tas.get_meta("scene_path") if hucre.mevcut_tas.has_meta("scene_path") else ""
				
				# Only select player pieces (white side)
				if "white" in path.to_lower():
					if hucre.mevcut_tas.has_meta("is_immovable"):
						return
					_select_hucre(hucre)
				else:
					print("Düşman taşı seçilemez! (Path: %s)" % path)
					_clear_selection()
			else:
				_clear_selection()

func _handle_double_click():
	var space_state = get_world_3d().direct_space_state
	var crosshair_pos = get_viewport().get_mouse_position()
	var origin = project_ray_origin(crosshair_pos)
	var end = origin + project_ray_normal(crosshair_pos) * ray_length
	var query = PhysicsRayQueryParameters3D.create(origin, end)
	var result = space_state.intersect_ray(query)
	
	if result and result.collider.has_meta("is_grid_cell"):
		var hucre = result.collider.get_meta("grid_cell_node")
		if hucre.mevcut_tas:
			var path = hucre.mevcut_tas.get_meta("scene_path") if hucre.mevcut_tas.has_meta("scene_path") else ""
			if path != "" and has_node("/root/InspectUI"):
				get_node("/root/InspectUI").show_piece(path)
				get_viewport().set_input_as_handled()

func _select_hucre(hucre: GridHucre):
	if selected_hucre == hucre:
		_clear_selection()
		SesYoneticisi.play_error()
		return
		
	if selected_hucre: _clear_selection()
	
	selected_hucre = hucre
	# "Titreme" (Shake) effect
	var piece = hucre.mevcut_tas
	var tw = create_tween().set_parallel(true)
	tw.tween_property(piece, "position:y", piece.position.y + 0.1, 0.1).set_trans(Tween.TRANS_SINE)
	
	# Show highlights
	var path = piece.get_meta("scene_path")
	var attacker_stats = PieceDatabase.get_piece_stats(path)
	var valid_coords = PieceDatabase.get_valid_moves(Vector2i(hucre.sutun, hucre.satir), path)
	
	var grid = hucre.get_parent()
	for coord in valid_coords:
		if grid.hucrelerin_sozlugu.has(coord):
			var target = grid.hucrelerin_sozlugu[coord]
			move_highlights.append(target)
			
			# Highlight color: 
			# Red: Kill (Attack >= Defense)
			# Orange: Damage (Attack < Defense)
			# Green: Empty
			var color = Color(0, 1, 0, 0.4) # Soft Green for empty squares
			
			if target.mevcut_tas:
				var target_path = target.mevcut_tas.get_meta("scene_path") if target.mevcut_tas.has_meta("scene_path") else ""
				if "black" in target_path.to_lower():
					var defender_base_stats = PieceDatabase.get_piece_stats(target_path)
					var current_def = target.mevcut_tas.get_meta("current_defense") if target.mevcut_tas.has_meta("current_defense") else defender_base_stats.get("defense", 1)
					
					if attacker_stats.get("attack", 0) >= current_def:
						color = Color(1, 0.1, 0.1, 0.6) # Kill - Rich Red
					else:
						color = Color(1, 0.6, 0.0, 0.6) # Damage - Vibrant Orange
				elif "white" in target_path.to_lower():
					# Friendly piece, skip moved highlight entirely
					continue
				else:
					# Unknown/Neutral piece
					color = Color(1, 1, 0, 0.5)
					
			target.set_highlight(true, color)
	
	# Auto-transition to board view when a piece is selected
	_transition_to_board_view()

func _clear_selection():
	if selected_hucre and selected_hucre.mevcut_tas:
		var tw = create_tween()
		tw.tween_property(selected_hucre.mevcut_tas, "position:y", 0.0, 0.1).set_trans(Tween.TRANS_SINE)
		
	selected_hucre = null
	for h in move_highlights:
		h.set_highlight(false)
	move_highlights.clear()
	
	if last_highlighted_cell:
		last_highlighted_cell.set_highlight(false)
		last_highlighted_cell.set_preview_piece("")
		last_highlighted_cell = null
		
	# Auto-transition back to seated view when selection is cleared
	if is_zoomed_view:
		_transition_to_seated_view()

func _execute_move(from: GridHucre, to: GridHucre):
	var piece = from.mevcut_tas
	var path = piece.get_meta("scene_path")
	from.mevcut_tas = null
	_clear_selection()
	
	# Jump animation
	var tw = create_tween()
	var start_pos = piece.global_position
	var end_pos = to.global_position
	var mid_point = (start_pos + end_pos) / 2.0 + Vector3(0, 0.15, 0)
	
	tw.tween_property(piece, "global_position", mid_point, 0.25).set_trans(Tween.TRANS_SINE)
	tw.tween_property(piece, "global_position", end_pos, 0.25).set_trans(Tween.TRANS_SINE)
	
	await tw.finished
	
	SesYoneticisi.play_place_block()
	
	# Impact Shake
	if to.mevcut_tas:
		apply_shake(0.2, 0.3)
	
	# Combat Resolution
	if to.mevcut_tas:
		var attacker_stats = PieceDatabase.get_piece_stats(path)
		var defender = to.mevcut_tas
		var defender_path = defender.get_meta("scene_path")
		var defender_stats = PieceDatabase.get_piece_stats(defender_path)
		
		# Get or Initialize current defense
		var current_def = defender.get_meta("current_defense") if defender.has_meta("current_defense") else defender_stats["defense"]
		current_def -= attacker_stats["attack"]
		defender.set_meta("current_defense", current_def)
		
		if current_def <= 0:
			# Capture!
			_create_puff(to.global_position)
			apply_shake(0.4, 0.5) # Bigger shake on kill
			
			var is_king = defender.has_meta("is_king")
			var is_player_piece = "white" in defender_path.to_lower()
			
			defender.queue_free()
			to.mevcut_tas = piece
			piece.reparent(to)
			piece.position = Vector3.ZERO
			
			if is_king:
				if is_player_piece:
					trigger_loss()
				else:
					trigger_win()
		else:
			# Bounce back!
			var tw_back = create_tween()
			tw_back.tween_property(piece, "global_position", from.global_position, 0.3).set_trans(Tween.TRANS_BACK)
			await tw_back.finished
			from.mevcut_tas = piece
			piece.reparent(from)
			piece.position = Vector3.ZERO
	else:
		to.mevcut_tas = piece
		piece.reparent(to)
		piece.position = Vector3.ZERO
	
	# End Player Turn
	var manager = get_tree().get_first_node_in_group("oyun_yoneticisi")
	if manager: manager.next_turn()
	
	# Auto-transition back to seated view when turn ends
	_transition_to_seated_view()

func _create_puff(pos: Vector3):
	# Simple code-based puff effect using a Sphere
	var puff = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.05
	sphere.height = 0.1
	puff.mesh = sphere
	
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1, 1, 1, 0.8)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puff.material_override = mat
	
	get_tree().root.add_child(puff)
	puff.global_position = pos + Vector3(0, 0.1, 0)
	
	var tw = create_tween().set_parallel(true)
	tw.tween_property(puff, "scale", Vector3(3, 3, 3), 0.3).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.3)
	tw.chain().tween_callback(puff.queue_free)

func pick_up_piece(piece: Node3D, scene_path: String):
	held_piece = piece
	held_piece_scene = scene_path
	# Taşı kameraya "bağlayalım"
	held_piece.reparent(self)
	
	# Kullanıcının istediği "yakın ve büyük" görünüm için optimize edilmiş değerler:
	held_piece.position = Vector3(0.4, -0.4, -0.6) 
	held_piece.rotation_degrees = Vector3(3.8, 154.4, 0.8)
	held_piece.scale = Vector3(1.0, 1.0, 1.0)
	
	# UI'yı göster
	if has_node("/root/InspectUI"):
		get_node("/root/InspectUI").show_piece(scene_path)
		# Gerçek taşı gizleyelim (UI kendi kopyasını gösterecek)
		held_piece.visible = false

func _process_placement_preview():
	if is_placing_piece: return
	
	var space_state = get_world_3d().direct_space_state
	var v_size = get_viewport().get_visible_rect().size
	var crosshair_pos = get_viewport().get_mouse_position() if current_state == PlayerState.SEATED else v_size / 2.0
	var origin = project_ray_origin(crosshair_pos)
	var end = origin + project_ray_normal(crosshair_pos) * ray_length
	var query = PhysicsRayQueryParameters3D.create(origin, end)
	var result = space_state.intersect_ray(query)
	
	var current_hucre: GridHucre = null
	if result:
		var collider = result.collider
		if collider.has_meta("is_grid_cell"):
			current_hucre = collider.get_meta("grid_cell_node")
	
	# Optimization: Only update if the cell has changed
	if current_hucre != last_highlighted_cell:
		# Clear old highlight
		if last_highlighted_cell:
			last_highlighted_cell.set_highlight(false)
			last_highlighted_cell.set_preview_piece("")
		
		# Set new highlight
		last_highlighted_cell = current_hucre
		if last_highlighted_cell:
			# Check if cell is an allowed placement square
			if not last_highlighted_cell.mevcut_tas and _is_cell_valid_for_placement(last_highlighted_cell):
				last_highlighted_cell.set_highlight(true, Color(0, 1, 0, 0.4)) # Yeşil önizleme
				last_highlighted_cell.set_preview_piece(held_piece_scene)
			else:
				# Even if it's hit, if it's invalid, treat as null for next frame check
				last_highlighted_cell = null

func is_node_part_of_box(node: Node) -> bool:
	var current = node
	while current and current != get_tree().root:
		if "box" in current.name.to_lower():
			return true
		current = current.get_parent()
	return false

func place_held_piece():
	if is_receiving_piece: return
	
	if current_state == PlayerState.STANDING:
		await sit_down()
		# After sitting down, the preview might need a refresh logic but usually 
		# the player is still looking near the grid. 
		# If the last_highlighted_cell is null (common after sitting transit), we abort
		
	if not last_highlighted_cell:
		SesYoneticisi.play_error()
		return
	
	is_placing_piece = true
	var target_hucre = last_highlighted_cell
	var target_pos = target_hucre.global_position
	
	# Temizle (Önizleme taşını hemen kaldıralım ki asıl taş uçarken görsel karmaşa olmasın)
	target_hucre.set_preview_piece("")
	target_hucre.set_highlight(false)
	last_highlighted_cell = null
	
	# Taşı grid'e taşıyalım
	held_piece.reparent(get_tree().root)
	
	var tween = create_tween().set_parallel(true)
	tween.tween_property(held_piece, "global_position", target_pos, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(held_piece, "scale", Vector3(1, 1, 1), 0.5)
	tween.tween_property(held_piece, "rotation_degrees", Vector3.ZERO, 0.5)
	
	await tween.finished
	
	SesYoneticisi.play_place_block()
	
	if held_piece:
		held_piece.reparent(target_hucre)
		held_piece.position = Vector3.ZERO
	
	# Taşı yerleştirdiğimizde derinlik önceliğini sıfırlayalım (Normal görünsün)
	set_piece_render_priority(held_piece, 0, false)
	
	# Sahne yolunu saklayalım ki ilerde hover-click ile tanıyabilelim
	held_piece.set_meta("scene_path", held_piece_scene)
	
	target_hucre.mevcut_tas = held_piece
	held_piece = null
	held_piece_scene = ""
	is_placing_piece = false
	
func trigger_win():
	print("VICTORY! King defeated.")
	is_game_over = true
	# Character sound (Angry)
	SesYoneticisi.play_angry(_get_enemy_pos())
	
	# Give 1 second for the impact before sequence
	await get_tree().create_timer(1.0).timeout
	
	# Check for Puke Condition (Every 3 sections)
	var manager = get_tree().get_first_node_in_group("oyun_yoneticisi")
	if manager and manager.phase_number % 3 == 0:
		await _play_puke_sequence()
	
	if upgrade_manager and upgrade_manager.has_method("start_upgrade_sequence"):
		upgrade_manager.start_upgrade_sequence()
	else:
		# Fallback if no manager
		stand_up()
		manager = get_tree().get_first_node_in_group("oyun_yoneticisi")
		if manager: manager.cleanup_board()
	Engine.time_scale = 1.0
	
	# UI'yı gizle
	if has_node("/root/InspectUI"):
		get_node("/root/InspectUI").hide_piece()
	
	print("Taş yerleştirildi.")

func _play_puke_sequence():
	print("[Camera3D] Starting Puke Sequence...")
	var sitting_node = get_tree().get_first_node_in_group("sitting_node")
	
	if not sitting_node and owner:
		sitting_node = owner.get_node_or_null("Sitting")
	
	if not sitting_node:
		print("[Camera3D] ERROR: Sitting node NOT FOUND in group 'sitting_node' or relative to owner.")
		return
	
	print("[Camera3D] Sitting node found: ", sitting_node.get_path())
	var sitting_anim = sitting_node.find_child("AnimationPlayer", true, false)
	
	if sitting_anim:
		# FALLBACK INJECTION: Ensure 'puke' is present
		if not sitting_anim.has_animation("puke"):
			print("[Camera3D] 'puke' animation missing. Injecting now...")
			var lib: AnimationLibrary
			if sitting_anim.has_animation_library(""):
				lib = sitting_anim.get_animation_library("")
			else:
				lib = AnimationLibrary.new()
				sitting_anim.add_animation_library("", lib)
			
			var a_puke = load("res://puke.res")
			if a_puke: lib.add_animation("puke", a_puke)
	
	if sitting_anim and sitting_anim.has_animation("puke"):
		print("[Camera3D] Playing 'puke' animation.")
		sitting_anim.play("puke")
		
		# Create Bone Attachment for neck if it doesn't exist
		var skel = sitting_node.find_child("Skeleton3D", true, false)
		var puke_origin_node = sitting_node # Fallback
		
		if skel:
			var attachment = skel.find_child("PukeAttachment", true, false)
			if not attachment:
				attachment = BoneAttachment3D.new()
				attachment.name = "PukeAttachment"
				attachment.bone_name = "mixamorig_Neck"
				skel.add_child(attachment)
			puke_origin_node = attachment
		
		# Create Blood Effect
		await get_tree().create_timer(0.3).timeout # Wait for mouth to open
		print("[Camera3D] Spawning blood particles.")
		
		# Puke Sound 1
		SesYoneticisi.play_puke()
		
		var blood = blood_puke_scene.instantiate()
		# Set local_coords to false so particles fountain in world space
		if blood.has_method("set_local_coords"):
			blood.set_local_coords(false)
		
		puke_origin_node.add_child(blood)
		blood.position = Vector3.ZERO # Start exactly at bone/origin
		
		# Correct orientation: particles fly towards grid center
		var target_puke = Vector3(0, -0.65, -1.97)
		
		# Puke Sound 2 (Triggered after 4 seconds as per user request for total ~8-9s)
		get_tree().create_timer(4.0).timeout.connect(func(): SesYoneticisi.play_puke())
		
		# Dynamic LookAt Loop: Keep puke aimed at target even as character moves
		var puke_time = 0.0
		var duration = 7.5
		while puke_time < duration:
			if is_instance_valid(blood):
				blood.look_at(target_puke)
			await get_tree().process_frame
			puke_time += get_process_delta_time()
		
		if is_instance_valid(blood):
			blood.emitting = false
		
		await get_tree().create_timer(2.0).timeout # Total wait ~9.5s
		if is_instance_valid(blood):
			blood.queue_free()
		
		if sitting_anim.is_playing() and sitting_anim.current_animation == "puke":
			print("[Camera3D] Waiting for animation to finish...")
			await sitting_anim.animation_finished
		
		print("[Camera3D] Puke sequence complete.")
		# Resume sitting loop
		var manager = get_tree().get_first_node_in_group("oyun_yoneticisi")
		if manager and manager.has_method("_start_sitting_loop"):
			manager._start_sitting_loop()
	else:
		print("[Camera3D] ERROR: 'puke' animation not found. List: ", sitting_anim.get_animation_list())

# Taşın materyallerini ayarlama yardımcısı (X-Ray desteği eklendi)
func set_piece_render_priority(node: Node, priority: int, x_ray: bool = false):
	if node is MeshInstance3D:
		# Meta verisini güncelle ki GlobalShaderApplier fark etsin
		node.set_meta("render_on_top", x_ray)
		
		for i in range(node.get_surface_override_material_count()):
			var mat = node.get_surface_override_material(i)
			if not mat:
				mat = node.mesh.surface_get_material(i)
			
			if mat:
				var new_mat = mat.duplicate()
				new_mat.render_priority = priority
				if new_mat is StandardMaterial3D:
					new_mat.no_depth_test = x_ray
				node.set_surface_override_material(i, new_mat)
				
		if node.mesh:
			for i in range(node.mesh.get_surface_count()):
				var mat = node.mesh.surface_get_material(i)
				if mat:
					var new_mat = mat.duplicate()
					new_mat.render_priority = priority
					if new_mat is StandardMaterial3D:
						new_mat.no_depth_test = x_ray
					node.set_surface_override_material(i, new_mat)
		
		# GlobalShaderApplier'ı manuel tetikleyelim
		var applier = get_tree().root.find_child("GlobalShaderApplier", true, false)
		if applier and applier.has_method("_apply_toon_ps1"):
			applier._apply_toon_ps1(node, true)

	for child in node.get_children():
		set_piece_render_priority(child, priority, x_ray)

func _is_cell_valid_for_placement(hucre: GridHucre) -> bool:
	# Player's Side (Row 4 is closest to camera, Row 3 is in front of it)
	if hucre.satir == 4:
		# Can place anywhere in Row 4 EXCEPT the king's spot (Col 2)
		return hucre.sutun != 2
	elif hucre.satir == 3:
		# Can ONLY place in front of the king (Col 2)
		return hucre.sutun == 2
	
	return false

func _on_inspect_dismissed():
	if held_piece:
		held_piece.visible = true
		print("İnceleme bitti, asıl taş tekrar görünür.")

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

func _transition_to_board_view():
	if not camera2: return
	is_transitioning_view = true
	var tw = create_tween().set_parallel(true)
	tw.tween_property(self, "position", camera2.position, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "rotation_degrees", camera2.rotation_degrees, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	is_zoomed_view = true
	is_transitioning_view = false

func _transition_to_seated_view():
	is_transitioning_view = true
	var tw = create_tween().set_parallel(true)
	tw.tween_property(self, "position", seated_position, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "rotation_degrees", seated_rotation, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	is_zoomed_view = false
	is_transitioning_view = false

func trigger_loss():
	print("GAME OVER! Player King defeated.")
	is_game_over = true
	is_locked = true # Disable controls
	
	# Falling Animation
	var tw = create_tween().set_parallel(true)
	# Tilt camera sideways and crash to floor
	tw.tween_property(self, "rotation_degrees:z", 75.0, 0.6).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "position:y", -0.9, 0.6).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "rotation_degrees:x", -10.0, 0.6)
	
	apply_shake(0.5, 0.8)
	SesYoneticisi.play_fall()
	SesYoneticisi.play_evil_laugh()
	
	await tw.finished
	
	# Notify UI (will be created in root by OyunYoneticisi or here)
	var ui = get_node_or_null("/root/GameOverUI")
	
	# Board cleanup
	var manager = get_tree().get_first_node_in_group("oyun_yoneticisi")
	if manager: manager.cleanup_board()
	
	if ui:
		ui.show_game_over()
	else:
		# Fallback: create it if it doesn't exist
		var script = load("res://GameOverUI.gd")
		if script:
			var new_ui = script.new()
			new_ui.name = "GameOverUI"
			get_tree().root.add_child(new_ui)
			new_ui.show_game_over()

func enter_upgrade_selection_view():
	is_upgrade_mode = true
	if current_state == PlayerState.SEATED:
		stand_up()
		await get_tree().create_timer(1.2).timeout 
	
	# Kullanıcının belirttiği kesin konum ve açı
	var target_pos = Vector3(-1.062, -0.086, 2.303)
	var target_rot = Vector3(-13.7, 84.9, 0)
	
	var tw = create_tween().set_parallel(true)
	tw.tween_property(self, "global_position", target_pos, 1.2).set_trans(Tween.TRANS_SINE)
	tw.tween_property(self, "rotation_degrees", target_rot, 1.2).set_trans(Tween.TRANS_SINE)
	
	await tw.finished
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if crosshair_ui: crosshair_ui.visible = false

func exit_upgrade_selection_view():
	is_upgrade_mode = false
	# This is now handled by release_to_walk() or sit_down()

func return_to_table():
	is_upgrade_mode = false
	is_game_over = false # Sıfırla ki sit_down engellenmesin
	
	# Masaya oturma animasyonunu başlat
	sit_down()
	
	# İmleci geri getir
	if crosshair_ui:
		crosshair_ui.visible = true
	
	# Oyun Yöneticisini bul ve taze maçı başlat
	var manager = get_tree().get_first_node_in_group("oyun_yoneticisi")
	if manager and manager.has_method("restart_new_match"):
		manager.restart_new_match()
	
	print("[Camera3D] Masaya dönüldü, imleç ve yeni maç tetiklendi.")

func release_to_walk():
	
	# Mevcut bakış açısını yaw/pitch değişkenlerine aktar (Smooth transition)
	yaw = rotation_degrees.y
	pitch = rotation_degrees.x
	
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if crosshair_ui: crosshair_ui.visible = true
	print("PLAYER RELEASED TO WALK MODE")

func _process_upgrade_interaction():
	if not is_upgrade_mode: return
	
	var mouse_pos = get_viewport().get_mouse_position()
	var from = project_ray_origin(mouse_pos)
	var to = from + project_ray_normal(mouse_pos) * ray_length * 2.0
	
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1 # Pieces are on layer 1
	var result = space_state.intersect_ray(query)
	
	var new_hovered = null
	if result:
		var collider = result.collider
		var target = collider.get_parent() if collider is StaticBody3D else collider
		if target.has_meta("is_upgrade_choice"):
			new_hovered = target
	
	if new_hovered != hovered_upgrade_piece:
		if hovered_upgrade_piece:
			_set_piece_highlight(hovered_upgrade_piece, false)
		hovered_upgrade_piece = new_hovered
		if hovered_upgrade_piece:
			_set_piece_highlight(hovered_upgrade_piece, true)
			SesYoneticisi.play_hover()

func _set_piece_highlight(piece: Node3D, active: bool):
	# Kill existing tween if any
	if piece.has_meta("hover_tween"):
		var old_tw = piece.get_meta("hover_tween")
		if old_tw and old_tw.is_valid():
			old_tw.kill()
		piece.remove_meta("hover_tween")

	if active:
		var tw = create_tween().set_loops()
		tw.tween_property(piece, "scale", Vector3(1.1, 1.1, 1.1), 0.2).set_trans(Tween.TRANS_SINE)
		tw.tween_property(piece, "scale", Vector3(1.0, 1.0, 1.0), 0.2).set_trans(Tween.TRANS_SINE)
		piece.set_meta("hover_tween", tw)
	else:
		piece.scale = Vector3(1.0, 1.0, 1.0)

func _get_enemy_pos() -> Vector3:
	var sitting = get_tree().get_first_node_in_group("sitting_node")
	if sitting: return sitting.global_position
	return Vector3(0, -0.25, -1.5) # Fallback near the character

func _handle_upgrade_click():
	if hovered_upgrade_piece and upgrade_manager:
		upgrade_manager.select_piece(hovered_upgrade_piece)
		_set_piece_highlight(hovered_upgrade_piece, false)
		hovered_upgrade_piece = null
