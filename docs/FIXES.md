# Fix plan — from the October 2026 project scan

Everything the deep scan found, and how each item was fixed. Longer-term work (real tables,
background jobs, deployment) stays in [PLAN.md](PLAN.md).

## Phase 1 — Security
| # | Fix | Status |
|---|---|---|
| 1.1 | EMS server address, DB user and DB name in `docs/instructions.md` and the public git history | Removed from the doc. **History rewrite needs the owner** — see below |
| 1.2 | Uploader could change the text or access of a published document | Fixed in `policy.write_error`: uploaders only edit their own Draft/Pending/Changes-requested documents. Tested |
| 1.3 | Admin could demote, deactivate or delete themselves | Server refuses it, and keeps at least one active administrator. Tested |
| 1.4 | Weak sign-in secret, CORS open to every site | New 64-character `JWT_SECRET`; the API refuses to start with the default secret outside dev mode; CORS limited to `CORS_ORIGINS` |
| 1.5 | Viewers could overwrite anyone's feedback or unanswered-question records | Only approvers manage them; feedback has an owner; unanswered questions are logged by the server |
| 1.6 | Test admin login, OpenAI key | **Owner action** — see TODO.md |

**Scrubbing the history (run once, from the project folder).** A backup of the repo is in
`D:/backups/svsu-before-scrub.git`.
First create `../replace.txt` **outside the repo** with three lines, `<value>==>[removed]`, one each
for the old EMS server address, database user and database name (never commit this file). Then:
```bash
backend/.venv/Scripts/python -m git_filter_repo --replace-text ../replace.txt --force
git remote add origin https://github.com/Abh1shxkk/svsu-knowledge-assistant.git
git push --force origin main
```
GitHub may keep old commits reachable by their id for a while. Ask GitHub Support to purge cached
views, or make the repository private.

## Phase 2 — "Looks saved but isn't" and other bugs — done
- The browser rolls a change back and shows the server's reason when a save or delete is refused.
- Buttons are shown only to roles the server allows (deadline Done, Withdraw/Restore, Edit,
  collection rename/delete, Review queue links).
- Upload accepts only what the server reads (no `.doc`/`.xls`; the message says to convert them).
- Uploaders see their own drafts and pending documents in the Library, and can resubmit after
  "Changes requested".
- No "SAMPLE" watermark or "sd/-" signature on real uploads.
- Deleting a document removes its deadlines, bookmarks, conflicts and links, and takes it out of collections.
- AI settings take effect: passages per answer, default language, history-only rule, logging of
  unanswered questions, showing the evidence label.
- One feedback entry per answer; chats grouped by real dates; "Questions this month" counts everyone's
  questions from a server-side usage log.

## Phase 3 — Speed — done
- Requests read only the record kinds they need.
- Lists leave out document text; it loads when a document is opened. Library text search runs on the server.
- Upload processing runs on a worker thread, so other people aren't blocked.
- Embeddings are sent in batches of 256, so long documents save.

## Phase 4 — Prototype features — done
Ask: export answer or conversation (Word, print/PDF, copy), compare documents, report conflict,
request a document, "what was wrong" feedback · Document: link documents, add revision, add/remove
tags, add deadline, submit draft · Upload: duplicate check, save draft, revision and related
documents · Review: reviewer checklist, real automatic checks (missing fields, duplicate reference,
near-identical active document, empty pages, low OCR confidence, dates) · Deadlines: add, edit,
delete, personal reminders (in-app, email when SMTP is set) · Reports: questions per week, copy as
CSV, assign, request document, compare · Admin: rename tags, edit and delete users, passages per
answer · Notifications bell · Viewer page buttons · Rename conversation.

## Phase 5 — Tests, tooling, docs — done
10 API tests on a separate test database (plus 25 policy tests) · 3 Playwright browser journeys ·
GitHub Actions CI · pinned Python versions (npm is pinned by `package-lock.json`) ·
`python -m app.cli backup` · `instructions.md`, `design.md` and `rules.md` rewritten.
Migrations (Alembic) come with the move to real tables (PLAN.md 0.1).
