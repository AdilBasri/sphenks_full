extends Control

var overlay: ColorRect
var v_box: VBoxContainer
var title: Label
var try_again_btn: Button
var quit_btn: Button

func _ready():
	# UI Setup
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	
	overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0)
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0
	add_child(overlay)
	
	v_box = VBoxContainer.new()
	v_box.anchor_left = 0.5
	v_box.anchor_top = 0.5
	v_box.anchor_right = 0.5
	v_box.anchor_bottom = 0.5
	v_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	v_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	v_box.alignment = BoxContainer.ALIGNMENT_CENTER
	v_box.visible = false
	v_box.modulate.a = 0
	add_child(v_box)
	
	title = Label.new()
	title.text = "GAME OVER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var title_font = load("res://Assets/fonts/Golden Horse.ttf")
	title.add_theme_font_override("font", title_font)
	title.add_theme_font_size_override("font_size", 64)
	v_box.add_child(title)
	
	var spacer = Control.new()
	spacer.custom_minimum_size.y = 20
	v_box.add_child(spacer)
	
	var btn_font = load("res://Assets/fonts/Helvetica Punk.ttf")
	
	try_again_btn = Button.new()
	try_again_btn.text = "TRY AGAIN"
	try_again_btn.flat = true
	try_again_btn.add_theme_font_override("font", btn_font)
	try_again_btn.add_theme_font_size_override("font_size", 24)
	try_again_btn.pressed.connect(_on_try_again)
	v_box.add_child(try_again_btn)
	
	quit_btn = Button.new()
	quit_btn.text = "QUIT"
	quit_btn.flat = true
	quit_btn.add_theme_font_override("font", btn_font)
	quit_btn.add_theme_font_size_override("font_size", 24)
	quit_btn.pressed.connect(_on_quit)
	v_box.add_child(quit_btn)

func show_game_over():
	# Fade to Black
	var tw = create_tween()
	tw.tween_property(overlay, "color", Color(0, 0, 0, 1.0), 1.5)
	tw.tween_callback(func(): v_box.visible = true)
	tw.tween_property(v_box, "modulate:a", 1.0, 1.0)
	
	# Show mouse
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_try_again():
	print("Restarting game...")
	# Reset time scale just in case
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()
	queue_free()

func _on_quit():
	get_tree().quit()
