class_name AnimeCharacter
extends Node3D
## 动漫风格角色: Mixamo 骨架 (FBX 导入) + 程序化卡通"纸娃娃"部件 + Toon 着色。
## 动画: idle/run/forehand/backhand/victory 来自本地 Mixamo mocap FBX,
##       serve 为骨架上程序化生成的关键帧 (世界空间姿态增量 + FK)。
## 面向前方 +Z; 玩家默认朝向 +Z, 对手由 main 旋转 180°。

signal swing_finished

var skeleton: Skeleton3D
var anim: AnimationPlayer
var skin: Dictionary
var bones := {}            # 规范名 -> 骨骼真名
var rest_xf := {}          # 规范名 -> 静止姿态全局 Transform3D (构建时抓取)
var move_speed := 0.0      # 由 main 每帧写入 (m/s), 驱动 idle/run 切换
var _swinging := false

const BONE_ORDER := [
	"Hips", "Spine", "Spine1", "Spine2", "Neck", "Head",
	"LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
	"RightShoulder", "RightArm", "RightForeArm", "RightHand",
	"LeftUpLeg", "LeftLeg", "LeftFoot", "RightUpLeg", "RightLeg", "RightFoot",
]


## 从 FBX 导出场景中提取第一个有效动画片段。
static func extract_clip(path: String, looped: bool) -> Animation:
	var ps: PackedScene = load(path)
	if ps == null:
		push_warning("无法加载动画: " + path)
		return null
	var root := ps.instantiate()
	var ap := _find_ap(root)
	var out: Animation = null
	if ap:
		var best_len := 0.0
		for n in ap.get_animation_list():
			var a := ap.get_animation(n)
			var score := a.length
			if n == "Take 001":
				score += 100.0
			if score > best_len and a.length > 0.1:
				best_len = score
				out = a
	if root != null:
		root.free()
	if out:
		out = out.duplicate(true)
		out.loop_mode = Animation.LOOP_LINEAR if looped else Animation.LOOP_NONE
	return out


