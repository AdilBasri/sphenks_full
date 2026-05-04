extends Node

var white_pieces = [
	"res://Pawn/bishop_white.tscn",
	"res://Pawn/castle_white.tscn",
	"res://Pawn/horse_white.tscn",
	"res://Pawn/piyon_white.tscn",
	"res://Pawn/queen_white.tscn"
]

var red_pieces = [
	"res://Pawn/bishop_red.tscn",
	"res://Pawn/castle_red.tscn",
	"res://Pawn/horse_red.tscn",
	"res://Pawn/piyon_red.tscn",
	"res://Pawn/queen_red.tscn"
]

var black_pieces = [
	"res://Pawn/bishop_black.tscn",
	"res://Pawn/castle_black.tscn",
	"res://Pawn/horse_black.tscn",
	"res://Pawn/piyon_black.tscn",
	"res://Pawn/queen_black.tscn"
]

var green_pieces = [
	"res://Pawn/bishop_green.tscn",
	"res://Pawn/castle_green.tscn",
	"res://Pawn/horse_green.tscn",
	"res://Pawn/piyon_green.tscn",
	"res://Pawn/queen_green.tscn"
]

enum GameTurn { PLAYER, ENEMY }
var current_turn: GameTurn = GameTurn.PLAYER:
	set(value):
		current_turn = value
		_update_skull_eye_color()
var round_number: int = 1
var phase_number: int = 1 # Moved here for better visibility
var is_game_active: bool = false
var is_tutorial_mode: bool = true
var tutorial_manager: Node
var is_processing_turn: bool = false
var pending_ai_timer: SceneTreeTimer = null

var camera: Camera3D
var box: Node3D
var anim_player: AnimationPlayer
var sequence_started: bool = false
var eye_tween: Tween
var escape_instruction_canvas: CanvasLayer = null # Track for cleanup

const PLAYER_DRAW_POS = Vector3(0.109, -0.50, -1.597)
const ENEMY_DRAW_POS = Vector3(-0.29, -0.50, -2.06)

func _ready():
	if get_tree().current_scene.name == "anamenu":
		is_game_active = false
		return
		
	add_to_group("oyun_yoneticisi")
	# Referansları bulalım
	camera = get_viewport().get_camera_3d()
	# Sahnede isminde 'box' geçen ve AnimationPlayer'ı olan objeyi bulalım
	var all_nodes = get_tree().root.find_children("*", "Node3D", true, false)
	for node in all_nodes:
		if "box" in node.name.to_lower():
			var temp_anim = node.find_child("AnimationPlayer", true, false)
			if temp_anim:
				box = node
				anim_player = temp_anim
				break
			else:
				# Eğer node isminde box varsa ama animasyonu yoksa, yine de tutalım (yedek)
				if not box: box = node
	
	if box:
		# print("Kutu bulundu: ", box.name)
		if not anim_player:
			anim_player = box.find_child("AnimationPlayer", true, false)
		
		if anim_player:
			# print("Animasyon Oynatıcı bulundu: ", anim_player.name)
			# print("Mevcut animasyonlar: ", anim_player.get_animation_list())
			pass
		else:
			# Çok daha agresif bir arama (Sahnedeki her yere bak)
			print("BAŞARISIZ: Kutuda AnimationPlayer yok. Sahne ağacında aranıyor...")
			var all_anims = get_tree().root.find_children("*", "AnimationPlayer", true, false)
			for ap in all_anims:
				print("- Sahne genelinde bulunan AP: ", ap.get_path(), " (Animasyonlar: ", ap.get_animation_list(), ")")
	
	# --- LOAD GAME DATA ---
	var sm = get_node_or_null("/root/SettingsManager")
	var save_data = sm.load_game_data() if sm else {}
	if not save_data.is_empty():
		is_tutorial_mode = save_data.get("is_tutorial_mode", true)
		phase_number = save_data.get("phase_number", 1)
		if save_data.has("piece_stats"):
			PieceDatabase.set_raw_stats(save_data["piece_stats"])
		print("[OyunYoneticisi] Game Loaded. Phase: ", phase_number, " Tutorial Mode: ", is_tutorial_mode)
	if OnlineManager.is_online and OnlineManager.lobby_id != 0:
		is_tutorial_mode = false
		phase_number = 1
		PieceDatabase.reset_database_for_online()
	elif get_tree().current_scene.name == "Node3D":
		# Direct online scene test
		is_tutorial_mode = false
		phase_number = 1
		PieceDatabase.reset_database_for_online()
		
	# BGM Setup: Tutorial mode needs intro, otherwise direct loop
	SesYoneticisi.setup_bgm_player(is_tutorial_mode)

	# Setup Tutorial Manager ONLY if needed
	if is_tutorial_mode:
		tutorial_manager = load("res://Scripts/TutorialManager.gd").new()
		add_child(tutorial_manager)
		tutorial_manager.tutorial_completed.connect(_on_tutorial_completed)

	if OnlineManager.is_online and OnlineManager.lobby_id != 0:
		print("[OyunYoneticisi] Starting Online Mode directly")
		if get_tree().current_scene.name == "Node3D":
			_setup_online_player_roles()
		start_game()
	else:
		# Start the game loop after a brief wait
		await get_tree().create_timer(1.0).timeout
		
		if not is_tutorial_mode:
			print("[OyunYoneticisi] Starting directly in Phase ", phase_number)
			start_game()
		else:
			print("[OyunYoneticisi] Starting Tutorial...")
	
	# Setup basement door interaction
	_setup_basement_door()
	_update_skull_eye_color() # Initial call

func reset_game_state():
	print("[OyunYoneticisi] Resetting game state...")
	is_game_active = false
	sequence_started = false
	is_processing_turn = false
	
	if is_instance_valid(tutorial_manager):
		tutorial_manager.queue_free()
		tutorial_manager = null
	
	# Stop any pending tweens if they exist
	if eye_tween and eye_tween.is_running():
		eye_tween.kill()
		
	# Clear escape instruction UI if it exists
	if is_instance_valid(escape_instruction_canvas):
		escape_instruction_canvas.queue_free()
		escape_instruction_canvas = null


func _input(event):
	if event is InputEventKey and event.pressed:
		# Ctrl + B: Kill Enemy King (Debug)
		if event.keycode == KEY_B and event.ctrl_pressed:
			_debug_kill_enemy_king()
		# Ctrl + N: Jump to Phase 6 (Debug)
		if event.keycode == KEY_N and event.ctrl_pressed:
			_debug_skip_to_phase_6()
		# Ctrl + F: Toggle FreeCam
		if (event.keycode == KEY_F or event.physical_keycode == KEY_F) and (event.ctrl_pressed or Input.is_key_pressed(KEY_CTRL)):
			print("[OyunYoneticisi] Ctrl+F detected!")
			_toggle_freecam()


