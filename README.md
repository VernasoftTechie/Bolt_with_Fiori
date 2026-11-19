# Bolt — Smart Form to Adobe Form migration console (RAP + Fiori)

Replaces the Bolt Console web app with an app that runs **inside the client's SAP system**:

- **Smart Forms** — every custom Smart Form of the system the app is launched in. Select, Next,
  Commit: each form gets a serial number and a GitHub branch, and its legacy files (legacy grab,
  driver sources, Smart Form XML, Smart Styles) are produced in SAP and sent automatically.
- **Drafts** — committed forms whose initial load is not on GitHub yet (GitHub not set up, or the
  send failed). Send them again as often as needed, or discard one to free the form.
- **Migrations** — live status of every migration from its branch status file; the communication
  panel to answer the migration engineer (confirm, problem, question, change, concern, files),
  stop / resume, legacy documents, status history.
- **Setup** (right side, own page) — GitHub, AI provider, target repository, global reference
  library; administrators only. Everything client-specific lives here.
- **Help** (right side, own page) — searchable in-app help, `app/bolt-fiori/webapp/help/help.html`,
  updated with every change (see *What's new*).

The engineer side is unchanged: engineer windows work from the branches and status files exactly as
with the web app.

| | |
|---|---|
| ABAP | package `ZSFTAD_BOLT`, objects `ZAB*` (DIL naming), S/4HANA 2023, RAP managed BOs, OData V4 |
| Service | `ZAB_UI_BOLT` / binding `ZAB_UI_BOLT_O4` |
| Fiori | freestyle SAPUI5 ≥ 1.120, `app/bolt-fiori`, BSP `ZSFTAD_BOLT` or BTP HTML5 repository |

## Start here

| You are | Read |
|---|---|
| installing it (ABAP, Basis, Fiori) | [docs/04_installation.md](docs/04_installation.md) |
| the client's network / Basis / security team | [docs/03_client_connectivity.md](docs/03_client_connectivity.md) |
| a user of the app | [docs/02_operator_guide.md](docs/02_operator_guide.md) |
| developing it | [CLAUDE.md](CLAUDE.md), [docs/01_architecture.md](docs/01_architecture.md), [docs/05_build_notes.md](docs/05_build_notes.md), [docs/06_naming.md](docs/06_naming.md), [docs/07_recheck_matrix.md](docs/07_recheck_matrix.md) |

Discussion notes and earlier documents: [docs/discussion/](docs/discussion/).

## Repository layout

| Path | Content |
|---|---|
| `src/` | all ABAP objects (abapGit, `.abapgit.xml`) |
| `app/bolt-fiori/` | the Fiori app (`ui5-deploy.yaml` on-premise, `mta.yaml` BTP) |
| `tools/gen_ddic.mjs` | generates every domain, data element and table (single source of the DDIC) |
| `tools/gen_metadata.mjs` | generates the abapGit metadata of the other objects, checks DIL names |
| `tools/make_install_branches.mjs` | builds `install/1-ddic` … `install/4-service` from `main` |
| `tools/mock/mock-server.mjs` | local mock of the OData service for UI work: `node tools/mock/mock-server.mjs` → http://localhost:8099 |
| `docs/` | guides, decisions, issue log |

## Branches

`main` is the complete app. `install/1-ddic`, `install/2-logic`, `install/3-rap`,
`install/4-service` are cumulative subsets of `main` for the first installation, increment by
increment (DDIC first). They are rebuilt from `main` by `tools/make_install_branches.mjs` — never
commit to them directly.
