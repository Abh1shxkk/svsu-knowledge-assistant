# SVSU Knowledge Assistant — Project Rules

> Audience: everyone contributing code to this project (human or AI).
> These are hard rules. If a rule blocks you, raise it — don't quietly break it.

---

## 1. Security & secrets (top priority)

1. **No secret ever committed.** No API keys, DB passwords, connection strings, or tokens in
   source, config, fixtures, or docs. This includes the MSSQL password and the OpenAI key.
   - *Context:* this project has already had an OpenAI key leaked via a committed `.env` in a
     related repo, and the DB password was shared in plaintext chat. Treat both as compromised
     until rotated.
2. **All secrets come from `.env`** (git-ignored) loaded via `pydantic-settings`. Commit a
   `.env.example` with **empty** values and comments only.
3. **`.gitignore` includes `.env` from commit #1.** Verify before the first push.
4. **Never pass passwords on a command line.** Use env vars (e.g. `SQLCMDPASSWORD`) — command
   lines land in shell history and process lists.
5. **Rotate on exposure.** If a secret is ever printed, logged, or committed, rotate it, don't
   just delete the line — git history and logs keep it.
6. **Least privilege on the DB.** The app's SQL login should be read-only where it only reads
   EMS data; write access limited to the app's own tables/schema.
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

1. **Enforce authorization server-side, always.** The frontend hides things for UX; the API must
   independently deny. Never trust a client-supplied role.
2. Roles: `admin` (full) and `viewer` (restricted). Viewers cannot see restricted docs, pending
   docs, or admin/upload/review/reports modules.
3. Every document-returning endpoint (library, ask, viewer, collections, deadlines) applies the
   same permission filter.
4. Auth via JWT with short-lived access tokens; verify on every request.

---

## 5. Document lifecycle

1. A document is **Draft → Pending → Published** (or **Rejected**). Only **Published** docs are
   visible in the library and usable in answers.
2. Publishing is an explicit approver action and is **audit-logged** (who, when).
3. Superseded documents are marked, not silently deleted; history is preserved.
4. Re-uploading a duplicate is detected and flagged, not silently indexed twice.

---

## 6. Database rules (MSSQL)

1. It is **Microsoft SQL Server (port 1433)**, not MySQL. Use `mssql+pyodbc`/`pymssql`, not a
   MySQL driver.
2. **Never run destructive SQL against the EMS DB.** Reads only, unless the table is explicitly
   owned by this app. No `DROP`/`TRUNCATE`/schema changes on shared tables.
3. All queries parameterized — **no string-concatenated SQL** (injection + correctness).
4. Map the real schema before coding ingestion; don't assume column names.
5. Connections are pooled and time-bounded; handle the DB being unreachable gracefully (it has
   already timed out from outside the network — build for allowlist/VPN realities).

---

## 7. Code quality

1. **Match the surrounding code** — naming, structure, comment density, idiom.
2. Backend: type hints + Pydantic models at the boundaries; services layer (`app/services/*`) does
   the work, routers stay thin (mirror the existing GenAI repo layout).
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
