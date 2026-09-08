extends SceneTree
## 球场亮带诊断: 同一场景 4 个变量各拍一张
## 运行(窗口): godot --path . --script res://tests/diag_world.gd

var cam: Camera3D
var sun: DirectionalLight3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("071522")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("cfe4ff")
	env.ambient_light_energy = 0.7
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color("071522")
	env.fog_depth_begin = 30.0
	env.fog_depth_end = 90.0
	we.environment = env
	root.add_child(we)

	sun = DirectionalLight3D.new()
	sun.light_color = Color("fff1dd")
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	root.add_child(sun)
	sun.look_at_from_position(Vector3(7, 18, -7), Vector3.ZERO, Vector3.UP)

	_plane(Color("0a2030"), Vector2(80, 44), -0.05, Vector3(0, 0, 10), 16)
	_plane(Color("277fa8"), Vector2(CourtConfig.COURT_LENGTH + 1.2, CourtConfig.COURT_WIDTH + 1.2), 0.0)
	_plane(Color("2e9bc8"), Vector2(CourtConfig.COURT_LENGTH, CourtConfig.COURT_WIDTH), 0.02)

	cam = Camera3D.new()
	cam.fov = 62.0
	cam.near = 0.2
	root.add_child(cam)
	cam.make_current()

	cam.position = Vector3(0, 5.1, -13.6)
	cam.look_at(Vector3(0, 1.0, 2.2))

	# k: 全新 Environment, 唯一区别 = 无雾 (旧 env 运行时改动不可靠, 必须整体重建)
	var env2 := Environment.new()
	env2.background_mode = Environment.BG_COLOR
	env2.background_color = Color("071522")
	env2.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env2.ambient_light_color = Color("cfe4ff")
	env2.ambient_light_energy = 0.7
	env2.fog_enabled = false
	we.environment = env2
	await _settle()
	await _shot("diag_k_nofog_fresh.png")

	# l: 全新 Environment, 雾开 (对照组)
	var env3 := Environment.new()
	env3.background_mode = Environment.BG_COLOR
	env3.background_color = Color("071522")
	env3.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env3.ambient_light_color = Color("cfe4ff")
	env3.ambient_light_energy = 0.7
	env3.fog_enabled = true
	env3.fog_mode = Environment.FOG_MODE_DEPTH
	env3.fog_light_color = Color("071522")
	env3.fog_depth_begin = 30.0
	env3.fog_depth_end = 90.0
	we.environment = env3
	await _settle()
	await _shot("diag_l_fog_fresh.png")

	# n: 置顶窗口后抓屏, 仅裁剪窗口区域 (区分渲染伪影 vs 回读伪影)
	var win: Window = root
	DisplayServer.window_set_position(Vector2i(0, 0), win.get_window_id())
	DisplayServer.window_move_to_foreground(win.get_window_id())
	for i in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	var wp := DisplayServer.window_get_position(win.get_window_id())
	var ws := DisplayServer.window_get_size(win.get_window_id())
	var scr := DisplayServer.screen_get_image(-1)
	print("[DIAG] window at ", wp, " size ", ws, " screen ", scr.get_width(), "x", scr.get_height())
	var img2 := scr.get_region(Rect2i(wp, ws))
	img2.save_png("C:/Users/Zonlic/Desktop/experiment/tennis/godot/shots/diag_n_window.png")
	print("[DIAG] saved diag_n_window.png")

	quit(0)


func _settle() -> void:
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw


func _shot(name: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png("C:/Users/Zonlic/Desktop/experiment/tennis/godot/shots/" + name)
	print("[DIAG] saved ", name)


func _plane(color: Color, size: Vector2, y: float, center := Vector3.ZERO, subdivide := 0) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = size
	if subdivide > 0:
		pm.subdivide_width = subdivide
		pm.subdivide_depth = subdivide
	mi.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mi.material_override = m
	mi.position = Vector3(center.x, y, center.z)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
