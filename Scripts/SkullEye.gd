extends MeshInstance3D

@export_group("Skull Eye Settings")
@export var eye_color_player: Color = Color(0.1, 0.5, 0.1)
@export var eye_color_enemy: Color = Color(0.4, 0.0, 0.0)
@export var eye_emission_intensity: float = 0.85
@export var light_energy_multiplier: float = 1.0
@export var light_range: float = 2.0

@export var hover_intensity_multiplier: float = 2.0

var eye_tween: Tween
var omni_light: OmniLight3D
var is_hovered: bool = false

func _ready():
	_setup_light()

func _process(_delta):
	_update_hover_state()

func _setup_light():
	omni_light = get_node_or_null("OmniLight3D")
	if not omni_light:
		omni_light = OmniLight3D.new()
		omni_light.name = "OmniLight3D"
		add_child(omni_light)
	
	omni_light.light_energy = 0
	omni_light.shadow_enabled = false # Keep it cheap

func _update_hover_state():
	var cam = get_viewport().get_camera_3d()
	if not cam: return
	
	# Use standard center or mouse pos depending on state
	var mouse_pos = get_viewport().get_mouse_position()
	
	var origin = cam.project_ray_origin(mouse_pos)
	var end = origin + cam.project_ray_normal(mouse_pos) * 10.0
	
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(origin, end)
	# Raycast only for the skull collision layer if possible, or check meta
	var result = space_state.intersect_ray(query)
	
	var hovered = false
	if result and result.collider.has_meta("is_skull"):
		hovered = true
	
	set_hover(hovered)

func set_hover(hovered: bool):
	if is_hovered == hovered: return
	is_hovered = hovered
	
	# Find current turn state from OyunYoneticisi
	var oy = get_tree().get_first_node_in_group("oyun_yoneticisi")
	if not oy: oy = get_tree().current_scene
	
	var is_player = true
	if oy and "current_turn" in oy:
		is_player = (oy.current_turn == 0) # 0 is PLAYER in enum
	
	update_eye(is_player)

func update_eye(is_player_turn: bool):
	if not omni_light: _setup_light()
	
	var mat = material_override
	if not mat or not mat is StandardMaterial3D:
		mat = StandardMaterial3D.new()
		mat.albedo_color = Color.BLACK
		mat.emission_enabled = true
		mat.emission = Color.BLACK
		mat.emission_energy_multiplier = 0.0
		material_override = mat
	
	var target_color = eye_color_player if is_player_turn else eye_color_enemy
	var target_emission = eye_emission_intensity
	var target_light_energy = light_energy_multiplier
	
	# Apply hover boost
	if is_hovered:
		target_emission *= hover_intensity_multiplier
		target_light_energy *= hover_intensity_multiplier
	
	if eye_tween: eye_tween.kill()
	eye_tween = create_tween()
	eye_tween.set_parallel(true)
	eye_tween.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	
	# Mesh Visuals
	eye_tween.tween_property(mat, "albedo_color", target_color * 0.4, 0.4) # Faster for hover response
	eye_tween.tween_property(mat, "emission", target_color, 0.4)
	eye_tween.tween_property(mat, "emission_energy_multiplier", target_emission, 0.4)
	
	# Environment Light
	eye_tween.tween_property(omni_light, "light_color", target_color, 0.4)
	eye_tween.tween_property(omni_light, "light_energy", target_light_energy, 0.4)
	omni_light.omni_range = light_range
