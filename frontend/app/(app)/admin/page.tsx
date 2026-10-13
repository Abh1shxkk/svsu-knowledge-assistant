"use client";

import { useState } from "react";
import { api } from "@/lib/api";
import { aiSettings, lists, roleMatrix, useStore } from "@/lib/store";
import { initials } from "@/lib/util";
import { Icon } from "@/components/icon";
import { Field, Tabs } from "@/components/ui";
import type { AiSettings, Lists } from "@/lib/types";

const ROLES = ["Administrator", "Approver", "Uploader", "Viewer"];
const CAPS: [string, number[]][] = [["Administrator", [1, 1, 1, 1]], ["Approver", [1, 1, 1, 0]], ["Uploader", [1, 1, 0, 0]], ["Viewer", [1, 0, 0, 0]]];

export default function AdminPage() {
  const s = useStore();
  const { save, toast, openModal, closeModal } = useStore.getState();
  const [tab, setTab] = useState("users");
  const L = lists(s);
  const ai = aiSettings(s);
  const matrix = roleMatrix(s);

  const saveLists = (patch: Partial<Lists>) => save("settings", { id: "lists", ...L, ...patch });
  const docsWith = (fn: (d: typeof s.documents[number]) => boolean) => s.documents.filter(fn).length;

  return (
    <div className="wrap">
      <div className="pagehead"><div><h2>Administration</h2><p>Manage people, access, tags and how the assistant answers.</p></div></div>
      <Tabs active={tab} onChange={setTab} tabs={[["users", "Users & roles"], ["access", "Access levels"], ["tags", "Subject tags"], ["depts", "Departments"], ["audit", "Audit log"], ["ai", "AI settings"]]} />

      {tab === "users" && (
        <>
          <div className="card"><div className="card-h"><h3>Users and roles</h3>
            <button className="btn sm pri" onClick={() => openModal({ title: "Add user", body: <AddUser /> })} type="button"><Icon n="plus" s /> Add user</button></div>
            <div className="table-wrap"><table className="t"><thead><tr><th>Name</th><th>Department</th><th>Role</th><th>Last active</th><th>Status</th><th /></tr></thead>
              <tbody>{s.users.map((u) => (
                <tr key={u.id}><td><div className="row" style={{ flexWrap: "nowrap" }}><span className="av">{initials(u.name)}</span><div><b style={{ fontWeight: 500 }}>{u.name}</b><div className="xs muted">{u.email}</div></div></div></td>
                  <td>{u.dept}</td>
                  <td><select className="inp" style={{ width: "auto", padding: "4px 8px" }} value={u.role} onChange={(e) => { void save("users", { ...u, role: e.target.value }); toast(`${u.name} is now ${e.target.value}`); }}>
                    {ROLES.map((r) => <option key={r}>{r}</option>)}</select></td>
                  <td>{u.last}</td><td>{u.active ? <span className="pill ok">Active</span> : <span className="pill mute">Deactivated</span>}</td>
                  <td style={{ textAlign: "right", whiteSpace: "nowrap" }}>
                    {u.login_id && <button className="btn sm" onClick={() => openModal({ title: "Reset password", body: <ResetPassword loginId={u.login_id!} name={u.name} /> })} type="button">Reset password</button>}{" "}
                    <button className="btn sm" onClick={() => { void save("users", { ...u, active: !u.active }); toast(u.active ? `${u.name} deactivated` : `${u.name} reactivated`); }} type="button">{u.active ? "Deactivate" : "Reactivate"}</button></td>
                </tr>
              ))}</tbody></table></div></div>
          <div className="card"><div className="card-h"><h3>What each role can do</h3></div>
            <div className="table-wrap"><table className="t"><thead><tr><th>Role</th><th>Ask &amp; view</th><th>Upload</th><th>Approve</th><th>Manage users</th></tr></thead>
              <tbody>{CAPS.map(([r, a]) => <tr key={r}><td>{r}</td>{a.map((x, i) => <td key={i}>{x ? <span style={{ color: "var(--green)" }}><Icon n="check" s /></span> : <span className="muted">—</span>}</td>)}</tr>)}</tbody></table></div></div>
        </>
      )}

      {tab === "access" && (
        <>
          <div className="note info"><Icon n="alert" s /><p className="sm"><b>Access levels control who can open a document and who the AI may answer from.</b> They are set per document and are independent of subject tags.</p></div>
          <div className="card"><div className="card-h"><h3>Access levels by role</h3><span className="xs muted">Tick to allow</span></div>
            <div className="table-wrap"><table className="t"><thead><tr><th>Role</th>{L.VIS.map((v) => <th key={v}>{v}</th>)}</tr></thead>
              <tbody>{Object.entries(matrix).map(([r, a]) => (
                <tr key={r}><td>{r}</td>{a.map((x, i) => (
                  <td key={i}><input type="checkbox" checked={!!x} disabled={r === "Administrator"} aria-label={`${r} can see ${L.VIS[i]}`}
                    onChange={(e) => { const m = { ...matrix, [r]: a.map((y, j) => (j === i ? (e.target.checked ? 1 : 0) : y)) }; void save("settings", { id: "roles", matrix: m }); toast("Access updated for " + r); }} /></td>
                ))}</tr>
              ))}</tbody></table></div></div>
          <div className="grid2">{L.VIS.map((v) => (
            <div key={v} className="card card-b"><div className="row between"><b>{v}</b><span className="pill mute plain">{docsWith((d) => d.visibility === v)} docs</span></div>
              <p className="sm muted" style={{ marginTop: 6 }}>{L.VIS_DESC[v]}</p></div>
          ))}</div>
        </>
      )}

      {tab === "tags" && (
        <div className="card"><div className="card-h"><h3>Subject tags</h3>
          <AddToList placeholder="New tag name" onAdd={(t) => { if (L.TAGS.includes(t)) { toast("That tag already exists"); return; } void saveLists({ TAGS: [...L.TAGS, t] }); toast("Tag added"); }} /></div>
          {L.TAGS.map((t) => { const n = docsWith((d) => d.tags.includes(t)); return (
            <div key={t} className="li"><Icon n="tag" s /><div className="main"><b>{t}</b><span>{n} document{n === 1 ? "" : "s"}</span></div>
              <button className="btn sm danger" type="button" onClick={() => { if (n) { toast(`“${t}” is used on ${n} document(s). Remove it from those first.`); return; } void saveLists({ TAGS: L.TAGS.filter((x) => x !== t) }); toast("Tag deleted"); }}>Delete</button></div>
          ); })}
        </div>
      )}

      {tab === "depts" && (
        <div className="card"><div className="card-h"><h3>Departments</h3>
          <AddToList placeholder="New department" onAdd={(t) => { if (L.DEPTS.includes(t)) { toast("Already exists"); return; } void saveLists({ DEPTS: [...L.DEPTS, t] }); toast("Department added"); }} /></div>
          {L.DEPTS.map((t) => { const n = docsWith((d) => d.dept === t); return (
            <div key={t} className="li"><Icon n="layers" s /><div className="main"><b>{t}</b><span>{n} documents · {s.users.filter((u) => u.dept === t).length} users</span></div></div>
          ); })}
        </div>
      )}

      {tab === "audit" && <AuditLog />}

      {tab === "ai" && (
        <div className="card"><div className="card-h"><h3>Answer behaviour</h3></div>
          {([
            ["requireCite", "Require a citation for every claim", "Answers without supporting passages are blocked. Always on.", true],
            ["histOnly", "Use superseded documents only for historical questions", "Prevents old rules appearing in answers about current policy."],
            ["showConf", "Show evidence strength label", "Displays the label on each answer."],
            ["logUnans", "Log unanswered questions", "Questions with no supporting record go to Reports for follow-up."],
          ] as [keyof AiSettings, string, string, boolean?][]).map(([k, label, hint, lock]) => (
            <label key={k} className="li" style={{ cursor: "pointer" }}>
              <div className="main"><b>{label}</b><span style={{ whiteSpace: "normal" }}>{hint}</span></div>
              <input type="checkbox" checked={!!ai[k]} disabled={lock} style={{ width: 18, height: 18 }}
                onChange={(e) => { void save("settings", { id: "ai", ...ai, [k]: e.target.checked }); toast("AI settings saved"); }} /></label>
          ))}
          <div className="li"><div className="main"><b>Default answer language</b><span>Used when the user hasn’t chosen one</span></div>
            <select className="inp" style={{ width: "auto" }} value={ai.lang} onChange={(e) => { void save("settings", { id: "ai", ...ai, lang: e.target.value }); toast("AI settings saved"); }}>
              <option value="auto">Same as question</option><option value="en">English</option><option value="hi">हिन्दी</option></select></div>
        </div>
      )}
    </div>
  );

  function AddUser() {
    const [u, setU] = useState({ name: "", email: "", login_id: "", dept: L.DEPTS[0] ?? "", role: "Viewer", password: "" });
    const [busy, setBusy] = useState(false);
    const create = async () => {
      if (!u.name.trim() || !u.login_id.trim() || !u.password) { toast("Name, Login ID and password are required"); return; }
      setBusy(true);
      try {
        await api.createAccount(u);
        await useStore.getState().load();
        closeModal(); toast("Account created. They can sign in with that Login ID and password.");
      } catch (e) { toast((e as Error).message); setBusy(false); }
    };
    return (
      <>
        <Field label="Full name"><input className="inp" value={u.name} onChange={(e) => setU({ ...u, name: e.target.value })} /></Field>
        <div className="grid2">
          <Field label="Login ID" hint="What they type to sign in"><input className="inp" value={u.login_id} onChange={(e) => setU({ ...u, login_id: e.target.value })} placeholder="e.g. their employee ID" /></Field>
          <Field label="University email"><input className="inp" type="email" value={u.email} onChange={(e) => setU({ ...u, email: e.target.value })} /></Field>
          <Field label="Department"><select className="inp" value={u.dept} onChange={(e) => setU({ ...u, dept: e.target.value })}>{L.DEPTS.map((d) => <option key={d}>{d}</option>)}</select></Field>
          <Field label="Role"><select className="inp" value={u.role} onChange={(e) => setU({ ...u, role: e.target.value })}>{ROLES.map((r) => <option key={r}>{r}</option>)}</select></Field>
        </div>
        <Field label="Temporary password" hint="Share it with the user; they should change it later"><input className="inp" type="text" value={u.password} onChange={(e) => setU({ ...u, password: e.target.value })} /></Field>
        <div className="mft" style={{ position: "static", borderTop: "1px solid var(--line)", marginTop: 4, paddingTop: 12 }}>
          <button className="btn" onClick={closeModal} type="button">Cancel</button>
          <button className="btn pri" type="button" disabled={busy} onClick={create}>{busy ? "Creating…" : "Add user"}</button>
        </div>
      </>
    );
  }
}

