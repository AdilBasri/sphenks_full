extends Control

# --- RENKLER ---
const C_GOLD       = Color("#cca653")
const C_GOLD_DIM   = Color("#5b4a32")
const C_ROW_BG     = Color("#151210")
const C_ROW_LINE   = Color("#2a2015")
const C_TEXT_DIM   = Color("#8c7a62")
const C_TEXT_MUTED = Color("#3a3020")
const C_READY      = Color("#2a5a26")
const C_NOT_READY  = Color("#5a2a2a")
const C_EMPTY_BG   = Color("#0e0c0a")

# --- NODE REFERANSLARI ---
@onready var room_name_label: Label      = $MarginContainer/RootVBox/Header/RoomNameLabel
@onready var player_grid: GridContainer  = $MarginContainer/RootVBox/PlayerGrid
@onready var room_code_value: Label      = $MarginContainer/RootVBox/RoomCodeSection/RoomCodeValue
@onready var waiting_label: Label        = $MarginContainer/RootVBox/WaitingLabel
@onready var leave_btn: Button           = $MarginContainer/RootVBox/BottomBar/LeaveBtn
@onready var ready_btn: Button           = $MarginContainer/RootVBox/BottomBar/ReadyBtn
@onready var start_btn: Button           = $MarginContainer/RootVBox/BottomBar/StartBtn

var slot_panels: Array = []
var is_ready_local: bool = false

func _ready():
	_apply_styles()
	_connect_signals()
	_init_room()
	
	if SesYoneticisi.has_method("start_menu_music"):
		SesYoneticisi.start_menu_music()

# ─────────────────────────────────────────────
# BAŞLAT
# ─────────────────────────────────────────────

func _init_room():
	# Oda adı
	var rn = OnlineManager.room_name if OnlineManager.room_name != "" else "The Room"
	room_name_label.text = "— " + rn.to_upper() + " —"

	# Oda kodu
	room_code_value.text = OnlineManager.room_code if OnlineManager.room_code != "" else "------"

	# Slot referanslarını topla
	slot_panels = [
		player_grid.get_node("Slot0"),
		player_grid.get_node("Slot1"),
		player_grid.get_node("Slot2"),
		player_grid.get_node("Slot3"),
	]

	# Tüm slotları boş göster
	for i in range(4):
		_set_slot_empty(i)

	# Mevcut oyuncuları doldur
	for steam_id in OnlineManager.players.keys():
		var idx = OnlineManager.players[steam_id]
		var is_rdy = OnlineManager.player_ready.get(steam_id, false)
		_set_slot_filled(idx, steam_id, is_rdy)

	# Host değilse start butonu görünmesin
	start_btn.visible = OnlineManager.is_host

	_update_waiting_label()
	_update_start_btn()

# ─────────────────────────────────────────────
# SLOT — BOŞ
# ─────────────────────────────────────────────

func _set_slot_empty(idx: int):
	if idx >= slot_panels.size(): return
	var panel = slot_panels[idx]
	_clear_slot(panel)

	var style = StyleBoxFlat.new()
	style.bg_color = C_EMPTY_BG
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = Color("#1a1510")
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	panel.add_theme_stylebox_override("panel", style)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	margin.add_child(vbox)

	var dots = Label.new()
	dots.text = "○ ○ ○ ○"
	dots.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dots.add_theme_color_override("font_color", Color("#2a2015"))
	dots.add_theme_font_size_override("font_size", 12)
	vbox.add_child(dots)

	var awaiting = Label.new()
	awaiting.text = "awaiting soul..."
	awaiting.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	awaiting.add_theme_color_override("font_color", Color("#2a2015"))
	awaiting.add_theme_font_size_override("font_size", 9)
	vbox.add_child(awaiting)

# ─────────────────────────────────────────────
# SLOT — DOLU
# ─────────────────────────────────────────────

