# CLAUDE.md

Guidance for Claude Code in this repo. Read `PROJECT_BRIEFING.md` too before starting a feature — it holds the product purpose, the non-negotiable guardrails and the roadmap.

## Commands

No build system, package manager, linter, CI or tests. The whole app is one static file: [index.html](index.html) (~2750 lines, HTML + CSS + JS inline).

```bash
python3 -m http.server 8765          # preview at http://localhost:8765/index.html
# Syntax-check the inline JS before committing:
python3 -c "import re; open('/tmp/s.js','w').write(re.search(r'<script>(.*)</script>\s*</body>', open('index.html').read(), re.S).group(1))"
node --check /tmp/s.js
```

## Architecture

Framework-free single file. Three CDN dependencies: `xlsx.full.min.js` (SheetJS), `jszip.min.js` (used by SheetJS for writing), `supabase-js`. Roboto via a Google Fonts `@import`.

**XLSX analysis never leaves the browser** — spreadsheet contents are not uploaded anywhere. Only decoder descriptions and the planned Orakel knowledge base are server-backed.

### Supabase (project ITB.BERICHTE, `jkxxgvhknswhbayvmmoc`, eu-central-1)

The applied database state is mirrored as SQL in [supabase/migrations/](supabase/migrations/) — documentation, not a runner; keep it in sync when you change the schema.

`SUPABASE_URL`/`SUPABASE_KEY` are hardcoded and public by design — **all access control lives in RLS**, and no policy or grant addresses `anon`. The app ships to public GitHub Pages from a public repo, so anything `anon` could read would be world-readable. There is no usage tracking of any kind; keep it that way.

Tables (RLS on, every policy `to authenticated`):

- `profiles` — created by the `handle_new_user` trigger; `display_name`, `role` (`'user' | 'admin'`, default `'user'`).
- `decoder_features` — custom bit descriptions plus review columns (`status`, `reviewed_by/at`, `review_note`).
- `orakel_entries` — Q&A knowledge base, same review columns. **Schema only, no UI yet.**

**The approval rule is enforced in the database, not in the UI:**

- `guard_review()` — BEFORE INSERT/UPDATE trigger on both content tables. Non-admins cannot set `status`, `reviewed_by/at` or `review_note` at all; their inserts are forced to `pending` and any content edit drops the row back to `pending`. An admin's own insert is auto-approved.
- `guard_profile_role()` — role changes require an admin, and the last admin cannot be demoted. `auth.uid() is null` (service role / SQL editor) is the deliberate recovery path.
- `is_admin()` — `SECURITY DEFINER`, `STABLE`, `authenticated` only. Policies call it as `(select public.is_admin())` rather than joining `profiles`, which would recurse into the `profiles` policies.
- `approve_decoder_feature(p_id)` — `SECURITY DEFINER` RPC that checks `is_admin()` itself; it approves a row and replaces the previously approved one for the same `(type, position)` in one statement. Rejecting is a plain admin UPDATE.
- Two partial unique indexes replace the old `(type, position)` constraint: one `where status = 'approved'`, one on `(type, position, created_by) where status = 'pending'`. An open proposal can sit next to the live description without displacing it, so the client does explicit insert-vs-update (`adminTargetRow()`), never an upsert.
- SELECT: `status = 'approved' or created_by = auth.uid() or is_admin()`. UPDATE/DELETE additionally require `status <> 'approved'` for non-admins.

Advisor WARNs for `is_admin()` and `approve_decoder_feature()` are expected — both check permissions themselves. Auth is email/password with Supabase's default email confirmation; `authApplyState()` handles the pre-confirmation state. The app is fully usable signed out.

### Tabs

No router: `showView(name)` toggles `.active` on the `.tab`/`.view` pair keyed by `data-view`.

| Tab | `data-view` | Section id | JS region | Visible to |
|---|---|---|---|---|
| Decoder (default) | `zconfig` | `view-zconfig` | index.html:1484-2378 | everyone |
| KM-Pruefung | `pruef` | `view-pruef` | index.html:1070-1483 | everyone |
| PTO-Erkennung | `merge` | `view-merge` | index.html:2607-2749 | everyone |
| Admin | `admin` | `view-admin` | index.html:2379-2606 | admins only |

`#tab-admin` stays `display:none` until `authApplyRoleUI()` confirms an admin. Because the login form lives inside `#view-admin`, the header carries an **"Anmelden" button** (`authShowLogin()`) that opens that view without the tab being visible. A signed-in non-admin sitting on the admin view is pushed back to the Decoder.

