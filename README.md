# ACEMATCH · 竖屏 3D 网球对决

类 Tennis Clash 的 3D 网球游戏，含 **Web 原型**（JS + Three.js）与 **Godot 4 移植版**（`godot/`，含动漫风格卡通角色），严格依据 PRD（Tennis_Game_iOS_Agent_PRD.md）实现核心玩法闭环：标准尺寸球场、真实弹道物理、滑屏击球、发球/回合/计分状态机、AI 对手、落点指示器、音效与震动。

- **技术栈**：原生 JS (ES Modules) + Three.js r160（本地依赖，无 CDN，离线可用），零构建工具；Godot 4.7.2（GL Compatibility）
- **平台**：手机/桌面浏览器均可（竖屏 9:16 自适应，桌面自动信箱化）；Godot 版面向桌面/移动导出
- **PRD 对应**：PRD §1.1 允许的 Web 技术栈分支（Unity 基线版本见 `unity/` 移植脚本集）

## 快速开始

```bash
cd tennis
npm install            # 可选：three.js 运行时单文件已随仓库 vendor/ 提供，无需网络
npm run serve          # python -m http.server 8080
# 或任意静态服务器: npx serve -l 8080 .
```

浏览器打开 <http://127.0.0.1:8080/>（ES Modules 需经 HTTP 访问，不能直接 file:// 打开）。

## Godot 4 版（godot/）

```bash
# 需 Godot 4.7+（本地路径示例: C:\Users\Zonlic\Desktop\experiment\tools\godot.exe）
godot --path godot                        # 窗口运行（540×960 竖屏）
godot --headless --path godot -- --smoke --speed=10    # 无头自动演示完整局
godot --path godot -- --shots=<DIR>       # 五连拍: 菜单/发球/回合/得分/结算
```

命令行参数（`--` 之后）：`--smoke`（无头 autoPilot 打完整局，`[SMOKE]` 事件流，正常结束 exit 0 / 超时 exit 1）、`--shots=DIR`（截图模式五连拍，须真实窗口）、`--autopilot`、`--speed=N`（每帧 N 个固定 1/60 逻辑步）、`--skin=N`（0-3 选角色）、`--difficulty=F`（0-1）、`--max-sec=N`。smoke/shots 用固定种子，结果可复现。

**操作**：滑屏击球/发球（同 Web 版）；**方向键 / WASD / 左下虚拟方向键**手动移动（覆盖自动跑位）；**空格** = 中速直线击球。

**结构**：`scenes/main.tscn` 极简（root Node3D + main.gd，场景/HUD 全程序化构建）；`scripts/main.gd` 为 game.js 的编排移植（比赛流程/AI/物理子步 1/120/相机/HUD/命令行模式），纯逻辑层（court_config/ball_physics/strike/referee，class_name 全局类）与 Web 版逐函数对应且已单测；`scripts/anime_character.gd` 为卡通"纸娃娃"角色（Mixamo FBX 骨架 + 程序化部件挂骨骼 + Toon 材质，动画 idle/run/正手/反手/victory 来自本地 Mixamo 资产、发球为程序化关键帧）；界面中文用系统字体（微软雅黑）。角色面向 +Z，对手由 main 旋转 180°；相机在 z=-13.6 朝 +Z，屏幕右 = 世界 -X，输入层统一翻转 dx。

**与 Web 版的已知差异**：Web 版 `scene.js` 球场 PlaneGeometry 两轴写反（球场长边误朝横向、部分白线悬在场外，蓝绿色调相近不易察觉），Godot 版已修正为正确比例。

## 操作

| 动作 | 效果 |
| --- | --- |
| 向上滑动 | 击球 / 发球（滑动越快越深、越平） |
| 滑动方向 | 控制落点偏转（满宽滑屏 ±25°） |
| 曲线滑动 | 附加旋转（上旋/下旋，影响落地后前冲） |
| 自动跑位 | 球员自动跑向落点，击球后 0.6x 速度回底线中心 |

**时机三档**（PRD §3 Module 1，球员脚下光圈提示）：
- 绿圈 <0.8m **Perfect**：+15% 球速
- 黄圈 0.8~1.8m **Good**：标准
- 橙圈 1.8~2.5m **Dive**：高吊弱回球

**赛制**（PRD §3 Module 3）：先得 7 分且净胜 2 分获胜；每分轮换发球；发球须落入对角发球区，失误二次，双误送分。

## 目录结构

