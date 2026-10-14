"use client";

import { useEffect, useState } from "react";
import { api } from "@/lib/api";
import type { Doc } from "@/lib/types";
import { Icon } from "./icon";

const isPdf = (d: Doc) => d.file?.mime === "application/pdf";
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

function Picture({ load, k, alt, zoom = 1 }: { load: () => Promise<Blob>; k: string; alt: string; zoom?: number }) {
  const got = useBlob(load, k);
  if (got?.error) return <div className="empty sm">{got.error}</div>;
  if (!got?.href) return <div className="empty orig-wait"><span className="spin" /></div>;
  return <img className="orig-img" src={got.href} alt={alt} style={{ width: `${zoom * 100}%` }} />;  // eslint-disable-line @next/next/no-img-element
}

/** One page of the real document: PDF pages are drawn as pictures on the server, so every browser
 *  (phones included) shows them the same; photos as they are; Word and Excel as a download. */
export function OriginalFile({ doc, page = 1, zoom = 1 }: { doc: Doc; page?: number; zoom?: number }) {
  if (isPdf(doc)) return <Picture load={() => api.originalPage(doc.id, page)} k={`${doc.id}:${doc.file!.key}:${page}`} alt={`Page ${page} of ${doc.title}`} zoom={zoom} />;
  if (doc.file?.mime.startsWith("image/")) return <Picture load={() => api.originalFile(doc.id)} k={`${doc.id}:${doc.file.key}`} alt={doc.title} zoom={zoom} />;
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
