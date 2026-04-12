extends Node
class_name PieceUpgradeManager

@onready var game_manager = get_tree().get_first_node_in_group("oyun_yoneticisi")
@onready var camera = get_viewport().get_camera_3d()

var selection_pieces: Array[Node3D] = []
var selected_piece: Node3D = null
var is_selection_active: bool = false

var fabric_markers: Array[Marker3D] = []
var altar_marker: Marker3D = null

var whetstone_atk: Node3D = null
var whetstone_def: Node3D = null
var marker_atk: Marker3D = null
var marker_def: Marker3D = null

var upgrade_points: int = 3
var labels_nodes: Array[Label3D] = []
var points_label: Label3D = null

var selection_lockout: float = 0.0

func _process(delta):
	if selection_lockout > 0.0:
		selection_lockout -= delta

const FONT_DOMINICA = preload("res://Assets/fonts/dominica.ttf")

func _ready():
	_find_markers()
	_setup_diegetic_ui()

func _find_markers():
	fabric_markers.clear()
	var base_node = get_tree().current_scene
	if not base_node: base_node = get_tree().root
	
	print("[PieceUpgradeManager] Markörler taranıyor...")
	
	var fabrics = ["fabric2", "fabric3", "fabric4"]
	for f_name in fabrics:
		var node = base_node.find_child(f_name, true, false)
		if not node:
			node = base_node.find_child("*" + f_name + "*", true, false)
			
		if node:
			var marker = node.find_child("Marker3D", true, false)
			if marker:
				fabric_markers.append(marker)
			else:
				fabric_markers.append(node)
	
	var altar_node = base_node.find_child("altar", true, false)
	if altar_node:
		altar_marker = altar_node.find_child("Marker3D", true, false)
		if not altar_marker: altar_marker = altar_node
	
	# Whetstones
	whetstone_atk = base_node.find_child("whetstone_atk", true, false)
	whetstone_def = base_node.find_child("whetstone_def", true, false)
	
	if whetstone_atk:
		marker_atk = whetstone_atk.find_child("Marker3D", true, false)
		_ensure_collision(whetstone_atk, "atk")
		print("[PieceUpgradeManager] Whetstone ATK found at ", whetstone_atk.global_position)
	else:
		print("[PieceUpgradeManager] WARNING: whetstone_atk not found!")
		
	if whetstone_def:
		marker_def = whetstone_def.find_child("Marker3D", true, false)
		_ensure_collision(whetstone_def, "def")
		print("[PieceUpgradeManager] Whetstone DEF found at ", whetstone_def.global_position)
	else:
		print("[PieceUpgradeManager] WARNING: whetstone_def not found!")
		
	if altar_marker:
		print("[PieceUpgradeManager] Altar target pos: ", altar_marker.global_position)
	else:
		print("[PieceUpgradeManager] WARNING: Altar not found!")

func _ensure_collision(node: Node3D, type: String):
	# Check if the node itself is a body
	if node is CollisionObject3D:
		print("[PieceUpgradeManager] Node ", node.name, " is itself a collision object. Tagging it.")
		node.set_meta("is_whetstone", true)
		node.set_meta("whetstone_type", type)
		node.collision_layer |= 1 # Add to layer 1
		return

	var existing_body = node.find_child("*StaticBody*", true, false)
	if existing_body:
		print("[PieceUpgradeManager] Found existing collision for ", node.name, ". Tagging it.")
		existing_body.set_meta("is_whetstone", true)
		existing_body.set_meta("whetstone_type", type)
		existing_body.collision_layer |= 1 # Add to layer 1
		return
		
	var sb = StaticBody3D.new()
	sb.set_meta("is_whetstone", true)
	sb.set_meta("whetstone_type", type)
	node.add_child(sb)
	sb.collision_layer = 1
	var cs = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(0.4, 0.4, 0.4)
	cs.shape = box
	sb.add_child(cs)

