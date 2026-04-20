extends Node

# Preloaded Sounds
var error_sound = preload("res://Assets/Sounds/ErrorSound.mp3")
var fall_sound = preload("res://Assets/Sounds/fall.mp3")
var handing_item_sound = preload("res://Assets/Sounds/handing_item.mp3")
var place_block_sound = preload("res://Assets/Sounds/place_block.mp3")
var walking_sound = preload("res://Assets/Sounds/walking.mp3")
var bgm_intro = preload("res://Assets/Sounds/background_ilk_kisim.mp3")
var bgm_loop = preload("res://Assets/Sounds/background_ikinci_kisim.mp3")
var angry_sound = preload("res://Assets/Sounds/angry.mp3")
var evil_laugh_sound = preload("res://Assets/Sounds/evil_laugh.mp3")
var puke_sound = preload("res://Assets/Sounds/puke.mp3")

var walking_player: AudioStreamPlayer
var bgm_player_active: AudioStreamPlayer
var bgm_player_fade: AudioStreamPlayer
var bgm_loop_timer: Timer
var crossfade_duration: float = 4.0

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	setup_audio_buses()
	setup_walking_player()
	
	# Setup Loop Timer
	bgm_loop_timer = Timer.new()
	bgm_loop_timer.one_shot = true
	add_child(bgm_loop_timer)
	bgm_loop_timer.timeout.connect(_start_loop_crossfade)
	
	setup_bgm_player()

func setup_audio_buses():
	# Mastering: Setup SFX, Footsteps, and Music buses with effects
	
	# 1. Create SFX Bus if it doesn't exist
	var sfx_bus_idx = AudioServer.get_bus_index("SFX")
	if sfx_bus_idx == -1:
		AudioServer.add_bus()
		sfx_bus_idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(sfx_bus_idx, "SFX")
		AudioServer.set_bus_send(sfx_bus_idx, "Master")
	
	# Add Compressor to SFX for "Mastering"
	var sfx_comp = AudioEffectCompressor.new()
	sfx_comp.threshold = -12.0
	sfx_comp.ratio = 4.0
	sfx_comp.gain = 2.0
	AudioServer.add_bus_effect(sfx_bus_idx, sfx_comp)
	
	# 2. Create Footsteps Bus
	var walk_bus_idx = AudioServer.get_bus_index("Footsteps")
	if walk_bus_idx == -1:
		AudioServer.add_bus()
		walk_bus_idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(walk_bus_idx, "Footsteps")
		AudioServer.set_bus_send(walk_bus_idx, "SFX")
	
	AudioServer.set_bus_volume_db(walk_bus_idx, -6.0)
	var walk_eq = AudioEffectEQ.new()
	AudioServer.add_bus_effect(walk_bus_idx, walk_eq)
	
	# 3. Create Music Bus with Sidechain (Ducking)
	var music_bus_idx = AudioServer.get_bus_index("Music")
	if music_bus_idx == -1:
		AudioServer.add_bus()
		music_bus_idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(music_bus_idx, "Music")
		AudioServer.set_bus_send(music_bus_idx, "Master")
	
	# Set base volume for music (lower to not overwhelm)
	AudioServer.set_bus_volume_db(music_bus_idx, -12.0)
	
	# Sidechain Compressor: Dips music when SFX plays
	var music_duck = AudioEffectCompressor.new()
	music_duck.threshold = -24.0 # Low threshold to catch SFX
	music_duck.ratio = 3.0       # Moderate ducking
	music_duck.release_ms = 500  # Smooth return
	music_duck.sidechain = "SFX" # LISTEN TO SFX BUS
	AudioServer.add_bus_effect(music_bus_idx, music_duck)

func setup_walking_player():
	# Ensure the stream loops
	if walking_sound is AudioStreamMP3:
		walking_sound.loop = true
	
	walking_player = AudioStreamPlayer.new()
	walking_player.stream = walking_sound
	walking_player.bus = "Footsteps"
	add_child(walking_player)

func setup_bgm_player(use_intro: bool = false):
	if bgm_loop is AudioStreamMP3:
		bgm_loop.loop = false
	if bgm_intro is AudioStreamMP3:
		bgm_intro.loop = false
		
	if not bgm_player_active:
		bgm_player_active = AudioStreamPlayer.new()
		bgm_player_active.bus = "Music"
		add_child(bgm_player_active)
	
	if not bgm_player_fade:
		bgm_player_fade = AudioStreamPlayer.new()
		bgm_player_fade.bus = "Music"
		add_child(bgm_player_fade)
	
	# Stop and reset state
	bgm_loop_timer.stop()
	bgm_player_active.stop()
	bgm_player_fade.stop()
	bgm_player_active.volume_db = 0
	bgm_player_fade.volume_db = -80
	
	# Clear old connections
	if bgm_player_active.finished.is_connected(_on_bgm_finished):
		bgm_player_active.finished.disconnect(_on_bgm_finished)
	
	if use_intro:
		bgm_player_active.stream = bgm_intro
		bgm_player_active.finished.connect(_on_bgm_finished)
		bgm_player_active.play()
	else:
		bgm_player_active.stream = bgm_loop
		bgm_player_active.play()
		_schedule_loop_crossfade()

