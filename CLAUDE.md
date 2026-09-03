# CLAUDE.md

Guidance for Claude Code in this repo. Read `PROJECT_BRIEFING.md` too before starting a feature — it holds the product purpose, the non-negotiable guardrails and the roadmap.

## Commands

No build system, package manager, linter, CI or tests. The whole app is one static file: [index.html](index.html) (~4785 lines, HTML + CSS + JS inline). About a fifth of that is the `VEH_DB` vehicle table — see *CAN Verfuegbarkeit* below.

```bash
python3 -m http.server 8765          # preview at http://localhost:8765/index.html
# Syntax-check the inline JS before committing:
python3 -c "import re; open('/tmp/s.js','w').write(re.search(r'<script>(.*)</script>\s*</body>', open('index.html').read(), re.S).group(1))"
node --check /tmp/s.js
```

## Architecture

Framework-free single file. Five CDN dependencies, each pinned with an SRI `integrity` hash and `crossorigin="anonymous"`: `xlsx.full.min.js` (SheetJS 0.20.3, served from `cdn.sheetjs.com` — npm/cdnjs stop at the vulnerable 0.18.5), `jszip.min.js` (used **directly** by `downloadMarked()`, which rewrites the sheet XML by hand), `supabase-js`, and — for the Import sub-tab only — `html2canvas` 1.4.1 and `jspdf.umd.min.js` 4.2.1 (the UMD build exports `window.jspdf.jsPDF`). Bumping a version means recomputing its hash: `curl -s <url> | openssl dgst -sha384 -binary | openssl base64 -A`. Roboto via a Google Fonts `@import` (no SRI possible on an `@import`).

**XLSX analysis never leaves the browser** — spreadsheet contents are not uploaded anywhere. Only decoder descriptions are server-backed.

### Supabase (project ITB.BERICHTE, `jkxxgvhknswhbayvmmoc`, eu-central-1)

The applied database state is mirrored as SQL in [supabase/schema.sql](supabase/schema.sql) — a snapshot of what is live, not a migration runner. It is written in dependency order and would replay on an empty database. Keep it in sync when you change the schema.

`SUPABASE_URL`/`SUPABASE_KEY` are hardcoded and public by design — **all access control lives in RLS**, and no policy or grant addresses `anon`. The app ships to public GitHub Pages from a public repo, so anything `anon` could read would be world-readable. There is no usage tracking of any kind; keep it that way.

Tables (RLS on, every policy `to authenticated`):

- `profiles` — created by the `handle_new_user` trigger; `display_name`, `role` (`'user' | 'admin'`, default `'user'`).
- `decoder_features` — custom bit descriptions plus review columns (`status`, `reviewed_by/at`, `review_note`).

**The approval rule is enforced in the database, not in the UI:**

- `guard_review()` — BEFORE INSERT/UPDATE trigger on `decoder_features`. Non-admins cannot set `status`, `reviewed_by/at` or `review_note` at all; their inserts are forced to `pending` and any content edit drops the row back to `pending`. An admin's own insert is auto-approved.
- `guard_profile_role()` — role changes require an admin, and the last admin cannot be demoted. `auth.uid() is null` (service role / SQL editor) is the deliberate recovery path.
- `is_admin()` — `SECURITY DEFINER`, `STABLE`, `authenticated` only. Policies call it as `(select public.is_admin())` rather than joining `profiles`, which would recurse into the `profiles` policies.
- `approve_decoder_feature(p_id)` — `SECURITY DEFINER` RPC that checks `is_admin()` itself; it approves a row and replaces the previously approved one for the same `(type, position)` in one statement. Rejecting is a plain admin UPDATE.
- Two partial unique indexes replace the old `(type, position)` constraint: one `where status = 'approved'`, one on `(type, position, created_by) where status = 'pending'`. An open proposal can sit next to the live description without displacing it, so the client does explicit insert-vs-update (`adminTargetRow()`), never an upsert.
- Decoder-feature SELECT: `status = 'approved' or created_by = auth.uid() or is_admin()`. UPDATE/DELETE additionally require `status <> 'approved'` for non-admins.

