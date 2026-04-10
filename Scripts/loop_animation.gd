extends Node3D

@export var animation_name: String = "Take 01"

func _ready():
	var anim_player = find_child("AnimationPlayer")
	if anim_player and anim_player is AnimationPlayer:
		var list = anim_player.get_animation_list()
		if list.size() == 0:
			return
			
		var target_anim = animation_name
		if not anim_player.has_animation(target_anim):
			# Fallback to the first available animation if "Take 01" is missing/renamed
			target_anim = list[0]
			
		anim_player.play(target_anim)
		
		# Ensure it loops
		var anim = anim_player.get_animation(target_anim)
		if anim:
			anim.loop_mode = Animation.LOOP_LINEAR
