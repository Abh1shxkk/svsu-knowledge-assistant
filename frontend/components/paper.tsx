"use client";

import type { Block, Doc } from "@/lib/types";
import { fmtD } from "@/lib/util";
import { Icon } from "./icon";

export type Highlight = { page: number; block: string; quote?: string } | null;

function Letterhead({ d }: { d: Doc }) {
  const hi = d.lang === "hi";
  return (
    <>
      <div className="lh">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src="/logo.png" alt="" />
        <div>
          <div className="lh-n">{hi ? "स्वामी विवेकानन्द सुभारती विश्वविद्यालय" : "Swami Vivekanand Subharti University"}</div>
          <div className="lh-s">Subhartipuram, NH-58, Delhi–Haridwar Bypass Road, Meerut (U.P.)</div>
          <div className="lh-o">{hi ? "कार्यालय: " : "Office of the "}{d.authority}</div>
        </div>
      </div>
      <div className="lh-ref">
        <span>{hi ? "पत्रांक" : "No."} {d.ref}</span>
        <span>{hi ? "दिनांक" : "Date"}: {fmtD(d.date)}</span>
      </div>
    </>
  );
}

function BlockP({ b, page, hl, onBookmark }: {
  b: Block; page: number; hl: Highlight; onBookmark?: (page: number, block: string) => void;
}) {
  const text = b.text as string;
  const on = hl && hl.page === page && hl.block === b.id;
  let inner: React.ReactNode = text;
  if (on) {
    const q = hl.quote ?? "";
    const i = q ? text.indexOf(q) : -1;
    inner = i >= 0
      ? <>{text.slice(0, i)}<mark className="hl">{q}</mark>{text.slice(i + q.length)}</>
      : <mark className="hl">{text}</mark>;
  }
  return (
    <p className={`blk ${b.kind}${on ? " hlb" : ""}`} data-block={b.id}>
      {inner}
      {onBookmark && b.kind !== "subj" && (
        <button className="bmk" type="button" title="Bookmark this passage"
          aria-label="Bookmark this passage" onClick={() => onBookmark(page, b.id)}><Icon n="bm" s /></button>
      )}
    </p>
  );
}

function Sheet({ page, hl }: { page: Block[]; hl: Highlight }) {
  return (
    <div className="table-wrap">
      <table className="sheet">
        <tbody>
          <tr><th /><th>A</th><th>B</th><th>C</th><th>D</th></tr>
          {page.map((b, i) => (
            <tr key={b.id} className={`${b.kind === "hdr" ? "hdr" : ""} ${hl && hl.block === b.id ? "hlb" : ""}`} data-block={b.id}>
              <td className="rn">{i + 1}</td>
              {(b.text as string[]).map((x, j) => <td key={j}>{x}</td>)}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

export function Pages({ doc, hl = null, onBookmark, zoom, only }: {
  doc: Doc; hl?: Highlight; onBookmark?: (page: number, block: string) => void; zoom?: number; only?: number;
}) {
  if (!doc.pages) return <div className="empty"><span className="spin" /></div>;
  const pages = doc.pages;
  return (
    <>
      {pages.map((page, pi) => (only !== undefined && pi !== only) ? null : (
        <div key={pi} className={`paper ${doc.fileType === "scan" ? "scan" : ""}`} data-page={pi + 1} lang={doc.lang}
          style={zoom ? { zoom } : undefined}>
          {doc.fileType === "scan" && <span className="ocrbadge">Scanned · OCR text {doc.ocr}% confidence</span>}
          {pi === 0 && doc.sample && <Letterhead d={doc} />}
          {doc.fileType === "xlsx"
            ? <Sheet page={page} hl={hl} />
            : page.map((b) => <BlockP key={b.id} b={b} page={pi + 1} hl={hl} onBookmark={onBookmark} />)}
          {/* The prototype's sample letters carry a signature block and a watermark; real uploads don't. */}
          {doc.sample && pi === pages.length - 1 && doc.fileType !== "xlsx" && (
            <div className="sign">
              <div className="scrib">sd/-</div><div><b>{doc.authority}</b></div>
              <div className="cc">Copy to: All Heads of Institutions · Notice boards · University ERP</div>
            </div>
          )}
          <div className="pfoot"><span>{doc.ref}</span><span>Page {pi + 1} of {pages.length}</span></div>
          {doc.sample && <div className="wm">SAMPLE</div>}
        </div>
      ))}
    </>
  );
}

export const docText = (d: Doc) =>
  (d.pages ?? []).map((pg, i) => `— Page ${i + 1} —\n` + pg.map((b) => (Array.isArray(b.text) ? b.text.join("\t") : b.text)).join("\n\n")).join("\n\n");
