# What's left

The October 2026 scan's fixes are recorded in [docs/FIXES.md](docs/FIXES.md); longer-term work and
its design are in [docs/PLAN.md](docs/PLAN.md).

Current state: login, all 12 screens and every prototype feature; uploads with OCR (Tesseract,
Hindi + English), duplicate checks and drafts; cited answers from PostgreSQL + pgvector; access
enforced on the server; notifications and reminders; Word/PDF export; light and dark themes.
Tested by 35 backend tests (policy + API) and 3 browser journeys.

## 1. Owner actions (can't be done in code)
- [ ] **Scrub the EMS server details from the public git history** (commands in docs/FIXES.md 1.1),
      and tell IT the server address was public.
- [ ] **Rotate the OpenAI key** and the **EMS password** that were shared in chat.
- [ ] **Create the real administrator** (`python -m app.cli create-admin`), then clear
      `DEV_ADMIN_USER` / `DEV_ADMIN_PASS` in `backend/.env`.
- [ ] Schedule the daily backup (`python -m app.cli backup`) and try one restore.

## 2. Before many people use it (PLAN.md)
- [ ] **Real tables, migrations (Alembic) and paginated APIs** (Phase 0.1, 0.3, 0.8). Lists already
      leave out document text, but `/records` still sends every record a person may see.
- [ ] **Keep the original files** (Phase 1.1) — today only the extracted text is stored.
- [ ] **Background processing for uploads** (Phase 1.2) — OCR no longer blocks other people, but a
      long scan still keeps the uploader waiting.
- [ ] Secure-cookie sessions instead of a token in the browser (Phase 0.7).

## 3. Not set up yet
- [ ] Hindi OCR quality — about 62–77% on test scans; check Hindi text before submitting.
- [ ] Production deployment: server, managed PostgreSQL with `vector`, HTTPS, `CORS_ORIGINS`,
      SMTP for reminder emails.
