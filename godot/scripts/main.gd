extends Node3D
## ACEMATCH 主场景编排 —— js/game.js (比赛流程/AI/物理步进/裁判接线) +
## render/scene.js (球场/灯光/相机) + render/fx.js (球影/落点/时机光圈) + ui.js (HUD) 的整合移植。
## 坐标: 玩家半场 z<0, 相机 z=-13.6 朝 +Z → 屏幕右 = 世界 -X, 输入层在此统一翻转 dx。
## 命令行 ("--" 之后): --smoke | --shots=DIR | --autopilot | --speed=N | --skin=N | --difficulty=F | --max-sec=N

const STEP := 1.0 / 120.0            # 物理子步 (与 game.js 一致)
const FIXED_DT := 1.0 / 60.0         # --speed 模式的固定逻辑步长

const COL_BG := Color("071522")
const COL_COURT := Color("2e9bc8")
const COL_EDGE := Color("277fa8")
const COL_APRON := Color("0a2030")
const COL_LINE := Color("f5faff")
const COL_BALL := Color("d8e63c")
const COL_GREEN := Color("3dff88")
const COL_RED := Color("ff4a4a")
const COL_YELLOW := Color("ffd23d")
const COL_ORANGE := Color("ff7a3d")
const COL_FENCE := Color("0a1b2b")

const DL := 5.485                    # 双打边线 (装饰)

## 球员/对手状态载体 (JS 中为普通对象)
class Actor:
	var id := "p1"
	var pos := Vector3.ZERO
	var move_target := Vector3.ZERO
	var has_target := false
	var landing := {}                  # predict_landing 缓存
	var landing_shot := -1
	var strike_delay := 0.0
	var has_struck := true
	var char: AnimeCharacter = null

var referee := Referee.new()
var difficulty := 0.55
var auto_play := false
var started := false

var p1: Actor
var p2: Actor

var ball: BallPhysics.BallState
var ball_active := false
var toss_pos := Vector3.ZERO
var awaiting_serve = null           # {server, done} 或 null
var last_striker := ""
var last_bounce_side := 0           # 0=未落地, 否则 sign(z)
var has_bounced_shot := false       # 本次击球是否已合法落地
var struck_shot_ids := {"p1": -1, "p2": -1}
var serve_side := -1
var shot_id := 0
var point_end_timer := 0.0
var ai_serve_timer := 0.0
var phase_key := ""
var hint_key := ""
var victory_played := false
var game_time := 0.0

# ---- 节点引用 ----
var camera: Camera3D
var ball_mesh: MeshInstance3D
var ball_shadow: MeshInstance3D
var landing_root: Node3D
var landing_ring_mat: StandardMaterial3D
var landing_disc_mat: StandardMaterial3D
var reticle_mesh: MeshInstance3D
var reticle_mat: StandardMaterial3D
var landing_t := 0.0
var reticle_t := 0.0

# ---- HUD 引用 ----
var hud_root: Control
var lbl_score_p1: Label
var lbl_score_p2: Label
var dot_p1: Label
var dot_p2: Label
var lbl_phase: Label
var lbl_toast: Label
var lbl_hint: Label
var start_overlay: Control
var end_overlay: Control
var lbl_end_title: Label
var lbl_end_score: Label
var toast_timer := 0.0
var dpad_vec := Vector2.ZERO
var ui_font: FontFile

# ---- 命令行选项 ----
var opt_smoke := false
var opt_shots_dir := ""
var opt_autopilot := false
var opt_speed := 0                  # 0 = 实时
var opt_skin := 0
var opt_difficulty := -1.0
var opt_max_sec := 0.0

# ---- 截图模式状态机 ----
var shots_stage := 0
var shots_timer := 0.0
var shot_busy := false
var captured01 := false

var swipe_down = null               # {x0, y0, t0, samples}


func _ready() -> void:
	_parse_args()
	auto_play = opt_smoke or opt_autopilot or opt_shots_dir != ""
	if opt_smoke or opt_shots_dir != "":
		seed(20260908)
		if opt_max_sec <= 0.0:
			opt_max_sec = 240.0
	else:
		randomize()
	if opt_difficulty >= 0.0:
		difficulty = opt_difficulty

	ball = BallPhysics.BallState.new(Vector3(0, 2.7, 0), Vector3.ZERO)
	p1 = Actor.new(); p1.id = "p1"; p1.pos = Vector3(0, 0, CourtConfig.PLAYER_BASE.z)
	p2 = Actor.new(); p2.id = "p2"; p2.pos = Vector3(0, 0, CourtConfig.AI_BASE.z)

	_build_world()
	_build_ball_fx()
	_build_characters()
	_build_ui()

	if opt_smoke:
		print("[SMOKE] READY difficulty=%.2f skin=%d" % [difficulty, opt_skin])
	if opt_smoke or opt_autopilot:
		start_match()


# ================================================================ 命令行

func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--smoke":
			opt_smoke = true
		elif a.begins_with("--shots="):
			opt_shots_dir = a.substr(8)
		elif a == "--autopilot":
			opt_autopilot = true
		elif a.begins_with("--speed="):
			opt_speed = maxi(1, int(a.substr(8)))
		elif a.begins_with("--skin="):
			opt_skin = clampi(int(a.substr(7)), 0, Skins.ALL.size() - 1)
		elif a.begins_with("--difficulty="):
			opt_difficulty = clampf(float(a.substr(13)), 0.0, 1.0)
		elif a.begins_with("--max-sec="):
			opt_max_sec = maxf(1.0, float(a.substr(10)))


func _process(_delta: float) -> void:
	if opt_speed > 0:
		for i in opt_speed:
			_step(FIXED_DT)
			game_time += FIXED_DT
	else:
		var dt := minf(_delta, 0.05)
		_step(dt)
		game_time += dt

	if (opt_smoke or opt_shots_dir != "") and game_time > opt_max_sec:
		if opt_smoke:
			print("[SMOKE] TIMEOUT t=%.1f phase=%s score=%d-%d" % [
				game_time, referee.phase, referee.score["p1"], referee.score["p2"]])
		else:
			print("[SHOTS] TIMEOUT stage=%d t=%.1f" % [shots_stage, game_time])
		get_tree().quit(1)


# ================================================================ 场景构建

