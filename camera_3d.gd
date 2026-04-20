@tool
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
var head_bob_time = 0.0

# Centralized Paper Physics
var falling_papers : Array = [] # Stores Dictionary: { node: Node3D, velocity: Vector3, is_settling: bool }
var gravity_constant = 9.8
var rotation_settle_speed = 8.0
var interact_label: Label = null
var hand_node: Node3D = null
var is_punching: bool = false # Still used for one-shot check or state
var is_holding_interaction: bool = false
var held_object: Node3D = null
var held_object_offset: Transform3D
var hand_base_pos: Vector3
var hand_base_rot: Vector3
var hand_anim_pos: Vector3 = Vector3.ZERO
var hand_anim_rot: Vector3 = Vector3.ZERO

var ray_length: float = 10.0
@onready var crosshair_ui: TextureRect = get_tree().root.find_child("Crosshair", true, false)
@onready var camera2: Camera3D = get_parent().get_node("Camera3D2") if get_parent().has_node("Camera3D2") else null
var piece_name_label: Label = null
var held_piece_name_label: Label = null
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

# Stylish Interaction Params
var base_fov: float = 80.0
var focus_fov: float = 72.0
var interaction_jitter_intensity: float = 0.003 # Subtle jitter for held pieces
var jitter_speed: float = 55.0 # Speed of the vibration
var jitter_time: float = 0.0

# Tracking Params
var tracking_target: Node3D = null
var is_tracking_enemy: bool = false
var tracking_fov: float = 75.0
var tracking_lerp_speed: float = 2.5 # Slower, calmer rotation
var fov_tween: Tween = null

signal piece_placed
signal piece_moved
signal camera_returned_to_board

func _ready():
	base_fov = fov
	if get_tree().current_scene.name == "anamenu":
		if crosshair_ui:
			crosshair_ui.visible = false
		return
		
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

	# Setup Hand Node
	hand_node = get_node_or_null("hand")
	if not hand_node:
		hand_node = get_node_or_null("Sketchfab_Scene") # Fallback
	
	if hand_node and not Engine.is_editor_hint():
		hand_node.visible = false
		_setup_hand_visuals(hand_node)
		hand_base_pos = hand_node.position
		hand_base_rot = hand_node.rotation_degrees
	
	_sync_paper_colliders(get_parent())
	_apply_drawer_materials()

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
		interact_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		interact_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		interact_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
		var settings = LabelSettings.new()
		settings.font = load("res://Assets/fonts/Golden Horse.ttf")
		settings.font_size = 18
		settings.font_color = Color.WHITE
		settings.outline_size = 6
		settings.outline_color = Color.BLACK
		interact_label.label_settings = settings
		
		interact_label.position.y -= 50 # Move up slightly from bottom
		
		interact_label.visible = false
		control.add_child(interact_label)
		
		# Create Piece Info Label
		piece_name_label = Label.new()
		piece_name_label.name = "PieceInfoLabel"
		var piece_settings = LabelSettings.new()
		piece_settings.font = load("res://Assets/fonts/Golden Horse.ttf")
		piece_settings.font_size = 28
		piece_settings.font_color = Color.WHITE
		piece_settings.outline_size = 8
		piece_settings.outline_color = Color.BLACK
		piece_name_label.label_settings = piece_settings
		piece_name_label.visible = false
		control.add_child(piece_name_label)
		
		# Eldeki taş ismi için aynı stilde ikinci etiket
		held_piece_name_label = Label.new()
		held_piece_name_label.name = "HeldPieceLabel"
		held_piece_name_label.label_settings = piece_settings # Aynı stil
		held_piece_name_label.visible = false
		control.add_child(held_piece_name_label)

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
	
	if hand_node and not is_upgrade_mode:
		hand_node.visible = true
# print("PLAYER STANDING")

func sit_down():
	if is_game_over:
# print("Oyun bittiği için baştan yükleniyor...")
		Engine.time_scale = 1.0
		get_tree().reload_current_scene()
		return
		
	if current_state != PlayerState.STANDING: return
	
	if interact_label: interact_label.visible = false
	current_state = PlayerState.TRANSITIONING
	is_locked = true
	
	if hand_node:
		hand_node.visible = false
	
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
	camera_returned_to_board.emit()
# print("PLAYER SEATED")

