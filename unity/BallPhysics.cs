// BallPhysics.cs —— PRD §4 Prompt#1.2: 网球物理(重力/0.72 反弹/阻力) + PRD §2.2 弹道公式
// 参考实现(与 Web 原型 js/core/physics.js 逻辑一致), 未在 Unity 编辑器中编译验证。
using UnityEngine;

public class BallPhysics : MonoBehaviour
{
    public const float Gravity = -9.81f;
    public const float Restitution = 0.72f;     // PRD: bounciness 0.72
    public const float TangentLoss = 0.78f;     // 落地水平速度保留
    public const float Drag = 0.12f;            // 指数空气阻力 /s
    public const float BallRadius = 0.0335f;
    public const float NetHeight = 0.914f;
    public const float NetClearance = 0.3f;     // PRD: 至少净过网 0.3m
    public const float TMin = 0.62f;
    public const float TMax = 1.3f;

    public Vector3 velocity;
    public string spinType = "Flat";            // Flat / Topspin / Slice
    public bool active;

    // PRD §2.2 弹道发射公式: Vx=(xt-x0)/T, Vz=(zt-z0)/T, Vy=(-y0-0.5·g·T²)/T
    public static Vector3 SolveLaunch(Vector3 p0, Vector3 target, float T)
    {
        return new Vector3(
            (target.x - p0.x) / T,
            (-p0.y - 0.5f * Gravity * T * T) / T,
            (target.z - p0.z) / T
        );
    }

    // 过网瞬间高度(解析); 不过网返回 float.MaxValue
    public static float NetClearanceAt(Vector3 p0, Vector3 v, float T)
    {
        if (Mathf.Abs(v.z) < 1e-6f) return float.MaxValue;
        float tc = -p0.z / v.z;
        if (tc <= 0f || tc >= T) return float.MaxValue;
        return p0.y + v.y * tc + 0.5f * Gravity * tc * tc;
    }

    // 抬高弧线(T 增大)直至过网高度满足 NetHeight+NetClearance, 上限 TMax
    public static float EnsureNetClearance(Vector3 p0, Vector3 target, float T)
    {
        float t = Mathf.Clamp(T, TMin, TMax);
        for (int i = 0; i < 40; i++)
        {
            Vector3 v = SolveLaunch(p0, target, t);
            if (NetClearanceAt(p0, v, t) >= NetHeight + NetClearance + 0.06f) return t;
            if (t >= TMax) break;
            t = Mathf.Min(t + 0.04f, TMax);
        }
        return t;
    }

    public void Launch(Vector3 from, Vector3 target, float T, string spin = "Flat")
    {
        transform.position = from;
        velocity = SolveLaunch(from, target, EnsureNetClearance(from, target, T));
        spinType = spin;
        active = true;
    }

    private void Update()
    {
        if (!active) return;
        float dt = Time.deltaTime;
        // 半隐式欧拉 + 指数阻力
        float drag = Mathf.Exp(-Drag * dt);
        velocity.x *= drag;
        velocity.y += Gravity * dt;
        velocity.z *= drag;
        transform.position += velocity * dt;

        // 地面反弹(PRD: 0.72)
        if (transform.position.y <= BallRadius && velocity.y < 0f)
        {
            Vector3 p = transform.position;
            p.y = BallRadius;
            transform.position = p;
            velocity.y = -velocity.y * Restitution;
            float keep = TangentLoss;
            if (spinType == "Topspin") keep *= 1.18f;
            else if (spinType == "Slice") keep *= 0.82f;
            velocity.x *= keep;
            velocity.z *= keep;
        }

        // 飞出场地
        if (Mathf.Abs(transform.position.z) > CourtGenerator.HalfL + 3.5f ||
            Mathf.Abs(transform.position.x) > 8f || transform.position.y < -2f)
        {
            active = false;
        }
    }
}
