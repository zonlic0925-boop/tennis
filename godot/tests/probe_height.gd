extends SceneTree
## 临时探查: 角色世界身高 + 骨架缩放, 用于相机标定

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var ch := AnimeCharacter.new()
	root.add_child(ch)
	var clips := {"run": AnimeCharacter.extract_clip("res://assets/anims/run_forward.fbx", true)}
	ch.build(load("res://assets/anims/idle.fbx"), Skins.ALL[2], clips)
	await process_frame
	var skel: Skeleton3D = ch.skeleton
	print("model_root scale=", ch.get_child(0).scale, " global=", ch.get_child(0).global_transform)
	for bn in ["hips", "head", "leftfoot", "rightfoot", "lefttoe" ]:
		if not ch.bones.has(bn):
			print(bn, " 不存在")
			continue
		var idx := skel.find_bone(ch.bones[bn])
		var gp: Transform3D = skel.get_bone_global_pose(idx)
		var world: Transform3D = ch.get_child(0).global_transform * ch.skeleton.global_transform * gp
		print("%s: world_y=%.3f (local y=%.3f)" % [bn, world.origin.y, gp.origin.y])
	quit(0)
