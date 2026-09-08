// 滑屏 → 击球参数映射 —— PRD §2.2 (Swipe Vector to Velocity Vector)
// 纯函数模块。

import { COURT, STRIKE, TUNING, clamp, lerp } from './config.js';
import { ensureNetClearance } from './physics.js';

const RAD = Math.PI / 180;

// swipe = { dx, dy, dt(秒), samples:[{x,y}] }, 约定: dy 向上为正(屏幕坐标已翻转)
// 返回 { power, deflection(弧度), spin, len, speed }
export function mapSwipe(swipe) {
  const len = Math.hypot(swipe.dx, swipe.dy);
  const speed = len / Math.max(swipe.dt, 0.05);

  // PRD: θx = atan2(Δx, Δy) × K_angle, 满宽滑屏 → ±25°
  const angle = Math.atan2(swipe.dx, swipe.dy); // 0 = 正上方
  const n = clamp(angle / (STRIKE.SWIPE_ANGLE_MAX * RAD), -1, 1);
  const deflection = n * STRIKE.MAX_DEFLECT_DEG * RAD;

  // PRD: 目标 Z 由滑屏速度与长度共同决定
  const power = clamp(
    0.62 * (speed / TUNING.SWIPE_SPEED_MAX) + 0.38 * (len / TUNING.SWIPE_LEN_MAX),
    TUNING.POWER_MIN,
    1
  );

  return { power, deflection, spin: detectSpin(swipe.samples), len, speed };
}

// 滑屏轨迹曲率 → 旋转类型(PRD §3 网络包 schema: Flat/Topspin/Slice)
function detectSpin(samples) {
  if (!samples || samples.length < 3) return 'Flat';
  const a = samples[0];
  const b = samples[samples.length - 1];
  const L = Math.hypot(b.x - a.x, b.y - a.y);
  if (L < 1e-6) return 'Flat';
  const mid = samples[Math.floor(samples.length / 2)];
  const dev = ((mid.x - a.x) * (b.y - a.y) - (mid.y - a.y) * (b.x - a.x)) / L;
  const rel = dev / L;
  if (rel > 0.12) return 'Topspin';
  if (rel < -0.12) return 'Slice';
  return 'Flat';
}

// 常规回球: 由滑屏映射计算对方半场落点并反解初速度。
// from: 击球点, dir: +1 打向 z>0 半场 / -1 反之
export function strokeFromSwipe(mapped, from, dir = 1) {
  const depth = lerp(TUNING.Z_DEPTH_MIN, TUNING.Z_DEPTH_MAX, mapped.power);
  const target = {
    x: clamp(from.x + Math.tan(mapped.deflection) * Math.abs(depth * dir - from.z), -5.2, 5.2),
    z: dir * depth,
  };
  const T = lerp(TUNING.T_MAX, TUNING.T_MIN, mapped.power);
  const solved = ensureNetClearance(from, target, T);
  return {
    target,
    T: solved.T,
    v: solved.v,
    spin: mapped.spin,
    power: mapped.power,
  };
}

// 发球: 落点约束在对角发球区, |x| 由偏转角映射到 [0.5, 3.8]。
export function serveFromSwipe(mapped, serveSide, from, dir = 1) {
  const tz = dir * lerp(TUNING.SERVE_Z_MIN, TUNING.SERVE_Z_MAX, mapped.power);
  const mag = clamp(Math.abs(mapped.deflection) / (STRIKE.MAX_DEFLECT_DEG * RAD), 0, 1);
  const tx = -serveSide * (0.5 + mag * 3.3);
  const T = lerp(1.4, 1.0, mapped.power);
  const solved = ensureNetClearance(from, { x: tx, z: tz }, T);
  return { target: { x: tx, z: tz }, T: solved.T, v: solved.v, spin: 'Flat', power: mapped.power };
}

// AI 自动击球参数: 目标在玩家半场, 尽量打向远离玩家当前位置的一侧。
export function aiStroke(playerPos, difficulty, from, dir = -1) {
  const away = playerPos.x > 0 ? -1 : 1;
  const goAway = Math.random() < 0.72;
  let tx;
  if (goAway) {
    tx = clamp(away * (1.8 + Math.random() * 1.7) + (Math.random() - 0.5) * 0.8, -3.7, 3.7);
  } else {
    tx = clamp(playerPos.x + (Math.random() - 0.5) * 2.4, -3.7, 3.7);
  }
  const tz = dir * lerp(TUNING.Z_DEPTH_MIN, TUNING.Z_DEPTH_MAX, 0.35 + 0.65 * Math.random());
  const power = 0.42 + 0.42 * difficulty + Math.random() * 0.18;
  const T = lerp(TUNING.T_MAX, TUNING.T_MIN, power);
  const solved = ensureNetClearance(from, { x: tx, z: tz }, T);
  return {
    target: { x: tx, z: tz },
    T: solved.T,
    v: solved.v,
    spin: Math.random() < 0.3 ? 'Topspin' : 'Flat',
    power,
  };
}
