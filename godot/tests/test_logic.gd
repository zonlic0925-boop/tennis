extends SceneTree
## 纯逻辑单元测试 —— tests/run-tests.mjs 的 GDScript 移植
## 运行: godot --headless --path . --script res://tests/test_logic.gd

var passed := 0
var failures: Array[String] = []


func _init() -> void:
	seed(20260908)
	_run_all()
	if failures.size() > 0:
		printerr("\n%d 项失败 / %d 项" % [failures.size(), passed + failures.size()])
		for f in failures:
			printerr("  FAIL ", f)
		quit(1)
	else:
		print("\n全部通过: %d 项" % passed)
		quit(0)


func test(name: String, fn: Callable) -> void:
	var err: Variant = fn.call()
	if err == null or err == "":
		passed += 1
		print("  ok  ", name)
	else:
		failures.append("%s -> %s" % [name, err])
		printerr("FAIL  ", name, "  ::  ", err)


func near(got: float, want: float, tol: float, msg: String) -> String:
	if absf(got - want) > tol:
		return "%s: %f vs %f (±%f)" % [msg, got, want, tol]
	return ""


func ok(cond: bool, msg: String) -> String:
	return "" if cond else msg


func eq(got, want, msg: String) -> String:
	return "" if got == want else "%s: got %s want %s" % [msg, str(got), str(want)]


