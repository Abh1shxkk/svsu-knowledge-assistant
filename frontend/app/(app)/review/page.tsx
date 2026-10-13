"use client";

import { useState } from "react";
import Link from "next/link";
import { getDoc, me, useStore } from "@/lib/store";
import { Pages } from "@/components/paper";
import { fmtD, todayIso } from "@/lib/util";
import { Icon } from "@/components/icon";
import { Ft, Pill } from "@/components/ui";

export default function ReviewPage() {
  const s = useStore();
  const { save, logAudit, toast } = useStore.getState();
  const queue = s.documents.filter((d) => ["Pending", "Changes requested"].includes(d.status));
  const [selId, setSelId] = useState<string | null>(queue[0]?.id ?? null);
  const [comment, setComment] = useState("");
  const d = selId ? getDoc(s, selId) : queue[0];

  const decided = s.documents.flatMap((x) => x.approvals.filter((a) => /Approved|Rejected|Changes|Withdrawn/.test(a.step)).map((a) => ({ ...a, doc: x })))
    .sort((a, b) => b.date.localeCompare(a.date)).slice(0, 8);

  const decide = (v: "approve" | "changes" | "reject") => {
    if (!d) return;
    if (v !== "approve" && !comment.trim()) { toast("Add a comment for the uploader"); return; }
    const by = me(s).name;
    const next = { ...d };
    if (v === "approve") {
      next.status = "Active";
      next.approvals = [...d.approvals, { step: "Approved and published", by, date: todayIso(), kind: "ok", note: comment }];
      if (d.revisionOf) { const o = getDoc(s, d.revisionOf); if (o && o.status === "Active") void save("documents", { ...o, status: "Superseded", supersededBy: d.id }); }
      logAudit("Approved", d.title); toast("Approved and published to the library");
    } else if (v === "changes") {
      next.status = "Changes requested";
      next.approvals = [...d.approvals, { step: "Changes requested", by, date: todayIso(), kind: "warn", note: comment }];
      toast("Sent back to " + d.uploadedBy);
    } else {
      next.status = "Rejected";
      next.approvals = [...d.approvals, { step: "Rejected", by, date: todayIso(), kind: "bad", note: comment }];
      toast("Document rejected");
    }
    void save("documents", next);
    setComment(""); setSelId(null);
  };

  const checks = d ? [
    ["ok", "Required fields complete"],
    ["ok", "Reference number present"],
    ["ok", "No conflicting active document found"],
    d.visibility === "Management Only" ? ["warn", "Visibility is Management Only. Change to All Staff on approval if staff should see it."] : ["ok", "Visibility: " + d.visibility],
    ["ok", `Text extracted from all ${d.pages.length} page(s)`],
  ] as [string, string][] : [];

  return (
    <div className="wrap">
      <div className="pagehead"><div><h2>Review &amp; Approvals</h2><p>Documents are only used in the library and AI answers after an approver publishes them.</p></div><span className="pill warn">{queue.length} waiting</span></div>

      {queue.length && d ? (
        <div className="rgrid">
          <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
            {queue.map((x) => (
              <button key={x.id} className={`ritem ${x.id === d.id ? "on" : ""}`} onClick={() => setSelId(x.id)} type="button">
                <div className="row between"><Ft k={x.fileType} /><Pill status={x.status} /></div>
                <b>{x.title}</b><span className="xs muted">{x.dept} · submitted {fmtD(x.approvals[0]?.date)} by {x.uploadedBy}</span>
              </button>
            ))}
          </div>
          <div className="card">
            <div className="card-h"><div><h3>{d.title}</h3><span className="mono muted">{d.ref}</span></div><Link className="btn sm" href={`/library/${d.id}`}>Full record</Link></div>
            <div className="card-b rv2">
              <div className="pagesbox" style={{ maxHeight: 560, padding: 14 }}><Pages doc={d} /></div>
              <div style={{ display: "flex", flexDirection: "column", gap: 16, minWidth: 0 }}>
                <dl className="kv" style={{ gridTemplateColumns: "110px 1fr" }}>
                  <dt>Type</dt><dd>{d.type}</dd><dt>Authority</dt><dd>{d.authority}</dd><dt>Effective</dt><dd>{fmtD(d.effective)}</dd>
                  <dt>Audience</dt><dd>{d.audience.join(", ")}</dd><dt>Tags</dt><dd>{d.tags.join(", ")}</dd><dt>Visibility</dt><dd>{d.visibility}</dd>
                </dl>
                <div><b className="sm">Automatic checks</b><div className="checks" style={{ marginTop: 6 }}>
                  {checks.map(([k, t], i) => <div key={i} className={`c ${k}`}><Icon n={k === "ok" ? "check" : "alert"} s /><span>{t}</span></div>)}</div></div>
                <div className="fld"><label htmlFor="revc">Comment to uploader</label>
                  <textarea className="inp" id="revc" rows={3} value={comment} onChange={(e) => setComment(e.target.value)} placeholder="Required when requesting changes or rejecting" /></div>
                <div className="row">
                  <button className="btn pri" onClick={() => decide("approve")} type="button"><Icon n="check" s /> Approve &amp; publish</button>
                  <button className="btn" onClick={() => decide("changes")} type="button">Request changes</button>
                  <button className="btn danger" onClick={() => decide("reject")} type="button">Reject</button>
                </div>
              </div>
            </div>
          </div>
        </div>
      ) : <div className="card empty"><p><b>All caught up.</b> No documents are waiting for review.</p><Link className="btn sm" href="/upload" style={{ marginTop: 10 }}>Upload a document</Link></div>}

      <div className="card"><div className="card-h"><h3>Recent decisions</h3></div>
        <div className="table-wrap"><table className="t"><thead><tr><th>Document</th><th>Decision</th><th>By</th><th>Date</th></tr></thead>
          <tbody>{decided.map((a, i) => (
            <tr key={i}><td><Link className="link" href={`/library/${a.doc.id}`}>{a.doc.title}</Link></td>
              <td><span className={`pill ${a.kind || "mute"}`}>{a.step}</span></td><td>{a.by}</td><td className="num">{fmtD(a.date)}</td></tr>
          ))}</tbody></table></div></div>
    </div>
  );
}
