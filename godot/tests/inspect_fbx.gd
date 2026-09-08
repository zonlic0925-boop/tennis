extends SceneTree
## 探查 FBX 导入结果: 场景树 / 骨骼名 / 动画列表 / 骨骼世界位姿
## 运行: godot --headless --path . --script res://tests/inspect_fbx.gd

func _init() -> void:
	for f in ["res://assets/anims/idle.fbx", "res://assets/anims/run_forward.fbx", "res://assets/anims/xbot.fbx"]:
		print("\n==== ", f, " ====")
		var ps: PackedScene = load(f)
		if ps == null:
			printerr("LOAD FAILED")
			continue
		var root := ps.instantiate()
		_dump(root, 0)
		var skel := _find_skel(root)
		if skel:
			print("-- bones(%d):" % skel.get_bone_count())
			var names: Array[String] = []
			for i in skel.get_bone_count():
				names.append(skel.get_bone_name(i))
			print(", ".join(names))
			var hips := _bone(skel, "hips")
			if hips >= 0:
				var gp: Transform3D = skel.get_bone_global_pose(hips)
				print("Hips global pos: ", gp.origin, "  basis scale: ", gp.basis.get_scale())
				for bn in ["RightArm", "RightForeArm", "RightHand", "LeftArm", "Head", "Spine2", "RightUpLeg", "RightLeg", "RightFoot"]:
					var bi := _bone(skel, bn)
					if bi >= 0:
						var g: Transform3D = skel.get_bone_global_pose(bi)
						print("  %-13s pos=%s" % [bn, g.origin])
			else:
				print("NO HIPS FOUND")
		var ap := _find_anim(root)
		if ap:
			print("-- animations: ", ap.get_animation_list())
			for a in ap.get_animation_list():
				var anim := ap.get_animation(a)
				print("   ", a, " len=", anim.length, " tracks=", anim.get_track_count())
				for t in mini(6, anim.get_track_count()):
					print("      track: ", anim.track_get_path(t), " type=", anim.track_get_type(t))
		root.free()
	quit(0)


func _dump(n: Node, d: int) -> void:
	print("  ".repeat(d), n.name, " (", n.get_class(), ")")
	for c in n.get_children():
		_dump(c, d + 1)


func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skel(c)
		if r:
			return r
	return null


func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_anim(c)
		if r:
			return r
	return null


func _bone(skel: Skeleton3D, suffix: String) -> int:
	for i in skel.get_bone_count():
		var bn := skel.get_bone_name(i).to_lower().replace(":", "_").replace("mixamorig_", "")
		if bn == suffix.to_lower():
			return i
	return -1
