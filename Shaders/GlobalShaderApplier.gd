extends Node

# Preload shaders to ensure they are ready
const BASE_SHADER = preload("res://Shaders/toon_ps1.gdshader")
const OUTLINE_SHADER = preload("res://Shaders/toon_ps1_outline.gdshader")

func _ready():
	# Apply to everything currently in the tree
	_process_node(get_tree().root)
	
	# Listen for future nodes entering the world
	get_tree().node_added.connect(_on_node_added)

func _on_node_added(node: Node):
	_process_node(node)

func _process_node(node: Node):
	# Only target 3D meshes
	if node is MeshInstance3D:
		_apply_toon_ps1(node)
	
	# Recurse for existing children if needed (mostly for _ready() call)
	for child in node.get_children():
		_process_node(child)

func _apply_toon_ps1(mesh: MeshInstance3D):
	# Skip if we already have this shader (prevents infinite loops if script is re-run)
	if mesh.material_override and mesh.material_override is ShaderMaterial:
		if mesh.material_override.shader == BASE_SHADER:
			return

	# 1. Try to extract original material properties
	var original_material = mesh.get_active_material(0)
	var tex = null
	var color = Color.WHITE
	
	if original_material is StandardMaterial3D:
		tex = original_material.albedo_texture
		color = original_material.albedo_color
	elif original_material is ORMMaterial3D:
		tex = original_material.albedo_texture
		color = original_material.albedo_color

	# 2. Create the New Base Material
	var toon_mat = ShaderMaterial.new()
	toon_mat.shader = BASE_SHADER
	toon_mat.set_shader_parameter("albedo_texture", tex)
	toon_mat.set_shader_parameter("albedo_color", color)
	toon_mat.set_shader_parameter("jitter_strength", 0.08) # Slightly smoother
	toon_mat.set_shader_parameter("resolution_scale", 480.0) # Matched to new res
	toon_mat.set_shader_parameter("color_steps", 5) # Slightly more color depth
	toon_mat.set_shader_parameter("dither_grain", 0.35) # A bit cleaner
	toon_mat.set_shader_parameter("affine_warp", 0.5) # Reduced warping for clarity

	# 3. Create the Outline Material (Next Pass)
	var outline_mat = ShaderMaterial.new()
	outline_mat.shader = OUTLINE_SHADER
	outline_mat.set_shader_parameter("outline_color", Color.BLACK * 0.5) # Murky outline
	outline_mat.set_shader_parameter("outline_width", 1.2)
	outline_mat.set_shader_parameter("jitter_strength", 0.1)
	outline_mat.set_shader_parameter("resolution_scale", 256.0)

	# Attach outline as a next pass
	toon_mat.next_pass = outline_mat

	# 4. Override
	mesh.material_override = toon_mat
