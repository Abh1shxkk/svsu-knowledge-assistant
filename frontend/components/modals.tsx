"use client";

/** Modals used from more than one screen. Each one saves through the store, so the server decides. */
import { useState } from "react";
import { api } from "@/lib/api";
import { getDoc, lists, me, permitted, useFullDoc, useStore } from "@/lib/store";
import type { Answer, Chat, Deadline, Msg, Reminder } from "@/lib/types";
import { blockText, fmtD, nid, todayIso } from "@/lib/util";
import { answerText } from "./answer";
import { Icon } from "./icon";
import { Pages } from "./paper";
import { Field, ModalFoot, Pill } from "./ui";

type AiMsg = Extract<Msg, { role: "ai" }>;
const close = () => useStore.getState().closeModal();

/* ---------- Answer feedback ---------- */
const REASONS = ["Incorrect information", "Wrong or missing source", "Outdated document used", "Conflicting information", "Incomplete answer", "Wrong language"];

/** One feedback entry per answer: rating again replaces it. */
export async function rate(chat: Chat, m: AiMsg, rating: "up" | "down", reason = "", comment = "") {
  const st = useStore.getState();
  await st.save("chats", { ...chat, msgs: chat.msgs.map((x) => (x.id === m.id ? { ...x, fb: rating } : x)) });
  const ok = await st.save("feedback", { id: "fb-" + m.id, q: m.q, rating, reason, comment, who: me(st).name, when: todayIso() });
  if (ok) st.toast(rating === "up" ? "Thanks. Marked as helpful." : "Feedback sent to Reports & Feedback");
}

export function FeedbackModal({ chat, m }: { chat: Chat; m: AiMsg }) {
  const [reason, setReason] = useState(REASONS[0]);
  const [comment, setComment] = useState("");
  return (
    <>
      <div className="chips">{REASONS.map((r) => (
        <label key={r} className="chk"><input type="radio" name="fbr" checked={reason === r} onChange={() => setReason(r)} />{r}</label>
      ))}</div>
      <Field label="Comment (optional)" htmlFor="fb-c"><textarea className="inp" id="fb-c" rows={3} value={comment} onChange={(e) => setComment(e.target.value)} placeholder="What should the answer have said?" /></Field>
      <p className="xs muted">Feedback goes to Reports &amp; Feedback for the document owners.</p>
      <ModalFoot>
        <button className="btn" onClick={close} type="button">Cancel</button>
        <button className="btn pri" type="button" onClick={() => { close(); void rate(chat, m, "down", reason, comment); }}>Send feedback</button>
      </ModalFoot>
    </>
  );
}

/* ---------- Export cited summary ---------- */
export type ExportItem = { q: string; answer: Answer };

function summaryText(items: ExportItem[]) {
  const s = useStore.getState();
  return items.map(({ q, answer }) => {
    const src = answer.cites.map((c, i) => {
      const d = getDoc(s, c.doc);
      return `[${i + 1}] ${d ? `${d.title} (${d.ref})` : c.doc}, page ${c.page} — "${c.quote}"`;
    });
    return [`Q: ${q}`, answerText(answer), ...(src.length ? ["Sources", ...src] : [])].join("\n");
  }).join("\n\n");
}

