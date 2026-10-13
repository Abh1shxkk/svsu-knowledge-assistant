"use client";

import { useEffect, useState } from "react";
import { usePathname, useRouter } from "next/navigation";
import { useStore } from "@/lib/store";
import { getToken } from "@/lib/api";
import { ModalHost, Sidebar, Toasts, Topbar } from "@/components/shell";
import { Viewer } from "@/components/viewer";

const COLLAPSE_KEY = "svsu_sidebar_collapsed";

export default function AppLayout({ children }: { children: React.ReactNode }) {
  const router = useRouter();
  const path = usePathname();
  const { loaded, error, load } = useStore();
  const [sideOpen, setSideOpen] = useState(false); // phones: sidebar slides over the page
  const [collapsed, setCollapsed] = useState(() => {
    try { return localStorage.getItem(COLLAPSE_KEY) === "1"; } catch { return false; }
  });

  useEffect(() => {
    if (!getToken()) { router.replace("/login"); return; }
    void load();
  }, [load, router]);

  useEffect(() => { if (error === "no-session") router.replace("/login"); }, [error, router]);

  const toggle = () => {
    if (matchMedia("(max-width: 860px)").matches) { setSideOpen((o) => !o); return; }
    setCollapsed((c) => {
      try { localStorage.setItem(COLLAPSE_KEY, c ? "0" : "1"); } catch { /* private mode */ }
      return !c;
    });
  };

  if (!loaded) {
    return (
      <div className="app-loading">
        {error && error !== "no-session"
          ? <div className="card card-b">Couldn&apos;t reach the server. Is the API running? <span className="muted">{error}</span></div>
          : <div className="spin" style={{ width: 28, height: 28 }} />}
      </div>
    );
  }

  return (
    <div className={`app ${collapsed ? "collapsed" : ""} ${sideOpen ? "sideopen" : ""}`}>
      <Sidebar onNavigate={() => setSideOpen(false)} />
      <div className="scrim" onClick={() => setSideOpen(false)} />
      <div className="mainwrap">
        <Topbar collapsed={collapsed} onToggle={toggle} />
        <div className="workspace">
          <main className={`content ${path === "/ask" ? "chatmode" : ""}`}>{children}</main>
          <Viewer />
        </div>
      </div>
      <ModalHost />
      <Toasts />
    </div>
  );
}
