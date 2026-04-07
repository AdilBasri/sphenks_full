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
enum Turn { PLAYER, ENEMY }
var current_turn: Turn = Turn.PLAYER
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
var held_card: Node3D = null
var held_block: Node3D = null

var ghost_block: Node3D = null
var current_hovered_cell: Node3D = null
var is_placement_valid: bool = false

var enemy_placement_mode: bool = false
var knife_mode: bool = false
var original_camera_transform: Transform3D
var original_camera_rotation_degrees: Vector3

var current_hovered_part: Node3D = null
var outline_instance: MeshInstance3D = null

# Shake Params
var shake_intensity: float = 0.0
var shake_duration: float = 0.0
var shake_offset: Vector3 = Vector3.ZERO

# New Gameplay Params
var is_gun_mode: bool = false
var gun_node: Node3D = null
var gun_original_transform: Transform3D
var gun_original_scale: Vector3 = Vector3.ONE
var card_data: Dictionary = {} # Keeps track of original parents and transforms
var discard_label: Label = null
var trash_node: Node3D = null
var discard_label_base_pos: Vector2
var overlay_camera: Camera3D = null
var overlay_viewport: SubViewport = null
var bullet_chamber_index: int = -1 # Secret bullet position (0-5)
var current_chamber_index: int = 0 # Current hammer position (0-5)

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
	
	setup_viewmodel_rendering()
	
	# Kartlara kod üzerinden bir fizik alanı (Hitbox) ekleyelim ki raycast ile tıklayabilelim
	for card_name in ["card", "card2", "card3", "card4"]:
		var card = get_tree().root.find_child(card_name, true, false)
		if card:
			var static_body = StaticBody3D.new()
			static_body.set_meta("is_card", true)
			static_body.set_meta("card_node", card)
			
			var collision_shape = CollisionShape3D.new()
			var box_shape = BoxShape3D.new()
			box_shape.size = Vector3(4.0, 0.5, 6.0) # Hitboxu garantiye almak için biraz büyüttüm
			collision_shape.shape = box_shape
			
			static_body.add_child(collision_shape)
			card.add_child(static_body)

	# Find Gun
	gun_node = get_tree().root.find_child("gun", true, false)
	if gun_node:
		gun_original_transform = gun_node.global_transform
		gun_original_scale = gun_node.scale

	# Setup Enemy Loop
	var sitting = get_tree().root.find_child("Sitting", true, false)
	if sitting:
		var enemy_anim = sitting.find_child("AnimationPlayer", true, false)
		if enemy_anim:
			# Load and register animations
			var lib = enemy_anim.get_animation_library("")
			if not lib:
				lib = AnimationLibrary.new()
				enemy_anim.add_animation_library("", lib)
				
			var anim_otur1 = load("res://oturma1.res")
			var anim_geri = load("res://geri_otur.res")
			var anim_take = load("res://take_gun.res")
			var anim_egun = load("res://enemy_gun.res")
			
			if anim_otur1: lib.add_animation("oturma1", anim_otur1)
			if anim_geri: lib.add_animation("geri_otur", anim_geri)
			if anim_take: lib.add_animation("take_gun", anim_take)
			if anim_egun: lib.add_animation("enemy_gun", anim_egun)
			
			enemy_anim.get_animation("oturma1").loop_mode = Animation.LOOP_LINEAR
			enemy_anim.play("oturma1")
			
	# Find and Setup Trash
	trash_node = get_tree().root.find_child("trash", true, false)
	if trash_node:
		var sb = StaticBody3D.new()
		sb.set_meta("is_trash", true)
		var cs = CollisionShape3D.new()
		var box = BoxShape3D.new()
		box.size = Vector3(250, 400, 250) # The trash can scale is very small (0.001), so internal size should be large or wait...
		# Adjusting size based on the trash can's relative local space.
		cs.shape = box
		sb.add_child(cs)
		trash_node.add_child(sb)

	# Find Discard Label
	discard_label = get_tree().root.find_child("DiscardLabel", true, false)
	if discard_label:
		discard_label_base_pos = discard_label.position
		discard_label.visible = false
		
	setup_viewmodel_overlay()
	reset_revolver()
	_setup_enemy_collision()
	
	# Reset state if reloaded
	Engine.time_scale = 1.0
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _setup_enemy_collision():
	# Find Sitting node and move its collision to a dedicated Layer (Layer 2)
	# This avoids "DısDuvar" or other room objects blocking the bullet.
	var sitting = get_tree().root.find_child("Sitting", true, false)
	if sitting:
		_set_collision_layer_recursive(sitting, 2) # Bit 2 (value 2)

func _set_collision_layer_recursive(node: Node, layer: int):
	if node is CollisionObject3D:
		node.collision_layer = layer
	for child in node.get_children():
		_set_collision_layer_recursive(child, layer)

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
		
		# Set styling similar to DiscardLabel if possible
		if discard_label:
			interact_label.label_settings = discard_label.label_settings
			
		control.add_child(interact_label)

func stand_up():
	if current_state != PlayerState.SEATED: return
	
	current_state = PlayerState.TRANSITIONING
	is_locked = true
	
	# Close all modes
	is_gun_mode = false
	knife_mode = false
	if outline_instance: outline_instance.queue_free(); outline_instance = null
	
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

func reset_revolver():
	# Randomize bullet position 0-5
	bullet_chamber_index = randi() % 6
	current_chamber_index = 0
	print("REVOLVER SPUN: Bullet is in chamber ", bullet_chamber_index + 1)

func setup_viewmodel_overlay():
	# 1. Create Viewport Structure for the Gun
	var control = get_tree().root.find_child("Control", true, false)
	if not control: return
	
	var container = SubViewportContainer.new()
	container.name = "ViewmodelContainer"
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	# Add on top of other UI but it shares the viewport output
	control.add_child(container)
	
	overlay_viewport = SubViewport.new()
	overlay_viewport.transparent_bg = true
	overlay_viewport.handle_input_locally = false # Inputs go to main
	overlay_viewport.msaa_3d = Viewport.MSAA_2X # Anti-aliasing for the viewmodel
	overlay_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	container.add_child(overlay_viewport)
	
	# Link the world so lights and environment are shared!
	overlay_viewport.world_3d = get_world_3d()
	
	overlay_camera = Camera3D.new()
	overlay_viewport.add_child(overlay_camera)
	overlay_camera.cull_mask = (1 << 1) # Layer 2 ONLY
	
	# Main Camera should NOT see Layer 2
	cull_mask &= ~(1 << 1) 

func reset_rotation():
	yaw = start_y
	pitch = start_x
	rotation_degrees.y = yaw
	rotation_degrees.x = pitch
	# Warp mouse to center to sync with reset yaw/pitch
	Input.warp_mouse(get_viewport().get_visible_rect().size / 2.0)
	is_locked = false

func apply_shake(intensity: float, duration: float):
	shake_intensity = intensity
	shake_duration = duration

