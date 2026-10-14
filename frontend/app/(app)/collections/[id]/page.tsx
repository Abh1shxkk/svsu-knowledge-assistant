"use client";

import Link from "next/link";
import { useState } from "react";
import { useParams, useRouter } from "next/navigation";
import { getDoc, ownsItem, permitted, useStore } from "@/lib/store";
import { todayIso } from "@/lib/util";
import { Icon } from "@/components/icon";
import { Ft, Field, Pill } from "@/components/ui";
import type { Collection } from "@/lib/types";

export default function CollectionDetail() {
  const id = useParams().id as string;
  const router = useRouter();
  const s = useStore();
  const co = s.collections.find((c) => c.id === id);
  const { save, remove, toast, openModal, closeModal } = useStore.getState();
  if (!co) return <div className="wrap"><div className="empty">Collection not found.</div></div>;
  const ds = co.docs.map((d) => getDoc(s, d)).filter(Boolean);
  const mine = ownsItem(s, co);

  const askColl = () => router.push(`/ask?group=coll:${encodeURIComponent(co.id)}`);
  const removeDoc = async (docId: string) => { if (await save("collections", { ...co, docs: co.docs.filter((x) => x !== docId), updated: todayIso() })) toast("Removed from collection"); };
  const del = () => openModal({
    title: "Delete collection?",
    body: <p>Delete <b>{co.name}</b>? The {co.docs.length} documents in it are not deleted.</p>,
    foot: <><button className="btn" onClick={closeModal} type="button">Cancel</button>
      <button className="btn danger" type="button" onClick={async () => { closeModal(); if (await remove("collections", co.id)) { toast("Collection deleted"); router.push("/collections"); } }}>Delete collection</button></>,
  });

  return (
    <div className="wrap">
      <div className="crumb"><Link href="/collections">Collections</Link><Icon n="cr" s /><span>{co.name}</span></div>
      <div className="pagehead">
        <div><h2>{co.name}</h2><p>{co.desc}{co.ownerName && <span className="muted"> · by {co.ownerName}</span>}</p></div>
        <div className="row">
          <button className="btn pri" onClick={askColl} type="button"><Icon n="spark" s /> Ask this collection</button>
          {mine && <>
            <button className="btn" onClick={() => openModal({ title: "Add documents", body: <AddDocs co={co} /> })} type="button"><Icon n="plus" s /> Add documents</button>
            <button className="btn" onClick={() => openModal({ title: "Rename collection", body: <RenameColl co={co} /> })} type="button"><Icon n="edit" s /> Rename</button>
            <button className="btn danger" onClick={del} type="button"><Icon n="trash" s /> Delete</button>
          </>}
        </div>
      </div>
      <div className="card">
        {ds.length ? ds.map((d) => d && (
          <div key={d.id} className="li"><Ft k={d.fileType} />
            <div className="main"><b>{d.title}</b><span className="mono">{d.ref}</span> <span>· {d.dept}</span></div><Pill status={d.status} />
            <Link className="btn sm" href={`/library/${d.id}`}>Open</Link>
            {mine && <button className="iconbtn" aria-label="Remove from collection" onClick={() => removeDoc(d.id)} type="button"><Icon n="x" s /></button>}
          </div>
        )) : <div className="empty">This collection is empty. Add documents to start.</div>}
      </div>
    </div>
  );
}

function AddDocs({ co }: { co: Collection }) {
  const s = useStore();
  const { save, closeModal, toast } = useStore.getState();
  const [sel, setSel] = useState<string[]>([]);
  const avail = permitted(s).filter((d) => !co.docs.includes(d.id));
  return (
    <>
      <div style={{ maxHeight: 300, overflow: "auto" }}>
        {avail.length ? avail.map((d) => (
          <label key={d.id} className="row sm" style={{ padding: "5px 0", flexWrap: "nowrap" }}>
            <input type="checkbox" checked={sel.includes(d.id)} onChange={(e) => setSel((f) => e.target.checked ? [...f, d.id] : f.filter((x) => x !== d.id))} />
            <span lang={d.lang}>{d.title} <span className="mono muted">{d.ref}</span></span>
          </label>
        )) : <p className="muted sm">Every document is already in this collection.</p>}
      </div>
      <div className="mft" style={{ position: "static", borderTop: "1px solid var(--line)", marginTop: 4, paddingTop: 12 }}>
        <button className="btn" onClick={closeModal} type="button">Cancel</button>
        <button className="btn pri" type="button" onClick={async () => { if (await save("collections", { ...co, docs: [...co.docs, ...sel], updated: todayIso() })) { closeModal(); toast(`${sel.length} document(s) added`); } }}>Add selected</button>
      </div>
    </>
  );
}

function RenameColl({ co }: { co: Collection }) {
  const { save, closeModal, toast } = useStore.getState();
  const [name, setName] = useState(co.name);
  const [desc, setDesc] = useState(co.desc);
  return (
    <>
      <Field label="Name"><input className="inp" value={name} onChange={(e) => setName(e.target.value)} /></Field>
      <Field label="Description"><textarea className="inp" rows={2} value={desc} onChange={(e) => setDesc(e.target.value)} /></Field>
      <div className="mft" style={{ position: "static", borderTop: "1px solid var(--line)", marginTop: 4, paddingTop: 12 }}>
        <button className="btn" onClick={closeModal} type="button">Cancel</button>
        <button className="btn pri" type="button" onClick={async () => { if (await save("collections", { ...co, name, desc, updated: todayIso() })) { closeModal(); toast("Collection updated"); } }}>Save</button>
      </div>
    </>
  );
}
