# Fix plan — from the October 2026 project scan

Everything the deep scan found, in the order it is being fixed. Each phase is committed on its own.
Longer-term work (real tables, background jobs, deployment) stays in [PLAN.md](PLAN.md).

## Phase 1 — Security (first)
| # | Fix | How |
|---|---|---|
| 1.1 | EMS server address, DB user and DB name in `docs/instructions.md` and public git history | Remove from the doc; rewrite history with `git filter-repo --replace-text`; force-push. Backup mirror kept on D: |
| 1.2 | Uploader can change text/visibility of a published document | `policy.write_error`: non-approvers may only edit their own unpublished documents. Tests added |
| 1.3 | Admin can demote, deactivate or delete themselves (lockout) | Server refuses changes to your own role/active flag, and removing the last active Administrator |
| 1.4 | Default sign-in secret, CORS `*` | Server refuses to start with the default `JWT_SECRET` unless the test admin (dev mode) is on; CORS origins from `CORS_ORIGINS` |
| 1.5 | Test admin login, OpenAI key | Owner action: create the real admin, clear `DEV_ADMIN_*`, rotate the OpenAI key |

## Phase 2 — "Looks saved but isn't" and other bugs
| # | Fix |
|---|---|
| 2.1 | `save`/`remove` in the browser roll back and show the server's reason when the server refuses |
| 2.2 | Buttons the server would refuse are hidden for that role (deadline Done, Withdraw/Restore, collection rename/delete) |
| 2.3 | Upload accepts only what the server can read (no `.doc`/`.xls`) |
| 2.4 | Uploaders: see their own pending documents in Library, resubmit after "Changes requested", no dead "Review queue" link |
| 2.5 | No "SAMPLE" watermark or fake signature on real uploads |
| 2.6 | Deleting a document also deletes its deadlines and bookmarks and removes it from collections |
| 2.7 | AI settings take effect: max sources, default language, history-only rule, log unanswered, show confidence |
| 2.8 | One feedback entry per answer; chat dates from a timestamp; correct "answers this month" |

## Phase 3 — Speed
| # | Fix |
|---|---|
| 3.1 | Read only the record kinds a request needs (not the whole database) |
| 3.2 | Library and dashboards get documents without their full text; text loads when a document is opened |
| 3.3 | Upload processing runs off the main thread, so other people aren't blocked |
| 3.4 | Embeddings are sent in batches, so large documents save |

## Phase 4 — Missing prototype features
Ask: export, report conflict, compare documents, request a document, feedback reason ·
Document: link documents, add revision, add deadline, edit tags · Upload: duplicate check, save draft,
link to older version · Review: checklist, real automatic checks · Deadlines: add/edit/delete,
reminders · Reports: weekly chart, copy CSV, assign · Admin: rename tags, edit/delete users ·
Notifications bell · Viewer page buttons.

## Phase 5 — Tests, tooling, docs
API tests (pytest + test database) · Playwright browser tests · GitHub Actions CI · pinned
dependency versions · database backup script · rewrite `instructions.md`, `design.md`, `rules.md`.
Migrations (Alembic) come with the move to real tables (PLAN.md 0.1).