Advisor WARNs for `is_admin()` and `approve_decoder_feature()` are expected — both check permissions themselves. `anon` additionally has **no SQL grants at all** (revoked on top of RLS, including default privileges for future tables), so a table that ever lost its RLS would still not be world-readable.

Auth is email/password. `authApplyState()` handles both the confirmed and unconfirmed state, but do **not** assume a mail round-trip protects anything: whether self-registration is open and whether addresses are auto-confirmed is a project setting in the Supabase dashboard, and the RLS model treats every `authenticated` user as a trusted colleague. Check that setting before drawing conclusions. The app is fully usable signed out.

### Tabs

No router: `showView(name)` toggles `.active` on the `.tab`/`.view` pair keyed by `data-view`.

| Tab | `data-view` | Section id | JS region | Visible to |
|---|---|---|---|---|
| Decoder (default) | `zconfig` | `view-zconfig` | index.html:1613-2518 | everyone |
| ↳ CAN Verfuegbarkeit (pane) | — | `zc-pane-veh` | index.html:2519-3918 | everyone |
| KM-Pruefung | `pruef` | `view-pruef` | index.html:1199-1612 | everyone |
| PTO-Erkennung | `merge` | `view-merge` | index.html:4642-4772 | everyone |
| Admin | `admin` | `view-admin` | index.html:3919-4641 | admins only |

`#tab-admin` stays `display:none` until `authApplyRoleUI()` confirms an admin. Because the login form lives inside `#view-admin`, the header carries an **"Anmelden" button** (`authShowLogin()`) that opens that view without the tab being visible. A signed-in non-admin sitting on the admin view is pushed back to the Decoder.

**Decoder** — `zcParse()` (index.html:2098) sniffs the pasted string type by regex (`$QR:ZCONFIG`, `ZCONFIG2/3/4`, `ZVALUE`, `ZVALUE2`, `DATACONFIG`, `CHECKTMR`, `EVENT=`) and dispatches to type-specific rendering; `zcParseCheckTmr()` (2276) and `zcParseEvent()` (2412) are separate. Meanings come from the static tables `ZC_DEFS`, `ZC2_DEFS`, `ZC3_DEFS`, `ZC4_DEFS`, `ZV_DEFS`, `ZV2_DEFS`, `DATACONFIG_DEFS`, `EVENT_DEFS` — domain data, only to be changed against verified device documentation. `DATACONFIG_DEFS` deliberately holds several field names per data number; both render paths handle that. Compact grid view: `zcRenderDataGrid()` (2481).

The Decoder tab holds **two panes**, switched by `vehSetPane('dec'|'veh')` (index.html:3671) via a `.zc-fbtn` row — no second tab, no router change: *Decoder* (`#zc-pane-dec`, the decoder above) and *CAN Verfuegbarkeit* (`#zc-pane-veh`).

**CAN Verfuegbarkeit** — answers "which CAN values can this vehicle deliver?". `vehParse()` (3660) splits the query into terms plus an optional model year; `vehMatch()` (3636) requires every term to appear in the model name and ranks word-start hits above hits inside a word, then sorts by whether the year falls into the generation's range (`fits` 2/1/0 — out-of-range hits are listed separately as *Andere Generationen*). A four-digit token that matches no generation is retried as a plain search term, so "BMW 2002" still works. `vehShow()`/`vehBack()` toggle list and detail inside `#veh-out`. The detail view is split in two: `vehRenderDetailHead()` (3795, title/summary/filter buttons/parameter search box) is rebuilt only when a vehicle is opened, while `vehRenderDetailBody()` (3845, the parameter groups, filtered by the "Alle Parameter"/"Nur verfuegbare" toggle and the search box) is re-rendered into `#veh-detail-body` on every keystroke via `vehRefreshBody()` — keeping the search input itself untouched so typing doesn't lose focus.

