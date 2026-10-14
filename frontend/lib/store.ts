"use client";

import { useEffect, type ReactNode } from "react";
import { create } from "zustand";
import { api, getToken, setToken, type SessionUser } from "./api";
import type { AiSettings, Cite, Doc, Kind, Lists, Records } from "./types";
import { initials, nid, todayIso } from "./util";

export type Viewer = {
  doc: string; page?: number; block?: string; quote?: string; zoom: number;
  cites?: Cite[]; idx?: number; msg?: string;
};
/** What the assistant searches: a group of documents, minus any the person unticked.
 *  group is "all", "dept:<name>", "tag:<subject>", "coll:<collection id>" or "doc:<document id>". */
export type Scope = { group: string; off: string[] };
export type Modal = { title: string; body: ReactNode; foot?: ReactNode; wide?: boolean; drawer?: boolean } | null;

const EMPTY: Records = {
  documents: [], collections: [], deadlines: [], chats: [], bm_answers: [], bm_passages: [], feedback: [],
  unanswered: [], conflicts: [], users: [], audit: [], settings: [], reminders: [], prefs: [],
};

type State = Records & {
  loaded: boolean; error: string; session: SessionUser | null;
  scope: Scope; ansLang: string; activeChat: string | null;
  viewer: Viewer | null; modal: Modal; toasts: { id: string; msg: string }[];
  /** Documents opened in full (with their text), by id. */
  full: Record<string, Doc>;
  load: () => Promise<void>;
  loadDoc: (id: string) => Promise<Doc | undefined>;
  logout: () => void;
  /** Saves on the server; the screen updates at once and goes back if the server refuses. Resolves true if saved. */
  save: <K extends Kind>(kind: K, item: Records[K][number]) => Promise<boolean>;
  remove: (kind: Kind, id: string) => Promise<boolean>;
  toast: (msg: string) => void;
  openModal: (m: NonNullable<Modal>) => void;
  closeModal: () => void;
  openViewer: (v: Omit<Viewer, "zoom"> & { zoom?: number }) => void;
  closeViewer: () => void;
  set: (p: Partial<State>) => void;
};

export const useStore = create<State>((set, get) => ({
  ...EMPTY,
  loaded: false, error: "", session: null,
  scope: { group: "all", off: [] }, ansLang: "auto", activeChat: null,
  viewer: null, modal: null, toasts: [], full: {},

  load: async () => {
    if (!getToken()) { set({ error: "no-session" }); return; }
    try {
      const [session, records] = await Promise.all([api.me(), api.records()]);
      const first = !get().loaded;
      set({ ...records, session, loaded: true, error: "", full: {} });
      if (first) set({ ansLang: aiSettings(get()).lang || "auto" });
    } catch (e) {
      set({ error: (e as Error).message });
    }
  },
  loadDoc: async (id) => {
    if (get().full[id]) return get().full[id];
    try {
      const doc = await api.document(id);
      set({ full: { ...get().full, [id]: doc } });
      return doc;
    } catch { return undefined; }
  },
  logout: () => { setToken(null); set({ session: null, loaded: false }); location.href = "/login"; },
  save: async (kind, item) => {
    const before = { [kind]: get()[kind], full: get().full } as Partial<State>;
    const list = get()[kind] as { id: string }[];
    const i = list.findIndex((x) => x.id === item.id);
    let shown: { id: string } = item;
    const patch: Partial<State> = {};
    if (kind === "documents") {  // lists hold details only; the text lives in `full`
      const { pages, ...meta } = item as Doc;
      shown = meta;
      const cached = get().full[item.id];
      if (pages || cached) patch.full = { ...get().full, [item.id]: { ...cached, ...meta, pages: pages ?? cached?.pages } as Doc };
    }
    set({ ...patch, [kind]: i < 0 ? [shown, ...list] : list.map((x) => (x.id === item.id ? shown : x)) } as Partial<State>);
    try { await api.put(kind, item.id, item); return true; }
    catch (e) { set(before); get().toast(`Not saved: ${(e as Error).message}`); return false; }
  },
  remove: async (kind, id) => {
    const before = { [kind]: get()[kind] } as Partial<State>;
    set({ [kind]: (get()[kind] as { id: string }[]).filter((x) => x.id !== id) } as Partial<State>);
    try {
      await api.remove(kind, id);
      if (kind === "documents") void get().load();  // the server also removed its deadlines, bookmarks and links
      return true;
    } catch (e) { set(before); get().toast(`Not deleted: ${(e as Error).message}`); return false; }
  },
  toast: (msg) => {
    const id = nid("t");
    set({ toasts: [...get().toasts, { id, msg }] });
    setTimeout(() => set({ toasts: get().toasts.filter((t) => t.id !== id) }), 2800);
  },
  openModal: (modal) => set({ modal }),
  closeModal: () => set({ modal: null }),
  openViewer: (v) => set({ viewer: { zoom: 1, ...v } }),
  closeViewer: () => set({ viewer: null }),
  set: (p) => set(p),
}));