func _debug_kill_enemy_king():
	if not is_game_active: return
	
	var grid = get_tree().root.find_child("OyuncuGrid", true, false)
	if not grid: return
	
	# Find the black king
	for hucre in grid.hucrelerin_sozlugu.values():
		if hucre.mevcut_tas and hucre.mevcut_tas.has_meta("is_king"):
			var path = hucre.mevcut_tas.get_meta("scene_path") if hucre.mevcut_tas.has_meta("scene_path") else ""
			if "black" in path.to_lower():
				print("[DEBUG] Killing Enemy King via Shortcut!")
				
				# Play shatter FX
				_spawn_shatter_fx(hucre.mevcut_tas.global_position, hucre.mevcut_tas, 1.0, true)
				
				# Deselect if necessary
				if camera and camera.has_method("_clear_selection"):
					camera._clear_selection()
				
				# Remove piece
				hucre.mevcut_tas.queue_free()
				hucre.mevcut_tas = null
				
				# Trigger win/phase end
				if is_tutorial_mode and tutorial_manager:
					tutorial_manager.on_king_died(false)
				elif camera and camera.has_method("trigger_win"):
					camera.trigger_win()
				return

func _debug_skip_to_phase_6():
	print("[DEBUG] Skipping to Phase 7 (Escape Route Testing)...")
	is_game_active = false
	cleanup_board()
	phase_number = 7
	
	# Skip directly to escape start
	_on_phase_6_start()

func _toggle_freecam():
	print("[OyunYoneticisi] Toggling FreeCam...")
	var free_cam = get_tree().root.find_child("FreeCam", true, false)
	
	if not free_cam:
		# Try searching for case-insensitive or other names
		var all_nodes = get_tree().root.find_children("*", "Camera3D", true, false)
		for node in all_nodes:
			if "free" in node.name.to_lower():
				free_cam = node
				break
	
	if not free_cam:
		# Create it dynamically if it doesn't exist
		print("[OyunYoneticisi] FreeCam node not found. Creating one...")
		free_cam = Camera3D.new()
		free_cam.name = "FreeCam"
		free_cam.set_script(load("res://Scripts/FreeCam.gd"))
		# Start at current camera position
		var current_cam = get_viewport().get_camera_3d()
		if current_cam:
			free_cam.global_transform = current_cam.global_transform
		get_tree().root.add_child(free_cam)
	
	if free_cam.has_method("set_enabled"):
		var new_state = not free_cam.is_active
		free_cam.set_enabled(new_state)
		print("[OyunYoneticisi] FreeCam enabled: ", new_state)
		
		# If we are disabling freecam, restore the mouse mode of the game
		if not new_state:
			var cam = get_viewport().get_camera_3d()
			if cam and cam.has_method("restore_mouse_mode"):
				cam.restore_mouse_mode()
	else:
		# If the node exists but doesn't have the script, attach it
		print("[OyunYoneticisi] FreeCam node found but missing script. Attaching...")
		free_cam.set_script(load("res://Scripts/FreeCam.gd"))
		free_cam.set_enabled(true)

func _on_phase_6_start():
	print("[OyunYoneticisi] Entering Escape Sequence (Final Phase). Triggering Stand Up.")
	if camera and camera.has_method("stand_up"):
		camera.stand_up()
	
	# Show message at Top Center
	await get_tree().create_timer(1.2).timeout
	_show_escape_instruction("Find a way to get out.")
	
	# Ensure door interaction is setup
	_setup_basement_door()
func _show_escape_instruction(text: String):
	if is_instance_valid(escape_instruction_canvas):
		escape_instruction_canvas.queue_free()

	escape_instruction_canvas = CanvasLayer.new()
	escape_instruction_canvas.layer = 100
	get_tree().root.add_child(escape_instruction_canvas)
	
	var label = Label.new()
	label.name = "EscapeInstruction"
	label.text = text
	var settings = LabelSettings.new()
	settings.font = load("res://Assets/fonts/dominica.ttf")
	settings.font_size = 28 # Slightly smaller
	settings.font_color = Color(0.9, 0.85, 0.7) # Cream/Yellowish
	settings.outline_size = 6
	settings.outline_color = Color.BLACK
	label.label_settings = settings
	
	label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	label.position.y += 40 # Higher (was 50)
	escape_instruction_canvas.add_child(label)
	
	label.modulate.a = 0
	var tw = create_tween()
	tw.tween_property(label, "modulate:a", 1.0, 1.0)

