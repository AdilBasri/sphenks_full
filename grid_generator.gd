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

var hucrelerin_sozlugu: Dictionary = {}

func _ready() -> void:
	# Grid'i oluştur
	olustur_grid()
	
	# Grid koordinatlarını konsola yazdır (Oyun başladığında)
	if not Engine.is_editor_hint():
		print_grid_coords()

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
			# Setup çağrısında boyutu da geçiyoruz!
			hucre.setup(s, r, hucre_boyutu)
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
