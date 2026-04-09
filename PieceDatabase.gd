extends Node

# Stat Database for Chess Pieces
# Completely decoupled to allow independent upgrades in the future.

var white_stats: Dictionary = {}
var black_stats: Dictionary = {}

func _ready():
	_initialize_database()

func _initialize_database():
	# Initial Base Stats
	var base_data = {
		"pawn": {
			"name": "Pawn",
			"attack": 1,
			"defense": 1,
			"description": "Can move 1 square in any direction."
		},
		"castle": {
			"name": "Castle",
			"attack": 1,
			"defense": 3,
			"description": "Can move 1 square straight."
		},
		"bishop": {
			"name": "Bishop",
			"attack": 2,
			"defense": 1,
			"description": "Can move 1 square diagonally."
		},
		"horse": {
			"name": "Horse",
			"attack": 2,
			"defense": 1,
			"description": "Can move straight and diagonally, has 2 movement actions."
		},
		"king": {
			"name": "King",
			"attack": 0,
			"defense": 3,
			"description": "The objective is to kill the King. It cannot move and stands fixed in the center. Upon taking damage, a new piece is drawn to replace it."
		},
		"queen": {
			"name": "Queen",
			"attack": 3,
			"defense": 2,
			"description": "Can move 1 square in any direction (straight and diagonally)."
		}
	}

	# Deep copy to dictionaries (ensure they are completely independent objects)
	for key in base_data:
		white_stats[key] = base_data[key].duplicate(true)
		black_stats[key] = base_data[key].duplicate(true)
		
	print("[PieceDatabase] Decoupled stats initialized.")

func get_piece_stats(piece_id: String) -> Dictionary:
	var lower_id = piece_id.to_lower()
	var is_white = "white" in lower_id
	var stats_source = white_stats if is_white else black_stats
	
	# Determine type from filename only (to avoid 'Pawn/' directory matching)
	var filename = lower_id.get_file()
	var type_key = ""
	if "piyon" in filename or "pawn" in filename: type_key = "pawn"
	elif "castle" in filename: type_key = "castle"
	elif "bishop" in filename: type_key = "bishop"
	elif "horse" in filename: type_key = "horse"
	elif "king" in filename: type_key = "king"
	elif "queen" in filename: type_key = "queen"
	
	if stats_source.has(type_key):
		return stats_source[type_key]
	
	return {}

func upgrade_piece(type_key: String, is_white: bool, stat_name: String, amount: int):
	var stats_source = white_stats if is_white else black_stats
	if stats_source.has(type_key) and stats_source[type_key].has(stat_name):
		stats_source[type_key][stat_name] += amount
		print("[PieceDatabase] Upgraded %s %s: %s +%d" % ["White" if is_white else "Black", type_key, stat_name, amount])

func get_piece_display_name(path: String) -> String:
	var file_name = path.get_file().to_lower()
	if "king" in file_name: return "King"
	if "queen" in file_name: return "Queen"
	if "horse" in file_name: return "Horse"
	if "piyon" in file_name or "pawn" in file_name: return "Pawn"
	if "bishop" in file_name: return "Bishop"
	if "castle" in file_name or "rook" in file_name: return "Castle"
	return "Piece"
