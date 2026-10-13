"use client";

import { useState } from "react";
import { api } from "@/lib/api";
import { me, useStore } from "@/lib/store";
import { Icon } from "@/components/icon";
import { Field } from "@/components/ui";

const ROLE_HELP: Record<string, string> = {
  Administrator: "Everything, including users, roles, access levels and settings.",
  Approver: "Upload, approve or reject documents, and see reports.",
  Uploader: "Upload documents and submit them for approval.",
  Viewer: "Ask questions and read the documents you're allowed to see.",
};

export default function ProfilePage() {
  const s = useStore();
  const u = s.session;
  const isTestAdmin = !!u?.dev;

  return (
    <div className="wrap" style={{ maxWidth: 820 }}>
      <div className="pagehead"><div><h2>My profile</h2><p>Your details, password and how the app looks for you.</p></div></div>

      <div className="card">
        <div className="card-h"><h3>Your details</h3></div>
        <div className="card-b" style={{ display: "flex", flexDirection: "column", gap: 18 }}>
          <div className="row" style={{ gap: 14 }}>
            <span className="av" style={{ width: 56, height: 56, borderRadius: 18, fontSize: 18 }}>{me(s).initials}</span>
            <div><b style={{ fontSize: 16 }}>{me(s).name}</b><div className="sm muted">{u?.role} · Login ID {u?.login_id}</div></div>
          </div>
          {isTestAdmin
            ? <div className="note warn"><Icon n="alert" s /><p className="sm">You&apos;re signed in as the local test admin, which has no profile. Create your own account to edit details here.</p></div>
            : <DetailsForm key={u?.login_id} />}
          <dl className="kv" style={{ gridTemplateColumns: "140px 1fr" }}>
            <dt>Login ID</dt><dd className="mono">{u?.login_id}</dd>
            <dt>Department</dt><dd>{u?.dept || "—"}</dd>
            <dt>Role</dt><dd>{u?.role} <span className="muted sm">· {ROLE_HELP[u?.role ?? "Viewer"]}</span></dd>
          </dl>
          <p className="xs muted">Login ID, department and role decide what you can see, so only an administrator can change them.</p>
        </div>
      </div>

      {!isTestAdmin && (
        <div className="card">
          <div className="card-h"><h3>Password</h3></div>
          <div className="card-b"><PasswordForm /></div>
        </div>
      )}

      <div className="card">
        <div className="card-h"><h3>Appearance</h3></div>
        <div className="card-b row between">
          <span className="sm">Theme</span>
          <ThemeChoice />
        </div>
      </div>
    </div>
  );
}

function DetailsForm() {
  const s = useStore();
  const { set, toast } = useStore.getState();
  const [f, setF] = useState({ name: s.session?.name ?? "", email: s.session?.email ?? "" });
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const save = async (e: React.FormEvent) => {
    e.preventDefault();
    setBusy(true); setError("");
    try {
      const updated = await api.updateProfile(f);
      set({ session: { ...s.session!, ...updated } });
      toast("Profile saved");
    } catch (err) { setError((err as Error).message); }
    setBusy(false);
  };
  return (
    <form onSubmit={save} style={{ display: "flex", flexDirection: "column", gap: 12 }}>
      <div className="grid2">
        <Field label="Full name" htmlFor="pf-name"><input id="pf-name" className="inp" value={f.name} onChange={(e) => setF({ ...f, name: e.target.value })} required /></Field>
        <Field label="Email" htmlFor="pf-email"><input id="pf-email" className="inp" type="email" value={f.email} onChange={(e) => setF({ ...f, email: e.target.value })} /></Field>
      </div>
      {error && <div className="note bad"><Icon n="alert" s /><p className="sm">{error}</p></div>}
      <div className="row" style={{ justifyContent: "flex-end" }}><button className="btn pri" type="submit" disabled={busy}>{busy ? "Saving…" : "Save details"}</button></div>
    </form>
  );
}

function PasswordForm() {
  const { toast } = useStore.getState();
  const blank = { current: "", next: "", again: "" };
  const [f, setF] = useState(blank);
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (f.next !== f.again) { setError("The new passwords don't match."); return; }
    setBusy(true); setError("");
    try { await api.changePassword(f.current, f.next); setF(blank); toast("Password changed"); }
    catch (err) { setError((err as Error).message); }
    setBusy(false);
  };
  const field = (k: keyof typeof f, label: string, auto: string) => (
    <Field label={label} htmlFor={`pw-${k}`}>
      <input className="inp" id={`pw-${k}`} type="password" autoComplete={auto} required value={f[k]} onChange={(e) => setF({ ...f, [k]: e.target.value })} />
    </Field>
  );
  return (
    <form onSubmit={submit} style={{ display: "flex", flexDirection: "column", gap: 12 }}>
      <div className="grid3">
        {field("current", "Current password", "current-password")}
        {field("next", "New password", "new-password")}
        {field("again", "Repeat new password", "new-password")}
      </div>
      <span className="xs muted">At least 10 characters, mixing letters with numbers or symbols.</span>
      {error && <div className="note bad"><Icon n="alert" s /><p className="sm">{error}</p></div>}
      <div className="row" style={{ justifyContent: "flex-end" }}><button className="btn pri" type="submit" disabled={busy}>{busy ? "Saving…" : "Change password"}</button></div>
    </form>
  );
}

function ThemeChoice() {
  const [theme, setTheme] = useState(() => (typeof document !== "undefined" && document.documentElement.dataset.theme) || "light");
  const pick = (t: string) => {
    document.documentElement.setAttribute("data-theme", t);
    try { localStorage.setItem("svsu_theme", t); } catch { /* private mode */ }
    setTheme(t);
  };
  return (
    <div className="seg">
      {[["light", "Light", "sun"], ["dark", "Dark", "moon"]].map(([t, label, icon]) => (
        <button key={t} type="button" className={theme === t ? "on" : ""} onClick={() => pick(t)}><Icon n={icon} s /> {label}</button>
      ))}
    </div>
  );
}
