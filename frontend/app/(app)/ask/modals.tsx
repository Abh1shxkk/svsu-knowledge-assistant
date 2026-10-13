"use client";

import { useState } from "react";
import { answerable, lists, scopeLabel, useStore } from "@/lib/store";

export function ScopeModal() {
  const s = useStore();
  const docs = answerable(s);
  const [mode, setMode] = useState(s.scope.mode);
  const [files, setFiles] = useState<string[]>(s.scope.files);
  const [coll, setColl] = useState(s.scope.coll ?? s.collections[0]?.id ?? null);
  const { set, closeModal, toast } = useStore.getState();

  const apply = () => {
    if (mode === "files" && !files.length) { toast("Select at least one file"); return; }
    set({ scope: { mode, files, coll } });
    closeModal();
    toast("Scope: " + scopeLabel(useStore.getState()));
  };

  return (
    <>
      <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
        <label className="chk" style={{ borderRadius: 8, padding: "10px 12px" }}>
          <input type="radio" name="mode" checked={mode === "all"} onChange={() => setMode("all")} />
          <span><b style={{ fontWeight: 500 }}>All permitted documents</b> <span className="xs muted">({docs.length})</span></span>
        </label>
        <label className="chk" style={{ borderRadius: 8, padding: "10px 12px" }}>
          <input type="radio" name="mode" checked={mode === "files"} onChange={() => setMode("files")} />
          <span><b style={{ fontWeight: 500 }}>Selected files</b></span>
        </label>
        {mode === "files" && (
          <div style={{ maxHeight: 220, overflow: "auto", border: "1px solid var(--line)", borderRadius: 8, padding: "6px 10px" }}>
            {docs.map((d) => (
              <label key={d.id} className="row sm" style={{ padding: "5px 0", flexWrap: "nowrap" }}>
                <input type="checkbox" checked={files.includes(d.id)}
                  onChange={(e) => setFiles((f) => e.target.checked ? [...f, d.id] : f.filter((x) => x !== d.id))} />
                <span style={{ minWidth: 0 }} lang={d.lang}>{d.title} <span className="mono muted">{d.ref}</span></span>
              </label>
            ))}
          </div>
        )}
        <label className="chk" style={{ borderRadius: 8, padding: "10px 12px" }}>
          <input type="radio" name="mode" checked={mode === "collection"} onChange={() => setMode("collection")} />
          <span><b style={{ fontWeight: 500 }}>A collection</b></span>
        </label>
        {mode === "collection" && (
          <select className="inp" value={coll ?? ""} onChange={(e) => setColl(e.target.value)} aria-label="Collection">
            {s.collections.map((c) => <option key={c.id} value={c.id}>{c.name} ({c.docs.length})</option>)}
          </select>
        )}
      </div>
      <div className="mft" style={{ position: "static", borderTop: "1px solid var(--line)", marginTop: 14, paddingTop: 12 }}>
        <button className="btn" onClick={closeModal} type="button">Cancel</button>
        <button className="btn pri" onClick={apply} type="button">Apply scope</button>
      </div>
    </>
  );
}

export function FiltersModal() {
  const s = useStore();
  const L = lists(s);
  const [f, setF] = useState(s.filters);
  const { set, closeModal, toast } = useStore.getState();
  const sel = (k: keyof typeof f, label: string, arr: string[]) => (
    <div className="fld"><label>{label}</label>
      <select className="inp" value={f[k]} onChange={(e) => setF({ ...f, [k]: e.target.value })}>
        <option value="">Any</option>{arr.map((v) => <option key={v}>{v}</option>)}
      </select></div>
  );
  return (
    <>
      <div className="grid2">
        {sel("dept", "Department", L.DEPTS)}
        {sel("subject", "Subject", L.TAGS)}
        {sel("type", "Document type", L.TYPES)}
        <div />
        <div className="fld"><label>Dated from</label><input type="date" className="inp" value={f.from} onChange={(e) => setF({ ...f, from: e.target.value })} /></div>
        <div className="fld"><label>Dated to</label><input type="date" className="inp" value={f.to} onChange={(e) => setF({ ...f, to: e.target.value })} /></div>
      </div>
      <button type="button" className="btn sm ghost" style={{ alignSelf: "flex-start", marginTop: 10 }}
        onClick={() => setF({ dept: "", subject: "", type: "", from: "", to: "" })}>Clear all filters</button>
      <div className="mft" style={{ position: "static", borderTop: "1px solid var(--line)", marginTop: 14, paddingTop: 12 }}>
        <button className="btn" onClick={closeModal} type="button">Cancel</button>
        <button className="btn pri" type="button" onClick={() => {
          set({ filters: f }); closeModal();
          const n = Object.values(f).filter(Boolean).length;
          toast(n ? `${n} filter(s) applied` : "No filters applied");
        }}>Apply filters</button>
      </div>
    </>
  );
}
