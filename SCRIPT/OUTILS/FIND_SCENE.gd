extends RefCounted
class_name FIND_SCENE

static func find_scene_in_tree(root_node: Node) -> Node:
	# Étape 1 : Vérifie dans SubViewport
	var subviewport = root_node.get_node("SubViewportContainer/SubViewport")
	if subviewport:
		for node in subviewport.get_children():
			if ID.get_scene(node.name) != null:
				print("Scène trouvée dans SubViewport :", node.name)
				return node

	# Étape 2 : Vérifie les enfants directs de root
	for node in root_node.get_children():
		if ID.get_scene(node.name) != null:
			print("Scène trouvée parmi les enfants de root :", node.name)
			return node

	# Étape 3 : Recherche récursive
	var stack = root_node.get_children()
	while stack.size() > 0:
		var current_node = stack.pop_front()
		if ID.get_scene(current_node.name) != null:
			print("Scène trouvée dans tout l'arbre :", current_node.name)
			return current_node
		stack.append_array(current_node.get_children())

	print("Aucune scène correspondante trouvée.")
	return null