Data tables (`VEH_COLS`, `VEH_GROUPS`, `VEH_IND`, `VEH_TYPES`, `VEH_DB`, from index.html:2534) come from the Albatross S10 CAN module tables (firmware 3.0.28, 27.08.2026) and are **domain data under the same rule as `ZC_DEFS`** — only to be changed against the verified manufacturer tables. The on-road table is the superset: all 125 truck/bus rows and all 98 electric-car rows appear in it character-for-character, so `VEH_DB` holds one list of 919 models and the last field only records which of the two specialised tables also lists a model. One row is `Name|mask|indicators|body type|extra tables`; position *n* of the mask belongs to `VEH_COLS[n]`, column 0 carries the ignition signal (`s` key signal / `I` engine-on only), every other column is `0` none, `1` supported, `2` supported but possibly missing on a contactless connection, `3` two fuel kinds. Trailing `0`s are cut off, so `vehCell()` treats anything past the end as `0`. `VEH_COLS[n]` and `VEH_IND[key]` are each `[German, original English]` — every description in the *CAN Verfuegbarkeit* pane (`vehParamRow()`, 3777) renders the English original from the template first, the German translation as the `.veh-orig` line underneath.

**KM-Pruefung** — `analyze()` (1297) reads a trip report via SheetJS. Vehicles are grouped structurally by header-row pattern, not by plate format (`extractKennzeichen()`, 1258). Two error classes: a km delta beyond tolerance (0.1 km, or 1 km with "1-km-Spruenge ignorieren"), and frozen series of `FROZEN_THRESHOLD = 20` (938) identical readings. `downloadMarked()` (1522) writes the marked-up `.xlsx` back out.

**PTO-Erkennung** — `analyzeFileForInput()` (4694) scans each file: plates by regex, `hasInput` via `/Input\s*\d+\s*ein/i`, `hasPTO` via `/\bNA\s*ein\b/i`. `analyzeMergeFiles()` (4730) merges the per-file results into one per-plate overview.

**Admin** — admin-only CRUD for custom descriptions on decoder positions (`ADMIN_TYPES`, 1919). Three sub-tabs via `adminSetSubview()` (3929), in this order: *Feature anlegen* (form, list, `#review-panel` with `reviewApprove()`/`reviewReject()`), *Import* (see below) and *Benutzer & Rollen* (`rolesRender()`/`rolesSet()`). The `.admin-subview` blocks sit in the same order as their buttons — keep them in sync so reading and tab order match. `adminGetFeature(type, position)` is what the Decoder calls — it returns **only the approved row**, so unapproved text never reads as official. It scans the in-memory `adminFeatures`, refilled by `adminLoadFeatures()` on sign-in and on every switch to the tab; mutations re-sync through it instead of patching the array. `adminCanEdit()` mirrors the RLS rules in the UI. `ADMIN_STORAGE_KEY` (1918) survives only for the one-time localStorage migration (`adminMigrateLocal()`).

**Import** (index.html:4148-4641, all functions prefixed `imp`) — turns a browser-saved manufacturer manual (one `.htm` file plus its same-named `_files` folder) into one continuous A4 PDF that is downloaded straight away. Nothing is uploaded and nothing is written to Supabase; this is a pure browser conversion, like the XLSX tabs.

`impFindPackage()` (4223) insists on **exactly one** matching `.htm`/`_files` pair — zero or several is an error, not a guess. `impBuildDocument()` (4365) inlines the stylesheets, rewrites every local reference (`img` sources become data URLs so html2canvas draws them reliably) and strips everything executable or interactive — `script`, `iframe`, `form`, `on*` attributes and `href`s all go. `impCreatePdf()` (4454) renders the result in an off-screen `srcdoc` iframe, rasterises it with html2canvas and slices the canvas into A4 pages; pages taller than `IMP_MAX_PAGE_HEIGHT_PX` (30000) are refused rather than silently truncated. `impRunImport()` (4618) runs the conversion and triggers the download. The export CSS and `impSimplifyCarGalleries()` (4342) carry site-specific rules for the manufacturer portals these manuals come from — same rules as the sibling app they were ported from.

