# What's left

How to build all of this — order, design and effort — is in [docs/PLAN.md](docs/PLAN.md).

Current state: login, all 12 screens, uploads with OCR (Tesseract; Textract wired in),
search and cited answers from PostgreSQL + pgvector, light/dark themes — built and tested locally.
Below is what still needs doing, most important first.

## 1. Must fix before real staff use it
- [ ] **Server-side permissions.** The browser currently receives every document (including
      "Management Only" and pending ones), and `/ask` trusts the browser's list of allowed documents.
      The server must filter documents by the signed-in person's role.
- [ ] **Keep the original files.** Uploads save only the extracted text. Store the original PDF / scan /
      image and let people view and download it.
- [ ] **Remove sample data.** The 16 prototype documents, sample users ("Dr. Neha Sharma" etc.),
      audit log, feedback and deadlines are still loaded from `backend/seed.json`.
- [ ] **Real administrator.** Replace the local test admin login with a real admin account,
      then clear `DEV_ADMIN_USER` / `DEV_ADMIN_PASS` in `backend/.env`.
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
