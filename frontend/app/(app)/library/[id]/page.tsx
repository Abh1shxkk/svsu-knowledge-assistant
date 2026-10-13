"use client";

import { useState } from "react";
import Link from "next/link";
import { useParams, useRouter } from "next/navigation";
import { canUpload, getDoc, HIDDEN_ST, lists, useStore } from "@/lib/store";
import { Pages, docText } from "@/components/paper";
import { fmtD, nid } from "@/lib/util";
import { Icon } from "@/components/icon";
import { Ft, Note, Pill, Tabs, Tags, DateBox, Due } from "@/components/ui";
import { EditMetaModal, WithdrawModal } from "./modals";
import type { Doc } from "@/lib/types";

export default function DocDetail() {
  const id = useParams().id as string;
  const router = useRouter();
  const s = useStore();
  const d = getDoc(s, id);
  const [tab, setTab] = useState("overview");
  const { openViewer, openModal, save, toast, set } = useStore.getState();

  if (!d) return <div className="wrap"><div className="empty">Document not found.</div></div>;
  const admin = canUpload(s);
  const dls = s.deadlines.filter((x) => x.doc === d.id);
  const bms = s.bm_passages.filter((x) => x.doc === d.id);
  const tabs: [string, string, number?][] = [
    ["overview", "Overview"], ["preview", "Preview"], ["text", "Extracted text"], ["approvals", "Approval history"],
    ["versions", "Versions", d.versions.length], ["related", "Related", d.related.length + (d.revisionOf ? 1 : 0) + (d.supersededBy ? 1 : 0)],
    ["access", "Access"], ["deadlines", "Actions & deadlines", dls.length], ["bookmarks", "Bookmarks", bms.length],
  ];

  const askAbout = () => { set({ scope: { mode: "files", files: [d.id], coll: null }, activeChat: null }); toast("Scope set to this document"); router.push("/ask"); };
  const restore = () => { void save("documents", { ...d, status: "Active" }); toast("Document restored to Active"); };

  return (
    <div className="wrap">
      <div className="crumb"><Link href="/library">Document Library</Link><Icon n="cr" s /><span className="mono">{d.ref}</span></div>
      <div className="dhero">
        <div style={{ display: "flex", flexDirection: "column", gap: 8, minWidth: 0 }}>
          <div className="row"><Pill status={d.status} /><Ft k={d.fileType} /><span className="sm muted">{d.type} · {d.dept} · {fmtD(d.date)}</span></div>
          <h2 lang={d.lang}>{d.title}</h2>
        </div>
        <div className="row">
          {!HIDDEN_ST.includes(d.status) && d.status !== "Withdrawn" && <button className="btn pri" onClick={askAbout} type="button"><Icon n="spark" s /> Ask about this</button>}
          <button className="btn" onClick={() => openViewer({ doc: d.id, page: 1 })} type="button"><Icon n="eye" s /> Open viewer</button>
          {admin && <>
            <button className="btn" onClick={() => openModal({ title: "Edit metadata", drawer: true, body: <EditMetaModal doc={d} /> })} type="button"><Icon n="edit" s /> Edit</button>
            {d.status !== "Withdrawn"
              ? <button className="btn danger" onClick={() => openModal({ title: "Withdraw document", body: <WithdrawModal doc={d} /> })} type="button"><Icon n="ban" s /> Withdraw</button>
              : <button className="btn" onClick={restore} type="button">Restore</button>}
          </>}
        </div>
      </div>

      <Tabs tabs={tabs} active={tab} onChange={setTab} />

      {tab === "overview" && <Overview d={d} admin={admin} />}
      {tab === "preview" && <div className="pagesbox"><Pages doc={d} onBookmark={admin || true ? (page, block) => bookmarkPassage(d, page, block) : undefined} /></div>}
      {tab === "text" && (
        <>
          <div className="row between"><p className="sm muted">{d.fileType === "scan" ? `Text from the OCR layer (${d.ocr}% confidence). Check against the scan before relying on figures.` : "Text extracted from the file. This is what the assistant searches."}</p>
            <button className="btn sm" onClick={() => { navigator.clipboard?.writeText(docText(d)); toast("Copied"); }} type="button"><Icon n="copy" s /> Copy text</button></div>
          <div className="exttext" lang={d.lang}>{docText(d)}</div>
        </>
      )}
      {tab === "approvals" && (
        <div className="card"><div className="timeline">{d.approvals.map((a, i) => (
          <div key={i} className={`tl ${a.kind}`}><i /><div><b>{a.step}</b><span>{fmtD(a.date)} · {a.by}</span>{a.note && <p>{a.note}</p>}</div></div>
        ))}</div></div>
      )}
      {tab === "versions" && (
        <div className="card"><div className="card-h"><h3>Version history</h3></div>
          <div className="table-wrap"><table className="t"><thead><tr><th>Version</th><th>Date</th><th>By</th><th>Change</th></tr></thead>
            <tbody>{[...d.versions].reverse().map((v, i) => (
              <tr key={i}><td className="mono">v{v.v}{i === 0 && <span className="pill info plain"> Current</span>}</td><td>{fmtD(v.date)}</td><td>{v.by}</td><td>{v.note}</td></tr>
            ))}</tbody></table></div></div>
      )}
      {tab === "related" && <Related d={d} />}
      {tab === "access" && <Access d={d} admin={admin} />}
      {tab === "deadlines" && (
        <div className="card"><div className="card-h"><h3>Actions and deadlines from this document</h3>
          {admin && <button className="btn sm" onClick={() => findDeadlines(d)} type="button"><Icon n="spark" s /> Find deadlines</button>}</div>
          {dls.length ? dls.map((x) => (
            <div key={x.id} className="li"><DateBox date={x.date} /><div className="main"><b>{x.title}</b><span>{x.owner} · {x.aud}</span></div><Due date={x.date} done={x.done} />
              <button className="btn sm" onClick={() => openViewer({ doc: x.doc, page: x.page, block: x.block, quote: x.quote })} type="button">Show in document</button></div>
          )) : <div className="empty">No deadlines extracted yet. {admin && "Use “Find deadlines”."}</div>}
        </div>
      )}
      {tab === "bookmarks" && (
        <div className="card"><div className="card-h"><h3>Bookmarked passages</h3></div>
          {bms.length ? bms.map((b) => (
            <div key={b.id} className="li"><span className="av" style={{ width: 28, height: 28 }}><Icon n="bm" s /></span>
              <div className="main"><b style={{ whiteSpace: "normal", fontFamily: "var(--f-doc)", fontWeight: 400 }} lang={d.lang}>“{b.quote}”</b><span>Page {b.page}{b.note && " · " + b.note}</span></div>
              <button className="btn sm" onClick={() => openViewer({ doc: b.doc, page: b.page, block: b.block, quote: b.quote })} type="button">Show</button></div>
          )) : <div className="empty">No bookmarks yet. Open the Preview tab and hover a paragraph to bookmark it.</div>}
        </div>
      )}
    </div>
  );

  function bookmarkPassage(doc: Doc, page: number, block: string) {
    const b = doc.pages[page - 1]?.find((x) => x.id === block);
    const quote = b ? (b.text as string).replace(/^\d+\.\s*/, "") : "";
    void save("bm_passages", { id: nid("bp"), doc: doc.id, page, block, quote, note: "", when: new Date().toLocaleDateString("en-IN") });
    toast("Passage bookmarked");
  }
  async function findDeadlines(doc: Doc) {
    toast("Reading the document for dates…");
    try {
      const found = await import("@/lib/api").then((m) => m.api.deadlines(doc.id));
      let added = 0;
      for (const dl of found) {
        if (!s.deadlines.some((x) => x.doc === doc.id && x.title === dl.title && x.date === dl.date)) {
          await save("deadlines", { ...dl, id: nid("dl"), dept: doc.dept }); added++;
        }
      }
      toast(added ? `${added} deadline(s) added` : "No new deadlines found");
    } catch (e) { toast((e as Error).message); }
  }
}

