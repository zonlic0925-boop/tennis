// 游戏编排 —— 输入 / 移动 / AI / 物理步进 / 裁判接线 / 相机
// 对应 PRD §3: TouchInputController + PlayerMovementController + MatchReferee + CameraController
import * as THREE from 'three';
import { createScene, createPlayerRig } from './render/scene.js';
import { createFx } from './render/fx.js';
import { createAudio } from './render/audio.js';
import { createUI } from './ui.js';
import { COURT, STRIKE, TUNING, clamp } from './core/config.js';
import {
  integrate, predictLanding, checkInBounds, checkServeBox, solveLaunchCorrected,
} from './core/physics.js';
import { mapSwipe, strokeFromSwipe, serveFromSwipe, aiStroke } from './core/strike.js';
import { Referee } from './core/referee.js';

const STEP = 1 / 120; // 物理子步

const REASON_TEXT = {
  out: (p) => (p ? '对手出界，得分！' : '出界，对手得分'),
  net: (p) => (p ? '对手下网，得分！' : '下网，对手得分'),
  doubleBounce: (p) => (p ? '对手没接住，得分！' : '没接住，对手得分'),
  doubleFault: (p) => (p ? '对手双误，得分！' : '双误，对手得分'),
};

export class Game {
  constructor(domElement) {
    this.dom = domElement;
    this.ui = createUI();
    this.audio = createAudio();
    this.referee = new Referee();
    this.difficulty = 0.55;
    this.autoPlay = false;

    const { scene, camera, ball } = createScene();
    this.scene = scene;
    this.camera = camera;
    this.ballMesh = ball;

    this.p1 = {
      pos: { x: 0, z: TUNING.PLAYER_BASE.z },
      rig: null, landing: null, landingShot: -1, strikeDelay: 0, hasStruck: true,
    };
    this.p2 = {
      pos: { x: 0, z: TUNING.AI_BASE.z },
      rig: null, landing: null, landingShot: -1, strikeDelay: 0, hasStruck: true,
    };

    this.ball = { x: 0, y: 2.7, z: 0, vx: 0, vy: 0, vz: 0, spin: 'Flat', active: false };
    this.awaitingServe = null;
    this.lastStriker = null;
    this.lastBounceSide = null;
    this.hasBouncedShot = false; // 本次击球是否已合法落地(用于出界/两跳判定)
    this.struckShotIds = { p1: -1, p2: -1 }; // 同一球只允许击打一次
    this.serveSide = -1;
    this.shotId = 0;
    this.pointEndTimer = 0;
    this.aiServeTimer = 0;
    this.phaseKey = '';
    this.hintKey = '';
    this.started = false;
    this.lastNow = performance.now();

    this._buildRigs();
    this.fx = createFx(scene);
    this._bindInput();
    this._bindUI();
    this._syncScore();
  }

  _buildRigs() {
    const r1 = createPlayerRig({ shirt: 0xff5a4e, cap: 0xf5faff });
    const r2 = createPlayerRig({ shirt: 0xffc53d, cap: 0x1b3a5c });
    r2.group.rotation.y = Math.PI;
    this.scene.add(r1.group, r2.group);
    this.p1.rig = r1;
    this.p2.rig = r2;
    this._placeRigs();
  }

  _placeRigs() {
    this.p1.rig.group.position.set(this.p1.pos.x, 0, this.p1.pos.z);
    this.p2.rig.group.position.set(this.p2.pos.x, 0, this.p2.pos.z);
  }

  _bindInput() {
    const dom = this.dom;
    let down = null;
    const pos = (e) => {
      const r = dom.getBoundingClientRect();
      return { x: e.clientX - r.left, y: e.clientY - r.top };
    };
    dom.addEventListener('pointerdown', (e) => {
      this.audio.ensure();
      const p = pos(e);
      down = { x0: p.x, y0: p.y, t0: performance.now(), samples: [] };
    });
    dom.addEventListener('pointermove', (e) => {
      if (!down) return;
      const p = pos(e);
      down.samples.push({ x: p.x, y: p.y });
      if (down.samples.length > 30) down.samples.shift();
    });
    const finish = (e) => {
      if (!down) return;
      const p = pos(e);
      const t1 = performance.now();
      // 屏幕 y 向下为正 → 转为"向上为正"的滑动向量(mapSwipe 约定)
      const swipe = {
        dx: p.x - down.x0,
        dy: -(p.y - down.y0),
        dt: (t1 - down.t0) / 1000,
        samples: [...down.samples, { x: p.x, y: p.y }],
      };
      down = null;
      this.routeSwipe(swipe);
    };
    dom.addEventListener('pointerup', finish);
    dom.addEventListener('pointercancel', finish);
  }

