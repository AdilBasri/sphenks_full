extends Node

# --- SİNYALLER ---
# --- SİNYALLER ---
signal lobby_created(lobby_id)
signal player_joined(steam_id, player_index)
signal player_left(steam_id)
signal lobby_full()
signal data_received(from_id, data)
signal player_ready_changed(steam_id, is_ready)
signal game_started()
signal entered_room()
signal password_required(lobby_id, correct_password)
signal join_failed(reason)
signal lobby_list_updated(lobbies)

# --- DEĞİŞKENLER ---
var lobby_id: int = 0
var is_host: bool = false
var my_steam_id: int = 0
var players: Dictionary = {}      # {steam_id: player_index}
var player_ready: Dictionary = {} # {steam_id: bool}
var room_code: String = ""
var room_name: String = ""
var room_password: String = ""
var temp_joining_lobby_id: int = 0
var is_searching_by_code: bool = false

var is_online: bool = false
var max_players: int = 4

# Oda kodu benzersizliği için (online + offline her ikisinde de kullan)
static var _used_codes: Dictionary = {}

func _ready():
	var initialize_response: Dictionary = Steam.steamInitEx()
	print("Steam Init: ", initialize_response)
	if initialize_response['status'] == 0:
		is_online = true
		my_steam_id = Steam.getSteamID()
		_connect_steam_signals()
	else:
		print("Steam kapalı — offline/test modu aktif.")

func _process(_delta):
	if is_online:
		Steam.run_callbacks()
		_read_packets()

func _connect_steam_signals():
	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_joined.connect(_on_lobby_joined)
	Steam.lobby_chat_update.connect(_on_lobby_chat_update)
	Steam.p2p_session_request.connect(_on_p2p_session_request)
	Steam.lobby_match_list.connect(_on_lobby_match_list)

# ─────────────────────────────────────────────
# LOBİ
# ─────────────────────────────────────────────

func create_lobby(name: String = "My Room", password: String = ""):
	room_name = name
	room_password = password
	if not is_online:
		# Offline test modu
		room_code = _generate_unique_room_code()
		is_host = true
		lobby_id = 999999  # sahte ID
		players.clear()
		player_ready.clear()
		# Kendimizi ekle (steam_id = 0 offline için)
		_add_player(0)
		lobby_created.emit(lobby_id)
		entered_room.emit()
		return
	Steam.createLobby(2, max_players)

func join_lobby(id: int):
	if not is_online: return
	Steam.joinLobby(id)

func join_by_code(code: String):
	if not is_online: return
	Steam.addRequestLobbyListStringFilter("room_code", code, 0)
	Steam.requestLobbyList()

func leave_lobby():
	if lobby_id != 0 and is_online:
		Steam.leaveLobby(lobby_id)
	# Kod'u serbest bırak
	_used_codes.erase(room_code)
	lobby_id = 0
	players.clear()
	player_ready.clear()
	room_code = ""
	room_name = ""
	is_host = false

# ─────────────────────────────────────────────
# HAZIR / OYUNU BAŞLAT
# ─────────────────────────────────────────────

func set_ready(rdy: bool):
	player_ready[my_steam_id] = rdy
	player_ready_changed.emit(my_steam_id, rdy)
	if is_online:
		broadcast({"type": "ready", "steam_id": my_steam_id, "is_ready": rdy})

func start_game():
	if not is_host: return
	if is_online:
		broadcast({"type": "start_game"})
	game_started.emit()

func are_all_ready() -> bool:
	if players.size() < 2: return false
	for sid in players.keys():
		if not player_ready.get(sid, false):
			return false
	return true

func get_player_display_name(steam_id: int) -> String:
	# Steam açıksa Steam ismini al, kapalıysa Player N
	if is_online and steam_id != 0:
		var name = Steam.getFriendPersonaName(steam_id)
		if name and name != "":
			return name
	var idx = players.get(steam_id, 0)
	return "Player " + str(idx + 1)

# ─────────────────────────────────────────────
# KOD ÜRETİMİ
# ─────────────────────────────────────────────

func _generate_unique_room_code() -> String:
	var attempts = 0
	while attempts < 200:
		var code = str(randi() % 900000 + 100000)  # 100000–999999
		if not _used_codes.has(code):
			_used_codes[code] = true
			return code
		attempts += 1
	# Çok nadir fallback
	return str(randi() % 900000 + 100000)

