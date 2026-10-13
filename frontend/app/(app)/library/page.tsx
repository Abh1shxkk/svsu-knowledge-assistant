"use client";

import { Suspense, useState } from "react";
import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { canUpload, lists, permitted, useStore } from "@/lib/store";
import { docText } from "@/components/paper";
import { fmtD, plural } from "@/lib/util";
import { Icon } from "@/components/icon";
import { Ft, Pill, Tags } from "@/components/ui";
import type { Doc } from "@/lib/types";

type Lib = {
  q: string; subject: string; dept: string; aud: string; type: string; status: string;
  vis: string; from: string; to: string; sort: "new" | "old" | "eff" | "title"; view: "list" | "grid"; showFilters: boolean;
};
const BLANK: Lib = { q: "", subject: "", dept: "", aud: "", type: "", status: "", vis: "", from: "", to: "", sort: "new", view: "list", showFilters: true };

export default function LibraryPage() {
  return <Suspense><Library /></Suspense>;
}

function Library() {
  const s = useStore();
  const L2 = lists(s);
  const params = useSearchParams();
  // Seed search/status from the link once (e.g. a dashboard KPI or the top-bar search).
  const [L, setL] = useState<Lib>(() => ({ ...BLANK, q: params.get("q") ?? "", status: params.get("status") ?? "" }));

  let ds = permitted(s);
  const q = L.q.trim().toLowerCase();
  if (q) ds = ds.filter((d) => (d.title + " " + d.ref + " " + d.description + " " + d.tags.join(" ") + " " + d.dept + " " + docText(d)).toLowerCase().includes(q));
  if (L.subject) ds = ds.filter((d) => d.tags.includes(L.subject));
  if (L.dept) ds = ds.filter((d) => d.dept === L.dept);
  if (L.aud) ds = ds.filter((d) => d.audience.includes(L.aud));
  if (L.type) ds = ds.filter((d) => d.type === L.type);
  if (L.status) ds = ds.filter((d) => L.status === "Superseded" ? ["Superseded", "Withdrawn"].includes(d.status) : d.status === L.status);
  if (L.vis) ds = ds.filter((d) => d.visibility === L.vis);
  if (L.from) ds = ds.filter((d) => d.date >= L.from);
  if (L.to) ds = ds.filter((d) => d.date <= L.to);
  const sorters: Record<Lib["sort"], (a: Doc, b: Doc) => number> = {
    new: (a, b) => b.date.localeCompare(a.date), old: (a, b) => a.date.localeCompare(b.date),
    title: (a, b) => a.title.localeCompare(b.title), eff: (a, b) => (b.effective || "").localeCompare(a.effective || ""),
  };
  ds = [...ds].sort(sorters[L.sort]);

  const set = (patch: Partial<Lib>) => setL((p) => ({ ...p, ...patch }));
  const sel = (k: keyof Lib, label: string, arr: string[]) => (
    <div className="fld"><label>{label}</label>
      <select className="inp" value={L[k] as string} onChange={(e) => set({ [k]: e.target.value } as Partial<Lib>)}>
        <option value="">Any</option>{arr.map((v) => <option key={v}>{v}</option>)}</select></div>
  );

  return (
    <div className="wrap">
      <div className="pagehead">
        <div><h2>Document Library</h2><p>Every official letter, notice, circular and policy you are permitted to see. Superseded and withdrawn records stay here as history.</p></div>
        {canUpload(s) && <Link className="btn pri" href="/upload"><Icon n="upload" s /> Upload</Link>}
      </div>

      <div className="libbar">
        <div className="search"><Icon n="search" s /><input className="inp" placeholder="Search title, reference number or text inside documents" value={L.q} onChange={(e) => set({ q: e.target.value })} /></div>
        <select className="inp" style={{ width: "auto" }} value={L.sort} onChange={(e) => set({ sort: e.target.value as Lib["sort"] })} aria-label="Sort">
          <option value="new">Newest first</option><option value="old">Oldest first</option><option value="eff">Effective date</option><option value="title">Title A–Z</option></select>
        <button className="btn" onClick={() => set({ showFilters: !L.showFilters })} type="button"><Icon n="filter" s /> Filters</button>
        <div className="seg">
          <button className={L.view === "list" ? "on" : ""} aria-label="List view" onClick={() => set({ view: "list" })} type="button"><Icon n="list" s /></button>
          <button className={L.view === "grid" ? "on" : ""} aria-label="Grid view" onClick={() => set({ view: "grid" })} type="button"><Icon n="grid" s /></button>
        </div>
      </div>

      {L.showFilters && (
        <div className="card card-b">
          <div className="filters">
            {sel("subject", "Subject", L2.TAGS)}{sel("dept", "Department", L2.DEPTS)}{sel("aud", "Audience", L2.AUDS)}{sel("type", "Document type", L2.TYPES)}
            <div className="fld"><label>Status</label><select className="inp" value={L.status} onChange={(e) => set({ status: e.target.value })}>
              <option value="">Any</option>{["Active", "Pending", "Superseded", "Withdrawn", "Expired"].map((v) => <option key={v}>{v}</option>)}</select></div>
            {sel("vis", "Visibility", L2.VIS)}
            <div className="fld"><label>Dated from</label><input type="date" className="inp" value={L.from} onChange={(e) => set({ from: e.target.value })} /></div>
            <div className="fld"><label>Dated to</label><input type="date" className="inp" value={L.to} onChange={(e) => set({ to: e.target.value })} /></div>
          </div>
          <div className="row between" style={{ marginTop: 12 }}>
            <span className="sm muted">{plural(ds.length, "document")}</span>
            <button className="btn ghost sm" onClick={() => setL(BLANK)} type="button">Clear filters</button>
          </div>
        </div>
      )}

      {!ds.length ? (
        <div className="card empty"><p><b>No documents match these filters.</b></p>
          <p className="sm" style={{ marginTop: 4 }}>Try removing a filter or searching for a reference number.</p>
          <button className="btn sm" style={{ marginTop: 10 }} onClick={() => setL(BLANK)} type="button">Clear all filters</button></div>
      ) : L.view === "grid" ? (
        <div className="dgrid-cards">
          {ds.map((d) => (
            <Link key={d.id} className="dcard" href={`/library/${d.id}`}>
              <div className="thumb"><div className="mini">{[40, 100, 85, 92, 70, 88].map((w, i) => <i key={i} style={{ width: `${w}%`, height: i === 0 ? 6 : undefined }} />)}</div><Ft k={d.fileType} /></div>
              <div className="body"><div className="row between"><Pill status={d.status} /><span className="xs muted num">{fmtD(d.date)}</span></div>
                <b>{d.title}</b><span className="mono muted">{d.ref}</span><Tags tags={d.tags} /></div>
            </Link>
          ))}
        </div>
      ) : (
        <div className="card">
          <div className="dhead"><span /><span>Document</span><span className="c3">Department · Audience</span><span className="c4">Date</span><span>Status</span></div>
          {ds.map((d) => (
            <Link key={d.id} className="drow" href={`/library/${d.id}`}>
              <Ft k={d.fileType} />
              <div className="tt" style={{ minWidth: 0 }}><b>{d.title}</b><span className="mono">{d.ref}</span> <span>· {d.type}</span><div style={{ marginTop: 5 }}><Tags tags={d.tags} /></div></div>
              <div className="c3 sm" style={{ minWidth: 0 }}><div>{d.dept}</div><div className="muted xs">{d.audience.join(", ")}</div></div>
              <div className="c4 sm num">{fmtD(d.date)}<div className="xs muted">{d.visibility}</div></div>
              <div><Pill status={d.status} /></div>
            </Link>
          ))}
        </div>
      )}
    </div>
  );
}
