extends Control

@onready var lobby_list = $HBoxContainer/LeftPanel/LobbyScroll/LobbyList
@onready var refresh_btn = $HBoxContainer/LeftPanel/RefreshBtn

@onready var party_slots = [
	$HBoxContainer/RightPanel/Slots/Slot1,
	$HBoxContainer/RightPanel/Slots/Slot2,
	$HBoxContainer/RightPanel/Slots/Slot3,
	$HBoxContainer/RightPanel/Slots/Slot4
]

@onready var create_btn = $BottomBar/HBoxContainer/CreateBtn
@onready var join_btn = $BottomBar/HBoxContainer/JoinBtn
@onready var back_btn = $BottomBar/BackBtn

@onready var join_popup = $JoinPopup
@onready var lobby_id_input = $JoinPopup/VBoxContainer/LobbyIdInput
@onready var confirm_join_btn = $JoinPopup/VBoxContainer/ConfirmJoinBtn

@onready var prepare_label = $PrepareLabel
@onready var profile_name = $TopRight/HBoxContainer/ProfileName

func _ready():
	_apply_dark_fantasy_theme()
	_connect_signals()
	
	if OnlineManager.is_online:
		var persona_name = Steam.getFriendPersonaName(OnlineManager.my_steam_id)
		if persona_name:
			profile_name.text = persona_name
	
	_refresh_party_slots()

func _apply_dark_fantasy_theme():
	# --- Background (Dark Stone) ---
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.08, 0.07, 0.07, 1.0)
	bg_style.border_width_bottom = 2
	bg_style.border_width_top = 2
	bg_style.border_width_left = 2
	bg_style.border_width_right = 2
	bg_style.border_color = Color(0.15, 0.12, 0.10, 1.0)
	$Background.add_theme_stylebox_override("panel", bg_style)
	
	# --- Title (Worn Gold) ---
	var title_settings = LabelSettings.new()
	title_settings.font_size = 54
	title_settings.font_color = Color(0.7, 0.55, 0.25, 1.0) # Worn gold
	title_settings.shadow_color = Color(0, 0, 0, 1)
	title_settings.shadow_size = 4
	title_settings.shadow_offset = Vector2(2, 2)
	$Title.label_settings = title_settings
	
	# --- Button Style (Iron & Wood) ---
	var btn_normal = StyleBoxFlat.new()
	btn_normal.bg_color = Color(0.15, 0.13, 0.12, 1.0) # Dark wood
	btn_normal.border_width_all = 2
	btn_normal.border_color = Color(0.25, 0.25, 0.25, 1.0) # Iron trim
	btn_normal.corner_radius_top_left = 2
	btn_normal.corner_radius_top_right = 2
	btn_normal.corner_radius_bottom_left = 2
	btn_normal.corner_radius_bottom_right = 2
	
	var btn_hover = btn_normal.duplicate()
	btn_hover.bg_color = Color(0.2, 0.15, 0.1, 1.0) # Slightly warmer on hover
	btn_hover.border_color = Color(0.6, 0.45, 0.2, 1.0) # Gold trim on hover
	
	var btn_pressed = btn_normal.duplicate()
	btn_pressed.bg_color = Color(0.05, 0.05, 0.05, 1.0)
	
	for btn in [create_btn, join_btn, refresh_btn, back_btn, confirm_join_btn]:
		btn.add_theme_stylebox_override("normal", btn_normal)
		btn.add_theme_stylebox_override("hover", btn_hover)
		btn.add_theme_stylebox_override("pressed", btn_pressed)
		btn.add_theme_color_override("font_color", Color(0.8, 0.75, 0.7, 1.0))
	
	# --- Slot Style (Iron-framed portrait) ---
	var slot_style = StyleBoxFlat.new()
	slot_style.bg_color = Color(0.05, 0.04, 0.04, 1.0)
	slot_style.border_width_all = 3
	slot_style.border_color = Color(0.15, 0.15, 0.15, 1.0) # Heavy iron
	slot_style.shadow_color = Color(0, 0, 0, 0.8)
	slot_style.shadow_size = 5
	
	for slot in party_slots:
		slot.add_theme_stylebox_override("panel", slot_style)
		slot.modulate = Color(0.4, 0.4, 0.4, 1.0) # Dim when empty
		var label = slot.get_node("NameLabel")
		label.add_theme_color_override("font_color", Color(0.5, 0.4, 0.3, 1.0))

