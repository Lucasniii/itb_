# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Commands

There is no build system, package manager, linter, or test suite — the entire app is one static file, [index.html](index.html) (HTML + CSS + JS inline, ~2750 lines).

- **Run/preview:** open [index.html](index.html) directly in a browser, or serve it locally for a more realistic environment:
  ```bash
  python3 -m http.server 8765   # from the repo root, then open http://localhost:8765/index.html
  ```
- **Syntax-check the inline JS** (no linter configured, but a quick sanity check before committing):
  ```bash
  python3 -c "import re; open('/tmp/s.js','w').write(re.search(r'<script>(.*)</script>\s*</body>', open('index.html').read(), re.S).group(1))"
  node --check /tmp/s.js
  ```
- No tests exist. No `package.json`/`Makefile`/CI config in this repo.

## Architecture

Single-file, framework-free app: all markup, styles, and logic live in [index.html](index.html). Three external runtime dependencies are loaded via CDN `<script>` tags: `xlsx.full.min.js` (SheetJS, for reading/writing `.xlsx`), `jszip.min.js` (used internally by SheetJS for `.xlsx` writing), and `supabase-js` (shared database + auth). Fonts (`DM Mono`, `Syne`) are loaded via a Google Fonts `@import`.

XLSX analysis (KM-Pruefung and PTO-Erkennung) stays fully client-side — spreadsheet contents are never uploaded anywhere. The Decoder's custom bit descriptions and the planned Orakel knowledge base are the only server-backed data.

### Supabase (shared data + auth)

The browser connects directly to Supabase; there is no custom application server. Project **ITB.BERICHTE** (`jkxxgvhknswhbayvmmoc`, eu-central-1) is initialized through `window.supabase.createClient()` with `SUPABASE_URL` and the publishable key near the top of the inline script (`index.html:814-822`). The publishable key is public by design — authorization must never depend on hiding it or on client-side UI checks.

The app is publicly deployed from a public repository. All actual access control therefore lives in Supabase Row Level Security (RLS), with policies scoped to `authenticated`; nothing is granted to `anon`. There are no SQL migrations in this repository, so the live schema, policies, functions, and triggers are managed in Supabase and documented here and in [PROJECT_BRIEFING.md](PROJECT_BRIEFING.md).

Tables (all RLS-enabled):

- `profiles` — auto-created on signup by the `handle_new_user` trigger on `auth.users`; stores `display_name` and `role` (`'user' | 'admin'`, default `'user'`).
- `decoder_features` — custom Decoder descriptions plus review fields (`status`, `reviewed_by`, `reviewed_at`, `review_note`). INSERT/UPDATE policies require `created_by`/`updated_by = auth.uid()` so clients cannot forge authorship.
- `orakel_entries` — question/answer/tags knowledge base with the same review fields. The schema exists, but its UI has not been built yet.

There is no usage tracking. The former `usage_daily` table, `log_usage()` function, and client-side `logUsage()` calls were removed; do not reintroduce analytics without explicit approval.

#### Authentication, roles, and review workflow

Authentication uses Supabase email/password auth with default email confirmation. `authApplyState()` handles both an active session and the post-signup state where the email has not yet been confirmed. Signed-out users can use the local tools, but receive no database-backed custom Decoder descriptions.

Two roles are stored in `profiles.role`: **user** may submit content and edit their own not-yet-approved submissions; **admin** may approve/reject content and assign roles. The client-side `authRole`, `authIsAdmin()`, and hidden controls only shape the UI. RLS policies and database triggers are the binding security boundary.

The current UI exposes the Admin tab only to admins, so non-admins cannot currently submit `decoder_features` through the interface. The database review workflow remains active for future interfaces such as the planned Orakel tab:

- `is_admin()` — `SECURITY DEFINER`, `STABLE`, and granted only to `authenticated`; policies use it instead of recursively querying `profiles`.
- `guard_review()` — BEFORE INSERT/UPDATE trigger on both content tables. Non-admin submissions are forced to `pending`, review fields cannot be forged, and content edits return a row to `pending`. An admin's own insert is auto-approved.
- `guard_profile_role()` — BEFORE UPDATE trigger on `profiles`; only admins can change roles, and the last admin cannot be demoted. `auth.uid() is null` remains the SQL editor/service-role recovery path.
- `approve_decoder_feature(p_id)` — `SECURITY DEFINER` RPC that checks admin status and atomically approves a proposal while replacing the previously approved row at the same `(type, position)`.
- Two partial unique indexes allow one approved row per `(type, position)` and one pending row per `(type, position, created_by)`. The client uses explicit insert-versus-update logic in `adminTargetRow()` rather than an upsert.
- SELECT policies expose approved rows, a caller's own rows, and all rows to admins. Non-admin UPDATE/DELETE policies additionally exclude approved rows.

