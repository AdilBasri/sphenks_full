extends MeshInstance3D

@export_group("Skull Eye Settings")
@export var eye_color_player: Color = Color(0.1, 0.5, 0.1)
@export var eye_color_enemy: Color = Color(0.4, 0.0, 0.0)
@export var eye_emission_intensity: float = 0.85

var eye_tween: Tween

func update_eye(is_player_turn: bool):
	var mat = material_override
	if not mat or not mat is StandardMaterial3D:
		mat = StandardMaterial3D.new()
		mat.albedo_color = Color.BLACK
		mat.emission_enabled = true
		mat.emission = Color.BLACK
		mat.emission_energy_multiplier = 0.0
		material_override = mat
	
	var target_color = eye_color_player if is_player_turn else eye_color_enemy
	var target_emission = eye_emission_intensity
	
	if eye_tween: eye_tween.kill()
	eye_tween = create_tween()
	eye_tween.set_parallel(true)
	eye_tween.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	
	eye_tween.tween_property(mat, "albedo_color", target_color * 0.4, 1.0)
	eye_tween.tween_property(mat, "emission", target_color, 1.0)
	eye_tween.tween_property(mat, "emission_energy_multiplier", target_emission, 1.0)