func setup_viewmodel_rendering():
	var hand = find_child("el_tam", true, false)
	if hand:
		_apply_no_depth_recursive(hand, 10)
	
	var mice = find_child("mice", true, false)
	if mice:
		_apply_no_depth_recursive(mice, 11)
		setup_mice_animations(mice)

func setup_mice_animations(mice_node: Node):
	var anim_player = mice_node.find_child("AnimationPlayer", true, false)
	if anim_player and anim_player is AnimationPlayer:
		var all_anims = anim_player.get_animation_list()
		var sequence = []
		
		# Sequence animations 1, 2, 3
		for suffix in ["1", "2", "3"]:
			for a in all_anims:
				if a.ends_with(suffix):
					sequence.append(a)
					break
		
		if sequence.size() > 0:
			# Play the first one
			anim_player.play(sequence[0])
			# Connect signal to play the next one when finished
			anim_player.animation_finished.connect(func(anim_name):
				var idx = sequence.find(anim_name)
				if idx != -1:
					var next_idx = (idx + 1) % sequence.size()
					anim_player.play(sequence[next_idx])
			)

func _apply_no_depth_recursive(node: Node, priority: int):
	# REVERT: We are now using a scaling-based viewmodel approach.
	# We no longer need to disable depth test, which broke internal sorting.
	if node is MeshInstance3D:
		for i in range(node.get_surface_override_material_count()):
			# Just clean up any previous overrides
			node.set_surface_override_material(i, null)
			node.material_override = null
	
	for child in node.get_children():
		_apply_no_depth_recursive(child, priority)

func _remove_no_depth_recursive(node: Node):
	if node is MeshInstance3D:
		node.material_override = null
		for i in range(node.get_surface_override_material_count()):
			node.set_surface_override_material(i, null)
			node.set_surface_override_material(i, null)
	
	for child in node.get_children():
		_remove_no_depth_recursive(child)

func _input(event):
	if is_game_over: return
	
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if current_turn != Turn.PLAYER: return # CANNOT ACT DURING ENEMY TURN
		
		if is_gun_mode:
			shoot_gun()
		elif discard_label and discard_label.visible:
			discard_held_block()
		elif held_block != null:
			if is_placement_valid and current_hovered_cell != null:
				place_held_block()
		elif held_card != null:
			consume_held_card()
		else:
			interact_with_crosshair()

	if is_locked: return
	if event is InputEventMouseMotion:
		# Only rotate if the mouse is captured (Fixes browser/itch.io mouse fight)
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
	
	if held_block != null:
		update_block_preview()
		_handle_discard_hover()
	elif discard_label:
		discard_label.visible = false
		
	if knife_mode:
		var space_state = get_world_3d().direct_space_state
		var v_size = get_viewport().get_visible_rect().size
		var center = v_size / 2.0
		var origin = project_ray_origin(center)
		var end = origin + project_ray_normal(center) * ray_length
		var query = PhysicsRayQueryParameters3D.create(origin, end)
		var result = space_state.intersect_ray(query)
		
		var found_part = null
		if result and result.collider.has_meta("is_block"):
			var b_node = result.collider.get_meta("block_node")
			if b_node and b_node.get_meta("placed"):
				found_part = result.collider.get_parent()
		elif result and result.collider.has_meta("is_grid_cell"):
			var cell_node = result.collider.get_meta("grid_cell_node")
			if cell_node.has_meta("dolu") and cell_node.get_meta("dolu"):
				var block_t = _find_block_occupying_cell(cell_node)
				if block_t:
					for p in block_t.get_children():
						if "Part" in p.name:
							var cs = p.find_child("CollisionShape3D", true, false)
							if cs:
								var g = cell_node.get_parent()
								var m_l = g.to_local(cs.global_position)
								var c_l = g.to_local(cell_node.global_position)
								if Vector2(m_l.x, m_l.z).distance_to(Vector2(c_l.x, c_l.z)) < 0.05:
									found_part = p
									break
		
		if current_hovered_part != found_part:
			current_hovered_part = found_part
			_update_knife_hover()
	else:
		if current_hovered_part:
			current_hovered_part = null
			_update_knife_hover()
	
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
	
	if is_gun_mode and gun_node:
		# Constant vibration while in gun mode (SYNCED WITH 0.75x SCALE)
		var scale_factor = 0.75
		var vib_x = randf_range(-0.002, 0.002)
		var vib_y = randf_range(-0.002, 0.002)
		var target_v_pos = Vector3(0.5, -0.4, -0.6) + Vector3(vib_x, vib_y, 0)
		gun_node.position = gun_node.position.lerp(target_v_pos, _delta * 10.0)
		
		# Sync Overlay Camera with Main Camera
		if overlay_camera:
			overlay_camera.global_transform = global_transform
			overlay_camera.fov = fov
		
		# Ensure it follows camera perfectly
		if gun_node.get_parent() != self:
			var g_trans = gun_node.global_transform
			if gun_node.get_parent(): gun_node.get_parent().remove_child(gun_node)
			add_child(gun_node)
			gun_node.global_transform = g_trans
	
	rotation_degrees.y = yaw + breath_yaw + (shake_offset.x * 2.0)
	rotation_degrees.x = pitch + breath_pitch + (shake_offset.y * 2.0)
	rotation_degrees.z = breath_roll + (shake_offset.z * 5.0)
	
	if current_state == PlayerState.STANDING:
		_process_chair_interaction()

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
		var target_part_to_delete = null
		var target_block = null
		
		if collider.has_meta("is_grid_cell"):
			var cell_node = collider.get_meta("grid_cell_node")
			if knife_mode and cell_node.has_meta("dolu") and cell_node.get_meta("dolu"):
				target_block = _find_block_occupying_cell(cell_node)
				if target_block:
					for p in target_block.get_children():
						if "Part" in p.name:
							var cs = p.find_child("CollisionShape3D", true, false)
							if cs:
								var g = cell_node.get_parent()
								var m_l = g.to_local(cs.global_position)
								var c_l = g.to_local(cell_node.global_position)
								if Vector2(m_l.x, m_l.z).distance_to(Vector2(c_l.x, c_l.z)) < 0.05:
									target_part_to_delete = p
									break
			
		elif collider.has_meta("is_card"):
			var card_node = collider.get_meta("card_node")
			if card_node:
				pick_up_card(card_node)
		elif collider.has_meta("is_block"):
			var block_node = collider.get_meta("block_node")
			if knife_mode and block_node and block_node.get_meta("placed"):
				target_part_to_delete = collider.get_parent()
				target_block = block_node
			elif block_node and not block_node.get_meta("placed"):
				pick_up_block(block_node)
				
		if knife_mode and target_part_to_delete and target_block:
			_clear_single_part(target_part_to_delete, target_block)
			knife_mode = false
			if outline_instance:
				outline_instance.queue_free()
				outline_instance = null
			current_hovered_part = null

func _find_block_occupying_cell(cell_node):
	for child in get_tree().root.get_children():
		if child.has_meta("placed") and child.get_meta("placed") == true:
			if child.has_meta("occupying_cells"):
				var cells = child.get_meta("occupying_cells")
				if cells.has(cell_node):
					return child
	return null

