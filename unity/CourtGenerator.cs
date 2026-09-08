// CourtGenerator.cs —— PRD §4 Prompt#1.1: 程序化生成标准单打网球场
// 参考实现(与 Web 原型 js/render/scene.js 逻辑一致), 未在 Unity 编辑器中编译验证。
// 尺寸: 23.77m × 8.23m(单打), 网高 0.914m。坐标系: X 右 / Y 上 / Z 朝向对手, 网在 Z=0。
using UnityEngine;

public class CourtGenerator : MonoBehaviour
{
    public const float CourtLength = 23.77f;
    public const float CourtWidth = 8.23f;
    public const float HalfL = CourtLength * 0.5f;
    public const float HalfW = CourtWidth * 0.5f;
    public const float NetHeight = 0.914f;
    public const float ServiceLine = 6.4f;

    public Material courtMaterial;
    public Material lineMaterial;
    public Material netMaterial;

    [ContextMenu("Generate Court")]
    public void Generate()
    {
        ClearChildren();
        CreateGround();
        CreateCourt();
        CreateLines();
        CreateNet();
    }

    private void ClearChildren()
    {
        for (int i = transform.childCount - 1; i >= 0; i--)
            DestroyImmediate(transform.GetChild(i).gameObject);
    }

    private void CreateGround()
    {
        var ground = GameObject.CreatePrimitive(PrimitiveType.Plane); // 默认 10x10, 需缩放
        ground.name = "Apron";
        ground.transform.SetParent(transform);
        ground.transform.localScale = new Vector3(12f, 1f, 12f);
        ground.transform.position = new Vector3(0f, -0.01f, 0f);
        if (courtMaterial != null)
            ground.GetComponent<Renderer>().sharedMaterial = new Material(courtMaterial);
    }

    private void CreateCourt()
    {
        var court = GameObject.CreatePrimitive(PrimitiveType.Cube);
        court.name = "Court";
        court.transform.SetParent(transform);
        court.transform.localScale = new Vector3(CourtWidth, 0.02f, CourtLength);
        court.transform.position = new Vector3(0f, 0.01f, 0f);
    }

    private void CreateLine(float x1, float z1, float x2, float z2, float width = 0.05f)
    {
        var line = GameObject.CreatePrimitive(PrimitiveType.Cube);
        line.name = "Line";
        line.transform.SetParent(transform);
        float len = Mathf.Sqrt((x2 - x1) * (x2 - x1) + (z2 - z1) * (z2 - z1));
        line.transform.localScale = new Vector3(len, 0.008f, width);
        line.transform.position = new Vector3((x1 + x2) * 0.5f, 0.02f, (z1 + z2) * 0.5f);
        line.transform.rotation = Quaternion.Euler(0f, -Mathf.Atan2(z2 - z1, x2 - x1) * Mathf.Rad2Deg, 0f);
        if (lineMaterial != null)
            line.GetComponent<Renderer>().sharedMaterial = lineMaterial;
    }

    private void CreateLines()
    {
        // 底线
        CreateLine(-HalfW, -HalfL, HalfW, -HalfL);
        CreateLine(-HalfW, HalfL, HalfW, HalfL);
        // 单打边线
        CreateLine(-HalfW, -HalfL, -HalfW, HalfL);
        CreateLine(HalfW, -HalfL, HalfW, HalfL);
        // 发球线 + 中线
        CreateLine(-HalfW, -ServiceLine, HalfW, -ServiceLine);
        CreateLine(-HalfW, ServiceLine, HalfW, ServiceLine);
        CreateLine(0f, -ServiceLine, 0f, ServiceLine);
    }

    private void CreateNet()
    {
        var net = GameObject.CreatePrimitive(PrimitiveType.Cube);
        net.name = "Net";
        net.transform.SetParent(transform);
        net.transform.localScale = new Vector3(10.97f + 1.2f, NetHeight, 0.02f);
        net.transform.position = new Vector3(0f, NetHeight * 0.5f, 0f);
        if (netMaterial != null)
            net.GetComponent<Renderer>().sharedMaterial = netMaterial;
    }
}
