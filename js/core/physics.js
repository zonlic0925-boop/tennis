// 弹道物理 —— PRD §2.2 / §4 Prompt#1
// 纯函数模块，不依赖渲染，可直接单测。

import { COURT, PHYS, TUNING, clamp } from './config.js';

const { GRAVITY, RESTITUTION, TANGENT_LOSS, DRAG, TOPSPIN_FORWARD, SLICE_FORWARD } = PHYS;
const SIM_DT = 1 / 240;

// 半隐式欧拉积分一步。返回 bounce 事件(若落地)。
export function integrate(state, dt, { bounce = true } = {}) {
  const drag = Math.exp(-DRAG * dt);
  state.vx *= drag;
  state.vy += GRAVITY * dt;
  state.vz *= drag;
  state.x += state.vx * dt;
  state.y += state.vy * dt;
  state.z += state.vz * dt;

  if (bounce && state.y <= COURT.BALL_RADIUS && state.vy < 0) {
    state.y = COURT.BALL_RADIUS;
    state.vy = -state.vy * RESTITUTION;
    let keep = TANGENT_LOSS;
    if (state.spin === 'Topspin') keep *= TOPSPIN_FORWARD;
    else if (state.spin === 'Slice') keep *= SLICE_FORWARD;
    state.vx *= keep;
    state.vz *= keep;
    return { bounced: true, at: { x: state.x, z: state.z } };
  }
  return null;
}

// PRD §2.2 弹道发射公式: 给定起点/落点/飞行时间 T, 反解初速度(无阻力解析解)。
export function solveLaunch(p0, target, T) {
  return {
    vx: (target.x - p0.x) / T,
    vz: (target.z - p0.z) / T,
    vy: (-p0.y - 0.5 * GRAVITY * T * T) / T,
  };
}

// 在解析解基础上迭代修正 vx/vz, 抵消空气阻力导致的落点偏差。
export function solveLaunchCorrected(p0, target, T) {
  const v = solveLaunch(p0, target, T);
  const steps = Math.max(1, Math.round(T / SIM_DT));
  for (let i = 0; i < 3; i++) {
    const s = { x: p0.x, y: p0.y, z: p0.z, ...v, spin: 'Flat' };
    for (let j = 0; j < steps; j++) integrate(s, SIM_DT, { bounce: false });
    v.vx += (target.x - s.x) / T;
    v.vz += (target.z - s.z) / T;
  }
  return v;
}

// 球过网(z=0)瞬间的高度；不过网返回 1e9。
export function netClearance(p0, v, T) {
  if (Math.abs(v.vz) < 1e-6) return 1e9;
  const tc = (0 - p0.z) / v.vz;
  if (tc <= 0 || tc >= T) return 1e9;
  return p0.y + v.vy * tc + 0.5 * GRAVITY * tc * tc;
}

// PRD: 有效击球需净过网 NET_HEIGHT+0.3。抬高弧线(T 增大)直至满足, 上限 T_MAX。
// 判定留 0.06m 余量补偿阻力引起的实际高度略降; 最终速度经阻力修正。
export function ensureNetClearance(p0, target, T) {
  let t = clamp(T, TUNING.T_MIN, TUNING.T_MAX);
  for (let i = 0; i < 40; i++) {
    const v = solveLaunch(p0, target, t);
    if (netClearance(p0, v, t) >= COURT.NET_HEIGHT + COURT.NET_CLEARANCE + 0.06) {
      return { T: t, v: solveLaunchCorrected(p0, target, t) };
    }
    if (t >= TUNING.T_MAX) break;
    t = Math.min(t + 0.04, TUNING.T_MAX);
  }
  return { T: t, v: solveLaunchCorrected(p0, target, t) };
}

// 从当前状态前推模拟到首次落地/碰网, 用于落点指示器与 AI 跑位。
// PRD §3 Module 4: 对手客户端确定性弹道模拟 + 落点地面标记。
export function predictLanding(state, { maxT = 6 } = {}) {
  const s = { ...state };
  let t = 0;
  while (t < maxT) {
    const px = s.x, py = s.y, pz = s.z;
    integrate(s, SIM_DT, { bounce: false });
    t += SIM_DT;
    // 碰网
    if ((pz <= 0 && s.z > 0) || (pz >= 0 && s.z < 0)) {
      const f = pz / (pz - s.z);
      const yAt = py + f * (s.y - py);
      if (yAt < COURT.NET_HEIGHT) return { net: true, t, pos: { x: s.x, z: 0 } };
    }
    // 首次落地(线性插值取地面交点), 只关心第一落点
    if (py > COURT.BALL_RADIUS && s.y <= COURT.BALL_RADIUS && s.vy < 0) {
      const f = (py - COURT.BALL_RADIUS) / (py - s.y);
      const x = px + f * (s.x - px);
      const z = pz + f * (s.z - pz);
      return { net: false, t, pos: { x, z }, inBounds: checkInBounds(x, z) };
    }
  }
  return { net: false, t: maxT, pos: { x: s.x, z: s.z }, inBounds: false };
}

export function checkInBounds(x, z) {
  return Math.abs(x) <= COURT.HALF_W && Math.abs(z) <= COURT.HALF_L;
}

// 发球区校验: 对角线半区, |z| ∈ [发球线, 底线]。
export function checkServeBox(x, z, serverSide) {
  const inDepth = Math.abs(z) >= COURT.SERVICE_LINE && Math.abs(z) <= COURT.HALF_L;
  const inDiagonal = Math.sign(x) === -serverSide && Math.abs(x) <= COURT.HALF_W;
  return inDepth && inDiagonal;
}