/* ---------- Roles ---------- */
type S = ReturnType<typeof useStore.getState>;
export const role = (s: Pick<S, "session">) => s.session?.role ?? "Viewer";
export const canUpload = (s: Pick<S, "session">) => ["Administrator", "Approver", "Uploader"].includes(role(s));
export const canApprove = (s: Pick<S, "session">) => ["Administrator", "Approver"].includes(role(s));
export const isAdmin = (s: Pick<S, "session">) => role(s) === "Administrator";
/** Uploaders may still change their own documents until they are published. */
export const EDITABLE_ST = ["Draft", "Pending", "Changes requested"];
export const isMine = (s: Pick<S, "session">, d: Doc) => !!d.uploader_id && d.uploader_id === s.session?.login_id;
export const canEditDoc = (s: Pick<S, "session">, d: Doc) => canApprove(s) || (canUpload(s) && isMine(s, d) && EDITABLE_ST.includes(d.status));
export const ownsItem = (s: Pick<S, "session">, x: { owner?: string }) => isAdmin(s) || !x.owner || x.owner === s.session?.login_id;

export const me = (s: Pick<S, "session">) => {
  const u = s.session;
  const name = u?.name || "User";
  return { name, email: u?.email ?? "", title: role(s), initials: initials(name) };
};

/* ---------- Derived data ---------- */
export const HIDDEN_ST = ["Pending", "Draft", "Changes requested", "Rejected"];
export const lists = (s: S) => (s.settings.find((x) => x.id === "lists") as Lists | undefined) ?? EMPTY_LISTS;
export const aiSettings = (s: S) => (s.settings.find((x) => x.id === "ai") as AiSettings | undefined) ?? DEFAULT_AI;
export const roleMatrix = (s: S) =>
  (s.settings.find((x) => x.id === "roles") as { matrix: Record<string, number[]> } | undefined)?.matrix ?? {};
export const getDoc = (s: S, id: string) => s.documents.find((d) => d.id === id);

/** A document with its full text, loaded on first use. */
export function useFullDoc(id: string | undefined): Doc | undefined {
  const doc = useStore((s) => (id ? s.full[id] : undefined));
  const listed = useStore((s) => (id ? s.documents.some((d) => d.id === id) : false));
  useEffect(() => { if (id && listed && !doc) void useStore.getState().loadDoc(id); }, [id, listed, doc]);
  return doc;
}

/** The server sends only documents this person may see. */
export const permitted = (s: S): Doc[] => s.documents;
export const ANSWERABLE_ST = ["Active", "Superseded", "Expired"];
export const answerable = (s: S) => s.documents.filter((d) => ANSWERABLE_ST.includes(d.status));

const split = (group: string) => { const i = group.indexOf(":"); return i < 0 ? [group, ""] : [group.slice(0, i), group.slice(i + 1)]; };

/** The answerable documents in a group (before any are unticked). */
export const groupDocs = (s: S, group: string): Doc[] => {
  const [kind, v] = split(group);
  const co = kind === "coll" ? s.collections.find((c) => c.id === v) : undefined;
  return answerable(s).filter((d) => kind === "dept" ? d.dept === v : kind === "tag" ? d.tags.includes(v)
    : kind === "coll" ? !!co?.docs.includes(d.id) : kind === "doc" ? d.id === v : true);
};
export const scopeDocs = (s: S) => groupDocs(s, s.scope.group).filter((d) => !s.scope.off.includes(d.id));

export const groupLabel = (s: S, group: string) => {
  const [kind, v] = split(group);
  return kind === "coll" ? s.collections.find((c) => c.id === v)?.name ?? "Collection"
    : kind === "doc" ? getDoc(s, v)?.title ?? "One document" : kind === "all" ? "All documents" : v;
};

/** Ready-made groups: every department and subject that has documents, plus the collections. */
export const scopeGroups = (s: S) => {
  const docs = answerable(s);
  const count = (values: string[]) => {
    const n: Record<string, number> = {};
    values.forEach((v) => { if (v) n[v] = (n[v] ?? 0) + 1; });
    return Object.entries(n).sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]));
  };
  return [
    { label: "Departments", kind: "dept", items: count(docs.map((d) => d.dept)) },
    { label: "Subjects", kind: "tag", items: count(docs.flatMap((d) => d.tags)) },
    { label: "Collections", kind: "coll", items: s.collections.map((c) => [c.id, groupDocs(s, "coll:" + c.id).length] as [string, number]) },
  ].map((g) => ({ ...g, items: g.items.map(([v, n]) => ({ value: `${g.kind}:${v}`, label: g.kind === "coll" ? groupLabel(s, "coll:" + v) : v, count: n })) }));
};

export const setScope = (group: string, off: string[] = []) => useStore.setState({ scope: { group, off } });
export const clearScope = () => setScope("all");

const EMPTY_LISTS: Lists = { TAGS: [], AUDS: [], DEPTS: [], TYPES: [], AUTHS: [], INSTS: [], VIS: [], VIS_DESC: {} };
/** "Today", "Yesterday", "Previous 7 days" or the month, from a chat's start time. */
export const chatGroup = (c: { at?: string; when?: string }) => {
  if (!c.at) return c.when || "Earlier";
  const days = Math.floor((new Date(todayIso() + "T00:00:00").getTime() - new Date(c.at.slice(0, 10) + "T00:00:00").getTime()) / 864e5);
  return days <= 0 ? "Today" : days === 1 ? "Yesterday" : days < 7 ? "Previous 7 days"
    : new Date(c.at).toLocaleDateString("en-IN", { month: "long", year: "numeric" });
};

const DEFAULT_AI: AiSettings = { requireCite: true, histOnly: true, showConf: true, logUnans: true, lang: "auto", maxSources: 8 };
