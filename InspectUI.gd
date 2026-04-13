extends CanvasLayer

@onready var blur_rect: ColorRect = $ColorRect
@onready var margin_container: MarginContainer = $MarginContainer
@onready var name_label: Label = $MarginContainer/VBoxContainer/NameLabel
@onready var stats_label: Label = $MarginContainer/VBoxContainer/StatsLabel
@onready var desc_label: Label = $MarginContainer/VBoxContainer/DescLabel
@onready var slots_container: HBoxContainer = $MarginContainer/VBoxContainer/HBoxContainer
@onready var viewport_piece_anchor: Node3D = $SubViewportContainer/SubViewport/PieceAnchor

signal dismissed

var is_active: bool = false
var viewport_piece: Node3D = null
var rotation_speed: float = 0.5
var sensitivity: float = 0.2
var _can_dismiss: bool = false

var inspected_node: Node3D = null # The actual piece in the world
var inspected_path: String = "" # Path to pieces database info

func _ready():
	blur_rect.material.set_shader_parameter("blur_amount", 0.0)
	margin_container.modulate.a = 0
	visible = false
	
	# Font Uygulamaları
	var golden_font = load("res://Assets/fonts/Golden Horse.ttf")
	var normal_font = load("res://Assets/fonts/Helvetica Punk.ttf")
	
	name_label.add_theme_font_override("font", golden_font)
	name_label.add_theme_font_size_override("font_size", 36)
	
	stats_label.add_theme_font_override("font", normal_font)
	stats_label.add_theme_font_size_override("font_size", 22)
	
	desc_label.add_theme_font_override("font", normal_font)
	desc_label.add_theme_font_size_override("font_size", 18)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	
	_setup_upgrade_slots()

func _process(_delta):
	if is_active:
		_update_labels()

func _update_labels():
	if inspected_path == "": return
	var stats = PieceDatabase.get_piece_stats(inspected_path)
	if stats.is_empty(): return
	
	var current_atk = stats.get("attack", 0)
	var current_def = stats.get("defense", 0)
	
	# If we are inspecting a specific piece on the board, show its live stats
	if inspected_node and is_instance_valid(inspected_node):
		if inspected_node.has_meta("current_defense"):
			current_def = inspected_node.get_meta("current_defense")
		if inspected_node.has_meta("current_attack"):
			current_atk = inspected_node.get_meta("current_attack")
			
	stats_label.text = "Attack: %d | Defense: %d" % [current_atk, current_def]
	name_label.text = stats.get("name", "Piece")
	desc_label.text = stats.get("description", "")

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

var is_held_piece: bool = false

func show_piece(piece_scene_path: String, from_chest: bool = false, node: Node3D = null):
	inspected_path = piece_scene_path
	inspected_node = node
	
	var stats = PieceDatabase.get_piece_stats(piece_scene_path)
	if stats.is_empty(): return
	
	is_held_piece = from_chest
	
	# Initial Update
	_update_labels()
	
	# Setup 3D Viewport Piece
	if viewport_piece: viewport_piece.queue_free()
	var scene = load(piece_scene_path)
	if scene:
		viewport_piece = scene.instantiate()
		viewport_piece_anchor.add_child(viewport_piece)
		viewport_piece_anchor.position = Vector3(1.3, -0.507, -1.597)
		viewport_piece_anchor.rotation_degrees = Vector3(3.8, 154.4, 0.8)
		viewport_piece.position = Vector3.ZERO
		viewport_piece.scale = Vector3(15.0, 15.0, 15.0)
		_apply_ps1_to_viewport_piece(viewport_piece)
	
	is_active = true
	visible = true
	
	var tween = create_tween().set_parallel(true)
	tween.tween_method(func(val): blur_rect.material.set_shader_parameter("blur_amount", val), 0.0, 4.0, 0.5)
	tween.tween_property(margin_container, "modulate:a", 1.0, 0.5)
	
	_can_dismiss = false
	get_tree().create_timer(0.2).timeout.connect(func(): _can_dismiss = true)

func _apply_ps1_to_viewport_piece(node: Node):
	var applier = get_tree().root.find_child("GlobalShaderApplier", true, false)
	if applier and applier.has_method("_process_node"):
		node.set_meta("render_on_top", false) 
		applier._process_node(node)

func hide_piece():
	if not is_active: return
	is_active = false
	
	# Tutorial ve diğer sistemlerin ilerlemesi için sinyali her zaman gönderiyoruz
	dismissed.emit()
	
	var tween = create_tween().set_parallel(true)
	tween.tween_method(func(val): blur_rect.material.set_shader_parameter("blur_amount", val), 4.0, 0.0, 0.3)
	tween.tween_property(margin_container, "modulate:a", 0.0, 0.3)
	
	await tween.finished
	
	# Animasyon biter bitmez temizliği yapıyoruz
	clear_viewport_piece()

func clear_viewport_piece():
	if viewport_piece:
		viewport_piece.queue_free()
		viewport_piece = null
	
	inspected_node = null
	inspected_path = ""
	
	is_active = false # Çifte kontrol
	visible = false
	blur_rect.material.set_shader_parameter("blur_amount", 0.0)

func _input(event):
	if not is_active: return
	
	if event is InputEventMouseMotion:
		viewport_piece_anchor.rotate_y(deg_to_rad(event.relative.x * sensitivity))
		viewport_piece_anchor.rotate_object_local(Vector3.RIGHT, deg_to_rad(-event.relative.y * sensitivity))
		get_viewport().set_input_as_handled()
		
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _can_dismiss:
			get_viewport().set_input_as_handled()
			hide_piece()
