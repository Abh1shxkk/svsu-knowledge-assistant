"use client";

import { useEffect, useState } from "react";
import { api, type KeyStatus } from "@/lib/api";
import { aiSettings, lists, roleMatrix, useStore } from "@/lib/store";
import { initials } from "@/lib/util";
import { Icon } from "@/components/icon";
import { Field, ModalFoot, Tabs } from "@/components/ui";
import type { AiSettings, Lists, User } from "@/lib/types";

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
  const saveAi = async (patch: Partial<AiSettings>) => { if (await save("settings", { id: "ai", ...ai, ...patch })) toast("AI settings saved"); };
  const self = (u: User) => u.login_id === s.session?.login_id;
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
                  <td><select className="inp" style={{ width: "auto", padding: "4px 8px" }} value={u.role} disabled={self(u)} title={self(u) ? "You can't change your own role" : undefined}
                    onChange={async (e) => { const role = e.target.value; if (await save("users", { ...u, role })) toast(`${u.name} is now ${role}`); }}>
                    {ROLES.map((r) => <option key={r}>{r}</option>)}</select></td>
                  <td>{u.last}</td><td>{u.active ? <span className="pill ok">Active</span> : <span className="pill mute">Deactivated</span>}</td>
                  <td style={{ textAlign: "right", whiteSpace: "nowrap" }}>
                    {u.login_id && <button className="btn sm" onClick={() => openModal({ title: "Reset password", body: <ResetPassword loginId={u.login_id!} name={u.name} /> })} type="button">Reset password</button>}{" "}
                    <button className="btn sm" onClick={() => openModal({ title: "Edit user", body: <EditUser u={u} /> })} type="button">Edit</button>{" "}
                    {!self(u) && <>
                      <button className="btn sm" onClick={async () => { if (await save("users", { ...u, active: !u.active })) toast(u.active ? `${u.name} deactivated` : `${u.name} reactivated`); }} type="button">{u.active ? "Deactivate" : "Reactivate"}</button>{" "}
                      <button className="btn sm danger" onClick={() => openModal({ title: "Delete user?", body: <p>Delete <b>{u.name}</b> ({u.login_id})? They will no longer be able to sign in. Their documents stay. To keep their history, deactivate them instead.</p>,
                        foot: <><button className="btn" onClick={closeModal} type="button">Cancel</button>
                          <button className="btn danger" type="button" onClick={async () => { closeModal(); if (await useStore.getState().remove("users", u.id)) toast(`${u.name} deleted`); }}>Delete user</button></> })} type="button">Delete</button>
                    </>}</td>
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
                    onChange={async (e) => { const m = { ...matrix, [r]: a.map((y, j) => (j === i ? (e.target.checked ? 1 : 0) : y)) }; if (await save("settings", { id: "roles", matrix: m })) toast("Access updated for " + r); }} /></td>
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
          <AddToList placeholder="New tag name" onAdd={async (t) => { if (L.TAGS.includes(t)) { toast("That tag already exists"); return; } if (await saveLists({ TAGS: [...L.TAGS, t] })) toast("Tag added"); }} /></div>
          {L.TAGS.map((t) => { const n = docsWith((d) => d.tags.includes(t)); return (
            <div key={t} className="li"><Icon n="tag" s /><div className="main"><b>{t}</b><span>{n} document{n === 1 ? "" : "s"}</span></div>
              <button className="btn sm" type="button" onClick={() => openModal({ title: "Rename tag", body: <RenameTag tag={t} /> })}>Rename</button>
              <button className="btn sm danger" type="button" onClick={async () => { if (n) { toast(`“${t}” is used on ${n} document(s). Remove it from those or rename the tag instead.`); return; } if (await saveLists({ TAGS: L.TAGS.filter((x) => x !== t) })) toast("Tag deleted"); }}>Delete</button></div>
          ); })}
        </div>
      )}

      {tab === "depts" && (
        <div className="card"><div className="card-h"><h3>Departments</h3>
          <AddToList placeholder="New department" onAdd={async (t) => { if (L.DEPTS.includes(t)) { toast("Already exists"); return; } if (await saveLists({ DEPTS: [...L.DEPTS, t] })) toast("Department added"); }} /></div>
          {L.DEPTS.map((t) => { const n = docsWith((d) => d.dept === t); return (
            <div key={t} className="li"><Icon n="layers" s /><div className="main"><b>{t}</b><span>{n} documents · {s.users.filter((u) => u.dept === t).length} users</span></div></div>
          ); })}
        </div>
      )}

      {tab === "audit" && <AuditLog />}

      {tab === "ai" && <OpenAiKey />}
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
                onChange={(e) => void saveAi({ [k]: e.target.checked })} /></label>
          ))}
          <div className="li"><div className="main"><b>Default answer language</b><span>Used when the user hasn’t chosen one</span></div>
            <select className="inp" style={{ width: "auto" }} value={ai.lang} onChange={(e) => void saveAi({ lang: e.target.value })}>
              <option value="auto">Same as question</option><option value="en">English</option><option value="hi">हिन्दी</option></select></div>
          <div className="li"><div className="main"><b>Passages read per answer</b><span>More gives fuller answers on broad questions, but costs more and takes longer</span></div>
            <select className="inp" style={{ width: "auto" }} value={ai.maxSources} onChange={(e) => void saveAi({ maxSources: Number(e.target.value) })}>
              {[4, 6, 8, 10, 12].map((n) => <option key={n} value={n}>{n}</option>)}</select></div>
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

