# SVSU Knowledge Assistant — Design System (v0, draft)

> Audience: the engineers + designer building the UI.
>
> **Status: v0.5.** Direction locked: **Apple-website aesthetic** + **premium, card-based** UI,
> **beige/white/green** palette, dashboard layout based on the **Donezo** reference
> (Dribbble, `original-1ca571d7…`). We keep the prototype's **functionality**, not its UI — the
> prototype's "registry desk / navy rail" look is discarded. Palette + dashboard layout are now
> specified below; refine spacing/shadows during build.

---

## 1. Design principles (the Apple feel)

1. **Calm and spacious.** Generous whitespace. Let content breathe. Nothing is cramped.
2. **Content first, chrome last.** Minimal borders. Depth comes from soft shadows and subtle
   layering, not heavy lines.
3. **One clear action per view.** A single obvious primary action; everything else recedes.
4. **Soft, large-radius cards** on a light neutral canvas. Cards are the primary surface.
5. **Crisp typography.** Tight, confident headings; comfortable body. SF-style system font.
6. **Restraint in color.** A near-monochrome base with one accent. Color carries meaning only.
7. **Motion is subtle and physical.** Gentle ease, short durations. No bouncing or spinning.
8. **Accessible by default.** WCAG AA contrast, visible focus, full keyboard support, honored
   `prefers-reduced-motion` and `prefers-color-scheme`.

---

## 2. Design tokens

Define these as CSS variables + Tailwind theme extensions. Values are the v0 baseline; swap when
the reference example lands.

**Direction (from the Donezo reference):** warm **beige/cream canvas**, **white cards**, a
**forest/emerald green** accent. Apple's spacing and restraint, but warm instead of cool-grey.
Layout language mirrors Donezo: rounded white cards on a soft canvas, KPI tiles with a small
circular "open" button top-right, one tile filled with the accent, charts (bars + radial gauge)
inside their own cards, a light sidebar with a green active pill.

### Color — light (default)
```
--bg:            #f3efe7   /* app canvas — warm beige/cream */
--surface:       #ffffff   /* cards — crisp white on the beige */
--surface-2:     #faf7f1   /* inset / secondary surface — faint cream */
--border:        #e7e0d3   /* hairline (warm), used sparingly */
--fg:            #1c2b22   /* primary text — deep green-black */
--fg-2:          #4a5850   /* secondary text */
--fg-3:          #8a938b   /* muted / captions */
--accent:        #1f7a4d   /* forest/emerald green — primary actions, active */
--accent-hover:  #1a6a43
--accent-2:      #2e9d63   /* brighter green — charts, gradients */
--accent-soft:   #e4f0e8   /* tinted green backgrounds / chips */
--accent-ink:    #ffffff   /* text on accent surfaces */
--success:       #1f7a4d
--warning:       #b25000
--danger:        #c23b2e
--ring:          rgba(31,122,77,.35)  /* focus ring (green) */
```
> KPI "highlight" tile (like Donezo's filled green card): background `--accent` (or a subtle
> `linear-gradient(145deg,var(--accent),var(--accent-hover))`), text `--accent-ink`.

### Color — dark (`prefers-color-scheme: dark` and `[data-theme="dark"]`)
```
--bg:            #15130f   /* warm near-black */
--surface:       #211e18   /* cards — warm dark */
--surface-2:     #2a2620
--border:        #38332a
--fg:            #f1ede4   /* warm off-white */
--fg-2:          #b8b2a4
--fg-3:          #8a8578
--accent:        #46c586   /* brighter green for dark bg */
--accent-hover:  #5bd095
--accent-2:      #46c586
--accent-soft:   #16301f
--accent-ink:    #0e1a12
```
> Follow the artifact theming contract: define tokens on `:root`, redefine under
> `@media (prefers-color-scheme: dark){:root:not([data-theme="light"])}` **and** `:root[data-theme="dark"]`,
> and give `body` an explicit background.

### Typography
```
--font-ui:   -apple-system, BlinkMacSystemFont, "SF Pro Text", "Inter", system-ui, sans-serif;
--font-hi:   "Noto Sans Devanagari", var(--font-ui);     /* Hindi UI */
--font-hi-serif: "Noto Serif Devanagari", Georgia, serif; /* Hindi document body */
--font-mono: ui-monospace, "SF Mono", "JetBrains Mono", monospace;
```
Scale (desktop):
| Token | Size / line-height / weight | Use |
|-------|------|-----|
| display | 40 / 1.1 / 600 | hero / page title on dashboard |
| h1 | 28 / 1.2 / 600 | page titles |
| h2 | 22 / 1.25 / 600 | section titles |
| h3 | 17 / 1.3 / 600 | card titles |
| body | 15 / 1.5 / 400 | default |
| small | 13 / 1.45 / 400 | secondary |
| caption | 11.5 / 1.4 / 500 | labels, meta (tracking +.02em, uppercase for eyebrows) |

