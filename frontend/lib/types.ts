export type Block = { id: string; text: string | string[]; kind: "p" | "subj" | "hdr" | "row" };
export type Status = "Active" | "Pending" | "Draft" | "Changes requested" | "Superseded" | "Withdrawn" | "Expired" | "Rejected";
export type FileKind = "pdf" | "scan" | "docx" | "xlsx" | "img" | "txt";
export type Step = { step: string; by: string; date: string; kind: "" | "ok" | "warn" | "bad"; note?: string };

export type Doc = {
  id: string; title: string; ref: string; type: string; authority: string; dept: string; institution: string;
  date: string; effective: string; expiry: string; audience: string[]; tags: string[]; visibility: string;
  status: Status; fileType: FileKind; lang: "en" | "hi"; description: string; uploadedBy: string; uploadedOn: string;
  related: string[]; revisionOf: string | null; supersededBy: string | null; withdrawReason?: string;
  versions: { v: string; date: string; by: string; note: string }[]; approvals: Step[];
  /** Full text. Lists leave it out; open a document (useFullDoc) to get it. */
  pages?: Block[][]; ocr?: number; sample?: boolean; uploader_id?: string;
  /** The original uploaded file (older documents may not have one). */
  file?: { key: string; name: string; mime: string; pages?: number };
};

/** owner is the creator's Login ID (set by the server); ownerName is shown. */
export type Collection = { id: string; name: string; desc: string; docs: string[]; owner?: string; ownerName?: string; updated: string };
export type Deadline = {
  id: string; title: string; date: string; doc: string; page: number; block: string; quote: string;
  owner: string; aud: string; dept: string; conflict?: boolean; done?: boolean;
};
/** A person's own reminder for a deadline. */
export type Reminder = { id: string; deadline: string; days: number; via: string[] };
/** Per-person preferences: notifications already seen. */
export type Prefs = { id: string; seen: string[] };
export type Notice = { key: string; text: string; href: string };

export type Cite = { doc: string; page: number; block: string; quote: string };
export type BodyPart = { p?: string; ul?: string[]; table?: { head: string[]; rows: string[][] }; sub?: string; opts?: string[] };
export type Answer = {
  source: "documents"; label: string; banner: { kind: string; text: string } | null;
  body: BodyPart[]; cites: Cite[]; follow: string[]; missing?: string[]; queries?: string[];
};
export type Msg =
  | { id: string; role: "user"; text: string }
  | { id: string; role: "ai"; q: string; pending?: boolean; error?: string; answer?: Answer; fb?: "up" | "down" };
/** at: when the chat started (ISO); `when` is the label older chats were saved with. */
export type Chat = { id: string; title: string; msgs: Msg[]; saved: boolean; savedName?: string; when?: string; at?: string };

export type BmAnswer = { id: string; chat: string; msg: string; q: string; when: string };
export type BmPassage = { id: string; doc: string; page: number; block: string; quote: string; note: string; when: string };
export type Feedback = { id: string; q: string; rating: "up" | "down"; reason: string; comment: string; who: string; when: string };
export type Unanswered = { id: string; q: string; count: number; dept: string; status: string; last: string; note?: string; requested_by?: string };
export type Conflict = { id: string; docs: string[]; topic: string; status: string; reported: string; by: string };
export type User = { id: string; name: string; email: string; role: string; dept: string; active: boolean; last: string; login_id?: string };
export type Audit = { id: string; t: string; who: string; act: string; what: string };

export type Lists = {
  TAGS: string[]; AUDS: string[]; DEPTS: string[]; TYPES: string[]; AUTHS: string[]; INSTS: string[];
  VIS: string[]; VIS_DESC: Record<string, string>;
};
export type AiSettings = { requireCite: boolean; histOnly: boolean; showConf: boolean; logUnans: boolean; lang: string; maxSources: number };

/** Every record kind the API stores, keyed as the backend names them. */
export type Records = {
  documents: Doc[]; collections: Collection[]; deadlines: Deadline[]; chats: Chat[];
  bm_answers: BmAnswer[]; bm_passages: BmPassage[]; feedback: Feedback[]; unanswered: Unanswered[];
  conflicts: Conflict[]; users: User[]; audit: Audit[]; reminders: Reminder[]; prefs: Prefs[];
  settings: ({ id: "lists" } & Lists | { id: "ai" } & AiSettings | { id: "roles"; matrix: Record<string, number[]> })[];
};
export type Kind = keyof Records;
