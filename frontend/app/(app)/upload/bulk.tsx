"use client";

import { useEffect, useRef, useState } from "react";
import { api, type ImportBatch } from "@/lib/api";
import { canApprove, lists, useStore } from "@/lib/store";
import { Icon } from "@/components/icon";
import { Field } from "@/components/ui";

const SUPPORTED = /\.(pdf|docx|xlsx|csv|png|jpe?g|webp|txt|md)$/i;

/** Many files at once: each is sent to the server and processed in the background (read, OCR,
 *  details suggested, indexed). The page can be closed while that runs; progress is shown here. */
export function BulkImport() {
  const s = useStore();
  const L = lists(s);
  const approver = canApprove(s);
  const [opts, setOpts] = useState({ visibility: L.VIS[1] ?? L.VIS[0] ?? "", dept: "", publish: false });
  const [sending, setSending] = useState<{ done: number; total: number; skipped: number; errors: number } | null>(null);
  const [batches, setBatches] = useState<ImportBatch[]>([]);
  const folderRef = useRef<HTMLInputElement>(null);
  const filesRef = useRef<HTMLInputElement>(null);

  useEffect(() => { folderRef.current?.setAttribute("webkitdirectory", ""); }, []);
  const busy = batches.some((b) => b.counts.queued || b.counts.running) || !!sending;
  useEffect(() => {  // refresh progress every few seconds while anything is being processed
    let stop = false;
    const tick = () => api.imports().then((b) => { if (!stop) setBatches(b); }).catch(() => {});
    tick();
    const t = setInterval(tick, busy ? 4000 : 20000);
    return () => { stop = true; clearInterval(t); };
  }, [busy]);

  async function start(list: FileList | null) {
    const files = Array.from(list ?? []).filter((f) => SUPPORTED.test(f.name));
    const skipped = (list?.length ?? 0) - files.length;
    if (!files.length) { s.toast(skipped ? "None of these files can be read (use PDF, Word, Excel, images or text)" : "No files chosen"); return; }
    const batch = "b" + Date.now().toString(36);
    const state = { done: 0, total: files.length, skipped, errors: 0 };
    setSending({ ...state });
    for (const f of files) {  // one at a time, so a slow connection or a big folder doesn't overload the server
      try { await api.importFile(f, batch, opts); } catch { state.errors++; }
      state.done++;
      setSending({ ...state });
    }
    setSending(null);
    s.toast(`${files.length - state.errors} file(s) queued${state.errors ? `, ${state.errors} couldn't be sent` : ""}`);
    setBatches(await api.imports());
  }

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 14 }}>
      <div className="card card-b" style={{ display: "flex", flexDirection: "column", gap: 14 }}>
        <div><h3 style={{ fontSize: 15 }}>Bulk import</h3>
          <p className="sm muted">Choose a whole folder or many files. Each file is read (OCR for scans), described by the assistant and indexed in the background — you can close this page. Details can be checked and corrected afterwards.</p></div>
        <div className="grid3">
          <Field label="Who can see them" htmlFor="bi-vis"><select className="inp" id="bi-vis" value={opts.visibility} onChange={(e) => setOpts({ ...opts, visibility: e.target.value })}>
            {L.VIS.map((v) => <option key={v}>{v}</option>)}</select></Field>
          <Field label="Department" hint="Leave as suggested to let the assistant pick per file" htmlFor="bi-dept"><select className="inp" id="bi-dept" value={opts.dept} onChange={(e) => setOpts({ ...opts, dept: e.target.value })}>
            <option value="">As suggested</option>{L.DEPTS.map((d) => <option key={d}>{d}</option>)}</select></Field>
          <Field label="After reading">
            <select className="inp" value={opts.publish ? "publish" : "review"} onChange={(e) => setOpts({ ...opts, publish: e.target.value === "publish" })} disabled={!approver} aria-label="After reading">
              <option value="review">Send to Review &amp; Approvals</option>{approver && <option value="publish">Publish straight away</option>}</select></Field>
        </div>
        {opts.publish && <div className="note warn"><Icon n="alert" s /><p className="sm">Published files are used in answers immediately, with the assistant&apos;s suggested details. Check a few afterwards.</p></div>}
        <div className="row">
          <button className="btn pri" type="button" disabled={!!sending} onClick={() => folderRef.current?.click()}><Icon n="layers" s /> Choose a folder</button>
          <button className="btn" type="button" disabled={!!sending} onClick={() => filesRef.current?.click()}><Icon n="upload" s /> Choose files</button>
          <input ref={folderRef} type="file" multiple hidden onChange={(e) => { void start(e.target.files); e.target.value = ""; }} />
          <input ref={filesRef} type="file" multiple hidden accept=".pdf,.docx,.xlsx,.csv,.png,.jpg,.jpeg,.webp,.txt,.md" onChange={(e) => { void start(e.target.files); e.target.value = ""; }} />
        </div>
        {sending && (
          <div><div className="row between sm"><span>Sending {sending.done} of {sending.total}…</span>{sending.skipped > 0 && <span className="muted">{sending.skipped} unsupported file(s) skipped</span>}</div>
            <div className="bar-track"><i style={{ width: `${(100 * sending.done) / sending.total}%` }} /></div>
            <p className="xs muted">Keep this page open until sending finishes; processing then continues on the server.</p></div>
        )}
      </div>

      {batches.length > 0 && (
        <div className="card"><div className="card-h"><h3>Imports</h3><span className="xs muted">{busy ? "Processing… refreshes automatically" : "All finished"}</span></div>
          {batches.map((b) => {
            const c = b.counts, total = Object.values(c).reduce((a, n) => a + (n ?? 0), 0);
            const finished = (c.done ?? 0) + (c.duplicate ?? 0) + (c.failed ?? 0);
            return (
              <div key={b.batch} className="li" style={{ flexDirection: "column", alignItems: "stretch", gap: 8 }}>
                <div className="row between"><b className="sm">{total} file{total === 1 ? "" : "s"} · {b.publish ? "published" : "sent to review"}{b.by && <span className="muted"> · by {b.by}</span>}</b>
                  <span className="xs muted">{b.updated ? new Date(b.updated).toLocaleString("en-IN", { dateStyle: "medium", timeStyle: "short" }) : ""}</span></div>
                <div className="bar-track"><i style={{ width: `${(100 * finished) / Math.max(total, 1)}%` }} /></div>
                <div className="row xs">
                  {c.done ? <span className="pill ok">{c.done} imported</span> : null}
                  {c.running || c.queued ? <span className="pill info">{(c.running ?? 0) + (c.queued ?? 0)} waiting</span> : null}
                  {c.duplicate ? <span className="pill mute">{c.duplicate} already in the library</span> : null}
                  {c.failed ? <span className="pill bad">{c.failed} failed</span> : null}
                  {c.failed ? <button className="btn sm" type="button" onClick={async () => { const r = await api.retryImport(b.batch); s.toast(`${r.requeued} file(s) will be tried again`); setBatches(await api.imports()); }}>Retry failed</button> : null}
                </div>
                {b.failed.length > 0 && (
                  <details className="xs"><summary>Why files failed</summary>
                    <ul className="faillist">{b.failed.slice(0, 50).map((f, i) => <li key={i}><b>{f.name}</b> — {f.error}</li>)}</ul></details>
                )}
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