function ResetPassword({ loginId, name }: { loginId: string; name: string }) {
  const { closeModal, toast } = useStore.getState();
  const [pw, setPw] = useState("");
  const [busy, setBusy] = useState(false);
  const submit = async () => {
    if (!pw) { toast("Enter a new password"); return; }
    setBusy(true);
    try { await api.resetPassword(loginId, pw); closeModal(); toast(`Password reset for ${name}`); }
    catch (e) { toast((e as Error).message); setBusy(false); }
  };
  return (
    <>
      <p className="sm muted">Set a new password for <b>{name}</b> (Login ID {loginId}). Share it with them; they should change it later.</p>
      <Field label="New password"><input className="inp" type="text" value={pw} onChange={(e) => setPw(e.target.value)} autoFocus /></Field>
      <div className="mft" style={{ position: "static", borderTop: "1px solid var(--line)", marginTop: 4, paddingTop: 12 }}>
        <button className="btn" onClick={closeModal} type="button">Cancel</button>
        <button className="btn pri" type="button" disabled={busy} onClick={submit}>{busy ? "Saving…" : "Reset password"}</button>
      </div>
    </>
  );
}

function AddToList({ placeholder, onAdd }: { placeholder: string; onAdd: (t: string) => void }) {
  const [v, setV] = useState("");
  return (
    <form className="row" onSubmit={(e) => { e.preventDefault(); if (v.trim()) { onAdd(v.trim()); setV(""); } }}>
      <input className="inp" value={v} onChange={(e) => setV(e.target.value)} placeholder={placeholder} style={{ width: 190 }} aria-label={placeholder} />
      <button className="btn sm pri" type="submit"><Icon n="plus" s /> Add</button>
    </form>
  );
}

function AuditLog() {
  const s = useStore();
  const [act, setAct] = useState("");
  const acts = [...new Set(s.audit.map((a) => a.act))];
  const rows = s.audit.filter((a) => !act || a.act === act);
  return (
    <div className="card"><div className="card-h"><h3>Audit log</h3>
      <select className="inp" style={{ width: "auto" }} value={act} onChange={(e) => setAct(e.target.value)} aria-label="Filter action">
        <option value="">All actions</option>{acts.map((a) => <option key={a}>{a}</option>)}</select></div>
      <div className="table-wrap"><table className="t"><thead><tr><th>Time</th><th>User</th><th>Action</th><th>Item</th></tr></thead>
        <tbody>{rows.length ? rows.map((a) => (
          <tr key={a.id}><td className="num" style={{ whiteSpace: "nowrap" }}>{a.t}</td><td>{a.who}</td><td><span className="tag">{a.act}</span></td><td>{a.what}</td></tr>
        )) : <tr><td colSpan={4}><div className="empty">No audit entries yet.</div></td></tr>}</tbody></table></div>
    </div>
  );
}
