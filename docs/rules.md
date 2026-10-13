# SVSU Knowledge Assistant — Project Rules

> Audience: everyone contributing code to this project (human or AI).
> These are hard rules. If a rule blocks you, raise it — don't quietly break it.

---

## 1. Security & secrets (top priority)

1. **No secret ever committed.** No API keys, DB passwords, connection strings, or tokens in
   source, config, fixtures, or docs — and no internal server addresses, user names or database
   names either. This includes the OpenAI key and the database URL.
   - *Context:* an OpenAI key and EMS credentials were once shared in plaintext chat, and EMS server
     details were committed to this repo's history. Treat anything exposed as compromised until rotated.
2. **All secrets come from `.env`** (git-ignored) loaded via `pydantic-settings`. Commit a
   `.env.example` with **empty** values and comments only.
3. **`.gitignore` includes `.env` from commit #1.** Verify before the first push.
4. **Never pass passwords on a command line.** Use env vars or hidden prompts (as
   `python -m app.cli create-admin` does) — command lines land in shell history and process lists.
5. **Rotate on exposure.** If a secret is ever printed, logged, or committed, rotate it, don't
   just delete the line — git history and logs keep it.
6. **Least privilege on the DB.** In production the app's database user owns only this app's
   database; no superuser.
7. **Never send secrets to third parties.** Don't put the user's email, DB creds, or internal
   data into request headers/URLs/payloads to unrelated services.

---

## 2. Data handling & privacy

1. This is **official university data** — treat it as confidential.
2. Only data the university has approved may leave the network. OpenAI is approved for
   generation/embeddings per the stakeholder; nothing else goes to a third party without sign-off.
3. **Log for audit, not for leak.** Log who asked what and which docs were accessed; never log
   full document contents or secrets.
4. PII and restricted documents must respect the permission model everywhere (see §4).

---

## 3. RAG correctness (the product's core promise)

1. **Answers must be grounded in retrieved documents only.** The model must not answer from
   general knowledge. System prompt enforces this.
2. **Always cite.** Every answer returns the source doc id, page, and passage used. No citation →
   no claim.
3. **Refuse gracefully.** If retrieval finds nothing relevant, respond "I couldn't find this in
   the documents" — never fabricate or guess.
4. **Retrieval is permission-filtered before generation**, not after. A user must never receive an
   answer drawn from a document they aren't allowed to see.
5. **Only published documents are retrievable.** Drafts/pending/rejected docs are excluded from
   the index used for answering (see §5 review gate).
6. Hindi and English queries must both work against the same corpus.

---

## 4. Access control & roles

1. **Enforce authorization server-side, always.** `backend/app/policy.py` is the single place that
   decides who may see or change what; every endpoint goes through it. The frontend only hides
   buttons the server would refuse. Never trust a client-supplied role or owner.
2. Roles: **Administrator, Approver, Uploader, Viewer** (see instructions.md §2). Document access
   levels (Public, All Staff, Department only, Management Only) are mapped to roles by the matrix in
   Administration → Access levels, and the server enforces it.
3. Every response is filtered: documents, deadlines, collections, bookmarks, search, `/ask`
   retrieval and exports only ever include documents the person may open.
4. Chats, bookmarks, reminders and preferences are private to their owner; the server records the
   owner, not the browser.
5. Nobody can remove their own administrator access, and there is always one active administrator.
6. Every rule change gets a test in `tests/test_policy.py` or `tests/test_api.py`.

---

## 5. Document lifecycle

1. **Draft → Pending → Active** (or **Changes requested → Pending**, or **Rejected**). Later:
   **Superseded** (a revision was approved), **Withdrawn**, **Expired**. Only Active, Superseded and
   Expired documents are used in answers; Superseded and Expired only as history.
2. Uploaders work only on their own Draft, Pending or Changes-requested documents and can only
   save or submit them. Publishing, rejecting and withdrawing are approver actions.
3. Every change is **audit-logged by the server** (who, what, when). The browser cannot write the log.
4. Documents are replaced by revisions, not edited in place, once published.
5. Uploads that repeat an existing document (same text or reference number) are flagged.

---

## 6. Database rules (PostgreSQL)

1. One PostgreSQL 16 database with the `vector` extension holds everything.
2. All queries go through SQLAlchemy — **no string-built SQL**.
3. Tests use their own database (`svsu_test`) and must never touch the real one.
4. Back up daily (`python -m app.cli backup`) and test a restore before going live.

---

## 7. Code quality

1. **Match the surrounding code** — naming, structure, comment density, idiom.
2. Backend: type hints and Pydantic models at the boundaries; endpoints in `main.py` stay thin and
   call the modules (`policy`, `rag`, `extract`, `store`, …). No extra layers until they're needed.
3. Frontend: TypeScript strict; no `any` without a written reason; components small and composed.
4. **No secrets, tokens, or real data in tests or fixtures.** Use synthetic data.
5. Handle errors explicitly; fail loudly in dev, gracefully in prod. No silent `except: pass`.
6. Report outcomes honestly — if something is untested or a step was skipped, say so.

---

## 8. UI rules

1. Follow `design.md` tokens — **no hardcoded colors, sizes, or shadows** in components.
2. Apple-aesthetic, card-based, premium. Discard the prototype's visual style; keep its behavior.
3. WCAG AA, keyboard-complete, `prefers-reduced-motion` and dark mode honored.
4. Hindi must render correctly and never clip; all user-facing strings are translatable.

---

## 9. Git & workflow

1. Never commit to the default branch directly — branch, then PR.
2. Commit/push only when asked.
3. No secret in any commit (§1). Review the diff before every commit.
4. Conventional, descriptive commit messages.

---

## 10. AI-assistant working rules (for Claude / agents on this repo)

1. Before recommending a file/flag/table, verify it still exists.
2. Don't print or echo secrets, even when asked to "just show it" — point to where the owner can
   retrieve it themselves.
3. For outward or hard-to-reverse actions (sending data out, deleting, writing to the shared DB),
   confirm first unless explicitly authorized.
4. Prefer small, reviewable changes; explain trade-offs with a recommendation, not a survey.
