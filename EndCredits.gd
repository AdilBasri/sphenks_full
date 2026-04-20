extends Control

@onready var teamhusk = $Logos/TeamHusk
@onready var interred = $Logos/Interred
@onready var whistlist = $Logos/Whistlist

func _ready():
	# Initial visibility
	teamhusk.modulate.a = 0
	interred.modulate.a = 0
	whistlist.modulate.a = 0
	
	# Bam Bam Bam sequential fade-in
	var tw = create_tween()
	tw.tween_interval(1.5) # Initial black silence
	
	# Logo 1: Team Husk (Top Left)
	tw.tween_property(teamhusk, "modulate:a", 1.0, 1.2).set_trans(Tween.TRANS_SINE)
	tw.tween_interval(0.3)
	
	# Logo 2: Interred (Top Right)
	tw.tween_property(interred, "modulate:a", 1.0, 1.2).set_trans(Tween.TRANS_SINE)
	tw.tween_interval(0.3)
	
	# Logo 3: Wishlist (Bottom Center)
	tw.tween_property(whistlist, "modulate:a", 1.0, 1.2).set_trans(Tween.TRANS_SINE)
	
	# Stay for 7 seconds
	tw.tween_interval(7.0)
	
	# Fade whole screen to black
	tw.tween_property(self, "modulate:a", 0.0, 1.0)
	tw.finished.connect(_on_sequence_finished)

func _on_sequence_finished():
	get_tree().change_scene_to_file("res://anamenu.tscn")