func _start_sitting_loop():
	# print("[OyunYoneticisi] Starting Sitting Animation Loop...")
	var sitting_node = get_tree().get_first_node_in_group("sitting_node")
	
	if not sitting_node:
		sitting_node = get_node_or_null("Sitting")
	
	if sitting_node:
		var sitting_anim = sitting_node.get_node_or_null("AnimationPlayer")
		if not sitting_anim:
			sitting_anim = sitting_node.find_child("AnimationPlayer", true, false)
		if sitting_anim:
			# INJECTION LOGIC: Ensure animations are present
			# Sitting loop should only play idle animation
			# Puke is handled by camera_3d.gd sequence
			if not sitting_anim.has_animation("oturma1") or not sitting_anim.has_animation("puke"):
				print("[OyunYoneticisi] Injecting missing animations into Sitting AnimationPlayer...")
				var lib: AnimationLibrary
				if sitting_anim.has_animation_library(""):
					lib = sitting_anim.get_animation_library("")
				else:
					lib = AnimationLibrary.new()
					sitting_anim.add_animation_library("", lib)
				
				if not sitting_anim.has_animation("oturma1"):
					var a_oturma = load("res://oturma1.res")
					if a_oturma: lib.add_animation("oturma1", a_oturma)
				
				if not sitting_anim.has_animation("puke"):
					var a_puke = load("res://puke.res")
					if a_puke: lib.add_animation("puke", a_puke)
			
			# Play Loop
			if sitting_anim.has_animation("oturma1"):
				# print("[OyunYoneticisi] Preparing to start Sitting loop...")
				
				# Check if Skeleton3D exists and is visible
				var skel = sitting_node.find_child("Skeleton3D", true, false)
				if skel:
					# print("[OyunYoneticisi] Skeleton3D found. Visible=", skel.visible, " BoneCount=", skel.get_bone_count())
					# print("[OyunYoneticisi] First 5 Bone Names: ", skel.get_bone_name(0), ", ", skel.get_bone_name(1), ", ", skel.get_bone_name(2), ", ", skel.get_bone_name(3), ", ", skel.get_bone_name(4))
					
					# REMAP ANIMATIONS (The Ultimate Fix)
					var lib: AnimationLibrary = sitting_anim.get_animation_library("")
					for anim_name in ["oturma1", "puke"]:
						if sitting_anim.has_animation(anim_name):
							var old_anim = sitting_anim.get_animation(anim_name)
							if old_anim is Animation:
								var new_anim = old_anim.duplicate()
								var remapped_count = 0
								# REMAPPING DISABLED: Using explicit root_node in Sitting.tscn instead
								# for i in range(new_anim.get_track_count()):
								# 	var path = new_anim.track_get_path(i)
								# 	var path_str = str(path)
								# 	if "Skeleton3D:" in path_str:
								# 		var new_path = path_str.replace("Skeleton3D:", ".:")
								# 		new_anim.track_set_path(i, NodePath(new_path))
								# 		remapped_count += 1
								pass
								
								if remapped_count > 0:
									# print("[OyunYoneticisi] Remapped ", remapped_count, " tracks for ", anim_name)
									if anim_name == "oturma1":
										new_anim.loop_mode = Animation.LOOP_LINEAR
									lib.add_animation(anim_name, new_anim)
					
					# Animation playback REMOVED - Keep skeleton active for head tracking
					sitting_anim.active = false 
					# print("[OyunYoneticisi] Boss animations disabled. HeadLook remains active.")
					
					# Re-enable head look after a short delay
					await get_tree().create_timer(1.0).timeout
					if skel.has_method("set_process"):
						# print("[OyunYoneticisi] Re-enabling HeadLook logic.")
						skel.set_process(true)
				
				# print("[OyunYoneticisi] Animation Tracks for 'oturma1':")
				# for i in range(final_anim.get_track_count()):
				# 	print("  - Track %d: %s (Type: %d)" % [i, final_anim.track_get_path(i), final_anim.track_get_type(i)])
			else:
				print("[OyunYoneticisi] ERROR: 'oturma1' still missing after injection! List: ", sitting_anim.get_animation_list())
		else:
			print("[OyunYoneticisi] ERROR: AnimationPlayer not found in Sitting node.")
	else:
		print("[OyunYoneticisi] ERROR: Sitting node NOT FOUND.")

func start_game():
	var grid = get_tree().root.find_child("OyuncuGrid", true, false)
	if grid and grid.has_method("spawn_kings"):
		grid.spawn_kings()
		
	is_game_active = true
	round_number = 1
	current_turn = GameTurn.PLAYER
	
	if OnlineManager.is_online and OnlineManager.lobby_id != 0 and phase_number == 1:
		var cam = get_viewport().get_camera_3d()
		if cam and cam.get("upgrade_manager"):
			cam.upgrade_manager.start_upgrade_sequence()
			return
			
	start_current_turn_logic()

func start_current_turn_logic():
	if not is_game_active and is_tutorial_mode:
		return
		
	if camera and camera.is_game_over:
		is_game_active = false
		return
		
	# print("--- Round %d | Turn: %s ---" % [round_number, "PLAYER" if current_turn == GameTurn.PLAYER else "ENEMY"])
	
	# Draw Piece if round is odd (1, 3, 5...)
	var should_draw = (round_number % 2 != 0)
	if is_tutorial_mode:
		# In tutorial, only PLAYER gets automatic pieces (to recover if they die)
		# Enemy is manually given only ONE piece by TutorialManager
		if current_turn == GameTurn.ENEMY:
			should_draw = false
			
	if should_draw:
		start_chest_sequence()
	else:
		# Check for valid moves in even rounds (Move Only)
		var is_white = (current_turn == GameTurn.PLAYER)
		if not _has_side_any_moves(is_white):
			print("--- Tarafın yapabileceği hamle yok, sıra geçiliyor... ---")
			await get_tree().create_timer(1.0).timeout
			next_turn()
		else:
			if current_turn == GameTurn.ENEMY:
				_process_enemy_move_only()

func restart_new_match():
	is_game_active = false
	cleanup_board()
	
	# Reset state
	phase_number += 1
	round_number = 1
	current_turn = GameTurn.PLAYER
	sequence_started = false
	
	# AI Upgrade: Düşmana da 1 puan ver (Rastgele dağıt)
	_apply_enemy_upgrade()
	
	# --- YENİ SİSTEM: KİNG UPGRADES (Phase Transitions) ---
	# Düşman King her bölüm canı artar
	var enemy_king_heal = 1
	if phase_number == 3 or phase_number == 6:
		enemy_king_heal = 2
	
	PieceDatabase.upgrade_piece("king", false, "defense", enemy_king_heal)
	
	# Oyuncu King her iki bölümde bir +1 can alır
	if phase_number % 2 == 0:
		PieceDatabase.upgrade_piece("king", true, "defense", 1)
	
	# Şahları ve Grid'i resetle
	var grid = get_tree().root.find_child("OyuncuGrid", true, false)
	if grid and grid.has_method("spawn_kings"):
		grid.spawn_kings()
		
	print("[OyunYoneticisi] Phase %d hazırlanıyor..." % phase_number)
	await get_tree().create_timer(0.5).timeout
	
	if phase_number != 7:
		if has_method("_show_phase_message"):
			_show_phase_message()
	
	if phase_number == 7:
		_on_phase_6_start()
		return # End of typical round loop, start escape
	
	# Save progress at the start of a new Phase
	save_game()
	
	await get_tree().create_timer(1.2).timeout
	is_game_active = true
	start_current_turn_logic()

func _apply_enemy_upgrade():
	var types = ["pawn", "castle", "bishop", "horse", "queen"]
	var type = types[randi() % types.size()]
	var stat = "attack" if randf() > 0.5 else "defense"
	
	# PieceDatabase üzerinden düşman (Siyah) taşını geliştir
	PieceDatabase.upgrade_piece(type, false, stat, 1)

