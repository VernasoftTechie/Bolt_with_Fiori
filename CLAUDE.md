# CLAUDE.md — read this first

## Landing zone (Commit Gate — never cross without asking)

| | Value |
|---|---|
| GitHub repo | `VernasoftTechie/Bolt_with_Fiori` (private), branch `main`, direct push; `install/*` branches are generated |
| ABAP package | `ZSFTAD_BOLT` (set when linking in abapGit, not in the files) |
| Object names | DIL policy, module AB: `ZAB_DM_BOLT_*`, `ZAB_DE_BOLT_*`, `ZABT_BOLT_*`, `ZAB_CDS_<I/C/CE/A>_BOLT_*`, `ZCL_AB_BOLT_*`, `ZCX_AB_BOLT`, `ZBP_AB_BOLT_*`, `ZABR_BOLT_*`, service `ZAB_UI_BOLT(_O4)` — see `docs/06_naming.md` |
| UI | BSP `ZSFTAD_BOLT`, UI5 namespace `vernasoft.boltfiori`, BTP destination `BOLT_S4` |
| System | S/4HANA 2023 on-prem, SAP_BASIS 7.58, standard ABAP |

## Before changing anything

1. `docs/01_architecture.md` — how it works; `docs/05_build_notes.md` — what is verified and what
   is not yet; `docs/07_recheck_matrix.md` — the requirements.
2. The status-file format is a **contract with the engineer windows and tools/queue.mjs**.
   `ZCL_AB_BOLT_STATUS_FILE` must stay identical to Bolt Console's `statusParse.js`. Change both or
   neither, and keep its unit tests green. Never write CLAIMED_BY.
3. Communication texts are **not** stored in SAP — only basic status (`ZABT_BOLT_MIG`) and event rows
   (`ZABT_BOLT_HIST`). Keep it that way (user decision 2026-11-18).
4. ABAP standards: DIL naming (`gv_/gt_/gs_/gc_`, `lv_/lt_/ls_`, `<lfs_>/<lfv_>/<lft_>`,
   `iv_/is_/it_/ev_/rv_/rs_/rt_`), no `INTO CORRESPONDING`, no `INSERT` (MODIFY for DB writes,
   APPEND/VALUE BASE + SORT for internal tables), sorted tables or explicit SORT, 7.4+ syntax.
   A method with RETURNING has no EXPORTING/CHANGING.
5. RAP: no DB writes in the interaction phase (EML in local mode, or the saver of a
   `with additional save` BO). GitHub/HTTP calls are fine in action handlers. A failed send is a
   warning (so FAILED is saved), a refused client action is `failed`.
6. DDIC changes: edit `tools/gen_ddic.mjs` and run it. Other new/renamed objects: run
   `node tools/gen_metadata.mjs`. Both fail on DIL or length problems.
7. UI changes: test against `node tools/mock/mock-server.mjs` (add new actions or fields to the mock
   as well — it mirrors the ABAP checks and messages).
8. Before pushing: commit on `main`, then `node tools/make_install_branches.mjs`, then push `main`
   and `install/*` together, so SAP (abapGit), Fiori and GitHub stay in sync.
9. Log every activation/runtime error and its fix in `docs/BUILD_ISSUES_LOG.md`.
10. **Help is part of every change.** Any change a user can see (screen, button, status, message,
    setup field, job, prerequisite) also updates `app/bolt-fiori/webapp/help/help.html` — the
    section concerned and *What's new* (version = `gc_version` in `ZCL_AB_BOLT_Q_SYSINFO`, manifest,
    mock) — and `docs/02_operator_guide.md`. Sections are split at `<!-- section:<id>|<title> -->`.

## Commit trailer

```
Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
```