Supabase queries use the signed-in session automatically: profiles are loaded through `sb.from('profiles')`, features through `sb.from('decoder_features')`, and approvals through `sb.rpc('approve_decoder_feature', ...)`.

### Tabs (views)
Four tabs, toggled purely by JS adding/removing `.active` on `.tab` / `.view` elements keyed by a shared `data-view` name — no router, no framework:

| Tab | `data-view` | Section id | JS region (approx.) | Visible to |
|---|---|---|---|---|
| Decoder (default view) | `zconfig` | `view-zconfig` | index.html:1481-2375 | everyone |
| KM-Pruefung | `pruef` | `view-pruef` | index.html:1067-1480 | everyone |
| PTO-Erkennung | `merge` | `view-merge` | index.html:2604-2740 | everyone |
| Admin | `admin` | `view-admin` | index.html:2376-2603 | admins only |

`showView(name)` toggles the views. Switching to Admin re-fetches both features (`adminLoadFeatures()`) and profiles (`profilesLoad()`). The Admin tab button and content stay hidden until `authApplyRoleUI()` confirms an admin. Because the login form lives in the Admin view, the header's **Anmelden** button calls `authShowLogin()` to open that login gate even while the tab itself is hidden.

### Decoder (Z-Config / Data-Config / Event)
Parses pasted device strings (`$QR:ZCONFIG`, `ZCONFIG2/3/4`, `ZVALUE`, `ZVALUE2`, `DATACONFIG`, `CHECKTMR`, `EVENT=<code>`) via `zcParse()` (`index.html:1954`), which sniffs the string type by regex and dispatches to type-specific rendering. Bit/field meanings come from static lookup tables defined near the top of this region: `ZC_DEFS`, `ZC2_DEFS`, `ZC3_DEFS`, `ZC4_DEFS`, `ZV_DEFS`, `ZV2_DEFS`, `DATACONFIG_DEFS`, and `EVENT_DEFS`. DATACONFIG has an alternate compact grid view (`zcRenderDataGrid()`, `index.html:2337`) toggled through `zcSetDcView()`. Approved `decoder_features` are overlaid through the in-memory `adminFeatures` cache; DATACONFIG cells can also be clicked to toggle bits locally.

### KM-Pruefung
Reads an `.xlsx` trip report via SheetJS (`analyze()`, `index.html:1164`). Vehicles are grouped **structurally** by header-row pattern (not by license-plate format, which varies by country) — see `extractKennzeichen()` (`index.html:1125`) for the two recognized header shapes. Two error classes are detected per group:
- **KM-Sprung-Fehler**: actual vs. expected km delta mismatch beyond a tolerance (0.1 km default, 1 km if "1-km-Spruenge ignorieren" is checked).
- **Eingefrorene KM-Serien**: `FROZEN_THRESHOLD = 20` (`index.html:811`) — 20+ consecutive trips with an identical km reading are flagged, including the first row of the run.

Results can be downloaded back out as a marked-up `.xlsx` (`downloadMarked()`, `index.html:1389`).

### PTO-Erkennung
Reads multiple `.xlsx` detail reports and detects active inputs or PTO events from report cell text. Per-file results are cached in `mergeAnalysisCache` and merged into one combined per-license-plate overview by `analyzeMergeFiles()` (`index.html:2691`). Everything remains in the browser.

### Admin
CRUD UI for attaching custom description text to individual Decoder bits/data numbers (`ADMIN_TYPES`, `index.html:1786`: ZCONFIG/2/3/4, ZVALUE/2, DATACONFIG). Entries are stored centrally in Supabase `decoder_features` and shared across authenticated users according to RLS.

The Admin tab is visible to admins only. It contains two subviews controlled by `adminSetSubview()`:

| Subview | Container | Contents |
|---|---|---|
| Feature anlegen | `admin-sub-features` | form, feature list, pending review queue |
| Benutzer & Rollen | `admin-sub-roles` | profile list and role management |

`adminLoadFeatures()` (`index.html:1808`) reloads permitted rows from Supabase on sign-in and whenever the Admin tab opens. `adminGetFeature(type, position)` (`index.html:1905`) is the synchronous lookup used by the Decoder and returns only the approved row. Mutations write through Supabase and then call `adminLoadFeatures()` to re-sync instead of mutating the cache optimistically. `profilesLoad()` supplies author/reviewer names.

