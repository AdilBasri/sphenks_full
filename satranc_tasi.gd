extends Node3D
class_name SatrancTasi

enum Renk { BEYAZ, SIYAH }
@export var renk: Renk = Renk.BEYAZ
@export var tas_tipi: String = ""

func _ready() -> void:
	# İsimden renk tahmini yapalım (Kullanıcı kolaylığı için)
	var lower_name = name.to_lower()
	if "white" in lower_name or "beyaz" in lower_name:
		renk = Renk.BEYAZ
	elif "black" in lower_name or "siyah" in lower_name:
		renk = Renk.SIYAH
	
	# Taş tipini belirleme
	if tas_tipi == "":
		tas_tipi = name.split("_")[0] 
	
	add_to_group("satranc_taslari")
	set_meta("is_chess_piece", true)

func select() -> void:
	# Görsel bir geri bildirim eklenebilir (örn: shader, outline)
	print("%s seçildi!" % name)

func deselect() -> void:
	print("%s seçimi kaldırıldı." % name)
