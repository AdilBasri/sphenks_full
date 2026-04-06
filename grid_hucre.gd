@tool
extends Node3D
class_name GridHucre

var sutun: int = 0
var satir: int = 0
var boyut: float = 1.0

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
	# Mevcut görselleri temizle
	for child in get_children():
		child.queue_free()
	
	# 1. Kenarlık (Border) - Biraz daha büyük ve koyu renkli
	var border_mesh = MeshInstance3D.new()
	var border_plane = PlaneMesh.new()
	border_plane.size = Vector2(boyut * 1.05, boyut * 1.05) # Hücreden biraz büyük
	border_mesh.mesh = border_plane
	
	var border_mat = StandardMaterial3D.new()
	border_mat.albedo_color = Color(0.2, 0.2, 0.2) # Koyu gri kenarlık
	border_mesh.material_override = border_mat
	add_child(border_mesh)
	
	# 2. Hücre Yüzeyi - Ana renk (soluk beyaz/gri)
	var surface_mesh = MeshInstance3D.new()
	var surface_plane = PlaneMesh.new()
	surface_plane.size = Vector2(boyut * 0.95, boyut * 0.95) # Kenarlıktan biraz küçük
	surface_mesh.mesh = surface_plane
	
	var surface_mat = StandardMaterial3D.new()
	surface_mat.albedo_color = Color(0.8, 0.8, 0.8) # Soluk beyaz/gri
	surface_mesh.material_override = surface_mat
	# Z-fighting engellemek için çok az yukarı kaydırıyoruz
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