func _clear_single_part(part_node: Node3D, block_node: Node3D):
	var c_shape = part_node.find_child("CollisionShape3D", true, false)
	if c_shape:
		for g_name in ["OyuncuGrid", "DüşmanGrid"]:
			var g = get_tree().root.find_child(g_name, true, false)
			if g:
				var m_local = g.to_local(c_shape.global_position)
				var closest_cell = null
				var min_dist = 999.0
				var b_size = g.get("hucre_boyutu") if g.get("hucre_boyutu") else 0.1
				var max_dist = b_size / 1.5
				
				for c in g.get_children():
					if "sutun" in c:
						var c_local = g.to_local(c.global_position)
						var dist = Vector2(m_local.x, m_local.z).distance_to(Vector2(c_local.x, c_local.z))
						if dist < min_dist and dist < max_dist:
							min_dist = dist
							closest_cell = c
				
				if closest_cell:
					closest_cell.set_meta("dolu", false)
					if block_node and block_node.has_meta("occupying_cells"):
						var cells = block_node.get_meta("occupying_cells")
						if cells.has(closest_cell):
							cells.erase(closest_cell)
							block_node.set_meta("occupying_cells", cells)
					break 
					
	part_node.queue_free()
	
	if block_node:
		var has_parts = false
		for c in block_node.get_children():
			if c != part_node and "Part" in c.name and !c.is_queued_for_deletion():
				has_parts = true
				break
		if not has_parts:
			block_node.queue_free()

func _update_knife_hover():
	if outline_instance and is_instance_valid(outline_instance):
		outline_instance.queue_free()
		outline_instance = null
		
	if current_hovered_part and is_instance_valid(current_hovered_part):
		var mesh_node = current_hovered_part.find_child("Mesh*", true, false)
		if mesh_node and mesh_node is CSGBox3D:
			outline_instance = MeshInstance3D.new()
			var box = BoxMesh.new()
			box.size = mesh_node.size * 1.1 
			outline_instance.mesh = box
			
			var mat = StandardMaterial3D.new()
			mat.albedo_color = Color(1.0, 1.0, 0.0) 
			mat.cull_mode = BaseMaterial3D.CULL_FRONT
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			outline_instance.material_override = mat
			
			current_hovered_part.add_child(outline_instance)
			outline_instance.position = mesh_node.position

func pick_up_card(card_node: Node3D):
	if held_card != null: return
	
	# Store original desk data BEFORE reparenting
	if not card_data.has(card_node.name):
		card_data[card_node.name] = {
			"parent": card_node.get_parent(),
			"global_transform": card_node.global_transform,
			"scale": card_node.scale
		}
	
	held_card = card_node
	
	var g_trans = card_node.global_transform
	card_node.get_parent().remove_child(card_node)
	add_child(card_node)
	card_node.global_transform = g_trans
	
	# Disable interaction while held
	for cs in card_node.find_children("*", "CollisionShape3D", true, false):
		cs.disabled = true
	
	# Masanın altına girmemesi için her şeyin üstünde çizilmesini sağla
	_apply_no_depth_recursive(card_node, 12)

	var tw = create_tween().set_parallel(true)
	card_node.set_meta("active_tween", tw)
	
	var hand_pos = Vector3(0, -0.1, -0.2) 
	
	# Kart eğer fizik objesi ise hareketini donduralım ki gravity etki etmesin
	if card_node is RigidBody3D:
		card_node.freeze = true
	
	var hand_rot = Vector3(0, deg_to_rad(180), 0)
	
	tw.tween_property(card_node, "position", hand_pos, 0.4).set_trans(Tween.TRANS_SINE)
	tw.tween_property(card_node, "rotation", hand_rot, 0.4).set_trans(Tween.TRANS_SINE)
	tw.tween_property(card_node, "scale", card_node.scale.abs() * 0.4, 0.4).set_trans(Tween.TRANS_SINE)

func create_ghost_block(original_block: Node3D):
	if ghost_block: ghost_block.queue_free()
	
	ghost_block = original_block.duplicate()
	get_tree().root.add_child(ghost_block)
	
	# Hayaletin fizik etkileşimini sadece devre dışı bırak, KESİNLİKLE SİLME çünkü yer tespiti için lazım
	for c in ghost_block.find_children("*", "StaticBody3D", true, false):
		c.collision_layer = 0
		c.collision_mask = 0
	
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0, 1, 0, 0.5) # Yeşil
	
	for m in ghost_block.find_children("*", "CSGBox3D"):
		m.material = mat
		# Yassı önizleme için Y boyutunu baştan kıs
		m.size.y *= 0.33
	
	ghost_block.visible = false

func consume_held_card():
	if held_card == null: return
	
	var card_to_return = held_card
	held_card = null # Clear immediately to prevent double-click issues
	
	# 20% Chance for garbage card to enemy (for cards 1, 3, 4)
	if card_to_return.name in ["card", "card3", "card4"]:
		if randf() < 0.2:
			enemy_placement_mode = true
			return_card_to_table(card_to_return)
			trigger_paravan_sequence()
			return

	# Determine block scene
	var scenes = []
	if card_to_return.name == "card2":
		scenes = ["res://block_tek.tscn"]
	else:
		scenes = [
			"res://block_tek.tscn",
			"res://block_l.tscn",
			"res://block_t.tscn",
			"res://block_kare.tscn",
			"res://block_line.tscn"
		]
	
	var random_scene = scenes[randi() % scenes.size()]
	var block_scene = load(random_scene)
	if block_scene:
		spawn_block_on_table(block_scene)
		
	return_card_to_table(card_to_return)

func return_card_to_table(card_node: Node3D):
	if not card_data.has(card_node.name): 
		card_node.queue_free()
		return
		
	var data = card_data[card_node.name]
	
	# Kill any existing tweens to prevent rubber-banding back to hand
	if card_node.has_meta("active_tween"):
		var old_tw = card_node.get_meta("active_tween")
		if old_tw and old_tw.is_valid():
			old_tw.kill()
		card_node.remove_meta("active_tween")
	
	# Instant detach from camera
	if card_node.get_parent():
		card_node.get_parent().remove_child(card_node)
	
	# Instant visual reset
	_remove_no_depth_recursive(card_node)
	
	# Reparent back to table and reset transform immediately
	data.parent.add_child(card_node)
	card_node.global_transform = data.global_transform
	card_node.scale = data.scale
	
	# Ensure collision is re-enabled instantly
	for cs in card_node.find_children("*", "CollisionShape3D", true, false):
		cs.disabled = false

