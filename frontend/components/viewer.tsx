"use client";

import { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { getDoc, useFullDoc, useStore } from "@/lib/store";
import { fmtD, nid, todayIso } from "@/lib/util";
import { Icon } from "./icon";
import { DownloadOriginal, OriginalFile } from "./original";
import { Pages } from "./paper";
import { Pill } from "./ui";

export function Viewer() {
  const v = useStore((s) => s.viewer);
  const doc = useFullDoc(v?.doc);
  const newer = useStore((s) => (doc?.supersededBy ? getDoc(s, doc.supersededBy) : undefined));
  const { closeViewer, openViewer, save, toast } = useStore.getState();
  const bodyRef = useRef<HTMLDivElement>(null);
  const [view, setView] = useState<"original" | "text">("original");  // the real file, or the text read from it
  const showOriginal = view === "original" && !!doc?.file;

  useEffect(() => {
    const mk = bodyRef.current?.querySelector("mark.hl, tr.hlb");
    if (mk && bodyRef.current) {
      const top = mk.getBoundingClientRect().top - bodyRef.current.getBoundingClientRect().top
        + bodyRef.current.scrollTop - bodyRef.current.clientHeight / 3;
      bodyRef.current.scrollTo({ top: Math.max(0, top), behavior: "smooth" });
      mk.classList.add("pulse");
    }
  }, [v?.doc, v?.block, v?.idx, doc, showOriginal]);

  if (!v || !doc) return null;
  const cites = v.cites ?? [];
  const idx = v.idx ?? 0;
  const cur = cites[idx];
  const hl = v.block ? { page: v.page ?? 1, block: v.block, quote: v.quote } : null;

  const step = (d: number) => {
    const c = cites[idx + d];
    if (c) openViewer({ ...v, doc: c.doc, page: c.page, block: c.block, quote: c.quote, idx: idx + d });
  };
  const pageCount = doc.pages?.length ?? 1;
  const goPage = (d: number) => {
    const page = Math.min(pageCount, Math.max(1, (v.page ?? 1) + d));
    openViewer({ ...v, page });
    bodyRef.current?.querySelector(`[data-page="${page}"]`)?.scrollIntoView({ behavior: "smooth", block: "start" });
  };
  const zoom = (d: number) => openViewer({ ...v, zoom: Math.min(1.6, Math.max(0.6, +(v.zoom + d).toFixed(1))) });
  const bookmark = async () => {
    if (!v.block) return;
    if (await save("bm_passages", { id: nid("bp"), doc: v.doc, page: v.page ?? 1, block: v.block, quote: v.quote ?? "", note: "", when: todayIso() }))
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
        {doc.status === "Superseded" && newer && (
          <div className="note warn" style={{ padding: "7px 10px" }}><Icon n="alert" s /><span className="sm">Superseded by{" "}
            <button className="link" onClick={() => openViewer({ doc: newer.id, page: 1 })} type="button">{newer.ref}</button>. Shown because it was cited as a historical or comparison source.</span></div>
        )}
        {doc.status === "Withdrawn" && <div className="note bad" style={{ padding: "7px 10px" }}><Icon n="ban" s /><span className="sm">This document has been withdrawn.</span></div>}
        {cur && (
          <div className="cstep">
            <button className="iconbtn" disabled={idx === 0} aria-label="Previous citation" onClick={() => step(-1)} type="button"><Icon n="cl" /></button>
            <div className="q"><b>Citation {idx + 1} of {cites.length}</b> · page {cur.page}<em lang={doc.lang}>{cur.quote}</em>
              {showOriginal && <button className="link xs" onClick={() => setView("text")} type="button">Show highlighted in text</button>}</div>
            <button className="iconbtn" disabled={idx === cites.length - 1} aria-label="Next citation" onClick={() => step(1)} type="button"><Icon n="cr" /></button>
          </div>
        )}
        <div className="vtools">
          {doc.file && (
            <div className="seg" role="tablist" aria-label="View">
              <button role="tab" aria-selected={showOriginal} className={showOriginal ? "on" : ""} onClick={() => setView("original")} type="button">Original</button>
              <button role="tab" aria-selected={!showOriginal} className={!showOriginal ? "on" : ""} onClick={() => setView("text")} type="button">Text</button>
            </div>
          )}
          {!showOriginal && <>
          <button className="btn sm" aria-label="Previous page" disabled={(v.page ?? 1) <= 1} onClick={() => goPage(-1)} type="button"><Icon n="cl" s /></button>
          <span className="pg">Page {v.page ?? 1} / {pageCount}</span>
          <button className="btn sm" aria-label="Next page" disabled={(v.page ?? 1) >= pageCount} onClick={() => goPage(1)} type="button"><Icon n="cr" s /></button>
          <button className="btn sm" aria-label="Zoom out" onClick={() => zoom(-0.1)} type="button"><Icon n="zout" s /></button>
          <span className="pg">{Math.round(v.zoom * 100)}%</span>
          <button className="btn sm" aria-label="Zoom in" onClick={() => zoom(0.1)} type="button"><Icon n="zin" s /></button>
          </>}
          <span style={{ flex: 1 }} />
          {showOriginal && <DownloadOriginal doc={doc} small />}
          {hl && <button className="btn sm" onClick={bookmark} type="button"><Icon n="bm" s /> Bookmark passage</button>}
          <Link className="btn sm" href={`/library/${doc.id}`} onClick={closeViewer}><Icon n="open" s /> Details</Link>
        </div>
      </div>
      <div className={`vbody ${showOriginal ? "orig-body" : ""}`} ref={bodyRef}>
        {showOriginal ? <OriginalFile doc={doc} page={v.page ?? 1} /> : <Pages doc={doc} hl={hl} zoom={v.zoom} />}
      </div>
      <div className="vfoot">
        {showOriginal ? <span>The original file as uploaded{hl ? `, at page ${v.page}. Use Text to see the cited passage highlighted.` : "."}</span>
          : hl ? <><i /><span>Highlighted text is the exact passage cited. Page {v.page}.</span></>
            : <span>The text read from the document{doc.fileType === "scan" ? " by OCR — check figures against the original" : ""}. Click a citation in an answer to jump to a passage.</span>}
      </div>
    </aside>
  );
}
