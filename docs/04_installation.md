# Installation — step by step (version 2)

Three people, in this order. Each part ends with a check; don't start the next part until the check
passes. Send any error **exactly as SAP shows it** (screenshot or copied text) to Vernasoft — every
fix goes back to this repository, so SAP, Fiori and GitHub stay in sync.

| Part | Who | Result |
|---|---|---|
| A | SAP backend (ABAP / Basis) | The ABAP objects active, the OData service published, jobs scheduled |
| B | Network / Basis | The system can reach `api.github.com` (and the AI provider) over HTTPS |
| C | Fiori consultant | The app deployed and on the launchpad |
| D | Bolt administrator | The app configured — LIVE |
| E | Everybody | One form end to end |

**Two repositories — don't mix them up**

| Repository | What it holds | Who uses it |
|---|---|---|
| `VernasoftTechie/Bolt_with_Fiori` | The **app itself** (ABAP objects in `src/`, the Fiori app in `app/bolt-fiori`) | abapGit pulls it in part A; the Fiori consultant builds from it in part C |
| The client's **migration repository** (for Dangote: the repository in Vernasoft's client registry) | One branch per migrated form, the status files the engineer works from | Set on the Configuration tab in part D. Use the client's existing migration repository, so the engineer's queue tool keeps seeing every migration. |

**Names used below** (agreed 2026-11-19)

| | Value |
|---|---|
| ABAP package | `ZSFTAD_BOLT` |
| BSP application (Fiori) | `ZSFTAD_BOLT` |
| OData V4 service binding | `ZAB_UI_BOLT_O4` (service definition `ZAB_UI_BOLT`) |
| Service URL | `/sap/opu/odata4/sap/zab_ui_bolt_o4/srvd/sap/zab_ui_bolt/0001/` |
| Launchpad intent | `BoltMigration-manage` |

---

## Part A — SAP backend (ABAP)

The objects come in **four increments**, DDIC first. Each increment is a branch of
`Bolt_with_Fiori`; each branch contains everything of the increments before it. You switch the
abapGit repository from one branch to the next and pull again — abapGit then only creates the new
objects.

| Branch | Adds | Objects |
|---|---|---|
| `install/1-ddic` | Domains, data elements, tables | 51 DOMA, 51 DTEL, 7 TABL |
| `install/2-logic` | Exception class, service classes, driver-index and self-test reports | 10 CLAS, 2 PROG |
| `install/3-rap` | CDS views, behaviour definitions and pools, query classes, sync report | 23 DDLS, 6 BDEF, 6 CLAS, 1 PROG |
| `install/4-service` | Service definition, binding, Gateway registration | SRVD, SRVB, G4BA |

`main` = `install/4-service`. After installation, keep the abapGit repository on **`main`** for
every later update.

### A0. Before you start

1. abapGit is installed (the standalone report `ZABAPGIT_STANDALONE` is enough).
2. The system can reach `github.com` for abapGit itself (same network rule as part B, but for
   `github.com`). If it cannot, use abapGit **offline**: download the branch as ZIP from GitHub
   (Code → Download ZIP) and import it with *New Offline Repo*. Everything below works the same.
3. `Bolt_with_Fiori` is a **private** repository: abapGit asks for a GitHub user and a token with
   *Contents: Read* on it when pulling.
4. A transportable workbench request for the package.

### A1. Package

SE21 (or SE80) → create package **`ZSFTAD_BOLT`**, transportable, software component `HOME`,
with your transport request. (The object names inside follow the DIL policy, `ZAB*` — the package
name is independent of them.)

### A2. Increment 1 — DDIC

1. abapGit → **New Online** → URL `https://github.com/VernasoftTechie/Bolt_with_Fiori.git`,
   package `ZSFTAD_BOLT`, **branch `install/1-ddic`** → Create Online Repo.
2. **Pull**. Confirm the transport request. abapGit creates and activates 109 objects.
3. **Check:**
   - SE11: the seven tables `ZABT_BOLT_SETUP`, `ZABT_BOLT_MIG`, `ZABT_BOLT_HIST`, `ZABT_BOLT_FILE`,
     `ZABT_BOLT_LIB`, `ZABT_BOLT_SECRT`, `ZABT_BOLT_DRVIX` exist and are **active**.
   - They are **cross-client** (no MANDT field) — on purpose: Smart Forms are cross-client, so the
     migration list is the same in every client.
   - abapGit shows no object in red/yellow.

### A3. Increment 2 — logic

