"use client";

import { Suspense, useEffect, useRef, useState } from "react";
import { useSearchParams } from "next/navigation";
import { api } from "@/lib/api";
import { aiSettings, chatGroup, clearScope, groupLabel, scopeDocs, setScope, useStore } from "@/lib/store";
import type { Answer, Chat, Msg } from "@/lib/types";
import { isHindi, nid, todayIso } from "@/lib/util";
import { Icon } from "@/components/icon";
import { AnswerView, KIND_INFO, answerText } from "@/components/answer";
import { DocsPanel } from "./docs-panel";
import { CompareModal, ExportModal, FeedbackModal, RequestDocModal, rate, reportConflict, type ExportItem } from "@/components/modals";

const SUGGESTIONS: [string, string][] = [
  ["One source", "How many casual leaves can teaching staff take?"],
  ["Multiple sources", "What do faculty need to do for the end-term exams?"],
  ["Revised policy", "Has the earned leave rule changed?"],
  ["Conflicting instructions", "When is the last date for the second instalment fee?"],
  ["Historical record", "What was the casual leave limit in 2024?"],
  ["Insufficient evidence", "What is the maternity leave policy for contract staff?"],
  ["हिन्दी प्रश्न", "परीक्षा ड्यूटी में रिपोर्टिंग का समय क्या है?"],
];

export default function AskPage() {
  return <Suspense><Ask /></Suspense>;
}