  _bindUI() {
    this.ui.onStart(() => this.startMatch());
    this.ui.onAgain(() => this.restart());
  }

  // ============ 比赛流程 ============

  startMatch() {
    this.audio.ensure();
    this.referee.reset();
    this.referee.startMatch();
    this.started = true;
    this.ui.hideStart();
    this.ui.hideEnd();
    this.ui.showHud();
    this._syncScore();
    this.setupServe(this.referee.state.server);
  }

  restart() {
    this.startMatch();
  }

  get totalPoints() {
    return this.referee.score.p1 + this.referee.score.p2;
  }

  setupServe(server) {
    this.awaitingServe = { server, done: false };
    this.serveSide = this.totalPoints % 2 === 0 ? -1 : 1;
    const dir = server === 'p1' ? -1 : 1;
    const toss = { x: this.serveSide * 1.4, y: TUNING.SERVE_TOSS_Y, z: dir * TUNING.SERVE_TOSS_Z };
    this.tossPos = toss;
    Object.assign(this.ball, toss, { vx: 0, vy: 0, vz: 0, spin: 'Flat', active: false });
    this.lastBounceSide = null;
    this.aiServeTimer = 1.15 + Math.random() * 0.7;
    this.fx.hideLanding();
    this.fx.hideReticle();
    // 站位
    if (server === 'p1') {
      this.p1.moveTarget = { x: this.serveSide * 1.7, z: -9.8 };
      this.p2.moveTarget = { x: -this.serveSide * 1.4, z: 8.6 };
    } else {
      this.p2.moveTarget = { x: this.serveSide * 1.7, z: 9.8 };
      this.p1.moveTarget = { x: -this.serveSide * 1.4, z: -8.6 };
    }
  }

  // 滑屏路由: 发球 或 回合击球(PRD §3 Module 1 输入生命周期)
  routeSwipe(swipe) {
    if (!this.started || this.autoPlay) return;
    const s = this.referee.state;
    if (s.phase === 'serve' && this.awaitingServe && !this.awaitingServe.done && s.server === 'p1') {
      this.execServe('p1', mapSwipe(swipe));
    } else if (s.phase === 'rally') {
      this.tryStrike('p1', mapSwipe(swipe));
    }
  }

  execServe(server, mapped) {
    const dir = server === 'p1' ? 1 : -1;
    const from = { ...this.tossPos };
    const r = serveFromSwipe(mapped, this.serveSide, from, dir);
    this.launch(server, from, r, 'good');
    this.awaitingServe.done = true;
  }

  // 通用发射: 设速度/旋转/归属/动画; 对手击球后显示落点指示器(PRD §5.1)
  launch(striker, from, r, tier) {
    Object.assign(this.ball, from, { ...r.v, spin: r.spin, active: true });
    this.lastStriker = striker;
    this.lastBounceSide = null;
    this.hasBouncedShot = false;
    this.shotId += 1;
    this.struckShotIds[striker] = this.shotId;
    this.fx.hideLanding();
    const rig = striker === 'p1' ? this.p1.rig : this.p2.rig;
    rig.anim.swingT = 0;
    this.audio.hit(tier);
    if (striker === 'p2') {
      const pred = predictLanding(this.ball);
      if (pred && !pred.net) this.fx.showLanding(pred.pos.x, pred.pos.z, pred.inBounds);
    }
  }