function EditUser({ u }: { u: User }) {
  const s = useStore();
  const [f, setF] = useState({ name: u.name, email: u.email, dept: u.dept });
  const submit = async () => {
    if (!f.name.trim()) { s.toast("Enter a name"); return; }
    if (await s.save("users", { ...u, ...f, name: f.name.trim() })) { s.closeModal(); s.toast("User updated"); }
  };
  return (
    <>
      <Field label="Full name" htmlFor="eu-n"><input className="inp" id="eu-n" value={f.name} onChange={(e) => setF({ ...f, name: e.target.value })} /></Field>
      <div className="grid2">
        <Field label="University email" htmlFor="eu-e"><input className="inp" id="eu-e" type="email" value={f.email} onChange={(e) => setF({ ...f, email: e.target.value })} /></Field>
        <Field label="Department" htmlFor="eu-d"><select className="inp" id="eu-d" value={f.dept} onChange={(e) => setF({ ...f, dept: e.target.value })}>{lists(s).DEPTS.map((d) => <option key={d}>{d}</option>)}</select></Field>
      </div>
      <p className="xs muted">Login ID {u.login_id} can&apos;t be changed. Change the role in the table.</p>
      <ModalFoot><button className="btn" onClick={s.closeModal} type="button">Cancel</button><button className="btn pri" onClick={submit} type="button">Save</button></ModalFoot>
    </>
  );
}

/** The OpenAI API key the assistant uses. Typed in once; afterwards only its last 4 characters are shown. */
function OpenAiKey() {
  const { toast } = useStore.getState();
  const [status, setStatus] = useState<KeyStatus | null>(null);
  const [key, setKey] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  useEffect(() => { api.keyStatus().then(setStatus).catch((e) => setError((e as Error).message)); }, []);
  const run = async (action: () => Promise<KeyStatus>, done: string) => {
    setBusy(true); setError("");
    try { setStatus(await action()); setKey(""); toast(done); } catch (e) { setError((e as Error).message); }
    setBusy(false);
  };
  const where = !status ? "Checking…"
    : status.source === "admin" ? `Using the key ending ••••${status.last4}, saved by ${status.by} on ${status.at}.`
      : status.source === "env" ? `Using the key from the server's settings file, ending ••••${status.last4}.`
        : "No key is set. The assistant can't answer questions or read uploads until one is added.";
  return (
    <div className="card"><div className="card-h"><h3>OpenAI API key</h3>
      {status && <span className={`pill ${status.source === "none" ? "bad" : "ok"}`}>{status.source === "none" ? "Not set" : "Connected"}</span>}</div>
      <div className="card-b" style={{ display: "flex", flexDirection: "column", gap: 12 }}>
        <p className="sm">{where}</p>
        <form className="row" style={{ flexWrap: "nowrap" }} onSubmit={(e) => { e.preventDefault(); if (key.trim()) void run(() => api.setKey(key), "API key saved. The assistant uses it from now on."); }}>
          <input className="inp" type="password" autoComplete="off" spellCheck={false} value={key} onChange={(e) => setKey(e.target.value)}
            placeholder={status?.source === "none" ? "Paste the API key (sk-…)" : "Paste a new key to replace it"} aria-label="New OpenAI API key" />
          <button className="btn pri" type="submit" disabled={busy || !key.trim()}>{busy ? "Checking…" : "Save key"}</button>
        </form>
        {error && <div className="note bad"><Icon n="alert" s /><p className="sm">{error}</p></div>}
        <p className="xs muted">The key is checked with OpenAI before it is saved, stored on the server only and never shown again.
          Create or revoke keys at platform.openai.com → API keys.</p>
        {status?.source === "admin" && (
          <div><button className="btn sm" type="button" disabled={busy} onClick={() => void run(api.removeKey, "Saved key removed")}>Remove saved key</button>
            <span className="xs muted"> Goes back to the key in the server&apos;s settings file, if there is one.</span></div>
        )}
      </div>
    </div>
  );
}

function RenameTag({ tag }: { tag: string }) {
  const s = useStore();
  const [name, setName] = useState(tag);
  const submit = async () => {
    try { await api.renameTag(tag, name.trim()); s.closeModal(); s.toast("Tag renamed"); void s.load(); }
    catch (e) { s.toast((e as Error).message); }
  };
  return (
    <>
      <Field label="New name" htmlFor="rt-n"><input className="inp" id="rt-n" value={name} onChange={(e) => setName(e.target.value)} autoFocus /></Field>
      <p className="xs muted">All documents with this tag will be updated.</p>
      <ModalFoot><button className="btn" onClick={s.closeModal} type="button">Cancel</button><button className="btn pri" onClick={submit} type="button">Rename</button></ModalFoot>
    </>
  );
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
