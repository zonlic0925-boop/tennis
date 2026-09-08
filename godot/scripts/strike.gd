class_name Strike
## 滑屏 → 击球参数映射 —— js/core/strike.js 的 GDScript 移植 (PRD §2.2)
## swipe 约定: dy 向上为正(屏幕坐标已翻转)。纯函数, 可单测。

const RAD := PI / 180.0


## 返回 { power, deflection, spin, len, speed }
static func map_swipe(dx: float, dy: float, dt: float, samples: Array = []) -> Dictionary:
	var l := sqrt(dx * dx + dy * dy)
	var speed := l / maxf(dt, 0.05)

	var angle := atan2(dx, dy)  # 0 = 正上方
	var n := CourtConfig.clampf(angle / (CourtConfig.SWIPE_ANGLE_MAX * RAD), -1.0, 1.0)
	var deflection := n * CourtConfig.MAX_DEFLECT_DEG * RAD

	var power := CourtConfig.clampf(
		0.62 * (speed / CourtConfig.SWIPE_SPEED_MAX) + 0.38 * (l / CourtConfig.SWIPE_LEN_MAX),
		CourtConfig.POWER_MIN, 1.0
	)
	return {"power": power, "deflection": deflection, "spin": detect_spin(samples), "len": l, "speed": speed}


## 滑屏轨迹曲率 → 旋转类型: Flat / Topspin / Slice
static func detect_spin(samples: Array) -> String:
	if samples.size() < 3:
		return "Flat"
	var a: Vector2 = samples[0]
	var b: Vector2 = samples[samples.size() - 1]
	var L := (b - a).length()
	if L < 1e-6:
		return "Flat"
	var mid: Vector2 = samples[samples.size() / 2]
	var dev := ((mid.x - a.x) * (b.y - a.y) - (mid.y - a.y) * (b.x - a.x)) / L
	var rel := dev / L
	if rel > 0.12:
		return "Topspin"
	if rel < -0.12:
		return "Slice"
	return "Flat"


## 常规回球: 由滑屏映射计算对方半场落点并反解初速度。
## from: 击球点, dir: +1 打向 z>0 半场 / -1 反之。返回 { target, T, v, spin, power }
static func stroke_from_swipe(mapped: Dictionary, from: Vector3, dir := 1) -> Dictionary:
	var depth := CourtConfig.lerpf_(CourtConfig.Z_DEPTH_MIN, CourtConfig.Z_DEPTH_MAX, mapped.power)
	var target := Vector3(
		CourtConfig.clampf(from.x + tan(mapped.deflection) * absf(depth * dir - from.z), -5.2, 5.2),
		0,
		dir * depth
	)
	var T := CourtConfig.lerpf_(CourtConfig.T_MAX, CourtConfig.T_MIN, mapped.power)
	var solved := BallPhysics.ensure_net_clearance(from, target, T)
	return {"target": target, "T": solved.T, "v": solved.v, "spin": mapped.spin, "power": mapped.power}


## 发球: 落点约束在对角发球区, |x| 由偏转角映射到 [0.5, 3.8]。
static func serve_from_swipe(mapped: Dictionary, serve_side: int, from: Vector3, dir := 1) -> Dictionary:
	var tz := dir * CourtConfig.lerpf_(CourtConfig.SERVE_Z_MIN, CourtConfig.SERVE_Z_MAX, mapped.power)
	var mag := CourtConfig.clampf(absf(mapped.deflection) / (CourtConfig.MAX_DEFLECT_DEG * RAD), 0.0, 1.0)
	var tx := -serve_side * (0.5 + mag * 3.3)
	var T := CourtConfig.lerpf_(1.4, 1.0, mapped.power)
	var solved := BallPhysics.ensure_net_clearance(from, Vector3(tx, 0, tz), T)
	return {"target": Vector3(tx, 0, tz), "T": solved.T, "v": solved.v, "spin": "Flat", "power": mapped.power}


## AI 自动击球: 目标在玩家半场, 尽量打向远离玩家当前位置的一侧。
static func ai_stroke(player_pos: Vector3, difficulty: float, from: Vector3, dir := -1) -> Dictionary:
	var away := -1 if player_pos.x > 0 else 1
	var go_away := randf() < 0.72
	var tx: float
	if go_away:
		tx = CourtConfig.clampf(away * (1.8 + randf() * 1.7) + (randf() - 0.5) * 0.8, -3.7, 3.7)
	else:
		tx = CourtConfig.clampf(player_pos.x + (randf() - 0.5) * 2.4, -3.7, 3.7)
	var tz := dir * CourtConfig.lerpf_(CourtConfig.Z_DEPTH_MIN, CourtConfig.Z_DEPTH_MAX, 0.35 + 0.65 * randf())
	var power := 0.42 + 0.42 * difficulty + randf() * 0.18
	var T := CourtConfig.lerpf_(CourtConfig.T_MAX, CourtConfig.T_MIN, power)
	var solved := BallPhysics.ensure_net_clearance(from, Vector3(tx, 0, tz), T)
	return {"target": Vector3(tx, 0, tz), "T": solved.T, "v": solved.v,
			"spin": "Topspin" if randf() < 0.3 else "Flat", "power": power}
