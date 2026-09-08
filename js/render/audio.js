// 合成音效(WebAudio)与震动反馈 —— PRD §5.2/§5.3
// 全部程序合成, 无外部音频资源, 离线可用。

export function createAudio() {
  let ctx = null;

  function ensure() {
    try {
      if (!ctx) {
        const AC = window.AudioContext || window.webkitAudioContext;
        if (AC) ctx = new AC();
      }
      if (ctx && ctx.state === 'suspended') ctx.resume();
    } catch { /* 音频不可用时静默降级 */ }
    return ctx;
  }

  function tone(f0, f1, dur, { gain = 0.4, type = 'sine', at = 0 } = {}) {
    if (!ctx) return;
    const t0 = ctx.currentTime + at;
    const o = ctx.createOscillator();
    o.type = type;
    o.frequency.setValueAtTime(f0, t0);
    o.frequency.exponentialRampToValueAtTime(Math.max(f1, 1), t0 + dur);
    const g = ctx.createGain();
    g.gain.setValueAtTime(gain, t0);
    g.gain.exponentialRampToValueAtTime(0.001, t0 + dur);
    o.connect(g).connect(ctx.destination);
    o.start(t0);
    o.stop(t0 + dur + 0.03);
  }

  function noise(dur, freq, { gain = 0.3, type = 'bandpass', at = 0 } = {}) {
    if (!ctx) return;
    const t0 = ctx.currentTime + at;
    const n = Math.floor(ctx.sampleRate * dur);
    const buf = ctx.createBuffer(1, n, ctx.sampleRate);
    const d = buf.getChannelData(0);
    for (let i = 0; i < n; i++) d[i] = Math.random() * 2 - 1;
    const src = ctx.createBufferSource();
    src.buffer = buf;
    const f = ctx.createBiquadFilter();
    f.type = type;
    f.frequency.value = freq;
    f.Q.value = 1.1;
    const g = ctx.createGain();
    g.gain.setValueAtTime(gain, t0);
    g.gain.exponentialRampToValueAtTime(0.001, t0 + dur);
    src.connect(f).connect(g).connect(ctx.destination);
    src.start(t0);
  }

  function vibrate(pattern) {
    try { navigator.vibrate?.(pattern); } catch { /* 不支持时忽略 */ }
  }

  return {
    ensure,
    // 拍面击球: 甜区更亮(高频更多)
    hit(tier) {
      const bright = tier === 'perfect' ? 1.35 : tier === 'good' ? 1.0 : 0.75;
      noise(0.05, 2600 * bright, { gain: 0.42 });
      tone(190, 80, 0.09, { gain: 0.5 });
      vibrate(tier === 'perfect' ? 25 : 15);
    },
    bounce() {
      noise(0.03, 3800, { gain: 0.16, type: 'highpass' });
      tone(150, 90, 0.06, { gain: 0.18 });
    },
    net() {
      tone(240, 210, 0.1, { gain: 0.32, type: 'square' });
    },
    whiff() {
      noise(0.09, 1100, { gain: 0.14 });
    },
    fault() {
      tone(170, 120, 0.16, { gain: 0.26, type: 'square' });
    },
    point() {
      tone(523, 523, 0.12, { gain: 0.24 });
      tone(784, 784, 0.2, { gain: 0.26, at: 0.12 });
      vibrate([10, 40, 10]);
    },
    win() {
      [523, 659, 784, 1047].forEach((f, i) => tone(f, f, 0.22, { gain: 0.3, at: i * 0.14 }));
      vibrate([20, 60, 20, 60, 80]);
    },
    lose() {
      [392, 330, 262].forEach((f, i) => tone(f, f, 0.26, { gain: 0.24, at: i * 0.18 }));
    },
  };
}
