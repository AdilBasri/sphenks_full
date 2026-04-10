extends OmniLight3D

@export var base_energy: float = 1.0
@export var noise_speed: float = 8.0
@export var noise_amplitude: float = 0.5
@export var stutter_chance: float = 0.05

var time: float = 0.0
var _timer: float = 0.0
var _target_energy: float = 0.0

func _ready():
	base_energy = light_energy
	_target_energy = base_energy

func _process(delta):
	_timer += delta
	time += delta * noise_speed
	
	# Only update the target energy every 0.05 seconds to save CPU
	if _timer > 0.05:
		_timer = 0.0
		# Smooth wave flicker calculation
		_target_energy = base_energy + (sin(time) * noise_amplitude * 0.5)
		
		# Random stutter/glitch feel
		if randf() < stutter_chance:
			_target_energy *= randf_range(0.6, 1.4)
		
	# Smoothly interpolate to the target energy
	light_energy = lerp(light_energy, _target_energy, delta * 20.0)