func restore_mouse_mode():
	if current_state == PlayerState.SEATED:
		Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _input(event):
	if event.is_action_pressed("ui_cancel"):
		var pm = get_tree().root.find_child("PauseMenu", true, false)
		if pm:
			pm.pause()

	# Upgrade modunda: tüm guard'ları atla, direkt etkileşime izin ver
	if is_upgrade_mode and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_upgrade_click()
		get_viewport().set_input_as_handled()
		return
	
	if is_receiving_piece: return
	
	# Block all camera actions and rotation if any full-screen UI is active
	if _is_any_ui_active():
		return

	if is_locked: return
	
	# Interactions
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if is_game_over and current_state == PlayerState.SEATED: return
		
		# Guard: No interaction if a piece is being placed/received or it's not our turn
		if is_placing_piece or is_receiving_piece: return
		
		var manager = get_tree().get_first_node_in_group("oyun_yoneticisi")
		if manager and manager.current_turn != manager.GameTurn.PLAYER and not is_upgrade_mode:
			return
		
		if held_piece:
			if _check_tutorial_permission(0): # 0 = PLACE
				place_held_piece()
		else:
			if not is_upgrade_mode:
				if _check_tutorial_permission(4): # 4 = BOARD_CLICK
					interact_with_crosshair()
					if current_state == PlayerState.STANDING:
						_hand_reach()
	
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if current_state == PlayerState.STANDING:
			_hand_retract()
	
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if is_game_over or is_placing_piece or is_receiving_piece: return
		
		# Check if we are right-clicking a piece to inspect it
		var result = _raycast_from_mouse()
		if result and result.collider.has_meta("is_grid_cell"):
			var hucre = result.collider.get_meta("grid_cell_node")
			if hucre and hucre.mevcut_tas and hucre != selected_hucre:
				if _check_tutorial_permission(2): # 2 = INSPECT
					var path = hucre.mevcut_tas.get_meta("scene_path") if hucre.mevcut_tas.has_meta("scene_path") else ""
					if path != "" and has_node("/root/InspectUI"):
						get_node("/root/InspectUI").show_piece(path, false, hucre.mevcut_tas) # Taşın kendisini de gönderiyoruz
						return # Prevent deselection if we are inspecting
		
		# Default: Deselect on right click
		if held_piece:
			SesYoneticisi.play_error()
		_clear_selection()
		if is_zoomed_view:
			_transition_to_seated_view()
	
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not held_piece and not is_upgrade_mode:
		# Check if we clicked an already standing piece to open info
		var result = _raycast_from_mouse()
		if result and result.collider.has_meta("is_grid_cell"):
			var hucre = result.collider.get_meta("grid_cell_node")
			if hucre and hucre.mevcut_tas:
				# Signal that we are inspecting a board piece (for Sequence 5)
				pass # This is handled by right-click in current version, but user requested left-click info check in tutorial
	
	if event is InputEventKey:
		if event.keycode == KEY_E:
			if current_state == PlayerState.STANDING:
				if event.pressed:
					if interact_label.visible:
						# Check what we are interacting with
						var target = _get_interaction_target()
						if target:
							if target.has_meta("is_chair"):
								sit_down()
							elif target.has_meta("is_door") or "kapi" in target.name.to_lower() or "door" in target.name.to_lower():
								var logic = target.get_meta("door_logic") if target.has_meta("door_logic") else null
								if not logic:
									# Fallback search
									logic = get_tree().get_first_node_in_group("door_logic")
								
								if logic and logic.has_method("interact"):
									var manager = get_tree().get_first_node_in_group("oyun_yoneticisi")
									if manager and manager.get("_all_news_removed"):
										logic.interact()
							else:
								# PROXIMITY FALLBACK for Interaction
								var manager = get_tree().get_first_node_in_group("oyun_yoneticisi")
								if manager and manager.get("_all_news_removed"):
									var kapi = get_tree().root.find_child("kapi", true, false)
									if kapi and global_position.distance_to(kapi.global_position) < 3.0:
										var logic = get_tree().get_first_node_in_group("door_logic")
										if logic and logic.has_method("enable_escape"): 
											logic.enable_escape() # Just in case
										if logic and logic.has_method("interact"):
											logic.interact()
					else:
						_hand_reach()
				else: # Released
					_hand_retract()
		
		# Only check these on press
		if event.pressed:
			if current_state == PlayerState.SEATED and not is_transitioning_view:
				if event.keycode == KEY_W and not is_zoomed_view:
					_transition_to_board_view()
				elif event.keycode == KEY_S and is_zoomed_view:
					_transition_to_seated_view()
					
			if event.keycode == KEY_C and current_state == PlayerState.SEATED and not is_transitioning_view:
				stand_up()

	# Rotation
	if event is InputEventMouseMotion:
		# Only rotate if the mouse is captured
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			return
			
		# Convert mouse motion to rotation
		if current_state != PlayerState.SEATED:
			yaw -= event.relative.x * sensitivity
			pitch -= event.relative.y * sensitivity
			
			# Limits (RELATIVE TO START ANGLES)
			pitch = clamp(pitch, -85, 85)

func _is_any_ui_active() -> bool:
	var inspect_ui = get_node_or_null("/root/InspectUI")
	if inspect_ui and inspect_ui.is_active: return true
	var upgrade_ui = get_node_or_null("/root/UpgradeUI")
	if upgrade_ui and upgrade_ui.is_active: return true
	return false

func _process(_delta):
	if Engine.is_editor_hint():
		_apply_drawer_materials()
		return
		
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
	
	# Hand Jitter & Animation Apply
	if hand_node and current_state == PlayerState.STANDING:
		var jitter_time = t * 10.0 # Even lower frequency for stability
		var jitter_pos = Vector3(
			randf_range(-0.0003, 0.0003),
			randf_range(-0.0003, 0.0003),
			randf_range(-0.0003, 0.0003)
		)
		var jitter_rot = Vector3(
			sin(jitter_time * 1.2) * 0.1,
			cos(jitter_time * 0.8) * 0.1,
			sin(jitter_time * 1.5) * 0.1
		)
		hand_node.position = hand_base_pos + hand_anim_pos + jitter_pos
		hand_node.rotation_degrees = hand_base_rot + hand_anim_rot + jitter_rot
		
		# Held Object Follow
		if held_object:
			_process_held_object_follow()
	
	if current_state == PlayerState.SEATED:
		if not is_transitioning_view:
			if is_zoomed_view and camera2:
				position = camera2.position
				rotation_degrees = camera2.rotation_degrees
			elif is_tracking_enemy and tracking_target and is_instance_valid(tracking_target):
				# Smoothly look at the tracking target (enemy piece)
				var target_pos = tracking_target.global_position
				var dir = (target_pos - global_position).normalized()
				var target_quat = Quaternion(Basis.looking_at(dir, Vector3.UP))
				var current_quat = Quaternion(basis)
				var final_quat = current_quat.slerp(target_quat, _delta * tracking_lerp_speed)
				basis = Basis(final_quat)
				# FOV is now handled by Tween in start/stop tracking
			else:
				rotation_degrees.y = seated_rotation.y
				rotation_degrees.x = seated_rotation.x
				rotation_degrees.z = seated_rotation.z
				# Reset FOV is now handled by Tween or board transitions
				pass
	elif not is_upgrade_mode:
		rotation_degrees.y = yaw + breath_yaw + (shake_offset.x * 2.0)
		rotation_degrees.x = pitch + breath_pitch + (shake_offset.y * 2.0)
		rotation_degrees.z = breath_roll + (shake_offset.z * 5.0)
	
	if current_state == PlayerState.STANDING:
		_process_chair_interaction()
	
	# Stylish Piece Jitter (Vibration)
	_process_piece_vibration(_delta)
	
	# Update Crosshair Position
	_update_crosshair_position()
	_update_piece_hover_info()
	_update_held_piece_label() # Eldeki taşın ismini güncelle

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
			# Check piece parent for upgrade choices to ensure we find 'scene_path'
			var actual_piece = target_piece
			if not actual_piece.has_meta("scene_path") and actual_piece.get_parent() and actual_piece.get_parent().has_meta("scene_path"):
				actual_piece = actual_piece.get_parent()
				
			var path = actual_piece.get_meta("scene_path") if actual_piece.has_meta("scene_path") else ""
			if path != "":
				var display_name = PieceDatabase.get_piece_display_name(path)
				piece_name_label.text = display_name
				piece_name_label.global_position = crosshair_pos + Vector2(25, -25)
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

