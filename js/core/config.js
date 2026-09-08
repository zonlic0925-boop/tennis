// 球场与物理常量 —— 对应 PRD §2.1 / §3
// 坐标系: X 右, Y 上, Z 朝向对手。玩家半场 z<0, 对手半场 z>0, 网在 z=0。

export const COURT = {
  LENGTH: 23.77,          // PRD: 全场长度
  WIDTH: 8.23,            // PRD: 单打宽度
  HALF_L: 11.885,
  HALF_W: 4.115,
  NET_HEIGHT: 0.914,      // PRD: 网高
  NET_CLEARANCE: 0.3,     // PRD: 有效击球至少过网 0.3m
  SERVICE_LINE: 6.4,      // 发球线距网
  BALL_RADIUS: 0.0335,
};

export const PHYS = {
  GRAVITY: -9.81,
  RESTITUTION: 0.72,      // PRD Prompt#1: 弹跳系数 0.72
  TANGENT_LOSS: 0.78,     // 落地水平速度保留
  DRAG: 0.12,             // 指数空气阻力 /s
  TOPSPIN_FORWARD: 1.18,  // 上旋落地前冲加成
  SLICE_FORWARD: 0.82,    // 下旋落地减速
};

export const STRIKE = {
  PERFECT_DIST: 0.8,      // PRD: <0.8m Perfect
  GOOD_DIST: 1.8,         // PRD: 0.8~1.8m Good
  DIVE_DIST: 2.5,         // PRD: 1.8~2.5m Dive/Stretch
  PERFECT_BONUS: 1.15,    // PRD: Perfect +15% 球速
  MAX_DEFLECT_DEG: 25,    // PRD: 满宽滑屏对应 ±25° 偏转角
  SWIPE_ANGLE_MAX: 75,    // 滑屏角度达到该值即映射到满偏转
  PLAYER_SPEED: 6.5,      // PRD Prompt#3: 移速 6.5 m/s
  RECOVER_SPEED: 0.6,     // PRD: 击球后 0.6x 速度回位
};

export const TUNING = {
  SWIPE_SPEED_MAX: 6000,  // px/s 满力量
  SWIPE_LEN_MAX: 1000,    // px 满力量
  POWER_MIN: 0.12,
  T_MIN: 0.62,            // 最短飞行时间(力量最大)
  T_MAX: 1.3,             // 最长飞行时间(力量最小)
  Z_DEPTH_MIN: 3.2,       // 对方半场最浅落点
  Z_DEPTH_MAX: 10.3,      // 对方半场最深落点
  SERVE_Z_MIN: 6.4,
  SERVE_Z_MAX: 10.4,
  SERVE_TOSS_Y: 2.7,
  SERVE_TOSS_Z: 10.4,
  PLAYER_BASE: { x: 0, z: -9.4 },   // PRD: 回位点 (0,0,-9.5)
  AI_BASE: { x: 0, z: 9.4 },
};

export const MATCH = {
  TARGET_POINTS: 7,       // PRD: 先到 7 分
  WIN_BY: 2,              // PRD: 需净胜 2 分
};

export const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));
export const lerp = (a, b, t) => a + (b - a) * t;