  tryStrike(side, mapped) {
    if (this.struckShotIds[side] === this.shotId) return false; // 同一球只击一次
    const tier = this.tierAt(side);
    if (!tier) {
      this.audio.whiff();
      return false;
    }
    const p = side === 'p1' ? this.p1 : this.p2;
    const dir = side === 'p1' ? 1 : -1;
    const from = {
      x: p.pos.x + 0.3 * dir,
      y: clamp(this.ball.y, 0.7, 2.4),
      z: p.pos.z + 0.55 * dir,
    };
    let r;
    if (tier === 'dive') {
      // PRD: Dive/Stretch → 高吊弱回球
      const weak = { power: 0.3, deflection: mapped.deflection * 0.5, spin: 'Flat' };
      r = strokeFromSwipe(weak, from, dir);
    } else {
      r = strokeFromSwipe(mapped, from, dir);
      if (tier === 'perfect') {
        r.v.vx *= STRIKE.PERFECT_BONUS;
        r.v.vy *= STRIKE.PERFECT_BONUS;
        r.v.vz *= STRIKE.PERFECT_BONUS;
      } else {
        r.v.vx *= 1 + (Math.random() - 0.5) * 0.04;
        r.v.vz *= 1 + (Math.random() - 0.5) * 0.04;
      }
    }
    this.launch(side, from, r, tier === 'dive' ? 'good' : tier);
    return true;
  }

  // 击球时机三档判定(PRD: <0.8 Perfect / 0.8~1.8 Good / 1.8~2.5 Dive)
  tierAt(side) {
    if (!this.ball.active || this.ball.y > 3.1) return null;
    const p = side === 'p1' ? this.p1 : this.p2;
    const dir = side === 'p1' ? 1 : -1;
    const behind = (this.ball.z - p.pos.z) * dir < -1.3;   // 球已在身后
    const overNet = this.ball.z * dir > 0.2;               // 球仍在对方半场
    if (behind || overNet) return null;
    const px = p.pos.x + 0.25 * dir;
    const pz = p.pos.z + 0.5 * dir;
    const d = Math.hypot(this.ball.x - px, this.ball.z - pz);
    if (d < STRIKE.PERFECT_DIST) return 'perfect';
    if (d < STRIKE.GOOD_DIST) return 'good';
    if (d <= STRIKE.DIVE_DIST) return 'dive';
    return null;
  }

  // ============ 事件判定 ============

  onNetHit() {
    this.audio.net();
    if (this.awaitingServe) {
      this.serveFault();
    } else if (this.referee.state.phase === 'rally') {
      this.awardPoint(this.referee.other(this.lastStriker), 'net');
    }
  }

  serveFault() {
    const server = this.awaitingServe.server;
    this.awaitingServe = null;
    this.audio.fault();
    const res = this.referee.onServeFault(server);
    if (res && res.doubleFault) {
      // referee 已完成判分, 这里只做表现层收尾
      this.pointAwarded(this.referee.other(server), 'doubleFault');
    } else {
      this.ui.toast('发球失误', 'bad');
      this.setupServe(server);
    }
  }

  resolveServeBounce(at) {
    this.hasBouncedShot = true;
    if (checkServeBox(at.x, at.z, this.serveSide)) {
      this.audio.bounce();
      this.referee.onServeIn(this.awaitingServe.server);
      this.awaitingServe = null;
      this.lastBounceSide = Math.sign(at.z);
    } else {
      this.serveFault();
    }
  }

  resolveRallyBounce(at) {
    this.hasBouncedShot = true;
    this.audio.bounce();
    if (!checkInBounds(at.x, at.z)) {
      this.awardPoint(this.referee.other(this.lastStriker), 'out');
      return;
    }
    const side = Math.sign(at.z);
    if (side === this.lastBounceSide) {
      this.awardPoint(this.lastStriker, 'doubleBounce');
    } else {
      this.lastBounceSide = side;
    }
  }

  awardPoint(winner, reason) {
    const res = this.referee.onRallyEnd(winner, reason);
    if (!res) return;
    this.pointAwarded(winner, reason);
  }

  // 表现层收尾(referee 可能已判分, 如双误)
  pointAwarded(winner, reason) {
    this.ball.active = false;
    this.fx.hideLanding();
    this.fx.hideReticle();
    this.ui.bumpScore(winner);
    const isP1 = winner === 'p1';
    this.ui.toast(REASON_TEXT[reason]?.(isP1) ?? '得分！', isP1 ? 'good' : 'bad');
    this.audio.point();
    this.pointEndTimer = this.referee.state.phase === 'match_end' ? 1.15 : 1.5;
  }