func trigger_paravan_sequence():
	# Animasyon ve kamera hareketi başlat
	var paravan_cam = get_tree().root.find_child("ParavanKamerasi", true, false)
	var paravan_node = get_tree().root.find_child("paravan", true, false)
	
	if paravan_cam and paravan_node:
		is_locked = true
		
		# 1- Önce kamerayı yavaşça default ortalanmış açısına çekelim
		var rot_tw = create_tween().set_parallel(true)
		rot_tw.tween_property(self, "rotation_degrees:y", start_y, 0.4).set_trans(Tween.TRANS_SINE)
		rot_tw.tween_property(self, "rotation_degrees:x", start_x, 0.4).set_trans(Tween.TRANS_SINE)
		await rot_tw.finished
		
		# Temel yerimizi kaydet (Geri dönmek için)
		original_camera_transform = global_transform
		original_camera_rotation_degrees = rotation_degrees
		
		var anim_player = paravan_node.find_child("AnimationPlayer", true, false)
		
		# Güvenlik önlemi: Eğer paravan içinde değilse kök sahnede veya GameRoom'da da arayalim.
		if not anim_player:
			anim_player = get_tree().root.find_child("AnimationPlayer", true, false)
			
		if anim_player:
			var target_anim = "paravan_ac"
			if not anim_player.has_animation(target_anim):
				target_anim = anim_player.get_animation_list()[0]
				
			# Hızı 2 katına çıkar
			anim_player.speed_scale = 2.0
			anim_player.play(target_anim)
			
			# Animasyonun tam yarısını hesapla (Hız 2 olduğu için bekleyeceğimiz süre / 2 olur)
			var half_time = anim_player.current_animation_length / 2.0
			await get_tree().create_timer(half_time / 2.0).timeout
			
			# Yarıda dondur (Böylece geriye kalanı dönerken kapanış için oynatılabilecek)
			anim_player.pause()
		else:
			await get_tree().create_timer(1.0).timeout
		
		# 2- Paravan yarıya kadar açıldı (durdu), ŞİMDİ kamerayı hareket ettiriyoruz
		var tw = create_tween()
		tw.tween_property(self, "global_transform", paravan_cam.global_transform, 1.0).set_trans(Tween.TRANS_SINE)
		tw.tween_callback(func():
			var euler = paravan_cam.rotation_degrees
			start_y = euler.y
			start_x = euler.x
			yaw = euler.y
			pitch = euler.x
			rotation_degrees = euler
			is_locked = false # İzin ver etrafa baksın
			
			# Çöp objeyi eline alan logic'i tetikliyoruz. Yerde belirmeden!
			var block_scene = load("res://block_cop.tscn")
			if block_scene:
				held_block = block_scene.instantiate()
				# scale_factor hesabı
				var size = 0.1 
				var grid_gen = get_tree().root.find_child("DüşmanGrid", true, false)
				if grid_gen and grid_gen.get("hucre_boyutu"):
					size = grid_gen.hucre_boyutu
				var scale_factor = size / 0.1
				held_block.scale = Vector3(scale_factor, scale_factor, scale_factor)
				
				add_child(held_block)
				held_block.position = Vector3(-0.25, -0.05, -0.4)
				held_block.rotation = Vector3(deg_to_rad(20), deg_to_rad(35), 0)
				
				for sb in held_block.find_children("*", "StaticBody3D"):
					sb.collision_layer = 0
					sb.collision_mask = 0
					
				create_ghost_block(held_block)
		)

func spawn_block_on_table(block_scene: PackedScene):
	var spawned_block = block_scene.instantiate()
	var marker = get_tree().root.find_child("BlokSpawnNoktasi", true, false)
	if marker:
		marker.get_parent().add_child(spawned_block)
		spawned_block.global_position = marker.global_position
		
		var size = 0.1 
		var grid_gen = get_tree().root.find_child("OyuncuGrid", true, false)
		if grid_gen and grid_gen.get("hucre_boyutu"):
			size = grid_gen.hucre_boyutu
			
		var scale_factor = size / 0.1
		spawned_block.scale = Vector3(scale_factor, scale_factor, scale_factor)
		
		for sb in spawned_block.find_children("*", "StaticBody3D"):
			sb.set_meta("is_block", true)
			sb.set_meta("block_node", spawned_block)
		spawned_block.set_meta("placed", false)

func pick_up_block(block_node):
	held_block = block_node
	
	# Block'u kameraya bağla
	var g_trans = held_block.global_transform
	held_block.get_parent().remove_child(held_block)
	add_child(held_block)
	held_block.global_transform = g_trans
	
	# Anlayabileceğimiz çok iyi bir açıyla (isometric) ekranın biraz daha sol/aşağı kısmına koyalım
	var tw = create_tween().set_parallel(true)
	tw.tween_property(held_block, "position", Vector3(-0.25, -0.05, -0.4), 0.3).set_trans(Tween.TRANS_SINE)
	tw.tween_property(held_block, "rotation", Vector3(deg_to_rad(20), deg_to_rad(35), 0), 0.3).set_trans(Tween.TRANS_SINE)
	
	# Tutarken tüm parçaların çarpışmasını kapat
	for sb in held_block.find_children("*", "StaticBody3D"):
		sb.collision_layer = 0
		sb.collision_mask = 0
		
	var size = 0.1
	var grid_gen = get_tree().root.find_child("OyuncuGrid", true, false)
	if grid_gen and grid_gen.get("hucre_boyutu"):
		size = grid_gen.hucre_boyutu
		
	create_ghost_block(held_block)

func update_block_preview():
	if ghost_block == null: return
	
	var space_state = get_world_3d().direct_space_state
	var v_size = get_viewport().get_visible_rect().size
	var center = v_size / 2.0
	var origin = project_ray_origin(center)
	var end = origin + project_ray_normal(center) * ray_length
	var query = PhysicsRayQueryParameters3D.create(origin, end)
	var result = space_state.intersect_ray(query)
	
	current_hovered_cell = null
	is_placement_valid = false
	ghost_block.visible = false
	
	if result and result.collider.has_meta("is_grid_cell"):
		ghost_block.visible = true
		current_hovered_cell = result.collider.get_meta("grid_cell_node")
		
		# Pivotu merkeze hizala, azıcık yukarı kaldır ve döndürmeyi sıfırla/hizala
		var base_y_offset = 0.0165
		ghost_block.global_position = current_hovered_cell.global_position + current_hovered_cell.global_transform.basis.y * base_y_offset
		ghost_block.global_rotation = current_hovered_cell.global_rotation
		
		# Çok hücreli (Multi-mesh) bloklar için tam doğrulama
		is_placement_valid = true
		var target_cells = []
		
		# Hedef grid'i belirle (Düşman veya Oyuncu)
		var active_grid_name = "DüşmanGrid" if enemy_placement_mode else "OyuncuGrid"
		var grid_gen = get_tree().root.find_child(active_grid_name, true, false)
		
		var b_size = 0.1
		if grid_gen and grid_gen.get("hucre_boyutu"):
			b_size = grid_gen.hucre_boyutu
			
		var max_dist = b_size / 1.5 
		
		# Artık görseller farklı bir mesh (GLTF) olabileceğinden çarpışma kutularının merkezlerini baz alıyoruz
		# Duplicate işleminde owner silindiği için owned=false zorunludur!
		for m in ghost_block.find_children("*", "CollisionShape3D", true, false):
			# Koordinat dönüşümünü grid uzayına çekerek hesaplamayı tablo eğik bile olsa doğru yapalım
			var m_local = grid_gen.to_local(m.global_position) if grid_gen else m.global_position
			var closest_cell = null
			var min_dist = 999.0
			
			if grid_gen:
				for c in grid_gen.get_children():
					if "sutun" in c: # GridHucre düğümü olduğunu anlamak için
						var c_local = grid_gen.to_local(c.global_position)
						var dist = Vector2(m_local.x, m_local.z).distance_to(Vector2(c_local.x, c_local.z))
						if dist < min_dist and dist < max_dist:
							min_dist = dist
							closest_cell = c
							
			if closest_cell:
				var is_full = closest_cell.get_meta("dolu") if closest_cell.has_meta("dolu") else false
				if is_full:
					is_placement_valid = false
					break
				else:
					if not target_cells.has(closest_cell):
						target_cells.append(closest_cell)
			else:
				# Taşıyor (Uygun bir hücre bulunamadı)
				is_placement_valid = false
				break
				
		var color = Color(0, 1, 0, 0.5) if is_placement_valid else Color(1, 0, 0, 0.5)
		
		# Hayaletin üstündeki herhangi bir CSGBox veya Mesh varsa rengini boya
		for m in ghost_block.find_children("*", "CSGBox3D", true, false):
			if m.material: m.material.albedo_color = color
			
		for m in ghost_block.find_children("*", "MeshInstance3D", true, false):
			if m.get_surface_override_material(0):
				m.get_surface_override_material(0).albedo_color = color
				
		ghost_block.set_meta("target_cells", target_cells)

