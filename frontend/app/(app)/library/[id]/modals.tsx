"use client";

import { useState } from "react";
import { lists, me, useStore } from "@/lib/store";
import { fmtD, todayIso } from "@/lib/util";
import type { Doc } from "@/lib/types";
import { Field } from "@/components/ui";

export function EditMetaModal({ doc }: { doc: Doc }) {
  const s = useStore();
  const L = lists(s);
  const { save, closeModal, toast } = useStore.getState();
  const [m, setM] = useState(doc);
  const set = (patch: Partial<Doc>) => setM((p) => ({ ...p, ...patch }));
  const toggleAud = (a: string) => set({ audience: m.audience.includes(a) ? m.audience.filter((x) => x !== a) : [...m.audience, a] });
  const submit = () => {
    const last = m.versions[m.versions.length - 1];
    const versions = [...m.versions, { v: (parseFloat(last.v) + 0.1).toFixed(1), date: todayIso(), by: me(s).name, note: "Metadata edited" }];
    void save("documents", { ...m, versions });
    closeModal(); toast("Metadata saved");
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
      <div className="mft" style={{ position: "static", borderTop: "1px solid var(--line)", marginTop: 4, paddingTop: 12 }}>
        <button className="btn" onClick={closeModal} type="button">Cancel</button>
        <button className="btn pri" onClick={submit} type="button">Save changes</button>
      </div>
    </>
  );
}

export function WithdrawModal({ doc }: { doc: Doc }) {
  const s = useStore();
  const { save, closeModal, toast } = useStore.getState();
  const [reason, setReason] = useState("");
  const [date, setDate] = useState(todayIso());
  const submit = () => {
    if (!reason.trim()) { toast("Add a reason"); return; }
    void save("documents", {
      ...doc, status: "Withdrawn", withdrawReason: reason,
      approvals: [...doc.approvals, { step: "Withdrawn", by: me(s).name, date, kind: "bad", note: reason }],
    });
    closeModal(); toast("Document withdrawn. It will no longer be used in answers.");
  };
  return (
    <>
      <div className="note bad"><p className="sm"><b>{doc.title}</b> will stop being used in AI answers. It stays in the library, marked Withdrawn, for the record.</p></div>
      <Field label="Reason or withdrawing order" req><textarea className="inp" rows={3} value={reason} onChange={(e) => setReason(e.target.value)} placeholder="e.g. Withdrawn vide Office Order SVSU/REG/ADM/2026/120" /></Field>
      <Field label="Withdrawal date"><input type="date" className="inp" value={date} onChange={(e) => setDate(e.target.value)} /></Field>
      <div className="mft" style={{ position: "static", borderTop: "1px solid var(--line)", marginTop: 4, paddingTop: 12 }}>
        <button className="btn" onClick={closeModal} type="button">Cancel</button>
        <button className="btn danger" onClick={submit} type="button">Withdraw document</button>
      </div>
      <span className="xs muted">{fmtD(date)}</span>
    </>
  );
}
