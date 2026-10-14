"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { api } from "@/lib/api";
import { getDoc, me, useFullDoc, useStore } from "@/lib/store";
import { Pages } from "@/components/paper";
import { fmtD, todayIso } from "@/lib/util";
import { Icon } from "@/components/icon";
import { Ft, Pill } from "@/components/ui";

const CHECKLIST = ["Content matches the signed original", "Tags and audience are correct", "Access level is appropriate", "Older versions are linked"];

export default function ReviewPage() {
  const s = useStore();
  const { save, toast } = useStore.getState();
  const queue = s.documents.filter((d) => ["Pending", "Changes requested"].includes(d.status));
  const [selId, setSelId] = useState<string | null>(null);
  const d = (selId && queue.find((x) => x.id === selId)) || queue[0];
  const full = useFullDoc(d?.id);
  // The comment, checklist and checks belong to the document on screen; switching documents starts afresh.
  const [form, setForm] = useState({ id: "", comment: "", ticked: [] as number[] });
  const { comment, ticked } = form.id === d?.id ? form : { comment: "", ticked: [] as number[] };
  const setComment = (c: string) => setForm({ id: d!.id, comment: c, ticked });
  const setTicked = (t: number[]) => setForm({ id: d!.id, comment, ticked: t });
  const [loaded, setLoaded] = useState<{ id: string; list: [string, string][] } | null>(null);
  const checks = d && loaded?.id === d.id ? loaded.list : null;  // an empty queue has no document
  useEffect(() => {
    const id = d?.id;
    if (id) api.checks(id).then((list) => setLoaded({ id, list })).catch(() => setLoaded({ id, list: [["warn", "Automatic checks could not run"]] }));
  }, [d?.id]);

  const decided = s.documents.flatMap((x) => x.approvals.filter((a) => /Approved|Rejected|Changes|Withdrawn/.test(a.step)).map((a) => ({ ...a, doc: x })))
    .sort((a, b) => b.date.localeCompare(a.date)).slice(0, 8);

  const decide = async (v: "approve" | "changes" | "reject") => {
    if (!d) return;
    if (v !== "approve" && !comment.trim()) { toast("Add a comment for the uploader"); return; }
    if (v === "approve" && ticked.length < CHECKLIST.length) { toast("Tick every item on the reviewer checklist first"); return; }
    const by = me(s).name;
    const [status, step, kind, msg] = {
      approve: ["Active", "Approved and published", "ok", "Approved and published to the library"],
      changes: ["Changes requested", "Changes requested", "warn", "Sent back to " + d.uploadedBy],
      reject: ["Rejected", "Rejected", "bad", "Document rejected"],
    }[v] as [typeof d.status, string, "ok" | "warn" | "bad", string];
    if (!await save("documents", { ...d, status, approvals: [...d.approvals, { step, by, date: todayIso(), kind, note: comment }] })) return;
    if (v === "approve") {
      const now = () => useStore.getState();
      const old = d.revisionOf ? getDoc(now(), d.revisionOf) : undefined;  // a published revision replaces the older document
      if (old && old.status === "Active") await save("documents", { ...old, status: "Superseded", supersededBy: d.id });
      for (const rid of d.related) {  // links chosen at upload become two-way
        const o = getDoc(now(), rid);
        if (o && !o.related.includes(d.id)) await save("documents", { ...o, related: [...o.related, d.id] });
      }
    }
    toast(msg);
    setSelId(null); setForm({ id: "", comment: "", ticked: [] });
  };

  return (
    <div className="wrap">
      <div className="pagehead"><div><h2>Review &amp; Approvals</h2><p>Documents are only used in the library and AI answers after an approver publishes them.</p></div><span className="pill warn">{queue.length} waiting</span></div>

      {d ? (
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
              <div className="pagesbox" style={{ maxHeight: 560, padding: 14 }}>{full ? <Pages doc={full} /> : <span className="spin" />}</div>
              <div style={{ display: "flex", flexDirection: "column", gap: 16, minWidth: 0 }}>
                <dl className="kv" style={{ gridTemplateColumns: "110px 1fr" }}>
                  <dt>Type</dt><dd>{d.type}</dd><dt>Authority</dt><dd>{d.authority}</dd><dt>Effective</dt><dd>{fmtD(d.effective)}</dd>
                  <dt>Audience</dt><dd>{d.audience.join(", ")}</dd><dt>Tags</dt><dd>{d.tags.join(", ")}</dd><dt>Visibility</dt><dd>{d.visibility}</dd>
                  {d.revisionOf && <><dt>Revises</dt><dd>{getDoc(s, d.revisionOf)?.ref ?? "—"}</dd></>}
                </dl>
                <div><b className="sm">Automatic checks</b><div className="checks" style={{ marginTop: 6 }}>
                  {checks ? checks.map(([k, t], i) => <div key={i} className={`c ${k}`}><Icon n={k === "ok" ? "check" : "alert"} s /><span>{t}</span></div>)
                    : <div className="c"><span className="spin" /> Checking…</div>}</div></div>
                <div><b className="sm">Reviewer checklist</b><div className="checks" style={{ marginTop: 6 }}>
                  {CHECKLIST.map((t, i) => (
                    <label key={t} className="c"><input type="checkbox" checked={ticked.includes(i)} onChange={() => setTicked(ticked.includes(i) ? ticked.filter((x) => x !== i) : [...ticked, i])} /> {t}</label>
                  ))}</div></div>
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
