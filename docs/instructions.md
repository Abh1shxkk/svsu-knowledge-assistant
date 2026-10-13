# SVSU Knowledge Assistant — Build Instructions

> **What this is:** A role-based **RAG** (Retrieval-Augmented Generation) system for official
> university records. Staff upload documents (letters, notices, circulars, policies); an AI model
> indexes them and answers questions **grounded in those documents**, always citing the exact
> source page/passage. It never answers from general knowledge — only from the ingested data.

Audience: the engineers building this project.

---

## 1. Product in one paragraph

Subharti University (SVSU) staff need to find answers buried across thousands of official
documents. Today that means manually digging through PDFs. This app ingests those documents,
makes them searchable in plain language (English + Hindi), and lets a user ask a question and get
a **cited, document-grounded answer** — with the original passage shown side-by-side. Access is
controlled by role: administrators see everything; viewers only see what they are permitted to.

---

## 2. Core modules (functionality carried over from the prototype)

The HTML prototype (`svsu-assistant.html`) is the **functional spec**. We take its *modules and
behavior*, not its UI. Build these:

| # | Module | What it does |
|---|--------|--------------|
| 1 | **Ask (AI chat)** | Natural-language Q&A grounded in documents. Every answer cites source doc + page + passage. Can scope a question to one file or a Collection. Multi-turn chat history. |
| 2 | **Document Library** | Browse/search all permitted documents. Filters (subject, dept, audience, type, status, visibility, date). List + card/grid views. Opens a paginated **document viewer**. |
| 3 | **Document Viewer** | Paginated view of the source document with a letterhead, selectable text blocks, highlight of the cited passage, and "bookmark passage" / "ask about this document". |
| 4 | **Upload pipeline** | Add files → extract text (OCR for scans) → auto-classify (type/subject) → auto-tag → chunk → embed → index. Shows a live processing queue. Duplicate detection. |
| 5 | **Review & Approvals** | A document is **not searchable or visible in the library until an approver publishes it.** Draft → pending → published/rejected workflow. |
| 6 | **Collections** | Group documents for a team/task, then ask questions scoped to just that group. |
| 7 | **Actions & Deadlines** | Auto-extract dates and required actions from documents; each item links back to the source passage. |
| 8 | **Saved Chats & Bookmarks** | Keep conversations, answers, and document passages for later. |
| 9 | **Reports & Feedback** | Usage figures over time; questions/feedback that need follow-up. |
| 10 | **Administration** | Manage people, roles/access, the tag vocabulary, and answer settings. |
| 11 | **Roles & permissions** | `admin` (e.g. Deputy Registrar) vs `viewer` (e.g. HOD). Restricted docs, pending docs, and admin modules are hidden from viewers. |
| 12 | **Multilingual** | English + Hindi (Devanagari). Must handle Hindi in documents, questions, and answers. |

---

## 3. Architecture (high level)

```
┌────────────┐     ┌──────────────────────── Backend (FastAPI) ───────────────────────┐
│  Frontend  │     │                                                                   │
│ Next.js +  │────▶│  /auth   /documents   /ask   /upload   /collections   /admin ...  │
│ Tailwind   │ API │     │          │         │        │                               │
│ (Apple UI) │◀────│     ▼          ▼         ▼        ▼                               │
└────────────┘     │  Auth/RBAC  Ingestion  RAG      OCR + classify + tag              │
                   │              pipeline  engine                                     │
                   └──────┬──────────────┬────────────────┬────────────────────────────┘
                          │              │                │
                   ┌──────▼─────┐  ┌─────▼──────┐   ┌──────▼──────┐
                   │  MSSQL     │  │  Qdrant    │   │  OpenAI     │
                   │ (metadata, │  │ (vector    │   │ (embeddings │
                   │  users,    │  │  index /   │   │  + GPT-4o   │
                   │  app data, │  │  chunks)   │   │  answers)   │
                   │  EMS src)  │  └────────────┘   └─────────────┘
                   └────────────┘
```

