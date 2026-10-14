# Answer quality, speed and sign-in security — plan

Written for: the project team. Each step comes from a weakness seen when testing with real SVSU
circulars (14 questions with known answers: 13 correct after the October fixes). Each step is built,
tested (API tests + browser tests on the test server) and deployed on its own; the 14 questions and the
automatic quality test are re-run at the end to show the effect.

| # | Step | Weakness it fixes | Cost per question |
|---|---|---|---|
| 1 | **Re-ranking** — search fetches ~30 candidate paragraphs; a small model scores each against the question; the best 8 are read | Similar documents (every event has a committee table) — the wrong event's table was picked | ≈ ₹0.1 |
| 2 | **Fact check** — after answering, a small model checks every statement against the cited passages; unsupported ones are flagged on screen | A website "from its own knowledge"; a total it added up itself | ≈ ₹0.1–0.2 |
| 3 | **Streaming** — the answer appears as it is written, with progress ("Searching…", "Reading 8 passages…") | 5–8 s of waiting before anything shows | — |
| 4 | **Expiry** — expiry dates suggested at upload (an event notice expires after the event); documents past expiry become Expired automatically and are used as history only | Past events answered as if current | — |
| 5 | **Two-step verification** — authenticator-app codes (TOTP) with one-time recovery codes; administrators can require it for Administrators and Approvers and reset it; repeated wrong passwords or codes lock sign-in for a few minutes | Password-only sign-in, no limit on guessing | — |
| 6 | **"Needs a text check" list** — scanned documents with words OCR was unsure of, worst first, to correct with Edit text | OCR mistakes (handwritten numbers, faint print) found only by chance | — |

Later (not in this round): questions about the documents themselves ("circulars from the Registrar this
month") answered from document details; staff 👎 answers fed into the quality test automatically.

## Done when
- API tests cover each step; browser tests cover streaming, the fact-check warning, two-step
  sign-in (set-up, sign-in with a code, a recovery code, lock-out) and the check list.
- The 14 real questions score at least as well as before; the quality-test report is attached below.

## Results
(filled in after the round)