func _set_slot_filled(idx: int, steam_id: int, is_rdy: bool):
	if idx >= slot_panels.size(): return
	var panel = slot_panels[idx]
	_clear_slot(panel)

	var style = StyleBoxFlat.new()
	style.bg_color = Color("#1a1814") if is_rdy else C_ROW_BG
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = C_GOLD_DIM if is_rdy else C_ROW_LINE
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	panel.add_theme_stylebox_override("panel", style)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	panel.add_child(margin)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	hbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	margin.add_child(hbox)

	# Avatar daire
	var avatar_panel = Panel.new()
	avatar_panel.custom_minimum_size = Vector2(38, 38)
	var avatar_style = StyleBoxFlat.new()
	avatar_style.bg_color = _steam_id_to_color(steam_id)
	avatar_style.corner_radius_top_left = 19
	avatar_style.corner_radius_top_right = 19
	avatar_style.corner_radius_bottom_left = 19
	avatar_style.corner_radius_bottom_right = 19
	avatar_panel.add_theme_stylebox_override("panel", avatar_style)
	hbox.add_child(avatar_panel)

	var initial_label = Label.new()
	initial_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	var display_name = OnlineManager.get_player_display_name(steam_id)
	initial_label.text = display_name.substr(0, 1).to_upper()
	initial_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	initial_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	initial_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	initial_label.add_theme_font_size_override("font_size", 15)
	avatar_panel.add_child(initial_label)

	# Bilgi sütunu
	var info_vbox = VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_vbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info_vbox.add_theme_constant_override("separation", 2)
	hbox.add_child(info_vbox)

	var name_lbl = Label.new()
	name_lbl.text = display_name
	name_lbl.add_theme_color_override("font_color", C_GOLD)
	name_lbl.add_theme_font_size_override("font_size", 11)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	info_vbox.add_child(name_lbl)

	# Player index 0 = Host
	var role_lbl = Label.new()
	var player_index = OnlineManager.players.get(steam_id, -1)
	role_lbl.text = "Host" if player_index == 0 else "Joined"
	role_lbl.add_theme_color_override("font_color", C_TEXT_DIM)
	role_lbl.add_theme_font_size_override("font_size", 9)
	info_vbox.add_child(role_lbl)

	# Hazır rozeti
	var badge_margin = MarginContainer.new()
	badge_margin.add_theme_constant_override("margin_top", 2)
	info_vbox.add_child(badge_margin)

	var badge_panel = Panel.new()
	var badge_style = StyleBoxFlat.new()
	if is_rdy:
		badge_style.bg_color = Color("#1e5a1a")  # Koyu yeşil
		badge_style.border_color = Color("#3a9a34")
	else:
		badge_style.bg_color = Color("#3a1a1a")  # Koyu kırmızı
		badge_style.border_color = Color("#7a3030")
	badge_style.border_width_left = 1
	badge_style.border_width_right = 1
	badge_style.border_width_top = 1
	badge_style.border_width_bottom = 1
	badge_style.corner_radius_top_left = 2
	badge_style.corner_radius_top_right = 2
	badge_style.corner_radius_bottom_left = 2
	badge_style.corner_radius_bottom_right = 2
	badge_style.content_margin_left = 5
	badge_style.content_margin_right = 5
	badge_style.content_margin_top = 1
	badge_style.content_margin_bottom = 1
	badge_panel.add_theme_stylebox_override("panel", badge_style)
	badge_margin.add_child(badge_panel)

	var badge_lbl = Label.new()
	badge_lbl.text = "READY" if is_rdy else "NOT READY"
	badge_lbl.add_theme_color_override("font_color", Color("#7dcc78") if is_rdy else Color("#cc7878"))
	badge_lbl.add_theme_font_size_override("font_size", 8)
	badge_panel.add_child(badge_lbl)

func _clear_slot(panel: Panel):
	for child in panel.get_children():
		child.queue_free()

func _steam_id_to_color(steam_id: int) -> Color:
	var colors = [
		Color("#4a3a7a"), Color("#3a5a4a"), Color("#5a3a3a"),
		Color("#3a4a5a"), Color("#5a4a2a"), Color("#2a4a5a"),
	]
	return colors[steam_id % colors.size()]

# ─────────────────────────────────────────────
# DURUM GÜNCELLEME
# ─────────────────────────────────────────────

func _update_waiting_label():
	var count = OnlineManager.players.size()
	waiting_label.text = "Waiting for players...  %d / %d" % [count, OnlineManager.max_players]

func _update_start_btn():
	if not OnlineManager.is_host:
		start_btn.visible = false
		return
	start_btn.visible = true
	start_btn.disabled = not OnlineManager.are_all_ready()

# ─────────────────────────────────────────────
# SİNYALLER
# ─────────────────────────────────────────────

func _connect_signals():
	leave_btn.pressed.connect(_on_leave_pressed)
	ready_btn.pressed.connect(_on_ready_pressed)
	start_btn.pressed.connect(_on_start_pressed)

	OnlineManager.player_joined.connect(_on_player_joined)
	OnlineManager.player_left.connect(_on_player_left)
	OnlineManager.player_ready_changed.connect(_on_player_ready_changed)
	OnlineManager.game_started.connect(_on_game_started)

func _on_leave_pressed():
	OnlineManager.leave_lobby()
	(Engine.get_main_loop() as SceneTree).change_scene_to_file("res://Scenes/UI/lobby_scene.tscn")

func _on_ready_pressed():
	is_ready_local = not is_ready_local
	OnlineManager.set_ready(is_ready_local)
	ready_btn.text = "CANCEL READY" if is_ready_local else "READY UP"

func _on_start_pressed():
	OnlineManager.start_game()

func _on_player_joined(steam_id: int, player_index: int):
	_init_room()

func _on_player_left(steam_id: int):
	_init_room()

func _on_player_ready_changed(steam_id: int, p_is_ready: bool):
	_init_room()


func _on_game_started():
	print("Oyun Başlıyor!")
	# get_tree().change_scene_to_file("res://Scenes/Game/game.tscn")

# ─────────────────────────────────────────────
# STİLLER
# ─────────────────────────────────────────────

func _apply_styles():
	_style_button(leave_btn, false)
	_style_button(ready_btn, false)
	_style_button(start_btn, true)

func _style_button(btn: Button, gold_border: bool):
	var normal = StyleBoxFlat.new()
	normal.bg_color = Color("#141210")
	normal.border_width_left = 1
	normal.border_width_right = 1
	normal.border_width_top = 1
	normal.border_width_bottom = 1
	normal.border_color = C_GOLD_DIM if gold_border else C_ROW_LINE
	normal.corner_radius_top_left = 2
	normal.corner_radius_top_right = 2
	normal.corner_radius_bottom_left = 2
	normal.corner_radius_bottom_right = 2

	var hover = normal.duplicate()
	hover.bg_color = Color("#1e1a12")
	hover.border_color = C_GOLD

	var pressed = normal.duplicate()
	pressed.bg_color = Color("#0a0807")

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", normal.duplicate())
	btn.add_theme_color_override("font_color", C_GOLD if gold_border else C_TEXT_DIM)
	btn.add_theme_font_size_override("font_size", 11)
