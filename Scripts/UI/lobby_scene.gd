extends Control

# Node referansları (.tscn'den)
@onready var lobby_list_vbox: VBoxContainer = $MarginContainer/RootVBox/ScrollContainer/LobbyListVBox
@onready var refresh_btn: Button           = $MarginContainer/RootVBox/BottomBar/RefreshBtn
@onready var create_btn: Button            = $MarginContainer/RootVBox/BottomBar/CreateBtn
@onready var back_btn: Button              = $MarginContainer/RootVBox/BottomBar/BackBtn
@onready var join_by_code_btn: Button      = $MarginContainer/RootVBox/BottomBar/JoinByCodeBtn

# Popup
@onready var popup_overlay: ColorRect      = $PopupOverlay
@onready var create_popup: Panel           = $CreateRoomPopup
@onready var room_name_input: LineEdit     = $CreateRoomPopup/MarginContainer/VBox/RoomNameInput
@onready var room_password_input: LineEdit = $CreateRoomPopup/MarginContainer/VBox/RoomPasswordInput
@onready var popup_cancel: Button          = $CreateRoomPopup/MarginContainer/VBox/Buttons/CancelBtn
@onready var popup_confirm: Button         = $CreateRoomPopup/MarginContainer/VBox/Buttons/ConfirmBtn

# Join Password Popup
@onready var join_password_popup: Panel     = $JoinPasswordPopup
@onready var join_password_input: LineEdit  = $JoinPasswordPopup/MarginContainer/VBox/JoinPasswordInput
@onready var join_password_cancel: Button   = $JoinPasswordPopup/MarginContainer/VBox/Buttons/CancelBtn
@onready var join_password_confirm: Button  = $JoinPasswordPopup/MarginContainer/VBox/Buttons/ConfirmBtn

# Join By Code Popup
@onready var join_by_code_popup: Panel     = $JoinByCodePopup
@onready var code_popup_input: LineEdit     = $JoinByCodePopup/MarginContainer/VBox/CodeInput
@onready var code_popup_cancel: Button     = $JoinByCodePopup/MarginContainer/VBox/Buttons/CancelBtn
@onready var code_popup_confirm: Button    = $JoinByCodePopup/MarginContainer/VBox/Buttons/ConfirmBtn

var temp_joining_lobby_id: int = 0
var temp_joining_lobby_pwd: String = ""



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
	
	if SesYoneticisi.has_method("start_menu_music"):
		SesYoneticisi.start_menu_music()

	# Gerçek lobileri anında çek
	if OnlineManager.is_online:
		OnlineManager.refresh_lobby_list()


# ─────────────────────────────────────────────
# STİL - Sadece buton/input stilleri (renkler .tscn'den ayarlanamıyor kolayca)
# ─────────────────────────────────────────────

func _apply_button_styles():
	_style_button(back_btn, false)
	_style_button(refresh_btn, false)
	_style_button(create_btn, true)
	_style_button(join_by_code_btn, false)
	_style_popup()


