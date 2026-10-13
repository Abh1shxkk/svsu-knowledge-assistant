"use client";

import { useRef, useState } from "react";
import Link from "next/link";
import { api, type Extracted } from "@/lib/api";
import { canApprove, lists, me, useStore } from "@/lib/store";
import { blockText, isHindi, nid, todayIso } from "@/lib/util";
import { Icon } from "@/components/icon";
import { Ft, Field } from "@/components/ui";
import type { Block, Doc, FileKind } from "@/lib/types";

type Meta = Partial<Pick<Doc, "title" | "ref" | "type" | "authority" | "dept" | "institution" | "date" | "effective" | "expiry" | "audience" | "tags" | "visibility" | "description" | "related">>
  & { revRel?: "new" | "revision" | "supersedes"; revDoc?: string };
type Item = {
  id: string; name: string; kind: FileKind; pages: Block[][]; ocr?: number | null; ocrEngine?: string | null; meta: Meta;
  status: "processing" | "ready" | "submitted" | "draft"; docId?: string; errors: Record<string, string>; dup?: Extracted["duplicate"];
};

const REQUIRED: [keyof Meta, string][] = [
  ["title", "Enter the document title"], ["ref", "Enter the reference number"], ["type", "Choose a document type"],
  ["authority", "Choose the issuing authority"], ["dept", "Choose the department"], ["date", "Enter the document date"],
  ["visibility", "Choose who can see this"],
];