func _show_phase_message():
	var canvas = CanvasLayer.new()
	canvas.layer = 200
	get_tree().root.add_child(canvas)
	
	var label = Label.new()
	label.text = "PHASE %d" % phase_number
	
	var settings = LabelSettings.new()
	settings.font = load("res://Assets/fonts/dominica.ttf")
	settings.font_size = 84 # Dominica için daha görkemli bir boyut
	settings.font_color = Color.WHITE
	settings.outline_size = 14
	settings.outline_color = Color(0, 0, 0, 0.9)
	label.label_settings = settings
	
	label.set_anchors_preset(Control.PRESET_CENTER)
	label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	label.grow_vertical = Control.GROW_DIRECTION_BOTH
	canvas.add_child(label)
	
	label.modulate.a = 0
	var tw = create_tween()
	tw.tween_property(label, "modulate:a", 1.0, 0.4)
	tw.tween_interval(1.0)
	tw.tween_property(label, "modulate:a", 0.0, 0.4)
	tw.tween_callback(canvas.queue_free)

func cleanup_board():
	# print("Oyun bitti, tahta temizleniyor...")
	var grid = get_tree().root.find_child("OyuncuGrid", true, false)
	if not grid: return
	
	for hucre in grid.hucrelerin_sozlugu.values():
		if hucre.mevcut_tas:
			if not hucre.mevcut_tas.has_meta("is_king"):
				hucre.mevcut_tas.queue_free()
				hucre.mevcut_tas = null
			else:
				# Reset king and its defense
				var king = hucre.mevcut_tas
				var path = king.get_meta("scene_path")
				var stats = PieceDatabase.get_piece_stats(path)
				if not stats.is_empty():
					king.set_meta("current_defense", stats["defense"])

func cleanup_non_king_pieces():
	print("Tutorial reset: Cleaning non-king pieces...")
	var grid = get_tree().root.find_child("OyuncuGrid", true, false)
	if not grid: return
	
	for hucre in grid.hucrelerin_sozlugu.values():
		if hucre.mevcut_tas and not hucre.mevcut_tas.has_meta("is_king"):
			hucre.mevcut_tas.queue_free()
			hucre.mevcut_tas = null
	
	# Ensure Kings are present and reset to full health
	if grid.has_method("spawn_kings"):
		grid.spawn_kings()

func next_turn():
	if is_processing_turn or not is_game_active: return
	is_processing_turn = true
	
	if camera and camera.has_method("stop_tracking"):
		camera.stop_tracking()
		
	# Kill any pending AI thinking if turn is forced to switch
	
	if current_turn == GameTurn.PLAYER:
		current_turn = GameTurn.ENEMY
	else:
		current_turn = GameTurn.PLAYER
		round_number += 1
	
	start_current_turn_logic()
	
	# Clear boss target when turn ends or changes
	_set_boss_head_target(null)
	
	is_processing_turn = false

func start_chest_sequence():
	_update_skull_eye_color()
	if camera and camera.is_game_over: return
	# print("Sandık sekansı başlatılıyor...")
	if sequence_started: 
		# print("Sekans zaten çalışıyor!")
		return
	sequence_started = true
	
	if camera: camera.is_receiving_piece = true
	
	if anim_player:
		# En uygun animasyonu seç (İçinde 'open' geçen)
		var anim_name = anim_player.get_animation_list()[0]
		for a in anim_player.get_animation_list():
			if "open" in a.to_lower() or "açılış" in a.to_lower():
				anim_name = a
				break
		
		# print("Seçilen Animasyon: ", anim_name)
		anim_player.play(anim_name)
		
		# Animasyonu 2.5 saniyeye kadar oynat ve gerekirse durdur/yavaşlat
		await get_tree().create_timer(2.3).timeout # Biraz önceden hazırlık
		
		# Hangi tarafsa ona göre taş çıkar
		if current_turn == GameTurn.PLAYER:
			spawn_random_white_piece()
		else:
			_spawn_random_black_piece_for_enemy()
	else:
		print("HATA: Animasyon oynatıcı (AnimationPlayer) bulunamadı!")
		sequence_started = false