function Ask() {
  const params = useSearchParams();
  const s = useStore();
  const { save, set, openModal, openViewer, toast } = useStore.getState();
  const active = s.chats.find((c) => c.id === s.activeChat) ?? null;
  const msgsRef = useRef<HTMLDivElement>(null);
  const [histOpen, setHistOpen] = useState(false);
  const [text, setText] = useState("");
  const [search, setSearch] = useState("");
  const [tab, setTab] = useState<"docs" | "chats">("docs");

  // Links: open a chat (?c=), ask a question (?q=), or search a group of documents (?group=dept:Examination).
  useEffect(() => {
    const c = params.get("c");
    const q = params.get("q");
    const g = params.get("group");
    if (g) { setScope(g); set({ activeChat: null }); }
    if (c && s.chats.some((x) => x.id === c)) set({ activeChat: c });
    else if (q) { set({ activeChat: null }); void ask(q); }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [params]);

  useEffect(() => { if (msgsRef.current) msgsRef.current.scrollTop = msgsRef.current.scrollHeight; }, [active?.msgs]);

  async function ask(q: string) {
    q = q.trim();
    if (!q) return;
    const userMsg: Msg = { id: nid("m"), role: "user", text: q };
    const aiMsg: Msg = { id: nid("m"), role: "ai", q, pending: true };
    let chat = useStore.getState().chats.find((c) => c.id === useStore.getState().activeChat);
    if (!chat) {
      chat = { id: nid("ch"), title: q.length > 48 ? q.slice(0, 46) + "…" : q, msgs: [userMsg, aiMsg], saved: false, at: new Date().toISOString() };
      set({ activeChat: chat.id });
    } else {
      chat = { ...chat, msgs: [...chat.msgs, userMsg, aiMsg] };
    }
    await save("chats", chat);

    const st = useStore.getState();
    const lang = st.ansLang;  // "auto": answer in the question's own language, Hinglish included
    try {
      const answer = await api.ask({
        question: q,
        scope_ids: scopeDocs(st).map((d) => d.id),
        lang,
        // Earlier questions in this chat, so a follow-up like "and in 2023?" can be rewritten in full.
        history: chat.msgs.filter((m): m is Extract<Msg, { role: "user" }> => m.role === "user").map((m) => m.text).slice(0, -1),
      });
      finish(chat.id, aiMsg.id, { answer });  // unanswered questions are logged by the server
    } catch (e) {
      finish(chat.id, aiMsg.id, { error: (e as Error).message });
    }
  }

  function finish(chatId: string, msgId: string, patch: { answer?: Answer; error?: string }) {
    const chat = useStore.getState().chats.find((c) => c.id === chatId);
    if (!chat) return;
    void save("chats", { ...chat, msgs: chat.msgs.map((m) => (m.id === msgId ? { ...m, pending: false, ...patch } : m)) });
  }

  function onCite(msg: Extract<Msg, { role: "ai" }>, i: number) {
    const c = msg.answer?.cites[i];
    if (c) openViewer({ doc: c.doc, page: c.page, block: c.block, quote: c.quote, cites: msg.answer!.cites, idx: i, msg: msg.id });
  }

  const groups: Record<string, Chat[]> = {};
  s.chats.forEach((c) => { (groups[chatGroup(c)] ??= []).push(c); });
  const cited = new Set(active?.msgs.flatMap((m) => (m.role === "ai" ? m.answer?.cites.map((c) => c.doc) ?? [] : [])));
  const inScope = scopeDocs(s).length;
  const showDocs = () => { setTab("docs"); setHistOpen(true); };

  return (
    <div className={`chat ${histOpen ? "histopen" : ""}`}>
      <aside className="hist" aria-label="Documents and conversations">
        <div className="htabs seg" role="tablist">
          <button role="tab" aria-selected={tab === "docs"} className={tab === "docs" ? "on" : ""} onClick={() => setTab("docs")} type="button"><Icon n="file" s /> Documents</button>
          <button role="tab" aria-selected={tab === "chats"} className={tab === "chats" ? "on" : ""} onClick={() => setTab("chats")} type="button"><Icon n="chat" s /> Chats</button>
        </div>
        {tab === "docs" ? <DocsPanel cited={cited} /> : <>
        <div className="hh">
          <button className="btn pri" style={{ justifyContent: "center" }} onClick={() => { set({ activeChat: null }); setHistOpen(false); }} type="button"><Icon n="plus" s /> New conversation</button>
          <input className="inp" placeholder="Search conversations" value={search} onChange={(e) => setSearch(e.target.value)} aria-label="Search conversations" />
        </div>
        <div className="hl-list">
          {Object.entries(groups).map(([g, list]) => {
            const items = list.filter((c) => !search || c.title.toLowerCase().includes(search.toLowerCase()));
            return items.length ? (
              <div key={g}><div className="g">{g}</div>
                {items.map((c) => (
                  <div key={c.id} className="hrow">
                    <button className={`hitem ${c.id === s.activeChat ? "on" : ""}`} onClick={() => { set({ activeChat: c.id }); setHistOpen(false); }} type="button">
                      <b>{c.title}</b><span>{c.saved && <><Icon n="bm" s /> Saved · </>}{Math.ceil(c.msgs.length / 2)} question{c.msgs.length > 2 ? "s" : ""}</span>
                    </button>
                    <button className="iconbtn del" aria-label={`Delete conversation ${c.title}`} title="Delete conversation" onClick={() => deleteChat(c)} type="button"><Icon n="trash" s /></button>
                  </div>
                ))}
              </div>
            ) : null;
          })}
          {!s.chats.length && <div className="empty sm">No conversations yet.</div>}
        </div>
        </>}
      </aside>

      <section className="conv">
        <div className="convh">
          <button className="iconbtn menu-btn" aria-label="Show documents and conversations" onClick={() => setHistOpen((o) => !o)} type="button"><Icon n="hist" /></button>
          <span className="ttl">{active?.title ?? "New conversation"}</span>
          <button className="scopebtn" onClick={showDocs} type="button" title="Choose which documents to search">
            <Icon n="layers" s /><b>{groupLabel(s, s.scope.group)}</b><span>· {inScope} document{inScope === 1 ? "" : "s"}</span></button>
          {active && active.msgs.length > 0 && <>
            <button className="btn ghost sm" type="button" onClick={() => openModal({ title: "Export cited summary", wide: true, body: <ExportModal title={active.title} items={exportItems(active)} /> })}><Icon n="export" s /> Export</button>
            <button className="btn ghost sm" onClick={() => saveChat(active)} type="button"><Icon n="save" s /> {active.saved ? "Saved" : "Save"}</button>
          </>}
        </div>

        <div className="msgs" ref={msgsRef}>
          <div className="msgs-in">
            {active && active.msgs.length
              ? active.msgs.map((m) => <Message key={m.id} m={m} onCite={onCite} onAsk={ask} toast={toast} save={save} chat={active} />)
              : <Welcome onAsk={ask} />}
          </div>
        </div>

        <div className="composer">
          <form onSubmit={(e) => { e.preventDefault(); ask(text); setText(""); }}>
            <div className="cbox">
              <textarea rows={1} value={text} onChange={(e) => setText(e.target.value)}
                onKeyDown={(e) => { if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); ask(text); setText(""); } }}
                placeholder="Ask in Hindi or English, e.g. “आकस्मिक अवकाश कितने दिन का है?”" aria-label="Your question" />
              <button className="btn pri" type="submit" aria-label="Send"><Icon n="send" s /></button>
            </div>
            <div className="cmeta">
              <span><Icon n="globe" s /> Answer in <select value={s.ansLang} onChange={(e) => set({ ansLang: e.target.value })} aria-label="Answer language">
                <option value="auto">Same as question</option><option value="en">English</option><option value="hi">हिन्दी</option></select></span>
              <span>Searching {inScope} document{inScope === 1 ? "" : "s"}</span>
              <span>Answers come only from the records and always cite their sources.</span>
            </div>
          </form>
        </div>
      </section>
    </div>
  );

  function deleteChat(chat: Chat) {
    openModal({
      title: "Delete conversation?",
      body: <p>Delete <b>{chat.title}</b>? Its answers and any bookmarks of them are removed. This can&apos;t be undone.</p>,
      foot: <><button className="btn" onClick={() => useStore.getState().closeModal()} type="button">Cancel</button>
        <button className="btn danger" type="button" onClick={async () => {
          useStore.getState().closeModal();
          if (useStore.getState().activeChat === chat.id) set({ activeChat: null });
          if (await useStore.getState().remove("chats", chat.id)) {
            set({ bm_answers: useStore.getState().bm_answers.filter((b) => b.chat !== chat.id) });
            toast("Conversation deleted");
          }
        }}>Delete</button></>,
    });
  }

  async function saveChat(chat: Chat) {
    if (await save("chats", { ...chat, saved: !chat.saved, savedName: chat.savedName ?? chat.title }))
      toast(chat.saved ? "Removed from saved conversations" : "Conversation saved");
  }
}

