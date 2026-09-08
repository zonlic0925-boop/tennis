// NetworkMatchManager.cs —— PRD §3 Module 4 + §4 Prompt#4: 1v1 房间码联机(客户端权威击球)
// 参考实现骨架(Colyseus/轻量 WebSocket), 未在 Unity 编辑器中编译验证。
// 架构(PRD §1.2): 击球方客户端优先物理推算并广播, 防守方预测平滑插值。
using System;
using UnityEngine;

// PRD §3 Module 4 数据包 Schema
[Serializable]
public class BallStrokePayload
{
    public long tick;
    public float[] origin;          // [x, y, z]
    public float[] velocity;        // [vx, vy, vz]
    public string spinType;         // "Flat" | "Topspin" | "Slice"
    public float[] targetLanding;   // [x, z]
    public double timestamp;
}

[Serializable]
public class PlayerPositionPayload
{
    public string playerId;
    public float[] position;        // [x, y, z]
    public float[] velocity;        // [vx, vz]
    public int animationState;
}

public class NetworkMatchManager : MonoBehaviour
{
    public BallPhysics ball;
    public string serverUrl = "ws://localhost:2567"; // Colyseus 默认端口
    public int roomCode = 0;                        // PRD: 4 位房间码

    private WebSocketClient client;                 // 见下方接口契约
    private bool isStriker;                         // 本端是否为击球方(客户端权威)
    private float syncTimer;

    void Start()
    {
        // 连接握手: 携带房间码加入 Colyseus 房间
        client = new WebSocketClient(serverUrl);
        client.OnOpen += () => client.Send($"{{ \"room\": \"match\", \"code\": {roomCode} }}");
        client.OnMessage += HandleMessage;
        client.Connect();
    }

    void Update()
    {
        // 防守方: 收到击球包后确定性弹道模拟 + 落点地面标记(PRD Lag Compensation)
        // 击球方: 本地物理结果周期性广播
        if (isStriker)
        {
            syncTimer += Time.deltaTime;
            if (syncTimer > 0.05f) // 20Hz
            {
                syncTimer = 0f;
                BroadcastBallStroke();
            }
        }
    }

    // 击球方客户端权威: 本端计算出初速度后立即广播
    public void BroadcastBallStroke()
    {
        var payload = new BallStrokePayload
        {
            tick = DateTime.UtcNow.Ticks,
            origin = new[] { ball.transform.position.x, ball.transform.position.y, ball.transform.position.z },
            velocity = new[] { ball.velocity.x, ball.velocity.y, ball.velocity.z },
            spinType = ball.spinType,
            targetLanding = new[] { 0f, 0f }, // 由 BallPhysics 的解析解推算落点
            timestamp = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds(),
        };
        client.Send(JsonUtility.ToJson(payload));
    }

    public void BroadcastPlayerPosition(string playerId, Vector3 pos, Vector2 vel, int animState)
    {
        var payload = new PlayerPositionPayload
        {
            playerId = playerId,
            position = new[] { pos.x, pos.y, pos.z },
            velocity = new[] { vel.x, vel.y },
            animationState = animState,
        };
        client.Send(JsonUtility.ToJson(payload));
    }

    // 防守方: 收到击球包 → 立即以相同初速度启动本地确定性模拟(无网络等待)
    private void HandleMessage(string json)
    {
        try
        {
            var payload = JsonUtility.FromJson<BallStrokePayload>(json);
            if (payload?.velocity == null) return;
            ball.transform.position = new Vector3(payload.origin[0], payload.origin[1], payload.origin[2]);
            ball.velocity = new Vector3(payload.velocity[0], payload.velocity[1], payload.velocity[2]);
            ball.spinType = payload.spinType;
            ball.active = true;
            isStriker = false;
            // 在 targetLanding 处渲染地面落点标记(Decal), 绿色界内/红色出界(PRD §5.1)
            ShowLandingMarker(new Vector3(payload.targetLanding[0], 0f, payload.targetLanding[1]));
        }
        catch (Exception e)
        {
            Debug.LogWarning($"[Network] 忽略无效包: {e.Message}");
        }
    }

    private void ShowLandingMarker(Vector3 pos)
    {
        // TODO: 实例化脉冲 Decal, 颜色依界内外切换(绿/红)
    }

    void OnDestroy()
    {
        client?.Close();
    }
}

// 轻量 WebSocket 客户端接口契约(生产环境替换为 Colyseus SDK 或 NativeWebSocket)
public class WebSocketClient
{
    public event Action OnOpen;
    public event Action<string> OnMessage;

    public WebSocketClient(string url) { }
    public void Connect() { }
    public void Send(string data) { }
    public void Close() { }
}
