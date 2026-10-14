import type { Answer, Deadline, Doc, FileKind, Block, Kind, Notice, Records } from "./types";

export const API_URL = process.env.NEXT_PUBLIC_API_URL ?? "http://127.0.0.1:8000";
const TOKEN_KEY = "svsu_token";

export const getToken = () => {
  try { return localStorage.getItem(TOKEN_KEY); } catch { return null; }
};
export const setToken = (t: string | null) => {
  try { if (t) localStorage.setItem(TOKEN_KEY, t); else localStorage.removeItem(TOKEN_KEY); } catch { /* private mode */ }
};

/** Thrown with status 401 when the session is missing or expired. */
export class ApiError extends Error {
  constructor(public status: number, message: string) { super(message); }
}

async function send(path: string, init: RequestInit = {}): Promise<Response> {
  const token = getToken();
  const headers = new Headers(init.headers);
  if (token) headers.set("Authorization", `Bearer ${token}`);
  const res = await fetch(API_URL + path, { ...init, headers });
  if (res.status === 401 && path !== "/login") {
    setToken(null);
    if (typeof window !== "undefined" && location.pathname !== "/login") location.href = "/login";
  }
  if (!res.ok) throw new ApiError(res.status, (await res.json().catch(() => null))?.detail ?? `Request failed (${res.status})`);
  return res;
}

async function call<T>(path: string, init: RequestInit = {}): Promise<T> {
  const res = await send(path, init);
  return (res.headers.get("content-type")?.includes("json") ? res.json() : res.blob()) as Promise<T>;
}
const jsonBody = (method: string, body: unknown): RequestInit => ({
  method, headers: { "Content-Type": "application/json" }, body: JSON.stringify(body),
});

type AskBody = { question: string; scope_ids: string[]; lang: string; history: string[] };
export type AskEvent = { status?: string; delta?: string };

export type ImportBatch = {
  batch: string; by: string; publish: boolean; updated: string | null;
  counts: Partial<Record<"queued" | "running" | "done" | "duplicate" | "failed", number>>; failed: { name: string; error: string }[];
};
export type QualityReport = {
  id: string; at: string; questions: number; paragraph_found: number; document_found: number; cited_right_document: number;
  answered_correctly: number; correct_by_style: Record<string, number>; misses: { question: string; answer: string; got: string; found: boolean }[];
};

export type MfaStart = { secret: string; uri: string; qr: string };
export type KeyStatus = { source: "admin" | "env" | "none"; last4: string; by?: string; at?: string };

export type Extracted = {
  kind: FileKind; pages: Block[][]; ocr: number | null; ocr_engine: string | null; suggestion: Record<string, unknown>;
  duplicate: { id: string; title: string; ref: string; status: string } | null;
  file: { key: string; name: string; mime: string; pages?: number };
  unsure?: string[];
};

export type SessionUser = { login_id: string; name: string; email: string; role: string; dept?: string; dev?: boolean; employee_id?: number };