function Message({ m, onCite, onAsk, toast, save, chat }: {
  m: Msg; onCite: (m: Extract<Msg, { role: "ai" }>, i: number) => void; onAsk: (q: string) => void;
  toast: (s: string) => void; save: ReturnType<typeof useStore.getState>["save"]; chat: Chat;
}) {
  const s = useStore();
  if (m.role === "user") return <div className="mu" lang={isHindi(m.text) ? "hi" : "en"}>{m.text}</div>;
  if (m.pending) return (
    <div className="ma"><div className="bot"><Icon n="spark" /></div><div className="box">
      <div className="thinking"><div><span className="spin" />Searching the records…</div></div></div></div>
  );
  if (m.error) return (
    <div className="ma"><div className="bot"><Icon n="spark" /></div><div className="box">
      <div className="mb"><div className="banner conflict"><Icon n="alert" s /><span>{m.error}</span></div></div></div></div>
  );
  if (!m.answer) return null;
  const a = m.answer;
  const ai = m as Extract<Msg, { role: "ai" }>;
  const lang = isHindi(m.q) ? "hi" : "en";
  const bm = s.bm_answers.some((b) => b.msg === m.id);
  const cited = [...new Set(a.cites.map((c) => c.doc))];
  const { openModal } = useStore.getState();

  return (
    <div className="ma" id={m.id}><div className="bot"><Icon n="spark" /></div><div className="box">
      <div className="mh"><b>SVSU Assistant</b>{aiSettings(s).showConf && <span className={`pill plain ${KIND_INFO[a.label] ?? "mute"}`}>{a.label}</span>}
        <span>From documents</span></div>
      {a.queries && a.queries.length > 0 && (
        <div className="searched"><Icon n="search" s /><span>Searched for: {a.queries.join(" · ")}</span></div>
      )}
      <AnswerView answer={a} msgId={m.id} lang={lang} onCite={(i) => onCite(ai, i)} onAsk={onAsk} />
      {a.label === "Conflicting instructions" && cited.length >= 2 && (
        <div className="mb row">
          <button className="btn sm" type="button" onClick={() => openModal({ title: "Compare documents", wide: true, body: <CompareModal a={cited[0]} b={cited[1]} topic={m.q} /> })}>Compare both documents</button>
          <button className="btn sm ghost" type="button" onClick={() => void reportConflict(cited.slice(0, 2), m.q)}>Report conflict</button>
        </div>
      )}
      {a.label === "Insufficient evidence" && (
        <div className="mb row"><button className="btn sm" type="button" onClick={() => openModal({ title: "Request a document", body: <RequestDocModal q={m.q} dept={s.session?.dept} /> })}><Icon n="file" s /> Request a document</button></div>
      )}
      {a.label === "Outside your scope" && (
        <div className="mb row"><button className="btn sm pri" type="button" onClick={() => { clearScope(); onAsk(m.q); }}>Search all permitted documents</button></div>
      )}
      <div className="macts">
        <button className="btn ghost" onClick={() => { navigator.clipboard?.writeText(answerText(a)); toast("Copied"); }} type="button"><Icon n="copy" s /> Copy</button>
        <button className={`btn ghost ${bm ? "on" : ""}`} type="button" onClick={async () => {
          const b = s.bm_answers.find((x) => x.msg === m.id);
          if (b) { if (await useStore.getState().remove("bm_answers", b.id)) toast("Bookmark removed"); }
          else if (await save("bm_answers", { id: nid("ba"), chat: chat.id, msg: m.id, q: m.q, when: todayIso() })) toast("Answer bookmarked");
        }}><Icon n="bm" s /> {bm ? "Bookmarked" : "Bookmark"}</button>
        <button className="btn ghost" type="button" onClick={() => openModal({ title: "Export cited summary", wide: true, body: <ExportModal title={m.q} items={[{ q: m.q, answer: a }]} /> })}><Icon n="export" s /> Export</button>
        <span style={{ flex: 1 }} />
        <button className={`btn ghost ${m.fb === "up" ? "on" : ""}`} aria-label="Helpful" type="button" onClick={() => void rate(chat, ai, "up")}><Icon n="up" s /></button>
        <button className={`btn ghost ${m.fb === "down" ? "on" : ""}`} aria-label="Not helpful" type="button" onClick={() => openModal({ title: "What was wrong with this answer?", body: <FeedbackModal chat={chat} m={ai} /> })}><Icon n="down" s /></button>
      </div>
    </div></div>
  );
}

/** Question-and-answer pairs of a chat, for export. */
function exportItems(chat: Chat): ExportItem[] {
  return chat.msgs.flatMap((m) => (m.role === "ai" && m.answer ? [{ q: m.q, answer: m.answer }] : []));
}

function Welcome({ onAsk }: { onAsk: (q: string) => void }) {
  return (
    <div className="welcome">
      <h2>Ask about SVSU letters, notices and policies</h2>
      <p>Answers come only from documents you are allowed to see. Every claim has a numbered citation — click a number to open the source at the exact passage.</p>
      <div className="sugg">
        {SUGGESTIONS.map(([k, q]) => (
          <button key={q} className="sq" onClick={() => onAsk(q)} type="button"><span>{k}</span><b lang={isHindi(q) ? "hi" : "en"}>{q}</b></button>
        ))}
      </div>
    </div>
  );
}