func _update_held_piece_label():
	if not held_piece_name_label: return
	
	# İnceleme ekranı açıkken, el boşken veya yerleştirme (glide) sırasında gösterme
	var inspect_ui = get_node_or_null("/root/InspectUI")
	if not held_piece or (inspect_ui and inspect_ui.is_active) or is_placing_piece:
		held_piece_name_label.visible = false
		return
		
	# İsmi al ve göster
	held_piece_name_label.text = PieceDatabase.get_piece_display_name(held_piece_scene)
	
	# Taşın ekran üzerindeki konumunu hesapla (Sağ-üst)
	var screen_pos = unproject_position(held_piece.global_position)
	var y_offset = -95 if "piyon" in held_piece_scene.to_lower() else -140
	held_piece_name_label.global_position = screen_pos + Vector2(-40, y_offset)
	held_piece_name_label.visible = true

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
	
	_process_falling_papers(_delta)

func _process_falling_papers(_delta):
	var to_remove = []
	var space_state = get_world_3d().direct_space_state
	
	for i in range(falling_papers.size() - 1, -1, -1):
		var data = falling_papers[i]
		var node = data.node
		if not is_instance_valid(node):
			to_remove.append(i)
			continue
		
		# Gravity applied to global Y
		data.velocity.y -= gravity_constant * _delta
		node.global_position += data.velocity * _delta
		
		# Smoothly rotate to face-up (-90 on X)
		node.global_rotation_degrees.x = lerp(node.global_rotation_degrees.x, -90.0, _delta * rotation_settle_speed)
		node.global_rotation_degrees.z = lerp(node.global_rotation_degrees.z, 0.0, _delta * rotation_settle_speed)
		
		# Robust Ground Detection
		# Shoot a ray from current position downwards
		var ray_origin = node.global_position + Vector3(0, 0.1, 0)
		var ray_target = node.global_position - Vector3(0, 0.2, 0) # Look 20cm ahead
		
		var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_target)
		query.collision_mask = 1 # Environment/Colliders
		query.exclude = [node] # Exclude self
		
		var result = space_state.intersect_ray(query)
		
		# Stop if hit surface OR hit basement limits
		# Room floor is roughly around -0.7 to -1.2 depending on transform
		if result or node.global_position.y <= -2.0:
			if result:
				node.global_position.y = result.position.y + 0.005 # Settle precisely
				print("[PaperPhysics] ", node.name, " landed on ", result.collider.name, " at Y: ", node.global_position.y)
			else:
				node.global_position.y = -0.73 # Fallback
				
			node.global_rotation_degrees.x = -90
			node.global_rotation_degrees.z = 0
			node.global_rotation_degrees.y += randf_range(-20, 20)
			
			to_remove.append(i)
	
	for index in to_remove:
		falling_papers.remove_at(index)

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
	# If escape is in progress or door is open, stop all interaction processing
	var active_door = get_tree().get_first_node_in_group("door_logic")
	if (active_door and active_door.is_open) or is_locked:
		if interact_label: interact_label.visible = false
		return

	if not interact_label: return
	
	var result = _raycast_from_mouse()
	
	if result:
		var collider = result.collider
		
		if collider.has_meta("is_chair"):
			interact_label.text = "Sit Down (E)"
			interact_label.visible = true
		elif collider.has_meta("is_door") or "kapi" in collider.name.to_lower() or "door" in collider.name.to_lower():
			var logic = collider.get_meta("door_logic") if collider.has_meta("door_logic") else null
			_update_door_prompt(logic)
		else:
			# ULTIMATE FALLBACK: Distance-based check if raycast misses but we are looking at the door
			_check_proximity_door_interaction()
	else:
		_check_proximity_door_interaction()

func _check_proximity_door_interaction():
	var manager = get_tree().get_first_node_in_group("oyun_yoneticisi")
	if not manager or not manager.get("_all_news_removed"):
		interact_label.visible = false
		return
		
	# Find kapi node manually
	var kapi = get_tree().root.find_child("kapi", true, false)
	if kapi:
		var dist = global_position.distance_to(kapi.global_position)
		if dist < 3.0:
			# check if looking at it (dot product)
			var forward = -global_transform.basis.z
			var to_door = (kapi.global_position - global_position).normalized()
			if forward.dot(to_door) > 0.7: # Facing general direction
				interact_label.text = "Open the door (E)"
				interact_label.visible = true
				return
	
	interact_label.visible = false

func _update_door_prompt(logic):
	var escape_ready = false
	if logic:
		escape_ready = logic.is_escape_ready
	else:
		var manager = get_tree().get_first_node_in_group("oyun_yoneticisi")
		if manager and manager.get("_all_news_removed"):
			escape_ready = true
	
	if escape_ready:
		interact_label.text = "Open the door (E)"
		interact_label.visible = true
	else:
		interact_label.visible = false

