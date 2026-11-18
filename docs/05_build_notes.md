# Build notes — version 1 (2026-11-18)

## Decisions

| Decision | Value | Source |
|---|---|---|
| Repository | `VernasoftTechie/Bolt_with_Fiori` (private) | user, 2026-11-18 |
| ABAP package | `ZBOLT_FIORI` | user, 2026-11-18 |
| Object stem | `BOLT`: `ZI_/ZC_BOLT_*`, `ZBP_I_BOLT_*`, `ZCL_BOLT_*`, `ZBOLT_*` tables/reports, `ZCX_BOLT`, `ZCE_BOLT_*` custom entities, `ZA_BOLT_*` action parameters | user, 2026-11-18 |
| Platform | S/4HANA 2023 on-premise, SAP_BASIS 7.58, standard ABAP, RAP OData V4, SAPUI5 1.120 freestyle | user, 2026-11-18 |
| UI | One dashboard (tabs Smart Forms Overview / Migration / Configuration / Help) + migration detail page | user, 2026-11-18 |
| GitHub access | Directly from the client's SAP through SM59 (Basic logon, fine-grained token) | user, 2026-11-16/18 |
| One service | `ZBOLT_UI` serves the UI and the source API (`SourceForm`/`SourceFile`) other systems call | design |
| Status-file format | Byte-for-byte the web app's (`statusParse.js` port + unit tests) | design — engineer windows must not change |
| Driver scan | Offline (`ZBOLT_R_DRIVER_INDEX` → `ZBOLT_DRVIDX`); one click reads the index + NACE | design — the full scan takes minutes |
| ABAP standards | DIL naming (`gv_/gt_/gs_/lv_/lt_/ls_`, `<lfs_>/<lfv_>/<lft_>` field symbols), no `INTO CORRESPONDING`, MODIFY not INSERT for DB writes, 7.4+ syntax | Vernasoft standard |

## Formats copied from objects confirmed on real systems

| Object type | Template | Where confirmed |
|---|---|---|
| TABL (built-in and data-element fields, STRG) | `zrap_mt_hdr.tabl.xml`, `zhr_ess_*.tabl.xml` | ZRAP_MT / ZHR_ESS_V1 activated |
| DDLS + `.baseinfo` (view entity, projection, custom, abstract) | ZRAP_MT, VS-Tower `zc_twr_shortdump` | ZRAP_MT, VS-Tower live |
| BDEF | `zi_rap_mt_hdr.bdef.xml` (incl. LINKS) | ZRAP_MT activated |
| Behaviour pool | `zbp_i_ess_req_head` (`FOR BEHAVIOR OF`, local handler) | ZHR_ESS_V1 activated |
| SRVD / SRVB / G4BA | VS-Tower `ztwr_ui_srvb_o4` | VS-Tower live |
| CLAS / PROG | VS-Tower, Utility-Class-and-Method, ZSF2AF_R_LEGACY_GRAB | live |
| Query provider | `zcl_twr_shortdump_qry` | VS-Tower live |
| UI5 project (ui5.yaml, deploy, manifest, named OData model) | VS-Tower `ui/controltower` | VS-Tower deployed |

`tools/gen_metadata.mjs` writes every `.xml`/`.baseinfo` from these shapes. It also enforces the
Playbook rules: UTF-8 BOM on `.xml` but not on sources, a `.baseinfo` for every DDLS, and name
lengths.

## Verified before the first push

- **UI end to end against the mock service** (`tools/mock/mock-server.mjs`) in a browser at
  1440×900:
  - Smart Forms list per system
  - refusing to select a form already in migration
  - Next → Commit selection → per-form send with live results, including a failed send with its
    reason
  - Migration list with KPIs and filters
  - detail page with status-file timeline (Markdown), Confirm (status and panel change, entry
    appears, message)
  - Configuration save (PATCH in `$batch`)
  - add a source system + automatic connection test
  - unreachable system (red chip, "Setup needed", reason shown, Next disabled)
