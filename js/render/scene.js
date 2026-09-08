// 3D 场景构建 —— PRD §4 Prompt#1 (CourtGenerator 的 Web 实现)
import * as THREE from 'three';
import { COURT } from '../core/config.js';

const COURT_COLOR = 0x2e9bc8;   // 迈阿密蓝硬地
const COURT_EDGE = 0x277fa8;    // 缓冲带
const APRON = 0x0a2030;         // 场外
const LINE_COLOR = 0xf5faff;

function makeTextTexture(text, opts = {}) {
  const c = document.createElement('canvas');
  c.width = 2048;
  c.height = 256;
  const g = c.getContext('2d');
  g.clearRect(0, 0, c.width, c.height);
  g.font = `${opts.weight || 700} ${opts.size || 168}px "Bahnschrift Condensed", "Arial Narrow", sans-serif`;
  g.textAlign = 'center';
  g.textBaseline = 'middle';
  g.fillStyle = opts.color || 'rgba(255,255,255,0.5)';
  g.fillText(text, c.width / 2, c.height / 2);
  const tex = new THREE.CanvasTexture(c);
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.anisotropy = 4;
  return tex;
}

export function createScene() {
  const scene = new THREE.Scene();
  scene.background = new THREE.Color(0x071522);
  scene.fog = new THREE.Fog(0x071522, 30, 90);

  const camera = new THREE.PerspectiveCamera(62, 9 / 16, 0.1, 300);
  camera.position.set(0, 5.1, -13.6);
  camera.lookAt(0, 1.0, 2.2);

  // ---- 灯光 ----
  const hemi = new THREE.HemisphereLight(0xcfe4ff, 0x16324a, 1.1);
  scene.add(hemi);
  const sun = new THREE.DirectionalLight(0xfff1dd, 1.7);
  sun.position.set(7, 18, -7);
  sun.castShadow = true;
  sun.shadow.mapSize.set(2048, 2048);
  sun.shadow.camera.left = -20;
  sun.shadow.camera.right = 20;
  sun.shadow.camera.top = 20;
  sun.shadow.camera.bottom = -20;
  sun.shadow.camera.near = 1;
  sun.shadow.camera.far = 60;
  sun.shadow.bias = -0.0004;
  scene.add(sun);

  const floorMat = new THREE.MeshStandardMaterial({ color: APRON, roughness: 1 });
  const apron = new THREE.Mesh(new THREE.PlaneGeometry(170, 170), floorMat);
  apron.rotation.x = -Math.PI / 2;
  apron.position.y = -0.03;
  apron.receiveShadow = true;
  scene.add(apron);

  // ---- 球场 ----
  const edgeMat = new THREE.MeshStandardMaterial({ color: COURT_EDGE, roughness: 0.9 });
  const courtEdge = new THREE.Mesh(new THREE.PlaneGeometry(COURT.LENGTH + 1.2, COURT.WIDTH + 1.2), edgeMat);
  courtEdge.rotation.x = -Math.PI / 2;
  courtEdge.position.y = 0;
  courtEdge.receiveShadow = true;
  scene.add(courtEdge);

  const courtMat = new THREE.MeshStandardMaterial({ color: COURT_COLOR, roughness: 0.85 });
  const court = new THREE.Mesh(new THREE.PlaneGeometry(COURT.LENGTH, COURT.WIDTH), courtMat);
  court.rotation.x = -Math.PI / 2;
  court.position.y = 0.004;
  court.receiveShadow = true;
  scene.add(court);

  // ---- 场地线(白色薄条) ----
  const lineMat = new THREE.MeshStandardMaterial({ color: LINE_COLOR, roughness: 0.6 });
  function addLine(x1, z1, x2, z2, w = 0.05) {
    const len = Math.hypot(x2 - x1, z2 - z1);
    const m = new THREE.Mesh(new THREE.BoxGeometry(len, 0.008, w), lineMat);
    m.position.set((x1 + x2) / 2, 0.012, (z1 + z2) / 2);
    m.rotation.y = -Math.atan2(z2 - z1, x2 - x1);
    scene.add(m);
  }
  const HL = COURT.HALF_L, HW = COURT.HALF_W;
  addLine(-HW, -HL, HW, -HL);                 // 底线 x2
  addLine(-HW, HL, HW, HL);
  addLine(-HW, -HL, -HW, HL);                 // 单打边线 x2
  addLine(HW, -HL, HW, HL);
  const DL = 5.485;                           // 双打边线(装饰)
  addLine(-DL, -HL, -DL, HL, 0.04);
  addLine(DL, -HL, DL, HL, 0.04);
  addLine(-HW, -COURT.SERVICE_LINE, HW, -COURT.SERVICE_LINE);  // 发球线 x2
  addLine(-HW, COURT.SERVICE_LINE, HW, COURT.SERVICE_LINE);
  addLine(0, -COURT.SERVICE_LINE, 0, COURT.SERVICE_LINE, 0.05); // 中线
  addLine(0, -HL, 0, -HL + 0.55, 0.03);       // 中点标记 x2
  addLine(0, HL, 0, HL - 0.55, 0.03);

  // ---- 球网(0.914m) ----
  const netMat = new THREE.MeshStandardMaterial({
    color: 0xffffff, transparent: true, opacity: 0.3, roughness: 0.9,
  });
  const net = new THREE.Mesh(new THREE.BoxGeometry(DL * 2 + 1.2, COURT.NET_HEIGHT, 0.02), netMat);
  net.position.set(0, COURT.NET_HEIGHT / 2, 0);
  net.castShadow = true;
  scene.add(net);
  const band = new THREE.Mesh(new THREE.BoxGeometry(DL * 2 + 1.2, 0.06, 0.05), new THREE.MeshStandardMaterial({ color: 0xffffff, roughness: 0.6 }));
  band.position.set(0, COURT.NET_HEIGHT - 0.03, 0);
  scene.add(band);
  const postMat = new THREE.MeshStandardMaterial({ color: 0xd8e4ee, roughness: 0.4, metalness: 0.6 });
  for (const s of [-1, 1]) {
    const post = new THREE.Mesh(new THREE.CylinderGeometry(0.05, 0.05, 1.07, 12), postMat);
    post.position.set(s * (DL + 0.6), 0.535, 0);
    post.castShadow = true;
    scene.add(post);
  }

  // ---- 场地围栏装饰 + 幽灵文字(签名元素) ----
  const fenceMat = new THREE.MeshStandardMaterial({ color: 0x0a1b2b, roughness: 1 });
  for (const s of [-1, 1]) {
    const wall = new THREE.Mesh(new THREE.BoxGeometry(1.6, 2.4, 46), fenceMat);
    wall.position.set(s * 12.5, 1.2, 0);
    scene.add(wall);
  }
  const ghost = new THREE.Mesh(
    new THREE.PlaneGeometry(9, 30),
    new THREE.MeshBasicMaterial({ map: makeTextTexture('MATCH POINT'), transparent: true, opacity: 0.16, depthWrite: false })
  );
  ghost.rotation.x = -Math.PI / 2;
  ghost.position.set(0, 0.02, 16.6);
  scene.add(ghost);

  // ---- 球 ----
  const ball = new THREE.Mesh(
    new THREE.SphereGeometry(COURT.BALL_RADIUS, 24, 18),
    new THREE.MeshStandardMaterial({ color: 0xd8e63c, roughness: 0.55 })
  );
  ball.castShadow = true;
  ball.visible = false;
  scene.add(ball);

  return { scene, camera, ball };
}

