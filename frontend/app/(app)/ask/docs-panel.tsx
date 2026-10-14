"use client";

import { useState } from "react";
import { answerable, groupDocs, scopeGroups, setScope, useStore } from "@/lib/store";
import { Icon } from "@/components/icon";
import { Pill } from "@/components/ui";

/** The documents the assistant searches: pick a group (department, subject, collection), then untick any
 *  to leave out. Documents cited in the open conversation are highlighted. */
export function DocsPanel({ cited }: { cited: Set<string> }) {
  const s = useStore();
  const { openViewer } = useStore.getState();
  const [find, setFind] = useState("");
  const { group, off } = s.scope;
  const inGroup = groupDocs(s, group);
  const shown = inGroup.filter((d) => !find || `${d.title} ${d.ref}`.toLowerCase().includes(find.toLowerCase()));
  const searched = inGroup.filter((d) => !off.includes(d.id)).length;
  const toggle = (id: string) => setScope(group, off.includes(id) ? off.filter((x) => x !== id) : [...off, id]);

  return (
    <>
      <div className="hh">
        <label className="xs muted" htmlFor="sc-group">Search in</label>
        <select className="inp" id="sc-group" value={group} onChange={(e) => setScope(e.target.value)}>
          <option value="all">All documents ({answerable(s).length})</option>
          {group.startsWith("doc:") && <option value={group}>This document only</option>}
          {scopeGroups(s).map((g) => g.items.length > 0 && (
            <optgroup key={g.label} label={g.label}>
              {g.items.map((i) => <option key={i.value} value={i.value}>{i.label} ({i.count})</option>)}
            </optgroup>
          ))}
        </select>
        {inGroup.length > 6 && (
          <input className="inp" value={find} onChange={(e) => setFind(e.target.value)} placeholder="Find in this list" aria-label="Find a document in this list" />
        )}
        <div className="row between xs muted">
          <span>Searching {searched} of {inGroup.length}</span>
          {inGroup.length > 1 && <span>
            <button className="link" type="button" onClick={() => setScope(group)}>All</button>{" · "}
            <button className="link" type="button" onClick={() => setScope(group, inGroup.map((d) => d.id))}>None</button>
          </span>}
        </div>
      </div>
      <div className="hl-list">
        {shown.map((d) => (
          <div key={d.id} className={`dpick ${cited.has(d.id) ? "cited" : ""} ${off.includes(d.id) ? "off" : ""}`}>
            <input type="checkbox" checked={!off.includes(d.id)} onChange={() => toggle(d.id)} aria-label={`Search ${d.title}`} />
            <button className="t" type="button" onClick={() => openViewer({ doc: d.id, page: 1 })} title="Open the document">
              <b lang={d.lang}>{d.title}</b>
              <span className="mono">{d.ref}</span><span> · {d.dept}</span>
            </button>
            {cited.has(d.id) ? <span className="cited-mark" title="Cited in this conversation"><Icon n="spark" s /></span>
              : d.status !== "Active" && <Pill status={d.status} />}
          </div>
        ))}
        {!inGroup.length && <div className="empty sm">No published documents here yet.</div>}
      </div>
    </>
  );
}
