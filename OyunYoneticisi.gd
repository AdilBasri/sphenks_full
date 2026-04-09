extends Node

var white_pieces = [
	"res://Pawn/bishop_white.tscn",
	"res://Pawn/castle_white.tscn",
	"res://Pawn/horse_white.tscn",
	"res://Pawn/piyon_white.tscn",
	"res://Pawn/queen_white.tscn"
]

var black_pieces = [
	"res://Pawn/bishop_black.tscn",
	"res://Pawn/castle_black.tscn",
	"res://Pawn/horse_black.tscn",
	"res://Pawn/piyon_black.tscn",
	"res://Pawn/queen_black.tscn"
]

enum GameTurn { PLAYER, ENEMY }
var current_turn: GameTurn = GameTurn.PLAYER
var round_number: int = 1
var is_game_active: bool = false

var camera: Camera3D
var box: Node3D
var anim_player: AnimationPlayer
var sequence_started: bool = false

const PLAYER_DRAW_POS = Vector3(0.109, -0.50, -1.597)
const ENEMY_DRAW_POS = Vector3(-0.29, -0.50, -2.06)

func _ready():
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
		print("Kutu bulundu: ", box.name)
		if not anim_player:
			anim_player = box.find_child("AnimationPlayer", true, false)
		
		if anim_player:
			print("Animasyon Oynatıcı bulundu: ", anim_player.name)
			print("Mevcut animasyonlar: ", anim_player.get_animation_list())
		else:
			# Çok daha agresif bir arama (Sahnedeki her yere bak)
			print("BAŞARISIZ: Kutuda AnimationPlayer yok. Sahne ağacında aranıyor...")
			var all_anims = get_tree().root.find_children("*", "AnimationPlayer", true, false)
			for ap in all_anims:
				print("- Sahne genelinde bulunan AP: ", ap.get_path(), " (Animasyonlar: ", ap.get_animation_list(), ")")
	
	# Start the game loop after a brief wait
	await get_tree().create_timer(1.0).timeout
	start_game()

func start_game():
	is_game_active = true
	round_number = 1
	current_turn = GameTurn.PLAYER
	start_current_turn_logic()

func start_current_turn_logic():
	if camera and camera.is_game_over:
		is_game_active = false
		return
		
	print("--- Round %d | Turn: %s ---" % [round_number, "PLAYER" if current_turn == GameTurn.PLAYER else "ENEMY"])
	
	# Draw Piece if round is odd (1, 3, 5...)
	if round_number % 2 != 0:
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

func cleanup_board():
	print("Oyun bitti, tahta temizleniyor...")
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

func next_turn():
	if current_turn == GameTurn.PLAYER:
		current_turn = GameTurn.ENEMY
	else:
		current_turn = GameTurn.PLAYER
		round_number += 1
	
	start_current_turn_logic()

func start_chest_sequence():
	if camera and camera.is_game_over: return
	print("Sandık sekansı başlatılıyor...")
	if sequence_started: 
		print("Sekans zaten çalışıyor!")
		return
	sequence_started = true
	
	if anim_player:
		# En uygun animasyonu seç (İçinde 'open' geçen)
		var anim_name = anim_player.get_animation_list()[0]
		for a in anim_player.get_animation_list():
			if "open" in a.to_lower() or "açılış" in a.to_lower():
				anim_name = a
				break
		
		print("Seçilen Animasyon: ", anim_name)
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
	var random_path = white_pieces[randi() % white_pieces.size()]
	print("Taş çıkarılıyor: ", random_path)
	var piece_scene = load(random_path)
	if not piece_scene:
		print("HATA: Taş sahnesi yüklenemedi: ", random_path)
		sequence_started = false
		return
		
	var piece = piece_scene.instantiate()
	
	# ÖNEMLİ: Meta verisini SAHNEYE EKLEMEDEN ÖNCE verelim ki GlobalShaderApplier bunu yakalasın
	piece.set_meta("render_on_top", true)
	
	# Önce sahneye ekliyoruz, sonra global_position atıyoruz (Aksi takdirde 'not in tree' hatası verir)
	get_tree().root.add_child(piece)
	
	# Adım 1: Taşı tam olarak sandığın merkezinde oluşturalım
	piece.global_position = box.global_position
	piece.scale = Vector3(0.1, 0.1, 0.1) # Sandıktan çıkarken başta küçük olsun
	
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
	# Kameraya göre yerel konuma gidiyoruz (Pürüzsüz geçiş)
	drift_tween.tween_property(piece, "position", Vector3(0.4, -0.4, -0.6), 1.0).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	drift_tween.tween_property(piece, "rotation_degrees", Vector3(3.8, 154.4, 0.8), 1.0)
	
	await drift_tween.finished
	
	# Kamera scriptine bildirim gönder
	if camera.has_method("pick_up_piece"):
		camera.pick_up_piece(piece, random_path)