func _get_interaction_target() -> Node:
	var result = _raycast_from_mouse()
	if result: return result.collider
	return null

func interact_with_crosshair():
	if is_receiving_piece: return
	
	# Eğer tutorial diyaloğu açıksa board etkileşimini sessizce yoksay
	# (Godot'ta _input tüm olayları alır; set_input_as_handled sadece _unhandled_input için geçerli)
	var tm = get_tree().get_first_node_in_group("tutorial_manager")
	if tm and tm.dialogue_ui and tm.dialogue_ui.visible: return

	
	# Not: Sıra kontrolü artık _input seviyesinde yapılıyor
	if not is_upgrade_mode:
		pass
		

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
# print("Düşman taşı seçilemez! (Path: %s)" % path)
					_clear_selection()
					if is_zoomed_view:
						_transition_to_seated_view()
			else:
				_clear_selection()
				if is_zoomed_view:
					_transition_to_seated_view()

func _raycast_from_mouse() -> Dictionary:
	var space_state = get_world_3d().direct_space_state
	var crosshair_pos = get_viewport().get_mouse_position() if (current_state == PlayerState.SEATED or is_upgrade_mode) else get_viewport().get_visible_rect().size / 2.0
	var origin = project_ray_origin(crosshair_pos)
	var end = origin + project_ray_normal(crosshair_pos) * ray_length
	var query = PhysicsRayQueryParameters3D.create(origin, end)
	return space_state.intersect_ray(query)

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
			# Determine highlight color and if valid
			var color = Color(0, 1, 0, 0.4) # Soft Green for empty squares
			var is_friendly = false
			
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
					is_friendly = true
				else:
					# Unknown/Neutral piece
					color = Color(1, 1, 0, 0.5)
			
			if not is_friendly:
				move_highlights.append(target)
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
		
	# Camera return is now handled explicitly at move end or cancel

func _execute_move(from: GridHucre, to: GridHucre):
	if not _check_tutorial_permission(1): # 1 = MOVE
		return
		
	is_placing_piece = true
	
	# Friendly fire guard
	if to.mevcut_tas:
		var target_path = to.mevcut_tas.get_meta("scene_path") if to.mevcut_tas.has_meta("scene_path") else ""
		if "white" in target_path.to_lower():
			_clear_selection()
			is_placing_piece = false
			return
		
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
		
		# Check for invulnerability (Kings)
		var is_king = defender.has_meta("is_king")
		if is_king:
			var tm = get_tree().get_first_node_in_group("tutorial_manager")
			if tm and not tm.can_damage_king("white" in defender_path.to_lower()):
				# Sync bounce back
				pass
			else:
				current_def -= attacker_stats["attack"]
		else:
			current_def -= attacker_stats["attack"]
			
		defender.set_meta("current_defense", current_def)
		
		# Feedback triggers
		var manager = get_tree().get_first_node_in_group("oyun_yoneticisi")
		if manager:
			var is_white_defender = "white" in defender_path.to_lower()
			var hit_intensity = 0.33 if current_def > 0 else 1.0
			var is_king_death = is_king and current_def <= 0
			manager._spawn_shatter_fx(defender.global_position, defender, hit_intensity, is_king_death)
			
			# King Specific Hit Feedback
			if is_king:
				if not is_white_defender:
					# Enemy King Hit: Play Chime
					SesYoneticisi.play_hover() 
				else:
					# Player King Hit: INTENSE Shake
					apply_shake(1.0, 1.0)
			
			if not (is_king and is_white_defender):
				apply_shake(0.2, 0.3)
		
		if current_def <= 0:
			# Capture!
			if manager and not ("white" in defender_path.to_lower()):
				# React physically only when enemy piece is lost
				manager._enemy_react_to_damage(is_king)
			apply_shake(0.4, 0.5) # Bigger shake on kill
			
			var is_player_piece = "white" in defender_path.to_lower()
			
			defender.queue_free()
			to.mevcut_tas = piece
			piece.reparent(to)
			piece.position = Vector3.ZERO
			
			if is_king:
				var tm = get_tree().get_first_node_in_group("tutorial_manager")
				if is_player_piece:
					if tm and tm.is_tutorial_active:
						is_game_over = true  # Oyun döngüsünü anında durdur
						tm.on_king_died(true)
					else:
						trigger_loss()
				else:
					if tm and tm.is_tutorial_active:
						is_game_over = true  # Oyun döngüsünü anında durdur
						tm.on_king_died(false)
					else:
						trigger_win()
				
				is_placing_piece = false
				# King yakalandığında sıra geçişi ve kamera geçişi YOK
				# (upgrade sekansı veya oyun sonu sekansı kamerayı yönetir)
				return
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
	
	piece_moved.emit()
	
	# End Player Turn
	var manager = get_tree().get_first_node_in_group("oyun_yoneticisi")
	if manager: manager.next_turn()
	
	is_placing_piece = false
	
	# LAND -> Return camera
	_transition_to_seated_view()
	
# Handle high-frequency jitter for held/selected pieces
func _process_piece_vibration(_delta):
	jitter_time += _delta * jitter_speed
	var jitter_offset = Vector3(
		sin(jitter_time) * interaction_jitter_intensity,
		cos(jitter_time * 1.1) * interaction_jitter_intensity,
		sin(jitter_time * 0.9) * interaction_jitter_intensity
	)
	
	# Mode 1: Held piece (from chest)
	if held_piece and not is_placing_piece:
		# Base position is Vector3(0.75, -0.05, -0.8) as defined in pick_up_piece
		held_piece.position = Vector3(0.75, -0.05, -0.8) + jitter_offset
		
	# Mode 2: Selected piece (on board)
	if selected_hucre and selected_hucre.mevcut_tas:
		#selected_hucre.mevcut_tas.position = Vector3.ZERO + jitter_offset
		# Since grid pieces are reparented, we might want to jitter their local transform
		# But careful not to break the 'lift' interpolation
		var lift_y = 0.1 # This matches the value in _select_hucre
		selected_hucre.mevcut_tas.position = Vector3(0, lift_y, 0) + jitter_offset

