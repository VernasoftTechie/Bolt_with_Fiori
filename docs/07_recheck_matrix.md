# Re-check matrix — every requirement, where it is built, how it was verified

Requirements as given on 2026-11-18/19. **Mock** = verified in the browser against
`tools/mock/mock-server.mjs` (same entity sets, actions, checks and messages as the ABAP behaviour).
**SAP** = can only be verified at the first activation (part A of `04_installation.md`).

| # | Requirement | Built in | Verified |
|---|---|---|---|
| 1 | No system selection — the logged-on system is the source; Smart Forms list from where the app is launched | `ZAB_CDS_CE_BOLT_SYSINFO`, `ZCL_AB_BOLT_FORM_CATALOG` (TADIR of this system), header chip "S4D · client 100" | Mock; SAP: A5 check 4 |
| 2 | OData services pulled from GitHub, not created by hand | SRVD/SRVB/G4BA in `src/`, increment 4; one manual step: Publish | SAP: A5 |
| 3 | DIL naming | all objects; generators refuse violations | `node tools/gen_ddic.mjs`, `node tools/gen_metadata.mjs` ("DDIC OK", "metadata OK") |
| 4 | Built from the DDIC level | install branches `install/1-ddic` … `4-service` | `node tools/make_install_branches.mjs` |
| 5 | End to end in sync SAP – Fiori – GitHub | one repository, one commit for ABAP + Fiori + docs; install branches built from `main` | this commit |
| 6 | Engineer side unchanged | status file format byte-for-byte (`ZCL_AB_BOLT_STATUS_FILE` + unit tests), same path, same headings, never writes CLAIMED_BY, branch names as the web app | unit tests (SAP: A3 check 1); queue tool reads the branch (E3) |
| 7 | Replace the web app; Fiori on-premise **and** BTP | `ui5-deploy.yaml` (BSP `ZSFTAD_BOLT`), `mta.yaml` + `xs-app.json` (destination `BOLT_S4`) | build files written; deploy = part C |
| 8 | Fully automatic transfer of the Smart Form source — no manual download | `ZCL_AB_BOLT_MIG_SVC=>build_files`: legacy grab + drivers, Smart Form XML (`CL_SSF_FB_SMART_FORM`, as abapGit), Smart Styles (`SSF_READ_STYLE`, as abapGit) | Mock (commit → files); SAP: A3 check 2 (`ZABR_BOLT_SELFTEST`) |
| 9 | Configuration in the setup page, client independent (nothing client-specific hard-coded) | `ZABT_BOLT_SETUP` + Setup page: client name, admins, GitHub URL/SSL/SM59, repository, prefix, folders, Smart Form prefixes, AI | Mock |
| 10 | Configuration page behaves like the web app | client name saved on leaving the field; GitHub token connect/disconnect with "Connected as … (…)" + scopes + help; AI card (provider/key/model/base URL/max tokens, Test, Save, key-saved rule); 2. Repository gated until GitHub + AI ready; Check access text "✓ … · private · default branch … · push access"; Create repository (private, connected account); Save repository settings; Global library (4 categories, several files, provenance, push to default branch, remove = list only) | Mock: all of these, incl. refusals (missing repo, own user not in admin list) |
| 11 | Admin protection of the Setup page | Administrators list + global authorization (replaces the admin password); refused save shows the saved value again | Mock |
| 12 | File uploads behave like the web app | several files, drag & drop or choose, list with remove before sending, same accepted types | Mock (staging, library upload with 2 files) |
| 13 | Stop behaves like the web app | reason input, "Stop requested" entry with the reason, Stopped banner, Resume; local stop before the first send | Mock |
| 14 | Communication panel behaves like the web app | Waiting on + note, confirm only when waiting on someone else and not stopped, problem/question/change need text or files, Raise a concern also after completion, attachments to `concerns/<ms>/` with the "Attached: … (pushed to …)" line, notices auto-hide after 8 s, newest first | Mock (confirm, stop) |
| 15 | Stopped form can be selected again (re-process) | `commitSelection`: STOPPED → new serial, run n+1, branch `-r<n>`, old run Superseded | Mock (ZSD_PROFORMA → No. 7, run 2, `…-r2`) |
| 16 | Already selected form cannot be selected again | ACTIVE/COMPLETED refused in the UI and again in `commitSelection` (with a table lock) | Mock |
| 17 | Tables updated with all basic details, no texts | `ZABT_BOLT_MIG` (status, waiting on, stop, picked up/completed/stopped dates, counts, complexity, source system), `ZABT_BOLT_HIST` (event rows), `ZABT_BOLT_FILE` | Mock (status history table) |
| 18 | Clients can analyse progress any time | Migrations tab filters with counts + export to spreadsheet; history per migration; job keeps statuses current | Mock |
| 19 | Fiori enhancements | Counts on the filters and tabs, IllustratedMessage empty states, spreadsheet export, drag & drop, LIVE indicator, AI summary, status history, files on the branch, re-process guidance | Mock |
| 20 | Dashboard in sequence, nothing repeated (v2.1, 2026-11-19) | Left: process tabs *1 Smart Forms → 2 Drafts → 3 Migrations*, one filter row with counts + one toolbar per tab, each button once. Right: Setup card (check rows + LIVE, *Open setup*) and Help card. Setup on its own page. Narrow screens: side cards below, secondary columns pop in | Mock (1440 / 1024 / 600 px) |
| 21 | A connection problem at commit puts the entry into a draft window; the user repeats until the initial load is on GitHub (v2.1) | `commitSelection` no longer requires LIVE (warning, PENDING); failed send = FAILED; *2 Drafts* tab + draft banner on the migration page: *Send to GitHub*, *Send all drafts* (no limit by hand), *Discard*; job retries up to *Maximum send attempts*; job skips drafts while GitHub is not set up | Mock: save as drafts, send all (2 sent, 1 failed), send failed again, discard |
| 22 | Help complete and kept current with every change (v2.1) | Help page (search, sections, previous/next) from `webapp/help/help.html`: process, every tab, migration page, statuses, setup fields, prerequisites, troubleshooting, data, glossary, *What's new*. CLAUDE.md rule: every change updates it | Mock |
| 23 | Every page refresh loads the new status; pages open for a while reload every 2 minutes (user, 2026-11-23) | Dashboard: GitHub read at every open / refresh + 2-minute tick (`BaseController.startAutoRefresh`), paused while forms are ticked, a dialog is open, something is busy or the tab is hidden; migration page: live status at open + 2-minute tick, paused while typing / staging / busy; server: `refreshAll` reads a migration at most once per 60 s (`gc_resync_secs`, LAST_SYNC_AT) | Mock: read on load, auto tick keeps a ticked form, no refresh while typing (text kept), refresh after clearing, dashboard timer stops on the migration page |

## Not verified yet (needs SAP)

See `05_build_notes.md` → *Not verified yet*. Every item there is exercised by the checks of
`04_installation.md` part A.