func _connect_signals():
	create_btn.pressed.connect(_on_create_pressed)
	join_btn.pressed.connect(_on_join_pressed)
	refresh_btn.pressed.connect(_on_refresh_pressed)
	back_btn.pressed.connect(_on_back_pressed)
	confirm_join_btn.pressed.connect(_on_confirm_join_pressed)
	
	# OnlineManager Sinyalleri
	OnlineManager.lobby_created.connect(_on_lobby_created)
	OnlineManager.player_joined.connect(_on_player_joined)
	OnlineManager.player_left.connect(_on_player_left)
	OnlineManager.lobby_full.connect(_on_lobby_full)

func _on_create_pressed():
	OnlineManager.create_lobby()

func _on_join_pressed():
	join_popup.popup_centered()

func _on_confirm_join_pressed():
	var id_text = lobby_id_input.text.strip_edges()
	if id_text.is_valid_int():
		var id = id_text.to_int()
		OnlineManager.join_lobby(id)
		join_popup.hide()

func _on_refresh_pressed():
	# If we add refresh logic to OnlineManager later
	if OnlineManager.has_method("refresh_lobby_list"):
		OnlineManager.refresh_lobby_list()
	else:
		print("Refresh lobby functionality not yet implemented in OnlineManager.")

func _on_back_pressed():
	# TODO: Go back to main menu
	pass

func _on_lobby_created(id):
	create_btn.disabled = true
	join_btn.disabled = true
	_refresh_party_slots()

func _on_player_joined(steam_id, index):
	_refresh_party_slots()

func _on_player_left(steam_id):
	_refresh_party_slots()

func _on_lobby_full():
	create_btn.disabled = true
	join_btn.disabled = true
	prepare_label.visible = true

func _refresh_party_slots():
	# Reset all slots to empty state
	for i in range(party_slots.size()):
		var slot = party_slots[i]
		var name_label = slot.get_node("NameLabel")
		name_label.text = "Empty Slot"
		name_label.add_theme_color_override("font_color", Color(0.4, 0.3, 0.2, 1.0))
		slot.modulate = Color(0.4, 0.4, 0.4, 1.0) # Dim, dark silhouette
	
	# Fill slots based on OnlineManager.players
	for steam_id in OnlineManager.players.keys():
		var idx = OnlineManager.players[steam_id]
		if idx < party_slots.size():
			var slot = party_slots[idx]
			var name_label = slot.get_node("NameLabel")
			var persona_name = Steam.getFriendPersonaName(steam_id)
			name_label.text = persona_name if persona_name else str(steam_id)
			
			# Highlight filled slots (candlelight orange glow)
			name_label.add_theme_color_override("font_color", Color(0.9, 0.6, 0.2, 1.0))
			slot.modulate = Color(1.0, 1.0, 1.0, 1.0)

# Eklenecek lobi listesini güncelleme fonksiyonu
func populate_lobby_list(lobbies: Array):
	for child in lobby_list.get_children():
		child.queue_free()
		
	for lobby in lobbies:
		var btn = Button.new()
		btn.text = lobby.name + " (" + str(lobby.current_players) + "/" + str(lobby.max_players) + ")"
		btn.custom_minimum_size = Vector2(0, 40)
		btn.pressed.connect(func(): OnlineManager.join_lobby(lobby.id))
		
		# Apply basic style to list items
		var btn_style = StyleBoxFlat.new()
		btn_style.bg_color = Color(0.1, 0.08, 0.08, 1.0)
		btn_style.border_width_bottom = 1
		btn_style.border_color = Color(0.2, 0.15, 0.1, 1.0)
		btn.add_theme_stylebox_override("normal", btn_style)
		
		lobby_list.add_child(btn)