func pick_up_piece(piece: Node3D, scene_path: String):
	held_piece = piece
	held_piece_scene = scene_path
	# Taşı kameraya "bağlayalım"
	held_piece.reparent(self)
	
	# Kullanıcının istediği "yakın ve büyük" görünüm için optimize edilmiş değerler:
	# 'Elde tutma' (Yeni sağ-üst çapraz ve 1.3x büyük) konumu ile eşle
	held_piece.position = Vector3(0.75, -0.05, -0.8) 
	held_piece.rotation_degrees = Vector3(5, 155, 0)
	held_piece.scale = Vector3(4.2, 4.2, 4.2)
	
	# UI'yı göster
	if has_node("/root/InspectUI"):
		get_node("/root/InspectUI").show_piece(scene_path, true, held_piece) # Sandık için true, held_piece gönderiliyor
		# Gerçek taşı gizleyelim, UI (SubViewport) kendi kopyasını gösterecek (sevilen o keskin haliyle)
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
	if is_receiving_piece or is_placing_piece: return
	
	is_placing_piece = true
	
	if current_state == PlayerState.STANDING:
		await sit_down()
		
	if not last_highlighted_cell:
		SesYoneticisi.play_error()
		is_placing_piece = false
		return
	
	if held_piece_name_label: held_piece_name_label.visible = false
	var target_hucre = last_highlighted_cell
	var target_pos = target_hucre.global_position
	
	# Temizle (Önizleme taşını hemen kaldıralım ki asıl taş uçarken görsel karmaşa olmasın)
	target_hucre.set_preview_piece("")
	target_hucre.set_highlight(false)
	last_highlighted_cell = null
	
	# Taşı grid'e taşıyalım
	held_piece.reparent(get_tree().root)
	
	# InspectUI temizliğini burada yapalım ki "Glide" anında UI tamamen gitsin
	if has_node("/root/InspectUI"):
		get_node("/root/InspectUI").clear_viewport_piece()
	
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
	piece_placed.emit()
	
	# Stylishly return to seated view after placement
	_transition_to_seated_view()
	
func trigger_win():
	if is_game_over: return
	is_game_over = true
	# Character sound (Angry)
	SesYoneticisi.play_angry(_get_enemy_pos())
	
	# Clear tracking and return to seated view to see the character
	stop_tracking()
	if is_zoomed_view:
		_transition_to_seated_view()
	
	# Give 1 second for the impact before sequence
	await get_tree().create_timer(1.0).timeout
	
	# Check for Puke Condition (Every 3 sections)
	var manager = get_tree().get_first_node_in_group("oyun_yoneticisi")
	
	if manager and manager.phase_number == 6:
		# Final victory, skip upgrade and trigger escape sequence transition
		manager.restart_new_match()
		return

	if manager and manager.phase_number % 3 == 0:
		await _play_puke_sequence()
	
	if upgrade_manager and upgrade_manager.has_method("start_upgrade_sequence"):
		upgrade_manager.start_upgrade_sequence()
	else:
		# Fallback if no manager
		stand_up()
		manager = get_tree().get_first_node_in_group("oyun_yoneticisi")
		if manager: manager.cleanup_board()
	
func start_tracking(target: Node3D):
	tracking_target = target
	is_tracking_enemy = true
	
	if fov_tween: fov_tween.kill()
	fov_tween = create_tween()
	fov_tween.tween_property(self, "fov", tracking_fov, 0.6).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	
func stop_tracking():
	is_tracking_enemy = false
	tracking_target = null
	
	if fov_tween: fov_tween.kill()
	fov_tween = create_tween()
	fov_tween.tween_property(self, "fov", base_fov, 0.8).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN_OUT)
	
func _play_puke_sequence():
# print("[Camera3D] Starting Puke Sequence...")
	var sitting_node = get_tree().get_first_node_in_group("sitting_node")
	
	if not sitting_node and owner:
		sitting_node = owner.get_node_or_null("Sitting")
	
	if not sitting_node:
		print("[Camera3D] ERROR: Sitting node NOT FOUND in group 'sitting_node' or relative to owner.")
		return
	
# print("[Camera3D] Sitting node found: ", sitting_node.get_path())
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
# print("[Camera3D] Playing 'puke' animation.")
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
			
		# Spawn Particles
		if blood_puke_scene:
			var puke_fx = blood_puke_scene.instantiate()
			puke_origin_node.add_child(puke_fx)
			# Ensure it stops and cleans up
			get_tree().create_timer(3.0).timeout.connect(func():
				if is_instance_valid(puke_fx):
					puke_fx.emitting = false
					get_tree().create_timer(2.0).timeout.connect(puke_fx.queue_free)
			)
		
		# Create Blood Effect
		await get_tree().create_timer(0.3).timeout # Wait for mouth to open
# print("[Camera3D] Spawning blood particles.")
		
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
		
# print("[Camera3D] Puke sequence complete.")
		# Resume sitting loop
		var manager = get_tree().get_first_node_in_group("oyun_yoneticisi")
		if manager and manager.has_method("_start_sitting_loop"):
			manager._start_sitting_loop()
	else:
		print("[Camera3D] ERROR: 'puke' animation not found. List: ", sitting_anim.get_animation_list())

