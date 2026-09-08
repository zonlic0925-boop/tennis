class_name Skins
## 皮肤定义: 男 ×2 / 女 ×2, 供开始界面选择。
## style: spiky(刺猬短发) / short(利落短发) / pony(侧马尾) / twin(双马尾)

const ALL: Array[Dictionary] = [
	{
		"id": "yang", "label": "烈阳", "gender": "m",
		"skin": Color(0.96, 0.78, 0.63), "hair": Color(0.12, 0.10, 0.10),
		"style": "spiky", "cap": true, "cap_color": Color(0.96, 0.95, 0.92),
		"shirt": Color(0.87, 0.22, 0.20), "shirt2": Color(0.97, 0.94, 0.89),
		"bottom": Color(0.95, 0.94, 0.90), "skirt": false,
		"shoe": Color(0.92, 0.92, 0.95), "eye": Color(0.30, 0.18, 0.13),
		"racket": Color(0.80, 0.20, 0.22), "blush": false,
	},
	{
		"id": "lei", "label": "苍雷", "gender": "m",
		"skin": Color(0.94, 0.76, 0.61), "hair": Color(0.32, 0.22, 0.14),
		"style": "short", "cap": false, "cap_color": Color.WHITE,
		"shirt": Color(0.13, 0.30, 0.56), "shirt2": Color(0.10, 0.72, 0.72),
		"bottom": Color(0.12, 0.13, 0.16), "skirt": false,
		"shoe": Color(0.22, 0.22, 0.25), "eye": Color(0.14, 0.38, 0.28),
		"racket": Color(0.20, 0.42, 0.82), "blush": false,
	},
	{
		"id": "ying", "label": "樱语", "gender": "f",
		"skin": Color(0.99, 0.86, 0.76), "hair": Color(0.64, 0.43, 0.36),
		"style": "pony", "cap": false, "cap_color": Color.WHITE,
		"shirt": Color(0.99, 0.74, 0.80), "shirt2": Color(0.99, 0.97, 0.95),
		"bottom": Color(0.96, 0.92, 0.93), "skirt": true,
		"skirt_color": Color(0.97, 0.46, 0.57),
		"shoe": Color(0.96, 0.91, 0.92), "eye": Color(0.58, 0.24, 0.18),
		"racket": Color(0.92, 0.42, 0.58), "blush": true,
	},
	{
		"id": "lan", "label": "蔚蓝", "gender": "f",
		"skin": Color(0.97, 0.82, 0.70), "hair": Color(0.16, 0.22, 0.46),
		"style": "twin", "cap": false, "cap_color": Color.WHITE,
		"shirt": Color(0.20, 0.55, 0.76), "shirt2": Color(0.86, 0.91, 0.98),
		"bottom": Color(0.32, 0.27, 0.52), "skirt": true,
		"skirt_color": Color(0.38, 0.32, 0.62),
		"shoe": Color(0.86, 0.89, 0.96), "eye": Color(0.18, 0.38, 0.72),
		"racket": Color(0.30, 0.62, 0.92), "blush": true,
	},
]


static func by_id(id: String) -> Dictionary:
	for s in ALL:
		if s.id == id:
			return s
	return ALL[0]
