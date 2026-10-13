"use client";

import { useState } from "react";
import { getDoc, useStore } from "@/lib/store";
import { fmtD } from "@/lib/util";
import { Icon } from "@/components/icon";
import type { Msg } from "@/lib/types";

export default function ReportsPage() {
  const s = useStore();
  const { save, toast } = useStore.getState();
  const [fbFilter, setFbFilter] = useState<"all" | "down">("all");

  const aiMsgs = s.chats.flatMap((c) => c.msgs.filter((m): m is Extract<Msg, { role: "ai" }> => m.role === "ai" && !!m.answer));
  const withCites = aiMsgs.filter((m) => (m.answer?.cites.length ?? 0) > 0).length;
  const citePct = aiMsgs.length ? Math.round((withCites / aiMsgs.length) * 100) : 0;
  const up = s.feedback.filter((f) => f.rating === "up").length;
  const helpfulPct = s.feedback.length ? Math.round((up / s.feedback.length) * 100) : 0;
  const openUnans = s.unanswered.filter((u) => u.status !== "Resolved").length;

  // Unanswered questions grouped by department (real data).
  const byDept: Record<string, number> = {};
  s.unanswered.forEach((u) => { byDept[u.dept] = (byDept[u.dept] ?? 0) + u.count; });
  const bars = Object.entries(byDept).sort((a, b) => b[1] - a[1]).slice(0, 6);
  const barMax = Math.max(1, ...bars.map(([, n]) => n));

  const fbs = s.feedback.filter((f) => fbFilter === "all" || f.rating === "down");
  const resolveU = (id: string) => { const u = s.unanswered.find((x) => x.id === id); if (u) { void save("unanswered", { ...u, status: "Resolved" }); toast("Marked as resolved"); } };
  const resolveC = (id: string) => { const c = s.conflicts.find((x) => x.id === id); if (c) { void save("conflicts", { ...c, status: "Resolved" }); toast("Conflict marked resolved"); } };

  return (
    <div className="wrap">
      <div className="pagehead"><div><h2>Reports &amp; Feedback</h2><p>Usage figures, questions the records could not answer, and feedback that needs follow-up.</p></div></div>

      <div className="kpis kpis4">
        <div className="kpi"><span>AI answers this month</span><b>{aiMsgs.length}</b><small>Across all conversations</small></div>
        <div className="kpi"><span>Answered with citations</span><b>{citePct}%</b><small>Rest: clarifications or no record</small></div>
        <div className="kpi"><span>Unanswered (open)</span><b>{openUnans}</b><small>Need a document uploaded</small></div>
        <div className="kpi"><span>Rated helpful</span><b>{helpfulPct}%</b><small>{s.feedback.length} ratings</small></div>
      </div>

      <div className="dgrid">
        <div className="card"><div className="card-h"><h3>Unanswered questions by department</h3><span className="xs muted">Times asked</span></div>
          {bars.length ? <div className="bars">{bars.map(([k, v]) => (
            <div key={k} className="bar"><span>{k}</span><div className="tr"><i style={{ width: `${(v / barMax) * 100}%` }} /></div><b>{v}</b></div>
          ))}</div> : <div className="empty">No unanswered questions.</div>}
        </div>
        <div className="card"><div className="card-h"><h3>Open conflicts between documents</h3></div>
          {s.conflicts.length ? s.conflicts.map((cf) => (
            <div key={cf.id} className="li" style={{ alignItems: "flex-start" }}>
              <span style={{ color: "var(--red)", marginTop: 2 }}><Icon n="alert" s /></span>
              <div className="main"><b style={{ whiteSpace: "normal" }}>{cf.topic}</b>
                <span>{cf.docs.map((id) => getDoc(s, id)?.ref).join(" vs ")} · reported {cf.reported} by {cf.by}</span>
                <div className="row" style={{ marginTop: 6 }}>
                  {cf.status === "Open" ? <button className="btn sm ok" onClick={() => resolveC(cf.id)} type="button">Mark resolved</button> : <span className="pill ok">Resolved</span>}
                </div></div>
            </div>
          )) : <div className="empty">No open conflicts.</div>}
        </div>
      </div>

      <div className="card"><div className="card-h"><h3>Unanswered questions</h3><span className="xs muted">Count shows how often it was asked</span></div>
        <div className="table-wrap"><table className="t">
          <thead><tr><th>Question</th><th>Times</th><th>Last asked</th><th>Department</th><th>Status</th><th /></tr></thead>
          <tbody>{s.unanswered.length ? s.unanswered.map((u) => (
            <tr key={u.id}><td>{u.q}</td><td className="num">{u.count}</td><td className="num">{fmtD(u.last)}</td><td>{u.dept}</td>
              <td><span className={`pill ${u.status === "Resolved" ? "ok" : u.status === "Open" ? "warn" : "info"}`}>{u.status}</span></td>
              <td style={{ textAlign: "right", whiteSpace: "nowrap" }}>{u.status !== "Resolved" && <button className="btn sm ok" onClick={() => resolveU(u.id)} type="button">Resolve</button>}</td>
            </tr>
          )) : <tr><td colSpan={6}><div className="empty">No unanswered questions.</div></td></tr>}</tbody>
        </table></div></div>

      <div className="card"><div className="card-h"><h3>Answer feedback</h3>
        <div className="seg"><button className={fbFilter === "all" ? "on" : ""} onClick={() => setFbFilter("all")} type="button">All ({s.feedback.length})</button>
          <button className={fbFilter === "down" ? "on" : ""} onClick={() => setFbFilter("down")} type="button">Not helpful ({s.feedback.length - up})</button></div></div>
        {fbs.length ? fbs.map((f) => (
          <div key={f.id} className="li" style={{ alignItems: "flex-start" }}>
            <span style={{ color: f.rating === "up" ? "var(--green)" : "var(--red)", marginTop: 2 }}><Icon n={f.rating} s /></span>
            <div className="main"><b style={{ whiteSpace: "normal" }}>{f.q}</b>
              <span style={{ display: "block", whiteSpace: "normal" }}>{f.reason && <span className="tag">{f.reason}</span>} {f.comment}</span>
              <span>{f.who} · {f.when}</span></div>
          </div>
        )) : <div className="empty">No feedback yet.</div>}
      </div>
    </div>
  );
}
