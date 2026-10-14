"use client";

import { useEffect, useState } from "react";
import { api } from "@/lib/api";
import { getDoc, lists, useStore } from "@/lib/store";
import { fmtD } from "@/lib/util";
import { Icon } from "@/components/icon";
import { BarChart } from "@/components/charts";
import { CompareModal, RequestDocModal } from "@/components/modals";
import { Field, ModalFoot } from "@/components/ui";
import type { Unanswered } from "@/lib/types";
import { QualityCard } from "./quality";

type Summary = Awaited<ReturnType<typeof api.reportSummary>>;
const csvCell = (v: string | number) => `"${String(v).replace(/"/g, '""')}"`;

export default function ReportsPage() {
  const s = useStore();
  const { save, toast, openModal } = useStore.getState();
  const [fbFilter, setFbFilter] = useState<"all" | "down">("all");
  const [sum, setSum] = useState<Summary | null>(null);
  useEffect(() => { api.reportSummary().then(setSum).catch(() => setSum(null)); }, []);

  const up = s.feedback.filter((f) => f.rating === "up").length;
  const helpfulPct = s.feedback.length ? Math.round((up / s.feedback.length) * 100) : 0;
  const openUnans = s.unanswered.filter((u) => u.status !== "Resolved").length;
  const fbs = s.feedback.filter((f) => fbFilter === "all" || f.rating === "down");

  const resolveU = async (u: Unanswered) => { if (await save("unanswered", { ...u, status: "Resolved" })) toast("Marked as resolved"); };
  const resolveC = async (id: string) => { const c = s.conflicts.find((x) => x.id === id); if (c && await save("conflicts", { ...c, status: "Resolved" })) toast("Conflict marked resolved"); };
  const copyCsv = () => {
    const rows = s.unanswered.map((u) => [u.q, u.count, u.last, u.dept, u.status].map(csvCell).join(","));
    navigator.clipboard?.writeText(["Question,Times asked,Last asked,Department,Status", ...rows].join("\n"));
    toast("Copied as CSV");
  };

  return (
    <div className="wrap">
      <div className="pagehead"><div><h2>Reports &amp; Feedback</h2><p>Usage figures, questions the records could not answer, and feedback that needs follow-up.</p></div>
        <button className="btn" onClick={copyCsv} type="button"><Icon n="copy" s /> Copy as CSV</button></div>

      <div className="kpis kpis4">
        <div className="kpi"><span>Questions this month</span><b>{sum?.month ?? "—"}</b><small>Asked by everyone, across all conversations</small></div>
        <div className="kpi"><span>Answered with citations</span><b>{sum ? `${sum.cited}%` : "—"}</b><small>Rest: clarifications or no record</small></div>
        <div className="kpi"><span>Unanswered (open)</span><b>{openUnans}</b><small>Need a document uploaded</small></div>
        <div className="kpi"><span>Rated helpful</span><b>{helpfulPct}%</b><small>{s.feedback.length} ratings</small></div>
      </div>

      <QualityCard />

      <div className="dgrid">
        <div className="card"><div className="card-h"><h3>Questions per week</h3><span className="xs muted">Last 8 weeks</span></div>
          <div className="card-b" style={{ maxWidth: 460, width: "100%", margin: "0 auto" }}>{sum ? <BarChart points={sum.weeks} caption="Questions asked per week" /> : <span className="spin" />}</div>
        </div>
        <div className="card"><div className="card-h"><h3>Open conflicts between documents</h3></div>
          {s.conflicts.length ? s.conflicts.map((cf) => (
            <div key={cf.id} className="li" style={{ alignItems: "flex-start" }}>
              <span style={{ color: "var(--red)", marginTop: 2 }}><Icon n="alert" s /></span>
              <div className="main"><b style={{ whiteSpace: "normal" }}>{cf.topic}</b>
                <span>{cf.docs.map((id) => getDoc(s, id)?.ref ?? "a removed document").join(" vs ")} · reported {fmtD(cf.reported)} by {cf.by}</span>
                <div className="row" style={{ marginTop: 6 }}>
                  {cf.docs.length >= 2 && <button className="btn sm" type="button" onClick={() => openModal({ title: "Compare documents", wide: true, body: <CompareModal a={cf.docs[0]} b={cf.docs[1]} topic={cf.topic} /> })}>Compare</button>}
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
            <tr key={u.id}><td>{u.q}{u.note && <div className="xs muted">{u.requested_by && `${u.requested_by}: `}{u.note}</div>}</td>
              <td className="num">{u.count}</td><td className="num">{fmtD(u.last)}</td><td>{u.dept}</td>
              <td><span className={`pill ${u.status === "Resolved" ? "ok" : u.status === "Open" ? "warn" : "info"}`}>{u.status}</span></td>
              <td style={{ textAlign: "right", whiteSpace: "nowrap" }}>{u.status !== "Resolved" && <>
                <button className="btn sm" type="button" onClick={() => openModal({ title: "Assign question", body: <AssignModal u={u} /> })}>Assign</button>{" "}
                <button className="btn sm" type="button" onClick={() => openModal({ title: "Request a document", body: <RequestDocModal q={u.q} dept={u.dept} /> })}>Request document</button>{" "}
                <button className="btn sm ok" onClick={() => resolveU(u)} type="button">Resolve</button></>}</td>
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
              <span>{f.who} · {fmtD(f.when)}</span></div>
          </div>
        )) : <div className="empty">No feedback yet.</div>}
      </div>
    </div>
  );
}

function AssignModal({ u }: { u: Unanswered }) {
  const s = useStore();
  const [dept, setDept] = useState(u.dept);
  const submit = async () => {
    if (await s.save("unanswered", { ...u, dept, status: "Assigned" })) { s.closeModal(); s.toast("Assigned to " + dept); }
  };
  return (
    <>
      <p className="sm">“{u.q}”</p>
      <Field label="Department" htmlFor="as-d"><select className="inp" id="as-d" value={dept} onChange={(e) => setDept(e.target.value)}>
        {lists(s).DEPTS.map((d) => <option key={d}>{d}</option>)}</select></Field>
      <ModalFoot><button className="btn" onClick={s.closeModal} type="button">Cancel</button><button className="btn pri" onClick={submit} type="button">Assign</button></ModalFoot>
    </>
  );
}
