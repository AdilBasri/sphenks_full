extends Node

# Sinyaller
signal lobby_created(connect_flag, lobby_id)
signal lobby_joined(lobby_id, permissions, locked, response)
signal player_connected(steam_id)
signal player_disconnected(steam_id)
signal p2p_message_received(sender_id, message)

var is_online: bool = false
var lobby_id: int = 0
var connected_players: Array = []
var max_players: int = 2 # Oyuncu sayısını oyunun gereksinimine göre ayarlayabiliriz

func _ready():
	# Steam'i başlat
	var initialize_response: Dictionary = Steam.steamInitEx()
	print("Steam Init: ", initialize_response)
	
	if initialize_response['status'] == 0:
		is_online = true
		_connect_steam_signals()
	else:
		print("Steam başlatılamadı, online özellikler devre dışı.")

func _process(_delta):
	if is_online:
		Steam.run_callbacks()
		_read_p2p_packets()

func _connect_steam_signals():
	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_joined.connect(_on_lobby_joined)
	Steam.lobby_chat_update.connect(_on_lobby_chat_update)
	Steam.p2p_session_request.connect(_on_p2p_session_request)

# --- LOBİ İŞLEMLERİ ---

func create_lobby():
	if not is_online: return
	print("Lobi oluşturuluyor...")
	# Lobi tipi: 2 (Public - Herkese açık) veya 1 (Friends Only)
	Steam.createLobby(2, max_players)

func join_lobby(id: int):
	if not is_online: return
	print("Lobiye katılılıyor: ", id)
	Steam.joinLobby(id)

func leave_lobby():
	if lobby_id != 0:
		Steam.leaveLobby(lobby_id)
		lobby_id = 0
		connected_players.clear()

func _on_lobby_created(connect_flag: int, new_lobby_id: int):
	if connect_flag == 1:
		lobby_id = new_lobby_id
		print("Lobi başarıyla oluşturuldu. Lobi ID: ", lobby_id)
		
		# Lobi ayarlarını yap (Örnek)
		Steam.setLobbyData(lobby_id, "name", "Sphenks Lobi")
		Steam.setLobbyData(lobby_id, "mode", "coop")
		
		var my_steam_id = Steam.getSteamID()
		if not connected_players.has(my_steam_id):
			connected_players.append(my_steam_id)
			player_connected.emit(my_steam_id)
	else:
		print("Lobi oluşturulamadı.")
	
	lobby_created.emit(connect_flag, new_lobby_id)

func _on_lobby_joined(joined_lobby_id: int, permissions: int, locked: bool, response: int):
	if response == 1: # Başarılı
		lobby_id = joined_lobby_id
		print("Lobiye katılındı. Lobi ID: ", lobby_id)
		
		# Kendi ID'mizi ekleyelim
		var my_steam_id = Steam.getSteamID()
		connected_players.clear()
		connected_players.append(my_steam_id)
		
		# Lobideki diğer oyuncuları bulalım
		var num_members = Steam.getNumLobbyMembers(lobby_id)
		for i in range(num_members):
			var member_id = Steam.getLobbyMemberByIndex(lobby_id, i)
			if member_id != my_steam_id:
				if not connected_players.has(member_id):
					connected_players.append(member_id)
					player_connected.emit(member_id)
	else:
		print("Lobiye katılamadı. Hata Kodu: ", response)
		
	lobby_joined.emit(joined_lobby_id, permissions, locked, response)

func _on_lobby_chat_update(changed_lobby_id: int, changed_user_id: int, making_change_id: int, chat_state: int):
	if changed_lobby_id != lobby_id: return
	
	# chat_state 1: Katıldı, 2: Ayrıldı, 8: Atıldı, 16: Banlandı
	if chat_state == 1: # Katıldı
		if not connected_players.has(changed_user_id):
			connected_players.append(changed_user_id)
			player_connected.emit(changed_user_id)
			print("Oyuncu Katıldı: ", changed_user_id)
	elif chat_state in [2, 8, 16]: # Ayrıldı
		if connected_players.has(changed_user_id):
			connected_players.erase(changed_user_id)
			player_disconnected.emit(changed_user_id)
			print("Oyuncu Ayrıldı: ", changed_user_id)

# --- P2P AĞ İŞLEMLERİ ---

func send_p2p_packet(target_steam_id: int, message_dict: Dictionary):
	if not is_online: return
	
	# Veriyi byte dizisine çevir (JSON olarak)
	var data_string = JSON.stringify(message_dict)
	var data_buffer = data_string.to_utf8_buffer()
	
	# Gönderim tipi: 0 (Unreliable), 2 (Reliable), 3 (Reliable With Buffering)
	var send_type = 2
	var channel = 0
	
	Steam.sendP2PPacket(target_steam_id, data_buffer, send_type, channel)

func broadcast_p2p_packet(message_dict: Dictionary):
	if not is_online: return
	
	var my_steam_id = Steam.getSteamID()
	for player_id in connected_players:
		if player_id != my_steam_id:
			send_p2p_packet(player_id, message_dict)

func _read_p2p_packets():
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
			var message_dict = json.data
			p2p_message_received.emit(sender_id, message_dict)
		else:
			print("P2P Paket parse hatası.")
			
		# Sonraki paketi kontrol et
		packet_size = Steam.getAvailableP2PPacketSize(0)

func _on_p2p_session_request(remote_steam_id: int):
	print("P2P İsteği Geldi: ", remote_steam_id)
	# Sadece lobimizdeki kişilerin isteklerini kabul et
	if connected_players.has(remote_steam_id):
		Steam.acceptP2PSessionWithUser(remote_steam_id)
		print("P2P İsteği Kabul Edildi: ", remote_steam_id)
