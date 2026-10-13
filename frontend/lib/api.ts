import type { Answer, Deadline, FileKind, Block, Kind, Records } from "./types";

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

async function call<T>(path: string, init: RequestInit = {}): Promise<T> {
  const token = getToken();
  const headers = new Headers(init.headers);
  if (token) headers.set("Authorization", `Bearer ${token}`);
  const res = await fetch(API_URL + path, { ...init, headers });
  if (res.status === 401 && path !== "/login") {
    setToken(null);
    if (typeof window !== "undefined" && location.pathname !== "/login") location.href = "/login";
  }
  if (!res.ok) throw new ApiError(res.status, (await res.json().catch(() => null))?.detail ?? `Request failed (${res.status})`);
  return res.json();
}
const jsonBody = (method: string, body: unknown): RequestInit => ({
  method, headers: { "Content-Type": "application/json" }, body: JSON.stringify(body),
});

export type SessionUser = { login_id: string; name: string; email: string; role: string; employee_id?: number };

export const api = {
  login: (login_id: string, password: string) =>
    call<{ token: string; user: SessionUser }>("/login", jsonBody("POST", { login_id, password })),
  me: () => call<SessionUser>("/me"),
  records: () => call<Records>("/records"),
  put: (kind: Kind, id: string, data: unknown) => call(`/records/${kind}/${encodeURIComponent(id)}`, jsonBody("PUT", data)),
  remove: (kind: Kind, id: string) => call(`/records/${kind}/${encodeURIComponent(id)}`, { method: "DELETE" }),
  ask: (body: { question: string; scope_ids: string[]; permitted_ids: string[]; lang: string }) =>
    call<Answer>("/ask", jsonBody("POST", body)),
  extract: (file: File) => {
    const fd = new FormData();
    fd.append("file", file);
    return call<{ kind: FileKind; pages: Block[][]; ocr: number | null; ocr_engine: string | null; suggestion: Record<string, unknown> }>("/extract", { method: "POST", body: fd });
  },
  deadlines: (docId: string) => call<Omit<Deadline, "id" | "dept">[]>(`/documents/${docId}/deadlines`, { method: "POST" }),
  createAccount: (a: { login_id: string; name: string; email: string; dept: string; role: string; password: string }) =>
    call<{ ok: boolean }>("/accounts", jsonBody("POST", a)),
  resetPassword: (login_id: string, password: string) =>
    call<{ ok: boolean }>(`/accounts/${encodeURIComponent(login_id)}/password`, jsonBody("PUT", { password })),
};