  finishPoint() {
    const s = this.referee.state;
    if (s.phase === 'match_end') {
      const winnerIsPlayer = s.matchWinner === 'p1';
      this.ui.showResult(winnerIsPlayer, `${this.referee.score.p1} — ${this.referee.score.p2}`);
      if (winnerIsPlayer) this.audio.win();
      else this.audio.lose();
      return;
    }
    this.referee.nextServe();
    this.setupServe(this.referee.state.server);
  }

  // ============ 每帧更新 ============

  update(dtOverride = null) {
    const now = performance.now();
    const dt = Math.min(dtOverride ?? (now - this.lastNow) / 1000, 0.05);
    this.lastNow = now;
    const s = this.referee.state;

    if (this.started) {
      if (this.autoPlay) this.autoPilot(dt, s);
      else this.playerUpdate(dt, s);
      this.aiUpdate(dt, s);
      this.stepBall(dt, s);

      if (s.phase === 'point_end' || s.phase === 'match_end') {
        this.pointEndTimer -= dt;
        if (this.pointEndTimer <= 0) this.finishPoint();
      }
    }

    // 渲染同步
    this._placeRigs();
    this.p1.rig.update(dt);
    this.p2.rig.update(dt);
    this.ballMesh.position.set(this.ball.x, this.ball.y, this.ball.z);
    this.ballMesh.visible = this.awaitingServe !== null || this.ball.active;
    this.fx.update(dt, this.ball, this.ball.active, this.p1.pos.x, this.p1.pos.z);
    this.updateReticle(s);
    this.updateHint(s);
    this.cameraUpdate(dt);
    this.syncPhaseLabel(s);
  }

  resize(w, h) {
    this.camera.aspect = w / h;
    this.camera.updateProjectionMatrix();
  }

  // ---- 玩家移动(自动跑位 + 击球后 0.6x 回位, PRD §3 Module 2) ----
  playerUpdate(dt, s) {
    const p = this.p1;
    let target = null;
    let factor = 1;
    // 对方发球在空中时即预判落点跑位
    const serveIncoming = s.phase === 'serve' && this.awaitingServe && this.awaitingServe.done && s.server === 'p2';

    if (s.phase === 'serve' && !serveIncoming) {
      target = p.moveTarget ?? (s.server === 'p1' ? { x: this.serveSide * 1.7, z: -9.8 } : { x: -this.serveSide * 1.4, z: -8.6 });
    } else if ((s.phase === 'rally' || serveIncoming) && this.ball.active && (this.ball.vz < 0 || this.ball.z < 0)) {
      if (p.landingShot !== this.shotId) {
        p.landingShot = this.shotId;
        p.landing = predictLanding(this.ball);
      }
      if (p.landing && !p.landing.net && p.landing.inBounds) {
        target = {
          x: clamp(p.landing.pos.x, -3.9, 3.9),
          z: clamp(p.landing.pos.z + 0.6, -10.4, -4.0),
        };
      }
    } else if (s.phase !== 'point_end' && s.phase !== 'match_end') {
      target = { x: TUNING.PLAYER_BASE.x, z: TUNING.PLAYER_BASE.z };
      factor = STRIKE.RECOVER_SPEED;
    }

    if (target) this.moveToward(p, target, STRIKE.PLAYER_SPEED * factor, dt);
    else this.markMove(p, 0);
  }

