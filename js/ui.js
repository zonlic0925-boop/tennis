// HUD 与覆盖层 UI —— 转播比分条 / 事件提示 / 开始与结算
const $ = (id) => document.getElementById(id);

const PHASE_TEXT = {
  serve_p1: ['你的发球', '二发'],
  serve_p2: ['对手发球', '对手二发'],
  rally: '回合中',
  point_end: '',
  match_end: '比赛结束',
};

export function createUI() {
  const el = {
    hud: $('hud'),
    scoreP1: $('score-p1'),
    scoreP2: $('score-p2'),
    dotP1: $('dot-p1'),
    dotP2: $('dot-p2'),
    dash: $('score-dash'),
    phase: $('phase-label'),
    toast: $('toast'),
    hint: $('hint'),
    hintText: $('hint-text'),
    start: $('overlay-start'),
    end: $('overlay-end'),
    endTitle: $('end-title'),
    endScore: $('end-score'),
    btnStart: $('btn-start'),
    btnAgain: $('btn-again'),
  };
  let toastTimer = 0;

  function bump(num) {
    num.classList.remove('bump');
    void num.offsetWidth; // 重触发动画
    num.classList.add('bump');
  }

  return {
    el,

    onStart(cb) {
      el.btnStart.addEventListener('click', cb);
    },
    onAgain(cb) {
      el.btnAgain.addEventListener('click', cb);
    },

    showHud() { el.hud.classList.remove('hidden'); },
    hideStart() { el.start.classList.add('hidden'); },
    showEnd() { el.end.classList.remove('hidden'); },
    hideEnd() { el.end.classList.add('hidden'); },

    setScore(p1, p2, server, winnerSide) {
      el.scoreP1.textContent = p1;
      el.scoreP2.textContent = p2;
      el.dotP1.classList.toggle('on', server === 'p1');
      el.dotP2.classList.toggle('on', server === 'p2');
      el.dash.textContent = winnerSide === null ? '—' : winnerSide;
      el.scoreP1.classList.toggle('lead', p1 > p2);
      el.scoreP2.classList.toggle('lead', p2 > p1);
    },

    bumpScore(side) {
      bump(side === 'p1' ? el.scoreP1 : el.scoreP2);
    },

    setPhase(state) {
      const key = `${state.phase}_${state.server}`;
      const text = state.phase === 'serve'
        ? PHASE_TEXT[key][Math.min(state.serveAttempt - 1, 1)]
        : PHASE_TEXT[state.phase] ?? '';
      el.phase.textContent = text;
    },

    setHint(visible, text) {
      el.hint.classList.toggle('hidden', !visible);
      if (text) el.hintText.textContent = text;
    },

    toast(text, kind = 'info', dur = 1500) {
      el.toast.textContent = text;
      el.toast.className = kind;
      el.toast.classList.remove('hidden');
      clearTimeout(toastTimer);
      toastTimer = setTimeout(() => el.toast.classList.add('hidden'), dur);
    },

    showResult(winnerIsPlayer, scoreText) {
      el.endTitle.textContent = winnerIsPlayer ? '胜利！' : '惜败';
      el.endTitle.classList.toggle('lose', !winnerIsPlayer);
      el.endScore.textContent = scoreText;
      this.showEnd();
    },
  };
}
