extends Node

signal tutorial_completed

var is_tutorial_active: bool = true
var current_sequence: int = 1

# Dialogue UI reference
var dialogue_ui: CanvasLayer
var pixel_fade: CanvasLayer

# Flags to prevent re-triggering
var flags = {
	"intro_done": false,
	"first_piece_placed": false,
	"first_move_done": false,
	"first_info_closed": false,
	"combat_intro_done": false,
	"victory_done": false,
	"upgrades_done": false,
	"enemy_spawned": false
}

enum ActionType { PLACE, MOVE, INSPECT, UPGRADE, BOARD_CLICK }

func _ready():
	# Instantiate UI components
	dialogue_ui = load("res://DialogueUI.tscn").instantiate()
	get_tree().root.add_child.call_deferred(dialogue_ui)
	
	pixel_fade = load("res://PixelFade.tscn").instantiate()
	get_tree().root.add_child.call_deferred(pixel_fade)
	
	add_to_group("tutorial_manager")
	call_deferred("_connect_signals")
	
	# Wait one frame to ensure nodes are in tree
	await get_tree().process_frame
	
	# Start Sequence 1
	start_sequence_1()

func _connect_signals():
	var camera = get_viewport().get_camera_3d()
	if camera:
		camera.piece_placed.connect(on_piece_placed)
		camera.piece_moved.connect(on_piece_moved)
		camera.camera_returned_to_board.connect(on_camera_returned_to_board)
		
		# upgrade_manager bağlantısını dene (camera._ready() zaten çalışmış olmalı)
		_try_connect_upgrade_manager(camera)
	
	var inspect_ui = get_node_or_null("/root/InspectUI")
	if inspect_ui:
		inspect_ui.dismissed.connect(on_piece_info_closed)

func _try_connect_upgrade_manager(camera: Camera3D) -> bool:
	if not camera.upgrade_manager: return false
	if camera.upgrade_manager.is_connected("piece_placed_on_altar", on_piece_on_altar): return true
	camera.upgrade_manager.piece_placed_on_altar.connect(on_piece_on_altar)
	# print("[TutorialManager] Connected to piece_placed_on_altar signal.")
	return true


func start_sequence_1():
	if flags.intro_done: return
	
	# Initial state: Pixel fade at 0 (Black)
	var fade_rect = pixel_fade.get_node("ColorRect")
	fade_rect.material.set_shader_parameter("progress", 0.0)
	
	# Camera setup: Slightly tilted down
	var camera = get_viewport().get_camera_3d()
	var original_rot = camera.rotation_degrees
	camera.rotation_degrees.x -= 15.0 # Tilt down
	
	# 3 second fade-in
	var tw = create_tween()
	tw.tween_property(fade_rect.material, "shader_parameter/progress", 1.0, 3.0)
	
	# 1 second camera correction
	await get_tree().create_timer(1.0).timeout
	var cam_tw = create_tween()
	cam_tw.tween_property(camera, "rotation_degrees", original_rot, 1.0).set_trans(Tween.TRANS_SINE)
	
	await tw.finished
	
	# Dialogue Box 1
	dialogue_ui.display_text("You found your way here. Most don't. There isn't any clock, any window... any door.")
	await dialogue_ui.dialogue_finished
	
	# Dialogue Box 2
	dialogue_ui.display_text("There isn't any clock either. But I'd rather you hurry up. Just the board, you and me.")
	await dialogue_ui.dialogue_finished
	
	flags.intro_done = true
	current_sequence = 2
	
	# After box 2: chest opens, piece rises
	var oy = get_tree().get_first_node_in_group("oyun_yoneticisi")
	if oy:
		oy.start_chest_sequence()

func on_piece_info_closed():
	if current_sequence == 2:
		start_sequence_2()
	elif current_sequence == 5 and not flags.combat_intro_done:
		start_sequence_5()

func start_sequence_2():
	if flags.first_piece_placed or current_sequence != 2: return
	flags.first_piece_placed = true
	
	dialogue_ui.display_text("Every two turns, you receive a piece like this. Six at most. Be careful.")
	await dialogue_ui.dialogue_finished
	
	dialogue_ui.display_text("Now place the piece you're holding onto a green highlighted square.")
	await dialogue_ui.dialogue_finished
	
	# Show green highlights
	var camera = get_viewport().get_camera_3d()
	if camera and camera.has_method("_update_valid_moves_highlight"):
		camera._update_valid_moves_highlight()
	
	current_sequence = 3

func on_piece_placed():
	if current_sequence == 3 and not (dialogue_ui and dialogue_ui.visible):
		start_sequence_3()
		var camera = get_viewport().get_camera_3d()
		if camera and camera.has_method("_clear_highlights"):
			camera._clear_highlights()

func start_sequence_3():
	if current_sequence != 3 or flags.first_move_done: return
	flags.first_move_done = true
	
	dialogue_ui.display_text("Select the piece you just placed and make a move based on its characteristics.")
	await dialogue_ui.dialogue_finished
	current_sequence = 4

func on_piece_moved():
	if current_sequence == 4 and not (dialogue_ui and dialogue_ui.visible):
		start_sequence_4()

func start_sequence_4():
	if current_sequence != 4 or flags.first_info_closed: return
	flags.first_info_closed = true
	
	dialogue_ui.display_text("Right-click a piece standing on the board to see its information.")
	await dialogue_ui.dialogue_finished
	current_sequence = 5

