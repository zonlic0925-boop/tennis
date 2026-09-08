extends SceneTree
## 角色构建验证: 4 套皮肤 × (骨架/部件数/动画注册/发球关键帧手部位姿)
## 运行: godot --headless --path . --script res://tests/test_character.gd

var failures: Array[String] = []


func _init() -> void:
	# 等一帧让 class 缓存可用后执行
	call_deferred("_run")


func _run() -> void:
	var idle_scene: PackedScene = load("res://assets/anims/idle.fbx")
	var clips := {
		"run": AnimeCharacter.extract_clip("res://assets/anims/run_forward.fbx", true),
		"forehand": AnimeCharacter.extract_clip("res://assets/anims/forehand_swing.fbx", false),
		"backhand": AnimeCharacter.extract_clip("res://assets/anims/backhand_swing.fbx", false),
		"victory": AnimeCharacter.extract_clip("res://assets/anims/victory.fbx", false),
	}
	for k in clips:
		if clips[k] == null:
			failures.append("clip 加载失败: " + k)
		else:
			print("clip %s: len=%.2fs tracks=%d" % [k, clips[k].length, clips[k].get_track_count()])

	for s in Skins.ALL:
		var ch := AnimeCharacter.new()
		ch.name = "Char_" + s.id
		root.add_child(ch)
		ch.build(idle_scene, s, clips)

		var meshes := _count_meshes(ch)
		var anims := ch.anim.get_animation_list()
		print("[%s %s] bones=%d meshes=%d anims=%s" % [s.id, s.label, ch.skeleton.get_bone_count(), meshes, ",".join(anims)])
		if meshes < 25:
			failures.append("%s 部件过少: %d" % [s.id, meshes])
		for need in ["idle", "run", "forehand", "backhand", "serve", "victory"]:
			if not ch.anim.has_animation(need):
				failures.append("%s 缺动画 %s" % [s.id, need])

		# 发球关键帧数据 sanity: 各骨骼旋转在关键帧之间应有明显差异
		var serve_anim := ch.anim.get_animation("serve")
		var ra_path: String = "Skeleton3D:" + ch.bones["righthand"].replace("RightHand", "RightArm")
		var ra_track := -1
		for t in serve_anim.get_track_count():
			if str(serve_anim.track_get_path(t)) == ra_path:
				ra_track = t
				break
		if ra_track < 0:
			failures.append("%s serve 缺 RightArm 轨道" % s.id)
		else:
			var q1: Quaternion = serve_anim.rotation_track_interpolate(ra_track, 0.24)
			var q2: Quaternion = serve_anim.rotation_track_interpolate(ra_track, 0.46)
			print("  serve RightArm t=0.24 vs 0.46 夹角=%.1f°" % rad_to_deg(q1.angle_to(q2)))
			if q1.angle_to(q2) < 0.5:
				failures.append("%s serve 关键帧无差异" % s.id)

	if failures.is_empty():
		print("\n角色构建验证通过")
		quit(0)
	else:
		for f in failures:
			printerr("FAIL ", f)
		quit(1)


func _count_meshes(n: Node) -> int:
	var c := 0
	if n is MeshInstance3D and n.visible:
		c += 1
	for ch in n.get_children():
		c += _count_meshes(ch)
	return c