export const api = {
  /** A session, or (with two-step verification) a ticket for the code step: mfa "code" or "setup". */
  login: (login_id: string, password: string) =>
    call<{ token?: string; user?: SessionUser; mfa?: "code" | "setup"; ticket?: string }>("/login", jsonBody("POST", { login_id, password })),
  loginMfa: (ticket: string, code: string) =>
    call<{ token: string; user: SessionUser; recovery?: string[] }>("/login/mfa", jsonBody("POST", { ticket, code })),
  loginMfaSetup: (ticket: string) => call<MfaStart>("/login/mfa/setup", jsonBody("POST", { ticket })),
  myMfa: () => call<{ on: boolean; required: boolean; recovery_left: number }>("/me/mfa"),
  mfaSetup: () => call<MfaStart>("/me/mfa/setup", { method: "POST" }),
  mfaEnable: (code: string) => call<{ recovery: string[] }>("/me/mfa/enable", jsonBody("POST", { code })),
  mfaDisable: (password: string) => call<{ ok: boolean }>("/me/mfa/disable", jsonBody("POST", { password })),
  mfaUsers: () => call<string[]>("/accounts/mfa"),
  resetMfa: (login_id: string) => call<{ ok: boolean }>(`/accounts/${encodeURIComponent(login_id)}/mfa`, { method: "DELETE" }),
  me: () => call<SessionUser>("/me"),
  records: () => call<Records>("/records"),
  put: (kind: Kind, id: string, data: unknown) => call(`/records/${kind}/${encodeURIComponent(id)}`, jsonBody("PUT", data)),
  remove: (kind: Kind, id: string) => call(`/records/${kind}/${encodeURIComponent(id)}`, { method: "DELETE" }),
  ask: (body: AskBody) => call<Answer>("/ask", jsonBody("POST", body)),
  /** The same answer, received while it is made: progress and the text as it is written, then the answer. */
  askStream: async (body: AskBody, onEvent: (e: AskEvent) => void): Promise<Answer> => {
    const reader = (await send("/ask/stream", jsonBody("POST", body))).body!.pipeThrough(new TextDecoderStream()).getReader();
    let buf = "";
    for (;;) {
      const { value, done } = await reader.read();
      if (done) throw new Error("The answer was cut off. Please try again.");
      buf += value;
      for (let i = buf.indexOf("\n\n"); i >= 0; i = buf.indexOf("\n\n")) {
        const line = buf.slice(0, i);
        buf = buf.slice(i + 2);
        if (!line.startsWith("data: ")) continue;
        const e = JSON.parse(line.slice(6));
        if (e.done) return e.done as Answer;
        if (e.error) throw new Error(e.error);
        onEvent(e);
      }
    }
  },
  extract: (file: File) => {
    const fd = new FormData();
    fd.append("file", file);
    return call<Extracted>("/extract", { method: "POST", body: fd });
  },
  document: (id: string) => call<Doc>(`/documents/${encodeURIComponent(id)}`),
  originalFile: (id: string) => call<Blob>(`/documents/${encodeURIComponent(id)}/file`),
  originalPage: (id: string, n: number) => call<Blob>(`/documents/${encodeURIComponent(id)}/file/page/${n}`),
  search: (q: string) => call<string[]>(`/search?q=${encodeURIComponent(q)}`),
  checks: (id: string) => call<[string, string][]>(`/documents/${encodeURIComponent(id)}/checks`),
  notifications: () => call<Notice[]>("/notifications"),
  reportSummary: () => call<{ month: number; cited: number; weeks: { label: string; value: number }[] }>("/reports/summary"),
  requestDoc: (q: string, dept: string, note: string) => call<{ ok: boolean }>("/unanswered/request", jsonBody("POST", { q, dept, note })),
  renameTag: (old: string, next: string) => call<{ ok: boolean }>("/admin/tags/rename", jsonBody("POST", { old, new: next })),
  importFile: (file: File, batch: string, o: { visibility: string; publish: boolean; dept: string }) => {
    const fd = new FormData();
    fd.append("file", file); fd.append("batch", batch); fd.append("visibility", o.visibility);
    fd.append("publish", String(o.publish)); fd.append("dept", o.dept);
    return call<{ ok: boolean }>("/imports", { method: "POST", body: fd });
  },
  imports: () => call<ImportBatch[]>("/imports"),
  retryImport: (batch: string) => call<{ requeued: number }>(`/imports/${encodeURIComponent(batch)}/retry`, { method: "POST" }),
  quality: () => call<{ latest: QualityReport | null; running: boolean }>("/reports/quality"),
  runQuality: (fresh: boolean) => call<{ ok: boolean }>(`/reports/quality/run?new=${fresh}`, { method: "POST" }),
  /** Administrators only. The key itself never comes back, only its last 4 characters. */
  keyStatus: () => call<KeyStatus>("/admin/openai-key"),
  setKey: (key: string) => call<KeyStatus>("/admin/openai-key", jsonBody("PUT", { key })),
  removeKey: () => call<KeyStatus>("/admin/openai-key", { method: "DELETE" }),
  exportDocx: (title: string, items: { q: string; answer: Answer }[]) => call<Blob>("/export/docx", jsonBody("POST", { title, items })),
  deadlines: (docId: string) => call<Omit<Deadline, "id" | "dept">[]>(`/documents/${docId}/deadlines`, { method: "POST" }),
  createAccount: (a: { login_id: string; name: string; email: string; dept: string; role: string; password: string }) =>
    call<{ ok: boolean }>("/accounts", jsonBody("POST", a)),
  updateProfile: (p: { name: string; email: string }) => call<SessionUser>("/me/profile", jsonBody("PUT", p)),
  changePassword: (current: string, next: string) =>
    call<{ ok: boolean }>("/me/password", jsonBody("PUT", { current, new: next })),
  resetPassword: (login_id: string, password: string) =>
    call<{ ok: boolean }>(`/accounts/${encodeURIComponent(login_id)}/password`, jsonBody("PUT", { password })),
};
