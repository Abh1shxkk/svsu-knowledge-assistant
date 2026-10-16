"use client";

import { useEffect, useRef, useState } from "react";
import { api } from "@/lib/api";
import type { Doc } from "@/lib/types";
import { Icon } from "./icon";

const isPdf = (d: Doc) => d.file?.mime === "application/pdf";
/** PDFs and photos can be shown as they are; for text, Word and Excel the text view is the document. */
export const previewable = (d: Doc) => isPdf(d) || !!d.file?.mime.startsWith("image/");
/** Pages in the original file (PDFs), or the pages of text read from it. */
export const originalPages = (d: Doc) => (isPdf(d) ? d.file?.pages ?? 1 : 1);

/** Loads a file the API serves (the request needs the sign-in token, so it can't be a plain link). */
function useBlob(load: () => Promise<Blob>, key: string) {
  const [got, setGot] = useState<{ key: string; href?: string; error?: string } | null>(null);
  useEffect(() => {
    let href = "", cancelled = false;
    load().then((blob) => { if (!cancelled) { href = URL.createObjectURL(blob); setGot({ key, href }); } })
      .catch((e) => { if (!cancelled) setGot({ key, error: (e as Error).message }); });
    return () => { cancelled = true; if (href) URL.revokeObjectURL(href); };
  }, [key]); // eslint-disable-line react-hooks/exhaustive-deps
  return got?.key === key ? got : null;
}

/** Boxes covering a quote on one page of the original, fetched once per page and quote. */
function useHighlight(docId: string, page: number, quote: string | undefined) {
  const key = quote ? `${docId}:${page}:${quote}` : "";
  const [got, setGot] = useState<{ key: string; rects: number[][] } | null>(null);
  useEffect(() => {
    if (!key) return;
    let cancelled = false;
    api.pageHighlight(docId, page, quote!).then(
      (r) => { if (!cancelled) setGot({ key, rects: r.rects }); },
      () => { if (!cancelled) setGot({ key, rects: [] }); });  // not found or failed: the page still shows
    return () => { cancelled = true; };
  }, [key]); // eslint-disable-line react-hooks/exhaustive-deps
  return got?.key === key ? got.rects : null;
}

function Picture({ load, k, alt, zoom = 1, rects }: {
  load: () => Promise<Blob>; k: string; alt: string; zoom?: number; rects?: number[][] | null;
}) {
  const got = useBlob(load, k);
  const first = useRef<HTMLSpanElement>(null);
  useEffect(() => {  // bring the highlighted passage into view once it is drawn
    first.current?.scrollIntoView({ block: "center", behavior: "smooth" });
  }, [rects, got?.href]);
  if (got?.error) return <div className="empty sm">{got.error}</div>;
  if (!got?.href) return <div className="empty orig-wait"><span className="spin" /></div>;
  return (
    <div className="orig-wrap" style={{ width: `${zoom * 100}%` }}>
      <img className="orig-img" src={got.href} alt={alt} />{/* eslint-disable-line @next/next/no-img-element */}
      {rects?.map(([x0, y0, x1, y1], i) => (
        <span key={i} ref={i === 0 ? first : undefined} className="orig-hl pulse" aria-hidden
          style={{ left: `${x0 * 100}%`, top: `${y0 * 100}%`, width: `${(x1 - x0) * 100}%`, height: `${(y1 - y0) * 100}%` }} />
      ))}
    </div>
  );
}

/** One page of the real document: PDF pages are drawn as pictures on the server, so every browser
 *  (phones included) shows them the same; photos as they are; Word and Excel as a download.
 *  With `quote`, the cited passage is highlighted on the page where it can be found there;
 *  `onFound` says whether it was (null while looking). */
export function OriginalFile({ doc, page = 1, zoom = 1, quote, onFound }: {
  doc: Doc; page?: number; zoom?: number; quote?: string; onFound?: (found: boolean | null) => void;
}) {
  const canShow = isPdf(doc) || !!doc.file?.mime.startsWith("image/");
  const rects = useHighlight(doc.id, page, canShow ? quote : undefined);
  useEffect(() => { onFound?.(quote ? (rects ? rects.length > 0 : null) : false); }, [rects, quote]); // eslint-disable-line react-hooks/exhaustive-deps
  if (isPdf(doc)) return <Picture load={() => api.originalPage(doc.id, page)} k={`${doc.id}:${doc.file!.key}:${page}`} alt={`Page ${page} of ${doc.title}`} zoom={zoom} rects={rects} />;
  if (doc.file?.mime.startsWith("image/")) return <Picture load={() => api.originalFile(doc.id)} k={`${doc.id}:${doc.file.key}`} alt={doc.title} zoom={zoom} rects={rects} />;
  return (
    <div className="empty" style={{ display: "flex", flexDirection: "column", gap: 10, alignItems: "center" }}>
      <p className="sm">Word and Excel files can&apos;t be shown in the browser. Download the original, or use the Text view.</p>
      <DownloadOriginal doc={doc} />
    </div>
  );
}

/** Every page, one under the other (document page preview). */
export function OriginalPages({ doc }: { doc: Doc }) {
  return <>{Array.from({ length: originalPages(doc) }, (_, i) => <OriginalFile key={i} doc={doc} page={i + 1} />)}</>;
}

export function DownloadOriginal({ doc, small }: { doc: Doc; small?: boolean }) {
  if (!doc.file) return null;
  const save = async () => {
    const blob = await api.originalFile(doc.id);
    const a = Object.assign(document.createElement("a"), { href: URL.createObjectURL(blob), download: doc.file?.name ?? "document" });
    a.click(); URL.revokeObjectURL(a.href);
  };
  return <button className={`btn ${small ? "sm" : ""}`} onClick={() => void save()} type="button"><Icon n="open" s /> Download original</button>;
}