func set_piece_render_priority(node: Node, priority: int, x_ray: bool = false):
	# Meta verisini güncelle ki GlobalShaderApplier fark etsin
	node.set_meta("render_on_top", x_ray)
	
	if node is MeshInstance3D:
		
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
		
		# GlobalShaderApplier'ı sadece ilk kez veya zorunluysa tetikleyelim
		var applier = get_tree().root.find_child("GlobalShaderApplier", true, false)
		if applier and applier.has_method("_process_node"):
			applier._process_node(node)

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
		# Kesikliği önlemek için: Önce taşı yaklaşık UI konumunda (ortada) hazırla, sonra süzdür
		held_piece.position = Vector3(0.1, -0.1, -0.8) # Başlangıç (Süzülme başlangıcı)
		held_piece.rotation_degrees = Vector3(5, 155, 0)
		held_piece.scale = Vector3(3.2, 3.2, 3.2)
		held_piece.visible = true
		
		# Şimdi eldeki asıl "büyük ve sağ-üst" yerine süzülerek gitsin
		var tw = create_tween().set_parallel(true)
		tw.tween_property(held_piece, "position", Vector3(0.75, -0.05, -0.8), 0.6).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
		tw.tween_property(held_piece, "scale", Vector3(4.2, 4.2, 4.2), 0.6).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
		
		# Global shader (Kenarlık vb.) ve önde görünme (X-Ray) aktif
		set_piece_render_priority(held_piece, 10, true)

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
	if not camera2 or is_zoomed_view or is_transitioning_view: return
	is_transitioning_view = true
	var tw = create_tween().set_parallel(true)
	# Premium transition with Quart easing and FOV focus
	tw.tween_property(self, "position", camera2.position, 0.6).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "rotation_degrees", camera2.rotation_degrees, 0.6).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "fov", focus_fov, 0.6).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	
	await tw.finished
	is_zoomed_view = true
	is_transitioning_view = false

func _transition_to_seated_view():
	if not is_zoomed_view or is_transitioning_view: return
	is_transitioning_view = true
	var tw = create_tween().set_parallel(true)
	# Returning with same premium feel and FOV reset
	tw.tween_property(self, "position", seated_position, 0.6).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "rotation_degrees", seated_rotation, 0.6).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "fov", base_fov, 0.6).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN_OUT)
	
	await tw.finished
	is_zoomed_view = false
	is_transitioning_view = false

func trigger_loss():
# print("GAME OVER! Player King defeated.")
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
	
	else:
		# Fallback: create it if it doesn't exist
		var script = load("res://GameOverUI.gd")
		if script:
			var new_ui = script.new()
			new_ui.name = "GameOverUI"
			get_tree().root.add_child(new_ui)
			new_ui.show_game_over()

func _transition_to_upgrade_view():
	enter_upgrade_selection_view()

func enter_upgrade_selection_view():
	is_upgrade_mode = true
	
	# CLEAR HELD PIECE (Fix for softlock)
	if held_piece:
		held_piece.queue_free()
		held_piece = null
		held_piece_scene = ""
	is_receiving_piece = false
	
	if current_state == PlayerState.SEATED:
		stand_up()
		await get_tree().create_timer(1.2).timeout 
	
	if hand_node:
		hand_node.visible = false
	
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
	# Eğer tutorial hâlâ aktifse, restart_new_match yerine TutorialManager devralır
	var manager = get_tree().get_first_node_in_group("oyun_yoneticisi")
	if manager and manager.has_method("restart_new_match") and not manager.is_tutorial_mode:
		manager.restart_new_match()
	
# print("[Camera3D] Masaya dönüldü, imleç ve yeni maç tetiklendi.")

func release_to_walk():
	
	# Mevcut bakış açısını yaw/pitch değişkenlerine aktar (Smooth transition)
	yaw = rotation_degrees.y
	pitch = rotation_degrees.x
	
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if crosshair_ui: crosshair_ui.visible = true
# print("PLAYER RELEASED TO WALK MODE")

var hovered_whetstone: Node3D = null

func _process_upgrade_interaction():
	if not is_upgrade_mode: return
	
	var mouse_pos = get_viewport().get_mouse_position()
	var from = project_ray_origin(mouse_pos)
	var to = from + project_ray_normal(mouse_pos) * ray_length * 2.0
	
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	# Layers: Pieces/Whetstones on Layer 1
	var result = space_state.intersect_ray(query)
	
	var new_hovered_piece = null
	var new_hovered_whetstone = null
	
	if result:
		var collider = result.collider
		if collider.has_meta("is_upgrade_choice"):
			# SUCCESS: Get the actual piece Node3D, not the StaticBody3D child
			new_hovered_piece = collider.get_parent() if collider.get_parent() else collider
		elif collider.has_meta("is_whetstone"):
			new_hovered_whetstone = collider
			
	# Handle Piece Hover
	if new_hovered_piece != hovered_upgrade_piece:
		if hovered_upgrade_piece:
			_set_piece_highlight(hovered_upgrade_piece, false)
			if piece_name_label: piece_name_label.visible = false
			
		hovered_upgrade_piece = new_hovered_piece
		
		if hovered_upgrade_piece:
			_set_piece_highlight(hovered_upgrade_piece, true)
			SesYoneticisi.play_hover()
			# Show Tooltip (Non-intrusive)
			if piece_name_label and hovered_upgrade_piece.has_meta("scene_path"):
				var path = hovered_upgrade_piece.get_meta("scene_path")
				piece_name_label.text = PieceDatabase.get_piece_display_name(path)
				piece_name_label.visible = true
				piece_name_label.global_position = get_viewport().get_mouse_position() + Vector2(25, -25)

	# Handle Whetstone Hover (Visual feedback)
	if new_hovered_whetstone != hovered_whetstone:
		hovered_whetstone = new_hovered_whetstone
		if hovered_whetstone:
			# Optional: add a subtle sound or visual if needed
			SesYoneticisi.play_hover()

func _set_piece_highlight(piece: Node3D, active: bool):
	if not is_instance_valid(piece): return
	if piece.has_meta("hover_tween"):
		var old_tw = piece.get_meta("hover_tween")
		if old_tw and old_tw.is_valid():
			old_tw.kill()
		piece.remove_meta("hover_tween")

	if active:
		var tw = create_tween().set_loops()
		tw.tween_property(piece, "scale", Vector3(1.6, 1.6, 1.6), 0.2).set_trans(Tween.TRANS_SINE)
		tw.tween_property(piece, "scale", Vector3(1.5, 1.5, 1.5), 0.2).set_trans(Tween.TRANS_SINE)
		piece.set_meta("hover_tween", tw)
	else:
		piece.scale = Vector3(1.5, 1.5, 1.5)