func _style_popup():
	# Popup Panel arka planı
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color("#0f0d0b")
	panel_style.border_width_left = 1
	panel_style.border_width_right = 1
	panel_style.border_width_top = 1
	panel_style.border_width_bottom = 1
	panel_style.border_color = Color("#5b4a32")
	panel_style.corner_radius_top_left = 4
	panel_style.corner_radius_top_right = 4
	panel_style.corner_radius_bottom_left = 4
	panel_style.corner_radius_bottom_right = 4
	create_popup.add_theme_stylebox_override("panel", panel_style)
	join_password_popup.add_theme_stylebox_override("panel", panel_style)
	join_by_code_popup.add_theme_stylebox_override("panel", panel_style)

	_style_input(room_name_input)
	_style_input(room_password_input)
	_style_input(join_password_input)
	_style_input(code_popup_input)
	
	_style_button(popup_cancel, false)
	_style_button(popup_confirm, true)
	_style_button(join_password_cancel, false)
	_style_button(join_password_confirm, true)
	_style_button(code_popup_cancel, false)
	_style_button(code_popup_confirm, true)


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

	var disabled_style = normal.duplicate()
	disabled_style.bg_color = Color("#0a0908")
	disabled_style.border_color = Color("#2d2418")
	btn.add_theme_stylebox_override("disabled", disabled_style)

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

	# Ping
	var ping_lbl = Label.new()
	var ping_val = (lobby_id % 60) + 35 + (randi() % 15)
	ping_lbl.text = str(ping_val) + " ms"
	ping_lbl.custom_minimum_size = Vector2(60, 0)
	ping_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ping_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	
	if ping_val < 60:
		ping_lbl.add_theme_color_override("font_color", Color("#5dbb63")) # Canlı Yeşil
	elif ping_val < 100:
		ping_lbl.add_theme_color_override("font_color", Color("#e5c158")) # Canlı Sarı
	else:
		ping_lbl.add_theme_color_override("font_color", Color("#d9534f")) # Canlı Kırmızı
		
	ping_lbl.add_theme_font_size_override("font_size", 11)
	hbox.add_child(ping_lbl)

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
	# Hover efekti
	click_btn.mouse_entered.connect(func():
		bg_style.bg_color = Color("#201c16")
		bg_style.border_color = C_GOLD_DIM
	)
	click_btn.mouse_exited.connect(func():
		bg_style.bg_color = C_ROW_BG
		bg_style.border_color = C_ROW_LINE
	)
	click_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	click_btn.pressed.connect(func(): 
		if is_locked:
			_on_password_required(lobby_id if lobby_id > 0 else 999999, "1234")
		else:
			if lobby_id > 0 and lobby_id != 999999:
				OnlineManager.join_lobby(lobby_id)
			else:
				(Engine.get_main_loop() as SceneTree).change_scene_to_file("res://Scenes/UI/room_scene.tscn")
	)
	row_container.add_child(click_btn)

	lobby_list_vbox.add_child(row_container)

# ─────────────────────────────────────────────
# SİNYAL BAĞLANTILARI
# ─────────────────────────────────────────────

func _connect_signals():
	create_btn.pressed.connect(_on_create_pressed)
	refresh_btn.pressed.connect(_on_refresh_pressed)
	back_btn.pressed.connect(_on_back_pressed)
	join_by_code_btn.pressed.connect(_on_enter_code_pressed)

	OnlineManager.lobby_created.connect(_on_lobby_created)
	OnlineManager.player_joined.connect(_on_player_joined)
	OnlineManager.player_left.connect(_on_player_left)
	OnlineManager.lobby_full.connect(_on_lobby_full)
	OnlineManager.entered_room.connect(_on_entered_room)
	
	if OnlineManager.has_signal("password_required"):
		OnlineManager.password_required.connect(_on_password_required)
	if OnlineManager.has_signal("lobby_list_updated"):
		OnlineManager.lobby_list_updated.connect(populate_lobby_list)

	# Popup sinyalleri
	popup_cancel.pressed.connect(_on_popup_cancel)
	popup_confirm.pressed.connect(_on_popup_confirm)
	room_name_input.text_submitted.connect(func(_t): _on_popup_confirm())
	room_password_input.text_submitted.connect(func(_t): _on_popup_confirm())
	
	join_password_cancel.pressed.connect(_on_join_password_cancel)
	join_password_confirm.pressed.connect(_on_join_password_confirm)
	join_password_input.text_submitted.connect(func(_t): _on_join_password_confirm())
	
	code_popup_cancel.pressed.connect(_on_code_popup_cancel)
	code_popup_confirm.pressed.connect(_on_code_popup_confirm)
	code_popup_input.text_submitted.connect(func(_t): _on_code_popup_confirm())

	
	popup_overlay.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed:
			_close_popup()
	)


func _on_create_pressed():
	_show_create_popup()

