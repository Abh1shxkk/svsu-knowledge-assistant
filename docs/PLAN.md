# SVSU Knowledge Assistant — Implementation Plan

**Purpose:** what is left, and how to build it so the system holds up with real staff, thousands of
documents and years of history. Read this before starting any item in [TODO.md](../TODO.md).

**Short version:** the screens and the AI pipeline work, but the data layer was built for a
prototype. Phase 0 rebuilds that foundation (server-owned permissions, real tables, per-person data,
paginated APIs). Everything after it — original files, background processing, better search, the
missing features, deployment — sits on top of Phase 0 and would have to be redone without it.

| Phase | What | Rough effort (1 developer) |
|---|---|---|
| 0 | Foundation: data model, server-side permissions, real APIs | 2–3 weeks |
| 1 | Document pipeline: original files, background processing, OCR quality | 2 weeks |
| 2 | Search and answer quality | 1–2 weeks |
| 3 | Remaining prototype features | 2 weeks |
| 4 | Tests, deployment, operations | 1–2 weeks |
| | **Total** | **about 8–11 weeks** |

---

## How answering works (the agreed design)

1. **Extract text once** at upload (OCR for scans) and **save it as vector embeddings**, one per paragraph.
2. When someone asks, **the LLM rewrites the question for search**: 2–3 self-contained queries in
   English and Hindi, abbreviations expanded (CL → casual leave), follow-ups completed from the
   earlier questions in the chat. The LLM does not search.
3. **Semantic search** (pgvector) finds the matching paragraphs for every query, keeps each paragraph's
   best match, and caps it at 3 paragraphs per document so one long document can't crowd out the rest.
4. The LLM writes the answer **only from those paragraphs**, citing each claim.

Steps 2 and 3 are implemented (`rag.rewrite`, `rag._search_all`); the person sees "Searched for: …"
under each answer. Phase 2.1 adds keyword matching alongside step 3.

---

## 1. Where we are

**Working today (tested locally):** login with app-managed accounts; all 12 screens; light/dark
themes; uploads of PDF, scans, Word, Excel, images and text; OCR with Tesseract (Hindi + English)
and AWS Textract wired in; paragraph embeddings stored in PostgreSQL + pgvector; cited answers
in English and Hindi, including conflicting, revised, historical and "not in the records" cases.

**Why the current shape won't scale or isn't safe** (all confirmed in the code):

| # | Problem | Effect |
|---|---|---|
| 1 | `GET /records` sends the **entire database** to every signed-in browser | Slow as data grows; a Viewer receives restricted documents |
| 2 | **Permissions are checked only in the browser**; `/ask` trusts the browser's list of allowed documents | Anyone technical can read restricted documents or make the AI answer from them |
| 3 | **Chats, bookmarks and saved items have no owner** | Every person sees everyone's conversations |
| 4 | The **browser decides document status** (approve/reject) and **writes the audit log** | An Uploader could publish their own document; the audit log can be faked |
| 5 | **OCR, metadata suggestion and embedding run inside the upload request** | A 10-page scan holds a web request open for a minute; failures lose the work |
| 6 | **Original files are not kept** — only extracted text | No "view original" or download; OCR mistakes can't be checked against the source |
| 7 | **Library search runs in the browser** over every document's full text | Breaks down at a few hundred documents |
| 8 | No migrations, no automated tests, local-only database, test admin login, sample data loaded | Can't be deployed or changed safely |

---

## 2. Target architecture

```
 Browser (Next.js)
   │  httpOnly session cookie · paginated, permission-filtered requests
   ▼
 API (FastAPI, stateless — run 1..N copies behind a load balancer)
   │  • every query passes through one access policy
   │  • state changes (approve, withdraw…) only through explicit endpoints
   │  • audit log written here, never by the browser
   ├──────────────► PostgreSQL 16 + pgvector  (single source of truth)
   │                 tables · embeddings (HNSW) · full-text indexes · job queue
   ├──────────────► Object storage  (S3 in production, a local folder in development)
   │                 original uploaded files, exports
   ▼
 Worker (same codebase, run 1..N copies)
     picks jobs from the queue: OCR (Tesseract / Textract) → paragraphs → suggested details →
     embeddings → deadline extraction · scheduled jobs: reminders, cleanup
     └──► OpenAI (answers, embeddings) · AWS Textract · email (SMTP / AWS SES)
```

**Principles**
1. **The server is the only authority** for who can see what and which state a document is in.
2. **The browser only receives what the person may see, one page at a time.**
3. **Slow work never runs inside a web request** — it becomes a job with retries.
4. **Text is read once, embedded once.** Re-embed a paragraph only if its text changed.
5. **Every schema change is a migration** (Alembic); every setting comes from the environment.
6. **No extra infrastructure until it's needed.** The job queue lives in PostgreSQL
   (`FOR UPDATE SKIP LOCKED`); add Redis only if job volume ever demands it.

---

## 3. Data model

