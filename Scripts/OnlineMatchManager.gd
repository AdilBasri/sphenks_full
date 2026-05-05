extends Node

var current_turn_index: int = 0
var is_game_active: bool = false
var _names_initialized: bool = false

func _ready():
	add_to_group("online_match_manager")
	print("[OnlineMatchManager] Initializing...")
	
	# Ensure stats are clean for online
	PieceDatabase.reset_database_for_online()
	
	# Setup role for testing if needed
	if OnlineManager.assigned_role == -1:
		OnlineManager.assigned_role = randi() % 4
		print("[OnlineMatchManager] F6 Test: Assigned Role Player ", OnlineManager.assigned_role + 1)
		
		# Populate players for testing names if empty
		if OnlineManager.players.is_empty():
			for i in range(4):
				OnlineManager.players[i] = i
				if i != OnlineManager.assigned_role:
					OnlineManager.bot_names[i] = "Test Bot " + str(i + 1)
	
	# Important: Wait a frame for the scene tree to fully settle
	await get_tree().process_frame
	_setup_cameras()
	_setup_player_names()
	
	# Start the game
	is_game_active = true

func _process(_delta):
	# Retry name setup if players join late or if it failed initially
	if not _names_initialized and is_game_active:
		if not OnlineManager.players.is_empty():
			_setup_player_names()

func _setup_cameras():
	var role = OnlineManager.assigned_role
	var players_node = get_tree().root.find_child("Players", true, false)
	
	if not players_node:
		print("[OnlineMatchManager] CRITICAL ERROR: 'Players' node not found!")
		return
		
	print("[OnlineMatchManager] Role detected: ", role, " (Player ", role + 1, ")")
	
	# 1. First, find ALL cameras in the scene and disable them
	var all_cameras = get_tree().root.find_children("*", "Camera3D", true, false)
	for cam in all_cameras:
		cam.current = false
	
	# 2. Activate our specific player camera
	var p_name = "Player" + str(role + 1)
	var p_node = players_node.get_node_or_null(p_name)
	if p_node:
		var cam = p_node.get_node_or_null("Camera3D")
		if cam:
			cam.make_current()
			cam.current = true 
			print("[OnlineMatchManager] SUCCESS: Activated camera at ", cam.get_path())
			
			# Initialize mouse mode for the match
			Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN
			
			if cam.has_method("set_assigned_role"):
				cam.set_assigned_role(role)
		else:
			print("[OnlineMatchManager] ERROR: Camera3D missing under ", p_name)
	else:
		print("[OnlineMatchManager] ERROR: Player node ", p_name, " not found!")

	# 3. Handle other players
	for i in range(4):
		if i == role: continue
		var other_p = players_node.get_node_or_null("Player" + str(i + 1))
		if other_p:
			var other_cam = other_p.get_node_or_null("Camera3D")
			if other_cam:
				other_cam.current = false
				other_cam.set_process(false)
				other_cam.set_physics_process(false)
				var inspect_ui = other_cam.get_node_or_null("InspectUI")
				if inspect_ui: inspect_ui.visible = false

func _setup_player_names():
	var role = OnlineManager.assigned_role
	var players_node = get_tree().root.find_child("Players", true, false)
	if not players_node: return

	var player_keys = OnlineManager.players.keys()
	if player_keys.is_empty(): return
	
	print("[OnlineMatchManager] Setting up player names for ", player_keys.size(), " players...")
	for steam_id in player_keys:
		var idx = OnlineManager.players[steam_id]
		var p_name = "Player" + str(idx + 1)
		var p_node = players_node.get_node_or_null(p_name)
		
		if p_node:
			var display_name = OnlineManager.get_player_display_name(steam_id)
			var bone_attachment = p_node.get_node_or_null("Sitting/Skeleton3D/BoneAttachment3D")
			
			if bone_attachment:
				# Remove old label if exists
				var old_label = bone_attachment.get_node_or_null("NameLabel")
				if old_label: old_label.queue_free()
				
				var label = Label3D.new()
				label.name = "NameLabel"
				label.text = display_name
				label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				label.font_size = 42
				label.outline_size = 12
				label.outline_modulate = Color.BLACK
				label.position = Vector3(0, 0.4, 0)
				label.modulate = Color(1.0, 0.9, 0.7)
				label.render_priority = 10
				label.set_meta("skip_shader", true)
				
				bone_attachment.add_child(label)
				
				# CRITICAL FIX: Hide the label from our own perspective
				if steam_id == OnlineManager.my_steam_id or idx == role:
					label.visible = false
					label.queue_free() # Completely remove it for the local player
			
	_names_initialized = true
