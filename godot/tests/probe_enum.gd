extends SceneTree
func _init() -> void:
	var keys := ClassDB.class_get_integer_constant_list("BaseMaterial3D", true)
	var toonish: Array[String] = []
	for k in keys:
		var kl := String(k).to_lower()
		if kl.contains("toon") or kl.contains("shading") or kl.contains("ramp"):
			toonish.append(String(k))
	print("MATCHES: ", toonish)
	var m := StandardMaterial3D.new()
	print("has set_shading_mode: ", m.get_property_list().any(func(p): return p.name == "shading_mode"))
	quit(0)