- **Bugs found and fixed in that run:**
  - `sap.m.Table` *rememberSelections* fought the bound `selected` property → `rememberSelections="false"`
  - the LIVE pill's bound `class` (classes cannot be bound in XML views) → inverted ObjectStatus
  - a missing icon name
  - systems table column widths
- Every view, fragment and metadata `.xml` is well-formed; every JavaScript file passes `node --check`.

## NOT verified yet — needs the first activation in SAP

No SAP system is reachable from where this was built. The offline ABAP checker (abaplint) could not
be installed in that environment, so the ABAP has been reviewed by hand only. These are the places
most likely to need a fix at first activation, highest risk first:

1. **`ZCL_BOLT_FORM_EXPORT=>export_xml`** — `CL_SSF_FB_SMART_FORM->load( im_formname, im_language )`
   and `->xml_download( parent, document )` follow abapGit's SSFO serializer. Verify the signatures
   and compare one export with SMARTFORMS → Utilities → Download (installation step 10.4).
2. **RAP EML in `ZBP_I_BOLT_MIGRATION`:**
   - `CREATE` + `CREATE BY \_Log` with `%cid_ref` in one statement
   - static action results (`%cid` + `%param`)
   - `internal create/update/delete`
   - `READ ... BY \_Log`
3. **`ZBP_I_BOLT_SETUP`:**
   - `managed with additional save` saver (`save_modified`, `cleanup_finalize`)
   - the cross-BO `MODIFY ENTITIES OF zi_bolt_system` inside `initialize`
4. **Abstract entities** typed `abap.string( 0 )` and `abap_boolean`.
5. **`/ui2/cl_json` `pretty_mode-low_case`** deserialising the upper-case element names of
   `SourceForm`/`SourceFile` (only for QA/PRD reading). Check with one remote system.
6. **`ZCX_BOLT`:** `METHODS if_message~get_text REDEFINITION`.
7. **`STXFADM` / `STXFADMT` columns** for description and last change. Read dynamically and guarded,
   so the worst case is blank columns, not an error.
8. **Generated TABL XML** for built-in types. Same shape as ZRAP_MT, but every table is new.
9. **No ETag on the three root entities.** This is deliberate: the UI calls actions without reading
   the row first, and the background job changes rows while the screen is open. Both confirmed
   examples (ZRAP_MT, ESS) had an ETag. If `strict ( 2 )` refuses to activate without one, add
   `etag master LocalLastChanged`, and in `model/service.js` read the entity before calling an
   action so the V4 model sends `If-Match`.

Log every activation error and its fix in `docs/BUILD_ISSUES_LOG.md` (the Playbook fix-loop: first
real error → fix → activate again).

## Parity with the Bolt Console web app

| Web app | Here |
|---|---|
| Client name, AI provider (provider/key/model/base URL/max tokens + Test), GitHub connection + target repo + branch prefix + Check access, one Save | Configuration tab, same fields; GitHub token in SM59 instead of the page |
| LIVE indicator + "+ New migration" only when everything is connected | Header chips SAP/GitHub/AI + LIVE; **Next** disabled until all are connected |
| Migration list: name, form, branch, status, complexity, age, updated, delete | Same columns + serial no., system, waiting on, note; withdraw replaces delete |
| Complexity signal from the XML | Ported (`ZCL_BOLT_FORM_EXPORT=>complexity`, same thresholds) |
| Status board: stop/resume, confirm, problem, question, change, concern, attachments | Same actions, same status-file headings |
| Auto-heal of failed branch creation | `ZBOLT_R_SYNC` + *Send to GitHub again* |
| Duplicate-branch protection | A form already in migration can't be selected; an unknown existing branch is never overwritten |
| — (new) | Smart Forms Overview per source system, serial numbers, logs in SAP, files pushed list, AI summary, Import from GitHub, KPI tiles, multi-system extraction |
