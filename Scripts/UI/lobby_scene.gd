extends Control

# Tüm node referansları
var lobby_list_vbox: VBoxContainer
var refresh_btn: Button
var create_btn: Button
var back_btn: Button
var room_code_input: LineEdit
var no_rooms_label: Label

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
	_build_ui()
	_connect_signals()
	_populate_test_rows()

func _build_ui():
	# === BACKGROUND ===
	var bg = ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Vignette (koyu kenarlı)
	var vignette = _make_gradient_rect()
	add_child(vignette)

	# === ROOT MARGIN CONTAINER ===
	var root_margin = MarginContainer.new()
	root_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_margin.add_theme_constant_override("margin_left", 24)
	root_margin.add_theme_constant_override("margin_right", 24)
	root_margin.add_theme_constant_override("margin_top", 12)
	root_margin.add_theme_constant_override("margin_bottom", 10)
	add_child(root_margin)

	var root_vbox = VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 0)
	root_margin.add_child(root_vbox)

	# === HEADER ===
	var header = VBoxContainer.new()
	header.add_theme_constant_override("separation", 2)
	root_vbox.add_child(header)

	var title = Label.new()
	title.text = "INTERRED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", C_GOLD)
	title.add_theme_font_size_override("font_size", 32)
	header.add_child(title)

	var arrow = Label.new()
	arrow.text = "▼"
	arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	arrow.add_theme_color_override("font_color", C_GOLD_DIM)
	arrow.add_theme_font_size_override("font_size", 10)
	header.add_child(arrow)

	var subtitle = Label.new()
	subtitle.text = "— OPEN ROOMS —"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", C_GOLD_DIM)
	subtitle.add_theme_font_size_override("font_size", 11)
	header.add_child(subtitle)

	# Ayırıcı
	var sep1 = _make_separator(8)
	root_vbox.add_child(sep1)

	# === TABLO BAŞLIĞI ===
	var table_header = _make_table_row_header()
	root_vbox.add_child(table_header)

	var sep2 = _make_separator(4)
	root_vbox.add_child(sep2)

	# === SCROLL - ODA LİSTESİ ===
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root_vbox.add_child(scroll)

	lobby_list_vbox = VBoxContainer.new()
	lobby_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lobby_list_vbox.add_theme_constant_override("separation", 4)
	scroll.add_child(lobby_list_vbox)

	# "no more rooms found"
	var sep3 = _make_separator(6)
	root_vbox.add_child(sep3)

	no_rooms_label = Label.new()
	no_rooms_label.text = "no more rooms found"
	no_rooms_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	no_rooms_label.add_theme_color_override("font_color", C_TEXT_MUTED)
	no_rooms_label.add_theme_font_size_override("font_size", 10)
	no_rooms_label.visible = false
	root_vbox.add_child(no_rooms_label)

	# === SPACER ===
	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_child(spacer)

	# === ALT BUTON ÇUBUĞU ===
	var bottom_sep = _make_hsep_line()
	root_vbox.add_child(bottom_sep)

	var sep4 = _make_separator(8)
	root_vbox.add_child(sep4)

	var bottom_bar = HBoxContainer.new()
	bottom_bar.add_theme_constant_override("separation", 10)
	root_vbox.add_child(bottom_bar)

	back_btn = _make_button("BACK", 90)
	bottom_bar.add_child(back_btn)

	refresh_btn = _make_button("↻  REFRESH", 120)
	bottom_bar.add_child(refresh_btn)

	# Genişletici
	var fill = Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_bar.add_child(fill)

	room_code_input = LineEdit.new()
	room_code_input.placeholder_text = "ENTER ROOM CODE"
	room_code_input.custom_minimum_size = Vector2(160, 34)
	room_code_input.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_style_input(room_code_input)
	bottom_bar.add_child(room_code_input)

	create_btn = _make_button("CREATE ROOM", 130, true)
	bottom_bar.add_child(create_btn)

	var sep5 = _make_separator(6)
	root_vbox.add_child(sep5)

	# === FOOTER ===
	var footer = Label.new()
	footer.text = "SCREEN 1 — LOBBY BROWSER"
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_color_override("font_color", C_TEXT_MUTED)
	footer.add_theme_font_size_override("font_size", 9)
	root_vbox.add_child(footer)

# ─────────────────────────────────────────────
# YARDIMCI FONKSIYONLAR
# ─────────────────────────────────────────────

