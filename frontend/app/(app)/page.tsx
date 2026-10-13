"use client";

import { useState } from "react";
import Link from "next/link";
import { canApprove, canUpload, chatGroup, getDoc, me, permitted, useStore } from "@/lib/store";
import { daysTo, fmtD, isHindi, plural, todayIso } from "@/lib/util";
import { Icon } from "@/components/icon";
import { KIND_INFO } from "@/components/answer";
import { AreaChart, BarChart, TickGauge } from "@/components/charts";
import { Ft, Pill, Row } from "@/components/ui";
import type { Deadline, Msg } from "@/lib/types";

const greeting = () => {
  const h = new Date().getHours();
  return h < 12 ? "Good morning" : h < 17 ? "Good afternoon" : "Good evening";
};
const monthLabel = (d: Date) => d.toLocaleDateString("en-IN", { month: "short" });
const isoOf = (d: Date) => d.toLocaleDateString("en-CA");

export default function Dashboard() {
  const s = useStore();
  const ds = permitted(s);
  const today = todayIso();
  const active = ds.filter((d) => d.status === "Active").length;
  const pending = ds.filter((d) => d.status === "Pending").length;
  const history = ds.filter((d) => ["Superseded", "Withdrawn"].includes(d.status)).length;
  const upcoming = s.deadlines.filter((x) => !x.done && daysTo(x.date) >= 0).sort((a, b) => a.date.localeCompare(b.date));
  const openUnans = s.unanswered.filter((u) => u.status !== "Resolved");

  // Uploads per month, last 6 months.
  const months = Array.from({ length: 6 }, (_, i) => { const d = new Date(); d.setDate(1); d.setMonth(d.getMonth() - 5 + i); return d; });
  const uploads = months.map((m) => ({ label: monthLabel(m), value: ds.filter((d) => d.uploadedOn.slice(0, 7) === isoOf(m).slice(0, 7)).length }));

  // Documents per subject, top 7.
  const tagCount: Record<string, number> = {};
  ds.forEach((d) => d.tags.forEach((t) => { tagCount[t] = (tagCount[t] ?? 0) + 1; }));
  const subjects = Object.entries(tagCount).sort((a, b) => b[1] - a[1]).slice(0, 7).map(([label, value]) => ({ label: label.slice(0, 5), value }));

  // Deadlines due per week, next 6 weeks.
  const weeks = Array.from({ length: 6 }, (_, i) => ({
    label: i === 0 ? "Now" : `+${i}w`,
    value: upcoming.filter((x) => Math.floor(daysTo(x.date) / 7) === i).length,
  }));

  return (
    <div className="wrap">
      <div className="dash">
        <div className="dash-main">
          <div className="hero">
            <div>
              <h2>{greeting()}, {me(s).name.split(" ")[0]}</h2>
              <p>{fmtD(today)} · {plural(ds.length, "document")} you can open, across {plural(new Set(ds.map((d) => d.dept)).size, "department")}.</p>
            </div>
            <div className="row">
              {canUpload(s) && <Link className="btn" href="/upload"><Icon n="upload" s /> Upload</Link>}
              <Link className="btn pri" href="/ask"><Icon n="spark" s /> Ask a question</Link>
            </div>
          </div>

          <div className="statrow">
            <Stat href="/library" label="Total documents" value={ds.length} />
            <Stat href="/library?status=Active" label="Active" value={active} />
            <Stat href={canApprove(s) ? "/review" : "/library?status=Pending"} label="Pending approvals" value={pending} />
            <Stat href="/library?status=Superseded" label="Superseded or withdrawn" value={history} />
          </div>

          <div className="sechead"><h3>Overview</h3><Link className="btn ghost sm" href="/reports">Reports <Icon n="cr" s /></Link></div>
          <div className="tiles">
            <Tile title="Uploads" chip="Last 6 months" value={uploads[5].value} sub="this month">
              <AreaChart points={uploads} caption="Documents uploaded per month" />
            </Tile>
            <Tile title="Documents by subject" chip="All time" value={Object.keys(tagCount).length} sub="subjects">
              <BarChart points={subjects} caption="Documents per subject" />
            </Tile>
            <Tile title="Upcoming deadlines" chip="Next 6 weeks" value={upcoming.length} sub={`${upcoming.filter((x) => daysTo(x.date) <= 7).length} this week`}>
              <BarChart points={weeks} caption="Deadlines due per week" thin />
            </Tile>
            <Tile title="Documents in force" chip="Active share">
              <TickGauge percent={ds.length ? Math.round((active / ds.length) * 100) : 0} label={`${active} of ${ds.length} active`} />
            </Tile>
          </div>

          <div className="lists2">
            <div className="card">
              <div className="card-h"><h3>Recent documents</h3><Link className="btn ghost sm" href="/library">Library <Icon n="cr" s /></Link></div>
              {ds.length ? [...ds].sort((a, b) => b.uploadedOn.localeCompare(a.uploadedOn)).slice(0, 5).map((d) => (
                <Row key={d.id} href={`/library/${d.id}`} lead={<Ft k={d.fileType} />} lang={d.lang}
                  title={d.title} meta={`${fmtD(d.uploadedOn)} · ${d.uploadedBy}`} trail={<Pill status={d.status} />} />
              )) : <div className="empty">No documents yet.</div>}
            </div>
            <div className="card">
              <div className="card-h"><h3>Recent conversations</h3><Link className="btn ghost sm" href="/saved">Saved <Icon n="cr" s /></Link></div>
              {s.chats.length ? s.chats.slice(0, 5).map((c) => {
                const label = lastLabel(c.msgs);
                return (
                  <Row key={c.id} href={`/ask?c=${c.id}`} lead={<span className="av" style={{ width: 30, height: 30, borderRadius: 10 }}><Icon n="chat" s /></span>}
                    title={c.title} meta={`${chatGroup(c)} · ${plural(Math.ceil(c.msgs.length / 2), "question")}`}
                    trail={label ? <span className={`pill plain ${KIND_INFO[label] ?? "mute"}`}>{label}</span> : undefined} />
                );
              }) : <div className="empty">No conversations yet. Ask a question to start.</div>}
            </div>
          </div>

          <div className="card">
            <div className="card-h"><h3>Questions the records could not answer</h3><span className="xs muted">{openUnans.length} open</span></div>
            {openUnans.length ? openUnans.slice(0, 5).map((u) => (
              <Row key={u.id} href={`/ask?q=${encodeURIComponent(u.q)}`} lang={isHindi(u.q) ? "hi" : "en"}
                lead={<span className="av" style={{ width: 30, height: 30, borderRadius: 10 }}><Icon n="search" s /></span>}
                title={u.q} meta={`Asked ${u.count}× · ${u.dept}`} trail={<span className="btn sm">Ask again</span>} />
            )) : <div className="empty">Every question so far was answered from the records.</div>}
          </div>
        </div>

        <DeadlinePanel upcoming={upcoming} />
      </div>
    </div>
  );
}

