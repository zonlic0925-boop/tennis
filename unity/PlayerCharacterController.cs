// PlayerCharacterController.cs —— PRD §4 Prompt#3 + §3 Module 2: 点击移动 / 触发区 / 击球后回位
// 参考实现(与 Web 原型 js/game.js 移动逻辑一致), 未在 Unity 编辑器中编译验证。
using UnityEngine;

[RequireComponent(typeof(CharacterController))]
public class PlayerCharacterController : MonoBehaviour
{
    public float moveSpeed = 6.5f;        // PRD Prompt#3: 6.5 m/s
    public float recoverFactor = 0.6f;    // PRD Module 2: 击球后 0.6x 速度回位
    public Vector3 homeBase = new Vector3(0f, 0f, -9.5f); // PRD: 底线中心 (0,0,-9.5)
    public float strikeTriggerRadius = 1.5f; // PRD Prompt#3: 1.5m 触发区

    private CharacterController cc;
    private Vector3 moveTarget;
    private bool hasTarget;
    private bool recovering;

    void Awake()
    {
        cc = GetComponent<CharacterController>();
    }

    void Update()
    {
        // 点击球场 → 射线到 Y=0 地面 → 设置目标(PRD Module 2: Tap on court)
        if (Input.GetMouseButtonDown(0) || (Input.touchCount > 0 && Input.GetTouch(0).phase == TouchPhase.Began))
        {
            Vector3 screenPos = Input.touchCount > 0
                ? (Vector3)Input.GetTouch(0).position
                : Input.mousePosition;
            Ray ray = Camera.main.ScreenPointToRay(screenPos);
            Plane ground = new Plane(Vector3.up, Vector3.zero);
            if (ground.Raycast(ray, out float enter))
            {
                Vector3 hit = ray.GetPoint(enter);
                if (Mathf.Abs(hit.x) <= 6f && Mathf.Abs(hit.z) <= 13f)
                {
                    moveTarget = new Vector3(hit.x, 0f, hit.z);
                    hasTarget = true;
                    recovering = false;
                }
            }
        }

        // 击球后的自动回位: 0.6x 速度向底线中心(PRD Module 2)
        if (recovering)
        {
            moveTarget = homeBase;
            hasTarget = true;
        }

        if (hasTarget)
        {
            Vector3 to = moveTarget - transform.position;
            to.y = 0f;
            float dist = to.magnitude;
            if (dist < 0.06f)
            {
                hasTarget = false;
            }
            else
            {
                float speed = moveSpeed * (recovering ? recoverFactor : 1f);
                Vector3 step = to.normalized * Mathf.Min(speed * Time.deltaTime, dist);
                cc.Move(step);
            }
        }
    }

    // 击球成功后调用: 触发挥拍动画事件与回位(PRD Prompt#3.3/3.4)
    public void OnStrokeCompleted()
    {
        recovering = true;
    }

    // 球是否进入 1.5m 触发区(PRD Prompt#3.2)
    public bool IsBallInStrikeZone(Vector3 ballPos)
    {
        Vector3 d = ballPos - transform.position;
        d.y = 0f;
        return d.magnitude <= strikeTriggerRadius;
    }
}
