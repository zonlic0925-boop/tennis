// 纯逻辑模块单元测试 —— node tests/run-tests.mjs
import assert from 'node:assert/strict';
import { COURT } from '../js/core/config.js';
import {
  solveLaunch, solveLaunchCorrected, ensureNetClearance, netClearance, integrate,
  predictLanding, checkInBounds, checkServeBox,
} from '../js/core/physics.js';
import { mapSwipe, strokeFromSwipe, serveFromSwipe, aiStroke } from '../js/core/strike.js';
import { Referee } from '../js/core/referee.js';

let passed = 0;
const failures = [];
function test(name, fn) {
  try {
    fn();
    passed += 1;
    console.log(`  ok  ${name}`);
  } catch (e) {
    failures.push({ name, e });
    console.error(`FAIL  ${name}\n      ${e.message}`);
  }
}
const near = (a, b, tol, msg) => assert.ok(Math.abs(a - b) <= tol, `${msg}: ${a} vs ${b} (±${tol})`);

console.log('== 物理: 弹道求解 ==');
test('solveLaunch 符合 PRD 公式', () => {
  const v = solveLaunch({ x: 0, y: 1.2, z: -9 }, { x: 2.1, z: 8.4 }, 1.0);
  near(v.vx, 2.1, 1e-9, 'vx');
  near(v.vz, 17.4, 1e-9, 'vz');
  near(v.vy, -1.2 + 4.905, 1e-9, 'vy = (-y0 - 0.5·g·T²)/T');
});

test('solveLaunchCorrected: 含空气阻力仍精确命中目标', () => {
  const p0 = { x: 0, y: 1.2, z: -9 };
  const target = { x: 2.1, z: 8.4 };
  const T = 1.0;
  const v = solveLaunchCorrected(p0, target, T);
  const s = { ...p0, ...v, spin: 'Flat' };
  const dt = 1 / 600;
  for (let t = 0; t < T; t += dt) integrate(s, dt, { bounce: false });
  near(s.x, target.x, 0.15, 'x 落点');
  near(s.z, target.z, 0.15, 'z 落点');
  near(s.y, 0, 0.25, 'y 落地');
});

test('ensureNetClearance: 平快球被抬升到过网 0.3m 以上', () => {
  const p0 = { x: 0, y: 1.2, z: -9 };
  const target = { x: 0, z: 10 };
  const { T, v } = ensureNetClearance(p0, target, 0.62);
  const clearance = netClearance(p0, v, T);
  assert.ok(clearance >= COURT.NET_HEIGHT + COURT.NET_CLEARANCE - 1e-6,
    `过网高度不足: ${clearance}`);
  assert.ok(T <= 1.3 + 1e-6, `T 超上限: ${T}`);
});

test('弹跳: 反弹系数 0.72 生效', () => {
  const s = { x: 0, y: 1, z: 0, vx: 0, vy: -4, vz: 0, spin: 'Flat' };
  const dt = 1 / 240;
  let vyBefore = null;
  let bounced = null;
  for (let i = 0; i < 400 && !bounced; i++) {
    vyBefore = s.vy;
    bounced = integrate(s, dt);
  }
  assert.ok(bounced, '应发生落地');
  assert.ok(s.vy > 0, '落地后应向上弹起');
  near(s.vy, -vyBefore * 0.72, 0.15, '反弹速度 = 0.72 × 落地瞬间速度');
});

test('predictLanding: 第一落点预测与界内外判定正确', () => {
  const v = solveLaunchCorrected({ x: 0, y: 2, z: 9 }, { x: 1, z: -8 }, 1.1);
  const inRes = predictLanding({ x: 0, y: 2, z: 9, ...v, spin: 'Flat' });
  assert.equal(inRes.net, false);
  assert.equal(inRes.inBounds, true, '界内球');
  near(inRes.pos.x, 1, 0.4, '预测落点 x');
  near(inRes.pos.z, -8, 0.6, '预测落点 z');

  const v2 = solveLaunch({ x: 0, y: 2, z: 9 }, { x: 6, z: -6 }, 1.0);
  const outRes = predictLanding({ x: 0, y: 2, z: 9, ...v2, spin: 'Flat' });
  assert.equal(outRes.inBounds, false, '出界球应判出界');

  const flat = { x: 0, y: 1.5, z: 9, vx: 0, vy: 0, vz: -20, spin: 'Flat' };
  const netRes = predictLanding(flat);
  assert.equal(netRes.net, true, '平击球应碰网');
});

test('场地/发球区校验', () => {
  assert.equal(checkInBounds(4.115, 11.885), true);
  assert.equal(checkInBounds(4.2, 0), false);
  assert.equal(checkInBounds(0, 12), false);
  // 服务器在右半区(serveSide=+1) → 球必须落在左半区
  assert.equal(checkServeBox(-2, 8, 1), true);
  assert.equal(checkServeBox(2, 8, 1), false, '发球必须进对角区');
  assert.equal(checkServeBox(-2, 5, 1), false, '发球深度不足(没过发球线)');
});

console.log('== 滑屏映射 ==');
test('满宽右滑 → 偏转 ≈ +25°', () => {
  const m = mapSwipe({ dx: 400, dy: 8, dt: 0.1, samples: [] });
  near(m.deflection, (25 * Math.PI) / 180, 0.03, '偏转角');
});