func _get_enemy_pos() -> Vector3:
	var sitting = get_tree().get_first_node_in_group("sitting_node")
	if sitting: return sitting.global_position
	return Vector3(0, -0.25, -1.5)

func _handle_upgrade_click():
	if not upgrade_manager: return
	
	# If we ALREADY selected a piece, we only care about whetstones
	if upgrade_manager.selected_piece != null:
		if hovered_whetstone:
			var type = hovered_whetstone.get_meta("whetstone_type") if hovered_whetstone.has_meta("whetstone_type") else ""
			if type != "":
				upgrade_manager.process_upgrade(type)
		return
	
	# Otherwise, we are in the selection phase
	if hovered_upgrade_piece:
		# Hide UI before moving
		if has_node("/root/InspectUI"): get_node("/root/InspectUI").hide_piece()
		
		upgrade_manager.select_piece(hovered_upgrade_piece)
		_set_piece_highlight(hovered_upgrade_piece, false)
		hovered_upgrade_piece = null
	elif hovered_whetstone:
		var type = hovered_whetstone.get_meta("whetstone_type") if hovered_whetstone.has_meta("whetstone_type") else ""
		if type != "":
			upgrade_manager.process_upgrade(type)

func _check_tutorial_permission(action_type: int) -> bool:
	var tm = get_tree().get_first_node_in_group("tutorial_manager")
	if tm and tm.has_method("is_action_allowed"):
		# Using int for enum safety across scripts
		if not tm.is_action_allowed(action_type):
			return false
	return true

func _setup_hand_visuals(node: Node):
	if node is MeshInstance3D:
		node.layers = 2 # Viewmodel layer
		# Force Unshaded Material
		for i in range(node.get_surface_override_material_count()):
			var mat = node.get_surface_override_material(i)
			if not mat: mat = node.mesh.surface_get_material(i)
			if mat:
				var new_mat = mat.duplicate()
				if new_mat is StandardMaterial3D:
					new_mat.roughness = 1.0 # Remove shine
					new_mat.metallic = 0.0 # Standardize surface
					new_mat.albedo_color = new_mat.albedo_color * 0.5 # Damp intensity to avoid blowouts
				node.set_surface_override_material(i, new_mat)
	
	for child in node.get_children():
		_setup_hand_visuals(child)

func _hand_reach():
	if not hand_node or is_holding_interaction: return
	
	is_holding_interaction = true
	is_punching = true
	
	# Raycast for papers and drawers before reaching
	_try_grab_paper()
	_try_interact_drawer()
	
	var target_pos = Vector3(0, -0.05, -0.1)
	var target_rot = Vector3(-25.0, 5.0, -2.0)
	
	var tw = create_tween().set_parallel(true)
	tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "hand_anim_pos", target_pos, 0.15)
	tw.tween_property(self, "hand_anim_rot", target_rot, 0.15)

func _hand_retract():
	if not is_holding_interaction: return
	
	var tw_back = create_tween().set_parallel(true)
	tw_back.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw_back.tween_property(self, "hand_anim_pos", Vector3.ZERO, 0.3)
	tw_back.tween_property(self, "hand_anim_rot", Vector3.ZERO, 0.3)
	
	await tw_back.finished
	
	# Release object if held
	if held_object:
		_release_paper()
		
	is_holding_interaction = false
	is_punching = false

func _try_interact_drawer():
	var space_state = get_world_3d().direct_space_state
	var v_size = get_viewport().get_visible_rect().size
	var crosshair_pos = v_size / 2.0
	var origin = project_ray_origin(crosshair_pos)
	var end = origin + project_ray_normal(crosshair_pos) * 2.5
	
	var query = PhysicsRayQueryParameters3D.create(origin, end)
	var result = space_state.intersect_ray(query)
	
	if result:
		var hit_node = result.collider
		var target = hit_node
		
		# Find parent node named 'drawer'
		while target and not ("drawer" in target.name.to_lower()):
			target = target.get_parent()
			
		if target:
			var anim_player = target.find_child("AnimationPlayer", true, false)
			if anim_player:
				# Determine animation index from name
				var anim_idx = "01"
				if "2" in target.name: anim_idx = "02"
				elif "3" in target.name: anim_idx = "03"
				elif "4" in target.name: anim_idx = "04"
				elif "5" in target.name: anim_idx = "05"
				
				var anim_name = "DRAWER_" + anim_idx + ".001Action"
				
				# Check list to be sure
				var anim_list = anim_player.get_animation_list()
				if anim_name not in anim_list and anim_list.size() > 0:
					anim_name = anim_list[0] # Fallback to first if name mismatch
				
				# Toggle logic
				var is_open = target.get_meta("is_open") if target.has_meta("is_open") else false
				
				if not is_open:
					anim_player.play(anim_name)
					target.set_meta("is_open", true)
				else:
					anim_player.play_backwards(anim_name)
					target.set_meta("is_open", false)
				
				SesYoneticisi.play_handing()