func _build_world() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = COL_BG
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("cfe4ff")
	env.ambient_light_energy = 0.55
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = COL_BG
	env.fog_depth_begin = 30.0
	env.fog_depth_end = 90.0
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.light_color = Color("fff1dd")
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)
	sun.look_at_from_position(Vector3(7, 18, -7), Vector3.ZERO, Vector3.UP)

	# ---- 地面: 场外 / 缓冲带 / 球场 (PlaneMesh 天生朝上, 无需旋转)
	# 注意 PlaneMesh.size = (X 宽度, Z 深度): 场地长边 23.77 沿 Z (纵深), 宽 8.23 沿 X。
	# Web 原型此处恰好把两轴写反 (球场成横条, 白线悬在场外), 移植时修正。
	# apron 不得穿过相机近平面: 巨型三角被近平面裁剪后深度插值会出错
	_plane(COL_APRON, Vector2(80, 44), -0.05, Vector3(0, 0, 10), 16)
	_plane(COL_EDGE, Vector2(CourtConfig.COURT_WIDTH + 1.2, CourtConfig.COURT_LENGTH + 1.2), 0.0)
	_plane(COL_COURT, Vector2(CourtConfig.COURT_WIDTH, CourtConfig.COURT_LENGTH), 0.02)

	# ---- 白线 ----
	var hl := CourtConfig.HALF_L
	var hw := CourtConfig.HALF_W
	_line(-hw, -hl, hw, -hl)
	_line(-hw, hl, hw, hl)
	_line(-hw, -hl, -hw, hl)
	_line(hw, -hl, hw, hl)
	_line(-DL, -hl, -DL, hl, 0.04)
	_line(DL, -hl, DL, hl, 0.04)
	_line(-hw, -CourtConfig.SERVICE_LINE, hw, -CourtConfig.SERVICE_LINE)
	_line(-hw, CourtConfig.SERVICE_LINE, hw, CourtConfig.SERVICE_LINE)
	_line(0, -CourtConfig.SERVICE_LINE, 0, CourtConfig.SERVICE_LINE)
	_line(0, -hl, 0, -hl + 0.55, 0.03)
	_line(0, hl, 0, hl - 0.55, 0.03)

	# ---- 球网 ----
	var net := _mesh_box(Vector3(DL * 2 + 1.2, CourtConfig.NET_HEIGHT, 0.02),
		_flat(Color(1, 1, 1, 0.3)), Vector3(0, CourtConfig.NET_HEIGHT / 2, 0))
	net.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh_box(Vector3(DL * 2 + 1.2, 0.06, 0.05),
		_std(Color("ffffff"), 0.6), Vector3(0, CourtConfig.NET_HEIGHT - 0.03, 0))
	for s in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.05
		cyl.bottom_radius = 0.05
		cyl.height = 1.07
		post.mesh = cyl
		post.material_override = _std(Color("d8e4ee"), 0.4)
		post.position = Vector3(s * (DL + 0.6), 0.535, 0)
		add_child(post)

	# ---- 围栏 + 幽灵文字 ----
	for s in [-1.0, 1.0]:
		_mesh_box(Vector3(1.6, 2.4, 46), _std(COL_FENCE, 1.0), Vector3(s * 12.5, 1.2, 0))
	var ghost := Label3D.new()
	ghost.text = "MATCH POINT"
	ghost.font_size = 220
	ghost.pixel_size = 0.006
	ghost.modulate = Color(1, 1, 1, 0.16)
	ghost.rotation = Vector3(-PI / 2, 0, PI)   # 平躺 + 字头朝远端 (玩家视角正读)
	ghost.position = Vector3(0, 0.05, 16.6)
	ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ghost)

	# ---- 相机 ----
	camera = Camera3D.new()
	camera.fov = 62.0
	camera.near = 0.2                       # 默认 0.05 深度精度差, 会放大共面翻转
	camera.position = Vector3(0, 5.1, -13.6)
	add_child(camera)
	camera.make_current()
	camera.look_at(Vector3(0, 1.0, 2.2))