test('垂直上滑 → 偏转 0, 力量由速度决定', () => {
  const slow = mapSwipe({ dx: 0, dy: 300, dt: 0.5, samples: [] });
  const fast = mapSwipe({ dx: 0, dy: 800, dt: 0.12, samples: [] });
  near(slow.deflection, 0, 1e-6, '慢滑偏转');
  assert.ok(fast.power > slow.power, '快速长滑力量应更大');
});

test('真实屏幕输入约定: 屏幕向上滑(dy翻转后为正) → 偏转 0', () => {
  // 模拟屏幕坐标: 起点 y=550, 终点 y=220(向上), 转换后 dy=330
  const screenDy = -(220 - 550);
  const m = mapSwipe({ dx: 0, dy: screenDy, dt: 0.2, samples: [] });
  near(m.deflection, 0, 1e-6, '垂直上滑不得产生横向偏转');
  // 屏幕向下滑 → dy 为负 → 偏转向下
  const m2 = mapSwipe({ dx: 0, dy: -(550 - 220), dt: 0.2, samples: [] });
  assert.ok(Math.abs(m2.deflection) > 0.3, '下滑应有明显偏转');
});

test('曲线滑屏 → 识别旋转类型', () => {
  const curve = mapSwipe({
    dx: 0, dy: 500, dt: 0.2,
    samples: [{ x: 0, y: 0 }, { x: 80, y: 250 }, { x: 0, y: 500 }],
  });
  assert.equal(curve.spin, 'Topspin');
  const flat = mapSwipe({ dx: 0, dy: 500, dt: 0.2, samples: [{ x: 0, y: 0 }, { x: 0, y: 250 }, { x: 0, y: 500 }] });
  assert.equal(flat.spin, 'Flat');
});

test('strokeFromSwipe: 落点在对方半场且过网', () => {
  const m = mapSwipe({ dx: 0, dy: 700, dt: 0.15, samples: [] });
  const r = strokeFromSwipe(m, { x: 0, y: 1.2, z: -9 }, 1);
  assert.ok(r.target.z > 0, '目标在对方半场');
  assert.ok(netClearance({ x: 0, y: 1.2, z: -9 }, r.v, r.T) >= COURT.NET_HEIGHT + 0.3 - 1e-6, '过网');
});

test('serveFromSwipe: 发球落点在对角发球区', () => {
  const m = mapSwipe({ dx: 0, dy: 700, dt: 0.15, samples: [] });
  const from = { x: 1.25, y: 2.7, z: -10.4 };
  const r = serveFromSwipe(m, 1, from, 1);
  assert.equal(checkServeBox(r.target.x, r.target.z, 1), true, `发球目标应在区内: ${r.target.x},${r.target.z}`);
});

test('aiStroke: 目标始终在玩家半场', () => {
  for (let i = 0; i < 50; i++) {
    const r = aiStroke({ x: (Math.random() - 0.5) * 8, z: -8 }, 0.7, { x: 0, y: 1.2, z: 9 }, -1);
    assert.ok(r.target.z < 0, 'AI 回球到玩家半场');
    assert.ok(Math.abs(r.target.x) <= 5.2);
  }
});

console.log('== 裁判状态机 ==');
test('双误 → 接发方得分, 发球轮换', () => {
  const r = new Referee();
  r.startMatch();
  const f1 = r.onServeFault('p1');
  assert.equal(f1.doubleFault, false);
  assert.equal(r.state.serveAttempt, 2);
  const f2 = r.onServeFault('p1');
  assert.equal(f2.phase, 'point_end');
  assert.equal(r.score.p2, 1);
  assert.equal(r.state.server, 'p2', '每分后轮换发球');
  r.nextServe();
  assert.equal(r.state.phase, 'serve');
});

test('6-6 → 7-6 领先 1 分不结束, 比赛继续', () => {
  const r = new Referee();
  r.startMatch();
  for (let i = 0; i < 12; i++) {
    const res = r.onRallyEnd(i % 2 === 0 ? 'p1' : 'p2', 'test');
    assert.notEqual(res.phase, 'match_end', '6-6 前不应结束');
    r.nextServe();
  }
  assert.equal(r.score.p1, 6);
  assert.equal(r.score.p2, 6);
  let result = r.onRallyEnd('p1', 'test'); // 7-6
  assert.notEqual(result.phase, 'match_end', '7-6 领先 1 分不应结束');
  r.nextServe();
  result = r.onRallyEnd('p2', 'test'); // 7-7
  assert.notEqual(result.phase, 'match_end', '7-7 平不应结束');
});

test('7-7 后连赢 2 分, 9-7 结束比赛', () => {
  const r = new Referee();
  r.startMatch();
  let result = null;
  for (let i = 0; i < 14; i++) {
    result = r.onRallyEnd(i % 2 === 0 ? 'p1' : 'p2', 'test');
    r.nextServe();
  }
  assert.equal(r.score.p1, 7);
  assert.equal(r.score.p2, 7);
  result = r.onRallyEnd('p1', 'test'); // 8-7
  assert.notEqual(result.phase, 'match_end');
  r.nextServe();
  result = r.onRallyEnd('p1', 'test'); // 9-7
  assert.equal(result.phase, 'match_end');
  assert.equal(result.winner, 'p1');
  assert.equal(r.score.p1, 9);
  assert.equal(r.score.p2, 7);
});

console.log('');
if (failures.length) {
  console.error(`\n${failures.length} 项失败 / ${passed + failures.length} 项`);
  process.exit(1);
} else {
  console.log(`全部通过: ${passed} 项`);
}
