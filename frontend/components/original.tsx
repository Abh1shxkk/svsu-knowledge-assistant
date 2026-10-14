"use client";

import { useEffect, useState } from "react";
import { api } from "@/lib/api";
import type { Doc } from "@/lib/types";
import { Icon } from "./icon";

/** Fetches the original upload (the request needs the sign-in token, so it can't be a plain link). */
function useOriginal(doc: Doc) {
  const [url, setUrl] = useState<{ key: string; href: string } | null>(null);
  const [failed, setFailed] = useState("");
  const key = doc.file?.key;
  useEffect(() => {
    if (!key) return;
    let href = "", cancelled = false;
    api.originalFile(doc.id)
      .then((blob) => { if (!cancelled) { href = URL.createObjectURL(blob); setUrl({ key, href }); } })
      .catch((e) => { if (!cancelled) setFailed((e as Error).message); });
    return () => { cancelled = true; if (href) URL.revokeObjectURL(href); };
  }, [doc.id, key]);
  return { href: url && url.key === key ? url.href : "", failed };
}

/** The real document: PDFs in the browser's own viewer (at the given page), images as pictures, other
 *  files (Word, Excel) as a download. */
export function OriginalFile({ doc, page = 1 }: { doc: Doc; page?: number }) {
  const { href, failed } = useOriginal(doc);
  if (failed) return <div className="empty sm">{failed}</div>;
  if (!href) return <div className="empty"><span className="spin" /></div>;
  const mime = doc.file!.mime;
  if (mime === "application/pdf") return <iframe className="orig" src={`${href}#page=${page}`} title={`Original: ${doc.title}`} />;
  if (mime.startsWith("image/")) return <img className="orig-img" src={href} alt={`Original: ${doc.title}`} />;  // eslint-disable-line @next/next/no-img-element
  return (
    <div className="empty" style={{ display: "flex", flexDirection: "column", gap: 10, alignItems: "center" }}>
      <p className="sm">This file type can&apos;t be shown in the browser. Download it, or use the Text view.</p>
      <DownloadOriginal doc={doc} />
    </div>
  );
}

export function DownloadOriginal({ doc, small }: { doc: Doc; small?: boolean }) {
  const save = async () => {
    const blob = await api.originalFile(doc.id);
    const a = Object.assign(document.createElement("a"), { href: URL.createObjectURL(blob), download: doc.file?.name ?? "document" });
    a.click(); URL.revokeObjectURL(a.href);
  };
  if (!doc.file) return null;
  return <button className={`btn ${small ? "sm" : ""}`} onClick={() => void save()} type="button"><Icon n="open" s /> Download original</button>;
}
