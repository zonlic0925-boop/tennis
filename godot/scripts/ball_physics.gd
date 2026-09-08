class_name BallPhysics
## 弹道物理 —— js/core/physics.js 的 GDScript 移植 (PRD §2.2)
## BallState: pos/vel (Vector3) + spin (String)。纯函数, 可单测。

class BallState:
	var pos: Vector3
	var vel: Vector3
	var spin := "Flat"

	func _init(p := Vector3.ZERO, v := Vector3.ZERO, s := "Flat") -> void:
		pos = p
		vel = v
		spin = s

	func clone() -> BallState:
		return BallState.new(pos, vel, spin)


## 半隐式欧拉积分一步。落地反弹时返回 {bounced=true, at=Vector3(x,0,z)}, 否则空字典。
static func integrate(s: BallState, dt: float, do_bounce := true) -> Dictionary:
	var drag := exp(-CourtConfig.DRAG * dt)
	s.vel.x *= drag
	s.vel.y += CourtConfig.GRAVITY * dt
	s.vel.z *= drag
	s.pos += s.vel * dt

	if do_bounce and s.pos.y <= CourtConfig.BALL_RADIUS and s.vel.y < 0.0:
		s.pos.y = CourtConfig.BALL_RADIUS
		s.vel.y = -s.vel.y * CourtConfig.RESTITUTION
		var keep := CourtConfig.TANGENT_LOSS
		if s.spin == "Topspin":
			keep *= CourtConfig.TOPSPIN_FORWARD
		elif s.spin == "Slice":
			keep *= CourtConfig.SLICE_FORWARD
		s.vel.x *= keep
		s.vel.z *= keep
		return {"bounced": true, "at": Vector3(s.pos.x, 0, s.pos.z)}
	return {}


## 弹道发射公式: 给定起点/落点/飞行时间 T, 反解初速度(无阻力解析解)。
static func solve_launch(p0: Vector3, target: Vector3, T: float) -> Vector3:
	return Vector3(
		(target.x - p0.x) / T,
		(-p0.y - 0.5 * CourtConfig.GRAVITY * T * T) / T,
		(target.z - p0.z) / T
	)


## 解析解基础上迭代修正 vx/vz, 抵消空气阻力导致的落点偏差。
static func solve_launch_corrected(p0: Vector3, target: Vector3, T: float) -> Vector3:
	var v := solve_launch(p0, target, T)
	var steps := maxi(1, roundi(T / CourtConfig.SIM_DT))
	for i in 3:
		var s := BallState.new(p0, v, "Flat")
		for j in steps:
			integrate(s, CourtConfig.SIM_DT, false)
		v.x += (target.x - s.pos.x) / T
		v.z += (target.z - s.pos.z) / T
	return v


## 球过网(z=0)瞬间的高度; 不过网返回 1e9。
static func net_clearance(p0: Vector3, v: Vector3, T: float) -> float:
	if absf(v.z) < 1e-6:
		return 1e9
	var tc := (0.0 - p0.z) / v.z
	if tc <= 0.0 or tc >= T:
		return 1e9
	return p0.y + v.y * tc + 0.5 * CourtConfig.GRAVITY * tc * tc


## 有效击球需净过网 NET_HEIGHT+0.3: 抬高弧线(T 增大)直至满足, 上限 T_MAX。
static func ensure_net_clearance(p0: Vector3, target: Vector3, T: float) -> Dictionary:
	var t := CourtConfig.clampf(T, CourtConfig.T_MIN, CourtConfig.T_MAX)
	var v := Vector3.ZERO
	for i in 40:
		v = solve_launch(p0, target, t)
		if net_clearance(p0, v, t) >= CourtConfig.NET_HEIGHT + CourtConfig.NET_CLEARANCE + 0.06:
			return {"T": t, "v": solve_launch_corrected(p0, target, t)}
		if t >= CourtConfig.T_MAX:
			break
		t = minf(t + 0.04, CourtConfig.T_MAX)
	return {"T": t, "v": solve_launch_corrected(p0, target, t)}


## 前推模拟到首次落地/碰网, 用于落点指示器与 AI 跑位。
static func predict_landing(state: BallState, max_t := 6.0) -> Dictionary:
	var s := state.clone()
	var t := 0.0
	while t < max_t:
		var p := s.pos
		integrate(s, CourtConfig.SIM_DT, false)
		t += CourtConfig.SIM_DT
		if (p.z <= 0.0 and s.pos.z > 0.0) or (p.z >= 0.0 and s.pos.z < 0.0):
			var f := p.z / (p.z - s.pos.z)
			var y_at := p.y + f * (s.pos.y - p.y)
			if y_at < CourtConfig.NET_HEIGHT:
				return {"net": true, "t": t, "pos": Vector3(s.pos.x, 0, 0)}
		if p.y > CourtConfig.BALL_RADIUS and s.pos.y <= CourtConfig.BALL_RADIUS and s.vel.y < 0.0:
			var f2 := (p.y - CourtConfig.BALL_RADIUS) / (p.y - s.pos.y)
			var x := p.x + f2 * (s.pos.x - p.x)
			var z := p.z + f2 * (s.pos.z - p.z)
			return {"net": false, "t": t, "pos": Vector3(x, 0, z), "in_bounds": check_in_bounds(x, z)}
	return {"net": false, "t": max_t, "pos": Vector3(s.pos.x, 0, s.pos.z), "in_bounds": false}


static func check_in_bounds(x: float, z: float) -> bool:
	return absf(x) <= CourtConfig.HALF_W and absf(z) <= CourtConfig.HALF_L


## 发球区校验: 对角线半区, |z| ∈ [发球线, 底线]。
static func check_serve_box(x: float, z: float, server_side: int) -> bool:
	var in_depth := absf(z) >= CourtConfig.SERVICE_LINE and absf(z) <= CourtConfig.HALF_L
	var in_diagonal := signf(x) == -float(server_side) and absf(x) <= CourtConfig.HALF_W
	return in_depth and in_diagonal