`ADMIN_STORAGE_KEY` (`itb-admin-features-v1`) exists only for the one-time migration of data created by the former local-only version. `adminMigrateLocal()` inserts valid leftover entries into Supabase and then removes the local key; `localStorage` is no longer the primary persistence layer.

## Style conventions

### Colors (CSS custom properties on `:root`)
```css
--bg: #0f0f0f;       /* page background, near-black */
--surface: #1a1a1a;  /* card/box background */
--border: #2a2a2a;   /* default border */
--accent: #e8ff47;   /* neon yellow — accent / active state */
--red: #ff4444;      /* error */
--orange: #ff9944;   /* warning / "frozen" */
--green: #44ff88;    /* success / OK */
--text: #f0f0f0;     /* primary text */
--muted: #666;       /* secondary text */
```
Dark-mode only, no theme toggle. Status colors are used consistently: red = error, orange = warning/frozen, green = OK/active, accent yellow = interaction/focus. Colored surfaces (badges, chips, pills) use `rgba()` of the status color for the background plus a thin `rgba()` border in the same hue.

### Typography
- Body text/monospace: `'DM Mono', 'Courier New', monospace` — used for body, inputs, tables, textareas.
- Headings/UI labels (buttons, tabs, titles): `'Syne', Arial, sans-serif`, `font-weight: 700–800`, often with `letter-spacing`.
- Small UI text (labels, meta info): `0.6–0.8rem`, often `text-transform: uppercase` with `letter-spacing: 0.06–0.1em`.

### Layout
- `box-sizing: border-box` globally.
- Centered column layouts, `max-width: 960px`, `display: flex; flex-direction: column; align-items: center`.
- `border-radius: 2px` almost everywhere (`3–4px` for larger containers) — deliberately squared-off, no "rounded" look.
- Spacing in multiples of 4px, typically `6/8/10/12/14/16/20/24/32px`.
- One responsive breakpoint, `@media (max-width: 600px)`, collapsing grids to 1–2 columns.

### Component patterns
- **Tabs** (`.tabs`/`.tab`): flat buttons, `border-bottom: 2px solid transparent`, active = accent color + underline.
- **Drop zones** (`.drop-zone`): dashed border (`2px dashed`), border color changes on drag-over/file-selected.
- **Buttons**: `.btn-choose` (secondary, transparent + border), `.btn-run` (primary, accent background, black text), `.btn-dl` (accent outline). Hover via `opacity`/`border-color`/`translateY(-1px)`.
- **Status badges/chips/tags** (`.badge`, `.kz-chip`, `.tag-x`, `.tag-frozen`, `.tag-ok`): compact, color-coded pills.
- **Tables**: plain, `border-collapse: collapse`, faint row separators, header on `var(--surface)`, white-overlay row hover.
- **Collapsible sections** (`.kz-section`/`.kz-header`/`.kz-body.collapsed`): clicking the header toggles the body via `toggleSection()`.

### Language & comments
- UI text is **German**, with `ae`/`oe`/`ue` substituted for umlauts in strings/comments (e.g. "Kilometerspruenge", "unveraenderte", "Fahrzeuge") — keep this substitution for consistency rather than typing literal umlauts in JS string literals.
- Code comments are a German/English mix: German for domain logic, English for generic technical block markers.
- Large section dividers in the `<script>` block use ASCII boxes:
  ```js
  /* ════════════════════════════════════════════════════════════════
     SECTION NAME
     ════════════════════════════════════════════════════════════════ */
  ```

### JavaScript style
- No framework, no module system — one large `<script>` block, `var` declarations throughout (not enforcing `let`/`const`), an ES5/ES6 mix.
- Functions are global (`function xyz() {}`); events wired via `addEventListener` or inline `onclick="..."`.
- Direct DOM access via `document.getElementById`/`querySelectorAll`; no virtual DOM — HTML is built via `innerHTML` string concatenation.
- Lookup-table constants use `UPPER_SNAKE_CASE` or `PascalCase` (`FROZEN_THRESHOLD`, `DATACONFIG_DEFS`, `EVENT_DEFS`, `ADMIN_TYPES`).

## Project Briefing and Roadmap

Before starting a new feature, read `PROJECT_BRIEFING.md` as well. It contains
the product purpose, non-negotiable safeguards, prioritized roadmap, open
product decisions, and a reusable task prompt.