1. abapGit → repository settings (or the branch switch button) → branch **`install/2-logic`** → **Pull**.
2. **Check 1 — unit tests:** SE24 / ADT → class `ZCL_AB_BOLT_STATUS_FILE` → *Unit Test*
   (Ctrl+Shift+F10). All tests green. (They prove the status-file format is identical to the one
   the engineers' tools read.)
3. **Check 2 — the automatic export (the heart of the app):** SE38 → `ZABR_BOLT_SELFTEST`
   - *Smart Form*: a real custom form, e.g. one already migrated by hand
   - tick *Download the files to the PC*, folder e.g. `C:\temp\bolt_selftest` (create it first)
   - Execute. The list shows each file (SNAPSHOT = legacy grab, XML, STYLE, DRIVER) with its size
     and no red warnings.
   - Compare the downloaded `<form>.xml` with SMARTFORMS → the same form → Utilities → Download
     Form. They must be the same form (a text compare may only differ in the first line).
4. **Check 3 — driver index:** SE38 → `ZABR_BOLT_DRIVER_INDEX` → Execute (first with *Test run*,
   then without). It reads all custom programs once; this can take several minutes.

### A4. Increment 3 — RAP

1. Branch **`install/3-rap`** → **Pull**.
2. abapGit activates the CDS views first, then the behaviour definitions and classes. If anything
   stays inactive, open the activation log, copy it, and send it to Vernasoft — this is the
   increment most likely to need a correction on the first system (see `docs/05_build_notes.md`,
   "Not verified yet").
3. **Check:** in ADT (or SE80 → Core Data Services) the behaviour definitions
   `ZAB_CDS_I_BOLT_MIG`, `ZAB_CDS_I_BOLT_SETUP`, `ZAB_CDS_I_BOLT_LIB` are active, and their
   behaviour pools `ZBP_AB_BOLT_MIG`, `ZBP_AB_BOLT_SETUP`, `ZBP_AB_BOLT_LIB` are active.

### A5. Increment 4 — the OData service

1. Branch **`install/4-service`** → **Pull**. Then switch the repository to **`main`** (nothing to
   pull — it is the same content) and keep it there.
2. **Publish the service** — one of:
   - ADT → service binding `ZAB_UI_BOLT_O4` → **Publish**, or
   - transaction **`/IWFND/V4_ADMIN`** → *Publish Service Groups* → system alias `LOCAL` → service
     group `ZAB_UI_BOLT_O4` → Publish (choose a customizing request).
3. **Check:** open in a browser (logged on to SAP):
   `https://<host>:<port>/sap/opu/odata4/sap/zab_ui_bolt_o4/srvd/sap/zab_ui_bolt/0001/$metadata?sap-client=<client>`
   — an XML document with the entity sets *Migration, History, MigrationFile, Setup, Library,
   SmartForm, StatusFile, Timeline, SystemInfo* appears.
4. **Check:** `.../0001/SmartForm?$top=5` returns five of this system's custom Smart Forms.

### A6. Authorizations (PFCG)

| Role | For | Contents |
|---|---|---|
| `Z_BOLT_USER` (name per your convention) | everybody who uses the app | Launchpad catalog/space with the Bolt tile (part C); **S_SERVICE** for the OData V4 service group `ZAB_UI_BOLT_O4` (add it on the role's *Menu* tab: *Authorization Default* → *TADIR Service* → `IWSG`/`G4BA`, or with the Fiori launchpad's role wizard) |
| Bolt administrator | 1–2 people | the same role; their SAP user IDs are entered in the app under *Configuration → Administrators* (this replaces the web app's admin password) |
| Basis only | — | **S_TABU_NAM** for table `ZABT_BOLT_SECRT` (stored GitHub token / AI key) — give it to nobody else |

### A7. Background jobs (SM36)

| Job name (DIL) | Program | Variant | Frequency |
|---|---|---|---|
| `Z_AB_HR_BOLT_SYNC` | `ZABR_BOLT_SYNC` | both boxes ticked, *Maximum send attempts* 5 | every **15 minutes** |
| `Z_AB_DA_BOLT_DRIVER_INDEX` | `ZABR_BOLT_DRIVER_INDEX` | *Test run* not ticked | **daily**, at night |

The sync job retries any form whose transfer to GitHub failed, and reads the status of every open
migration from GitHub, so the Migration tab and the history table are current even when nobody has
the app open. Run it under a user with the app's role.

---

## Part B — Network and certificates (Basis / network)

Full detail for the client's teams: `docs/03_client_connectivity.md`. In short:

1. Outbound **HTTPS (443)** from every application server to **`api.github.com`** (and, if an AI
   provider is used, to `api.openai.com` / `api.anthropic.com` / the company gateway).
2. **STRUST** → PSE **SSL client Anonymous** (`ANONYM`) → import the root + intermediate
   certificates of `api.github.com` (export them from a browser) → add to the certificate list →
   save → SMICM → Administration → ICM → Exit Soft.
3. If the system goes out through a proxy: **SICF** → *Client* → *Proxy Settings* (or, alternatively,
   an SM59 type G destination with the proxy, entered later on the Configuration tab under
   *Advanced*).
4. **Check:** after part D step 2 (token connected), run `ZABR_BOLT_SELFTEST` with *Check the
   GitHub connection* ticked → "GitHub: connected as …" and "Repository …: private, default branch
   main, push access".

---

## Part C — Fiori (the Fiori consultant)

Source: folder `app/bolt-fiori` of `Bolt_with_Fiori` (branch `main`). Freestyle SAPUI5, minimum
UI5 1.120, libraries `sap.m`, `sap.ui.core`, `sap.ui.unified`, `sap.ui.export`. The OData model
points to the service of part A5 — nothing else to configure in the app.

### C1. Build and preview

```bash
cd app/bolt-fiori
npm install
```

In `ui5.yaml` set `backend.url` and `client` to the S/4 system; `npm start` previews the app
against the real service (fiori-tools proxy).

### C2a. Deploy to the on-premise Fiori launchpad (S/4 front-end)

1. `ui5-deploy.yaml`: set `target.url`, `client` and `transport` (BSP **`ZSFTAD_BOLT`**, package
   **`ZSFTAD_BOLT`** are already set). Credentials come from the environment variables
   `ABAP_USER` / `ABAP_PASSWORD` — never commit them.
2. `npm run deploy` → BSP application `ZSFTAD_BOLT` is created and the app index is updated
   (if not: SE38 `/UI5/APP_INDEX_CALCULATE` for `ZSFTAD_BOLT`).
3. Launchpad (`/UI2/FLPD_CUST` or the Launchpad app manager):
   - **Target mapping**: semantic object `BoltMigration`, action `manage`, application type
     *SAPUI5 Fiori App*, URL `/sap/bc/ui5_ui5/sap/zsftad_bolt`, ID `vernasoft.boltfiori`.
   - **Tile**: title *Bolt Console*, subtitle *Smart Form to Adobe Form migration*, icon
     `sap-icon://journey-change`, same intent.
   - Put both in a catalog + group/space, and that catalog into the role of A6.
4. **Check:** open the tile — the header shows the system ID and client, the Smart Forms tab lists
   the system's custom Smart Forms.

### C2b. Deploy to SAP BTP Work Zone (only if the client runs Fiori on BTP)

1. Cloud Connector: expose the S/4 system (virtual host, e.g. `s4-bolt:443`) with path
   `/sap/opu/odata4/` and principal propagation.
2. Subaccount destination **`BOLT_S4`**: HTTP, OnPremise, URL = the virtual host, Authentication
   *PrincipalPropagation*, additional properties `sap-client`, `HTML5.DynamicDestination=true`,
   `WebIDEEnabled=true`, `WebIDEUsage=odata_gen`. (The name is used in `webapp/xs-app.json`.)
3. `npm run deploy:cf` (Cloud Foundry CLI with the MultiApps plugin, logged on to the space) —
   builds `mta.yaml` and deploys the app to the HTML5 application repository.
4. Work Zone → Channel Manager → refresh the HTML5 content provider → add the app to a
   role/space/page.
5. **Check:** as in C2a. Every user works in S/4 as themselves (principal propagation), so the
   authorizations of A6 apply unchanged.

---

## Part D — Configure the app (Bolt administrator, once)

Open the app → **Configuration**. Everything client-specific is set here — nothing is hard-coded,
so the same app serves any client.

1. **Client name** (saved when you leave the field) and **Administrators** — enter your own SAP
   user ID first (the app refuses a list without you).
2. **1. Connections → GitHub**: paste the personal access token (*How do I create a token?* shows
   the steps; fine-grained, *Contents: Read and write* on the migration repository) → **Connect**.
   It shows *Connected as …*. The token is stored in SAP and never shown again.
3. **1. Connections → AI provider**: *Built-in (offline)* needs nothing; for OpenAI/Anthropic paste
   the key, **Test connection**, **Save**.
4. **2. Repository**: the client's migration repository (`owner/name` or URL) → **Check access**
   (✓ … push access) → branch prefix (default `vernasofttechie` — keep it, the engineers' branches
   follow it) → **Save repository settings**.
5. Optional: **Global reference library** — upload logos, Smart Styles, naming standards, policies.
6. *Advanced* only if part B needed it (SM59 destinations, another SSL client) — leave the status
   folder at `docs/legacy_grab`.
7. **Check:** the header shows **GitHub ✓ · AI ✓ · LIVE**.

---

## Part E — First form end to end (everybody)

1. **Smart Forms** tab → tick one form → **Next** → **Commit**. The dialog shows the serial number,
   then "*n files on branch vernasofttechie-<form>*".
2. On GitHub, the migration repository has the new branch with `<FORM>.md`, `<form>.xml`,
   `style_*.xml`, `driver_*.txt` and `docs/legacy_grab/<form>_status.md` (STATUS: queued).
3. The engineer's queue (`node tools/queue.mjs list <repo>`) lists the branch as ready — the
   engineer window claims it exactly as before.
4. **Migration** tab → open the form → the timeline shows *Queued*. When the engineer writes to the
   status file, **Refresh** (or the 15-minute job) shows it; *Waiting on: client* brings up
   **I've done this — confirm** and the other buttons, exactly like the web app.
5. Try **Stop this migration** (with a reason) and **Resume migration** once.

If all five steps work, the installation is complete. Log anything unexpected in
`docs/BUILD_ISSUES_LOG.md` (or send it to Vernasoft).

---

## Updating later

- ABAP: abapGit → repository on `main` → **Pull**.
- Fiori: pull `main`, `npm run deploy` (or `npm run deploy:cf`).
- Both come from the same commit of `Bolt_with_Fiori`, so SAP and Fiori stay at the same version.