  // ---- AI: 跑位 + 回球 + 发球(含失误概率) ----
  aiUpdate(dt, s) {
    const ai = this.p2;
    // 对方发球在空中时即预判落点跑位
    const serveIncoming = s.phase === 'serve' && this.awaitingServe && this.awaitingServe.done && s.server === 'p1';

    if (s.phase === 'serve' && s.server === 'p2' && !serveIncoming) {
      if (ai.moveTarget) this.moveToward(ai, ai.moveTarget, STRIKE.PLAYER_SPEED, dt);
      if (!this.awaitingServe.done) {
        this.aiServeTimer -= dt;
        if (this.aiServeTimer <= 0) this.aiServe();
      }
      return;
    }

    if ((s.phase === 'rally' || serveIncoming) && this.ball.active && (this.ball.vz > 0 || this.ball.z > 0)) {
      if (ai.landingShot !== this.shotId) {
        ai.landingShot = this.shotId;
        ai.landing = predictLanding(this.ball);
        ai.hasStruck = false;
        ai.strikeDelay = 0.08 + Math.random() * 0.08;
      }
      let target = null;
      if (ai.landing && !ai.landing.net && ai.landing.inBounds) {
        target = {
          x: clamp(ai.landing.pos.x, -3.9, 3.9),
          z: clamp(Math.abs(ai.landing.pos.z) - 0.7, 3.5, 10.2),
        };
      }
      if (target) this.moveToward(ai, target, STRIKE.PLAYER_SPEED, dt);

      // 击球窗口: 球接近时提前启动反应计时, 弹起瞬间挥拍(接发不抢攻)
      if (!ai.hasStruck) {
        const d = Math.hypot(this.ball.x - ai.pos.x, this.ball.z - ai.pos.z);
        if (d < 1.3 && (s.phase === 'rally' || serveIncoming)) {
          ai.strikeDelay -= dt;
          if (ai.strikeDelay <= 0 && s.phase === 'rally' && d < 1.8 && this.ball.y < 3.1) {
            this.aiStrike();
          }
        }
      }
    } else if (s.phase === 'serve') {
      if (ai.moveTarget) this.moveToward(ai, ai.moveTarget, STRIKE.PLAYER_SPEED, dt);
    } else if (s.phase !== 'point_end' && s.phase !== 'match_end') {
      this.moveToward(ai, { x: TUNING.AI_BASE.x, z: TUNING.AI_BASE.z }, STRIKE.PLAYER_SPEED * STRIKE.RECOVER_SPEED, dt);
    } else {
      this.markMove(ai, 0);
    }
  }

  aiServe() {
    const from = { ...this.tossPos };
    const mapped = {
      power: 0.55 + Math.random() * 0.3,
      deflection: (Math.random() * 2 - 1) * 0.35,
      spin: 'Flat',
    };
    let r = serveFromSwipe(mapped, this.serveSide, from, -1);
    // 失误概率随难度下降
    if (Math.random() < (1 - this.difficulty) * 0.16) {
      if (Math.random() < 0.6) {
        const t = { x: r.target.x, z: -12.4 }; // 出界(过长)
        r = { ...r, target: t, v: solveLaunchCorrected(from, t, r.T) };
      } else {
        r = { ...r, v: { ...r.v, vy: 0.4 } }; // 下网(平飞)
      }
    }
    this.launch('p2', from, r, 'good');
    this.awaitingServe.done = true;
  }

  aiStrike() {
    const ai = this.p2;
    ai.hasStruck = true;
    if (Math.random() < (1 - this.difficulty) * 0.1) {
      this.audio.whiff();
      return;
    }
    const from = { x: ai.pos.x - 0.3, y: clamp(this.ball.y, 0.7, 2.4), z: ai.pos.z - 0.55 };
    const r = aiStroke(this.p1.pos, this.difficulty, from, -1);
    if (Math.random() < 0.2) {
      r.v.vx *= STRIKE.PERFECT_BONUS;
      r.v.vy *= STRIKE.PERFECT_BONUS;
      r.v.vz *= STRIKE.PERFECT_BONUS;
    }
    this.launch('p2', from, r, 'good');
  }