export default function UploadPage() {
  const s = useStore();
  const L = lists(s);
  const { save, toast } = useStore.getState();
  const [queue, setQueue] = useState<Item[]>([]);
  const [selId, setSelId] = useState<string | null>(null);
  const [over, setOver] = useState(false);
  const fileRef = useRef<HTMLInputElement>(null);
  const sel = queue.find((q) => q.id === selId);
  const active = s.documents.filter((d) => d.status === "Active");

  const update = (id: string, patch: Partial<Item>) => setQueue((q) => q.map((it) => (it.id === id ? { ...it, ...patch } : it)));
  const setMeta = (id: string, patch: Meta) => setQueue((q) => q.map((it) => (it.id === id ? { ...it, meta: { ...it.meta, ...patch }, errors: {} } : it)));

  async function addFiles(files: FileList) {
    for (const file of Array.from(files)) {
      const id = nid("q");
      const item: Item = { id, name: file.name, kind: "pdf", pages: [], meta: { institution: L.INSTS[0] }, status: "processing", errors: {} };
      setQueue((q) => [...q, item]); setSelId((cur) => cur ?? id);
      try {
        const res = await api.extract(file);
        update(id, { kind: res.kind, pages: res.pages, ocr: res.ocr, ocrEngine: res.ocr_engine, status: "ready", dup: res.duplicate, meta: { institution: L.INSTS[0], ...(res.suggestion as Meta) } });
      } catch (e) { toast((e as Error).message); setQueue((q) => q.filter((x) => x.id !== id)); }
    }
  }

  /** Submit for approval, or save as a draft (only the title is needed) to finish later. */
  async function submit(it: Item, draft = false) {
    const m = it.meta;
    const errors: Record<string, string> = {};
    if (draft) { if (!m.title?.trim()) errors.title = "Add a title to save a draft"; }
    else {
      REQUIRED.forEach(([k, msg]) => { if (!m[k]) errors[k] = msg; });
      if (!m.audience?.length) errors.audience = "Choose at least one audience";
      if (!m.tags?.length) errors.tags = "Choose at least one subject tag";
      if (m.revRel && m.revRel !== "new" && !m.revDoc) errors.revDoc = "Choose the document this revises";
      if (m.expiry && m.effective && m.expiry < m.effective) errors.expiry = "Expiry date must be after the effective date";
    }
    if (Object.keys(errors).length) { update(it.id, { errors }); toast("Fill in the highlighted fields"); return; }
    const id = it.docId ?? nid("D");
    const by = me(s).name;
    const doc: Doc = {
      id, title: m.title!.trim(), ref: m.ref ?? "", type: m.type ?? "", authority: m.authority ?? "", dept: m.dept ?? "", institution: m.institution || L.INSTS[0],
      date: m.date ?? "", effective: m.effective || m.date || "", expiry: m.expiry || "", audience: m.audience ?? [], tags: m.tags ?? [],
      visibility: m.visibility || L.VIS[L.VIS.length - 1],  // a draft with no access chosen stays at the most restricted level
      status: draft ? "Draft" : "Pending", fileType: it.kind, description: m.description || "", uploadedBy: by, uploadedOn: todayIso(),
      lang: it.pages.some((p) => p.some((b) => isHindi(blockText(b.text)))) ? "hi" : "en",
      related: m.related ?? [], revisionOf: m.revRel && m.revRel !== "new" ? m.revDoc ?? null : null, supersededBy: null,
      versions: [{ v: "1.0", date: todayIso(), by, note: "Original upload" }],
      approvals: [{ step: draft ? "Saved as draft" : "Submitted for approval", by, date: todayIso(), kind: "", note: "Uploaded from " + it.name }],
      pages: it.pages, ...(it.ocr != null ? { ocr: it.ocr } : {}),
    };
    if (!await save("documents", doc)) return;
    update(it.id, { status: draft ? "draft" : "submitted", docId: id });
    toast(draft ? "Draft saved. You can finish it later from the document record." : "Submitted for approval");
  }

  const fld = (it: Item, k: keyof Meta, label: string, req?: boolean) => (
    <Field label={label} req={req} error={it.errors[k]} htmlFor={`u-${k}`}>
      {k === "type" || k === "authority" || k === "dept" || k === "visibility" || k === "institution" ? (
        <select id={`u-${k}`} className={`inp ${it.errors[k] ? "err" : ""}`} value={(it.meta[k] as string) || ""} onChange={(e) => setMeta(it.id, { [k]: e.target.value } as Meta)}>
          <option value="">Select…</option>{(k === "type" ? L.TYPES : k === "authority" ? L.AUTHS : k === "dept" ? L.DEPTS : k === "visibility" ? L.VIS : L.INSTS).map((x) => <option key={x}>{x}</option>)}
        </select>
      ) : (
        <input id={`u-${k}`} className={`inp ${it.errors[k] ? "err" : ""}`} type={k.includes("date") || k === "effective" || k === "expiry" ? "date" : "text"}
          value={(it.meta[k] as string) || ""} onChange={(e) => setMeta(it.id, { [k]: e.target.value } as Meta)} />
      )}
    </Field>
  );
  const toggle = (it: Item, k: "audience" | "tags" | "related", v: string) =>
    setMeta(it.id, { [k]: it.meta[k]?.includes(v) ? it.meta[k]!.filter((x) => x !== v) : [...(it.meta[k] ?? []), v] });

  return (
    <div className="wrap">
      <div className="pagehead"><div><h2>Upload documents</h2><p>Add official letters, notices, circulars and policies. Files are read, tagged and sent for approval before the assistant can use them.</p></div>
        {canApprove(s) && <Link className="btn" href="/review"><Icon n="shield" s /> Review queue</Link>}</div>

      <div className="upgrid">
        <div style={{ display: "flex", flexDirection: "column", gap: 14, minWidth: 0 }}>
          <div className={`drop ${over ? "over" : ""}`}
            onDragOver={(e) => { e.preventDefault(); setOver(true); }} onDragLeave={() => setOver(false)}
            onDrop={(e) => { e.preventDefault(); setOver(false); if (e.dataTransfer.files.length) addFiles(e.dataTransfer.files); }}>
            <div className="ic"><Icon n="upload" /></div><b>Drop files here</b>
            <span className="sm muted">PDF, scanned PDF, Word (.docx), Excel (.xlsx), CSV, images (JPG, PNG) and text files. Save older .doc and .xls files in the newer format first.</span>
            <button className="btn pri" type="button" onClick={() => fileRef.current?.click()}>Choose files</button>
            <input ref={fileRef} type="file" multiple hidden accept=".pdf,.docx,.xlsx,.csv,.png,.jpg,.jpeg,.webp,.txt,.md"
              onChange={(e) => { if (e.target.files) addFiles(e.target.files); e.target.value = ""; }} />
            <span className="xs muted">Scanned PDFs and photos are read with OCR. Text is extracted and the assistant searches it after approval.</span>
          </div>
          <div className="card"><div className="card-h"><h3>Upload queue</h3><span className="xs muted">{queue.filter((q) => q.status !== "processing").length} of {queue.length} ready</span></div>
            <div className="card-b" style={{ display: "flex", flexDirection: "column", gap: 8 }}>
              {queue.length ? queue.map((it) => (
                <button key={it.id} className={`qitem ${selId === it.id ? "on" : ""}`} onClick={() => setSelId(it.id)} type="button">
                  <Ft k={it.kind} /><div style={{ minWidth: 0 }}><div className="nm">{it.name}</div>
                    <div className="st">{it.status === "processing" ? <><span className="spin" /> Reading…</>
                      : it.status === "submitted" ? <><span style={{ color: "var(--green)" }}><Icon n="check" s /></span> Submitted</>
                        : it.status === "draft" ? "Draft saved" : it.dup ? "Possible duplicate · needs details" : "Ready · add details"}</div></div>
                  <span className="iconbtn" role="button" aria-label="Remove" onClick={(e) => { e.stopPropagation(); setQueue((q) => q.filter((x) => x.id !== it.id)); }}><Icon n="x" s /></span>
                </button>
              )) : <p className="sm muted">No files yet. Choose files to begin.</p>}
            </div>
          </div>
        </div>

        <div style={{ minWidth: 0 }}>
          {!sel ? (
            <div className="card card-b"><h3 style={{ fontSize: 15 }}>How uploading works</h3>
              <div className="timeline" style={{ padding: 0, marginTop: 10 }}>
                {[["Add files", "Choose your own files. Each is read and (for scans) run through OCR."], ["Automatic checks", "Details and tags are suggested, and duplicates of existing documents are flagged."], ["Review the details", "Check and edit the suggestions. Save a draft to finish later."], ["Submit for approval", "An approver checks the document before it appears in the library and AI answers."]].map(([a, b], i) => (
                  <div key={i} className="tl"><i /><div><b>{i + 1}. {a}</b><p>{b}</p></div></div>
                ))}
              </div>
            </div>
          ) : sel.status === "processing" ? (
            <div className="card card-b" style={{ display: "flex", flexDirection: "column", gap: 10, alignItems: "center", padding: 40 }}>
              <span className="spin" style={{ width: 26, height: 26 }} /><b>Reading {sel.name}</b><span className="sm muted">Extracting text, suggesting details and checking for duplicates…</span></div>
          ) : sel.status === "submitted" || sel.status === "draft" ? (
            <div className="card card-b" style={{ display: "flex", flexDirection: "column", gap: 12 }}>
              <div className="note ok"><Icon n="check" s /><p><b>{sel.meta.title}</b> {sel.status === "draft" ? "was saved as a draft." : "was submitted for approval."}</p></div>
              <p className="sm muted">{sel.status === "draft" ? "Only you and approvers can see it. Open the record to finish the details and submit it." : "It will appear in the library and AI answers once an approver publishes it."}</p>
              <div className="row">
                {canApprove(s) && sel.status === "submitted" && <Link className="btn pri" href="/review">Open review queue</Link>}
                {sel.docId && <Link className="btn" href={`/library/${sel.docId}`}>View document record</Link>}
              </div>
            </div>
          ) : (
            <form className="card" onSubmit={(e) => { e.preventDefault(); void submit(sel); }} noValidate>
              <div className="card-h"><div style={{ minWidth: 0 }}><h3 style={{ whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{sel.name}</h3><span className="xs muted">{sel.kind.toUpperCase()}{sel.ocr != null && ` · OCR by ${sel.ocrEngine} · ${sel.ocr}% confidence`}</span></div></div>
              <div className="card-b" style={{ display: "flex", flexDirection: "column", gap: 16 }}>
                {sel.dup && (
                  <div className="note warn"><Icon n="alert" s /><div><b>This may be a duplicate.</b>
                    <p className="sm">It matches <b>{sel.dup.title}</b> ({sel.dup.ref}), already {sel.dup.status.toLowerCase()}.</p>
                    <div className="row" style={{ marginTop: 8 }}>
                      <Link className="btn sm" href={`/library/${sel.dup.id}`}>View existing</Link>
                      <button type="button" className="btn sm" onClick={() => { setMeta(sel.id, { revRel: "revision", revDoc: sel.dup!.id }); update(sel.id, { dup: null }); toast("Set as a revision of the existing document"); }}>Upload as a new revision</button>
                      <button type="button" className="btn sm ghost" onClick={() => update(sel.id, { dup: null })}>It&apos;s a different document</button>
                    </div></div></div>
                )}
                <div className="sec" style={{ border: 0, padding: 0 }}><h4>Extracted text (what the assistant will search)</h4>
                  <div className="prevbox"><pre>{sel.pages.flat().map((b) => blockText(b.text)).join("\n").slice(0, 1200) || "No text could be read from this file."}</pre></div></div>
                <div className="sec"><h4>Document details</h4>
                  {fld(sel, "title", "Document title", true)}
                  <div className="grid2">{fld(sel, "ref", "Reference / letter number", true)}{fld(sel, "type", "Document type", true)}{fld(sel, "authority", "Issuing authority", true)}{fld(sel, "dept", "Issuing department", true)}</div>
                  {fld(sel, "institution", "Institution / college")}
                  <div className="grid3">{fld(sel, "date", "Document date", true)}{fld(sel, "effective", "Effective date")}{fld(sel, "expiry", "Expiry date")}</div>
                  <Field label="Applicable audience" req error={sel.errors.audience}><div className="chips">{L.AUDS.map((a) => (
                    <label key={a} className="chk"><input type="checkbox" checked={sel.meta.audience?.includes(a) ?? false} onChange={() => toggle(sel, "audience", a)} />{a}</label>
                  ))}</div></Field>
                </div>
                <div className="sec"><h4>Subject tags <small>What the document is about</small></h4>
                  <Field error={sel.errors.tags}><div className="chips">{L.TAGS.map((t) => (
                    <label key={t} className="chk"><input type="checkbox" checked={sel.meta.tags?.includes(t) ?? false} onChange={() => toggle(sel, "tags", t)} />{t}</label>
                  ))}</div></Field></div>
                <div className="sec"><h4>Visibility and access <small>Who may open it</small></h4>
                  <Field error={sel.errors.visibility}><div className="grid2">{L.VIS.map((v) => (
                    <label key={v} className="chk" style={{ borderRadius: 8, padding: "9px 12px", alignItems: "flex-start" }}>
                      <input type="radio" name="uvis" checked={sel.meta.visibility === v} onChange={() => setMeta(sel.id, { visibility: v })} />
                      <span><b style={{ fontWeight: 500 }}>{v}</b><br /><span className="xs muted" style={{ fontWeight: 400 }}>{L.VIS_DESC[v]}</span></span></label>
                  ))}</div></Field></div>
                <div className="sec"><h4>Relationships</h4>
                  <div className="grid2">
                    <Field label="Revision relationship" htmlFor="u-revRel"><select className="inp" id="u-revRel" value={sel.meta.revRel ?? "new"} onChange={(e) => setMeta(sel.id, { revRel: e.target.value as Meta["revRel"] })}>
                      <option value="new">New document</option><option value="revision">Revision of an existing document</option><option value="supersedes">Supersedes an existing document</option></select></Field>
                    {sel.meta.revRel && sel.meta.revRel !== "new" ? (
                      <Field label="Which document?" req error={sel.errors.revDoc} hint="The older document will be marked superseded on approval" htmlFor="u-revDoc">
                        <select className={`inp ${sel.errors.revDoc ? "err" : ""}`} id="u-revDoc" value={sel.meta.revDoc ?? ""} onChange={(e) => setMeta(sel.id, { revDoc: e.target.value })}>
                          <option value="">Select…</option>{active.map((d) => <option key={d.id} value={d.id}>{d.ref} — {d.title}</option>)}</select></Field>
                    ) : <div />}
                  </div>
                  {active.length > 0 && <Field label="Related documents" hint="Optional.">
                    <div style={{ maxHeight: 140, overflow: "auto", border: "1px solid var(--line)", borderRadius: 8, padding: "6px 10px" }}>
                      {active.map((d) => (
                        <label key={d.id} className="row sm" style={{ padding: "3px 0", flexWrap: "nowrap" }}>
                          <input type="checkbox" checked={sel.meta.related?.includes(d.id) ?? false} onChange={() => toggle(sel, "related", d.id)} />
                          <span lang={d.lang}>{d.ref} — {d.title}</span></label>
                      ))}</div></Field>}
                </div>
                <Field label="Description or remarks"><textarea className="inp" rows={3} value={sel.meta.description || ""} onChange={(e) => setMeta(sel.id, { description: e.target.value })} /></Field>
              </div>
              <div className="mft" style={{ position: "static", borderTop: "1px solid var(--line)", display: "flex", justifyContent: "space-between", gap: 8, padding: "12px 16px", flexWrap: "wrap" }}>
                <span className="xs muted" style={{ alignSelf: "center" }}>Fields marked * are required to submit.</span>
                <div className="row">
                  <button type="button" className="btn" onClick={() => void submit(sel, true)}><Icon n="save" s /> Save draft</button>
                  <button type="submit" className="btn pri">Submit for approval</button>
                </div>
              </div>
            </form>
          )}
        </div>
      </div>
    </div>
  );
}
