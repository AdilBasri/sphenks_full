@tool
extends Node3D
class_name GridHucre

var sutun: int = 0
var satir: int = 0
var boyut: float = 1.0
var mevcut_tas: Node3D = null # Bu hücredeki satranç taşı
var highlight_mesh: MeshInstance3D = null
var preview_tas: Node3D = null # Önizleme için geçici taş

func _ready() -> void:
	# Bu hücrenin görselini oluşturur.
	refresh_visuals()

func setup(p_sutun: int, p_satir: int, p_boyut: float = 1.0) -> void:
	sutun = p_sutun
	satir = p_satir
	boyut = p_boyut
	name = "Hucre_%d_%d" % [sutun, satir]
	refresh_visuals()

func refresh_visuals() -> void:
	# Mevcut görselleri temizle (Highlight mesh hariç)
	for child in get_children():
		if child != highlight_mesh and child != preview_tas and not child is StaticBody3D:
			child.queue_free()
	
	# Eğer highlight_mesh yoksa oluştur (Sadece ilk kez)
	if not highlight_mesh:
		highlight_mesh = MeshInstance3D.new()
		var highlight_plane = PlaneMesh.new()
		highlight_plane.size = Vector2(boyut, boyut)
		highlight_mesh.mesh = highlight_plane
		
		var highlight_mat = StandardMaterial3D.new()
		highlight_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		highlight_mat.albedo_color = Color(1, 1, 0, 0.4) # Yarı saydam sarı
		highlight_mesh.material_override = highlight_mat
		highlight_mesh.position.y = 0.002
		highlight_mesh.visible = false 
		add_child(highlight_mesh)
	
	# 1. Kenarlık (Border) - Biraz daha büyük ve koyu renkli
	var border_mesh = MeshInstance3D.new()
	var border_plane = PlaneMesh.new()
	border_plane.size = Vector2(boyut * 1.05, boyut * 1.05)
	border_mesh.mesh = border_plane
	var border_mat = StandardMaterial3D.new()
	border_mat.albedo_color = Color(0.2, 0.2, 0.2)
	border_mesh.material_override = border_mat
	add_child(border_mesh)
	
	# 2. Hücre Yüzeyi - Ana renk
	var surface_mesh = MeshInstance3D.new()
	var surface_plane = PlaneMesh.new()
	surface_plane.size = Vector2(boyut * 0.95, boyut * 0.95)
	surface_mesh.mesh = surface_plane
	var surface_mat = StandardMaterial3D.new()
	surface_mat.albedo_color = Color(0.8, 0.8, 0.8)
	surface_mesh.material_override = surface_mat
	surface_mesh.position.y = 0.001 
	add_child(surface_mesh)
	
	# Raycast için çarpışma kutusu
	var static_body = StaticBody3D.new()
	static_body.set_meta("is_grid_cell", true)
	static_body.set_meta("grid_cell_node", self)
	
	var col_shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(boyut, 0.05, boyut)
	col_shape.shape = box
	static_body.add_child(col_shape)
	add_child(static_body)

func set_highlight(active: bool, color: Color = Color(1, 1, 0, 0.4)) -> void:
	if highlight_mesh:
		highlight_mesh.visible = active
		var mat = highlight_mesh.material_override as StandardMaterial3D
		if mat and active:
			mat.albedo_color = color

func set_preview_piece(piece_scene_path: String) -> void:
	if preview_tas:
		preview_tas.queue_free()
		preview_tas = null
	
	if piece_scene_path != "":
		var scene = load(piece_scene_path)
		if scene:
			preview_tas = scene.instantiate()
			add_child(preview_tas)
			# Tüm materyalleri saydam yapmaya çalışalım
			for child in preview_tas.find_children("*", "MeshInstance3D", true, false):
				var mat = child.mesh.surface_get_material(0).duplicate()
				if mat is StandardMaterial3D:
					mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					mat.albedo_color.a = 0.4
					child.material_override = mat