func _run_all() -> void:
	print("== 物理: 弹道求解 ==")
	test("solve_launch 符合 PRD 公式", func() -> String:
		var v := BallPhysics.solve_launch(Vector3(0, 1.2, -9), Vector3(2.1, 0, 8.4), 1.0)
		var e := near(v.x, 2.1, 1e-6, "vx")
		if e != "": return e
		e = near(v.z, 17.4, 1e-6, "vz")
		if e != "": return e
		return near(v.y, -1.2 + 4.905, 1e-6, "vy = (-y0 - 0.5·g·T²)/T")
	)

	test("solve_launch_corrected: 含空气阻力仍精确命中目标", func() -> String:
		var p0 := Vector3(0, 1.2, -9)
		var target := Vector3(2.1, 0, 8.4)
		var T := 1.0
		var v := BallPhysics.solve_launch_corrected(p0, target, T)
		var s := BallPhysics.BallState.new(p0, v, "Flat")
		var dt := 1.0 / 600.0
		var t := 0.0
		while t < T:
			BallPhysics.integrate(s, dt, false)
			t += dt
		var e := near(s.pos.x, target.x, 0.15, "x 落点")
		if e != "": return e
		e = near(s.pos.z, target.z, 0.15, "z 落点")
		if e != "": return e
		return near(s.pos.y, 0.0, 0.25, "y 落地")
	)

	test("ensure_net_clearance: 平快球被抬升到过网 0.3m 以上", func() -> String:
		var p0 := Vector3(0, 1.2, -9)
		var r := BallPhysics.ensure_net_clearance(p0, Vector3(0, 0, 10), 0.62)
		var clearance := BallPhysics.net_clearance(p0, r.v, r.T)
		var e := ok(clearance >= CourtConfig.NET_HEIGHT + CourtConfig.NET_CLEARANCE - 1e-6,
			"过网高度不足: %f" % clearance)
		if e != "": return e
		return ok(r.T <= CourtConfig.T_MAX + 1e-6, "T 超上限: %f" % r.T)
	)

	test("弹跳: 反弹系数 0.72 生效", func() -> String:
		var s := BallPhysics.BallState.new(Vector3(0, 1, 0), Vector3(0, -4, 0), "Flat")
		var dt := 1.0 / 240.0
		var vy_before := 0.0
		var bounced := {}
		for i in 400:
			if not bounced.is_empty():
				break
			vy_before = s.vel.y
			bounced = BallPhysics.integrate(s, dt)
		var e := ok(not bounced.is_empty(), "应发生落地")
		if e != "": return e
		e = ok(s.vel.y > 0, "落地后应向上弹起")
		if e != "": return e
		return near(s.vel.y, -vy_before * 0.72, 0.15, "反弹速度 = 0.72 × 落地瞬间速度")
	)

	test("predict_landing: 第一落点预测与界内外判定正确", func() -> String:
		var v := BallPhysics.solve_launch_corrected(Vector3(0, 2, 9), Vector3(1, 0, -8), 1.1)
		var in_res := BallPhysics.predict_landing(BallPhysics.BallState.new(Vector3(0, 2, 9), v, "Flat"))
		var e := eq(in_res.net, false, "不应碰网")
		if e != "": return e
		e = eq(in_res.in_bounds, true, "界内球")
		if e != "": return e
		e = near(in_res.pos.x, 1.0, 0.4, "预测落点 x")
		if e != "": return e
		e = near(in_res.pos.z, -8.0, 0.6, "预测落点 z")
		if e != "": return e

		var v2 := BallPhysics.solve_launch(Vector3(0, 2, 9), Vector3(6, 0, -6), 1.0)
		var out_res := BallPhysics.predict_landing(BallPhysics.BallState.new(Vector3(0, 2, 9), v2, "Flat"))
		e = eq(out_res.in_bounds, false, "出界球应判出界")
		if e != "": return e

		var flat := BallPhysics.BallState.new(Vector3(0, 1.5, 9), Vector3(0, 0, -20), "Flat")
		var net_res := BallPhysics.predict_landing(flat)
		return eq(net_res.net, true, "平击球应碰网")
	)

	test("场地/发球区校验", func() -> String:
		var e := ok(BallPhysics.check_in_bounds(4.115, 11.885), "底线内侧应界内")
		if e != "": return e
		e = ok(!BallPhysics.check_in_bounds(4.2, 0.0), "边线外应出界")
		if e != "": return e
		e = ok(!BallPhysics.check_in_bounds(0.0, 12.0), "底线外应出界")
		if e != "": return e
		e = ok(BallPhysics.check_serve_box(-2.0, 8.0, 1), "对角区应有效")
		if e != "": return e
		e = ok(!BallPhysics.check_serve_box(2.0, 8.0, 1), "发球必须进对角区")
		if e != "": return e
		return ok(!BallPhysics.check_serve_box(-2.0, 5.0, 1), "发球深度不足(没过发球线)")
	)

	print("== 滑屏映射 ==")
	test("满宽右滑 → 偏转 ≈ +25°", func() -> String:
		var m := Strike.map_swipe(400, 8, 0.1)
		return near(m.deflection, 25.0 * PI / 180.0, 0.03, "偏转角")
	)

	test("垂直上滑 → 偏转 0, 力量由速度决定", func() -> String:
		var slow := Strike.map_swipe(0, 300, 0.5)
		var fast := Strike.map_swipe(0, 800, 0.12)
		var e := near(slow.deflection, 0.0, 1e-6, "慢滑偏转")
		if e != "": return e
		return ok(fast.power > slow.power, "快速长滑力量应更大")
	)

	test("真实屏幕输入约定: 屏幕向上滑(dy翻转后为正) → 偏转 0", func() -> String:
		var screen_dy := -(220.0 - 550.0)
		var m := Strike.map_swipe(0, screen_dy, 0.2)
		var e := near(m.deflection, 0.0, 1e-6, "垂直上滑不得产生横向偏转")
		if e != "": return e
		var m2 := Strike.map_swipe(0, -(550.0 - 220.0), 0.2)
		return ok(absf(m2.deflection) > 0.3, "下滑应有明显偏转")
	)

	test("曲线滑屏 → 识别旋转类型", func() -> String:
		var curve := Strike.map_swipe(0, 500, 0.2, [Vector2(0, 0), Vector2(80, 250), Vector2(0, 500)])
		var e := eq(curve.spin, "Topspin", "曲线滑屏")
		if e != "": return e
		var flat := Strike.map_swipe(0, 500, 0.2, [Vector2(0, 0), Vector2(0, 250), Vector2(0, 500)])
		return eq(flat.spin, "Flat", "直线滑屏")
	)

	test("stroke_from_swipe: 落点在对方半场且过网", func() -> String:
		var m := Strike.map_swipe(0, 700, 0.15)
		var from := Vector3(0, 1.2, -9)
		var r := Strike.stroke_from_swipe(m, from, 1)
		var e := ok(r.target.z > 0, "目标在对方半场")
		if e != "": return e
		return ok(BallPhysics.net_clearance(from, r.v, r.T) >= CourtConfig.NET_HEIGHT + 0.3 - 1e-6, "过网")
	)

	test("serve_from_swipe: 发球落点在对角发球区", func() -> String:
		var m := Strike.map_swipe(0, 700, 0.15)
		var from := Vector3(1.25, 2.7, -10.4)
		var r := Strike.serve_from_swipe(m, 1, from, 1)
		return ok(BallPhysics.check_serve_box(r.target.x, r.target.z, 1),
			"发球目标应在区内: %s,%s" % [r.target.x, r.target.z])
	)

	test("ai_stroke: 目标始终在玩家半场", func() -> String:
		for i in 50:
			var pp := Vector3((randf() - 0.5) * 8.0, 0, -8)
			var r := Strike.ai_stroke(pp, 0.7, Vector3(0, 1.2, 9), -1)
			if r.target.z >= 0:
				return "AI 回球必须在玩家半场"
			if absf(r.target.x) > 5.2:
				return "AI 目标 x 超界"
		return ""
	)

	print("== 裁判状态机 ==")
	test("双误 → 接发方得分, 发球轮换", func() -> String:
		var r := Referee.new()
		r.start_match()
		var f1 := r.on_serve_fault("p1")
		var e := eq(f1.double_fault, false, "一发失误不是双误")
		if e != "": return e
		e = eq(r.serve_attempt, 2, "进入二发")
		if e != "": return e
		var f2 := r.on_serve_fault("p1")
		e = eq(f2.phase, "point_end", "双误结束该分")
		if e != "": return e
		e = eq(r.score.p2, 1, "接发方得分")
		if e != "": return e
		e = eq(r.server, "p2", "每分后轮换发球")
		if e != "": return e
		r.next_serve()
		return eq(r.phase, "serve", "进入下一分发球")
	)

	test("6-6 → 7-6 领先 1 分不结束, 比赛继续", func() -> String:
		var r := Referee.new()
		r.start_match()
		for i in 12:
			var res := r.on_rally_end("p1" if i % 2 == 0 else "p2", "test")
			if res.phase == "match_end":
				return "6-6 前不应结束"
			r.next_serve()
		var e := eq(r.score.p1, 6, "p1 6分")
		if e != "": return e
		e = eq(r.score.p2, 6, "p2 6分")
		if e != "": return e
		var result := r.on_rally_end("p1", "test")  # 7-6
		e = ok(result.phase != "match_end", "7-6 领先 1 分不应结束")
		if e != "": return e
		r.next_serve()
		result = r.on_rally_end("p2", "test")  # 7-7
		return ok(result.phase != "match_end", "7-7 平不应结束")
	)

	test("7-7 后连赢 2 分, 9-7 结束比赛", func() -> String:
		var r := Referee.new()
		r.start_match()
		var result := {}
		for i in 14:
			result = r.on_rally_end("p1" if i % 2 == 0 else "p2", "test")
			r.next_serve()
		var e := eq(r.score.p1, 7, "p1 7分")
		if e != "": return e
		e = eq(r.score.p2, 7, "p2 7分")
		if e != "": return e
		result = r.on_rally_end("p1", "test")  # 8-7
		e = ok(result.phase != "match_end", "8-7 不结束")
		if e != "": return e
		r.next_serve()
		result = r.on_rally_end("p1", "test")  # 9-7
		e = eq(result.phase, "match_end", "9-7 应结束")
		if e != "": return e
		e = eq(result.winner, "p1", "胜者 p1")
		if e != "": return e
		e = eq(r.score.p1, 9, "p1 9分")
		if e != "": return e
		return eq(r.score.p2, 7, "p2 7分")
	)