func _setup_diegetic_ui():
	# Points Label on Altar (Raised to -0.12 to avoid clipping)
	points_label = _create_label("3", Vector3(-1.83, -0.12, 2.265), Color.GOLD)
	
	# Atk Label
	_create_label("+1 Attack", Vector3(-1.78, -0.12, 2.561), Color.RED)
	
	# Def Label
	_create_label("+1 Defense", Vector3(-1.78, -0.12, 1.975), Color.SKY_BLUE)

func _create_label(text: String, pos: Vector3, color: Color) -> Label3D:
	var l = Label3D.new()
	l.text = text
	l.font = FONT_DOMINICA
	l.font_size = 36
	l.pixel_size = 0.0012
	l.modulate = color
	l.outline_modulate = Color.BLACK
	l.outline_size = 8
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = false
	l.set_meta("skip_shader", true)
	
	# Use deferred calls to avoid "Parent node is busy" while camera is setting up
	get_tree().root.add_child.call_deferred(l)
	l.set_deferred("global_position", pos)
	
	labels_nodes.append(l)
	l.visible = false
	return l

func start_upgrade_sequence():
	if is_selection_active: return
	_find_markers()
	
	if fabric_markers.is_empty(): return
	
	is_selection_active = true
	upgrade_points = 3
	selection_lockout = 0.6 # 0.6 second delay before allowing selection
	if points_label: points_label.text = "3"
	
	for l in labels_nodes: l.visible = true
	
	if camera and camera.has_method("enter_upgrade_selection_view"):
		camera.enter_upgrade_selection_view()
	
	_clear_selection_pieces()
	
	if not game_manager:
		game_manager = get_tree().get_first_node_in_group("oyun_yoneticisi")
	
	if not game_manager:
		print("[PieceUpgradeManager] ERROR: OyunYoneticisi not found!")
		is_selection_active = false
		return
		
	var pool = game_manager.white_pieces.duplicate()
	pool.shuffle()
	
	var spawn_count = min(pool.size(), fabric_markers.size(), 3)
	for i in range(spawn_count):
		var piece_path = pool[i]
		var piece_scene = load(piece_path)
		if piece_scene:
			var piece = piece_scene.instantiate()
			var target_global_pos = fabric_markers[i].global_position
			
			get_tree().current_scene.add_child(piece)
			piece.global_position = target_global_pos
			piece.global_position.y += 0.08
			piece.scale = Vector3(1.5, 1.5, 1.5)
			piece.set_meta("scene_path", piece_path)
			piece.set_meta("is_upgrade_choice", true)
			_add_collision_to_piece(piece)
			selection_pieces.append(piece)
			_setup_piece_visuals(piece)

func _add_collision_to_piece(piece: Node3D):
	if piece.find_child("*StaticBody*", true, false): return
	var body = StaticBody3D.new()
	body.collision_layer = 1
	body.set_meta("is_chess_piece", true)
	body.set_meta("is_upgrade_choice", true)
	piece.add_child(body)
	var shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(0.3, 0.6, 0.3)
	shape.shape = box
	shape.position.y = 0.3
	body.add_child(shape)

func _setup_piece_visuals(piece: Node3D):
	var applier = get_tree().root.find_child("GlobalShaderApplier", true, false)
	if applier and applier.has_method("_process_node"):
		applier._process_node(piece)

func select_piece(piece: Node3D):
	if selection_lockout > 0.0 or selected_piece or not is_selection_active: return
	
	if not piece or not piece is Node3D:
		print("[PieceUpgradeManager] ERROR: Invalid piece passed to select_piece")
		return
	selected_piece = piece
	
	# Hide others
	print("[PieceUpgradeManager] Selection confirmed: ", piece.name)
	for p in selection_pieces:
		if p != piece:
			var tw_hide = create_tween()
			tw_hide.tween_property(p, "scale", Vector3.ZERO, 0.2)
			tw_hide.tween_callback(p.queue_free)
	
	if not altar_marker: return
	var target_pos = altar_marker.global_position
	var tw = create_tween().set_parallel(false)
	tw.tween_property(piece, "global_position:y", piece.global_position.y + 0.4, 0.3).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(piece, "global_position", target_pos, 0.6).set_trans(Tween.TRANS_SINE)
	
	# NO UI POPUP HERE