**Decoder** — `zcParse()` (index.html:1957) sniffs the pasted string type by regex (`$QR:ZCONFIG`, `ZCONFIG2/3/4`, `ZVALUE`, `ZVALUE2`, `DATACONFIG`, `CHECKTMR`, `EVENT=`) and dispatches to type-specific rendering; `zcParseCheckTmr()` (2135) and `zcParseEvent()` (2271) are separate. Meanings come from the static tables `ZC_DEFS`, `ZC2_DEFS`, `ZC3_DEFS`, `ZC4_DEFS`, `ZV_DEFS`, `ZV2_DEFS`, `DATACONFIG_DEFS`, `EVENT_DEFS` — domain data, only to be changed against verified device documentation. `DATACONFIG_DEFS` deliberately holds several field names per data number; both render paths handle that. Compact grid view: `zcRenderDataGrid()` (2340).

**KM-Pruefung** — `analyze()` (1167) reads a trip report via SheetJS. Vehicles are grouped structurally by header-row pattern, not by plate format (`extractKennzeichen()`, 1128). Two error classes: a km delta beyond tolerance (0.1 km, or 1 km with "1-km-Spruenge ignorieren"), and frozen series of `FROZEN_THRESHOLD = 20` (814) identical readings. `downloadMarked()` (1392) writes the marked-up `.xlsx` back out.

**PTO-Erkennung** — `analyzeFileForInput()` (2658) scans each file: plates by regex, `hasInput` via `/Input\s*\d+\s*ein/i`, `hasPTO` via `/\bNA\s*ein\b/i`. `analyzeMergeFiles()` (2694) merges the per-file results into one per-plate overview.

**Admin** — admin-only CRUD for custom descriptions on decoder positions (`ADMIN_TYPES`, 1789). Two sub-tabs via `adminSetSubview()`: *Feature anlegen* (form, list, `#review-panel` with `reviewApprove()`/`reviewReject()`) and *Benutzer & Rollen* (`rolesRender()`/`rolesSet()`). `adminGetFeature(type, position)` is what the Decoder calls — it returns **only the approved row**, so unapproved text never reads as official. It scans the in-memory `adminFeatures`, refilled by `adminLoadFeatures()` on sign-in and on every switch to the tab; mutations re-sync through it instead of patching the array. `adminCanEdit()` mirrors the RLS rules in the UI. `ADMIN_STORAGE_KEY` (1788) survives only for the one-time localStorage migration (`adminMigrateLocal()`).

## Style conventions

**Colors** — CSS custom properties on `:root`, dark only, no theme toggle: `--bg #0f0f0f`, `--surface #1a1a1a`, `--border #2a2a2a`, `--accent #e8ff47` (interaction/active), `--red #ff4444` (error), `--orange #ff9944` (warning/frozen), `--green #44ff88` (OK/active), `--text #f0f0f0`, `--muted #666`. Colored surfaces use `rgba()` of the status color plus a thin border in the same hue. Never hardcode a hex outside `:root`.

**Type** — one family, `'Roboto', Arial, sans-serif`, loaded via a Google Fonts `@import` at weights 400/500/700/800: 400–500 for body, inputs and tables, 700–800 for headings, buttons and tabs. Small UI text 0.6–0.8rem, often uppercase with `letter-spacing: 0.06–0.1em`.

**Layout** — `box-sizing: border-box`, centered columns at `max-width: 960px`, `border-radius: 2px` (3–4px for large containers), spacing in 4px multiples, one breakpoint at `max-width: 600px`.

**Components** — tabs and sub-tabs are flat buttons with a 2px accent underline when active; drop zones use `2px dashed`; buttons are `.btn-choose` (secondary), `.btn-run` (accent), `.btn-dl` (outline); status pills are `.badge`/`.kz-chip`/`.tag-x`/`.tag-frozen`/`.tag-ok`; collapsible sections toggle via `toggleSection()`. An `<input>` inside a flex row needs `flex: 1; min-width: 0`, otherwise it keeps its default width and clips its placeholder.

**Language** — UI text is German, with `ae`/`oe`/`ue` instead of umlauts in JS strings and comments. Comments mix German (domain logic) and English (technical markers); section dividers use the ASCII box style already in the file.

**JavaScript** — one `<script>` block, global functions, `var` throughout, ES5/ES6 mix, no modules. DOM via `getElementById`/`querySelectorAll`; HTML is built by `innerHTML` string concatenation, so **escape every interpolated value with `zcEsc()`** — including values read from uploaded spreadsheets, which some KM-/PTO render paths still miss. Lookup constants use `UPPER_SNAKE_CASE`.