func _plane(color: Color, size: Vector2, y: float, center := Vector3.ZERO, subdivide := 0) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = size
	if subdivide > 0:
		pm.subdivide_width = subdivide
		pm.subdivide_depth = subdivide
	mi.mesh = pm
	var m := _std(color, 0.85)
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED   # 地面无高光, 保持卡通平涂
	mi.material_override = m
	mi.position = Vector3(center.x, y, center.z)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _line(x1: float, z1: float, x2: float, z2: float, w := 0.05) -> void:
	var len := sqrt((x2 - x1) * (x2 - x1) + (z2 - z1) * (z2 - z1))
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	if absf(x2 - x1) >= absf(z2 - z1):
		box.size = Vector3(len, 0.008, w)
	else:
		box.size = Vector3(w, 0.008, len)
	mi.mesh = box
	var m := _std(COL_LINE, 0.6)
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mi.material_override = m
	mi.position = Vector3((x1 + x2) / 2, 0.035, (z1 + z2) / 2)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _mesh_box(size: Vector3, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	return mi


func _std(color: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	return m


func _flat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	if color.a < 0.99:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.disable_receive_shadows = true
	return m


func _build_ball_fx() -> void:
	ball_mesh = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = CourtConfig.BALL_RADIUS
	sm.height = CourtConfig.BALL_RADIUS * 2.0
	ball_mesh.mesh = sm
	ball_mesh.material_override = _std(COL_BALL, 0.55)
	ball_mesh.visible = false
	add_child(ball_mesh)

	ball_shadow = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.09
	cyl.bottom_radius = 0.09
	cyl.height = 0.002
	ball_shadow.mesh = cyl
	ball_shadow.material_override = _flat(Color(0, 0, 0, 0.32))
	ball_shadow.position.y = 0.05
	ball_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ball_shadow.visible = false
	add_child(ball_shadow)

	# 落点指示器 (对手击球后): 外圈 + 半透明内盘
	landing_root = Node3D.new()
	landing_root.visible = false
	add_child(landing_root)
	landing_ring_mat = _flat(COL_GREEN)
	landing_disc_mat = _flat(Color(COL_GREEN, 0.26))
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.34
	torus.outer_radius = 0.44
	ring.mesh = torus
	ring.material_override = landing_ring_mat
	ring.position.y = 0.06
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	landing_root.add_child(ring)
	var disc := MeshInstance3D.new()
	var dcyl := CylinderMesh.new()
	dcyl.top_radius = 0.34
	dcyl.bottom_radius = 0.34
	dcyl.height = 0.004
	disc.mesh = dcyl
	disc.material_override = landing_disc_mat
	disc.position.y = 0.055
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	landing_root.add_child(disc)

	# 击球时机光圈 (玩家脚下)
	reticle_mat = _flat(COL_GREEN)
	reticle_mesh = MeshInstance3D.new()
	var rtorus := TorusMesh.new()
	rtorus.inner_radius = 0.5
	rtorus.outer_radius = 0.62
	reticle_mesh.mesh = rtorus
	reticle_mesh.material_override = reticle_mat
	reticle_mesh.position.y = 0.06
	reticle_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	reticle_mesh.visible = false
	add_child(reticle_mesh)


func _build_characters() -> void:
	if p1.char != null:
		p1.char.queue_free()
		p2.char.queue_free()
	var idle_scene: PackedScene = load("res://assets/anims/idle.fbx")
	var clips := {
		"run": AnimeCharacter.extract_clip("res://assets/anims/run_forward.fbx", true),
		"forehand": AnimeCharacter.extract_clip("res://assets/anims/forehand_swing.fbx", false),
		"backhand": AnimeCharacter.extract_clip("res://assets/anims/backhand_swing.fbx", false),
		"victory": AnimeCharacter.extract_clip("res://assets/anims/victory.fbx", false),
	}
	p1.char = _make_char(idle_scene, Skins.ALL[opt_skin], clips)
	p2.char = _make_char(idle_scene, Skins.ALL[(opt_skin + 1) % Skins.ALL.size()], clips)
	p2.char.rotation.y = PI                       # 对手面向 -Z


func _make_char(scene: PackedScene, skin: Dictionary, clips: Dictionary) -> AnimeCharacter:
	var ch := AnimeCharacter.new()
	add_child(ch)
	ch.build(scene, skin, clips)
	return ch


# ================================================================ UI

func _load_font() -> FontFile:
	for p in ["C:/Windows/Fonts/msyh.ttc", "C:/Windows/Fonts/simhei.ttf"]:
		if FileAccess.file_exists(p):
			var f := FontFile.new()
			if f.load_dynamic_font(p) == OK:
				return f
	return null


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	ui_font = _load_font()

	hud_root = _full_rect(layer)
	hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.visible = false

	# ---- 转播比分条 ----
	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_top = 10.0
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 10)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(bar)
	dot_p1 = _label("●", 18, COL_GREEN, bar)
	_label("你", 20, Color.WHITE, bar)
	lbl_score_p1 = _label("0", 28, Color.WHITE, bar)
	_label("—", 22, Color(1, 1, 1, 0.5), bar)
	lbl_score_p2 = _label("0", 28, Color.WHITE, bar)
	_label("对手", 20, Color.WHITE, bar)
	dot_p2 = _label("●", 18, COL_GREEN, bar)
	for d in [dot_p1, dot_p2]:
		d.modulate.a = 0.2

	lbl_phase = _label("", 17, Color(1, 1, 1, 0.65), hud_root)
	lbl_phase.position = Vector2(0, 50)
	lbl_phase.size = Vector2(540, 26)
	lbl_phase.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	lbl_toast = _label("", 25, Color.WHITE, hud_root)
	lbl_toast.position = Vector2(0, 150)
	lbl_toast.size = Vector2(540, 40)
	lbl_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_toast.visible = false

	lbl_hint = _label("", 19, Color(1, 1, 1, 0.9), hud_root)
	lbl_hint.position = Vector2(0, 806)
	lbl_hint.size = Vector2(540, 40)
	lbl_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	if not auto_play:
		_build_dpad()

	# ---- 开始界面 ----
	start_overlay = _full_rect(layer)
	var dim := ColorRect.new()
	dim.color = Color(COL_BG, 0.92)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	start_overlay.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	start_overlay.add_child(cc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	cc.add_child(vb)

	var title := _label("ACEMATCH", 44, Color.WHITE, vb)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sub := _label("卡通 3D 网球对决 · 先得 7 分", 17, Color(1, 1, 1, 0.65), vb)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_label("选择角色", 15, Color(1, 1, 1, 0.55), vb)
	var skin_group := ButtonGroup.new()
	var skin_row := HBoxContainer.new()
	skin_row.alignment = BoxContainer.ALIGNMENT_CENTER
	skin_row.add_theme_constant_override("separation", 8)
	vb.add_child(skin_row)
	for i in Skins.ALL.size():
		var b := Button.new()
		b.text = Skins.ALL[i]["label"]
		b.custom_minimum_size = Vector2(96, 46)
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = true
		b.button_group = skin_group
		b.button_pressed = i == opt_skin
		b.pressed.connect(_on_skin_selected.bind(i))
		skin_row.add_child(b)

	_label("难度", 15, Color(1, 1, 1, 0.55), vb)
	var diff_row := HBoxContainer.new()
	diff_row.alignment = BoxContainer.ALIGNMENT_CENTER
	diff_row.add_theme_constant_override("separation", 8)
	vb.add_child(diff_row)
	var diff_group := ButtonGroup.new()
	var defs := [["简单", 0.3], ["普通", 0.55], ["困难", 0.8]]
	for i in defs.size():
		var b2 := Button.new()
		b2.text = defs[i][0]
		b2.custom_minimum_size = Vector2(80, 38)
		b2.focus_mode = Control.FOCUS_NONE
		b2.toggle_mode = true
		b2.button_group = diff_group
		b2.button_pressed = absf(defs[i][1] - difficulty) < 0.13
		b2.pressed.connect(_on_diff_selected.bind(defs[i][1]))
		diff_row.add_child(b2)

	var btn_start := Button.new()
	btn_start.text = "开始比赛"
	btn_start.custom_minimum_size = Vector2(200, 58)
	btn_start.focus_mode = Control.FOCUS_NONE
	btn_start.pressed.connect(start_match)
	var bwrap := CenterContainer.new()
	bwrap.add_child(btn_start)
	vb.add_child(bwrap)
	var ops := _label("操作: 滑屏/方向键移动 · 上滑或空格击球", 14, Color(1, 1, 1, 0.45), vb)
	ops.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# ---- 结算界面 ----
	end_overlay = _full_rect(layer)
	var dim2 := ColorRect.new()
	dim2.color = Color(COL_BG, 0.82)
	dim2.set_anchors_preset(Control.PRESET_FULL_RECT)
	end_overlay.add_child(dim2)
	var cc2 := CenterContainer.new()
	cc2.set_anchors_preset(Control.PRESET_FULL_RECT)
	end_overlay.add_child(cc2)
	var vb2 := VBoxContainer.new()
	vb2.add_theme_constant_override("separation", 16)
	vb2.alignment = BoxContainer.ALIGNMENT_CENTER
	cc2.add_child(vb2)
	lbl_end_title = _label("", 42, Color.WHITE, vb2)
	lbl_end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_end_score = _label("", 26, Color(1, 1, 1, 0.8), vb2)
	lbl_end_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var btn_again := Button.new()
	btn_again.text = "再来一局"
	btn_again.custom_minimum_size = Vector2(180, 52)
	btn_again.focus_mode = Control.FOCUS_NONE
	btn_again.pressed.connect(start_match)
	var awrap := CenterContainer.new()
	awrap.add_child(btn_again)
	vb2.add_child(awrap)
	end_overlay.visible = false


func _full_rect(parent: Node) -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(c)
	return c


func _label(text: String, size: int, color: Color, parent: Node) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if ui_font != null:
		l.add_theme_font_override("font", ui_font)
	parent.add_child(l)
	return l


func _build_dpad() -> void:
	var dp := Control.new()
	dp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dp.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	dp.offset_left = 20.0
	dp.offset_top = -210.0
	dp.offset_right = 20.0 + 174.0
	dp.offset_bottom = -30.0
	dp.modulate.a = 0.55
	hud_root.add_child(dp)
	var defs := [
		[Vector2(58, 0), "▲", Vector2(0, 1)],
		[Vector2(0, 58), "◀", Vector2(-1, 0)],
		[Vector2(116, 58), "▶", Vector2(1, 0)],
		[Vector2(58, 116), "▼", Vector2(0, -1)],
	]
	for d in defs:
		var b := Button.new()
		b.text = d[1]
		b.position = d[0]
		b.size = Vector2(58, 58)
		b.focus_mode = Control.FOCUS_NONE
		b.button_down.connect(_dpad_press.bind(d[2]))
		b.button_up.connect(_dpad_release.bind(d[2]))
		dp.add_child(b)


func _dpad_press(d: Vector2) -> void:
	dpad_vec += d


func _dpad_release(d: Vector2) -> void:
	dpad_vec -= d


func _on_skin_selected(idx: int) -> void:
	opt_skin = idx
	_build_characters()


func _on_diff_selected(d: float) -> void:
	difficulty = d


# ================================================================ 比赛流程

func start_match() -> void:
	referee.reset()
	referee.start_match()
	started = true
	victory_played = false
	start_overlay.visible = false
	end_overlay.visible = false
	hud_root.visible = true
	if opt_smoke:
		print("[SMOKE] START server=%s" % referee.server)
	_sync_score()
	_setup_serve(referee.server)


func _total_points() -> int:
	return referee.score["p1"] + referee.score["p2"]


func _setup_serve(server: String) -> void:
	awaiting_serve = {"server": server, "done": false}
	serve_side = -1 if _total_points() % 2 == 0 else 1
	var dir := -1.0 if server == "p1" else 1.0
	toss_pos = Vector3(serve_side * 1.4, CourtConfig.SERVE_TOSS_Y, dir * CourtConfig.SERVE_TOSS_Z)
	ball.pos = toss_pos
	ball.vel = Vector3.ZERO
	ball.spin = "Flat"
	ball_active = false
	last_bounce_side = 0
	ai_serve_timer = 1.15 + randf() * 0.7
	landing_root.visible = false
	reticle_mesh.visible = false
	if server == "p1":
		p1.move_target = Vector3(serve_side * 1.7, 0, -9.8)
		p2.move_target = Vector3(-serve_side * 1.4, 0, 8.6)
	else:
		p2.move_target = Vector3(serve_side * 1.7, 0, 9.8)
		p1.move_target = Vector3(-serve_side * 1.4, 0, -8.6)
	p1.has_target = true
	p2.has_target = true
	if opt_smoke:
		print("[SMOKE] SERVE server=%s attempt=%d side=%d" % [server, referee.serve_attempt, serve_side])


# ---- 滑屏路由: 发球 或 回合击球 ----
func _route_swipe(wdx: float, wdy: float, wdt: float, wsamples: Array) -> void:
	if not started or auto_play:
		return
	var mapped := Strike.map_swipe(wdx, wdy, wdt, wsamples)
	if referee.phase == "serve" and awaiting_serve != null and not awaiting_serve.done and referee.server == "p1":
		_exec_serve(mapped)
	elif referee.phase == "rally":
		_try_strike(p1, mapped)


func _exec_serve(mapped: Dictionary) -> void:
	var from := toss_pos
	var r := Strike.serve_from_swipe(mapped, serve_side, from, 1)
	_launch(p1, from, r, "good", "serve")
	awaiting_serve.done = true


func _launch(actor: Actor, from: Vector3, r: Dictionary, tier: String, kind := "") -> void:
	# 动画: 用击球前球位判正/反手 (launch 会覆写球位, 必须先算)
	var swing_kind := kind
	if swing_kind == "":
		var right: Vector3 = -actor.char.global_basis.x
		var d3 := ball.pos - actor.char.global_position
		var lateral := Vector2(right.x, right.z).dot(Vector2(d3.x, d3.z))
		swing_kind = "forehand" if lateral > 0.0 else "backhand"
	ball.pos = from
	ball.vel = r["v"]
	ball.spin = r["spin"]
	ball_active = true
	last_striker = actor.id
	last_bounce_side = 0
	has_bounced_shot = false
	shot_id += 1
	struck_shot_ids[actor.id] = shot_id
	landing_root.visible = false
	actor.char.play_action(swing_kind, 1.0 if kind == "serve" else 1.5)
	if actor.id == "p2":
		var pred := BallPhysics.predict_landing(ball)
		if not pred.is_empty() and not pred["net"]:
			_show_landing(pred["pos"].x, pred["pos"].z, pred["in_bounds"])


func _try_strike(actor: Actor, mapped: Dictionary) -> bool:
	if struck_shot_ids[actor.id] == shot_id:
		return false                        # 同一球只击一次
	var tier := _tier_at(actor)
	if tier == "":
		return false
	var dir := 1.0 if actor.id == "p1" else -1.0
	var from := Vector3(
		actor.pos.x + 0.3 * dir,
		clampf(ball.pos.y, 0.7, 2.4),
		actor.pos.z + 0.55 * dir)
	var r: Dictionary
	if tier == "dive":
		var weak := {"power": 0.3, "deflection": mapped["deflection"] * 0.5, "spin": "Flat"}
		r = Strike.stroke_from_swipe(weak, from, int(dir))
	else:
		r = Strike.stroke_from_swipe(mapped, from, int(dir))
		var v: Vector3 = r["v"]
		if tier == "perfect":
			v *= CourtConfig.PERFECT_BONUS
		else:
			v.x *= 1.0 + (randf() - 0.5) * 0.04
			v.z *= 1.0 + (randf() - 0.5) * 0.04
		r["v"] = v
	_launch(actor, from, r, "good" if tier == "dive" else tier)
	return true


## 击球时机三档: <0.8 Perfect / 0.8~1.8 Good / 1.8~2.5 Dive, 空串=不可击
func _tier_at(actor: Actor) -> String:
	if not ball_active or ball.pos.y > 3.1:
		return ""
	var dir := 1.0 if actor.id == "p1" else -1.0
	var behind := (ball.pos.z - actor.pos.z) * dir < -1.3   # 球已在身后
	var over_net := ball.pos.z * dir > 0.2                  # 球仍在对方半场
	if behind or over_net:
		return ""
	var px := actor.pos.x + 0.25 * dir
	var pz := actor.pos.z + 0.5 * dir
	var d := Vector2(ball.pos.x - px, ball.pos.z - pz).length()
	if d < CourtConfig.PERFECT_DIST:
		return "perfect"
	if d < CourtConfig.GOOD_DIST:
		return "good"
	if d <= CourtConfig.DIVE_DIST:
		return "dive"
	return ""


# ================================================================ 事件判定

func _on_net_hit() -> void:
	if awaiting_serve != null:
		_serve_fault()
	elif referee.phase == "rally":
		_award_point(referee.other(last_striker), "net")


func _serve_fault() -> void:
	var server: String = awaiting_serve["server"]
	awaiting_serve = null
	var res := referee.on_serve_fault(server)
	if res.has("phase"):
		# 双误: referee 已判分
		_point_awarded(res.get("winner", referee.other(server)), "doubleFault")
	else:
		if opt_smoke:
			print("[SMOKE] FAULT server=%s" % server)
		_toast("发球失误", "bad")
		_setup_serve(server)


func _resolve_serve_bounce(at: Vector3) -> void:
	has_bounced_shot = true
	if BallPhysics.check_serve_box(at.x, at.z, serve_side):
		referee.on_serve_in(awaiting_serve["server"])
		awaiting_serve = null
		last_bounce_side = signi(at.z)
	else:
		_serve_fault()


func _resolve_rally_bounce(at: Vector3) -> void:
	has_bounced_shot = true
	if not BallPhysics.check_in_bounds(at.x, at.z):
		_award_point(referee.other(last_striker), "out")
		return
	var side := signi(at.z)
	if side == last_bounce_side:
		_award_point(last_striker, "doubleBounce")
	else:
		last_bounce_side = side


func _award_point(winner: String, reason: String) -> void:
	var res := referee.on_rally_end(winner, reason)
	if res.is_empty():
		return
	_point_awarded(winner, reason)


func _point_awarded(winner: String, reason: String) -> void:
	ball_active = false
	landing_root.visible = false
	reticle_mesh.visible = false
	var is_p1 := winner == "p1"
	_toast(_reason_text(reason, is_p1), "good" if is_p1 else "bad")
	point_end_timer = 1.15 if referee.phase == "match_end" else 1.5
	if opt_smoke:
		print("[SMOKE] POINT winner=%s reason=%s score=%d-%d t=%.1f" % [
			winner, reason, referee.score["p1"], referee.score["p2"], game_time])


func _reason_text(reason: String, player_won: bool) -> String:
	match reason:
		"out":
			return "对手出界，得分！" if player_won else "出界，对手得分"
		"net":
			return "对手下网，得分！" if player_won else "下网，对手得分"
		"doubleBounce":
			return "对手没接住，得分！" if player_won else "没接住，对手得分"
		"doubleFault":
			return "对手双误，得分！" if player_won else "双误，对手得分"
	return "得分！"


func _finish_point() -> void:
	if referee.phase == "match_end":
		var win := referee.match_winner == "p1"
		lbl_end_title.text = "胜利！" if win else "惜败"
		lbl_end_title.add_theme_color_override("font_color", COL_GREEN if win else COL_RED)
		lbl_end_score.text = "%d — %d" % [referee.score["p1"], referee.score["p2"]]
		end_overlay.visible = true
		if not victory_played:
			victory_played = true
			var wch := p1.char if win else p2.char
			wch.play_action("victory")
		if opt_smoke:
			print("[SMOKE] MATCH_END winner=%s score=%d-%d t=%.1f" % [
				referee.match_winner, referee.score["p1"], referee.score["p2"], game_time])
			get_tree().quit(0)
	else:
		referee.next_serve()
		_setup_serve(referee.server)


# ================================================================ 每帧步进

func _step(dt: float) -> void:
	if started:
		if auto_play:
			_auto_pilot(dt)
		else:
			_player_update(dt)
		_ai_update(dt)
		_step_ball(dt)

		if referee.phase == "point_end" or referee.phase == "match_end":
			point_end_timer -= dt
			if point_end_timer <= 0.0:
				_finish_point()

	if toast_timer > 0.0:
		toast_timer -= dt
		if toast_timer <= 0.0:
			lbl_toast.visible = false

	# 表现层同步
	p1.char.position = Vector3(p1.pos.x, 0, p1.pos.z)
	p2.char.position = Vector3(p2.pos.x, 0, p2.pos.z)
	for a: Actor in [p1, p2]:
		a.char.move_speed = maxf(a.char.move_speed - dt * 2.2, 0.0)
		a.char.update_anim()
	ball_mesh.position = ball.pos
	ball_mesh.visible = awaiting_serve != null or ball_active
	_fx_update(dt)
	_update_reticle()
	_update_hint()
	_camera_update(dt)
	_sync_phase()

	if opt_shots_dir != "" and shots_stage < 5:
		_shots_tick(dt)


func _mark_move(actor: Actor, v: float) -> void:
	actor.char.move_speed = maxf(actor.char.move_speed, v)


func _move_actor_toward(actor: Actor, target: Vector3, speed: float, dt: float) -> void:
	var dx := target.x - actor.pos.x
	var dz := target.z - actor.pos.z
	var dist := sqrt(dx * dx + dz * dz)
	if dist < 0.06:
		_mark_move(actor, 0.0)
		return
	var step := minf(speed * dt, dist)
	actor.pos.x += dx / dist * step
	actor.pos.z += dz / dist * step
	_mark_move(actor, 1.0)


## 屏幕空间移动向量 (x 右正, y 上正); 世界换算: wx=-x, wz=+y
func _screen_dir() -> Vector2:
	var kv := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var v := Vector2(kv.x, -kv.y) + dpad_vec
	if v.length() > 1.0:
		v = v.normalized()
	return v


## 玩家移动 (手动输入优先; 否则自动跑位 + 击球后 0.6x 回位)
func _player_update(dt: float) -> void:
	var a := p1
	var sd := _screen_dir()
	if sd.length() > 0.25 and referee.phase != "point_end" and referee.phase != "match_end":
		a.pos += Vector3(-sd.x, 0, sd.y) * CourtConfig.PLAYER_SPEED * dt
		a.pos.x = clampf(a.pos.x, -4.6, 4.6)
		a.pos.z = clampf(a.pos.z, -11.4, -2.8)
		_mark_move(a, 1.0)
		return

	var target := Vector3.ZERO
	var has_target := false
	var factor := 1.0
	# 对方发球在空中时即预判落点跑位
	var serve_incoming: bool = referee.phase == "serve" and awaiting_serve != null \
		and awaiting_serve.done and referee.server == "p2"

	if referee.phase == "serve" and not serve_incoming:
		if p1.has_target:
			target = p1.move_target
			has_target = true
		else:
			target = Vector3(serve_side * 1.7, 0, -9.8) if referee.server == "p1" \
				else Vector3(-serve_side * 1.4, 0, -8.6)
			has_target = true
	elif (referee.phase == "rally" or serve_incoming) and ball_active \
			and (ball.vel.z < 0 or ball.pos.z < 0):
		if p1.landing_shot != shot_id:
			p1.landing_shot = shot_id
			p1.landing = BallPhysics.predict_landing(ball)
		if not p1.landing.is_empty() and not p1.landing["net"] and p1.landing["in_bounds"]:
			target = Vector3(
				clampf(p1.landing["pos"].x, -3.9, 3.9),
				0,
				clampf(p1.landing["pos"].z + 0.6, -10.4, -4.0))
			has_target = true
	elif referee.phase != "point_end" and referee.phase != "match_end":
		target = CourtConfig.PLAYER_BASE
		has_target = true
		factor = CourtConfig.RECOVER_SPEED

	if has_target:
		_move_actor_toward(a, target, CourtConfig.PLAYER_SPEED * factor, dt)
	else:
		_mark_move(a, 0.0)


## AI: 跑位 + 回球 + 发球(含失误概率)
func _ai_update(dt: float) -> void:
	var ai := p2
	var serve_incoming: bool = referee.phase == "serve" and awaiting_serve != null \
		and awaiting_serve.done and referee.server == "p1"

	if referee.phase == "serve" and referee.server == "p2" and not serve_incoming:
		if ai.has_target:
			_move_actor_toward(ai, ai.move_target, CourtConfig.PLAYER_SPEED, dt)
		if not awaiting_serve.done:
			ai_serve_timer -= dt
			if ai_serve_timer <= 0.0:
				_ai_serve()
		return

	if (referee.phase == "rally" or serve_incoming) and ball_active \
			and (ball.vel.z > 0 or ball.pos.z > 0):
		if ai.landing_shot != shot_id:
			ai.landing_shot = shot_id
			ai.landing = BallPhysics.predict_landing(ball)
			ai.has_struck = false
			ai.strike_delay = 0.08 + randf() * 0.08
		var has_target := false
		var target := Vector3.ZERO
		if not ai.landing.is_empty() and not ai.landing["net"] and ai.landing["in_bounds"]:
			target = Vector3(
				clampf(ai.landing["pos"].x, -3.9, 3.9),
				0,
				clampf(absf(ai.landing["pos"].z) - 0.7, 3.5, 10.2))
			has_target = true
		if has_target:
			_move_actor_toward(ai, target, CourtConfig.PLAYER_SPEED, dt)

		# 击球窗口: 球接近时提前启动反应计时, 弹起瞬间挥拍 (接发不抢攻)
		if not ai.has_struck:
			var d := Vector2(ball.pos.x - ai.pos.x, ball.pos.z - ai.pos.z).length()
			if d < 1.3:
				ai.strike_delay -= dt
				if ai.strike_delay <= 0.0 and referee.phase == "rally" and d < 1.8 and ball.pos.y < 3.1:
					_ai_strike()
	elif referee.phase == "serve":
		if ai.has_target:
			_move_actor_toward(ai, ai.move_target, CourtConfig.PLAYER_SPEED, dt)
	elif referee.phase != "point_end" and referee.phase != "match_end":
		_move_actor_toward(ai, CourtConfig.AI_BASE, CourtConfig.PLAYER_SPEED * CourtConfig.RECOVER_SPEED, dt)
	else:
		_mark_move(ai, 0.0)


func _ai_serve() -> void:
	var from := toss_pos
	var mapped := {
		"power": 0.55 + randf() * 0.3,
		"deflection": (randf() * 2.0 - 1.0) * 0.35,
		"spin": "Flat",
	}
	var r := Strike.serve_from_swipe(mapped, serve_side, from, -1)
	# 失误概率随难度下降
	if randf() < (1.0 - difficulty) * 0.16:
		if randf() < 0.6:
			var t := Vector3(r["target"].x, 0, -12.4)     # 出界(过长)
			r["target"] = t
			r["v"] = BallPhysics.solve_launch_corrected(from, t, r["T"])
		else:
			var v: Vector3 = r["v"]
			v.y = 0.4                                     # 下网(平飞)
			r["v"] = v
	_launch(p2, from, r, "good", "serve")
	awaiting_serve.done = true


func _ai_strike() -> void:
	var ai := p2
	ai.has_struck = true
	if randf() < (1.0 - difficulty) * 0.1:
		return                                            # 挥空
	var from := Vector3(ai.pos.x - 0.3, clampf(ball.pos.y, 0.7, 2.4), ai.pos.z - 0.55)
	var r := Strike.ai_stroke(p1.pos, difficulty, from, -1)
	if randf() < 0.2:
		var v: Vector3 = r["v"]
		v *= CourtConfig.PERFECT_BONUS
		r["v"] = v
	_launch(p2, from, r, "good")


## 自动演示/调试: 玩家侧也由 AI 逻辑驱动
func _auto_pilot(dt: float) -> void:
	var a := p1
	var serve_incoming: bool = referee.phase == "serve" and awaiting_serve != null \
		and awaiting_serve.done and referee.server == "p2"

	if referee.phase == "serve" and referee.server == "p1" and not serve_incoming:
		if a.has_target:
			_move_actor_toward(a, a.move_target, CourtConfig.PLAYER_SPEED, dt)
		if not awaiting_serve.done:
			ai_serve_timer -= dt
			if ai_serve_timer <= 0.0:
				var from := toss_pos
				var mapped := {
					"power": 0.58 + randf() * 0.25,
					"deflection": (randf() * 2.0 - 1.0) * 0.4,
					"spin": "Flat",
				}
				var r := Strike.serve_from_swipe(mapped, serve_side, from, 1)
				_launch(p1, from, r, "good", "serve")
				awaiting_serve.done = true
		return

	if referee.phase == "serve" and not serve_incoming:
		if a.has_target:
			_move_actor_toward(a, a.move_target, CourtConfig.PLAYER_SPEED, dt)
		return

	if (referee.phase == "rally" or serve_incoming) and ball_active \
			and (ball.vel.z < 0 or ball.pos.z < 0):
		if a.landing_shot != shot_id:
			a.landing_shot = shot_id
			a.landing = BallPhysics.predict_landing(ball)
			a.has_struck = false
			a.strike_delay = 0.08 + randf() * 0.08
		var has_target := false
		var target := Vector3.ZERO
		if not a.landing.is_empty() and not a.landing["net"] and a.landing["in_bounds"]:
			target = Vector3(
				clampf(a.landing["pos"].x, -3.9, 3.9),
				0,
				clampf(a.landing["pos"].z + 0.6, -10.4, -4.0))
			has_target = true
		if has_target:
			_move_actor_toward(a, target, CourtConfig.PLAYER_SPEED, dt)

		if not a.has_struck:
			var d := Vector2(ball.pos.x - a.pos.x, ball.pos.z - a.pos.z).length()
			if d < 1.3:
				a.strike_delay -= dt
				if a.strike_delay <= 0.0 and referee.phase == "rally" and d < 1.8 and ball.pos.y < 3.1:
					a.has_struck = true
					if randf() < (1.0 - difficulty) * 0.08:
						return                            # 挥空
					var from := Vector3(a.pos.x + 0.3, clampf(ball.pos.y, 0.7, 2.4), a.pos.z + 0.55)
					var r := Strike.ai_stroke(p2.pos, difficulty, from, 1)
					_launch(p1, from, r, "good")
	elif referee.phase != "point_end" and referee.phase != "match_end":
		_move_actor_toward(a, CourtConfig.PLAYER_BASE, CourtConfig.PLAYER_SPEED * CourtConfig.RECOVER_SPEED, dt)
	else:
		_mark_move(a, 0.0)


## 球物理步进 + 事件
func _step_ball(dt: float) -> void:
	if not ball_active:
		return
	var steps := maxi(1, roundi(dt / STEP))
	var h := dt / steps
	for i in steps:
		if not ball_active:
			return
		var prev_z := ball.pos.z
		var prev_y := ball.pos.y
		var ev := BallPhysics.integrate(ball, h, true)
		# 过网判定
		if (prev_z <= 0.0 and ball.pos.z > 0.0) or (prev_z >= 0.0 and ball.pos.z < 0.0):
			var f := prev_z / (prev_z - ball.pos.z)
			var y_at := prev_y + f * (ball.pos.y - prev_y)
			if y_at < CourtConfig.NET_HEIGHT:
				_on_net_hit()
				return
		# 落地判定
		if not ev.is_empty():
			if awaiting_serve != null:
				_resolve_serve_bounce(ev["at"])
			elif referee.phase == "rally":
				_resolve_rally_bounce(ev["at"])
		# 直接飞出场地
		if absf(ball.pos.z) > CourtConfig.HALF_L + 3.5 or absf(ball.pos.x) > 8.0 or ball.pos.y < -2.0:
			if awaiting_serve != null:
				_serve_fault()
			elif referee.phase == "rally":
				# 未落地飞出 → 击球方出界; 已合法落地后飞出 → 接球方没接到
				if has_bounced_shot:
					_award_point(last_striker, "doubleBounce")
				else:
					_award_point(referee.other(last_striker), "out")
			return


# ================================================================ 特效 / 相机 / HUD

func _show_landing(x: float, z: float, in_bounds: bool) -> void:
	landing_root.visible = true
	landing_root.position = Vector3(x, 0, z)
	landing_root.scale = Vector3.ONE
	landing_t = 0.0
	var c := COL_GREEN if in_bounds else COL_RED
	landing_ring_mat.albedo_color = c
	landing_disc_mat.albedo_color = Color(c, 0.26)


func _show_reticle(x: float, z: float, tier: String) -> void:
	reticle_mesh.visible = true
	reticle_mesh.position = Vector3(x, 0.06, z)
	reticle_t = 0.0
	reticle_mat.albedo_color = COL_GREEN if tier == "perfect" \
		else (COL_YELLOW if tier == "good" else COL_ORANGE)


func _update_reticle() -> void:
	if referee.phase == "rally" and ball_active and ball.pos.z < 0:
		var d := Vector2(ball.pos.x - p1.pos.x, ball.pos.z - p1.pos.z).length()
		if d < 3.4:
			var tier := _tier_at(p1)
			if tier != "":
				_show_reticle(p1.pos.x, p1.pos.z, tier)
				return
	reticle_mesh.visible = false


func _fx_update(dt: float) -> void:
	# 球影 (深度感知)
	if ball_active:
		ball_shadow.visible = true
		ball_shadow.position = Vector3(ball.pos.x, 0.05, ball.pos.z)
		var k := minf(1.0, maxf(ball.pos.y, 0.05) / 4.0)
		var s := 1.0 + k * 2.2
		ball_shadow.scale = Vector3(s, 1, s)
	else:
		ball_shadow.visible = false
	# 脉冲
	if landing_root.visible:
		landing_t += dt
		var ls := 1.0 + 0.09 * sin(landing_t * 7.0)
		landing_root.scale = Vector3(ls, 1, ls)
		landing_root.rotation.y += dt * 1.4
	if reticle_mesh.visible:
		reticle_t += dt
		var rs := 1.0 + 0.12 * sin(reticle_t * 10.0)
		reticle_mesh.scale = Vector3(rs, 1, rs)


func _camera_update(dt: float) -> void:
	var k := 1.0 - exp(-dt * 3.2)
	camera.position.x += (p1.pos.x * 0.3 - camera.position.x) * k
	var ty := 5.1 + clampf((ball.pos.y - 2.5) * 0.14, 0.0, 1.1)
	camera.position.y += (ty - camera.position.y) * (1.0 - exp(-dt * 2.2))
	camera.position.z = -13.6
	camera.look_at(Vector3(p1.pos.x * 0.16, 1.0, 2.2))
	var fov_target := 62.0 + clampf((ball.pos.y - 2.8) * 0.8, 0.0, 5.0)
	if absf(camera.fov - fov_target) > 0.01:
		camera.fov += (fov_target - camera.fov) * (1.0 - exp(-dt * 3.0))


func _update_hint() -> void:
	var text := ""
	if not auto_play:
		if referee.phase == "serve" and awaiting_serve != null and not awaiting_serve.done \
				and referee.server == "p1":
			text = "向上滑动发球（或按空格）"
		elif referee.phase == "rally" and ball_active and ball.pos.z < 0:
			var d := Vector2(ball.pos.x - p1.pos.x, ball.pos.z - p1.pos.z).length()
			if d < 4.5 and d > 0.4:
				text = "滑动击球！（或按空格）"
	if text != hint_key:
		hint_key = text
		lbl_hint.text = text
		lbl_hint.visible = text != ""


func _toast(text: String, kind: String) -> void:
	lbl_toast.text = text
	var c := Color.WHITE
	if kind == "good":
		c = COL_GREEN
	elif kind == "bad":
		c = COL_RED
	lbl_toast.add_theme_color_override("font_color", c)
	lbl_toast.visible = true
	toast_timer = 1.5


func _sync_phase() -> void:
	var key := "%s|%s|%d|%d-%d" % [referee.phase, referee.server, referee.serve_attempt,
		referee.score["p1"], referee.score["p2"]]
	if key != phase_key:
		phase_key = key
		lbl_phase.text = _phase_text()
		_sync_score()


func _phase_text() -> String:
	if referee.phase == "serve":
		if referee.server == "p1":
			return "你的发球" if referee.serve_attempt == 1 else "二发"
		return "对手发球" if referee.serve_attempt == 1 else "对手二发"
	if referee.phase == "rally":
		return "回合中"
	if referee.phase == "match_end":
		return "比赛结束"
	return ""


func _sync_score() -> void:
	lbl_score_p1.text = str(referee.score["p1"])
	lbl_score_p2.text = str(referee.score["p2"])
	dot_p1.modulate.a = 1.0 if referee.server == "p1" else 0.2
	dot_p2.modulate.a = 1.0 if referee.server == "p2" else 0.2
	lbl_score_p1.add_theme_color_override("font_color",
		COL_GREEN if referee.score["p1"] > referee.score["p2"] else Color.WHITE)
	lbl_score_p2.add_theme_color_override("font_color",
		COL_GREEN if referee.score["p2"] > referee.score["p1"] else Color.WHITE)


# ================================================================ 输入

func _unhandled_input(event: InputEvent) -> void:
	if auto_play:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_swipe_begin(event.position)
		else:
			_swipe_end(event.position)
	elif event is InputEventMouseMotion and swipe_down != null:
		_swipe_sample(event.position)
	elif event is InputEventScreenTouch:
		if event.pressed:
			_swipe_begin(event.position)
		else:
			_swipe_end(event.position)
	elif event is InputEventScreenDrag and swipe_down != null:
		_swipe_sample(event.position)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			_keyboard_strike()


func _swipe_begin(p: Vector2) -> void:
	swipe_down = {"x0": p.x, "y0": p.y, "t0": Time.get_ticks_msec(), "samples": []}


func _swipe_sample(p: Vector2) -> void:
	var samples: Array = swipe_down["samples"]
	samples.append(p)
	if samples.size() > 30:
		samples.pop_front()


func _swipe_end(p: Vector2) -> void:
	if swipe_down == null:
		return
	var dt := maxf((Time.get_ticks_msec() - swipe_down["t0"]) / 1000.0, 0.016)
	var dx: float = p.x - swipe_down["x0"]
	var dy: float = -(p.y - swipe_down["y0"])          # 屏幕 y 向下为正 → 转为向上为正
	var samples: Array = swipe_down["samples"]
	samples.append(p)
	swipe_down = null
	# 屏幕右 = 世界 -X: 输入层翻转 dx 与样本 x, 纯逻辑层 (Strike) 保持不动
	var wsamples: Array = []
	for s: Vector2 in samples:
		wsamples.append(Vector2(-s.x, s.y))
	_route_swipe(-dx, dy, dt, wsamples)


func _keyboard_strike() -> void:
	# 空格 = 中速直线击球/发球
	_route_swipe(0.0, 1000.0, 0.22, [Vector2(0, 0), Vector2(0, 500), Vector2(0, 1000)])


# ================================================================ 截图模式

func _shots_tick(dt: float) -> void:
	match shots_stage:
		0:
			# 先截图后开局: 同帧改可见性会污染当前帧渲染, 隔一帧再 start_match
			shots_timer += dt
			if shots_timer >= 0.6:
				if not captured01:
					captured01 = true
					_capture("01_menu.png")
				elif not shot_busy:
					start_match()
					shots_stage = 1
					shots_timer = 0.0
		1:
			if referee.phase == "serve" and awaiting_serve != null \
					and not awaiting_serve.done and referee.server == "p1":
				shots_timer += dt
				if shots_timer >= 0.7:
					_capture("02_serve.png")
					shots_stage = 2
					shots_timer = 0.0
		2:
			if referee.phase == "rally" and ball_active \
					and ball.pos.z < 2.0 and ball.pos.z > -10.5:
				shots_timer += dt
				if shots_timer >= 0.35:
					_capture("03_rally.png")
					shots_stage = 3
					shots_timer = 0.0
			else:
				shots_timer = 0.0
		3:
			if referee.phase == "point_end":
				shots_timer += dt
				if shots_timer >= 0.5:
					_capture("04_point.png")
					shots_stage = 4
					shots_timer = 0.0
		4:
			if referee.phase == "match_end":
				shots_timer += dt
				if shots_timer >= 1.3:
					_capture("05_result.png")
					shots_stage = 5


func _capture(path: String) -> void:
	if shot_busy:
		return
	shot_busy = true
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(opt_shots_dir.path_join(path))
	print("[SHOTS] saved ", path)
	shot_busy = false
	if path == "05_result.png":
		get_tree().quit(0)
