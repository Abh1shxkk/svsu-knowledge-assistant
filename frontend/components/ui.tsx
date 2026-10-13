"use client";

import Link from "next/link";
import type { ReactNode } from "react";
import type { FileKind, Status } from "@/lib/types";
import { daysTo, plural } from "@/lib/util";
import { Icon } from "./icon";

export function DateBox({ date }: { date: string }) {
  const d = new Date(date + "T00:00:00");
  return <div className="datebox"><i>{d.toLocaleDateString("en-IN", { month: "short" })}</i><b>{d.getDate()}</b></div>;
}
export function Due({ date, done }: { date: string; done?: boolean }) {
  if (done) return <span className="due done">Completed</span>;
  const n = daysTo(date);
  if (n < 0) return <span className="due over">{plural(-n, "day")} overdue</span>;
  if (n === 0) return <span className="due over">Due today</span>;
  if (n <= 7) return <span className="due soon">In {plural(n, "day")}</span>;
  return <span className="due later">In {n} days</span>;
}

const STATUS_PILL: Record<string, string> = {
  Active: "ok", Pending: "warn", "Changes requested": "warn", Draft: "mute",
  Superseded: "mute2", Withdrawn: "bad", Expired: "mute", Rejected: "bad",
};
export const Pill = ({ status, plain = false }: { status: Status | string; plain?: boolean }) => (
  <span className={`pill ${plain ? "plain " : ""}${STATUS_PILL[status] ?? "mute"}`}>{status}</span>
);

const FT: Record<FileKind, string> = { pdf: "PDF", scan: "SCAN", docx: "DOCX", xlsx: "XLSX", img: "IMG", txt: "TXT" };
export const Ft = ({ k }: { k: FileKind }) => <span className={`ft ft-${k}`}>{FT[k] ?? "FILE"}</span>;

export const Tags = ({ tags }: { tags: string[] }) => (
  <div className="tags">{tags.map((t) => <span key={t} className="tag">{t}</span>)}</div>
);

export const Empty = ({ children }: { children: ReactNode }) => <div className="empty">{children}</div>;

export const Note = ({ kind, children }: { kind: "warn" | "bad" | "info" | "ok"; children: ReactNode }) => (
  <div className={`note ${kind}`}>
    <Icon n={kind === "bad" ? "ban" : kind === "ok" ? "check" : kind === "info" ? "alert" : "alert"} s />
    <div>{children}</div>
  </div>
);

/** Page header: title, subtitle and optional right-side actions. */
export const PageHead = ({ title, sub, actions, lang }: { title: string; sub?: string; actions?: ReactNode; lang?: string }) => (
  <div className="pagehead">
    <div><h2 lang={lang}>{title}</h2>{sub && <p>{sub}</p>}</div>
    {actions && <div className="row">{actions}</div>}
  </div>
);

export const Tabs = ({ tabs, active, onChange }: {
  tabs: [key: string, label: string, count?: number][]; active: string; onChange: (k: string) => void;
}) => (
  <div className="tabs" role="tablist">
    {tabs.map(([k, label, count]) => (
      <button key={k} role="tab" className={k === active ? "on" : ""} onClick={() => onChange(k)}>
        {label}{count !== undefined && <span className="c">{count}</span>}
      </button>
    ))}
  </div>
);

/** A labelled form field. */
export const Field = ({ label, req, hint, error, children, htmlFor }: {
  label?: string; req?: boolean; hint?: string; error?: string; children: ReactNode; htmlFor?: string;
}) => (
  <div className="fld">
    {label && <label htmlFor={htmlFor}>{label}{req && <i> *</i>}</label>}
    {children}
    {error ? <span className="errmsg">{error}</span> : hint ? <span className="hint">{hint}</span> : null}
  </div>
);

/** Clickable list row (icon · title · meta · trailing). */
export const Row = ({ href, onClick, lead, title, meta, trail, lang }: {
  href?: string; onClick?: () => void; lead?: ReactNode; title: ReactNode; meta?: ReactNode; trail?: ReactNode; lang?: string;
}) => {
  const inner = (
    <>
      {lead}
      <div className="main"><b lang={lang}>{title}</b>{meta && <span>{meta}</span>}</div>
      {trail}
    </>
  );
  if (href) return <Link href={href} className="li">{inner}</Link>;
  return <button className="li" onClick={onClick} type="button">{inner}</button>;
};

export const Avatar = ({ text, size = 32 }: { text: string; size?: number }) => (
  <span className="av" style={{ width: size, height: size }}>{text}</span>
);
