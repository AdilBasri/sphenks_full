extends Node
class_name PieceUpgradeManager

@onready var game_manager = get_tree().get_first_node_in_group("oyun_yoneticisi")
@onready var camera = get_viewport().get_camera_3d()

var selection_pieces: Array[Node3D] = []
var selected_piece: Node3D = null
var is_selection_active: bool = false

var fabric_markers: Array[Marker3D] = []
var altar_marker: Marker3D = null

var upgrade_ui: CanvasLayer = null

func _ready():
	_find_markers()
	_setup_ui()

func _find_markers():
	fabric_markers.clear()
	var base_node = get_tree().current_scene
	if not base_node: base_node = get_tree().root
	
	print("[PieceUpgradeManager] Markörler taranıyor...")
	
	var fabrics = ["fabric2", "fabric3", "fabric4"]
	for f_name in fabrics:
		var node = base_node.find_child(f_name, true, false)
		if not node:
			# Yedek plan: Eğer tam isimle bulunamazsa içinde "fabric" geçenleri tara
			node = base_node.find_child("*" + f_name + "*", true, false)
			
		if node:
			var marker = node.find_child("Marker3D", true, false)
			if marker:
				fabric_markers.append(marker)
				print("[PieceUpgradeManager] Markör bulundu: ", f_name)
			else:
				fabric_markers.append(node)
				print("[PieceUpgradeManager] Uyarı: %s için Marker3D yok, direkt düğüm kullanılıyor." % f_name)
		else:
			print("[PieceUpgradeManager] KRİTİK: %s sahne ağacında bulunamadı!" % f_name)
	
	var altar_node = base_node.find_child("altar", true, false)
	if altar_node:
		altar_marker = altar_node.find_child("Marker3D", true, false)
		if not altar_marker: altar_marker = altar_node
		print("[PieceUpgradeManager] Altar markörü hazır.")

func _setup_ui():
	var ui_scene = load("res://UpgradeUI.tscn")
	if ui_scene:
		upgrade_ui = ui_scene.instantiate()
		get_tree().root.add_child.call_deferred(upgrade_ui)
		if upgrade_ui.has_signal("upgrade_confirmed"):
			upgrade_ui.upgrade_confirmed.connect(_on_upgrade_done)
		print("[PieceUpgradeManager] UpgradeUI yüklendi.")

func start_upgrade_sequence():
	if is_selection_active: return
	
	# Markörleri tazele
	_find_markers()
	
	if fabric_markers.is_empty():
		print("[PieceUpgradeManager] HATA: Hiçbir kumaş markörü bulunamadı!")
		return
	
	if not game_manager:
		game_manager = get_tree().get_first_node_in_group("oyun_yoneticisi")
	
	if not game_manager or not "white_pieces" in game_manager:
		print("[PieceUpgradeManager] HATA: Game Manager veya white_pieces havuzu eksik!")
		return
		
	is_selection_active = true
	
	# Kamerayı hazırla
	if camera and camera.has_method("enter_upgrade_selection_view"):
		camera.enter_upgrade_selection_view()
	
	_clear_selection_pieces()
	
	# UI kontrolü
	if not upgrade_ui: _setup_ui()
	
	var pool = game_manager.white_pieces.duplicate()
	pool.shuffle()
	
	var spawn_count = min(pool.size(), fabric_markers.size(), 3)
	var spawned_count = 0
	
	for i in range(spawn_count):
		var piece_path = pool[i]
		var piece_scene = load(piece_path)
		if piece_scene:
			var piece = piece_scene.instantiate()
			var target_global_pos = fabric_markers[i].global_position
			
			# Eğer markörler üst üsteyse (fabric2/3 sorunu) yana kaydır
			if i > 0:
				for j in range(i):
					if target_global_pos.distance_to(fabric_markers[j].global_position) < 0.1:
						target_global_pos.z += 0.4 # Z ekseninde yana kaydır
			
			get_tree().current_scene.add_child(piece)
			piece.global_position = target_global_pos
			piece.global_position.y += 0.08 # İdeal yükseklik
			piece.rotation = Vector3.ZERO
			piece.scale = Vector3(1.5, 1.5, 1.5)
			
			_add_collision_to_piece(piece)
			
			piece.set_meta("scene_path", piece_path)
			piece.set_meta("is_upgrade_choice", true)
			selection_pieces.append(piece)
			
			_setup_piece_visuals(piece)
			spawned_count += 1
			print("[PieceUpgradeManager] Taş yerleştirildi: %s (Kumaş: %s) Dünya Pos: %s" % [piece.name, fabric_markers[i].get_parent().name, piece.global_position])
	
	if spawned_count == 0:
		is_selection_active = false
		if camera.has_method("release_to_walk"):
			camera.release_to_walk()

func _add_collision_to_piece(piece: Node3D):
	if piece.find_child("*StaticBody*", true, false): return
	var body = StaticBody3D.new()
	body.collision_layer = 1
	piece.add_child(body)
	var shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(0.5, 0.8, 0.5)
	shape.shape = box
	shape.position.y = 0.4
	body.add_child(shape)

func _setup_piece_visuals(piece: Node3D):
	piece.set_meta("is_upgrade_choice", true)
	var applier = get_tree().root.find_child("GlobalShaderApplier", true, false)
	if applier and applier.has_method("_process_node"):
		applier._process_node(piece)

func select_piece(piece: Node3D):
	if selected_piece or not is_selection_active: return
	selected_piece = piece
	
	# Diğerlerini temizle
	for p in selection_pieces:
		if p != piece:
			var tw_hide = create_tween()
			tw_hide.tween_property(p, "scale", Vector3.ZERO, 0.2)
			tw_hide.tween_callback(p.queue_free)
	
	if not altar_marker: 
		print("[PieceUpgradeManager] HATA: Altar markörü bulunamadı!")
		return

	var target_pos = altar_marker.global_position
	var tw = create_tween().set_parallel(false)
	
	tw.tween_property(piece, "global_position:y", piece.global_position.y + 0.4, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(piece, "global_position", target_pos, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	
	tw.finished.connect(func():
		if upgrade_ui:
			upgrade_ui.open(piece.get_meta("scene_path"))
			print("[PieceUpgradeManager] UI tetiklendi.")
		else:
			print("[PieceUpgradeManager] HATA: UI örneği (instance) bulunamadı!")
	)

func _on_upgrade_done(_type, _atk, _def):
	is_selection_active = false
	if selected_piece:
		selected_piece.queue_free()
		selected_piece = null
	
	selection_pieces.clear()
	
	if camera and camera.has_method("exit_upgrade_selection_view"):
		camera.exit_upgrade_selection_view()
	
	if camera and camera.has_method("release_to_walk"):
		camera.release_to_walk()

func _clear_selection_pieces():
	for p in selection_pieces:
		if is_instance_valid(p):
			p.queue_free()
	selection_pieces.clear()
	selected_piece = null
