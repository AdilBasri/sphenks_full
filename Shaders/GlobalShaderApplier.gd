extends Node

# Preload shaders to ensure they are ready
const BASE_SHADER = preload("res://Shaders/toon_ps1.gdshader")
const OUTLINE_SHADER = preload("res://Shaders/toon_ps1_outline.gdshader")
const BASE_SHADER_NO_DEPTH = preload("res://Shaders/toon_ps1_no_depth.gdshader")
const OUTLINE_SHADER_NO_DEPTH = preload("res://Shaders/toon_ps1_outline_no_depth.gdshader")
const BARREL_SHADER = preload("res://Shaders/barrel_distortion.gdshader")

# Performance Optimization State
var _mat_cache: Dictionary = {}
var _pending_nodes: Array[Node] = []
var _excluded_cache: Dictionary = {} # Node path -> bool

func _ready():
	# Apply to everything currently in the tree
	_process_node(get_tree().root)
	
	# SETUP GLOBAL OVERLAY (Barrel Distortion)
	_setup_screen_effects()
	
	# Listen for future nodes entering the world
	get_tree().node_added.connect(_on_node_added)

func _process(_delta):
	if _pending_nodes.is_empty():
		return
		
	# Process a small batch of nodes per frame to prevent jitter
	var start_time = Time.get_ticks_msec()
	while not _pending_nodes.is_empty():
		var node = _pending_nodes.pop_front()
		if is_instance_valid(node):
			_process_node(node)
		
		# Limit processing time per frame (e.g., 2ms) to keep frame rate stable
		if Time.get_ticks_msec() - start_time > 2:
			break

func _on_node_added(node: Node):
	# Optimization: Fast-exit for common Godot internal nodes
	if node is Timer or node is AnimationPlayer or node is AudioStreamPlayer or node is AudioStreamPlayer3D or node is CanvasItem:
		return
	
	# Optimization: Add to queue instead of processing instantly
	_pending_nodes.append(node)

func _process_node(node: Node):
	# Allow manual exclusion via meta tag
	if node.has_meta("skip_shader") and node.get_meta("skip_shader"):
		return
		
	# EXCLUSION: Skip fabric1 and altar subtrees
	if _is_excluded(node):
		return
		
	# Only target 3D meshes
	if node is MeshInstance3D:
		# Layer 2 is reserved for Viewmodels (Gun/Cards)
		if node.layers == 2:
			return
		
		# Detect if this mesh belongs to a chess piece (Pawn folder, etc.)
		var is_piece = _is_chess_piece(node)
		_apply_toon_ps1(node, is_piece)
	
	# Recurse for existing children if needed
	# Optimization: Only recurse if the node is part of a 3D branch or root
	# Skip recursion for pure UI/Control branches beyond the root logic
	if node is Node3D or node == get_tree().root or node.name == "GameRoom":
		for child in node.get_children():
			_process_node(child)

func _is_excluded(node: Node) -> bool:
	# Check path-based cache first
	var path = node.get_path()
	if _excluded_cache.has(path):
		return _excluded_cache[path]
		
	# Checks if this node or any ancestor is fabric1, altar, or ashtray
	var p = node
	var result = false
	while p and p != get_tree().root:
		var lname = p.name.to_lower()
		if lname == "fabric1" or lname == "altar" or lname == "ashtray" or "whetstone" in lname \
		or "vent" in lname or "kapi" in lname or "door" in lname or "kapı" in lname:
			result = true
			break
		p = p.get_parent()
	
	_excluded_cache[path] = result
	return result

func _is_chess_piece(node: Node) -> bool:
	# Check the node itself
	if node is SatrancTasi or node.is_in_group("satranc_taslari") or node.has_meta("is_chess_piece"):
		return true
		
	# Traverse up to find if it belongs to a Pawn scene
	var p = node
	while p:
		if p is SatrancTasi or p.is_in_group("satranc_taslari"):
			return true
		var path = p.scene_file_path
		if path != "" and path.contains("/Pawn/"):
			return true
		# Also check node name for common piece names just in case
		var lower_name = p.name.to_lower()
		if "white" in lower_name or "black" in lower_name:
			if "piyon" in lower_name or "bishop" in lower_name or "horse" in lower_name or "castle" in lower_name or "king" in lower_name or "queen" in lower_name:
				return true
		p = p.get_parent()
			
	return false