func spawn_random_white_piece():
	if camera and camera.held_piece:
		print("Oyuncunun elinde zaten taş var, yenisi verilmiyor.")
		sequence_started = false
		return

	if camera: camera.is_receiving_piece = true
	
	var random_path = white_pieces[randi() % white_pieces.size()]
	# print("Taş çıkarılıyor: ", random_path)
	
	# Horse Trigger
	if "horse" in random_path.to_lower():
		SesYoneticisi.play_angry(_get_enemy_pos())
	
	var piece_scene = load(random_path)
	if not piece_scene:
		print("HATA: Taş sahnesi yüklenemedi: ", random_path)
		sequence_started = false
		if camera: camera.is_receiving_piece = false
		return
		
	var piece = piece_scene.instantiate()
	
	# ÖNEMLİ: Meta verisini SAHNEYE EKLEMEDEN ÖNCE verelim ki GlobalShaderApplier bunu yakalasın
	piece.set_meta("render_on_top", true)
	
	# Önce sahneye ekliyoruz, sonra global_position atıyoruz (Aksi takdirde 'not in tree' hatası verir)
	get_tree().root.add_child(piece)
	
	# Adım 1: Taşı tam olarak sandığın merkezinde oluşturalım
	piece.global_position = box.global_position
	piece.scale = Vector3(0.1, 0.1, 0.1) # Asla tam 0 yapmıyoruz (Basis Inversion hatası için)
	
	SesYoneticisi.play_handing()
	
	# Materyal ayarlarını da yapalım (StandardMaterial kullanan taşlar için)
	set_piece_render_priority(piece, 100, true)
	
	# Initialize persistent health
	var stats = PieceDatabase.get_piece_stats(random_path)
	if not stats.is_empty():
		piece.set_meta("current_defense", stats["defense"])
	
	# Adım 2: Sandıktan önce hafifçe yukarı yükselme animasyonu (0.4 saniye)
	var rise_tween = create_tween().set_parallel(true)
	rise_tween.tween_property(piece, "global_position", box.global_position + Vector3(0, 0.3, 0), 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	rise_tween.tween_property(piece, "scale", Vector3(1.0, 1.0, 1.0), 0.5)
	
	await rise_tween.finished
	
	# Adım 3: Şimdi kameraya bağlayıp eldeki konuma süzülmesini sağlayalım
	piece.reparent(camera)
	
	var drift_tween = create_tween().set_parallel(true)
	# 'Elde tutma' (Yeni sağ-üst çapraz ve dev boyut) konumuna süzül
	drift_tween.tween_property(piece, "position", Vector3(0.75, -0.05, -0.8), 1.0).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	drift_tween.tween_property(piece, "rotation_degrees", Vector3(5, 155, 0), 1.0)
	drift_tween.tween_property(piece, "scale", Vector3(4.2, 4.2, 4.2), 1.0)
	
	await drift_tween.finished
	
	if camera: camera.is_receiving_piece = false
	
	# Kamera scriptine bildirim gönder
	if camera.has_method("pick_up_piece"):
		camera.pick_up_piece(piece, random_path)
		
	sequence_started = false
	if anim_player: anim_player.speed_scale = 1.0 # Kutuyu kapat

func _spawn_random_black_piece_for_enemy():
	if camera: camera.is_receiving_piece = true
	var random_path = black_pieces[randi() % black_pieces.size()]
	# print("Düşman taşı çıkarılıyor: ", random_path)
	
	# Horse Trigger
	if "horse" in random_path.to_lower():
		SesYoneticisi.play_evil_laugh()
	
	var piece_scene = load(random_path)
	if not piece_scene:
		if camera: camera.is_receiving_piece = false
		return
	
	var piece = piece_scene.instantiate()
	piece.set_meta("render_on_top", true)
	get_tree().root.add_child(piece)
	
	if camera and camera.has_method("start_tracking"):
		camera.start_tracking(piece)
	
	_set_boss_head_target(piece) # Boss tracks his new piece
	
	piece.global_position = box.global_position
	piece.scale = Vector3(0.1, 0.1, 0.1)
	
	SesYoneticisi.play_handing()
	
	set_piece_render_priority(piece, 100, true)
	
	# Initialize persistent health
	var stats = PieceDatabase.get_piece_stats(random_path)
	if not stats.is_empty():
		piece.set_meta("current_defense", stats["defense"])
	
	# Rise animation
	var tw = create_tween().set_parallel(true)
	tw.tween_property(piece, "global_position", box.global_position + Vector3(0, 0.3, 0), 0.5).set_trans(Tween.TRANS_BACK)
	tw.tween_property(piece, "scale", Vector3(1.0, 1.0, 1.0), 0.5)
	await tw.finished
	
	# Move to Enemy Draw Position (facing player)
	var tw2 = create_tween().set_parallel(true)
	tw2.tween_property(piece, "global_position", ENEMY_DRAW_POS, 1.0).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	tw2.tween_property(piece, "rotation_degrees:y", 0.0, 1.0)
	await tw2.finished
	
	if camera: camera.is_receiving_piece = false
	
	sequence_started = false
	if anim_player: anim_player.speed_scale = 1.0 # Kutuyu kapat
	
	# AI Think and Place
	await get_tree().create_timer(randf_range(1.5, 3.0)).timeout
	_ai_place_piece(piece, random_path)

func _set_boss_head_target(node: Node3D):
	var boss_node = get_tree().get_first_node_in_group("sitting_node")
	if not boss_node:
		boss_node = get_node_or_null("Sitting")
	
	if boss_node:
		var skel = boss_node.find_child("Skeleton3D", true, false)
		if skel and "target_override" in skel:
			skel.target_override = node

func _get_enemy_pos() -> Vector3:
	var sitting = get_tree().get_first_node_in_group("sitting_node")
	if sitting: return sitting.global_position
	return Vector3.ZERO

func _update_skull_eye_color():
	var goz = get_node_or_null("Masa/skullp/Goz")
	if not goz: goz = find_child("Goz", true, false)
	if not goz: return
	
	if goz.has_method("update_eye"):
		goz.update_eye(current_turn == GameTurn.PLAYER)

func _setup_basement_door():
	# Find 'kapi' in the scene (search globally if needed)
	var kapi = get_tree().root.find_child("kapi", true, false)
	if not kapi:
		var basement = get_tree().root.find_child("Bodrum_Odasi", true, false)
		if basement:
			kapi = basement.find_child("kapi", true, false)
	
	if not kapi: 
		# Final fallback
		var all_nodes = get_tree().root.find_children("*", "Node3D", true, false)
		for n in all_nodes:
			if n.name.to_lower() == "kapi":
				kapi = n
				break
	
	if not kapi: 
		print("[OyunYoneticisi] ERROR: 'kapi' not found in scene!")
		return
	
	# The user provided a specific path inside the door GLB
	# Path: door_old_metal/door_2_door old metal_0
	var door_mesh = kapi.find_child("door_2_door", true, false)
	
	if not door_mesh:
		# Fallback: find any mesh containing 'door' and 'metal'
		var meshes = kapi.find_children("*", "MeshInstance3D", true, false)
		for m in meshes:
			if "door" in m.name.to_lower() and "metal" in m.name.to_lower():
				door_mesh = m
				break
	
	if door_mesh:
		print("[OyunYoneticisi] Found Basement Door Mesh: ", door_mesh.name)
		
		# 1. Create StaticBody3D for raycasting - ATTACH TO KAPI (more stable pivot)
		var sb = StaticBody3D.new()
		sb.name = "DoorStaticBody"
		kapi.add_child(sb) # Change from door_mesh to kapi
		sb.set_meta("is_door", true)
		sb.collision_layer = 1
		sb.collision_mask = 1
		
		# 2. Add CollisionShape3D (Use a fixed size if AABB is small/weird)
		var cs = CollisionShape3D.new()
		var box_shape = BoxShape3D.new()
		box_shape.size = Vector3(2.0, 3.0, 1.0) # Even larger block
		cs.shape = box_shape
		sb.add_child(cs)
		# Position it centrally relative to kapi (basement door typically faces +Z or -Z)
		cs.position = Vector3(0, 1.0, 0) # Center vertically
		
		# 3. Attach Logic Script
		var logic = load("res://DoorInteraction.gd").new()
		logic.set_meta("target_node", door_mesh) # Set BEFORE add_child
		add_child(logic)
		sb.set_meta("door_logic", logic)
		
		# print("[OyunYoneticisi] Basement door link complete.")
		
		# Set as globally accessible for news tracking
		logic.add_to_group("door_logic")

var _news_check_timer: Timer = null
var _all_news_removed: bool = false

func _process(delta):
	# Debug print every 2 seconds
	if phase_number == 7:
		if not _all_news_removed:
			_check_news_status()

var _cached_news_node: Node = null
var _news_touched_count: int = 0
var _already_touched: Dictionary = {}

func notify_news_grabbed(node: Node):
	# Door opening condition: ONLY items inside the "News" node count.
	if not _cached_news_node:
		_cached_news_node = get_tree().root.find_child("News", true, false)
		if not _cached_news_node:
			_cached_news_node = get_tree().current_scene.find_child("News", true, false)
	
	if _cached_news_node and not _cached_news_node.is_ancestor_of(node):
		print("[OyunYoneticisi] Grabbed item is NOT in News node. Ignoring for escape trigger.")
		return

	if not _already_touched.has(node.get_instance_id()):
		_already_touched[node.get_instance_id()] = true
		_news_touched_count += 1
		print("[OyunYoneticisi] Newspaper TOUCHED! Total: ", _news_touched_count, "/3")

func notify_news_released(node: Node):
	# Trigger escape readiness only when the 3rd paper is DROPPED
	if _news_touched_count >= 3 and not _all_news_removed:
		_all_news_removed = true
		print("[OyunYoneticisi] RELEASE TRIGGER: Escape ready!")
		_force_enable_door_escape()

func _force_enable_door_escape():
	var door_logic = get_tree().get_first_node_in_group("door_logic")
	if door_logic and door_logic.has_method("enable_escape"):
		door_logic.enable_escape()
		print("[OyunYoneticisi] ESCAPE ENABLED SUCCESSFULLY.")
	else:
		# Search even harder
		var nodes = get_tree().get_nodes_in_group("door_logic")
		if nodes.size() > 0:
			nodes[0].enable_escape()
			print("[OyunYoneticisi] ESCAPE ENABLED SUCCESSFULLY (Fallback search).")

func _check_news_status():
	if not _cached_news_node:
		_cached_news_node = get_tree().root.find_child("News", true, false)
		if not _cached_news_node:
			_cached_news_node = get_tree().current_scene.find_child("News", true, false)
			
	if not _cached_news_node: return
	
	var count = _cached_news_node.get_child_count()
	if count == 0 and not _all_news_removed:
		_all_news_removed = true
		print("[OyunYoneticisi] ALL NEWS REMOVED (Child Count Check).")
		_force_enable_door_escape()

func _ai_place_piece(piece: Node3D, scene_path: String):
	# Find Grid
	var grid = get_tree().root.find_child("OyuncuGrid", true, false)
	if not grid: return
	
	# AI focuses on top rows (0 and 1)
	var possible_cells = []
	for cell in grid.hucrelerin_sozlugu.values():
		if (cell.satir == 0 or cell.satir == 1) and not cell.mevcut_tas:
			# Extra check: If Row 0, avoid King spot if it's already there
			if cell.satir == 0 and cell.sutun == 2: continue
			possible_cells.append(cell)
	
	if possible_cells.size() > 0:
		var target_cell = possible_cells[randi() % possible_cells.size()]
		
		# Move to cell
		var tw = create_tween().set_parallel(true)
		tw.tween_property(piece, "global_position", target_cell.global_position, 0.5).set_trans(Tween.TRANS_SINE)
		tw.tween_property(piece, "rotation_degrees", Vector3.ZERO, 0.5)
		await tw.finished
		
		SesYoneticisi.play_place_block()
		
		# Finalize placement
		piece.reparent(get_tree().root)
		set_piece_render_priority(piece, 0, false)
		piece.set_meta("scene_path", scene_path)
		target_cell.mevcut_tas = piece
		
		# After placing, AI moves the piece too?
		# User said: "düşman koyduğu taşı en mantıklı şekilde... hareket ettirecek"
		await get_tree().create_timer(1.0).timeout
		_ai_move_piece(target_cell)
	else:
		print("Düşman için uygun yerleşim yeri bulunamadı!")
		next_turn()

func _ai_move_piece(hucre: GridHucre):
	if not hucre.mevcut_tas:
		next_turn()
		return
		
	# Instead of just this piece, AI should consider ALL pieces it has
	# But if called after placement, maybe it just wants to move THIS piece?
	# User: "düşman koyduğu taşı en mantıklı şekilde... hareket ettirecek"
	# Let's find the best move for THIS piece specifically
	var best_move = _get_best_move_for_piece(hucre)
	if best_move:
		await _execute_ai_move(hucre, best_move)
	else:
		next_turn()

func _process_enemy_move_only():
	var grid = get_tree().root.find_child("OyuncuGrid", true, false)
	if not grid: return
	
	var best_score = -999999
	var best_move_data = null # { "from": hucre, "to": target_hucre }
	
	for hucre in grid.hucrelerin_sozlugu.values():
		if hucre.mevcut_tas and "black" in hucre.mevcut_tas.get_meta("scene_path").to_lower():
			var move = _get_best_move_for_piece(hucre)
			if move:
				var score = _evaluate_move(hucre, move)
				if score > best_score:
					best_score = score
					best_move_data = {"from": hucre, "to": move}
	
	if best_move_data:
		var this_turn = current_turn
		pending_ai_timer = get_tree().create_timer(1.0)
		await pending_ai_timer.timeout
		
		# Guard: Turn must still be Enemy and timer must still be the active one
		if current_turn != this_turn or not is_game_active:
			return
			
		await _execute_ai_move(best_move_data["from"], best_move_data["to"])
	else:
		next_turn()

func _get_best_move_for_piece(hucre: GridHucre) -> GridHucre:
	var path = hucre.mevcut_tas.get_meta("scene_path")
	var valid_moves = PieceDatabase.get_valid_moves(Vector2i(hucre.sutun, hucre.satir), path)
	if valid_moves.size() == 0: return null
	
	var grid = hucre.get_parent()
	var best_score = -999999
	var best_target = null
	
	for move_coord in valid_moves:
		if grid.hucrelerin_sozlugu.has(move_coord):
			var target = grid.hucrelerin_sozlugu[move_coord]
			
			# Friendly Fire Check: AI (Black) cannot move to square with another Black piece
			if target.mevcut_tas:
				var path_target = target.mevcut_tas.get_meta("scene_path") if target.mevcut_tas.has_meta("scene_path") else ""
				if "black" in path_target.to_lower():
					continue
			
			var score = _evaluate_move(hucre, target)
			if score > best_score:
				best_score = score
				best_target = target
				
	return best_target

func _evaluate_move(from: GridHucre, to: GridHucre) -> float:
	var score = 0.0
	var piece = from.mevcut_tas
	var path = piece.get_meta("scene_path")
	var attacker_stats = PieceDatabase.get_piece_stats(path)
	
	# Target Player King (Absolute priority)
	if to.mevcut_tas:
		var defender_path = to.mevcut_tas.get_meta("scene_path").to_lower()
		var defender_stats = PieceDatabase.get_piece_stats(defender_path)
		
		if "white" in defender_path:
			if "king" in defender_path:
				score += 10000.0 # Kill King!
			else:
				score += 100.0 + defender_stats["defense"]
				
			# Check if we can actually kill it
			var current_def = to.mevcut_tas.get_meta("current_defense") if to.mevcut_tas.has_meta("current_defense") else defender_stats["defense"]
			if attacker_stats["attack"] < current_def:
				score -= 50.0 # Disincentivize pointless bouncing
	
	# Proximity to player side (Row 4 is where player King resides)
	# Dist to Row 4, Col 2
	var dist_to_king = Vector2(to.sutun, to.satir).distance_to(Vector2(2, 4))
	score += (10.0 - dist_to_king) * 5.0
	
	# Defence: If enemy is near our King (Row 0, Col 2)
	# This is a bit simplified, but AI will move to squares near its own king if threatened
	return score

func _execute_ai_move(from: GridHucre, to: GridHucre):
	if not from or not is_instance_valid(from.mevcut_tas):
		next_turn()
		return
		
	var piece = from.mevcut_tas
	var path = piece.get_meta("scene_path")
	from.mevcut_tas = null
	
	# Focus camera on the moving piece
	if camera and camera.has_method("start_tracking"):
		camera.start_tracking(piece)
		
	_set_boss_head_target(piece) # Boss tracks his moving piece
	
	# Jump animation (Shared logic with camera_3d but automated)
	var tw = create_tween()
	var start_pos = piece.global_position
	var end_pos = to.global_position
	var mid_point = (start_pos + end_pos) / 2.0 + Vector3(0, 0.15, 0)
	
	tw.tween_property(piece, "global_position", mid_point, 0.25).set_trans(Tween.TRANS_SINE)
	tw.tween_property(piece, "global_position", end_pos, 0.25).set_trans(Tween.TRANS_SINE)
	await tw.finished
	
	SesYoneticisi.play_place_block()
	
	# Friendly fire guard for AI
	if to.mevcut_tas:
		var target_path = to.mevcut_tas.get_meta("scene_path") if to.mevcut_tas.has_meta("scene_path") else ""
		if "black" in target_path.to_lower():
			next_turn()
			return
	
	# Combat Resolution (Same as player's)
	if to.mevcut_tas:
		var attacker_stats = PieceDatabase.get_piece_stats(path)
		var defender = to.mevcut_tas
		var defender_path = defender.get_meta("scene_path")
		var defender_stats = PieceDatabase.get_piece_stats(defender_path)
		
		var current_def = defender.get_meta("current_defense") if defender.has_meta("current_defense") else defender_stats["defense"]
		
		# Check for invulnerability (Kings)
		var is_king = defender.has_meta("is_king")
		if is_king:
			var tm = get_tree().get_first_node_in_group("tutorial_manager")
			if tm and not tm.can_damage_king("white" in defender_path.to_lower()):
				# Sync bounce back by setting def same as before so it doesn't drop to 0
				pass
			else:
				current_def -= attacker_stats["attack"]
		else:
			current_def -= attacker_stats["attack"]
			
		defender.set_meta("current_defense", current_def)
			
		# Premium Damage Feedback (Material Aware)
		var is_white_defender = "white" in defender_path.to_lower()
		var hit_intensity = 0.33 if current_def > 0 else 1.0
		var is_king_death = is_king and current_def <= 0
		_spawn_shatter_fx(defender.global_position, defender, hit_intensity, is_king_death)
		
		# King Specific Hit Feedback
		if is_king:
			if not is_white_defender:
				# Enemy King Hit: Play Chime
				SesYoneticisi.play_hover() 
			else:
				# Player King Hit: INTENSE Shake
				if camera.has_method("apply_shake"): camera.apply_shake(1.0, 1.0)
		
		if camera.has_method("apply_shake") and not (is_king and is_white_defender):
			camera.apply_shake(0.2, 0.3)
		
		if current_def <= 0:
			# Capture!
			if not is_white_defender:
				# React physically only when enemy piece is lost
				_enemy_react_to_damage(is_king)
			if camera.has_method("apply_shake"): camera.apply_shake(0.4, 0.5)
			
			var is_player_king = is_king and "white" in defender_path.to_lower()
			
			SesYoneticisi.play_piece_remove()
			defender.queue_free()
			to.mevcut_tas = piece
			piece.reparent(to)
			piece.position = Vector3.ZERO
			
			if is_king:
				if is_player_king:
					if is_tutorial_mode:
						tutorial_manager.on_king_died(true)
					elif camera.has_method("trigger_loss"): 
						camera.trigger_loss()
				else:
					if is_tutorial_mode:
						tutorial_manager.on_king_died(false)
					elif camera.has_method("trigger_win"): 
						camera.trigger_win()
		else:
			# Bounce back!
			var tw_back = create_tween()
			tw_back.tween_property(piece, "global_position", from.global_position, 0.3).set_trans(Tween.TRANS_BACK)
			await tw_back.finished
			from.mevcut_tas = piece
			piece.reparent(from)
			piece.position = Vector3.ZERO
	else:
		to.mevcut_tas = piece
		piece.reparent(to)
		piece.position = Vector3.ZERO
	
	next_turn()

		
func set_piece_render_priority(node: Node, priority: int, x_ray: bool = false):
	# Meta verisini güncelle ki GlobalShaderApplier fark etsin (Eğer dinamik değişirse)
	node.set_meta("render_on_top", x_ray)
	
	if node is MeshInstance3D:
		
		# Override materyalleri gez
		for i in range(node.get_surface_override_material_count()):
			var mat = node.get_surface_override_material(i)
			if not mat:
				mat = node.mesh.surface_get_material(i)
			
			if mat:
				# Materyali unique yapalım ki sadece bu taş etkilensin
				# (Daha önce yapılmışsa duplicate() masrafından kaçınmak için kontrol edilebilir ama şimdilik güvenli yol)
				var new_mat = mat.duplicate()
				new_mat.render_priority = priority
				
				if new_mat is StandardMaterial3D:
					new_mat.no_depth_test = x_ray
				elif new_mat is ShaderMaterial:
					# ShaderMaterial'da no_depth_test shader kodundadır, 
					# GlobalShaderApplier bunu 'render_on_top' meta verisine bakarak shader değiştirerek halledecek.
					pass
					
				node.set_surface_override_material(i, new_mat)
		
		# Eğer override yoksa mesh'in kendisindeki materyalleri override olarak atayalım
		if node.mesh:
			for i in range(node.mesh.get_surface_count()):
				var mat = node.mesh.surface_get_material(i)
				if mat:
					var new_mat = mat.duplicate()
					new_mat.render_priority = priority
					if new_mat is StandardMaterial3D:
						new_mat.no_depth_test = x_ray
					node.set_surface_override_material(i, new_mat)
		
		# GlobalShaderApplier'ı manuel tetikleyelim ki shader'ı (no-depth) hemen güncellesin
		var applier = get_tree().root.find_child("GlobalShaderApplier", true, false)
		if applier and applier.has_method("_apply_toon_ps1"):
			applier._apply_toon_ps1(node, true)
	
	for child in node.get_children():
		set_piece_render_priority(child, priority, x_ray)
	
	# Not: sequence_started ve anim_player.speed_scale artık çağıran fonksiyonlarda sıfırlanıyor

func _has_side_any_moves(is_white: bool) -> bool:
	# 1. If currently holding a piece from box, they HAVE a move (placement)
	if is_white and camera and camera.held_piece != null:
		return true
		
	# 2. Check all pieces on board for valid moves
	var grid = get_tree().root.find_child("OyuncuGrid", true, false)
	if not grid: return false
	
	var keyword = "white" if is_white else "black"
	
	for hucre in grid.hucrelerin_sozlugu.values():
		if hucre.mevcut_tas:
			var path = hucre.mevcut_tas.get_meta("scene_path") if hucre.mevcut_tas.has_meta("scene_path") else ""
			if keyword in path.to_lower():
				# immovable pieces (Kings) don't count as "available moves" if they can't move
				if hucre.mevcut_tas.has_meta("is_immovable"):
					continue
					
				var moves = PieceDatabase.get_valid_moves(Vector2i(hucre.sutun, hucre.satir), path)
				if moves.size() > 0:
					return true
					
	return false
func _on_tutorial_completed():
	is_tutorial_mode = false
	save_game()
	start_game()

func save_game():
	var save_data = {
		"is_tutorial_mode": is_tutorial_mode,
		"phase_number": phase_number,
		"piece_stats": PieceDatabase.get_raw_stats()
	}
	SettingsManager.save_game_data(save_data)
	print("[OyunYoneticisi] Game Saved automatically.")
func _spawn_shatter_fx(pos: Vector3, piece_node: Node3D, intensity: float = 1.0, is_king_death: bool = false):
	var fx_scene = load("res://FX/ShatterFX.tscn")
	if fx_scene:
		var fx = fx_scene.instantiate()
		fx.intensity = intensity
		fx.is_king_death = is_king_death
		
		# Detect color from piece
		var piece_color = Color(0.95, 0.95, 0.95) # Default white
		var path = piece_node.get_meta("scene_path").to_lower() if piece_node.has_meta("scene_path") else ""
		if "black" in path: piece_color = Color(0.1, 0.1, 0.1)
		
		fx.piece_color = piece_color
		get_tree().root.add_child(fx)
		fx.global_position = pos

func _enemy_react_to_damage(is_king_hit: bool = false):
	# 1. Sound effects (Pitched down further if King hit)
	var pitch = 2.0 if is_king_hit else 1.0
	SesYoneticisi.play_impact_slam()
	
	# 2. Find character node
	var sitting_node = get_tree().get_first_node_in_group("sitting_node")
	if not sitting_node: return
	
	var skel = sitting_node.find_child("Skeleton3D", true, false)
	if not skel: return
	
	# 3. Play groan ONLY if King hit
	if is_king_hit:
		get_tree().create_timer(0.05).timeout.connect(func():
			SesYoneticisi.play_enemy_groan(skel.global_position)
		)

	# 4. Procedural Torso Slam (Animation override via code/tween)
	if sitting_node.has_meta("slam_tween"):
		var old_tw = sitting_node.get_meta("slam_tween")
		if old_tw.is_valid(): old_tw.kill()
	
	var tw = create_tween()
	sitting_node.set_meta("slam_tween", tw)
	
	var bone_idx = 0 
	var skel_node: Skeleton3D = skel
	var original_pose = skel_node.get_bone_pose_rotation(bone_idx)
	
	# Slam forward (Pitch rotation) - MORE violent for King
	var slam_angle = 35 if is_king_hit else 15
	var slam_rot = original_pose * Quaternion(Vector3(1, 0, 0), deg_to_rad(slam_angle))
	
	tw.set_parallel(true)
	# Fast slam forward
	tw.tween_method(func(q: Quaternion): skel_node.set_bone_pose_rotation(bone_idx, q), original_pose, slam_rot, 0.04).set_trans(Tween.TRANS_EXPO)
	
	# Shake the character node intensely
	var original_pos = sitting_node.position
	var shake_range = 0.05 if is_king_hit else 0.02
	for i in range(12):
		var offset = Vector3(randf_range(-shake_range, shake_range), randf_range(-0.02, 0.02), randf_range(-shake_range, shake_range))
		tw.tween_property(sitting_node, "position", original_pos + offset, 0.02)
	
	# Bounce back
	tw.set_parallel(false)
	var bounce_time = 0.8 if is_king_hit else 0.5
	tw.tween_method(func(q: Quaternion): skel_node.set_bone_pose_rotation(bone_idx, q), slam_rot, original_pose, bounce_time).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(sitting_node, "position", original_pos, 0.1)
func _setup_online_player_roles():
	var role = OnlineManager.assigned_role
	if role == -1:
		# Random role for testing if not in a real lobby
		role = randi() % 4
		OnlineManager.assigned_role = role
		print("[OyunYoneticisi] Testing mode: Randomly assigned to Player ", role + 1)
		
	var players_node = get_tree().root.find_child("Players", true, false)
	if not players_node: return
	
	for i in range(4):
		var p_name = "Player" + str(i + 1)
		var p_node = players_node.get_node_or_null(p_name)
		if p_node:
			var cam = p_node.get_node_or_null("Camera3D")
			if cam:
				if i == role:
					cam.make_current()
					print("[OyunYoneticisi] Camera activated for: ", p_name)
					# Ensure camera script knows its role if needed
					if cam.has_method("set_assigned_role"):
						cam.set_assigned_role(role)
				else:
					cam.clear_current()
					cam.enabled = false # Optional but safer
					# Disable processing for other players' cameras
					cam.set_process(false)
					cam.set_physics_process(false)
					cam.set_process_input(false)
					cam.set_process_unhandled_input(false)
