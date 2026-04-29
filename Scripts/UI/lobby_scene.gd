extends Control

# Node referansları (.tscn'den)
@onready var lobby_list_vbox: VBoxContainer = $MarginContainer/RootVBox/ScrollContainer/LobbyListVBox
@onready var no_rooms_label: Label         = $MarginContainer/RootVBox/NoRoomsLabel
@onready var refresh_btn: Button           = $MarginContainer/RootVBox/BottomBar/RefreshBtn
@onready var create_btn: Button            = $MarginContainer/RootVBox/BottomBar/CreateBtn
@onready var back_btn: Button              = $MarginContainer/RootVBox/BottomBar/BackBtn
@onready var room_code_input: LineEdit     = $MarginContainer/RootVBox/BottomBar/RoomCodeInput

# --- RENKLER ---
const C_BG         = Color("#0f0d0b")
const C_GOLD       = Color("#cca653")
const C_GOLD_DIM   = Color("#5b4a32")
const C_GOLD_FAINT = Color("#2c2114")
const C_ROW_BG     = Color("#151210")
const C_ROW_LINE   = Color("#2a2015")
const C_TEXT_DIM   = Color("#8c7a62")
const C_TEXT_MUTED = Color("#3a3020")

func _ready():
	_apply_button_styles()
	_connect_signals()
	_populate_test_rows()

# ─────────────────────────────────────────────
# STİL - Sadece buton/input stilleri (renkler .tscn'den ayarlanamıyor kolayca)
# ─────────────────────────────────────────────

func _apply_button_styles():
	_style_button(back_btn, false)
	_style_button(refresh_btn, false)
	_style_button(create_btn, true)
	_style_input(room_code_input)

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

func _style_input(input: LineEdit):
	var style = StyleBoxFlat.new()
	style.bg_color = Color("#141210")
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = C_ROW_LINE
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 2
	style.content_margin_left = 8
	style.content_margin_right = 8

	input.add_theme_stylebox_override("normal", style)
	input.add_theme_stylebox_override("focus", style)
	input.add_theme_color_override("font_color", C_GOLD_DIM)
	input.add_theme_color_override("font_placeholder_color", Color("#3a3020"))
	input.add_theme_font_size_override("font_size", 10)

# ─────────────────────────────────────────────
# ODA SATIRI OLUŞTUR
# ─────────────────────────────────────────────

func add_lobby_row(room_name: String, host_name: String, players_str: String, is_locked: bool, lobby_id: int):
	var row_container = MarginContainer.new()

	# Arka plan panel
	var row_bg = Panel.new()
	row_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = C_ROW_BG
	bg_style.border_width_bottom = 1
	bg_style.border_color = C_ROW_LINE
	row_bg.add_theme_stylebox_override("panel", bg_style)
	row_container.add_child(row_bg)

	# İçerik satırı
	var hbox = HBoxContainer.new()
	hbox.custom_minimum_size = Vector2(0, 42)
	hbox.add_theme_constant_override("separation", 0)
	row_container.add_child(hbox)

	# Sol altın çizgi
	var accent = ColorRect.new()
	accent.color = C_GOLD
	accent.custom_minimum_size = Vector2(3, 0)
	hbox.add_child(accent)

	var space1 = Control.new()
	space1.custom_minimum_size = Vector2(8, 0)
	hbox.add_child(space1)

	# Oda ismi
	var name_lbl = Label.new()
	name_lbl.text = room_name
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_lbl.add_theme_color_override("font_color", C_GOLD)
	name_lbl.add_theme_font_size_override("font_size", 13)
	hbox.add_child(name_lbl)

	# Host
	var host_lbl = Label.new()
	host_lbl.text = host_name
	host_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	host_lbl.add_theme_color_override("font_color", C_TEXT_DIM)
	host_lbl.add_theme_font_size_override("font_size", 11)
	hbox.add_child(host_lbl)

	# Oyuncu sayısı rozet
	var p_margin = MarginContainer.new()
	p_margin.custom_minimum_size = Vector2(60, 0)
	p_margin.add_theme_constant_override("margin_left", 4)
	p_margin.add_theme_constant_override("margin_right", 4)
	p_margin.add_theme_constant_override("margin_top", 10)
	p_margin.add_theme_constant_override("margin_bottom", 10)
	hbox.add_child(p_margin)

	var p_panel = Panel.new()
	var p_style = StyleBoxFlat.new()
	p_style.bg_color = Color(0, 0, 0, 0)
	p_style.border_width_left = 1
	p_style.border_width_right = 1
	p_style.border_width_top = 1
	p_style.border_width_bottom = 1
	p_style.border_color = C_GOLD_DIM
	p_style.corner_radius_top_left = 3
	p_style.corner_radius_top_right = 3
	p_style.corner_radius_bottom_left = 3
	p_style.corner_radius_bottom_right = 3
	p_panel.add_theme_stylebox_override("panel", p_style)
	p_margin.add_child(p_panel)

	var p_inner = MarginContainer.new()
	p_inner.add_theme_constant_override("margin_left", 6)
	p_inner.add_theme_constant_override("margin_right", 6)
	p_inner.add_theme_constant_override("margin_top", 2)
	p_inner.add_theme_constant_override("margin_bottom", 2)
	p_panel.add_child(p_inner)

	var p_lbl = Label.new()
	p_lbl.text = players_str
	p_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p_lbl.add_theme_color_override("font_color", C_GOLD)
	p_lbl.add_theme_font_size_override("font_size", 11)
	p_inner.add_child(p_lbl)

	# Kilit
	var lock_lbl = Label.new()
	if is_locked:
		lock_lbl.text = "🔒"
		lock_lbl.add_theme_color_override("font_color", Color("#cca653")) # Altın, görünür
		lock_lbl.add_theme_font_size_override("font_size", 14)
	else:
		lock_lbl.text = "—"
		lock_lbl.add_theme_color_override("font_color", C_TEXT_MUTED)
		lock_lbl.add_theme_font_size_override("font_size", 12)
	lock_lbl.custom_minimum_size = Vector2(46, 0)
	lock_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lock_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(lock_lbl)

	# Tıklanabilir görünmez buton
	var click_btn = Button.new()
	click_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	click_btn.flat = true
	var flat_style = StyleBoxEmpty.new()
	for s in ["normal", "hover", "pressed", "focus"]:
		click_btn.add_theme_stylebox_override(s, flat_style)
	click_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	click_btn.pressed.connect(func(): OnlineManager.join_lobby(lobby_id))
	row_container.add_child(click_btn)

	lobby_list_vbox.add_child(row_container)

