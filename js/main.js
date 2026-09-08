// 入口: 渲染器 / 主循环 / 尺寸适配 / 调试接口
import * as THREE from 'three';
import { Game } from './game.js';

const stage = document.getElementById('stage');

const renderer = new THREE.WebGLRenderer({ antialias: true });
renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.05;
stage.appendChild(renderer.domElement);

const game = new Game(renderer.domElement);

function resize() {
  const rect = stage.getBoundingClientRect();
  const w = Math.max(1, Math.round(rect.width || window.innerWidth));
  const h = Math.max(1, Math.round(rect.height || window.innerHeight));
  // updateStyle 必须为 true: 无内联宽高时 canvas 会按缓冲区尺寸(dpr 缩放后)显示,
  // 在 dpr>=2 的手机上溢出舞台 2 倍, 画面被裁剪成左上角
  renderer.setSize(w, h);
  game.resize(w, h);
}
window.addEventListener('resize', resize);
window.addEventListener('orientationchange', () => setTimeout(resize, 120));
if (typeof ResizeObserver !== 'undefined') {
  new ResizeObserver(resize).observe(stage);
}
resize();
requestAnimationFrame(resize);
setTimeout(resize, 60);
setTimeout(resize, 300);

// 渲染循环: rAF 优先; 受限 WebView 中 rAF 可能被挂起, 2s 无 tick 则降级为定时器驱动
let rafWatchdog = null;
let driverPaused = false;
function scheduleWatchdog() {
  clearTimeout(rafWatchdog);
  rafWatchdog = setTimeout(() => {
    renderer.setAnimationLoop(null);
    setInterval(frame, 33);
  }, 2000);
}
function frame() {
  scheduleWatchdog();
  if (driverPaused) return;
  game.update();
  renderer.render(game.scene, game.camera);
  if (debugCanvas) {
    if (debugCanvas.width !== renderer.domElement.width || debugCanvas.height !== renderer.domElement.height) {
      debugCanvas.width = renderer.domElement.width;
      debugCanvas.height = renderer.domElement.height;
    }
    debugCanvas.getContext('2d').drawImage(renderer.domElement, 0, 0);
  }
}
renderer.setAnimationLoop(frame);

// 调试: ?debug=1 时把 WebGL 帧同步到 2D canvas, 供自动化像素级验证
let debugCanvas = null;
if (new URLSearchParams(location.search).has('debug')) {
  debugCanvas = document.createElement('canvas');
  document.body.appendChild(debugCanvas);
}
window.__debugCanvas = debugCanvas;

// 调试/自动化测试接口
window.game = {
  _game: game,
  start: () => game.startMatch(),
  getState: () => game.getState(),
  setDifficulty: (d) => game.setDifficulty(d),
  autoPlay: (on = true) => { game.autoPlay = on; },
  simulateSwipe: (x0, y0, x1, y1, durMs) => game.injectSwipe(x0, y0, x1, y1, durMs),
  step: (dt) => game.update(dt),
  renderFrame: () => renderer.render(game.scene, game.camera),
  project: (x, y, z) => {
    const v = new THREE.Vector3(x, y, z).project(game.camera);
    return { x: Math.round((v.x + 1) / 2 * renderer.domElement.width), y: Math.round((1 - v.y) / 2 * renderer.domElement.height) };
  },
  syncDebug: () => {
    const wc = renderer.domElement;
    if (debugCanvas.width !== wc.width || debugCanvas.height !== wc.height) {
      debugCanvas.width = wc.width;
      debugCanvas.height = wc.height;
    }
    debugCanvas.getContext('2d').drawImage(wc, 0, 0);
  },
  sample: (x, y) => {
    const d = debugCanvas.getContext('2d').getImageData(Math.floor(x), Math.floor(y), 1, 1).data;
    return [d[0], d[1], d[2]];
  },
  pause: (p = true) => { driverPaused = p; },
};
