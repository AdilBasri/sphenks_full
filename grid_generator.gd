@tool
extends Node3D
class_name GridOlusturucu

@export var sutun_sayisi: int = 6:
	set(v):
		sutun_sayisi = v
		olustur_grid()

@export var satir_sayisi: int = 3:
	set(v):
		satir_sayisi = v
		olustur_grid()

@export var hucre_boyutu: float = 1.0:
	set(v):
		hucre_boyutu = v
		olustur_grid()

@export var bosluk: float = 0.1:
	set(v):
		bosluk = v
		olustur_grid()
		
@export_group("Görünüm")
@export var damali_aktif: bool = true:
	set(v):
		damali_aktif = v
		olustur_grid()

@export var renk_ana: Color = Color(0.8, 0.8, 0.8):
	set(v):
		renk_ana = v
		olustur_grid()

@export var renk_alternatif: Color = Color(0.4, 0.4, 0.4):
	set(v):
		renk_alternatif = v
		olustur_grid()

var hucrelerin_sozlugu: Dictionary = {}

func _ready() -> void:
	# Grid'i oluştur
	olustur_grid()
	
	# Grid koordinatlarını konsola yazdır (Oyun başladığında)
	if not Engine.is_editor_hint():
		print_grid_coords()
		# Taşları bulup gridle ilişkilendirelim
		# Biraz bekliyoruz ki sahnede her şey tam yüklensin
		await get_tree().create_timer(0.1).timeout
		taslari_gridle_eslestir()
		spawn_kings()

func olustur_grid() -> void:
	if not is_inside_tree(): return
	
	# Eski hücreleri temizle (varsa)
	for child in get_children():
		child.queue_free()
	hucrelerin_sozlugu.clear()
	
	# Toplam genişlik ve derinlik (merkezlemek için)
	# Tek bir hücrenin kapladığı toplam alan = hucre_boyutu + bosluk
	# Ama sonuncudan sonra boşluk gelmediği için (N-1) * (hucre_boyutu + bosluk) + hucre_boyutu?
	# Basitleştirelim:
	var toplam_genislik = (sutun_sayisi - 1) * (hucre_boyutu + bosluk)
	var toplam_derinlik = (satir_sayisi - 1) * (hucre_boyutu + bosluk)
	
	for s in range(sutun_sayisi):
		for r in range(satir_sayisi):
			var hucre = GridHucre.new()
			
			# Renk seçimi (Damalı desen)
			var renk = renk_ana
			if damali_aktif and (s + r) % 2 == 1:
				renk = renk_alternatif
				
			# Setup çağrısında boyutu ve rengi de geçiyoruz!
			hucre.setup(s, r, hucre_boyutu, renk)
			add_child(hucre)
			
			# Pozisyonu ayarla (merkezli)
			var pos_x = s * (hucre_boyutu + bosluk) - toplam_genislik / 2.0
			var pos_z = r * (hucre_boyutu + bosluk) - toplam_derinlik / 2.0
			hucre.position = Vector3(pos_x, 0, pos_z)
			
			# Sözlüğe ekle
			hucrelerin_sozlugu[Vector2i(s, r)] = hucre

func print_grid_coords() -> void:
	print("--- %s Grid Koordinatları ---" % name)
	for coord in hucrelerin_sozlugu:
		var hucre = hucrelerin_sozlugu[coord]
		print("- Hücre: (%d, %d) @ %s" % [hucre.sutun, hucre.satir, hucre.global_position])
	print("---------------------------------")
func clear_grid() -> void:
	for hucre in hucrelerin_sozlugu.values():
		hucre.mevcut_tas = null

func taslari_gridle_eslestir() -> void:
	print("--- Taşlar Gridle Eşleştiriliyor ---")
	
	# Sahnedeki TÜM satranç taşlarını bulalım. 
	# Önce gruptakilere bakalım (en hızlısı)
	var taslar = get_tree().get_nodes_in_group("satranc_taslari")
	
	# Eğer grup boşsa veya bazı taşlar eksikse, sahne ağacını tamamen tarayalım
	# Not: get_parent() yerine ana sahne köküne kadar çıkabiliriz.
	var ana_sahne = get_tree().current_scene
	if ana_sahne:
		# Sahnedeki tüm node'ları gezerek isim-tabanlı veya script-tabanlı bulalım
		var tum_node_lar = ana_sahne.find_children("*", "Node3D", true, false)
		for node in tum_node_lar:
			if node in taslar: continue # Zaten gruptan bulduysak atla
			
			var lower_name = node.name.to_lower()
			if "black" in lower_name or "white" in lower_name or node.has_meta("is_chess_piece") or node is SatrancTasi:
				taslar.append(node)
	
	for tas in taslar:
		var en_yakin_hucre: GridHucre = null
		var en_yakin_mesafe: float = 9999.0
		
		# Her bir taş için en yakın hücreyi bul
		for hucre in hucrelerin_sozlugu.values():
			var mesafe = tas.global_position.distance_to(hucre.global_position)
			if mesafe < en_yakin_mesafe:
				en_yakin_mesafe = mesafe
				en_yakin_hucre = hucre
		
		# Eğer mesafe makul ise (hücre boyutunun yarısından azsa) oraya yerleştir
		if en_yakin_hucre and en_yakin_mesafe < hucre_boyutu:
			en_yakin_hucre.mevcut_tas = tas
			# Taşı hücrenin tam merkezine hizala (Opsiyonel ama temiz durur)
			tas.global_position.x = en_yakin_hucre.global_position.x
			tas.global_position.z = en_yakin_hucre.global_position.z
			print("- %s -> (%d, %d) hücresine yerleşti." % [tas.name, en_yakin_hucre.sutun, en_yakin_hucre.satir])
	
	print("---------------------------------")

func spawn_kings() -> void:
	print("--- Krallar Yerleştiriliyor ---")
	
	# White King (Row 4, Col 2) - Player Side
	_spawn_king_to_cell(2, 4, "res://Pawn/king_white.tscn")
	
	# Black King (Row 0, Col 2) - AI Side
	_spawn_king_to_cell(2, 0, "res://Pawn/king_black.tscn")
	
	print("-------------------------------")

func _spawn_king_to_cell(s: int, r: int, scene_path: String) -> void:
	var coord = Vector2i(s, r)
	if not hucrelerin_sozlugu.has(coord): return
	
	var hucre = hucrelerin_sozlugu[coord]
	if hucre.mevcut_tas: 
		hucre.mevcut_tas.queue_free()
	
	var scene = load(scene_path)
	if scene:
		var king = scene.instantiate()
		add_child(king) # Add to grid so it stays in the world
		king.global_position = hucre.global_position
		king.set_meta("is_immovable", true)
		king.set_meta("is_king", true)
		hucre.mevcut_tas = king
		print("- King (%s) -> (%d, %d) yerleştirildi." % [scene_path.get_file(), s, r])