func start_sequence_5():
	flags.combat_intro_done = true
	dialogue_ui.display_text("When two pieces meet, only one walks away. The stronger attack wins. Simple enough?")
	await dialogue_ui.dialogue_finished
	
	dialogue_ui.display_text("Kill my King. Protect yours. That's all there is to it.")
	await dialogue_ui.dialogue_finished
	
	dialogue_ui.display_text("Go ahead. Try.")
	await dialogue_ui.dialogue_finished
	
	var oy = get_tree().get_first_node_in_group("oyun_yoneticisi")
	if oy:
		oy.is_game_active = true # Activate game loop for combat
		if not flags.enemy_spawned:
			# Düşman hamlesi sırasında oyuncuyu engellemek için sırayı rakibe veriyoruz
			oy.current_turn = oy.GameTurn.ENEMY 
			oy.start_chest_sequence()
			flags.enemy_spawned = true

func on_king_died(is_player_king: bool):
	if is_tutorial_active:
		if is_player_king:
			# Restart tutorial from Sequence 5
			var oy = get_tree().get_first_node_in_group("oyun_yoneticisi")
			if oy: oy.cleanup_non_king_pieces()
			flags.enemy_spawned = false
			start_sequence_5()
		else:
			current_sequence = 7
			start_sequence_6()

# --- SEQUENCE 6: Upgrade Phase ---

func start_sequence_6():
	if flags.victory_done: return
	flags.victory_done = true
	
	# Oyun döngüsünü durdur, board'u temizle (trigger_win ile aynı davranış)
	var oy = get_tree().get_first_node_in_group("oyun_yoneticisi")
	if oy:
		oy.is_game_active = false
	
	# InspectUI'yi kapat (elde taş varsa gizle)
	var inspect_ui = get_node_or_null("/root/InspectUI")
	if inspect_ui and inspect_ui.has_method("hide_piece"):
		inspect_ui.hide_piece()
	
	# Box 10: "Well." — auto-dismiss after 1.5s, no click needed
	dialogue_ui.display_text("Well.")
	await get_tree().create_timer(1.5).timeout
	# Force-close without click (camera is about to move)
	dialogue_ui.visible = false
	
	# Mark game_over so sit_down() won't trigger scene reload
	var camera = get_viewport().get_camera_3d()
	if camera:
		camera.is_game_over = true
	
	# Board'u temizle (upgrade rafına geçmeden önce)
	if oy and oy.has_method("cleanup_board"):
		oy.cleanup_board()
	
	current_sequence = 7
	
	# Trigger upgrade sequence (same as trigger_win does in normal game)
	# This moves camera to upgrade shelf AND spawns draft pieces
	if camera and camera.upgrade_manager and camera.upgrade_manager.has_method("start_upgrade_sequence"):
		_try_connect_upgrade_manager(camera)  # Sinyal bağlantısını garantile
		camera.upgrade_manager.start_upgrade_sequence()
		print("[TutorialManager] upgrade_manager.start_upgrade_sequence() called.")
	else:
		if camera and camera.has_method("_transition_to_upgrade_view"):
			camera._transition_to_upgrade_view()
		print("[TutorialManager] WARNING: upgrade_manager not found, using fallback.")
	
	# Wait for stand_up (~1.2s) + camera tween to shelf (~1.2s) + buffer
	await get_tree().create_timer(2.8).timeout
	
	# Box 11: Explain whetstones — click to continue
	dialogue_ui.display_text("The whetstone on the left sharpens attack. The one on the right hardens defense.")
	await dialogue_ui.dialogue_finished
	
	# Now wait — on_piece_on_altar() will fire when player picks a piece (Box 12)


# --- SEQUENCE 6 cont: Piece reaches altar ---

func on_piece_on_altar():
	if current_sequence != 7 or not flags.victory_done: return
	
	# Box 12: Instruct to spend points — click to continue
	dialogue_ui.display_text("Spend all your points. Then come back.")
	await dialogue_ui.dialogue_finished
	# Player now uses whetstones. Camera returns automatically when _finish_upgrade() runs.

# --- SEQUENCE 7: Back at the board ---

func on_camera_returned_to_board():
	if is_tutorial_active and flags.victory_done:
		start_sequence_7()

func start_sequence_7():
	# Box 13 part 1
	dialogue_ui.display_text("Done? Good.")
	await dialogue_ui.dialogue_finished
	
	# Box 13 part 2
	dialogue_ui.display_text("I won't be as patient this time.")
	await dialogue_ui.dialogue_finished
	
	# Tutorial complete — activate full game
	is_tutorial_active = false
	tutorial_completed.emit()
	
	# Signal OyunYoneticisi to start real game loop
	var oy = get_tree().get_first_node_in_group("oyun_yoneticisi")
	if oy:
		oy.current_turn = oy.GameTurn.PLAYER
		oy.round_number = 1
		oy._show_phase_message() # PHASE 1 text on screen

func can_damage_king(is_player_king: bool) -> bool:
	if not is_tutorial_active: return true
	
	if is_player_king:
		# Player King never takes damage in tutorial
		return false
	else:
		# Enemy King only takes damage after the combat explanation is finished
		if current_sequence < 5: return false
		if current_sequence == 5 and dialogue_ui.visible: return false
		return flags.combat_intro_done

# --- Permission gate (blocks out-of-sequence board actions) ---

func is_action_allowed(action: ActionType) -> bool:
	if not is_tutorial_active: return true
	
	# Upgrade phase: always allow everything
	if current_sequence == 7:
		return true
	
	# Block while dialogue is showing
	if dialogue_ui and dialogue_ui.visible:
		return false
	
	match current_sequence:
		1, 2:
			return false
		3, 4, 5:
			return action == ActionType.PLACE or action == ActionType.MOVE or action == ActionType.BOARD_CLICK or action == ActionType.INSPECT
		6:
			return action == ActionType.PLACE or action == ActionType.MOVE or action == ActionType.BOARD_CLICK or action == ActionType.INSPECT
	
	return false
