"use client";

import { Fragment, type ReactNode } from "react";
import type { Answer, BodyPart } from "@/lib/types";
import { useStore, getDoc } from "@/lib/store";
import { Icon } from "./icon";
import { Pill } from "./ui";

export const KIND_INFO: Record<string, string> = {
  "One source": "info", "Multiple sources": "info", "Revised policy": "info",
  "Historical record": "warn", "Conflicting instructions": "bad", "Insufficient evidence": "mute2",
  "Needs clarification": "mute2", "Outside your scope": "warn",
};
const BANNER_ICON: Record<string, string> = { conflict: "alert", revised: "rev", insuff: "search", scope: "clock", historical: "clock" };

/** Answers saved before the server cleaned them may hold objects where text belongs; show their text. */
const txt = (x: unknown): string =>
  typeof x === "string" ? x : x && typeof x === "object" ? String(Object.values(x)[0] ?? "") : x == null ? "" : String(x);

/** Render **bold** and {n} citation markers as clickable chips. */
function inline(text: unknown, msgId: string, onCite: (i: number) => void): ReactNode[] {
  return txt(text).split(/(\*\*[^*]+\*\*|\{\d+\})/g).filter(Boolean).map((part, i) => {
    const bold = part.match(/^\*\*([^*]+)\*\*$/);
    if (bold) return <strong key={i}>{bold[1]}</strong>;
    const cite = part.match(/^\{(\d+)\}$/);
    if (cite) {
      const n = Number(cite[1]);
      return (
        <button key={i} className="cite" data-m={msgId} data-i={n - 1} title={`Open source ${n}`}
          onClick={() => onCite(n - 1)} type="button">{n}</button>
      );
    }
    return <Fragment key={i}>{part}</Fragment>;
  });
}

function Part({ part, msgId, lang, onCite, onAsk }: {
  part: BodyPart; msgId: string; lang: string; onCite: (i: number) => void; onAsk: (q: string) => void;
}) {
  if (part.p !== undefined) return <p lang={lang}>{inline(part.p, msgId, onCite)}</p>;
  if (part.sub !== undefined) return <p className="sub">{inline(part.sub, msgId, onCite)}</p>;
  if (part.ul) return <ul>{part.ul.map((x, i) => <li key={i} lang={lang}>{inline(x, msgId, onCite)}</li>)}</ul>;
  if (part.opts) return (
    <div className="chips">{part.opts.map(txt).map((q, i) => (
      <button key={i} className="fchip" onClick={() => onAsk(q)} type="button">{q}</button>))}</div>
  );
  if (part.table) return (
    <div className="table-wrap"><table>
      <thead><tr>{part.table.head.map((h, i) => <th key={i}>{txt(h)}</th>)}</tr></thead>
      <tbody>{part.table.rows.map((r, i) => (
        <tr key={i}>{r.map((x, j) => <td key={j}>{inline(x, msgId, onCite)}</td>)}</tr>))}</tbody>
    </table></div>
  );
  return null;
}

/** The answer body, sources and follow-up chips of one AI message. */
export function AnswerView({ answer, msgId, lang, onCite, onAsk }: {
  answer: Answer; msgId: string; lang: string; onCite: (i: number) => void; onAsk: (q: string) => void;
}) {
  const s = useStore();
  return (
    <>
      <div className="mb">
        {answer.banner && (
          <div className={`banner ${answer.banner.kind === "historical" ? "historical" : answer.banner.kind}`}>
            <Icon n={BANNER_ICON[answer.banner.kind] ?? "alert"} s /><span>{txt(answer.banner.text)}</span>
          </div>
        )}
        {answer.body.map((part, i) => (
          <Part key={i} part={part} msgId={msgId} lang={lang} onCite={onCite} onAsk={onAsk} />
        ))}
      </div>
      {answer.cites.length > 0 && (
        <div className="srcs">
          <div className="h">Sources</div>
          {answer.cites.map((c, i) => {
            const d = getDoc(s, c.doc);
            return (
              <button key={i} className="src" onClick={() => onCite(i)} type="button">
                <span className="n">{i + 1}</span>
                <span className="x"><b lang={d?.lang}>{d?.title ?? c.doc}</b> <span>· {d?.ref} · page {c.page}</span></span>
                {d && d.status !== "Active" && <Pill status={d.status} />}
              </button>
            );
          })}
        </div>
      )}
      {answer.follow.length > 0 && (
        <div className="follow" style={{ paddingTop: 12 }}>
          {answer.follow.map(txt).filter(Boolean).map((q, i) => (
            <button key={i} className="fchip" lang={/[ऀ-ॿ]/.test(q) ? "hi" : "en"}
              onClick={() => onAsk(q)} type="button">{q}</button>
          ))}
        </div>
      )}
    </>
  );
}

/** Plain-text version of an answer, for copy and export. */
export function answerText(a: Answer): string {
  const clean = (x: string) => x.replace(/\*\*/g, "").replace(/\{(\d+)\}/g, "[$1]");
  const lines: string[] = [];
  if (a.banner) lines.push("Note: " + a.banner.text);
  for (const p of a.body) {
    if (p.p) lines.push(clean(txt(p.p)));
    if (p.sub) lines.push(clean(txt(p.sub)));
    if (p.ul) p.ul.forEach((x) => lines.push("• " + clean(txt(x))));
    if (p.opts) p.opts.forEach((x) => lines.push("• " + txt(x)));
    if (p.table) { lines.push(p.table.head.map(txt).join(" | ")); p.table.rows.forEach((r) => lines.push(r.map((c) => clean(txt(c))).join(" | "))); }
  }
  return lines.join("\n");
}
