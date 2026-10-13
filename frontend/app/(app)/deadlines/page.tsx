"use client";

import { useState } from "react";
import { getDoc, lists, useStore } from "@/lib/store";
import { daysTo, todayIso } from "@/lib/util";
import { Icon } from "@/components/icon";
import { DateBox, Due } from "@/components/ui";
import type { Deadline } from "@/lib/types";

const GROUPS: [string, (x: Deadline) => boolean][] = [
  ["This week", (x) => !x.done && daysTo(x.date) >= 0 && daysTo(x.date) <= 7],
  ["Later this month and next", (x) => !x.done && daysTo(x.date) > 7],
  ["Overdue", (x) => !x.done && daysTo(x.date) < 0],
  ["Completed", (x) => !!x.done],
];

export default function DeadlinesPage() {
  const s = useStore();
  const { openViewer, save, toast } = useStore.getState();
  const [filter, setFilter] = useState<"upcoming" | "overdue" | "done" | "all">("upcoming");
  const [dept, setDept] = useState("");
  const [view, setView] = useState<"list" | "cal">("list");
  const [[y, mo], setMonth] = useState<[number, number]>(() => { const d = new Date(); return [d.getFullYear(), d.getMonth()]; });

  let ds = [...s.deadlines].sort((a, b) => a.date.localeCompare(b.date));
  if (dept) ds = ds.filter((x) => x.dept === dept);
  const list = filter === "upcoming" ? ds.filter((x) => !x.done && daysTo(x.date) >= 0)
    : filter === "overdue" ? ds.filter((x) => !x.done && daysTo(x.date) < 0)
      : filter === "done" ? ds.filter((x) => x.done) : ds;

  const toggleDone = (x: Deadline) => { void save("deadlines", { ...x, done: !x.done }); toast(x.done ? "Marked as not done" : "Marked as done"); };
  const show = (x: Deadline) => openViewer({ doc: x.doc, page: x.page, block: x.block, quote: x.quote });

  const item = (x: Deadline) => {
    const doc = getDoc(s, x.doc);
    return (
      <div key={x.id} className="li">
        <DateBox date={x.date} />
        <div className="main"><b style={{ whiteSpace: "normal" }}>{x.title}</b>
          <span>{x.owner} · {x.aud} · <button className="link" onClick={() => show(x)} type="button">{doc?.ref}, p.{x.page}</button>
            {x.conflict && <span style={{ color: "var(--red)" }}> · conflicts with another document</span>}</span></div>
        <Due date={x.date} done={x.done} />
        <button className={`btn sm ${x.done ? "" : "ok"}`} onClick={() => toggleDone(x)} type="button">{x.done ? "Undo" : <><Icon n="check" s /> Done</>}</button>
      </div>
    );
  };

  return (
    <div className="wrap">
      <div className="pagehead"><div><h2>Actions &amp; Deadlines</h2><p>Dates and required actions extracted from documents. Each item links to the passage it came from.</p></div></div>
      <div className="row between">
        <div className="row">
          <div className="seg">{([["upcoming", "Upcoming"], ["overdue", "Overdue"], ["done", "Completed"], ["all", "All"]] as const).map(([k, l]) => (
            <button key={k} className={filter === k ? "on" : ""} onClick={() => setFilter(k)} type="button">{l}</button>))}</div>
          <select className="inp" style={{ width: "auto" }} value={dept} onChange={(e) => setDept(e.target.value)} aria-label="Department">
            <option value="">All departments</option>{lists(s).DEPTS.map((d) => <option key={d}>{d}</option>)}</select>
        </div>
        <div className="seg">
          <button className={view === "list" ? "on" : ""} onClick={() => setView("list")} type="button"><Icon n="list" s /> List</button>
          <button className={view === "cal" ? "on" : ""} onClick={() => setView("cal")} type="button"><Icon n="cal" s /> Calendar</button>
        </div>
      </div>

      {view === "list" ? (
        list.length ? GROUPS.map(([g, fn]) => {
          const l = list.filter(fn);
          return l.length ? <div key={g} className="card"><div className="card-h"><h3>{g}</h3><span className="xs muted">{l.length}</span></div>{l.map(item)}</div> : null;
        }) : <div className="card empty">No deadlines match these filters.</div>
      ) : (
        <Calendar y={y} mo={mo} deadlines={ds} onNav={(d) => { let m = mo + d, yy = y; if (m < 0) { m = 11; yy--; } if (m > 11) { m = 0; yy++; } setMonth([yy, m]); }} onShow={show} />
      )}
    </div>
  );
}

function Calendar({ y, mo, deadlines, onNav, onShow }: {
  y: number; mo: number; deadlines: Deadline[]; onNav: (d: number) => void; onShow: (x: Deadline) => void;
}) {
  const first = new Date(y, mo, 1);
  const start = (first.getDay() + 6) % 7;
  const dim = new Date(y, mo + 1, 0).getDate();
  const today = todayIso();
  const cells = [];
  for (let i = 0; i < 42; i++) {
    const dn = i - start + 1;
    const dt = new Date(y, mo, dn);
    const iso = `${dt.getFullYear()}-${String(dt.getMonth() + 1).padStart(2, "0")}-${String(dt.getDate()).padStart(2, "0")}`;
    const evs = deadlines.filter((x) => x.date === iso);
    cells.push(
      <div key={i} className={`d ${dn < 1 || dn > dim ? "out" : ""} ${iso === today ? "today" : ""}`}>
        <span className="dn">{dt.getDate()}</span>
        {evs.map((x) => <button key={x.id} className={`ev ${x.conflict ? "cf" : ""} ${x.done ? "dn2" : ""}`} title={x.title} onClick={() => onShow(x)} type="button">{x.title}</button>)}
      </div>,
    );
    if (i >= 34 && dn >= dim) break;
  }
  return (
    <div className="card">
      <div className="card-h"><div className="row">
        <button className="btn sm" aria-label="Previous month" onClick={() => onNav(-1)} type="button"><Icon n="cl" s /></button>
        <h3>{first.toLocaleDateString("en-IN", { month: "long", year: "numeric" })}</h3>
        <button className="btn sm" aria-label="Next month" onClick={() => onNav(1)} type="button"><Icon n="cr" s /></button>
      </div><span className="xs muted">Red items conflict with another document</span></div>
      <div style={{ overflowX: "auto" }}><div className="cal">
        {["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"].map((x) => <div key={x} className="dh">{x}</div>)}{cells}
      </div></div>
    </div>
  );
}