func place_held_block():
	# Sol üstteki bloğu siluet(ghost) bloğun pozisyonuna doğru uçur (fırlat)
	var tw = create_tween()
	var target_global_pos = ghost_block.global_position
	var target_global_rot = ghost_block.global_rotation
	
	# Bloğu kameradan çıkar, dünyaya ekle ki bağımsız dursun
	var g_trans = held_block.global_transform
	remove_child(held_block)
	get_tree().root.add_child(held_block)
	held_block.global_transform = g_trans
	
	tw.tween_property(held_block, "global_position", target_global_pos, 0.2).set_trans(Tween.TRANS_SINE)
	tw.tween_property(held_block, "rotation", target_global_rot, 0.2).set_trans(Tween.TRANS_SINE)
	
	# Yere inerken tüm çocuk meshleri 1x0.33x1'e yassılaşsın
	for m in held_block.find_children("*", "CSGBox3D"):
		tw.tween_property(m, "size:y", m.size.y * 0.33, 0.2).set_trans(Tween.TRANS_SINE)
		
	for s in held_block.find_children("*", "CollisionShape3D", true, false):
		if s.shape is BoxShape3D:
			s.shape.size.y *= 0.33
		
	# Kapladığı bütün hücreleri dolu olarak işaretle
	var assigned_cells = []
	if ghost_block.has_meta("target_cells"):
		var targets = ghost_block.get_meta("target_cells")
		for t in targets:
			t.set_meta("dolu", true)
			assigned_cells.append(t)
			
	# Bıçak silmesi için bunları kaydediyoruz
	held_block.set_meta("occupying_cells", assigned_cells)
	
	# Bloğa yerleştirildi damgası vur (Artık raycast ile alılamaz!)
	held_block.set_meta("placed", true)
	
	var temp_block = held_block
	held_block = null
	
	if ghost_block: 
		ghost_block.queue_free()
		ghost_block = null
		
	# Yere indiğinde tüm fizik alanlarını aç ki tıklanabilsin
	tw.tween_callback(func():
		if temp_block and is_instance_valid(temp_block):
			for sb in temp_block.find_children("*", "StaticBody3D"):
				sb.collision_layer = 1
				sb.collision_mask = 1
				
		# Düşman modu geri dönüş lojiği
		if enemy_placement_mode:
			enemy_placement_mode = false
			is_locked = true
			
			var ret_tw = create_tween()
			ret_tw.tween_property(self, "global_transform", original_camera_transform, 1.0).set_trans(Tween.TRANS_SINE).set_delay(0.5)
			
			# Kamera yerine ulaşıp geri döndükten SONRA paravanı kapatalım
			ret_tw.tween_callback(func():
				var paravan_node = get_tree().root.find_child("paravan", true, false)
				var anim_player = null
				if paravan_node:
					anim_player = paravan_node.find_child("AnimationPlayer", true, false)
				if not anim_player:
					anim_player = get_tree().root.find_child("AnimationPlayer", true, false)
					
				if anim_player:
					# Kapatmak için dondurduğumuz yerden kaldığı gibi devam ettir!
					anim_player.speed_scale = 2.0
					anim_player.play()
						
				var euler = original_camera_rotation_degrees
				start_y = euler.y
				start_x = euler.x
				yaw = euler.y
				pitch = euler.x
				rotation_degrees = euler
				is_locked = false
				
				# Check if board or a row is full after placement
				if is_row_complete() or is_grid_full():
					activate_gun()
				else:
					switch_turn()
			)
		else:
			# Regular placement check
			if is_row_complete() or is_grid_full():
				activate_gun()
			else:
				switch_turn()
	)

func is_grid_full() -> bool:
	var grid = get_tree().root.find_child("OyuncuGrid", true, false)
	if not grid: return false
	
	for cell in grid.get_children():
		if cell.has_method("setup"): # GridHucre identifier
			if not cell.has_meta("dolu") or cell.get_meta("dolu") == false:
				return false
	return true

func is_row_complete() -> bool:
	var grid = get_tree().root.find_child("OyuncuGrid", true, false)
	if not grid or not grid.get("hucrelerin_sozlugu"): return false
	
	var cells = grid.hucrelerin_sozlugu
	for r in range(grid.satir_sayisi):
		var row_full = true
		for s in range(grid.sutun_sayisi):
			var cell = cells.get(Vector2i(s, r))
			if not cell or not cell.has_meta("dolu") or cell.get_meta("dolu") == false:
				row_full = false
				break
		if row_full:
			return true
	return false

