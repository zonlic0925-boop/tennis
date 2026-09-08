// TouchStrokeController.cs —— PRD §3 Module 1 + §4 Prompt#2: 滑屏 → 弹道落点 → 初速度
// 参考实现(与 Web 原型 js/core/strike.js 逻辑一致), 未在 Unity 编辑器中编译验证。
// PRD 击球时机: <0.8m Perfect(+15%) / 0.8~1.8m Good / 1.8~2.5m Dive(高吊弱回)
using UnityEngine;

public class TouchStrokeController : MonoBehaviour
{
    public BallPhysics ball;
    public Transform player;               // 击球方球员
    public float playerDir = 1f;           // +1 打向 Z>0 半场, -1 反之

    public const float PerfectDist = 0.8f;
    public const float GoodDist = 1.8f;
    public const float DiveDist = 2.5f;
    public const float PerfectBonus = 1.15f;
    public const float MaxDeflectDeg = 25f;  // PRD: 满宽滑屏 → ±25°
    public const float SwipeAngleMax = 75f;  // 滑屏角度满偏转阈值

    public const float ZDepthMin = 3.2f;     // 对方半场最浅落点
    public const float ZDepthMax = 10.3f;    // 最深落点

    private Vector2 startPos;
    private float startTime;
    private bool tracking;

    public enum Tier { None, Perfect, Good, Dive }

    void Update()
    {
        // 竖屏触摸: PRD §1.3 ScreenOrientation.Portrait
        if (Input.touchCount == 0) return;
        Touch t = Input.GetTouch(0);
        if (t.phase == TouchPhase.Began)
        {
            startPos = t.position;
            startTime = Time.time;
            tracking = true;
        }
        else if (t.phase == TouchPhase.Ended && tracking)
        {
            tracking = false;
            Vector2 delta = t.position - startPos; // Unity 屏幕坐标 Y 向上, 上滑 delta.y > 0
            float dt = Mathf.Max(Time.time - startTime, 0.05f);
            OnSwipe(delta, dt);
        }
    }

    public void OnSwipe(Vector2 delta, float dt)
    {
        // PRD §2.2: θx = atan2(Δx, Δy) × K_angle → 满宽 ±25°
        float len = delta.magnitude;
        float speed = len / dt;
        float angle = Mathf.Atan2(delta.x, delta.y);
        float n = Mathf.Clamp(angle / (SwipeAngleMax * Mathf.Deg2Rad), -1f, 1f);
        float deflection = n * MaxDeflectDeg * Mathf.Deg2Rad;

        // PRD: Z 落点由滑屏速度与长度决定
        float power = Mathf.Clamp(0.62f * (speed / 6000f) + 0.38f * (len / 1000f), 0.12f, 1f);

        Tier tier = EvaluateTiming();
        if (tier == Tier.None) return; // 挥空

        Vector3 from = PlayerStrikePoint();
        float depth = Mathf.Lerp(ZDepthMin, ZDepthMax, power);
        Vector3 target;
        float T;
        if (tier == Tier.Dive)
        {
            // 高吊弱回球
            target = new Vector3(from.x + Mathf.Tan(deflection * 0.5f) * Mathf.Abs(playerDir * 3.5f - from.z), 0f, playerDir * 3.5f);
            T = 1.35f;
        }
        else
        {
            float tz = playerDir * depth;
            float tx = Mathf.Clamp(from.x + Mathf.Tan(deflection) * Mathf.Abs(tz - from.z), -5.2f, 5.2f);
            target = new Vector3(tx, 0f, tz);
            T = Mathf.Lerp(BallPhysics.TMax, BallPhysics.TMin, power);
        }
        ball.Launch(from, target, T);
        if (tier == Tier.Perfect) ball.velocity *= PerfectBonus; // PRD: +15%
    }

    // PRD 击球时机窗口: 球与拍面枢轴距离三档
    public Tier EvaluateTiming()
    {
        if (ball == null || player == null || !ball.active) return Tier.None;
        if (ball.transform.position.y > 3.1f) return Tier.None;
        Vector3 pivot = player.position + new Vector3(0.25f * playerDir, 0f, 0.5f * playerDir);
        Vector3 d = ball.transform.position - pivot;
        d.y = 0f;
        float dist = d.magnitude;
        if (dist < PerfectDist) return Tier.Perfect;
        if (dist < GoodDist) return Tier.Good;
        if (dist <= DiveDist) return Tier.Dive;
        return Tier.None;
    }

    private Vector3 PlayerStrikePoint()
    {
        float y = Mathf.Clamp(ball.transform.position.y, 0.7f, 2.4f);
        return player.position + new Vector3(0.3f * playerDir, y - player.position.y, 0.55f * playerDir);
    }
}
