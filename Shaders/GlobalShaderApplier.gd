extends Node

# Preload shaders to ensure they are ready
const BASE_SHADER = preload("res://Shaders/toon_ps1.gdshader")
const OUTLINE_SHADER = preload("res://Shaders/toon_ps1_outline.gdshader")
const BARREL_SHADER = preload("res://Shaders/barrel_distortion.gdshader")

func _ready():
	# Apply to everything currently in the tree
	_process_node(get_tree().root)
	
	# SETUP GLOBAL OVERLAY (Barrel Distortion)
	_setup_screen_effects()
	
	# Listen for future nodes entering the world
	get_tree().node_added.connect(_on_node_added)

func _on_node_added(node: Node):
	_process_node(node)

func _process_node(node: Node):
	# Only target 3D meshes
	if node is MeshInstance3D:
		# Layer 2 is reserved for Viewmodels (Gun/Cards)
		# We preserve the original look if it's already set to Layer 2
		if node.layers == 2:
			return
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

func _setup_screen_effects():
	print("[GlobalShaderApplier] Setting up CRT Barrel Distortion Overlay...")
	# 1. Create a CanvasLayer to ensure it's drawn on top
	# Special: Adding it to the root window directly to override local viewports
	var cl = CanvasLayer.new()
	cl.name = "PostProcessLayer"
	cl.layer = 150 # Extremely high layer to be on top of EVERYTHING
	get_tree().root.add_child.call_deferred(cl)
	
	# 2. Add a BackBufferCopy just in case for older renderers or complex viewport setups
	var bbc = BackBufferCopy.new()
	bbc.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	cl.add_child(bbc)
	
	# 3. Create the ColorRect that covers the screen
	var rect = ColorRect.new()
	rect.name = "BarrelDistortionOverlay"
	
	# Matching viewport size exactly to ensure UV 0.5 is the screen center
	var update_size = func():
		rect.size = get_viewport().get_visible_rect().size
	
	update_size.call()
	get_viewport().size_changed.connect(update_size)
	
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE # Don't block clicking!
	cl.add_child(rect)
	
	# 4. Apply the Barrel Distortion Shader
	var mat = ShaderMaterial.new()
	mat.shader = BARREL_SHADER
	
	# CRT Preset Values:
	mat.set_shader_parameter("distortion_strength", 0.15) 
	mat.set_shader_parameter("scale", 0.95) 
	mat.set_shader_parameter("scanline_intensity", 0.12)
	mat.set_shader_parameter("noise_intensity", 0.05)
	mat.set_shader_parameter("chromatic_aberration", 0.003)
	mat.set_shader_parameter("vignette_intensity", 0.45)
	mat.set_shader_parameter("brightness", 1.1)
	
	rect.material = mat
	print("[GlobalShaderApplier] CRT Effect Active.")
