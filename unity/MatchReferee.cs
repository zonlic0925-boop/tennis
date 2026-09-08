// MatchReferee.cs —— PRD §3 Module 3: 规则引擎(7 分净胜 2 / 发球校验 / 回合判定)
// 参考实现(与 Web 原型 js/core/referee.js 逻辑一致), 未在 Unity 编辑器中编译验证。
using System;
using UnityEngine;

public class MatchReferee : MonoBehaviour
{
    public const int TargetPoints = 7;  // PRD: First to 7
    public const int WinBy = 2;         // PRD: Win by 2

    public enum Phase { WaitingForPlayers, CoinToss, Serving, InPlay, PointScored, MatchEnd }

    public Phase phase { get; private set; } = Phase.WaitingForPlayers;
    public int scoreP1 { get; private set; }
    public int scoreP2 { get; private set; }
    public bool serverIsP1 { get; private set; } = true;
    public int serveAttempt { get; private set; } = 1;
    public bool matchOver { get; private set; }
    public bool playerWon { get; private set; }

    public event Action<string> OnToast;   // "双误" / "出界" / "下网" ...
    public event Action<bool> OnMatchEnd;  // winnerIsPlayer

    public void StartMatch()
    {
        scoreP1 = 0;
        scoreP2 = 0;
        serverIsP1 = true;
        serveAttempt = 1;
        phase = Phase.Serving;
        matchOver = false;
    }

    // 发球落点校验: 对角线发球区 |Z| ∈ [6.4, 11.885]
    public static bool CheckServeBox(Vector3 pos, float serverSideSign)
    {
        bool inDepth = Mathf.Abs(pos.z) >= 6.4f && Mathf.Abs(pos.z) <= CourtGenerator.HalfL;
        bool inDiagonal = Mathf.Sign(pos.x) == -serverSideSign && Mathf.Abs(pos.x) <= CourtGenerator.HalfW;
        return inDepth && inDiagonal;
    }

    public static bool CheckInBounds(Vector3 pos)
    {
        return Mathf.Abs(pos.x) <= CourtGenerator.HalfW && Mathf.Abs(pos.z) <= CourtGenerator.HalfL;
    }

    // 发球失误 → 二发; 双误 → 接发方得分
    public void OnServeFault(bool wasServerP1)
    {
        if (phase != Phase.Serving || wasServerP1 != serverIsP1) return;
        if (serveAttempt == 1)
        {
            serveAttempt = 2;
            OnToast?.Invoke("发球失误");
            return;
        }
        AwardPoint(!serverIsP1, "双误");
    }

    public void OnServeIn(bool wasServerP1)
    {
        if (phase == Phase.Serving && wasServerP1 == serverIsP1)
            phase = Phase.InPlay;
    }

    // 回合结束: 得分方得分并轮换发球; 检查赛点(7 分净胜 2)
    public void AwardPoint(bool winnerIsP1, string reason)
    {
        if (phase != Phase.InPlay && phase != Phase.Serving) return;
        if (winnerIsP1) scoreP1++;
        else scoreP2++;
        OnToast?.Invoke(reason);

        int lead = Mathf.Abs(scoreP1 - scoreP2);
        int high = Mathf.Max(scoreP1, scoreP2);
        if (high >= TargetPoints && lead >= WinBy)
        {
            phase = Phase.MatchEnd;
            matchOver = true;
            playerWon = scoreP1 > scoreP2;
            OnMatchEnd?.Invoke(playerWon);
            return;
        }
        phase = Phase.PointScored;
        serverIsP1 = !serverIsP1;   // 每分轮换发球
        serveAttempt = 1;
    }

    public void NextServe()
    {
        if (phase == Phase.PointScored) phase = Phase.Serving;
    }
}
