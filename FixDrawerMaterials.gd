@tool
extends EditorScript

# HOW TO USE:
# 1. Open this script in Godot.
# 2. Go to 'File' -> 'Run' (or press Ctrl+Shift+X).
# 3. This will BAKING the wood material into your drawers permanently.
# 4. You can then try saving the scene.

func _run():
	var root = get_editor_interface().get_edited_scene_root()
	if not root:
		print("No scene open!")
		return
	
	var mat = load("res://Masa_Ahsap.tres")
	if not mat:
		print("Material not found at res://Masa_Ahsap.tres")
		return
		
	print("--- Applying Wood Material to Drawers (Baking) ---")
	
	var drawer_names = ["drawer", "drawer2", "drawer3", "drawer4", "drawer5"]
	var count = 0
	
	for d_name in drawer_names:
		var d = root.find_child(d_name, true, false)
		if d:
			count += _apply_recursive(d, mat)
	
	print("--- Finished. Baked material into ", count, " mesh surfaces. ---")
	print("Press Ctrl+S to save the scene and make it permanent in Editor/Menu.")

func _apply_recursive(node: Node, mat: Material) -> int:
	var c = 0
	if node is MeshInstance3D:
		# Apply to all surfaces
		for i in range(node.get_surface_override_material_count()):
			node.set_surface_override_material(i, mat)
		c += 1
		
	for child in node.get_children():
		c += _apply_recursive(child, mat)
	return c