func activate_gun():
	if not gun_node or is_gun_mode: return
	is_gun_mode = true
	is_locked = true 
	
	# THE PRO STRUCTURAL FIX: Overlay Viewport Reparenting
	if gun_node.get_parent(): gun_node.get_parent().remove_child(gun_node)
	if overlay_viewport:
		overlay_viewport.add_child(gun_node)
	else:
		add_child(gun_node)
		
	# Move Gun to Viewmodel Layer (Layer 2)
	_set_layer_recursive(gun_node, 2)
	
	# BOOSTED SCALE (Visual clarity)
	var scale_factor = 0.75
	gun_node.scale = gun_original_scale * scale_factor
	
	# Natural Viewmodel Position (Right Middle Bottom)
	gun_node.position = Vector3(0.5, -1.2, -0.4) # Starting lower for rise
	gun_node.rotation = Vector3(deg_to_rad(-45), deg_to_rad(-80), 0)
	
	# Glow/Highlight
	_apply_gun_glow_recursive(gun_node, true)
	
	var tw = create_tween().set_parallel(true)
	var target_pos = Vector3(0.5, -0.4, -0.6) 
	var target_rot = Vector3(deg_to_rad(0), deg_to_rad(-80), 0)
	
	tw.tween_property(gun_node, "position", target_pos, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(gun_node, "rotation", target_rot, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	# Constant vibration during rise
	for i in range(12):
		tw.tween_property(gun_node, "position", Vector3(randf_range(-0.01, 0.01), randf_range(-0.01, 0.01), 0), 0.05).as_relative()
	
	await tw.finished
	is_locked = false

func _set_layer_recursive(node: Node, layer_index: int):
	if node is VisualInstance3D:
		node.layers = (1 << (layer_index - 1))
	for child in node.get_children():
		_set_layer_recursive(child, layer_index)

func shoot_gun():
	if not is_gun_mode: return
	
	# TRUE RUSSIAN ROULETTE LOGIC (Stateful Chamber Check)
	var is_hit = (current_chamber_index == bullet_chamber_index)
	print("CLICK! Chamber ", current_chamber_index + 1, " / 6. Result: ", "BANG!" if is_hit else "Empty")
	
	if is_hit:
		# BULLET FIRED!
		var anim = gun_node.find_child("AnimationPlayer", true, false)
		if anim:
			anim.play("Animation") 
		
		# Hit detection
		var space_state = get_world_3d().direct_space_state
		var v_size = get_viewport().get_visible_rect().size
		var center = v_size / 2.0
		var origin = project_ray_origin(center)
		# EXTENDED RANGE to 100 meters
		var end = origin + project_ray_normal(center) * 100.0
		var query = PhysicsRayQueryParameters3D.create(origin, end)
		query.collision_mask = 2 # ONLY CHECK LAYER 2 (Enemy)
		query.collide_with_areas = true 
		var result = space_state.intersect_ray(query)
		
		var aimed_at_enemy = false
		if result:
			var node = result.collider
			print("BULLET HIT SOMETHING: ", node.name, " (at pos: ", result.position, ")")
			while node != null:
				if "Sitting" in node.name or node.has_meta("is_enemy"):
					aimed_at_enemy = true
					break
				node = node.get_parent()
		else:
			print("BULLET HIT NOTHING (Void)")
		
		if aimed_at_enemy:
			print("BULLET HIT ENEMY! SPAWNING AT: ", result.position)
			# Hit Payoff (JUICE)
			spawn_blood_vfx(result.position)
			shake_intensity = 1.0 # Stronger shake
			shake_duration = 0.5
			
			# HUD Hit Polish (Visual Impact)
			var control = get_tree().root.find_child("Control", true, false)
			if control:
				# Screen Flash
				var flash = ColorRect.new()
				flash.color = Color(1.0, 0, 0, 0.7) # Saturated Red
				flash.set_anchors_preset(Control.PRESET_FULL_RECT)
				control.add_child(flash)
				
				# Fade out flash
				var ftw = create_tween()
				ftw.tween_property(flash, "color:a", 0.0, 0.2).set_delay(0.05)
				ftw.tween_callback(flash.queue_free)
			
			# GUN RECOIL (Kick)
			if gun_node:
				var gtw = create_tween()
				var recoil_pos = gun_node.position + Vector3(0, 0.05, 0.15)
				gtw.tween_property(gun_node, "position", recoil_pos, 0.08).set_trans(Tween.TRANS_SINE)
				gtw.tween_property(gun_node, "position", Vector3(0.5, -0.4, -0.6), 0.2).set_trans(Tween.TRANS_BACK)
			
			# SLOW MOTION START (60% slow)
			Engine.time_scale = 0.4
			print("SLOW-MO START (1.5s)")
			
			# Wait in real-time (not scaled time)
			await get_tree().create_timer(1.5, true, false, true).timeout 
			
			Engine.time_scale = 1.0
			print("SLOW-MO END")
			
			# Bullet fired, reset revolver cycle
			reset_revolver()
			reset_game_round()
			stand_up()
			# No switch turn here, player wins/stands up
		else:
			print("BULLET WASTED (MISSED)")
			# Even if miss, we reset revolver because the bullet is gone
			reset_revolver()
			get_tree().create_timer(2.0).timeout.connect(func():
				reset_game_round()
				switch_turn() # Switches to Enemy
			)
	else:
		# EMPTY CHAMBER (advances to next index)
		current_chamber_index += 1
		if current_chamber_index >= 6:
			reset_revolver()
			
		print("CLICK! Empty chamber. Moving to ", current_chamber_index + 1)
		get_tree().create_timer(1.0).timeout.connect(func():
			reset_game_round()
			switch_turn() # Switches to Enemy
		)

func _handle_discard_hover():
	if not discard_label: return
	
	var space_state = get_world_3d().direct_space_state
	var v_size = get_viewport().get_visible_rect().size
	var center = v_size / 2.0
	var origin = project_ray_origin(center)
	var end = origin + project_ray_normal(center) * ray_length
	var query = PhysicsRayQueryParameters3D.create(origin, end)
	var result = space_state.intersect_ray(query)
	
	if result and result.collider.has_meta("is_trash"):
		discard_label.visible = true
		# Vibration effect
		var offset = Vector2(randf_range(-3, 3), randf_range(-3, 3))
		discard_label.position = discard_label_base_pos + offset
	else:
		discard_label.visible = false

func discard_held_block():
	if not held_block: return
	
	var block_to_discard = held_block
	held_block = null
	
	if ghost_block:
		ghost_block.queue_free()
		ghost_block = null
		
	var tw = create_tween().set_parallel(true)
	var target_pos = trash_node.global_position if trash_node else global_position + Vector3(0, -2, 0)
	
	tw.tween_property(block_to_discard, "global_position", target_pos, 0.4).set_trans(Tween.TRANS_SINE)
	tw.tween_property(block_to_discard, "scale", Vector3.ZERO, 0.4).set_trans(Tween.TRANS_SINE)
	tw.set_parallel(false)
	tw.tween_callback(block_to_discard.queue_free)
	
	if discard_label:
		discard_label.visible = false
	
	switch_turn()

func reset_game_round():
	is_gun_mode = false
	
	# Clear Player Grid
	var p_grid = get_tree().root.find_child("OyuncuGrid", true, false)
	if p_grid: p_grid.clear_grid()
	
	# Clear Enemy Grid
	var e_grid = get_tree().root.find_child("DüşmanGrid", true, false)
	if e_grid: e_grid.clear_grid()
	
	# Clear any other blocks in root
	for child in get_tree().root.get_children():
		if child.has_meta("placed") and child.get_meta("placed"):
			child.queue_free()
			
	# Return Gun to Table
	if gun_node:
		# Reset visuals
		_apply_gun_glow_recursive(gun_node, false)
		_set_layer_recursive(gun_node, 1)
		
		# Reset Scale
		gun_node.scale = gun_original_scale
		
		# Reparent back to world
		var g_trans = gun_node.global_transform
		if gun_node.get_parent(): gun_node.get_parent().remove_child(gun_node)
		get_tree().current_scene.add_child(gun_node)
		gun_node.global_transform = g_trans
		
		var tw = create_tween()
		tw.tween_property(gun_node, "global_transform", gun_original_transform, 0.5).set_trans(Tween.TRANS_SINE)

func spawn_blood_vfx(pos: Vector3):
	# BULLETPROOF MANUAL SPLATTER BURST
	# (Bypasses Particle Rendering Bugs)
	var splat_count = 20
	for i in range(splat_count):
		var sphere = MeshInstance3D.new()
		sphere.mesh = SphereMesh.new()
		sphere.mesh.radius = randf_range(0.08, 0.18)
		sphere.mesh.height = sphere.mesh.radius * 2.0
		
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0, 0)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0, 0)
		mat.emission_energy_multiplier = 4.0
		mat.no_depth_test = true # Nuclear visibility
		mat.render_priority = 120
		sphere.mesh.material = mat
		
		# Add to Viewport or Scene
		if overlay_viewport:
			overlay_viewport.add_child(sphere)
		else:
			get_tree().current_scene.add_child(sphere)
			
		sphere.global_position = pos
		sphere.layers = (1 << 0) | (1 << 1)
		
		# Animate from Head to Camera
		var cam_local_pos = global_position + Vector3(randf_range(-1, 1), randf_range(-1, 1), 0)
		var target_pos = lerp(pos, cam_local_pos, 0.9) # Flies towards you but stays slightly in front
		
		var btw = create_tween().set_parallel(true)
		btw.tween_property(sphere, "global_position", target_pos, randf_range(0.3, 0.6)).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		btw.tween_property(sphere, "scale", Vector3.ZERO, randf_range(0.4, 0.7)).set_delay(0.2)
		btw.tween_callback(sphere.queue_free).set_delay(0.8)

