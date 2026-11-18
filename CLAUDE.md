# CLAUDE.md — read this first

## Landing zone (Commit Gate — never cross without asking)

| | Value |
|---|---|
| GitHub repo | `VernasoftTechie/Bolt_with_Fiori` (private), branch `main`, direct push |
| ABAP package | `ZBOLT_FIORI` |
| Object stem | `BOLT` → `ZI_BOLT_*`, `ZC_BOLT_*`, `ZBP_I_BOLT_*`, `ZCL_BOLT_*`, `ZCE_BOLT_*`, `ZA_BOLT_*`, `ZBOLT_*` (tables, reports, service), `ZCX_BOLT` |
| UI | BSP `ZBOLT_FIORI`, UI5 namespace `vernasoft.boltfiori` |
| System | S/4HANA 2023 on-prem, SAP_BASIS 7.58, standard ABAP |

## Before changing anything

1. `docs/01_architecture.md` — how it works; `docs/05_build_notes.md` — what is verified and what is
   not yet.
2. The status-file format is a **contract with the engineer windows and tools/queue.mjs**.
   `ZCL_BOLT_STATUS_FILE` must stay identical to Bolt Console's `statusParse.js`. Change both or
   neither, and keep its unit tests green.
3. ABAP standards: DIL naming (`gv_/gt_/gs_/gc_`, `lv_/lt_/ls_`, `<lfs_>/<lfv_>/<lft_>`,
   `iv_/is_/it_/ev_/rv_/rs_/rt_`), no `INTO CORRESPONDING`, MODIFY instead of INSERT for DB
   writes, sorted tables or explicit SORT, 7.4+ syntax. A method with RETURNING has no
   EXPORTING/CHANGING.
4. RAP: no DB writes in the interaction phase (use EML in local mode, or the saver of a
   `with additional save` BO). GitHub/HTTP calls are fine in action handlers.
5. After adding or renaming an ABAP object, run `node tools/gen_metadata.mjs`. It writes the abapGit
   metadata in the shapes proven on real systems and fails on name-length or BOM problems.
6. UI changes: test against `node tools/mock/mock-server.mjs` (add new actions or fields to the mock
   as well).
7. Log every activation/runtime error and its fix in `docs/BUILD_ISSUES_LOG.md`.

## Commit trailer

```
Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
```