func process_upgrade(type: String):
	if not selected_piece or upgrade_points <= 0: return
	
	var target_marker = marker_atk if type == "atk" else marker_def
	if not target_marker: return
	
	# 1. Move to Whetstone
	var tw = create_tween()
	tw.tween_property(selected_piece, "global_position", target_marker.global_position, 0.4).set_trans(Tween.TRANS_SINE)
	await tw.finished
	
	# 2. Sharpening Animation (1.5s)
	_play_sharpening_effects(type)
	
	var anim_tw = create_tween()
	var start_p = selected_piece.position
	for i in range(4):
		anim_tw.tween_property(selected_piece, "position:z", start_p.z + 0.1, 0.18).set_trans(Tween.TRANS_SINE)
		anim_tw.tween_property(selected_piece, "position:z", start_p.z - 0.1, 0.18).set_trans(Tween.TRANS_SINE)
	
	await get_tree().create_timer(1.5).timeout
	
	# 3. Apply Stat
	var path = selected_piece.get_meta("scene_path")
	var stat_name = "attack" if type == "atk" else "defense"
	PieceDatabase.upgrade_piece(PieceDatabase.get_piece_type(path), true, stat_name, 1)
	
	upgrade_points -= 1
	if points_label: points_label.text = str(upgrade_points)
	
	# 4. Check Exit or Return
	if upgrade_points <= 0:
		await get_tree().create_timer(0.5).timeout
		_finish_upgrade()
	else:
		var tw_back = create_tween()
		tw_back.tween_property(selected_piece, "global_position", altar_marker.global_position, 0.4).set_trans(Tween.TRANS_SINE)

func _play_sharpening_effects(type: String):
	# Sound
	if SesYoneticisi.has_method("play_whetstone"):
		SesYoneticisi.play_whetstone(type)
	
	# Particles (Fire/Sparks)
	var sparks = CPUParticles3D.new()
	sparks.amount = 60 # Increased for more "fire" effect
	sparks.lifetime = 0.8
	sparks.explosiveness = 0.1
	sparks.spread = 90.0
	sparks.gravity = Vector3(0, 1.0, 0) # Rising embers
	sparks.initial_velocity_min = 2.0
	sparks.initial_velocity_max = 5.0
	sparks.scale_amount_min = 0.05
	sparks.scale_amount_max = 0.12
	sparks.color = Color(1.0, 0.4, 0.0) # Hot Fire Orange
	
	selected_piece.add_child(sparks)
	sparks.position = Vector3(0, 0.15, 0) # Raise so it comes from the piece body
	sparks.emitting = true
	
	get_tree().create_timer(1.5).timeout.connect(func(): 
		sparks.emitting = false
		get_tree().create_timer(1.0).timeout.connect(sparks.queue_free)
	)

func _finish_upgrade():
	is_selection_active = false
	for l in labels_nodes: l.visible = false
	
	if selected_piece:
		var tw = create_tween()
		tw.tween_property(selected_piece, "scale", Vector3.ZERO, 0.3)
		tw.tween_callback(selected_piece.queue_free)
		selected_piece = null
	
	selection_pieces.clear()
	
	if camera and camera.has_method("exit_upgrade_selection_view"):
		camera.exit_upgrade_selection_view()
	if camera and camera.has_method("return_to_table"):
		camera.return_to_table()

func _clear_selection_pieces():
	for p in selection_pieces:
		if is_instance_valid(p): p.queue_free()
	selection_pieces.clear()
	selected_piece = null
