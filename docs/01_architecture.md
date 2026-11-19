# Architecture — version 2

Bolt replaces the Bolt Console web app with a RAP + SAPUI5 app that runs **inside the client's SAP
system** — the system the app is launched in is the source of the Smart Forms (no system selection).
The engineer side is unchanged: engineer windows work from the GitHub branches and their status
files exactly as before.

```
 Client user (Fiori launchpad, on-premise or BTP Work Zone)
        │  OData V4  /sap/opu/odata4/sap/zab_ui_bolt_o4/srvd/sap/zab_ui_bolt/0001/
        ▼
 ┌──────────────────────────── client's S/4 system (package ZSFTAD_BOLT) ─────────────────────────┐
 │ RAP business objects            Query providers (read only)                                   │
 │  Migration ─┬ History            SmartForm   ← ZCL_AB_BOLT_FORM_CATALOG (TADIR/STXFADM/TNAPR)  │
 │             └ File               StatusFile  ┐                                                 │
 │  Setup (+ saver for secrets)     Timeline    ┘← the branch status file, read live from GitHub  │
 │  Library                         SystemInfo  ← sy-sysid / client / admin / readiness           │
 │        │ actions call                                                                          │
 │        ▼                                                                                        │
 │ ZCL_AB_BOLT_MIG_SVC ── ZCL_AB_BOLT_LEGACY_GRAB (port of ZSF2AF_R_LEGACY_GRAB)                  │
 │        │            ── ZCL_AB_BOLT_FORM_EXPORT (Smart Form XML + Smart Styles)                 │
 │        │            ── ZCL_AB_BOLT_STATUS_FILE (byte-for-byte statusParse.js)                  │
 │        ▼                                                                                        │
 │ ZCL_AB_BOLT_GITHUB ── ZCL_AB_BOLT_HTTP (URL + STRUST, or optional SM59) ──► api.github.com      │
 │ Tables: ZABT_BOLT_SETUP / MIG / HIST / FILE / LIB / SECRT / DRVIX (cross-client)               │
 │ Jobs:   ZABR_BOLT_SYNC (15 min)   ZABR_BOLT_DRIVER_INDEX (daily)                               │
 └─────────────────────────────────────────────────────────────────────────────────────────────────┘
        ▲                                                         │ one commit per form
        │ status file writes (confirm / problem / stop …)         ▼
        └──────────── client's migration repository on GitHub ◄── engineer windows (unchanged)
```

## The flows

| Flow | What happens | RAP |
|---|---|---|
| **Smart Forms tab** | Every custom Smart Form of this system (prefixes from the setup), with package, last change, NACE output types and driver programs, and its migration state: NONE / ACTIVE / STOPPED / COMPLETED | custom entity `SmartForm` |
| **Next → Commit** | One migration per selected form: next serial number (table lock so two users never get the same), run number, branch `<prefix>-<form>` (re-process: `-r<n>`). ACTIVE and COMPLETED forms are refused; a STOPPED form starts a re-process run and the stopped run is closed (*Superseded*). | static action `commitSelection` |
| **Automatic transfer** | Right after Commit, form by form: legacy grab `.md` + driver sources, Smart Form XML, every custom Smart Style the form uses, and the Queued status file — **one commit**, the branch reference written last, so a branch never exists half-made. An existing branch with a status file is adopted; one without is never overwritten. A failed send is saved as FAILED with its reason and retried by the job. | instance action `pushToGitHub` |
| **Live status** | The status file is read live from the branch; its header is stored as basic status (status, waiting on, stop, picked up by, dates) and every change writes one history row. The texts are not stored. | `refreshStatus`, `refreshAll`, custom entities `StatusFile`, `Timeline` |
| **Communication panel** | *I've done this — confirm* (only while waiting on someone other than the engineer, and not stopped — the only thing that releases a WAITING_ON hand-off), *Report a problem / Ask a question / Request a change*, *Raise a concern* (also after completion), with several attachments pushed to `<branch>/concerns/<ms>/`. Headings, texts and status changes are those of the web app. | action `respond` |
| **Stop / Resume** | STOP requested / none in the status file, with the reason; resume puts the migration back exactly where it was. Never sent to GitHub: a local stop. | actions `requestStop`, `resume` |
| **Legacy documents** | Stage files to add and files to remove, then *Save changes*: added files are pushed to `<branch>/`, removed ones only leave the list (the branch is untouched). | action `saveLegacyDocs` |
| **Configuration** | Client name (saved on leaving the field), administrators, GitHub token connect/disconnect, AI provider + test, target repository check/create/save, global reference library, advanced settings. Administrators only. | `Setup` actions, `Library` upload/delete |

## RAP design rules used

- Managed business objects, `strict ( 2 )`, ETag on every root (`LocalChanged`), managed UUID keys.
- Migrations are changed **only** by actions (`internal create / update`); the UI cannot write a
  status directly.
- Every database write in the interaction phase goes through **EML in local mode**; the GitHub
  token and the AI key are written only in the **saver** (`managed with additional save`).
- HTTP calls to GitHub happen inside the actions; their result is stored by the same action.
- A failed GitHub send is reported as a *warning*, not *failed*, so the FAILED state is saved and
  not rolled back. A refused client action (e.g. "Nothing is waiting for your confirmation") is
  *failed* and changes nothing.
- Global authorization: Setup/Library changes for administrators only; migrations for every app user.
- Validation on save: the administrator list must contain the user saving it; folders and prefixes
  are checked.
- The background job uses the same BO through EML + `COMMIT ENTITIES`.

## What is stored where

| Data | Where | Why |
|---|---|---|
| Basic status, dates, counts, serial/run numbers | `ZABT_BOLT_MIG` | progress analysis at any time (Migration tab, export) |
| One row per event (committed, sent, status change, confirm, stop …) — no texts | `ZABT_BOLT_HIST` | history of every migration |
| Files on each branch (path, kind, size, commit; removed-from-list flag) | `ZABT_BOLT_FILE` | Legacy documents, Files on the branch |
| Messages, notes, engineer entries | the status file on the branch only | single source both sides read |
| GitHub token, AI key | `ZABT_BOLT_SECRT` (encoded, never returned by the service) | protect with S_TABU_NAM |
| Driver programs per form | `ZABT_BOLT_DRVIX` | the slow scan runs once a day, one click stays fast |

All tables are **cross-client**: Smart Forms are cross-client repository objects, so the list of
migrations is the same whichever client the app is opened in.

## The contract with the engineer side

- Status file path `docs/legacy_grab/<slug>_status.md` (folder configurable, keep the default),
  header `STATUS / UPDATED / WAITING_ON / NOTE / STOP / CLAIMED_BY`, `---`, entries
  `## <ISO time> — <heading>`. `ZCL_AB_BOLT_STATUS_FILE` is a byte-for-byte port of
  `statusParse.js` with unit tests. Change both or neither.
- The app never writes `CLAIMED_BY`.
- Writes send the blob SHA; on a conflict the file is read again and the entry re-applied (three
  attempts).
- Branch names follow `migrationBranchName()` of the web app; the re-process suffix `-r<n>` keeps
  the slug, so `tools/queue.mjs` finds the status file on the new branch as on any other.
