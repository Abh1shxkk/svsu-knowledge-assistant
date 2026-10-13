# SVSU Knowledge Assistant — Design System (v1)

> Audience: anyone changing the UI. This describes the design as built. All values live as CSS
> variables in `frontend/app/globals.css`; components use the variables, never raw values.

**Direction:** a calm, premium, card-based dashboard (Donezo reference for layout), with a
**petrol-blue accent on warm stone (light) and warm charcoal (dark)**. Rounded cards, a collapsible
sidebar, subtle motion. We keep the prototype's functionality and names, not its look.

---

## 1. Principles

1. **Calm and spacious.** Generous whitespace; depth from soft shadows, few borders.
2. **One clear action per view.** One primary (accent) button; everything else recedes.
3. **Color carries meaning only.** Near-neutral base, one accent; status colors only for status,
   always with an icon or label.
4. **Documents look like documents.** Letters render on a paper surface in a serif face.
5. **Accessible by default.** WCAG AA contrast, visible focus, keyboard-complete, reduced motion.

## 2. Tokens

### Color
| Token | Light | Dark | Use |
|---|---|---|---|
| `--bg` | `#f5f4f1` | `#141312` | app canvas |
| `--surface` / `--surface-2` / `--surface-3` | `#ffffff` / `#f8f7f4` / `#efede8` | `#1c1b19` / `#22211f` / `#2b2a27` | cards, insets, hovers |
| `--line` / `--line-2` | `#e7e4de` / `#d8d4cc` | `#2e2c29` / `#3c3a36` | hairlines |
| `--fg` / `--fg-2` / `--fg-3` | `#1b1a18` / `#57534d` / `#78736b` | `#f1efea` / `#c3beb5` / `#958f85` | text: primary, secondary, muted |
| `--accent` / `--accent-2` / `--accent-soft` | `#1f5f73` / `#174b5c` / `#e6eff1` | `#4f97ad` / `#63a7bc` / `#1d2f35` | primary actions, active nav, chips |
| `--chart` | `#0a7aa0` | `#2a9fc7` | single-series charts |
| `--green` · `--amber` · `--red` (+ `-soft`) | `#2f7a4a` · `#9a6a12` · `#b4452c` | `#6fbf8a` · `#e3b25a` · `#e58a73` | status only: ok · warning · problem |

Dark mode is chosen by the person (top bar or My profile) and stored per browser; it is its own
palette, not an automatic inversion.

### Type
- **UI:** Geist, with Noto Sans Devanagari for Hindi (`--f-ui`).
- **Headings and documents:** Source Serif, with Noto Serif Devanagari (`--f-doc`).
- **Reference numbers and code:** Geist Mono (`--f-mono`).
- Body 14px/1.5; page titles 26px serif; card titles 15–16px semibold; numbers tabular.

### Shape and motion
`--r: 16px` cards (pills and buttons fully rounded), soft layered shadows, `--ease:
cubic-bezier(.2,.8,.2,1)` for the sidebar collapse and hovers. Motion is off under
`prefers-reduced-motion`.

## 3. Layout

- **Shell:** collapsible left sidebar (icon rail when collapsed, slide-over on phones, no scrollbar),
  top bar with page title, document search, Ask AI, notifications bell, theme toggle and profile.
- **Content:** centered wrap with 16–24px gutters; no horizontal page scroll down to 390px wide.
- **Viewer:** documents open in a panel beside the page, with citation stepping and page buttons.

## 4. Components

Card · KPI/stat tile · tile with chart · button (primary, default, ghost, danger, small) · input
and select · pill (status) · tag · chips (checkbox groups) · tabs · list row (`.li`) · timeline ·
note/banner (info, warn, bad, ok) · modal and drawer (`ModalFoot` for actions) · dropdown
(notifications) · toast · empty state · paper (document page, letterhead for sample documents only).

Charts are single-series and monochrome (`--chart`), with values on hover and a hidden data table
for screen readers. Build any new chart with the `dataviz` guidance; never a dual axis.

## 5. Signature screens

- **Dashboard:** greeting hero with Upload / Ask actions, four stat tiles, chart tiles (uploads
  per month, documents by subject, deadlines per week, documents in force), recent documents and
  conversations, unanswered questions, and a deadlines calendar panel.
- **Ask AI:** history column, conversation, scope and filter controls, answers with numbered
  citations, sources, evidence label, and actions (copy, bookmark, export, rate, compare, request).
- **Library / document record:** filterable list or grid; record with overview, preview, text,
  approvals, versions, related, access, deadlines and bookmarks tabs.

## 6. Accessibility & language

- AA contrast for every text/background pair in both themes.
- Visible `:focus-visible` ring; every control reachable by keyboard; dialogs labelled.
- Hindi text gets `lang="hi"` and Devanagari fonts; never clipped.
- Meaning never by color alone.
