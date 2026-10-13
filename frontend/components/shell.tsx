"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { canApprove, canUpload, isAdmin, me, useStore } from "@/lib/store";
import { daysTo } from "@/lib/util";
import { api } from "@/lib/api";
import type { Notice } from "@/lib/types";
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
export const TITLES: Record<string, string> = { ...Object.fromEntries(NAV.map(([r, l]) => [r, l])), "/profile": "My profile" };

/** Pages only some roles may open — the server enforces the data; this keeps the screens honest. */
export const PAGE_ACCESS: Record<string, (s: ReturnType<typeof useStore.getState>) => boolean> =
  Object.fromEntries(NAV.filter(([, , , vis]) => vis).map(([route, , , vis]) => [route, vis!]));

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
        <Link href="/profile" onClick={onNavigate} className="me-link" title="My profile">
          <span className="av">{u.initials}</span>
          <div style={{ minWidth: 0 }}><b>{u.name}</b><span>{u.title}</span></div>
        </Link>
        <button className="iconbtn" title="Sign out" aria-label="Sign out" onClick={() => useStore.getState().logout()} type="button"><Icon n="logout" s /></button>
      </div>
    </aside>
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
      <Bell />
      <ThemeToggle />
      <Link href="/profile" className="uav" title="My profile" aria-label="My profile">{me(s).initials}</Link>
    </header>
  );
}

/** Notifications, worked out by the server; refreshed on every page change and each minute. */
function Bell() {
  const path = usePathname();
  const router = useRouter();
  const s = useStore();
  const [items, setItems] = useState<Notice[]>([]);
  const [open, setOpen] = useState(false);
  useEffect(() => {
    const get = () => api.notifications().then(setItems).catch(() => {});
    get();
    const t = setInterval(get, 60_000);
    return () => clearInterval(t);
  }, [path, s.documents, s.deadlines]);
  const prefsId = "pf-" + (s.session?.login_id ?? "");
  const seen = new Set(s.prefs.find((p) => p.id === prefsId)?.seen ?? []);
  const fresh = items.filter((n) => !seen.has(n.key));
  const markRead = () => { void s.save("prefs", { id: prefsId, seen: items.map((n) => n.key) }); setOpen(false); };
  return (
    <>
      <button className="iconbtn" style={{ position: "relative" }} aria-label={`Notifications${fresh.length ? ` (${fresh.length} new)` : ""}`} title="Notifications" onClick={() => setOpen((o) => !o)} type="button">
        <Icon n="bell" />{fresh.length > 0 && <span className="dot" />}
      </button>
      {open && (
        <div className="dropdown" role="dialog" aria-label="Notifications">
          <div className="card-h"><h3>Notifications</h3>{items.length > 0 && <button className="btn ghost sm" onClick={markRead} type="button">Mark all read</button>}</div>
          {items.length ? items.map((n) => (
            <button key={n.key} className="li" type="button" onClick={() => { setOpen(false); router.push(n.href); }}>
              <span className="av" style={{ width: 28, height: 28 }}><Icon n="bell" s /></span>
              <div className="main"><b style={{ whiteSpace: "normal", fontWeight: seen.has(n.key) ? 400 : 600 }}>{n.text}</b></div>
            </button>
          )) : <div className="empty sm">You&apos;re all caught up.</div>}
        </div>
      )}
    </>
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