func _make_gradient_rect() -> Control:
	# Kenar karartma efekti (simüle)
	var c = ColorRect.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.color = Color(0, 0, 0, 0)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

func _make_separator(height: int) -> Control:
	var s = Control.new()
	s.custom_minimum_size = Vector2(0, height)
	return s

func _make_hsep_line() -> ColorRect:
	var line = ColorRect.new()
	line.color = C_GOLD_FAINT
	line.custom_minimum_size = Vector2(0, 1)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return line

func _make_table_row_header() -> HBoxContainer:
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 0)

	# Sol boşluk (accent bar ile hizalamak için)
	var pad = Control.new()
	pad.custom_minimum_size = Vector2(10, 0)
	hbox.add_child(pad)

	var h_name = _make_header_label("ROOM NAME")
	h_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(h_name)

	var h_host = _make_header_label("HOST")
	h_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(h_host)

	var h_players = _make_header_label("PLAYERS")
	h_players.custom_minimum_size = Vector2(60, 0)
	h_players.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hbox.add_child(h_players)

	var h_lock = _make_header_label("LOCK")
	h_lock.custom_minimum_size = Vector2(40, 0)
	h_lock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hbox.add_child(h_lock)

	return hbox

func _make_header_label(text: String) -> Label:
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", C_GOLD_DIM)
	lbl.add_theme_font_size_override("font_size", 10)
	return lbl

func _make_button(text: String, min_width: int = 100, gold_border: bool = false) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(min_width, 34)
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER

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
	return btn

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

func add_lobby_row(room_name: String, sub_text: String, host_name: String, players_str: String, is_locked: bool, lobby_id: int):
	var row_container = MarginContainer.new()
	row_container.add_theme_constant_override("margin_left", 0)
	row_container.add_theme_constant_override("margin_right", 0)
	row_container.add_theme_constant_override("margin_top", 0)
	row_container.add_theme_constant_override("margin_bottom", 0)

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

	# Oda isim + sub text
	var room_vbox = VBoxContainer.new()
	room_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	room_vbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	room_vbox.add_theme_constant_override("separation", 1)
	hbox.add_child(room_vbox)

	var name_lbl = Label.new()
	name_lbl.text = room_name
	name_lbl.add_theme_color_override("font_color", C_GOLD)
	name_lbl.add_theme_font_size_override("font_size", 13)
	room_vbox.add_child(name_lbl)

	var sub_lbl = Label.new()
	sub_lbl.text = sub_text
	sub_lbl.add_theme_color_override("font_color", C_GOLD_DIM)
	sub_lbl.add_theme_font_size_override("font_size", 9)
	room_vbox.add_child(sub_lbl)

	# Host
	var host_lbl = Label.new()
	host_lbl.text = host_name
	host_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	host_lbl.add_theme_color_override("font_color", C_TEXT_DIM)
	host_lbl.add_theme_font_size_override("font_size", 11)
	hbox.add_child(host_lbl)

	# Oyuncu sayısı (çerçeveli rozet)
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
	lock_lbl.text = "🔒" if is_locked else "—"
	lock_lbl.custom_minimum_size = Vector2(40, 0)
	lock_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lock_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lock_lbl.add_theme_color_override("font_color", C_GOLD_DIM)
	lock_lbl.add_theme_font_size_override("font_size", 11)
	hbox.add_child(lock_lbl)

	var space2 = Control.new()
	space2.custom_minimum_size = Vector2(6, 0)
	hbox.add_child(space2)

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

func populate_lobby_list(lobbies: Array):
	for child in lobby_list_vbox.get_children():
		child.queue_free()
	no_rooms_label.visible = lobbies.is_empty()
	for lobby in lobbies:
		add_lobby_row(
			lobby.get("name", "Unknown Room"),
			lobby.get("mode", ""),
			lobby.get("host", ""),
			str(lobby.get("current_players", 0)) + " / " + str(lobby.get("max_players", 4)),
			lobby.get("locked", false),
			lobby.get("id", 0)
		)

# Test: Görsel referans için örnek satırlar
func _populate_test_rows():
	add_lobby_row("The Hollow Keep",  "dungeon · swords only", "Morwen", "3 / 4", true,  1)
	add_lobby_row("Crypt of Echoes",  "classic · all pieces",  "Dravek", "1 / 4", false, 2)
	add_lobby_row("Bone Chamber",     "classic · all pieces",  "Vyreth", "2 / 4", false, 3)
	no_rooms_label.visible = true
