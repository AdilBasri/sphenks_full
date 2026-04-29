extends Node

# --- SİNYALLER ---
signal lobby_created(lobby_id)
signal player_joined(steam_id, player_index)
signal player_left(steam_id)
signal lobby_full()
signal data_received(from_id, data)

# --- DEĞİŞKENLER ---
var lobby_id: int = 0
var is_host: bool = false
var my_steam_id: int = 0
var players: Dictionary = {} # {steam_id: player_index}

# Ekstra durum takibi için
var is_online: bool = false
var max_players: int = 4

func _ready():
	# Steam'i başlat
	var initialize_response: Dictionary = Steam.steamInitEx()
	print("Steam Init: ", initialize_response)
	
	if initialize_response['status'] == 0:
		is_online = true
		my_steam_id = Steam.getSteamID()
		_connect_steam_signals()
	else:
		print("Steam başlatılamadı, online özellikler devre dışı.")

func _process(_delta):
	if is_online:
		Steam.run_callbacks()
		_read_packets()

func _connect_steam_signals():
	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_joined.connect(_on_lobby_joined)
	Steam.lobby_chat_update.connect(_on_lobby_chat_update)
	Steam.p2p_session_request.connect(_on_p2p_session_request)

# --- FONKSİYONLAR ---

func create_lobby():
	if not is_online: return
	print("Lobi oluşturuluyor...")
	# Lobi tipi: 2 (Public - Herkese açık) veya 1 (Friends Only)
	Steam.createLobby(2, max_players)

func join_lobby(id: int):
	if not is_online: return
	print("Lobiye katılılıyor: ", id)
	Steam.joinLobby(id)

func send_data(target_id: int, data: Dictionary):
	if not is_online: return
	
	var data_string = JSON.stringify(data)
	var data_buffer = data_string.to_utf8_buffer()
	
	# Gönderim tipi: 2 (Reliable - Güvenilir)
	var send_type = 2
	var channel = 0
	
	Steam.sendP2PPacket(target_id, data_buffer, send_type, channel)

func broadcast(data: Dictionary):
	if not is_online: return
	
	for steam_id in players.keys():
		if steam_id != my_steam_id:
			send_data(steam_id, data)

func _read_packets():
	var packet_size = Steam.getAvailableP2PPacketSize(0)
	while packet_size > 0:
		var packet = Steam.readP2PPacket(packet_size, 0)
		if packet.is_empty():
			break
			
		var sender_id = packet["remote_steam_id"]
		var data_buffer = packet["data"]
		var data_string = data_buffer.get_string_from_utf8()
		
		var json = JSON.new()
		var parse_result = json.parse(data_string)
		
		if parse_result == OK:
			var data = json.data
			data_received.emit(sender_id, data)
		else:
			print("P2P Paket parse hatası.")
			
		# Sonraki paketi kontrol et
		packet_size = Steam.getAvailableP2PPacketSize(0)

# --- CALLBACK FONKSİYONLARI ---

func _on_lobby_created(connect_flag: int, new_lobby_id: int):
	if connect_flag == 1:
		lobby_id = new_lobby_id
		is_host = true
		print("Lobi başarıyla oluşturuldu. Lobi ID: ", lobby_id)
		
		Steam.setLobbyData(lobby_id, "name", "Sphenks Lobi")
		Steam.setLobbyData(lobby_id, "mode", "coop")
		
		# Kurucu olarak kendimizi ekleyelim (player_index = 0)
		_add_player(my_steam_id)
		
		lobby_created.emit(lobby_id)
	else:
		print("Lobi oluşturulamadı.")

func _on_lobby_joined(joined_lobby_id: int, permissions: int, locked: bool, response: int):
	if response == 1: # Başarılı
		lobby_id = joined_lobby_id
		is_host = false
		print("Lobiye katılındı. Lobi ID: ", lobby_id)
		
		players.clear()
		
		# Kendimizi ekleyelim
		_add_player(my_steam_id)
		
		# Lobideki diğer oyuncuları bulalım
		var num_members = Steam.getNumLobbyMembers(lobby_id)
		for i in range(num_members):
			var member_id = Steam.getLobbyMemberByIndex(lobby_id, i)
			if member_id != my_steam_id:
				_add_player(member_id)
				
		if players.size() >= max_players:
			lobby_full.emit()
	else:
		print("Lobiye katılamadı. Hata Kodu: ", response)

func _on_lobby_chat_update(changed_lobby_id: int, changed_user_id: int, making_change_id: int, chat_state: int):
	if changed_lobby_id != lobby_id: return
	
	# chat_state 1: Katıldı, 2: Ayrıldı, 8: Atıldı, 16: Banlandı
	if chat_state == 1: # Katıldı
		if not players.has(changed_user_id):
			_add_player(changed_user_id)
			print("Oyuncu Katıldı: ", changed_user_id)
			
			if players.size() >= max_players:
				lobby_full.emit()
				
	elif chat_state in [2, 8, 16]: # Ayrıldı
		if players.has(changed_user_id):
			players.erase(changed_user_id)
			player_left.emit(changed_user_id)
			print("Oyuncu Ayrıldı: ", changed_user_id)

func _on_p2p_session_request(remote_steam_id: int):
	print("P2P İsteği Geldi: ", remote_steam_id)
	# Sadece lobimizdeki kişilerin isteklerini kabul et
	if players.has(remote_steam_id):
		Steam.acceptP2PSessionWithUser(remote_steam_id)
		print("P2P İsteği Kabul Edildi: ", remote_steam_id)

func _add_player(steam_id: int):
	if not players.has(steam_id):
		var player_index = players.size()
		players[steam_id] = player_index
		player_joined.emit(steam_id, player_index)
