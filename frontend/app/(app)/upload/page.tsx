"use client";

import { useRef, useState } from "react";
import Link from "next/link";
import { api } from "@/lib/api";
import { lists, me, useStore } from "@/lib/store";
import { blockText, isHindi, nid, todayIso } from "@/lib/util";
import { Icon } from "@/components/icon";
import { Ft, Field } from "@/components/ui";
import type { Block, Doc, FileKind } from "@/lib/types";

type Meta = Partial<Pick<Doc, "title" | "ref" | "type" | "authority" | "dept" | "institution" | "date" | "effective" | "expiry" | "audience" | "tags" | "visibility" | "description">>;
type Item = { id: string; name: string; kind: FileKind; pages: Block[][]; ocr?: number | null; ocrEngine?: string | null; meta: Meta; status: "processing" | "ready" | "submitted"; docId?: string; errors: Record<string, string> };

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

  const update = (id: string, patch: Partial<Item>) => setQueue((q) => q.map((it) => (it.id === id ? { ...it, ...patch } : it)));
  const setMeta = (id: string, patch: Meta) => setQueue((q) => q.map((it) => (it.id === id ? { ...it, meta: { ...it.meta, ...patch }, errors: {} } : it)));

  async function addFiles(files: FileList) {
    for (const file of Array.from(files)) {
      const id = nid("q");
      const item: Item = { id, name: file.name, kind: "pdf", pages: [], meta: { institution: L.INSTS[0] }, status: "processing", errors: {} };
      setQueue((q) => [...q, item]); setSelId((cur) => cur ?? id);
      try {
        const res = await api.extract(file);
        update(id, { kind: res.kind, pages: res.pages, ocr: res.ocr, ocrEngine: res.ocr_engine, status: "ready", meta: { institution: L.INSTS[0], ...(res.suggestion as Meta) } });
      } catch (e) { toast((e as Error).message); setQueue((q) => q.filter((x) => x.id !== id)); }
    }
  }

  function submit(it: Item) {
    const errors: Record<string, string> = {};
    REQUIRED.forEach(([k, msg]) => { if (!it.meta[k]) errors[k] = msg; });
    if (!it.meta.audience?.length) errors.audience = "Choose at least one audience";
    if (!it.meta.tags?.length) errors.tags = "Choose at least one subject tag";
    if (Object.keys(errors).length) { update(it.id, { errors }); toast("Fill in the highlighted fields"); return; }
    const id = nid("D");
    const m = it.meta;
    const lang: "en" | "hi" = it.pages.some((p) => p.some((b) => isHindi(blockText(b.text)))) ? "hi" : "en";
    const doc: Doc = {
      id, title: m.title!, ref: m.ref!, type: m.type!, authority: m.authority!, dept: m.dept!, institution: m.institution || L.INSTS[0],
      date: m.date!, effective: m.effective || m.date!, expiry: m.expiry || "", audience: m.audience!, tags: m.tags!, visibility: m.visibility!,
      status: "Pending", fileType: it.kind, lang, description: m.description || "", uploadedBy: me(s).name, uploadedOn: todayIso(),
      related: [], revisionOf: null, supersededBy: null,
      versions: [{ v: "1.0", date: todayIso(), by: me(s).name, note: "Original upload" }],
      approvals: [{ step: "Submitted for approval", by: me(s).name, date: todayIso(), kind: "", note: "Uploaded from " + it.name }],
      pages: it.pages, ...(it.ocr != null ? { ocr: it.ocr } : {}),
    };
    void save("documents", doc);
    update(it.id, { status: "submitted", docId: id });
    toast("Submitted for approval");
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

  return (
    <div className="wrap">
      <div className="pagehead"><div><h2>Upload documents</h2><p>Add official letters, notices, circulars and policies. Files are read, tagged and sent for approval before the assistant can use them.</p></div>
        <Link className="btn" href="/review"><Icon n="shield" s /> Review queue</Link></div>

      <div className="upgrid">
        <div style={{ display: "flex", flexDirection: "column", gap: 14, minWidth: 0 }}>
          <div className={`drop ${over ? "over" : ""}`}
            onDragOver={(e) => { e.preventDefault(); setOver(true); }} onDragLeave={() => setOver(false)}
            onDrop={(e) => { e.preventDefault(); setOver(false); if (e.dataTransfer.files.length) addFiles(e.dataTransfer.files); }}>
            <div className="ic"><Icon n="upload" /></div><b>Drop files here</b>
            <span className="sm muted">PDF, scanned PDF, Word, Excel, images (JPG, PNG) and text files.</span>
            <button className="btn pri" type="button" onClick={() => fileRef.current?.click()}>Choose files</button>
            <input ref={fileRef} type="file" multiple hidden accept=".pdf,.doc,.docx,.xls,.xlsx,.csv,.png,.jpg,.jpeg,.webp,.txt,.md"
              onChange={(e) => { if (e.target.files) addFiles(e.target.files); e.target.value = ""; }} />
            <span className="xs muted">Scanned PDFs and photos are read with OCR. Text is extracted and the assistant searches it after approval.</span>
          </div>
          <div className="card"><div className="card-h"><h3>Upload queue</h3><span className="xs muted">{queue.filter((q) => q.status !== "processing").length} of {queue.length} ready</span></div>
            <div className="card-b" style={{ display: "flex", flexDirection: "column", gap: 8 }}>
              {queue.length ? queue.map((it) => (
                <button key={it.id} className={`qitem ${selId === it.id ? "on" : ""}`} onClick={() => setSelId(it.id)} type="button">
                  <Ft k={it.kind} /><div style={{ minWidth: 0 }}><div className="nm">{it.name}</div>
                    <div className="st">{it.status === "processing" ? <><span className="spin" /> Reading…</> : it.status === "submitted" ? <><span style={{ color: "var(--green)" }}><Icon n="check" s /></span> Submitted</> : "Ready · add details"}</div></div>
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
                {[["Add files", "Choose your own files. Each is read and (for scans) run through OCR."], ["Review the details", "The assistant suggests title, type, tags and dates. Check and edit them."], ["Submit for approval", "An approver checks the document before it appears in the library and AI answers."]].map(([a, b], i) => (
                  <div key={i} className="tl"><i /><div><b>{i + 1}. {a}</b><p>{b}</p></div></div>
                ))}
              </div>
            </div>
          ) : sel.status === "processing" ? (
            <div className="card card-b" style={{ display: "flex", flexDirection: "column", gap: 10, alignItems: "center", padding: 40 }}>
              <span className="spin" style={{ width: 26, height: 26 }} /><b>Reading {sel.name}</b><span className="sm muted">Extracting text{sel.kind === "scan" ? " with OCR" : ""}…</span></div>
          ) : sel.status === "submitted" ? (
            <div className="card card-b" style={{ display: "flex", flexDirection: "column", gap: 12 }}>
              <div className="note ok"><Icon n="check" s /><p><b>{sel.meta.title}</b> was submitted for approval.</p></div>
              <div className="row"><Link className="btn pri" href="/review">Open review queue</Link>{sel.docId && <Link className="btn" href={`/library/${sel.docId}`}>View document record</Link>}</div>
            </div>
          ) : (
            <form className="card" onSubmit={(e) => { e.preventDefault(); submit(sel); }} noValidate>
              <div className="card-h"><div style={{ minWidth: 0 }}><h3 style={{ whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{sel.name}</h3><span className="xs muted">{sel.kind.toUpperCase()}{sel.ocr != null && ` · OCR by ${sel.ocrEngine} · ${sel.ocr}% confidence`}</span></div></div>
              <div className="card-b" style={{ display: "flex", flexDirection: "column", gap: 16 }}>
                <div className="sec" style={{ border: 0, padding: 0 }}><h4>Extracted text (what the assistant will search)</h4>
                  <div className="prevbox"><pre>{sel.pages.flat().map((b) => blockText(b.text)).join("\n").slice(0, 1200) || "No text could be read from this file."}</pre></div></div>
                <div className="sec"><h4>Document details</h4>
                  {fld(sel, "title", "Document title", true)}
                  <div className="grid2">{fld(sel, "ref", "Reference / letter number", true)}{fld(sel, "type", "Document type", true)}{fld(sel, "authority", "Issuing authority", true)}{fld(sel, "dept", "Issuing department", true)}</div>
                  {fld(sel, "institution", "Institution / college")}
                  <div className="grid3">{fld(sel, "date", "Document date", true)}{fld(sel, "effective", "Effective date")}{fld(sel, "expiry", "Expiry date")}</div>
                  <Field label="Applicable audience" req error={sel.errors.audience}><div className="chips">{L.AUDS.map((a) => (
                    <label key={a} className="chk"><input type="checkbox" checked={sel.meta.audience?.includes(a) ?? false}
                      onChange={() => setMeta(sel.id, { audience: sel.meta.audience?.includes(a) ? sel.meta.audience.filter((x) => x !== a) : [...(sel.meta.audience ?? []), a] })} />{a}</label>
                  ))}</div></Field>
                </div>
                <div className="sec"><h4>Subject tags <small>What the document is about</small></h4>
                  <Field error={sel.errors.tags}><div className="chips">{L.TAGS.map((t) => (
                    <label key={t} className="chk"><input type="checkbox" checked={sel.meta.tags?.includes(t) ?? false}
                      onChange={() => setMeta(sel.id, { tags: sel.meta.tags?.includes(t) ? sel.meta.tags.filter((x) => x !== t) : [...(sel.meta.tags ?? []), t] })} />{t}</label>
                  ))}</div></Field></div>
                <div className="sec"><h4>Visibility and access <small>Who may open it</small></h4>
                  <Field error={sel.errors.visibility}><div className="grid2">{L.VIS.map((v) => (
                    <label key={v} className="chk" style={{ borderRadius: 8, padding: "9px 12px", alignItems: "flex-start" }}>
                      <input type="radio" name="uvis" checked={sel.meta.visibility === v} onChange={() => setMeta(sel.id, { visibility: v })} />
                      <span><b style={{ fontWeight: 500 }}>{v}</b><br /><span className="xs muted" style={{ fontWeight: 400 }}>{L.VIS_DESC[v]}</span></span></label>
                  ))}</div></Field></div>
                <Field label="Description or remarks"><textarea className="inp" rows={3} value={sel.meta.description || ""} onChange={(e) => setMeta(sel.id, { description: e.target.value })} /></Field>
              </div>
              <div className="mft" style={{ position: "static", borderTop: "1px solid var(--line)", display: "flex", justifyContent: "flex-end", gap: 8, padding: "12px 16px" }}>
                <button type="submit" className="btn pri">Submit for approval</button>
              </div>
            </form>
          )}
        </div>
      </div>
    </div>
  );
}