function Stat({ href, label, value }: { href: string; label: string; value: number }) {
  return <Link className="stat" href={href}><span>{label}</span><b>{value.toLocaleString("en-IN")}</b></Link>;
}

function Tile({ title, chip, value, sub, children }: { title: string; chip: string; value?: number; sub?: string; children: React.ReactNode }) {
  return (
    <div className="tile">
      <div className="tile-h"><b>{title}</b><span className="chip">{chip}</span></div>
      <div className="tile-body">
        {children}
        {value !== undefined && <div className="big"><b>{value}</b><span>{sub}</span></div>}
      </div>
    </div>
  );
}

/** Inverse panel: month calendar with deadline days marked, the next few deadlines, and a link to all. */
function DeadlinePanel({ upcoming }: { upcoming: Deadline[] }) {
  const s = useStore();
  const { openViewer } = useStore.getState();
  const [cursor, setCursor] = useState(() => { const d = new Date(); return new Date(d.getFullYear(), d.getMonth(), 1); });
  const y = cursor.getFullYear(), m = cursor.getMonth();
  const start = (new Date(y, m, 1).getDay() + 6) % 7; // Monday first
  const dim = new Date(y, m + 1, 0).getDate();
  const today = todayIso();
  const byDay: Record<string, Deadline[]> = {};
  s.deadlines.forEach((x) => { (byDay[x.date] ??= []).push(x); });
  const show = (x: Deadline) => openViewer({ doc: x.doc, page: x.page, block: x.block, quote: x.quote });
  const cells = Array.from({ length: Math.ceil((start + dim) / 7) * 7 }, (_, i) => new Date(y, m, i - start + 1));

  return (
    <aside className="panel" aria-label="Deadlines">
      <div className="mcal-h">
        <h3>Deadlines</h3>
        <div className="row" style={{ gap: 6 }}>
          <button onClick={() => setCursor(new Date(y, m - 1, 1))} aria-label="Previous month" type="button"><Icon n="cl" s /></button>
          <button onClick={() => setCursor(new Date(y, m + 1, 1))} aria-label="Next month" type="button"><Icon n="cr" s /></button>
        </div>
      </div>
      <span className="muted sm">{cursor.toLocaleDateString("en-IN", { month: "long", year: "numeric" })}</span>
      <div className="mcal">
        {["M", "T", "W", "T", "F", "S", "S"].map((d, i) => <span key={i} className="wd">{d}</span>)}
        {cells.map((d, i) => {
          const iso = isoOf(d);
          const list = byDay[iso];
          const cls = `dd ${d.getMonth() !== m ? "out" : ""} ${iso === today ? "today" : list ? "has" : ""}`;
          return list
            ? <button key={i} className={cls} style={{ border: 0, color: "inherit" }} title={list.map((x) => x.title).join("\n")} onClick={() => show(list[0])} type="button">{d.getDate()}</button>
            : <span key={i} className={cls}>{d.getDate()}</span>;
        })}
      </div>
      <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
        <span className="muted xs" style={{ textTransform: "uppercase", letterSpacing: ".06em" }}>Coming up</span>
        {upcoming.length ? upcoming.slice(0, 4).map((x) => {
          const d = new Date(x.date + "T00:00:00");
          return (
            <button key={x.id} className="pitem" onClick={() => show(x)} type="button">
              <span className="dbx"><i>{d.toLocaleDateString("en-IN", { month: "short" })}</i><b>{d.getDate()}</b></span>
              <span className="t"><b>{x.title}</b><span>{getDoc(s, x.doc)?.ref} · {daysTo(x.date) === 0 ? "today" : `in ${plural(daysTo(x.date), "day")}`}</span></span>
            </button>
          );
        }) : <span className="muted sm">Nothing due.</span>}
      </div>
      <Link className="btn full" href="/deadlines">View all deadlines</Link>
    </aside>
  );
}

function lastLabel(msgs: Msg[]) {
  const ai = [...msgs].reverse().find((m): m is Extract<Msg, { role: "ai" }> => m.role === "ai");
  return ai?.answer?.label ?? "";
}