# ─────────────────────────────────────────────
# SİNYAL BAĞLANTILARI
# ─────────────────────────────────────────────

func _connect_signals():
	create_btn.pressed.connect(_on_create_pressed)
	refresh_btn.pressed.connect(_on_refresh_pressed)
	back_btn.pressed.connect(_on_back_pressed)
	room_code_input.text_submitted.connect(_on_room_code_submitted)

	OnlineManager.lobby_created.connect(_on_lobby_created)
	OnlineManager.player_joined.connect(_on_player_joined)
	OnlineManager.player_left.connect(_on_player_left)
	OnlineManager.lobby_full.connect(_on_lobby_full)

func _on_create_pressed():
	OnlineManager.create_lobby()

func _on_refresh_pressed():
	if OnlineManager.has_method("refresh_lobby_list"):
		OnlineManager.refresh_lobby_list()

func _on_back_pressed():
	pass

func _on_room_code_submitted(text: String):
	text = text.strip_edges()
	if text.is_valid_int():
		OnlineManager.join_lobby(text.to_int())
		room_code_input.text = ""

func _on_lobby_created(_id):
	create_btn.disabled = true

func _on_player_joined(_steam_id, _index):
	pass

func _on_player_left(_steam_id):
	pass

func _on_lobby_full():
	create_btn.disabled = true
	room_code_input.editable = false

# ─────────────────────────────────────────────
# LOBI LİSTESİ - Dışarıdan çağrılır
# ─────────────────────────────────────────────

func populate_lobby_list(lobbies: Array):
	for child in lobby_list_vbox.get_children():
		child.queue_free()
	no_rooms_label.visible = lobbies.is_empty()
	for lobby in lobbies:
		add_lobby_row(
			lobby.get("name", "Unknown Room"),
			lobby.get("host", ""),
			str(lobby.get("current_players", 0)) + " / " + str(lobby.get("max_players", 4)),
			lobby.get("locked", false),
			lobby.get("id", 0)
		)

# Test satırları (Steam olmadan görmek için)
func _populate_test_rows():
	add_lobby_row("The Hollow Keep",   "Morwen", "3 / 4", true,  1)
	add_lobby_row("Crypt of Echoes",   "Dravek", "1 / 4", false, 2)
	add_lobby_row("Bone Chamber",      "Vyreth", "2 / 4", false, 3)
	add_lobby_row("Iron Sepulchre",    "Aldric", "1 / 4", true,  4)
	add_lobby_row("The Drowning Vault","Seraph", "4 / 4", false, 5)
	add_lobby_row("Ashgate Prison",    "Korryn", "2 / 4", false, 6)
	no_rooms_label.visible = true
