extends Node

# Stat Database for Chess Pieces
# Completely decoupled to allow independent upgrades in the future.

var white_stats: Dictionary = {}
var black_stats: Dictionary = {}

# Backups to preserve singleplayer progress during online matches
var white_stats_backup: Dictionary = {}
var black_stats_backup: Dictionary = {}

func _ready():
	_initialize_database()

func _initialize_database():
	# Initial Base Stats
	var base_data = {
		"pawn": {
			"name": "Pawn",
			"attack": 2,
			"defense": 2,
			"description": "Can move 1 square in any direction."
		},
		"castle": {
			"name": "Castle",
			"attack": 2,
			"defense": 4,
			"description": "Can move 1 square straight."
		},
		"bishop": {
			"name": "Bishop",
			"attack": 3,
			"defense": 2,
			"description": "Can move 1 square diagonally."
		},
		"horse": {
			"name": "Horse",
			"attack": 3,
			"defense": 1,
			"description": "Can move straight and diagonally, has 2 movement actions."
		},
		"king": {
			"name": "King",
			"attack": 0,
			"defense": 5,
			"description": "The objective is to kill the King. It cannot move and stands fixed in the center. Upon taking damage, a new piece is drawn to replace it."
		},
		"queen": {
			"name": "Queen",
			"attack": 3,
			"defense": 3,
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

func get_piece_type(path: String) -> String:
	var filename = path.get_file().to_lower()
	if "piyon" in filename or "pawn" in filename: return "pawn"
	if "castle" in filename or "rook" in filename: return "castle"
	if "bishop" in filename: return "bishop"
	if "horse" in filename: return "horse"
	if "king" in filename: return "king"
	if "queen" in filename: return "queen"
	return ""

func get_valid_moves(current_pos: Vector2i, piece_path: String) -> Array[Vector2i]:
	var file_name = piece_path.get_file().to_lower()
	var moves: Array[Vector2i] = []
	
	var offsets: Array[Vector2i] = []
	
	if "piyon" in file_name or "pawn" in file_name or "queen" in file_name:
		# Pawn and Queen: 1 square in any direction (8 neighbors)
		offsets = [
			Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0),
			Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)
		]
	elif "castle" in file_name:
		# Castle: 1 square straight (4 neighbors)
		offsets = [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]
	elif "bishop" in file_name:
		# Bishop: 1 square diagonal (4 neighbors)
		offsets = [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
	elif "horse" in file_name:
		# Horse: Straight and Diagonal, 2 actions (Up to distance 2)
		# We'll include all neighbors within radius 2
		for x in range(-2, 3):
			for y in range(-2, 3):
				if x == 0 and y == 0: continue
				offsets.append(Vector2i(x, y))
	elif "king" in file_name:
		# King: Immovable
		return []

	# Calculate final coordinates and clamp to grid (7x7)
	for offset in offsets:
		var target = current_pos + offset
		if target.x >= 0 and target.x < 7 and target.y >= 0 and target.y < 7:
			moves.append(target)
			
	return moves

func reset_database_for_online():
	# Save current stats to backup (Singleplayer)
	white_stats_backup = white_stats.duplicate(true)
	black_stats_backup = black_stats.duplicate(true)
	# Reset current stats to base for the online match
	_initialize_database()
	print("[PieceDatabase] Singleplayer stats backed up and database reset for online play.")

func restore_database_after_online():
	if not white_stats_backup.is_empty():
		white_stats = white_stats_backup.duplicate(true)
		black_stats = black_stats_backup.duplicate(true)
		white_stats_backup.clear()
		black_stats_backup.clear()
		print("[PieceDatabase] Singleplayer stats restored from backup.")

func get_raw_stats() -> Dictionary:
	return {
		"white": white_stats,
		"black": black_stats
	}

func set_raw_stats(data: Dictionary):
	if data.has("white"):
		white_stats = data["white"]
	if data.has("black"):
		black_stats = data["black"]
	print("[PieceDatabase] Stats restored from save.")
