"use client";

import { useState } from "react";
import Link from "next/link";
import { getDoc, useStore } from "@/lib/store";
import { plural } from "@/lib/util";
import { Icon } from "@/components/icon";
import { Tabs } from "@/components/ui";
import { answerText } from "@/components/answer";
import type { Msg } from "@/lib/types";

export default function SavedPage() {
  const s = useStore();
  const { remove, openViewer, toast } = useStore.getState();
  const [tab, setTab] = useState("chats");
  const saved = s.chats.filter((c) => c.saved);

  return (
    <div className="wrap">
      <div className="pagehead"><div><h2>Saved Chats &amp; Bookmarks</h2><p>Conversations, answers and document passages you kept for later.</p></div></div>
      <Tabs active={tab} onChange={setTab} tabs={[["chats", "Saved conversations", saved.length], ["answers", "Bookmarked answers", s.bm_answers.length], ["passages", "Bookmarked passages", s.bm_passages.length]]} />

      {tab === "chats" && (saved.length ? (
        <div className="card">{saved.map((c) => (
          <div key={c.id} className="li"><span className="av" style={{ width: 30, height: 30 }}><Icon n="chat" s /></span>
            <div className="main"><b>{c.savedName || c.title}</b><span>{plural(Math.ceil(c.msgs.length / 2), "question")} · {c.when} · first: {(c.msgs[0] as { text: string }).text}</span></div>
            <Link className="btn sm" href={`/ask?c=${c.id}`}>Open</Link>
            <button className="iconbtn" aria-label="Remove from saved" onClick={() => { void useStore.getState().save("chats", { ...c, saved: false }); toast("Removed from saved"); }} type="button"><Icon n="trash" s /></button>
          </div>
        ))}</div>
      ) : <div className="card empty">No saved conversations. Use “Save” in a conversation to keep it here.</div>)}

      {tab === "answers" && (s.bm_answers.length ? (
        <div className="card">{s.bm_answers.map((b) => {
          const chat = s.chats.find((c) => c.id === b.chat);
          const m = chat?.msgs.find((x) => x.id === b.msg) as Extract<Msg, { role: "ai" }> | undefined;
          const preview = m?.answer ? answerText(m.answer).replace(/\[\d+\]/g, "").slice(0, 170) : "";
          return (
            <div key={b.id} className="li"><span className="av" style={{ width: 30, height: 30 }}><Icon n="bm" s /></span>
              <div className="main"><b>{b.q}</b><span style={{ display: "block", whiteSpace: "normal" }}>{preview}…</span>
                <span>{m?.answer?.cites.length ?? 0} sources · bookmarked {b.when}</span></div>
              {chat && <Link className="btn sm" href={`/ask?c=${chat.id}`}>Open</Link>}
              <button className="iconbtn" aria-label="Remove bookmark" onClick={() => { void remove("bm_answers", b.id); toast("Bookmark removed"); }} type="button"><Icon n="trash" s /></button>
            </div>
          );
        })}</div>
      ) : <div className="card empty">No bookmarked answers yet.</div>)}

      {tab === "passages" && (s.bm_passages.length ? (
        <div className="card">{s.bm_passages.map((b) => {
          const d = getDoc(s, b.doc);
          return (
            <div key={b.id} className="li"><span className="av" style={{ width: 30, height: 30 }}><Icon n="file" s /></span>
              <div className="main"><b style={{ whiteSpace: "normal", fontFamily: "var(--f-doc)", fontWeight: 400 }} lang={d?.lang}>“{b.quote}”</b>
                <span>{d?.title} · {d?.ref}, p.{b.page}{b.note && " · Note: " + b.note}</span></div>
              <button className="btn sm" onClick={() => openViewer({ doc: b.doc, page: b.page, block: b.block, quote: b.quote })} type="button">Show passage</button>
              <button className="iconbtn" aria-label="Remove bookmark" onClick={() => { void remove("bm_passages", b.id); toast("Bookmark removed"); }} type="button"><Icon n="trash" s /></button>
            </div>
          );
        })}</div>
      ) : <div className="card empty">No bookmarked passages. Open a citation and choose “Bookmark passage”.</div>)}
    </div>
  );
}
