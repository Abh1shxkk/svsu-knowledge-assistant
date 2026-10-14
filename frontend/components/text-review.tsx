"use client";

import { Fragment, useState, type ReactNode } from "react";
import type { Block } from "@/lib/types";
import { blockText } from "@/lib/util";
import { Icon } from "./icon";

/** A document's text as plain text: pages marked "=== Page n ===", paragraphs separated by a blank line. */
export const pagesToText = (pages: Block[][]) =>
  pages.map((pg, i) => `=== Page ${i + 1} ===\n` + pg.map((b) => blockText(b.text)).join("\n\n")).join("\n\n");

/** The reverse: corrected text back into pages of paragraphs (every paragraph gets a fresh id). */
export function textToPages(text: string): Block[][] {
  let n = 0;
  return text.split(/^=+ *Page \d+ *=+ *$/m)
    .map((page) => page.split(/\n\s*\n/).map((p) => p.trim()).filter(Boolean)
      .map((p): Block => ({ id: `b${++n}`, text: p, kind: "p" })))
    .filter((page) => page.length);
}

/** Underline the words OCR wasn't sure about. */
function marked(text: string, unsure: string[]): ReactNode {
  if (!unsure.length) return text;
  const esc = [...unsure].sort((a, b) => b.length - a.length).map((w) => w.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"));
  const re = new RegExp(`(${esc.join("|")})`, "g");
  return text.split(re).map((part, i) => (i % 2 ? <mark key={i} className="lowconf" title="Read with low confidence">{part}</mark> : <Fragment key={i}>{part}</Fragment>));
}

/** Shows the text the assistant will search, with OCR doubts marked, and lets it be corrected. */
export function TextReview({ pages, unsure = [], editable, onSave, lang }: {
  pages: Block[][]; unsure?: string[]; editable: boolean; onSave: (pages: Block[][]) => void | Promise<unknown>; lang?: string;
}) {
  const [draft, setDraft] = useState<string | null>(null);
  const sheet = pages.some((pg) => pg.some((b) => Array.isArray(b.text)));  // spreadsheet rows aren't edited as text
  const text = pagesToText(pages);
  const save = async () => {
    const next = textToPages(draft ?? "");
    if (!next.length) return;
    await onSave(next);
    setDraft(null);
  };
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
      {unsure.length > 0 && draft === null && (
        <div className="note warn"><Icon n="alert" s /><p className="sm"><b>{unsure.length} word{unsure.length > 1 ? "s were" : " was"} read with low confidence</b> (underlined in red). Compare them with the original and correct any mistakes, especially dates, numbers and codes.</p></div>
      )}
      {draft === null ? (
        <div className="exttext" lang={lang}>{marked(text, unsure)}</div>
      ) : (
        <>
          <p className="xs muted">Keep the “=== Page n ===” lines. A blank line separates paragraphs; keep each table row on its own line.</p>
          <textarea className="inp exttext-edit" lang={lang} value={draft} onChange={(e) => setDraft(e.target.value)} spellCheck={false} aria-label="Document text" />
        </>
      )}
      {editable && !sheet && (
        <div className="row" style={{ justifyContent: "flex-end" }}>
          {draft === null
            ? <button className="btn sm" type="button" onClick={() => setDraft(text)}><Icon n="edit" s /> Edit text</button>
            : <>
              <button className="btn sm" type="button" onClick={() => setDraft(null)}>Cancel</button>
              <button className="btn sm pri" type="button" onClick={() => void save()}>Save text</button>
            </>}
        </div>
      )}
    </div>
  );
}
