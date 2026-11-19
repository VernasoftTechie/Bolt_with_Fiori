# Object naming — DIL policy

All ABAP object names follow **"Policy for ABAP Naming Standards - DIL" (Ver 1.0)**, module ID
**AB** (ABAP / non-functional). `tools/gen_ddic.mjs` and `tools/gen_metadata.mjs` refuse any name
that breaks these patterns or lengths. The package is the client's choice (`ZSFTAD_BOLT`) and is set
when the repository is linked in abapGit.

| Object | DIL pattern | Max | Used here |
|---|---|---|---|
| Domain | `ZAA_B_` (B = DM) | 30 | `ZAB_DM_BOLT_<name>` — 51 |
| Data element | `ZAA_B_` (B = DE) | 30 | `ZAB_DE_BOLT_<name>` — 51 |
| Table | `ZAAB_` (B = T) | 16 | `ZABT_BOLT_SETUP`, `_MIG`, `_HIST`, `_FILE`, `_LIB`, `_SECRT`, `_DRVIX` |
| Table field | — | 16 | e.g. `LOCAL_CHANGED`, `COMPLEXITY_INFO` |
| CDS view | `ZAA_B_` (B = CDS) | 30 (DDL) | `ZAB_CDS_I_BOLT_*` (interface), `ZAB_CDS_C_BOLT_*` (projection), `ZAB_CDS_CE_BOLT_*` (custom), `ZAB_CDS_A_BOLT_*` (action parameters) |
| Report | `ZAAD_` (D = R) | 40 | `ZABR_BOLT_SYNC`, `ZABR_BOLT_DRIVER_INDEX`, `ZABR_BOLT_SELFTEST` |
| Background job | `Z_AA_BB_xxx` | — | `Z_AB_HR_BOLT_SYNC` (hourly class, runs every 15 min), `Z_AB_DA_BOLT_DRIVER_INDEX` (daily) |
| Classes | not covered by DIL | 30 | `ZCL_AB_BOLT_*`, exception `ZCX_AB_BOLT`, behaviour pools `ZBP_AB_BOLT_MIG/_SETUP/_LIB` |
| Service definition / binding | not covered | 30 | `ZAB_UI_BOLT` / `ZAB_UI_BOLT_O4` |
| BSP application | not covered | 15 | `ZSFTAD_BOLT` (client's choice) |

**Domain, data element and field carry the same descriptive name** — one domain per data element
(e.g. field `MIG_STATUS` → `ZAB_DE_BOLT_MIG_STATUS` → `ZAB_DM_BOLT_MIG_STATUS`). Generic technical
fields use standard SAP data elements: `SYSUUID_X16`, `TIMESTAMPL`, `SYUNAME`, `ABAP_BOOLEAN`,
`TDSFNAME`, `DEVCLASS`, `PROGNAME`, `SYSYSID`, `SYMANDT`, `RFCDEST`.

**Program elements** (all classes and reports): `gv_/gt_/gs_/gc_/go_/gr_`, `lv_/lt_/ls_/lc_/lo_/lr_`,
`<lfs_>/<lfv_>/<lft_>`, method parameters `iv_/is_/it_/ev_/es_/et_/cv_/rv_/rs_/rt_`, selection
screen `p_/cb_`, types `ty_`. No `INTO CORRESPONDING`, no `INSERT` (MODIFY for database writes,
APPEND + SORT for internal tables), sorted tables or explicit SORT, 7.4+ syntax.

The full field list: `docs/generated_field_catalog.md` (generated).
