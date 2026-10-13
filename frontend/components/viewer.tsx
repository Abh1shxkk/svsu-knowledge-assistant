"use client";

import { useEffect, useRef } from "react";
import Link from "next/link";
import { getDoc, useStore } from "@/lib/store";
import { fmtD, nid } from "@/lib/util";
import { Icon } from "./icon";
import { Pages } from "./paper";
import { Pill } from "./ui";

export function Viewer() {
  const v = useStore((s) => s.viewer);
  const doc = useStore((s) => (s.viewer ? getDoc(s, s.viewer.doc) : undefined));
  const { closeViewer, openViewer, save, toast } = useStore.getState();
  const bodyRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const mk = bodyRef.current?.querySelector("mark.hl, tr.hlb");
    if (mk && bodyRef.current) {
      const top = mk.getBoundingClientRect().top - bodyRef.current.getBoundingClientRect().top
        + bodyRef.current.scrollTop - bodyRef.current.clientHeight / 3;
      bodyRef.current.scrollTo({ top: Math.max(0, top), behavior: "smooth" });
      mk.classList.add("pulse");
    }
  }, [v?.doc, v?.block, v?.idx]);

  if (!v || !doc) return null;
  const cites = v.cites ?? [];
  const idx = v.idx ?? 0;
  const cur = cites[idx];
  const hl = v.block ? { page: v.page ?? 1, block: v.block, quote: v.quote } : null;

  const step = (d: number) => {
    const c = cites[idx + d];
    if (c) openViewer({ ...v, doc: c.doc, page: c.page, block: c.block, quote: c.quote, idx: idx + d });
  };
  const zoom = (d: number) => openViewer({ ...v, zoom: Math.min(1.6, Math.max(0.6, +(v.zoom + d).toFixed(1))) });
  const bookmark = () => {
    if (!v.block) return;
    save("bm_passages", { id: nid("bp"), doc: v.doc, page: v.page ?? 1, block: v.block, quote: v.quote ?? "", note: "", when: new Date().toLocaleDateString("en-IN") });
    toast("Passage bookmarked. Find it in Saved Chats & Bookmarks.");
  };

  return (
    <aside className="viewer" aria-label="Document viewer">
      <div className="vh">
        <div className="r1">
          <div className="t">
            <b lang={doc.lang}>{doc.title}</b>
            <span className="mono">{doc.ref}</span> <span>· {doc.authority} · {fmtD(doc.date)}</span>
          </div>
          <Pill status={doc.status} />
          <button className="iconbtn" aria-label="Close viewer" onClick={closeViewer} type="button"><Icon n="x" /></button>
        </div>
        {cur && (
          <div className="cstep">
            <button className="iconbtn" disabled={idx === 0} aria-label="Previous citation" onClick={() => step(-1)} type="button"><Icon n="cl" /></button>
            <div className="q"><b>Citation {idx + 1} of {cites.length}</b> · page {cur.page}<em lang={doc.lang}>{cur.quote}</em></div>
            <button className="iconbtn" disabled={idx === cites.length - 1} aria-label="Next citation" onClick={() => step(1)} type="button"><Icon n="cr" /></button>
          </div>
        )}
        <div className="vtools">
          <span className="pg">Page {v.page ?? 1} / {doc.pages.length}</span>
          <button className="btn sm" aria-label="Zoom out" onClick={() => zoom(-0.1)} type="button"><Icon n="zout" s /></button>
          <span className="pg">{Math.round(v.zoom * 100)}%</span>
          <button className="btn sm" aria-label="Zoom in" onClick={() => zoom(0.1)} type="button"><Icon n="zin" s /></button>
          <span style={{ flex: 1 }} />
          {hl && <button className="btn sm" onClick={bookmark} type="button"><Icon n="bm" s /> Bookmark passage</button>}
          <Link className="btn sm" href={`/library/${doc.id}`} onClick={closeViewer}><Icon n="open" s /> Details</Link>
        </div>
      </div>
      <div className="vbody" ref={bodyRef}><Pages doc={doc} hl={hl} zoom={v.zoom} /></div>
      <div className="vfoot">
        {hl ? <><i /><span>Highlighted text is the exact passage cited. Page {v.page}.</span></>
          : <span>Viewing full document. Click a citation in an answer to jump to a passage.</span>}
      </div>
    </aside>
  );
}