func _show_create_popup():
	room_name_input.text = ""
	popup_overlay.visible = true
	create_popup.visible = true
	room_name_input.call_deferred("grab_focus")

func _close_popup():
	popup_overlay.visible = false
	create_popup.visible = false
	join_by_code_popup.visible = false
	join_password_popup.visible = false
	room_name_input.text = ""
	code_popup_input.text = ""

func _on_popup_cancel():
	_close_popup()


func _on_enter_code_pressed():
	code_popup_input.text = ""
	popup_overlay.visible = true
	join_by_code_popup.visible = true
	code_popup_input.call_deferred("grab_focus")

func _on_code_popup_cancel():
	_close_popup()

func _on_code_popup_confirm():
	var code = code_popup_input.text.strip_edges()
	if code.length() == 6:
		_close_popup()
		OnlineManager.join_by_code(code)
	elif code.is_valid_int():
		_close_popup()
		OnlineManager.join_lobby(code.to_int())


func _on_popup_confirm():
	var name = room_name_input.text.strip_edges()
	var pwd = room_password_input.text.strip_edges()
	if name == "":
		name = "My Room"
	_close_popup()
	room_password_input.text = ""
	OnlineManager.create_lobby(name, pwd)

func _on_password_required(target_id: int, correct_password: String):
	temp_joining_lobby_id = target_id
	temp_joining_lobby_pwd = correct_password
	_show_join_password_popup()

func _show_join_password_popup():
	join_password_input.text = ""
	popup_overlay.visible = true
	join_password_popup.visible = true
	join_password_input.call_deferred("grab_focus")

func _close_join_popup():
	popup_overlay.visible = false
	join_password_popup.visible = false
	join_password_input.text = ""

func _on_join_password_cancel():
	_close_join_popup()
	temp_joining_lobby_id = 0
	temp_joining_lobby_pwd = ""

func _on_join_password_confirm():
	var entered = join_password_input.text.strip_edges()
	if entered == temp_joining_lobby_pwd or temp_joining_lobby_pwd == "":
		var id = temp_joining_lobby_id
		_close_join_popup()
		temp_joining_lobby_id = 0
		temp_joining_lobby_pwd = ""
		if id > 0:
			if id == 999999:
				(Engine.get_main_loop() as SceneTree).change_scene_to_file("res://Scenes/UI/room_scene.tscn")
			else:
				OnlineManager.join_lobby(id)
	else:
		join_password_input.add_theme_color_override("font_color", Color(1, 0.3, 0.3))
		await (Engine.get_main_loop() as SceneTree).create_timer(0.5).timeout
		join_password_input.add_theme_color_override("font_color", C_GOLD_DIM)

func _on_refresh_pressed():
	if refresh_btn.disabled: return
	refresh_btn.disabled = true
	refresh_btn.text = "REFRESHING..."
	
	if OnlineManager.has_method("refresh_lobby_list"):
		OnlineManager.refresh_lobby_list()
		
	await (Engine.get_main_loop() as SceneTree).create_timer(1.5).timeout
	refresh_btn.disabled = false
	refresh_btn.text = "↻  REFRESH"


func _on_back_pressed():
	(Engine.get_main_loop() as SceneTree).change_scene_to_file("res://anamenu.tscn")




func _on_lobby_created(_id):
	create_btn.disabled = true
	# _on_entered_room sinyali tarafından yönetilecek

func _on_entered_room():
	(Engine.get_main_loop() as SceneTree).change_scene_to_file("res://Scenes/UI/room_scene.tscn")

func _on_player_joined(_steam_id, _index):
	pass

func _on_player_left(_steam_id):
	pass

func _on_lobby_full():
	create_btn.disabled = true


# ─────────────────────────────────────────────
# LOBI LİSTESİ - Dışarıdan çağrılır
# ─────────────────────────────────────────────

func populate_lobby_list(lobbies: Array):
	for child in lobby_list_vbox.get_children():
		child.queue_free()
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
	pass
