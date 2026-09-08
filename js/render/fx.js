// 动态特效 —— 尾迹 / 球影 / 落点指示器(PRD §5.1) / 击球时机光圈
import * as THREE from 'three';

const TRAIL_MAX = 16;
const GREEN = 0x3dff88;
const RED = 0xff4a4a;
const YELLOW = 0xffd23d;
const ORANGE = 0xff7a3d;

export function createFx(scene) {
  // ---- 球尾迹 ----
  const trailPos = new Float32Array(TRAIL_MAX * 3);
  const trailGeo = new THREE.BufferGeometry();
  trailGeo.setAttribute('position', new THREE.BufferAttribute(trailPos, 3));
  trailGeo.setDrawRange(0, 0);
  const trail = new THREE.Line(
    trailGeo,
    new THREE.LineBasicMaterial({ color: 0xffe66a, transparent: true, opacity: 0.5, depthWrite: false })
  );
  trail.frustumCulled = false;
  scene.add(trail);
  let trailPoints = [];
  let trailTimer = 0;

  // ---- 球影(深度感知) ----
  const shadow = new THREE.Mesh(
    new THREE.CircleGeometry(0.09, 20),
    new THREE.MeshBasicMaterial({ color: 0x000000, transparent: true, opacity: 0.32, depthWrite: false })
  );
  shadow.rotation.x = -Math.PI / 2;
  shadow.position.y = 0.015;
  scene.add(shadow);

  // ---- 落点指示器: 外圈 + 半透明内盘, 脉冲动画 ----
  const ringMat = new THREE.MeshBasicMaterial({ color: GREEN, transparent: true, opacity: 0.95, depthWrite: false });
  const discMat = new THREE.MeshBasicMaterial({ color: GREEN, transparent: true, opacity: 0.26, depthWrite: false });
  const ring = new THREE.Mesh(new THREE.RingGeometry(0.34, 0.44, 40), ringMat);
  const disc = new THREE.Mesh(new THREE.CircleGeometry(0.34, 40), discMat);
  const landing = new THREE.Group();
  ring.rotation.x = -Math.PI / 2;
  disc.rotation.x = -Math.PI / 2;
  ring.position.y = 0.02;
  disc.position.y = 0.016;
  landing.add(ring, disc);
  landing.visible = false;
  scene.add(landing);
  let landingT = 0;

  // ---- 击球时机光圈(玩家脚下) ----
  const reticleMat = new THREE.MeshBasicMaterial({ color: GREEN, transparent: true, opacity: 0.9, depthWrite: false });
  const reticle = new THREE.Mesh(new THREE.RingGeometry(0.5, 0.62, 40), reticleMat);
  reticle.rotation.x = -Math.PI / 2;
  reticle.position.y = 0.02;
  reticle.visible = false;
  scene.add(reticle);
  let reticleT = 0;

  return {
    // ---- 每帧更新 ----
    update(dt, ball, ballActive, playerX, playerZ) {
      // 尾迹
      trailTimer += dt;
      if (ballActive && (Math.abs(ball.vx) + Math.abs(ball.vz)) > 5 && trailTimer > 1 / 30) {
        trailTimer = 0;
        trailPoints.push([ball.x, ball.y, ball.z]);
        if (trailPoints.length > TRAIL_MAX) trailPoints.shift();
      } else if (!ballActive) {
        trailPoints = [];
      }
      for (let i = 0; i < TRAIL_MAX; i++) {
        const p = trailPoints[trailPoints.length - TRAIL_MAX + i];
        if (p) {
          trailPos[i * 3] = p[0];
          trailPos[i * 3 + 1] = p[1];
          trailPos[i * 3 + 2] = p[2];
        } else {
          trailPos[i * 3] = 0; trailPos[i * 3 + 1] = -99; trailPos[i * 3 + 2] = 0;
        }
      }
      trailGeo.setDrawRange(0, Math.min(trailPoints.length, TRAIL_MAX));
      trailGeo.attributes.position.needsUpdate = true;

      // 球影
      if (ballActive) {
        shadow.visible = true;
        shadow.position.set(ball.x, 0.015, ball.z);
        const h = Math.max(ball.y, 0.05);
        const k = Math.min(1, h / 4);
        shadow.scale.setScalar(1 + k * 2.2);
        shadow.material.opacity = Math.max(0.08, 0.34 - k * 0.26);
      } else {
        shadow.visible = false;
      }

      // 落点指示器脉冲
      if (landing.visible) {
        landingT += dt;
        const s = 1 + 0.09 * Math.sin(landingT * 7);
        landing.scale.setScalar(s);
        landing.rotation.z += dt * 1.4;
      }

      // 时机光圈脉冲
      if (reticle.visible) {
        reticleT += dt;
        const s = 1 + 0.12 * Math.sin(reticleT * 10);
        reticle.scale.setScalar(s);
        reticle.position.set(playerX, 0.02, playerZ);
      }
    },

    showLanding(x, z, inBounds) {
      landing.visible = true;
      landing.position.set(x, 0, z);
      landing.scale.setScalar(1);
      landingT = 0;
      const c = inBounds ? GREEN : RED;
      ringMat.color.setHex(c);
      discMat.color.setHex(c);
    },
    hideLanding() { landing.visible = false; },

    showReticle(x, z, tier) {
      reticle.visible = true;
      reticle.position.set(x, 0.02, z);
      reticleT = 0;
      const c = tier === 'perfect' ? GREEN : tier === 'good' ? YELLOW : ORANGE;
      reticleMat.color.setHex(c);
    },
    hideReticle() { reticle.visible = false; },
  };
}
