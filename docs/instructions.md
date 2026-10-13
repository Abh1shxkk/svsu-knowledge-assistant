# SVSU Knowledge Assistant — Build Instructions

> Audience: developers working on this project. What the product is, how it is built, and how to
> run it. Remaining work is in [PLAN.md](PLAN.md) and [../TODO.md](../TODO.md).

---

## 1. Product in one paragraph

Staff of Swami Vivekanand Subharti University ask questions about official letters, notices,
circulars and policies, in Hindi or English, and get answers **only from the university's own
documents**, with every claim cited to the exact passage. Documents are uploaded, read once (OCR
for scans), checked by an approver and only then used in answers. Who can open a document, and so
who the assistant may answer from, is decided by role, department and the document's access level.

## 2. Modules (names and order from the prototype)

Dashboard · Ask AI · Document Library · Upload Documents · Review & Approvals · Collections ·
Actions & Deadlines · Saved Chats & Bookmarks · Reports & Feedback · Administration, plus My profile.

| Role | Can do |
|---|---|
| Viewer | Ask, read permitted documents, collections, bookmarks, deadline reminders |
| Uploader | + upload, save drafts, edit and resubmit **their own unpublished** documents, add deadlines |
| Approver | + review, publish, reject, withdraw, link documents, reports |
| Administrator | + users, roles, access levels, tags, departments, AI settings, audit log, delete documents |

## 3. How answering works

1. **Text is extracted once**, at upload (PyMuPDF, python-docx, openpyxl; Tesseract OCR for scans
   and photos, Hindi + English). Each paragraph is embedded and stored in PostgreSQL with pgvector.
2. **The LLM rewrites the question** into 2–3 search queries (English and Hindi, abbreviations
   expanded, follow-ups completed from the chat). It does not search.
3. **Semantic search** (pgvector, cosine) finds the paragraphs, only within documents the person may
   see and has in scope, at most 3 per document.
4. **The LLM answers from those paragraphs only** and cites each claim. If nothing matches, it says
   so; the question is logged for Reports.

## 4. Architecture

```
Browser (Next.js 16, React 19, Zustand)
   │  JWT bearer token · lists without document text · text loaded per document
   ▼
API (FastAPI, Python 3.11)          app/main.py — endpoints
   ├─ policy.py   who may see / change what (the only place access is decided; unit-tested)
   ├─ rag.py      embeddings, search, answers        ├─ extract.py  file reading, suggestions
   ├─ ocr.py      Tesseract                          ├─ notices.py  notifications, reminder emails
   ├─ auth.py     accounts (bcrypt), tokens          ├─ export.py   Word export
   └─ store.py    records in PostgreSQL (JSONB)
   ▼
PostgreSQL 16 + pgvector — one database: records, credentials, blocks (embeddings)
OpenAI — gpt-4o (answers), gpt-4o-mini (query rewriting), text-embedding-3-small
```

## 5. Running it locally

```bash
# backend (needs Tesseract 5 with eng, hin and osd language files)
cd backend && python -m venv .venv && .venv/Scripts/pip install -r requirements.txt -r requirements-dev.txt
cp .env.example .env          # fill in OPENAI_API_KEY and JWT_SECRET
.venv/Scripts/python -m app.cli create-admin --login-id <id> --name "<name>"
.venv/Scripts/python -m uvicorn app.main:app --port 8000

# frontend
cd frontend && npm ci && npx next dev --port 3000
```
With `DATABASE_URL` blank, a local PostgreSQL (pgserver) starts with its data in `PG_DATA_DIR`.

## 6. Tests

| What | Command |
|---|---|
| Access rules + API (separate `svsu_test` database, OpenAI stubbed) | `cd backend && python -m pytest` |
| Browser journeys (both servers running) | `cd frontend && E2E_ADMIN_ID=… E2E_ADMIN_PASS=… npx playwright test` |
| Types and lint | `npx tsc --noEmit && npx eslint app components lib` |

GitHub Actions runs the backend tests, type-check, lint and build on every push.

## 7. Operations

- **Backups:** `python -m app.cli backup --to D:/backups/svsu` (daily from Task Scheduler/cron;
  keeps 30). Restore with `pg_restore --clean --dbname <DATABASE_URL> <file>`.
- **Reminder emails:** set `SMTP_*` in `.env`; otherwise reminders show in the app only.
- **Production:** set `DATABASE_URL`, a long random `JWT_SECRET`, `CORS_ORIGINS` to the real site,
  and leave `DEV_ADMIN_USER`/`DEV_ADMIN_PASS` blank. The API refuses to start with the default secret.

## 8. Data source

The project's own PostgreSQL database (with pgvector). The old EMS connection was removed.
