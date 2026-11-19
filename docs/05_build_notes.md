# Build notes — version 2 (2026-11-19)

## Decisions

| Decision | Value | Source |
|---|---|---|
| Repository | `VernasoftTechie/Bolt_with_Fiori` (private), branch `main` + install branches | user, 2026-11-18/19 |
| ABAP package | `ZSFTAD_BOLT` | user, 2026-11-19 |
| BSP application | `ZSFTAD_BOLT` | user, 2026-11-19 |
| Object names | DIL policy, module AB (`docs/06_naming.md`) | user, 2026-11-18 |
| Source system | the system the app runs in — no system selection (v1's DEV/QA/PRD selection removed) | user, 2026-11-18 |
| Tables | cross-client (Smart Forms are cross-client) | design |
| Stored | basic status + history rows; no message texts (they stay in the branch status file) | user, 2026-11-18 |
| Re-process | stopped form → new migration, new serial, run n+1, branch `<prefix>-<form>-r<n>`; the stopped run is closed | user request, design |
| GitHub access | token pasted on the Configuration tab (as in the web app), URL + STRUST by default, SM59 optional | design (parity with the web app, fewer Basis steps) |
| Admin protection | Administrators list + RAP global authorization (replaces the web app's admin password) | design |
| Rulebook upload of the web app | dropped — it only fed the retired AI planner | design |
| Delete migration (web app) | replaced by Stop + re-process: a migration record is never deleted, so progress can always be analysed | design |
| ABAP standards | DIL program-element naming, no INTO CORRESPONDING, no INSERT, sorted tables / explicit SORT, 7.4+ | Vernasoft standard |

## Formats copied from objects confirmed on real systems

| Object type | Template | Where confirmed |
|---|---|---|
| DOMA (with fixed values), DTEL (domain-based) | `zrap_mt_scanstat.doma.xml`, `zcust_bp_flag.dtel.xml` | ZRAP_MT, Dangote_Requirements activated |
| TABL (data-element fields) | ZRAP_MT tables | ZRAP_MT activated |
| DDLS + `.baseinfo`, BDEF, behaviour pool | ZRAP_MT, ZHR_ESS_V1, VS-Tower | activated |
| SRVD / SRVB / G4BA | VS-Tower `ztwr_ui_srvb_o4` | VS-Tower live |
| CLAS / PROG | VS-Tower, Utility-Class-and-Method | live |
| Smart Form XML export | abapGit SSFO serializer (`CL_SSF_FB_SMART_FORM->load / xml_download`) | abapGit source |
| Smart Style export | abapGit SSST serializer (`SSF_READ_STYLE`) | abapGit source |
| Smart Style names in the form XML | `STDSTYLE` / `STYLE_NAME` elements | real export `ymmgrnnote.xml` |

## Verified

- Generators: `node tools/gen_ddic.mjs` → "51 domains, 51 data elements, 7 tables … DDIC OK";
  `node tools/gen_metadata.mjs` → "metadata OK" (BOM rules, baseinfo, DIL names and lengths).
- Every JavaScript file passes `node --check`; every view/fragment is well-formed XML.
- The UI end to end against the mock service (1440×900) — see `07_recheck_matrix.md`.
  Bugs found and fixed in that run: B3–B5 in `BUILD_ISSUES_LOG.md`.

## Not verified yet — needs the first activation in SAP

No SAP system is reachable from where this was built, and the offline ABAP checker could not be
installed, so the ABAP was reviewed by hand. Most likely to need a fix, highest risk first:

1. **`ZCL_AB_BOLT_FORM_EXPORT=>export_xml` / `export_style`** — signatures follow abapGit; check with
   `ZABR_BOLT_SELFTEST` (A3 check 2) and compare with SMARTFORMS → Download.
2. **RAP EML in `ZBP_AB_BOLT_MIG`** — `CREATE` + `CREATE BY \_History` with `%cid_ref` in one
   statement, static action results, `READ … BY \_File`, `UPDATE` of the child entity File.
3. **Cross-client tables under a managed BO** — supported, but a first for us.
4. **ETag + actions from the UI** — the UI binds each instance action to the freshly read row and
   sends `If-Match: *` (`execute(…, bIgnoreETag)`).
5. **`ZBP_AB_BOLT_SETUP` saver** (`save_modified`, `cleanup_finalize`) and the validation.
6. **`CL_HTTP_CLIENT=>CREATE_BY_URL` with `ssl_id`** — needs the STRUST import of part B.
7. **`ENQUEUE_E_TABLE`** inside the `commitSelection` action (serial-number lock).
8. **Filters on Edm.Guid in the custom entities** (`StatusFile`, `Timeline`) — the query class
   accepts the value with or without dashes.
9. **`STXFADM` / `STXFADMT` / `TNAPR` columns** — read guarded; worst case blank columns.

Log every activation error and its fix in `docs/BUILD_ISSUES_LOG.md`.

## Parity with the Bolt Console web app

| Web app | Here |
|---|---|
| Configure: client name (blur), admin password, GitHub connection (token, scopes, help), AI settings (+Test, shared Save), 2. Repository gated (check / create / save), global library, rulebook | Same, admin password → Administrators list; rulebook dropped |
| New migration: name + upload the legacy grab by hand | Smart Forms tab: select → Next → Commit; files produced and sent automatically |
| Migration list: status, complexity, age, updated, delete | Same + serial, run, picked up by, KPIs, export; delete → Stop + re-process |
| Workspace: header, complexity, status board, legacy documents (staged add/remove) | Same + status history, files on the branch, AI summary |
| Status board: stop/resume, confirm, problem/question/change, concern, attachments, notices | Same texts and rules |
| Auto-heal of failed branch creation | Job `ZABR_BOLT_SYNC` + *Send to GitHub again* |