func _apply_gun_glow_recursive(node: Node, active: bool):
	if node is MeshInstance3D:
		for i in range(node.get_surface_override_material_count()):
			var mat = node.get_surface_override_material(i)
			if active:
				if not mat: mat = node.mesh.surface_get_material(i).duplicate()
				if mat is BaseMaterial3D:
					mat.emission_enabled = true
					mat.emission = Color(1.0, 1.0, 0.5) # Yellow glow
					mat.emission_energy_multiplier = 0.5
				node.set_surface_override_material(i, mat)
			else:
				node.set_surface_override_material(i, null)
	
	for child in node.get_children():
		_apply_gun_glow_recursive(child, active)

func switch_turn():
	if is_game_over: return
	
	if current_turn == Turn.PLAYER:
		current_turn = Turn.ENEMY
		print("--- ENEMY TURN ---")
		start_enemy_turn()
	else:
		current_turn = Turn.PLAYER
		print("--- PLAYER TURN ---")

func start_enemy_turn():
	await get_tree().create_timer(1.5).timeout # Thinking delay
	
	# 20% Chance for trash card to player
	var target_grid_name = "DüşmanGrid"
	var is_trash_attempt = (randf() < 0.2)
	
	# Determine block scene
	var scenes = [
		"res://block_tek.tscn",
		"res://block_l.tscn",
		"res://block_t.tscn",
		"res://block_kare.tscn",
		"res://block_line.tscn"
	]
	var block_scene = load(scenes[randi() % scenes.size()])
	var temp_block = block_scene.instantiate()
	
	var grid = get_tree().root.find_child("DüşmanGrid", true, false)
	var move = find_ai_move(temp_block, grid)
	
	if move.size() > 0:
		# Always place its own block first
		ai_place_block(temp_block, move, grid, is_trash_attempt)
	else:
		# AI couldn't find a move
		temp_block.queue_free()
		if is_trash_attempt:
			# Even if no regular move, maybe can send trash? 
			# But usually AI should always have a move early on.
			ai_process_trash_only()
		else:
			switch_turn()

func ai_process_trash_only():
	var trash_block = load("res://block_cop.tscn").instantiate()
	var grid = get_tree().root.find_child("OyuncuGrid", true, false)
	var move = find_ai_move(trash_block, grid)
	if move.size() > 0:
		enemy_send_trash_to_player(trash_block, move)
	else:
		trash_block.queue_free()
		switch_turn()

func find_ai_move(block_node: Node3D, grid: GridOlusturucu) -> Dictionary:
	var cell_list = grid.hucrelerin_sozlugu.values()
	cell_list.shuffle()
	
	var b_size = grid.hucre_boyutu
	var max_dist = b_size / 1.5
	
	for start_cell in cell_list:
		for rot_idx in range(4):
			block_node.rotation_degrees.y = rot_idx * 90
			var can_place = true
			var target_cells = []
			
			# Temporary attach to tree to get global transforms
			if not block_node.is_inside_tree():
				get_tree().current_scene.add_child(block_node)
			
			for m in block_node.find_children("*", "CollisionShape3D", true, false):
				block_node.global_position = start_cell.global_position
				var m_local = grid.to_local(m.global_position)
				var closest_cell = null
				var min_dist = 999.0
				
				for c in grid.get_children():
					if "sutun" in c:
						var c_local = grid.to_local(c.global_position)
						var dist = Vector2(m_local.x, m_local.z).distance_to(Vector2(c_local.x, c_local.z))
						if dist < min_dist and dist < max_dist:
							min_dist = dist
							closest_cell = c
				
				if closest_cell and not closest_cell.get_meta("dolu", false):
					if not target_cells.has(closest_cell):
						target_cells.append(closest_cell)
				else:
					can_place = false
					break
			
			if can_place and target_cells.size() > 0:
				# Detach before returning so it can be handled by the caller
				if block_node.get_parent(): block_node.get_parent().remove_child(block_node)
				return {"cell": start_cell, "rotation": block_node.rotation_degrees.y, "target_cells": target_cells}
	
	if block_node.get_parent(): block_node.get_parent().remove_child(block_node)
	return {}

func ai_place_block(block_node: Node3D, move: Dictionary, grid: GridOlusturucu, trigger_trash: bool = false):
	get_tree().current_scene.add_child(block_node)
	block_node.global_position = move.cell.global_position
	block_node.rotation_degrees.y = move.rotation
	
	var scale_factor = grid.hucre_boyutu / 0.1
	block_node.scale = Vector3(scale_factor, scale_factor, scale_factor)
	
	for m in block_node.find_children("*", "CSGBox3D"):
		m.size.y *= 0.33
	for s in block_node.find_children("*", "CollisionShape3D", true, false):
		if s.shape is BoxShape3D: s.shape.size.y *= 0.33
	
	for t in move.target_cells:
		t.set_meta("dolu", true)
	
	block_node.set_meta("placed", true)
	block_node.set_meta("occupying_cells", move.target_cells)
	
	# Small delay before next action
	await get_tree().create_timer(0.5).timeout
	
	if trigger_trash:
		ai_process_trash_only()
	elif is_row_complete_on_grid(grid) or is_grid_full_on_grid(grid):
		enemy_shoot_sequence()
	else:
		switch_turn()