**The RAG flow (the heart of the app):**
1. User asks a question (optionally scoped to a file/collection).
2. Embed the question (OpenAI `text-embedding-3-large`).
3. Vector search in Qdrant → top-K relevant chunks **the user is permitted to see**.
4. Build a prompt: system instructions + retrieved chunks + question.
5. GPT-4o generates an answer **using only the retrieved chunks**, with inline citations.
6. Return the answer + the source passages (doc id, page, chunk) so the UI can show/highlight them.
7. If nothing relevant is retrieved → say "I couldn't find this in the documents," never invent.

---

## 4. Recommended tech stack

Chosen to (a) reuse what already works in the `GenAI` repo, (b) match the existing **MSSQL** EMS
database, and (c) support the premium frontend.

### Backend
- **Language/framework:** Python 3.11 + **FastAPI** (same shape as the GenAI repo: `app/services/*`).
- **RAG/orchestration:** LangChain (as in the GenAI repo) or a thin custom layer.
- **LLM + embeddings:** **OpenAI** — `gpt-4o` for answers, `text-embedding-3-large` for embeddings.
- **Vector DB:** **Qdrant** (already used in the GenAI repo).
- **Relational DB:** **Microsoft SQL Server** (the existing EMS DB — port **1433**).
  - Driver: `pyodbc` (or `pymssql`) via **SQLAlchemy** (`mssql+pyodbc`). *Not* a MySQL driver.
- **Document parsing:** `pypdf`/`pdfplumber` for text PDFs; **OCR** for scans via Tesseract
  (`pytesseract`) or GPT-4o vision. Hindi OCR: Tesseract `hin` language pack.
- **Auth:** JWT (access + refresh), password hashing with `passlib[bcrypt]`.
- **Background jobs:** the ingestion pipeline runs async (FastAPI `BackgroundTasks` to start; move
  to **Celery + Redis** or RQ once volume grows).
- **Config:** `pydantic-settings` reading from `.env` (never hardcode secrets — see `rules.md`).

### Frontend
- **Framework:** **Next.js (App Router) + TypeScript**.
- **Styling:** **Tailwind CSS** with a custom design-token layer (see `design.md`) for the
  Apple-style premium aesthetic. Component primitives from **shadcn/ui** (headless, restyled).
- **State/data:** TanStack Query for server state; minimal global state (Zustand) for UI.
- **Fonts:** system font stack (`-apple-system`/SF Pro feel) for UI; `Noto Sans/Serif Devanagari`
  for Hindi.

### Infra
- **Containers:** Docker Compose for local (api, qdrant, redis) — SQL Server is external/existing.
- **Env:** `.env` per service, git-ignored. Secrets via the host/orchestrator in production.

---

## 5. Data source

The project's own PostgreSQL database (with pgvector). The old EMS connection was removed.

---

## 6. Build order (suggested milestones)

1. **M0 — Access & schema.** Reach the MSSQL DB, run the check query, map the real schema. Confirm
   where documents/files live (rows? file paths? blobs?).
2. **M1 — Backend skeleton.** FastAPI + settings + MSSQL connection + Qdrant + OpenAI wiring. Health checks.
3. **M2 — Ingestion pipeline.** Upload → parse/OCR → chunk → embed → index. Review/publish gate.
4. **M3 — RAG ask endpoint.** Retrieval + grounded answer + citations + permission filtering.
5. **M4 — Frontend shell.** Apple-style layout, auth, Library + Viewer.
6. **M5 — Ask UI.** Chat with citations and source panel.
7. **M6 — Collections, Actions/Deadlines, Saved, Reports, Admin.**
8. **M7 — Hardening.** Roles enforced server-side, audit log, Hindi QA, performance.

---

## 7. Open questions to resolve with the stakeholder

- Where exactly do source documents live — as files on disk, URLs, or BLOBs inside the EMS DB?
- Expected volume (number of documents, total size) → affects OCR/indexing cost and infra.
- Is OpenAI contractually allowed for this (potentially sensitive) official data? (Confirmed
  "Cloud, OpenAI OK" direction — get it in writing from the university.)
- SSO/existing identity system to integrate with, or standalone auth?
