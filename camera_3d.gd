extends Camera3D

@export var sensitivity = 0.08
@export var limit_y = 100.0  # Horizontal (Left/Right)
@export var limit_x = 75.0  # Vertical (Up/Down)

var yaw: float = 0.0
var pitch: float = 0.0
var start_y: float = 0.0
var start_x: float = 0.0
var is_locked: bool = false

var ray_length: float = 10.0
var held_card: Node3D = null
var held_block: Node3D = null

# Shake Params
var shake_intensity: float = 0.0
var shake_duration: float = 0.0
var shake_offset: Vector3 = Vector3.ZERO

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
	
	setup_viewmodel_rendering()
	
	# Kartlara kod üzerinden bir fizik alanı (Hitbox) ekleyelim ki raycast ile tıklayabilelim
	for card_name in ["card", "card2"]:
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
	if node is MeshInstance3D:
		for i in range(node.get_surface_override_material_count()):
			var mat = node.get_surface_override_material(i)
			if not mat:
				if node.mesh:
					mat = node.mesh.surface_get_material(i)
			
			if mat:
				var new_mat = mat.duplicate()
				if new_mat is StandardMaterial3D:
					new_mat.no_depth_test = true
					new_mat.render_priority = priority
				node.set_surface_override_material(i, new_mat)
	
	for child in node.get_children():
		_apply_no_depth_recursive(child, priority)

func _input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if held_block != null:
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
		yaw = clamp(yaw, start_y - limit_y, start_y + limit_y)
		pitch = clamp(pitch, start_x - limit_x, start_x + limit_x)

func _process(_delta):
	if is_locked: return
	
	if held_block != null:
		update_block_preview()
	
	# Shake logic
	if shake_duration > 0:
		shake_duration -= _delta
		var current_intensity = shake_intensity * (shake_duration / shake_duration + 0.1) # Decaying
		shake_offset = Vector3(
			randf_range(-1, 1) * current_intensity,
			randf_range(-1, 1) * current_intensity,
			0
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
		if collider.has_meta("is_card"):
			var card_node = collider.get_meta("card_node")
			if card_node:
				pick_up_card(card_node)
		elif collider.has_meta("is_block"):
			var block_node = collider.get_meta("block_node")
			if block_node and not block_node.get_meta("placed"):
				pick_up_block(block_node)

func pick_up_card(card_node: Node3D):
	if held_card != null: return
	held_card = card_node
	
	var g_trans = card_node.global_transform
	card_node.get_parent().remove_child(card_node)
	add_child(card_node)
	card_node.global_transform = g_trans
	
	# Masanın altına girmemesi için her şeyin üstünde çizilmesini sağla
	_apply_no_depth_recursive(card_node, 12)
	
	var tw = create_tween().set_parallel(true)
	var hand_pos = Vector3(0, -0.25, -0.5) # Ekranın alt ortası
	
	# Kartın dikey ve düzgün görünmesi için rotasyonları - gltf modelinin iç koordinatlarına bağlı
	var hand_rot = Vector3(deg_to_rad(-90), deg_to_rad(180), 0)
	
	tw.tween_property(card_node, "position", hand_pos, 0.4).set_trans(Tween.TRANS_SINE)
	tw.tween_property(card_node, "rotation", hand_rot, 0.4).set_trans(Tween.TRANS_SINE)
	tw.tween_property(card_node, "scale", Vector3(0.07, 0.07, 0.07) * 1.5, 0.4).set_trans(Tween.TRANS_SINE)

func consume_held_card():
	if held_card == null: return
	
	held_card.queue_free()
	held_card = null
	
	# Spawn a single block at BlokSpawnNoktasi
	var marker = get_tree().root.find_child("BlokSpawnNoktasi", true, false)
	if marker:
		var block = CSGBox3D.new()
		# GridScene varsa hücre boyutunu alalım, yoksa varsayılan 0.1 yapalım
		var size = 0.1 
		var grid_gen = get_tree().root.find_child("OyuncuGrid", true, false)
		if grid_gen and grid_gen.get("hucre_boyutu"):
			size = grid_gen.hucre_boyutu
			
		block.size = Vector3(size, size, size)
		
		# Görsellik için basit bir materyal
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.2, 0.6, 1.0) # Açık mavi bir küp
		block.material = mat
		
		marker.get_parent().add_child(block)
		block.global_position = marker.global_position
		
		# Bloğun tıklanabilmesi için hit-box ayarları
		var static_body = StaticBody3D.new()
		static_body.set_meta("is_block", true)
		static_body.set_meta("block_node", block)
		var c_shape = CollisionShape3D.new()
		var b_shape = BoxShape3D.new()
		b_shape.size = Vector3(size, size, size)
		c_shape.shape = b_shape
		static_body.add_child(c_shape)
		block.add_child(static_body)
		block.set_meta("placed", false)
	else:
		print("HATA: Sahnede 'BlokSpawnNoktasi' adında bir node bulunamadı! Lütfen tam adını kontrol et.")

func pick_up_block(block_node):
	held_block = block_node
	
	# Elimizde tutarken raycast ışınlarımızı (yere giden) engellemesin diye hit-box'ını kapatıyoruz
	for c in held_block.get_children():
		if c is StaticBody3D:
			c.collision_layer = 0
			c.collision_mask = 0

func update_block_preview():
	var space_state = get_world_3d().direct_space_state
	var v_size = get_viewport().get_visible_rect().size
	var center = v_size / 2.0
	var origin = project_ray_origin(center)
	var end = origin + project_ray_normal(center) * ray_length
	var query = PhysicsRayQueryParameters3D.create(origin, end)
	var result = space_state.intersect_ray(query)
	
	if result and result.collider.has_meta("is_grid_cell"):
		var cell_node = result.collider.get_meta("grid_cell_node")
		# Bloğun boyunu hesapla (CSGBox3D'nin Y boyu)
		var y_offset = held_block.size.y / 2.0
		# Bloğu direkt olarak grid hücresinin üzerine tak / kilitle (Snap)
		held_block.global_position = cell_node.global_position + Vector3(0, y_offset, 0)
	else:
		# Grid'e bakmıyorsak sadece crosshair'in hemen önünde uçsun
		var target_pos = origin + project_ray_normal(center) * 2.0
		held_block.global_position = held_block.global_position.lerp(target_pos, 0.2)

func place_held_block():
	# Yerleştirildi, fizik çarpışmasını geri aç ki grid'in üzerinde dursun
	for c in held_block.get_children():
		if c is StaticBody3D:
			c.collision_layer = 1
			c.collision_mask = 1
			
	held_block.set_meta("placed", true)
	held_block = null