Replace the generic `records` JSONB table with real tables (JSONB stays only where the shape is
genuinely free-form, such as an answer's body).

| Table | Key columns | Notes |
|---|---|---|
| `users` | id, login_id (unique), name, email, dept, role, active, password_hash, last_login | merges today's `users` records + `credentials` |
| `documents` | id, title, ref, type, authority, dept, institution, dates, audience[], tags[], visibility, status, file_key, file_hash, file_type, lang, ocr_confidence, ocr_engine, uploaded_by, created_at | status is a state machine (see Phase 0.4) |
| `blocks` | id, document_id, version, page, block, kind, text, text_hash, embedding vector(1536), tsv tsvector | already exists; add `tsv` for keyword search and `text_hash` to skip unchanged paragraphs |
| `document_versions` | document_id, version, file_key, note, created_by, created_at | revisions keep history |
| `document_events` | document_id, step, actor, note, created_at | the approval timeline |
| `document_links` | from_id, to_id, kind (related / revises / supersedes) | |
| `collections`, `collection_documents` | owner, name, description · (collection_id, document_id) | |
| `deadlines` | document_id, page, block, quote, title, due_date, owner_dept, audience, done | |
| `chats`, `messages` | **user_id**, title, saved · chat_id, role, text, answer JSONB, feedback | per person |
| `bookmarks` | **user_id**, kind (answer / passage), target ids, note | per person |
| `unanswered_questions`, `conflicts` | question, count, dept, status, assignee · doc ids, topic, status | |
| `notifications`, `reminders` | user_id, kind, payload, read_at · deadline_id, user_id, when, channel | |
| `audit_log` | actor, action, target, detail, ip, created_at | **append-only; written by the server** |
| `settings` | key, value JSONB | tag/department/type lists, AI behaviour, role → visibility matrix |
| `jobs` | kind, payload, status, attempts, run_after, error | the work queue |

**Access policy.** One function decides whether a person may see a document, and it is applied as a
SQL `WHERE` clause on every query — the library, the viewer, search, `/ask` retrieval, exports.
Inputs: the person's role, the role → visibility matrix from settings, their department (for
"Department only" documents), and the document status (Viewers never see Pending/Draft/Rejected).

---

## 4. Phases

### Phase 0 — Foundation (2–3 weeks) · *do first; everything depends on it*

| Step | Work | Done when |
|---|---|---|
| 0.1 | Add **Alembic**; create the tables above; a one-off migration that moves today's `records` data into them | Data visible through the new tables; `alembic upgrade head` rebuilds an empty database |
| 0.2 | **Access policy** module + unit tests covering every role × visibility × status combination | Tests pass for all combinations |
| 0.3 | Replace `/records` with **resource endpoints**, all filtered by the policy and paginated: `/documents`, `/documents/{id}`, `/documents/{id}/pages`, `/collections`, `/deadlines`, `/chats`, `/bookmarks`, `/reports/*`, `/admin/*` | A Viewer requesting a restricted document gets 404; first dashboard load is a few KB, not the whole database |
| 0.4 | **Document state machine** on the server: `submit`, `approve`, `request-changes`, `reject`, `withdraw`, `restore` endpoints, each checking the role and writing an event + audit entry | An Uploader cannot approve; every transition appears in the audit log |
| 0.5 | `/ask` computes the person's allowed documents **on the server**; the browser only sends its chosen scope, which is intersected with what's allowed | Test: a Viewer's question never cites a restricted document |
| 0.6 | **Per-person data**: chats, messages, bookmarks and collections get an owner | Two users never see each other's chats |
| 0.7 | **Sessions**: httpOnly, secure cookie instead of a token in `localStorage`; logout and deactivation end the session | Deactivated user is signed out on their next request |
| 0.8 | Frontend data layer: replace the load-everything store with **per-screen queries** (TanStack Query) with caching and pagination | Each screen fetches only its own data |
| 0.9 | **Clean start**: remove sample data (keep a `--demo` seed flag for development only); `python -m app.cli create-admin` for the first real administrator; delete the test-admin settings; rotate the OpenAI key and set a strong `JWT_SECRET` | Production database starts empty with one real admin |

### Phase 1 — Document pipeline (2 weeks)

| Step | Work | Done when |
|---|---|---|
| 1.1 | **File storage** behind one small interface: a local folder in development, S3 in production. Store every original on upload, keyed by content hash | Original file survives and can be downloaded via a short-lived signed link |
| 1.2 | **Background jobs**: upload returns at once with status "Processing"; a worker runs OCR → paragraphs → suggested details → embeddings. Retries with backoff, max attempts, failed jobs kept with their error | A 50-page scan doesn't block the page; the upload queue shows live progress |
| 1.3 | **Embed once**: hash each paragraph; on re-upload or edit, only changed paragraphs are re-embedded; embeddings sent in batches | Re-saving metadata costs no embedding calls |
| 1.4 | **OCR quality**: clean the image before OCR (greyscale, deskew, threshold), per-page confidence, low-confidence pages flagged; extracted text **editable** on the upload screen before submitting | Reviewer sees which pages need checking and can correct them |
| 1.5 | **Textract**: test with real keys; for multi-page PDFs use the asynchronous API via S3 (one job per document, not per page); monthly page cap | English scans read by Textract within the cap |
| 1.6 | **Viewer shows the original** (PDF rendered in the browser) with the cited passage highlighted, plus the extracted text alongside | Citation opens the real document at the right place |
| 1.7 | **Duplicates** detected on the server by file hash and title similarity; upload limits (size, pages) from settings | Same file uploaded twice is flagged before processing |