Headings use `letter-spacing: -0.015em` (Apple's tight display tracking).

### Spacing, radius, shadow, motion
```
--space: 4 8 12 16 20 24 32 40 56 72   /* 4px base scale */
--r-sm: 10px;  --r: 16px;  --r-lg: 22px;  --r-pill: 999px   /* large, soft radii */
--shadow-sm: 0 1px 2px rgba(0,0,0,.04), 0 1px 3px rgba(0,0,0,.06);
--shadow:    0 4px 16px rgba(0,0,0,.06), 0 1px 3px rgba(0,0,0,.05);
--shadow-lg: 0 12px 40px rgba(0,0,0,.10);     /* modals, popovers */
--ease: cubic-bezier(.4,0,.2,1);   --dur: 180ms;   --dur-lg: 260ms;
```

---

## 3. Layout

- **Max content width:** 1200–1280px, centered, with a 24px (mobile 16px) side gutter.
- **Shell:** a slim left sidebar (collapsible icon rail on narrow screens) + top bar + content.
  The sidebar is light/translucent (not the prototype's dark navy) — think a frosted
  `backdrop-filter: blur()` panel.
- **Grid:** 12-col fluid; cards snap to a responsive auto-fill grid
  (`repeat(auto-fill, minmax(280px, 1fr))`), gap 20–24px.
- **Responsive:** full support down to 390px phone width. No horizontal page scroll.

---

## 4. Core components

- **Card** — the primary surface. White, `--r` radius, `--shadow`, 20–24px padding, no visible
  border in light mode (shadow does the work); hairline border only in dark mode. Hover: lift
  shadow + 1px translateY on interactive cards.
- **Stat / KPI tile** — big tabular-number value, small caption label, optional trend chip.
  Used on the dashboard. (See `dataviz` skill before building any chart.)
- **Button** — primary: solid `--accent`, white text, pill or `--r-sm` radius, no border.
  Secondary: `--surface` with hairline. Ghost: text-only. Height 36–44px, confident padding.
- **Input / search** — `--surface-2` fill, no hard border, focus ring `--ring`. Rounded.
- **Pill / tag / status chip** — soft tinted background (`*-soft`), meaningful color only.
- **Document card** (Library grid) — thumbnail/preview, title, ref no., status pill, tags, date.
- **Chat bubble** — user vs assistant; assistant answers render markdown and show **numbered
  citations** that open the source passage in the viewer panel.
- **Source / citation panel** — docked beside the answer; highlights the cited passage.
- **Modal / sheet** — `--shadow-lg`, large radius, backdrop blur, generous padding.
- **Toast** — bottom, subtle slide-up, auto-dismiss.
- **Empty states** — calm, centered, with one clear next action (very Apple).

---

## 5. Signature screens

- **Dashboard** — modeled on the Donezo reference, retoned beige/white/green:
  - **Header row:** page title ("Dashboard") + one-line subtitle on the left; primary actions on
    the right (e.g. **+ Upload document**, **Import from EMS**) — primary is solid green.
  - **KPI row:** 4 tiles — e.g. **Total Documents**, **Pending Review**, **Questions this week**,
    **Deadlines due**. Each tile: small circular "open ↗" button top-right, big tabular number,
    tiny trend caption. The **first tile is the filled green highlight** (accent background), the
    rest are white cards. (Map to our data, not Donezo's "projects".)
  - **Middle row:** a wide **Usage Analytics** card (weekly bar chart, S–S, active bars in green,
    inactive hatched) + a **Reminders/Next deadline** card with a call-to-action button.
  - **Right column:** a **Recent documents / activity** list (icon + title + meta), and a compact
    secondary widget (e.g. **Index status** or **Top questions**) where Donezo puts its timer.
  - **Lower row:** **Team / Collaboration** list with status chips, and a **radial gauge** card
    (e.g. % of documents published / indexed).
  - Build charts per the `dataviz` skill; green accent for the primary series, warm neutral for the
    rest. Cards use `--r-lg` radius and `--shadow`.
- **Ask** — centered conversation column; answers with citations; collapsible source panel.
- **Library** — filter bar + responsive card grid; click → viewer.
- **Viewer** — paginated document with the cited passage highlighted.

---

## 6. Accessibility & i18n (non-negotiable)

- WCAG 2.1 AA contrast on all text (verify every token pairing).
- Visible `:focus-visible` ring everywhere; full keyboard operability.
- Respect `prefers-reduced-motion` (disable non-essential motion).
- Every language-switchable string externalized; Hindi uses Devanagari fonts and must not clip.
- Don't encode meaning in color alone — pair with icon/label.

---

## 7. Reference & versioning

- **v0.5 (current):** incorporated the **Donezo** dashboard reference — palette set to
  beige/white/green, dashboard layout specified (§5).
- **Still to refine during build:** exact shadow depth, card radius feel, sidebar translucency,
  and the real KPI/chart data bindings. Tokens are structured so these stay **one-file changes**.
- Bump to **v1** once the first built dashboard is reviewed against this doc.
