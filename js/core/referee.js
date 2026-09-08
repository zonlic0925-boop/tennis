// 裁判状态机 —— PRD §3 Module 3 (MatchReferee)
// 先到 7 分且净胜 2 分获胜。状态机: serve → rally → point_end → (serve | match_end)

import { MATCH } from './config.js';

export class Referee {
  constructor({ targetPoints = MATCH.TARGET_POINTS, winBy = MATCH.WIN_BY, players = ['p1', 'p2'] } = {}) {
    this.cfg = { targetPoints, winBy, players };
    this.reset();
  }

  reset() {
    const [a, b] = this.cfg.players;
    this.score = { [a]: 0, [b]: 0 };
    this.phase = 'menu';
    this.server = a;
    this.serveAttempt = 1;
    this.matchWinner = null;
  }

  startMatch() {
    this.phase = 'serve';
    this.server = this.cfg.players[0];
    this.serveAttempt = 1;
  }

  // 发球失误。一发失误 → 二发; 二发失误 → 双误, 接发方得分。
  onServeFault(serverId) {
    if (this.phase !== 'serve' || serverId !== this.server) return null;
    if (this.serveAttempt === 1) {
      this.serveAttempt = 2;
      return { doubleFault: false };
    }
    return this._awardPoint(this.other(serverId), 'doubleFault');
  }

  onServeIn(serverId) {
    if (this.phase === 'serve' && serverId === this.server) {
      this.phase = 'rally';
      return true;
    }
    return false;
  }

  onRallyEnd(winnerId, reason) {
    if (this.phase !== 'rally' && this.phase !== 'serve') return null;
    return this._awardPoint(winnerId, reason);
  }

  _awardPoint(winnerId, reason) {
    const lead = this.score[winnerId] + 1 - this.score[this.other(winnerId)];
    this.score[winnerId] += 1;
    if (this.score[winnerId] >= this.cfg.targetPoints && lead >= this.cfg.winBy) {
      this.phase = 'match_end';
      this.matchWinner = winnerId;
      return { phase: 'match_end', winner: winnerId, score: { ...this.score }, reason };
    }
    this.phase = 'point_end';
    this.server = this.other(this.server); // 每分轮换发球
    this.serveAttempt = 1;
    return { phase: 'point_end', score: { ...this.score }, nextServer: this.server, reason };
  }

  // point_end 结束后进入下一分发球
  nextServe() {
    if (this.phase === 'point_end') {
      this.phase = 'serve';
      this.serveAttempt = 1;
    }
  }

  other(id) {
    return id === this.cfg.players[0] ? this.cfg.players[1] : this.cfg.players[0];
  }

  get state() {
    return {
      phase: this.phase,
      score: { ...this.score },
      server: this.server,
      serveAttempt: this.serveAttempt,
      matchWinner: this.matchWinner,
    };
  }
}
