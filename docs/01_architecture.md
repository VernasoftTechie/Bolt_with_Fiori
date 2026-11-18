# Architecture

Bolt with Fiori replaces the Bolt Console web application (Node + React, hosted on a server) with
a **RAP + Fiori** application inside the client's SAP system. The process is the same as the web
app's. Three things change:

1. **No manual legacy-grab download or upload.** The app runs the legacy grab and the Smart Form XML
   export itself, on the chosen source system, and pushes the files to GitHub.
2. **Logs live in SAP.** Every migration, its status-file timeline and this app's own events are in
   SAP tables (`ZBOLT_MIG`, `ZBOLT_MIGLOG`, `ZBOLT_MIGFILE`).
3. **Nothing to host.** The UI is a Fiori app on the Launchpad, the backend is the ABAP stack.

The engineer side does not change at all. The engineer windows read and write only GitHub — the
branch and its status file `docs/legacy_grab/<slug>_status.md`. The app writes exactly the same
branch names, folder layout and status-file format as the web app (`ZCL_BOLT_STATUS_FILE` is a
line-for-line port of `statusParse.js`, with unit tests).

## Components

```
 Fiori app (BSP ZBOLT_FIORI, freestyle SAPUI5)
   │  OData V4: /sap/opu/odata4/sap/zbolt_ui_o4/srvd/sap/zbolt_ui/0001/
   ▼
 Service ZBOLT_UI (binding ZBOLT_UI_O4)
   ├─ Migration ─┬─ MigrationLog      managed RAP BO ZI_BOLT_MIGRATION  (ZBOLT_MIG, _MIGLOG, _MIGFILE)
   │             └─ MigrationFile     actions: commitSelection, pushToGitHub, refreshStatus, refreshAll,
   │                                  confirmManual, raiseConcern, setStop, addReferenceFile,
   │                                  withdraw, importFromGitHub, aiSummary
   ├─ Setup                           managed RAP BO ZI_BOLT_SETUP (ZBOLT_SETUP; key -> ZBOLT_SECRET)
   ├─ SourceSystem                    managed RAP BO ZI_BOLT_SYSTEM (ZBOLT_SYSTEM)  DEV / QA / PRD
   ├─ SmartForm                       custom entity  (list for the selected system + migration state)
   ├─ SourceForm   ┐ source API: the same service on QA/PRD answers these two for the app in DEV
   └─ SourceFile   ┘
         │
         ▼
 ZCL_BOLT_MIGRATION_SVC ── ZCL_BOLT_GITHUB ── ZCL_BOLT_HTTP ── SM59 ZBOLT_GITHUB ── api.github.com
         │              └─ ZCL_BOLT_STATUS_FILE (format)
         ├─ ZCL_BOLT_SOURCE ─ this system: ZCL_BOLT_LEGACY_GRAB + ZCL_BOLT_FORM_EXPORT
         │                  └ QA/PRD: OData SourceForm/SourceFile through SM59 ZBOLT_QA / ZBOLT_PRD
         └─ ZCL_BOLT_AI ── SM59 ZBOLT_AI ── OpenAI-compatible / Anthropic
 Reports: ZBOLT_R_SYNC (background send + status sync), ZBOLT_R_DRIVER_INDEX, ZBOLT_R_SETUP
```

## The flow, step by step

| Step | Web app | Bolt with Fiori |
|---|---|---|
| Choose forms | Operator runs ZSF2AF_R_LEGACY_GRAB, downloads files, uploads them in "+ New migration" | **Smart Forms Overview**: pick the source system, tick forms (ones already in migration cannot be ticked), **Next** |
| Confirm | — | Dialog lists the selection → **Commit selection** → rows in `ZBOLT_MIG` with the next serial number |
| Send | Server creates branch + uploads files + Queued status file, retries in background | Each form: legacy grab + XML export on the source system → **one commit** with all files and the Queued status file, branch reference created last. Failed → saved as FAILED with the reason, retried by `ZBOLT_R_SYNC` |
| Follow | Status board reads the status file on open | **Migration** tab: refreshes from GitHub on open, on Refresh, optional 2-minute auto refresh, plus the background job |
| Answer | Confirm / problem / question / change / concern / stop / resume / attach | Identical, same headings and texts in the status file, plus "Sent from Bolt with Fiori by SAP user X" |
| Close | Engineer sets `completed` | Same — read from the status file |

