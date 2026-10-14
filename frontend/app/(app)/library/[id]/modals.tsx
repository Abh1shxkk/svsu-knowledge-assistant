"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { api } from "@/lib/api";
import { lists, me, useStore } from "@/lib/store";
import { blockText, fmtD, isHindi, nid, todayIso } from "@/lib/util";
import type { Doc } from "@/lib/types";
import { Field, ModalFoot } from "@/components/ui";

const close = () => useStore.getState().closeModal();
const nextVersion = (d: Doc) => (parseFloat(d.versions[d.versions.length - 1]?.v ?? "1.0") + 0.1).toFixed(1);

export function EditMetaModal({ doc }: { doc: Doc }) {
  const s = useStore();
  const L = lists(s);
  const [m, setM] = useState(doc);
  const set = (patch: Partial<Doc>) => setM((p) => ({ ...p, ...patch }));
  const toggleAud = (a: string) => set({ audience: m.audience.includes(a) ? m.audience.filter((x) => x !== a) : [...m.audience, a] });
  const submit = async () => {
    if (m.expiry && m.effective && m.expiry < m.effective) { s.toast("Expiry date must be after the effective date"); return; }
    const versions = [...m.versions, { v: nextVersion(m), date: todayIso(), by: me(s).name, note: "Metadata edited" }];
    if (await s.save("documents", { ...m, versions })) { close(); s.toast("Metadata saved"); }
  };
  return (
    <>
      <Field label="Title"><input className="inp" value={m.title} onChange={(e) => set({ title: e.target.value })} /></Field>
      <div className="grid2">
        <Field label="Reference number"><input className="inp" value={m.ref} onChange={(e) => set({ ref: e.target.value })} /></Field>
        <Field label="Type"><select className="inp" value={m.type} onChange={(e) => set({ type: e.target.value })}>{L.TYPES.map((x) => <option key={x}>{x}</option>)}</select></Field>
        <Field label="Issuing authority"><select className="inp" value={m.authority} onChange={(e) => set({ authority: e.target.value })}>{L.AUTHS.map((x) => <option key={x}>{x}</option>)}</select></Field>
        <Field label="Department"><select className="inp" value={m.dept} onChange={(e) => set({ dept: e.target.value })}>{L.DEPTS.map((x) => <option key={x}>{x}</option>)}</select></Field>
        <Field label="Document date"><input type="date" className="inp" value={m.date} onChange={(e) => set({ date: e.target.value })} /></Field>
        <Field label="Effective date"><input type="date" className="inp" value={m.effective} onChange={(e) => set({ effective: e.target.value })} /></Field>
        <Field label="Expiry date"><input type="date" className="inp" value={m.expiry} onChange={(e) => set({ expiry: e.target.value })} /></Field>
        <Field label="Institution"><select className="inp" value={m.institution} onChange={(e) => set({ institution: e.target.value })}>{L.INSTS.map((x) => <option key={x}>{x}</option>)}</select></Field>
      </div>
      <Field label="Audience"><div className="chips">{L.AUDS.map((a) => (
        <label key={a} className="chk"><input type="checkbox" checked={m.audience.includes(a)} onChange={() => toggleAud(a)} />{a}</label>
      ))}</div></Field>
      <Field label="Subject tags"><div className="chips">{L.TAGS.map((t) => (
        <label key={t} className="chk"><input type="checkbox" checked={m.tags.includes(t)}
          onChange={() => set({ tags: m.tags.includes(t) ? m.tags.filter((x) => x !== t) : [...m.tags, t] })} />{t}</label>
      ))}</div></Field>
      <Field label="Description"><textarea className="inp" rows={3} value={m.description} onChange={(e) => set({ description: e.target.value })} /></Field>
      <ModalFoot><button className="btn" onClick={close} type="button">Cancel</button><button className="btn pri" onClick={submit} type="button">Save changes</button></ModalFoot>
    </>
  );
}

export function WithdrawModal({ doc }: { doc: Doc }) {
  const s = useStore();
  const [reason, setReason] = useState("");
  const [date, setDate] = useState(todayIso());
  const submit = async () => {
    if (!reason.trim()) { s.toast("Add a reason"); return; }
    const ok = await s.save("documents", {
      ...doc, status: "Withdrawn", withdrawReason: reason,
      approvals: [...doc.approvals, { step: "Withdrawn", by: me(s).name, date, kind: "bad", note: reason }],
    });
    if (ok) { close(); s.toast("Document withdrawn. It will no longer be used in answers."); }
  };
  return (
    <>
      <div className="note bad"><p className="sm"><b>{doc.title}</b> will stop being used in AI answers. It stays in the library, marked Withdrawn, for the record.</p></div>
      <Field label="Reason or withdrawing order" req><textarea className="inp" rows={3} value={reason} onChange={(e) => setReason(e.target.value)} placeholder="e.g. Withdrawn vide Office Order SVSU/REG/ADM/2026/120" /></Field>
      <Field label="Withdrawal date" hint={fmtD(date)}><input type="date" className="inp" value={date} onChange={(e) => setDate(e.target.value)} /></Field>
      <ModalFoot><button className="btn" onClick={close} type="button">Cancel</button><button className="btn danger" onClick={submit} type="button">Withdraw document</button></ModalFoot>
    </>
  );
}