func _apply_toon_ps1(mesh: MeshInstance3D, is_piece: bool = false):
	# 0. Check for "render on top" override
	var render_on_top = false
	var p = mesh
	while p:
		if p.has_meta("render_on_top") and p.get_meta("render_on_top") == true:
			render_on_top = true
			break
		p = p.get_parent()

	# Skip if we already have a shader, UNLESS we need to switch types
	if mesh.material_override and mesh.material_override is ShaderMaterial:
		var current_shader = mesh.material_override.shader
		if render_on_top:
			if current_shader == BASE_SHADER_NO_DEPTH: return
		else:
			if current_shader == BASE_SHADER: return

	# 1. Extract original material properties
	var original_material = mesh.get_active_material(0)
	if not original_material:
		# Fallback: create a basic material if missing so we can still apply the shader
		original_material = StandardMaterial3D.new()
		
	var tex = null
	var color = Color.WHITE
	
	if original_material is StandardMaterial3D or original_material is ORMMaterial3D:
		tex = original_material.albedo_texture
		color = original_material.albedo_color
	elif original_material is ShaderMaterial:
		# Extract from existing shader if possible (rare for base)
		if original_material.get_shader_parameter("albedo_texture"):
			tex = original_material.get_shader_parameter("albedo_texture")
		if original_material.get_shader_parameter("albedo_color"):
			color = original_material.get_shader_parameter("albedo_color")

	# 2. Configure parameters based on whether it's a piece or environment
	var jitter = 0.08
	var resolution = 360.0
	var steps = 5
	var dither = 0.35
	var light_int = 1.0
	var affine = 0.5
	
	if is_piece:
		# Pieces need much higher clarity and less blowout
		jitter = 0.015   # Very stable
		steps = 14       # Much smoother gradients
		light_int = 0.75 # Prevent white blowout
		dither = 0.2     # Cleaner look
		affine = 0.2     # Less texture warping for detail
		
		# If it's a white piece (pure white or very bright), tone down the albedo slightly
		if color.r > 0.9 and color.g > 0.9 and color.b > 0.9:
			color = Color(0.85, 0.85, 0.85)

	# 3. Use Cached Material if available
	var tex_id = tex.get_instance_id() if tex else 0
	var cache_key = "%d_%s_%d_%d" % [tex_id, str(color), int(is_piece), int(render_on_top)]
	
	if _mat_cache.has(cache_key):
		mesh.material_override = _mat_cache[cache_key]
		return

	# 4. Create the New Base Material
	var toon_mat = ShaderMaterial.new()
	toon_mat.shader = BASE_SHADER_NO_DEPTH if render_on_top else BASE_SHADER
	toon_mat.render_priority = 100 if render_on_top else 0
	
	toon_mat.set_shader_parameter("albedo_texture", tex)
	toon_mat.set_shader_parameter("albedo_color", color)
	toon_mat.set_shader_parameter("jitter_strength", jitter)
	toon_mat.set_shader_parameter("resolution_scale", resolution)
	toon_mat.set_shader_parameter("color_steps", steps)
	toon_mat.set_shader_parameter("dither_grain", dither)
	toon_mat.set_shader_parameter("affine_warp", affine)
	toon_mat.set_shader_parameter("light_intensity", light_int)

	# 5. Create the Outline Material (Next Pass)
	var outline_mat = ShaderMaterial.new()
	outline_mat.shader = OUTLINE_SHADER_NO_DEPTH if render_on_top else OUTLINE_SHADER
	outline_mat.render_priority = 101 if render_on_top else 0
	
	outline_mat.set_shader_parameter("outline_color", Color.BLACK * (0.3 if is_piece else 0.5))
	outline_mat.set_shader_parameter("outline_width", 0.6 if is_piece else 1.2)
	outline_mat.set_shader_parameter("jitter_strength", jitter)
	outline_mat.set_shader_parameter("resolution_scale", 256.0)

	toon_mat.next_pass = outline_mat
	
	# Store in cache and apply
	_mat_cache[cache_key] = toon_mat
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