# ─────────────────────────────────────────────
# P2P
# ─────────────────────────────────────────────

func send_data(target_id: int, data: Dictionary):
	if not is_online: return
	var buf = JSON.stringify(data).to_utf8_buffer()
	Steam.sendP2PPacket(target_id, buf, 2, 0)

func broadcast(data: Dictionary):
	if not is_online: return
	for sid in players.keys():
		if sid != my_steam_id:
			send_data(sid, data)

func _read_packets():
	var packet_size = Steam.getAvailableP2PPacketSize(0)
	while packet_size > 0:
		var packet = Steam.readP2PPacket(packet_size, 0)
		if packet.is_empty(): break
		var sender_id = packet["remote_steam_id"]
		var data_string = packet["data"].get_string_from_utf8()
		var json = JSON.new()
		if json.parse(data_string) == OK:
			_handle_message(sender_id, json.data)
		packet_size = Steam.getAvailableP2PPacketSize(0)

func _handle_message(from_id: int, data: Dictionary):
	match data.get("type", ""):
		"ready":
			var sid = data.get("steam_id", from_id)
			var rdy = data.get("is_ready", false)
			player_ready[sid] = rdy
			player_ready_changed.emit(sid, rdy)
		"start_game":
			game_started.emit()
		_:
			data_received.emit(from_id, data)

# ─────────────────────────────────────────────
# STEAM CALLBACKLER
# ─────────────────────────────────────────────

func _on_lobby_created(connect_flag: int, new_lobby_id: int):
	if connect_flag == 1:
		lobby_id = new_lobby_id
		is_host = true
		room_code = _generate_unique_room_code()
		Steam.setLobbyData(lobby_id, "room_code", room_code)
		Steam.setLobbyData(lobby_id, "room_name", room_name)
		Steam.setLobbyData(lobby_id, "password", room_password)
		_add_player(my_steam_id)
		lobby_created.emit(lobby_id)
		entered_room.emit()
	else:
		print("Lobi oluşturulamadı.")

func _on_lobby_match_list(lobbies: Array):
	if lobbies.is_empty():
		join_failed.emit("No room found with that code.")
		return
	
	var target_lobby = lobbies[0]
	var pwd = Steam.getLobbyData(target_lobby, "password")
	
	if pwd != "":
		password_required.emit(target_lobby, pwd)
	else:
		Steam.joinLobby(target_lobby)

func _on_lobby_joined(joined_lobby_id: int, _permissions: int, _locked: bool, response: int):
	if response == 1:
		lobby_id = joined_lobby_id
		is_host = false
		room_code = Steam.getLobbyData(lobby_id, "room_code")
		room_name = Steam.getLobbyData(lobby_id, "room_name")
		players.clear()
		player_ready.clear()
		_add_player(my_steam_id)
		var num = Steam.getNumLobbyMembers(lobby_id)
		for i in range(num):
			var mid = Steam.getLobbyMemberByIndex(lobby_id, i)
			if mid != my_steam_id:
				_add_player(mid)
		if players.size() >= max_players:
			lobby_full.emit()
		entered_room.emit()
	else:
		print("Lobiye katılamadı. Kod: ", response)

func _on_lobby_chat_update(changed_lobby_id: int, changed_user_id: int, _making: int, chat_state: int):
	if changed_lobby_id != lobby_id: return
	if chat_state == 1:
		if not players.has(changed_user_id):
			_add_player(changed_user_id)
			if players.size() >= max_players:
				lobby_full.emit()
	elif chat_state in [2, 8, 16]:
		if players.has(changed_user_id):
			players.erase(changed_user_id)
			player_ready.erase(changed_user_id)
			player_left.emit(changed_user_id)

func _on_p2p_session_request(remote_steam_id: int):
	if players.has(remote_steam_id):
		Steam.acceptP2PSessionWithUser(remote_steam_id)

func _add_player(steam_id: int):
	if not players.has(steam_id):
		var idx = players.size()
		players[steam_id] = idx
		player_ready[steam_id] = false
		player_joined.emit(steam_id, idx)
