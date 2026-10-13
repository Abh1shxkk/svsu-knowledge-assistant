/** Small formatting helpers shared by every screen. Dates are ISO "YYYY-MM-DD". */

export const todayIso = () => new Date().toLocaleDateString("en-CA"); // local date as YYYY-MM-DD

export const fmtD = (d?: string) =>
  d ? new Date(d + "T00:00:00").toLocaleDateString("en-IN", { day: "numeric", month: "short", year: "numeric" }) : "—";

export const daysTo = (d: string) =>
  Math.round((new Date(d + "T00:00:00").getTime() - new Date(todayIso() + "T00:00:00").getTime()) / 864e5);

/** "13 Oct 2026, 11:42 am" — used for audit entries and bookmarks. */
export const nowStr = () =>
  new Date().toLocaleString("en-IN", { day: "2-digit", month: "short", year: "numeric", hour: "numeric", minute: "2-digit" });

export const nid = (prefix: string) => prefix + Date.now().toString(36) + Math.random().toString(36).slice(2, 6);

export const initials = (name: string) =>
  name.replace(/^(Dr\.|Prof\.)\s*/, "").split(" ").map((w) => w[0]).slice(0, 2).join("");

export const isHindi = (s: string) => /[ऀ-ॿ]/.test(s);

export const plural = (n: number, word: string) => `${n} ${word}${n === 1 ? "" : "s"}`;

export const blockText = (text: string | string[]) => (Array.isArray(text) ? text.join(" | ") : text);
