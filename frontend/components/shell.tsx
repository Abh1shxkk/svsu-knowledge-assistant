"use client";

import { useState } from "react";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { api } from "@/lib/api";
import { canApprove, canUpload, isAdmin, me, useStore } from "@/lib/store";
import { daysTo } from "@/lib/util";
import { Icon } from "./icon";

/** [route, label, icon, visible?] — order and names match the prototype. */
const NAV: [string, string, string, ((s: ReturnType<typeof useStore.getState>) => boolean)?][] = [
  ["/", "Dashboard", "home"],
  ["/ask", "Ask AI", "chat"],
  ["/library", "Document Library", "file"],
  ["/upload", "Upload Documents", "upload", canUpload],
  ["/review", "Review & Approvals", "shield", canApprove],
  ["/collections", "Collections", "layers"],
  ["/deadlines", "Actions & Deadlines", "cal"],
  ["/saved", "Saved Chats & Bookmarks", "bm"],
  ["/reports", "Reports & Feedback", "chart", canApprove],
  ["/admin", "Administration", "sliders", isAdmin],
];
export const TITLES: Record<string, string> = Object.fromEntries(NAV.map(([r, l]) => [r, l]));

const activeRoute = (path: string) =>
  path.startsWith("/library") ? "/library" : path.startsWith("/collections") ? "/collections" : "/" + (path.split("/")[1] ?? "");

export function Sidebar({ onNavigate }: { onNavigate?: () => void }) {
  const s = useStore();
  const active = activeRoute(usePathname());
  const pending = s.documents.filter((d) => d.status === "Pending").length;
  const soon = s.deadlines.filter((x) => !x.done && daysTo(x.date) >= 0 && daysTo(x.date) <= 14).length;
  const u = me(s);

  return (
    <aside className="side" aria-label="Main navigation">
      <div className="brand">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src="/logo.png" alt="SVSU logo" />
        <div><b>SVSU Assistant</b><span>Records &amp; policies</span></div>
      </div>
      <nav className="nav">
        {NAV.filter(([, , , vis]) => !vis || vis(s)).map(([route, label, icon]) => {
          const badge = route === "/review" ? pending : route === "/deadlines" ? soon : 0;
          return (
            <Link key={route} href={route} title={label} onClick={onNavigate} className={active === route ? "on" : ""}>
              <Icon n={icon} /><span className="lbl">{label}</span>
              {badge > 0 && <span className="badge">{badge}</span>}
            </Link>
          );
        })}
      </nav>
      <div className="me">
        <span className="av">{u.initials}</span>
        <div style={{ minWidth: 0 }}><b>{u.name}</b><span>{u.title}</span></div>
        <button className="iconbtn" title="Change password" aria-label="Change password" type="button"
          onClick={() => useStore.getState().openModal({ title: "Change password", body: <ChangePassword /> })}><Icon n="key" s /></button>
        <button className="iconbtn" title="Sign out" aria-label="Sign out" onClick={() => useStore.getState().logout()} type="button"><Icon n="logout" s /></button>
      </div>
    </aside>
  );
}

function ChangePassword() {
  const { closeModal, toast } = useStore.getState();
  const [f, setF] = useState({ current: "", next: "", again: "" });
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (f.next !== f.again) { setError("The new passwords don't match."); return; }
    setBusy(true); setError("");
    try { await api.changePassword(f.current, f.next); closeModal(); toast("Password changed"); }
    catch (err) { setError((err as Error).message); setBusy(false); }
  };
  const field = (k: keyof typeof f, label: string, auto: string) => (
    <div className="fld"><label htmlFor={`pw-${k}`}>{label}</label>
      <input className="inp" id={`pw-${k}`} type="password" autoComplete={auto} required value={f[k]}
        onChange={(e) => setF({ ...f, [k]: e.target.value })} /></div>
  );
  return (
    <form onSubmit={submit} style={{ display: "flex", flexDirection: "column", gap: 12 }}>
      {field("current", "Current password", "current-password")}
      {field("next", "New password", "new-password")}
      {field("again", "Repeat new password", "new-password")}
      <span className="xs muted">At least 10 characters, mixing letters with numbers or symbols.</span>
      {error && <div className="note bad"><Icon n="alert" s /><p className="sm">{error}</p></div>}
      <div className="row" style={{ justifyContent: "flex-end" }}>
        <button className="btn" type="button" onClick={closeModal}>Cancel</button>
        <button className="btn pri" type="submit" disabled={busy}>{busy ? "Saving…" : "Change password"}</button>
      </div>
    </form>
  );
}

function ThemeToggle() {
  const [dark, setDark] = useState(() => typeof document !== "undefined" && document.documentElement.dataset.theme === "dark");
  const flip = () => {
    const t = dark ? "light" : "dark";
    document.documentElement.setAttribute("data-theme", t);
    try { localStorage.setItem("svsu_theme", t); } catch { /* private mode */ }
    setDark(!dark);
  };
  return (
    <button className="iconbtn" onClick={flip} type="button" aria-label={dark ? "Switch to light mode" : "Switch to dark mode"} title={dark ? "Light mode" : "Dark mode"}>
      <Icon n={dark ? "sun" : "moon"} />
    </button>
  );
}

export function Topbar({ collapsed, onToggle }: { collapsed: boolean; onToggle: () => void }) {
  const path = usePathname();
  const router = useRouter();
  const s = useStore();
  const [q, setQ] = useState("");
  return (
    <header className="top">
      <button className="iconbtn" onClick={onToggle} type="button" aria-label={collapsed ? "Expand sidebar" : "Collapse sidebar"} title={collapsed ? "Expand sidebar" : "Collapse sidebar"}>
        <Icon n={collapsed ? "panelOpen" : "panelClose"} />
      </button>
      <h1>{TITLES[activeRoute(path)] ?? ""}</h1>
      <form className="gsearch" onSubmit={(e) => { e.preventDefault(); router.push(`/library?q=${encodeURIComponent(q)}`); setQ(""); }}>
        <Icon n="search" s />
        <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Search documents, reference numbers…" aria-label="Search documents" />
      </form>
      {path !== "/ask" && <Link className="btn pri" href="/ask"><Icon n="spark" s /><span>Ask AI</span></Link>}
      <ThemeToggle />
      <span className="uav" title={me(s).name}>{me(s).initials}</span>
    </header>
  );
}

export function Toasts() {
  const toasts = useStore((s) => s.toasts);
  return <div className="toasts">{toasts.map((t) => <div key={t.id} className="toast">{t.msg}</div>)}</div>;
}

export function ModalHost() {
  const modal = useStore((s) => s.modal);
  const close = useStore((s) => s.closeModal);
  if (!modal) return null;
  return (
    <div className={`ov ${modal.drawer ? "dr" : ""}`} onClick={(e) => { if (e.target === e.currentTarget) close(); }}>
      <div className={`modal ${modal.wide ? "wide" : ""}`} role="dialog" aria-modal="true" aria-label={modal.title}>
        <div className="mhd"><h3>{modal.title}</h3>
          <button className="iconbtn" aria-label="Close" onClick={close} type="button"><Icon n="x" /></button></div>
        <div className="mbd">{modal.body}</div>
        {modal.foot && <div className="mft">{modal.foot}</div>}
      </div>
    </div>
  );
}
