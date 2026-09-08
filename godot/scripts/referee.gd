class_name Referee
extends RefCounted
## 裁判状态机 —— js/core/referee.js 的 GDScript 移植 (PRD §3 Module 3)
## 先到 7 分且净胜 2 分获胜。状态: menu → serve → rally → point_end → (serve | match_end)

var score := {"p1": 0, "p2": 0}
var phase := "menu"
var server := "p1"
var serve_attempt := 1
var match_winner := ""


func reset() -> void:
	score = {"p1": 0, "p2": 0}
	phase = "menu"
	server = "p1"
	serve_attempt = 1
	match_winner = ""


func start_match() -> void:
	phase = "serve"
	server = "p1"
	serve_attempt = 1


## 发球失误: 一发失误 → 二发; 二发失误 → 双误, 接发方得分。
func on_serve_fault(server_id: String) -> Dictionary:
	if phase != "serve" or server_id != server:
		return {}
	if serve_attempt == 1:
		serve_attempt = 2
		return {"double_fault": false}
	return _award_point(other(server_id), "doubleFault")


func on_serve_in(server_id: String) -> bool:
	if phase == "serve" and server_id == server:
		phase = "rally"
		return true
	return false


func on_rally_end(winner_id: String, reason: String) -> Dictionary:
	if phase != "rally" and phase != "serve":
		return {}
	return _award_point(winner_id, reason)


func _award_point(winner_id: String, reason: String) -> Dictionary:
	var lead: int = score[winner_id] + 1 - score[other(winner_id)]
	score[winner_id] += 1
	if score[winner_id] >= CourtConfig.TARGET_POINTS and lead >= CourtConfig.WIN_BY:
		phase = "match_end"
		match_winner = winner_id
		return {"phase": "match_end", "winner": winner_id, "score": score.duplicate(), "reason": reason}
	phase = "point_end"
	server = other(server)  # 每分轮换发球
	serve_attempt = 1
	return {"phase": "point_end", "score": score.duplicate(), "next_server": server, "reason": reason}


func next_serve() -> void:
	if phase == "point_end":
		phase = "serve"
		serve_attempt = 1


func other(id: String) -> String:
	return "p2" if id == "p1" else "p1"