static func _find_ap(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_ap(c)
		if r:
			return r
	return null


static func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skel(c)
		if r:
			return r
	return null


static func _toon(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.albedo_color = color
	m.roughness = 1.0
	return m


static func _flat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	if color.a < 0.99:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


## 构建角色 (base_scene: 带 Mixamo 骨架与 idle 动画的 FBX 场景)
func build(base_scene: PackedScene, skin_def: Dictionary, clips: Dictionary) -> void:
	skin = skin_def
	var root := base_scene.instantiate()
	root.name = "ModelRoot"
	add_child(root)

	skeleton = _find_skel(root)
	anim = _find_ap(root)
	anim.root_node = anim.get_path_to(root)

	# 隐藏原皮肤网格, 保留骨架
	for c in skeleton.get_children():
		if c is MeshInstance3D:
			c.visible = false

	# 骨骼名规范化索引 + 静止全局位姿
	for i in skeleton.get_bone_count():
		var bn := skeleton.get_bone_name(i)
		var norm := bn.to_lower().replace(":", "_").replace("mixamorig_", "")
		bones[norm] = bn
		rest_xf[norm] = skeleton.get_bone_global_pose(i)

	_build_body()
	_register_clips(clips)

	anim.playback_default_blend_time = 0.18
	if anim.has_animation("idle"):
		anim.play("idle")


func _register_clips(clips: Dictionary) -> void:
	var lib := anim.get_animation_library("")
	for key in clips:
		var a: Animation = clips[key]
		if a and not lib.has_animation(key):
			lib.add_animation(key, a)
	# 基础片段 "Take 001" → "idle"; 丢弃无用的 mixamo_com 绑定片段
	if lib.has_animation("Take 001"):
		var idle_anim := lib.get_animation("Take 001")
		idle_anim.loop_mode = Animation.LOOP_LINEAR
		lib.rename_animation("Take 001", "idle")
	if lib.has_animation("mixamo_com"):
		lib.remove_animation("mixamo_com")
	if lib.has_animation("run"):
		lib.get_animation("run").loop_mode = Animation.LOOP_LINEAR
	# 程序化发球
	if not lib.has_animation("serve"):
		lib.add_animation("serve", _build_serve_clip())


# ---------------------------------------------------------------- 每帧更新

func update_anim() -> void:
	if _swinging or anim == null:
		return
	if move_speed > 0.8 and anim.has_animation("run"):
		if anim.current_animation != "run":
			anim.play("run", 0.15)
		anim.speed_scale = clampf(move_speed / 6.5, 0.85, 1.4)
	else:
		if anim.current_animation != "idle":
			anim.play("idle", 0.22)
		anim.speed_scale = 1.0


## 播放一次动作, 返回时长(秒)。kind: forehand/backhand/serve/victory
func play_action(kind: String, speed := 1.0) -> float:
	if anim == null or not anim.has_animation(kind):
		return 0.0
	_swinging = true
	anim.speed_scale = speed
	anim.play(kind, 0.08)
	var dur := anim.get_animation(kind).length / maxf(speed, 0.01)
	var timer := get_tree().create_timer(dur)
	timer.timeout.connect(func() -> void:
		_swinging = false
		anim.speed_scale = 1.0
		swing_finished.emit())
	return dur


func is_busy() -> bool:
	return _swinging


# ---------------------------------------------------------------- 身体部件

func _world(bone: String, offset: Vector3) -> Transform3D:
	var xf: Transform3D = rest_xf[bone]
	return Transform3D(xf.basis, xf.origin + offset)


func _attach(bone: String, mi: MeshInstance3D, world_xf: Transform3D) -> void:
	var att := BoneAttachment3D.new()
	att.bone_name = bones[bone]
	skeleton.add_child(att)
	var bx: Transform3D = rest_xf[bone]
	mi.transform = bx.affine_inverse() * world_xf
	att.add_child(mi)


func _mesh(mesh: Mesh, mat: Material, world_xf: Transform3D, bone: String, scale := Vector3.ONE) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.scale = scale
	_attach(bone, mi, world_xf)


func _capsule_mesh(a: Vector3, b: Vector3, radius: float, mat: Material, bone: String, pad := 1.0) -> void:
	var dir := b - a
	var length := dir.length() * pad + radius * 2.0
	var cap := CapsuleMesh.new()
	cap.radius = radius
	cap.height = length
	var xf := Transform3D(_basis_along(dir.normalized()), (a + b) * 0.5)
	_mesh(cap, mat, xf, bone)


static func _basis_along(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var helper := Vector3(0, 0, 1)
	if absf(y.dot(helper)) > 0.99:
		helper = Vector3(1, 0, 0)
	var x := helper.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


func _sphere(radius: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	return s


func _cylinder(rt: float, rb: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = rt
	c.bottom_radius = rb
	c.height = h
	return c


func _box(w: float, h: float, d: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(w, h, d)
	return b


func _build_body() -> void:
	var male: bool = skin.gender == "m"
	var skin_c: Color = skin.skin
	var skin_mat := _toon(skin_c)
	var shirt_mat := _toon(skin.shirt)
	var shirt2_mat := _toon(skin.shirt2)
	var bottom_mat := _toon(skin.bottom)
	var hair_mat := _toon(skin.hair)
	var shoe_mat := _toon(skin.shoe)

	var arm_r := 0.052 if male else 0.045
	var fore_r := 0.042 if male else 0.036
	var thigh_r := 0.068 if male else 0.061
	var shin_r := 0.05 if male else 0.044

	# ---- 头 + 脸 (Head 骨骼) ----
	var hc: Vector3 = (rest_xf["head"].origin + Vector3(0, 0.145, 0))
	_mesh(_sphere(0.17), skin_mat, _xform(hc), "head")
	_build_face(hc)
	_build_hair(hc)

	# ---- 颈 ----
	_mesh(_cylinder(0.042, 0.048, 0.1), skin_mat, _xform(hc + Vector3(0, -0.13, 0)), "head")

	# ---- 躯干 ----
	var chest_r_top := 0.15 if male else 0.13
	var chest_r_bot := 0.172 if male else 0.155
	_mesh(_cylinder(chest_r_top, chest_r_bot, 0.30), shirt_mat,
		_xform(rest_xf["spine2"].origin + Vector3(0, 0.10, 0)), "spine2")
	_mesh(_cylinder(0.15, 0.152, 0.25), bottom_mat,
		_xform(rest_xf["hips"].origin + Vector3(0, 0.02, 0)), "hips")
	if skin.skirt:
		_mesh(_cylinder(0.158, 0.295, 0.30), _toon(skin.skirt_color),
			_xform(rest_xf["hips"].origin + Vector3(0, -0.01, 0)), "hips")

	# ---- 肩 ----
	for side: String in ["left", "right"]:
		var sb := side + "shoulder"
		if bones.has(sb):
			var p: Vector3 = rest_xf[sb].origin
			_mesh(_sphere(0.065 if male else 0.058), shirt_mat, _xform(p), sb)

	# ---- 手臂 (上臂=球衣短袖, 前臂=肤色, 手=肤色球) ----
	for side: String in ["left", "right"]:
		var s := "l" if side == "left" else "r"
		var arm_b := side + "arm"
		var fore_b := side + "forearm"
		var hand_b := side + "hand"
		_capsule_mesh(rest_xf[arm_b].origin, rest_xf[fore_b].origin, arm_r, shirt_mat, arm_b)
		_capsule_mesh(rest_xf[fore_b].origin, rest_xf[hand_b].origin, fore_r, skin_mat, fore_b)
		_mesh(_sphere(0.05 if male else 0.044), skin_mat, _xform(rest_xf[hand_b].origin), hand_b)

	# ---- 腿 + 鞋 ----
	for side: String in ["left", "right"]:
		var up := side + "upleg"
		var leg := side + "leg"
		var foot := side + "foot"
		_capsule_mesh(rest_xf[up].origin, rest_xf[leg].origin, thigh_r, skin_mat, up)
		_capsule_mesh(rest_xf[leg].origin, rest_xf[foot].origin, shin_r, skin_mat, leg)
		var fp: Vector3 = rest_xf[foot].origin
		_mesh(_box(0.105, 0.08, 0.22), shoe_mat, _xform(fp + Vector3(0, -0.03, 0.05)), foot)
		_mesh(_sphere(0.05), shoe_mat, _xform(fp + Vector3(0, -0.05, 0.14), ), foot, Vector3(1, 0.7, 1))

	# ---- 球拍 (右手) ----
	_build_racket(shirt2_mat)


func _xform(p: Vector3) -> Transform3D:
	return Transform3D(Basis.IDENTITY, p)


func _build_face(hc: Vector3) -> void:
	var eye_w := _flat(Color(0.99, 0.99, 1.0))
	var iris := _flat(skin.eye)
	var dark := _flat(Color(0.08, 0.07, 0.08))
	var white := _flat(Color.WHITE)
	var brow_m := _flat(skin.hair.darkened(0.1))
	var mouth_m := _flat(Color(0.72, 0.32, 0.38))

	for sx in [-1.0, 1.0]:
		# 眼白 (压扁, 稍微凸出)
		_mesh(_sphere(0.046), eye_w, _xform(hc + Vector3(sx * 0.066, 0.012, 0.146)), "head", Vector3(1, 1.3, 0.42))
		# 虹膜 + 瞳孔 + 高光
		_mesh(_sphere(0.03), iris, _xform(hc + Vector3(sx * 0.068, 0.008, 0.162)), "head", Vector3(1, 1.25, 0.4))
		_mesh(_sphere(0.014), dark, _xform(hc + Vector3(sx * 0.068, 0.005, 0.171)), "head", Vector3(1, 1.2, 0.4))
		_mesh(_sphere(0.008), white, _xform(hc + Vector3(sx * 0.068 + 0.012, 0.022, 0.174)), "head")
		# 眉毛
		var brow := _xform(hc + Vector3(sx * 0.068, 0.098, 0.149))
		brow.basis = Basis(Vector3.BACK, sx * -0.14) * Basis(Vector3.RIGHT, -0.12)
		_mesh(_box(0.075, 0.013, 0.014), brow_m, brow, "head")
		if skin.blush:
			var bl := _xform(hc + Vector3(sx * 0.105, -0.045, 0.128))
			bl.basis = Basis(Vector3.RIGHT, PI / 2)
			_mesh(_cylinder(0.024, 0.024, 0.005), _flat(Color(1.0, 0.55, 0.55, 0.55)), bl, "head")

	_mesh(_box(0.048, 0.015, 0.012), mouth_m, _xform(hc + Vector3(0, -0.075, 0.156)), "head")


func _build_hair(hc: Vector3) -> void:
	var hair_mat := _toon(skin.hair)
	var style: String = skin.style

	# 头盔式基础发罩 + 后脑勺 volume
	_mesh(_sphere(0.185), hair_mat, _xform(hc + Vector3(0, 0.045, -0.028)), "head")
	_mesh(_sphere(0.15), hair_mat, _xform(hc + Vector3(0, -0.03, -0.115)), "head")

	# 刘海 (额头一排)
	for i in 5:
		var x := -0.09 + i * 0.045
		var fx := _xform(hc + Vector3(x, 0.108 + absf(x) * 0.12, 0.132))
		fx.basis = Basis(Vector3.RIGHT, -0.22) * Basis(Vector3.BACK, x * 3.0)
		_mesh(_box(0.05, 0.1, 0.022), hair_mat, fx, "head")

	match style:
		"spiky":
			for i in 7:
				var ang := TAU * i / 7.0
				var r := 0.09
				var p := hc + Vector3(cos(ang) * r, 0.16, sin(ang) * r * 0.7 - 0.03)
				var sp := Transform3D(_basis_along(Vector3(cos(ang) * 0.5, 1.6, sin(ang) * 0.35 - 0.1)), p)
				var cone := CylinderMesh.new()
				cone.top_radius = 0.0
				cone.bottom_radius = 0.042
				cone.height = 0.15
				_mesh(cone, hair_mat, sp, "head")
		"pony":
			# 侧马尾 (右侧)
			var chain := [
				Vector3(0.11, 0.17, -0.06), Vector3(0.16, 0.04, -0.1),
				Vector3(0.15, -0.1, -0.12), Vector3(0.11, -0.21, -0.12),
			]
			var radii := [0.068, 0.058, 0.048, 0.03]
			for i in chain.size():
				_mesh(_sphere(radii[i]), hair_mat, _xform(hc + chain[i]), "head")
			var tip := Transform3D(_basis_along(Vector3(0.2, -1, 0.1)), hc + Vector3(0.1, -0.27, -0.12))
			var cone := CylinderMesh.new()
			cone.top_radius = 0.03
			cone.bottom_radius = 0.0
			cone.height = 0.08
			_mesh(cone, hair_mat, tip, "head")
		"twin":
			for sx in [-1.0, 1.0]:
				var chain := [
					Vector3(sx * 0.175, 0.06, -0.05), Vector3(sx * 0.21, -0.06, -0.07),
					Vector3(sx * 0.215, -0.17, -0.08),
				]
				var radii := [0.055, 0.047, 0.034]
				for i in chain.size():
					_mesh(_sphere(radii[i]), hair_mat, _xform(hc + chain[i]), "head")
				var tip := Transform3D(_basis_along(Vector3(sx * 0.2, -1, 0.05)), hc + Vector3(sx * 0.215, -0.23, -0.08))
				var cone := CylinderMesh.new()
				cone.top_radius = 0.032
				cone.bottom_radius = 0.0
				cone.height = 0.08
				_mesh(cone, hair_mat, tip, "head")
		_:
			pass  # short: 基础发型即可

	# 棒球帽 (可选)
	if skin.cap:
		var cap_mat := _toon(skin.cap_color)
		_mesh(_sphere(0.19), cap_mat, _xform(hc + Vector3(0, 0.075, -0.012)), "head", Vector3(1, 0.74, 1))
		_mesh(_box(0.2, 0.014, 0.14), cap_mat, _xform(hc + Vector3(0, 0.09, 0.16)), "head")
		_mesh(_sphere(0.022), cap_mat, _xform(hc + Vector3(0, 0.215, -0.012)), "head")


func _build_racket(accent_mat: Material) -> void:
	var hp: Vector3 = rest_xf["righthand"].origin
	var grip_mat := _toon(Color(0.16, 0.16, 0.2))
	var frame_mat := accent_mat
	var string_mat := _flat(Color(0.95, 0.97, 1.0, 0.4))
	# 手柄 (手下方) + 中杆
	_mesh(_cylinder(0.016, 0.016, 0.2), grip_mat, _xform(hp + Vector3(0, -0.03, 0)), "righthand")
	_mesh(_cylinder(0.011, 0.011, 0.16), frame_mat, _xform(hp + Vector3(0, 0.15, 0)), "righthand")
	# 拍框 (椭圆 Torus) + 拍线
	var head_center := hp + Vector3(0, 0.34, 0)
	var torus := TorusMesh.new()
	torus.inner_radius = 0.108
	torus.outer_radius = 0.125
	_mesh(torus, frame_mat, _xform(head_center), "righthand", Vector3(1, 1.4, 1))
	_mesh(_box(0.17, 0.25, 0.004), string_mat, _xform(head_center), "righthand", Vector3(1, 1.4, 1))


# ---------------------------------------------------------------- 程序化发球

## 用 idle@t0 的完整姿态做底, 施加世界空间姿态增量, FK 求出每关键帧的骨骼局部旋转。
func _build_serve_clip() -> Animation:
	var base := _sample_base_pose()
	var dur := 0.95
	var keys := [
		{"t": 0.0, "d": {}},
		{"t": 0.24, "d": {
			"RightArm": {"rx": 0, "ry": 20, "rz": -145},
			"RightForeArm": {"rx": 0, "ry": 0, "rz": -25},
			"LeftArm": {"rx": -25, "ry": 0, "rz": 138},
			"LeftForeArm": {"rx": 0, "ry": 0, "rz": 18},
			"Spine2": {"rx": 6, "ry": -18, "rz": 0},
			"Spine": {"rx": 2, "ry": -8, "rz": 0},
			"Head": {"rx": -14, "ry": 6, "rz": 0},
			"Hips": {"rx": 0, "ry": -10, "rz": 0},
		}},
		{"t": 0.46, "d": {
			"RightArm": {"rx": -150, "ry": -8, "rz": -12},
			"RightForeArm": {"rx": -18, "ry": 0, "rz": -8},
			"LeftArm": {"rx": -45, "ry": 0, "rz": 42},
			"LeftForeArm": {"rx": 0, "ry": 0, "rz": 10},
			"Spine2": {"rx": 14, "ry": 14, "rz": 0},
			"Spine": {"rx": 6, "ry": 6, "rz": 0},
			"Head": {"rx": 6, "ry": 8, "rz": 0},
			"Hips": {"rx": 0, "ry": 8, "rz": 0},
		}},
		{"t": 0.64, "d": {
			"RightArm": {"rx": -95, "ry": 28, "rz": 10},
			"RightForeArm": {"rx": -8, "ry": 0, "rz": 0},
			"LeftArm": {"rx": -20, "ry": 0, "rz": 15},
			"Spine2": {"rx": 16, "ry": 24, "rz": 0},
			"Spine": {"rx": 6, "ry": 10, "rz": 0},
			"Head": {"rx": 12, "ry": 10, "rz": 0},
			"Hips": {"rx": 0, "ry": 12, "rz": 0},
		}},
		{"t": dur, "d": {}},
	]
	return _pose_clip("serve", dur, keys, base)


func _sample_base_pose() -> Dictionary:
	# bone -> {pos: Vector3, rot: Quaternion}
	var out := {}
	var idle: Animation = null
	if anim and anim.has_animation("idle"):
		idle = anim.get_animation("idle")
	for bn in BONE_ORDER:
		var real: String = bones.get(bn.to_lower(), "")
		if real == "":
			continue
		var idx := skeleton.find_bone(real)
		var rest := skeleton.get_bone_rest(idx)
		var rot: Quaternion = rest.basis.get_rotation_quaternion()
		var pos: Vector3 = rest.origin
		if idle:
			for t in idle.get_track_count():
				if idle.track_get_type(t) != Animation.TYPE_ROTATION_3D:
					continue
				var path := str(idle.track_get_path(t))
				if path == "Skeleton3D:" + real:
					rot = idle.rotation_track_interpolate(t, 0.0)
				if idle.track_get_type(t) == Animation.TYPE_POSITION_3D and path == "Skeleton3D:" + real:
					pos = idle.position_track_interpolate(t, 0.0)
		out[bn] = {"pos": pos, "rot": rot}
	return out


## keys: [{t, d: {bone: {rx,ry,rz}(世界空间欧拉度)}}] → 完整姿态 Animation
func _pose_clip(_name: String, dur: float, keys: Array, base: Dictionary) -> Animation:
	var a := Animation.new()
	a.length = dur
	a.loop_mode = Animation.LOOP_NONE

	# 计算每个关键帧的局部旋转 (自上而下 FK)
	var frame_locals: Array = []  # [{bone: Quaternion}]
	for k in keys:
		var deltas: Dictionary = k.d
		var parent_new := Transform3D()
		var locals := {}
		for bn in BONE_ORDER:
			if not base.has(bn):
				continue
			var base_local := Transform3D(Basis(base[bn].rot), base[bn].pos)
			var world_delta := Basis.IDENTITY
			if deltas.has(bn):
				var e: Dictionary = deltas[bn]
				world_delta = Basis(Quaternion(Vector3.UP, deg_to_rad(e.ry))
					* Quaternion(Vector3.RIGHT, deg_to_rad(e.rx))
					* Quaternion(Vector3.BACK, deg_to_rad(e.rz)))
			var new_global := Transform3D(world_delta, Vector3.ZERO) * (parent_new * base_local)
			locals[bn] = (parent_new.affine_inverse() * new_global).basis.get_rotation_quaternion()
			parent_new = new_global
		frame_locals.append(locals)

	# Hips 位置轨迹 (静止位置)
	if base.has("Hips"):
		var pt := a.add_track(Animation.TYPE_POSITION_3D)
		a.track_set_path(pt, "Skeleton3D:" + bones["hips"])
		a.position_track_insert_key(pt, 0.0, base["Hips"].pos)
		a.position_track_insert_key(pt, dur, base["Hips"].pos)

	# 每根骨骼一条旋转轨迹, 关键帧 = 各帧姿态
	for bn in BONE_ORDER:
		if not base.has(bn) or not frame_locals[0].has(bn):
			continue
		var t := a.add_track(Animation.TYPE_ROTATION_3D)
		a.track_set_path(t, "Skeleton3D:" + bones[bn.to_lower()])
		for i in keys.size():
			a.rotation_track_insert_key(t, keys[i].t, frame_locals[i][bn])
	return a