function Overview({ d, admin }: { d: Doc; admin: boolean }) {
  const s = useStore();
  const sup = d.supersededBy ? getDoc(s, d.supersededBy) : null;
  return (
    <div className="dlayout">
      <div className="card"><div className="card-h"><h3>Metadata</h3></div>
        <div className="card-b"><dl className="kv">
          <dt>Reference number</dt><dd className="mono">{d.ref}</dd>
          <dt>Document type</dt><dd>{d.type} · <Ft k={d.fileType} /></dd>
          <dt>Issuing authority</dt><dd>{d.authority}</dd><dt>Issuing department</dt><dd>{d.dept}</dd>
          <dt>Institution</dt><dd>{d.institution}</dd>
          <dt>Document date</dt><dd>{fmtD(d.date)}</dd><dt>Effective date</dt><dd>{fmtD(d.effective)}</dd>
          <dt>Expiry date</dt><dd>{d.expiry ? fmtD(d.expiry) : "Not applicable"}</dd>
          <dt>Applicable audience</dt><dd>{d.audience.join(", ")}</dd>
          <dt>Subject tags</dt><dd><Tags tags={d.tags} /></dd>
          <dt>Visibility</dt><dd>{d.visibility}</dd>
          <dt>Uploaded</dt><dd>{fmtD(d.uploadedOn)} by {d.uploadedBy}</dd>
          <dt>Description</dt><dd>{d.description || "—"}</dd>
        </dl></div>
      </div>
      <div style={{ display: "flex", flexDirection: "column", gap: 14 }}>
        {d.status === "Superseded" && sup && <Note kind="warn"><b>Superseded.</b><p className="sm">Replaced by {sup.ref}. Kept for historical questions.</p></Note>}
        {d.status === "Withdrawn" && <Note kind="bad"><b>Withdrawn.</b><p className="sm">{d.withdrawReason}</p></Note>}
        {d.status === "Pending" && <Note kind="warn"><b>Waiting for approval.</b><p className="sm">Not used in AI answers until it is approved.</p></Note>}
        <div className="card"><div className="card-h"><h3>First page</h3></div>
          <div className="card-b" style={{ background: "var(--surface-2)", maxHeight: 360, overflow: "hidden" }}>
            <div style={{ transform: "scale(.52)", transformOrigin: "top left", width: "192%" }}>
              <Pages doc={{ ...d, pages: [d.pages[0]] }} />
            </div>
          </div>
        </div>
      </div>
    </div>
  );
  void admin;
}