export function ExportModal({ title, items }: { title: string; items: ExportItem[] }) {
  const { toast } = useStore.getState();
  const text = summaryText(items);
  const [busy, setBusy] = useState(false);
  const word = async () => {
    setBusy(true);
    try {
      const blob = await api.exportDocx(title, items);
      const a = Object.assign(document.createElement("a"), { href: URL.createObjectURL(blob), download: "svsu-cited-summary.docx" });
      a.click(); URL.revokeObjectURL(a.href);
    } catch (e) { toast((e as Error).message); }
    setBusy(false);
  };
  const pdf = () => {  // the browser's print dialog saves as PDF
    const w = window.open("", "_blank");
    if (!w) { toast("Allow pop-ups to print"); return; }
    const esc = (x: string) => x.replace(/[&<>]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" })[c]!);
    w.document.write(`<title>${esc(title)}</title><body style="font:14px/1.6 system-ui;max-width:720px;margin:32px auto;white-space:pre-wrap"><h2>${esc(title)}</h2>${esc(text)}</body>`);
    w.document.close(); w.print();
  };
  return (
    <>
      <div className="prevbox"><pre style={{ whiteSpace: "pre-wrap" }}>{text}</pre></div>
      <ModalFoot>
        <button className="btn" onClick={() => { navigator.clipboard?.writeText(text); toast("Copied"); }} type="button"><Icon n="copy" s /> Copy summary</button>
        <button className="btn" onClick={pdf} type="button">Print or save as PDF</button>
        <button className="btn pri" onClick={word} disabled={busy} type="button">{busy ? "Preparing…" : "Download Word"}</button>
      </ModalFoot>
    </>
  );
}

/* ---------- Compare two documents · report a conflict ---------- */
export async function reportConflict(docs: string[], topic: string) {
  const st = useStore.getState();
  if (st.conflicts.some((c) => c.status === "Open" && c.docs.join() === docs.join())) { st.toast("This conflict is already reported"); return; }
  const ok = await st.save("conflicts", { id: nid("cf"), docs, topic, status: "Open", reported: todayIso(), by: me(st).name });
  if (ok) st.toast("Conflict reported to the document owners");
}

function ComparePane({ id }: { id: string }) {
  const d = useFullDoc(id);
  if (!d) return <div className="empty"><span className="spin" /></div>;
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 8, minWidth: 0 }}>
      <div><Pill status={d.status} /> <b>{d.title}</b><div className="mono muted">{d.ref} · {fmtD(d.date)} · {d.authority}</div></div>
      <div className="pagesbox" style={{ padding: 10, maxHeight: 420 }}><Pages doc={d} zoom={0.62} /></div>
    </div>
  );
}

export function CompareModal({ a, b, topic }: { a: string; b: string; topic: string }) {
  return (
    <>
      <div className="grid2"><ComparePane id={a} /><ComparePane id={b} /></div>
      <ModalFoot>
        <button className="btn" onClick={close} type="button">Close</button>
        <button className="btn pri" type="button" onClick={() => { close(); void reportConflict([a, b], topic); }}>Report conflict</button>
      </ModalFoot>
    </>
  );
}

/* ---------- Request a document ---------- */
export function RequestDocModal({ q, dept }: { q: string; dept?: string }) {
  const s = useStore();
  const L = lists(s);
  const [d, setD] = useState(dept || L.DEPTS[0] || "");
  const [note, setNote] = useState(`Please upload the rule or circular that answers: “${q}”`);
  const send = async () => {
    try { await api.requestDoc(q, d, note); close(); s.toast(`Request sent to ${d}`); void s.load(); }
    catch (e) { s.toast((e as Error).message); }
  };
  return (
    <>
      <p className="sm">“{q}”</p>
      <Field label="Department" htmlFor="rq-d"><select className="inp" id="rq-d" value={d} onChange={(e) => setD(e.target.value)}>{L.DEPTS.map((x) => <option key={x}>{x}</option>)}</select></Field>
      <Field label="Note" htmlFor="rq-n"><textarea className="inp" id="rq-n" rows={3} value={note} onChange={(e) => setNote(e.target.value)} /></Field>
      <ModalFoot><button className="btn" onClick={close} type="button">Cancel</button><button className="btn pri" onClick={send} type="button">Send request</button></ModalFoot>
    </>
  );
}