/** Links are two-way: both documents list each other as related. */
export async function setLink(a: Doc, b: Doc, linked: boolean) {
  const { save } = useStore.getState();
  const edit = (d: Doc, other: string) => ({ ...d, related: linked ? [...new Set([...d.related, other])] : d.related.filter((x) => x !== other) });
  return (await save("documents", edit(a, b.id))) && save("documents", edit(b, a.id));
}

export function LinkDocModal({ doc }: { doc: Doc }) {
  const s = useStore();
  const options = s.documents.filter((x) => x.id !== doc.id && !doc.related.includes(x.id));
  const [r, setR] = useState("");
  const submit = async () => {
    const other = s.documents.find((x) => x.id === r);
    if (!other) { s.toast("Choose a document"); return; }
    if (await setLink(doc, other, true)) { close(); s.toast("Documents linked"); }
  };
  return (
    <>
      <Field label="Document" htmlFor="ld-d"><select className="inp" id="ld-d" value={r} onChange={(e) => setR(e.target.value)}>
        <option value="">Select…</option>{options.map((x) => <option key={x.id} value={x.id}>{x.ref} — {x.title}</option>)}</select></Field>
      <ModalFoot><button className="btn" onClick={close} type="button">Cancel</button><button className="btn pri" onClick={submit} type="button">Link document</button></ModalFoot>
    </>
  );
}

export function AddTagModal({ doc }: { doc: Doc }) {
  const s = useStore();
  const [sel, setSel] = useState<string[]>([]);
  const free = lists(s).TAGS.filter((t) => !doc.tags.includes(t));
  const submit = async () => {
    if (!sel.length) { s.toast("Choose at least one tag"); return; }
    if (await s.save("documents", { ...doc, tags: [...doc.tags, ...sel] })) { close(); s.toast(`${sel.length} tag(s) added`); }
  };
  return (
    <>
      <div className="chips">{free.map((t) => (
        <label key={t} className="chk"><input type="checkbox" checked={sel.includes(t)} onChange={() => setSel(sel.includes(t) ? sel.filter((x) => x !== t) : [...sel, t])} />{t}</label>
      ))}</div>
      <p className="xs muted">Tags describe the subject. To change who can see the document, use the Access tab.</p>
      <ModalFoot><button className="btn" onClick={close} type="button">Cancel</button><button className="btn pri" onClick={submit} type="button">Add tags</button></ModalFoot>
    </>
  );
}

/** A revision is a new document that goes through approval; approving it supersedes this one. */
export function AddRevisionModal({ doc }: { doc: Doc }) {
  const s = useStore();
  const router = useRouter();
  const [file, setFile] = useState<File | null>(null);
  const [v, setV] = useState(nextVersion(doc));
  const [effective, setEffective] = useState(todayIso());
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState(false);
  const submit = async () => {
    if (!file || !note.trim()) { s.toast("Choose the revised file and say what changed"); return; }
    setBusy(true);
    try {
      const res = await api.extract(file);
      const id = nid("D"), by = me(s).name;
      const rev: Doc = {
        ...doc, id, status: "Pending", effective, revisionOf: doc.id, supersededBy: null, related: [], withdrawReason: undefined,
        pages: res.pages, file: res.file, fileType: res.kind, ocr: res.ocr ?? undefined, sample: false, uploadedBy: by, uploadedOn: todayIso(),
        lang: res.pages.some((p) => p.some((b) => isHindi(blockText(b.text)))) ? "hi" : "en",
        versions: [...doc.versions, { v, date: todayIso(), by, note }],
        approvals: [{ step: "Revision submitted for approval", by, date: todayIso(), kind: "", note: `${note} (from ${file.name})` }],
      };
      if (await s.save("documents", rev)) { close(); s.toast("Revision submitted for approval"); router.push(`/library/${id}`); }
    } catch (e) { s.toast((e as Error).message); }
    setBusy(false);
  };
  return (
    <>
      <p className="sm muted">Upload a corrected or updated file for <b>{doc.title}</b>. The current version stays live until the revision is approved.</p>
      <Field label="Revised file" htmlFor="ar-f"><input type="file" className="inp" id="ar-f" accept=".pdf,.docx,.xlsx,.csv,.png,.jpg,.jpeg,.webp,.txt,.md" onChange={(e) => setFile(e.target.files?.[0] ?? null)} /></Field>
      <div className="grid2">
        <Field label="New version number" htmlFor="ar-v"><input className="inp" id="ar-v" value={v} onChange={(e) => setV(e.target.value)} /></Field>
        <Field label="Effective date" htmlFor="ar-e"><input type="date" className="inp" id="ar-e" value={effective} onChange={(e) => setEffective(e.target.value)} /></Field>
      </div>
      <Field label="What changed?" req htmlFor="ar-n"><textarea className="inp" id="ar-n" rows={3} value={note} onChange={(e) => setNote(e.target.value)} placeholder="e.g. Corrected the effective date in clause 7" /></Field>
      <ModalFoot><button className="btn" onClick={close} type="button">Cancel</button><button className="btn pri" onClick={submit} disabled={busy} type="button">{busy ? "Reading the file…" : "Submit revision"}</button></ModalFoot>
    </>
  );
}
