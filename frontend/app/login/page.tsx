"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { api, getToken, setToken } from "@/lib/api";
import { useStore } from "@/lib/store";
import { Icon } from "@/components/icon";
import { SetupMfa } from "@/components/mfa";

export default function LoginPage() {
  const router = useRouter();
  const [checking, setChecking] = useState(true); // already signed in? ask the server first
  const [loginId, setU] = useState("");
  const [password, setP] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [step, setStep] = useState<{ mfa?: "code" | "setup"; ticket?: string }>({});  // after the password
  const [code, setCode] = useState("");

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

  async function enter(token: string) {
    setToken(token);
    await useStore.getState().load();
    router.replace("/");
  }

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true); setError("");
    try {
      if (step.ticket) return await enter((await api.loginMfa(step.ticket, code)).token);
      const r = await api.login(loginId.trim(), password);
      if (r.token) return await enter(r.token);
      setStep({ mfa: r.mfa, ticket: r.ticket });
    } catch (err) {
      setError((err as Error).message || "Sign in failed.");
    }
    setBusy(false);
  }

  if (step.mfa === "setup") return frame(
    <div className="login-card">
      <h1>Set up two-step verification</h1>
      <p className="muted sm">Your role needs a code from your phone as well as your password. This takes a minute, once.</p>
      <SetupMfa start={() => api.loginMfaSetup(step.ticket!)}
        confirm={async (c) => { const r = await api.loginMfa(step.ticket!, c); setToken(r.token); return r.recovery ?? []; }}
        onDone={() => void enter(getToken()!)} />
    </div>,
  );

  return frame(
    <form className="login-card" onSubmit={submit}>
      <div className="login-brand">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src="/logo.png" alt="SVSU logo" />
        <div><b>SVSU Knowledge Assistant</b><span>Swami Vivekanand Subharti University</span></div>
      </div>
      {step.mfa === "code" ? <>
        <h1>Two-step verification</h1>
        <p className="muted sm">Enter the 6-digit code from your authenticator app. Lost your phone? Enter one of your recovery codes instead.</p>
        <div className="fld">
          <label htmlFor="code">Code</label>
          <input className="inp mono" id="code" value={code} onChange={(e) => setCode(e.target.value)} inputMode="numeric" autoComplete="one-time-code" required autoFocus />
        </div>
      </> : <>
        <h1>Sign in</h1>
        <p className="muted sm">Use the Login ID and password your administrator gave you.</p>
        <div className="fld">
          <label htmlFor="u">Login ID</label>
          <input className="inp" id="u" value={loginId} onChange={(e) => setU(e.target.value)} autoComplete="username" placeholder="e.g. 636325823" required autoFocus />
        </div>
        <div className="fld">
          <label htmlFor="p">Password</label>
          <input className="inp" id="p" type="password" value={password} onChange={(e) => setP(e.target.value)} autoComplete="current-password" required />
        </div>
      </>}
      {error && <div className="note bad"><Icon n="alert" s /><p className="sm">{error}</p></div>}
      <button className="btn pri" type="submit" disabled={busy}>
        {busy ? <span className="spin" /> : step.mfa ? <><Icon n="check" s /> Verify</> : <><Icon n="user" s /> Sign in</>}
      </button>
      {step.mfa
        ? <button className="btn ghost sm" type="button" onClick={() => { setStep({}); setCode(""); setError(""); }}>Back</button>
        : <p className="xs muted">No account? Ask an administrator to add you in Administration → Users.</p>}
    </form>,
  );
}

function frame(card: React.ReactNode) {
  return (
    <div className="login">
      <aside className="login-art" aria-label="About the assistant">
        <Graffiti />
        <div className="login-art-top">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/logo.png" alt="" />
          <div><b>Swami Vivekanand Subharti University</b><span>Subhartipuram, Meerut · Uttar Pradesh</span></div>
        </div>
        <div className="login-art-mid">
          <h2>SVSU Knowledge Assistant</h2>
          <p lang="hi">विश्वविद्यालय के पत्र, सूचनाएँ और नीतियाँ — एक जगह, प्रमाण सहित।</p>
          <ul>
            <li><Icon n="file" s /> Answers only from the university&apos;s own letters, notices and policies</li>
            <li><Icon n="check" s /> Every answer cites the exact page and passage</li>
            <li><Icon n="globe" s /> Ask in Hindi or English</li>
          </ul>
        </div>
        <p className="login-art-foot">For staff of Swami Vivekanand Subharti University</p>
      </aside>
      <main className="login-side">{card}</main>
    </div>
  );
}

/** Spray-tag style outlined words — Subharti, knowledge and learning in Hindi and English. Decorative only. */
function Graffiti() {
  // Kept to the top and bottom bands and the right edge, clear of the text in the middle.
  const tags: [string, number, number, number, number, string?][] = [  // text, x, y, size, rotate, lang
    ["सुभारती", 150, 250, 140, -6, "hi"], ["SVSU", 400, 120, 110, 8], ["ज्ञान", 480, 470, 100, -10, "hi"],
    ["MEERUT", 600, 560, 56, 84], ["विद्या", -10, 870, 120, 6, "hi"], ["knowledge", 250, 950, 84, -4], ["सत्य", 470, 800, 100, 10, "hi"],
  ];
  return (
    <svg className="login-graffiti" viewBox="0 0 640 960" preserveAspectRatio="xMidYMid slice" aria-hidden>
      {tags.map(([t, x, y, size, r, lang], i) => (
        <text key={i} x={x} y={y} fontSize={size} transform={`rotate(${r} ${x} ${y})`} lang={lang} className={i % 3 === 0 ? "fill" : ""}>{t}</text>
      ))}
      <circle cx="580" cy="300" r="60" /><circle cx="60" cy="900" r="110" />
      <path d="M-20 280 C 160 230, 300 330, 660 250" /><path d="M-20 720 C 200 690, 360 780, 660 700" />
    </svg>
  );
}