// 球员装配: 躯干 + 头 + 挥拍手臂组
export function createPlayerRig({ shirt, cap, skin = 0xf2c9a3 }) {
  const group = new THREE.Group();

  const shirtMat = new THREE.MeshStandardMaterial({ color: shirt, roughness: 0.7 });
  const torso = new THREE.Mesh(new THREE.CapsuleGeometry(0.28, 0.72, 6, 14), shirtMat);
  torso.position.y = 0.98;
  torso.castShadow = true;
  group.add(torso);

  const head = new THREE.Mesh(new THREE.SphereGeometry(0.2, 20, 14), new THREE.MeshStandardMaterial({ color: skin, roughness: 0.8 }));
  head.position.y = 1.66;
  head.castShadow = true;
  group.add(head);

  const capMat = new THREE.MeshStandardMaterial({ color: cap, roughness: 0.6 });
  const capMesh = new THREE.Mesh(new THREE.SphereGeometry(0.215, 20, 8, 0, Math.PI * 2, 0, Math.PI / 2), capMat);
  capMesh.position.y = 1.7;
  group.add(capMesh);

  // 球拍组: 肩关节在 (0.32, 1.3, 0), 挥拍绕 x 轴旋转
  const arm = new THREE.Group();
  arm.position.set(0.32, 1.3, 0);
  const grip = new THREE.Mesh(
    new THREE.CylinderGeometry(0.022, 0.022, 0.52, 8),
    new THREE.MeshStandardMaterial({ color: 0x2b2b3a, roughness: 0.6 })
  );
  grip.position.set(0, -0.2, 0);
  const face = new THREE.Mesh(
    new THREE.BoxGeometry(0.28, 0.36, 0.035),
    new THREE.MeshStandardMaterial({ color: 0x39416b, roughness: 0.5 })
  );
  face.position.set(0, -0.55, 0);
  arm.add(grip, face);
  arm.rotation.x = 0.65;
  group.add(arm);

  // 摆动/跑步的动画状态
  const anim = { swingT: -1, moving: 0, t: Math.random() * 10 };
  function update(dt) {
    anim.t += dt;
    if (anim.swingT >= 0 && anim.swingT < 1) {
      anim.swingT = Math.min(1, anim.swingT + dt / 0.34);
      const t = anim.swingT;
      // 后摆(0→0.35) → 前挥(0.35→0.75) → 随挥回位
      let a;
      if (t < 0.35) a = 0.65 + (t / 0.35) * (-2.9 - 0.65);
      else if (t < 0.75) a = -2.9 + ((t - 0.35) / 0.4) * (1.4 + 2.9);
      else a = 1.4 + ((t - 0.75) / 0.25) * (0.65 - 1.4);
      arm.rotation.x = a;
      torso.rotation.x = t < 0.75 ? -0.12 : 0;
    }
    // 跑步起伏
    const bob = anim.moving > 0.5 ? Math.abs(Math.sin(anim.t * 11)) * 0.06 : Math.sin(anim.t * 2.2) * 0.012;
    group.position.y = bob;
    anim.moving = Math.max(0, anim.moving - dt * 2.2);
  }
  return { group, arm, torso, anim, update };
}
