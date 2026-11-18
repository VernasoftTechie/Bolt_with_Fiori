# Installation guide — for the Fiori / ABAP consultant and Basis

Target: **SAP S/4HANA 2023 on-premise** (SAP_BASIS 7.58), standard ABAP, RAP OData V4, freestyle
SAPUI5 1.120. Package **`ZBOLT_FIORI`**, object names `Z*BOLT*`.

The order matters. Each step lists how to check it before you move on.

## 0. Prerequisites

- abapGit (standalone report or the developer version) in the target system, and ADT (Eclipse).
- Node.js 18+ on the PC that deploys the UI (for `fiori deploy`).
- The client has done its part of `docs/03_client_connectivity.md` (network, STRUST, SM59), or is
  doing it in parallel. You need it from step 6.

## 1. Package and pull

1. SE80 / ADT: create package **`ZBOLT_FIORI`** (transportable, software component of your Z
   development). Description: *Bolt with Fiori - Smart Form migration console*.
2. abapGit → *New Online* → `https://github.com/VernasoftTechie/Bolt_with_Fiori`, package
   `ZBOLT_FIORI`, branch `main` → **Pull**. `src/` holds every ABAP object; `app/`, `docs/` and
   `tools/` are ignored by abapGit.
3. **Activate All Inactive** on the package, **twice**. The second pass resolves the normal
   root ↔ child and class ↔ CDS circularity.

Check: no inactive objects are left in the package. If an error remains, fix the **first** real
error and activate again — later "does not exist" lines are usually only a cascade. Record each
error with its fix in `docs/BUILD_ISSUES_LOG.md`.

After the first clean activation, do abapGit **Stage → Commit** from the SAP system once. The repo
then mirrors SAP's exact serialization, and later pulls stay clean.

## 2. Publish the service

ADT → service binding **`ZBOLT_UI_O4`** → **Publish** (or `/IWFND/V4_ADMIN` → *Publish Service
Groups* → `ZBOLT_UI_O4`).

Check: in the binding, *Preview* entity `SmartForm` lists your custom Smart Forms. Service URL:
`/sap/opu/odata4/sap/zbolt_ui_o4/srvd/sap/zbolt_ui/0001/`

## 3. Unit tests

ADT → `ZCL_BOLT_STATUS_FILE` → *Run As → ABAP Unit Test*.

Check: all 6 green. These prove the status file is read and written in the exact format the
engineer windows use. Do not go live with a red one.

## 4. Driver index (every source system)

Run report **`ZBOLT_R_DRIVER_INDEX`** once in background (SE38 → F9). Run it in DEV now, and in
QA/PRD after transport.

It reads every custom program once and notes which Smart Forms each one calls. That is the slow
step of the old legacy grab, kept out of the button click.

Check: the spool lists "form <- program" pairs. Schedule it **weekly** (SM36) so new driver
programs are picked up.

## 5. Background sync

Schedule report **`ZBOLT_R_SYNC`** every **10 minutes** (SM36, a variant with both checkboxes on,
max attempts 10). It:

- re-sends any migration still *pending* or *failed* — a browser closed mid-send, a GitHub outage;
- reads every active migration's status from GitHub, so the Migration tab is current before anyone
  presses Refresh.

## 6. Destinations

Per `docs/03_client_connectivity.md`:

- `ZBOLT_GITHUB` (required)
- `ZBOLT_QA`, `ZBOLT_PRD` (only to read Smart Forms from those systems)
- `ZBOLT_AI` (optional)

Check: SM59 → *Connection Test* returns HTTP 200 or 401 (401 still means network and SSL are fine).

## 7. Deploy the UI

```bash
cd app/bolt-fiori
cp .env.example .env
npm install
npm run deploy
```

Before `npm run deploy`, set your SAP logon in `.env` and fill the three placeholders in
`ui5-deploy.yaml`: host:port, client, transport. The deploy creates BSP application
**`ZBOLT_FIORI`** in package `ZBOLT_FIORI`.

Check: `https://<host>:<port>/sap/bc/ui5_ui5/sap/zbolt_fiori/index.html?sap-client=<client>` opens
the dashboard.

## 8. Launchpad

- Target mapping: semantic object **`BoltMigration`**, action **`manage`**, SAPUI5 component
  `vernasoft.boltfiori`, URL `/sap/bc/ui5_ui5/sap/zbolt_fiori`.
- Tile: *Bolt Console — Smart Form to Adobe Form migration*, icon `sap-icon://journey-change`.
- Put it in a catalog and space/page, and in the operator and administrator PFCG roles, together
  with S_SERVICE for `ZBOLT_UI_O4`.

## 9. First start

1. Open the app. The first start creates the setup row and a source system **DEV** = "this
   system".
2. **Configuration** tab:
   - client name
   - administrators
   - GitHub: destination `ZBOLT_GITHUB`, owner `VernasoftTechie`, repository (the client's
     migration repo), base branch `main`, prefix `vernasofttechie`
   - AI provider (or *Built-in*)
3. **Save**, then **Check access** (GitHub) and **Test connection** (AI). Under *SAP systems*, add
   QA/PRD if needed and press **Test** on each.

To pre-fill all of this, run report **`ZBOLT_R_SETUP`** with the values Vernasoft gives you. It
writes only the fields you fill.

Check: the header shows **SAP ✓ GitHub ✓ AI ✓** and a green **LIVE**.

## 10. Smoke test (do this before the first real form)

1. **Smart Forms Overview**: the system's custom forms are listed, and NACE driver/output types are
   filled where configured.
2. Select **one test form** → **Next** → **Commit selection**. The dialog must end with *Sent — n
   file(s) on the new branch*.
3. On GitHub, branch `vernasofttechie-<form>` must contain:
   - `<FORM>.md`
   - `<form>.xml`
   - `driver_<PROGRAM>.txt`
   - `docs/legacy_grab/<form>_status.md`
4. **Compare the XML** with SMARTFORMS → Utilities → Download of the same form. The content must be
   the same. This verifies the export method (`ZCL_BOLT_FORM_EXPORT`), which was built from
   abapGit's own Smart Form serializer and is the one part that cannot be tested outside SAP.
   Report any difference to Vernasoft before going on.
5. **Migration** tab: the form shows *Queued*. Open it: the timeline shows the *Queued* entry.
6. Vernasoft confirms that the engineer tools read the branch (`queue.mjs list` shows it as READY).

## 11. Transport

Release the transport with the package and the BSP application to QA (and PRD if Smart Forms must
be read there). Publish the service binding there too (step 2) and run the driver index (step 4).
The Fiori screen is used only in DEV.

## Local UI development without SAP

```bash
node tools/mock/mock-server.mjs
```

Then open `http://localhost:8099/index.html`. This is a mock of the complete OData service with
example data — every screen and action works — for UI changes and demos.

After changing ABAP objects (new object, renamed object), regenerate their abapGit metadata:

```bash
node tools/gen_metadata.mjs
```
