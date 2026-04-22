extends CanvasLayer

@onready var control = $Control
@onready var menu_options = $Control/MenuOptions
@onready var settings_panel = $Control/SettingsPanel

# Settings UI
@onready var res_button = $Control/SettingsPanel/VBoxContainer/Resolution/Button
@onready var fullscreen_check = $Control/SettingsPanel/VBoxContainer/Fullscreen/CheckBox
@onready var master_slider = $Control/SettingsPanel/VBoxContainer/MasterVolume/HSlider
@onready var sfx_slider = $Control/SettingsPanel/VBoxContainer/SFXVolume/HSlider
@onready var music_slider = $Control/SettingsPanel/VBoxContainer/MusicVolume/HSlider

func _ready():
	control.visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS # Ensure this script runs when paused
	_sync_settings_ui()

func _input(event):
	if event.is_action_pressed("ui_cancel"):
		# If we are in the Main Menu, the Pause Menu should NOT open.
		# However, if settings are open, we still want to go back.
		if get_tree().current_scene.name == "anamenu":
			return # Let anamenu.gd handle it
			
		if settings_panel.visible:
			_on_back_pressed()
		else:
			if get_tree().paused:
				resume()
			else:
				pause()

func pause():
	get_tree().paused = true
	control.visible = true
	menu_options.visible = true
	settings_panel.visible = false
	
	# Force mouse to be visible and functional for the menu
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_sync_settings_ui()

func resume():
	get_tree().paused = false
	control.visible = false
	
	if get_tree().current_scene.name == "anamenu":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
		
	# Inform the camera to re-capture or re-confine the mouse as needed
	var camera = get_viewport().get_camera_3d()
	if camera and camera.has_method("restore_mouse_mode"):
		camera.restore_mouse_mode()
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_settings_pressed():
	menu_options.visible = false
	settings_panel.visible = true

func _on_main_menu_pressed():
	get_tree().paused = false
	var oy = get_tree().get_first_node_in_group("oyun_yoneticisi")
	if oy:
		oy.reset_game_state()
	get_tree().change_scene_to_file("res://anamenu.tscn")

func _on_exit_pressed():
	get_tree().quit()

# --- Settings Handling ---

func _sync_settings_ui():
	var s = SettingsManager.settings
	master_slider.value = s.master_volume
	sfx_slider.value = s.sfx_volume
	music_slider.value = s.music_volume
	fullscreen_check.button_pressed = s.fullscreen
	_update_res_button_text()

func _on_back_pressed():
	settings_panel.visible = false
	menu_options.visible = true
	SettingsManager.save_settings()

func _on_res_pressed():
	SettingsManager.settings.resolution = (SettingsManager.settings.resolution + 1) % 3
	_update_res_button_text()
	SettingsManager.apply_resolution()

func _on_fullscreen_toggled(button_pressed):
	SettingsManager.settings.fullscreen = button_pressed
	SettingsManager.apply_resolution()

func _on_master_volume_changed(value):
	SettingsManager.settings.master_volume = value
	SettingsManager.apply_audio()

func _on_sfx_volume_changed(value):
	SettingsManager.settings.sfx_volume = value
	SettingsManager.apply_audio()

func _on_music_volume_changed(value):
	SettingsManager.settings.music_volume = value
	SettingsManager.apply_audio()

func _update_res_button_text():
	match SettingsManager.settings.resolution:
		0: res_button.text = "640x360 (1x)"
		1: res_button.text = "1280x720 (2x)"
		2: res_button.text = "1920x1080 (3x)"