  // ---- 自动演示/调试: 玩家侧也由 AI 逻辑驱动 ----
  autoPilot(dt, s) {
    const p = this.p1;
    const serveIncoming = s.phase === 'serve' && this.awaitingServe && this.awaitingServe.done && s.server === 'p2';

    if (s.phase === 'serve' && s.server === 'p1' && !serveIncoming) {
      if (p.moveTarget) this.moveToward(p, p.moveTarget, STRIKE.PLAYER_SPEED, dt);
      if (!this.awaitingServe.done) {
        this.aiServeTimer -= dt;
        if (this.aiServeTimer <= 0) {
          const from = { ...this.tossPos };
          const mapped = {
            power: 0.58 + Math.random() * 0.25,
            deflection: (Math.random() * 2 - 1) * 0.4,
            spin: 'Flat',
          };
          const r = serveFromSwipe(mapped, this.serveSide, from, 1);
          this.launch('p1', from, r, 'good');
          this.awaitingServe.done = true;
        }
      }
      return;
    }

    if (s.phase === 'serve' && !serveIncoming) {
      if (p.moveTarget) this.moveToward(p, p.moveTarget, STRIKE.PLAYER_SPEED, dt);
      return;
    }

    if ((s.phase === 'rally' || serveIncoming) && this.ball.active && (this.ball.vz < 0 || this.ball.z < 0)) {
      if (p.landingShot !== this.shotId) {
        p.landingShot = this.shotId;
        p.landing = predictLanding(this.ball);
        p.hasStruck = false;
        p.strikeDelay = 0.08 + Math.random() * 0.08;
      }
      let target = null;
      if (p.landing && !p.landing.net && p.landing.inBounds) {
        target = {
          x: clamp(p.landing.pos.x, -3.9, 3.9),
          z: clamp(p.landing.pos.z + 0.6, -10.4, -4.0),
        };
      }
      if (target) this.moveToward(p, target, STRIKE.PLAYER_SPEED, dt);

      if (!p.hasStruck) {
        const d = Math.hypot(this.ball.x - p.pos.x, this.ball.z - p.pos.z);
        if (d < 1.3 && (s.phase === 'rally' || serveIncoming)) {
          p.strikeDelay -= dt;
          if (p.strikeDelay <= 0 && s.phase === 'rally' && d < 1.8 && this.ball.y < 3.1) {
            p.hasStruck = true;
            if (Math.random() < (1 - this.difficulty) * 0.08) {
              this.audio.whiff();
              return;
            }
            const from = { x: p.pos.x + 0.3, y: clamp(this.ball.y, 0.7, 2.4), z: p.pos.z + 0.55 };
            const r = aiStroke(this.p2.pos, this.difficulty, from, 1);
            this.launch('p1', from, r, 'good');
          }
        }
      }
    } else if (s.phase !== 'point_end' && s.phase !== 'match_end') {
      this.moveToward(p, { x: TUNING.PLAYER_BASE.x, z: TUNING.PLAYER_BASE.z }, STRIKE.PLAYER_SPEED * STRIKE.RECOVER_SPEED, dt);
    } else {
      this.markMove(p, 0);
    }
  }

  moveToward(actor, target, speed, dt) {
    const dx = target.x - actor.pos.x;
    const dz = target.z - actor.pos.z;
    const dist = Math.hypot(dx, dz);
    if (dist < 0.06) {
      this.markMove(actor, 0);
      return;
    }
    const step = Math.min(speed * dt, dist);
    actor.pos.x += (dx / dist) * step;
    actor.pos.z += (dz / dist) * step;
    this.markMove(actor, 1);
  }

  markMove(actor, v) {
    actor.rig.anim.moving = Math.max(actor.rig.anim.moving, v);
  }

  // ---- 球物理步进 + 事件 ----
  stepBall(dt, s) {
    if (!this.ball.active) return;
    const steps = Math.max(1, Math.round(dt / STEP));
    const h = dt / steps;
    for (let i = 0; i < steps; i++) {
      if (!this.ball.active) return;
      const prevZ = this.ball.z;
      const prevY = this.ball.y;
      const ev = integrate(this.ball, h, { bounce: true });
      // 过网判定
      if ((prevZ <= 0 && this.ball.z > 0) || (prevZ >= 0 && this.ball.z < 0)) {
        const f = prevZ / (prevZ - this.ball.z);
        const yAt = prevY + f * (this.ball.y - prevY);
        if (yAt < COURT.NET_HEIGHT) {
          this.onNetHit();
          return;
        }
      }
      // 落地判定
      if (ev) {
        if (this.awaitingServe) this.resolveServeBounce(ev.at);
        else if (s.phase === 'rally') this.resolveRallyBounce(ev.at);
        else this.audio.bounce();
      }
      // 直接飞出场地
      if (Math.abs(this.ball.z) > COURT.HALF_L + 3.5 || Math.abs(this.ball.x) > 8 || this.ball.y < -2) {
        if (this.awaitingServe) {
          this.serveFault();
        } else if (s.phase === 'rally') {
          // 未落地直接飞出 → 击球方出界失分; 已合法落地后飞出 → 接球方没接到
          if (this.hasBouncedShot) this.awardPoint(this.lastStriker, 'doubleBounce');
          else this.awardPoint(this.referee.other(this.lastStriker), 'out');
        }
        return;
      }
    }
  }