func is_row_complete_on_grid(grid: GridOlusturucu) -> bool:
	if not grid or not grid.get("hucrelerin_sozlugu"): return false
	var cells = grid.hucrelerin_sozlugu
	for r in range(grid.satir_sayisi):
		var row_full = true
		for s in range(grid.sutun_sayisi):
			var cell = cells.get(Vector2i(s, r))
			if not cell or not cell.has_meta("dolu") or cell.get_meta("dolu") == false:
				row_full = false
				break
		if row_full: return true
	return false

func is_grid_full_on_grid(grid: GridOlusturucu) -> bool:
	if not grid: return false
	for cell in grid.get_children():
		if "sutun" in cell:
			if not cell.has_meta("dolu") or cell.get_meta("dolu") == false:
				return false
	return true

func enemy_shoot_sequence():
	var sitting = get_tree().root.find_child("Sitting", true, false)
	var anim_player = null
	if sitting: anim_player = sitting.find_child("AnimationPlayer", true, false)
	
	if not anim_player:
		switch_turn()
		return

	# 1. STAND UP (Geri otur tersten)
	# Move Sitting node forward to avoid clipping into the wall
	var sit_tw = create_tween()
	sit_tw.tween_property(sitting, "global_position:z", sitting.global_position.z + 0.5, 0.5).set_trans(Tween.TRANS_SINE)
	
	anim_player.play("geri_otur", -1, -2.0, true)
	await anim_player.animation_finished
	
	# 2. TAKE GUN
	anim_player.play("take_gun")
	# Visually move gun to enemy's general direction
	var gun_tw = create_tween().set_parallel(true)
	gun_tw.tween_property(gun_node, "global_position", sitting.global_position + Vector3(0, 1.0, 0.5), 0.5)
	gun_tw.tween_property(gun_node, "global_rotation", Vector3(0, deg_to_rad(180), 0), 0.5)
	await anim_player.animation_finished

	# 3. FIRE
	anim_player.play("enemy_gun")
	await get_tree().create_timer(0.4).timeout # Wait for bang moment in animation
	
	# 4. RESULTS
	var is_hit = (current_chamber_index == bullet_chamber_index)
	if is_hit:
		# BLOOD STRIKE ON PLAYER (Camera FX)
		trigger_player_death()
	else:
		# CLICK!
		current_chamber_index += 1
		if current_chamber_index >= 6: reset_revolver()
		
		# Return Gun
		var ret_tw = create_tween()
		ret_tw.tween_property(gun_node, "global_transform", gun_original_transform, 0.5)
		
		# Sit back down
		var sit_ret_tw = create_tween()
		sit_ret_tw.tween_property(sitting, "global_position:z", sitting.global_position.z - 0.5, 0.5).set_trans(Tween.TRANS_SINE)
		
		anim_player.play("geri_otur")
		await anim_player.animation_finished
		anim_player.play("oturma1")
		
		reset_game_round()
		switch_turn()

func enemy_send_trash_to_player(block_node: Node3D, move_data: Dictionary):
	# Paravan opens, player sees trash falling onto their grid
	print("ENEMY SENDING TRASH...")
	
	# 1. Trigger Paravan sequence visually for the player
	var paravan_node = get_tree().root.find_child("paravan", true, false)
	var anim_player = null
	if paravan_node: anim_player = paravan_node.find_child("AnimationPlayer", true, false)
	
	if anim_player:
		var target_anim = "paravan_ac"
		if not anim_player.has_animation(target_anim):
			target_anim = anim_player.get_animation_list()[0]
			
		anim_player.speed_scale = 2.0
		anim_player.play(target_anim) 
		await get_tree().create_timer(0.5).timeout
		
	# 2. Spawn Block
	get_tree().current_scene.add_child(block_node)
	block_node.global_position = move_data.cell.global_position + Vector3(0, 0.5, 0) # Drop from above
	block_node.rotation_degrees.y = move_data.rotation
	var scale_factor = 0.1 # Default scale
	var p_grid = get_tree().root.find_child("OyuncuGrid", true, false)
	if p_grid: scale_factor = p_grid.hucre_boyutu / 0.1
	block_node.scale = Vector3(scale_factor, scale_factor, scale_factor)
	
	# Drop Tween
	var tw = create_tween()
	tw.tween_property(block_node, "global_position", move_data.cell.global_position, 0.5).set_trans(Tween.TRANS_BOUNCE)
	
	# Set occupation
	block_node.set_meta("placed", true)
	block_node.set_meta("occupying_cells", move_data.target_cells)
	for t in move_data.target_cells:
		t.set_meta("dolu", true)
		
	# 3. Close Paravan
	await get_tree().create_timer(0.5).timeout
	if anim_player:
		var target_anim = "paravan_ac"
		if not anim_player.has_animation(target_anim):
			target_anim = anim_player.get_animation_list()[0]
			
		anim_player.play_backwards(target_anim)
		await anim_player.animation_finished
		
	switch_turn()

func trigger_player_death():
	is_game_over = true
	is_locked = true
	
	# FALL DOWN
	var tw = create_tween().set_parallel(true)
	tw.tween_property(self, "rotation_degrees:z", 75.0, 1.2).set_trans(Tween.TRANS_BOUNCE)
	tw.tween_property(self, "rotation_degrees:x", 15.0, 1.2).set_trans(Tween.TRANS_BOUNCE)
	tw.tween_property(self, "position:y", position.y - 0.4, 1.2).set_trans(Tween.TRANS_BOUNCE)
	
	# RED BLOOM
	var control = get_tree().root.find_child("Control", true, false)
	var red = ColorRect.new()
	red.color = Color(1, 0, 0, 0)
	red.set_anchors_preset(Control.PRESET_FULL_RECT)
	control.add_child(red)
	tw.tween_property(red, "color:a", 0.6, 0.4)
	
	# FADE TO BLACK
	var black = ColorRect.new()
	black.color = Color(0, 0, 0, 0)
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	control.add_child(black)
	
	tw.set_parallel(false)
	tw.tween_property(black, "color:a", 1.0, 2.0).set_delay(1.0)
	
	tw.tween_callback(setup_death_menu)

func setup_death_menu():
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var control = get_tree().root.find_child("Control", true, false)
	
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	# Center it
	vbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	vbox.grow_vertical = Control.GROW_DIRECTION_BOTH
	control.add_child(vbox)
	
	var try_again = Button.new()
	try_again.text = "TRY AGAIN"
	try_again.pressed.connect(func(): get_tree().reload_current_scene())
	vbox.add_child(try_again)
	
	var quit = Button.new()
	quit.text = "QUIT"
	quit.pressed.connect(func(): get_tree().quit())
	vbox.add_child(quit)
	
	# Styling buttons
	for b in [try_again, quit]:
		b.custom_minimum_size = Vector2(200, 60)
