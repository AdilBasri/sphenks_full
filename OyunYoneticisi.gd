extends Node

var white_pieces = [
	"res://Pawn/bishop_white.tscn",
	"res://Pawn/castle_white.tscn",
	"res://Pawn/horse_white.tscn",
	"res://Pawn/king_white.tscn",
	"res://Pawn/piyon_white.tscn",
	"res://Pawn/queen_white.tscn"
]

var camera: Camera3D
var box: Node3D
var anim_player: AnimationPlayer
var sequence_started: bool = false

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

func start_chest_sequence():
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
		
		# Rastgele beyaz bir taş seç ve çıkar
		spawn_random_white_piece()
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
