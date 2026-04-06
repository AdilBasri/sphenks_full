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
				if new_mat is BaseMaterial3D:
					new_mat.no_depth_test = true
					new_mat.render_priority = priority
				node.set_surface_override_material(i, new_mat)
	
	for child in node.get_children():
		_apply_no_depth_recursive(child, priority)

func _input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if held_block != null:
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
		yaw = clamp(yaw, start_y - limit_y, start_y + limit_y)
		pitch = clamp(pitch, start_x - limit_x, start_x + limit_x)

func _process(_delta):
	if is_locked: return
	
	if held_block != null:
		update_block_preview()
		
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
	held_card = card_node
	
	var g_trans = card_node.global_transform
	card_node.get_parent().remove_child(card_node)
	add_child(card_node)
	card_node.global_transform = g_trans
	
	# Masanın altına girmemesi için her şeyin üstünde çizilmesini sağla
	_apply_no_depth_recursive(card_node, 12)
	var tw = create_tween().set_parallel(true)
	var hand_pos = Vector3(0, -0.1, -0.2) 
	
	# Kart eğer fizik objesi ise hareketini donduralım ki gravity etki etmesin
	if card_node is RigidBody3D:
		card_node.freeze = true
	
	# Eğer X ekseninde 90 döndürmek onu yatay yaptıysa, orijinal hali dikeydir.
	# Doğrudan kamerasının karşısına dik bir şekilde alalım:
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
	
	if held_card.name.to_lower().begins_with("card4") or held_card.name == "card4":
		knife_mode = true
		held_card.queue_free()
		held_card = null
		return
		
	if held_card.name.to_lower().begins_with("card3") or held_card.name == "card3":
		enemy_placement_mode = true
		
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
			
		held_card.queue_free()
		held_card = null
		return
	
	held_card.queue_free()
	held_card = null
	
	# block_tek sahnemizi yüklüyoruz - Artık rastgele sahneler atayabiliriz!
	var scenes = [
		"res://block_tek.tscn",
		"res://block_l.tscn",
		"res://block_t.tscn",
		"res://block_kare.tscn",
		"res://block_line.tscn"
	]
	var random_scene = scenes[randi() % scenes.size()]
	var block_scene = load(random_scene)
	if block_scene:
		var spawned_block = block_scene.instantiate()
		
		# Spawnda masaya koyacağız (Elden önce sahneye çıkar)
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
			
			# Tıklanabilmesi için hit-box oluştur (zaten statik bodyleri var block sahnelerinde! Meta verelim yeterli)
			for sb in spawned_block.find_children("*", "StaticBody3D"):
				sb.set_meta("is_block", true)
				sb.set_meta("block_node", spawned_block)
			spawned_block.set_meta("placed", false)
		else:
			print("HATA: Sahnede 'BlokSpawnNoktasi' adında bir node bulunamadı! Lütfen tam adını kontrol et.")

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
			)
	)
