extends CanvasLayer

@onready var blur_rect: ColorRect = $ColorRect
@onready var margin_container: MarginContainer = $MarginContainer
@onready var name_label: Label = $MarginContainer/VBoxContainer/NameLabel
@onready var stats_label: Label = $MarginContainer/VBoxContainer/StatsLabel
@onready var desc_label: Label = $MarginContainer/VBoxContainer/DescLabel
@onready var slots_container: HBoxContainer = $MarginContainer/VBoxContainer/HBoxContainer
@onready var viewport_piece_anchor: Node3D = $SubViewportContainer/SubViewport/PieceAnchor

var is_active: bool = false
var viewport_piece: Node3D = null
var rotation_speed: float = 0.5
var sensitivity: float = 0.2

signal dismissed

func _ready():
	blur_rect.material.set_shader_parameter("blur_amount", 0.0)
	margin_container.modulate.a = 0
	visible = false
	_setup_upgrade_slots()

func _setup_upgrade_slots():
	for child in slots_container.get_children():
		child.queue_free()
	for i in range(3):
		var slot = Panel.new()
		slot.custom_minimum_size = Vector2(40, 40)
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.1, 0.1, 0.1, 0.8)
		style.set_border_width_all(2)
		style.border_color = Color(0.3, 0.3, 0.3)
		style.set_corner_radius_all(20)
		style.shadow_size = 2
		style.shadow_color = Color(0, 0, 0, 0.5)
		style.set_expand_margin_all(1)
		slot.add_theme_stylebox_override("panel", style)
		slots_container.add_child(slot)

func show_piece(piece_scene_path: String):
	var stats = PieceDatabase.get_piece_stats(piece_scene_path)
	if stats.is_empty(): return
	
	# Update Text
	name_label.text = stats["name"]
	stats_label.text = "Attack: %d | Defense: %d" % [stats["attack"], stats["defense"]]
	desc_label.text = stats["description"]
	
	# Setup 3D Viewport Piece
	if viewport_piece: viewport_piece.queue_free()
	var scene = load(piece_scene_path)
	if scene:
		viewport_piece = scene.instantiate()
		viewport_piece_anchor.add_child(viewport_piece)
		
		# Set Anchor to the target position so rotation is centered
		viewport_piece_anchor.position = Vector3(1.3, -0.507, -1.597)
		viewport_piece_anchor.rotation_degrees = Vector3(3.8, 154.4, 0.8)
		
		# Piece itself stays at origin of anchor and gets much larger
		viewport_piece.position = Vector3.ZERO
		viewport_piece.scale = Vector3(15.0, 15.0, 15.0)
		
		# Apply global shader
		_apply_ps1_to_viewport_piece(viewport_piece)
	
	is_active = true
	visible = true
	
	var tween = create_tween().set_parallel(true)
	tween.tween_method(func(val): blur_rect.material.set_shader_parameter("blur_amount", val), 0.0, 4.0, 0.5)
	tween.tween_property(margin_container, "modulate:a", 1.0, 0.5)

func _apply_ps1_to_viewport_piece(node: Node):
	var applier = get_tree().root.find_child("GlobalShaderApplier", true, false)
	if applier and applier.has_method("_process_node"):
		node.set_meta("render_on_top", false) 
		applier._process_node(node)

func hide_piece():
	if not is_active: return
	is_active = false
	dismissed.emit() # Signal for camera to show the real piece again
	
	var tween = create_tween().set_parallel(true)
	tween.tween_method(func(val): blur_rect.material.set_shader_parameter("blur_amount", val), 4.0, 0.0, 0.4)
	tween.tween_property(margin_container, "modulate:a", 0.0, 0.4)
	
	await tween.finished
	visible = false
	if viewport_piece:
		viewport_piece.queue_free()
		viewport_piece = null

func _input(event):
	if not is_active: return
	
	# Rotation Logic
	if event is InputEventMouseMotion:
		viewport_piece_anchor.rotate_y(deg_to_rad(event.relative.x * sensitivity))
		viewport_piece_anchor.rotate_object_local(Vector3.RIGHT, deg_to_rad(-event.relative.y * sensitivity))
		
	# Dismiss Logic - Consume the click so main camera doesn't place piece
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		hide_piece()
