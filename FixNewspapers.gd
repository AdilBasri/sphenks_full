@tool
extends EditorScript

# HOW TO USE:
# 1. Open this script in Godot.
# 2. Go to 'File' -> 'Run' (or press Ctrl+Shift+X).
# 3. This will scan your OPEN SCENE and fix broken newspaper paths.

func _run():
	var root = get_editor_interface().get_edited_scene_root()
	if not root:
		print("No scene is currently open in the editor!")
		return
	
	print("--- Starting Newspaper Path Cleanup ---")
	var fixed_count = 0
	
	# Recursively find and fix nodes
	fixed_count = _process_node(root)
	
	print("--- Cleanup Finished. Fixed ", fixed_count, " nodes. ---")
	print("Now try SAVING the scene (Ctrl+S). The alert should be gone.")

func _process_node(node: Node) -> int:
	var count = 0
	
	# Check if this node is an instance of a scene
	if node.scene_file_path.contains("Assets/newspapers/"):
		var old_path = node.scene_file_path
		var new_path = old_path.replace("Assets/newspapers/", "Assets/newspaper1/")
		if FileAccess.file_exists(new_path):
			node.scene_file_path = new_path
			print("Fixed scene instance path: ", node.name, " -> ", new_path)
			count += 1
		else:
			# Try newspaper2
			new_path = old_path.replace("Assets/newspapers/", "Assets/newspaper2/")
			if FileAccess.file_exists(new_path):
				node.scene_file_path = new_path
				print("Fixed scene instance path: ", node.name, " -> ", new_path)
				count += 1
	
	# Check for MeshInstance3D resources
	if node is MeshInstance3D and node.mesh:
		var mesh_path = node.mesh.resource_path
		if mesh_path.contains("Assets/newspapers/"):
			var new_path = mesh_path.replace("Assets/newspapers/", "Assets/newspaper1/")
			if FileAccess.file_exists(new_path):
				node.mesh = load(new_path)
				print("Fixed Mesh path: ", node.name, " -> ", new_path)
				count += 1
			else:
				new_path = mesh_path.replace("Assets/newspapers/", "Assets/newspaper2/")
				if FileAccess.file_exists(new_path):
					node.mesh = load(new_path)
					print("Fixed Mesh path: ", node.name, " -> ", new_path)
					count += 1

	# Recurse
	for child in node.get_children():
		count += _process_node(child)
		
	return count
