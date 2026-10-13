"use client";

import Link from "next/link";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { permitted, useStore } from "@/lib/store";
import { fmtD, nid, plural, todayIso } from "@/lib/util";
import { Icon } from "@/components/icon";
import { Field } from "@/components/ui";

export default function CollectionsPage() {
  const s = useStore();
  const { openModal } = useStore.getState();
  return (
    <div className="wrap">
      <div className="pagehead">
        <div><h2>Collections</h2><p>Group documents for a team or task, then ask questions limited to that group.</p></div>
        <button className="btn pri" onClick={() => openModal({ title: "New collection", body: <NewCollection /> })} type="button"><Icon n="plus" s /> New collection</button>
      </div>
      <div className="cgrid">
        {s.collections.map((co) => (
          <Link key={co.id} className="coll" href={`/collections/${co.id}`}>
            <div className="stack">{co.docs.slice(0, 4).map((_, i) => <i key={i} />)}</div>
            <b>{co.name}</b><span className="sm muted">{co.desc}</span>
            <div className="row between xs muted" style={{ marginTop: "auto" }}>
              <span>{plural(co.docs.length, "document")} · {co.owner}</span><span>Updated {fmtD(co.updated)}</span>
            </div>
          </Link>
        ))}
        {!s.collections.length && <div className="card empty">No collections yet.</div>}
      </div>
    </div>
  );
}

function NewCollection() {
  const router = useRouter();
  const s = useStore();
  const { save, closeModal, toast, session } = useStore.getState();
  const [name, setName] = useState("");
  const [desc, setDesc] = useState("");
  const [docs, setDocs] = useState<string[]>([]);
  const create = () => {
    if (!name.trim()) { toast("Name the collection"); return; }
    const co = { id: nid("C"), name, desc, docs, owner: session?.name ?? "User", updated: todayIso() };
    void save("collections", co); closeModal(); toast("Collection created"); router.push(`/collections/${co.id}`);
  };
  return (
    <>
      <Field label="Name"><input className="inp" value={name} onChange={(e) => setName(e.target.value)} placeholder="e.g. NAAC documentation 2026" /></Field>
      <Field label="Description"><textarea className="inp" rows={2} value={desc} onChange={(e) => setDesc(e.target.value)} /></Field>
      <Field label="Documents">
        <div style={{ maxHeight: 220, overflow: "auto", border: "1px solid var(--line)", borderRadius: 8, padding: "6px 10px" }}>
          {permitted(s).map((d) => (
            <label key={d.id} className="row sm" style={{ padding: "4px 0", flexWrap: "nowrap" }}>
              <input type="checkbox" checked={docs.includes(d.id)} onChange={(e) => setDocs((f) => e.target.checked ? [...f, d.id] : f.filter((x) => x !== d.id))} />
              <span lang={d.lang}>{d.title}</span>
            </label>
          ))}
        </div>
      </Field>
      <div className="mft" style={{ position: "static", borderTop: "1px solid var(--line)", marginTop: 4, paddingTop: 12 }}>
        <button className="btn" onClick={closeModal} type="button">Cancel</button>
        <button className="btn pri" onClick={create} type="button">Create collection</button>
      </div>
    </>
  );
}
