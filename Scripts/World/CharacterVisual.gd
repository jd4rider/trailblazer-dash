class_name CharacterVisual
## Loads, tints and animates a Trailblazer model. The Blender build ships one
## rigged body per character with its own palette baked in, so tinting is only a
## fallback for models that are missing their colours.

const DIR := "res://Assets/Models/characters/"


static func spawn(character_id: String, scale := 1.0) -> Node3D:
	var path := DIR + character_id + ".glb"
	if not ResourceLoader.exists(path):
		path = DIR + "pip.glb"
	if not ResourceLoader.exists(path):
		return null
	var packed: PackedScene = load(path)
	if packed == null:
		return null
	var node := packed.instantiate() as Node3D
	node.scale = Vector3.ONE * scale
	node.rotation.y = PI
	return node


static func animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := animation_player(child)
		if found:
			return found
	return null


static func tint_for(node: Node3D, character_id: String) -> void:
	var entry := Roster.get_character(character_id)
	tint(node, entry)


static func tint(node: Node3D, entry: Dictionary) -> void:
	if node == null or entry.is_empty():
		return
	var outfit := Color(String(entry.get("outfit", "#2f7d78")))
	var accent := Color(String(entry.get("accent", "#e8a33d")))
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		for surface in range(mesh_instance.mesh.get_surface_count()):
			var material := mesh_instance.get_active_material(surface)
			if material == null:
				continue
			var name := material.resource_name
			if not (name.contains("jacket") or name.contains("trousers")
					or name.contains("hat") or name.contains("scarf")
					or name.contains("accent")):
				continue
			var copy := material.duplicate() as StandardMaterial3D
			if name.contains("jacket"):
				copy.albedo_color = outfit
			elif name.contains("trousers"):
				copy.albedo_color = outfit.darkened(0.22)
			elif name.contains("hat"):
				copy.albedo_color = Color("#efe3c6").lerp(accent, 0.3)
			elif name.contains("scarf") or name.contains("accent"):
				copy.albedo_color = accent
			mesh_instance.set_surface_override_material(surface, copy)
