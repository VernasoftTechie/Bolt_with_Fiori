# Bolt with Fiori

**Smart Form → Adobe Form migration console on SAP Fiori + RAP.** This replaces the Bolt Console web
application. It uses the same process and the same GitHub branches and status files, but there are
no legacy files to download or upload and no server to host.

The client picks Smart Forms from their own system (DEV, QA or PRD) on one screen and commits the
selection. For each form, the app runs the legacy grab and the Smart Form XML export on the source
system and pushes them, with the driver program sources and a status file, to a new branch in the
client's migration repository on GitHub. The Vernasoft engineer works the branch exactly as
before. The client follows every migration live in the Migration tab and answers there: confirm,
report a problem, ask, request a change, stop, resume.

| | |
|---|---|
| Platform | SAP S/4HANA 2023 on-premise (SAP_BASIS 7.58), standard ABAP, RAP OData V4 |
| UI | Freestyle SAPUI5 1.120, one dashboard with tabs + migration detail, BSP `ZBOLT_FIORI` |
| ABAP package | `ZBOLT_FIORI` — objects `Z*BOLT*` |
| Service | `ZBOLT_UI` / binding `ZBOLT_UI_O4` |
| Status | **Version 1 — built, UI verified against the mock; first SAP activation pending** (see `docs/05_build_notes.md`) |

## Start here

| You are | Read |
|---|---|
| The client's Basis / network / security team | [`docs/03_client_connectivity.md`](docs/03_client_connectivity.md) — what we need from you to connect SAP to GitHub |
| The Fiori / ABAP consultant installing it | [`docs/04_installation.md`](docs/04_installation.md) |
| The client's operator | [`docs/02_operator_guide.md`](docs/02_operator_guide.md) |
| A developer changing it | [`docs/01_architecture.md`](docs/01_architecture.md), [`docs/05_build_notes.md`](docs/05_build_notes.md), [`CLAUDE.md`](CLAUDE.md) |

## Repository layout

```
src/                 ABAP objects (abapGit, STARTING_FOLDER /src/)
  zbolt_*.tabl.xml     tables: setup, systems, migrations, log, files, secret, driver index
  zi_/zc_bolt_*        CDS + behaviour: Migration (+log, +files), Setup, SourceSystem
  zce_bolt_*           custom entities: SmartForm (UI list), SourceForm / SourceFile (source API)
  za_bolt_*            action parameters
  zcl_bolt_*           GitHub client, status file, legacy grab (port), XML export, source reader,
                       AI client, migration service, query providers, config, HTTP
  zbolt_r_*            reports: background sync, driver index, setup defaults
  zbolt_ui*            service definition + binding
app/bolt-fiori/      SAPUI5 app (ui5.yaml, ui5-deploy.yaml, webapp/)
tools/
  gen_metadata.mjs     writes the abapGit .xml/.baseinfo for every source in src/
  mock/mock-server.mjs local mock of the whole OData service (example data) for UI work and demos
docs/                architecture, operator guide, client connectivity, installation, build notes
```

## Try the UI without SAP

```bash
node tools/mock/mock-server.mjs
```

Then open `http://localhost:8099/index.html`. Everything works against example data: selecting forms,
commit and send, the migration list, confirm and concerns, and the configuration screens.
