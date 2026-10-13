# What's left

How to build all of this — order, design and effort — is in [docs/PLAN.md](docs/PLAN.md).

Current state: login, all 12 screens, uploads with OCR (Tesseract; Textract wired in),
search and cited answers from PostgreSQL + pgvector, light/dark themes — built and tested locally.
Below is what still needs doing, most important first.

## 1. Must fix before real staff use it
- [x] **Server-side permissions.** One access policy (`backend/app/policy.py`, 23 unit tests) now
      filters everything the browser receives and everything `/ask` may cite; writes are checked per
      role, chats/bookmarks are private, and the server writes the audit log.
- [ ] **Real tables and paginated APIs** (Plan Phase 0.1, 0.3, 0.8) — `/records` still loads all of a
      person's data at once; fine now, slow at thousands of documents.
- [ ] **Keep the original files.** Uploads save only the extracted text. Store the original PDF / scan /
      image and let people view and download it.
- [x] **Remove sample data.** Removed (backup in `D:/PostgreSQL/backups/`); new databases start
      empty unless `DEMO_DATA=true`.
- [ ] **Real administrator.** `python -m app.cli create-admin` is ready — run it for the real admin,
      then clear `DEV_ADMIN_USER` / `DEV_ADMIN_PASS` in `backend/.env`. Users can now change their
      own password.
- [ ] **Secrets.** Rotate the OpenAI API key (it was shared in chat) and set a long random `JWT_SECRET`.

## 2. Prototype features still missing or simplified
- [ ] Export an answer / conversation as a cited summary (PDF or Word)
- [ ] Deadline reminders (email / ERP notification) and the notifications bell
- [ ] Compare two documents side by side; "Report conflict" from an answer
- [ ] "Request a document" and "Assign" for unanswered questions
- [ ] Link related documents and "Add revision" from the document page
- [ ] Admin: rename tags; make the access-level grid actually control access

## 3. Not tested or not set up yet
- [ ] **AWS Textract** — needs `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` in `backend/.env`
- [ ] **Hindi OCR quality** — about 77% on a test scan; Hindi uploads need a human check of the
      extracted text before submitting
- [ ] Automated tests (backend API + key screens)
- [ ] Production deployment: a server, a production PostgreSQL with the `vector` extension
      (`DATABASE_URL`), HTTPS, and process management
- [ ] Update `docs/instructions.md`, `docs/design.md`, `docs/rules.md` — they still describe the
      EMS connection, SQLite and the old green theme
