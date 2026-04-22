extends Node3D

@onready var main_menu = $CanvasLayer/Control/MenuOptions
@onready var settings_panel = $CanvasLayer/Control/SettingsPanel
@onready var confirm_panel = $CanvasLayer/Control/ConfirmPanel
@onready var play_button = $CanvasLayer/Control/MenuOptions/PlayButton

# Audio Sliders
@onready var master_slider = $CanvasLayer/Control/SettingsPanel/VBoxContainer/MasterVolume/HSlider
@onready var sfx_slider = $CanvasLayer/Control/SettingsPanel/VBoxContainer/SFXVolume/HSlider
@onready var music_slider = $CanvasLayer/Control/SettingsPanel/VBoxContainer/MusicVolume/HSlider

# Toggles/Buttons
@onready var res_button = $CanvasLayer/Control/SettingsPanel/VBoxContainer/Resolution/Button
@onready var fullscreen_check = $CanvasLayer/Control/SettingsPanel/VBoxContainer/Fullscreen/CheckBox
@onready var colorblind_button = $CanvasLayer/Control/SettingsPanel/VBoxContainer/Colorblind/Button

func _ready():
	# Initial UI State
	settings_panel.visible = false
	confirm_panel.visible = false
	main_menu.visible = true
	
	# Check for save
	update_play_button_text()
	
	# Initialize Settings UI from manager
	_initialize_settings_ui()
	
	# Ensure mouse is visible for menu
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	# Reset OyunYoneticisi if it exists (in case we returned from game)
	var oy = get_tree().get_first_node_in_group("oyun_yoneticisi")
	if oy:
		oy.reset_game_state()
	
	# Small intro animation
	$CanvasLayer/Control.modulate.a = 0
	var tw = create_tween()
	tw.tween_property($CanvasLayer/Control, "modulate:a", 1.0, 1.0).set_trans(Tween.TRANS_SINE)
	
	# Start menu music (only if startup delay is done)
	if SesYoneticisi.startup_timer_finished:
		SesYoneticisi.start_menu_music()

func update_play_button_text():
	if SettingsManager.check_for_save():
		play_button.text = "CONTINUE"
	else:
		play_button.text = "PLAY"

func _initialize_settings_ui():
	var s = SettingsManager.settings
	master_slider.value = s.master_volume
	sfx_slider.value = s.sfx_volume
	music_slider.value = s.music_volume
	fullscreen_check.button_pressed = s.fullscreen
	_update_res_button_text()
	_update_colorblind_button_text()

# --- Main Menu Buttons ---

func _on_play_button_pressed():
	_play_click_sound()
	# Transition to game
	var f_tw = create_tween()
	f_tw.tween_property($CanvasLayer/Control, "modulate:a", 0.0, 0.5)
	
	# Fade out menu music manually for a smoother transition
	SesYoneticisi.stop_menu_music()
	
	await f_tw.finished
	get_tree().change_scene_to_file("res://camera.tscn")

func _on_settings_button_pressed():
	_play_click_sound()
	main_menu.visible = false
	settings_panel.visible = true

func _on_reset_save_button_pressed():
	_play_click_sound()
	confirm_panel.visible = true

func _on_exit_button_pressed():
	_play_click_sound()
	get_tree().quit()

# --- Settings Panel Logic ---

func _on_back_button_pressed():
	_play_click_sound()
	settings_panel.visible = false
	main_menu.visible = true
	SettingsManager.save_settings()

func _on_master_volume_changed(value):
	SettingsManager.settings.master_volume = value
	SettingsManager.apply_audio()

func _on_sfx_volume_changed(value):
	SettingsManager.settings.sfx_volume = value
	SettingsManager.apply_audio()
	# Play a sample sfx
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		SesYoneticisi.play_hover()

func _on_music_volume_changed(value):
	SettingsManager.settings.music_volume = value
	SettingsManager.apply_audio()

func _on_resolution_button_pressed():
	_play_click_sound()
	SettingsManager.settings.resolution = (SettingsManager.settings.resolution + 1) % 3
	_update_res_button_text()
	SettingsManager.apply_resolution()

func _on_fullscreen_toggled(button_pressed):
	_play_click_sound()
	SettingsManager.settings.fullscreen = button_pressed
	SettingsManager.apply_resolution()

func _on_colorblind_button_pressed():
	_play_click_sound()
	SettingsManager.settings.colorblind_mode = (SettingsManager.settings.colorblind_mode + 1) % 5
	_update_colorblind_button_text()
	SettingsManager.apply_colorblind()

func _update_res_button_text():
	match SettingsManager.settings.resolution:
		0: res_button.text = "640x360 (1x)"
		1: res_button.text = "1280x720 (2x)"
		2: res_button.text = "1920x1080 (3x)"

func _update_colorblind_button_text():
	var modes = ["Off", "Protanopia", "Deuteranopia", "Tritanopia", "Grayscale"]
	colorblind_button.text = modes[SettingsManager.settings.colorblind_mode]

# --- Confirmation Logic ---

func _on_confirm_yes():
	_play_click_sound()
	SettingsManager.reset_save()
	confirm_panel.visible = false
	update_play_button_text()

func _on_confirm_no():
	_play_click_sound()
	confirm_panel.visible = false

# --- Helpers ---

func _input(event):
	if event.is_action_pressed("ui_cancel"):
		if confirm_panel.visible:
			_on_confirm_no()
		elif settings_panel.visible:
			_on_back_button_pressed()

func _process(delta):
	# Subtle camera float
	var t = Time.get_ticks_msec() * 0.001
	$Camera3D.position.y = 0.31 + sin(t * 0.5) * 0.02
	$Camera3D.position.x = 1.46 + cos(t * 0.3) * 0.02

func _play_click_sound():
	SesYoneticisi.play_place_block()

func _on_button_hover():
	SesYoneticisi.play_hover()