  // ---- 时机光圈(PRD: 绿/黄/橙三档) ----
  updateReticle(s) {
    if (s.phase === 'rally' && this.ball.active && this.ball.z < 0) {
      const p = this.p1;
      const d = Math.hypot(this.ball.x - p.pos.x, this.ball.z - p.pos.z);
      if (d < 3.4) {
        const tier = this.tierAt('p1');
        if (tier) {
          this.fx.showReticle(p.pos.x, p.pos.z, tier);
          return;
        }
      }
    }
    this.fx.hideReticle();
  }

  // ---- 操作提示 ----
  updateHint(s) {
    let text = null;
    if (s.phase === 'serve' && s.server === 'p1' && this.awaitingServe && !this.awaitingServe.done && !this.autoPlay) {
      text = '向上滑动发球';
    } else if (s.phase === 'rally' && this.ball.active && this.ball.z < 0 && !this.autoPlay) {
      const p = this.p1;
      const d = Math.hypot(this.ball.x - p.pos.x, this.ball.z - p.pos.z);
      if (d < 4.5 && d > 0.4) text = '滑动击球！';
    }
    const key = text ?? '';
    if (key !== this.hintKey) {
      this.hintKey = key;
      this.ui.setHint(!!text, text);
    }
  }

  // ---- 相机(软阻尼跟随 + 高球时拉远) ----
  cameraUpdate(dt) {
    const c = this.camera;
    const k = 1 - Math.exp(-dt * 3.2);
    c.position.x += (this.p1.pos.x * 0.3 - c.position.x) * k;
    const ty = 5.1 + clamp((this.ball.y - 2.5) * 0.14, 0, 1.1);
    c.position.y += (ty - c.position.y) * (1 - Math.exp(-dt * 2.2));
    c.position.z = -13.6;
    c.lookAt(this.p1.pos.x * 0.16, 1.0, 2.2);
    const fovTarget = 62 + clamp((this.ball.y - 2.8) * 0.8, 0, 5);
    if (Math.abs(c.fov - fovTarget) > 0.01) {
      c.fov += (fovTarget - c.fov) * (1 - Math.exp(-dt * 3));
      c.updateProjectionMatrix();
    }
  }

  // ---- HUD 同步 ----
  syncPhaseLabel(s) {
    const key = `${s.phase}|${s.server}|${s.serveAttempt}|${s.score.p1}-${s.score.p2}`;
    if (key !== this.phaseKey) {
      this.phaseKey = key;
      this.ui.setPhase(s);
      this._syncScore();
    }
  }

  _syncScore() {
    const s = this.referee.state;
    this.ui.setScore(s.score.p1, s.score.p2, s.server, s.matchWinner);
  }

  // ============ 调试/测试接口 ============

  setDifficulty(d) { this.difficulty = clamp(d, 0, 1); }

  injectSwipe(x0, y0, x1, y1, durMs) {
    const dx = x1 - x0;
    const dy = -(y1 - y0); // 屏幕 y 向下为正 → 向上为正
    this.routeSwipe({
      dx, dy, dt: durMs / 1000,
      samples: [{ x: x0, y: y0 }, { x: (x0 + x1) / 2, y: (y0 + y1) / 2 }, { x: x1, y: y1 }],
    });
  }

  getState() {
    const s = this.referee.state;
    return {
      phase: s.phase,
      server: s.server,
      serveAttempt: s.serveAttempt,
      score: { ...s.score },
      matchWinner: s.matchWinner,
      difficulty: this.difficulty,
      autoPlay: this.autoPlay,
      ball: { ...this.ball },
      players: { p1: { ...this.p1.pos }, p2: { ...this.p2.pos } },
    };
  }
}