## Gate and status-file rules kept as they are

- Only **"Manual activity confirmed"** releases a `WAITING_ON` hand-off. The app refuses to confirm
  when nothing waits on the client or the migration is stopped (same checks as the web server).
- `CLAIMED_BY` is never written by the app. Only an engineer claims or releases.
- `STOP: requested` is set and cleared only by the client.
- Writes use the file's blob SHA. If the engineer wrote in between, GitHub refuses (409), and the app
  re-reads and re-applies, up to 3 times. No lost updates, no force-push.

## Several systems (DEV / QA / PRD)

The app runs in one system (normally DEV) and keeps the migrations there. The **source system** of
the Smart Forms can be any system in `ZBOLT_SYSTEM`:

- **This system** (`IsLocal`): read directly.
- **Another system**: the same Bolt package is installed there, and the app calls its OData entities
  `SourceForm` (list) and `SourceFile` (legacy grab + XML export of one form) through an SM59 HTTP
  destination. The extraction always runs on the system that holds the form, so the files are that
  system's truth.

A form name is one migration branch, so a form already in migration from DEV cannot be selected
again from QA.

## Data model

| Table | Purpose |
|---|---|
| `ZBOLT_SETUP` | one row: client name, administrators, GitHub (destination/owner/repo/base/prefix + last test), AI (provider/model/destination/path/max tokens + last test), form prefixes, NAST counting |
| `ZBOLT_SYSTEM` | source systems: ID, client, destination, service path, endpoint, local/default, last test |
| `ZBOLT_MIG` | one row per migration: serial no., form, system, branch, slug, send state (PENDING/PUSHED/FAILED/WITHDRAWN), mirror of the status-file header, complexity signal |
| `ZBOLT_MIGLOG` | `STATUS` rows = the status-file timeline (replaced when the file changes); `APP` rows = this app's own events |
| `ZBOLT_MIGFILE` | every file pushed to the branch (path, kind, size, when, who) |
| `ZBOLT_SECRET` | the AI API key — not part of any CDS view, never sent to the UI |
| `ZBOLT_DRVIDX` | driver index of the system it lives on (form → program candidates) |

## Security

- **GitHub token:** only in SM59 `ZBOLT_GITHUB` (Basic logon, fine-grained token limited to the
  client repository, Contents read/write).
- **AI key:** in `ZBOLT_SECRET`. It is written only in the RAP save phase, is not exposed by any CDS
  view, and is not shown again in the UI. Restrict table access (authorization group) as for any
  credential table.
- **Administrators** (Configuration → Administrators) can change the setup and source systems and
  withdraw migrations. A blank list means everyone. Enforced in the RAP behaviour, not only in the
  UI.
- Driver programs are only read (`READ REPORT`). Nothing in the source systems is changed.

## What is deliberately not in version 1

| Item | Why | Instead |
|---|---|---|
| Global library upload (logos, SmartStyle exports, naming docs → `docs/global_data/` on main) | Needs a separate push-to-main flow | The legacy grab's global sweep runs on the source system (`SourceFile` with FORM_NAME `*GLOBAL*`); a "Publish client specification" button is the planned next step |
| RAP migration type | The web app had it parked as well | Smart Forms only |
| AI execution plans / Bolt conversation | Superseded by the status-file process | AI summary of a migration's legacy grab |
| Live server push (SSE) | No server push in a Launchpad app | Refresh on open, Refresh button, optional 2-minute auto refresh, background job |
| Admin password | SAP users and roles exist | Administrators list + PFCG roles |
