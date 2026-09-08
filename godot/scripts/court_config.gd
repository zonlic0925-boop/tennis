class_name CourtConfig
## 球场与物理常量 —— 与 Web 原型 js/core/config.js 完全一致 (PRD §2.1 / §3)
## 坐标系: X 右, Y 上, -Z 朝向玩家。玩家半场 z<0, 对手半场 z>0, 网在 z=0。

const COURT_LENGTH := 23.77
const COURT_WIDTH := 8.23
const HALF_L := 11.885
const HALF_W := 4.115
const NET_HEIGHT := 0.914
const NET_CLEARANCE := 0.3
const SERVICE_LINE := 6.4
const BALL_RADIUS := 0.0335

const GRAVITY := -9.81
const RESTITUTION := 0.72       # PRD: 弹跳系数
const TANGENT_LOSS := 0.78      # 落地水平速度保留
const DRAG := 0.12              # 指数空气阻力 /s
const TOPSPIN_FORWARD := 1.18
const SLICE_FORWARD := 0.82

const PERFECT_DIST := 0.8       # <0.8m Perfect
const GOOD_DIST := 1.8          # 0.8~1.8m Good
const DIVE_DIST := 2.5          # 1.8~2.5m Dive
const PERFECT_BONUS := 1.15     # Perfect +15%
const MAX_DEFLECT_DEG := 25.0   # 满宽滑屏 ±25°
const SWIPE_ANGLE_MAX := 75.0
const PLAYER_SPEED := 6.5       # 移速 m/s
const RECOVER_SPEED := 0.6

const SWIPE_SPEED_MAX := 6000.0
const SWIPE_LEN_MAX := 1000.0
const POWER_MIN := 0.12
const T_MIN := 0.62
const T_MAX := 1.3
const Z_DEPTH_MIN := 3.2
const Z_DEPTH_MAX := 10.3
const SERVE_Z_MIN := 6.4
const SERVE_Z_MAX := 10.4
const SERVE_TOSS_Y := 2.7
const SERVE_TOSS_Z := 10.4
const PLAYER_BASE := Vector3(0, 0, -9.4)
const AI_BASE := Vector3(0, 0, 9.4)

const TARGET_POINTS := 7
const WIN_BY := 2

const SIM_DT := 1.0 / 240.0


static func clampf(v: float, lo: float, hi: float) -> float:
	return minf(hi, maxf(lo, v))


static func lerpf_(a: float, b: float, t: float) -> float:
	return a + (b - a) * t