Two ways in, one core: `impUseFiles()` (4576) does the detection and the status line for both. `impSelectPackage()` (4595) feeds it the `webkitdirectory` input; the `#import-drop` drop zone feeds it a dropped folder. A drop hands over `FileSystemEntry` objects rather than a file list, so `impEntriesFromDrop()` (4524) collects them — **synchronously**, because `DataTransfer.items` is emptied at the first `await` — and `impWalkEntry()` (4539) walks the tree, calling `readEntries()` in a loop (it returns at most 100 entries per call) and hanging the relative path on each file as `impPath`, which `impFilePath()` reads in place of `webkitRelativePath`. Dropping the parent folder and dropping the `.htm` plus its `_files` folder side by side both work. `IMP_MAX_DROPPED_FILES` (4166) stops a misdropped home directory. A drop clears the file input so only one source is ever live.

The long explanation of the tool sits in a hover/focus bubble on the `i` next to the heading (`.import-info`), not permanently in the panel. Below 600px the bubble would run off the right edge, so there it becomes a plain block under the heading and the wrapper goes `display: contents` — otherwise the `i` jumps to its own line when it opens.

## Style conventions

**Colors** — CSS custom properties on `:root`, dark only, no theme toggle: `--bg #0f0f0f`, `--surface #1a1a1a`, `--border #2a2a2a`, `--accent #e8ff47` (interaction/active), `--red #ff4444` (error), `--orange #ff9944` (warning/frozen), `--green #44ff88` (OK/active), `--text #f0f0f0`, `--muted #666`. Colored surfaces use `rgba()` of the status color plus a thin border in the same hue. Never hardcode a hex outside `:root`.

**Type** — one family, `'Roboto', Arial, sans-serif`, loaded via a Google Fonts `@import` at weights 400/500/700/800: 400–500 for body, inputs and tables, 700–800 for headings, buttons and tabs. Small UI text 0.6–0.8rem, often uppercase with `letter-spacing: 0.06–0.1em`.

**Layout** — `box-sizing: border-box`, centered columns at `max-width: 960px`, `border-radius: 2px` (3–4px for large containers), spacing in 4px multiples, one breakpoint at `max-width: 600px`.

**Components** — tabs and sub-tabs are flat buttons with a 2px accent underline when active; drop zones use `2px dashed`; buttons are `.btn-choose` (secondary), `.btn-run` (accent), `.btn-dl` (outline); status pills are `.badge`/`.kz-chip`/`.tag-x`/`.tag-frozen`/`.tag-ok`; collapsible sections toggle via `toggleSection()`. An `<input>` inside a flex row needs `flex: 1; min-width: 0`, otherwise it keeps its default width and clips its placeholder.

**Language** — UI text is German, with `ae`/`oe`/`ue` instead of umlauts in JS strings and comments. Comments mix German (domain logic) and English (technical markers); section dividers use the ASCII box style already in the file.

**JavaScript** — one `<script>` block, global functions, `var` throughout, ES5/ES6 mix, no modules. Promises are `.then()` chains everywhere except the Import region, where the read/embed/render/slice chain is `async`/`await` — a deliberate, documented exception. DOM via `getElementById`/`querySelectorAll`; HTML is built by `innerHTML` string concatenation, so **escape every interpolated value with `zcEsc()`** — license plates, dates, times and file names from uploaded spreadsheets included. Error text goes through `textContent` (`setStatus`, `authMsg`, `adminSetStatus`, `rolesMsg`) and needs no escaping. Lookup constants use `UPPER_SNAKE_CASE`.