### Phase 2 — Search and answer quality (1–2 weeks)

| Step | Work |
|---|---|
| 2.1 | **Hybrid retrieval**: combine vector similarity (pgvector) with PostgreSQL full-text search, merged by reciprocal-rank fusion. Exact matches like `SVSU/REG/HR/2026/114` and names then rank correctly. The `simple` text configuration works for Hindi |
| 2.2 | **Library search on the server** using the same full-text index, with filters and pagination |
| 2.3 | **Evaluation set**: 50–100 real questions with the documents they should cite; run automatically on every change so answer quality can't silently drop |
| 2.4 | **Streaming answers** (text appears as it's written) |
| 2.5 | **Cost control**: cache answers per question + scope + document versions; per-person rate limit; monthly budget alert; use a smaller model for routine tasks (metadata suggestion, deadline extraction) |

### Phase 3 — Remaining prototype features (2 weeks)

| Feature | Server design |
|---|---|
| Export cited summary | Generate PDF and Word on the server (WeasyPrint, python-docx), stored in object storage, downloaded via signed link |
| Deadlines + reminders | Deadline extraction runs as a job when a document is approved; a daily scheduled job sends reminders by email (SMTP / AWS SES) and in-app notifications |
| Notifications bell | `notifications` table; pending approvals, near deadlines and open conflicts generate entries |
| Compare documents · Report conflict | Side-by-side view of two documents; a conflict reported from an answer creates a `conflicts` row and notifies both owning departments |
| Request document · Assign unanswered question | Workflow on `unanswered_questions` with assignee department, status and notification |
| Link documents · Add revision | `document_links`; a revision uploads a new version through the same pipeline; approving it marks the old one superseded |
| Admin | Rename/merge tags (bulk update), department management, role matrix actually enforced by the access policy, deactivate user ends their sessions |

### Phase 4 — Quality, deployment and operations (1–2 weeks)

| Step | Work |
|---|---|
| 4.1 | **Tests**: pytest for the access policy, state machine and API (against a real test PostgreSQL); Playwright for login → upload → review → ask |
| 4.2 | **CI** on GitHub Actions: lint, type-check, tests and build on every push; nothing merges red |
| 4.3 | **Containers**: images for web, API and worker; `docker-compose` for development with the official `pgvector/pgvector` PostgreSQL image (replaces the local `pgserver`) |
| 4.4 | **Hosting** (recommended: AWS, since Textract is already AWS): managed PostgreSQL with pgvector (RDS), S3, SES, the three containers on a VM or ECS; HTTPS via a reverse proxy; CORS locked to the real domain; security headers |
| 4.5 | **Backups**: automated daily database snapshots with point-in-time recovery, S3 versioning; a tested restore |
| 4.6 | **Monitoring**: structured logs, error tracking, health checks, metrics for request latency, job-queue depth and daily OpenAI/Textract spend |
| 4.7 | **Docs**: rewrite `instructions.md`, `design.md`, `rules.md` for the real system; add a short runbook (deploy, restore, rotate keys, add a user) |

---

## 5. Scale and capacity

- **Search:** a university library of 10,000 documents × ~50 paragraphs ≈ 500,000 vectors. pgvector's
  HNSW index handles this on a single PostgreSQL server with millisecond lookups.
- **Users:** the API holds no session state, so it scales by running more copies. Add connection
  pooling (PgBouncer) once there are more than a handful of copies.
- **Uploads:** workers scale separately from the API, based on queue length; a burst of uploads
  waits in the queue instead of slowing everyone down.
- **Main running cost is OpenAI**, then Textract. Phase 2.5 keeps both measured and capped.

## 6. Decisions needed

| Decision | Options / recommendation |
|---|---|
| Hosting | **AWS (recommended)** — Textract, S3, SES and RDS in one place — or a university server |
| Email for reminders | University SMTP server, or AWS SES |
| Approval to send official records to OpenAI | Needs sign-off from the university; otherwise plan for a self-hosted model |
| Real administrators and approvers | Names and departments, so the first accounts and the access matrix are right |
| Retention | How long to keep chats, audit log and withdrawn documents |
| Monthly budget | OpenAI and Textract spend caps |

## 7. Risks

| Risk | Mitigation |
|---|---|
| Hindi OCR accuracy (~77% on a test scan) | Image clean-up (1.4), low-confidence flagging and human correction before submit |
| Textract can't read Hindi | Hindi always goes to Tesseract; detection is per page |
| Cost growth | Caching, budgets, smaller models for routine tasks (2.5) |
| One developer | Phase 0 first; each phase ships something usable on its own |
