# Build issues log

Every activation, runtime or deployment error hit on this repository, with its root cause and the
fix. Add an entry the moment a new one is hit. Use the same format as the other Vernasoft repos:
the situation, then the resolution.

| # | Date | Object | Symptom (exact message) | Root cause | Fix | Commit |
|---|---|---|---|---|---|---|
| B1 | 2026-11-18 | Dashboard.view.xml | Form selection lost when the commit dialog opened | `sap.m.Table` `rememberSelections` (default on) re-applied its own selection over the bound `selected` property on model refresh | `rememberSelections="false"` | v1 |
| B2 | 2026-11-18 | Dashboard.view.xml | LIVE pill without colour | `class="{= ... }"` — CSS classes cannot be bound in XML views | inverted `ObjectStatus` with bound `state` | v1 |
| B3 | 2026-11-19 | Dashboard.controller.js | Typing a repository, then *Test connection* on the AI card, put the saved repository back into the field and lost the *Check access* result | `_afterSetup` refilled every card from the setup row after any action | `_afterSetup(sSaved)` keeps the other cards' typed values; only the saved card is refilled | v2 |
| B4 | 2026-11-19 | Dashboard.controller.js | After "Add your own user ID … to the administrators" the field still showed the refused value | a refused PATCH left the edit field as typed | `_patch` restores the saved values when the save is refused | v2 |
| B5 | 2026-11-19 | Dashboard.view.xml | Migration list showed "Waiting on: Engineer" for a form whose send to GitHub failed | WAITING_ON comes from the status file, which does not exist before the send | shown only for migrations on GitHub (`waitingText`) | v2 |
| B6 | 2026-11-19 | zcl_ab_bolt_form_export | (found before activation) Smart Style names not found in the form XML | guessed element names STYLE/STYLENAME | checked a real export (`ymmgrnnote.xml`): `STDSTYLE` / `STYLE_NAME` | v2 |
| B7 | 2026-11-19 | ZAB_CDS_CE_BOLT_STATUS | `FOUND is a reserved word (choose another field name)` → `DDL Source ZAB_CDS_CE_BOLT_STATUS could not be activated`, activation cancelled | element `Found` is on SAP's reserved-word list (SQL keyword) | renamed to `StatusFound` in the CDS view, query class `ZCL_AB_BOLT_Q_STATUS`, the UI (Detail) and the mock; all other element names checked against the list | v2.0.1 |
| B8 | 2026-11-19 | ZAB_CDS_C_BOLT_FILE / _HIST / _LIB | Warning `Annotation value '…(PROJECTION)' length (4x)` | `@EndUserText.label` is limited to 40 characters | labels shortened; `gen_metadata.mjs` now refuses labels over 40 | v2.0.1 |
| B9 | 2026-11-19 | ZBP_AB_BOLT_SETUP (runtime, first app start) | `RFC Error: The current program has intentionally triggered a termination with a short dump` - ST22 `RAISE_SHORTDUMP` / `CX_RAP_HANDLER_NOT_IMPLEMENTED`: *Handler not implemented; Method: GLOBAL_AUTHORIZATION, Involved Entities: ZAB_CDS_C_BOLT_SETUP* on `Setup.initialize` | the behaviour pool load in the system is an empty class shell (12 KB, generated 07:03, before the BDEFs were activated at 07:32 after fix B7) - its local implementations (handler classes) were not active | **system:** activate ZBP_AB_BOLT_SETUP / _MIG / _LIB (Local Types tab filled, Ctrl+F2, Ctrl+F3), no inactive objects left. **app:** SystemInfo and Setup now load independently - a setup error shows in a strip, the header and lists still load | v2.0.2 |