```
tennis/
├── index.html              # 入口 + import map
├── styles.css              # HUD/菜单(转播比分条风格)
├── vendor/three.module.js  # three.js r160 运行时单文件(importmap 指向, 静态托管可用)
├── package.json
├── js/
│   ├── main.js             # 渲染器/主循环/尺寸适配/调试接口
│   ├── game.js             # 游戏编排: 输入/AI/物理步进/裁判接线/相机
│   ├── ui.js               # HUD、toast、开始/结算界面
│   ├── core/               # ★ 纯逻辑(无渲染依赖, 可单测)
│   │   ├── config.js       # PRD 常量(场地/物理/击球/调参)
│   │   ├── physics.js      # PRD §2.2 弹道公式/积分/落地预测
│   │   ├── strike.js       # 滑屏→落点→初速度 映射
│   │   └── referee.js      # 状态机: 发球/回合/7分净胜2
│   └── render/             # Three.js 渲染层
│       ├── scene.js        # 球场/球网/球员/灯光(PRD Prompt#1)
│       ├── fx.js           # 尾迹/球影/落点指示器/时机光圈
│       └── audio.js        # WebAudio 合成音效 + 震动
├── tests/run-tests.mjs     # 单元测试(16 项, node 直跑)
├── godot/                  # ★ Godot 4.7 移植版（GL Compatibility, 竖屏 540×960）
│   ├── project.godot       # 主场景 scenes/main.tscn; 输入映射 move_left/right/up/down
│   ├── scenes/main.tscn    # 极简场景: root Node3D + main.gd, 其余全程序化
│   ├── scripts/
│   │   ├── main.gd         # game.js 编排移植 + 场景/灯光/HUD/虚拟方向键构建
│   │   ├── anime_character.gd  # 卡通纸娃娃角色 (Mixamo 骨架 + 部件挂骨 + Toon)
│   │   ├── court_config.gd / ball_physics.gd / strike.gd / referee.gd  # 纯逻辑(与 js/core 对应)
│   │   └── skins.gd        # 4 套皮肤定义 (男×2 女×2)
│   ├── assets/anims/       # Mixamo 动画 FBX (idle/run/正手/反手/victory/骨架)
│   ├── tests/              # test_logic(16/16) / test_character / 诊断脚本
│   └── shots/              # 截图模式产物 (01_menu … 05_result)
└── unity/                  # ★ PRD 基线 Unity 2022.3 移植脚本(参考实现)
    ├── CourtGenerator.cs
    ├── BallPhysics.cs
    ├── TouchStrokeController.cs
    ├── PlayerCharacterController.cs
    ├── CameraController.cs
    ├── MatchReferee.cs
    └── NetworkMatchManager.cs
```

## PRD 覆盖对照

| PRD 条目 | 实现 | 状态 |
| --- | --- | --- |
| §2.1 坐标与场地 23.77×8.23 / 网 0.914 | `config.js` + `scene.js` | ✅ 已实测 |
| §2.2 滑屏→弹道公式（±25°、过网 0.3m） | `strike.js` + `physics.js` | ✅ 已实测 |
| §2.2 反弹 0.72 / 重力 / 阻力 | `physics.js` | ✅ 已实测 |
| §3 M1 击球时机三档 +15% | `game.js tierAt/tryStrike` | ✅ 已实测 |
| §3 M2 点击移动 / 0.6x 回位 / 相机阻尼 | `game.js`（自动跑位替代点按, Tennis Clash 同款手感） | ✅ 已实测 |
| §3 M3 7 分净胜 2 / 发球校验 / 轮换 | `referee.js` | ✅ 已实测 |
| §3 M4 网络包 schema / 落点标记 | `unity/NetworkMatchManager.cs` + `fx.js` 落点指示器 | ⬜ M2 |
| §5.1 落点指示器(绿/红脉冲) | `fx.js showLanding` | ✅ 已实现 |
| §5.2 震动反馈 | `navigator.vibrate`（iOS Safari 不支持，原生端由 Unity 实现） | ⚠️ 平台限制 |
| §5.3 击球/弹跳音效 | `audio.js` WebAudio 合成 | ✅ 已实现 |

## 验证记录（本次交付证据）

- **单元测试**：`node tests/run-tests.mjs` → 16/16 通过（弹道公式、阻力补偿落点、过网保证、反弹系数、落点预测、滑屏映射、发球区校验、双误、7 分净胜 2 赛点逻辑）
- **浏览器 E2E**（真实浏览器 + 确定性步进，2026-09-08）：
  - 3D 渲染像素断言：球场蓝 / 白线 / 双方球员色 / 网带 / 幽灵文字全部检出
  - 真实指针手势（cua 拖拽）成功触发发球；滑屏→弹道→落点判定→rally 全链路通过
  - AI 预判跑位 + 接发回球入界；出界/两跳/双误判分正确
  - 玩家 rally 击球 100% 命中；同一球防重复击打锁生效
  - autoPlay 完整比赛：7:2 打完，赛点触发 match_end，结算界面/HUD 比分 DOM 全部正确
- **已知限制**：无联网（M2）；iOS Safari 无震动 API；Unity 脚本为参考实现，未在 Unity 编辑器中编译验证；Web 版球场平面两轴反置（见上，Godot 版已修正）

## Godot 版验证记录（2026-09-08）

- **逻辑单测**：`godot --headless --path godot --script res://tests/test_logic.gd` → 16/16（与 Web 版同口径）
- **角色构建**：`test_character.gd` → 4 皮肤 × 65 骨骼 / 42-53 部件 / idle,run,forehand,backhand,serve,victory 全注册，发球关键帧 RightArm 夹角 ~103°
- **无头冒烟**：`--smoke --speed=10` → autoPilot 完整局 7-1 打完（发球轮换/出界/两跳判分事件齐全），65 游戏秒，固定种子两次运行时间轴完全一致，exit 0
- **视觉验证**：`--shots` 五连拍（`godot/shots/`）人工核查通过——菜单（皮肤/难度选择）、发球站位与抛球、回合球影、得分 toast、胜利结算 + 角色胜利动作；中文 HUD 正常渲染


## 路线图（M2）

1. **联网对战**：Colyseus/Node 房间码服务器 + `NetworkMatchManager.cs` 中定义的包 schema（`BallStrokePayload` 客户端权威击球广播，防守方确定性模拟，PRD §3 M4 已设计）
2. **iOS 打包**：`unity/` 脚本导入 Unity 2022.3 LTS（URP）→ Xcode 构建；竖屏 Portrait、Canvas Scaler 0.5 权重（PRD §1.3）
3. **表现层**：真实球员模型、球场材质、观众氛围、更多音效
