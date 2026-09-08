// CameraController.cs —— PRD §3 Module 2: 动态取景(软阻尼跟随 + 高球拉远)
// 参考实现(与 Web 原型 js/game.js cameraUpdate 一致), 未在 Unity 编辑器中编译验证。
using UnityEngine;

public class CameraController : MonoBehaviour
{
    public Transform player;      // 本方球员
    public Transform ball;
    public float xDamp = 0.2f;    // PRD: X 阻尼 0.2
    public float zDamp = 0.1f;    // PRD: Z 阻尼 0.1
    public float baseFov = 62f;
    public Vector3 basePos = new Vector3(0f, 5.1f, -13.6f);
    public Vector3 lookTarget = new Vector3(0f, 1.0f, 2.2f);

    private Camera cam;
    private Vector3 smoothedPos;

    void Awake()
    {
        cam = GetComponent<Camera>();
        smoothedPos = basePos;
    }

    void LateUpdate()
    {
        // PRD: 相机位置软阻尼跟随球员 X
        float tx = basePos.x + player.position.x * 0.3f;
        float ty = basePos.y + Mathf.Clamp((ball.position.y - 2.5f) * 0.14f, 0f, 1.1f);
        Vector3 target = new Vector3(tx, ty, basePos.z);

        // 帧率无关的指数阻尼(对应 PRD 阻尼系数的手感)
        float kx = 1f - Mathf.Exp(-xdamp * 16f * Time.deltaTime);
        float ky = 1f - Mathf.Exp(-zDamp * 22f * Time.deltaTime);
        smoothedPos.x += (target.x - smoothedPos.x) * kx;
        smoothedPos.y += (target.y - smoothedPos.y) * ky;
        smoothedPos.z = basePos.z;

        transform.position = smoothedPos;
        transform.LookAt(new Vector3(player.position.x * 0.16f, lookTarget.y, lookTarget.z));

        // PRD: 深场高吊球时动态拉远 FOV, 保持网与对手均在视锥内
        float fovTarget = baseFov + Mathf.Clamp((ball.position.y - 2.8f) * 0.8f, 0f, 5f);
        cam.fieldOfView = Mathf.Lerp(cam.fieldOfView, fovTarget, 1f - Mathf.Exp(-3f * Time.deltaTime));
    }
}
