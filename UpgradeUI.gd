extends CanvasLayer

@onready var blur_rect: ColorRect = $ColorRect
@onready var margin_container: MarginContainer = $MarginContainer
@onready var name_label: Label = $MarginContainer/VBoxContainer/NameLabel
@onready var credit_label: Label = $MarginContainer/VBoxContainer/CreditLabel
@onready var atk_value_label: Label = $MarginContainer/VBoxContainer/AttackBox/ValueLabel
@onready var def_value_label: Label = $MarginContainer/VBoxContainer/DefenseBox/ValueLabel
@onready var slots_container: HBoxContainer = $MarginContainer/VBoxContainer/SlotsContainer
@onready var viewport_piece_anchor: Node3D = $SubViewportContainer/SubViewport/PieceAnchor
@onready var decide_btn: Button = $DecideButton

@onready var atk_plus: Button = $MarginContainer/VBoxContainer/AttackBox/PlusBtn
@onready var atk_minus: Button = $MarginContainer/VBoxContainer/AttackBox/MinusBtn
@onready var def_plus: Button = $MarginContainer/VBoxContainer/DefenseBox/PlusBtn
@onready var def_minus: Button = $MarginContainer/VBoxContainer/DefenseBox/MinusBtn

signal dismissed
signal piece_on_altar

var is_active: bool = false
var viewport_piece: Node3D = null
var rotation_speed: float = 0.5
var sensitivity: float = 0.2

var total_credits: int = 3
var current_credits: int = 3
var base_atk: int = 0
var base_def: int = 0
var bonus_atk: int = 0
var bonus_def: int = 0

var current_piece_type: String = ""
var current_piece_path: String = ""

signal upgrade_confirmed(type_key, bonus_atk, bonus_def)

func _ready():
	blur_rect.material.set_shader_parameter("blur_amount", 0.0)
	margin_container.modulate.a = 0
	visible = false
	
	atk_plus.pressed.connect(_on_plus_pressed.bind("attack"))
	atk_minus.pressed.connect(_on_minus_pressed.bind("attack"))
	def_plus.pressed.connect(_on_plus_pressed.bind("defense"))
	def_minus.pressed.connect(_on_minus_pressed.bind("defense"))
	decide_btn.pressed.connect(_on_decide_pressed)
	
	# Font Uygulamaları
	var golden_font = load("res://Assets/fonts/Golden Horse.ttf")
	var normal_font = load("res://Assets/fonts/Helvetica Punk.ttf")
	
	name_label.add_theme_font_override("font", golden_font)
	name_label.add_theme_font_size_override("font_size", 32)
	
	credit_label.add_theme_font_override("font", normal_font)
	atk_value_label.add_theme_font_override("font", normal_font)
	def_value_label.add_theme_font_override("font", normal_font)
	
	decide_btn.add_theme_font_override("font", golden_font)
	decide_btn.add_theme_font_size_override("font_size", 22)
	
	_setup_slots()

func _setup_slots():
	for child in slots_container.get_children():
		child.queue_free()
	for i in range(total_credits):
		var slot = Panel.new()
		slot.custom_minimum_size = Vector2(30, 30)
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.1, 0.1, 0.1, 0.8)
		style.set_border_width_all(2)
		style.border_color = Color(0.3, 0.3, 0.3)
		style.set_corner_radius_all(15)
		slot.add_theme_stylebox_override("panel", style)
		slots_container.add_child(slot)

func _update_slots_visual():
	for i in range(slots_container.get_child_count()):
		var slot = slots_container.get_child(i) as Panel
		var style = slot.get_theme_stylebox("panel").duplicate()
		if i < (total_credits - current_credits):
			style.bg_color = Color(1, 0.84, 0, 1) # Yellow for used
		else:
			style.bg_color = Color(0.1, 0.1, 0.1, 0.8) # Gray for unused
		slot.add_theme_stylebox_override("panel", style)

