extends Node

# Preloaded Sounds
var error_sound = preload("res://Assets/Sounds/ErrorSound.mp3")
var fall_sound = preload("res://Assets/Sounds/fall.mp3")
var handing_item_sound = preload("res://Assets/Sounds/handing_item.mp3")
var place_block_sound = preload("res://Assets/Sounds/place_block.mp3")
var walking_sound = preload("res://Assets/Sounds/walking.mp3")
var bgm_sound = preload("res://Assets/Sounds/background (2).mp3")

var walking_player: AudioStreamPlayer
var bgm_player: AudioStreamPlayer

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	setup_audio_buses()
	setup_walking_player()
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

func setup_bgm_player():
	if bgm_sound is AudioStreamMP3:
		bgm_sound.loop = true
	
	bgm_player = AudioStreamPlayer.new()
	bgm_player.stream = bgm_sound
	bgm_player.bus = "Music"
	add_child(bgm_player)
	bgm_player.play()

# Global SFX player helper
func play_sfx(stream: AudioStream, pitch_scale: float = 1.0, volume_db: float = 0.0):
	var asp = AudioStreamPlayer.new()
	asp.stream = stream
	asp.bus = "SFX"
	asp.pitch_scale = pitch_scale
	asp.volume_db = volume_db
	add_child(asp)
	asp.play()
	asp.finished.connect(asp.queue_free)

# Specific Sound Helpers
func play_error():
	play_sfx(error_sound, 1.1, -2.0)

func play_place_block():
	play_sfx(place_block_sound, randf_range(0.9, 1.1))

func play_handing():
	play_sfx(handing_item_sound)

func play_fall():
	play_sfx(fall_sound)

# Walking control
func set_walking(is_moving: bool):
	if is_moving:
		if not walking_player.playing:
			walking_player.play()
		walking_player.stream_paused = false
	else:
		# Use pause instead of stop for a "resuming" feel if desired, 
		# but stop is usually cleaner for footstep loops.
		# For this request, we'll use pause to keep the rhythm.
		walking_player.stream_paused = true