function Related({ d }: { d: Doc }) {
  const s = useStore();
  const rel: [string, string][] = [
    ...(d.revisionOf ? [[d.revisionOf, "Revision of (replaces)"] as [string, string]] : []),
    ...(d.supersededBy ? [[d.supersededBy, "Superseded by"] as [string, string]] : []),
    ...d.related.map((r) => [r, "Related"] as [string, string]),
  ];
  return (
    <div className="card"><div className="card-h"><h3>Related documents</h3></div>
      {rel.length ? rel.map(([rid, label]) => {
        const r = getDoc(s, rid);
        return r ? (
          <div key={rid} className="li"><span className={`pill plain ${label === "Related" ? "mute" : "info"}`}>{label}</span>
            <div className="main"><b>{r.title}</b><span className="mono">{r.ref}</span></div><Pill status={r.status} />
            <Link className="btn sm" href={`/library/${r.id}`}>Open</Link></div>
        ) : null;
      }) : <div className="empty">No linked documents yet.</div>}
    </div>
  );
}

function Access({ d, admin }: { d: Doc; admin: boolean }) {
  const s = useStore();
  const L = lists(s);
  const { save, toast } = useStore.getState();
  const setVis = (v: string) => { void save("documents", { ...d, visibility: v }); toast("Access changed to " + v); };
  return (
    <div className="grid2">
      <div className="card"><div className="card-h"><h3>Who can see this document</h3></div>
        <div className="card-b" style={{ display: "flex", flexDirection: "column", gap: 10 }}>
          {L.VIS.map((v) => (
            <label key={v} className="chk" style={{ borderRadius: 8, padding: "10px 12px", alignItems: "flex-start", width: "100%" }}>
              <input type="radio" name="acc" value={v} checked={d.visibility === v} disabled={!admin} onChange={() => setVis(v)} />
              <span><b style={{ fontWeight: 500 }}>{v}</b><br /><span className="xs muted" style={{ fontWeight: 400 }}>{L.VIS_DESC[v]}</span></span>
            </label>
          ))}
        </div>
      </div>
      <div className="card"><div className="card-h"><h3>How access works</h3></div>
        <div className="card-b" style={{ display: "flex", flexDirection: "column", gap: 10, fontSize: 13 }}>
          <p><b>Access is separate from subject tags.</b> Tags describe what a document is about. Access decides who may open it and who the AI can answer from.</p>
          <p>The assistant only reads documents the person asking is allowed to open.</p>
          <p className="muted">Current audience: {d.audience.join(", ")}. Audience is informational and does not grant access.</p>
        </div>
      </div>
    </div>
  );
}