/* ---------- Deadlines ---------- */
export function DeadlineModal({ docId, deadline }: { docId?: string; deadline?: Deadline }) {
  const s = useStore();
  const [f, setF] = useState({
    title: deadline?.title ?? "", date: deadline?.date ?? todayIso(), owner: deadline?.owner ?? "HODs",
    aud: deadline?.aud ?? "Teaching staff", doc: deadline?.doc ?? docId ?? permitted(s)[0]?.id ?? "",
  });
  const doc = useFullDoc(f.doc);
  const submit = async () => {
    if (!f.title.trim() || !f.date || !f.doc) { s.toast("Fill in what, when and the source document"); return; }
    if (!doc?.pages) { s.toast("Still loading the document…"); return; }
    // A new deadline points at the document's first paragraph; an edited one keeps its passage.
    const b = doc.pages[0]?.find((x) => x.kind !== "subj") ?? doc.pages[0]?.[0];
    const keep = deadline && deadline.doc === f.doc;
    const item: Deadline = {
      ...(deadline ?? {}), id: deadline?.id ?? nid("dl"), title: f.title.trim(), date: f.date, owner: f.owner, aud: f.aud, doc: f.doc,
      dept: doc.dept, page: keep ? deadline.page : 1, block: keep ? deadline.block : b?.id ?? "", quote: keep ? deadline.quote : b && !Array.isArray(b.text) ? b.text : "",
    };
    if (await s.save("deadlines", item)) { close(); s.toast(deadline ? "Deadline updated" : "Deadline added"); }
  };
  const set = (p: Partial<typeof f>) => setF({ ...f, ...p });
  return (
    <>
      <Field label="What needs to be done?" htmlFor="ad-t"><input className="inp" id="ad-t" value={f.title} onChange={(e) => set({ title: e.target.value })} autoFocus /></Field>
      <div className="grid2">
        <Field label="Due date" htmlFor="ad-d"><input type="date" className="inp" id="ad-d" value={f.date} onChange={(e) => set({ date: e.target.value })} /></Field>
        <Field label="Responsible" htmlFor="ad-o"><input className="inp" id="ad-o" value={f.owner} onChange={(e) => set({ owner: e.target.value })} /></Field>
      </div>
      <Field label="Source document" htmlFor="ad-doc"><select className="inp" id="ad-doc" value={f.doc} onChange={(e) => set({ doc: e.target.value })}>
        {permitted(s).map((d) => <option key={d.id} value={d.id}>{d.ref} — {d.title}</option>)}</select></Field>
      <Field label="Applies to" htmlFor="ad-a"><input className="inp" id="ad-a" value={f.aud} onChange={(e) => set({ aud: e.target.value })} /></Field>
      {doc?.pages && deadline?.doc === f.doc && <p className="xs muted">Linked passage: “{blockText(doc.pages[deadline.page - 1]?.find((b) => b.id === deadline.block)?.text ?? "").slice(0, 120)}”</p>}
      <ModalFoot><button className="btn" onClick={close} type="button">Cancel</button><button className="btn pri" onClick={submit} type="button">{deadline ? "Save deadline" : "Add deadline"}</button></ModalFoot>
    </>
  );
}

const WHEN: [number, string][] = [[0, "On the day"], [1, "1 day before"], [3, "3 days before"], [7, "1 week before"]];
const CHANNELS = ["In the app", "Email"];

export function ReminderModal({ deadline }: { deadline: Deadline }) {
  const s = useStore();
  const existing = s.reminders.find((r) => r.deadline === deadline.id);
  const [days, setDays] = useState(existing?.days ?? 3);
  const [via, setVia] = useState(existing?.via ?? CHANNELS);
  const submit = async () => {
    const r: Reminder = { id: existing?.id ?? nid("rm"), deadline: deadline.id, days, via: via.length ? via : ["In the app"] };
    if (await s.save("reminders", r)) { close(); s.toast("Reminder set"); }
  };
  return (
    <>
      <p className="sm"><b>{deadline.title}</b> · due {fmtD(deadline.date)}</p>
      <Field label="Remind me" htmlFor="rm-w"><select className="inp" id="rm-w" value={days} onChange={(e) => setDays(Number(e.target.value))}>
        {WHEN.map(([n, l]) => <option key={n} value={n}>{l}</option>)}</select></Field>
      <Field label="Send through"><div className="chips">{CHANNELS.map((c) => (
        <label key={c} className="chk"><input type="checkbox" checked={via.includes(c)} onChange={() => setVia(via.includes(c) ? via.filter((x) => x !== c) : [...via, c])} />{c}</label>
      ))}</div></Field>
      <p className="xs muted">Email needs an address on your profile and the mail server set up by IT.</p>
      <ModalFoot>
        {existing && <button className="btn danger" style={{ marginRight: "auto" }} type="button" onClick={async () => { if (await s.remove("reminders", existing.id)) { close(); s.toast("Reminder removed"); } }}>Remove</button>}
        <button className="btn" onClick={close} type="button">Cancel</button><button className="btn pri" onClick={submit} type="button">Save reminder</button>
      </ModalFoot>
    </>
  );
}
