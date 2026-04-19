extends Node

const SETTINGS_FILE = "user://settings.cfg"

var config = ConfigFile.new()

# Defaults
var settings = {
	"resolution": 2, # 0: 640x360, 1: 1280x720, 2: 1920x1080
	"fullscreen": true,
	"master_volume": 1.0,
	"sfx_volume": 1.0,
	"music_volume": 0.8,
	"colorblind_mode": 0 # 0: Off, 1: Protanopia, 2: Deuteranopia, 3: Tritanopia, 4: Grayscale
}

func _ready():
	load_settings()
	# Update: Global Custom Cursor setup
	_setup_custom_cursor.call_deferred()
	# We use call_deferred to ensure the window and other nodes are ready before applying
	apply_all_settings.call_deferred()

func _setup_custom_cursor():
	var cursor_path = "res://Assets/cursor/Cursor.png"
	if FileAccess.file_exists(cursor_path):
		var img = load(cursor_path).get_image()
		# Original is 360x360, we need it much smaller for a standard cursor
		img.resize(24, 24, Image.INTERPOLATE_LANCZOS)
		var tex = ImageTexture.create_from_image(img)
		# Set globally for the app
		Input.set_custom_mouse_cursor(tex, Input.CURSOR_ARROW, Vector2(1,1))
		Input.set_custom_mouse_cursor(tex, Input.CURSOR_IBEAM, Vector2(1,1))
		Input.set_custom_mouse_cursor(tex, Input.CURSOR_POINTING_HAND, Vector2(1,1))

func load_settings():
	var err = config.load(SETTINGS_FILE)
	if err == OK:
		for section in config.get_sections():
			for key in config.get_section_keys(section):
				if settings.has(key):
					settings[key] = config.get_value(section, key)

func save_settings():
	for key in settings:
		config.set_value("Settings", key, settings[key])
	config.save(SETTINGS_FILE)

func apply_all_settings():
	apply_resolution()
	apply_audio()
	apply_colorblind()

func apply_resolution():
	# Resolution Map (Internal buffer size)
	var res_map = [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]
	var target_res = res_map[settings.resolution]
	
	# RESTORE AESTHETICS: Limit 3D rendering to 360p height to keep PS1 'crunchiness'
	var scale_3d = 1.0
	if target_res.y > 0:
		scale_3d = 360.0 / target_res.y
	get_viewport().scaling_3d_scale = scale_3d
	
	if settings.fullscreen:
		# Use DisplayServer for most reliable "True Fullscreen" (Exclusive)
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	else:
		# First return to windowed mode
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		
		# Set size explicitly
		DisplayServer.window_set_size(target_res)
		
		# Center window on current monitor
		var screen = DisplayServer.window_get_current_screen()
		var screen_rect = DisplayServer.screen_get_usable_rect(screen)
		var window_size = DisplayServer.window_get_size()
		var center_pos = screen_rect.position + (Vector2i(screen_rect.size) / 2) - (window_size / 2)
		DisplayServer.window_set_position(center_pos)

func apply_audio():
	_set_bus_volume("Master", settings.master_volume)
	_set_bus_volume("SFX", settings.sfx_volume)
	_set_bus_volume("Music", settings.music_volume)

func _set_bus_volume(bus_name: String, volume_linear: float):
	var bus_idx = AudioServer.get_bus_index(bus_name)
	if bus_idx != -1:
		AudioServer.set_bus_volume_db(bus_idx, linear_to_db(volume_linear))

func apply_colorblind():
	var applier = get_node_or_null("/root/GlobalShaderApplier")
	if applier:
		# Search in root instead of relative if needed
		var overlay = get_tree().root.find_child("BarrelDistortionOverlay", true, false)
		if overlay and overlay.material:
			overlay.material.set_shader_parameter("colorblind_mode", settings.colorblind_mode)

func check_for_save() -> bool:
	return FileAccess.file_exists("user://save_game.dat")

func reset_save():
	if FileAccess.file_exists("user://save_game.dat"):
		DirAccess.remove_absolute("user://save_game.dat")
		# Also reset piece database to defaults when resetting save if needed
		var db = get_node_or_null("/root/PieceDatabase")
		if db and db.has_method("_initialize_database"):
			db._initialize_database()
		return true
	return false

func save_game_data(data: Dictionary):
	var file = FileAccess.open("user://save_game.dat", FileAccess.WRITE)
	if file:
		file.store_var(data)
		file.close()

func load_game_data() -> Dictionary:
	if not check_for_save():
		return {}
	var file = FileAccess.open("user://save_game.dat", FileAccess.READ)
	if file:
		var data = file.get_var()
		file.close()
		if data is Dictionary:
			return data
	return {}