func _spawn_random_black_piece_for_enemy():
	var random_path = black_pieces[randi() % black_pieces.size()]
	print("Düşman taşı çıkarılıyor: ", random_path)
	var piece_scene = load(random_path)
	if not piece_scene: return
	
	var piece = piece_scene.instantiate()
	piece.set_meta("render_on_top", true)
	get_tree().root.add_child(piece)
	
	piece.global_position = box.global_position
	piece.scale = Vector3(0.1, 0.1, 0.1)
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
	
	# AI Think and Place
	await get_tree().create_timer(randf_range(1.5, 3.0)).timeout
	_ai_place_piece(piece, random_path)

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
		await get_tree().create_timer(1.0).timeout
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
	var piece = from.mevcut_tas
	var path = piece.get_meta("scene_path")
	from.mevcut_tas = null
	
	# Jump animation (Shared logic with camera_3d but automated)
	var tw = create_tween()
	var start_pos = piece.global_position
	var end_pos = to.global_position
	var mid_point = (start_pos + end_pos) / 2.0 + Vector3(0, 0.15, 0)
	
	tw.tween_property(piece, "global_position", mid_point, 0.25).set_trans(Tween.TRANS_SINE)
	tw.tween_property(piece, "global_position", end_pos, 0.25).set_trans(Tween.TRANS_SINE)
	await tw.finished
	
	# Combat Resolution (Same as player's)
	if to.mevcut_tas:
		var attacker_stats = PieceDatabase.get_piece_stats(path)
		var defender = to.mevcut_tas
		var defender_path = defender.get_meta("scene_path")
		var defender_stats = PieceDatabase.get_piece_stats(defender_path)
		
		var current_def = defender.get_meta("current_defense") if defender.has_meta("current_defense") else defender_stats["defense"]
		current_def -= attacker_stats["attack"]
		defender.set_meta("current_defense", current_def)
		
		if camera.has_method("apply_shake"): camera.apply_shake(0.2, 0.3)
		
		if current_def <= 0:
			# Capture!
			if camera.has_method("_create_puff"): camera._create_puff(to.global_position)
			if camera.has_method("apply_shake"): camera.apply_shake(0.4, 0.5)
			
			var is_king = defender.has_meta("is_king")
			var is_player_king = is_king and "white" in defender_path.to_lower()
			
			defender.queue_free()
			to.mevcut_tas = piece
			piece.reparent(to)
			piece.position = Vector3.ZERO
			
			if is_king:
				if is_player_king:
					if camera.has_method("trigger_loss"): camera.trigger_loss()
				else:
					if camera.has_method("trigger_win"): camera.trigger_win()
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

# Taşın materyallerini ayarlama yardımcısı
func set_piece_render_priority(node: Node, priority: int, x_ray: bool = false):
	if node is MeshInstance3D:
		# Meta verisini güncelle ki GlobalShaderApplier fark etsin (Eğer dinamik değişirse)
		node.set_meta("render_on_top", x_ray)
		
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
	
	# Kutu kapansın (Animasyonun devamı)
	# Eğer animasyon durdurulmuşsa devam ettir
	anim_player.speed_scale = 1.0
	sequence_started = false

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
