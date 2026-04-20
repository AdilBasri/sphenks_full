extends Control

func _ready():
	# Ensure video starts playing. 
	# A small delay can help the engine stabilize on launch.
	await get_tree().create_timer(0.2).timeout
	$VideoStreamPlayer.play()

func _on_video_stream_player_finished():
	_goto_menu()

func _goto_menu():
	# Stop input processing to prevent double scene changes
	set_process_input(false)
	get_tree().change_scene_to_file("res://anamenu.tscn")