func open(piece_path: String):
	current_piece_path = piece_path
	var stats = PieceDatabase.get_piece_stats(piece_path)
	if stats.is_empty(): return
	
	piece_on_altar.emit()
	
	current_credits = 3
	bonus_atk = 0
	bonus_def = 0
	base_atk = stats["attack"]
	base_def = stats["defense"]
	
	# Determine type key for database update
	var filename = piece_path.get_file().to_lower()
	if "piyon" in filename or "pawn" in filename: current_piece_type = "pawn"
	elif "castle" in filename: current_piece_type = "castle"
	elif "bishop" in filename: current_piece_type = "bishop"
	elif "horse" in filename: current_piece_type = "horse"
	elif "queen" in filename: current_piece_type = "queen"
	
	name_label.text = stats["name"].to_upper()
	_update_ui()
	
	# Setup 3D Piece
	if viewport_piece: viewport_piece.queue_free()
	var scene = load(piece_path)
	if scene:
		viewport_piece = scene.instantiate()
		viewport_piece_anchor.add_child(viewport_piece)
		viewport_piece.scale = Vector3(14.0, 14.0, 14.0)
		viewport_piece.rotation_degrees = Vector3(0, 180, 0)
		viewport_piece.position.y = -0.35 # Biraz yukarı kaldırdık
		_apply_shader_to_viewport_piece(viewport_piece)
	
	# Decide butonunu yazıyı saracak şekilde küçült (Taşma önlendi, orantı düzeltildi)
	decide_btn.custom_minimum_size = Vector2(110, 35)
	decide_btn.set_anchors_and_offsets_preset(7)
	decide_btn.grow_horizontal = Control.GROW_DIRECTION_BOTH
	decide_btn.position.y = get_viewport().get_visible_rect().size.y - 75
	
	is_active = true
	visible = true
	
	var tween = create_tween().set_parallel(true)
	tween.tween_method(func(val): blur_rect.material.set_shader_parameter("blur_amount", val), 0.0, 4.0, 0.5)
	tween.tween_property(margin_container, "modulate:a", 1.0, 0.5)
	tween.tween_property(decide_btn, "modulate:a", 1.0, 0.5)

func _update_ui():
	atk_value_label.text = str(base_atk + bonus_atk)
	def_value_label.text = str(base_def + bonus_def)
	credit_label.text = "CREDITS REMAINING: %d" % current_credits
	_update_slots_visual()
	
	atk_minus.disabled = (bonus_atk <= 0)
	def_minus.disabled = (bonus_def <= 0)
	atk_plus.disabled = (current_credits <= 0)
	def_plus.disabled = (current_credits <= 0)

func _on_plus_pressed(stat: String):
	if current_credits > 0:
		if stat == "attack": bonus_atk += 1
		else: bonus_def += 1
		current_credits -= 1
		_update_ui()
		SesYoneticisi.play_place_block() # Use existing sound

func _on_minus_pressed(stat: String):
	if stat == "attack" and bonus_atk > 0:
		bonus_atk -= 1
		current_credits += 1
	elif stat == "defense" and bonus_def > 0:
		bonus_def -= 1
		current_credits += 1
	_update_ui()

func _on_decide_pressed():
	# Apply to database
	if bonus_atk > 0:
		PieceDatabase.upgrade_piece(current_piece_type, true, "attack", bonus_atk)
	if bonus_def > 0:
		PieceDatabase.upgrade_piece(current_piece_type, true, "defense", bonus_def)
	
	upgrade_confirmed.emit(current_piece_type, bonus_atk, bonus_def)
	close()

func close():
	if not is_active: return
	is_active = false
	
	var tween = create_tween().set_parallel(true)
	tween.tween_method(func(val): blur_rect.material.set_shader_parameter("blur_amount", val), 4.0, 0.0, 0.4)
	tween.tween_property(margin_container, "modulate:a", 0.0, 0.4)
	tween.tween_property(decide_btn, "modulate:a", 0.0, 0.4)
	
	await tween.finished
	visible = false
	if viewport_piece:
		viewport_piece.queue_free()
		viewport_piece = null
	dismissed.emit()

func _apply_shader_to_viewport_piece(node: Node):
	var applier = get_tree().root.find_child("GlobalShaderApplier", true, false)
	if applier and applier.has_method("_process_node"):
		node.set_meta("render_on_top", false) 
		applier._process_node(node)

func _input(event):
	if not is_active: return
	if event is InputEventMouseMotion:
		viewport_piece_anchor.rotate_y(deg_to_rad(event.relative.x * sensitivity))
		get_viewport().set_input_as_handled()