func _try_grab_paper():
	var space_state = get_world_3d().direct_space_state
	var v_size = get_viewport().get_visible_rect().size
	var crosshair_pos = v_size / 2.0
	var origin = project_ray_origin(crosshair_pos)
	var end = origin + project_ray_normal(crosshair_pos) * 2.5 # Short range for grabbing
	
	var query = PhysicsRayQueryParameters3D.create(origin, end)
	# Exclude self if needed, though ray starts from camera
	var result = space_state.intersect_ray(query)
	
	if result:
		var hit_node = result.collider
		# Check if it's an interactable paper (poster, newspaper, generic "new")
		var lname = hit_node.name.to_lower()
		var pname = hit_node.get_parent().name.to_lower()
		var gpname = hit_node.get_parent().get_parent().name.to_lower() if hit_node.get_parent().get_parent() else ""
		
		var is_paper = "poster" in lname or "newspaper" in lname or lname.contains("new") \
					or "poster" in pname or "newspaper" in pname or pname.contains("new") \
					or "newspaper" in gpname or gpname.contains("new")
		
		if is_paper:
			var paper = hit_node
			# Find the root paper node (named poster, newspaper, or new)
			while paper and not ("poster" in paper.name.to_lower() or "newspaper" in paper.name.to_lower() or "new" in paper.name.to_lower()):
				paper = paper.get_parent()
			
			if paper:
				held_object = paper
				
				# Notify game manager if this is part of the escape papers
				var manager = get_tree().get_first_node_in_group("oyun_yoneticisi")
				if manager and manager.has_method("notify_news_grabbed"):
					manager.notify_news_grabbed(held_object)
				
				# Reparent to root so it's no longer inside its original container (e.g. News)
				var old_transform = held_object.global_transform
				held_object.get_parent().remove_child(held_object)
				get_tree().root.add_child(held_object)
				held_object.global_transform = old_transform
				
				# Disable collisions while holding to prevent pushing the player
				_set_node_collision_active(held_object, false)
				# Store offset transform relative to camera
				held_object_offset = global_transform.affine_inverse() * held_object.global_transform

func _process_held_object_follow():
	if not held_object: return
	# Smoothly follow camera with stored offset
	var target_transform = global_transform * held_object_offset
	held_object.global_transform = held_object.global_transform.interpolate_with(target_transform, 0.2)

func _set_node_collision_active(node: Node, active: bool):
	if node is CollisionShape3D:
		node.disabled = not active
	if node is CollisionObject3D:
		# Also disable/enable the whole body if possible, or just bits
		node.set_collision_layer_value(1, active) # Typically player/world layer
		node.set_collision_mask_value(1, active)
	
	for child in node.get_children():
		_set_node_collision_active(child, active)

func _release_paper():
	if not held_object: return
	
	var paper = held_object
	held_object = null
	
	# Notify manager that a paper was released (for escape trigger)
	var manager = get_tree().get_first_node_in_group("oyun_yoneticisi")
	if manager and manager.has_method("notify_news_released"):
		manager.notify_news_released(paper)
	
	# Centralized Physics handling: Add to falling list
	# Ensure no physics components already exist (clean fallback)
	if paper.has_node("PaperPhysicsComponent"):
		paper.get_node("PaperPhysicsComponent").queue_free()
	
	_set_node_collision_active(paper, false) # Keep disabled while falling to prevent glitches
	
	falling_papers.append({
		"node": paper,
		"velocity": Vector3(randf_range(-0.05, 0.05), 0, randf_range(-0.05, 0.05))
	})

func _sync_paper_colliders(root: Node):
	for child in root.get_children():
		var lname = child.name.to_lower()
		if "poster" in lname or "newspaper" in lname or lname.begins_with("new"):
			print("Syncing paper: ", child.name)
			_fix_paper_collider(child)
		_sync_paper_colliders(child)

func _fix_paper_collider(paper_node: Node3D):
	# Find the mesh to get the true dimensions
	var mesh_node = _find_mesh_node(paper_node)
	if not mesh_node: return
	
	var aabb = mesh_node.get_aabb()
	var mesh_scale = mesh_node.scale
	
	# Find or Create StaticBody3D
	var sb = paper_node.find_child("StaticBody3D", true, false)
	if not sb:
		sb = StaticBody3D.new()
		paper_node.add_child(sb)
	
	# Reset StaticBody3D transform
	sb.transform = Transform3D.IDENTITY
	
	# Find or Create CollisionShape3D
	var cs = sb.find_child("CollisionShape3D", true, false)
	if not cs:
		cs = CollisionShape3D.new()
		sb.add_child(cs)
	
	# Reset and Sync CollisionShape3D
	cs.transform = Transform3D.IDENTITY
	var box = BoxShape3D.new()
	box.size = aabb.size * mesh_scale * 1.5 # Extra padding for easier grabbing
	cs.shape = box
	cs.position = aabb.get_center() * mesh_scale

func _find_mesh_node(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D: return node
	for child in node.get_children():
		var m = _find_mesh_node(child)
		if m: return m
	return null

func play_hand_animation():
	# Legacy fallback or for quick taps
	_hand_reach()
	await get_tree().create_timer(0.2).timeout
	_hand_retract()


func _apply_drawer_materials():
	var mat_wood = load("res://Masa_Ahsap.tres")
	if not mat_wood: return
	
	# Create a silver material for handles
	var mat_silver = StandardMaterial3D.new()
	mat_silver.albedo_color = Color(0.75, 0.75, 0.8) # Silverish
	mat_silver.metallic = 1.0
	mat_silver.roughness = 0.2
	
	# Find all drawer containers
	var drawer_names = ["drawer", "drawer2", "drawer3", "drawer4", "drawer5"]
	for d_name in drawer_names:
		var d = get_tree().root.find_child(d_name, true, false) if not Engine.is_editor_hint() else get_parent().find_child(d_name, true, false)
		if d:
			_recursive_apply_material(d, mat_wood, mat_silver)

func _recursive_apply_material(node: Node, mat_wood: Material, mat_silver: Material):
	if node is MeshInstance3D:
		# ALEX Drawer handle logic: Typically the 'BLACK' or 'PLASTIC' parts are handles/rails
		var nname = node.name.to_lower()
		if "black" in nname or "handle" in nname or "knob" in nname:
			node.material_override = mat_silver
		else:
			node.material_override = mat_wood
	
	for child in node.get_children():
		_recursive_apply_material(child, mat_wood, mat_silver)
