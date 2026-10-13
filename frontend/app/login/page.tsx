"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { api, getToken, setToken } from "@/lib/api";
import { useStore } from "@/lib/store";
import { Icon } from "@/components/icon";

export default function LoginPage() {
  const router = useRouter();
  const [checking, setChecking] = useState(true); // already signed in? ask the server first
  const [loginId, setU] = useState("");
  const [password, setP] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  useEffect(() => {
    let cancelled = false;
    const signedIn = getToken()
      ? api.me().then(() => true, () => { setToken(null); return false; }) // expired: clear it
      : Promise.resolve(false);
    signedIn.then((ok) => {
      if (cancelled) return;
      if (ok) router.replace("/");
      else setChecking(false);
    });
    return () => { cancelled = true; };
  }, [router]);

  if (checking) return <div className="app-loading"><div className="spin" style={{ width: 28, height: 28 }} /></div>;

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true); setError("");
    try {
      const { token } = await api.login(loginId.trim(), password);
      setToken(token);
      await useStore.getState().load();
      router.replace("/");
    } catch (err) {
      setError((err as Error).message || "Sign in failed.");
      setBusy(false);
    }
  }

  return (
    <div className="login">
      <form className="login-card card" onSubmit={submit}>
        <div className="login-brand">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/logo.png" alt="SVSU logo" />
          <div><b>SVSU Knowledge Assistant</b><span>Swami Vivekanand Subharti University</span></div>
        </div>
        <h1>Sign in</h1>
        <p className="muted sm">Sign in with the Login ID and password your administrator gave you.</p>
        <div className="fld">
          <label htmlFor="u">Login ID</label>
          <input className="inp" id="u" value={loginId} onChange={(e) => setU(e.target.value)} autoComplete="username" placeholder="e.g. 636325823" required autoFocus />
        </div>
        <div className="fld">
          <label htmlFor="p">Password</label>
          <input className="inp" id="p" type="password" value={password} onChange={(e) => setP(e.target.value)} autoComplete="current-password" required />
        </div>
        {error && <div className="note bad"><Icon n="alert" s /><p className="sm">{error}</p></div>}
        <button className="btn pri" type="submit" disabled={busy} style={{ justifyContent: "center", height: 42 }}>
          {busy ? <span className="spin" /> : <><Icon n="user" s /> Sign in</>}
        </button>
        <p className="xs muted">Accounts are created by an administrator in Administration → Users.</p>
      </form>
    </div>
  );
}
