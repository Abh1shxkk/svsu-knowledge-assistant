"use client";

import type { ReactNode } from "react";
import { create } from "zustand";
import { api, getToken, setToken, type SessionUser } from "./api";
import type { AiSettings, Cite, Doc, Kind, Lists, Records } from "./types";
import { initials, nid } from "./util";

export type Viewer = {
  doc: string; page?: number; block?: string; quote?: string; zoom: number;
  cites?: Cite[]; idx?: number; msg?: string;
};
export type Scope = { mode: "all" | "files" | "collection"; files: string[]; coll: string | null };
export type Filters = { dept: string; subject: string; type: string; from: string; to: string };
export type Modal = { title: string; body: ReactNode; foot?: ReactNode; wide?: boolean; drawer?: boolean } | null;

const NO_FILTERS: Filters = { dept: "", subject: "", type: "", from: "", to: "" };
const EMPTY: Records = {
  documents: [], collections: [], deadlines: [], chats: [], bm_answers: [], bm_passages: [], feedback: [],
  unanswered: [], conflicts: [], users: [], audit: [], settings: [],
};

type State = Records & {
  loaded: boolean; error: string; session: SessionUser | null;
  scope: Scope; filters: Filters; ansLang: string; activeChat: string | null;
  viewer: Viewer | null; modal: Modal; toasts: { id: string; msg: string }[];
  load: () => Promise<void>;
  logout: () => void;
  save: <K extends Kind>(kind: K, item: Records[K][number]) => Promise<void>;
  remove: (kind: Kind, id: string) => Promise<void>;
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
  scope: { mode: "all", files: [], coll: null }, filters: NO_FILTERS, ansLang: "auto", activeChat: null,
  viewer: null, modal: null, toasts: [],

  load: async () => {
    if (!getToken()) { set({ error: "no-session" }); return; }
    try {
      const [session, records] = await Promise.all([api.me(), api.records()]);
      set({ ...records, session, loaded: true, error: "" });
    } catch (e) {
      set({ error: (e as Error).message });
    }
  },
  logout: () => { setToken(null); set({ session: null, loaded: false }); location.href = "/login"; },
  save: async (kind, item) => {
    const list = get()[kind] as { id: string }[];
    const i = list.findIndex((x) => x.id === item.id);
    set({ [kind]: i < 0 ? [item, ...list] : list.map((x) => (x.id === item.id ? item : x)) } as Partial<State>);
    try { await api.put(kind, item.id, item); } catch (e) { get().toast(`Couldn't save: ${(e as Error).message}`); }
  },
  remove: async (kind, id) => {
    set({ [kind]: (get()[kind] as { id: string }[]).filter((x) => x.id !== id) } as Partial<State>);
    try { await api.remove(kind, id); } catch (e) { get().toast(`Couldn't delete: ${(e as Error).message}`); }
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
/** Full document access (sees Management Only and pending items). */
export const fullAccess = (s: Pick<S, "session">) => canApprove(s);

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

export const permitted = (s: S): Doc[] =>
  fullAccess(s) ? s.documents
    : s.documents.filter((d) => d.visibility !== "Management Only" && !HIDDEN_ST.includes(d.status));
export const answerable = (s: S) => permitted(s).filter((d) => !HIDDEN_ST.includes(d.status) && d.status !== "Withdrawn");

export const scopeDocs = (s: S) => {
  let ds = answerable(s);
  if (s.scope.mode === "files") ds = ds.filter((d) => s.scope.files.includes(d.id));
  if (s.scope.mode === "collection") {
    const co = s.collections.find((c) => c.id === s.scope.coll);
    ds = ds.filter((d) => co?.docs.includes(d.id));
  }
  const f = s.filters;
  return ds.filter((d) => (!f.dept || d.dept === f.dept) && (!f.subject || d.tags.includes(f.subject))
    && (!f.type || d.type === f.type) && (!f.from || d.date >= f.from) && (!f.to || d.date <= f.to));
};
export const filterCount = (s: S) => Object.values(s.filters).filter(Boolean).length;
export const scopeLabel = (s: S) =>
  s.scope.mode === "files" ? `${s.scope.files.length} selected file${s.scope.files.length === 1 ? "" : "s"}`
    : s.scope.mode === "collection" ? s.collections.find((c) => c.id === s.scope.coll)?.name ?? "Collection"
      : "All permitted documents";
export const clearScope = () => useStore.setState({ scope: { mode: "all", files: [], coll: null }, filters: NO_FILTERS });

const EMPTY_LISTS: Lists = { TAGS: [], AUDS: [], DEPTS: [], TYPES: [], AUTHS: [], INSTS: [], VIS: [], VIS_DESC: {} };
const DEFAULT_AI: AiSettings = { requireCite: true, histOnly: true, showConf: true, logUnans: true, lang: "auto", maxSources: 8 };
