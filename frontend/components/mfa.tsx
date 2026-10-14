"use client";

import { useEffect, useState } from "react";
import type { MfaStart } from "@/lib/api";
import { Icon } from "./icon";

/** Setting up two-step verification: scan the QR code, type the first code, keep the recovery codes.
 *  Used on the profile page and during sign-in when a person's role requires it. */
export function SetupMfa({ start, confirm, onDone }: {
  start: () => Promise<MfaStart>; confirm: (code: string) => Promise<string[]>; onDone: () => void;
}) {
  const [setup, setSetup] = useState<MfaStart | null>(null);
  const [code, setCode] = useState("");
  const [codes, setCodes] = useState<string[] | null>(null);
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  useEffect(() => {  // once: each call makes a new key
    let cancelled = false;
    start().then((s) => { if (!cancelled) setSetup(s); }, (e) => setError((e as Error).message));
    return () => { cancelled = true; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  if (codes) return <RecoveryCodes codes={codes} onDone={onDone} />;
  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setBusy(true); setError("");
    try { setCodes(await confirm(code.trim())); } catch (err) { setError((err as Error).message); }
    setBusy(false);
  };
  return (
    <form className="mfa-setup" onSubmit={submit}>
      <ol className="sm">
        <li>Open an authenticator app on your phone (Google Authenticator, Microsoft Authenticator or similar).</li>
        <li>Scan this code, or type the key by hand.</li>
      </ol>
      {setup ? <div className="row" style={{ gap: 16, alignItems: "center" }}>
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img className="mfa-qr" src={setup.qr} alt="QR code for your authenticator app" width={164} height={164} />
        <div className="sm"><span className="muted">Key</span><div className="mono mfa-key">{setup.secret.match(/.{1,4}/g)?.join(" ")}</div></div>
      </div> : !error && <span className="spin" />}
      <label className="sm" htmlFor="mfa-first">3. Enter the 6-digit code the app shows</label>
      <div className="row" style={{ gap: 8 }}>
        <input id="mfa-first" className="inp mono" inputMode="numeric" autoComplete="one-time-code" maxLength={6} value={code}
          onChange={(e) => setCode(e.target.value.replace(/\D/g, ""))} required style={{ maxWidth: 140 }} />
        <button className="btn pri" type="submit" disabled={busy || !setup || code.length !== 6}>{busy ? <span className="spin" /> : "Turn on"}</button>
      </div>
      {error && <div className="note bad"><Icon n="alert" s /><p className="sm">{error}</p></div>}
    </form>
  );
}

export function RecoveryCodes({ codes, onDone }: { codes: string[]; onDone: () => void }) {
  return (
    <div className="mfa-setup">
      <div className="note ok"><Icon n="check" s /><p className="sm"><b>Two-step verification is on.</b> Keep these recovery codes somewhere safe. Each one works once, if you lose your phone. They won&apos;t be shown again.</p></div>
      <div className="mfa-codes mono">{codes.map((c) => <span key={c}>{c}</span>)}</div>
      <div className="row" style={{ gap: 8 }}>
        <button className="btn" type="button" onClick={() => navigator.clipboard?.writeText(codes.join("\n"))}><Icon n="copy" s /> Copy</button>
        <button className="btn pri" type="button" onClick={onDone}>I&apos;ve saved them</button>
      </div>
    </div>
  );
}