func _on_bgm_finished():
	if bgm_player_active.stream == bgm_intro:
		# Disconnect to avoid loops and transition
		if bgm_player_active.finished.is_connected(_on_bgm_finished):
			bgm_player_active.finished.disconnect(_on_bgm_finished)
			
		bgm_player_active.stream = bgm_loop
		bgm_player_active.volume_db = 0
		bgm_player_active.play()
		_schedule_loop_crossfade()

func _schedule_loop_crossfade():
	var length = bgm_loop.get_length()
	var wait_time = length - crossfade_duration
	
	if wait_time > 0:
		bgm_loop_timer.start(wait_time)
	else:
		# Fallback if track is too short for crossfade
		bgm_player_active.finished.connect(func(): 
			bgm_player_active.play()
		, CONNECT_ONE_SHOT)

func _start_loop_crossfade():
	# Start the second player from the beginning of the loop
	bgm_player_fade.stream = bgm_loop
	bgm_player_fade.volume_db = -80
	bgm_player_fade.play()
	
	var tween = create_tween()
	tween.set_parallel(true)
	# Fade out current, fade in next
	tween.tween_property(bgm_player_active, "volume_db", -80, crossfade_duration)
	tween.tween_property(bgm_player_fade, "volume_db", 0, crossfade_duration)
	
	tween.finished.connect(func():
		bgm_player_active.stop()
		# Swap references so 'active' is always the one playing the main volume
		var temp = bgm_player_active
		bgm_player_active = bgm_player_fade
		bgm_player_fade = temp
		# Repeat the cycle
		_schedule_loop_crossfade()
	)

# Global SFX player helper
func play_sfx(stream: AudioStream, pitch_scale: float = 1.0, volume_db: float = 0.0) -> AudioStreamPlayer:
	var asp = AudioStreamPlayer.new()
	asp.stream = stream
	asp.bus = "SFX"
	asp.pitch_scale = pitch_scale
	asp.volume_db = volume_db
	add_child(asp)
	asp.play()
	asp.finished.connect(asp.queue_free)
	return asp

func play_spatial_sfx(stream: AudioStream, global_pos: Vector3, pitch_scale: float = 1.0, volume_db: float = 0.0) -> AudioStreamPlayer3D:
	var asp = AudioStreamPlayer3D.new()
	asp.stream = stream
	asp.bus = "SFX"
	asp.pitch_scale = pitch_scale
	asp.volume_db = volume_db
	asp.unit_size = 10.0 # Standard range
	add_child(asp)
	asp.global_position = global_pos
	asp.play()
	asp.finished.connect(asp.queue_free)
	return asp

# Specific Sound Helpers
func play_error():
	play_sfx(error_sound, 1.1, -2.0)

func play_place_block():
	play_sfx(place_block_sound, randf_range(0.9, 1.1))

func play_handing():
	play_sfx(handing_item_sound)

func play_fall():
	play_sfx(fall_sound)

func play_hover():
	play_sfx(handing_item_sound, 1.2, -10.0) # High pitch, subtle

func play_angry(pos: Vector3):
	var asp = play_spatial_sfx(angry_sound, pos)
	# Trim to 1.80s as requested
	get_tree().create_timer(1.80).timeout.connect(func(): 
		if is_instance_valid(asp): asp.stop()
	)

func play_evil_laugh():
	var asp = play_sfx(evil_laugh_sound)
	# Trim to 1.78s as requested
	get_tree().create_timer(1.78).timeout.connect(func(): 
		if is_instance_valid(asp): asp.stop()
	)

func play_puke():
	play_sfx(puke_sound)

var whetstone_atk_sound = preload("res://Assets/Sounds/whetstone_atk.mp3")
var whetstone_def_sound = preload("res://Assets/Sounds/whetstone_def.mp3")

# Walking control
func set_walking(is_moving: bool):
	if is_moving:
		if not walking_player.playing:
			walking_player.play()
		walking_player.stream_paused = false
	else:
		walking_player.stream_paused = true

func play_impact_slam():
	# Use place_block pitched WAY down for a thud
	play_sfx(place_block_sound, 0.4, 2.0)
	# Also play a low rumble by using fall sound
	play_sfx(fall_sound, 0.6, -5.0)

func play_enemy_groan(pos: Vector3):
	# Use angry pitched down for a groan
	var asp = play_spatial_sfx(angry_sound, pos, 0.7, 5.0)
	# Trim to 1.8s as requested for angry sound
	get_tree().create_timer(1.8).timeout.connect(func():
		if is_instance_valid(asp): asp.stop()
	)

func play_whetstone(type: String):
	var stream = whetstone_atk_sound if type == "atk" else whetstone_def_sound
	var asp = play_sfx(stream)
	# Sound is 3s but animation is 1.5s. Cut it off.
	get_tree().create_timer(1.5).timeout.connect(func():
		if is_instance_valid(asp):
			asp.stop()
	)
